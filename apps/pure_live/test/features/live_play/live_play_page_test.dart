import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'live_play_support.dart';

Future<AppServices> _pump(
  WidgetTester tester, {
  required FakeSite site,
  required FakeDanmaku danmaku,
  double width = 400,
  LiveRoom? room,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
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
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  return services;
}

/// Lets a setting reach the widgets.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

void main() {
  testWidgets('phone: header, room strip, qualities, chat and flying danmaku; follow and unfollow', (tester) async {
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
    AppNavigator.toast = (_) {};

    expect(find.byKey(const ValueKey('live-play-portrait-stack')), findsOneWidget);
    expect(find.text('主播'), findsWidgets);
    // U.2a change 1: "平台 · 分区" under the name (3.x wrote "平台 / 分区").
    expect(find.text('哔哩哔哩 · 英雄联盟'), findsOneWidget);
    expect(find.text('今晚开黑'), findsWidgets);
    // U.2a change 7: the figure is an icon and the number; its name is the
    // tooltip (3.x wrote "热度 12.0万").
    expect(find.text('12.0万'), findsOneWidget);
    expect(find.byTooltip('热度'), findsOneWidget);
    expect(find.text('原画'), findsOneWidget);
    expect(find.text('线路1'), findsOneWidget);
    expect(find.text('弹幕列表'), findsOneWidget);
    expect(danmaku.connects, ['args-6']);

    danmaku.chat('第一条弹幕');
    await tester.pump();
    expect(find.textContaining('第一条弹幕', findRichText: true), findsOneWidget);
    final overlay = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
    expect(overlay.flyingCount, 1);

    // M13.16: the platform's bundled emoticons are pictures in the chat list.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    danmaku.chat('好[dog]');
    await tester.pump();
    final pictures = tester.widgetList<Image>(
      find.descendant(of: find.byKey(const ValueKey('live-play-chat')), matching: find.byType(Image)),
    );
    expect(
      [for (final picture in pictures) ((picture.image as ResizeImage).imageProvider as AssetImage).assetName],
      ['assets/emo/images/bilibili/dog.png'],
    );

    await tester.tap(find.byKey(const ValueKey('live-play-follow')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect((await tester.runAsync(services.store.follows.all))!.single.title, '今晚开黑');
    // U.2a change 12: "✓ 已关注" instead of 3.x's filled heart.
    expect(find.descendant(of: find.byKey(const ValueKey('live-play-follow')), matching: find.text('已关注')), findsOne);
    expect(find.byIcon(AppIcons.followed), findsOneWidget);

    // U.2n c8 (B-15): a small menu under the button says who and offers
    // "取消关注" in red; no centred dialog.
    await tester.tap(find.byKey(const ValueKey('live-play-follow')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('主播 · 哔哩哔哩'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('unfollow-confirm'));
    expect(find.descendant(of: confirm, matching: find.text('取消关注')), findsOneWidget);
    final scheme = Theme.of(tester.element(confirm)).colorScheme;
    expect(tester.widget<Text>(find.descendant(of: confirm, matching: find.text('取消关注'))).style?.color, scheme.error);
    expect(
      tester.getRect(confirm).top,
      greaterThan(tester.getRect(find.byKey(const ValueKey('live-play-follow'))).bottom),
      reason: 'under the button',
    );
    await tester.tap(confirm);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await tester.runAsync(services.store.follows.all), isEmpty);
    // Then a toast with "撤销", which puts the room back.
    expect(find.text('已取消关注 主播'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-toast-action')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(services.store.follows.all))!.single.title, '今晚开黑');

    await _close(tester, services);
  });

  testWidgets('room details show the announcement and the time on air', (tester) async {
    final started = DateTime.now().subtract(const Duration(minutes: 30));
    final services = await _pump(
      tester,
      site: FakeSite(liveRoom(startedAt: started)),
      danmaku: FakeDanmaku(),
    );
    // U.2a change 7: the time on air on the strip (was "已开播 30 分钟"); B09
    // c5 (audit B-16): in words, not "0:30".
    expect(find.text('30 分钟'), findsOneWidget);

    // U.2a: the details open over the chat instead of the old bottom sheet.
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    expect(find.text('公告'), findsOneWidget);
    expect(find.text('每晚八点开播'), findsOneWidget);
    expect(find.textContaining('已播 30 分钟'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-play-details')), findsNothing);
    await _close(tester, services);
  });

  testWidgets('block list: a word added in the tab is stored', (tester) async {
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: FakeDanmaku());
    AppNavigator.toast = (_) {};
    await tester.tap(find.text('屏蔽管理'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('live-play-block-input')), '剧透');
    await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(await tester.runAsync(() => services.store.blockLists.list(BlockKind.keyword)), ['剧透']);
    await _close(tester, services);
  });

  testWidgets('offline and failed rooms say why; wide windows put the chat beside the video', (tester) async {
    final site = FakeSite(liveRoom(status: LiveStatus.offline));
    var services = await _pump(tester, site: site, danmaku: FakeDanmaku(), width: 1200);
    expect(find.byKey(const ValueKey('live-play-desktop-split')), findsOneWidget);
    expect(find.text('当前主播未开播或已下播'), findsOneWidget);
    await _close(tester, services);

    final failing = FakeSite(liveRoom())..detailError = const NotFound(SiteIds.bilibili);
    services = await _pump(tester, site: failing, danmaku: FakeDanmaku());
    expect(find.text('直播间不存在或已被删除'), findsOneWidget);
    // U.2g c10: a room that does not exist offers another room, not a retry.
    expect(find.text('切换直播间'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await _close(tester, services);
  });

  testWidgets('M13.16: back from picture-in-picture the controls hide again and answer; shaded bars', (tester) async {
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: FakeDanmaku());
    final player = tester.state(find.byType(RoomPlayer));
    // The bars sit on a dark shade reaching past them: U.2a change 3 makes
    // it 60 % black at the edge (M13.16 had 70 %), fading into the picture.
    final shade = tester.widget<DecoratedBox>(find.byKey(const ValueKey('live-play-bottom-shade')));
    expect(((shade.decoration as BoxDecoration).gradient! as LinearGradient).colors.first, OnVideoColors.scrim);

    PictureInPicture.active.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('live-play-fullscreen')), findsNothing, reason: 'only the picture');
    expect(tester.state(find.byType(RoomPlayer)), same(player), reason: 'one player across the layouts');
    await tester.pump(const Duration(seconds: 5));

    PictureInPicture.active.value = false;
    await tester.pump();
    expect(tester.state(find.byType(RoomPlayer)), same(player));
    Finder controls() =>
        find.ancestor(of: find.byKey(const ValueKey('live-play-fullscreen')), matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(controls()).opacity, 0, reason: 'hidden again after 4 s');

    // A tap shows them; the fullscreen button works.
    await tester.tap(find.byType(LiveVideoView));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await tester.pump();
    expect(find.text('弹幕列表'), findsNothing);
    expect(find.byKey(const ValueKey('live-play-top-shade')), findsOneWidget);
    expect(tester.state(find.byType(RoomPlayer)), same(player));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('弹幕列表'), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('fullscreen hides the chat; back leaves fullscreen first', (tester) async {
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: FakeDanmaku());
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await tester.pump();
    expect(find.text('弹幕列表'), findsNothing);
    expect(find.text('今晚开黑'), findsOneWidget);

    final popped = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popped, isTrue);
    expect(find.text('弹幕列表'), findsOneWidget);
    await _close(tester, services);
  });

  group('F.2b: a tap or long press on a flying danmaku', () {
    /// Three danmaku in, the third (lane 3, below the top bar) a second in.
    Future<(DanmakuOverlayState, Offset)> fly(WidgetTester tester, FakeDanmaku danmaku, {String user = '路人'}) async {
      danmaku
        ..chat('第一条')
        ..chat('第二条')
        ..chat('点这一条弹幕', user: user);
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final overlay = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
      final (_, rect) = overlay.debugFlying.firstWhere((item) => item.$1.message == '点这一条弹幕');
      final box = tester.renderObject<RenderBox>(find.byType(DanmakuOverlay));
      return (overlay, box.localToGlobal(rect.center));
    }

    DanmakuOverlay overlay(WidgetTester tester) => tester.widget(find.byType(DanmakuOverlay));

    testWidgets('opens the long-press sheet; the danmaku stand until it closes', (tester) async {
      final danmaku = FakeDanmaku();
      final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
      AppNavigator.toast = (_) {};
      final (state, at) = await fly(tester, danmaku);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-copy-message')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-block-user')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-block-keyword')), findsOneWidget);
      expect(overlay(tester).held, isTrue);
      final rect = state.debugFlying.last.$2;
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.debugFlying.last.$2, rect, reason: 'held');

      await tester.tap(find.byKey(const ValueKey('room-panel-close')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsNothing);
      expect(overlay(tester).held, isFalse);

      // The long press opens the same sheet.
      final (_, again) = await fly(tester, danmaku);
      await tester.longPressAt(again);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-panel-close')));
      await tester.pump(const Duration(milliseconds: 400));
      await _close(tester, services);
    });

    testWidgets('B09 c1: a tap opens the actions at once; a double tap takes them back for the fullscreen', (
      tester,
    ) async {
      final danmaku = FakeDanmaku();
      final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
      AppNavigator.toast = (_) {};
      final (_, at) = await fly(tester, danmaku);
      await tester.tapAt(at);
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsOneWidget, reason: 'no double tap wait');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsNothing);
      expect(find.byType(AppBar), findsNothing, reason: 'fullscreen');
      expect(overlay(tester).held, isFalse);
      await _close(tester, services);
    });

    testWidgets('B01 c1: a masked sender (观***) has no "屏蔽此用户" in the sheet', (tester) async {
      final danmaku = FakeDanmaku();
      final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
      AppNavigator.toast = (_) {};
      final (_, at) = await fly(tester, danmaku, user: '观***');
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-block-user')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-block-keyword')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-panel-close')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await _close(tester, services);
    });

    testWidgets('with the tap switch off, a tap only shows or hides the controls; never on the bars', (tester) async {
      final danmaku = FakeDanmaku();
      final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
      await tester.runAsync(() => services.store.settings.set(Settings.enableDanmakuTapInteraction, false));
      await _settle(tester);
      final (_, at) = await fly(tester, danmaku);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live-play-message-sheet')), findsNothing);
      await _close(tester, services);

      expect(
        danmakuTapAllowed(
          local: const Offset(10, 40),
          size: const Size(400, 225),
          controlsVisible: true,
          top: 52,
          bottom: 52,
        ),
        isFalse,
      );
      expect(
        danmakuTapAllowed(
          local: const Offset(10, 200),
          size: const Size(400, 225),
          controlsVisible: true,
          top: 52,
          bottom: 52,
        ),
        isFalse,
      );
      expect(
        danmakuTapAllowed(
          local: const Offset(10, 100),
          size: const Size(400, 225),
          controlsVisible: true,
          top: 52,
          bottom: 52,
        ),
        isTrue,
      );
      expect(
        danmakuTapAllowed(
          local: const Offset(10, 40),
          size: const Size(400, 225),
          controlsVisible: false,
          top: 52,
          bottom: 52,
        ),
        isTrue,
      );
    });
  });

  testWidgets('F.2a, U.2h c10: the room passes the frame rate, the font and text-only; a paused video stops them', (
    tester,
  ) async {
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: danmaku);
    await tester.runAsync(() async {
      await services.store.settings.set(Settings.danmakuAutoFps, false);
      await services.store.settings.set(Settings.danmakuFps, 30);
      await services.store.settings.set(Settings.danmakuFontFamilyName, 'LXGWWenKai');
      await services.store.settings.set(Settings.noEmojiMode, true);
    });
    await _settle(tester);
    var overlay = tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay));
    expect(overlay.fps, 30);
    expect(overlay.look.fontFamily, 'LXGWWenKai');
    expect(overlay.look.textOnly, isTrue);
    expect(overlay.running, isTrue);

    final room = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller;
    await tester.runAsync(room.session.togglePlayPause);
    await tester.pump();
    overlay = tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay));
    expect(overlay.running, isFalse);
    danmaku.chat('暂停时不飞');
    await tester.pump();
    expect(tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay)).flyingCount, 0);

    // B02 c3: "暂停时的弹幕 · 继续飘过" lets them fly on while paused.
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuPausedBehavior, 'continue'));
    await tester.pump();
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).running, isTrue);
    danmaku.chat('暂停时照飞');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay)).flyingCount, 1);
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuPausedBehavior, 'pause'));
    await tester.pump();
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).running, isFalse);
    await _close(tester, services);
  });

  testWidgets('F.1a: "屏幕常亮" off, the room does not keep the screen on; on again, at once', (tester) async {
    final applied = <bool>[];
    ScreenWake.reset();
    ScreenWake.apply = ({required enabled}) async => applied.add(enabled);
    addTearDown(ScreenWake.reset);
    final services = await _pump(tester, site: FakeSite(liveRoom()), danmaku: FakeDanmaku());
    expect(applied, [true], reason: 'on by default (3.x), while it plays');
    await tester.runAsync(() => services.store.settings.set(Settings.enableScreenKeepOn, false));
    await _settle(tester);
    expect(applied, [true, false]);
    await tester.runAsync(() => services.store.settings.set(Settings.enableScreenKeepOn, true));
    await _settle(tester);
    expect(applied, [true, false, true]);
    await _close(tester, services);
    expect(applied.last, isFalse, reason: 'released when the room goes');
  });
}
