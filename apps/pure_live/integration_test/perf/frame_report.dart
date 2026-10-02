// Frame timings of the benchmark runs (P05; research 2026-10-02 §4.1 and
// §4.3 item 3; UI_PLAN §9.4): every frame's build (UI thread) and raster
// time from SchedulerBinding.addTimingsCallback, their P50/P90/P99, the
// janky frames and research §4.1's pass marks, as JSON.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';

/// Collects the frames drawn between [start] and [stop].
final class FrameRecorder {
  /// Creates the recorder; [requested] holds the numbers of the frames the
  /// app asked for (frame_requests.dart), null to keep every frame.
  new({this.requested});

  /// The frames the app asked for, by engine frame number.
  final Set<int>? requested;

  final List<FrameTiming> _timings = [];
  int _from = 0;
  bool _running = false;

  /// How long [stop] waits for the engine's last batch: profile and release
  /// builds report timings in batches (at most a second apart).
  static const Duration flush = Duration(milliseconds: 1500);

  static int get _frameNumber => PlatformDispatcher.instance.frameData.frameNumber;

  /// Starts collecting; frames begun before this are left out.
  void start() {
    assert(!_running, 'already started');
    _running = true;
    _timings.clear();
    _from = _frameNumber;
    SchedulerBinding.instance.addTimingsCallback(_add);
  }

  void _add(List<FrameTiming> timings) => _timings.addAll(timings);

  /// Stops collecting and answers the frames begun since [start] and before
  /// now (the frames of the wait for the last batch are left out).
  Future<RecordedFrames> stop() async {
    assert(_running, 'not started');
    final until = _frameNumber;
    await Future<void>.delayed(flush);
    SchedulerBinding.instance.removeTimingsCallback(_add);
    _running = false;
    return appFrames(_timings, from: _from, until: until, requested: requested);
  }
}

/// The frames a recording kept, and how many it left out because the app
/// had not asked for them.
typedef RecordedFrames = ({List<FrameTiming> frames, int idleLeftOut});

/// The frames of [timings] numbered after [from] up to [until] (the engine's
/// frame numbers; not checked where the engine gives none) that the app
/// asked for ([requested]; null keeps all).
///
/// A live test binding draws a frame on every vsync once the engine drew
/// one, also while nothing changes; the app would draw none then, so those
/// frames would flatter the figures. When no frame is in [requested] (an
/// engine that numbers its frames otherwise), every frame is kept.
RecordedFrames appFrames(List<FrameTiming> timings, {int? from, int? until, Set<int>? requested}) {
  bool inside(FrameTiming timing) {
    final number = timing.frameNumber;
    if (number < 0) return true;
    if (from != null && from > 0 && number <= from) return false;
    if (until != null && until > 0 && number > until) return false;
    return true;
  }

  final window = [
    for (final timing in timings)
      if (inside(timing)) timing,
  ];
  if (requested == null) return (frames: window, idleLeftOut: 0);
  final asked = [
    for (final timing in window)
      if (requested.contains(timing.frameNumber)) timing,
  ];
  if (asked.isEmpty) return (frames: window, idleLeftOut: 0);
  return (frames: asked, idleLeftOut: window.length - asked.length);
}

/// P50, P90, P99, the largest and the mean of one series in milliseconds.
final class Percentiles {
  /// The figures of [values] (milliseconds); zeros when empty.
  factory of(List<double> values) {
    if (values.isEmpty) return const Percentiles._(0, 0, 0, 0, 0, 0);
    final sorted = List.of(values)..sort();
    double at(double share) => sorted[math.max(0, (share * sorted.length).ceil() - 1)];
    final sum = sorted.fold<double>(0, (total, value) => total + value);
    return Percentiles._(sorted.length, at(0.5), at(0.9), at(0.99), sorted.last, sum / sorted.length);
  }

  const new _(this.count, this.p50, this.p90, this.p99, this.max, this.mean);

  /// Values.
  final int count;

  /// The median.
  final double p50;

  /// The 90th percentile (nearest rank).
  final double p90;

  /// The 99th percentile (nearest rank).
  final double p99;

  /// The largest value.
  final double max;

  /// The mean.
  final double mean;

  /// The figures rounded to 0.01 ms.
  Map<String, Object> toJson() => {
    'p50': _round(p50),
    'p90': _round(p90),
    'p99': _round(p99),
    'max': _round(max),
    'mean': _round(mean),
  };
}

