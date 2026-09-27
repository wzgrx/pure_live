import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import 'support/fake_live.dart';

Uint8List _flv(List<Uint8List> packets) => Uint8List.fromList([for (final packet in packets) ...packet]);

void main() {
  const flv = SyntheticFlv();
  final layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', DateTime(2026, 9, 27, 10));

  test('scanFlv stops at the last complete tag', () async {
    final files = MemoryRecordFiles();
    final whole = _flv(flv.connection(0, 2000));
    files.put('/a.flv', [...whole, ...SyntheticFlv.video(2000, key: true).sublist(0, 7)]);
    final scan = await scanFlv(files, '/a.flv');
    expect(scan.validLength, whole.length);
    expect(scan.truncated, isTrue);
    expect(scan.lastTimestamp, 1978);
    files.put('/bad.flv', [1, 2, 3]);
    expect((await scanFlv(files, '/bad.flv')).validLength, 0);
  });

  test('a PreviousTagSize that does not match ends the valid part', () async {
    final files = MemoryRecordFiles();
    final tags = flv.connection(0, 200);
    final broken = Uint8List.fromList(tags.last)..[tags.last.length - 1] ^= 0xff;
    files.put('/a.flv', _flv([...tags.take(tags.length - 1), broken]));
    final scan = await scanFlv(files, '/a.flv');
    expect(scan.validLength, _flv(tags.take(tags.length - 1).toList()).length);
  });

  test('recoverSession finishes a crashed session (§14.1)', () async {
    final files = MemoryRecordFiles();
    final first = layout.segment(1);
    final second = layout.segment(2);
    files
      ..put(first, _flv(flv.connection(0, 3000)))
      ..put('$second.part', [..._flv(flv.connection(0, 1000)), 9, 9, 9])
      ..put('${layout.segment(3)}.part', FlvTagHeader.onlyHeader)
      ..put(
        '${layout.segment(2, extension: 'xml')}.part',
        utf8.encode('$chatXmlHead<d p="1.000,1,25,0,0,0,0,0" user="u">hi</d>\n'),
      )
      ..put('${layout.segment(1, extension: 'mp4')}.partial', [1, 2, 3])
      ..put('/rec/douyu/主播/2026-09-27/other_001.flv.part', [1]);

    final segments = await recoverSession(files, layout, room: 'douyu:9999');

    expect(segments, [first, second]);
    final repaired = FlvFile(files.bytesOf(second)!);
    expect(repaired.trailing, 0, reason: 'partial bytes after the last tag are cut');
    expect(await files.exists('${layout.segment(3)}.part'), isFalse, reason: 'no media: deleted');
    expect(await files.exists(layout.segment(3)), isFalse);
    final xml = utf8.decode(files.bytesOf(layout.segment(2, extension: 'xml'))!);
    expect(xml.trimRight(), endsWith('</i>'));
    expect(await files.exists('${layout.segment(1, extension: 'mp4')}.partial'), isFalse);
    expect(
      await files.exists('/rec/douyu/主播/2026-09-27/other_001.flv.part'),
      isTrue,
      reason: 'other sessions untouched',
    );
    final gaps = jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>;
    final crash = (gaps['gaps']! as List).single as Map<String, Object?>;
    expect(crash['reason'], 'crash');
    expect(crash['missingMs'], isNull);
    expect(crash['part'], endsWith('_002.flv'));
  });

  test('recovery keeps existing gaps and survives a damaged gaps.json', () async {
    final files = MemoryRecordFiles()
      ..put('${layout.segment(1)}.part', _flv(flv.connection(0, 500)))
      ..put(layout.gaps, utf8.encode('{not json'));
    await recoverSession(files, layout, room: 'douyu:9999');
    final gaps = jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>;
    expect(gaps['gaps']! as List, hasLength(1));
  });

  test('IoRecordFiles: exclusive create, truncate, atomic write', () async {
    final dir = await Directory.systemTemp.createTemp('live_record_io');
    addTearDown(() => dir.delete(recursive: true));
    const files = IoRecordFiles();
    final path = '${dir.path}/sub/a.flv.part';
    final sink = await files.create(path);
    await sink.write([1, 2, 3, 4, 5]);
    await sink.flush();
    await sink.close();
    await expectLater(files.create(path), throwsA(isA<RecordFileExists>()));
    await files.truncate(path, 2);
    expect(await files.read(path), [1, 2]);
    await files.writeAtomic('${dir.path}/g.json', [7]);
    expect(await files.read('${dir.path}/g.json'), [7]);
    expect(await files.exists('${dir.path}/g.json.tmp'), isFalse);
    expect(await files.list('${dir.path}/sub'), ['a.flv.part']);
    final reader = await files.open(path);
    expect(await reader.read(1, 5), [2]);
    await reader.close();
  });
}

/// An FLV file with only its header.
abstract final class FlvTagHeader {
  static final onlyHeader = [0x46, 0x4C, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0];
}
