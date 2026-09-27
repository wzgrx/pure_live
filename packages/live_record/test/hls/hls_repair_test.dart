import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';

void main() {
  final layout = SessionLayout.at('/rec', RoomRef('twitch', 'shroud'), 'shroud', DateTime(2026, 9, 28, 10));

  test('scanTs keeps whole packets and drops the last HLS segment a crash may have cut (§14.1)', () async {
    final files = MemoryRecordFiles();
    final segments = [for (var seq = 0; seq < 3; seq++) tsSegment(seq)];
    final whole = Uint8List.fromList([for (final s in segments) ...s]);
    files.put('/a.ts', [...whole, ...tsSegment(3).sublist(0, 500)]);
    final scan = await scanTs(files, '/a.ts');
    expect(scan.validLength, whole.length, reason: 'up to the start of the fourth segment');
    expect(scan.media, greaterThan(0));
    expect(scan.durationMs, 2 * 2000 + 2000 * 60 ~/ 90, reason: 'first to last timestamp kept');
  });

  test('scanTs stops at lost sync; one segment is kept as it is', () async {
    final files = MemoryRecordFiles();
    final one = tsSegment(0);
    files.put('/a.ts', [...one.sublist(0, 188 * 5), 0, 1, 2, ...one.sublist(188 * 5)]);
    expect((await scanTs(files, '/a.ts')).validLength, 188 * 5);
    files.put('/b.ts', one);
    expect((await scanTs(files, '/b.ts')).validLength, one.length);
    files.put('/c.ts', [1, 2, 3]);
    expect((await scanTs(files, '/c.ts')).media, 0);
  });

  test('scanFmp4 keeps the initialisation section and whole fragments only', () async {
    final files = MemoryRecordFiles();
    final whole = [...fmp4Init, ...fmp4Fragments[0]];
    files.put('/a.m4s', [...whole, ...fmp4Fragments[1].sublist(0, 4000)]);
    final scan = await scanFmp4(files, '/a.m4s');
    expect(scan.validLength, whole.length);
    expect(scan.media, 1);
    files.put('/b.m4s', fmp4Init);
    expect((await scanFmp4(files, '/b.m4s')).media, 0, reason: 'no fragment: no media');
    files.put('/c.m4s', [...fmp4Init, ...fmp4Fragments[0], ...fmp4Fragments[1]]);
    final full = await scanFmp4(files, '/c.m4s');
    expect((full.media, full.truncated, full.durationMs), (2, false, 1000));
  });

  test('recoverSession finishes crashed .ts and .m4s files; empty ones go; a crash gap is added', () async {
    final files = MemoryRecordFiles();
    final ts = layout.segment(1, extension: 'ts');
    final m4s = layout.segment(2, extension: 'm4s');
    final empty = layout.segment(3, extension: 'ts');
    files
      ..put('$ts.part', [...tsSegment(0), ...tsSegment(1), ...tsSegment(2).sublist(0, 1000)])
      ..put('$m4s.part', [...fmp4Init, ...fmp4Fragments[0], ...fmp4Fragments[1].sublist(0, 100)])
      ..put('$empty.part', fmp4Init.sublist(0, 10));
    final segments = await recoverSession(files, layout, room: 'twitch:shroud');
    expect(segments, [ts, m4s]);
    expect(files.bytesOf(ts), [...tsSegment(0), ...tsSegment(1)]);
    expect(files.bytesOf(m4s), [...fmp4Init, ...fmp4Fragments[0]]);
    expect(await files.exists(empty), isFalse);
    expect(await files.exists('$empty.part'), isFalse);
    final gaps = (jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>)['gaps']! as List;
    expect((gaps.single as Map)['reason'], 'crash');
    expect((gaps.single as Map)['part'], '${layout.prefix}_002.m4s');
    // The repaired files remux.
    for (final path in segments) {
      final result = await remuxRecording(files: files, input: path, output: '$path.mp4');
      expect(result.videoSamples, greaterThan(0));
    }
  });
}
