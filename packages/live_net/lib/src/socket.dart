import 'dart:async';
import 'dart:io';

import 'package:live_net/src/proxy.dart';

/// State of a [LiveSocket].
enum SocketStatus {
  /// Open and receiving.
  connected,

  /// Lost; a reconnect is scheduled.
  failed,

  /// Closed by [LiveSocket.close] or after the last reconnect failed.
  closed,
}

/// One open WebSocket.
abstract interface class SocketChannel {
  /// Incoming messages: `String` for text frames, `List<int>` for binary.
  Stream<Object?> get stream;

  /// Sends a text or binary message.
  void add(Object data);

  /// Starts the closing handshake.
  Future<void> close([int? code, String? reason]);

  /// Close code from the peer, once closed.
  int? get closeCode;

  /// Close reason from the peer, once closed.
  String? get closeReason;
}

/// Opens a WebSocket to [endpoint] through [route]; completes when the
/// handshake is done.
typedef SocketConnector = Future<SocketChannel> Function(
  Uri endpoint, {
  required Map<String, String> headers,
  required Iterable<String>? protocols,
  required ProxyRoute route,
  required Duration connectTimeout,
});

/// The `HttpClient` for a WebSocket handshake through [route], or null to use
/// the default client. A custom client that only answers DIRECT is not just
/// unnecessary: on Android's `dart:io` WebSocket path it could leave the
/// upgrade pending until the connect timeout on reachable hosts (seen in
/// 3.x), so direct routes keep the default.
///
/// With [plainUserAgent] a client is always made and its own User-Agent is
/// cleared, so a caller's `user-agent` header is sent without dart:io's
/// `Dart/<version> (dart:io)` prefix (UPGRADES B-2, off by default until
/// verified on Android, where 3.x saw a custom direct client stall).
HttpClient? webSocketClientFor(ProxyRoute route, {bool plainUserAgent = false}) {
  final client = switch (route) {
    DirectRoute() => plainUserAgent ? HttpClient() : null,
    HttpProxyRoute() =>
      HttpClient()
        ..idleTimeout = const Duration(seconds: 30)
        ..findProxy = (_) => route.directive,
  };
  if (plainUserAgent) client?.userAgent = null;
  return client;
}

/// [SocketConnector] on `dart:io`. With [pingInterval] the socket sends a
/// WebSocket ping at that interval and closes itself when a pong does not
/// come back before the next one (`WebSocket.pingInterval`), for servers
/// that keep a session only while its socket is provably alive (FC2's media
/// control socket, which 3.x pinged every 15 s). [plainUserAgent]: see
/// [webSocketClientFor].
Future<SocketChannel> connectIoSocket(
  Uri endpoint, {
  required Map<String, String> headers,
  required Iterable<String>? protocols,
  required ProxyRoute route,
  required Duration connectTimeout,
  Duration? pingInterval,
  bool plainUserAgent = false,
}) async {
  final client = webSocketClientFor(route, plainUserAgent: plainUserAgent);
  try {
    final socket = await WebSocket.connect(
      endpoint.toString(),
      headers: headers,
      protocols: protocols,
      customClient: client,
    ).timeout(connectTimeout);
    if (pingInterval != null) socket.pingInterval = pingInterval;
    return _IoSocketChannel(socket);
  } finally {
    // The client is only needed for the upgrade; closing it releases idle
    // proxy connections without ending the detached WebSocket.
    client?.close();
  }
}

