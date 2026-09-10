import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/recorder/services/recording_segment_clock.dart';

void main() {
  const prefix = 'attempt-001';
  const good = 'attempt-001_000000.ts,0.000000,12.300000\nattempt-001_000001.ts,12.300000,13.200000\n';
  final paths = [
    for (var i = 0; i < 2; i++)
      p.join(Directory.systemTemp.path, 'clock fixture', '${prefix}_${i.toString().padLeft(6, '0')}.ts'),
  ];
  test('observed journal keeps reference clock and explicit zero inpoints', () {
    final clock = RecordingSegmentClock.parse(good, prefix: prefix, segments: paths);
    expect(clock.starts, [0, 12300000]);
    final manifest = clock.toConcatManifest();
    expect(manifest, startsWith('ffconcat version 1.0\n'));
    expect('inpoint 0'.allMatches(manifest), hasLength(2));
    expect(manifest, contains('duration 12.300000\n'));
    expect('duration '.allMatches(manifest), hasLength(1));
    expect(RecordingSegmentClock.journalName(prefix), 'attempt-001.clock-v1.csv');
    expect(() => clock.starts.add(1), throwsUnsupportedError);
  });
  test('VFR ends are not substituted for the next reference start', () {
    final changed = good.replaceFirst('12.300000', '12.250000');
    expect(
      RecordingSegmentClock.parse(changed, prefix: prefix, segments: paths).toConcatManifest(),
      contains('duration 12.300000\n'),
    );
    final overlap = good.replaceFirst('12.300000', '12.350000');
    expect(
      RecordingSegmentClock.parse(overlap, prefix: prefix, segments: paths).toConcatManifest(),
      contains('duration 12.300000\n'),
    );
  });
  test('single stopped segment needs no fabricated terminal duration', () {
    final clock = RecordingSegmentClock.parse(
      'attempt-001_000000.ts,0,0.04\n',
      prefix: prefix,
      segments: [paths.first],
    );
    expect(clock.toConcatManifest(), isNot(contains('duration ')));
  });
  for (final invalid in [
    '',
    good.trimRight(),
    '$good\n',
    good.replaceAll(prefix, 'other'),
    good.replaceFirst('000000', '000001'),
    good.replaceFirst('attempt-001_000000.ts', '../attempt-001_000000.ts'),
    good.replaceFirst('attempt-001_000000.ts', '"attempt-001_000000.ts"'),
    good.replaceFirst('0.000000', '-1.000000'),
    good.replaceFirst('0.000000', '1.000000'),
    good.replaceFirst('12.300000', '0.000000'),
    good.replaceFirst('13.200000', '12.000000'),
    good.replaceAll('12.300000', 'NaN'),
    good.replaceAll('12.300000', '1e3'),
    good.replaceAll('12.300000', '12.3000001'),
    good.replaceAll('12.300000', '9007199254.740992'),
    good.replaceFirst('000001.ts,12.300000', '000001.ts,0.000000'),
  ]) {
    test('rejects malformed or foreign journal ${invalid.hashCode}', () {
      expect(() => RecordingSegmentClock.parse(invalid, prefix: prefix, segments: paths), throwsFormatException);
    });
  }
  test('different directories, path controls and missing selected files fail closed', () {
    for (final bad in [
      [paths.first],
      paths.reversed.toList(),
      [paths.first, p.join(Directory.systemTemp.path, 'other', p.basename(paths.last))],
      [p.join(Directory.systemTemp.path, 'bad\nroot', p.basename(paths.first)), paths.last],
    ]) {
      expect(() => RecordingSegmentClock.parse(good, prefix: prefix, segments: bad), throwsFormatException);
    }
    expect(() => RecordingSegmentClock.journalName('../attempt'), throwsFormatException);
  });
  test('CRLF and apostrophes are handled without adding manifest directives', () {
    final quoted = paths.map((path) => p.join(p.dirname(path), "anchor's", p.basename(path))).toList();
    final clock = RecordingSegmentClock.parse(good.replaceAll('\n', '\r\n'), prefix: prefix, segments: quoted);
    expect(clock.toConcatManifest(), contains(r"anchor'\''s"));
  });
  test('bounded UTF-8 file read uses the same parser and closes its stream', () async {
    final dir = await Directory.systemTemp.createTemp('clock-journal-');
    try {
      final file = await File(p.join(dir.path, 'clock.csv')).writeAsString(good);
      final clock = await RecordingSegmentClock.read(file, prefix: prefix, segments: paths.map(File.new).toList());
      expect(clock.starts, [0, 12300000]);
      await file.writeAsBytes([255]);
      await expectLater(
        RecordingSegmentClock.read(file, prefix: prefix, segments: paths.map(File.new).toList()),
        throwsFormatException,
      );
      await file.writeAsString(' ' * (RecordingSegmentClock.maxBytes + 1));
      await expectLater(
        RecordingSegmentClock.read(file, prefix: prefix, segments: paths.map(File.new).toList()),
        throwsFormatException,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
