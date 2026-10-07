import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/capture.dart';
import 'package:live_record/src/ffmpeg.dart';
import 'package:live_record/src/input.dart';
import 'package:live_record/src/merge.dart';
import 'package:live_record/src/metrics.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/policy.dart';
import 'package:live_record/src/resolver.dart';
import 'package:live_record/src/scheduler.dart';
import 'package:live_record/src/segments.dart';
import 'package:live_record/src/settings.dart';
import 'package:live_record/src/storage.dart';
import 'package:live_record/src/task.dart';
import 'package:meta/meta.dart';

/// Keeps the process alive while recordings run (3.x
/// `RecorderBackgroundService`: Android's foreground service). The app
/// (M12) implements it; [acquire] throws [RecordKeepAliveException] when
/// the platform refuses.
abstract interface class RecordKeepAlive {
  /// Holds the process for [owner].
  Future<void> acquire(Object owner);

  /// Releases [owner]'s hold.
  Future<void> release(Object owner);
}

/// The platform refused to keep recordings alive.
final class RecordKeepAliveException implements Exception {
  /// Creates the failure; [reason] is `timeout` for Android's time limit.
  const new(this.reason);

  /// Why.
  final String reason;
}

/// What the interface should tell the user (3.x's toasts from the
/// recorder).
enum RecordNoticeKind {
  /// FFmpeg failed and will not retry, or failed for the first time.
  captureFailed,

  /// The stream could not be resolved and the task stopped.
  resolveFailed,

  /// A start was requested while the task is still starting.
  starting,

  /// The platform served a lower quality than the one asked for (once per
  /// recording; the player's "平台实际返回").
  qualityLimited,
}

/// A message for the user about a task.
@immutable
final class RecordNotice {
  /// Creates the notice.
  const new(this.task, this.kind, {this.failure, this.streamError, this.quality});

  /// The task.
  final RecordTask task;

  /// Kind.
  final RecordNoticeKind kind;

  /// FFmpeg's failure for [RecordNoticeKind.captureFailed].
  final FfmpegFailureKind? failure;

  /// The resolution failure for [RecordNoticeKind.resolveFailed].
  final RecordStreamException? streamError;

  /// The served quality for [RecordNoticeKind.qualityLimited].
  final String? quality;
}

final class _Runtime {
  int? session;
  RecordCapture? capture;
  Completer<void>? lifecycle;
  Timer? pollTimer;
  int pollFailures = 0;
  Future<void>? poll;
  bool pollAutomatic = false;
  Timer? retryTimer;
  Timer? leaseTimer;
  ({String sourceUrl, ResolvedRecordStream stream})? prefetched;
  bool rapidRecovery = false;
  ({int bytes, int seconds}) base = (bytes: 0, seconds: 0);
  SegmentMeter? meter;
  BitrateWindow bitrate = BitrateWindow();
  Timer? monitor;
  DateTime? monitorStartedAt;
  DateTime? lastPersist;
  Future<void>? finalizing;
  Future<bool>? start;
  Future<void>? stop;
  Future<void>? recovering;
  bool starting = false;
  bool removing = false;
  Object? keepAliveOwner;

  /// This recording already said its quality was limited.
  bool qualityNoticed = false;
}

