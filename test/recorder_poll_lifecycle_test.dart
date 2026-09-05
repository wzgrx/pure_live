import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Site site;
  late _Scheduler scheduler;
  late RecorderController recorder;
  late RecordSettingsController settings;
  late LiveRecordTask task;

  setUp(() async {
    Get.testMode = true;
    root = await Directory.systemTemp.createTemp('pure-live-poll-lifecycle-');
    Hive.init(root.path);
    await HivePrefUtil.init();
    site = _Site();
    scheduler = _Scheduler();
    settings = RecordSettingsController();
    settings.enablePolling.value = false;
    recorder = RecorderController.forTesting(
      settings: settings,
      ffmpeg: _Events(),
      scheduler: scheduler,
      siteResolver: (_) => site,
      pollTimeout: const Duration(milliseconds: 500),
    );
    Get.put(recorder);
    task = makeTask('fixture');
    recorder.tasks.add(task);
  });

  tearDown(() async {
    Get.delete<RecorderController>(force: true);
    site.releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    Get.reset();
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: 'fixture did not reach its controlled boundary');
  }

  for (final live in [false, true]) {
    test('a status response arriving after stop preserves user intent (live=$live)', () async {
      final response = site.hold();
      final poll = recorder.refreshTaskStatus(task);
      expect(site.requests, ['fixture']);
      await recorder.stopTask(task);
      response.complete(room('fixture', live: live));
      await poll;
      await Future<void>.delayed(Duration.zero);
      expect(task.status, RecordStatus.stopped);
      expect(task.title, 'original');
      expect(scheduler.starts, isEmpty);
    });
  }

  test('a delayed failure after stop does not overwrite the stopped card', () async {
    final response = site.hold();
    final poll = recorder.refreshTaskStatus(task);
    await recorder.stopTask(task);
    response.completeError(const SocketException('fixture network failure'));
    await poll;
    await Future<void>.delayed(Duration.zero);
    expect(task.status, RecordStatus.stopped);
    expect(task.lastError, isNull);
  });

  test('a response after service close is discarded', () async {
    final response = site.hold();
    final poll = recorder.refreshTaskStatus(task);
    Get.delete<RecorderController>(force: true);
    final before = task.toJson();
    response.complete(room('fixture'));
    await poll;
    await Future<void>.delayed(Duration.zero);
    expect(task.toJson(), before);
    expect(scheduler.starts, isEmpty);
  });

  test('a replaced task with the same ID is not overwritten by the old request', () async {
    final response = site.hold();
    final poll = recorder.refreshTaskStatus(task);
    final replacement = makeTask('fixture')..title = 'replacement';
    recorder.tasks.assignAll([replacement]);
    response.complete(room('fixture'));
    await poll;
    await Future<void>.delayed(Duration.zero);
    expect(identical(recorder.tasks.single, replacement), isTrue);
    expect(replacement.title, 'replacement');
    expect(task.title, 'original');
  });

  test('skipping a stopped task does not leave a permanent in-flight marker', () async {
    task.wasStoppedByUser = true;
    await recorder.refreshTaskStatus(task);
    expect(site.requests, isEmpty);
    task.wasStoppedByUser = false;
    await recorder.refreshTaskStatus(task);
    expect(site.requests, ['fixture']);
  });

  test('concurrent refresh callers join the same outstanding result', () async {
    final response = site.hold();
    final first = recorder.refreshTaskStatus(task);
    var secondDone = false;
    final second = recorder.refreshTaskStatus(task).then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(site.requests, ['fixture']);
    expect(secondDone, isFalse);
    response.complete(room('fixture'));
    await Future.wait([first, second]);
    expect(task.title, 'refreshed');
  });

  test('manual start invalidates a pending room status response', () async {
    final response = site.hold();
    final poll = recorder.refreshTaskStatus(task);
    await recorder.startTask(task);
    expect(scheduler.starts, ['fixture']);
    response.complete(room('fixture'));
    await poll;
    await Future<void>.delayed(Duration.zero);
    expect(task.status, RecordStatus.queued);
    expect(task.title, 'original');
    expect(scheduler.starts, ['fixture']);
  });

  test('startup keeps manual stop and terminal history while resuming only unfinished work', () async {
    settings.autoStartOnBoot.value = true;
    final stopped = makeTask('stopped')
      ..status = RecordStatus.stopped
      ..wasStoppedByUser = true;
    final completed = makeTask('completed')..status = RecordStatus.completed;
    final failed = makeTask('failed')..status = RecordStatus.failed;
    final waiting = makeTask('waiting')..status = RecordStatus.waitingLive;
    final running = makeTask('running')..status = RecordStatus.running;
    await HivePrefUtil.setString(
      RecorderKeys.recorderTasks,
      jsonEncode([stopped.toJson(), completed.toJson(), failed.toJson(), waiting.toJson(), running.toJson()]),
    );
    await recorder.restoreAndAutoPoll();
    expect(site.requests.toSet(), {'waiting', 'running'});
    final restoredStopped = recorder.tasks.singleWhere((candidate) => candidate.taskId == 'stopped');
    expect(restoredStopped.wasStoppedByUser, isTrue);
    expect(restoredStopped.status, RecordStatus.stopped);
    expect(recorder.tasks.singleWhere((candidate) => candidate.taskId == 'completed').status, RecordStatus.completed);
    expect(recorder.tasks.singleWhere((candidate) => candidate.taskId == 'failed').status, RecordStatus.failed);
  });

  test('a late old request does not release a replacement request owner', () async {
    final old = site.hold();
    final first = recorder.refreshTaskStatus(task);
    await recorder.stopTask(task);
    task.wasStoppedByUser = false;
    task.status = RecordStatus.waitingLive;
    final current = site.hold();
    final second = recorder.refreshTaskStatus(task);
    expect(site.requests, hasLength(2));
    old.complete(room('fixture', live: true));
    await Future<void>.delayed(Duration.zero);
    var joined = false;
    final third = recorder.refreshTaskStatus(task).then((_) => joined = true);
    await Future<void>.delayed(Duration.zero);
    expect(joined, isFalse);
    expect(site.requests, hasLength(2));
    current.complete(room('fixture'));
    await Future.wait([first, second, third]);
    expect(scheduler.starts, isEmpty);
  });

  test('a timed-out request releases the slot and its late response is ignored', () async {
    final late = site.hold();
    await recorder.refreshTaskStatus(task);
    expect(task.lastError, contains('TimeoutException'));
    final current = site.hold();
    final second = recorder.refreshTaskStatus(task);
    late.complete(room('fixture', live: true));
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.starts, isEmpty);
    expect(task.title, 'original');
    current.complete(room('fixture'));
    await second;
    expect(site.requests, hasLength(2));
    expect(task.title, 'refreshed');
    expect(site.fullDetailRequests, 0, reason: 'polling uses the lightweight room refresh contract');
  });

  test('disabling automatic checks cancels an active automatic request and scheduled checks', () async {
    final response = site.hold();
    settings.enablePolling.value = true;
    await until(() => site.requests.length == 1);
    settings.enablePolling.value = false;
    response.complete(room('fixture', live: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(task.title, 'original');
    expect(scheduler.starts, isEmpty);
    settings.enablePolling.value = true;
    await until(() => site.requests.length == 2);
    expect(task.title, 'refreshed');
  });

  test('an explicit one-shot check works when automatic checks are disabled', () async {
    final response = site.hold();
    final poll = recorder.refreshTaskStatus(task);
    settings.enablePolling.value = false;
    response.complete(room('fixture', live: true));
    await poll;
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.starts, ['fixture']);
  });

  test('startup fans out at most three requests and one slow room does not block later rooms', () async {
    settings.autoStartOnBoot.value = true;
    final first = site.hold();
    final second = site.hold();
    final third = site.hold();
    await HivePrefUtil.setString(
      RecorderKeys.recorderTasks,
      jsonEncode([for (var i = 0; i < 8; i++) makeTask('room$i').toJson()]),
    );
    final startup = recorder.restoreAndAutoPoll();
    await until(() => site.requests.length == 3);
    expect(site.requests, ['room0', 'room1', 'room2']);
    second.complete(room('room1'));
    await until(() => site.requests.length == 8);
    expect(first.isCompleted, isFalse);
    expect(third.isCompleted, isFalse);
    expect(site.maximumActive, 3);
    first.complete(room('room0'));
    third.complete(room('room2'));
    await startup;
  });

  test('closing during startup stops queued room checks and resolves coalesced startup callers', () async {
    settings.autoStartOnBoot.value = true;
    for (var i = 0; i < 3; i++) {
      site.hold();
    }
    await HivePrefUtil.setString(
      RecorderKeys.recorderTasks,
      jsonEncode([for (var i = 0; i < 8; i++) makeTask('room$i').toJson()]),
    );
    final first = recorder.restoreAndAutoPoll();
    final second = recorder.restoreAndAutoPoll();
    await until(() => site.requests.length == 3);
    Get.delete<RecorderController>(force: true);
    await Future.wait([first, second]).timeout(const Duration(seconds: 1));
    site.releaseAll();
    await Future<void>.delayed(Duration.zero);
    expect(site.requests, hasLength(3));
    expect(scheduler.starts, isEmpty);
  });

  test('duplicate saved task IDs do not transfer resume intent to completed history', () async {
    settings.autoStartOnBoot.value = true;
    final completed = makeTask('duplicate')..status = RecordStatus.completed;
    await HivePrefUtil.setString(
      RecorderKeys.recorderTasks,
      jsonEncode([completed.toJson(), makeTask('duplicate').toJson()]),
    );
    await recorder.restoreAndAutoPoll();
    expect(site.requests, isEmpty);
    expect(recorder.tasks.single.status, RecordStatus.completed);
  });
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
  status: RecordStatus.waitingLive,
);

