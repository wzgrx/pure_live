// The room's three arrangements of one control layer (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏,
// U.2c, U.2d): landscape fullscreen, the wide room and portrait streams; the
// order, icons, places and states the confirmed designs fix.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/bar_parts.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';
import 'no_images.dart';

final class _Room {
  new(this.services, this.engine, this.orientations);

  final AppServices services;
  final FakeEngine engine;

  /// Orientations the page asked the system for, in order.
  final List<Object?> orientations;
}

Future<_Room> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  TargetPlatform platform = TargetPlatform.android,
  bool portrait = false,
  bool autoRotate = false,
  Map<Setting<Object>, Object> settings = const {},
  LiveRoom? detail,
  BaseCacheManager? images,
}) async {
  // Reset by [_close]: the test must end with it unset.
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  final orientations = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemChrome.setPreferredOrientations') orientations.add(call.arguments);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  const systemAccess = MethodChannel('pure_live/system_access');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, (call) async {
    if (call.method == 'sensorLandscape') orientations.add(call.method);
    return call.method != 'autoRotate' || autoRotate;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, null));
  final engine = FakeEngine();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(detail ?? liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        // With [images], pictures ask that cache (and get none).
        builder: images == null
            ? null
            : (context, child) => LiveUiScope(
                config: LiveUiConfig(imageCacheManager: images),
                child: child!,
              ),
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  if (portrait) {
    engine.emit(const EngineVideoSize(720, 1280));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return _Room(services, engine, orientations);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Shows the controls again (they hide after 4 s of quiet).
Future<void> _wake(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: tester.getCenter(find.byType(RoomPlayer)));
  await gesture.moveBy(const Offset(4, 4));
  await tester.pump(const Duration(seconds: 1));
  await gesture.removePointer();
}

/// The keys of [keys] found under [scope], left to right.
List<String> _order(WidgetTester tester, Finder scope, List<String> keys) => [
  for (final key in keys)
    if (find.descendant(of: scope, matching: find.byKey(ValueKey(key))).evaluate().isNotEmpty) key,
]..sort((a, b) => tester.getCenter(find.byKey(ValueKey(a))).dx.compareTo(tester.getCenter(find.byKey(ValueKey(b))).dx));

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

const _topKeys = [
  'live-play-back',
  'live-play-clock',
  'live-play-battery',
  'live-play-video-title',
  'live-play-switch-room',
  'live-play-audio-only',
  'live-play-cast',
  'live-play-pip',
  'live-play-record',
  'live-play-menu',
];

const _bottomKeys = [
  'live-play-pause',
  'live-play-refresh',
  'live-play-video-follow',
  'live-play-danmaku-toggle',
  'live-play-danmaku-settings',
  'local-composer-video',
  'local-composer-star',
  'live-play-quality',
  'live-play-line',
  'live-play-orientation',
  'live-play-portrait-mode',
  'live-play-video-fit',
  'live-play-volume',
  'live-play-chat-column',
  'live-play-window-fullscreen',
  'live-play-fullscreen',
];

void main() {
  group('U.2c landscape fullscreen', () {
    testWidgets('phone: the bars in order with their icons; the lock at the right; the composer in the middle', (
      tester,
    ) async {
      final room = await _pump(tester, width: 852, height: 393);
      await _tap(tester, 'live-play-fullscreen');
      final top = _key('live-play-top-bar');
      // Change 2 adds record and the menu (no FFmpeg in tests: no record);
      // change 4 puts the clock by Back; picture-in-picture waits for a
      // device that offers it.
      expect(_order(tester, top, _topKeys), [
        'live-play-back',
        'live-play-clock',
        'live-play-video-title',
        'live-play-switch-room',
        'live-play-audio-only',
        'live-play-cast',
        'live-play-menu',
      ]);
      expect(_in('live-play-back', find.byIcon(AppIcons.back)), findsOneWidget);
      expect(_in('live-play-switch-room', find.byIcon(AppIcons.switchRoom)), findsOneWidget);
      // Change 5: no dark disc behind switch room.
      expect(tester.widget(_key('live-play-switch-room')), isA<VideoIconButton>());
      expect(_in('live-play-menu', find.byIcon(AppIcons.roomMenu)), findsOneWidget);
      expect(tester.widget<Text>(_key('live-play-clock')).data, matches(RegExp(r'^\d\d:\d\d$')));

      final bottom = _key('live-play-bottom-bar');
      expect(_order(tester, bottom, _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-video-follow',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'local-composer-video',
        'live-play-quality',
        'live-play-line',
        'live-play-orientation',
        'live-play-video-fit',
        'live-play-fullscreen',
      ]);
      expect(_in('live-play-video-fit', find.byIcon(AppIcons.aspectRatio)), findsOneWidget);
      expect(_in('live-play-fullscreen', find.byIcon(AppIcons.exitFullscreen)), findsOneWidget);
      // Change 6: follow is the bar's pill.
      expect(_in('live-play-video-follow', find.text('关注')), findsOneWidget);
      expect(tester.getSize(_in('live-play-video-follow', find.byType(DecoratedBox)).first).height, 32);
      // U.2k's composer in the middle, at most 420 wide.
      expect(tester.getSize(_key('local-composer-video')).width, lessThanOrEqualTo(420));
      // Change 7: 60 % black at the edges.
      final shade = tester.widget<DecoratedBox>(_key('live-play-bottom-shade'));
      expect(((shade.decoration as BoxDecoration).gradient! as LinearGradient).colors.first, OnVideoColors.scrim);
      // The lock at the right, in the middle (3.x `LockButton`).
      final lock = tester.getCenter(_key('live-play-lock'));
      expect(lock.dy, closeTo(393 / 2, 1));
      expect(lock.dx, greaterThan(852 - 80));
      expect(tester.getSize(_key('live-play-lock')).width, 50);
      await _close(tester, room);
    });

    testWidgets('narrow (740): the composer folds into its star; no button drops', (tester) async {
      final room = await _pump(tester, width: 740, height: 360);
      await _tap(tester, 'live-play-fullscreen');
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-video-follow',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'local-composer-star',
        'live-play-quality',
        'live-play-line',
        'live-play-orientation',
        'live-play-video-fit',
        'live-play-fullscreen',
      ]);
      expect(_in('local-composer-star', find.byIcon(AppIcons.localStyle)), findsOneWidget);
      // The star opens the field above the bar (U.2k c14).
      await _tap(tester, 'local-composer-star');
      expect(_key('local-composer-row'), findsOneWidget);
      expect(tester.getRect(_key('local-composer-row')).bottom, lessThan(tester.getRect(_key('live-play-pause')).top));
      await _close(tester, room);
    });

    testWidgets('local interaction off: no composer, the buttons keep their places', (tester) async {
      final room = await _pump(tester, width: 852, height: 393, settings: {Settings.localInteractionEnabled: false});
      await _tap(tester, 'live-play-fullscreen');
      expect(_key('local-composer-video'), findsNothing);
      expect(_key('local-composer-star'), findsNothing);
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), hasLength(10));
      await _close(tester, room);
    });

    testWidgets('lock: the bars and gestures stop, only the unlock button stays; it brings them back', (tester) async {
      final room = await _pump(tester, width: 852, height: 393);
      await _tap(tester, 'live-play-fullscreen');
      await _tap(tester, 'live-play-lock');
      expect(_key('live-play-bottom-bar'), findsNothing);
      expect(_key('live-play-top-bar'), findsNothing);
      expect(_in('live-play-unlock', find.byIcon(AppIcons.locked)), findsOneWidget);
      await _tap(tester, 'live-play-unlock');
      expect(_key('live-play-bottom-bar'), findsOneWidget);
      expect(_in('live-play-lock', find.byIcon(AppIcons.unlocked)), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('Windows: the clock, no orientation; the volume before leaving', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.windows);
      await _tap(tester, 'live-play-fullscreen');
      expect(_order(tester, _key('live-play-top-bar'), _topKeys), [
        'live-play-back',
        'live-play-clock',
        'live-play-video-title',
        'live-play-switch-room',
        'live-play-audio-only',
        'live-play-menu',
      ], reason: 'no desktop mini window in tests (U.2j shows it where there is one)');
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-video-follow',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'local-composer-video',
        'live-play-quality',
        'live-play-line',
        'live-play-video-fit',
        'live-play-volume',
        'live-play-fullscreen',
      ]);
      // Esc leaves the fullscreen.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-desktop-split'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('the battery shows its level, nothing without a battery', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              PlayerBattery(read: _seventySix),
              PlayerBattery(read: _none),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('76'), findsOneWidget);
      expect(_key('live-play-battery'), findsOneWidget);
      // B09 c5 (audit B-18): at least 11 (it was 9).
      expect(tester.widget<Text>(find.text('76')).style!.fontSize, greaterThanOrEqualTo(11));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('O05.3 leaving the landscape fullscreen turns the phone upright', () {
    const sideways = ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'];
    const upright = ['DeviceOrientation.portraitUp'];

    Future<void> doubleTap(WidgetTester tester) async {
      final picture = tester.getRect(find.byType(LiveVideoView));
      final at = Offset(picture.left + 60, picture.center.dy);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('auto-rotate off: the button and double tap, out by Back and double tap', (tester) async {
      final room = await _pump(tester);
      await _tap(tester, 'live-play-fullscreen');
      tester.view.physicalSize = const Size(852, 393);
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(room.orientations, [sideways, 'sensorLandscape', upright], reason: 'upright first');
      tester.view.physicalSize = const Size(393, 852);
      await tester.pump(const Duration(seconds: 4));
      expect(room.orientations.last, isEmpty, reason: 'then free again');

      room.orientations.clear();
      await doubleTap(tester);
      expect(find.byType(AppBar), findsNothing, reason: 'fullscreen');
      tester.view.physicalSize = const Size(852, 393);
      await tester.pump(const Duration(seconds: 1));
      await doubleTap(tester);
      expect(find.byType(AppBar), findsOneWidget, reason: 'back from the fullscreen');
      expect(room.orientations, [sideways, 'sensorLandscape', upright]);
      tester.view.physicalSize = const Size(393, 852);
      await tester.pump(const Duration(seconds: 4));
      expect(room.orientations, [sideways, 'sensorLandscape', upright, <Object?>[]]);
      await _close(tester, room);
    });

    testWidgets('auto-rotate on: let go at once, following the phone', (tester) async {
      final room = await _pump(tester, autoRotate: true);
      await _tap(tester, 'live-play-fullscreen');
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(room.orientations, [sideways, 'sensorLandscape', <Object?>[]]);
      await _close(tester, room);
    });

    testWidgets('the room closed while in the fullscreen: upright, then free', (tester) async {
      final room = await _pump(tester);
      await _tap(tester, 'live-play-fullscreen');
      await _close(tester, room);
      expect(room.orientations, [sideways, 'sensorLandscape', upright, <Object?>[]]);
    });
  });

  group('U.2d wide room', () {
    testWidgets('840 and wider: the chat column (34 %, 300-400) with the strip; a 16:9 frame; Windows bar', (
      tester,
    ) async {
      final room = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.windows);
      expect(_key('live-play-desktop-split'), findsOneWidget);
      expect(tester.getSize(_key('live-play-chat-box')).width, 400);
      expect(find.descendant(of: _key('live-play-chat-box'), matching: _key('live-play-info')), findsOneWidget);
      final frame = tester.getSize(_key('live-play-video-frame'));
      expect(frame.width / frame.height, closeTo(16 / 9, 0.01));
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'live-play-volume',
        'live-play-chat-column',
        'live-play-window-fullscreen',
        'live-play-fullscreen',
      ]);
      expect(_in('live-play-chat-column', find.byIcon(AppIcons.chatColumn)), findsOneWidget);
      expect(_in('live-play-window-fullscreen', find.byIcon(AppIcons.windowFullscreen)), findsOneWidget);
      // Change 6: hovering names it.
      expect(tester.widget<VideoIconButton>(_key('live-play-window-fullscreen')).tooltip, '窗口内全屏（隐藏顶栏和聊天栏）');
      // Change 3: the app bar is the portrait one.
      expect(find.descendant(of: find.byType(AppBar), matching: _key('live-play-follow')), findsOneWidget);
      await _close(tester, room);

      final tablet = await _pump(tester, width: 1280, height: 800);
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'live-play-orientation',
        'live-play-chat-column',
        'live-play-fullscreen',
      ]);
      await _close(tester, tablet);
    });

    testWidgets('600-839 is the phone stack (change 2, H1)', (tester) async {
      final room = await _pump(tester, width: 720, height: 1000);
      expect(_key('live-play-portrait-stack'), findsOneWidget);
      expect(_key('live-play-desktop-split'), findsNothing);
      expect(tester.getSize(_key('live-play-video-box')).width, 720);
      await _close(tester, room);
    });

    testWidgets('fold the chat from the bar or the edge handle; the choice is kept for the next room', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.windows);
      expect(_in('live-play-chat-handle', find.byIcon(AppIcons.chatColumnFold)), findsOneWidget);
      await _tap(tester, 'live-play-chat-column');
      expect(room.services.store.settings.get(Settings.livePlayChatCollapsed), isTrue);
      expect(tester.getSize(_key('live-play-chat-box')).width, 0);
      expect(tester.widget<VideoIconButton>(_key('live-play-chat-column')).tooltip, '展开聊天栏');
      expect(_in('live-play-chat-handle', find.byIcon(AppIcons.chatColumnUnfold)), findsOneWidget);
      // The header stays (W7: only the chat folds).
      expect(find.byType(AppBar), findsOneWidget);
      // Change 8: a panel comes in from the right, 360 wide.
      await _tap(tester, 'live-play-danmaku-settings');
      final panel = tester.getRect(_key('live-play-side-panel'));
      expect(panel.width, 360);
      expect(panel.right, 1280);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      await _wake(tester);
      await _tap(tester, 'live-play-chat-handle');
      expect(room.services.store.settings.get(Settings.livePlayChatCollapsed), isFalse);
      await _close(tester, room);

      final next = await _pump(
        tester,
        width: 1280,
        height: 800,
        platform: TargetPlatform.windows,
        settings: {Settings.livePlayChatCollapsed: true},
      );
      expect(tester.getSize(_key('live-play-chat-box')).width, 0, reason: 'remembered');
      await _close(tester, next);
    });

    testWidgets('B09 c5: the edge handle shows and hides with the controls, at the picture edge', (tester) async {
      // Audit B-19: always on the picture's right edge, it took the volume
      // drag and the taps on the danmaku there.
      final room = await _pump(tester, width: 1280, height: 800);
      Finder layer() => find.ancestor(of: _key('live-play-chat-handle'), matching: find.byType(AnimatedOpacity));
      expect(find.descendant(of: find.byType(RoomPlayer), matching: _key('live-play-chat-handle')), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(layer()).opacity, 1);
      final handle = tester.getRect(_key('live-play-chat-handle'));
      expect(handle.right, closeTo(tester.getRect(find.byType(RoomPlayer)).right, 0.5));
      expect(handle.center.dy, closeTo(tester.getRect(find.byType(RoomPlayer)).center.dy, 0.5));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.widget<AnimatedOpacity>(layer()).opacity, 0);
      expect(
        find.ancestor(
          of: _key('live-play-chat-handle'),
          matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring),
        ),
        findsOneWidget,
        reason: 'hidden, it takes nothing',
      );
      // A tap brings it with the controls; it folds the chat.
      await tester.tapAt(tester.getRect(find.byType(RoomPlayer)).center);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, 'live-play-chat-handle');
      expect(room.services.store.settings.get(Settings.livePlayChatCollapsed), isTrue);
      await _close(tester, room);
    });

    testWidgets('in-window fullscreen (desktops): no app bar or chat, the landscape bars; Esc leaves it', (
      tester,
    ) async {
      final room = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.linux);
      await _tap(tester, 'live-play-window-fullscreen');
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('弹幕列表'), findsNothing);
      expect(_key('live-play-clock'), findsOneWidget);
      expect(_in('live-play-window-fullscreen', find.byIcon(AppIcons.windowFullscreenExit)), findsOneWidget);
      expect(_key('live-play-fullscreen'), findsNothing, reason: '3.x: leave it first');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AppBar), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('under 480 high (a phone held sideways): the picture and the chat list (A07.17 c2)', (tester) async {
      final room = await _pump(tester, width: 740, height: 360);
      expect(_key('live-play-phone-landscape'), findsOneWidget, reason: 'not the phone stack at 740');
      expect(_key('live-play-desktop-split'), findsNothing, reason: 'not the tablet split either');
      expect(tester.getSize(_key('live-play-landscape-chat')).width, phoneLandscapeChatWidth);
      expect(find.byType(AppBar), findsOneWidget);
      await _close(tester, room);
    });
  });

  group('U.2b portrait streams', () {
    testWidgets('the picture fills the room under a three-stop panel; its handle and 横屏全屏; controls above it', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      expect(_key('live-play-portrait-panel'), findsOneWidget);
      // 852 - the app bar 56 = 796; "均衡" starts at the middle stop (44 %).
      final sheet = tester.getRect(_key('live-play-portrait-sheet'));
      expect(sheet.height, closeTo(796 * 0.44, 0.5));
      expect(tester.getSize(find.byType(RoomPlayer)).height, 796, reason: 'the picture fills the area');
      expect(find.text('下滑进入竖屏全屏'), findsOneWidget);
      expect(_in('portrait-landscape-fullscreen', find.text('横屏全屏')), findsOneWidget);
      expect(
        tester.getCenter(_key('portrait-landscape-fullscreen')).dx,
        greaterThan(tester.getCenter(_key('live-play-portrait-enter-hint')).dx),
        reason: 'change 3: at the right of the handle row',
      );
      expect(
        (tester.getCenter(_key('portrait-landscape-fullscreen')).dy -
                tester.getCenter(_key('live-play-portrait-enter-hint')).dy)
            .abs(),
        lessThan(2),
      );
      // Change 2: the bottom bar sits on the panel's upper edge.
      expect(tester.getRect(_key('live-play-bottom-bar')).bottom, closeTo(sheet.top, 1));
      expect(_order(tester, _key('live-play-bottom-bar'), _bottomKeys), [
        'live-play-pause',
        'live-play-refresh',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'live-play-orientation',
        'live-play-fullscreen',
      ]);
      // Change 4: the strip, the tabs and the chat in the panel.
      expect(find.descendant(of: _key('live-play-portrait-sheet'), matching: _key('live-play-info')), findsOneWidget);
      expect(find.descendant(of: _key('live-play-portrait-sheet'), matching: find.text('弹幕列表')), findsOneWidget);
      await _close(tester, room);

      final immersive = await _pump(tester, portrait: true, settings: {Settings.portraitLayoutMode: 'immersive'});
      expect(
        tester.getSize(_key('live-play-portrait-sheet')).height,
        portraitPanelLeast,
        reason: '"沉浸": the lowest; the local composer is a star on the chat (A07.17 c3)',
      );
      await _close(tester, immersive);
    });

    testWidgets('drag the handle: the nearest stop; the controls move once let go; past the lowest: fullscreen', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      final before = tester.getRect(_key('live-play-bottom-bar')).bottom;
      final drag = await tester.startGesture(tester.getCenter(_key('live-play-portrait-handle')));
      // The first move takes the drag (A03.3: no jump of the slop).
      await drag.moveBy(const Offset(0, -20));
      await drag.moveBy(const Offset(0, -60));
      await drag.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(tester.getRect(_key('live-play-bottom-bar')).bottom, before, reason: 'not while dragging');
      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final stops = portraitPanelStops(796, 'balanced');
      expect(tester.getSize(_key('live-play-portrait-sheet')).height, closeTo(stops.maximum, 0.5));
      expect(tester.getRect(_key('live-play-bottom-bar')).bottom, closeTo(852 - stops.maximum, 1));

      // Down past the lowest stop: the portrait fullscreen (appendix A 5).
      await tester.drag(_key('live-play-portrait-handle'), const Offset(0, 700));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AppBar), findsNothing);
      expect(_key('live-play-bottom-first-row'), findsOneWidget);
      expect(room.orientations.last, ['DeviceOrientation.portraitUp']);
      await _close(tester, room);
    });

    testWidgets('A03.3 c3: dragging the panel for 2 s rebuilds no RoomPlayer; it moves once let go', (tester) async {
      final room = await _pump(tester, portrait: true);
      final player = tester.widget<RoomPlayer>(find.byType(RoomPlayer));
      var rebuilt = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is RoomPlayer) rebuilt++;
      };
      try {
        final drag = await tester.startGesture(tester.getCenter(_key('live-play-portrait-handle')));
        var time = Duration.zero;
        // 240 frames at 120 Hz, up and down.
        for (var i = 0; i < 240; i++) {
          time += const Duration(microseconds: 8333);
          await drag.moveBy(Offset(0, i.isEven ? -6 : 4), timeStamp: time);
          await tester.pump(const Duration(microseconds: 8333));
        }
        expect(tester.getSize(_key('live-play-portrait-sheet')).height, greaterThan(796 * 0.44 + 100));
        expect(rebuilt, 0);
        expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)), same(player));
        await drag.up(timeStamp: time);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(rebuilt, greaterThan(0), reason: 'the controls move above the stop it settled at');
      expect(
        tester.widget<RoomPlayer>(find.byType(RoomPlayer)).overlayBottom,
        portraitPanelStops(796, 'balanced').maximum,
      );
      await _close(tester, room);
    });

    testWidgets('B09 c4, c5: the stop is kept through the fullscreen; the handle reads 最低, 中间, 最高', (tester) async {
      final semantics = tester.ensureSemantics();
      final room = await _pump(tester, portrait: true);
      final stops = portraitPanelStops(796, 'balanced');
      SemanticsNode handle() => tester.getSemantics(find.bySemanticsLabel('弹幕面板高度'));
      // Audit B-17: the stop's name, not "350 px".
      expect(handle().value, '中间');
      expect(handle().increasedValue, '最高');
      expect(handle().decreasedValue, '最低');
      await tester.drag(_key('live-play-portrait-handle'), const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(_key('live-play-portrait-sheet')).height, closeTo(stops.maximum, 0.5));
      expect(handle().value, '最高');
      expect(handle().decreasedValue, '中间');

      // Audit B-12: into the portrait fullscreen and back, at the same stop.
      await _tap(tester, 'live-play-fullscreen');
      expect(_key('live-play-portrait-panel'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(_key('live-play-portrait-sheet')).height, closeTo(stops.maximum, 0.5));
      expect(tester.getRect(_key('live-play-bottom-bar')).bottom, closeTo(852 - stops.maximum, 1));
      semantics.dispose();
      await _close(tester, room);
    });

    testWidgets('portrait fullscreen: two rows each end; the hint for 3 s; an upward swipe and Back restore', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      // Change 5: the fullscreen button of a portrait room (and double tap,
      // appendix A 3) is the portrait fullscreen.
      await _tap(tester, 'live-play-fullscreen');
      expect(_key('live-play-portrait-hint'), findsOneWidget);
      final top = _key('live-play-top-bar');
      final second = _key('live-play-top-second-row');
      expect(
        _order(
          tester,
          top,
          _topKeys,
        ).where((key) => find.descendant(of: second, matching: _key(key)).evaluate().isEmpty),
        ['live-play-back', 'live-play-video-title', 'live-play-menu'],
      );
      expect(find.descendant(of: top, matching: _key('live-play-video-follow')), findsOneWidget);
      expect(_order(tester, second, _topKeys), [
        'live-play-clock',
        'live-play-switch-room',
        'live-play-audio-only',
        'live-play-cast',
      ]);
      final first = _key('live-play-bottom-first-row');
      expect(_order(tester, first, _bottomKeys), ['local-composer-video', 'live-play-quality', 'live-play-line']);
      expect(
        _order(
          tester,
          _key('live-play-bottom-bar'),
          _bottomKeys,
        ).where((key) => find.descendant(of: first, matching: _key(key)).evaluate().isEmpty),
        [
          'live-play-pause',
          'live-play-refresh',
          'live-play-danmaku-toggle',
          'live-play-danmaku-settings',
          'live-play-portrait-mode',
          'live-play-orientation',
          'live-play-fullscreen',
        ],
      );
      expect(_in('live-play-portrait-mode', find.byIcon(AppIcons.aspectRatio)), findsOneWidget);
      expect(_in('live-play-fullscreen', find.byIcon(AppIcons.exitFullscreen)), findsOneWidget);
      expect(_key('live-play-lock'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      final hint = find.ancestor(of: _key('live-play-portrait-hint'), matching: find.byType(AnimatedOpacity));
      expect(tester.widget<AnimatedOpacity>(hint).opacity, 0, reason: 'fades after three seconds');

      // An upward swipe on the bottom bars brings the panel back.
      await _wake(tester);
      await tester.dragFrom(tester.getCenter(_key('live-play-pause')), const Offset(0, -120));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-portrait-panel'), findsOneWidget);

      await _tap(tester, 'live-play-fullscreen');
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-portrait-panel'), findsOneWidget, reason: 'Back leaves the fullscreen first');
      await _close(tester, room);
    });

    testWidgets("A07.15 c2: an upward swipe from the system's gesture area still restores the panel", (tester) async {
      final room = await _pump(tester, portrait: true);
      await _tap(tester, 'live-play-fullscreen');
      tester.view.systemGestureInsets = const FakeViewPadding(bottom: 32);
      addTearDown(tester.view.resetSystemGestureInsets);
      // The controls hide after 4 s: the swipe lands on the picture.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(_key('live-play-portrait-panel'), findsNothing);
      await tester.dragFrom(const Offset(196, 852 - 10), const Offset(0, -120));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-portrait-panel'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('B09 c3: 360 wide, a split screen, the largest display size: no overflow; the rows scroll', (
      tester,
    ) async {
      // Audit B-11: the second rows were plain rows; seven 48 buttons need
      // 352 with the margins. The largest display size leaves about 300
      // (and the bars' text grows up to 1.3 times).
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final width in [360.0, 300.0, 280.0]) {
        final room = await _pump(tester, width: width, height: 640, portrait: true);
        await _tap(tester, 'live-play-fullscreen');
        expect(tester.takeException(), isNull, reason: '$width');
        expect(_key('live-play-bottom-first-row'), findsOneWidget);
        // The fullscreen stays at the end of its row, on screen.
        final exit = tester.getRect(_key('live-play-fullscreen'));
        expect(exit.right, lessThanOrEqualTo(width), reason: '$width');
        final rows = [_key('live-play-top-second-row'), _key('live-play-bottom-second-row')];
        for (final row in rows) {
          expect(tester.getRect(row).right, lessThanOrEqualTo(width), reason: '$width');
          final scroll = find.descendant(of: row, matching: find.byType(Scrollable));
          expect(scroll, findsOneWidget, reason: '$width');
        }
        if (width < 340) {
          // What does not fit is a sideways drag away: the orientation.
          final bottom = tester.state<ScrollableState>(
            find.descendant(of: rows.last, matching: find.byType(Scrollable)),
          );
          expect(bottom.position.maxScrollExtent, greaterThan(0), reason: '$width');
          await tester.drag(rows.last, const Offset(-200, 0));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(tester.getRect(_key('live-play-orientation')).right, lessThanOrEqualTo(exit.left + 1));
        }
        await _close(tester, room);
      }
    });

    testWidgets('picture mode: the 画面比例 icon, yellow off the default; a titled menu with lines; applies', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      await _tap(tester, 'live-play-fullscreen');
      expect(tester.widget<IconButton>(_key('live-play-portrait-mode')).color, OnVideoColors.foreground);
      await _tap(tester, 'live-play-portrait-mode');
      expect(_key('small-menu-title'), findsOneWidget);
      expect(find.text('竖屏全屏画面模式'), findsWidgets);
      for (final line in ['完整保留直播内容，空白区域保持纯色', '铺满整个屏幕，可能裁掉左右部分内容']) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.descendant(of: _key('portrait-mode-1'), matching: find.byIcon(AppIcons.selected)), findsOneWidget);
      // The picture is not dimmed (a menu, not a dialog).
      expect(
        find.byType(ModalBarrier).evaluate().every((barrier) {
          final color = (barrier.widget as ModalBarrier).color;
          return color == null || color.a == 0;
        }),
        isTrue,
      );
      await tester.tap(_key('portrait-mode-3'));
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.portraitFullscreenDisplayMode), 'cover');
      expect(_key('live-play-picture-cover'), findsOneWidget);
      expect(tester.widget<IconButton>(_key('live-play-portrait-mode')).color, OnVideoColors.active);
      await _close(tester, room);
    });

    testWidgets('orientation: a titled small menu, each with its line, a tick; 记住 applies when switched', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      await _tap(tester, 'live-play-orientation');
      // U.2n c6: next to the button like the picture mode, not a dialog.
      expect(find.byType(Dialog), findsNothing);
      expect(_key('small-menu-title'), findsOneWidget);
      expect(find.text('本直播间画面方向'), findsOneWidget);
      expect(find.text('按画面的实际尺寸判断是竖屏还是横屏直播'), findsOneWidget);
      expect(find.text('当作竖屏直播：画面加高、下面是可拖的面板，能进竖屏全屏'), findsOneWidget);
      expect(find.descendant(of: _key('room-orientation-0'), matching: find.byIcon(AppIcons.selected)), findsOneWidget);
      await tester.tap(_key('room-orientation-remember'));
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.rememberPortraitRoomOverride), isFalse, reason: 'at once');
      expect(_key('room-orientation-0'), findsOneWidget, reason: 'the switch leaves the menu open');
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('room-orientation-0'), findsNothing, reason: 'Back closes it');
      await _close(tester, room);
    });

    testWidgets('横屏全屏: once sideways with the ambient sides; leaving turns the phone back upright', (tester) async {
      final room = await _pump(tester, portrait: true);
      await _tap(tester, 'portrait-landscape-fullscreen');
      expect(room.orientations.reversed.take(2), [
        'sensorLandscape',
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      ], reason: 'turning over with the phone even while auto-rotate is off (issue #36)');
      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('ambient-backdrop'), findsOneWidget);
      expect(_key('live-play-clock'), findsOneWidget);
      expect(_key('live-play-bottom-first-row'), findsNothing, reason: 'the landscape bars');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(room.orientations.last, ['DeviceOrientation.portraitUp'], reason: 'appendix A 11');
      await tester.pump(const Duration(seconds: 4));
      expect(room.orientations.last, isEmpty, reason: 'then free again');
      await _close(tester, room);
    });

    testWidgets('wide: a portrait stream takes the full height over the ambient background (change 13)', (
      tester,
    ) async {
      final room = await _pump(tester, width: 1280, height: 800, portrait: true, platform: TargetPlatform.windows);
      expect(_key('live-play-video-frame'), findsNothing);
      expect(tester.getSize(find.byType(RoomPlayer)).height, 744);
      expect(_key('ambient-backdrop'), findsOneWidget);
      await _close(tester, room);
    });

    group("A07.16 JD Live: the play answer's blurred frame behind the stream", () {
      /// JD Live's play answer (fixtures/jdlive/S02-play-live): a blurred
      /// frame as the background and no card cover (upgrade 28-3).
      JdLiveRoom play() =>
          JdLiveApi.play(File('../../fixtures/jdlive/S02-play-live/body.json').readAsStringSync(), liveId: '48378944');

      LiveRoom detail({String cover = '', Object? data}) =>
          liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))).copyWith(cover: cover, data: data);

      String backdrop(WidgetTester tester) => tester.widget<LiveNetworkImage>(_key('ambient-backdrop-cover')).url;

      test('the sample has a blurred frame and no card cover', () {
        expect(play().background, startsWith('https://m.360buyimg.com/'));
        expect(play().cover, isEmpty);
      });

      testWidgets('portrait fullscreen, no cover (not seen as a card): the blurred frame', (tester) async {
        final jd = play();
        final room = await _pump(
          tester,
          portrait: true,
          detail: detail(data: jd),
          images: NoImages(),
        );
        await _tap(tester, 'live-play-fullscreen');
        expect(backdrop(tester), jd.background);
        await _close(tester, room);
      });

      testWidgets('with a card cover too, the blurred frame first (X2)', (tester) async {
        final jd = play();
        final room = await _pump(
          tester,
          width: 1280,
          height: 800,
          portrait: true,
          platform: TargetPlatform.windows,
          images: NoImages(),
          detail: detail(cover: 'https://example.com/card.jpg', data: jd),
        );
        expect(backdrop(tester), jd.background);
        await _close(tester, room);
      });

      testWidgets('landscape fullscreen: the same frame at the sides', (tester) async {
        final jd = play();
        final room = await _pump(
          tester,
          portrait: true,
          detail: detail(data: jd),
          images: NoImages(),
        );
        await _tap(tester, 'portrait-landscape-fullscreen');
        tester.view.physicalSize = const Size(852, 393);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(backdrop(tester), jd.background);
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(seconds: 4));
        await _close(tester, room);
      });

      testWidgets('another room (no JD play answer): its cover, as before', (tester) async {
        final room = await _pump(
          tester,
          portrait: true,
          images: NoImages(),
          detail: detail(cover: 'https://example.com/card.jpg'),
        );
        await _tap(tester, 'live-play-fullscreen');
        expect(backdrop(tester), 'https://example.com/card.jpg');
        await _close(tester, room);
      });
    });

    testWidgets('"兼容 16:9": the 16:9 stack, and still the portrait fullscreen (change 5)', (tester) async {
      final room = await _pump(tester, portrait: true, settings: {Settings.portraitLayoutMode: 'compatibility'});
      expect(_key('live-play-portrait-stack'), findsOneWidget);
      await _tap(tester, 'live-play-fullscreen');
      expect(_key('live-play-bottom-first-row'), findsOneWidget);
      expect(_key('live-play-portrait-mode'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('desktop, narrow: a grip and "全屏"; no portrait fullscreen', (tester) async {
      final room = await _pump(tester, width: 500, portrait: true, platform: TargetPlatform.windows);
      expect(_key('live-play-portrait-grip'), findsOneWidget);
      expect(find.text('下滑进入竖屏全屏'), findsNothing);
      expect(_in('portrait-landscape-fullscreen', find.text('全屏')), findsOneWidget);
      await _tap(tester, 'portrait-landscape-fullscreen');
      expect(_key('live-play-bottom-first-row'), findsNothing);
      expect(_key('live-play-clock'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('panels in the portrait fullscreen rise from the bottom', (tester) async {
      final room = await _pump(tester, portrait: true);
      await _tap(tester, 'live-play-fullscreen');
      await _tap(tester, 'live-play-danmaku-settings');
      final panel = tester.getRect(_key('live-play-bottom-panel'));
      expect(panel.bottom, 852);
      expect(panel.width, 393);
      await _close(tester, room);
    });
  });

  testWidgets('appendix A 1: a tap hides playing controls on phones; desktops only show them', (tester) async {
    final room = await _pump(tester);
    Finder controls() => find.ancestor(of: _key('live-play-fullscreen'), matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 1);
    await tester.tap(find.byType(LiveVideoView));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 0);
    await _close(tester, room);

    final desktop = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.windows);
    await tester.tap(find.byType(LiveVideoView));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 1);
    await _close(tester, desktop);
  });

  testWidgets('B09 c1: a tap acts at once; a second one takes it back and toggles the fullscreen', (tester) async {
    // Audit B-8: the picture's double tap held every tap back by its
    // timeout (about 300 ms) before the controls showed.
    final room = await _pump(tester);
    Finder controls() => find.ancestor(of: _key('live-play-fullscreen'), matching: find.byType(AnimatedOpacity));
    double shown() => tester.widget<AnimatedOpacity>(controls()).opacity;
    await tester.pump(const Duration(seconds: 5));
    expect(shown(), 0);
    final picture = tester.getRect(find.byType(LiveVideoView));
    final at = Offset(picture.left + 60, picture.center.dy);
    await tester.tapAt(at);
    await tester.pump();
    expect(shown(), 1, reason: 'at once, not after the double tap timeout');
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(at);
    await tester.pump();
    expect(shown(), 0, reason: 'a later tap is a tap of its own');
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    // A double tap: the first tap shows the controls at once, the second
    // takes that back and enters the fullscreen (appendix A 3).
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown(), 1);
    await tester.tapAt(at + const Offset(8, 4));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBar), findsNothing, reason: 'fullscreen');
    // And out again the same way.
    tester.view.physicalSize = const Size(852, 393);
    await tester.pump(const Duration(seconds: 1));
    final full = tester.getRect(find.byType(LiveVideoView));
    final there = Offset(full.left + 120, full.center.dy);
    await tester.tapAt(there);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(there);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBar), findsOneWidget, reason: 'back from the fullscreen');
    await _close(tester, room);
  });

  testWidgets('B09 c1: a double tap where a button appears does not press it', (tester) async {
    // The first tap shows the bars at once; the second must still be the
    // double tap, not a tap on the pause button that just appeared there.
    final room = await _pump(tester);
    final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;
    room.engine.emit(const EngineVideoSize(1920, 1080));
    await tester.pump(const Duration(seconds: 5));
    final status = session.state.status;
    final at = tester.getCenter(_key('live-play-pause'));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(at);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(session.state.status, status, reason: 'not paused');
    expect(find.byType(AppBar), findsNothing, reason: 'the double tap entered the fullscreen');
    // A moment later the bars take taps again.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    final pause = tester.getCenter(_key('live-play-pause'));
    await tester.tapAt(pause);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(session.state.status, PlaybackStatus.paused);
    await _close(tester, room);
  });

  testWidgets('B09 c1: locked, taps only show or hide the unlock button; no double tap', (tester) async {
    final room = await _pump(tester, width: 852, height: 393);
    await _tap(tester, 'live-play-fullscreen');
    await _tap(tester, 'live-play-lock');
    final picture = tester.getRect(find.byType(LiveVideoView));
    final at = Offset(picture.left + 120, picture.center.dy);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(at);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBar), findsNothing, reason: 'still in the fullscreen');
    expect(_key('live-play-unlock'), findsOneWidget);
    await _close(tester, room);
  });

  testWidgets('B09 c2: the recording corner clears a cut-out on the left in landscape', (tester) async {
    final room = await _pump(tester, width: 852, height: 393);
    tester.view.padding = const FakeViewPadding(left: 40);
    await _tap(tester, 'live-play-fullscreen');
    await tester.pump(const Duration(seconds: 5));
    final corner = tester.widget<Positioned>(_key('live-play-recording-corner'));
    expect(corner.left, 12 + 40);
    await _close(tester, room);
  });

  testWidgets('paused: a tap on the picture only shows the controls; the play mark resumes', (tester) async {
    // 2026-10-02 (user): a stray tap no longer starts a paused stream, and the
    // mark in the middle shows what a tap does (play), not the paused state.
    // B02 c1, c2: paused, the controls stay; the mark sits on a 64 disc of
    // 45 % black and turns while the stream comes back.
    final room = await _pump(tester);
    final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;
    Finder controls() => find.ancestor(of: _key('live-play-fullscreen'), matching: find.byType(AnimatedOpacity));
    double shown() => tester.widget<AnimatedOpacity>(controls()).opacity;
    room.engine.emit(const EngineVideoSize(1920, 1080));
    await tester.runAsync(session.togglePlayPause);
    await tester.pump();
    expect(session.state.status, PlaybackStatus.paused);
    expect(find.descendant(of: _key('picture-paused-play'), matching: find.byIcon(AppIcons.play)), findsOneWidget);
    expect(tester.getSize(_key('picture-paused-play')), const Size(64, 64));
    final disc = tester.widget<IconButton>(
      find.descendant(of: _key('picture-paused-play'), matching: find.byType(IconButton)),
    );
    expect(disc.style!.backgroundColor!.resolve({}), OnVideoColors.button);

    // c1: the controls do not hide by themselves while paused.
    await tester.pump(const Duration(seconds: 10));
    expect(shown(), 1);
    // A tap on the picture hides or shows them; it never resumes, and the
    // mark stays.
    final picture = tester.getRect(find.byType(LiveVideoView));
    final away = Offset(picture.left + 40, picture.center.dy);
    await tester.tapAt(away);
    await tester.pump(const Duration(seconds: 1));
    expect(shown(), 0);
    expect(session.state.status, PlaybackStatus.paused, reason: 'a tap elsewhere does not resume');
    expect(_key('picture-paused-play'), findsOneWidget);
    await tester.tapAt(away);
    await tester.pump(const Duration(seconds: 1));
    expect(shown(), 1);
    await tester.pump(const Duration(seconds: 10));
    expect(shown(), 1);

    await tester.tap(_key('picture-paused-play'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(session.state.status, isNot(PlaybackStatus.paused));
    // The picture waits for data: the same disc turns, nothing says
    // "正在重连" (B02 c4).
    room.engine.emit(const EngineBuffering(buffering: true));
    await tester.pump();
    expect(_in('picture-buffering', find.byKey(const ValueKey('video-centre-busy'))), findsOneWidget);
    expect(find.textContaining('正在重连'), findsNothing);
    room.engine.emit(const EngineBuffering(buffering: false));
    await tester.pump();
    expect(_key('picture-buffering'), findsNothing);
    // Playing again, the controls hide after the quiet as before.
    await tester.pump(const Duration(seconds: 5));
    expect(shown(), 0);
    await _close(tester, room);
  });

  testWidgets('B02 c1: a pause from elsewhere (the notification, a headset) brings the controls and keeps them', (
    tester,
  ) async {
    final room = await _pump(tester);
    final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;
    Finder controls() => find.ancestor(of: _key('live-play-fullscreen'), matching: find.byType(AnimatedOpacity));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 0);
    await tester.runAsync(session.pause);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 1);
    await _close(tester, room);
  });

  testWidgets('the room menu on each platform: cast only on Android, the new window only on Windows', (tester) async {
    // docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏, U.2d: "投屏只有 Android" (the menu as well as the
    // top bar; U.17a for iOS); U.13: "在新窗口打开" where the desktop shell
    // opens windows (A16.2: the Windows shell sets the launcher).
    const group1 = ['room-menu-switchRoom', 'room-menu-timer', 'room-menu-volume', 'room-menu-videoFit'];
    const local = ['room-menu-localInteraction'];
    const passOn = ['room-menu-streamLink', 'room-menu-share', 'room-menu-external'];
    const cases = <(TargetPlatform, Size, List<String>)>[
      (TargetPlatform.android, Size(393, 852), [...group1, 'room-menu-cast', ...passOn, ...local]),
      (TargetPlatform.iOS, Size(393, 852), [...group1, ...passOn, ...local]),
      (TargetPlatform.windows, Size(1280, 800), [...group1, ...passOn, 'room-menu-newWindow', ...local]),
      (TargetPlatform.linux, Size(1280, 800), [...group1, ...passOn, ...local]),
      (TargetPlatform.macOS, Size(1280, 800), [...group1, ...passOn, ...local]),
    ];
    const all = [...group1, 'room-menu-cast', ...passOn, 'room-menu-newWindow', ...local];
    List<String> menu() => [
      for (final key in all)
        if (_key(key).evaluate().isNotEmpty) key,
    ]..sort((a, b) => tester.getCenter(_key(a)).dy.compareTo(tester.getCenter(_key(b)).dy));

    addTearDown(() => DesktopWindow.newWindowLauncher = null);
    for (final (platform, size, expected) in cases) {
      DesktopWindow.newWindowLauncher = platform == TargetPlatform.windows ? ({room}) async {} : null;
      final room = await _pump(tester, width: size.width, height: size.height, platform: platform);
      await _tap(tester, 'live-play-menu');
      expect(menu(), expected, reason: '$platform');
      if (castSupported(platform)) {
        expect(_in('room-menu-cast', find.byIcon(AppIcons.cast)), findsOneWidget);
      }
      // The fullscreen bars carry the same menu, less what the bars show
      // (B05, docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板 c12: ⇄ and cast on the top bar; the fit on
      // the landscape bottom bar, not on the upright fullscreen's).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, 'live-play-fullscreen');
      expect(_key('live-play-cast'), castSupported(platform) ? findsOneWidget : findsNothing, reason: '$platform');
      await tester.tap(find.descendant(of: _key('live-play-top-bar'), matching: _key('live-play-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final onBars = {'room-menu-switchRoom', 'room-menu-cast', if (size.width > size.height) 'room-menu-videoFit'};
      expect(menu(), [
        for (final key in expected)
          if (!onBars.contains(key)) key,
      ], reason: '$platform fullscreen');
      await _close(tester, room);
    }
  });

  group('layout logic', () {
    test('the size classes: wide from 840, the phone below, a short window sideways', () {
      expect(roomPageLayout(width: 1280, height: 800, portraitPanel: false), RoomPageLayout.wide);
      expect(roomPageLayout(width: 840, height: 800, portraitPanel: true), RoomPageLayout.wide);
      expect(roomPageLayout(width: 839, height: 1000, portraitPanel: false), RoomPageLayout.phone);
      expect(roomPageLayout(width: 393, height: 852, portraitPanel: true), RoomPageLayout.portraitPanel);
      expect(roomPageLayout(width: 852, height: 393, portraitPanel: false), RoomPageLayout.landscape);
      expect(
        roomPageLayout(width: 852, height: 393, portraitPanel: false, mobile: false),
        RoomPageLayout.wide,
        reason: 'a short desktop window keeps the split (A07.17)',
      );
      expect(roomPageLayout(width: 360, height: 400, portraitPanel: false), RoomPageLayout.phone);
      expect(roomPageLayout(width: 560, height: 400, portraitPanel: false), RoomPageLayout.phone);
      expect(
        controlsArrangement(
          display: RoomDisplay.fullscreen,
          page: RoomPageLayout.phone,
          width: 393,
          height: 852,
          mobile: true,
        ),
        ControlsArrangement.portraitFullscreen,
      );
      expect(
        controlsArrangement(
          display: RoomDisplay.fullscreen,
          page: RoomPageLayout.phone,
          width: 393,
          height: 852,
          mobile: false,
        ),
        ControlsArrangement.landscape,
      );
      expect(
        controlsArrangement(
          display: RoomDisplay.inline,
          page: RoomPageLayout.wide,
          width: 1280,
          height: 800,
          mobile: false,
        ),
        ControlsArrangement.inline,
      );
      expect(chatColumnWidth(1280), 400);
      expect(chatColumnWidth(840), 300);
      expect(chatColumnWidth(1000), 340);
    });

    test('the panel stops (250 / 44 % / 68 %) and its gestures; the portrait fullscreen rules', () {
      final stops = portraitPanelStops(740, 'balanced');
      expect(stops.minimum, 250);
      expect(stops.middle, closeTo(325.6, 0.01));
      expect(stops.maximum, closeTo(503.2, 0.01));
      expect(stops.initial, stops.middle);
      expect(portraitPanelStops(740, 'immersive').initial, 250);
      expect(portraitPanelStops(300, 'balanced').maximum, 250, reason: 'at least the lowest');
      expect(nearestStop(400, [250, 326, 503]), 326);
      expect(panelDragEntersFullscreen(dismissed: 72, panelHeight: 200, velocity: 0), isTrue);
      expect(panelDragEntersFullscreen(dismissed: 71, panelHeight: 200, velocity: 0), isFalse);
      expect(panelDragEntersFullscreen(dismissed: 30, panelHeight: 400, velocity: 950), isTrue);
      expect(swipeRestoresPanel(upward: 64, velocity: 0), isTrue);
      expect(swipeRestoresPanel(upward: 30, velocity: -900), isTrue);
      expect(swipeRestoresPanel(upward: 30, velocity: -100), isFalse);
      expect(balancedScale(width: 405, height: 750, aspectRatio: 9 / 16), closeTo(9 / 16 / (405 / 750), 0.001));
      expect(balancedScale(width: 393, height: 852, aspectRatio: 9 / 16), 1.08, reason: 'at most 8 %');
      expect(PortraitDisplayMode.of('nope'), PortraitDisplayMode.ambient);
      expect(FullscreenOrientation.of('landscape'), FullscreenOrientation.landscape);
      expect(
        portraitPanelEligible(
          portraitStream: true,
          adaptation: true,
          adaptiveHeight: true,
          layoutMode: 'compatibility',
        ),
        isFalse,
      );
      expect(portraitFullscreenEligible(mobile: true, portraitStream: true, adaptation: true), isTrue);
      expect(portraitFullscreenEligible(mobile: false, portraitStream: true, adaptation: true), isFalse);
      expect(
        portraitFullscreenEligible(mobile: true, portraitStream: true, adaptation: true, policy: 'landscape'),
        isFalse,
      );
    });
  });
}

Future<int?> _seventySix() async => 76;

Future<int?> _none() async => null;
