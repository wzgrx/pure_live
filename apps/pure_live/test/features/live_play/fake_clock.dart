// A clock whose timers fire when a test moves it (O01.3's background keeper).
import 'dart:async';

/// Timers that fire when the test moves the clock ([advance]).
final class FakeClock {
  DateTime now = DateTime(2026, 10, 9, 22);
  final List<FakeTimer> timers = [];

  Timer timer(Duration delay, void Function() callback) {
    final timer = FakeTimer(this, now.add(delay), callback);
    timers.add(timer);
    return timer;
  }

  /// Moves the clock by [by], firing what falls due in order.
  Future<void> advance(Duration by) async {
    final end = now.add(by);
    while (true) {
      final due = timers.where((timer) => timer.active && !timer.at.isAfter(end)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.at;
      next.fire();
      // Let a try's future run.
      await Future<void>.delayed(Duration.zero);
    }
    now = end;
  }

  /// The delays of the timers still waiting, from now.
  List<Duration> get pending => [
    for (final timer in timers)
      if (timer.active) timer.at.difference(now),
  ];
}

/// A timer of [FakeClock].
final class FakeTimer implements Timer {
  /// Creates the timer.
  new(this.clock, this.at, this.callback);

  final FakeClock clock;
  final DateTime at;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  bool get isActive => _active;

  bool get active => _active;

  @override
  void cancel() => _active = false;

  @override
  int get tick => 0;
}
