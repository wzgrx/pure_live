// The portrait live room of U.2a (docs/ui/compare/U.2a/README.md): the
// order, icons and states the confirmed design fixes.
import 'dart:async';

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
import 'package:pure_live/features/live_play/layout/room_details.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/area_lookup.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A platform whose detail waits for [gate] (the room loading).
class _SlowSite extends FakeSite {
  new(super.room);

  final Completer<void> gate = Completer();

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    await gate.future;
    return await super.getRoomDetail(roomId: roomId);
  }
}

final class _Room {
  new(this.services, this.engine, this.danmaku, this.toasts);

  final AppServices services;
  final FakeEngine engine;
  final FakeDanmaku danmaku;
  final List<String> toasts;
}

Future<_Room> _pump(
  WidgetTester tester, {
  FakeSite? site,
  double width = 400,
  double height = 900,
  LiveRoom? room,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  final engine = FakeEngine();
  final danmaku = FakeDanmaku();
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  final platform = site ?? FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => platform})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, engine, danmaku, toasts);
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
}

/// The keys of [keys] found under [scope], left to right.
List<String> _order(WidgetTester tester, Finder scope, List<String> keys) {
  final found =
      [
        for (final key in keys)
          if (find.descendant(of: scope, matching: find.byKey(ValueKey(key))).evaluate().isNotEmpty) key,
      ]..sort(
        (a, b) => tester.getCenter(find.byKey(ValueKey(a))).dx.compareTo(tester.getCenter(find.byKey(ValueKey(b))).dx),
      );
  return found;
}

Finder _in(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);

