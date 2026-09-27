import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/chat.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/flv/flv_writer.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/recovery.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/retry.dart';
import 'package:live_record/src/rooms.dart';
import 'package:live_record/src/session.dart';
import 'package:live_record/src/settings.dart';
import 'package:live_record/src/storage.dart';
import 'package:live_record/src/store.dart';
import 'package:live_record/src/task.dart';
import 'package:path/path.dart' as p;

/// Timings of the manager; defaults follow the spec.
final class RecordManagerTimings {
  /// Creates the timings.
  const new({
    this.startSpacing = const Duration(seconds: 5),
    this.stateDebounce = const Duration(seconds: 2),
    this.progressPersist = const Duration(seconds: 10),
    this.progressInterval = const Duration(seconds: 1),
    this.checkTimeout = const Duration(seconds: 20),
    this.chatRetry = const Duration(seconds: 30),
    this.resumeChecks = 3,
    this.storageCheck = const Duration(minutes: 1),
  });

  /// Least time between two session starts (§11.3).
  final Duration startSpacing;

  /// State changes are written together after this (§13).
  final Duration stateDebounce;

  /// Progress snapshots are written at most this often (§13).
  final Duration progressPersist;

  /// Progress is pushed at most this often per task (§19).
  final Duration progressInterval;

  /// Limit of one waiting-for-live check.
  final Duration checkTimeout;

  /// Wait before reconnecting a failed chat (§17).
  final Duration chatRetry;

  /// Strict checks running at once when resuming on launch (§14.2).
  final int resumeChecks;

  /// Interval of the storage limit check while it is on (§15).
  final Duration storageCheck;
}

final class _Runtime {
  new(this.task);

  RecordTask task;
  final controller = StreamController<RecordTask>.broadcast(sync: true);
  Future<void> intents = Future.value();
  int generation = 0;
  RecordSession? session;
  Future<void>? running;
  StopCause? stopCause;
  bool remuxOnStop = true;
  bool interrupted = false;
  Timer? pollTimer;
  Future<void>? polling;
  int pollRounds = 0;
  Timer? progressTimer;
  StreamSubscription<RecordChatMessage>? chat;
  Timer? chatRetry;
  bool removed = false;

  void stopChat() {
    chatRetry?.cancel();
    chatRetry = null;
    unawaited(chat?.cancel());
    chat = null;
  }
}

final class _Waiter {
  new(this.runtime, this.generation);

  final _Runtime runtime;
  final int generation;
  final done = Completer<bool>();
}

/// Concurrency slots with FIFO queueing and spacing between starts (§11.1–§11.3).
final class _Slots {
  new(this.max, this.spacing);

  int max;
  final Duration spacing;
  int used = 0;
  DateTime? _lastGrant;
  final _queue = ListQueue<_Waiter>();
  Timer? _timer;

  /// Waits for a slot; [force] takes one at once, beyond [max] and the
  /// spacing (the user's "force start", spec §2).
  Future<bool> acquire(_Runtime runtime, {bool force = false}) {
    if (force) {
      _grantNow();
      return Future.value(true);
    }
    final waiter = _Waiter(runtime, runtime.generation);
    _queue.add(waiter);
    _pump();
    return waiter.done.future;
  }

  /// Grants the queued request of [runtime] at once (spec §2 "强制开始");
  /// false when it is not queued.
  bool force(_Runtime runtime) {
    final waiter = _queue
        .where((w) => identical(w.runtime, runtime) && w.generation == runtime.generation && !w.done.isCompleted)
        .firstOrNull;
    if (waiter == null) return false;
    _queue.remove(waiter);
    _grantNow();
    waiter.done.complete(true);
    _pump();
    return true;
  }

  void _grantNow() {
    used++;
    _lastGrant = clock.now();
  }

  void cancel(_Runtime runtime) {
    _queue.removeWhere((waiter) {
      if (!identical(waiter.runtime, runtime)) return false;
      if (!waiter.done.isCompleted) waiter.done.complete(false);
      return true;
    });
    _pump();
  }

  void release() {
    if (used > 0) used--;
    _pump();
  }

  void _pump() {
    _queue.removeWhere((waiter) {
      final stale = waiter.runtime.generation != waiter.generation || waiter.runtime.removed;
      if (stale && !waiter.done.isCompleted) waiter.done.complete(false);
      return stale;
    });
    if (_queue.isEmpty || used >= max || _timer != null) return;
    final last = _lastGrant;
    if (last != null) {
      final wait = last.add(spacing).difference(clock.now());
      if (wait > Duration.zero) {
        _timer = Timer(wait, () {
          _timer = null;
          _pump();
        });
        return;
      }
    }
    final waiter = _queue.removeFirst();
    used++;
    _lastGrant = clock.now();
    waiter.done.complete(true);
    _pump();
  }

  void dispose() {
    _timer?.cancel();
    for (final waiter in _queue) {
      if (!waiter.done.isCompleted) waiter.done.complete(false);
    }
    _queue.clear();
  }
}

