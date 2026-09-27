import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/remux/ts_demux.dart';

/// One upstream HTTP response body as bytes: a single HTTP stream
/// (`StreamFormat.other`, spec §8).
abstract interface class ByteSource {
  /// The next bytes; null once the stream ended cleanly. Throws the error
  /// that ended it otherwise (reset, idle timeout), after the bytes before it.
  Future<Uint8List?> next();

  /// Drops the connection.
  Future<void> cancel();
}

/// Opens a single HTTP stream for [line].
typedef ByteSourceOpener = Future<ByteSource> Function(StreamLine line);

/// Opens [line] over `dart:io` with TLS verification on, the line's headers
/// and [proxyDirective] as `HttpClient.findProxy`'s answer, like the FLV
/// connections (spec §18). A status other than 200 throws
/// [UpstreamStatusException]. Reading ends with a [TimeoutException] after
/// [idleTimeout] (`record.readTimeout`) without data while the reader
/// waits; the socket is paused while 4 MiB wait to be read (backpressure).
Future<ByteSource> openHttpStream(
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
    return _HttpByteSource(client, response, idleTimeout);
  } on Object {
    client.close(force: true);
    rethrow;
  }
}

final class _HttpByteSource implements ByteSource {
  new(this._client, Stream<List<int>> body, this._idleTimeout) {
    _subscription = body.listen(_onChunk, onError: _finish, onDone: _finish, cancelOnError: true);
  }

  static const int _pauseAbove = 4 << 20;
  static const int _resumeBelow = 1 << 20;

  final HttpClient _client;
  final Duration _idleTimeout;
  final _queue = ListQueue<Uint8List>();
  var _queued = 0;
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Timer? _idle;
  var _done = false;
  Object? _error;
  StackTrace? _stack;

  void _onChunk(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    if (bytes.isEmpty) return;
    _queue.add(bytes);
    _queued += bytes.length;
    _wake();
    if (_queued > _pauseAbove && !_subscription.isPaused) _subscription.pause();
  }

  void _finish([Object? error, StackTrace? stack]) {
    if (_done) return;
    _done = true;
    _error = error;
    _stack = stack;
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
      if (_done) {
        final error = _error;
        if (error != null) Error.throwWithStackTrace(error, _stack ?? StackTrace.current);
        return null;
      }
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
    final bytes = _queue.removeFirst();
    _queued -= bytes.length;
    if (_queued < _resumeBelow && _subscription.isPaused && !_done) _subscription.resume();
    return bytes;
  }

  @override
  Future<void> cancel() async {
    _finish();
    _queue.clear();
    _queued = 0;
    _client.close(force: true);
    try {
      await _subscription.cancel();
    } on Object {
      // Already failed.
    }
  }
}

/// What a single HTTP stream holds, by its first bytes (spec §8.1).
enum StreamContent {
  /// An FLV file header.
  flv,

  /// MPEG-TS: five 188-byte packets in a row.
  ts,

  /// An HLS playlist (`#EXTM3U`).
  hls,

  /// Anything else: not recorded.
  unknown,
}

/// Bytes a sniff reads at most before it gives up.
const int sniffLimit = 64 * 1024;

/// Aligned sync bytes that make a stream MPEG-TS.
const tsSniffPackets = 5;

const _m3u = '#EXTM3U';

/// Offset in `[0, 188)` from which [tsSniffPackets] packets start with the
/// sync byte in [data]; -1 when there is none; null when more bytes could
/// still make one.
int? tsSyncOffset(Uint8List data, {int packets = tsSniffPackets}) {
  var viable = false;
  for (var offset = 0; offset < tsPacketSize; offset++) {
    if (offset >= data.length) {
      viable = true;
      break;
    }
    var ok = true;
    var complete = true;
    for (var i = 0; i < packets; i++) {
      final at = offset + i * tsPacketSize;
      if (at >= data.length) {
        complete = false;
        break;
      }
      if (data[at] != tsSync) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    if (complete) return offset;
    viable = true;
  }
  return viable ? null : -1;
}

/// What the first bytes [head] of a single HTTP stream hold; null while
/// more bytes could tell. [ended]: no more bytes will come.
StreamContent? sniffContent(Uint8List head, {bool ended = false}) {
  if (head.length >= 3 && head[0] == 0x46 && head[1] == 0x4C && head[2] == 0x56) return StreamContent.flv;
  var undecided = head.length < 3 && _prefixOf(head, 'FLV'.codeUnits);
  var at = head.length >= 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF ? 3 : 0;
  while (at < head.length && (head[at] == 0x20 || head[at] == 0x09 || head[at] == 0x0D || head[at] == 0x0A)) {
    at++;
  }
  final rest = Uint8List.sublistView(head, at);
  if (rest.length >= _m3u.length && _prefixOf(_m3u.codeUnits, rest.sublist(0, _m3u.length))) return StreamContent.hls;
  if (rest.length < _m3u.length && _prefixOf(rest, _m3u.codeUnits)) undecided = true;
  final sync = tsSyncOffset(head);
  if (sync != null && sync >= 0) return StreamContent.ts;
  if (sync == null) undecided = true;
  if (ended || head.length >= sniffLimit || !undecided) return StreamContent.unknown;
  return null;
}

bool _prefixOf(List<int> prefix, List<int> of) {
  if (prefix.length > of.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (prefix[i] != of[i]) return false;
  }
  return true;
}

/// The sniffed start of a single HTTP stream.
final class StreamSniff {
  /// Creates a result.
  const new(this.content, this.head);

  /// What the stream holds.
  final StreamContent content;

  /// The bytes read so far; they belong to the stream.
  final Uint8List head;
}

/// Reads the start of [source] until [sniffContent] decides (at most
/// [sniffLimit] bytes). A stream that ends before any byte throws
/// [StateError]; errors of [source] propagate.
Future<StreamSniff> sniffStream(ByteSource source) async {
  final head = BytesBuilder(copy: false);
  while (true) {
    final bytes = await source.next();
    if (bytes != null) head.add(bytes);
    final data = head.toBytes();
    if (bytes == null && data.isEmpty) throw StateError('the stream ended before any data');
    final content = sniffContent(data, ended: bytes == null);
    if (content != null) return StreamSniff(content, data);
  }
}

/// An FLV connection over a single HTTP stream sniffed as FLV: the bytes
/// read so far, then the rest, framed into FLV packets like `openHttpFlv`.
/// Bad framing or a failing source ends it (the splicer then decides).
final class FlvByteSource implements FlvPacketSource {
  /// Creates the source; [head] are the bytes the sniff read.
  new(this._source, Uint8List head) {
    _feed(head);
  }

  final ByteSource _source;
  final _framer = FlvFramer();
  final _queue = ListQueue<Uint8List>();
  var _done = false;

  /// Why the connection ended, for diagnostics.
  Object? endReason;

  void _feed(Uint8List bytes) {
    try {
      _queue.addAll(_framer.add(bytes));
    } on FormatException catch (error) {
      endReason = error;
      _done = true;
      unawaited(_source.cancel());
    }
  }

  @override
  Future<Uint8List?> next() async {
    while (_queue.isEmpty) {
      if (_done) return null;
      Uint8List? bytes;
      try {
        bytes = await _source.next();
      } on Object catch (error) {
        endReason = error;
      }
      if (bytes == null) {
        _done = true;
        return null;
      }
      _feed(bytes);
    }
    return _queue.removeFirst();
  }

  @override
  Future<void> cancel() async {
    _done = true;
    _queue.clear();
    await _source.cancel();
  }
}
