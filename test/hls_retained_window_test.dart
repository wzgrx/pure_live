import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';

final source = Uri.parse('https://media.example/live/index.m3u8');
String playlist(int first, int count, {String context = '', bool end = false}) =>
    '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$first\n$context'
    '${List.generate(count, (i) => '#EXTINF:2,segment ${first + i}\ns${first + i}.m4s\n').join()}'
    '${end ? '#EXT-X-ENDLIST\n' : ''}';
HlsMediaSnapshot snapshot(int first, int count, {String context = '', bool end = false}) =>
    HlsMediaSnapshot.parse(playlist(first, count, context: context, end: end), source);

void main() {
  test('sliding snapshots retain a contiguous historical window and report eviction', () {
    final window = HlsRetainedWindow(source, maximumSegments: 4);
    expect(window.merge(snapshot(100, 3)), isEmpty);
    expect(window.merge(snapshot(101, 3)), isEmpty);
    expect(window.segments.map((s) => s.sequence), [100, 101, 102, 103]);
    final evicted = window.merge(snapshot(102, 3));
    expect(evicted.map((s) => s.sequence), [100]);
    expect(window.segments.map((s) => s.sequence), [101, 102, 103, 104]);
    expect(window.segments.first.uri.toString(), 'https://media.example/live/s101.m4s');
    expect(() => window.segments.clear(), throwsUnsupportedError);
    expect(() => evicted.clear(), throwsUnsupportedError);
  });
  test('metadata byte budget is independent from segment count and atomic on oversized input', () {
    final first = snapshot(0, 2);
    final budget = first.segments.last.retainedBytes;
    final window = HlsRetainedWindow(source, maximumBytes: budget);
    expect(window.merge(first).map((s) => s.sequence), [0]);
    expect(window.retainedBytes, lessThanOrEqualTo(budget));
    final before = window.segments;
    final long = playlist(2, 1).replaceAll('s2.m4s', '${'x' * 1000}.m4s');
    expect(() => window.merge(HlsMediaSnapshot.parse(long, source)), throwsFormatException);
    expect(identical(before, window.segments), true);
  });
  test('refresh gaps, stale extents, conflicts and other sources leave prior state intact', () {
    final window = HlsRetainedWindow(source)..merge(snapshot(10, 3));
    final before = window.segments;
    for (final invalid in [
      snapshot(14, 2),
      snapshot(9, 3),
      snapshot(10, 2, end: true),
      HlsMediaSnapshot.parse(playlist(11, 3).replaceAll('s11.m4s', 'other.m4s'), source),
      HlsMediaSnapshot.parse(playlist(11, 3), Uri.parse('https://media.example/audio.m3u8')),
      HlsMediaSnapshot.parse(playlist(11, 3).replaceAll('TARGETDURATION:2', 'TARGETDURATION:3'), source),
    ]) {
      expect(() => window.merge(invalid), throwsFormatException);
      expect(identical(window.segments, before), true);
      expect(window.ended, false);
    }
  });
  test('endlist is terminal and duplicate terminal refresh is idempotent', () {
    final window = HlsRetainedWindow(source)..merge(snapshot(0, 3));
    window.merge(snapshot(1, 3, end: true));
    expect(window.ended, true);
    expect(window.merge(snapshot(1, 3, end: true)), isEmpty);
    expect(() => window.merge(snapshot(1, 3)), throwsFormatException);
    expect(() => window.merge(snapshot(2, 3, end: true)), throwsFormatException);
  });
  test('implicit byte ranges resolve to absolute offsets before prefix eviction', () {
    const text =
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
        '#EXTINF:2,\n#EXT-X-BYTERANGE:10@100\nall.mp4\n'
        '#EXTINF:2,\n#EXT-X-BYTERANGE:20\nall.mp4\n';
    final parsed = HlsMediaSnapshot.parse(text, source);
    expect(parsed.segments.last.range!.requestHeader, 'bytes=110-129');
    final window = HlsRetainedWindow(source, maximumSegments: 1)..merge(parsed);
    expect(window.segments.single.range!.identity, '20@110');
  });
  test('initialization key ownership survives media rotation and NONE', () {
    final parsed = HlsMediaSnapshot.parse(
      [
        playlist(
          0,
          1,
          context:
              '#EXT-X-KEY:METHOD=AES-128,URI="key,a",IV=0x01\n'
              '#EXT-X-MAP:URI="init.mp4",BYTERANGE="8@16"\n'
              '#EXT-X-KEY:METHOD=AES-128,URI="key,b",IV=0x02\n',
        ),
        '#EXT-X-KEY:METHOD=NONE\n#EXTINF:2,\ns1.m4s\n',
      ].join(),
      source,
    );
    final first = parsed.segments.first;
    expect(first.initialization!.range!.requestHeader, 'bytes=16-23');
    expect(first.initialization!.keys.single.uri!.path, '/live/key,a');
    expect(first.keys.single.uri!.path, '/live/key,b');
    expect(parsed.segments.last.keys, isEmpty);
    expect(parsed.segments.last.initialization!.keys.single.attributes['IV'], '0x01');
    expect(() => first.keys.clear(), throwsUnsupportedError);
    expect(() => first.keys.single.attributes.clear(), throwsUnsupportedError);
  });
  test('multiple key formats and reordered equivalent attributes keep identity', () {
    const a = '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k1",KEYFORMAT="one"\n';
    const b = '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k2",KEYFORMAT="two"\n';
    final window = HlsRetainedWindow(source)..merge(snapshot(0, 2, context: '$a$b'));
    final reordered = snapshot(
      0,
      2,
      context: '$b#EXT-X-KEY:URI="https://media.example/live/k1",KEYFORMAT="one",METHOD=SAMPLE-AES\n',
    );
    expect(window.merge(reordered), isEmpty);
    expect(window.segments.first.keys.length, 2);
  });
  test('discontinuity and PDT carry no invented wall time across a discontinuity', () {
    final parsed = HlsMediaSnapshot.parse(
      [
        playlist(
          30,
          2,
          context:
              '#EXT-X-DISCONTINUITY-SEQUENCE:8\n'
              '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T18:00:00+08:00\n',
        ),
        '#EXT-X-DISCONTINUITY\n#EXTINF:2,\ns32.m4s\n'
            '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:20Z\n#EXTINF:2,\ns33.m4s\n',
      ].join(),
      source,
    );
    expect(parsed.segments.map((s) => s.discontinuity), [8, 8, 9, 9]);
    expect(parsed.segments[1].programTime, DateTime.utc(2026, 9, 9, 10, 0, 2));
    expect(parsed.segments[1].explicitProgramTime, false);
    expect(parsed.segments[2].programTime, isNull);
    expect(parsed.segments.last.programTime, DateTime.utc(2026, 9, 9, 10, 0, 20));
    final shifted = HlsMediaSnapshot.parse(
      playlist(31, 1, context: '#EXT-X-DISCONTINUITY-SEQUENCE:8\n#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:30Z\n'),
      source,
    );
    final window = HlsRetainedWindow(source)..merge(parsed);
    expect(() => window.merge(shifted), throwsFormatException);
  });
  test('an explicit PDT before a discontinuity still anchors the upcoming segment', () {
    final parsed = snapshot(0, 1, context: '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:00Z\n#EXT-X-DISCONTINUITY\n');
    expect(parsed.segments.single.programTime, DateTime.utc(2026, 9, 9, 10));
    expect(parsed.segments.single.explicitProgramTime, true);
    expect(parsed.segments.single.discontinuity, 1);
  });
  test('empty endlist and target duration remain terminal across empty refreshes', () {
    final window = HlsRetainedWindow(source)..merge(snapshot(0, 0, end: true));
    expect(() => window.merge(snapshot(0, 0)), throwsFormatException);
    expect(window.ended, true);
    expect(
      () => window.merge(
        HlsMediaSnapshot.parse(playlist(0, 0, end: true).replaceAll('TARGETDURATION:2', 'TARGETDURATION:3'), source),
      ),
      throwsFormatException,
    );
  });
  test('PDT-only conflict at identical sequence extent is atomic', () {
    final window = HlsRetainedWindow(source)
      ..merge(snapshot(0, 2, context: '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:00Z\n'));
    final before = window.segments;
    expect(
      () => window.merge(snapshot(0, 2, context: '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:01Z\n')),
      throwsFormatException,
    );
    expect(identical(before, window.segments), true);
  });
  test('gap is explicit and incomplete draft tags never silently qualify for retention', () {
    final gap = snapshot(0, 1, context: '#EXT-X-GAP\n');
    expect(gap.segments.single.gap, true);
    final draft = snapshot(0, 1, context: '#EXT-X-PART:DURATION=0.5,URI="partial.m4s"\n');
    expect(draft.unhandledTags, {'#EXT-X-PART'});
    expect(() => HlsRetainedWindow(source).merge(draft), throwsFormatException);
    expect(() => draft.unhandledTags.clear(), throwsUnsupportedError);
  });
  for (final entry in <String, String>{
    'orphan URI': '#EXT-X-TARGETDURATION:2\ns.m4s\n',
    'dangling duration': '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n',
    'zero duration': '#EXT-X-TARGETDURATION:2\n#EXTINF:0,\ns.m4s\n',
    'normalized invalid date': '#EXT-X-TARGETDURATION:2\n#EXT-X-PROGRAM-DATE-TIME:2026-02-30T10:00:00Z\n',
    'invalid timezone': '#EXT-X-TARGETDURATION:2\n#EXT-X-PROGRAM-DATE-TIME:2026-09-09T10:00:00+24:00\n',
    'exponent duration': '#EXT-X-TARGETDURATION:2\n#EXTINF:1e0,\ns.m4s\n',
    'duration exceeds target': '#EXT-X-TARGETDURATION:2\n#EXTINF:3,\ns.m4s\n',
    'nan duration': '#EXT-X-TARGETDURATION:2\n#EXTINF:NaN,\ns.m4s\n',
    'master': '#EXT-X-STREAM-INF:BANDWIDTH=1\na.m3u8\n',
    'delta': '#EXT-X-TARGETDURATION:2\n#EXT-X-SKIP:SKIPPED-SEGMENTS=3\n#EXTINF:2,\ns.m4s\n',
    'late sequence': '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.m4s\n#EXT-X-MEDIA-SEQUENCE:10\n',
    'duplicate sequence': '#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-MEDIA-SEQUENCE:2\n',
    'implicit range without base': '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:10\ns.m4s\n',
    'implicit range changed URI':
        '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:10@0\na.mp4\n#EXTINF:2,\n#EXT-X-BYTERANGE:10\nb.mp4\n',
    'overflow range': '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:10@9223372036854775807\ns.m4s\n',
    'negative sequence': '#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:-1\n',
    'overflow sequence': '#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:9223372036854775808\n',
    'duplicate attributes': '#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="a",URI="b"\n',
    'broken attributes': '#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="a,b\n',
    'none with attributes': '#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=NONE,URI="key"\n',
    'encrypted map without IV': '#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-MAP:URI="map"\n',
    'time without zone': '#EXT-X-TARGETDURATION:2\n#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:00\n',
    'media after end': '#EXT-X-TARGETDURATION:2\n#EXT-X-ENDLIST\n#EXTINF:2,\ns.m4s\n',
    'unsupported URI': '#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nfile:///private/s.m4s\n',
  }.entries) {
    test('invalid snapshot: ${entry.key}', () {
      expect(() => HlsMediaSnapshot.parse('#EXTM3U\n${entry.value}', source), throwsFormatException);
    });
  }
  test('per-segment dependency budget rejects repeated large key state before expansion', () {
    final key = 'k' * (64 * 1024);
    expect(() => snapshot(0, 2, context: '#EXT-X-KEY:METHOD=AES-128,URI="$key"\n'), throwsFormatException);
  });
  test('parser and window allocation limits are checked', () {
    expect(() => HlsMediaSnapshot.parse(playlist(0, 3), source, maximumSegments: 2), throwsFormatException);
    expect(() => HlsMediaSnapshot.parse('#EXTM3U\n${'x' * (4 * 1024 * 1024)}', source), throwsFormatException);
    expect(() => HlsMediaSnapshot.parse(playlist(0, 1), source, maximumSegments: 0), throwsArgumentError);
    expect(() => HlsRetainedWindow(source, maximumSegments: 0), throwsArgumentError);
    expect(() => HlsRetainedWindow(source, maximumBytes: 0), throwsArgumentError);
  });
}