/// Runs the recording tasks (spec §2, §3, §11–§14, §17).
///
/// One task per room, keyed by `RoomRef.key`, listed in the order added.
/// User intents on one task run one after another; asynchronous results of
/// an older generation are dropped. Sessions take one of `maxConcurrent`
/// slots from resolving until finalizing, first come first served, at least
/// 5 s apart. Tasks persist through a [RecordTaskStore]: state changes after
/// 2 s, progress at most every 10 s, final states at once.
final class RecordManager {
  /// Creates a manager writing under [root] (see `RecordRoot.resolve`).
  ///
  /// `rooms` gives strict room checks and stream sets (`SiteRecordRooms` over
  /// the live_core adapters); `store` persists tasks; `opener` connects
  /// upstream FLV (default: `httpRecordOpener` with `record.readTimeout`);
  /// `remuxer` converts finished segments to MP4 when `record.remuxToMp4` is
  /// on (none: the sources stay FLV); `chat` supplies chat when
  /// `record.danmaku` is on; `files` is the file system (tests pass
  /// `MemoryRecordFiles`); `transliterate` turns streamer names into pinyin
  /// folder names when `record.pinyinFolders` is on.
  new({
    required this._rooms,
    required this._store,
    required this.root,
    RecordSettings settings = const RecordSettings(),
    this._files = const IoRecordFiles(),
    this._opener,
    this._remuxer,
    this._chat,
    this.spliceTimings = const SpliceTimings(),
    this.writerLimits = const FlvWriterLimits(),
    this.timings = const RecordManagerTimings(),
    this._transliterate,
  }) : _settings = settings.clamped(),
       _slots = _Slots(settings.clamped().maxConcurrent, timings.startSpacing);

  /// Recording root.
  final String root;

  /// Splice limits for sessions.
  final SpliceTimings spliceTimings;

  /// Writer limits for sessions.
  final FlvWriterLimits writerLimits;

  /// Manager timings.
  final RecordManagerTimings timings;

  final RecordRooms _rooms;
  final RecordTaskStore _store;
  final RecordFiles _files;
  RecordSettings _settings;
  final RecordOpener? _opener;
  final Remuxer? _remuxer;
  final RecordChatSource? _chat;
  final String Function(String)? _transliterate;
  final _Slots _slots;

  final _runtimes = <String, _Runtime>{};
  final _order = <String>[];
  final _list = StreamController<List<RecordTask>>.broadcast();
  final _updates = StreamController<RecordTask>.broadcast(sync: true);
  final _active = StreamController<int>.broadcast();
  var _activeCount = 0;
  Future<void> _remuxing = Future.value();
  final _dirty = <String>{};
  Timer? _persistTimer;
  DateTime? _persistDue;
  Future<void> _persisting = Future.value();
  Future<void>? _recovered;
  var _disposed = false;
  Timer? _storageTimer;
  Future<StorageSweep?>? _sweeping;

  /// Settings in force.
  RecordSettings get settings => _settings;

  /// Tasks in the order they were added (stable; REG-RECORD-039).
  List<RecordTask> get tasks => [for (final key in _order) _runtimes[key]!.task];

  /// The task of [key], if any.
  RecordTask? task(String key) => _runtimes[key]?.task;

  /// Emits the task list when tasks are added or removed.
  Stream<List<RecordTask>> get listChanges => _list.stream;

  /// Every task snapshot as it changes (state at once, progress at most once a second).
  Stream<RecordTask> get updates => _updates.stream;

  /// Snapshots of one task: the current one first, then each change.
  Stream<RecordTask> watch(String key) async* {
    final runtime = _runtimes[key];
    if (runtime == null) return;
    yield runtime.task;
    yield* runtime.controller.stream;
  }

  /// Tasks that hold a session (queued through finalizing): the Android
  /// recording service runs while this is above 0 (§16.1).
  int get activeCount => _activeCount;

  /// Changes of [activeCount].
  Stream<int> get activeCountChanges => _active.stream;

  /// Completes when crash recovery and resume-on-launch are done (§14).
  Future<void> get recovered => _recovered ?? Future.value();

