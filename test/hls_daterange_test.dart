import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_retained_manifest.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';

final source = Uri.parse('https://media.example/live/index.m3u8');
String media(String ranges, {int first = 0, int count = 3}) =>
    '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$first\n'
    '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:${(first * 2).toString().padLeft(2, '0')}Z\n'
    '$ranges${List.generate(count, (i) => '#EXTINF:2,\ns${first + i}.ts\n').join()}';
String render(HlsRetainedWindow window) => renderHlsRetainedManifest(window, localUri: (uri) => uri);
String event(String id, {String start = '00', String extra = ''}) =>
    '#EXT-X-DATERANGE:ID="$id",START-DATE="2026-09-09T00:00:${start}Z"$extra\n';
HlsMediaSnapshot parse(String ranges, {int first = 0, int count = 3}) =>
    HlsMediaSnapshot.parse(media(ranges, first: first, count: count), source);

void main() {
  test('dated metadata is admitted and preserved in the actual retained publication', () {
    const tag =
        '#EXT-X-DATERANGE:ID="event",START-DATE="2026-09-09T00:00:00Z",'
        'PLANNED-DURATION=2,X-TITLE="one,two",SCTE35-OUT=0xFC12\n';
    final window = HlsRetainedWindow(source);
    window.merge(HlsMediaSnapshot.parse(media(tag), source));
    expect(render(window), contains(tag.trim()));
    window.merge(HlsMediaSnapshot.parse(media('#EXT-X-DATERANGE:ID="event",DURATION=4\n', first: 1), source));
    expect(render(window), contains('DURATION=4'));
    expect(render(window), contains('X-TITLE="one,two"'));
  });
  test('same-snapshot updates consolidate once and round-trip wire attribute types', () {
    final text =
        '${event('a', extra: ',X-N=-1.25,X-B=0xAB,X-S="a,b",CUE="ONCE"')}'
        '#EXT-X-DATERANGE:ID="a",DURATION=2,SCTE35-IN=0xFC00\n';
    final snapshot = parse(text);
    expect(snapshot.unhandledTags, isEmpty);
    expect(snapshot.dateRanges, hasLength(2));
    final window = HlsRetainedWindow(source)..merge(snapshot);
    expect(window.dateRanges, hasLength(1));
    expect(window.dateRanges.single.attributes['X-S'], '"a,b"');
    expect(window.dateRanges.single.attribute('X-S'), 'a,b');
    final roundTrip = HlsRetainedWindow(source)..merge(HlsMediaSnapshot.parse(render(window), source));
    expect(roundTrip.dateRanges.single.attributes, window.dateRanges.single.attributes);
    expect(() => snapshot.dateRanges.clear(), throwsUnsupportedError);
    expect(() => window.dateRanges.clear(), throwsUnsupportedError);
    expect(() => window.dateRanges.single.attributes.clear(), throwsUnsupportedError);
  });
  test('refresh conflicts roll back metadata, segments, version and terminal state together', () {
    final window = HlsRetainedWindow(source)..merge(parse(event('a', extra: ',PLANNED-DURATION=3')));
    final segments = window.segments;
    final ranges = window.dateRanges;
    final before = render(window);
    for (final update in [
      '#EXT-X-DATERANGE:ID="a",PLANNED-DURATION=4\n',
      '#EXT-X-DATERANGE:ID="a",END-DATE="2026-09-08T00:00:00Z"\n',
      '#EXT-X-DATERANGE:ID="a",DURATION=2\n#EXT-X-DATERANGE:ID="a",DURATION=3\n',
      '#EXT-X-DATERANGE:ID="new",DURATION=2\n',
    ]) {
      final incoming = HlsMediaSnapshot.parse('${media(update, first: 1)}#EXT-X-VERSION:12\n#EXT-X-ENDLIST\n', source);
      expect(() => window.merge(incoming), throwsFormatException);
      expect(identical(window.segments, segments), true);
      expect(identical(window.dateRanges, ranges), true);
      expect(render(window), before);
      expect(window.ended, false);
      expect(window.version, 1);
    }
  });
  test('closed metadata survives origin removal until retained media retires', () {
    final window = HlsRetainedWindow(source)..merge(parse(event('a', extra: ',DURATION=4')));
    window.merge(parse('', first: 2));
    expect(window.dateRanges.single.id, 'a');
    window.retireBefore(1);
    expect(window.dateRanges, hasLength(1));
    window.retireBefore(2);
    expect(window.dateRanges, isEmpty);
    final before = render(window);
    final backwards = media('', first: 3).replaceAll('00:00:06Z', '00:00:00Z');
    expect(() => window.merge(HlsMediaSnapshot.parse(backwards, source)), throwsFormatException);
    expect(render(window), before);
  });
  test('planned and unknown ranges remain open; zero duration at first sample is retained', () {
    final window = HlsRetainedWindow(source)
      ..merge(
        parse(
          '${event('planned', extra: ',PLANNED-DURATION=1')}${event('open')}${event('instant', start: '04', extra: ',DURATION=0')}',
        ),
      );
    window.retireBefore(2);
    expect(window.dateRanges.map((r) => r.id), ['planned', 'open', 'instant']);
    window.merge(parse('', first: 3));
    window.retireBefore(3);
    expect(window.dateRanges.map((r) => r.id), ['planned', 'open']);
  });
  test('unknown retained clocks keep events and anchorless publication is rejected', () {
    final text =
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns0.ts\n'
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:04Z\n'
        '${event('a', extra: ',DURATION=1')}#EXTINF:2,\ns1.ts\n';
    final window = HlsRetainedWindow(source)..merge(HlsMediaSnapshot.parse(text, source));
    expect(window.dateRanges, hasLength(1));
    expect(() => renderHlsRetainedManifest(window, localUri: (u) => u, throughSequence: 0), throwsFormatException);
    expect(render(window), contains('ID="a"'));
  });
  test('END-ON-NEXT retains its successor and rejects later insertion or overlap', () {
    final a = event('a', extra: ',CLASS="c",END-ON-NEXT=YES');
    final b = event('b', start: '04', extra: ',CLASS="c",DURATION=2');
    final window = HlsRetainedWindow(source)..merge(parse('$a$b'));
    window.merge(parse('', first: 1));
    expect(window.dateRanges.map((r) => r.id), ['a', 'b']);
    for (final tag in [
      event('middle', start: '02', extra: ',CLASS="c",DURATION=1'),
      event('overlap', start: '05', extra: ',CLASS="c",DURATION=1'),
      event('equal', start: '04', extra: ',CLASS="c",DURATION=0'),
    ]) {
      final before = render(window);
      expect(() => window.merge(parse(tag, first: 1)), throwsFormatException);
      expect(render(window), before);
    }
    window.retireBefore(2);
    expect(window.dateRanges.map((r) => r.id), ['b']);
  });
  test('END-ON-NEXT CLASS may be supplied by an earlier update', () {
    final window = HlsRetainedWindow(source)..merge(parse(event('a', extra: ',CLASS="c"')));
    window.merge(parse('#EXT-X-DATERANGE:ID="a",END-ON-NEXT=YES\n', first: 1));
    expect(window.dateRanges.single.attribute('END-ON-NEXT'), 'YES');
    expect(() => HlsRetainedWindow(source).merge(parse(event('b', extra: ',END-ON-NEXT=YES'))), throwsFormatException);
  });
  test('ordinary classes may overlap; lifecycle cues keep their following metadata', () {
    final overlap = HlsRetainedWindow(source)
      ..merge(
        parse(
          '${event('a', extra: ',CLASS="ordinary",DURATION=6')}${event('b', start: '02', extra: ',CLASS="ordinary",DURATION=6')}',
        ),
      );
    expect(overlap.dateRanges, hasLength(2));
    final cues = HlsRetainedWindow(source)
      ..merge(
        parse(
          '${event('a', extra: ',CLASS="cue",CUE="POST,ONCE",END-ON-NEXT=YES')}'
          '${event('b', start: '02', extra: ',CLASS="cue",END-ON-NEXT=YES')}'
          '${event('c', start: '04', extra: ',CLASS="cue",DURATION=1')}',
          count: 4,
        ),
      );
    cues.retireBefore(3);
    expect(cues.dateRanges.map((r) => r.id), ['a', 'b', 'c']);
  });
  test('nanosecond extent equality does not round contradictory events together', () {
    final valid = event(
      'a',
      start: '00.000000001',
      extra: ',DURATION=0.000000001,END-DATE="2026-09-09T00:00:00.000000002Z"',
    );
    expect((HlsRetainedWindow(source)..merge(parse(valid))).dateRanges, hasLength(1));
    expect(() => parse(valid.replaceAll('000000002Z', '000000003Z')), throwsFormatException);
    final noZone = event(
      'a',
      extra: ',DURATION=0.1,END-DATE="2026-09-09T00:00:00.1"',
    ).replaceAll('00:00:00Z', '00:00:00');
    expect((HlsRetainedWindow(source)..merge(parse(noZone))).dateRanges, hasLength(1));
  });
  test('rounded segment clocks never retire an event ahead of its real media extent', () {
    final text =
        '#EXTM3U\n#EXT-X-TARGETDURATION:1\n'
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:00Z\n'
        '${event('a', extra: ',DURATION=0.0000015')}'
        '${List.generate(3, (i) => '#EXTINF:0.0000006,\ns$i.ts\n').join()}';
    final window = HlsRetainedWindow(source)..merge(HlsMediaSnapshot.parse(text, source));
    window.retireBefore(2);
    expect(window.segments.single.programTime!.microsecond, 2);
    // Actual last-segment start is 1.2 us, before the event ends at 1.5 us.
    expect(window.dateRanges.single.id, 'a');
  });
  test('metadata bytes are charged and overflow is atomic instead of losing open events', () {
    final initial = parse(event('a'));
    final reference = HlsRetainedWindow(source)..merge(initial);
    final window = HlsRetainedWindow(source, maximumBytes: reference.retainedBytes)..merge(initial);
    expect(window.retainedBytes, reference.retainedBytes);
    final before = render(window);
    expect(() => window.merge(parse(event('big', extra: ',X-TEXT="${'x' * 2000}"'), first: 1)), throwsFormatException);
    expect(render(window), before);
    final limited = HlsRetainedWindow(source, maximumSegments: 1)..merge(parse(event('closed', extra: ',DURATION=2')));
    expect(limited.segments.single.sequence, 2);
    expect(limited.dateRanges, isEmpty);
  });
  test('range count, update count and consolidated attribute budgets are bounded', () {
    final initial = parse(event('a'));
    final window = HlsRetainedWindow(source)..merge(initial);
    final before = render(window);
    expect(() => window.merge(parse(List.generate(256, (i) => event('e$i')).join())), throwsFormatException);
    expect(render(window), before);
    expect(() => parse(List.filled(513, event('same')).join()), throwsFormatException);
    expect(() => parse(event('big', extra: ',X-TEXT="${'x' * 16400}"')), throwsFormatException);
    expect(
      () => HlsRetainedWindow(source).merge(
        parse(
          '${event('big', extra: ',X-A="${'a' * 8200}"')}'
          '#EXT-X-DATERANGE:ID="big",X-B="${'b' * 8200}"\n',
        ),
      ),
      throwsFormatException,
    );
    expect(() => parse(event('attrs', extra: List.generate(64, (i) => ',X-$i=1').join())), throwsFormatException);
  });
  test('DATERANGE requires a PDT and is not an invitation to fetch assets', () {
    expect(
      () => HlsMediaSnapshot.parse(
        media(event('a')).replaceAll(RegExp(r'#EXT-X-PROGRAM-DATE-TIME:[^\n]+\n'), ''),
        source,
      ),
      throwsFormatException,
    );
    for (final extra in [
      ',CLASS="com.apple.hls.interstitial"',
      ',X-ASSET-URI="https://asset.invalid/a"',
      ',X-ASSET-LIST="assets.json"',
    ]) {
      final snapshot = parse(event('a', extra: extra));
      expect(snapshot.unhandledTags, contains('#EXT-X-DATERANGE:interstitial'));
      expect(() => HlsRetainedWindow(source).merge(snapshot), throwsFormatException);
    }
    final partial = parse('${event('a')}#EXT-X-PART:DURATION=0.5,URI="part.ts"\n');
    expect(partial.unhandledTags, contains('#EXT-X-PART'));
    expect(() => HlsRetainedWindow(source).merge(partial), throwsFormatException);
  });
  for (final attributes in [
    'START-DATE="2026-09-09T00:00:00Z"',
    'ID=unquoted',
    'ID=""',
    'ID="a",ID="b"',
    'ID="a",',
    'ID="a",START-DATE=2026-09-09T00:00:00Z',
    'ID="a",START-DATE="2026-02-30T00:00:00Z"',
    'ID="a",CLASS=c',
    'ID="a",DURATION=-1',
    'ID="a",DURATION="1"',
    'ID="a",DURATION=1e3',
    'ID="a",DURATION=0.0000000001',
    'ID="a",END-ON-NEXT=NO',
    'ID="a",END-ON-NEXT=YES,DURATION=1',
    'ID="a",CUE="PRE,POST"',
    'ID="a",CUE="ONCE,ONCE"',
    'ID="a",CUE=ONCE',
    'ID="a",SCTE35-IN="0xFF"',
    'ID="a",SCTE35-CMD=0xZZ',
    'ID="a",X-FLAG=YES',
    'ID="a",UNKNOWN=1',
    'ID="a",X-TEXT="bad\u0000text"',
  ]) {
    test('invalid DATERANGE attributes are rejected: ${attributes.replaceAll('\u0000', '<NUL>')}', () {
      expect(() => parse('#EXT-X-DATERANGE:$attributes\n'), throwsFormatException);
    });
  }
}
