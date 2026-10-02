// The live room's other pop-ups (docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一, task B07): the room
// menu's sleep timer, room volume, stream address and casting are room
// panels in every layout; the fit and orientation are small menus next to
// their buttons; the room volume on a phone is the system's media volume;
// toasts in fullscreen sit above the bottom bar.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

final class _Room {
  new(this.services, this.danmaku, this.toasts);

  final AppServices services;
  final FakeDanmaku danmaku;
  final List<String> toasts;
}

Future<_Room> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  TargetPlatform platform = TargetPlatform.android,
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
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final danmaku = FakeDanmaku();
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
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
  return _Room(services, danmaku, toasts);
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

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

/// The room menu's button: the picture's top bar in fullscreen, else the
/// app bar's.
Finder _menuButton() {
  final onPicture = find.descendant(of: _key('live-play-top-bar'), matching: _key('live-play-menu'));
  return onPicture.evaluate().isNotEmpty ? onPicture : _key('live-play-menu').first;
}

Future<void> _menu(WidgetTester tester, String entry) async {
  await tester.tap(_menuButton());
  await tester.pumpAndSettle();
  await tester.tap(_key('room-menu-$entry'));
  await tester.pumpAndSettle();
}

Future<void> _closePanel(WidgetTester tester) async {
  await tester.tap(_key('room-panel-close'));
  await tester.pumpAndSettle();
}

/// The panels the room menu opens (U.2n c1), by their keys.
const _panels = {'timer': 'room-timer-panel', 'volume': 'room-volume-panel', 'streamLink': 'stream-panel-copy'};