void main() {
  testWidgets('header: back, avatar and names, follow, menu; the follow button follows the store', (tester) async {
    final room = await _pump(tester);
    final bar = find.byType(AppBar);
    expect(_order(tester, bar, ['live-play-title', 'live-play-follow', 'live-play-record', 'live-play-menu']), [
      'live-play-title',
      'live-play-follow',
      'live-play-menu',
    ], reason: 'no FFmpeg in tests: no record button');
    expect(find.descendant(of: bar, matching: find.byIcon(AppIcons.back)), findsOneWidget);
    expect(_in('live-play-menu', find.byIcon(AppIcons.roomMenu)), findsOneWidget);

    // Change 1: the name 15 semi-bold, "平台 · 分区" 12 in the secondary colour.
    final name = tester.widget<Text>(_in('live-play-title', find.text('主播')));
    expect(name.style?.fontSize, 15);
    expect(name.style?.fontWeight, FontWeight.w600);
    final area = tester.widget<Text>(find.text('哔哩哔哩 · 英雄联盟'));
    expect(area.style?.fontSize, 12);
    final scheme = Theme.of(tester.element(bar)).colorScheme;
    expect(area.style?.color, scheme.onSurfaceVariant);
    expect(tester.getSize(find.byKey(const ValueKey('live-play-title'))).width, greaterThanOrEqualTo(100));

    // Change 12: "＋ 关注" filled, then "✓ 已关注" grey; unfollowing asks.
    expect(_in('live-play-follow', find.byIcon(AppIcons.follow)), findsOneWidget);
    expect(_in('live-play-follow', find.text('关注')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-play-follow')));
    await _settle(tester);
    expect(_in('live-play-follow', find.byIcon(AppIcons.followed)), findsOneWidget);
    expect(_in('live-play-follow', find.text('已关注')), findsOneWidget);
    final followed = tester.widget<FilledButton>(find.byKey(const ValueKey('live-play-follow')));
    expect(followed.style?.backgroundColor?.resolve({}), scheme.surfaceContainerHighest);
    await tester.tap(find.byKey(const ValueKey('live-play-follow')));
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(room.services.store.follows.all), hasLength(1));
    await _close(tester, room);
  });

  testWidgets('portrait video bars: top title, audio, cast; bottom play to fullscreen', (tester) async {
    final room = await _pump(tester);
    final top = find.byKey(const ValueKey('live-play-top-bar'));
    expect(top, findsOneWidget, reason: 'change 2: the top bar shows in the portrait room too');
    expect(_in('live-play-top-bar', find.text('今晚开黑')), findsOneWidget);
    // Picture-in-picture joins on Android devices that offer it (the host
    // running the tests is not one, see topBarSlots below).
    expect(_order(tester, top, ['live-play-video-title', 'live-play-audio-only', 'live-play-cast', 'live-play-pip']), [
      'live-play-video-title',
      'live-play-audio-only',
      'live-play-cast',
    ]);
    expect(_in('live-play-audio-only', find.byIcon(AppIcons.audioOnly)), findsOneWidget);
    expect(_in('live-play-cast', find.byIcon(AppIcons.cast)), findsOneWidget);
    expect(_in('live-play-top-bar', find.byKey(const ValueKey('live-play-back'))), findsNothing);

    final bottom = find.byKey(const ValueKey('live-play-bottom-bar'));
    const all = [
      'live-play-pause',
      'live-play-refresh',
      'live-play-video-follow',
      'live-play-danmaku-toggle',
      'live-play-danmaku-settings',
      'live-play-quality',
      'live-play-video-fit',
      'live-play-orientation',
      'live-play-fullscreen',
    ];
    // Change 4: no "已关注" and no fit on the portrait bar (choice C, change 5).
    expect(_order(tester, bottom, all), [
      'live-play-pause',
      'live-play-refresh',
      'live-play-danmaku-toggle',
      'live-play-danmaku-settings',
      'live-play-orientation',
      'live-play-fullscreen',
    ]);
    expect(_in('live-play-pause', find.byIcon(AppIcons.pause)), findsOneWidget);
    expect(_in('live-play-refresh', find.byIcon(AppIcons.refresh)), findsOneWidget);
    expect(
      tester.widget<DanmakuIcon>(_in('live-play-danmaku-toggle', find.byType(DanmakuIcon))).kind,
      DanmakuIconKind.on,
    );
    expect(
      tester.widget<DanmakuIcon>(_in('live-play-danmaku-settings', find.byType(DanmakuIcon))).kind,
      DanmakuIconKind.settings,
    );
    expect(_in('live-play-orientation', find.byIcon(AppIcons.orientationAuto)), findsOneWidget);
    expect(_in('live-play-fullscreen', find.byIcon(AppIcons.fullscreen)), findsOneWidget);
    // Change 3: 60 % black at the edge, reaching into the picture; taps on
    // the shade reach the picture.
    final shade = find.byKey(const ValueKey('live-play-top-shade'));
    final decoration = tester.widget<DecoratedBox>(shade).decoration as BoxDecoration;
    expect((decoration.gradient! as LinearGradient).colors.first, OnVideoColors.scrim);
    expect(tester.getSize(shade).height, greaterThan(controlBarHeight + controlShadeReach - 1));
    expect(find.ancestor(of: shade, matching: find.byType(IgnorePointer)), findsWidgets);

    // E4: hiding the danmaku says once that the list keeps them.
    await tester.tap(find.byKey(const ValueKey('live-play-danmaku-toggle')));
    await _settle(tester);
    expect(
      tester.widget<DanmakuIcon>(_in('live-play-danmaku-toggle', find.byType(DanmakuIcon))).kind,
      DanmakuIconKind.off,
    );
    expect(room.toasts, ['已隐藏画面上的弹幕，弹幕列表照常显示']);
    await tester.tap(find.byKey(const ValueKey('live-play-danmaku-toggle')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('live-play-danmaku-toggle')));
    await _settle(tester);
    expect(room.toasts, hasLength(1));

    // E6: a fixed orientation turns the button yellow; the tooltip says it.
    await tester.tap(find.byKey(const ValueKey('live-play-orientation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-orientation-landscape')));
    await _settle(tester);
    final orientation = tester.widget<VideoIconButton>(find.byKey(const ValueKey('live-play-orientation')));
    expect(orientation.color, OnVideoColors.active);
    expect(orientation.tooltip, '画面方向：强制横屏');
    expect(_in('live-play-orientation', find.byIcon(AppIcons.orientationLandscape)), findsOneWidget);
    expect(room.services.store.settings.get(Settings.portraitRoomOverrides), {'bilibili:6': 'landscape'});
    await _close(tester, room);
  });

  testWidgets('fullscreen bars: back and room switcher on top; follow, pickers and fit at the bottom', (tester) async {
    final room = await _pump(tester, width: 900, height: 500);
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await _settle(tester);
    final top = find.byKey(const ValueKey('live-play-top-bar'));
    expect(
      _order(tester, top, ['live-play-back', 'live-play-video-title', 'live-play-switch-room', 'live-play-audio-only']),
      ['live-play-back', 'live-play-video-title', 'live-play-switch-room', 'live-play-audio-only'],
    );
    final bottom = find.byKey(const ValueKey('live-play-bottom-bar'));
    expect(
      _order(tester, bottom, [
        'live-play-pause',
        'live-play-refresh',
        'live-play-video-follow',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'live-play-quality',
        'live-play-line',
        'live-play-video-fit',
        'live-play-orientation',
        'live-play-fullscreen',
      ]),
      [
        'live-play-pause',
        'live-play-refresh',
        'live-play-video-follow',
        'live-play-danmaku-toggle',
        'live-play-danmaku-settings',
        'live-play-quality',
        'live-play-line',
        'live-play-video-fit',
        'live-play-orientation',
        'live-play-fullscreen',
      ],
    );
    expect(_in('live-play-video-follow', find.text('关注')), findsOneWidget);
    expect(_in('live-play-video-fit', find.text('默认比例')), findsOneWidget);
    expect(_in('live-play-fullscreen', find.byIcon(AppIcons.exitFullscreen)), findsOneWidget);
    // The fit button moves to the next fit (3.x `VideoFitSetting`).
    await tester.tap(find.byKey(const ValueKey('live-play-video-fit')));
    await _settle(tester);
    expect(room.services.store.settings.get(Settings.videoFitIndex), 1);
    expect(_in('live-play-video-fit', find.text('居中裁剪')), findsOneWidget);
    await _close(tester, room);
  });

  testWidgets('room strip: title and 详情, audience with steady digits, time on air, quality and line buttons', (
    tester,
  ) async {
    final room = await _pump(tester);
    expect(_in('live-play-info', find.text('今晚开黑')), findsOneWidget);
    expect(_in('live-play-info', find.text('详情')), findsOneWidget);
    expect(_in('live-play-info', find.byIcon(AppIcons.dropDown)), findsOneWidget);
    final heat = tester.widget<Text>(_in('live-play-audience', find.text('12.0万')));
    expect(heat.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(_in('live-play-audience', find.byIcon(AppIcons.audienceHeat)), findsOneWidget);
    expect(_in('live-play-audience', find.byIcon(AppIcons.liveDuration)), findsOneWidget);
    expect(_in('live-play-audience', find.text('0:30')), findsOneWidget);
    // Change 8: drop-down buttons, 32 high, 48 to touch.
    expect(_in('live-play-quality', find.text('原画')), findsOneWidget);
    expect(_in('live-play-line', find.text('线路1')), findsOneWidget);
    expect(_in('live-play-quality', find.byIcon(AppIcons.dropDown)), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('live-play-quality'))).height, greaterThanOrEqualTo(48));
    final box = find.descendant(
      of: find.byKey(const ValueKey('live-play-quality')),
      matching: find.byType(DecoratedBox),
    );
    expect(tester.getSize(box.first).height, 32);
    await _close(tester, room);
  });

  testWidgets('E2: names, strip and audience wait as grey bars until the room answers', (tester) async {
    final site = _SlowSite(liveRoom());
    final room = await _pump(
      tester,
      site: site,
      room: LiveRoom(platform: SiteIds.bilibili, roomId: '6'),
    );
    expect(find.byKey(const ValueKey('live-play-title-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-info-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-audience-placeholder')), findsOneWidget);
    site.gate.complete();
    await _settle(tester);
    expect(find.byKey(const ValueKey('live-play-title-placeholder')), findsNothing);
    expect(find.text('哔哩哔哩 · 英雄联盟'), findsOneWidget);
    await _close(tester, room);
  });

  testWidgets('details: over the chat, never the picture; Back, 收起 and a pull close them; follow in step', (
    tester,
  ) async {
    final site = FakeSite(
      liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30)), link: 'https://live.bilibili.com/6'),
    );
    final room = await _pump(tester, site: site);
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    final details = find.byKey(const ValueKey('live-play-details'));
    expect(details, findsOneWidget);
    expect(_in('live-play-info', find.text('收起')), findsOneWidget);
    final player = tester.getRect(find.byType(RoomPlayer));
    final strip = tester.getRect(find.byKey(const ValueKey('live-play-info')));
    expect(tester.getRect(details).top, greaterThanOrEqualTo(strip.bottom), reason: 'under the strip');
    expect(tester.getRect(details).overlaps(player), isFalse, reason: 'the picture stays uncovered');
    expect(find.byKey(const ValueKey('live-play-tabs')), findsOneWidget, reason: 'covered, not removed');
    // The details' content (change list "直播间详情").
    expect(_in('live-play-details-state', find.text('直播')), findsOneWidget);
    expect(_in('live-play-details-state', find.textContaining('已播 30 分钟')), findsOneWidget);
    expect(_in('live-play-details-figures', find.text('热度')), findsOneWidget);
    expect(_in('live-play-details-figures', find.text('0:30')), findsOneWidget);
    expect(find.text('每晚八点开播'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-details-copy-room-id')), findsOneWidget);
    final list = find.descendant(
      of: find.byKey(const ValueKey('live-play-details-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.byKey(const ValueKey('live-play-details-open')), 100, scrollable: list);
    expect(find.text('在哔哩哔哩打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-details-share')), findsOneWidget);

    // The follow button there and on the bar show the same.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('live-play-details-follow')), -100, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('live-play-details-follow')));
    await _settle(tester);
    expect(_in('live-play-follow', find.text('已关注')), findsOneWidget);
    expect(_in('live-play-details-follow', find.text('已关注')), findsOneWidget);

    // Back closes the details first and stays in the room.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(details, findsNothing);
    expect(find.byType(RoomPlayer), findsOneWidget);

    // The name opens them (E1); "收起" closes them.
    await tester.tap(find.byKey(const ValueKey('live-play-title')));
    await tester.pumpAndSettle();
    expect(details, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    expect(details, findsNothing);

    // A pull down past the top closes them.
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('live-play-details-list')), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(details, findsNothing);
    await _close(tester, room);
  });

  testWidgets('details on a wide window cover the chat column only; an unknown area says so', (tester) async {
    final room = await _pump(tester, width: 1200);
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    final details = tester.getRect(find.byKey(const ValueKey('live-play-details')));
    final player = tester.getRect(find.byType(RoomPlayer));
    expect(details.left, greaterThanOrEqualTo(player.right));
    await tester.tap(find.byKey(const ValueKey('live-play-details-area')));
    await _settle(tester);
    expect(room.toasts, contains('没有找到这个分区'));
    await _close(tester, room);
  });

  testWidgets('chat: compact lines, system labels once in 3 s, cards on request; counts on the tabs', (tester) async {
    final now = DateTime.now();
    final site = FakeSite(liveRoom())
      ..superChats = [
        LiveSuperChatMessage(
          userName: '老板',
          face: '',
          message: '加油',
          price: 30,
          startTime: now.subtract(const Duration(seconds: 10)),
          endTime: now.add(const Duration(minutes: 5)),
          backgroundColor: '#EDF5FF',
          backgroundBottomColor: '#2A60B2',
        ),
      ];
    final room = await _pump(tester, site: site);
    // Change 9: "醒目留言" with its count.
    expect(_in('live-play-super-chat-count', find.text('1')), findsOneWidget);

    // Change 10: the status line is a centred grey label, once in 3 s.
    room.danmaku.emit(const DanmakuReady());
    await tester.pump();
    expect(find.text('弹幕服务器连接正常'), findsOneWidget);
    expect(_in('live-play-system-line', find.text('弹幕服务器连接正常')), findsOneWidget);
    expect(find.textContaining('系统消息'), findsNothing);

    // Change 11: "用户名：" in the secondary colour, the message in the normal one.
    room.danmaku.chat('前排支持', user: '星河');
    await tester.pump();
    final line = tester.widget<Text>(_in('live-play-chat-line', find.byType(Text)).first);
    final spans = (line.textSpan! as TextSpan).children!;
    final name = spans.whereType<TextSpan>().firstWhere((span) => span.text == '星河：');
    final scheme = Theme.of(tester.element(find.byType(LivePlayPage))).colorScheme;
    expect(name.style?.color, scheme.onSurfaceVariant);
    expect(find.textContaining('前排支持', findRichText: true), findsOneWidget);

    // The details hide the tabs; what arrives meanwhile is counted.
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    room.danmaku
      ..chat('一')
      ..chat('二');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    expect(_in('live-play-unread-count', find.text('2')), findsOneWidget);
    await tester.tap(find.text('弹幕列表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-play-unread-count')), findsNothing);

    // Choice A: 3.x's cards stay as a setting.
    await tester.tap(find.text('弹幕设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卡片'));
    await _settle(tester);
    expect(room.services.store.settings.get(Settings.danmakuListStyle), 'card');
    await tester.tap(find.text('弹幕列表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-play-chat-card')), findsWidgets);
    expect(find.byKey(const ValueKey('live-play-chat-line')), findsNothing);
    await _close(tester, room);
  });

  testWidgets('chat actions: a double tap copies, a long press blocks a keyword (back from 3.x)', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final room = await _pump(tester);
    room.danmaku.chat('剧透警告', user: '路人');
    await tester.pump();
    final line = find.byKey(const ValueKey('live-play-chat-line')).last;
    await tester.tap(line);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(copied, '路人: 剧透警告');

    await tester.longPress(find.byKey(const ValueKey('live-play-chat-line')).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-play-copy-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-block-user')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-play-block-keyword')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('live-play-keyword-input')), '剧透');
    await tester.tap(find.byKey(const ValueKey('live-play-keyword-confirm')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => room.services.store.blockLists.list(BlockKind.keyword)), ['剧透']);
    expect(find.textContaining('剧透警告', findRichText: true), findsNothing);
    expect(room.toasts, contains('关键词已加入弹幕屏蔽列表'));
    await _close(tester, room);
  });

  testWidgets('menu: four squares; 画面比例 picks the fit', (tester) async {
    final room = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('live-play-menu')));
    await tester.pumpAndSettle();
    expect(_in('room-menu-videoFit', find.text('画面比例')), findsOneWidget);
    expect(_in('room-menu-videoFit', find.byIcon(AppIcons.aspectRatio)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-menu-videoFit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video-fit-2')));
    await _settle(tester);
    expect(room.services.store.settings.get(Settings.videoFitIndex), 2);
    await _close(tester, room);
  });

  testWidgets('E3: a dropped stream says it reconnects and offers the next line; E5 audio only', (tester) async {
    final room = await _pump(tester);
    room.engine.emit(const EngineBuffering(buffering: true));
    await tester.pump();
    expect(find.text('正在重连（第 1 次）'), findsOneWidget);
    await tester.tap(find.text('换线路'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('live-play-reconnecting')), findsNothing);
    expect(room.engine.opens.last.toString(), contains('b.example'));

    await tester.tap(find.byKey(const ValueKey('live-play-audio-only')));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-play-audio-cover')), findsOneWidget);
    expect(find.text('纯音频播放中'), findsOneWidget);
    final audio = tester.widget<VideoIconButton>(find.byKey(const ValueKey('live-play-audio-only')));
    expect(audio.color, OnVideoColors.active);
    await _close(tester, room);
  });

  group('room logic of U.2a', () {
    setUpAll(loadStrings);

    test('ReconnectWatch counts drops of a playing stream, not the user asking for another', () {
      final states = StreamController<PlaybackState>(sync: true);
      addTearDown(states.close);
      var now = DateTime(2026, 10, 1, 20);
      final watch = ReconnectWatch(states.stream, now: () => now);
      addTearDown(watch.dispose);
      PlaybackState status(PlaybackStatus value) => PlaybackState(status: value);
      states
        ..add(status(PlaybackStatus.opening))
        ..add(status(PlaybackStatus.playing));
      expect(watch.reconnecting, isFalse, reason: 'the first open is no drop');
      states.add(status(PlaybackStatus.buffering));
      expect((watch.reconnecting, watch.attempts), (true, 1));
      states
        ..add(status(PlaybackStatus.playing))
        ..add(status(PlaybackStatus.buffering));
      expect(watch.attempts, 2, reason: 'again soon after');
      states.add(status(PlaybackStatus.playing));
      now = now.add(const Duration(minutes: 1));
      states.add(status(PlaybackStatus.buffering));
      expect(watch.attempts, 1, reason: 'after a settled minute it counts from one');
      states.add(status(PlaybackStatus.playing));
      watch.expectReopen();
      states.add(status(PlaybackStatus.buffering));
      expect(watch.reconnecting, isFalse, reason: 'another line or quality');
      states.add(status(PlaybackStatus.stopped));
      expect(watch.attempts, 0);
    });

    test('orientation choice: remembered under the room, or for this run only', () async {
      final services = await testServices();
      addTearDown(services.close);
      RoomOrientationChoice.clearSession();
      final room = LiveRoom(platform: SiteIds.bilibili, roomId: '6');
      final choice = RoomOrientationChoice(settings: services.store.settings, room: room);
      expect(choice.value, RoomOrientation.automatic);
      await choice.choose(RoomOrientation.portrait, remember: false);
      expect(choice.value, RoomOrientation.portrait);
      expect(services.store.settings.get(Settings.portraitRoomOverrides), isEmpty);
      await choice.choose(RoomOrientation.landscape, remember: true);
      expect(services.store.settings.get(Settings.portraitRoomOverrides), {'bilibili:6': 'landscape'});
      expect(isPortraitLayout(choice.value, detected: true), isFalse);
      expect(isPortraitLayout(RoomOrientation.automatic, detected: true), isTrue);
    });

    test('areas by name; texts of the strip and the details; the top bar slots', () {
      final categories = [
        LiveCategory(
          id: '1',
          name: '网游',
          children: const [LiveArea(areaId: '86', areaName: '英雄联盟', shortName: 'LOL')],
        ),
      ];
      expect(findAreaByName(categories, ' 英雄联盟 ')?.areaId, '86');
      expect(findAreaByName(categories, 'lol')?.areaId, '86');
      expect(findAreaByName(categories, '王者荣耀'), isNull);
      expect(formatOnAir(const Duration(hours: 2, minutes: 18)), '2:18');
      expect(formatOnAir(const Duration(minutes: 5)), '0:05');
      final now = DateTime(2026, 10, 1, 21, 36);
      expect(startedText(DateTime(2026, 10, 1, 19, 18), now), '今天 19:18 开播');
      expect(startedText(DateTime(2026, 9, 30, 23, 5), now), '昨天 23:05 开播');
      expect(startedText(DateTime(2026, 9, 2, 8), now), '09-02 08:00 开播');
      expect(topBarSlots(android: true), [TopBarSlot.audioOnly, TopBarSlot.cast, TopBarSlot.pip]);
      expect(topBarSlots(android: false), [TopBarSlot.audioOnly]);
      expect(videoFits, hasLength(6));
    });
  });
}
