// The room's mini windows of U.2j (docs/ui/compare/U.2j/README.md): the
// in-app floating window, Android's picture-in-picture and the desktop mini
// window share one player and one set of buttons.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/desktop/mini_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/floating_window.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A platform whose detail can be held back ([hold]) to see the room load.
class _GatedSite extends FakeSite {
  new(super.room);

  Completer<void>? hold;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    await hold?.future;
    return await super.getRoomDetail(roomId: roomId);
  }
}

final class _App {
  new(this.services, this.site, this.engines, this.toasts, this.router);

  final AppServices services;
  final FakeSite site;
  final List<FakeEngine> engines;
  final List<String> toasts;
  final GoRouter router;

  FakeEngine get engine => engines.last;
}

/// The app's shape: a home page, the room and multi-view, with the floating
/// window over them (as `PureLiveApp` puts it).
Future<_App> _app(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  bool floatPlay = true,
  FakeSite? site,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() => services.store.settings.set(Settings.floatPlay, floatPlay));
  final engines = <FakeEngine>[];
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final platform = site ?? FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  final router = GoRouter(
    initialLocation: RoutePath.kInitial,
    observers: [liveRouteObserver],
    routes: [
      GoRoute(
        path: RoutePath.kInitial,
        pageBuilder: (context, state) => MaterialPage<Object?>(
          key: state.pageKey,
          name: RoutePath.kInitial,
          child: const Scaffold(body: Center(child: Text('首页'))),
        ),
      ),
      GoRoute(
        path: RoutePath.kLivePlay,
        pageBuilder: (context, state) => liveRoomPage(
          key: state.pageKey,
          arguments: state.extra,
          child: LivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: state.extra)),
        ),
      ),
      GoRoute(
        path: RoutePath.kMultiview,
        pageBuilder: (context, state) => MaterialPage<Object?>(
          key: state.pageKey,
          name: RoutePath.kMultiview,
          child: const Scaffold(body: Text('多画面')),
        ),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => platform})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) {
          final engine = FakeEngine();
          engines.add(engine);
          return fakeSession(engine);
        }),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: const LiveTheme().light,
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child!,
            const Positioned.fill(child: FloatingRoomLayer()),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
  return _App(services, platform, engines, toasts, router);
}

Future<void> _settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openRoom(WidgetTester tester, [LiveRoom? room]) async {
  await AppNavigator.toLiveRoomDetail(
    liveRoom: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
}

Future<void> _leaveRoom(WidgetTester tester, _App app) async {
  app.router.pop();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
}

Future<void> _close(WidgetTester tester, _App app) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(app.services.close);
}

final Finder _window = find.byKey(const ValueKey('floating-window'));

Finder _inWindow(Finder finder) => find.descendant(of: _window, matching: finder);

Finder _inKey(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);

double _opacityOf(WidgetTester tester, String key) => tester
    .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedOpacity)).first)
    .opacity;

/// A window system that does what it is asked (the desktop mini window).
final class _FakeHost implements MiniWindowHost {
  final List<String> calls = [];
  @override
  bool canPin = true;

  @override
  Future<void> enter({required double aspectRatio, required bool onTop}) async =>
      calls.add('enter ${aspectRatio.toStringAsFixed(2)} onTop=$onTop');

  @override
  Future<void> exit() async => calls.add('exit');

  @override
  Future<void> setOnTop({required bool onTop}) async => calls.add('onTop=$onTop');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> saveGeometry() async => calls.add('save');
}

