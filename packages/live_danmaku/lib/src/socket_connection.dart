import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// Timing of one platform's danmaku socket: 3.x's `WebScoketUtils`
/// parameters plus the platform's join timer. Each platform fills it from its
/// 3.x values (docs/D-弹幕/D01-平台弹幕协议/D01.1-弹幕框架和过滤/record.md lists them); the defaults are
/// the ones every 3.x platform shared.
@immutable
final class DanmakuSocketPolicy {
  /// Creates the policy.
  const new({
    required this.heartbeatInterval,
    this.inactivityTimeout,
    this.joinTimeout,
    this.maxReconnects = 8,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.connectTimeout = const Duration(seconds: 10),
    this.shutdownTimeout = const Duration(seconds: 2),
  });

  /// Heartbeat period (3.x `heartbeatTime`); zero sends none and turns the
  /// silence watchdog off.
  final Duration heartbeatInterval;

  /// Silence after which the socket is replaced; null means three heartbeat
  /// periods, at least 90 s.
  final Duration? inactivityTimeout;

  /// How long the platform has to confirm the join after the socket opened
  /// (Bilibili's auth reply 8 s, YY's handshake 15 s); then
  /// [DanmakuSocketConnection.onJoinTimeout] runs. Null: no limit.
  final Duration? joinTimeout;

  /// Failures in a row before giving up with
  /// [DanmakuCloseReason.reconnectsExhausted]; any message resets the count.
  final int maxReconnects;

  /// Wait before a reconnect: the next endpoint is tried after this delay,
  /// and it grows by one step after every full round of endpoints (at most
  /// six times).
  final Duration reconnectBaseDelay;

  /// Longest wait for one opening handshake.
  final Duration connectTimeout;

  /// Longest wait for a closing handshake.
  final Duration shutdownTimeout;
}

/// An opening handshake of a [DanmakuSocketConnection] that failed, for
/// [DanmakuSocketConnection.onHandshakeFailure].
@immutable
final class DanmakuHandshakeFailure {
  /// Creates the failure.
  const new({required this.endpoint, required this.error});

  /// The endpoint of the handshake.
  final Uri endpoint;

  /// What the connector threw: a [WebSocketException] when the server
  /// answered without upgrading, a [TimeoutException], [SocketException] or
  /// TLS error when no answer came.
  final Object error;

  /// Whether the server answered but refused the upgrade (an HTTP status
  /// other than 101, or an answer that failed the upgrade's checks), rather
  /// than the connection failing or timing out.
  bool get refused => error is WebSocketException;

  /// The HTTP status of the refusal (403 for a session the server no longer
  /// accepts), when the connector reports one: `dart:io`'s handshake does
  /// (`WebSocketException.httpStatusCode`); `connectExactWebSocket` only
  /// names the status line in its message.
  int? get statusCode => switch (error) {
    WebSocketException(:final httpStatusCode) => httpStatusCode,
    _ => null,
  };
}

/// Where one connection goes; built from the platform's arguments.
@immutable
final class DanmakuSocketTarget {
  /// Creates the target.
  const new({required this.endpoints, this.headers = const {}, this.protocols});

  /// Endpoints in order of preference; failures move to the next one.
  final List<Uri> endpoints;

  /// Handshake headers.
  final Map<String, String> headers;

  /// Subprotocols offered in the handshake (SOOP's `chat`).
  final List<String>? protocols;
}

