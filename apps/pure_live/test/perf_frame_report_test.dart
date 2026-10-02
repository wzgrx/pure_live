// The figures of the frame benchmarks (P05, integration_test/perf_test.dart):
// percentiles, janky frames and research 2026-10-02 §4.1's marks.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/perf/frame_report.dart';

/// Engine frame [number], built in [build] ms and rastered in [raster] ms.
FrameTiming _frame(double build, double raster, {int number = -1}) {
  final buildUs = (build * 1000).round();
  final rasterUs = (raster * 1000).round();
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 100,
    buildFinish: 100 + buildUs,
    rasterStart: 200 + buildUs,
    rasterFinish: 200 + buildUs + rasterUs,
    rasterFinishWallTime: 200 + buildUs + rasterUs,
    frameNumber: number,
  );
}

void main() {
  test('percentiles by nearest rank', () {
    final figures = Percentiles.of([for (var i = 1; i <= 100; i++) i.toDouble()]);
    expect(figures.count, 100);
    expect(figures.p50, 50);
    expect(figures.p90, 90);
    expect(figures.p99, 99);
    expect(figures.max, 100);
    expect(figures.mean, 50.5);
    expect(Percentiles.of(const [3]).p99, 3);
    expect(Percentiles.of(const []).toJson(), {'p50': 0.0, 'p90': 0.0, 'p99': 0.0, 'max': 0.0, 'mean': 0.0});
  });

  test('120 Hz: janky frames, the longest run and the marks of §4.1', () {
    // 8.33 ms a period: 97 quick frames, then a slow build, a slow raster
    // next to it, and one more slow raster on its own.
    final timings = [
      for (var i = 0; i < 97; i++) _frame(3, 4),
      _frame(9, 4),
      _frame(3, 12.6),
      _frame(3, 4),
      _frame(3, 9),
    ];
    final report = FrameReport.fromTimings('hot_scroll', timings, refreshRate: 120);
    expect(report.frames, 101);
    expect(report.periodMs, closeTo(8.33, 0.01));
    expect(report.jankyFrames, 3);
    expect(report.buildOverBudget, 1);
    expect(report.rasterOverBudget, 2);
    expect(report.longestJankRun, 2);
    expect(report.jankRate, closeTo(3 / 101, 1e-9));
    expect(report.checks, {
      'buildP90': true,
      'rasterP90': true,
      'buildP99': true,
      'rasterP99': true,
      'jankRate': false,
      'noJankPairs': false,
    });
    expect(report.passed, isFalse);
    final json = report.toJson();
    expect(json['frames'], 101);
    expect((json['rasterMs']! as Map)['p90'], 4.0);
    expect((json['jank']! as Map)['longestRun'], 2);
    expect(json['passed'], isFalse);
  });

  test("the room's raster share and the danmaku's UI limit tighten the P90 marks", () {
    final timings = [for (var i = 0; i < 200; i++) _frame(3.5, 5.5)];
    final plain = FrameReport.fromTimings('danmaku_200', timings, refreshRate: 120);
    expect(plain.passed, isTrue);
    final room = FrameReport.fromTimings('danmaku_200', timings, refreshRate: 120, rasterShare: 0.6, buildLimitMs: 3);
    expect(room.checks['rasterP90'], isFalse, reason: '5.5 ms > 0.6 × 8.33 ms');
    expect(room.checks['buildP90'], isFalse, reason: '3.5 ms > 3 ms');
    expect((room.toJson()['limits']! as Map)['rasterP90Ms'], 5.0);
    expect(FrameReport.fromTimings('none', const [], refreshRate: 60).passed, isFalse);
  });

  test('only the frames of the recording that the app asked for count', () {
    final timings = [for (var i = 1; i <= 8; i++) _frame(1, 1, number: i)];
    List<int> numbers(RecordedFrames recorded) => [for (final timing in recorded.frames) timing.frameNumber];

    // Begun after frame 2, up to frame 7.
    var recorded = appFrames(timings, from: 2, until: 7);
    expect(numbers(recorded), [3, 4, 5, 6, 7]);
    expect(recorded.idleLeftOut, 0);
    // The live binding's own frames (4 and 6 here) are left out.
    recorded = appFrames(timings, from: 2, until: 7, requested: {1, 3, 5, 7, 8});
    expect(numbers(recorded), [3, 5, 7]);
    expect(recorded.idleLeftOut, 2);
    // Frame numbers that never match keep every frame rather than none.
    expect(numbers(appFrames(timings, from: 2, until: 7, requested: {100})), [3, 4, 5, 6, 7]);
    // An engine without frame numbers: nothing to go by.
    expect(appFrames([for (var i = 0; i < 3; i++) _frame(1, 1)], from: 2, until: 7).frames, hasLength(3));
  });
}
