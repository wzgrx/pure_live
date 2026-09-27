import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';

/// One captured frame or HTTP exchange.
class CapturedFrame {
  /// Creates a frame.
  new({required this.direction, required this.millis, required this.bytes, this.text = false, this.url});

  /// `in` (received) or `out` (sent).
  final String direction;

  /// Milliseconds since the recording started.
  final int millis;

  /// Frame bytes (UTF-8 for text frames and HTTP bodies).
  List<int> bytes;

  /// Whether it was a text frame or an HTTP body.
  final bool text;

  /// For HTTP polling: the request URL.
  Uri? url;

  /// The frames.jsonl line.
  Map<String, Object?> toJson() => {
    'dir': direction,
    't': millis,
    if (url != null) 'url': url.toString(),
    if (text) 'text': utf8.decode(bytes, allowMalformed: true) else 'b64': base64.encode(bytes),
  };
}

/// Records what the connector sends and receives, then scrubs and writes it
/// as `fixtures/<platform>/danmaku/<case>/{frames.jsonl, meta.json}`
/// (docs/adr/0009-fixture-format.md rule 3).
class FrameRecorder {
  /// Creates a recorder for [detail]'s room.
  new({required this.platform, required this.detail});

  /// Platform id.
  final String platform;

  /// The room.
  final RoomDetail detail;

  final Stopwatch _clock = Stopwatch()..start();
  final List<CapturedFrame> _frames = [];
  final List<({Uri url, Map<String, String> headers})> _handshakes = [];
  final DateTime _started = DateTime.now().toUtc();

  /// Frames captured so far.
  int get frameCount => _frames.length;

  /// Wraps [inner] so every socket and poll is captured.
  DanmakuTransport wrap(DanmakuTransport inner) => _RecordingTransport(inner, this);

  void _add(String direction, List<int> bytes, {bool text = false, Uri? url}) => _frames.add(
    CapturedFrame(direction: direction, millis: _clock.elapsedMilliseconds, bytes: [...bytes], text: text, url: url),
  );

  /// Writes the unscrubbed capture to [path] (local debugging only; never
  /// commit it).
  void dumpRaw(String path) =>
      File(path).writeAsStringSync('${_frames.map((frame) => jsonEncode(frame.toJson())).join('\n')}\n');

  /// Scrubs the capture and writes it; returns the directory.
  Future<String> write({required String root, required String name, required ProxyRoute route}) async {
    final raw = <int>[for (final frame in _frames) ...frame.bytes];
    final scrubber = FrameScrubber.forPlatform(platform, detail);
    final result = scrubber.scrub(_frames, _handshakes);
    final directory = Directory('$root/fixtures/$platform/danmaku/$name')..createSync(recursive: true);
    final lines = result.frames.map((frame) => jsonEncode(frame.toJson())).join('\n');
    final meta = <String, Object?>{
      'schema': 1,
      'platform': platform,
      'case': name,
      'room': detail.ref.key,
      'danmakuKeys': result.danmakuKeys,
      'capturedAt': _started.toIso8601String(),
      'route': route is DirectRoute ? 'direct' : 'proxy',
      'handshakes': result.handshakes,
      'frames': result.frames.length,
      'raw': {'sha256': sha256.convert(raw).toString(), 'length': raw.length},
      'scrubbed': result.records,
      'tool': 'live_cli danmaku --record (schema 1)',
    };
    final metaText = const JsonEncoder.withIndent('  ').convert(meta);
    final leak = scrubber.findLeak(result.frames, metaText);
    if (leak != null) throw StateError('Refusing to write: a scrubbed value is still present ($leak)');
    File('${directory.path}/frames.jsonl').writeAsStringSync('$lines\n');
    File('${directory.path}/meta.json').writeAsStringSync('$metaText\n');
    return directory.path;
  }
}

final class _RecordingTransport implements DanmakuTransport {
  new(this._inner, this._recorder) : http = _RecordingHttp(_inner.http, _recorder);

  final DanmakuTransport _inner;
  final FrameRecorder _recorder;

  @override
  final LiveHttp http;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    required String site,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _recorder._handshakes.add((url: url, headers: headers));
    return _RecordingSocket(await _inner.connect(url, site: site, headers: headers, timeout: timeout), _recorder);
  }
}

final class _RecordingSocket implements DanmakuSocket {
  new(this._inner, this._recorder);

  final DanmakuSocket _inner;
  final FrameRecorder _recorder;

  @override
  Stream<Object?> get messages => _inner.messages.map((data) {
    switch (data) {
      case final List<int> bytes:
        _recorder._add('in', bytes);
      case final String text:
        _recorder._add('in', utf8.encode(text), text: true);
    }
    return data;
  });

  @override
  void send(List<int> frame) {
    _recorder._add('out', frame, text: frame is TextFrame);
    _inner.send(frame);
  }

  @override
  Future<void> close() => _inner.close();

  @override
  int? get closeCode => _inner.closeCode;
}

final class _RecordingHttp implements LiveHttp {
  new(this._inner, this._recorder);

  final LiveHttp _inner;
  final FrameRecorder _recorder;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final response = await _inner.send(request);
    // Text bodies stay readable; binary ones (Huya's WUP) go in as base64.
    var text = true;
    try {
      utf8.decode(response.bytes);
    } on FormatException {
      text = false;
    }
    _recorder._add('in', response.bytes, text: text, url: request.url);
    return response;
  }

  @override
  void close() => _inner.close();
}
