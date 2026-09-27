import 'dart:io';

import 'package:live_cli/live_cli.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

void main() {
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
}
