import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/json.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/niconico/niconico_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'niconico';

/// One watching seat (3.x's `NiconicoSession`): the WebSocket that holds a
/// program's stream grant.
///
/// The seat is owned by whoever opened it and never reconnects with an
/// expired bootstrap: when it ends, [done] says why and the owner reads the
/// watch page again. Playback, recording and quality discovery each open
/// their own; none is shared.
///
/// Protocol (3.x): text frames only; `startWatching` (abr, hls, high
/// latency, no comments, no reconnect) and `getAkashic` after the
/// handshake; the seat is ready once both `seat` and `stream` arrived; a
/// later `stream` replaces the grant and revokes the old one; `keepSeat`
/// every `keepIntervalSec`; `ping` is answered with `pong` and one more
/// `keepSeat`; `error` and `disconnect` end the seat, as does 90 s of
/// silence.
final class NiconicoSeat {
  new _(this._startupTimeout, this._silenceTimeout, this._closeTimeout, this._now, this._timer, this._periodic);

  /// Opens a seat on the watch page's [socket] through [route] with
  /// [connector] and waits, at most [startupTimeout], for its first grant.
  ///
  /// A cancelled [cancel] opens nothing; cancelling later ends the seat
  /// (the open throws a cancelled `TransportFailure`). A socket that is not
  /// the seat endpoint is `ApiChanged` without a connection. A handshake
  /// that finishes after the seat ended is closed at once.
  static Future<NiconicoSeat> open(
    Uri socket, {
    required SocketConnector connector,
    ProxyRoute route = const DirectRoute(),
    CancelToken? cancel,
    Duration startupTimeout = const Duration(seconds: 20),
    Duration silenceTimeout = const Duration(seconds: 90),
    Duration closeTimeout = const Duration(seconds: 2),
    DateTime Function()? now,
    Timer Function(Duration duration, void Function() callback)? timer,
    Timer Function(Duration period, void Function(Timer timer) callback)? periodicTimer,
  }) async {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
    if (!NiconicoApi.isSeatSocket(socket)) throw const ApiChanged(_site, 'seat: not a seat WebSocket');
    final seat = NiconicoSeat._(
      startupTimeout,
      silenceTimeout,
      closeTimeout,
      now ?? DateTime.now,
      timer ?? Timer.new,
      periodicTimer ?? Timer.periodic,
    );
    if (cancel != null) {
      unawaited(cancel.whenCancelled.then((_) => seat._end(const TransportFailure(_site, TransportReason.cancelled))));
    }
    seat._startup = seat._timer(
      startupTimeout,
      () => seat._end(NetworkFailure(_site, 'seat: no seat and stream within ${startupTimeout.inSeconds} s')),
    );
    unawaited(seat._handshake(socket, connector, route));
    try {
      await seat._ready.future;
      return seat;
    } on Object {
      await seat.close();
      rethrow;
    }
  }

  final Duration _startupTimeout;
  final Duration _silenceTimeout;
  final Duration _closeTimeout;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timer;
  final Timer Function(Duration, void Function(Timer)) _periodic;

  final Completer<void> _ready = Completer<void>();
  final Completer<Exception?> _done = Completer<Exception?>();
  final StreamController<NiconicoGrant> _changes = StreamController<NiconicoGrant>.broadcast();
  SocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _startup;
  Timer? _silence;
  Timer? _keep;
  NiconicoGrant? _grant;
  Exception? _failure;
  Future<void>? _closing;
  bool _closed = false;
  int? _keepIntervalSeconds;
  int _keepSeatsSent = 0;
  int _pongsSent = 0;
  Uri? _messageServer;

  /// The current grant; `StreamUnavailable` once the seat is closed.
  NiconicoGrant get current {
    final grant = _grant;
    if (_closed || grant == null || _keepIntervalSeconds == null) {
      throw const StreamUnavailable(_site, 'the seat is closed');
    }
    return grant;
  }

  /// Each new grant (the previous one is revoked).
  Stream<NiconicoGrant> get changes => _changes.stream;

  /// Completes when the seat has ended: null after [close], else why (a
  /// `SiteError`, or a cancelled `TransportFailure`).
  Future<Exception?> get done => _done.future;

  /// Whether the seat has ended.
  bool get isClosed => _closed;

  /// `seat.keepIntervalSec` of the last `seat` message.
  int? get keepIntervalSeconds => _keepIntervalSeconds;

  /// `keepSeat` messages sent.
  int get keepSeatsSent => _keepSeatsSent;

  /// `pong` messages sent.
  int get pongsSent => _pongsSent;