LiveRoom room(String id, {bool live = false}) =>
    LiveRoom(roomId: id, platform: 'huya', title: 'refreshed', liveStatus: live ? LiveStatus.live : LiveStatus.offline);

class _Site extends LiveSite implements LiveSiteRoomRefresher {
  final requests = <String>[];
  final gates = <Completer<LiveRoom>>[];
  var nextGate = 0;
  var fullDetailRequests = 0;
  var active = 0;
  var maximumActive = 0;
  Completer<LiveRoom> hold() {
    final gate = Completer<LiveRoom>();
    gates.add(gate);
    return gate;
  }

  void releaseAll() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete(room('fixture'));
    }
  }

  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) async {
    requests.add(roomId);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      return nextGate < gates.length ? await gates[nextGate++].future : room(roomId);
    } finally {
      active--;
    }
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) {
    fullDetailRequests++;
    return getRoomDetailForRefresh(roomId: roomId, platform: platform);
  }
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
  @override
  int get queuedCount => queued.length;
  @override
  int get runningCount => 0;
  @override
  bool isRunning(String taskId) => false;
  @override
  bool isQueued(String taskId) => queued.contains(taskId);
  @override
  Future<void> waitForTask(String taskId) async {}
  @override
  Future<void> clearAll() async => queued.clear();
  @override
  Future<void> cancel(String taskId) async {
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
