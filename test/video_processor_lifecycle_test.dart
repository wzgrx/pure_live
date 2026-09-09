import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

void main() {
  late Directory directory;
  late LiveRecordTask task;
  late File source;
  late _NativeLifecycleFixture native;
  late VideoProcessorService service;
  late CacheService cache;
  Future<bool>? conversion;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-finalization-');
    Get.testMode = true;
    cache = Get.put(CacheService(configuredPathResolver: () => null, defaultDirectoryResolver: () async => directory));
    task = LiveRecordTask.fromRoom(LiveRoom(platform: 'acfun', roomId: '123', nick: 'fixture'))
      ..outputDir = directory.path;
    source = await File(p.join(directory.path, '${task.recordingFilePrefix}_000000.ts')).writeAsBytes([1, 2, 3]);
    native = _NativeLifecycleFixture();
    // Ordinary lifecycle cases follow explicit native signals, not a 30 ms
    // race against real temporary-file I/O under the full suite's load.
    service = VideoProcessorService.forTesting(ffmpeg: native);
    conversion = null;
  });
  tearDown(() async {
    if (native.startGate?.isCompleted == false) native.startGate!.complete();
    if (native.exitGate?.isCompleted == false) native.exitGate!.complete();
    native.finish();
    await conversion?.timeout(const Duration(seconds: 2));
    await _waitForMergeRelease(service, task.taskId);
    service.onClose();
    Get.reset();
    await native.events.close();
    await directory.delete(recursive: true);
  });

  void useShortDeadline() {
    service.onClose();
    service = VideoProcessorService.forTesting(ffmpeg: native, completionTimeout: const Duration(milliseconds: 30));
  }

  test('persisted capture damage blocks remux before native IO and retains original source', () async {
    task.queuePendingAttempt(
      directoryPath: directory.path,
      filePrefix: task.recordingFilePrefix,
      inputIntegrityError: true,
    );
    task = LiveRecordTask.fromJson(task.toJson());
    conversion = service.convertToMp4(task: task, directoryPath: '${directory.path}/.');
    expect(await conversion, false);
    expect(native.startCalls, 0);
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect(await directory.list().where((f) => f.path.endsWith('.mp4')).length, 0);
    expect(task.pendingAttempts.single.inputIntegrityError, true);
    expect(service.isProcessing(task.taskId), false);
  });

  test('damage on another attempt does not prevent exact healthy source finalization', () async {
    task.inputTailDiscarded = true;
    task.inputCoverageIncomplete = true;
    task.queuePendingAttempt(directoryPath: directory.path, filePrefix: 'other', inputIntegrityError: true);
    native.finish();
    conversion = service.convertToMp4(task: task);
    expect(await conversion, true);
    expect(native.startCalls, 1);
    expect(await source.exists(), false);
    expect(task.pendingAttempts.single.inputIntegrityError, true);
    expect(task.inputTailDiscarded, true, reason: 'successful remux must not erase missing-input provenance');
    expect(task.inputCoverageIncomplete, true);
  });

  test('merge timeout covers the running native Future and cancels before cleanup', () async {
    useShortDeadline();
    conversion = service.convertToMp4(task: task);
    await native.started.future.timeout(const Duration(seconds: 2));
    var escapedDeadline = false;
    final result = await conversion!.timeout(
      const Duration(milliseconds: 300),
      onTimeout: () {
        escapedDeadline = true;
        return false;
      },
    );
    expect(escapedDeadline, isFalse, reason: 'The native start Future is the execution, not a start acknowledgement.');
    expect(result, isFalse);
    expect(native.stopCalls, 1);
    // Stop acknowledgement can precede both native exit and asynchronous file
    // cleanup. Observe the ownership release, not a microtask ordering.
    await _waitForMergeRelease(service, task.taskId);
    expect(native.running, isFalse);
    expect(service.isProcessing(task.taskId), isFalse);
    expect(await source.exists(), isTrue);
    expect(await File(native.output!).exists(), isFalse);
  });

  test('stop acknowledgement is latched until the actual writer exits', () async {
    native.exitGate = Completer<void>();
    conversion = service.convertToMp4(task: task);
    await native.started.future;
    await service.cancel(task.taskId);
    expect(native.running, true);
    await service.cancel(task.taskId);
    service.onClose();
    expect(native.stopCalls, 1);
    expect(service.isProcessing(task.taskId), true);
    expect(await source.exists(), true);
    native.exitGate!.complete();
    expect(await conversion!, false);
    await _waitForMergeRelease(service, task.taskId);
    expect(native.stopCalls, 1);
  });

  test('cancel during directory preparation never starts a native merge', () async {
    conversion = service.convertToMp4(task: task);
    await service.cancel(task.taskId);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(native.startCalls, 0);
    expect(await conversion!.timeout(const Duration(seconds: 1)), isFalse);
    expect(await source.exists(), isTrue);
    expect(service.isProcessing(task.taskId), isFalse);
  });

  test('a native stop that is still pending keeps ownership and files until it settles', () async {
    useShortDeadline();
    native.stopCompletes = false;
    conversion = service.convertToMp4(task: task);
    await native.started.future.timeout(const Duration(seconds: 2));
    var escapedDeadline = false;
    final result = await conversion!.timeout(
      const Duration(milliseconds: 300),
      onTimeout: () {
        escapedDeadline = true;
        return false;
      },
    );
    expect(escapedDeadline, isFalse);
    expect(result, isFalse);
    expect(service.isProcessing(task.taskId), isTrue);
    expect(await File(native.output!).exists(), isTrue);
    expect(cache.isDirectoryProtected(directory.path), isTrue);
    await cache.clearAll();
    expect(await source.exists(), isTrue);
    expect(await File(native.output!).exists(), isTrue);
    expect(await service.convertToMp4(task: task), isFalse);
    expect(native.startCalls, 1);
    native.finish();
    await _waitForMergeRelease(service, task.taskId);
    expect(service.isProcessing(task.taskId), isFalse);
    expect(await File(native.output!).exists(), isFalse);
    expect(await source.exists(), isTrue);
    expect(cache.isDirectoryProtected(directory.path), isFalse);
  });

  test('late native start acknowledgement observes a timeout cancellation', () async {
    useShortDeadline();
    native.startGate = Completer<void>();
    conversion = service.convertToMp4(task: task);
    expect(await conversion!.timeout(const Duration(milliseconds: 300)), isFalse);
    expect(service.isProcessing(task.taskId), isTrue);
    expect(native.stopCalls, 0);
    native.startGate!.complete();
    await native.started.future;
    await _waitForMergeRelease(service, task.taskId);
    expect(native.stopCalls, 1);
    expect(service.isProcessing(task.taskId), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('natural completion commits the output without overwriting an older MP4', () async {
    final oldOutput = await File(p.join(directory.path, '${task.recordingFilePrefix}.mp4')).writeAsBytes([9]);
    conversion = service.convertToMp4(task: task);
    await native.started.future;
    native.finish();
    expect(await conversion!, isTrue);
    expect(native.arguments, contains('-xerror'), reason: 'Corrupt packets must stop finalization before deleting TS.');
    expect(await oldOutput.readAsBytes(), [9]);
    expect(await File(p.join(directory.path, '${task.recordingFilePrefix}-1.mp4')).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isFalse);
    expect(native.stopCalls, 0);
    expect(service.isProcessing(task.taskId), isFalse);
  });

  test('cancelling an active merge preserves source segments and removes only its partial output', () async {
    conversion = service.convertToMp4(task: task);
    await native.started.future;
    await service.cancel(task.taskId);
    expect(await conversion!, isFalse);
    await _waitForMergeRelease(service, task.taskId);
    expect(await source.exists(), isTrue);
    expect(await File(native.output!).exists(), isFalse);
    expect(native.stopCalls, 1);
    expect(service.isProcessing(task.taskId), isFalse);
  });

  test('native execution failure preserves inputs and releases its task ownership', () async {
    native.failOnFinish = true;
    conversion = service.convertToMp4(task: task);
    await native.started.future;
    native.finish();
    expect(await conversion!, isFalse);
    await _waitForMergeRelease(service, task.taskId);
    expect(await source.exists(), isTrue);
    expect(await File(native.output!).exists(), isFalse);
    expect(service.isProcessing(task.taskId), isFalse);
  });

  test('native timestamp sentinel does not report merge completion before the file commits', () async {
    task.recordedSeconds = 32;
    final observed = <VideoProcessEvent>[];
    final subscription = service.stream.listen(observed.add);
    addTearDown(subscription.cancel);
    conversion = service.convertToMp4(task: task);
    await native.started.future;
    native.progress(time: 9223372013568000, size: 0);
    await Future<void>.delayed(Duration.zero);
    expect(observed.where((event) => event.type == VideoProcessEventType.progress).single.progress, 0);
    native.finish();
    expect(await conversion!, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(observed.last.type, VideoProcessEventType.completed);
    expect(observed.last.progress, 1);
  });
}

/// Cleanup performs asynchronous file I/O after the native Future settles.
/// Observe release, rather than assuming Windows finished it within 30 ms.
Future<void> _waitForMergeRelease(VideoProcessorService service, String taskId) async {
  final watch = Stopwatch()..start();
  while (service.isProcessing(taskId)) {
    if (watch.elapsed > const Duration(seconds: 2)) {
      throw TestFailure('Native merge ownership was not released after execution settled');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Mirrors FFmpegService.start / FFmpegSession.executeAsync: it resolves only
/// after execution ends. Files below are lifecycle fixtures, not playable media.
class _NativeLifecycleFixture implements FFmpegManager {
  final events = StreamController<FFmpegEvent>.broadcast();
  final started = Completer<void>();
  final _finish = Completer<void>();
  bool running = false;
  bool stopCompletes = true;
  bool failOnFinish = false;
  Completer<void>? startGate;
  Completer<void>? exitGate;
  int startCalls = 0;
  int stopCalls = 0;
  String? output;
  List<String> arguments = [];
  String? nativeTaskId;
  @override
  Stream<FFmpegEvent> get stream => events.stream;
  @override
  bool isRunning(String taskId) => running;
  @override
  Future<void> start({
    required String taskId,
    required List<String> arguments,
    bool liveRecording = false,
    HlsSourceQueryPolicy? sourceQueryPolicy,
    HlsRelayDiagnostics? hlsDiagnostics,
  }) async {
    this.arguments = arguments;
    startCalls++;
    nativeTaskId = taskId;
    await startGate?.future;
    running = true;
    output = arguments.last;
    await File(output!).writeAsBytes([1, 2, 3, 4]);
    events.add(FFmpegEvent(taskId: taskId, type: FFmpegEventType.startAck));
    started.complete();
    await _finish.future;
    await exitGate?.future;
    running = false;
    if (failOnFinish) throw StateError('fixture native execution failure');
    events.add(FFmpegEvent(taskId: taskId, type: FFmpegEventType.complete));
  }

  @override
  Future<void> stop(String taskId) async {
    stopCalls++;
    if (stopCompletes) finish();
  }

  void finish() {
    if (!_finish.isCompleted) _finish.complete();
  }

  void progress({required num time, required num size}) {
    events.add(FFmpegEvent(taskId: nativeTaskId!, type: FFmpegEventType.progress, data: {'time': time, 'size': size}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
