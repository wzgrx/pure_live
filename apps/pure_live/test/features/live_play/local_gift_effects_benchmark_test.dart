// D08.5 frame cost of the local gift effects
// (docs/D-弹幕/D08-本地互动/D08.5-三档礼物特效 c6), in the style of the chat
// benchmark (chat_benchmark_test.dart): debug mode on the test host, so
// compare runs with each other, not with a phone's profile build (the K90's
// numbers go to verify.md).
//
// 1. Each vehicle painted alone at 120 Hz for its 2.8 s, on the landscape
//    fullscreen's gift layer and on the small inline picture's: the time a
//    paint takes and the most particles a frame draws.
// 2. The live room in landscape fullscreen at 120 Hz for 4 s, with nothing,
//    a small gift's flying line and a big gift's vehicle: how long a frame
//    takes, and how often the effects' widgets are built (the animations
//    only repaint their own layer: a handful of builds in 480 frames).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/local_interaction/effects/local_gift_flyer.dart';
import 'package:pure_live/features/live_play/local_interaction/effects/local_gift_vehicle.dart';
import 'package:pure_live/features/live_play/local_interaction/local_gift_effect.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import 'local_interaction_support.dart';

/// Frames a second (the K90's 120 Hz).
const int _hz = 120;

double _percentile(List<int> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[math.min(sorted.length - 1, math.max(0, (sorted.length * p).ceil() - 1))] / 1000;

String _ms(List<int> micros) {
  final sorted = [...micros]..sort();
  final mean = micros.fold<int>(0, (sum, t) => sum + t) / micros.length / 1000;
  return 'mean ${mean.toStringAsFixed(3)}, P50 ${_percentile(sorted, 0.5).toStringAsFixed(3)}, '
      'P90 ${_percentile(sorted, 0.9).toStringAsFixed(3)}, P99 ${_percentile(sorted, 0.99).toStringAsFixed(3)}, '
      'max ${(sorted.last / 1000).toStringAsFixed(3)} ms';
}

void main() {
  test('each vehicle painted at $_hz Hz: time a paint, particles a frame', () {
    final lines = <String>[];
    for (final (name, size) in [('landscape', const Size(852, 237)), ('inline', const Size(400, 121))]) {
      for (final vehicle in LocalGiftVehicle.values) {
        final scene = LocalGiftVehicleScene(vehicle, seed: 0.37);
        final times = <int>[];
        var most = 0;
        final watch = Stopwatch();
        final frames = (LocalGiftVehicle.duration.inMilliseconds * _hz / 1000).floor();
        // Twice: the first run records the body (once a size), the second is
        // the steady state.
        for (var run = 0; run < 2; run++) {
          for (var frame = 0; frame < frames; frame++) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            watch
              ..reset()
              ..start();
            final drawn = scene.paint(canvas, size, frame / _hz);
            watch.stop();
            recorder.endRecording().dispose();
            if (run == 1) times.add(watch.elapsedMicroseconds);
            most = math.max(most, drawn);
          }
        }
        scene.dispose();
        lines.add(
          '  ${vehicle.name} $name ${size.width.toInt()}x${size.height.toInt()}: paint ${_ms(times)}; '
          'at most $most particles',
        );
        expect(most, lessThanOrEqualTo(LocalGiftVehicleScene.maxParticles));
        final sorted = [...times]..sort();
        // A paint is a few dozen circles and one picture: far under the
        // 8 ms frame even in debug mode here.
        expect(_percentile(sorted, 0.9), lessThan(2), reason: '${vehicle.name} $name');
      }
    }
    // The numbers go to the record (D08.5 record.md).
    // ignore: avoid_print
    print('D08.5 vehicle paint, $_hz Hz, ${LocalGiftVehicle.duration.inMilliseconds} ms each:\n${lines.join('\n')}');
  });

  testWidgets('the room in landscape fullscreen at $_hz Hz: nothing, a flying line, a vehicle', (tester) async {
    final room = await pumpLocalRoom(
      tester,
      width: 852,
      height: 393,
      settings: {Settings.localInteractionCoins: 1000000},
      wrap: (child) => Builder(
        builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: false), child: child),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final session = LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;
    final gifts = LocalCatalog.giftsFor(SiteIds.bilibili);

    const frame = Duration(microseconds: Duration.microsecondsPerSecond ~/ _hz);
    const frames = 4 * _hz;
    final report = <String>[];
    final effectTypes = {
      LocalGiftLayer,
      LocalGiftFlyer,
      LocalGiftFlyerLine,
      LocalGiftVehicleView,
      LocalGiftBanner,
      Flow,
      CustomPaint,
    };
    Future<Map<Type, int>> run(String name, LocalGift? gift) async {
      final builds = <Type, int>{};
      var all = 0;
      if (gift != null) {
        session.sendGift(gift);
        await tester.pump();
      }
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        all++;
        final type = element.widget.runtimeType;
        if (effectTypes.contains(type)) builds.update(type, (count) => count + 1, ifAbsent: () => 1);
      };
      final times = <int>[];
      final watch = Stopwatch();
      try {
        for (var f = 0; f < frames; f++) {
          watch
            ..reset()
            ..start();
          await tester.pump(frame);
          watch.stop();
          times.add(watch.elapsedMicroseconds);
        }
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      report.add(
        '  $name: frame ${_ms(times)}; ${(all / frames).toStringAsFixed(1)} builds a frame; '
        'effect widgets built: ${builds.isEmpty ? 'none' : builds.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
      );
      await tester.pump(const Duration(seconds: 1));
      return builds;
    }

    await run('nothing', null);
    final line = await run('small gift (the line, 4 s)', gifts[0]);
    final vehicle = await run('big gift (the vehicle 2.8 s and the banner 4 s)', gifts[2]);
    // The numbers go to the record (D08.5 record.md).
    // ignore: avoid_print
    print('D08.5 room at $_hz Hz, landscape fullscreen 852x393, $frames frames each:\n${report.join('\n')}');
    // The line moves by repainting its Flow: built when it starts and when
    // it leaves, not each frame.
    expect(line[LocalGiftFlyer] ?? 0, lessThanOrEqualTo(2));
    expect(line[LocalGiftFlyerLine] ?? 0, lessThanOrEqualTo(2));
    expect(line[Flow] ?? 0, lessThanOrEqualTo(2));
    // The vehicle repaints its CustomPaint; built when it starts and ends.
    expect(vehicle[LocalGiftVehicleView] ?? 0, lessThanOrEqualTo(3));
    expect(vehicle[LocalGiftLayer] ?? 0, lessThanOrEqualTo(3));
    await closeLocalRoom(tester, room);
  });
}
