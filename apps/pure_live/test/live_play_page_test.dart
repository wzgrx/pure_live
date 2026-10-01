import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/pages/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import 'live_play_support.dart';
import 'support.dart';

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
    expect(find.text('哔哩哔哩 / 英雄联盟'), findsOneWidget);
    expect(find.text('今晚开黑'), findsOneWidget);
    expect(find.textContaining('热度 12.0万'), findsOneWidget);
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
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-play-follow')));
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(services.store.follows.all), isEmpty);

    await _close(tester, services);
  });

  testWidgets('room info sheet shows the announcement and the time on air', (tester) async {
    final started = DateTime.now().subtract(const Duration(minutes: 30));
    final services = await _pump(
      tester,
      site: FakeSite(liveRoom(startedAt: started)),
      danmaku: FakeDanmaku(),
    );
    expect(find.textContaining('已开播 30 分钟'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    expect(find.text('公告'), findsOneWidget);
    expect(find.text('每晚八点开播'), findsOneWidget);
    expect(find.text('开播时间'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
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
    expect(find.text('重试'), findsOneWidget);
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
}
