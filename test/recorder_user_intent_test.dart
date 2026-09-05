import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/recording_output_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Recorder recorder;
  late _Scheduler scheduler;
  late _Metrics metrics;
  late LiveRecordTask task;

  setUp(() async {
    Get.testMode = true;
    root = await Directory.systemTemp.createTemp('pure-live-record-intent-');
    Hive.init(root.path);
    await HivePrefUtil.init();
    Get.put(CacheService(defaultDirectoryResolver: () async => root));
    scheduler = _Scheduler();
    metrics = _Metrics();
    final settings = _Settings();
    settings.autoStartOnBoot.value = false;
    settings.enablePolling.value = false;
    recorder = _Recorder(settings, scheduler, metrics);
    Get.put<RecorderController>(recorder);
    task = makeTask('fixture');
    recorder.tasks.add(task);
  });
  tearDown(() async {
    Get.delete<RecorderController>(force: true);
    if (recorder.permission?.isCompleted == false) recorder.permission!.complete(true);
    if (scheduler.cancellation?.isCompleted == false) scheduler.cancellation!.complete();
    if (scheduler.drain?.isCompleted == false) scheduler.drain!.complete();
    if (metrics.gate?.isCompleted == false) metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    Get.reset();
    await Hive.close();
    await root.delete(recursive: true);
  });
  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: 'controlled boundary was not reached');
  }

  Future<void> persistInterrupted({bool two = false}) async {
    task.status = RecordStatus.running;
    task.queuePendingAttempt(directoryPath: root.path, filePrefix: 'old');
    await HivePrefUtil.setString(
      RecorderKeys.recorderTasks,
      jsonEncode([
        task.toJson(),
        if (two)
          (makeTask('second')
                ..status = RecordStatus.running
                ..queuePendingAttempt(directoryPath: root.path, filePrefix: 'second'))
              .toJson(),
      ]),
    );
  }

  test('stop invalidates a start still waiting for storage permission', () async {
    recorder.permission = Completer<bool>();
    final starting = recorder.startTask(task);
    await recorder.stopTask(task);
    recorder.permission!.complete(true);
    expect(await starting, isFalse);
    expect(scheduler.starts, isEmpty);
    expect(task.status, RecordStatus.stopped);
    expect(task.wasStoppedByUser, isTrue);
    expect(task.fileSize, 100);
  });
  test('removal invalidates permission and retains the removed history data', () async {
    recorder.permission = Completer<bool>();
    final starting = recorder.startTask(task);
    await recorder.unRecorder(task);
    recorder.permission!.complete(true);
    expect(await starting, isFalse);
    expect(task.fileSize, 100);
    expect(recorder.tasks, isEmpty);
  });
  test('repeated start shares one permission request and one enqueue', () async {
    recorder.permission = Completer<bool>();
    final first = recorder.startTask(task);
    final second = recorder.startTask(task);
    expect(recorder.permissionCalls, 1);
    recorder.permission!.complete(true);
    expect(await Future.wait([first, second]), [true, true]);
    expect(scheduler.starts, ['fixture']);
  });
  test('an add returning from permission after service close creates no card', () async {
    recorder.permission = Completer<bool>();
    final adding = recorder.addTask(
      room: LiveRoom(roomId: 'new', platform: 'huya'),
    );
    Get.delete<RecorderController>(force: true);
    recorder.permission!.complete(true);
    expect(await adding, isNull);
    expect(recorder.tasks, [task]);
    expect(scheduler.starts, isEmpty);
  });
  test('start of a replaced task leaves old and replacement metadata untouched', () async {
    recorder.permission = Completer<bool>();
    final starting = recorder.startTask(task);
    final replacement = makeTask('fixture')..title = 'replacement';
    recorder.tasks.assignAll([replacement]);
    recorder.permission!.complete(true);
    expect(await starting, isFalse);
    expect(task.fileSize, 100);
    expect(recorder.tasks.single, same(replacement));
  });
  test('a new start waits for the preceding stop to drain before enqueue', () async {
    scheduler.cancellation = Completer<void>();
    final stopping = recorder.stopTask(task);
    final starting = recorder.startTask(task);
    await flush();
    expect(scheduler.starts, isEmpty);
    scheduler.cancellation!.complete();
    await stopping;
    expect(await starting, isTrue);
    expect(task.status, RecordStatus.queued);
    expect(task.wasStoppedByUser, isFalse);
  });
  test('a late stop does not replace a new card with the same task ID', () async {
    scheduler.cancellation = Completer<void>();
    final stopping = recorder.stopTask(task);
    final replacement = makeTask('fixture')..title = 'replacement';
    recorder.tasks.assignAll([replacement]);
    scheduler.cancellation!.complete();
    await stopping;
    expect(recorder.tasks.single, same(replacement));
  });
  test('manual start waits for interrupted output recovery before resetting counters', () async {
    await persistInterrupted();
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final restored = recorder.tasks.single;
    final starting = recorder.startTask(restored);
    await flush();
    expect(scheduler.starts, isEmpty);
    expect(restored.fileSize, 100);
    metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await restoring;
    expect(await starting, isTrue);
    expect(restored.status, RecordStatus.queued);
    expect(restored.pendingAttempts, hasLength(1), reason: 'failed old output remains recoverable');
  });
  test('recovery completion does not overwrite a replacement card', () async {
    await persistInterrupted();
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final replacement = makeTask('fixture')..title = 'replacement';
    recorder.tasks.assignAll([replacement]);
    metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await restoring;
    expect(recorder.tasks.single, same(replacement));
  });
  test('all interrupted tasks reserve recovery before the first file scan awaits', () async {
    await persistInterrupted(two: true);
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final second = recorder.tasks.last;
    final starting = recorder.startTask(second);
    await flush();
    expect(scheduler.starts, isEmpty);
    metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await restoring;
    expect(await starting, isTrue);
    expect(second.status, RecordStatus.queued);
  });

  test('permission denial preserves statistics and permits an explicit later retry', () async {
    recorder.permission = Completer<bool>();
    final first = recorder.startTask(task);
    recorder.permission!.complete(false);
    expect(await first, isFalse);
    expect(task.fileSize, 100);
    expect(task.recordedSeconds, 10);
    expect(scheduler.starts, isEmpty);
    recorder.permission = null;
    expect(await recorder.startTask(task), isTrue);
    expect(task.fileSize, 0);
    expect(task.status, RecordStatus.queued);
  });
  test('closing completes the user start without waiting for the system dialog', () async {
    recorder.permission = Completer<bool>();
    final starting = recorder.startTask(task);
    Get.delete<RecorderController>(force: true);
    expect(await starting.timeout(const Duration(seconds: 1)), isFalse);
    expect(recorder.permission!.isCompleted, isFalse);
    recorder.permission!.complete(true);
    await flush();
    expect(scheduler.starts, isEmpty);
    expect(task.fileSize, 100);
  });
  test('permission failure reaches coalesced callers and does not poison the next start', () async {
    recorder.permission = Completer<bool>();
    final first = recorder.startTask(task);
    final second = recorder.startTask(task);
    final firstError = expectLater(first, throwsStateError);
    final secondError = expectLater(second, throwsStateError);
    recorder.permission!.completeError(StateError('fixture permission failure'));
    await Future.wait([firstError, secondError]);
    recorder.permission = null;
    expect(await recorder.startTask(task), isTrue);
    expect(scheduler.starts, ['fixture']);
  });
  test('duplicate stops share native cancellation and wait for the same completion', () async {
    scheduler.cancellation = Completer<void>();
    final first = recorder.stopTask(task);
    final second = recorder.stopTask(task);
    await flush();
    expect(scheduler.cancelCalls, 1);
    scheduler.cancellation!.complete();
    await Future.wait([first, second]);
    expect(task.status, RecordStatus.stopped);
  });
  test('removal in progress rejects a new start instead of deleting its running card', () async {
    scheduler.cancellation = Completer<void>();
    final removing = recorder.unRecorder(task);
    expect(await recorder.startTask(task), isFalse);
    scheduler.cancellation!.complete();
    await removing;
    expect(scheduler.starts, isEmpty);
    expect(recorder.tasks, isEmpty);
  });
  test('another stop cancels the new start that is waiting for an older stop', () async {
    scheduler.cancellation = Completer<void>();
    final stopping = recorder.stopTask(task);
    final starting = recorder.startTask(task);
    await flush();
    final stopAgain = recorder.stopTask(task);
    expect(await starting.timeout(const Duration(seconds: 1)), isFalse);
    scheduler.cancellation!.complete();
    await Future.wait([stopping, stopAgain]);
    expect(scheduler.starts, isEmpty);
  });
  test('late permission completion does not clear the replacement start owner', () async {
    final oldPermission = Completer<bool>();
    recorder.permission = oldPermission;
    final oldStart = recorder.startTask(task);
    await recorder.stopTask(task);
    final currentPermission = Completer<bool>();
    recorder.permission = currentPermission;
    final currentStart = recorder.startTask(task);
    oldPermission.complete(true);
    await flush();
    expect(await oldStart, isFalse);
    expect(scheduler.starts, isEmpty);
    currentPermission.complete(true);
    expect(await currentStart, isTrue);
    expect(scheduler.starts, ['fixture']);
  });
  test('an unrelated task can start while old output recovery is waiting', () async {
    await persistInterrupted();
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final other = makeTask('other');
    recorder.tasks.add(other);
    expect(await recorder.startTask(other), isTrue);
    expect(scheduler.starts, ['other']);
    metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await restoring;
    expect(other.status, RecordStatus.queued);
  });
  test('close during recovery releases reservations without mutating cards or starting queued output', () async {
    await persistInterrupted(two: true);
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final pendingStart = recorder.startTask(recorder.tasks.last);
    final before = recorder.tasks.map((task) => task.toJson()).toList();
    final cache = CacheService.to;
    expect(cache.isDirectoryProtected(root.path), isTrue);
    Get.delete<RecorderController>(force: true);
    expect(await pendingStart, isFalse);
    expect(cache.isDirectoryProtected(root.path), isTrue);
    metrics.gate!.complete(RecordingOutputSnapshot.empty);
    await restoring;
    expect(cache.isDirectoryProtected(root.path), isFalse);
    expect(metrics.calls, 1);
    expect(recorder.tasks.map((task) => task.toJson()).toList(), before);
    expect(scheduler.starts, isEmpty);
  });
  test('failed file recovery releases its reservation and leaves the directory recoverable', () async {
    await persistInterrupted();
    metrics.gate = Completer<RecordingOutputSnapshot>();
    final restoring = recorder.restoreAndAutoPoll();
    await until(() => metrics.calls == 1);
    final restored = recorder.tasks.single;
    final starting = recorder.startTask(restored);
    metrics.gate!.completeError(const FileSystemException('fixture inaccessible directory'));
    await restoring;
    expect(await starting, isTrue);
    expect(restored.pendingAttempts, hasLength(1));
    expect(CacheService.to.isDirectoryProtected(root.path), isFalse);
    expect(restored.status, RecordStatus.queued);
  });

  test('a cancellation timeout is not proof that the native recording has drained', () async {
    scheduler.runningTask = task.taskId;
    scheduler.drain = Completer<void>();
    var stopped = false;
    final stopping = recorder.stopTask(task).then((_) => stopped = true);
    await flush();
    expect(stopped, isFalse, reason: 'cancellation returned while the native task still owns its slot');
    final starting = recorder.startTask(task);
    await flush();
    expect(scheduler.starts, isEmpty);
    expect(task.fileSize, 100);
    scheduler.drain!.complete();
    await stopping;
    expect(await starting, isTrue);
    expect(scheduler.starts, ['fixture']);
    expect(task.status, RecordStatus.queued);
  });

  for (final close in [false, true]) {
    test('add does not return a detached card after its start was cancelled (close=$close)', () async {
      final initialPermission = Completer<bool>();
      final startPermission = Completer<bool>();
      recorder.permission = initialPermission;
      final adding = recorder.addTask(
        room: LiveRoom(roomId: 'new', platform: 'huya'),
      );
      recorder.permission = startPermission;
      initialPermission.complete(true);
      await until(() => recorder.permissionCalls == 2);
      final added = recorder.tasks.last;
      if (close) {
        Get.delete<RecorderController>(force: true);
      } else {
        await recorder.unRecorder(added);
      }
      expect(await adding.timeout(const Duration(seconds: 1)), isNull);
      startPermission.complete(true);
      await flush();
      expect(scheduler.starts, isEmpty);
    });
  }
}