/// A danmaku connection over a reconnecting WebSocket ([LiveSocket]), the
/// runtime shared by 3.x's socket platforms (Bilibili, Douyu, Huya, Douyin,
/// SOOP, Twitch, YY).
///
/// A platform supplies the [target] of a room, what to send when the socket
/// opens ([onOpen]), how to read a frame ([onData]) and its heartbeat frame
/// ([heartbeatFrame]); the runtime does the rest as 3.x did:
///
/// - the first attempt completes [connect]; later ones are reported:
///   [DanmakuReconnecting] once per streak of failures (3.x `onReconnect`),
///   [DanmakuReady] whenever the platform confirms the join again,
///   [DanmakuClosed] with [DanmakuCloseReason.reconnectsExhausted] when the
///   policy's reconnects run out, unless [onReconnectsExhausted] takes over;
/// - heartbeats every [DanmakuSocketPolicy.heartbeatInterval] while the socket
///   is open, a silent socket replaced, endpoints rotated with the policy's
///   backoff;
/// - the join timer of [DanmakuSocketPolicy.joinTimeout] restarted at every
///   open;
/// - a failed handshake reported to [onHandshakeFailure], which may renew
///   the handshake headers before the next attempt.
abstract base class DanmakuSocketConnection<A extends Object> extends DanmakuConnectionBase<A> {
  /// Creates the connection for platform [site] (it selects the [proxy]
  /// route); `connector` replaces `dart:io`'s handshake (the case-sensitive
  /// one YY and SOOP need).
  new({required this.site, required this.policy, this.proxy = const FixedProxyPolicy(), this._connector})
    : super(heartbeatInterval: policy.heartbeatInterval);

  /// Platform id.
  final String site;

  /// Socket timing.
  final DanmakuSocketPolicy policy;

  /// Proxy routes, read at every handshake.
  final ProxyPolicy proxy;

  final SocketConnector? _connector;
  DanmakuSocketSession? _session;

  /// Where to connect for [args]; may wait for signatures or credentials.
  /// Throw [DanmakuStartFailure] when the room cannot be joined.
  @protected
  Future<DanmakuSocketTarget> target(A args, DanmakuRun run);

  /// The socket opened (also after every reconnect): send the join frames,
  /// and call [DanmakuSocketSession.ready] when an open socket already
  /// counts as joined.
  @protected
  void onOpen(DanmakuSocketSession session);

  /// A frame arrived: a `String` for text, `List<int>` for binary.
  @protected
  void onData(DanmakuSocketSession session, Object? data);

  /// The heartbeat frame to send now, or null for none (3.x `heartbeat()`).
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => null;

  /// The join was not confirmed within [DanmakuSocketPolicy.joinTimeout]:
  /// reconnects without a notice of its own (Bilibili). YY reconnects with a
  /// [DanmakuInterruption.handshakeTimeout] notice.
  @protected
  void onJoinTimeout(DanmakuSocketSession session) => session.reconnect();

  /// Detail of the [DanmakuInterruption.disconnected] notice from the last
  /// socket failure; empty, as 3.x showed it only for YY.
  @protected
  String reconnectDetail(String lastFailure) => '';

  /// An opening handshake failed ([failure]): the server refused the upgrade
  /// (for example HTTP 403 for a session it no longer accepts) or no answer
  /// came. The socket reconnects through the policy's backoff as after any
  /// failure; this is where a platform renews what the handshake carries.
  ///
  /// Headers returned here, at once or through a future, replace the
  /// target's for the following handshakes of this socket (a fresh session
  /// cookie); the next handshake waits for the future. Null, the default,
  /// changes nothing and waits for nothing; so does a future that fails.
  /// Called only while the run is current.
  @protected
  FutureOr<Map<String, String>?> onHandshakeFailure(DanmakuSocketSession session, DanmakuHandshakeFailure failure) =>
      null;

  /// The socket gave up after [DanmakuSocketPolicy.maxReconnects] failures
  /// in a row, [lastFailure] the last one. Returns whether the platform
  /// takes over: it then [DanmakuSocketSession.reopen]s or ends the run
  /// itself (Douyin first checks whether the broadcast moved to a new
  /// room). The default ends the run with
  /// [DanmakuCloseReason.reconnectsExhausted], as 3.x did.
  @protected
  bool onReconnectsExhausted(DanmakuSocketSession session, String lastFailure) => false;

  /// Opens the socket of [args]'s [target]. A target without endpoints ends
  /// with [DanmakuCloseReason.connectionFailed] (3.x stayed "connecting").
  @override
  @protected
  Future<void> start(A args, DanmakuRun run) async {
    final target = await this.target(args, run);
    if (!run.isActive) return;
    if (target.endpoints.every((endpoint) => endpoint.toString().trim().isEmpty)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No endpoint');
    }
    final session = _session = DanmakuSocketSession._(this, run);
    await session._open(target);
  }

  @override
  @protected
  Future<void> stop() async {
    final session = _session;
    _session = null;
    await session?._close();
  }

  @override
  void heartbeat() => _session?.heartbeat();
}

/// The socket side of one [DanmakuRun]: what the platform code of a
/// [DanmakuSocketConnection] talks through. Everything does nothing once the
/// run is over.
final class DanmakuSocketSession {
  new _(this._connection, this.run);

  final DanmakuSocketConnection<Object> _connection;

  /// The run: reports messages and state.
  final DanmakuRun run;

  LiveSocket? _socket;
  Timer? _joinTimer;

  /// The last socket failure (a close code and reason, an error), for
  /// diagnostics.
  String get lastFailure => _lastFailure;
  String _lastFailure = '';

  /// Whether the run is still current.
  bool get isActive => run.isActive;

  /// Whether the room counts as joined.
  bool get isConnected => run.isConnected;

  /// Sends a text (`String`) or binary (`List<int>`) frame while the socket
  /// is open; dropped otherwise, as 3.x did.
  void send(Object frame) {
    if (run.isActive) _socket?.send(frame);
  }

  /// Sends the platform's heartbeat frame now.
  void heartbeat() {
    if (!run.isActive) return;
    final frame = _connection.heartbeatFrame(this);
    if (frame != null) _socket?.send(frame);
  }

  /// The room is joined: stops the join timer, reports [DanmakuReady].
  void ready() {
    cancelJoinTimeout();
    run.ready();
  }

