// F.3a: joining into MP4 reports its progress from FFmpeg's statistics
// (3.x `VideoProcessorService.mergeProgress`), and the task carries it while
// it runs.
import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  test('progress is output over input bytes, else a plausible media time, below 100 %', () {
    double progress({num time = 0, int seconds = 0, num size = 0, int input = 0}) => RecordMerger.mergeProgress(
      elapsedMilliseconds: time,
      recordedSeconds: seconds,
      outputBytes: size,
      inputBytes: input,
    );

    expect(progress(size: 500, input: 2000), 0.25);
    expect(progress(size: 2000, input: 2000), 0.99, reason: 'only the commit is 100 %');
    expect(
      progress(size: 5000, input: 2000, time: 4000, seconds: 8),
      0.5,
      reason: 'implausible bytes fall back to time',
    );
    expect(progress(time: 60000, seconds: 8), 0, reason: 'a time far past the recording is not a measure');
    expect(progress(), 0);
  });

  test('a join reports rising progress from the statistics and 100 % once committed', () async {
    final directory = Directory.systemTemp.createTempSync('merge_progress');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final index in [0, 1]) {
      File('${directory.path}/${SegmentClock.segmentName('p', index)}').writeAsBytesSync(List.filled(1000, 1));
    }
    File('${directory.path}/${SegmentClock.journalName('p')}').writeAsStringSync(
      '${SegmentClock.segmentName('p', 0)},0.000000,4.000000\n${SegmentClock.segmentName('p', 1)},4.000000,8.000000\n',
    );
    final ffmpeg = FakeFfmpeg()
      ..joinStatistics = const [
        FfmpegStatistics(size: 500),
        FfmpegStatistics(size: 1000),
        FfmpegStatistics(size: 800),
        FfmpegStatistics(time: 6000),
        FfmpegStatistics(size: 1990),
      ];
    final reported = <double>[];
    final result = await RecordMerger(ffmpeg)
        .merge(directory: directory.path, filePrefix: 'p', recordedSeconds: 8, onProgress: reported.add);
    expect(result.ok, isTrue);
    expect(reported, [0.25, 0.5, 0.75, 0.99, 1]);
  });

  test('the task carries the join progress while it runs and drops it afterwards', () async {
    final root = Directory.systemTemp.createTempSync('merge_progress_task');
    final ffmpeg = FakeFfmpeg();
    final recorder = Recorder(
      sites: (id) => id == 'fake' ? FakeSite() : null,
      ffmpeg: ffmpeg,
      storage: RecordStorage(defaultDirectory: () async => root.path, configuredPath: () => ''),
      settings: RecordSettings.new,
      persist: (json) async {},
      startGap: Duration.zero,
    );
    addTearDown(() async {
      await recorder.dispose();
      root.deleteSync(recursive: true);
    });
    final task = (await recorder.addTask(
      LiveRoom(roomId: '1', platform: 'fake', nick: '主播', liveStatus: LiveStatus.live),
    ))!;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (task.status != RecordStatus.running || task.fileSize <= 0) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    ffmpeg.joinStatistics = const [FfmpegStatistics(size: 250), FfmpegStatistics(size: 500)];
    final seen = <double>[];
    final subscription = recorder.changes.listen((_) {
      if (task.mergeProgress case final progress?) seen.add(progress);
    });
    addTearDown(subscription.cancel);
    await recorder.stopTask(task);
    expect(task.status, RecordStatus.stopped);
    expect(seen, containsAllInOrder([0.25, 0.5, 1]));
    expect(seen, orderedEquals([...seen]..sort()), reason: 'progress never goes back');
    expect(task.mergeProgress, isNull);
    expect(recorder.toJson(), isNot(contains('mergeProgress')));
  });
}