LiveRecordTask makeTask(String id) => LiveRecordTask(
  taskId: id,
  roomId: id,
  platform: 'huya',
  title: 'original',
  nick: 'fixture',
  avatar: '',
  cover: '',
  createTime: DateTime(2026, 9, 5),
  fileSize: 100,
  recordedSeconds: 10,
  status: RecordStatus.stopped,
);

class _Recorder extends RecorderController {
  _Recorder(RecordSettingsController settings, FFmpegScheduler scheduler, RecordingOutputMetrics metrics)
    : super.forTesting(settings: settings, scheduler: scheduler, ffmpeg: _Events(), outputMetrics: metrics);
  Completer<bool>? permission;
  var permissionCalls = 0;
  @override
  Future<bool> requestStoragePermission() async {
    permissionCalls++;
    return permission?.future ?? true;
  }
}

class _Settings extends RecordSettingsController {
  @override
  Future<void> refreshCacheSize() async {}
}

class _Events implements FFmpegManager {
  @override
  Stream<FFmpegEvent> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scheduler implements FFmpegScheduler {
  final starts = <String>[];
  final queued = <String>{};
  Completer<void>? cancellation;
  var cancelCalls = 0;
  String? runningTask;
  Completer<void>? drain;
  @override
  int get queuedCount => queued.length;
  @override
  int get runningCount => 0;
  @override
  bool isRunning(String taskId) => taskId == runningTask;
  @override
  Future<void> waitForTask(String taskId) async {
    if (taskId != runningTask) return;
    await drain?.future;
    runningTask = null;
  }

  @override
  bool isQueued(String taskId) => queued.contains(taskId);
  @override
  Future<void> clearAll() async => queued.clear();
  @override
  Future<void> cancel(String taskId) async {
    cancelCalls++;
    await cancellation?.future;
    queued.remove(taskId);
  }

  @override
  void enqueue({required String taskId, required Future<void> Function(TaskCancelToken token) taskRunner}) {
    starts.add(taskId);
    queued.add(taskId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metrics extends RecordingOutputMetrics {
  Completer<RecordingOutputSnapshot>? gate;
  var calls = 0;
  @override
  Future<RecordingOutputSnapshot> measure({required String directoryPath, required String filePrefix}) async {
    calls++;
    return gate?.future ?? RecordingOutputSnapshot.empty;
  }
}
