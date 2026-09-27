import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_ui/src/danmaku/danmaku_engine.dart';

/// Result of one simulated run.
final class _Run {
  int frames = 0;
  int paints = 0;
  int peakVisible = 0;
  int peakPending = 0;
  int peakFrameLayouts = 0;
  final List<int> frameMicros = [];

  int percentile(double p) {
    final sorted = [...frameMicros]..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * p).floor())];
  }

  String summary(DanmakuStats stats) =>
      'frames $frames, paints $paints, added ${stats.added}, admitted ${stats.admitted}, '
      'layouts ${stats.layouts}, dropped overflow/stale/sampled '
      '${stats.droppedOverflow}/${stats.droppedStale}/${stats.droppedSampled}, peak visible $peakVisible, '
      'peak pending $peakPending, frame µs p50 ${percentile(0.5)} p99 ${percentile(0.99)} '
      'max ${percentile(1)}';
}

/// Feeds [perSecond] chat lines for [seconds] in 64 ms batches (CONN-2) into
/// an engine stepped at [fps], painting every changed frame, and checks the
/// per-frame budget on every frame.
_Run _simulate({
  required double perSecond,
  required double seconds,
  int fps = 60,
  DanmakuBudget budget = const DanmakuBudget(),
  Size size = const Size(852, 393),
}) {
  final random = math.Random(42);
  var now = Duration.zero;
  final engine = DanmakuEngine(budget: budget, clock: () => now)..resize(size, topInset: 24);
  final run = _Run();
  final frame = Duration(microseconds: Duration.microsecondsPerSecond ~/ fps);
  const batchEvery = Duration(milliseconds: 64);
  var nextBatch = Duration.zero;
  var owed = 0.0;
  var serial = 0;
  final watch = Stopwatch();

  DanmakuItem next() {
    serial++;
    final roll = random.nextInt(100);
    final text = switch (roll) {
      < 15 => '666',
      < 25 => '哈哈哈哈',
      _ => '弹幕$serial${'好' * random.nextInt(18)}',
    };
    return DanmakuItem(
      text,
      color: roll.isEven ? const Color(0xFFFFFFFF) : Color(0xFF000000 | random.nextInt(0xFFFFFF)),
      kind: roll < 97 ? DanmakuKind.scroll : (roll < 99 ? DanmakuKind.top : DanmakuKind.bottom),
      isLocal: serial % 500 == 0,
    );
  }

  final end = Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
  while (now < end) {
    now += frame;
    if (now >= nextBatch) {
      nextBatch += batchEvery;
      owed += perSecond * batchEvery.inMicroseconds / Duration.microsecondsPerSecond;
      final count = owed.floor();
      owed -= count;
      engine.addAll([for (var i = 0; i < count; i++) next()]);
    }
    final before = engine.stats.admitted;
    watch
      ..reset()
      ..start();
    final changed = engine.step(frame.inMicroseconds / Duration.microsecondsPerSecond);
    if (changed) {
      final recorder = PictureRecorder();
      engine.paint(Canvas(recorder), Offset.zero);
      recorder.endRecording().dispose();
      run.paints++;
    }
    watch.stop();
    run
      ..frames += 1
      ..frameMicros.add(watch.elapsedMicroseconds);

    final admitted = engine.stats.admitted - before;
    expect(admitted, lessThanOrEqualTo(budget.maxEmitPerFrame), reason: 'admissions per frame');
    expect(engine.lastFrameLayouts, lessThanOrEqualTo(admitted), reason: 'layouts only for new items');
    final local = engine.visibleItems.where((hit) => hit.item.isLocal).length;
    expect(engine.visibleCount - local, lessThanOrEqualTo(budget.maxVisible), reason: 'on-screen cap');
    expect(engine.pendingCount, lessThanOrEqualTo(budget.maxPending + 1), reason: 'waiting cap (+1 local)');
    run
      ..peakVisible = math.max(run.peakVisible, engine.visibleCount - local)
      ..peakPending = math.max(run.peakPending, engine.pendingCount)
      ..peakFrameLayouts = math.max(run.peakFrameLayouts, engine.lastFrameLayouts);
  }
  final stats = engine.stats;
  debugPrint(run.summary(stats));
  expect(stats.layouts, lessThanOrEqualTo(stats.admitted));
  expect(stats.maxFrameLayouts, lessThanOrEqualTo(budget.maxEmitPerFrame));
  engine.dispose();
  return run;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('2000 items over 60 s: bounded work per frame', () {
    final run = _simulate(perSecond: 2000 / 60, seconds: 60);
    expect(run.frames, inInclusiveRange(3600, 3601));
    expect(run.peakFrameLayouts, lessThanOrEqualTo(2));
    // Generous for a debug-mode test on a busy machine; the device budget
    // (≤ 3 ms of main-thread time per frame, PLAN §10) is measured on K90.
    final average = run.frameMicros.reduce((a, b) => a + b) / run.frames;
    expect(average, lessThan(1500), reason: 'average µs per frame');
  });

  test('200 items/s (the PLAN §10 stress rate) degrades density, not frames', () {
    final run = _simulate(perSecond: 200, seconds: 20, fps: 120);
    expect(run.peakVisible, 48, reason: 'the cap is reached and held');
    expect(run.peakPending, lessThanOrEqualTo(121));
    final average = run.frameMicros.reduce((a, b) => a + b) / run.frames;
    expect(average, lessThan(1500), reason: 'average µs per frame');
  });

  test('the PiP budget holds at 200 items/s', () {
    final run = _simulate(
      perSecond: 200,
      seconds: 10,
      fps: 30,
      budget: const DanmakuBudget.pip(),
      size: const Size(320, 180),
    );
    expect(run.peakVisible, 6);
  });
}
