import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/niconico/niconico_parse.dart';
import 'package:live_net/live_net.dart';

const _site = 'niconico';

/// A text WebSocket a seat talks over (injectable for tests).
abstract interface class NiconicoSocket {
  /// Received text messages; the stream ends when the socket closes.
  Stream<String> get messages;

  /// Sends one text message; ignored after close.
  void send(String text);

  /// Closes the socket.
  Future<void> close();
}

/// Opens a [NiconicoSocket] to [url] with [headers].
typedef NiconicoConnect = Future<NiconicoSocket> Function(Uri url, Map<String, String> headers);

/// [NiconicoConnect] on `dart:io` through [route] (the platform's proxy
/// route, so the seat takes the same path as the adapter's HTTP).
NiconicoConnect ioNiconicoConnect(ProxyRoute route) => (url, headers) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..findProxy = (_) => route.directive;
  try {
    final socket = await WebSocket.connect(
      url.toString(),
      headers: headers,
      customClient: client,
    ).timeout(const Duration(seconds: 15));
    client.close();
    return _IoSocket(socket);
  } on Object {
    client.close(force: true);
    rethrow;
  }
};

final class _IoSocket implements NiconicoSocket {
  new(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages => _socket.where((data) => data is String).cast<String>();

  @override
  void send(String text) {
    if (_socket.readyState == WebSocket.open) _socket.add(text);
  }

  @override
  Future<void> close() =>
      _socket.close(WebSocketStatus.normalClosure).timeout(const Duration(seconds: 2), onTimeout: () {});
}

/// One watching seat (spec/sites/niconico.md §6.2): the WebSocket session
/// that holds the stream grant. The key server refuses new AES keys within
/// a minute after the seat closes, so the seat must stay open for as long
/// as anything plays the grant. The seat answers `ping` with `pong` and
/// sends `keepSeat` every `keepIntervalSec`.
final class NiconicoSeat {
  new _(this._socket);

  /// Opens a seat on the watch page's [socket] URL and waits (up to
  /// [timeout]) for both the `seat` and the `stream` messages.
  static Future<NiconicoSeat> open(
    Uri socket, {
    required NiconicoConnect connect,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final NiconicoSocket raw;
    try {
      raw = await connect(socket, const {'Origin': 'https://live.nicovideo.jp'});
    } on SiteError {
      rethrow;
    } on Object catch (error) {
      throw NetworkFailure(_site, 'seat: $error');
    }
    final seat = NiconicoSeat._(raw).._listen();
    raw.send(
      jsonEncode({
        'type': 'startWatching',
        'data': {
          'stream': {'quality': 'abr', 'protocol': 'hls', 'latency': 'high', 'chasePlay': false},
          'room': {'protocol': 'webSocket', 'commentable': false},
          'reconnect': false,
        },
      }),
    );
    try {
      await seat._ready.future.timeout(timeout);
      return seat;
    } on TimeoutException {
      await seat.close();
      throw const NetworkFailure(_site, 'seat: no seat/stream within the timeout');
    } on Object {
      await seat.close();
      rethrow;
    }
  }

  final NiconicoSocket _socket;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _done = Completer<void>();
  StreamSubscription<String>? _subscription;
  Timer? _keep;
  NiconicoGrant? _grant;
  var _seated = false;
  var _closed = false;

  /// The current stream grant (a later `stream` message replaces it).
  NiconicoGrant get grant => _grant!;

  /// The comment server (`messageServer.viewUri`), once announced.
  Uri? messageServer;

  /// Concurrent viewers from the last `statistics` message.
  int? viewers;

  /// Why the seat ended: `disconnect` reason, error code or `closed`.
  String? endReason;

  /// Keep-alive messages sent so far (diagnostics and tests).
  int keepSeats = 0;

  /// Whether the seat is still open.
  bool get isOpen => !_closed;

  /// Completes when the seat has ended.
  Future<void> get done => _done.future;

  void _listen() {
    _subscription = _socket.messages.listen(
      _receive,
      onError: (Object error) => _end('error: $error'),
      onDone: () => _end(endReason ?? 'closed'),
      cancelOnError: true,
    );
  }

  void _send(Map<String, Object?> message) {
    if (!_closed) _socket.send(jsonEncode(message));
  }

  void _keepSeat() {
    if (_seated) {
      _send({'type': 'keepSeat'});
      keepSeats++;
    }
  }

  void _receive(String text) {
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final data = message['data'];
    switch (message['type']) {
      case 'ping':
        _send({'type': 'pong'});
        _keepSeat();
      case 'seat':
        final seconds = data is Map ? data['keepIntervalSec'] : null;
        final interval = seconds is int && seconds > 0 && seconds <= 300 ? seconds : 30;
        _seated = true;
        _keep?.cancel();
        _keep = Timer.periodic(Duration(seconds: interval), (_) => _keepSeat());
        _readyIfComplete();
      case 'stream':
        if (data is Map<String, dynamic>) {
          try {
            _grant = NiconicoParse.grant(data);
          } on SiteError catch (error) {
            if (!_ready.isCompleted) _ready.completeError(error);
            return;
          }
          _readyIfComplete();
        }
      case 'messageServer':
        if (data is Map) messageServer = Uri.tryParse('${data['viewUri']}');
      case 'statistics':
        if (data is Map && data['viewers'] is int) viewers = data['viewers'] as int;
      case 'error':
        final code = data is Map ? '${data['code']}' : 'unknown';
        endReason = 'error $code';
        if (!_ready.isCompleted) _ready.completeError(_error(code));
        unawaited(close());
      case 'disconnect':
        endReason = data is Map ? '${data['reason']}' : 'disconnect';
        if (!_ready.isCompleted) _ready.completeError(StreamUnavailable(_site, 'seat: disconnect $endReason'));
        unawaited(close());
    }
  }

  static SiteError _error(String code) => switch (code) {
    'NO_PERMISSION' || 'NOT_PLAYABLE' || 'TICKET_REQUIRED' => NeedsLogin(_site, 'seat: $code'),
    'TOO_MANY_CONNECTIONS' || 'CONNECT_ERROR' => RateLimited(_site, detail: 'seat: $code'),
    'INVALID_STREAM_QUALITY' || 'INVALID_MESSAGE' => ApiChanged(_site, 'seat: $code'),
    _ => StreamUnavailable(_site, 'seat: $code'),
  };

  void _readyIfComplete() {
    if (_seated && _grant != null && !_ready.isCompleted) _ready.complete();
  }

  void _end(String reason) {
    endReason ??= reason;
    if (!_ready.isCompleted) _ready.completeError(NetworkFailure(_site, 'seat: $reason'));
    unawaited(close());
  }

  /// Closes the seat (idempotent).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _keep?.cancel();
    endReason ??= 'closed';
    unawaited(_subscription?.cancel());
    try {
      await _socket.close();
    } on Object {
      // Already gone.
    }
    if (!_done.isCompleted) _done.complete();
  }
}