/// The recording core (the non-page part of 3.x's `RecorderController`):
/// tasks, the queue, live checks, attempts, retries, lease renewal,
/// finalization, persistence and restore.
///
/// Settings, storage, the FFmpeg runner, the keep-alive and persistence are
/// injected; the recording centre (M13) listens to [changes] and
/// [notices] and calls [addTask], [startTask], [stopTask], [removeTask] and
/// [refreshTaskStatus] like 3.x's page did.
final class Recorder {
  /// Creates the recorder. [sites] gives the adapter of a platform
  /// (`SiteRegistry.maybeOf`); `persist` stores the task list JSON (3.x's
  /// `recorder_tasks`, M9); `storageAccess` asks for storage permission
  /// (Android, M12), interactively only for a user action; [caFile] is the
  /// CA bundle for FFmpeg builds without a trust store.
  new({
    required LiveSite? Function(String platform) sites,
    required this.ffmpeg,
    required this.storage,
    required this.settings,
    RecordInputOpener? inputs,
    this._persist,
    this._keepAlive,
    this._storageAccess,
    this.caFile,
    this.pollTimeout = const Duration(seconds: 20),
    this.outputSampleInterval = const Duration(seconds: 1),
    Duration startGap = const Duration(seconds: 5),
  }) : resolver = RecordStreamResolver(sites),
       _sites = sites,
       inputs = inputs ?? RecordInputOpener() {
    scheduler = RecordScheduler(capacity: () => settings().maxTaskCount, minimumStartGap: startGap);
    _cacheTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_checkCache()));
  }

  /// FFmpeg.
  final FfmpegRunner ffmpeg;

  /// The recording directory.
  final RecordStorage storage;

  /// Current settings.
  final RecordSettings Function() settings;

  /// Stream selection.
  final RecordStreamResolver resolver;

  /// Input opening (relay).
  final RecordInputOpener inputs;

  /// CA bundle path for FFmpeg's HTTPS inputs, if the build needs one.
  final String? Function()? caFile;

  /// Bound of a live check.
  final Duration pollTimeout;

  /// Interval of the output measurement.
  final Duration outputSampleInterval;

  /// The queue.
  late final RecordScheduler scheduler;

  final LiveSite? Function(String platform) _sites;
  final Future<void> Function(String json)? _persist;
  final RecordKeepAlive? _keepAlive;
  final Future<bool> Function({required bool interactive})? _storageAccess;
  late final RecordMerger _merger = RecordMerger(ffmpeg);
  final _tasks = <RecordTask>[];
  final _runtime = <String, _Runtime>{};
  final _changes = StreamController<List<RecordTask>>.broadcast();
  final _notices = StreamController<RecordNotice>.broadcast();
  late final Timer _cacheTimer;
  Timer? _persistTimer;
  var _persistDirty = false;
  Future<void>? _persistInFlight;
  var _closing = false;
  var _cacheCheck = false;

  /// The tasks, in insertion and restore order.
  List<RecordTask> get tasks => List.unmodifiable(_tasks);

  /// The task list after every change.
  Stream<List<RecordTask>> get changes => _changes.stream;

  /// Messages for the user.
  Stream<RecordNotice> get notices => _notices.stream;

  /// Recordings running.
  int get runningCount => scheduler.runningCount;

  /// Recordings waiting for a slot.
  int get queuedCount => scheduler.queuedCount;

  _Runtime _rt(RecordTask task) => _runtime.putIfAbsent(task.taskId, _Runtime.new);

  bool _owns(RecordTask task) => !_closing && _tasks.any((candidate) => identical(candidate, task));

  void _update(RecordTask task, {bool persist = true}) {
    if (!_owns(task)) return;
    if (!_changes.isClosed) _changes.add(tasks);
    if (persist) _schedulePersist();
  }

  void _notice(RecordNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  Future<bool> _access({required bool interactive}) =>
      _storageAccess?.call(interactive: interactive) ?? Future.value(true);

  /// Adds a task for [room] (or returns the existing one) and starts it, or
  /// waits for the room to go live when not [startImmediately]. "Start now"
  /// does not check the card's cached state: the resolver decides.
  ///
  /// A new task takes the live room's own choices: [quality] and
  /// [recordDanmaku] instead of the settings' (`RecordTask.qualityOverride`,
  /// `recordDanmakuOverride`), and [autoRecord] (`RecordTask.autoRecord`).
  Future<RecordTask?> addTask(
    LiveRoom room, {
    bool startImmediately = true,
    String? quality,
    bool? recordDanmaku,
    bool? autoRecord,
  }) async {
    if (_closing || !await _access(interactive: true) || _closing) return null;
    final existing = _tasks.where((task) => task.roomId == room.roomId && task.platform == room.platform).firstOrNull;
    if (existing != null) return existing;
    final task = RecordTask.fromRoom(room, now: clock.now())
      ..qualityOverride = quality
      ..recordDanmakuOverride = recordDanmaku
      ..autoRecord = autoRecord;
    _tasks.add(task);
    _update(task);
    if (startImmediately) {
      await startTask(task);
    } else {
      task.status = RecordStatus.waitingLive;
      _update(task);
      _schedulePoll(task);
    }
    return _owns(task) && !_rt(task).removing ? task : null;
  }

  /// Sets [task]'s own choices (the live room's "这次录制" and "开播自动录"):
  /// the quality and chat of its next attempts, and whether it waits for the
  /// room again after a session. A null choice is left as it is; a running
  /// attempt keeps what it started with.
  void setTaskOptions(RecordTask task, {String? quality, bool? recordDanmaku, bool? autoRecord}) {
    if (!_owns(task)) return;
    if (quality != null) task.qualityOverride = quality;
    if (recordDanmaku != null) task.recordDanmakuOverride = recordDanmaku;
    if (autoRecord != null) task.autoRecord = autoRecord;
    _update(task);
  }

  /// Waits for [task]'s room to go live again (the live room's "开播自动录"
  /// turned on for a task that stopped, failed or finished; 3.x's "添加监控"
  /// for a room that has a task): the live checks resume. A task that is
  /// queued or recording keeps going and waits afterwards.
  Future<void> monitorTask(RecordTask task) async {
    if (!_owns(task) || _rt(task).removing) return;
    final rt = _rt(task);
    task.autoRecord = true;
    if (rt.starting || scheduler.isRunning(task.taskId) || scheduler.isQueued(task.taskId)) {
      _update(task);
      return;
    }
    await rt.stop;
    await rt.recovering;
    await rt.finalizing;
    if (!_owns(task) || rt.removing || task.status.isActive) return;
    task
      ..wasStoppedByUser = false
      ..autoReconnect = settings().autoReconnect
      ..retryCount = 0
      ..status = RecordStatus.waitingLive;
    _update(task);
    _schedulePoll(task);
  }

  /// Starts a new recording session of [task] (a user action): waits for a
  /// stop or join in progress, resets the session and queues it. True when
  /// the task did not fail.
  Future<bool> startTask(RecordTask task) {
    if (!_owns(task) || _rt(task).removing) return Future.value(false);
    final rt = _rt(task);
    return rt.start ??= _userStart(task).whenComplete(() => rt.start = null);
  }

  Future<bool> _userStart(RecordTask task) async {
    final rt = _rt(task);
    if (!await _access(interactive: true) || !_owns(task)) return false;
    await rt.stop;
    await rt.recovering;
    await rt.finalizing;
    if (!_owns(task) || rt.removing) return false;
    if (rt.starting || scheduler.isRunning(task.taskId) || scheduler.isQueued(task.taskId)) return true;
    task
      ..beginNewRecording(now: clock.now())
      ..retryCount = 0
      ..selectedQualityId = null
      ..selectedLineIndex = null
      ..wasStoppedByUser = false
      ..autoReconnect = settings().autoReconnect;
    rt
      ..base = (bytes: 0, seconds: 0)
      ..rapidRecovery = false
      ..prefetched = null
      ..qualityNoticed = false;
    _cancelLease(rt);
    await _start(task);
    return _owns(task) && task.status != RecordStatus.failed;
  }

  Future<void> _start(RecordTask task) async {
    final rt = _rt(task);
    if (!_owns(task) || task.wasStoppedByUser || rt.removing) return;
    await rt.recovering;
    await rt.stop;
    if (!_owns(task) || task.wasStoppedByUser || rt.removing) return;
    if (rt.starting) {
      _notice(RecordNotice(task, RecordNoticeKind.starting));
      return;
    }
    if (scheduler.isRunning(task.taskId) || scheduler.isQueued(task.taskId)) return;
    rt.starting = true;
    try {
      if (rt.keepAliveOwner == null) {
        final owner = Object();
        await _keepAlive?.acquire(owner);
        rt.keepAliveOwner = owner;
      }
      if (!_owns(task) || task.wasStoppedByUser || rt.removing) return;
      _stopPolling(rt);
      rt.retryTimer?.cancel();
      task.status = RecordStatus.queued;
      _update(task);
      scheduler.enqueue(task.taskId, (token) => _run(task, token));
    } on RecordKeepAliveException catch (error) {
      if (_owns(task) && !task.wasStoppedByUser) {
        task
          ..markFailure(stage: 'background', error: error.reason, now: clock.now())
          ..status = RecordStatus.failed;
        _update(task);
      }
    } on Object catch (error) {
      task
        ..markFailure(stage: 'scheduler', error: error, now: clock.now())
        ..status = RecordStatus.failed;
      _update(task);
    } finally {
      rt.starting = false;
      if (!scheduler.isRunning(task.taskId) && !scheduler.isQueued(task.taskId)) await _releaseKeepAlive(rt);
    }
  }

  Future<void> _releaseKeepAlive(_Runtime rt) async {
    final owner = rt.keepAliveOwner;
    if (owner == null) return;
    rt.keepAliveOwner = null;
    await flush();
    await _keepAlive?.release(owner);
  }

  Future<void> _run(RecordTask task, RecordCancelToken token) async {
    final rt = _rt(task);
    final previousUrl = task.currentUrl;
    rt.base = (bytes: task.fileSize, seconds: task.recordedSeconds);
    task
      ..beginNewAttempt(now: clock.now())
      ..outputDir = null
      ..status = RecordStatus.preparing;
    _update(task);
    final lifecycle = Completer<void>();
    rt.lifecycle = lifecycle;
    final discovery = LiveQualityDiscoveryScope();
    String? protectedDirectory;
    token.onCancel = () async {
      discovery.cancel();
      final capture = rt.capture;
      await Future.wait([discovery.close(), ?capture?.stop()]);
      if (capture == null && rt.finalizing == null) _completeLifecycle(rt);
    };
    try {
      if (token.isCancelled) return;
      final now = clock.now();
      final prefetched = rt.prefetched;
      rt.prefetched = null;
      final stream =
          rt.rapidRecovery &&
              prefetched != null &&
              prefetched.sourceUrl == previousUrl &&
              prefetched.stream.usableAt(now)
          ? prefetched.stream
          : await resolver.resolve(
              roomId: task.roomId,
              platform: task.platform,
              preferredQuality: task.preferredQuality(settings().defaultQuality),
              previousQualityId: task.selectedQualityId,
              previousLineIndex: task.selectedLineIndex,
              renewCurrent: rt.rapidRecovery,
              discovery: discovery,
            );
      if (token.isCancelled) return;
      final current = settings();
      final root = await storage.recordDirectory();
      final directory = attemptDirectory(
        root.path,
        platform: task.platform,
        nick: task.nick,
        now: clock.now(),
        pinyin: current.usePinyinForFolder,
      );
      await Directory(directory).create(recursive: true);
      protectedDirectory = directory;
      storage.protect(directory);
      final prefix = task.recordingFilePrefix;
      final reservation = await SegmentReservation.acquire(directory, prefix);
      final MediaInput input;
      try {
        final cuts = stream.line?.lease?.cutsConnection ?? false;
        input = await inputs.open(
          stream,
          site: task.platform,
          renew: cuts ? (line) => _renewLine(task, line) : null,
          onRenewed: (line) {
            if (_owns(task)) task.currentUrl = line.url;
          },
          cancel: discovery.cancelToken,
        );
      } on Object {
        reservation.release();
        rethrow;
      }
      task
        ..currentUrl = stream.line?.url
        ..selectedQuality = stream.qualityLabel
        ..selectedQualityId = stream.qualityCursorId
        ..selectedLineIndex = stream.lineIndex
        ..selectedLine = stream.lineLabel
        ..outputDir = directory;
      _update(task);
      if (token.isCancelled) {
        reservation.release();
        await input.close();
        return;
      }
      final arguments = FfmpegCommand.record(
        url: input.uri.toString(),
        headers: input.headers,
        proxyUrl: input.proxyUrl,
        caFile: caFile?.call(),
        outputDir: directory,
        filePrefix: prefix,
        segmentTime: current.segmentTime,
        preferBestStream: current.preferBestStream,
        rwTimeout: current.rwTimeout,
        threadQueueSize: current.threadQueueSize,
        separator: Platform.pathSeparator,
      );
      rt.capture = RecordCapture.start(
        runner: ffmpeg,
        input: input,
        arguments: arguments,
        reservation: reservation,
        onEvent: (event) => unawaited(_onCapture(task, event)),
      );
      if (stream.qualityLimited && !rt.qualityNoticed) {
        rt.qualityNoticed = true;
        _notice(RecordNotice(task, RecordNoticeKind.qualityLimited, quality: stream.qualityLabel));
      }
      _scheduleLeasePrefetch(task, stream);
      await lifecycle.future;
    } on RecordStreamException catch (error) {
      if (!token.isCancelled && _owns(task)) {
        task.markFailure(stage: error.stage, error: error.message, now: clock.now());
        if (error.type == RecordStreamErrorType.notLive && _endsAfterBroadcast(task)) {
          // The broadcast ended and the live room's "开播自动录" is off: the
          // session ends here instead of waiting for the next one.
          task.clearFailure();
          await _finalizing(rt, () => _closeSession(task, broadcastEnded: true));
        } else if (error.type == RecordStreamErrorType.notLive) {
          rt.rapidRecovery = false;
          task
            ..clearFailure()
            ..status = RecordStatus.waitingLive;
          _update(task);
          _schedulePoll(task);
        } else if (!error.retryable || !task.autoReconnect) {
          task.status = RecordStatus.failed;
          _update(task);
          _notice(RecordNotice(task, RecordNoticeKind.resolveFailed, streamError: error));
        } else {
          // A request that failed outright is the network, not the end of
          // the broadcast: it reconnects without using up the retries. A
          // platform that answers without a usable stream counts.
          final fast = rt.rapidRecovery;
          if (!_scheduleReconnect(task, fast: fast, counted: error.type != RecordStreamErrorType.networkError)) {
            await _finalizing(rt, () => _closeSession(task, broadcastEnded: fast));
          }
        }
      }
      _completeLifecycle(rt);
    } on Object catch (error) {
      if (!token.isCancelled && _owns(task)) {
        task.markFailure(stage: 'recorder', error: error, now: clock.now());
        if (task.autoReconnect) {
          final fast = rt.rapidRecovery;
          if (!_scheduleReconnect(task, fast: fast)) {
            await _finalizing(rt, () => _closeSession(task, broadcastEnded: fast));
          }
        } else {
          task.status = RecordStatus.failed;
          _update(task);
        }
      }
      _completeLifecycle(rt);
    } finally {
      await discovery.close();
      if (token.isCancelled && task.status != RecordStatus.stopped && _owns(task)) {
        task.status = RecordStatus.stopped;
        _update(task);
      }
      final capture = rt.capture;
      if (capture == null) _completeLifecycle(rt);
      await lifecycle.future;
      await capture?.done;
      if (identical(rt.lifecycle, lifecycle)) rt.lifecycle = null;
      if (identical(rt.capture, capture)) rt.capture = null;
      if (protectedDirectory != null) storage.release(protectedDirectory);
      if (rt.stop == null && (!_owns(task) || task.status != RecordStatus.reconnecting)) await _releaseKeepAlive(rt);
    }
  }

  Future<LivePlayLine> _renewLine(RecordTask task, LivePlayLine current) async {
    final discovery = LiveQualityDiscoveryScope();
    try {
      final renewed = await resolver.resolve(
        roomId: task.roomId,
        platform: task.platform,
        preferredQuality: task.preferredQuality(settings().defaultQuality),
        previousQualityId: task.selectedQualityId,
        previousLineIndex: task.selectedLineIndex,
        renewCurrent: true,
        discovery: discovery,
      );
      return renewed.line ?? (throw StateError('Renewal returned a recipe'));
    } finally {
      await discovery.close();
    }
  }

  void _completeLifecycle(_Runtime rt) {
    final lifecycle = rt.lifecycle;
    if (lifecycle != null && !lifecycle.isCompleted) lifecycle.complete();
  }

  Future<void> _onCapture(RecordTask task, CaptureEvent event) async {
    if (!_owns(task)) {
      // Closing or removed: only release the run waiting for this capture.
      final rt = _runtime[task.taskId];
      if (event is CaptureEnded && rt != null) _completeLifecycle(rt);
      return;
    }
    final rt = _rt(task);
    final now = clock.now();
    switch (event) {
      case CaptureAcknowledged(:final session):
        rt.session = session;
        task
          ..status = RecordStatus.preparing
          ..lastUpdate = now
          ..clearFailure();
        _startMonitor(task, rt);
        _update(task);
      case CaptureStarted(:final session):
        if (rt.session != session) return;
        task
          ..status = RecordStatus.running
          ..lastUpdate = now
          ..clearFailure();
        _update(task);
      case CaptureProgress(:final session, :final seconds, :final bytes, :final speed, :final fps):
        if (rt.session != session) return;
        final totalSeconds = rt.base.seconds + seconds;
        final totalBytes = rt.base.bytes + bytes;
        if (totalSeconds > task.recordedSeconds) task.recordedSeconds = totalSeconds;
        if (totalBytes > task.fileSize) task.fileSize = totalBytes;
        if (speed > 0) task.recordSpeed = speed;
        if (fps > 0) task.fps = fps;
        task
          ..status = RecordStatus.running
          ..lastUpdate = now;
        if (seconds >= 10) {
          task.retryCount = 0;
          rt.rapidRecovery = false;
        }
        _update(task, persist: _persistDue(rt, now));
      case CaptureCoverageGap(:final session):
        if (rt.session != session || task.inputCoverageIncomplete) return;
        task.inputCoverageIncomplete = true;
        _update(task);
      case final CaptureEnded ended:
        if (rt.session != null && rt.session != ended.session) return;
        _sampleOutput(task, rt);
        _stopMonitor(rt);
        _cancelLease(rt, keepPrefetched: true);
        rt.session = null;
        task
          ..inputCoverageIncomplete = task.inputCoverageIncomplete || ended.inputCoverageIncomplete
          ..lastUpdate = now;
        final manual = ended.manualStop || task.wasStoppedByUser;
        final failed = !ended.complete;
        final refresh = ended.refreshesSignedStream;
        if (refresh) rt.rapidRecovery = true;
        final fast = refresh || rt.rapidRecovery;
        final shouldRetry = ended.complete || ended.retryable;
        if (manual || !refresh || !shouldRetry) rt.prefetched = null;
        if (failed) {
          final kind = ended.kind?.name ?? 'native';
          final lastLine = ended.diagnostic.trim().split('\n').last.trim();
          task.markFailure(
            stage: 'ffmpeg.$kind',
            error: lastLine.isEmpty ? 'FFmpeg exit code ${ended.code}' : lastLine,
            now: now,
          );
          if (!ended.silent && (!shouldRetry || task.retryCount == 0)) {
            _notice(RecordNotice(task, RecordNoticeKind.captureFailed, failure: ended.kind));
          }
        }
        await _finalize(
          task,
          manual: manual,
          failed: failed,
          shouldRetry: shouldRetry,
          fast: fast,
          damaged: ended.inputIntegrityError,
        );
    }
  }

  bool _persistDue(_Runtime rt, DateTime now) {
    final last = rt.lastPersist;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) return false;
    rt.lastPersist = now;
    return true;
  }

  void _startMonitor(RecordTask task, _Runtime rt) {
    _stopMonitor(rt);
    final directory = task.outputDir;
    if (directory == null) return;
    rt
      ..meter = SegmentMeter(directory, task.recordingFilePrefix)
      ..bitrate = BitrateWindow()
      ..monitorStartedAt = null
      ..monitor = Timer.periodic(outputSampleInterval, (_) => _sampleOutput(task, rt));
  }

  void _stopMonitor(_Runtime rt) {
    rt.monitor?.cancel();
    rt
      ..monitor = null
      ..meter = null
      ..lastPersist = null;
  }

  void _sampleOutput(RecordTask task, _Runtime rt) {
    final meter = rt.meter;
    if (meter == null || !_owns(task)) return;
    final now = clock.now();
    final bytes = meter.sample();
    final capture = rt.capture;
    if (bytes <= 0 && !(capture?.mediaStarted ?? false)) return;
    final startedAt = rt.monitorStartedAt ??= now;
    final totalBytes = rt.base.bytes + bytes;
    if (totalBytes > task.fileSize) task.fileSize = totalBytes;
    final rate = rt.bitrate.add(bytes, now);
    if (rate != null) task.bitrate = rate;
    final seconds = math.max(now.difference(startedAt).inSeconds, capture?.recordedSeconds ?? 0);
    final totalSeconds = rt.base.seconds + seconds;
    if (totalSeconds > task.recordedSeconds) task.recordedSeconds = totalSeconds;
    if (task.recordSpeed <= 0) task.recordSpeed = 1;
    task
      ..status = RecordStatus.running
      ..lastUpdate = now;
    _update(task, persist: _persistDue(rt, now));
  }

  Future<void> _finalize(
    RecordTask task, {
    required bool manual,
    required bool failed,
    required bool shouldRetry,
    required bool fast,
    required bool damaged,
  }) {
    return _finalizing(
      _rt(task),
      () => _doFinalize(task, manual: manual, failed: failed, shouldRetry: shouldRetry, fast: fast, damaged: damaged),
    );
  }

  /// Runs [body] as the task's finalization (`_Runtime.finalizing`, which
  /// holds back starts, stops and live checks), or returns the one running.
  /// The future is stored before [body] starts: a body that finishes or
  /// starts another finalization synchronously can never leave it unset
  /// while it still works.
  Future<void> _finalizing(_Runtime rt, Future<void> Function() body) {
    final running = rt.finalizing;
    if (running != null) return running;
    final done = Completer<void>();
    final future = rt.finalizing = done.future;
    unawaited(() async {
      try {
        await body();
      } finally {
        if (identical(rt.finalizing, future)) rt.finalizing = null;
        done.complete();
      }
    }());
    return future;
  }

  Future<void> _doFinalize(
    RecordTask task, {
    required bool manual,
    required bool failed,
    required bool shouldRetry,
    required bool fast,
    required bool damaged,
  }) async {
    final rt = _rt(task);
    try {
      _queueCurrentAttempt(task, damaged: damaged);
      if (_closing) return;
      final stopped = manual || task.wasStoppedByUser;
      if (failed && shouldRetry && task.autoReconnect && !stopped) {
        // Reconnect first; joining waits until the session ends (3.x: a
        // 10–20 s join here left a hole at every short lease).
        if (_scheduleReconnect(task, fast: fast)) {
          _completeLifecycle(rt);
          return;
        }
        // Out of retries: the session ends here, joined before the run
        // (and its keep-alive) ends.
        await _closeSession(task, broadcastEnded: fast);
        return;
      }
      var merged = true;
      if (task.pendingAttempts.isNotEmpty) {
        task.status = RecordStatus.processing;
        _update(task);
        merged = await _mergePending(task);
        if (!_owns(task)) return;
      }
      if (!merged) {
        _markMergeFailure(task);
        task.status = RecordStatus.failed;
      } else if (stopped) {
        task.status = RecordStatus.stopped;
      } else if (failed) {
        task
          ..status = RecordStatus.failed
          ..retryCount = 0;
      } else if (task.autoReconnect) {
        task.status = RecordStatus.waitingLive;
        _update(task);
        _pollAfterRun(task, delay: const Duration(seconds: 1));
      } else {
        task.status = RecordStatus.completed;
      }
      _update(task);
    } on Object catch (error) {
      if (_owns(task)) {
        task
          ..markFailure(stage: 'merge', error: error, now: clock.now())
          ..status = RecordStatus.failed;
        _update(task);
      }
    } finally {
      _completeLifecycle(rt);
    }
  }

  /// Whether a session that recorded something ends with the broadcast
  /// instead of waiting for the next one (`RecordTask.autoRecord` off).
  bool _endsAfterBroadcast(RecordTask task) =>
      task.autoRecord == false && (task.recordedSeconds > 0 || task.pendingAttempts.isNotEmpty);

  /// Ends a session whose broadcast is over: the retries are used up or the
  /// room went offline ([broadcastEnded] for an offline room and for fast
  /// retries after live EOFs running out). The pending attempts are joined
  /// first; then a task that ends after the broadcast ([_endsAfterBroadcast])
  /// is completed ([broadcastEnded]) or failed, and any other waits for the
  /// room, checked again once this finalization is over. Runs inside
  /// [_finalizing].
  Future<void> _closeSession(RecordTask task, {required bool broadcastEnded}) async {
    final rt = _rt(task)..rapidRecovery = false;
    _cancelLease(rt);
    // Before the join empties the pending attempts.
    final ends = _endsAfterBroadcast(task);
    try {
      var merged = true;
      if (task.pendingAttempts.isNotEmpty) {
        task.status = RecordStatus.processing;
        _update(task);
        merged = await _mergePending(task);
        if (!_owns(task)) return;
      }
      if (!merged) {
        _markMergeFailure(task);
        task.status = RecordStatus.failed;
      } else if (ends && broadcastEnded) {
        task
          ..clearFailure()
          ..status = RecordStatus.completed
          ..retryCount = 0;
      } else if (ends) {
        task.status = RecordStatus.failed;
      } else {
        if (broadcastEnded) task.clearFailure();
        task.status = RecordStatus.waitingLive;
        _pollAfterRun(task);
      }
      _update(task);
    } on Object catch (error) {
      if (_owns(task)) {
        task
          ..markFailure(stage: 'merge', error: error, now: clock.now())
          ..status = RecordStatus.failed;
        _update(task);
      }
    }
  }

  /// Schedules [task]'s live check once its current run and finalization
  /// are over: both hold back [_schedulePoll] ([_canPoll]), so a check
  /// scheduled from inside them would never run.
  void _pollAfterRun(RecordTask task, {Duration? delay}) {
    final rt = _rt(task);
    unawaited(() async {
      await scheduler.waitFor(task.taskId);
      await rt.finalizing;
      if (_owns(task) && task.status == RecordStatus.waitingLive) _schedulePoll(task, delay: delay);
    }());
  }

  void _queueCurrentAttempt(RecordTask task, {bool allowLegacy = false, bool damaged = false}) {
    final directory = task.outputDir?.trim() ?? '';
    if (directory.isEmpty) return;
    final prefix = task.recordingFilePrefix;
    if (!SegmentMeter.hasSegments(directory, prefix, allowLegacy: allowLegacy)) return;
    task.queuePendingAttempt(directoryPath: directory, filePrefix: prefix, inputIntegrityError: damaged);
    _update(task);
  }

  /// Joins [task]'s attempts. [RecordTask.mergeProgress] follows the join,
  /// the attempts weighted by their source bytes; the interface hears of
  /// the first value and of each whole percent after it, never the store.
  Future<bool> _mergePending(RecordTask task, {bool allowLegacy = false}) async {
    final attempts = List.of(task.pendingAttempts);
    final sizes = [for (final attempt in attempts) SegmentMeter.measure(attempt.directoryPath, attempt.filePrefix)];
    final total = sizes.fold(0, (sum, size) => sum + size);
    var joined = 0.0;
    void progress(int index, double value) {
      final weight = total > 0 ? sizes[index] / total : 1 / attempts.length;
      if (value >= 1) joined += weight;
      final before = task.mergeProgress;
      final now = task.mergeProgress = (value >= 1 ? joined : joined + weight * value).clamp(0.0, 1.0);
      if (before == null || (now * 100).floor() != (before * 100).floor()) _update(task, persist: false);
    }

    try {
      return await _mergeAttempts(task, attempts, sizes, allowLegacy: allowLegacy, onProgress: progress);
    } finally {
      task.mergeProgress = null;
    }
  }

  Future<bool> _mergeAttempts(
    RecordTask task,
    List<PendingRecordingAttempt> attempts,
    List<int> sizes, {
    required bool allowLegacy,
    required void Function(int index, double progress) onProgress,
  }) async {
    var ok = true;
    for (final (index, attempt) in attempts.indexed) {
      if (!_owns(task)) return false;
      final sourceBytes = sizes[index];
      storage.protect(attempt.directoryPath);
      try {
        final result = await _merger.merge(
          directory: attempt.directoryPath,
          filePrefix: attempt.filePrefix,
          recordedSeconds: task.recordedSeconds,
          allowLegacy: allowLegacy,
          damaged: attempt.inputIntegrityError,
          cancelled: () => _closing,
          onProgress: (progress) => onProgress(index, progress),
        );
        if (!_owns(task)) return false;
        if (result.ok) {
          task.lastOutputPath = result.outputPath;
          final output = File(result.outputPath!);
          final finalized = output.existsSync() ? output.lengthSync() : 0;
          if (sourceBytes > 0 && finalized > 0) {
            task.fileSize = reconcileFinalizedBytes(
              totalBytes: task.fileSize,
              sourceBytes: sourceBytes,
              finalizedBytes: finalized,
            );
          }
          task.removePendingAttempt(attempt);
          _update(task);
        } else {
          ok = false;
        }
      } finally {
        storage.release(attempt.directoryPath);
      }
    }
    return ok;
  }

  void _markMergeFailure(RecordTask task) {
    final damaged = task.pendingAttempts.any((attempt) => attempt.inputIntegrityError);
    task.markFailure(
      stage: damaged ? 'ffmpeg.inputIntegrity' : 'merge',
      error: damaged ? 'Recorded input is damaged' : 'Joining the recording failed',
      now: clock.now(),
    );
  }

  /// Schedules the next attempt of [task] after a failure; false when the
  /// retries are used up, leaving the task to the caller ([_closeSession]).
  /// The count always rises (the card's "第 N 次"); a failure that is not
  /// [counted] (the network) never uses up the retries.
  bool _scheduleReconnect(RecordTask task, {bool fast = false, bool counted = true}) {
    if (!_owns(task) || task.wasStoppedByUser) return true;
    final rt = _rt(task);
    final current = settings();
    task.retryCount = (task.retryCount + 1).clamp(0, 1000);
    if (counted &&
        RecordPolicy.shouldEnterPollingAfterRetryLimit(
          retryCount: task.retryCount,
          maximumRetries: current.maxRetryCount,
          unexpectedEof: fast,
        )) {
      return false;
    }
    rt.retryTimer?.cancel();
    final delay = RecordPolicy.reconnectDelay(
      failureCount: task.retryCount - 1,
      configuredBaseSeconds: current.retryDelay,
      configuredMaximumSeconds: current.maxCheckInterval,
      enableBackoff: current.enableBackoff,
      unexpectedEof: fast,
    );
    task
      ..status = RecordStatus.reconnecting
      ..nextRetryAt = clock.now().add(delay);
    _update(task);
    rt.retryTimer = Timer(delay, () {
      rt.retryTimer = null;
      task.nextRetryAt = null;
      if (_owns(task) && !task.wasStoppedByUser) unawaited(_start(task));
    });
    return true;
  }

  void _scheduleLeasePrefetch(RecordTask task, ResolvedRecordStream stream, {Duration? delay}) {
    final rt = _rt(task);
    final lease = stream.line?.lease;
    final sourceUrl = task.currentUrl;
    // A lease that cuts the connection is renewed inside the relay.
    if (lease == null || lease.cutsConnection || sourceUrl == null) return;
    rt.leaseTimer?.cancel();
    final wait = delay ?? RecordPolicy.leasePrefetchDelay(now: clock.now(), refreshAt: lease.refreshAt);
    rt.leaseTimer = Timer(wait, () => unawaited(_prefetchLease(task, sourceUrl)));
  }

  Future<void> _prefetchLease(RecordTask task, String sourceUrl) async {
    final rt = _rt(task)..leaseTimer = null;
    bool owns() => _owns(task) && !task.wasStoppedByUser && task.currentUrl == sourceUrl && rt.capture != null;
    if (!owns()) return;
    final discovery = LiveQualityDiscoveryScope();
    DateTime? next;
    try {
      final renewed = await resolver.resolve(
        roomId: task.roomId,
        platform: task.platform,
        preferredQuality: task.preferredQuality(settings().defaultQuality),
        previousQualityId: task.selectedQualityId,
        previousLineIndex: task.selectedLineIndex,
        renewCurrent: true,
        discovery: discovery,
      );
      if (!owns() || !renewed.usableAt(clock.now())) return;
      rt.prefetched = (sourceUrl: sourceUrl, stream: renewed);
      next = renewed.refreshAt;
    } on Object {
      // Opportunistic: a failure never touches the healthy capture.
    } finally {
      await discovery.close();
    }
    if (!owns()) return;
    final wait = RecordPolicy.leaseMaintenanceDelay(now: clock.now(), refreshAt: next);
    rt.leaseTimer = Timer(wait, () => unawaited(_prefetchLease(task, sourceUrl)));
  }

  void _cancelLease(_Runtime rt, {bool keepPrefetched = false}) {
    rt.leaseTimer?.cancel();
    rt.leaseTimer = null;
    if (!keepPrefetched) rt.prefetched = null;
  }

  /// Stops [task] (a user action): cancels its run, waits for FFmpeg and any
  /// join, then joins the pending attempts.
  Future<void> stopTask(RecordTask task) {
    if (!_owns(task)) return Future.value();
    final rt = _rt(task);
    task
      ..wasStoppedByUser = true
      ..nextRetryAt = null;
    _stopPolling(rt);
    rt.retryTimer?.cancel();
    _cancelLease(rt);
    return rt.stop ??= _userStop(task).whenComplete(() => rt.stop = null);
  }

  Future<void> _userStop(RecordTask task) async {
    final rt = _rt(task);
    await scheduler.cancel(task.taskId);
    await scheduler.waitFor(task.taskId);
    await rt.recovering;
    await rt.finalizing;
    if (!_owns(task)) return;
    _stopMonitor(rt);
    rt
      ..base = (bytes: 0, seconds: 0)
      ..rapidRecovery = false;
    if (task.pendingAttempts.isNotEmpty) {
      task.status = RecordStatus.processing;
      _update(task);
      final merged = await _mergePending(task);
      if (!_owns(task)) return;
      task.status = merged ? RecordStatus.stopped : RecordStatus.failed;
      if (!merged) _markMergeFailure(task);
    } else {
      task.status = RecordStatus.stopped;
    }
    _update(task);
    await _releaseKeepAlive(rt);
  }

  /// The platform ended the keep-alive (Android's foreground-service time
  /// limit): every task holding it stops and fails with [reason] (3.x
  /// `_onBackgroundInterrupted`).
  Future<void> keepAliveInterrupted(String reason) async {
    final affected = [
      for (final task in _tasks)
        if (_rt(task).keepAliveOwner != null) task,
    ];
    await Future.wait(
      affected.map((task) async {
        await stopTask(task);
        if (!_owns(task)) return;
        task
          ..markFailure(stage: 'background', error: reason, now: clock.now())
          ..status = RecordStatus.failed;
        _update(task);
      }),
    );
    await flush();
  }

  /// Stops and removes [task].
  Future<void> removeTask(RecordTask task) async {
    if (!_owns(task)) return;
    final rt = _rt(task)..removing = true;
    try {
      await stopTask(task);
      if (!_owns(task)) return;
      _tasks.removeWhere((candidate) => identical(candidate, task));
      _runtime.remove(task.taskId);
      if (!_changes.isClosed) _changes.add(tasks);
      _schedulePersist();
    } finally {
      rt.removing = false;
    }
  }

  bool _canPoll(RecordTask task) {
    final rt = _rt(task);
    return _owns(task) &&
        !task.wasStoppedByUser &&
        !rt.starting &&
        rt.start == null &&
        rt.stop == null &&
        rt.recovering == null &&
        !rt.removing &&
        rt.finalizing == null &&
        !scheduler.isRunning(task.taskId) &&
        !scheduler.isQueued(task.taskId);
  }

  void _schedulePoll(RecordTask task, {Duration? delay}) {
    final current = settings();
    if (!current.enablePolling || !_canPoll(task)) return;
    final rt = _rt(task);
    rt.pollTimer?.cancel();
    final wait =
        delay ??
        RecordPolicy.pollingDelay(
          failureCount: rt.pollFailures,
          baseSeconds: current.liveCheckInterval,
          maximumSeconds: current.maxCheckInterval,
          enableBackoff: current.enableBackoff,
        );
    late final Timer timer;
    timer = Timer(wait, () {
      if (!identical(rt.pollTimer, timer)) return;
      rt.pollTimer = null;
      unawaited(_poll(task, automatic: true));
    });
    rt.pollTimer = timer;
  }

  void _stopPolling(_Runtime rt) {
    rt.pollTimer?.cancel();
    rt
      ..pollTimer = null
      ..pollFailures = 0
      ..poll = null;
  }

  Future<void> _poll(RecordTask task, {bool automatic = false}) {
    if (!_canPoll(task) || (automatic && !settings().enablePolling)) return Future.value();
    final rt = _rt(task);
    final existing = rt.poll;
    if (existing != null) return existing;
    rt.pollAutomatic = automatic;
    late final Future<void> poll;
    poll = _doPoll(task, () => identical(rt.poll, poll)).whenComplete(() {
      if (identical(rt.poll, poll)) {
        rt.poll = null;
        _schedulePoll(task);
      }
    });
    return rt.poll = poll;
  }

  Future<void> _doPoll(RecordTask task, bool Function() current) async {
    final rt = _rt(task);
    bool owns() => current() && _canPoll(task) && (!rt.pollAutomatic || settings().enablePolling);
    try {
      final site = _sites(task.platform);
      if (site == null) throw StateError('Unsupported live site: ${task.platform}');
      final room =
          await (site is LiveSiteRoomRefresher
                  ? (site as LiveSiteRoomRefresher).getRoomDetailForRefresh(roomId: task.roomId)
                  : site.getRoomDetail(roomId: task.roomId))
              .timeout(pollTimeout);
      if (!owns()) return;
      task
        ..updateFromRoom(room)
        ..lastLiveCheckAt = clock.now();
      _update(task);
      if (room.isPlayableNow) {
        rt
          ..pollFailures = 0
          ..qualityNoticed = false
          ..poll = null;
        task.retryCount = 0;
        await _start(task);
        return;
      }
      task.status = RecordStatus.waitingLive;
      _update(task);
      rt.pollFailures++;
    } on Object catch (error) {
      if (!owns()) return;
      rt.pollFailures++;
      task
        ..lastLiveCheckAt = clock.now()
        ..markFailure(stage: 'status', error: error, now: clock.now());
      _update(task);
    }
  }

  /// Checks [task]'s room now (the recording centre's refresh), starting it
  /// when live.
  Future<void> refreshTaskStatus(RecordTask task) async {
    if (!_canPoll(task)) return;
    final rt = _rt(task);
    rt.pollTimer?.cancel();
    rt
      ..pollTimer = null
      ..pollFailures = 0;
    await _poll(task);
  }

  /// Applies changed settings: polling switched off cancels the timers,
  /// switched on checks every waiting task now (3.x's `enablePolling`
  /// worker).
  void settingsChanged() {
    if (_closing) return;
    final enabled = settings().enablePolling;
    for (final task in _tasks) {
      final rt = _rt(task);
      if (!enabled) {
        rt.pollTimer?.cancel();
        rt.pollTimer = null;
        if (rt.pollAutomatic) rt.poll = null;
      } else if (task.status == RecordStatus.waitingLive) {
        _schedulePoll(task, delay: Duration.zero);
      }
    }
  }

  Future<void> _checkCache() async {
    final current = settings();
    if (_cacheCheck || !current.enableCacheLimit || _closing) return;
    _cacheCheck = true;
    try {
      if (await storage.sizeMB() > current.maxCacheMB) await storage.enforceLimit(maxMB: current.maxCacheMB.toDouble());
    } on Object {
      // Retried at the next check.
    } finally {
      _cacheCheck = false;
    }
  }

  /// Restores the task list from [json] (3.x's `recorder_tasks`): tasks
  /// that were recording are stopped and their segments joined (a killed
  /// process never ran FFmpeg's completion), and with "auto start on boot"
  /// the waiting and interrupted tasks check their rooms again, three at a
  /// time.
  Future<void> restore(String? json) async {
    if (_closing || json == null || json.trim().isEmpty) return;
    final restored = <RecordTask>[];
    final interrupted = <String>{};
    final resume = <String>{};
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          try {
            final task = RecordTask.fromJson(Map<String, Object?>.from(entry));
            if (task.roomId.trim().isEmpty || _sites(task.platform) == null) continue;
            if (restored.any((candidate) => candidate.taskId == task.taskId)) continue;
            if (_tasks.any((candidate) => candidate.taskId == task.taskId)) continue;
            if (const {
              RecordStatus.preparing,
              RecordStatus.running,
              RecordStatus.reconnecting,
              RecordStatus.processing,
            }.contains(task.status)) {
              interrupted.add(task.taskId);
            }
            if (!task.wasStoppedByUser &&
                const {
                  RecordStatus.queued,
                  RecordStatus.preparing,
                  RecordStatus.running,
                  RecordStatus.reconnecting,
                  RecordStatus.waitingLive,
                }.contains(task.status)) {
              resume.add(task.taskId);
            }
            if (!task.status.isFinished) task.status = RecordStatus.stopped;
            restored.add(task);
          } on Object {
            // A malformed task is skipped.
          }
        }
      }
    } on FormatException {
      return;
    }
    restored.sort((left, right) => left.status.order.compareTo(right.status.order));
    final recovering = <RecordTask, Completer<void>>{
      for (final task in restored)
        if (interrupted.contains(task.taskId) || task.pendingAttempts.isNotEmpty) task: Completer<void>(),
    };
    for (final MapEntry(key: task, value: completer) in recovering.entries) {
      _rt(task).recovering = completer.future;
    }
    _tasks.addAll(restored);
    if (!_changes.isClosed) _changes.add(tasks);
    _schedulePersist();
    for (final MapEntry(key: task, value: completer) in recovering.entries) {
      try {
        if (_owns(task)) await _recover(task);
      } on Object catch (error) {
        if (_owns(task)) {
          task
            ..markFailure(stage: 'merge', error: error, now: clock.now())
            ..status = RecordStatus.failed;
          _update(task);
        }
      } finally {
        _rt(task).recovering = null;
        completer.complete();
      }
    }
    if (_closing || !settings().autoStartOnBoot || resume.isEmpty) return;
    if (!await _access(interactive: false) || _closing) return;
    final candidates = [
      for (final task in restored)
        if (resume.contains(task.taskId)) task,
    ];
    var next = 0;
    Future<void> worker() async {
      while (!_closing && settings().autoStartOnBoot && next < candidates.length) {
        final task = candidates[next++];
        if (!_canPoll(task)) continue;
        task.status = RecordStatus.waitingLive;
        _update(task);
        await refreshTaskStatus(task);
      }
    }

    await Future.wait(List.generate(math.min(3, candidates.length), (_) => worker()));
  }

  Future<void> _recover(RecordTask task) async {
    _queueCurrentAttempt(task, allowLegacy: true);
    if (!_owns(task) || task.pendingAttempts.isEmpty) return;
    task.status = RecordStatus.processing;
    _update(task);
    final merged = await _mergePending(task, allowLegacy: true);
    if (!_owns(task)) return;
    task.status = merged ? RecordStatus.stopped : RecordStatus.failed;
    if (!merged) _markMergeFailure(task);
    _update(task);
  }

  /// The task list as 3.x JSON.
  String toJson() => jsonEncode([for (final task in _tasks) task.toJson()]);

  void _schedulePersist() {
    _persistDirty = true;
    if (_closing || (_persistTimer?.isActive ?? false)) return;
    _persistTimer = Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      unawaited(flush());
    });
  }

  /// Writes pending changes now and waits for every write in flight.
  Future<void> flush() async {
    while (true) {
      final inFlight = _persistInFlight;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      if (!_persistDirty) return;
      _persistDirty = false;
      final write = _persist?.call(toJson()).catchError((Object _) {}) ?? Future<void>.value();
      _persistInFlight = write;
      try {
        await write;
      } finally {
        if (identical(_persistInFlight, write)) _persistInFlight = null;
      }
    }
  }

  /// Stops every task's work (not marking it user-stopped, so a restore
  /// resumes it), writes the list and closes the streams.
  Future<void> dispose() async {
    if (_closing) return;
    _persistTimer?.cancel();
    _persistTimer = null;
    _cacheTimer.cancel();
    final snapshot = toJson();
    _closing = true;
    for (final rt in _runtime.values) {
      rt.pollTimer?.cancel();
      rt.retryTimer?.cancel();
      rt.leaseTimer?.cancel();
      rt.monitor?.cancel();
    }
    await scheduler.clear();
    await Future.wait([for (final rt in _runtime.values) ?rt.finalizing]);
    for (final rt in _runtime.values) {
      _completeLifecycle(rt);
      await _releaseKeepAlive(rt);
    }
    await _persist?.call(snapshot).catchError((Object _) {});
    await inputs.close();
    await _changes.close();
    await _notices.close();
  }
}
