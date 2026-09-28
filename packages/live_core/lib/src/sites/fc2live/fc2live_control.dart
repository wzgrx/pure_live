import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/fc2live/fc2live_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'fc2live';

/// One FC2 media-control seat (3.x's `Fc2ControlSession`): the WebSocket
/// whose session authorises a channel's HLS playlists. The media server
/// refuses variant playlists once the socket is gone, so whoever opens the
/// control (playback, recording) keeps it open for exactly as long as its
/// consumer reads the master, and closes it afterwards (M7, M8).
///
/// Protocol (3.x): the handshake carries the site's origin and UA and the
/// grant's `l_ortkn` cookie; after `connect_complete` the control sends
/// `get_hls_information` once and is open when the answer names the
/// channel's master playlist ([Fc2LiveApi.hlsMaster]); the socket pings
/// every 15 s ([pingInterval]). Only text frames of at most 2 MiB are
/// understood; anything else, `control_disconnection` (the grant expired),
/// an error or the socket closing ends the control, which never reconnects
/// with a used grant: [done] says why and the owner takes a new grant.
final class Fc2LiveControl {
  new _(this.grant, this._startupTimeout, this._closeTimeout, this._timer);

  /// Opens the control socket of [grant] through [route] with [connector]
  /// and waits, at most [startupTimeout] for the handshake and the master
  /// together, for the HLS answer.
  ///
  /// A cancelled [cancel] opens nothing; cancelling while it opens ends the
  /// control (the open throws a cancelled `TransportFailure`). Once open,
  /// the control belongs to the caller, who closes it: a later
  /// cancellation of [cancel] does not end it (3.x). A handshake that
  /// finishes after the control ended is closed at once.
  static Future<Fc2LiveControl> open(
    Fc2LiveGrant grant, {
    required SocketConnector connector,
    ProxyRoute route = const DirectRoute(),
    CancelToken? cancel,
    Duration startupTimeout = const Duration(seconds: 20),
    Duration closeTimeout = const Duration(seconds: 2),
    Timer Function(Duration duration, void Function() callback)? timer,
  }) async {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
    final control = Fc2LiveControl._(grant, startupTimeout, closeTimeout, timer ?? Timer.new);
    if (cancel != null) {
      unawaited(
        cancel.whenCancelled.then((_) {
          if (!control._ready.isCompleted) control._end(const TransportFailure(_site, TransportReason.cancelled));
        }),
      );
    }
    control._startup = control._timer(
      startupTimeout,
      () => control._end(NetworkFailure(_site, 'control: no HLS information within ${startupTimeout.inSeconds} s')),
    );
    unawaited(control._handshake(connector, route));
    try {
      await control._ready.future;
      return control;
    } on Object {
      await control.close();
      rethrow;
    }
  }

  /// [connectIoSocket] with 3.x's WebSocket ping: every [pingInterval].
  static Future<SocketChannel> connect(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) => connectIoSocket(
    endpoint,
    headers: headers,
    protocols: protocols,
    route: route,
    connectTimeout: connectTimeout,
    pingInterval: pingInterval,
  );

  /// 3.x's WebSocket ping interval.
  static const Duration pingInterval = Duration(seconds: 15);

  /// The largest message 3.x accepted.
  static const int messageLimit = 2 * 1024 * 1024;

  /// The one request (3.x's text, byte for byte).
  static const String hlsRequest = '{"name":"get_hls_information","arguments":{},"id":1}';

  /// The grant the control was opened with (used once).
  final Fc2LiveGrant grant;

  final Duration _startupTimeout;
  final Duration _closeTimeout;
  final Timer Function(Duration, void Function()) _timer;

  final Completer<void> _ready = Completer<void>();
  final Completer<Exception?> _done = Completer<Exception?>();
  SocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _startup;
  Uri? _master;
  Exception? _failure;
  Future<void>? _closing;
  bool _closed = false;
  bool _requested = false;

  /// The channel.
  String get channelId => grant.channelId;

