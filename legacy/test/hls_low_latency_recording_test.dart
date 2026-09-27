import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_retained_manifest.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';

final source = Uri.parse('https://fixture.invalid/live/index.m3u8');
const control =
    '#EXT-X-PART-INF:PART-TARGET=0.5\n'
    '#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,CAN-SKIP-UNTIL=6,PART-HOLD-BACK=1.5\n';
String live({int first = 0, int count = 1, String parts = '', String suffix = ''}) =>
    '#EXTM3U\n#EXT-X-VERSION:10\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:$first\n'
    '$control#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:${first.toString().padLeft(2, '0')}Z\n'
    '${List.generate(count, (i) => '#EXTINF:1,\ns${first + i}.m4s\n').join()}'
    '$parts$suffix';
HlsMediaSnapshot parse(String text) => HlsMediaSnapshot.parse(text, source);
String render(HlsRetainedWindow w) => renderHlsRetainedManifest(w, localUri: (u) => u);

void main() {
  test('complete parent recording preserves media without publishing upstream LL controls', () {
    final initial = live(
      parts: '#EXT-X-PART:DURATION=0.5,URI="p1.m4s",INDEPENDENT=YES\n',
      suffix:
          '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="future.m4s"\n'
          '#EXT-X-RENDITION-REPORT:URI="other.m3u8",LAST-MSN=1,LAST-PART=0\n',
    );
    final window = HlsRetainedWindow(source)..merge(parse(initial));
    expect(render(window), contains('/s0.m4s'));
    for (final absent in [
      '#EXT-X-PART',
      '#EXT-X-PRELOAD-HINT',
      '#EXT-X-RENDITION-REPORT',
      '#EXT-X-SERVER-CONTROL',
      'future.m4s',
    ]) {
      expect(render(window), isNot(contains(absent)));
    }
    window.merge(parse(live(count: 2)));
    expect(window.segments.map((s) => s.sequence), [0, 1]);
    expect(render(window), contains('/s1.m4s'));
  });
  test('typed capabilities and report defaults remain metadata, not resource selection', () {
    final snapshot = parse(
      live(
        parts: '#EXT-X-PART:DURATION=0.5,URI="p1.m4s"\n',
        suffix:
            '#EXT-X-PRELOAD-HINT:TYPE=MAP,URI="next-init.mp4",BYTERANGE-START=10\n'
            '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="next.mp4",BYTERANGE-START=20,BYTERANGE-LENGTH=4\n'
            '#EXT-X-RENDITION-REPORT:URI="other.m3u8"\n',
      ),
    );
    final ll = snapshot.lowLatency;
    expect(snapshot.unhandledTags, isEmpty);
    expect(ll.partTarget, 0.5);
    expect(ll.control!.canBlockReload, true);
    expect(ll.control!.skipUntil, 6);
    expect(ll.pendingParts.single.media.sequence, 1);
    expect(ll.preloadHints.first.offset, 10);
    expect(ll.preloadHints.first.length, isNull);
    expect(ll.preloadHints.last.length, 4);
    expect(ll.renditionReports.single.lastSequence, 1);
    expect(ll.renditionReports.single.lastPart, 0);
    for (final list in [ll.parts, ll.pendingParts, ll.preloadHints, ll.renditionReports]) {
      expect(() => list.clear(), throwsUnsupportedError);
    }
  });
  test('part byte ranges resolve within a parent only and keep MAP/key context', () {
    final text = live(
      count: 0,
      parts:
          '#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x01\n'
          '#EXT-X-MAP:URI="init.mp4"\n'
          '#EXT-X-PART:DURATION=0.5,URI="bundle.mp4",BYTERANGE="5@10",INDEPENDENT=YES\n'
          '#EXT-X-PART:DURATION=0.5,URI="bundle.mp4",BYTERANGE="6"\n'
          '#EXTINF:1,\nparent.mp4\n',
    );
    final snapshot = parse(text);
    expect(snapshot.lowLatency.parts.map((p) => p.media.range!.identity), ['5@10', '6@15']);
    expect(snapshot.lowLatency.parts.last.media.keys.single.attributes['IV'], '0x01');
    expect(snapshot.lowLatency.pendingParts, isEmpty);
    expect((HlsRetainedWindow(source)..merge(snapshot)).segments, hasLength(1));
    expect(() => parse('$text#EXT-X-PART:DURATION=0.5,URI="bundle.mp4",BYTERANGE="6"\n'), throwsFormatException);
  });
  test('pending prefixes survive omission, grow monotonically and promote exactly once', () {
    const a = '#EXT-X-PART:DURATION=0.5,URI="p1-0.m4s"\n';
    const b = '#EXT-X-PART:DURATION=0.5,URI="p1-1.m4s"\n';
    final w = HlsRetainedWindow(source)..merge(parse(live(parts: a)));
    final held = w.pendingParts;
    w.merge(parse(live()));
    expect(identical(w.pendingParts, held), true);
    w.merge(parse(live(parts: '$a$b')));
    expect(w.pendingParts, hasLength(2));
    final before = render(w);
    final pending = w.pendingParts;
    for (final invalid in [
      live(parts: a),
      live(parts: '$a$b'.replaceAll('p1-0', 'changed')),
      live(first: 2),
      live(parts: '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:02Z\n$a$b'),
    ]) {
      expect(() => w.merge(parse(invalid)), throwsFormatException);
      expect(identical(w.pendingParts, pending), true);
      expect(render(w), before);
    }
    w.merge(parse(live(count: 2)));
    expect(w.pendingParts, isEmpty);
    w.merge(parse(live(first: 1, count: 2)));
    expect(w.segments.map((s) => s.sequence), [0, 1, 2]);
  });
  test('promotion detects old MAP, key, discontinuity and duration conflicts atomically', () {
    const pending = '#EXT-X-PART:DURATION=0.5,URI="p1-0.m4s"\n#EXT-X-PART:DURATION=0.5,URI="p1-1.m4s"\n';
    for (final replacement in [
      '#EXT-X-MAP:URI="new.mp4"\n',
      '#EXT-X-KEY:METHOD=AES-128,URI="new.key"\n',
      '#EXT-X-DISCONTINUITY\n',
    ]) {
      final w = HlsRetainedWindow(source)..merge(parse(live(parts: pending)));
      final before = render(w);
      final changed = '${live()}$replacement#EXTINF:1,\ns1.m4s\n';
      expect(() => w.merge(parse(changed)), throwsFormatException);
      expect(render(w), before);
      expect(w.pendingParts, hasLength(2));
    }
    final w = HlsRetainedWindow(source)..merge(parse(live(parts: pending)));
    expect(() => w.merge(parse('${live()}#EXTINF:0.8,\ns1.m4s\n')), throwsFormatException);
  });
  test('part-only and unfinished terminal snapshots never silently qualify as complete recordings', () {
    const part = '#EXT-X-PART:DURATION=0.5,URI="part.m4s"\n';
    final onlyParts = parse(live(count: 0, parts: part));
    expect(onlyParts.segments, isEmpty);
    expect(() => HlsRetainedWindow(source).merge(onlyParts), throwsFormatException);
    final terminal = parse(live(parts: part, suffix: '#EXT-X-ENDLIST\n'));
    expect(terminal.unhandledTags, contains('#EXT-X-PART:unfinished-terminal'));
    expect(() => HlsRetainedWindow(source).merge(terminal), throwsFormatException);
    final finished = parse(live(suffix: '#EXT-X-ENDLIST\n'));
    expect((HlsRetainedWindow(source)..merge(finished)).ended, true);
  });
  test('pending metadata is charged to the window and preserves prior state on overflow', () {
    final initial = parse(live());
    final base = HlsRetainedWindow(source)..merge(initial);
    final w = HlsRetainedWindow(source, maximumBytes: base.retainedBytes)..merge(initial);
    expect(() => w.merge(parse(live(parts: '#EXT-X-PART:DURATION=0.5,URI="p.m4s"\n'))), throwsFormatException);
    expect(w.pendingParts, isEmpty);
    expect(w.retainedBytes, base.retainedBytes);
    final many = List.generate(257, (i) => '#EXT-X-PART:DURATION=0.001,URI="p$i.m4s"\n').join();
    expect(() => parse(live(parts: many)), throwsFormatException);
    final large = List.generate(32, (i) => '#EXT-X-PART:DURATION=0.001,URI="${'x' * 8000}$i.m4s"\n').join();
    expect(() => parse(live(parts: large)), throwsFormatException);
  });
  test('old completed parents may expose only a suffix of their parts', () {
    final text = live(count: 0, parts: '#EXT-X-PART:DURATION=0.5,URI="last-half.m4s"\n#EXTINF:1,\ns0.m4s\n');
    expect((HlsRetainedWindow(source)..merge(parse(text))).segments, hasLength(1));
  });
  for (final tag in [
    '#EXT-X-PART:DURATION=0.5,URI=unquoted',
    '#EXT-X-PART:DURATION=-1,URI="p"',
    '#EXT-X-PART:DURATION=0.6,URI="p"',
    '#EXT-X-PART:DURATION=0.5,URI="p",GAP=NO',
    '#EXT-X-PART:DURATION=0.5,URI="p",BYTERANGE="10"',
    '#EXT-X-PART:DURATION=0.5,URI="p",FUTURE=1',
    '#EXT-X-PART:DURATION=0.5,URI="p"\n#EXT-X-KEY:METHOD=NONE',
    '#EXT-X-PART:DURATION=0.5,URI="p"\n#EXT-X-MEDIA-SEQUENCE:4',
    '#EXT-X-PART:DURATION=0.1,URI="p"\n#EXT-X-PART:DURATION=0.5,URI="q"',
    '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p",BYTERANGE-LENGTH=0',
    '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p",BYTERANGE-START=9223372036854775807,BYTERANGE-LENGTH=1',
    '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p"\n#EXT-X-PRELOAD-HINT:TYPE=PART,URI="q"',
    '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="p"\n#EXT-X-ENDLIST',
    '#EXT-X-RENDITION-REPORT:URI="other",LAST-MSN=-1',
    '#EXT-X-RENDITION-REPORT:URI="other"\n#EXT-X-RENDITION-REPORT:URI="other"',
    '#EXT-X-SKIP:SKIPPED-SEGMENTS=1',
  ]) {
    test(
      'invalid LL recording metadata: $tag',
      () => expect(() => parse(live(parts: '$tag\n')), throwsFormatException),
    );
  }
  for (final attributes in [
    'CAN-SKIP-UNTIL=5',
    'CAN-SKIP-DATERANGES=YES',
    'HOLD-BACK=2',
    'PART-HOLD-BACK=0.9',
    'CAN-BLOCK-RELOAD=NO',
  ]) {
    test('invalid server capability: $attributes', () {
      final text = live().replaceAll(RegExp(r'#EXT-X-SERVER-CONTROL:[^\n]+'), '#EXT-X-SERVER-CONTROL:$attributes');
      expect(() => parse(text), throwsFormatException);
    });
  }
}
