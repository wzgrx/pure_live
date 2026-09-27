import 'package:live_cli/live_cli.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

void main() {
  test('counts steps, gaps and regressions of a relayed FLV', () {
    final report = LeaseReport()
      ..add(FlvTag.fileHeader())
      ..add(FlvTag.build(type: FlvTag.script, timestamp: 0, data: [2]))
      ..add(FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x17, 0, 0, 0, 0, 1]));
    for (var ts = 0; ts <= 2000; ts += 40) {
      final frameType = ts % 1000 == 0 ? 0x17 : 0x27;
      report.add(FlvTag.build(type: FlvTag.video, timestamp: ts, data: [frameType, 1, 0, 0, 0]));
    }
    for (var ts = 0; ts <= 2000; ts += 23) {
      report.add(FlvTag.build(type: FlvTag.audio, timestamp: ts, data: [0xAF, 1, 0]));
    }
    expect(report.clean, isTrue);
    expect(report.maxVideoStep, 40);
    expect(report.maxAudioStep, 23);
    expect(report.scripts, 1);
    expect(report.videoSpan, const Duration(seconds: 2));

    report
      ..add(FlvTag.build(type: FlvTag.video, timestamp: 3000, data: [0x17, 1, 0, 0, 0]))
      ..add(FlvTag.build(type: FlvTag.video, timestamp: 2990, data: [0x27, 1, 0, 0, 0]));
    expect(report.clean, isFalse);
    expect(report.gaps.single, (stream: 'video', from: 2000, to: 3000));
    expect(report.videoBackwards, 1);
    expect(report.stepAround(3000), 1000);
  });
}
