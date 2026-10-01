import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

/// A live HLS CDN in memory: a window of three 2-second segments that
/// slides on [advance]; a segment that left the window is gone (404), as on
/// real CDNs. Segments carry low-latency parts, a key, a date range.
final class _LiveCdn implements HlsUpstream {
  int first = 0;
  final requests = <String>[];

  static Uint8List body(int sequence) => Uint8List.fromList(List.filled(1000, sequence & 0xff));

  void advance([int count = 1]) => first += count;

  String playlist() {
    final out = StringBuffer(
      '#EXTM3U\n#EXT-X-VERSION:9\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$first\n'
      '#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0\n#EXT-X-PART-INF:PART-TARGET=0.5\n'
      '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n',
    );
    for (var sequence = first; sequence < first + 3; sequence++) {
      if (sequence == 4) out.writeln('#EXT-X-DATERANGE:ID="ad",START-DATE="2026-10-01T20:00:00Z"');
      out
        ..writeln('#EXT-X-PART:DURATION=0.5,URI="part$sequence.0.ts"')
        ..writeln('#EXTINF:2.000,')
        ..writeln('seg$sequence.ts');
    }
    out.writeln('#EXT-X-PRELOAD-HINT:TYPE=PART,URI="part${first + 3}.0.ts"');
    return out.toString();
  }

  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) async {
    final name = url.pathSegments.last;
    requests.add(name);
    if (name == 'media.m3u8') return _answer(url, utf8.encode(playlist()));
    final match = RegExp(r'^seg(\d+)\.ts$').firstMatch(name);
    final sequence = match == null ? null : int.parse(match.group(1)!);
    if (sequence != null && sequence >= first && sequence < first + 3) return _answer(url, body(sequence));
    return HlsUpstreamResponse(status: 404, url: url, body: const Stream.empty());
  }

  HlsUpstreamResponse _answer(Uri url, List<int> bytes) =>
      HlsUpstreamResponse(status: 200, url: url, body: Stream.value(bytes), contentLength: bytes.length);

  @override
  void close() {}
}

Future<({int status, Uint8List body})> _get(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    final builder = BytesBuilder();
    await response.forEach(builder.add);
    return (status: response.statusCode, body: builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

List<Uri> _segments(String playlist) => [
  for (final line in const LineSplitter().convert(playlist))
    if (line.startsWith('http')) Uri.parse(line),
];

void main() {
  test('a slow reader still gets segments that left the live window (prefetched, retained)', () async {
    final cdn = _LiveCdn();
    final relay = await LoopbackRelay.start(hlsUpstream: (_) => cdn, hlsPrefetch: const HlsPrefetchOptions());
    addTearDown(relay.close);
    final input = relay.openHls(
      const LivePlayLine('https://cdn.example/live/media.m3u8', format: StreamFormat.hls),
      site: 'chzzk',
    );

    // FFmpeg opens the playlist and starts at a segment.
    var playlist = utf8.decode((await _get(input.uri)).body);
    expect(playlist, isNot(contains('EXT-X-PART')), reason: 'low-latency parts are left out');
    expect(playlist, contains('#EXT-X-KEY:METHOD=AES-128,URI="'));
    var segments = _segments(playlist);
    expect(segments, hasLength(3));
    expect((await _get(segments.first)).body.first, 0);

    // It reloads after the CDN moved on: from now on the relay prefetches.
    cdn.advance();
    playlist = utf8.decode((await _get(input.uri)).body);
    for (var i = 0; i < 500 && !cdn.requests.toSet().containsAll(['seg1.ts', 'seg2.ts', 'seg3.ts']); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(cdn.requests, containsAll(['seg1.ts', 'seg2.ts', 'seg3.ts']));

    // The reader stalls while the CDN moves on: segments 1..3 are gone
    // upstream, yet the relay still lists and serves them.
    cdn.advance(3);
    playlist = utf8.decode((await _get(input.uri)).body);
    expect(playlist, contains('#EXT-X-MEDIA-SEQUENCE:0'), reason: 'from the segment before the next one needed');
    expect(playlist, contains('#EXT-X-DATERANGE:ID="ad"'), reason: 'a date range stays with its segment');
    segments = _segments(playlist);
    expect(segments, hasLength(7));
    for (final (index, url) in segments.skip(1).take(3).indexed) {
      final answer = await _get(url);
      expect(answer.status, 200);
      expect(answer.body.first, index + 1);
    }
    expect(input.isClosed, isFalse);
  });

  test('without prefetch options the relay serves on demand as before', () async {
    final cdn = _LiveCdn();
    final relay = await LoopbackRelay.start(hlsUpstream: (_) => cdn);
    addTearDown(relay.close);
    final input = relay.openHls(
      const LivePlayLine('https://cdn.example/live/media.m3u8', format: StreamFormat.hls),
      site: 'chzzk',
    );
    final playlist = utf8.decode((await _get(input.uri)).body);
    expect(playlist, contains('EXT-X-PART'));
    cdn.advance(3);
    expect((await _get(_segments(playlist).first)).status, 404);
  });
}
