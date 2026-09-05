import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/recording_output_metrics.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _EventManager native;
  late _Metrics metrics;
  late RecorderController recorder;
  late LiveRecordTask task;

  setUp(() async {
    Get.testMode = true;
    root = await Directory.systemTemp.createTemp('pure-live-output-lifecycle-');
    Hive.init(root.path);
    await HivePrefUtil.init();
    native = _EventManager();
    metrics = _Metrics();
    recorder = RecorderController.forTesting(
      settings: _Settings(),
      ffmpeg: native,
      scheduler: FFmpegScheduler.forTesting(),
      outputMetrics: metrics,
      outputSampleInterval: const Duration(milliseconds: 25),
    );
    Get.put(recorder);
    task = LiveRecordTask(
      taskId: 'huya_fixture',
      roomId: 'fixture',
      platform: 'huya',
      title: 'fixture',
      nick: 'fixture',
      avatar: '',
      cover: '',
      createTime: DateTime(2026, 9, 5),
      autoReconnect: false,
      outputDir: '${root.path}${Platform.pathSeparator}recording',
    );
    recorder.tasks.add(task);
  });

  tearDown(() async {
    Get.delete<RecorderController>(force: true);
    for (final tracker in metrics.trackers) {
      tracker.releaseAll();
    }
    final measurement = metrics.measurement;
    if (measurement != null && !measurement.isCompleted) measurement.complete(RecordingOutputSnapshot.empty);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await native.events.close();
    Get.reset();
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(predicate(), isTrue, reason: 'fixture did not reach the requested async boundary');
  }

  void emit(FFmpegEventType type, int session, [Map<String, dynamic> data = const {}]) {
    native.events.add(FFmpegEvent(taskId: task.taskId, type: type, data: {'sessionId': session, ...data}));
  }

  test('late old-session sampling cannot release the new session sampling lock', () async {
    final old = metrics.add()..holdNext();
    final current = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => old.calls == 1);
    emit(FFmpegEventType.startAck, 2);
    await until(() => current.calls == 1);
    old.releaseAll(bytes: 100);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(current.maximumActive, 1, reason: 'old completion must not enable overlapping tracker.sample calls');
    expect(task.fileSize, 0, reason: 'old bytes must not enter the new attempt');
  });

  test('output completing after service close cannot mutate its task', () async {
    final tracker = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    Get.delete<RecorderController>(force: true);
    final status = task.status;
    tracker.releaseAll(bytes: 100);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(task.fileSize, 0);
    expect(task.status, status);
  });

  test('a delayed terminal sample cannot stop the new session or overwrite its status', () async {
    final old = metrics.add();
    final current = metrics.add()..defaultBytes = 20;
    emit(FFmpegEventType.startAck, 1);
    await until(() => old.calls >= 1 && old.active == 0);
    old.holdNext();
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    await until(() => old.active == 1);
    emit(FFmpegEventType.startAck, 2);
    await until(() => current.calls >= 1 && task.fileSize == 20);
    old.releaseAll(bytes: 100);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    emit(FFmpegEventType.progress, 2, {'time': 1000, 'size': 333});
    await until(() => task.lastUpdate != null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(task.status, RecordStatus.running);
    expect(task.fileSize, 333, reason: 'new native progress must still own this task');
  });

  test('terminal handling waits for an active sample and takes a final fresh snapshot', () async {
    final tracker = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(task.status, isNot(RecordStatus.stopped), reason: 'a busy monitor is not a completed final sample');
    tracker.defaultBytes = 150;
    tracker.releaseAll(bytes: 100);
    await until(() => task.status == RecordStatus.stopped);
    expect(task.fileSize, 150, reason: 'the final snapshot must include the last bytes written by native shutdown');
    expect(tracker.maximumActive, 1);
  });

  test('duplicate terminal callbacks share one final snapshot and finalization', () async {
    final tracker = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    tracker.defaultBytes = 150;
    tracker.releaseAll(bytes: 100);
    await until(() => task.status == RecordStatus.stopped);
    expect(task.fileSize, 150);
    expect(tracker.calls, 2);
    expect(tracker.maximumActive, 1);
  });

  test('a failed read releases sampling ownership and later output is visible', () async {
    final tracker = metrics.add()
      ..failNext = true
      ..defaultBytes = 100;
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls >= 2 && task.fileSize == 100);
    expect(tracker.maximumActive, 1);
    expect(task.status, RecordStatus.running);
  });

  test('a blocked recording sample does not block another task', () async {
    final blocked = metrics.add()..holdNext();
    metrics.add().defaultBytes = 100;
    final second = LiveRecordTask.fromJson({...task.toJson(), 'taskId': 'second_fixture'});
    recorder.tasks.add(second);
    emit(FFmpegEventType.startAck, 1);
    await until(() => blocked.active == 1);
    native.events.add(FFmpegEvent(taskId: second.taskId, type: FFmpegEventType.startAck, data: {'sessionId': 2}));
    await until(() => second.fileSize == 100);
    expect(task.fileSize, 0);
    expect(blocked.active, 1);
  });

  test('native statistics from a different session do not contaminate the output owner', () async {
    metrics.add().defaultBytes = 100;
    native.counters = _Counters(2);
    emit(FFmpegEventType.startAck, 1);
    await until(() => task.fileSize > 0);
    expect(task.fileSize, 100);
    expect(task.recordedSeconds, 0);
  });

  test('a removed task cannot receive delayed output even when its ID is reused', () async {
    final tracker = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    final replacement = LiveRecordTask.fromJson(task.toJson());
    recorder.tasks.assignAll([replacement]);
    tracker.releaseAll(bytes: 100);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(task.fileSize, 0);
    expect(replacement.fileSize, 0);
  });

  test('an in-flight terminal snapshot is invalidated when the controller closes', () async {
    final tracker = metrics.add()..holdNext();
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    Get.delete<RecorderController>(force: true);
    final status = task.status;
    tracker.releaseAll(bytes: 100);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(task.status, status);
    expect(task.fileSize, 0);
  });

  test('service close drains the native runner and releases its scheduler and directory leases', () async {
    final cache = Get.put(CacheService(defaultDirectoryResolver: () async => root));
    Get.put<StreamResolverService>(_Resolver());
    metrics.add();
    native.execution = Completer<void>();
    expect(await recorder.startTask(task), isTrue);
    await until(() => native.running);
    emit(FFmpegEventType.startAck, 1);
    final directory = task.outputDir!;
    expect(cache.isDirectoryProtected(directory), isTrue);
    Get.delete<RecorderController>(force: true);
    await until(() => native.stops == 1);
    expect(recorder.scheduler.runningCount, 1, reason: 'cancellation is not native completion');
    expect(cache.isDirectoryProtected(directory), isTrue);
    // The event subscription is now closed. Native termination alone must
    // drain the runner, without depending on an undeliverable terminal event.
    native.execution!.complete();
    await until(() => !native.running);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(recorder.scheduler.runningCount, 0);
    expect(cache.isDirectoryProtected(directory), isFalse);
  });

  test('service close keeps the directory and scheduler owned until an existing finalizer drains', () async {
    final cache = Get.put(CacheService(defaultDirectoryResolver: () async => root));
    Get.put<StreamResolverService>(_Resolver());
    metrics.add();
    metrics.measurement = Completer<RecordingOutputSnapshot>();
    native.execution = Completer<void>();
    await recorder.startTask(task);
    await until(() => native.running);
    emit(FFmpegEventType.startAck, 1);
    final directory = task.outputDir!;
    final segment = File('$directory${Platform.pathSeparator}${task.recordingFilePrefix}_000000.ts');
    await segment.writeAsBytes([1, 2, 3]);
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    native.execution!.complete();
    await until(() => metrics.measurementCalls == 1);
    expect(native.running, isFalse);
    Get.delete<RecorderController>(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(recorder.scheduler.runningCount, 1);
    expect(cache.isDirectoryProtected(directory), isTrue);
    metrics.measurement!.complete(RecordingOutputSnapshot.empty);
    await until(() => recorder.scheduler.runningCount == 0);
    expect(cache.isDirectoryProtected(directory), isFalse);
    expect(await segment.exists(), isTrue, reason: 'shutdown preserves unfinished TS output for next startup');
    expect(task.pendingAttempts, hasLength(1));
  });

  test('manual stop waits for terminal sampling even when the native writer has already ended', () async {
    final cache = Get.put(CacheService(defaultDirectoryResolver: () async => root));
    Get.put<StreamResolverService>(_Resolver());
    final tracker = metrics.add()..holdNext();
    native.execution = Completer<void>();
    await recorder.startTask(task);
    await until(() => native.running);
    emit(FFmpegEventType.startAck, 1);
    await until(() => tracker.calls == 1);
    final directory = task.outputDir!;
    emit(FFmpegEventType.complete, 1, {'manualStop': true});
    native.execution!.complete();
    await until(() => !native.running);
    var stopped = false;
    final stop = recorder.stopTask(task).then((_) => stopped = true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(stopped, isFalse);
    expect(recorder.scheduler.runningCount, 1);
    expect(cache.isDirectoryProtected(directory), isTrue);
    tracker.defaultBytes = 150;
    tracker.releaseAll(bytes: 100);
    await stop.timeout(const Duration(seconds: 1));
    expect(task.fileSize, 150);
    expect(task.status, RecordStatus.stopped);
    expect(recorder.scheduler.runningCount, 0);
    expect(cache.isDirectoryProtected(directory), isFalse);
  });

  test('a late native exit releases the original directory owner rather than its registered replacement', () async {
    final original = Get.put(CacheService(defaultDirectoryResolver: () async => root));
    Get.put<StreamResolverService>(_Resolver());
    metrics.add();
    native.execution = Completer<void>();
    await recorder.startTask(task);
    await until(() => native.running);
    emit(FFmpegEventType.startAck, 1);
    final directory = task.outputDir!;
    Get.delete<RecorderController>(force: true);
    await until(() => native.stops == 1);
    Get.delete<CacheService>(force: true);
    final replacement = Get.put(CacheService(defaultDirectoryResolver: () async => root));
    replacement.protectDirectory(directory);
    native.execution!.complete();
    await until(() => recorder.scheduler.runningCount == 0);
    expect(original.isDirectoryProtected(directory), isFalse);
    expect(replacement.isDirectoryProtected(directory), isTrue);
  });
}

class _Settings extends RecordSettingsController {
  @override
  Future<void> refreshCacheSize() async {}
}

class _EventManager implements FFmpegManager {
  final events = StreamController<FFmpegEvent>.broadcast(sync: true);
  Completer<void>? execution;
  bool running = false;
  int stops = 0;
  FFmpegRecordSession? counters;
  @override
  Stream<FFmpegEvent> get stream => events.stream;
  @override
  FFmpegRecordSession? getSession(String taskId) => counters;
  @override
  bool isRunning(String taskId) => running;
  @override
  Future<void> start({required String taskId, required List<String> arguments, bool liveRecording = false}) async {
    running = true;
    try {
      await execution?.future;
    } finally {
      running = false;
    }
  }

  @override
  Future<void> stop(String taskId) async {
    stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Counters implements FFmpegRecordSession {
  _Counters(this.sessionId);
  @override
  final int sessionId;
  @override
  int fileSize = 1000;
  @override
  int recordedSeconds = 60;
  @override
  bool mediaStarted = true;
  @override
  double bitrate = 10;
  @override
  double speed = 1;
  @override
  double fps = 60;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver extends StreamResolverService {
  @override
  Future<ResolvedRecordStream> resolveStream({
    required String roomId,
    required String platform,
    required String preferredQuality,
    String? previousQualityId,
    int? previousLineIndex,
    bool renewCurrent = false,
  }) async => ResolvedRecordStream(
    url: 'https://fixture.invalid/live.flv',
    quality: LivePlayQuality(quality: 'fixture', id: 'fixture'),
    qualityCursorId: 'fixture',
    lineIndex: 0,
    candidateUrls: const ['https://fixture.invalid/live.flv'],
  );
}

class _Metrics extends RecordingOutputMetrics {
  final trackers = <_Tracker>[];
  Completer<RecordingOutputSnapshot>? measurement;
  int measurementCalls = 0;
  @override
  Future<RecordingOutputSnapshot> measure({required String directoryPath, required String filePrefix}) async {
    measurementCalls++;
    return await measurement?.future ?? RecordingOutputSnapshot.empty;
  }

  var index = 0;
  _Tracker add() {
    final tracker = _Tracker();
    trackers.add(tracker);
    return tracker;
  }

  @override
  RecordingOutputTracker track({required String directoryPath, required String filePrefix}) => trackers[index++];
}

class _Tracker extends RecordingOutputTracker {
  _Tracker() : super(directoryPath: '', filePrefix: '');
  final gates = <Completer<RecordingOutputSnapshot>>[];
  var calls = 0;
  var active = 0;
  var maximumActive = 0;
  var defaultBytes = 0;
  var failNext = false;
  var nextGate = 0;
  void holdNext() => gates.add(Completer<RecordingOutputSnapshot>());
  void releaseAll({int bytes = 0}) {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete(RecordingOutputSnapshot(bytes: bytes, segmentCount: bytes > 0 ? 1 : 0));
    }
  }

  @override
  Future<RecordingOutputSnapshot> sample() async {
    calls++;
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (failNext) {
        failNext = false;
        throw const FileSystemException('fixture read failure');
      }
      if (nextGate < gates.length) return await gates[nextGate++].future;
      return RecordingOutputSnapshot(bytes: defaultBytes, segmentCount: defaultBytes > 0 ? 1 : 0);
    } finally {
      active--;
    }
  }
}
