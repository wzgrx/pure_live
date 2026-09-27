/// Lane geometry and assignment of the on-video layer (spec/modules/danmaku.md
/// REN-5), as pure functions over numbers so the math is unit-tested apart
/// from painting.
///
/// Every scrolling item moves at the same speed, so an item that entered after
/// the previous one in its lane can never catch up with it: a lane is free as
/// soon as its last item has fully entered plus a gap.
abstract final class DanmakuLanes {
  /// How many lanes fit: the height between the insets, times [area] once
  /// (REG-DANMAKU-010), divided by [laneHeight]. At least one lane when
  /// [area] is positive and anything is left, zero otherwise.
  static int count({
    required double height,
    required double laneHeight,
    required double area,
    double topInset = 0,
    double bottomInset = 0,
  }) {
    if (area <= 0 || laneHeight <= 0 || !height.isFinite) return 0;
    final usable = height - topInset - bottomInset;
    if (usable <= 0) return 0;
    final lanes = (usable * area.clamp(0.0, 1.0) / laneHeight).floor();
    return lanes < 1 ? 1 : lanes;
  }

  /// Minimum horizontal gap between two items in a lane: one character.
  static double gap(double fontSize) => fontSize < 8 ? 8 : fontSize;

  /// The topmost lane a new scrolling item can enter at the right edge
  /// without touching the previous item, or -1.
  ///
  /// [tailRights] holds, per lane, the right edge of the lane's last item, or
  /// null when the lane is empty.
  static int pickScroll(List<double?> tailRights, {required double width, required double gap}) {
    for (var lane = 0; lane < tailRights.length; lane++) {
      final tail = tailRights[lane];
      if (tail == null || tail + gap <= width) return lane;
    }
    return -1;
  }

  /// The lane whose last item is furthest left: where a local item goes
  /// when no lane is free. -1 when there are no lanes.
  static int roomiestScroll(List<double?> tailRights) {
    var best = -1;
    var bestTail = double.infinity;
    for (var lane = 0; lane < tailRights.length; lane++) {
      final tail = tailRights[lane] ?? double.negativeInfinity;
      if (tail < bestTail) {
        best = lane;
        bestTail = tail;
      }
    }
    return best;
  }

  /// The first fixed lane (counted from its edge) that is free at [now], or
  /// -1. [busyUntil] holds, per lane, when its current item expires.
  static int pickFixed(List<double> busyUntil, double now) {
    for (var lane = 0; lane < busyUntil.length; lane++) {
      if (busyUntil[lane] <= now) return lane;
    }
    return -1;
  }

  /// The fixed lane that frees up first, for a local item; -1 without lanes.
  static int soonestFixed(List<double> busyUntil) {
    var best = -1;
    var bestUntil = double.infinity;
    for (var lane = 0; lane < busyUntil.length; lane++) {
      if (busyUntil[lane] < bestUntil) {
        best = lane;
        bestUntil = busyUntil[lane];
      }
    }
    return best;
  }

  /// Keeps [keep] of [items] spread evenly over the whole list, in order
  /// (SMP-2: uniform in time, not the first or last run).
  static List<T> sampleEvenly<T>(List<T> items, int keep) {
    if (keep <= 0) return <T>[];
    final n = items.length;
    if (n <= keep) return List<T>.of(items);
    return List<T>.generate(keep, (i) => items[((i + 0.5) * n / keep).floor()]);
  }
}
