/// SMP-1/SMP-2 keeps at most the budget's worth of screen candidates per
/// batch, spread evenly over the batch rather than its first or last run.
final class DensitySampler {
  /// Creates a sampler; unused budget carries over up to [maxCarry] seconds'
  /// worth, and at most [maxGap] of elapsed time counts.
  new({this.maxCarry = 0.25, this.maxGap = const Duration(seconds: 1)});

  /// Carried budget limit, in seconds of budget.
  final double maxCarry;

  /// Elapsed time cap per batch.
  final Duration maxGap;

  double _carry = 0;

  /// Indices of the [count] candidates to keep for a batch covering
  /// [elapsed] at [perSecond] candidates per second.
  List<int> pick(int count, Duration elapsed, double perSecond) {
    if (count <= 0) return const [];
    if (perSecond <= 0) {
      _carry = 0;
      return const [];
    }
    final gap = elapsed > maxGap ? maxGap : elapsed;
    final allowance = _carry + perSecond * gap.inMicroseconds / Duration.microsecondsPerSecond;
    final keep = allowance.floor() < count ? allowance.floor() : count;
    final limit = perSecond * maxCarry < 1 ? 1.0 : perSecond * maxCarry;
    final rest = allowance - keep;
    _carry = rest > limit ? limit : rest;
    if (keep >= count) return [for (var i = 0; i < count; i++) i];
    return [for (var i = 0; i < keep; i++) ((i + 0.5) * count / keep).floor()];
  }

  /// Drops the carried budget.
  void reset() => _carry = 0;
}