  /// Reports a message.
  void message(LiveMessage message) => run.message(message);

  /// No longer joined, without a notice (a join being renegotiated).
  void markDisconnected() => run.markDisconnected();

  /// Stops the join timer (the platform answered the join, even with a
  /// refusal).
  void cancelJoinTimeout() {
    _joinTimer?.cancel();
    _joinTimer = null;
  }

  /// Drops the socket and reconnects through the policy's backoff; with a
  /// [notice], reports it first as [DanmakuReconnecting] (YY). The socket
  /// then reports its own [DanmakuInterruption.disconnected] when this is the
  /// first failure of a streak, as in 3.x.
  void reconnect({DanmakuInterruption? notice, String detail = ''}) {
    if (!run.isActive) return;
    cancelJoinTimeout();
    if (notice != null) run.reconnecting(notice, detail: detail);
    _socket?.reconnect();
  }

  /// Replaces the socket with one to [target] without a notice (Bilibili
  /// after new credentials): the old one is closed first, and the new one
  /// starts with a fresh reconnect count.
  Future<void> reopen(DanmakuSocketTarget target) async {
    if (!run.isActive) return;
    cancelJoinTimeout();
    final previous = _socket;
    _socket = null;
    await previous?.close();
    if (run.isActive) await _open(target);
  }

  Future<void> _open(DanmakuSocketTarget target) async {
    final policy = _connection.policy;
    final connector = _connection._connector ?? connectIoSocket;
    late final LiveSocket socket;
    bool current() => run.isActive && identical(_socket, socket);
    // The target's headers until a failed handshake renews them.
    var handshakeHeaders = target.headers;
    Future<void>? renewing;
    void failed(Uri endpoint, Object error) {
      final FutureOr<Map<String, String>?> renewed;
      try {
        renewed = _connection.onHandshakeFailure(this, DanmakuHandshakeFailure(endpoint: endpoint, error: error));
      } on Object {
        return;
      }
      if (renewed is Map<String, String>) {
        handshakeHeaders = renewed;
      } else if (renewed is Future<Map<String, String>?>) {
        final wait = renewing = renewed.then<void>((headers) {
          if (headers != null && current()) handshakeHeaders = headers;
        }, onError: (Object _) {});
        unawaited(
          wait.whenComplete(() {
            if (identical(renewing, wait)) renewing = null;
          }),
        );
      }
    }

    // Every handshake of this socket goes through here: it waits for renewed
    // headers and reports a failure to the platform.
    Future<SocketChannel> handshake(
      Uri endpoint, {
      required Map<String, String> headers,
      required Iterable<String>? protocols,
      required ProxyRoute route,
      required Duration connectTimeout,
    }) async {
      final pending = renewing;
      if (pending != null) {
        await pending;
        if (!current()) throw StateError('Danmaku socket closed while its handshake headers were renewed');
      }
      try {
        return await connector(
          endpoint,
          headers: handshakeHeaders,
          protocols: protocols,
          route: route,
          connectTimeout: connectTimeout,
        );
      } on Object catch (error) {
        if (current()) failed(endpoint, error);
        rethrow;
      }
    }

    socket = LiveSocket(
      endpoints: target.endpoints,
      site: _connection.site,
      proxy: _connection.proxy,
      headers: target.headers,
      protocols: target.protocols,
      heartbeatInterval: policy.heartbeatInterval,
      inactivityTimeout: policy.inactivityTimeout,
      maxReconnects: policy.maxReconnects,
      reconnectBaseDelay: policy.reconnectBaseDelay,
      connectTimeout: policy.connectTimeout,
      shutdownTimeout: policy.shutdownTimeout,
      connector: handshake,
      onReady: () {
        if (current()) _opened();
      },
      onMessage: (data) {
        if (current()) _connection.onData(this, data);
      },
      onHeartbeat: () {
        if (current()) heartbeat();
      },
      onFailure: (reason) {
        if (!current()) return;
        _lastFailure = reason;
        cancelJoinTimeout();
      },
      onReconnecting: () {
        if (current()) {
          run.reconnecting(DanmakuInterruption.disconnected, detail: _connection.reconnectDetail(_lastFailure));
        }
      },
      onClosed: (reason) {
        if (!current() || _connection.onReconnectsExhausted(this, reason)) return;
        run.closed(DanmakuCloseReason.reconnectsExhausted, detail: reason);
      },
    );
    _socket = socket;
    await socket.connect();
  }

  void _opened() {
    cancelJoinTimeout();
    final timeout = _connection.policy.joinTimeout;
    if (timeout != null) {
      _joinTimer = Timer(timeout, () {
        _joinTimer = null;
        if (run.isActive && !run.isConnected) _connection.onJoinTimeout(this);
      });
    }
    _connection.onOpen(this);
  }

  Future<void> _close() async {
    cancelJoinTimeout();
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}