/// No centred dialog and nothing dims the picture.
void _noDialog(WidgetTester tester) {
  expect(find.byType(Dialog), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
  for (final barrier in tester.widgetList<ModalBarrier>(find.byType(ModalBarrier))) {
    expect(barrier.color == null || barrier.color!.a == 0, isTrue, reason: 'the picture is not dimmed');
  }
}

/// The words of the text widget [key].
String? _text(WidgetTester tester, String key) => tester.widget<Text>(_key(key)).data;

void main() {
  tearDown(() => DeviceControls.debugAvailable = null);

  group("U.2n c1: the room menu's settings are room panels", () {
    testWidgets('portrait: under the picture, all the height below it', (tester) async {
      final room = await _pump(tester);
      final video = tester.getRect(_key('live-play-video-box'));
      for (final MapEntry(key: entry, value: panel) in _panels.entries) {
        await _menu(tester, entry);
        expect(_key(panel), findsOneWidget, reason: entry);
        _noDialog(tester);
        final rect = tester.getRect(_key(panel));
        expect(rect.top, moreOrLessEquals(video.bottom), reason: entry);
        expect(rect.bottom, 852, reason: entry);
        expect(rect.width, 393, reason: entry);
        await _closePanel(tester);
        expect(_key(panel), findsNothing);
      }
      await _close(tester, room);
    });

    testWidgets('landscape fullscreen: on the right, 360 wide and the full height; cast from the top bar too', (
      tester,
    ) async {
      final room = await _pump(tester, width: 852, height: 393);
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      expect(_key('live-play-back'), findsOneWidget, reason: 'fullscreen');
      const right = Rect.fromLTRB(852.0 - 360, 0, 852, 393);
      // The menu on the picture leaves out what the bars show (U.2m c12):
      // the timer, the volume and the address are in it.
      for (final MapEntry(key: entry, value: panel) in _panels.entries) {
        await _menu(tester, entry);
        _noDialog(tester);
        expect(tester.getRect(_key(panel)), right, reason: entry);
        await _closePanel(tester);
      }
      await tester.tap(_key('live-play-cast'));
      await tester.pumpAndSettle();
      _noDialog(tester);
      expect(tester.getRect(_key('stream-panel-cast')), right);
      // Back closes the panel before leaving fullscreen.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_key('stream-panel-cast'), findsNothing);
      expect(_key('live-play-back'), findsOneWidget, reason: 'still fullscreen');
      await _close(tester, room);
    });

    testWidgets('portrait fullscreen: the bottom 60 %', (tester) async {
      final room = await _pump(tester);
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      expect(_key('live-play-bottom-first-row'), findsOneWidget, reason: 'the portrait fullscreen');
      for (final MapEntry(key: entry, value: panel) in _panels.entries) {
        await _menu(tester, entry);
        _noDialog(tester);
        final rect = tester.getRect(_key(panel));
        expect(rect.top, moreOrLessEquals(852 * 0.4), reason: entry);
        expect(rect.bottom, 852, reason: entry);
        await _closePanel(tester);
      }
      await _close(tester, room);
    });

    testWidgets('tablet: on the right over the chat column', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800);
      final chat = tester.getRect(_key('live-play-tabs'));
      for (final MapEntry(key: entry, value: panel) in _panels.entries) {
        await _menu(tester, entry);
        _noDialog(tester);
        final rect = tester.getRect(_key(panel));
        expect(rect.width, 360, reason: entry);
        expect(rect.right, 1280, reason: entry);
        expect(rect.overlaps(chat), isTrue, reason: entry);
        await _closePanel(tester);
      }
      await _close(tester, room);
    });

    testWidgets("a danmaku's actions: under the picture in portrait, on the right in fullscreen", (tester) async {
      final room = await _pump(tester, width: 852, height: 393);
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      // A tap on a flying danmaku (F.2b) opens the panel of its message.
      RoomPanelScope.maybeOf(tester.element(_key('live-play-back')))!.openMessage(
        const LiveMessage(type: LiveMessageType.chat, userName: '路人', message: '前排', color: LiveMessageColor.white),
      );
      await tester.pumpAndSettle();
      _noDialog(tester);
      expect(tester.getRect(_key('live-play-message-panel')), const Rect.fromLTRB(852.0 - 360, 0, 852, 393));
      expect(_in('live-play-message-card', find.textContaining('路人：前排', findRichText: true)), findsOneWidget);
      // B09 c8: the keyword is the panel's second page, still on the right;
      // no dialog in the middle of the picture.
      await tester.tap(_key('live-play-block-keyword'));
      await tester.pumpAndSettle();
      _noDialog(tester);
      expect(tester.getRect(_key('live-play-message-panel')), const Rect.fromLTRB(852.0 - 360, 0, 852, 393));
      expect(_in('live-play-message-panel', _key('live-play-keyword-input')), findsOneWidget);
      expect(_key('live-play-back'), findsOneWidget, reason: 'still in the fullscreen');
      await tester.enterText(_key('live-play-keyword-input'), '前');
      await tester.tap(_key('live-play-keyword-confirm'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => room.services.store.blockLists.list(BlockKind.keyword)), ['前']);
      expect(_key('live-play-message-panel'), findsNothing);
      expect(room.toasts, contains('关键词已加入弹幕屏蔽列表'));
      await _close(tester, room);
    });
  });

  group('U.2n c2, c3 (B-3, B-14): the room volume', () {
    testWidgets('Android: the system media volume, the same one the drag on the picture changes', (tester) async {
      var system = 0.8;
      final calls = <String>[];
      DeviceControls.debugAvailable = true;
      const channel = MethodChannel('pure_live/device_controls');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getVolume':
            return system;
          case 'setVolume':
            system = ((call.arguments as Map)['value'] as num).toDouble();
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final room = await _pump(tester);

      await _menu(tester, 'volume');
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '80%', reason: 'reads the system volume');
      expect(_in('room-volume-panel', find.text('调的是手机的媒体音量：和画面右侧上下滑、音量键是同一个音量')), findsOneWidget);
      final slider = tester.widget<Slider>(_key('room-volume-slider'));
      slider.onChangeStart!(0.8);
      slider.onChanged!(0.3);
      slider.onChangeEnd!(0.3);
      await _settle(tester);
      expect(system, 0.3);
      expect(_text(tester, 'room-volume-value'), '30%');
      // Nothing of its own: no room volume is kept on a phone.
      expect(room.services.store.settings.get(Settings.roomVolumes), isEmpty);

      // B-14: muting and back comes back to 30 %, not 100 %.
      await tester.tap(_key('room-volume-mute'));
      await _settle(tester);
      expect(system, 0);
      expect(find.byIcon(AppIcons.volumeMuted), findsOneWidget);
      await tester.tap(_key('room-volume-mute'));
      await _settle(tester);
      expect(system, 0.3);
      await _closePanel(tester);

      // The drag on the right of the picture starts from that same volume.
      final video = tester.getRect(_key('live-play-video-box'));
      final gesture = await tester.startGesture(Offset(video.right - 40, video.center.dy + 40));
      await gesture.moveBy(const Offset(0, -20));
      await _settle(tester);
      await gesture.moveBy(const Offset(0, -40));
      await _settle(tester);
      await gesture.up();
      await _settle(tester);
      expect(system, greaterThan(0.3));
      expect(system, lessThan(0.6), reason: "moved from 30 %, not from the player's 100 %");
      final afterDrag = system;

      // The panel shows what the drag left.
      await _menu(tester, 'volume');
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '${(afterDrag * 100).round()}%');
      // And it follows the volume keys while open.
      system = 0.65;
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '65%');
      expect(calls, isNot(contains('setBrightness')));
      await _closePanel(tester);
      await _close(tester, room);
    });

    testWidgets('elsewhere: the player volume, kept for the room; muting comes back to it', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800, platform: TargetPlatform.windows);
      await _menu(tester, 'volume');
      expect(_in('room-volume-panel', find.text('只对这个直播间生效，下次进来还是这个音量')), findsOneWidget);
      final slider = tester.widget<Slider>(_key('room-volume-slider'));
      slider.onChangeStart!(1);
      slider.onChanged!(0.4);
      slider.onChangeEnd!(0.4);
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '40%');
      expect(room.services.store.settings.get(Settings.roomVolumes), {'room_vol_bilibili_6': 0.4});
      await tester.tap(_key('room-volume-mute'));
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '0%');
      await tester.tap(_key('room-volume-mute'));
      await _settle(tester);
      expect(_text(tester, 'room-volume-value'), '40%');
      await _closePanel(tester);
      await _close(tester, room);
    });
  });

  testWidgets('U.2n c4 (B-13): the address panel goes back a page and marks the quality and line that play', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _menu(tester, 'streamLink');
    final scheme = Theme.of(tester.element(_key('stream-panel-copy'))).colorScheme;
    // The quality that plays: the primary colour with the tick.
    expect(_in('stream-quality-0', find.byIcon(AppIcons.selected)), findsOneWidget);
    expect(tester.widget<Text>(_in('stream-quality-0', find.text('原画'))).style?.color, scheme.primary);
    expect(_in('stream-quality-0', find.text('正在播放')), findsOneWidget);
    expect(_in('stream-quality-1', find.byIcon(AppIcons.selected)), findsNothing);
    expect(_key('stream-panel-back'), findsNothing, reason: 'the first page');

    await tester.tap(_key('stream-quality-1'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('超清 · 选择线路'), findsOneWidget);
    expect(_key('stream-line-1'), findsOneWidget);
    expect(find.byIcon(AppIcons.selected), findsNothing, reason: 'not the quality that plays');
    // ← goes back to the qualities.
    await tester.tap(_key('stream-panel-back'));
    await tester.pumpAndSettle();
    expect(_key('stream-quality-1'), findsOneWidget);
    expect(_key('stream-line-1'), findsNothing);

    await tester.tap(_key('stream-quality-0'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(_in('stream-line-0', find.byIcon(AppIcons.selected)), findsOneWidget, reason: 'the line that plays');
    expect(_in('stream-line-0', find.textContaining('正在播放')), findsOneWidget);
    expect(_in('stream-line-1', find.byIcon(AppIcons.selected)), findsNothing);
    await _closePanel(tester);
    await _close(tester, room);
  });

  group('U.2n c5: the fit is one small menu next to its button', () {
    Future<Rect> fitMenu(WidgetTester tester) async {
      _noDialog(tester);
      expect(find.byType(PopupMenuItem<int>), findsNWidgets(6));
      expect(_in('video-fit-0', find.byIcon(AppIcons.selected)), findsOneWidget);
      final scheme = Theme.of(tester.element(_key('video-fit-0'))).colorScheme;
      expect(tester.widget<Text>(_in('video-fit-0', find.text('默认比例'))).style?.color, scheme.primary);
      return tester.getRect(_key('video-fit-0')).expandToInclude(tester.getRect(_key('video-fit-5')));
    }

    testWidgets('from the room menu: under the menu button, lined up with it; a choice applies', (tester) async {
      final room = await _pump(tester);
      final button = tester.getRect(_menuButton());
      await _menu(tester, 'videoFit');
      final menu = await fitMenu(tester);
      expect(menu.top, greaterThan(button.bottom));
      expect(menu.top - button.bottom, lessThan(20));
      expect(menu.right, lessThanOrEqualTo(button.right));
      expect(button.right - menu.right, lessThan(20), reason: "lined up with the button's right edge");
      await tester.tap(_key('video-fit-2'));
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.videoFitIndex), 2);
      await _close(tester, room);
    });

    testWidgets('from the landscape bar: the same menu above its button', (tester) async {
      final room = await _pump(tester, width: 852, height: 393);
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      final button = tester.getRect(_key('live-play-video-fit'));
      await tester.tap(_key('live-play-video-fit'));
      await tester.pumpAndSettle();
      final menu = await fitMenu(tester);
      expect(menu.bottom, lessThan(button.top));
      await tester.tap(_key('video-fit-1'));
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.videoFitIndex), 1);
      await _close(tester, room);
    });
  });

  group('U.2n c10: toasts in fullscreen sit above the bottom bar', () {
    Future<Rect> toast(WidgetTester tester) async {
      showAppToastOn(ScaffoldMessenger.of(tester.element(_key('live-play-fullscreen'))), const AppToast('已复制直链'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    }

    testWidgets('landscape: 16 above the bar', (tester) async {
      final room = await _pump(tester, width: 852, height: 393);
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      final bar = tester.getRect(_key('live-play-bottom-bar'));
      final rect = await toast(tester);
      expect(rect.bottom, moreOrLessEquals(bar.top - 16));
      expect(rect.width, appToastMaxWidth);
      await tester.pump(const Duration(seconds: 4));
      await _close(tester, room);
    });

    testWidgets('portrait fullscreen: above both rows; the room page keeps 16 from the bottom', (tester) async {
      final room = await _pump(tester);
      var rect = await toast(tester);
      expect(rect.bottom, moreOrLessEquals(852 - 16));
      ScaffoldMessenger.of(tester.element(_key('live-play-fullscreen'))).removeCurrentSnackBar();
      await tester.pump();
      await tester.tap(_key('live-play-fullscreen'));
      await _settle(tester);
      expect(_key('live-play-bottom-first-row'), findsOneWidget, reason: 'the portrait fullscreen');
      final bar = tester.getRect(_key('live-play-bottom-bar'));
      rect = await toast(tester);
      expect(rect.bottom, moreOrLessEquals(bar.top - 16));
      await tester.pump(const Duration(seconds: 4));
      await _close(tester, room);
    });
  });
}
