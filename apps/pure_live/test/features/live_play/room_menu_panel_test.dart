// The room menu on the picture (docs/A-界面设计/A07-直播间界面/A07.23-横屏右上角菜单升级): the
// fullscreen bars' four-square button opens the room's panel (on the right
// in landscape, along the bottom in portrait fullscreen) instead of the small
// menu; the room page's bar keeps the small menu.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

final class _Room {
  new(this.services, this.engine);

  final AppServices services;
  final FakeEngine engine;
}

final Map<String, ThemeData> _themes = {
  'light': const LiveTheme().light,
  'dark': const LiveTheme().dark,
  'pure black': const LiveTheme(pureBlack: true).dark,
};

Future<_Room> _pump(
  WidgetTester tester, {
  required double width,
  required double height,
  ThemeData? theme,
  bool portrait = false,
  String? link,
  Map<Setting<Object>, Object> settings = const {},
}) async {
  // Reset by [_close].
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  const systemAccess = MethodChannel('pure_live/system_access');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, (call) async => false);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, null));
  final engine = FakeEngine();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom(link: link, startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: MaterialApp(
        theme: theme ?? const LiveTheme().light,
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
  return _Room(services, engine);
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The menu button on the picture's top bar.
Finder _videoMenu() => find.descendant(of: _key('live-play-top-bar'), matching: _key('live-play-menu'));

/// Opens the fullscreen and its menu panel.
Future<void> _openFullscreenMenu(WidgetTester tester) async {
  await _tap(tester, _key('live-play-fullscreen'));
  await _tap(tester, _videoMenu());
}

const _all = [
  'switchRoom',
  'timer',
  'volume',
  'videoFit',
  'cast',
  'streamLink',
  'share',
  'external',
  'newWindow',
  'localInteraction',
];

/// The room menu's rows shown in the panel, top to bottom.
List<String> _panelRows(WidgetTester tester) => [
  for (final entry in _all)
    if (_in('room-menu-panel', _key('room-menu-$entry')).evaluate().isNotEmpty) entry,
]..sort((a, b) => tester.getTopLeft(_key('room-menu-$a')).dy.compareTo(tester.getTopLeft(_key('room-menu-$b')).dy));

/// The rows of each group card of the panel.
List<List<String>> _groups(WidgetTester tester) => [
  for (var index = 0; _key('room-menu-group-$index').evaluate().isNotEmpty; index++)
    [
      for (final entry in _panelRows(tester))
        if (_in('room-menu-group-$index', _key('room-menu-$entry')).evaluate().isNotEmpty) entry,
    ],
];

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadStrings);

  for (final MapEntry(key: name, value: theme) in _themes.entries) {
    testWidgets('869×400 landscape ($name): the button opens the room menu panel on the right with every entry', (
      tester,
    ) async {
      final room = await _pump(tester, width: 869, height: 400, theme: theme);
      await _openFullscreenMenu(tester);
      // The room's panel, not the small menu over the corner.
      expect(_key('room-menu-panel'), findsOneWidget);
      expect(find.byType(PopupMenuItem<RoomMenuEntry>), findsNothing);
      expect(_in('room-menu-panel', find.text('菜单')), findsOneWidget, reason: 'the title');
      final panel = tester.getRect(_key('live-play-side-panel'));
      expect(panel, const Rect.fromLTWH(869 - 360.0, 0, 360, 400), reason: 'where every landscape panel is');
      // The same groups as the small menu, less what the bars show; those
      // are on the bars, so every 3.x entry is one tap away.
      expect(_groups(tester), [
        ['timer', 'volume'],
        ['streamLink', 'share', 'external'],
        ['localInteraction'],
      ]);
      expect(_key('live-play-switch-room'), findsOneWidget);
      expect(_key('live-play-cast'), findsOneWidget);
      expect(_key('live-play-video-fit'), findsOneWidget);
      // 3.x's icons; › on the rows that open a panel.
      const icons = {
        'timer': AppIcons.sleepTimer,
        'volume': AppIcons.roomVolume,
        'streamLink': AppIcons.streamLink,
        'share': AppIcons.share,
        'external': AppIcons.openExternal,
        'localInteraction': AppIcons.localInteraction,
      };
      for (final MapEntry(key: entry, value: icon) in icons.entries) {
        expect(_in('room-menu-$entry', find.byIcon(icon)), findsOneWidget, reason: entry);
        final opens = entry != 'share' && entry != 'external';
        expect(_in('room-menu-$entry', find.byIcon(AppIcons.forward)), opens ? findsOneWidget : findsNothing);
        final row = tester.getRect(_key('room-menu-$entry'));
        expect(row.height, greaterThanOrEqualTo(52), reason: '$entry: a 52 row (48 to tap and more)');
        expect(row.left, greaterThanOrEqualTo(panel.left));
        expect(row.right, lessThanOrEqualTo(panel.right));
      }
      expect(_in('room-menu-external', find.text('在哔哩哔哩打开')), findsOneWidget);
      expect(
        tester.getRect(_key('room-menu-localInteraction')).bottom,
        lessThanOrEqualTo(400),
        reason: 'the K90 on its side shows every row without scrolling',
      );
      // Readable: the words and icons on the card at least 4.5:1.
      final scheme = theme.colorScheme;
      final card = Color.alphaBlend(scheme.surfaceContainerHighest.withValues(alpha: 0.55), scheme.surface);
      final label = tester.widget<Text>(_in('room-menu-timer', find.text('定时关闭')));
      expect(_contrast(label.style!.color!, card), greaterThanOrEqualTo(4.5), reason: '$name: the name');
      final icon = tester.widget<Icon>(_in('room-menu-timer', find.byIcon(AppIcons.sleepTimer)));
      expect(_contrast(icon.color!, card), greaterThanOrEqualTo(4.5), reason: '$name: the icon');
      final rowColor = tester.widget<Material>(_key('room-panel')).color!;
      expect(rowColor, scheme.surface, reason: "the app's theme, as every panel (docs/specs/UI.md §3.7)");
      // The menu keeps the controls up while it is open.
      await tester.pump(const Duration(seconds: 10));
      expect(_videoMenu(), findsOneWidget);
      await _close(tester, room);
    });
  }

  testWidgets('a 2608×1200 window: the same panel, 360 wide on the right', (tester) async {
    final room = await _pump(tester, width: 2608, height: 1200);
    await _openFullscreenMenu(tester);
    expect(tester.getRect(_key('live-play-side-panel')), const Rect.fromLTWH(2608 - 360.0, 0, 360, 1200));
    expect(_groups(tester), [
      ['timer', 'volume'],
      ['streamLink', 'share', 'external'],
      ['localInteraction'],
    ]);
    await _close(tester, room);
  });

  testWidgets(
    "portrait: the room page's bar keeps the small menu; the portrait fullscreen opens the panel at the bottom",
    (tester) async {
      final room = await _pump(tester, width: 393, height: 852, portrait: true);
      await _tap(tester, _key('live-play-menu').first);
      expect(find.byType(PopupMenuItem<RoomMenuEntry>), findsWidgets, reason: 'the small menu next to the bar button');
      expect(_key('room-menu-panel'), findsNothing);
      for (final entry in ['switchRoom', 'timer', 'volume', 'videoFit', 'cast', 'streamLink', 'share', 'external']) {
        expect(_key('room-menu-$entry'), findsOneWidget, reason: entry);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));

      await _openFullscreenMenu(tester);
      expect(_key('room-menu-panel'), findsOneWidget);
      final panel = tester.getRect(_key('live-play-bottom-panel'));
      expect(panel.bottom, 852);
      expect(panel.width, 393);
      expect(_groups(tester), [
        ['timer', 'volume', 'videoFit'],
        ['streamLink', 'share', 'external'],
        ['localInteraction'],
      ]);
      expect(_in('room-menu-videoFit', find.byIcon(AppIcons.aspectRatio)), findsOneWidget);
      expect(tester.widget<Text>(_key('room-menu-videoFit-description')).data, '默认比例');
      // The button above the panel closes it again.
      await _tap(tester, _videoMenu());
      expect(_key('room-menu-panel'), findsNothing);
      await _close(tester, room);
    },
  );

  testWidgets('taps: a panel row opens its panel in place, an action closes it, the button and ✕ close it', (
    tester,
  ) async {
    final opened = <Uri>[];
    final previous = AppNavigator.openExternal;
    AppNavigator.openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => AppNavigator.openExternal = previous);
    final room = await _pump(tester, width: 869, height: 400, link: 'https://live.bilibili.com/6');
    await _openFullscreenMenu(tester);
    final panel = tester.getRect(_key('live-play-side-panel'));
    // The sleep timer opens where the menu was.
    await _tap(tester, _key('room-menu-timer'));
    expect(_key('room-menu-panel'), findsNothing);
    expect(_key('room-timer-panel'), findsOneWidget);
    expect(tester.getRect(_key('room-timer-panel')), panel);
    await _tap(tester, _key('room-panel-close'));
    expect(_key('room-timer-panel'), findsNothing);

    // Back closes it as every panel and stays in the fullscreen.
    await _tap(tester, _videoMenu());
    expect(_key('room-menu-panel'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_key('room-menu-panel'), findsNothing);
    expect(_videoMenu(), findsOneWidget, reason: 'still fullscreen');

    // Volume, the stream address and the local interaction: their panels.
    for (final (entry, opens) in [
      ('volume', 'room-volume-panel'),
      ('streamLink', 'panel-stream-link'),
      ('localInteraction', 'panel-local'),
    ]) {
      await _tap(tester, _videoMenu());
      await _tap(tester, _key('room-menu-$entry'));
      expect(_key(opens), findsOneWidget, reason: entry);
      expect(_key('room-menu-panel'), findsNothing);
      await _tap(tester, _key('room-panel-close'));
    }

    // "在哔哩哔哩打开" closes the panel and opens the page.
    await _tap(tester, _videoMenu());
    await tester.tap(_key('room-menu-external'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 1));
    expect(_key('room-menu-panel'), findsNothing);
    expect(opened, [Uri.parse('https://live.bilibili.com/6')], reason: 'the page (the test runs on the host)');
    await _close(tester, room);
  });

  testWidgets('portrait fullscreen: "画面比例" opens its small menu at the row; a fit closes the panel', (tester) async {
    final room = await _pump(tester, width: 393, height: 852, portrait: true);
    await _openFullscreenMenu(tester);
    final row = tester.getRect(_key('room-menu-videoFit'));
    await _tap(tester, _key('room-menu-videoFit'));
    expect(_key('video-fit-1'), findsOneWidget);
    final menu = tester.getRect(_key('video-fit-0'));
    expect((menu.top - row.bottom).abs() < 8 || (row.top - menu.bottom).abs() < 400, isTrue, reason: 'next to the row');
    await _tap(tester, _key('video-fit-1'));
    expect(room.services.store.settings.get(Settings.videoFitIndex), 1);
    expect(_key('room-menu-panel'), findsNothing);
    // Dismissed without a choice, the panel stays.
    await _tap(tester, _videoMenu());
    await _tap(tester, _key('room-menu-videoFit'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(_key('room-menu-panel'), findsOneWidget);
    expect(tester.widget<Text>(_key('room-menu-videoFit-description')).data, videoFitName(1));
    await _close(tester, room);
  });

  for (final (size, portrait) in [(const Size(869, 400), false), (const Size(393, 852), true)]) {
    testWidgets('2× text at ${size.width.toInt()}×${size.height.toInt()}: no overflow, every row reachable', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final room = await _pump(tester, width: size.width, height: size.height, portrait: portrait);
      await _openFullscreenMenu(tester);
      expect(_key('room-menu-panel'), findsOneWidget);
      // The last row: scrolled to, tapped, its panel opens.
      await tester.ensureVisible(_key('room-menu-localInteraction'));
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, _key('room-menu-localInteraction'));
      expect(_key('panel-local'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, room);
    });
  }
}