  /// The channel's low-latency master playlist (3.x's `master`), known
  /// once the control opened; worth opening only while [isClosed] is false.
  Uri get master => _master ?? (throw StateError('the FC2 control never opened'));

  /// The headers of every media request (3.x's `Fc2Api.mediaHeaders`).
  Map<String, String> get mediaHeaders => Fc2LiveApi.mediaHeaders(channelId);

  /// Completes when the control has ended: null after [close], else why (a
  /// `SiteError`, or a cancelled `TransportFailure`).
  Future<Exception?> get done => _done.future;

  /// Whether the control has ended (3.x's `isClosed`): its master must not
  /// be opened any more.
  bool get isClosed => _closed;

  Future<void> _handshake(SocketConnector connector, ProxyRoute route) async {
    final SocketChannel channel;
    try {
      channel = await connector(
        grant.endpoint,
        headers: grant.handshakeHeaders,
        protocols: null,
        route: route,
        connectTimeout: _startupTimeout,
      );
    } on Object catch (error) {
      _end(NetworkFailure(_site, 'control handshake: ${error.runtimeType}'));
      return;
    }
    if (_closed) {
      // The control ended (timeout, cancel) while the handshake was pending.
      unawaited(_quietly(channel.close()));
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _receive,
      onError: (Object error, StackTrace _) => _end(NetworkFailure(_site, 'control: ${error.runtimeType}')),
      onDone: () {
        final code = channel.closeCode;
        _end(NetworkFailure(_site, 'control closed by the server${code == null ? '' : ' ($code)'}'));
      },
      cancelOnError: true,
    );
  }

  void _receive(Object? frame) {
    if (_closed) return;
    try {
      if (frame is! String || frame.length > messageLimit) {
        throw const ApiChanged(_site, 'control: not a text frame of at most 2 MiB');
      }
      final Object? message;
      try {
        message = jsonDecode(frame);
      } on FormatException {
        throw const ApiChanged(_site, 'control: frame is not JSON');
      }
      if (message is! Map<String, dynamic>) throw const ApiChanged(_site, 'control: message is not an object');
      switch (message['name']) {
        case 'connect_complete':
          if (!_requested) {
            _requested = true;
            _send(hlsRequest);
          }
        case '_response_' when message['id'] == 1 && _requested && _master == null:
          _master = Fc2LiveApi.hlsMaster(message, channelId: channelId);
          _startup?.cancel();
          if (!_ready.isCompleted) _ready.complete();
        case 'control_disconnection':
          final arguments = message['arguments'];
          final code = arguments is Map ? arguments['code'] : null;
          // 4500: the grant expired. 3.x treated every disconnection as a
          // transport failure, so the consumer takes a new grant.
          _end(NetworkFailure(_site, 'control_disconnection${code == null ? '' : ' $code'}'));
        // initial_connect, connect_data, user_count, comments and the rest
        // grant nothing.
      }
    } on SiteError catch (error) {
      _end(error);
    }
  }

  void _send(String text) {
    final channel = _channel;
    if (_closed || channel == null) return;
    try {
      channel.add(text);
    } on Object catch (error) {
      _end(NetworkFailure(_site, 'control send: ${error.runtimeType}'));
    }
  }

  void _end(Exception reason) {
    if (_closed) return;
    _failure = reason;
    unawaited(close());
  }

  /// Ends the control: the startup timer stops and the socket is closed,
  /// waiting at most the close timeout (3.x: 2 s). Idempotent.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    _startup?.cancel();
    if (!_ready.isCompleted) {
      _ready.completeError(_failure ?? const StreamUnavailable(_site, 'the control was closed'));
    }
    return _closing = _dispose();
  }

  Future<void> _dispose() async {
    final cancelling = _subscription?.cancel();
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await Future.wait<void>([
      ?cancelling == null ? null : _quietly(cancelling),
      if (channel != null) _quietly(channel.close()),
    ]).timeout(_closeTimeout, onTimeout: () => const []);
    _done.complete(_failure);
  }

  static Future<void> _quietly(Future<void> future) async {
    try {
      await future;
    } on Object {
      // Already closed or broken.
    }
  }
}
