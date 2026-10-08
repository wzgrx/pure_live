// The room's small features of F.1b-F.1d (docs/README.md): the
// portrait layout before the first frame, the Kuaishou app link, the room
// switcher's refresh, Android's back held by the room, the player kept for
// the next room, the mini windows' portrait ratio, the portrait
// diagnostics, the memory pressure and the media keys.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/predictive_back.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/floating_window.dart';
import 'package:pure_live/features/live_play/player/portrait_diagnostics.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A platform whose lines declare a picture size (Douyin's `sdk_params`).
class _SizedSite extends FakeSite implements LivePlayUrlResolver {
  new(super.room, {this.width, this.height});

  final int? width;
  final int? height;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution.lines([
    LivePlayLine('https://a.example/${quality.id}.flv', width: width, height: height),
  ], appliedQualityData: quality.id);
}

final class _App {
  new(this.services, this.engines, this.sessions, this.router, this.back);

  final AppServices services;
  final List<FakeEngine> engines;
  final List<PlaybackSession> sessions;
  final GoRouter router;

  /// `setEnabled` calls on `pure_live/predictive_back`.
  final List<bool> back;

  FakeEngine get engine => engines.last;
}

const _channel = 'pure_live/predictive_back';

/// A home page and the room, with the floating window over them (as
/// `PureLiveApp`).
Future<_App> _app(
  WidgetTester tester, {
  FakeSite? site,
  bool floatPlay = false,
  Map<Setting<Object>, Object> settings = const {},
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  RoomBackChannel.instance.reset();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() => services.store.settings.set(Settings.floatPlay, floatPlay));
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  final back = <bool>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), (call) async {
    if (call.method == 'setEnabled') back.add((call.arguments as Map)['enabled'] as bool);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), null),
  );
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previousToast);
  final engines = <FakeEngine>[];
  final sessions = <PlaybackSession>[];
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
          final session = fakeSession(engine);
          sessions.add(session);
          return session;
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
  return _App(services, engines, sessions, router, back);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openRoom(WidgetTester tester, [String roomId = '6']) async {
  await AppNavigator.toLiveRoomDetail(
    liveRoom: LiveRoom(platform: SiteIds.bilibili, roomId: roomId, nick: '主播'),
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
  await FloatingRoom.instance.reset();
  await tester.runAsync(app.services.close);
  debugDefaultTargetPlatformOverride = null;
}

/// The system's back, as `MainActivity` hands it over.
Future<void> _nativeBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel,
    const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
    (_) {},
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  group('F.1b portrait before the first frame', () {
    testWidgets('a line declaring a portrait picture lays the room out as portrait; the decoder wins', (tester) async {
      final app = await _app(tester, site: _SizedSite(liveRoom(), width: 1088, height: 1920));
      await _openRoom(tester);
      expect(app.engine.opens, hasLength(1));
      expect(_key('live-play-portrait-panel'), findsOneWidget, reason: 'no frame yet, the line says portrait');
      app.engine.emit(const EngineVideoSize(1920, 1080));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-portrait-panel'), findsNothing);
      expect(
        _key('live-play-portrait-stack'),
        findsOneWidget,
        reason: 'the 16:9 stack once the decoder says landscape',
      );
      await _close(tester, app);
    });

    testWidgets('without a declared size the room starts as landscape (as before)', (tester) async {
      final app = await _app(tester, site: _SizedSite(liveRoom()));
      await _openRoom(tester);
      expect(_key('live-play-portrait-stack'), findsOneWidget);
      await _close(tester, app);
    });
  });

  group('F.1c', () {
    test('c1: Kuaishou opens its app by the broadcast id, from the detail or the danmaku arguments', () {
      const link =
          'kwai://liveaggregatesquare?liveStreamId=s%2B1&recoStreamId=s%2B1&recoLiveStreamId=s%2B1'
          '&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE';
      LiveRoom room({Object? data, Object? danmaku}) => LiveRoom(
        platform: SiteIds.kuaishou,
        roomId: 'abc',
        link: 'https://live.kuaishou.com/u/abc',
        data: data,
        danmakuData: danmaku,
      );
      final fromDetail = externalRoomTarget(room(data: const KuaishouRoomData(liveStreamId: 's+1')))!;
      expect(fromDetail.native.toString(), link);
      expect(fromDetail.web.toString(), 'https://live.kuaishou.com/u/abc');
      expect(
        externalRoomTarget(room(danmaku: const KuaishouDanmakuArgs(liveStreamId: ' s+1 ')))!.native.toString(),
        link,
      );
      expect(externalRoomTarget(room(data: const KuaishouRoomData()))!.native, isNull, reason: 'off air: the web');
    });

    testWidgets("c2: the app links the switcher's refresh to the follows", (tester) async {
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        await services.store.settings.set(Settings.showSplashPage, false);
        return services;
      }))!;
      final strings = (await tester.runAsync(loadStrings))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
        ),
      );
      await tester.pump();
      // B05: the switch panel's refresh and its last time (room_switch_test).
      final follows = RoomSwitchPanel.follows;
      expect(follows, isNotNull);
      expect(follows!.lastRefreshedAt(), isNull, reason: 'nothing refreshed yet');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(RoomSwitchPanel.follows, isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.close);
    });

    testWidgets("c3: Android's back: the room holds it; a dialog, then fullscreen, then the room", (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      expect(app.back, [true], reason: 'the room took the back');

      // Fullscreen: back leaves it, the room stays.
      await tester.tap(_key('live-play-fullscreen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-portrait-stack'), findsNothing);
      await _nativeBack(tester);
      expect(_key('live-play-portrait-stack'), findsOneWidget);

      // A dialog over the room closes first.
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorContext!,
          builder: (context) => const AlertDialog(content: Text('对话框')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _nativeBack(tester);
      expect(find.text('对话框'), findsNothing);
      expect(find.byType(LivePlayPage), findsOneWidget);

      // Then the room closes and gives the back up.
      await _nativeBack(tester);
      await _settle(tester);
      expect(find.byType(LivePlayPage), findsNothing);
      expect(find.text('首页'), findsOneWidget);
      expect(app.back, [true, false]);
      await _close(tester, app);
    });

    testWidgets('c3: a room taking over keeps the back when the one before closes', (tester) async {
      final calls = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), (call) async {
        calls.add((call.arguments as Map)['enabled'] as bool);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), null),
      );
      final channel = RoomBackChannel.instance..reset();
      final first = Object();
      final second = Object();
      var backs = '';
      await channel.hold(first, () async => backs += '1');
      await channel.hold(second, () async => backs += '2');
      await channel.release(first);
      expect(channel.held, isTrue);
      expect(calls, [true, true]);
      await _nativeBack(tester);
      expect(backs, '2');
      await channel.release(second);
      expect(calls, [true, true, false]);
      channel.reset();
    });
  });

  group('A07.19', () {
    testWidgets('back with the keyboard up only closes the keyboard; the next back reaches the room', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), (_) async => null);
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channel), null),
      );
      final channel = RoomBackChannel.instance..reset();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(focusNode: focus)),
        ),
      );
      var backs = 0;
      await channel.hold(Object(), () async => backs++);
      focus.requestFocus();
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await _nativeBack(tester);
      expect(backs, 0, reason: 'the keyboard goes first, as Android does for a plain back');
      expect(focus.hasFocus, isFalse);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await _nativeBack(tester);
      expect(backs, 1);
      channel.reset();
    });
  });

  group('F.1d', () {
    testWidgets('c1: "播放器强制销毁" off keeps the player for the next room; on releases it; a new setup gets a new one', (
      tester,
    ) async {
      final app = await _app(tester);
      await _openRoom(tester);
      final first = app.engine;
      await _leaveRoom(tester, app);
      expect(first.disposed, isFalse, reason: 'kept for the next room');

      await _openRoom(tester, '7');
      expect(app.engines, [first], reason: 'the next room plays on the same player');
      expect(first.opens, hasLength(2));

      // On: released at once, the next room builds its own.
      await tester.runAsync(() => app.services.store.settings.set(Settings.useHardStopOnExit, true));
      await _leaveRoom(tester, app);
      expect(first.disposed, isTrue);
      await _openRoom(tester);
      expect(app.engines, hasLength(2));

      // Off again, then the player is set up otherwise: the kept one goes.
      await tester.runAsync(() => app.services.store.settings.set(Settings.useHardStopOnExit, false));
      final second = app.engine;
      await _leaveRoom(tester, app);
      expect(second.disposed, isFalse);
      await tester.runAsync(() => app.services.store.settings.set(Settings.enableCodec, false));
      await _openRoom(tester);
      expect(app.engines, hasLength(3));
      expect(second.disposed, isTrue);
      await _close(tester, app);
    });

    test('c2: a portrait picture is 9:16 in the mini windows unless they follow its real ratio', () {
      expect(miniPictureSize(width: 600, height: 1280, portrait: true), (600, 1280));
      expect(miniPictureSize(width: 600, height: 1280, portrait: true, followPortrait: false), (9, 16));
      expect(miniPictureSize(width: 1440, height: 1080, followPortrait: false), (1440, 1080), reason: 'landscape');
      expect(miniPictureSize(portrait: true), (9, 16));
      expect(miniPictureSize(), (16, 9));
      // Before the first frame, the size the line declares (F.1b).
      const line = LivePlayLine('https://a.example/x.flv', width: 1088, height: 1920);
      final opening = const PlaybackState(
        status: PlaybackStatus.opening,
        line: line,
      ).copyWith(source: const LineSource(line));
      expect(expectedPictureSize(opening), (width: 1088, height: 1920));
      expect(expectedPictureSize(opening.copyWith(videoWidth: 1920, videoHeight: 1080)), (width: 1920, height: 1080));
      expect(expectedPictureSize(const PlaybackState()), (width: null, height: null));
    });

    testWidgets('c2: the floating window of a portrait room follows the setting', (tester) async {
      Future<Size> windowOf({required bool follow}) async {
        final app = await _app(tester, floatPlay: true, settings: {Settings.portraitPipFollowSource: follow});
        await _openRoom(tester);
        app.engine.emit(const EngineVideoSize(600, 1280));
        await tester.pump();
        await _leaveRoom(tester, app);
        final size = tester.getSize(_key('floating-window'));
        await _close(tester, app);
        return size;
      }

      // 220 × 1.2 high; the width by the ratio.
      expect((await windowOf(follow: true)).width, closeTo(264 * 600 / 1280, 0.1));
      expect((await windowOf(follow: false)).width, closeTo(264 * 9 / 16, 0.1));
    });

    test('c3: the diagnostics say the size, ratio, orientation, choice and where the size came from', () {
      const line = LivePlayLine('https://a.example/x.flv', width: 1088, height: 1920);
      final declared = const PlaybackState(
        status: PlaybackStatus.opening,
        line: line,
      ).copyWith(source: const LineSource(line));
      expect(portraitDiagnosticsText(declared, RoomOrientation.automatic), '1088×1920  0.567  竖屏  自动识别\n平台预判');
      expect(
        portraitDiagnosticsText(declared.copyWith(videoWidth: 1920, videoHeight: 1080), RoomOrientation.portrait),
        '1920×1080  1.778  横屏  强制竖屏\n解码尺寸',
      );
      expect(
        portraitDiagnosticsText(const PlaybackState(videoWidth: 1080, videoHeight: 1080), RoomOrientation.landscape),
        '1080×1080  1.000  近方形  强制横屏\n解码尺寸',
      );
      expect(portraitDiagnosticsText(const PlaybackState(), RoomOrientation.automatic), '--×--  --  等待尺寸  自动识别\n--');
    });

    testWidgets('c3: on the picture only with "显示识别状态" on', (tester) async {
      var app = await _app(tester);
      await _openRoom(tester);
      expect(_key('portrait-stream-diagnostics'), findsNothing);
      await _close(tester, app);
      app = await _app(tester, settings: {Settings.showPortraitDiagnostics: true});
      await _openRoom(tester);
      expect(_key('portrait-stream-diagnostics'), findsOneWidget);
      await _close(tester, app);
    });

    testWidgets('c5: memory pressure also drops the images on screen (3.x)', (tester) async {
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        await services.store.settings.set(Settings.showSplashPage, false);
        return services;
      }))!;
      final strings = (await tester.runAsync(loadStrings))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
        ),
      );
      await tester.pump();
      // A picture on screen: a cached completer with a listener.
      final cache = PaintingBinding.instance.imageCache;
      final completer = OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
      final listener = ImageStreamListener((_, _) {});
      cache.putIfAbsent(const ValueKey('on screen'), () => completer);
      completer.addListener(listener);
      expect(cache.liveImageCount, 1);
      tester.binding.handleMemoryPressure();
      expect(cache.liveImageCount, 0, reason: "Flutter's own clear() keeps the pictures on screen");
      completer.removeListener(listener);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.close);
    });

    testWidgets("c6: a keyboard's media keys pause, play and toggle", (tester) async {
      final app = await _app(tester);
      await _openRoom(tester);
      PlaybackStatus status() => app.sessions.single.state.status;
      expect(status(), PlaybackStatus.playing);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await _settle(tester);
      expect(status(), PlaybackStatus.paused);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await _settle(tester);
      expect(status(), PlaybackStatus.playing);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await _settle(tester);
      expect(status(), PlaybackStatus.paused);
      await _close(tester, app);
    });
  });
}