/// The summary of one benchmark run.
final class FrameReport {
  /// Summarises [timings] at [refreshRate] Hz.
  ///
  /// A frame is janky when its build or its raster took longer than one
  /// period. The marks are research §4.1's: build and raster P90 within a
  /// period ([rasterShare] of one for the live room, where every video frame
  /// redraws the screen), P99 within 1.5 periods, under 1 % janky frames and
  /// never two in a row; [buildLimitMs] caps the build P90 as well (UI_PLAN
  /// §9.4: 3 ms with 200 danmaku a second).
  factory fromTimings(
    String scenario,
    List<FrameTiming> timings, {
    required double refreshRate,
    double rasterShare = 1,
    double? buildLimitMs,
    Map<String, Object?> extra = const {},
  }) {
    double ms(Duration duration) => duration.inMicroseconds / 1000;
    final period = 1000 / refreshRate;
    final build = [for (final timing in timings) ms(timing.buildDuration)];
    final raster = [for (final timing in timings) ms(timing.rasterDuration)];
    var janky = 0;
    var buildOver = 0;
    var rasterOver = 0;
    var run = 0;
    var longestRun = 0;
    for (var i = 0; i < timings.length; i++) {
      final slowBuild = build[i] > period;
      final slowRaster = raster[i] > period;
      if (slowBuild) buildOver++;
      if (slowRaster) rasterOver++;
      if (slowBuild || slowRaster) {
        janky++;
        run++;
        longestRun = math.max(longestRun, run);
      } else {
        run = 0;
      }
    }
    return FrameReport._(
      scenario: scenario,
      refreshRate: refreshRate,
      build: Percentiles.of(build),
      raster: Percentiles.of(raster),
      total: Percentiles.of([for (final timing in timings) ms(timing.totalSpan)]),
      jankyFrames: janky,
      buildOverBudget: buildOver,
      rasterOverBudget: rasterOver,
      longestJankRun: longestRun,
      rasterShare: rasterShare,
      buildLimitMs: buildLimitMs,
      extra: extra,
    );
  }

  const new _({
    required this.scenario,
    required this.refreshRate,
    required this.build,
    required this.raster,
    required this.total,
    required this.jankyFrames,
    required this.buildOverBudget,
    required this.rasterOverBudget,
    required this.longestJankRun,
    required this.rasterShare,
    required this.buildLimitMs,
    required this.extra,
  });

  /// The scenario's name.
  final String scenario;

  /// The refresh rate the budget comes from.
  final double refreshRate;

  /// UI thread time per frame.
  final Percentiles build;

  /// Raster thread time per frame.
  final Percentiles raster;

  /// From vsync to the end of the raster.
  final Percentiles total;

  /// Frames whose build or raster took longer than a period.
  final int jankyFrames;

  /// Frames whose build took longer than a period.
  final int buildOverBudget;

  /// Frames whose raster took longer than a period.
  final int rasterOverBudget;

  /// The most janky frames in a row.
  final int longestJankRun;

  /// The share of a period the raster P90 may take.
  final double rasterShare;

  /// The largest build P90 in milliseconds, besides the period.
  final double? buildLimitMs;

  /// What else the scenario measured (memory, danmaku sent).
  final Map<String, Object?> extra;

  /// Frames.
  int get frames => build.count;

  /// One period in milliseconds.
  double get periodMs => 1000 / refreshRate;

  /// The share of janky frames.
  double get jankRate => frames == 0 ? 0 : jankyFrames / frames;

  /// Research §4.1's marks, each passed or not.
  Map<String, bool> get checks {
    final buildP90Limit = math.min(periodMs, buildLimitMs ?? periodMs);
    return {
      'buildP90': build.p90 <= buildP90Limit,
      'rasterP90': raster.p90 <= periodMs * rasterShare,
      'buildP99': build.p99 <= periodMs * 1.5,
      'rasterP99': raster.p99 <= periodMs * 1.5,
      'jankRate': jankRate < 0.01,
      'noJankPairs': longestJankRun < 2,
    };
  }

  /// Whether there were frames and every mark passed.
  bool get passed => frames > 0 && checks.values.every((passed) => passed);

  /// The report as JSON (milliseconds).
  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'refreshRate': _round(refreshRate),
    'periodMs': _round(periodMs),
    'frames': frames,
    'buildMs': build.toJson(),
    'rasterMs': raster.toJson(),
    'totalMs': total.toJson(),
    'jank': {
      'frames': jankyFrames,
      'rate': _round(jankRate * 100) / 100,
      'buildOverBudget': buildOverBudget,
      'rasterOverBudget': rasterOverBudget,
      'longestRun': longestJankRun,
    },
    'limits': {
      'buildP90Ms': _round(math.min(periodMs, buildLimitMs ?? periodMs)),
      'rasterP90Ms': _round(periodMs * rasterShare),
      'p99Ms': _round(periodMs * 1.5),
      'jankRate': 0.01,
    },
    'checks': checks,
    'passed': passed,
    if (extra.isNotEmpty) 'extra': extra,
  };

  /// One line for the console.
  String get summary =>
      '${scenario.padRight(26)} ${frames.toString().padLeft(5)} frames  '
      'build P90 ${_fixed(build.p90)} P99 ${_fixed(build.p99)}  '
      'raster P90 ${_fixed(raster.p90)} P99 ${_fixed(raster.p99)}  '
      'jank ${(jankRate * 100).toStringAsFixed(2)}% (run $longestJankRun)  '
      '${passed ? 'PASS' : 'FAIL'}';
}

double _round(double value) => (value * 100).roundToDouble() / 100;

String _fixed(double value) => value.toStringAsFixed(2).padLeft(6);
