// H01.5 c4–c6: empty segments left by a capture cut off before any data
// (a stop that cancelled FFmpeg, a stream that ended at once) no longer sink
// the join: an empty tail is skipped, an attempt of only empty segments is
// dropped, and an attempt that wrote nothing leaves no folder. An empty
// segment in the middle still fails closed.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('merge_empty'));
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  String path(String name) => '${directory.path}/$name';
  void segment(int index, int bytes) =>
      File(path(SegmentClock.segmentName('p', index))).writeAsBytesSync(List.filled(bytes, 1));
  void journal(List<String> rows) =>
      File(path(SegmentClock.journalName('p'))).writeAsStringSync(rows.map((row) => '$row\n').join());
  List<String> names() => [for (final entity in directory.listSync()) entity.uri.pathSegments.last]..sort();

  test('an empty last segment is skipped and the attempt joins', () async {
    segment(0, 1000);
    segment(1, 0);
    journal(['p_000000.clock-v1.ts,0.000000,4.000000']);
    final ffmpeg = FakeFfmpeg();
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p');
    expect(result.failure, isNull);
    expect(result.outputPath, endsWith('p.mp4'));
    expect(ffmpeg.joinManifests.single, contains('p_000000.clock-v1.ts'));
    expect(ffmpeg.joinManifests.single, isNot(contains('p_000001')));
    expect(names(), ['p.mp4']);
  });

  test('a journal row of the empty tail goes with it', () async {
    segment(0, 1000);
    segment(1, 0);
    journal(['p_000000.clock-v1.ts,0.000000,4.000000', 'p_000001.clock-v1.ts,4.000000,4.040000']);
    final ffmpeg = FakeFfmpeg();
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p');
    expect(result.ok, isTrue);
    expect(ffmpeg.joinManifests.single, isNot(contains('p_000001')));
    expect(names(), ['p.mp4']);
  });

  test('an empty segment in the middle still fails closed', () async {
    segment(0, 1000);
    segment(1, 0);
    segment(2, 1000);
    journal([
      'p_000000.clock-v1.ts,0.000000,4.000000',
      'p_000001.clock-v1.ts,4.000000,8.000000',
      'p_000002.clock-v1.ts,8.000000,12.000000',
    ]);
    final result = await RecordMerger(FakeFfmpeg()).merge(directory: directory.path, filePrefix: 'p');
    expect(result.failure, MergeFailure.segmentClock);
    expect(names(), ['p.clock-v1.csv', 'p_000000.clock-v1.ts', 'p_000001.clock-v1.ts', 'p_000002.clock-v1.ts']);
  });

  test('a journal row that is not the empty tail still fails closed', () async {
    segment(0, 1000);
    segment(1, 0);
    journal(['p_000000.clock-v1.ts,0.000000,4.000000', 'p_000002.clock-v1.ts,4.000000,8.000000']);
    final result = await RecordMerger(FakeFfmpeg()).merge(directory: directory.path, filePrefix: 'p');
    expect(result.failure, MergeFailure.segmentClock);
    expect(names(), hasLength(3));
  });

  test('an attempt of only empty segments is empty, not a failure', () async {
    segment(0, 0);
    final ffmpeg = FakeFfmpeg();
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p');
    expect(result.failure, MergeFailure.empty);
    expect(ffmpeg.runs, isEmpty);
  });

  test('discarding an empty attempt removes only its own empty files', () {
    segment(0, 0);
    journal([]);
    File(path('other_000000.clock-v1.ts')).writeAsBytesSync(const []);
    File(path('p.xml')).writeAsStringSync('<i/>');
    discardEmptyAttempt(directory.path, 'p');
    expect(names(), ['other_000000.clock-v1.ts', 'p.xml']);
    File(path('other_000000.clock-v1.ts')).deleteSync();
    File(path('p.xml')).deleteSync();
    segment(0, 0);
    journal(['p_000000.clock-v1.ts,0.000000,0.000000']);
    discardEmptyAttempt(directory.path, 'p');
    expect(directory.existsSync(), isFalse);
  });

  group('recorder', () {
    late FakeSite site;
    late FakeFfmpeg ffmpeg;
    late Recorder recorder;
    var settings = RecordSettings();

    setUp(() {
      site = FakeSite();
      ffmpeg = FakeFfmpeg();
      settings = RecordSettings();
      recorder = Recorder(
        sites: (id) => id == 'fake' ? site : null,
        ffmpeg: ffmpeg,
        storage: RecordStorage(defaultDirectory: () async => directory.path, configuredPath: () => ''),
        settings: () => settings,
        outputSampleInterval: const Duration(milliseconds: 20),
        startGap: Duration.zero,
      );
    });

    tearDown(() => recorder.dispose());

    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('restore drops a pending attempt that holds only empty segments', () async {
      final attempt = Directory('${directory.path}/fake/a/2026-10-01/10-00-00')..createSync(recursive: true);
      const prefix = '20261001_100000_000';
      File('${attempt.path}/${prefix}_000000.clock-v1.ts').writeAsBytesSync(const []);
      File('${attempt.path}/$prefix.clock-v1.csv').writeAsStringSync('');
      final stored = RecordTask(
        taskId: 'fake_1',
        roomId: '1',
        platform: 'fake',
        title: '',
        nick: 'a',
        avatar: '',
        cover: '',
        createTime: DateTime(2026, 10, 1, 10),
        status: RecordStatus.running,
        outputDir: attempt.path,
        pendingAttempts: [PendingRecordingAttempt(directoryPath: attempt.path, filePrefix: prefix)],
      );
      await recorder.restore(jsonEncode([stored.toJson()]));
      final task = recorder.tasks.single;
      expect(task.status, RecordStatus.stopped);
      expect(task.pendingAttempts, isEmpty);
      expect(task.lastError, isNull);
      expect(attempt.existsSync(), isFalse);
    });

    test('an attempt that wrote nothing leaves no folder', () async {
      settings = RecordSettings(autoReconnect: false);
      ffmpeg
        ..captureBytes = 0
        ..captureExit = 0;
      final task = (await recorder.addTask(
        LiveRoom(roomId: '1', platform: 'fake', nick: '主播', liveStatus: LiveStatus.live),
      ))!;
      await until(() => task.outputDir != null && task.status.isFinished);
      expect(task.pendingAttempts, isEmpty);
      expect(Directory(task.outputDir!).existsSync(), isFalse);
      expect(Directory(task.outputDir!).parent.existsSync(), isTrue);
    });
  });
}
