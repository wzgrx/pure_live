import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';

void main() {
  test('a synchronous runner failure releases the recorder capacity slot', () async {
    final scheduler = FFmpegScheduler.forTesting();
    scheduler.enqueue(taskId: 'sync-failure', taskRunner: (_) => throw StateError('fixture startup failure'));
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.isRunning('sync-failure'), isFalse);
    expect(scheduler.runningCount, 0);
  });

  test('immediate cancellation prevents a deferred runner from opening native resources', () async {
    final scheduler = FFmpegScheduler.forTesting();
    var starts = 0;
    scheduler.enqueue(
      taskId: 'cancel-before-run',
      taskRunner: (_) async {
        starts++;
      },
    );
    await scheduler.cancel('cancel-before-run');
    expect(starts, 0);
    expect(scheduler.totalCount, 0);
  });

  test('reentrant duplicate enqueue sees the already-owned capacity slot', () async {
    final scheduler = FFmpegScheduler.forTesting(capacity: 2);
    var starts = 0;
    scheduler.enqueue(
      taskId: 'reentrant',
      taskRunner: (_) {
        starts++;
        expect(scheduler.isRunning('reentrant'), isTrue);
        scheduler.enqueue(
          taskId: 'reentrant',
          taskRunner: (_) async {
            starts++;
          },
        );
        return Future<void>.value();
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(starts, 1);
    expect(scheduler.totalCount, 0);
  });

  test('synchronous and asynchronous failures both unblock the next waiting task', () async {
    for (final synchronous in [true, false]) {
      final scheduler = FFmpegScheduler.forTesting();
      final next = Completer<void>();
      scheduler.enqueue(
        taskId: 'failed',
        taskRunner: (_) {
          if (synchronous) throw StateError('sync fixture');
          return Future<void>.error(StateError('async fixture'));
        },
      );
      scheduler.enqueue(
        taskId: 'next',
        taskRunner: (_) async {
          next.complete();
        },
      );
      await next.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.totalCount, 0);
    }
  });

  test('cancelling an active task retains its slot until its runner actually exits', () async {
    final scheduler = FFmpegScheduler.forTesting();
    final entered = Completer<void>();
    final exit = Completer<void>();
    TaskCancelToken? owner;
    scheduler.enqueue(
      taskId: 'active',
      taskRunner: (token) {
        owner = token;
        entered.complete();
        return exit.future;
      },
    );
    await entered.future;
    final cancellation = scheduler.cancel('active');
    await Future<void>.delayed(Duration.zero);
    expect(owner!.isCancelled, isTrue);
    expect(scheduler.runningCount, 1);
    exit.complete();
    await cancellation;
    expect(scheduler.totalCount, 0);
  });
}
