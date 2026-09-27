import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/room/weak_network.dart';

const _qualities = [
  Quality(id: '4', label: '原画', rank: 4),
  Quality(id: '3', label: '超清', rank: 3),
  Quality(id: '2', label: '流畅', rank: 2),
];

PlaybackState _state(PlaybackPhase phase, {int quality = 0, bool picture = true}) => PlaybackState(
  phase: phase,
  wantsPlay: true,
  hasPicture: picture,
  qualities: _qualities,
  quality: _qualities[quality],
);

void main() {
  late DateTime now;
  late StallWatch watch;

  setUp(() {
    now = DateTime(2026, 9, 28, 20);
    watch = StallWatch(now: () => now);
  });

  /// One rebuffer at [at] seconds; returns what the watch asks for.
  Quality? stallAt(int at, {int quality = 0}) {
    now = DateTime(2026, 9, 28, 20).add(Duration(seconds: at));
    final lower = watch.observe(
      _state(PlaybackPhase.playing, quality: quality),
      _state(PlaybackPhase.stalled, quality: quality),
    );
    watch.observe(_state(PlaybackPhase.stalled, quality: quality), _state(PlaybackPhase.playing, quality: quality));
    return lower;
  }

  test('F-NEW-10: three rebuffers within a minute lower the quality by one step', () {
    expect(stallAt(0), isNull);
    expect(stallAt(20), isNull);
    expect(stallAt(40)?.label, '超清');
    // The count starts over at the new quality.
    expect(stallAt(50, quality: 1), isNull);
    expect(stallAt(60, quality: 1), isNull);
    expect(stallAt(70, quality: 1)?.label, '流畅');
    // Nothing lower than the lowest.
    expect(stallAt(80, quality: 2), isNull);
    expect(stallAt(81, quality: 2), isNull);
    expect(stallAt(82, quality: 2), isNull);
  });

  test('stalls spread over more than a minute do not count together', () {
    expect(stallAt(0), isNull);
    expect(stallAt(40), isNull);
    expect(stallAt(80), isNull, reason: 'the first one fell out of the window');
    expect(stallAt(90)?.label, '超清');
  });

  test('the first load and pauses are not stalls', () {
    for (var i = 0; i < 5; i++) {
      expect(
        watch.observe(_state(PlaybackPhase.connecting, picture: false), _state(PlaybackPhase.stalled, picture: false)),
        isNull,
      );
      expect(watch.observe(_state(PlaybackPhase.playing), _state(PlaybackPhase.paused)), isNull);
    }
  });

  test('a quality the user picked stops it for the room; a new room starts over', () {
    watch.picked();
    for (var i = 0; i < 5; i++) {
      expect(stallAt(i), isNull);
    }
    watch.reset();
    expect(stallAt(10), isNull);
    expect(stallAt(11), isNull);
    expect(stallAt(12)?.label, '超清');
  });
}
