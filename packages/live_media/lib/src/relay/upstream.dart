import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv.dart';

/// One upstream FLV connection as packets: the file header first, then tags.
abstract interface class FlvPacketSource {
  /// The next packet, or null once the connection ended (clean close, reset,
  /// idle timeout or a framing error); the splicer decides what follows.
  Future<Uint8List?> next();

  /// Drops the connection.
  Future<void> cancel();
}

/// Opens an upstream connection for [line].
typedef FlvSourceOpener = Future<FlvPacketSource> Function(StreamLine line);

/// The upstream request answered with a status other than 200.
final class UpstreamStatusException implements Exception {
  /// Creates the exception.
  const new(this.status, this.url);

  /// HTTP status.
  final int status;

  /// Requested URL.
  final Uri url;

  @override
  String toString() => 'Upstream answered HTTP $status for ${url.host}';
}

/// Opens [line] over `dart:io` with TLS verification on (SRC-4), the line's
/// headers, and [proxyDirective] as `HttpClient.findProxy`'s answer.
///
/// Reading stops after [idleTimeout] without data while the reader is
/// waiting (SRC-4); while the splicer is not reading, the socket is paused
/// once 2048 packets are queued.
Future<FlvPacketSource> openHttpFlv(
  StreamLine line, {
  String proxyDirective = 'DIRECT',
  Duration connectTimeout = const Duration(seconds: 15),
  Duration idleTimeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient()
    ..connectionTimeout = connectTimeout
    ..autoUncompress = false
    ..findProxy = ((_) => proxyDirective);
  try {
    final request = await client.getUrl(line.url).timeout(connectTimeout);
    line.headers.forEach(request.headers.set);
    final response = await request.close().timeout(connectTimeout);
    if (response.statusCode != HttpStatus.ok) {
      unawaited(response.drain<void>().catchError((Object _) {}));
      throw UpstreamStatusException(response.statusCode, line.url);
    }
    return _HttpFlvSource(client, response, idleTimeout);
  } on Object {
    client.close(force: true);
    rethrow;
  }
}

final class _HttpFlvSource implements FlvPacketSource {
  new(this._client, Stream<List<int>> body, this._idleTimeout) {
    _subscription = body.listen(
      _onChunk,
      onError: (Object error, StackTrace _) => _finish(error),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  static const _pauseAbove = 2048;
  static const _resumeBelow = 512;

  final HttpClient _client;
  final Duration _idleTimeout;
  final _framer = FlvFramer();
  final _queue = ListQueue<Uint8List>();
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Timer? _idle;
  var _done = false;

  /// Why the connection ended, for diagnostics.
  Object? endReason;

  void _onChunk(List<int> chunk) {
    try {
      _queue.addAll(_framer.add(chunk));
    } on FormatException catch (error) {
      _finish(error);
      unawaited(_subscription.cancel());
      return;
    }
    _wake();
    if (_queue.length > _pauseAbove && !_subscription.isPaused) _subscription.pause();
  }

  void _finish([Object? reason]) {
    if (_done) return;
    _done = true;
    endReason = reason;
    _idle?.cancel();
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  @override
  Future<Uint8List?> next() async {
    while (_queue.isEmpty) {
      if (_done) return null;
      if (_subscription.isPaused) _subscription.resume();
      _idle ??= Timer(_idleTimeout, () {
        _finish(TimeoutException('No upstream data', _idleTimeout));
        unawaited(_subscription.cancel());
        _client.close(force: true);
      });
      await (_waiter ??= Completer<void>()).future;
      _idle?.cancel();
      _idle = null;
    }
    final packet = _queue.removeFirst();
    if (_queue.length < _resumeBelow && _subscription.isPaused && !_done) _subscription.resume();
    return packet;
  }

  @override
  Future<void> cancel() async {
    _finish();
    _queue.clear();
    _client.close(force: true);
    try {
      await _subscription.cancel();
    } on Object {
      // Already failed.
    }
  }
}