final class _IoSocketChannel implements SocketChannel {
  new(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get stream => _socket;

  @override
  void add(Object data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _socket.close(code, reason);

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;
}

/// A WebSocket that fails over between [endpoints] and reconnects a bounded
/// number of times (3.x's `WebScoketUtils`, used by every danmaku protocol).
///
/// - After a failure it tries the next endpoint at once and waits a little
///   longer after each full round (base delay times rounds + 1, at most 6x).
/// - Any message resets the reconnect count; after [maxReconnects] failures
///   in a row it gives up and reports [onClosed].
/// - With a [heartbeatInterval], [onHeartbeat] runs on every tick while
///   messages keep arriving; a socket silent for [inactivityTimeout] (default
///   three intervals, at least 90 seconds) is treated as half-open and
///   replaced.
/// - Each connection has a generation, so callbacks from an old socket never
///   act on a newer one; [close] aborts a pending handshake and waits at most
///   [shutdownTimeout] for the closing handshake.
final class LiveSocket {
  /// Creates the socket; [connect] opens it. [site] selects the proxy route.
  new({
    required Iterable<Uri> endpoints,
    required this.site,
    this.proxy = const FixedProxyPolicy(),
    this.headers = const {},
    this.protocols,
    this.heartbeatInterval = Duration.zero,
    this.inactivityTimeout,
    this.maxReconnects = 8,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.shutdownTimeout = const Duration(seconds: 2),
    this.connectTimeout = const Duration(seconds: 10),
    this.onMessage,
    this.onReady,
    this.onHeartbeat,
    this.onReconnecting,
    this.onFailure,
    this.onClosed,
    SocketConnector? connector,
  }) : endpoints = _unique(endpoints),
       _connector = connector ?? connectIoSocket;

  /// Endpoints in order of preference, without duplicates.
  final List<Uri> endpoints;

  /// Platform id, for [proxy].
  final String site;

  /// Proxy routes; read at every handshake, so a changed setting applies to
  /// the next connection.
  final ProxyPolicy proxy;

  /// Handshake headers.
  final Map<String, String> headers;

  /// Subprotocols offered in the handshake.
  final Iterable<String>? protocols;

  /// Heartbeat tick; zero disables [onHeartbeat] and the silence watchdog.
  final Duration heartbeatInterval;

  /// Silence after which the socket is replaced; see the class comment.
  final Duration? inactivityTimeout;

  /// Failures in a row before giving up.
  final int maxReconnects;

  /// Delay before a reconnect, multiplied by completed endpoint rounds + 1.
  final Duration reconnectBaseDelay;

  /// Longest wait for a closing handshake.
  final Duration shutdownTimeout;

  /// Longest wait for an opening handshake.
  final Duration connectTimeout;

  /// A message arrived.
  final void Function(Object? message)? onMessage;

  /// A connection is open.
  final void Function()? onReady;

  /// Heartbeat tick while connected; send the platform's heartbeat here.
  final void Function()? onHeartbeat;

  /// The first failure of a streak: a reconnect is starting.
  final void Function()? onReconnecting;

  /// A connection failed; the text describes why (close code and reason
  /// when the peer closed).
  final void Function(String reason)? onFailure;

  /// Gave up after [maxReconnects] failures; the text is the last failure.
  final void Function(String reason)? onClosed;

  final SocketConnector _connector;

  /// Current state.
  SocketStatus get status => _status;
  SocketStatus _status = SocketStatus.closed;

  SocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  int _failures = 0;
  int _endpointIndex = 0;
  int _generation = 0;
  bool _manualClose = false;
  Completer<void>? _abort;
  Completer<void>? _connecting;
  DateTime? _lastMessageAt;

  static List<Uri> _unique(Iterable<Uri> endpoints) {
    final seen = <String>{};
    return List.unmodifiable([
      for (final endpoint in endpoints)
        if (endpoint.toString().trim().isNotEmpty && seen.add(endpoint.toString())) endpoint,
    ]);
  }

  /// Opens a connection; a second call while one is being opened waits for
  /// it. [retry] moves to the next endpoint first.
  Future<void> connect({bool retry = false}) async {
    final pending = _connecting;
    if (pending != null) {
      await pending.future;
      return;
    }
    if (endpoints.isEmpty) return;
    _manualClose = false;
    final generation = ++_generation;
    final abort = _abort = Completer<void>();
    final done = _connecting = Completer<void>();
    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      await _dispose();
      if (abort.isCompleted || generation != _generation) return;
      if (retry && endpoints.length > 1) _endpointIndex = (_endpointIndex + 1) % endpoints.length;
      final endpoint = endpoints[_endpointIndex % endpoints.length];
      final handshake = _connector(
        endpoint,
        headers: headers,
        protocols: protocols,
        route: proxy.routeFor(site, endpoint),
        connectTimeout: connectTimeout,
      );
      final channel = await Future.any<SocketChannel?>([handshake, abort.future.then((_) => null)]);
      if (channel == null || abort.isCompleted || generation != _generation) {
        // Abandoned: whenever the handshake still completes, close its socket.
        unawaited(handshake.then(_closeChannel, onError: (Object _) {}));
        return;
      }
      _ready(channel, generation);
    } on Object catch (error) {
      if (!_manualClose && generation == _generation) _scheduleReconnect('$error');
    } finally {
      if (identical(_abort, abort)) _abort = null;
      if (identical(_connecting, done)) _connecting = null;
      done.complete();
    }
  }

  void _ready(SocketChannel channel, int generation) {
    _channel = channel;
    _status = SocketStatus.connected;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lastMessageAt = DateTime.now();
    _subscription = channel.stream.listen(
      (message) {
        if (_manualClose || generation != _generation) return;
        _failures = 0;
        _lastMessageAt = DateTime.now();
        onMessage?.call(message);
      },
      onError: (Object error, StackTrace _) {
        if (!_manualClose && generation == _generation) _scheduleReconnect('$error');
      },
      onDone: () {
        if (_manualClose || generation != _generation) return;
        final code = channel.closeCode;
        final reason = channel.closeReason?.trim();
        _scheduleReconnect(
          'WebSocket closed'
          '${code == null ? '' : ' (code=$code)'}'
          '${reason == null || reason.isEmpty ? '' : ': $reason'}',
        );
      },
      cancelOnError: true,
    );
    onReady?.call();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    if (heartbeatInterval <= Duration.zero) return;
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (_status != SocketStatus.connected) return;
      final last = _lastMessageAt;
      if (last != null && DateTime.now().difference(last) >= _silenceLimit) {
        _scheduleReconnect('WebSocket heartbeat timed out');
        return;
      }
      onHeartbeat?.call();
    });
  }

  Duration get _silenceLimit {
    final configured = inactivityTimeout;
    if (configured != null) return configured;
    final window = heartbeatInterval * 3;
    const minimum = Duration(seconds: 90);
    return window > minimum ? window : minimum;
  }

  void _scheduleReconnect(String reason) {
    if (_manualClose || endpoints.isEmpty || (_reconnectTimer?.isActive ?? false)) return;
    onFailure?.call(reason);
    _status = SocketStatus.failed;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_failures == 0) onReconnecting?.call();
    if (_failures >= maxReconnects) {
      onClosed?.call(reason);
      unawaited(close());
      return;
    }
    _failures++;
    _endpointIndex = (_endpointIndex + 1) % endpoints.length;
    // The next endpoint at once; a longer pause after every full round.
    final rounds = _failures ~/ endpoints.length;
    _reconnectTimer = Timer(reconnectBaseDelay * (rounds.clamp(0, 5) + 1), () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  /// Sends [message] when connected; a send error starts a reconnect.
  void send(Object message) {
    if (_status != SocketStatus.connected) return;
    try {
      _channel?.add(message);
    } on Object catch (error) {
      _scheduleReconnect('$error');
    }
  }

  /// Drops the current connection and reconnects (for example after a
  /// platform asked for it).
  void reconnect() {
    if (!_manualClose) _scheduleReconnect('Reconnect requested');
  }

  Future<void> _dispose({bool waitForClose = true}) async {
    try {
      await _subscription?.cancel().timeout(shutdownTimeout);
    } on Object {
      // Bounded teardown.
    }
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final channel = _channel;
    _channel = null;
    _lastMessageAt = null;
    if (channel == null) return;
    final closing = _closeChannel(channel);
    if (!waitForClose) return;
    try {
      await closing.timeout(shutdownTimeout);
    } on TimeoutException {
      // The close stays observed by _closeChannel; release the caller.
    }
  }

  Future<void> _closeChannel(SocketChannel channel) async {
    try {
      await channel.close();
    } on Object {
      // Already closed or broken.
    }
  }

  /// Closes the socket, cancels reconnects and aborts a pending handshake.
  Future<void> close() async {
    _manualClose = true;
    _generation++;
    _status = SocketStatus.closed;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final pending = _connecting?.future;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    // While a handshake is pending, a graceful close could wait for an
    // upgrade that never comes; the abort owns that attempt.
    await _dispose(waitForClose: pending == null);
    await pending;
  }
}
