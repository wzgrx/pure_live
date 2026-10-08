import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/src/timing.dart';

void main() {
  test('a played open ends at its last mark, so the steps add up to the total (G03.1)', () {
    var now = DateTime.utc(2026, 10, 8);
    final monotonic = timingNow;
    timingNow = () => now;
    addTearDown(() => timingNow = monotonic);
    void wait(int ms) => now = now.add(Duration(milliseconds: ms));

    final startup = StartupMarks();
    final timing = OpenTiming(site: 'bilibili', startup: startup, sink: (_) {});
    wait(300);
    startup
      ..markDetail()
      ..markQualities();
    wait(200);
    startup.markUrls();
    for (final mark in [OpenTiming.engineReady, OpenTiming.input, OpenTiming.loaded, OpenTiming.firstFrame]) {
      wait(100);
      timing.mark(mark);
    }
    timing.mark(OpenTiming.playing);
    // A busy device calls finish a little after the last mark.
    wait(40);
    final played = timing.finish();
    final steps = [for (final step in played.segments) step ?? Duration.zero].reduce((a, b) => a + b);
    expect(played.total, steps);
    expect(played.total, const Duration(milliseconds: 900));

    // A failure ends when it failed.
    final failing = OpenTiming(site: 'douyu', startup: null, sink: (_) {});
    wait(100);
    failing.mark(OpenTiming.engineReady);
    wait(250);
    expect(failing.finish(error: 'network').total, const Duration(milliseconds: 350));
  });
}