  /// The comment server (`messageServer.viewUri`) once announced; for the
  /// danmaku connection (M5). 3.x did not read it.
  Uri? get messageServer => _messageServer;

  Future<void> _handshake(Uri socket, SocketConnector connector, ProxyRoute route) async {
    final SocketChannel channel;
    try {
      channel = await connector(
        socket,
        headers: NiconicoApi.seatHeaders,
        protocols: null,
        route: route,
        connectTimeout: _startupTimeout,
      );
    } on Object catch (error) {
      _end(NetworkFailure(_site, 'seat handshake: ${error.runtimeType}'));
      return;
    }
    if (_closed) {
      // The seat ended (timeout, cancel) while the handshake was pending.
      unawaited(_quietly(channel.close()));
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _receive,
      onError: (Object error, StackTrace _) => _end(NetworkFailure(_site, 'seat: ${error.runtimeType}')),
      onDone: () {
        final code = channel.closeCode;
        _end(NetworkFailure(_site, 'seat closed by the server${code == null ? '' : ' ($code)'}'));
      },
      cancelOnError: true,
    );
    _resetSilence();
    _send({
      'type': 'startWatching',
      'data': {
        'stream': {'quality': 'abr', 'protocol': 'hls', 'latency': 'high', 'chasePlay': false},
        'room': {'protocol': 'webSocket', 'commentable': false},
        'reconnect': false,
      },
    });
    _send({
      'type': 'getAkashic',
      'data': {'chasePlay': false},
    });
  }

  void _resetSilence() {
    _silence?.cancel();
    _silence = _timer(
      _silenceTimeout,
      () => _end(NetworkFailure(_site, 'seat silent for ${_silenceTimeout.inSeconds} s')),
    );
  }

  void _receive(Object? frame) {
    if (_closed) return;
    try {
      if (frame is! String || frame.length > 1024 * 1024) {
        throw const ApiChanged(_site, 'seat: not a text frame of at most 1 MiB');
      }
      final Object? message;
      try {
        message = jsonDecode(frame);
      } on FormatException {
        throw const ApiChanged(_site, 'seat: frame is not JSON');
      }
      if (message is! Map<String, dynamic> || message['type'] is! String) {
        throw const ApiChanged(_site, 'seat: message without a type');
      }
      _resetSilence();
      final data = message['data'];
      switch (message['type']) {
        case 'ping':
          if (_send({'type': 'pong'})) _pongsSent++;
          _keepSeat();
        case 'seat':
          final seconds = NiconicoApi.seatInterval(data);
          _keepIntervalSeconds = seconds;
          _keep?.cancel();
          _keep = _periodic(Duration(seconds: seconds), (_) => _keepSeat());
          _readyIfComplete();
        case 'stream':
          if (data is! Map<String, dynamic>) throw const ApiChanged(_site, 'seat: stream without data');
          final next = NiconicoApi.grant(data, now: _now());
          _grant?.revoke();
          _grant = next;
          _readyIfComplete();
          _changes.add(next);
        case 'messageServer':
          final view = data is Map ? jsonUrl(data['viewUri']) : null;
          if (view != null) _messageServer = view;
        case 'error':
          _end(NiconicoApi.seatError(data));
        case 'disconnect':
          _end(NiconicoApi.seatDisconnect(data));
        // serverTime, schedule, statistics and the rest grant nothing.
      }
    } on SiteError catch (error) {
      _end(error);
    }
  }

  void _readyIfComplete() {
    if (_keepIntervalSeconds != null && _grant != null && !_ready.isCompleted) {
      _startup?.cancel();
      _ready.complete();
    }
  }

  bool _send(Map<String, Object?> message) {
    final channel = _channel;
    if (_closed || channel == null) return false;
    try {
      channel.add(jsonEncode(message));
      return true;
    } on Object catch (error) {
      _end(NetworkFailure(_site, 'seat send: ${error.runtimeType}'));
      return false;
    }
  }

  void _keepSeat() {
    if (_keepIntervalSeconds != null && _send({'type': 'keepSeat'})) _keepSeatsSent++;
  }

  void _end(Exception reason) {
    if (_closed) return;
    _failure = reason;
    unawaited(close());
  }

  /// Ends the seat: timers stop, the grant is revoked and the socket is
  /// closed, waiting at most the close timeout. Idempotent.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    _startup?.cancel();
    _silence?.cancel();
    _keep?.cancel();
    _grant?.revoke();
    if (!_ready.isCompleted) {
      _ready.completeError(_failure ?? const StreamUnavailable(_site, 'the seat was closed'));
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
      if (channel != null) _quietly(channel.close(1000)),
    ]).timeout(_closeTimeout, onTimeout: () => const []);
    unawaited(_changes.close());
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
