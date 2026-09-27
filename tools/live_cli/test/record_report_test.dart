import 'dart:io';

import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

void main() {
  test('record url: one live room with one line, its format by the IPTV rule', () async {
    expect(urlFormat(Uri.parse('http://192.168.1.1:4022/udp/239.3.1.1:8000')), StreamFormat.other);
    expect(urlFormat(Uri.parse('https://cdn.test/live/index.M3U8?t=1')), StreamFormat.hls);
    expect(urlFormat(Uri.parse('https://cdn.test/live/a.flv')), StreamFormat.flv);
    final rooms = UrlRecordRooms(Uri.parse('http://127.0.0.1:8090/udp/239.1.1.1:5000'), headers: {'user-agent': 'x'});
    final detail = await rooms.detail(rooms.ref);
    expect(detail.card.state, LiveState.live);
    final line = (await rooms.streams(detail)).lines.single;
    expect((line.format, line.url.port), (StreamFormat.other, 8090));
    expect(line.headers, {'user-agent': 'x'});
  });

  test('stepReport finds the largest step and regressions', () {
    final report = stepReport([0, 0.04, 0.08, 0.2, 0.18, 0.22]);
    expect(report.count, 6);
    expect(report.maxStep, closeTo(0.12, 1e-9));
    expect(report.backwards, 1);
    expect(stepReport(const []).count, 0);
  });

  test('checkFlvFile applies the lease rules to a file', () async {
    final dir = await Directory.systemTemp.createTemp('live_cli_record');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.flv');
    final bytes = <int>[...FlvTag.fileHeader()];
    for (var ts = 0; ts <= 2000; ts += 40) {
      bytes.addAll(
        FlvTag.build(type: FlvTag.video, timestamp: ts, data: [if (ts % 1000 == 0) 0x17 else 0x27, 1, 0, 0, 0]),
      );
    }
    bytes.addAll(FlvTag.build(type: FlvTag.video, timestamp: 3000, data: [0x17, 1, 0, 0, 0]));
    await file.writeAsBytes(bytes);
    final report = await checkFlvFile(file.path);
    expect(report.maxVideoStep, 1000);
    expect(report.gaps, hasLength(1));
  });

  test('topLevelBoxes lists boxes in file order, with 64-bit sizes', () async {
    final dir = await Directory.systemTemp.createTemp('live_cli_remux');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.mp4');
    await file.writeAsBytes([
      ...[0, 0, 0, 16, ...'ftyp'.codeUnits, ...'isom'.codeUnits, 0, 0, 2, 0],
      ...[0, 0, 0, 8, ...'moov'.codeUnits],
      ...[0, 0, 0, 1, ...'mdat'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 20, 1, 2, 3, 4],
    ]);
    final boxes = await topLevelBoxes(file.path);
    expect(boxes.map((box) => (box.type, box.offset, box.size)), [('ftyp', 0, 16), ('moov', 16, 8), ('mdat', 24, 20)]);
  });
}
