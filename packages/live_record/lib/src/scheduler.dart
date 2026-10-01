import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

/// Cancellation of one scheduled run (3.x `TaskCancelToken`): the runner
/// sets [onCancel] to stop its work; a callback set after cancellation runs
/// at once.
final class RecordCancelToken {
  var _cancelled = false;
  var _invoked = false;
  FutureOr<void> Function()? _onCancel;

  /// Whether the run was cancelled.
  bool get isCancelled => _cancelled;

  /// Stops the run's work; awaited by [cancel].
  FutureOr<void> Function()? get onCancel => _onCancel;

  set onCancel(FutureOr<void> Function()? callback) {
    _onCancel = callback;
    if (_cancelled && callback != null && !_invoked) {
      _invoked = true;
      unawaited(Future.sync(callback).catchError((Object _) {}));
    }
  }

  /// Cancels and waits for [onCancel]; idempotent.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    final callback = _onCancel;
    if (callback == null || _invoked) return;
    _invoked = true;
    try {
      await callback();
    } on Object {
      // A failing stop callback must not break cancellation.
    }
  }
}

/// A run of the scheduler.
typedef RecordRun = Future<void> Function(RecordCancelToken token);

/// FIFO queue of recordings with a concurrency limit and a minimum gap
/// between starts (3.x `FFmpegScheduler`: capacity from the settings, 5 s
/// gap). One id runs or waits at most once.
final class RecordScheduler {
  /// Creates a scheduler with [capacity] read on every decision.
  new({required this.capacity, this.minimumStartGap = const Duration(seconds: 5)});

  /// Current concurrency limit.
  final int Function() capacity;

  /// Minimum time between two starts.
  final Duration minimumStartGap;

  final _queue = Queue<({String id, RecordRun run})>();
  final _running = <String, ({Future<void> done, RecordCancelToken token})>{};
  DateTime? _lastStart;
  Timer? _timer;

  /// Queues [run] for [id] unless it already runs or waits.
  void enqueue(String id, RecordRun run) {
    if (_running.containsKey(id) || _queue.any((entry) => entry.id == id)) return;
    _queue.add((id: id, run: run));
    _next();
  }

  /// Removes [id] from the queue, or cancels its run and waits for it (at
  /// most 20 s; [waitFor] waits without a bound).
  Future<void> cancel(String id) async {
    _queue.removeWhere((entry) => entry.id == id);
    if (_queue.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
    final running = _running[id];
    if (running != null) {
      unawaited(running.token.cancel());
      await running.done.timeout(const Duration(seconds: 20), onTimeout: () {});
    }
    _next();
  }

  /// Waits for the current run of [id], if any.
  Future<void> waitFor(String id) => _running[id]?.done ?? Future.value();

  /// Empties the queue and cancels every run.
  Future<void> clear() async {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    await Future.wait([
      for (final running in _running.values.toList())
        running.token.cancel().then((_) => running.done.timeout(const Duration(seconds: 20), onTimeout: () {})),
    ]);
  }

  /// Whether [id] runs.
  bool isRunning(String id) => _running.containsKey(id);

  /// Whether [id] waits.
  bool isQueued(String id) => _queue.any((entry) => entry.id == id);

  /// Number of runs.
  int get runningCount => _running.length;

  /// Number of waiting ids.
  int get queuedCount => _queue.length;

  void _next() {
    if (_timer?.isActive ?? false) return;
    while (_running.length < capacity() && _queue.isNotEmpty) {
      final now = clock.now();
      final last = _lastStart;
      if (last != null && now.difference(last) < minimumStartGap) {
        _timer = Timer(minimumStartGap - now.difference(last), () {
          _timer = null;
          _next();
        });
        return;
      }
      final entry = _queue.removeFirst();
      _lastStart = now;
      _start(entry.id, entry.run);
    }
  }

  void _start(String id, RecordRun run) {
    final token = RecordCancelToken();
    final completer = Completer<void>();
    final running = (done: completer.future, token: token);
    _running[id] = running;
    unawaited(
      Future(() async {
        try {
          if (!token.isCancelled) await run(token);
        } on Object {
          // The runner reports its own failures on the task.
        } finally {
          if (identical(_running[id], running)) _running.remove(id);
          completer.complete();
          _next();
        }
      }),
    );
  }
}
