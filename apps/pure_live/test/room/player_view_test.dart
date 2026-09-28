import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show DanmakuController, VideoBarScrim;
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/network.dart';
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
    TextScaler? textScaler,
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
          builder: (context, child) => textScaler == null
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: RepaintBoundary(
                  key: const ValueKey('picture'),
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

  group('on a white frame', () {
    setUp(() => debugPictureBackground = Colors.white);
    tearDown(() => debugPictureBackground = Colors.black);

    double contrast(Color a, Color b) {
      final (la, lb) = (a.computeLuminance(), b.computeLuminance());
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    /// The colour of the picture at [position] (relative to the player).
    Future<Color> pixel(WidgetTester tester, Offset position) async {
      final image = (await tester.runAsync(() => captureImage(tester.element(find.byKey(const ValueKey('picture'))))))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      final offset = (position.dy.floor() * image.width + position.dx.floor()) * 4;
      final color = Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
      image.dispose();
      return color;
    }

    testWidgets('principles §2.2: both bars sit on 60% black, white text reads at 4.5:1 or more', (tester) async {
      // The review's case: a 393 dp phone, the picture 221 dp high. The old
      // gradient left 38% black where the title is (2.7:1).
      await pumpPlayer(
        tester,
        size: const Size(393, 221),
        // Real time passes while the picture is captured: no platform network state.
        overrides: [networkKindProvider.overrideWith((ref) => Stream.value(NetworkKind.unmetered))],
      );
      final picture = tester.getTopLeft(find.byKey(const ValueKey('picture')));
      expect(await pixel(tester, const Offset(100, 110)), Colors.white, reason: 'the middle stays clear');
      for (final bar in ['room-top-bar', 'room-bottom-bar']) {
        final rect = tester.getRect(find.byKey(ValueKey(bar))).shift(-picture);
        // The button's padding at the left edge: scrim, no glyph. The whole
        // height of the bar is covered, not only the edge of the picture.
        for (final y in [rect.top + 1, rect.center.dy, rect.bottom - 1]) {
          final behind = await pixel(tester, Offset(2, y));
          expect(behind, const Color(0xFF666666), reason: '$bar at $y: 60% black over white');
          expect(contrast(Colors.white, behind), greaterThanOrEqualTo(4.5), reason: bar);
        }
      }
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('principles §2.3: text on the picture grows at most 1.3×', (tester) async {
    await pumpPlayer(
      tester,
      presentation: RoomPresentation.fullscreen,
      size: const Size(800, 400),
      textScaler: const TextScaler.linear(2),
    );
    final title = find.descendant(of: find.byKey(const ValueKey('room-top-bar')), matching: find.byType(Text)).first;
    expect(MediaQuery.textScalerOf(tester.element(title)).scale(10), 13);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the lock sits on the left edge, white on black, clear of the chat on the right', (tester) async {
    await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400));
    final lock = find.byKey(const ValueKey('room-lock'));
    final rect = tester.getRect(lock);
    final picture = tester.getRect(find.byType(PlayerView));
    expect(rect.left - picture.left, lessThan(24));
    expect(rect.right, lessThan(picture.left + picture.width * 0.6), reason: 'the chat overlay takes the right 40%');
    final style = tester.widget<IconButton>(lock).style!;
    expect(style.backgroundColor!.resolve({}), VideoBarScrim.color);
    expect(style.foregroundColor!.resolve({}), Colors.white);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('principles §6.5: a tip shows at the top left under the bar and goes after 3 s or a tap', (tester) async {
    final player = await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400))
      ..showTip('按 C 收起聊天栏');
    await tester.pump();
    final tip = find.byKey(const ValueKey('room-tip'));
    final picture = tester.getRect(find.byType(PlayerView));
    final rect = tester.getRect(tip);
    expect(rect.left - picture.left, lessThan(24));
    expect(rect.top, greaterThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('room-top-bar'))).bottom));
    expect(rect.bottom, lessThan(picture.center.dy), reason: 'off the middle of the picture');
    await tester.pump(const Duration(seconds: 3));
    expect(tip, findsNothing);

    player.showTip('按 C 收起聊天栏');
    await tester.pump();
    await tester.tap(tip);
    await tester.pump();
    expect(tip, findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the top bar back button goes to the page', (tester) async {
    await pumpPlayer(tester, presentation: RoomPresentation.fullscreen, size: const Size(800, 400));
    await tester.tap(find.byTooltip('返回'));
    expect(calls.back, 1);
  });
}
