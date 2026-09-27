import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show DanmakuController;
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/presentation.dart';

import '../danmaku/fake_danmaku.dart';

/// A room whose stream request never answers: the player stays idle, with
/// no failure overlay over the picture.
final class _QuietSite implements RoomSource, StreamSource {
  @override
  Future<RoomDetail> detail(RoomRef ref) async => liveRoom(id: ref.roomId);

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => Completer<StreamSet>().future;
}

final class _Calls {
  int fullscreen = 0;
  int back = 0;
}

void main() {
  late _Calls calls;
  late ValueNotifier<RoomPresentation> shown;

  Future<PlayerViewState> pumpPlayer(
    WidgetTester tester, {
    RoomPresentation presentation = RoomPresentation.inline,
    Size size = const Size(400, 300),
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    // Never opened (the stream request never answers), so it holds no timers;
    // its serial queue lives on the fake clock and is left to the test's end.
    final session = PlaybackSession(engine: () => throw UnimplementedError('no engine in widget tests'));
    final overlay = DanmakuController();
    addTearDown(overlay.dispose);
    calls = _Calls();
    shown = ValueNotifier(presentation);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(_QuietSite())}),
          ...overrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (context, presentation, _) => PlayerView(
                    detail: liveRoom(),
                    session: session,
                    presentation: presentation,
                    overlay: overlay,
                    onToggleFullscreen: () => calls.fullscreen++,
                    onBack: () => calls.back++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<PlayerViewState>(find.byType(PlayerView));
  }

  Offset at(WidgetTester tester, double fx, double fy) {
    final box = tester.getRect(find.byType(PlayerView));
    return Offset(box.left + box.width * fx, box.top + box.height * fy);
  }

  /// A single tap on the picture; single taps wait out the double-tap window.
  Future<void> tapPicture(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('INV-ROOM-03: a phone starts at the mobile default volume, never the device volume', (tester) async {
    final player = await pumpPlayer(tester);
    expect(player.volume, 0.5);
    expect(player.brightness, 1);
    expect(player.fit, VideoFit.contain);
  });

  testWidgets('F-ROOM-17: fullscreen shows the time of the app clock', (tester) async {
    await pumpPlayer(
      tester,
      presentation: RoomPresentation.fullscreen,
      overrides: [clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 21, 7))],
    );
    expect(find.text('21:07'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('T-03: the right half sets the volume, the left half the brightness', (tester) async {
    final player = await pumpPlayer(tester);
    // Half the picture height (150 of 300) is 25%; the touch slop eats a little.
    await tester.dragFrom(at(tester, 0.75, 0.7), const Offset(0, -150));
    await tester.pump();
    expect(player.volume, inInclusiveRange(0.66, 0.75));
    expect(player.brightness, 1);

    await tester.dragFrom(at(tester, 0.25, 0.3), const Offset(0, 150));
    await tester.pump();
    expect(player.brightness, inInclusiveRange(0.75, 0.84));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('T-06: spreading two fingers fills the screen, pinching fits it, one step each', (tester) async {
    final player = await pumpPlayer(tester);
    final center = at(tester, 0.5, 0.5);
    Future<void> twoFingers(double from, double to) async {
      final left = await tester.startGesture(center - Offset(from, 0));
      final right = await tester.startGesture(center + Offset(from, 0), pointer: 9);
      for (var step = 1; step <= 5; step++) {
        final gap = from + (to - from) * step / 5;
        await left.moveTo(center - Offset(gap, 0));
        await right.moveTo(center + Offset(gap, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
      await tester.pump();
    }

    await twoFingers(30, 120);
    expect(player.fit, VideoFit.cover);
    await twoFingers(120, 30);
    expect(player.fit, VideoFit.contain);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('T-02: a double tap asks the page to toggle fullscreen', (tester) async {
    await pumpPlayer(tester);
    final center = at(tester, 0.5, 0.5);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.fullscreen, 1);
  });

  testWidgets('T-10: the lock hides the bars and disables swipes, double tap and pinch', (tester) async {
    final player = await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400));
    final lock = find.byKey(const ValueKey('room-lock'));
    expect(lock, findsOneWidget);
    await tester.tap(lock);
    await tester.pump();
    expect(player.locked, isTrue);
    expect(player.controlsVisible, isFalse);

    final volume = player.volume;
    await tester.dragFrom(at(tester, 0.75, 0.7), const Offset(0, -150));
    await tester.pump();
    expect(player.volume, volume, reason: 'swipes are off while locked');

    final center = at(tester, 0.5, 0.5);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.fullscreen, 0, reason: 'double tap is off while locked');

    // Let the lock button hide, then a tap shows only the lock button.
    await tester.pump(const Duration(seconds: 5));
    expect(lock, findsNothing);
    await tapPicture(tester, center);
    expect(lock, findsOneWidget);
    expect(player.controlsVisible, isFalse);

    await tester.tap(lock);
    await tester.pump();
    expect(player.locked, isFalse);
    expect(player.controlsVisible, isTrue);
    await tester.dragFrom(at(tester, 0.75, 0.7), const Offset(0, -150));
    await tester.pump();
    expect(player.volume, greaterThan(volume));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('PS-2: a presentation change unlocks', (tester) async {
    final player = await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400));
    await tester.tap(find.byKey(const ValueKey('room-lock')));
    await tester.pump();
    expect(player.locked, isTrue);
    shown.value = RoomPresentation.inline;
    await tester.pump();
    expect(player.locked, isFalse);
    expect(player.controlsVisible, isTrue, reason: 'CL-3: controls show after a change');
    expect(find.byKey(const ValueKey('room-lock')), findsNothing, reason: 'inline has no lock');
  });

  testWidgets('T-07: a long press on the picture opens the quick panel; 填充 changes the fit', (tester) async {
    final player = await pumpPlayer(tester);
    await tester.longPressAt(at(tester, 0.5, 0.5));
    await tester.pumpAndSettle();
    expect(find.text('画面比例'), findsOneWidget);
    expect(find.text('定时关闭'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    await tester.tap(find.text('填充'));
    await tester.pumpAndSettle();
    expect(player.fit, VideoFit.cover);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('D-04 / D-10: the wheel and the arrow keys change the volume by 5%', (tester) async {
    final player = await pumpPlayer(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at(tester, 0.5, 0.5)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
    await tester.pump();
    expect(player.volume, closeTo(0.55, 1e-9));
    player
      ..changeVolume(-0.05)
      ..changeVolume(-0.05);
    await tester.pump();
    expect(player.volume, closeTo(0.45, 1e-9));
    player.toggleMute();
    expect(player.volume, 0);
    player.toggleMute();
    expect(player.volume, closeTo(0.45, 1e-9));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the top bar back button goes to the page', (tester) async {
    await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400));
    await tester.tap(find.byTooltip('返回'));
    expect(calls.back, 1);
  });
}