  /// Loads the stored tasks, then recovers and resumes them in the
  /// background (§14.1 on every launch, §14.2 when `resumeOnLaunch`). User
  /// intents on a recovering task wait for its recovery.
  Future<void> init() async {
    if (_recovered != null) throw StateError('init runs once');
    final loaded = await _store.load()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final task in loaded) {
      if (_runtimes.containsKey(task.key)) continue;
      _runtimes[task.key] = _Runtime(task);
      _order.add(task.key);
    }
    _list.add(tasks);
    _scheduleStorage();
    // Tasks that were active or waiting when the app last ended: crashed
    // ones (still active in the store) or ones stopped by [stopAll] on exit.
    final candidates = <_Runtime>[];
    final recoveries = <Future<void>>[];
    for (final runtime in _runtimes.values) {
      final task = runtime.task;
      final state = task.state;
      if (state.active || state == RecordState.waitingLive || task.stopCause == StopCause.appRestart) {
        candidates.add(runtime);
      }
      if (state.active) {
        recoveries.add(_serial(runtime, () => _recover(runtime)));
      } else if (state == RecordState.waitingLive) {
        _update(runtime, task.copyWith(state: RecordState.stopped, stopCause: StopCause.appRestart));
      } else if (task.stopCause == StopCause.appRestart) {
        recoveries.add(_serial(runtime, () => _remuxAfterExit(runtime)));
      }
    }
    _recovered = () async {
      await Future.wait(recoveries);
      final resumable = [
        for (final runtime in candidates)
          if (runtime.task.state == RecordState.stopped && runtime.task.stopCause == StopCause.appRestart) runtime,
      ];
      if (_settings.resumeOnLaunch) {
        if (resumable.isNotEmpty) await _resume(resumable);
      } else {
        // Not resumed now, so not at a later launch either.
        for (final runtime in resumable) {
          await _serial(runtime, () async {
            if (runtime.task.stopCause == StopCause.appRestart) {
              _update(runtime, runtime.task.copyWith(stopCause: null));
            }
          });
        }
      }
      await _flush();
    }();
  }

  /// Adds a task for [room] (or refreshes the existing one's display fields)
  /// and starts it when [start]; otherwise it waits for the room to go live
  /// (polling on) or stays stopped until polling is switched on (§12).
  Future<RecordTask> add(RoomDetail room, {RecordQuality? quality, bool start = true}) async {
    _checkAlive();
    final key = room.ref.key;
    var runtime = _runtimes[key];
    if (runtime == null) {
      runtime = _Runtime(
        RecordTask(
          room: room.ref,
          createdAt: clock.now(),
          state: RecordState.stopped,
          stopCause: StopCause.pollingOff,
          snapshot: RecordRoomSnapshot.of(room),
          quality: quality,
          autoReconnect: _settings.autoReconnect,
        ),
      );
      _runtimes[key] = runtime;
      _order.add(key);
      _list.add(tasks);
      _markDirty(runtime);
      if (!start && _settings.polling) {
        final added = runtime;
        await _serial(added, () async => _wait(added));
      }
    } else {
      _update(runtime, runtime.task.copyWith(snapshot: RecordRoomSnapshot.of(room), quality: quality));
    }
    if (start) await this.start(key);
    return runtime.task;
  }

  /// Starts recording [key] now: the strict check decides whether the room
  /// is live (REG-RECORD-038). Waits for an earlier stop, recovery or
  /// finalisation of the same task; clears counters, cursor and failure.
  Future<void> start(String key) {
    _checkAlive();
    final runtime = _runtimes[key];
    if (runtime == null) return Future.value();
    return _serial(runtime, () => _begin(runtime));
  }

  /// Starts [key] at once, without waiting for a concurrency slot or the
  /// 5 s start spacing (spec §2 "强制开始", §11.1): a queued task takes an
  /// extra slot now, a waiting one starts its session now. The strict room
  /// check still decides whether the room is live; offline goes back to
  /// waiting (polling on). Other states behave like [start].
  Future<void> forceStart(String key) {
    _checkAlive();
    final runtime = _runtimes[key];
    if (runtime == null) return Future.value();
    return _serial(runtime, () async {
      if (runtime.task.state == RecordState.queued && runtime.running != null) {
        _slots.force(runtime);
        return;
      }
      await _begin(runtime, force: true);
    });
  }

  Future<void> _begin(_Runtime runtime, {bool force = false}) async {
    // Already recording: nothing to do. Finalising: wait for it to finish.
    if (runtime.running != null && runtime.task.state != RecordState.finalizing) return;
    await runtime.running;
    if (runtime.removed) return;
    _cancelPoll(runtime);
    runtime
      ..generation += 1
      ..pollRounds = 0;
    _update(
      runtime,
      runtime.task.copyWith(
        state: RecordState.queued,
        cursor: null,
        failure: null,
        stopCause: null,
        retrying: null,
        nextCheckAt: null,
        autoReconnect: _settings.autoReconnect,
      ),
    );
    _launch(runtime, force: force);
  }

  /// Stops [key] as the user asked; completes when its files are final
  /// (remux included). Files already written are kept.
  Future<void> stop(String key) {
    final runtime = _runtimes[key];
    if (runtime == null) return Future.value();
    return _serial(runtime, () => _stop(runtime, StopCause.user));
  }

  /// Stops [key] like [stop], then removes the task (files and their records stay).
  Future<void> remove(String key) {
    final runtime = _runtimes[key];
    if (runtime == null) return Future.value();
    return _serial(runtime, () async {
      await _stop(runtime, StopCause.user);
      runtime.removed = true;
      _cancelPoll(runtime);
      _runtimes.remove(key);
      _order.remove(key);
      _dirty.remove(key);
      await _persisting;
      await _store.remove(key);
      await runtime.controller.close();
      _list.add(tasks);
    });
  }

  /// Checks a waiting room now (manual refresh; merged with a running check).
  Future<void> checkNow(String key) {
    final runtime = _runtimes[key];
    if (runtime == null || runtime.task.state != RecordState.waitingLive) return Future.value();
    return _poll(runtime, runtime.generation);
  }

  /// Retries the remux of a task that failed with `remuxFailed`; the kept
  /// sources are converted again.
  Future<void> retryRemux(String key) {
    final runtime = _runtimes[key];
    if (runtime == null) return Future.value();
    return _serial(runtime, () async {
      final task = runtime.task;
      final session = task.session;
      if (task.state != RecordState.failed || task.failure?.kind != RecordErrorKind.remuxFailed || session == null) {
        return;
      }
      _update(runtime, task.copyWith(state: RecordState.finalizing, failure: null, remuxProgress: 0.0));
      final (outputs, failure) = await _remux(runtime, session.segments);
      _update(
        runtime,
        runtime.task.copyWith(
          state: failure == null ? RecordState.completed : RecordState.failed,
          failure: failure,
          remuxProgress: null,
          session: session.copyWith(outputs: [...session.outputs, ...outputs]),
        ),
      );
      await _flush();
    });
  }

  /// Replaces the task list with [imported] from a backup (store.md §7.2
  /// `recordTasks`, spec/modules/record.md §13). Tasks holding a session
  /// (queued through finalizing) are left as they are, whether or not the
  /// backup has them; other local tasks missing from [imported] are removed
  /// (their files stay). An imported task replaces a local one of the same
  /// room, keeping the local session info (its files are on this device).
  /// Imported tasks come in stopped: [StopCause.pollingOff] ones wait for
  /// their room while polling is on (§12), others stay stopped. Returns the
  /// number of tasks written.
  Future<int> importTasks(Iterable<RecordTask> imported) async {
    _checkAlive();
    final incoming = <String, RecordTask>{for (final task in imported) task.key: task};
    for (final runtime in _runtimes.values.toList()) {
      if (!incoming.containsKey(runtime.task.key) && !runtime.task.state.active) await remove(runtime.task.key);
    }
    var written = 0;
    for (final task in incoming.values) {
      final restored = task.copyWith(
        state: RecordState.stopped,
        stopCause: task.stopCause == StopCause.pollingOff ? StopCause.pollingOff : StopCause.user,
        failure: null,
        cursor: null,
        retrying: null,
        nextCheckAt: null,
      );
      var runtime = _runtimes[task.key];
      if (runtime == null) {
        runtime = _Runtime(restored.copyWith(session: null));
        _runtimes[task.key] = runtime;
        _order.add(task.key);
        _markDirty(runtime);
      } else {
        final local = runtime;
        var skipped = false;
        await _serial(local, () async {
          if (local.task.state.active || local.removed) {
            skipped = true;
            return;
          }
          _cancelPoll(local);
          local.generation++;
          _update(local, restored.copyWith(session: local.task.session));
        });
        if (skipped) continue;
      }
      written++;
      if (_settings.polling && runtime.task.stopCause == StopCause.pollingOff) {
        final waiting = runtime;
        // The first check follows `liveCheckInterval`, not all at once.
        await _serial(waiting, () async => _wait(waiting));
      }
    }
    _list.add(tasks);
    await _flush();
    return written;
  }

  /// Keeps the recording root under `storageLimitMegabytes` now (spec §15);
  /// null when the limit is off. A sweep already running is shared.
  Future<StorageSweep?> sweepStorage() {
    final limit = _settings.storageLimitBytes;
    if (limit == null || _disposed) return Future.value();
    return _sweeping ??= () async {
      try {
        return await enforceStorageLimit(
          files: _files,
          root: root,
          limitBytes: limit,
          isProtected: _protectedDirectory,
        );
      } on Object {
        // An unreadable root is retried at the next check.
        return null;
      } finally {
        _sweeping = null;
      }
    }();
  }

  /// Session directories of tasks resolving, recording, reconnecting or
  /// finalizing (remux and crash recovery included) are never cleaned (§15).
  bool _protectedDirectory(String directory) {
    for (final runtime in _runtimes.values) {
      final state = runtime.task.state;
      final layout = runtime.task.session?.layout;
      if (layout == null || !(state.holdsSlot || state == RecordState.finalizing)) continue;
      if (p.equals(layout.directory, directory)) return true;
    }
    return false;
  }

  void _scheduleStorage() {
    if (_storageTimer != null || _disposed || _settings.storageLimitBytes == null) return;
    _storageTimer = Timer.periodic(timings.storageCheck, (_) => unawaited(sweepStorage()));
  }

  /// Applies new settings. Switching polling off moves waiting tasks to
  /// stopped (they never sit in "waiting" unchecked, REG-RECORD-033); switching
  /// it on puts them back and checks every waiting task at once (§12).
  Future<void> updateSettings(RecordSettings settings) async {
    final previous = _settings;
    _settings = settings.clamped();
    _slots
      ..max = _settings.maxConcurrent
      .._pump();
    for (final runtime in _runtimes.values) {
      runtime.session?.retrySettings = _settings;
    }
    if (previous.storageLimitMegabytes != _settings.storageLimitMegabytes) {
      _storageTimer?.cancel();
      _storageTimer = null;
      _scheduleStorage();
    }
    if (previous.polling && !_settings.polling) {
      for (final runtime in _runtimes.values.toList()) {
        if (runtime.task.state != RecordState.waitingLive) continue;
        _cancelPoll(runtime);
        runtime.generation++;
        _update(
          runtime,
          runtime.task.copyWith(state: RecordState.stopped, stopCause: StopCause.pollingOff, nextCheckAt: null),
        );
      }
    } else if (!previous.polling && _settings.polling) {
      for (final runtime in _runtimes.values.toList()) {
        final task = runtime.task;
        if (task.state == RecordState.stopped && task.stopCause == StopCause.pollingOff) {
          unawaited(_serial(runtime, () async => _wait(runtime, checkNow: true)));
        } else if (task.state == RecordState.waitingLive) {
          unawaited(_poll(runtime, runtime.generation));
        }
      }
    }
    await _flush();
  }

  /// App exit (§16.2): finalises every active task like a user stop, without
  /// remux, and waits up to [timeout] for the files. The tasks are stored as
  /// stopped by the app ([StopCause.appRestart]), so `resumeOnLaunch` picks
  /// them up at the next launch; the remux is skipped (the sources stay FLV).
  Future<void> stopAll({Duration timeout = const Duration(seconds: 10)}) async {
    final stops = [
      for (final runtime in _runtimes.values)
        if (runtime.task.state.active || runtime.task.state == RecordState.waitingLive)
          _serial(runtime, () => _stop(runtime, StopCause.appRestart, remux: false)),
    ];
    await Future.wait(stops).timeout(timeout, onTimeout: () => const []);
    await _flush();
  }

  /// The system ended background time (Android `onTimeout`, §16.1): every
  /// active task is finalised like a user stop and marked failed with
  /// `backgroundInterrupted`; only a manual start resumes it.
  Future<void> interruptAll({Duration timeout = const Duration(seconds: 45)}) async {
    final stops = [
      for (final runtime in _runtimes.values)
        if (runtime.task.state.active)
          _serial(runtime, () async {
            runtime.interrupted = true;
            await _stop(runtime, StopCause.user, remux: false);
          }),
    ];
    await Future.wait(stops).timeout(timeout, onTimeout: () => const []);
    await _flush();
  }

  /// Stops polling and sessions, writes pending state and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    await stopAll();
    _disposed = true;
    _persistTimer?.cancel();
    _storageTimer?.cancel();
    _slots.dispose();
    for (final runtime in _runtimes.values) {
      _cancelPoll(runtime);
      await runtime.controller.close();
    }
    await _flush();
    await _list.close();
    await _updates.close();
    await _active.close();
  }

  void _checkAlive() {
    if (_disposed) throw StateError('RecordManager is disposed');
  }

  Future<void> _serial(_Runtime runtime, Future<void> Function() action) {
    final next = runtime.intents.then((_) => action());
    runtime.intents = next.catchError((Object _) {});
    return next;
  }

  void _update(_Runtime runtime, RecordTask task, {bool progressOnly = false}) {
    runtime.task = task;
    if (!runtime.removed) {
      runtime.controller.add(task);
      _updates.add(task);
      _markDirty(runtime, progressOnly: progressOnly);
    }
    final active = _runtimes.values.where((runtime) => runtime.task.state.active).length;
    if (active != _activeCount) {
      _activeCount = active;
      if (!_active.isClosed) _active.add(active);
    }
  }

  // Persistence (§13).

  void _markDirty(_Runtime runtime, {bool progressOnly = false}) {
    _dirty.add(runtime.task.key);
    final due = clock.now().add(progressOnly ? timings.progressPersist : timings.stateDebounce);
    final current = _persistDue;
    if (current != null && !due.isBefore(current)) return;
    _persistTimer?.cancel();
    _persistDue = due;
    _persistTimer = Timer(due.difference(clock.now()), () => unawaited(_flush()));
  }

  Future<void> _flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistDue = null;
    final keys = _dirty.toList();
    _dirty.clear();
    final snapshot = [
      for (final key in keys)
        if (_runtimes[key] case final runtime?) runtime.task,
    ];
    if (snapshot.isEmpty) return _persisting;
    return _persisting = _persisting.then((_) => _store.save(snapshot)).catchError((Object _) {});
  }

  // Sessions.

  void _launch(_Runtime runtime, {bool force = false}) {
    runtime
      ..stopCause = null
      ..remuxOnStop = true
      ..interrupted = false;
    final generation = runtime.generation;
    final done = Completer<void>();
    runtime.running = done.future;
    unawaited(
      _runSession(runtime, generation, force: force).whenComplete(() {
        if (identical(runtime.running, done.future)) runtime.running = null;
        done.complete();
      }),
    );
  }

  bool _current(_Runtime runtime, int generation) => runtime.generation == generation && !runtime.removed;

  Future<void> _runSession(_Runtime runtime, int generation, {bool force = false}) async {
    final granted = await _slots.acquire(runtime, force: force);
    if (!granted) return;
    if (!_current(runtime, generation)) {
      _slots.release();
      return;
    }
    var holdsSlot = true;
    void releaseSlot() {
      if (!holdsSlot) return;
      holdsSlot = false;
      _slots.release();
    }

    final task = runtime.task;
    final layout = SessionLayout.at(
      root,
      task.room,
      task.snapshot.anchorName,
      clock.now(),
      transliterate: _transliterate,
    );
    final opener = (_opener ?? httpRecordOpener(readTimeout: _settings.readTimeout))(task.room.platform);
    late final RecordSession session;
    session = RecordSession(
      room: task.room,
      rooms: _rooms,
      layout: layout,
      files: _files,
      settings: _settings,
      opener: opener,
      quality: task.quality,
      cursor: task.cursor,
      autoReconnect: task.autoReconnect,
      spliceTimings: spliceTimings,
      writerLimits: writerLimits,
      requestTimeout: timings.checkTimeout,
      onPhase: (phase) {
        if (!identical(runtime.session, session)) return;
        final state = switch (phase) {
          SessionPhase.resolving => RecordState.resolving,
          SessionPhase.recording => RecordState.recording,
          SessionPhase.reconnecting => RecordState.reconnecting,
          SessionPhase.finalizing => RecordState.finalizing,
        };
        if (state == RecordState.finalizing) {
          releaseSlot();
          _stopChat(runtime);
        }
        _update(
          runtime,
          runtime.task.copyWith(state: state, retrying: state == RecordState.recording ? null : runtime.task.retrying),
        );
      },
      onDetail: (detail) {
        if (!identical(runtime.session, session)) return;
        _update(runtime, runtime.task.copyWith(snapshot: RecordRoomSnapshot.of(detail)));
        _startChat(runtime, session, detail);
      },
      onRetry: (failure, delay) {
        if (!identical(runtime.session, session)) return;
        _update(runtime, runtime.task.copyWith(retrying: failure));
      },
    );
    runtime.session = session;
    _update(
      runtime,
      runtime.task.copyWith(
        state: RecordState.resolving,
        session: RecordSessionInfo(layout: layout),
      ),
    );
    runtime.progressTimer = Timer.periodic(timings.progressInterval, (_) => _progress(runtime, session));
    SessionResult result;
    try {
      result = await session.run();
    } on Object catch (error) {
      result = SessionResult(
        end: SessionEnd.failed,
        failure: classifyError(error, RecordStage.writer),
        segments: [
          for (final segment in session.segments)
            if (segment.closed) segment,
        ],
        gaps: const [],
      );
    } finally {
      runtime.progressTimer?.cancel();
      runtime.progressTimer = null;
      releaseSlot();
      _stopChat(runtime);
    }
    _progress(runtime, session);
    final info = (runtime.task.session ?? RecordSessionInfo(layout: layout)).copyWith(
      segments: [for (final segment in result.segments) segment.path],
      gaps: result.gaps.length,
    );
    _update(
      runtime,
      runtime.task.copyWith(state: RecordState.finalizing, session: info, cursor: result.cursor, bitsPerSecond: 0),
    );

    var outputs = const <String>[];
    RecordFailure? remuxFailure;
    final stopCause = runtime.stopCause;
    final remux = stopCause == null || runtime.remuxOnStop;
    if (remux && result.segments.isNotEmpty) {
      (outputs, remuxFailure) = await _remux(runtime, info.segments);
    }
    runtime.session = null;

    var state = RecordState.completed;
    RecordFailure? failure;
    StopCause? cause;
    switch (result.end) {
      case SessionEnd.stopped:
        state = RecordState.stopped;
        cause = stopCause ?? StopCause.user;
      case SessionEnd.offline:
        state = _settings.polling && runtime.task.autoReconnect ? RecordState.waitingLive : RecordState.completed;
      case SessionEnd.exhausted:
        if (_settings.polling) {
          state = RecordState.waitingLive;
        } else {
          state = RecordState.failed;
          failure = RecordFailure(RecordErrorKind.retriesExhausted, RecordStage.scheduler, result.failure?.message);
        }
      case SessionEnd.failed:
        state = RecordState.failed;
        failure = result.failure;
      case SessionEnd.ended:
        state = RecordState.completed;
    }
    final lateStop = runtime.stopCause;
    if (lateStop != null && state == RecordState.waitingLive) {
      // Stopped while finalising after the room went offline: stay stopped.
      state = RecordState.stopped;
      cause = lateStop;
    }
    if (runtime.interrupted) {
      state = RecordState.failed;
      failure = RecordFailure(RecordErrorKind.backgroundInterrupted, RecordStage.background);
      cause = null;
    }
    if (remuxFailure != null && state != RecordState.failed) {
      state = RecordState.failed;
      failure = remuxFailure;
      cause = null;
    }
    _update(
      runtime,
      runtime.task.copyWith(
        state: state,
        failure: failure,
        stopCause: cause,
        retrying: null,
        remuxProgress: null,
        session: info.copyWith(outputs: outputs),
      ),
    );
    if (state == RecordState.waitingLive && _current(runtime, generation)) {
      runtime.pollRounds = 0;
      _schedulePoll(runtime, _pollDelay(runtime));
    }
    // Final state reaches the store before the session counts as over (§13).
    await _flush();
  }

  void _progress(_Runtime runtime, RecordSession session) {
    if (!identical(runtime.session, session)) return;
    final progress = session.progress;
    final info = runtime.task.session;
    if (info == null) return;
    _update(
      runtime,
      runtime.task.copyWith(
        session: info.copyWith(
          segments: [for (final segment in session.segments) segment.path],
          bytes: progress.bytes,
          media: progress.media,
          gaps: progress.gaps,
          connections: progress.connections,
          splices: progress.splices,
        ),
        bitsPerSecond: progress.bitsPerSecond,
        lastGapMs: progress.lastGapMs,
      ),
      progressOnly: true,
    );
  }

  Future<(List<String>, RecordFailure?)> _remux(_Runtime runtime, List<String> segments) async {
    final remuxer = _remuxer;
    if (remuxer == null || !_settings.remuxToMp4 || segments.isEmpty) return (const <String>[], null);
    final result = Completer<(List<String>, RecordFailure?)>();
    // One remux at a time; it does not take a recording slot (§10).
    _remuxing = _remuxing.then((_) async {
      try {
        final outcome = await remuxFiles(
          files: _files,
          remuxer: remuxer,
          inputs: segments,
          keepSource: _settings.keepSourceAfterRemux,
          onProgress: (value) => _update(runtime, runtime.task.copyWith(remuxProgress: value), progressOnly: true),
        );
        result.complete((outcome.outputs, outcome.failure));
      } on Object catch (error) {
        result.complete((const <String>[], RecordFailure(RecordErrorKind.remuxFailed, RecordStage.remux, '$error')));
      }
    });
    return await result.future;
  }

  Future<void> _stop(_Runtime runtime, StopCause cause, {bool remux = true}) async {
    final session = runtime.session;
    final running = runtime.running;
    if (running != null) {
      runtime
        ..stopCause = cause
        ..remuxOnStop = remux;
      if (session == null) {
        // Still queued for a slot.
        runtime.generation++;
        _slots.cancel(runtime);
        await running;
        _update(
          runtime,
          runtime.task.copyWith(
            state: runtime.interrupted ? RecordState.failed : RecordState.stopped,
            stopCause: runtime.interrupted ? null : cause,
            failure: runtime.interrupted
                ? RecordFailure(RecordErrorKind.backgroundInterrupted, RecordStage.background)
                : null,
          ),
        );
      } else {
        await session.stop();
        await running;
      }
      await _flush();
      return;
    }
    final state = runtime.task.state;
    if (state == RecordState.waitingLive || state == RecordState.queued) {
      _cancelPoll(runtime);
      runtime.generation++;
      _update(runtime, runtime.task.copyWith(state: RecordState.stopped, stopCause: cause, nextCheckAt: null));
      await _flush();
    }
  }

  // Chat (§17).

  void _startChat(_Runtime runtime, RecordSession session, RoomDetail detail) {
    final source = _chat;
    if (source == null || !_settings.danmaku || runtime.chat != null || runtime.chatRetry != null) return;
    void retry() {
      runtime.chat = null;
      if (!identical(runtime.session, session)) return;
      runtime.chatRetry = Timer(timings.chatRetry, () {
        runtime.chatRetry = null;
        if (identical(runtime.session, session) && runtime.task.state != RecordState.finalizing) {
          _startChat(runtime, session, detail);
        }
      });
    }

    try {
      runtime.chat = source
          .connect(detail)
          .listen(
            (message) {
              if (identical(runtime.session, session)) session.addChat(message);
            },
            onError: (Object _) {
              unawaited(runtime.chat?.cancel());
              retry();
            },
            onDone: retry,
            cancelOnError: true,
          );
    } on Object {
      retry();
    }
  }

  void _stopChat(_Runtime runtime) => runtime.stopChat();

  // Waiting for live (§12).

  /// Puts [runtime] into waiting (polling on) and schedules its checks.
  void _wait(_Runtime runtime, {bool checkNow = false}) {
    if (!_settings.polling) return;
    runtime.generation++;
    runtime.pollRounds = 0;
    _update(runtime, runtime.task.copyWith(state: RecordState.waitingLive, stopCause: null));
    _schedulePoll(runtime, checkNow ? Duration.zero : _pollDelay(runtime));
  }

  Duration _pollDelay(_Runtime runtime) =>
      RetryPolicy.regularDelay(_settings, runtime.pollRounds + 1, base: _settings.liveCheckInterval);

  void _schedulePoll(_Runtime runtime, Duration delay) {
    runtime.pollTimer?.cancel();
    if (!_settings.polling || runtime.removed) return;
    final generation = runtime.generation;
    _update(runtime, runtime.task.copyWith(nextCheckAt: clock.now().add(delay)));
    runtime.pollTimer = Timer(delay, () => unawaited(_poll(runtime, generation)));
  }

  void _cancelPoll(_Runtime runtime) {
    runtime.pollTimer?.cancel();
    runtime.pollTimer = null;
  }

  Future<void> _poll(_Runtime runtime, int generation) {
    final existing = runtime.polling;
    if (existing != null) return existing;
    final check = () async {
      bool? live;
      RecordFailure? failure;
      try {
        final detail = await _rooms.detail(runtime.task.room).timeout(timings.checkTimeout);
        if (_current(runtime, generation)) {
          _update(runtime, runtime.task.copyWith(snapshot: RecordRoomSnapshot.of(detail)));
        }
        // Replays (reruns, loops) count as offline: recording them only fills the
        // disk and keeps a monitored task busy (spec/modules/record.md §4.1).
        live = detail.state == LiveState.live;
      } on Object catch (error) {
        failure = classifyError(error, RecordStage.status);
        if (failure.kind == RecordErrorKind.roomOffline) {
          live = false;
          failure = null;
        }
      }
      // A late answer for an older generation is dropped (REG-RECORD-016).
      if (!_current(runtime, generation) || runtime.task.state != RecordState.waitingLive) return;
      if (live ?? false) {
        await _serial(runtime, () async {
          if (!_current(runtime, generation) || runtime.task.state != RecordState.waitingLive) return;
          _cancelPoll(runtime);
          runtime.generation++;
          runtime.stopCause = null;
          _update(runtime, runtime.task.copyWith(state: RecordState.queued, retrying: null, nextCheckAt: null));
          _launch(runtime);
        });
        return;
      }
      if (failure != null && failure.kind.fatal) {
        _cancelPoll(runtime);
        runtime.generation++;
        _update(runtime, runtime.task.copyWith(state: RecordState.failed, failure: failure, nextCheckAt: null));
        return;
      }
      runtime.pollRounds++;
      _update(runtime, runtime.task.copyWith(retrying: failure));
      _schedulePoll(runtime, _pollDelay(runtime));
    }();
    runtime.polling = check;
    return check.whenComplete(() {
      if (identical(runtime.polling, check)) runtime.polling = null;
    });
  }

  // Recovery (§14).

  /// Remuxes the closed segments of a task stopped by the last app exit (§16.2).
  Future<void> _remuxAfterExit(_Runtime runtime) async {
    final prior = runtime.task;
    final session = prior.session;
    if (session == null || session.outputs.isNotEmpty) return;
    final segments = [
      for (final path in session.segments)
        if (await _files.exists(path)) path,
    ];
    if (segments.isEmpty || _remuxer == null || !_settings.remuxToMp4) return;
    _update(runtime, prior.copyWith(state: RecordState.finalizing));
    final (outputs, failure) = await _remux(runtime, segments);
    _update(
      runtime,
      runtime.task.copyWith(
        state: failure == null ? RecordState.stopped : RecordState.failed,
        stopCause: failure == null ? prior.stopCause : null,
        failure: failure,
        remuxProgress: null,
        session: session.copyWith(outputs: outputs),
      ),
    );
  }

  Future<void> _recover(_Runtime runtime) async {
    final task = runtime.task;
    final session = task.session;
    if (session == null) {
      _update(runtime, task.copyWith(state: RecordState.stopped, stopCause: StopCause.appRestart));
      return;
    }
    _update(runtime, task.copyWith(state: RecordState.finalizing));
    List<String> segments;
    try {
      segments = await recoverSession(_files, session.layout, room: task.key);
    } on Object catch (error) {
      _update(
        runtime,
        runtime.task.copyWith(
          state: RecordState.failed,
          failure: RecordFailure(RecordErrorKind.inputDamaged, RecordStage.writer, '$error'),
        ),
      );
      return;
    }
    final info = session.copyWith(segments: segments, gaps: session.gaps + 1);
    _update(runtime, runtime.task.copyWith(session: info));
    final (outputs, failure) = await _remux(runtime, segments);
    _update(
      runtime,
      runtime.task.copyWith(
        state: failure == null ? RecordState.stopped : RecordState.failed,
        stopCause: failure == null ? StopCause.appRestart : null,
        failure: failure,
        remuxProgress: null,
        session: info.copyWith(outputs: outputs),
      ),
    );
  }

  Future<void> _resume(List<_Runtime> candidates) async {
    final problem = await RecordRoot.prepare(root, files: _files);
    if (problem != null) {
      final failure = classifyFileError(problem);
      for (final runtime in candidates) {
        await _serial(runtime, () async {
          _update(
            runtime,
            runtime.task.copyWith(state: RecordState.stopped, stopCause: StopCause.appRestart, failure: failure),
          );
        });
      }
      return;
    }
    final queue = ListQueue.of(candidates);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final runtime = queue.removeFirst();
        await _serial(runtime, () async {
          if (runtime.removed) return;
          bool? live;
          try {
            final detail = await _rooms.detail(runtime.task.room).timeout(timings.checkTimeout);
            // Replays (reruns, loops) count as offline: recording them only fills the
            // disk and keeps a monitored task busy (spec/modules/record.md §4.1).
            live = detail.state == LiveState.live;
          } on Object catch (error) {
            live = classifyError(error, RecordStage.status).kind == RecordErrorKind.roomOffline ? false : null;
          }
          if (live ?? false) {
            runtime.generation++;
            _update(
              runtime,
              runtime.task.copyWith(state: RecordState.queued, failure: null, stopCause: null, retrying: null),
            );
            _launch(runtime);
          } else if (_settings.polling) {
            _wait(runtime);
          } else {
            _update(runtime, runtime.task.copyWith(state: RecordState.stopped, stopCause: StopCause.pollingOff));
          }
        });
      }
    }

    await Future.wait([for (var i = 0; i < timings.resumeChecks; i++) worker()]);
  }
}