void main() {
  tearDown(() async {
    PictureInPicture.active.value = false;
    PictureInPicture.debugAndroid = null;
    DesktopWindow.miniHost = null;
    DesktopWindow.mini.value = false;
  });

  group('rules', () {
    test('c6: the in-app window is the short side × 0.56 within 220–360; portrait pictures 1.2 × high', () {
      expect(inAppMiniSize(screen: const Size(393, 852), aspectRatio: 16 / 9).width, closeTo(220.08, 0.01));
      expect(inAppMiniSize(screen: const Size(360, 640), aspectRatio: 16 / 9), const Size(220, 220 / (16 / 9)));
      expect(inAppMiniSize(screen: const Size(852, 393), aspectRatio: 16 / 9).width, closeTo(220.08, 0.01));
      expect(inAppMiniSize(screen: const Size(1280, 800), aspectRatio: 16 / 9), const Size(360, 202.5));
      expect(inAppMiniSize(screen: const Size(1920, 1080), aspectRatio: 16 / 9).width, 360);
      // 3.x: a 9:16 picture on a phone is 149 × 264.
      final portrait = inAppMiniSize(screen: const Size(360, 640), aspectRatio: 9 / 16);
      expect(portrait.height, 264);
      expect(portrait.width, closeTo(148.5, 0.01));
    });

    test('c6: bottom-right, above the home bar on narrow home pages, 16 from the edges; kept on screen', () {
      expect(inAppMiniBottomClearance(route: RoutePath.kInitial, width: 393, safeBottom: 24), 24 + 80 + 16);
      expect(inAppMiniBottomClearance(route: RoutePath.kInitial, width: 852, safeBottom: 0), 16);
      expect(inAppMiniBottomClearance(route: RoutePath.kSettings, width: 393, safeBottom: 0), 16);
      const window = Size(220, 124);
      expect(
        inAppMiniOffset(area: const Size(393, 852), window: window, bottomClearance: 96, topClearance: 40),
        const Offset(393 - 16 - 220, 852 - 96 - 124),
      );
      // Dragged out of a window that then shrank: back inside.
      expect(
        inAppMiniOffset(
          area: const Size(852, 393),
          window: window,
          bottomClearance: 16,
          topClearance: 16,
          dragged: const Offset(700, 800),
        ),
        const Offset(852 - 16 - 220, 393 - 16 - 124),
      );
      expect(
        inAppMiniOffset(
          area: const Size(852, 393),
          window: window,
          bottomClearance: 16,
          topClearance: 16,
          dragged: const Offset(-50, -50),
        ),
        const Offset(16, 16),
      );
    });

    test('c7: the danmaku keeps 10 or more with automatic scaling, three lanes in a 220 window', () {
      final phone = CompactDanmakuMetrics.resolve(width: 220, autoScale: true, fontSize: 12, speed: 90);
      expect(phone.fontSize, 10, reason: '3.x: 12 × 0.65 = 7.8');
      expect((124 * 0.5 / phone.laneHeight).floor(), 3);
      expect(CompactDanmakuMetrics.resolve(width: 360, autoScale: true, fontSize: 12, speed: 90).fontSize, 12);
      // The user's own smaller size stays.
      expect(CompactDanmakuMetrics.resolve(width: 220, autoScale: true, fontSize: 8, speed: 90).fontSize, 8);
      expect(CompactDanmakuMetrics.resolve(width: 220, autoScale: false, fontSize: 12, speed: 90).fontSize, 12);
      expect(CompactDanmakuMetrics.resolve(width: 220, autoScale: true, fontSize: 12, speed: 90).speed, 90 * 0.65);
    });

    test('the danmaku frame rate: 30, 60 or the display; a manual rate stays', () {
      int fps(String mode, {bool automatic = true}) =>
          compactDanmakuFps(automatic: automatic, configured: 45, mode: mode, maxRefreshRate: 120);
      expect(fps('powerSaving'), 30);
      expect(fps('balanced'), 60);
      expect(fps('performance'), 120);
      expect(fps('performance', automatic: false), 45);
    });

    test('c8: the status a mini window shows', () {
      MiniStatus of(RoomStage stage, PlaybackStatus playback, {bool reconnecting = false}) =>
          miniStatusOf(stage: stage, playback: playback, reconnecting: reconnecting);
      expect(of(RoomStage.loading, PlaybackStatus.idle), MiniStatus.loading);
      expect(of(RoomStage.playing, PlaybackStatus.opening), MiniStatus.loading);
      expect(of(RoomStage.playing, PlaybackStatus.playing), MiniStatus.playing);
      expect(of(RoomStage.playing, PlaybackStatus.paused), MiniStatus.paused);
      expect(of(RoomStage.playing, PlaybackStatus.buffering), MiniStatus.buffering);
      expect(of(RoomStage.playing, PlaybackStatus.buffering, reconnecting: true), MiniStatus.reconnecting);
      expect(of(RoomStage.playing, PlaybackStatus.error, reconnecting: true), MiniStatus.failed);
      expect(of(RoomStage.offline, PlaybackStatus.idle), MiniStatus.failed);
      expect(of(RoomStage.unplayable, PlaybackStatus.idle), MiniStatus.failed);
    });

    test('appendix A 8: only a playing room floats, not on purpose, not under another room', () {
      bool float({
        bool enabled = true,
        RoomStage stage = RoomStage.playing,
        bool suppressed = false,
        String top = '/home',
      }) => shouldFloatOnLeave(enabled: enabled, stage: stage, suppressed: suppressed, topRoute: top);
      expect(float(), isTrue);
      expect(float(enabled: false), isFalse);
      expect(float(stage: RoomStage.failed), isFalse);
      expect(float(stage: RoomStage.offline), isFalse);
      expect(float(suppressed: true), isFalse);
      expect(float(top: RoutePath.kLivePlay), isFalse);
      expect(float(top: RoutePath.kMultiview), isFalse);
    });

    test('J1: leaving enters picture-in-picture only while the picture plays on top', () {
      bool auto({
        bool enabled = true,
        bool onTop = true,
        PlaybackStatus status = PlaybackStatus.playing,
        bool audioOnly = false,
        RoomStage stage = RoomStage.playing,
      }) => shouldAutoEnterPip(enabled: enabled, onTop: onTop, stage: stage, status: status, audioOnly: audioOnly);
      expect(auto(), isTrue);
      expect(auto(enabled: false), isFalse, reason: 'off by default');
      expect(auto(onTop: false), isFalse);
      expect(auto(status: PlaybackStatus.paused), isFalse);
      expect(auto(audioOnly: true), isFalse);
      expect(auto(stage: RoomStage.offline), isFalse);
    });

    test('the desktop mini window: 3.x sizes, bottom-right 20 from the edges, remembered place kept on screen', () {
      expect(miniWindowSize(16 / 9), const Size(360, 202.5));
      expect(miniWindowSize(9 / 16), const Size(380 * 9 / 16, 380));
      expect(miniWindowSize(1), const Size(280, 280));
      const work = Rect.fromLTWH(0, 0, 1280, 752);
      expect(
        resolveMiniWindowBounds(defaultSize: const Size(360, 202.5), primaryWorkArea: work, workAreas: [work]),
        const Rect.fromLTWH(1280 - 20 - 360, 752 - 20 - 202.5, 360, 202.5),
      );
      // A monitor that is gone: back on the one there is.
      expect(
        resolveMiniWindowBounds(
          defaultSize: const Size(360, 202.5),
          primaryWorkArea: work,
          workAreas: [work],
          saved: const Rect.fromLTWH(3000, 100, 400, 225),
        ),
        const Rect.fromLTWH(1280 - 400, 100, 400, 225),
      );
    });

    test("text only leaves the platform's picture codes out", () {
      expect(withoutEmoteCodes('好耶[doge][doge]', ['[doge]']), '好耶');
      expect(withoutEmoteCodes('[doge]', ['[doge]']), '');
    });
  });

  group('in-app floating window', () {
    testWidgets('appendix A 8, c2, c6, c10: leaving a playing room floats it bottom-right with the same player', (
      tester,
    ) async {
      final app = await _app(tester);
      await _openRoom(tester);
      expect(app.engines, hasLength(1));
      expect(app.engine.opens, hasLength(1));
      await _leaveRoom(tester, app);

      expect(find.text('首页'), findsOneWidget);
      expect(_window, findsOneWidget);
      final rect = tester.getRect(_window);
      expect(rect.width, closeTo(220.08, 0.01));
      expect(rect.right, 393 - 16);
      expect(rect.bottom, closeTo(852 - 80 - 16, 0.01), reason: "above the home page's bottom bar");
      expect(app.engine.disposed, isFalse, reason: 'the player plays on');
      expect(_inWindow(find.byType(LiveVideoView)), findsOneWidget);
      // c10: square corners and a floating shadow, nothing clipped.
      final frame = tester.widget<DecoratedBox>(
        find.ancestor(of: find.byType(MiniPlayerSurface), matching: find.byType(DecoratedBox)).first,
      );
      expect((frame.decoration as BoxDecoration).borderRadius, isNull);
      expect((frame.decoration as BoxDecoration).boxShadow, OnVideoColors.floatingShadow);
      expect(_inWindow(find.byType(ClipRRect)), findsNothing);

      // c2: back top left, close top right, pause in the centre; 45 % black.
      expect(_inKey('mini-back', find.byIcon(AppIcons.backToRoom)), findsOneWidget);
      expect(_inKey('mini-close', find.byIcon(AppIcons.close)), findsOneWidget);
      expect(_inKey('mini-play-pause', find.byIcon(AppIcons.miniPause)), findsOneWidget);
      final back = tester.getRect(find.byKey(const ValueKey('mini-back')));
      final close = tester.getRect(find.byKey(const ValueKey('mini-close')));
      final centre = tester.getRect(find.byKey(const ValueKey('mini-play-pause')));
      expect(back.topLeft - rect.topLeft, const Offset(4, 4));
      expect(back.size, const Size(48, 48));
      expect(rect.right - close.right, closeTo(4, 0.01));
      expect(close.top - rect.top, 4);
      expect(centre.center.dx, closeTo(rect.center.dx, 0.01));
      expect(centre.size, const Size(58, 58));
      final style = tester.widget<IconButton>(_inKey('mini-close', find.byType(IconButton))).style!;
      expect(style.backgroundColor!.resolve({}), OnVideoColors.button);
      expect(OnVideoColors.button.a, closeTo(0.45, 0.01));

      // The buttons go after 3 s; a tap brings them, a tap while they show
      // goes back to the room, which plays on (no new player).
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'mini-back'), 0);
      await tester.tapAt(rect.topLeft + const Offset(60, 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'mini-back'), 1);
      await tester.tapAt(rect.topLeft + const Offset(60, 100));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(_window, findsNothing);
      expect(find.byKey(const ValueKey('live-play-portrait-stack')), findsOneWidget);
      expect(app.engines, hasLength(1), reason: 'the same player');
      expect(app.engine.opens, hasLength(1), reason: 'not opened again');

      // ✕ stops it.
      await _leaveRoom(tester, app);
      expect(_window, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mini-close')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_window, findsNothing);
      expect(app.engine.disposed, isTrue);
      await _close(tester, app);
    });

    testWidgets('c8: paused keeps the play button; audio only fits; a drop dims and says "正在重连"', (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      final engine = app.engine;

      await tester.tap(find.byKey(const ValueKey('mini-play-pause')));
      await _settle(tester);
      expect(_inKey('mini-play-pause', find.byIcon(AppIcons.miniPlay)), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'mini-play-pause'), 1, reason: 'paused: always shown');
      expect(_opacityOf(tester, 'mini-back'), 0);
      await tester.tap(find.byKey(const ValueKey('mini-play-pause')));
      await _settle(tester);
      expect(_inKey('mini-play-pause', find.byIcon(AppIcons.miniPause)), findsOneWidget);

      // A playing stream that drops.
      engine.emit(const EngineBuffering(buffering: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-reconnecting')), findsOneWidget);
      expect(_inKey('mini-reconnecting', find.text('正在重连')), findsOneWidget);
      engine.emit(const EngineBuffering(buffering: false));
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-reconnecting')), findsNothing);

      // Audio only: the streamer's picture and "纯音频模式", inside 124.
      await tester.runAsync(() => FloatingRoom.instance.runtime!.controller.setAudioOnly(enabled: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-audio-only')), findsOneWidget);
      expect(_inKey('mini-audio-only', find.text('纯音频模式')), findsOneWidget);
      final chip = tester.getRect(_inKey('mini-audio-only', find.text('纯音频模式')));
      expect(tester.getRect(_window).contains(chip.bottomCenter - const Offset(0, 1)), isTrue);
      await _close(tester, app);
    });

    testWidgets("c7: the floating window's danmaku is 10 high in three lanes, six at most, 30 frames", (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      final overlay = tester.widget<DanmakuOverlay>(_inWindow(find.byType(DanmakuOverlay)));
      expect(overlay.look.fontSize, 10);
      expect(overlay.look.laneHeight, 20);
      expect(overlay.maxVisible, 6);
      expect(overlay.fps, 30);
      expect(overlay.color, isNull, reason: "the platform's colours by default");
      await tester.runAsync(() => app.services.store.settings.set(Settings.enablePipDanmaku, false));
      await _settle(tester);
      expect(tester.widget<DanmakuOverlay>(_inWindow(find.byType(DanmakuOverlay))).visible, isFalse);
      await _close(tester, app);
    });

    testWidgets('appendix A 8: menus and dialogs hide it, it plays on; multi-view and other rooms close it', (
      tester,
    ) async {
      final app = await _app(tester);
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      expect(_window, findsOneWidget);

      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorContext!,
          builder: (context) => const AlertDialog(content: Text('对话框')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_window, findsNothing);
      expect(find.byKey(const ValueKey('floating-window'), skipOffstage: false), findsOneWidget);
      expect(app.engine.disposed, isFalse);
      Navigator.of(tester.element(find.text('对话框'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_window, findsOneWidget);

      // Another room: the floating one stops, the new room has its own player.
      final first = app.engine;
      await _openRoom(tester, LiveRoom(platform: SiteIds.bilibili, roomId: '7', nick: '另一位'));
      expect(first.disposed, isTrue);
      expect(app.engines, hasLength(2));

      // Multi-view closes it too.
      await _leaveRoom(tester, app);
      expect(_window, findsOneWidget);
      unawaited(AppNavigator.toMultiview());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(app.engine.disposed, isTrue);
      expect(find.byKey(const ValueKey('floating-window'), skipOffstage: false), findsNothing);
      await _close(tester, app);
    });

    testWidgets('appendix A 8: off, or a room that does not play, leaves nothing behind', (tester) async {
      final app = await _app(tester, floatPlay: false);
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      expect(_window, findsNothing);
      // F.1d: with "播放器强制销毁" off (3.x's default) the stopped player
      // waits 45 s for the next room, then goes.
      expect(app.engine.disposed, isFalse);
      await tester.pump(const Duration(seconds: 46));
      expect(app.engine.disposed, isTrue);
      await _close(tester, app);

      final offline = await _app(tester, site: FakeSite(liveRoom(status: LiveStatus.offline)));
      await _openRoom(tester);
      await _leaveRoom(tester, offline);
      expect(_window, findsNothing);
      await _close(tester, offline);
    });

    testWidgets(
      'c6: landscape and wide windows put it 16 from the corner; 360 wide on a tablet; drags stay on screen',
      (tester) async {
        final app = await _app(tester, size: const Size(852, 393));
        await _openRoom(tester);
        await _leaveRoom(tester, app);
        var rect = tester.getRect(_window);
        expect(rect.width, closeTo(220.08, 0.01));
        expect(rect.right, 852 - 16);
        expect(rect.bottom, 393 - 16, reason: 'no bottom bar beside a side rail');

        // Dragged up and left (80 % while dragged), then the window turns.
        final gesture = await tester.startGesture(rect.topLeft + const Offset(60, 100));
        await gesture.moveBy(const Offset(-30, 0));
        await gesture.moveBy(const Offset(-300, -150));
        await tester.pump();
        expect(
          tester
              .widget<AnimatedOpacity>(find.descendant(of: _window, matching: find.byType(AnimatedOpacity)).first)
              .opacity,
          0.8,
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        final moved = tester.getRect(_window);
        expect(moved.left, lessThan(rect.left - 200));
        tester.view.physicalSize = const Size(393, 852);
        await tester.pump();
        rect = tester.getRect(_window);
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(393 - 16));
        await _close(tester, app);

        final wide = await _app(tester, size: const Size(1280, 800));
        await _openRoom(tester);
        await _leaveRoom(tester, wide);
        rect = tester.getRect(_window);
        expect(rect.size, const Size(360, 202.5));
        expect(rect.bottomRight, const Offset(1280 - 16, 800 - 16));
        await _close(tester, wide);
      },
    );

    testWidgets('c8: loading on black, the end of a broadcast with refresh, a portrait picture 1.2 × high', (
      tester,
    ) async {
      final site = _GatedSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
      final app = await _app(tester, site: site);
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      final controller = FloatingRoom.instance.runtime!.controller;

      // A portrait stream: 149 × 264 as 3.x.
      app.engine.emit(const EngineVideoSize(720, 1280));
      await tester.pump();
      final portrait = tester.getRect(_window);
      expect(portrait.height, closeTo(264.1, 0.1));
      expect(portrait.width, closeTo(148.6, 0.1));
      expect(portrait.right, 393 - 16);

      // Reloading: a spinner on black, no centre button.
      site.hold = Completer();
      unawaited(controller.load());
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-play-pause')), findsNothing);
      // The broadcast ended meanwhile: dimmed, the reason, refresh in the
      // centre (always shown).
      site.room = liveRoom(status: LiveStatus.offline);
      site.hold!.complete();
      await _settle(tester);
      expect(find.byKey(const ValueKey('mini-failed')), findsOneWidget);
      expect(_inKey('mini-retry', find.byIcon(AppIcons.refresh)), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'mini-retry'), 1);
      expect(_opacityOf(tester, 'mini-close'), 0);
      await _close(tester, app);
    });

    testWidgets('a mouse shows the buttons while it hovers and a double click goes back to the room', (tester) async {
      final app = await _app(tester, size: const Size(1280, 800));
      await _openRoom(tester);
      await _leaveRoom(tester, app);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      final rect = tester.getRect(_window);
      expect(_opacityOf(tester, 'mini-back'), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(rect.topLeft + const Offset(80, 150));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'mini-back'), 1);
      // One click does nothing; two go back.
      await tester.tapAt(rect.topLeft + const Offset(80, 150), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_window, findsOneWidget);
      await tester.tapAt(rect.topLeft + const Offset(80, 150), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(_window, findsNothing);
      expect(find.byKey(const ValueKey('live-play-desktop-split')), findsOneWidget);
      expect(app.engines, hasLength(1));
      await _close(tester, app);
    });
  });

  group('desktop mini window', () {
    testWidgets('c2-c4, J2, J3: the window shrinks; back, close, pause, pin, wheel volume, Esc', (tester) async {
      final host = _FakeHost();
      DesktopWindow.miniHost = host;
      final app = await _app(tester, size: const Size(1280, 800));
      await _openRoom(tester);
      final button = find.byKey(const ValueKey('live-play-pip'));
      expect(button, findsOneWidget, reason: 'the desktop has the mini window');
      await tester.tap(button);
      await _settle(tester);
      expect(host.calls, ['enter 1.78 onTop=false']);
      expect(DesktopWindow.mini.value, isTrue);
      final surface = tester.widget<MiniPlayerSurface>(find.byType(MiniPlayerSurface));
      expect(surface.kind, MiniKind.desktop);
      expect(find.byKey(const ValueKey('live-play-desktop-split')), findsNothing, reason: 'only the picture');

      // The pin at the bottom right; on: the theme's primary colour.
      final view = tester.getRect(find.byType(MiniPlayerSurface));
      final pin = tester.getRect(find.byKey(const ValueKey('mini-pin')));
      expect(view.bottomRight - pin.bottomRight, const Offset(4, 4));
      expect(_inKey('mini-pin', find.byIcon(AppIcons.unpinned)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mini-pin')));
      await _settle(tester);
      expect(app.services.store.settings.get(Settings.windowsPipAlwaysOnTop), isTrue);
      expect(host.calls.last, 'onTop=true');
      expect(_inKey('mini-pin', find.byIcon(AppIcons.pinned)), findsOneWidget);
      final scheme = Theme.of(tester.element(find.byType(MiniPlayerSurface))).colorScheme;
      final pinStyle = tester.widget<IconButton>(find.byKey(const ValueKey('mini-pin'))).style!;
      expect(pinStyle.backgroundColor!.resolve({}), scheme.primary);

      // c4: the wheel changes the room's volume and shows the bar.
      final controller = FloatingRoomProbe.controllerOf(tester);
      final before = controller.volume;
      tester.binding.handlePointerEvent(PointerScrollEvent(position: view.center, scrollDelta: const Offset(0, 20)));
      await tester.pump();
      await _settle(tester, rounds: 2);
      expect(controller.volume, closeTo(before - 0.05, 0.001));
      expect(find.byKey(const ValueKey('mini-volume')), findsOneWidget);

      // Esc goes back to the room (c4).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(host.calls.last, 'exit');
      expect(find.byKey(const ValueKey('live-play-desktop-split')), findsOneWidget);
      expect(DesktopWindow.mini.value, isFalse);

      // ✕ (J3): stops, back to the page before the room, down to the taskbar;
      // no floating window even with "退出小窗播放" on.
      await tester.tap(find.byKey(const ValueKey('live-play-pip')));
      await _settle(tester);
      expect(host.calls.last, 'enter 1.78 onTop=true', reason: 'the pin is remembered');
      await tester.tap(find.byKey(const ValueKey('mini-close')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(host.calls.sublist(host.calls.length - 3), ['hide', 'exit', 'minimize']);
      expect(find.text('首页'), findsOneWidget);
      expect(_window, findsNothing);
      // F.1d: the stopped player waits 45 s for the next room ("播放器强制销毁"
      // off), then goes.
      await tester.pump(const Duration(seconds: 46));
      expect(app.engine.disposed, isTrue);
      await _close(tester, app);
    });

    testWidgets('c5: a desktop that refuses "on top" greys the pin and says why', (tester) async {
      final host = _FakeHost()..canPin = false;
      DesktopWindow.miniHost = host;
      final app = await _app(tester, size: const Size(1280, 800));
      await _openRoom(tester);
      await tester.tap(find.byKey(const ValueKey('live-play-pip')));
      await _settle(tester);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('mini-pin'))).onPressed, isNull);
      expect(find.byTooltip('这个桌面不支持置顶'), findsOneWidget);
      // Back by a double click.
      final view = tester.getRect(find.byType(MiniPlayerSurface));
      await tester.tapAt(view.topLeft + const Offset(100, 150), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(view.topLeft + const Offset(100, 150), kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(host.calls.last, 'exit');
      await _close(tester, app);
    });
  });

  group('Android picture-in-picture', () {
    late List<MethodCall> calls;
    late String status;
    late String entry;

    setUp(() {
      calls = [];
      status = 'allowed';
      entry = 'entered';
      PictureInPicture.debugAndroid = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pure_live/pip'),
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'isSupported' => true,
            'status' => status,
            'enter' => () {
              if (entry == 'entered') PictureInPicture.active.value = true;
              return entry;
            }(),
            'openSettings' => true,
            _ => null,
          };
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pure_live/pip'),
        null,
      );
    });

    testWidgets('c9: turned off in the system settings: the dialog and "去设置"', (tester) async {
      status = 'disabled';
      final app = await _app(tester);
      await _openRoom(tester);
      await tester.tap(find.byKey(const ValueKey('live-play-pip')));
      await _settle(tester);
      expect(find.text('无法打开画中画'), findsOneWidget);
      expect(find.text('系统设置里关掉了“纯粹直播”的画中画。打开后再点小窗按钮。'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-open-settings')));
      await _settle(tester);
      expect(calls.map((call) => call.method), contains('openSettings'));
      expect(calls.map((call) => call.method), isNot(contains('enter')));
      await _close(tester, app);
    });

    testWidgets('the picture alone with the danmaku and no buttons of ours; a refusal says so', (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      await tester.tap(find.byKey(const ValueKey('live-play-pip')));
      await _settle(tester);
      expect(calls.where((call) => call.method == 'enter'), hasLength(1));
      final surface = tester.widget<MiniPlayerSurface>(find.byType(MiniPlayerSurface));
      expect(surface.kind, MiniKind.systemPip);
      expect(find.byKey(const ValueKey('mini-back')), findsNothing);
      expect(find.byKey(const ValueKey('mini-close')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-fullscreen')), findsNothing);
      expect(
        find.descendant(of: find.byType(MiniPlayerSurface), matching: find.byType(DanmakuOverlay)),
        findsOneWidget,
      );
      PictureInPicture.active.value = false;
      await _settle(tester);
      expect(find.byType(MiniPlayerSurface), findsNothing);

      entry = 'failed';
      await tester.tap(find.byKey(const ValueKey('live-play-pip')));
      await _settle(tester);
      expect(app.toasts, contains('打开画中画失败，请重试'));
      expect(find.byType(MiniPlayerSurface), findsNothing);
      await _close(tester, app);
    });

    testWidgets('J1: "离开应用时自动小窗" arms leaving only while the picture plays', (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      List<bool> armed() => [
        for (final call in calls)
          if (call.method == 'setAutoEnter') (call.arguments as Map)['enabled'] as bool,
      ];
      expect(armed().where((value) => value), isEmpty, reason: 'off by default');
      await tester.runAsync(() => app.services.store.settings.set(Settings.autoPipOnLeave, true));
      await _settle(tester);
      expect(armed().last, isTrue);
      final controller = FloatingRoomProbe.controllerOf(tester);
      await tester.runAsync(controller.session.pause);
      await _settle(tester);
      expect(armed().last, isFalse, reason: 'paused');
      await tester.runAsync(controller.session.resume);
      await _settle(tester);
      expect(armed().last, isTrue);
      await tester.runAsync(() => controller.setAudioOnly(enabled: true));
      await _settle(tester);
      expect(armed().last, isFalse, reason: 'audio only');
      await _leaveRoom(tester, app);
      expect(armed().last, isFalse, reason: 'left the room');
      await _close(tester, app);
    });
  });
}

/// Reaches the room's controller through the page's player.
abstract final class FloatingRoomProbe {
  static LiveRoomController controllerOf(WidgetTester tester) {
    final runtime = FloatingRoom.instance.runtime;
    if (runtime != null) return runtime.controller;
    return tester.widget<RoomPlayer>(find.byType(RoomPlayer).first).controller;
  }
}
