import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

// Task B06: Bilibili's masked names for guests, the way to log in from the
// chat list, the fan badge and the avatar.

/// The room page under a router whose QR login page is a stand-in.
Future<AppServices> _pump(
  WidgetTester tester, {
  required FakeSite site,
  required FakeDanmaku danmaku,
  BaseCacheManager? images,
}) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
      GoRoute(
        path: RoutePath.kBiliBiliQRLogin,
        builder: (_, _) => const Scaffold(body: Text('扫码登录页')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(imageCacheManager: images),
        child: MaterialApp.router(
          theme: const LiveTheme().light,
          routerConfig: router,
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        ),
      ),
    ),
  );
  await _settle(tester);
  return services;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
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

LiveMessage _chat(String user, String text, {String fans = '', String level = '', String avatar = ''}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: user,
  message: text,
  color: LiveMessageColor.white,
  fansName: fans,
  fansLevel: level,
  data: avatar.isEmpty ? null : DanmakuSender(avatar: avatar),
);

/// An image cache without pictures: every address fails, so an avatar
/// shows its letter (tests make no requests).
final class _NoImages implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(HttpExceptionWithStatus(404, 'no pictures in tests', uri: Uri.parse(url)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _hint(String text) =>
    find.descendant(of: find.byKey(const ValueKey('live-play-name-hint')), matching: find.text(text));

void main() {
  testWidgets('c1: a guest sees the hint above the chat; 去登录 opens the QR login; the login reconnects', (tester) async {
    final site = FakeSite(liveRoom());
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, site: site, danmaku: danmaku);
    danmaku.emit(DanmakuReceived(_chat('观***', '前排')));
    await tester.pump();

    expect(_hint('访客模式下哔哩哔哩会隐藏昵称'), findsOneWidget);
    expect(_hint('去登录'), findsOneWidget);
    final hint = tester.getRect(find.byKey(const ValueKey('live-play-name-hint')));
    final line = tester.getRect(find.byKey(const ValueKey('live-play-chat-line')).last);
    expect(hint.bottom, lessThanOrEqualTo(line.top), reason: 'above the lines');
    expect(find.text('哔哩哔哩访客连接会隐藏弹幕昵称；登录该平台后使用其返回的完整昵称'), findsNothing, reason: 'no system line');

    await tester.tap(find.byKey(const ValueKey('live-play-name-hint-login')));
    await _settle(tester);
    expect(find.text('扫码登录页'), findsOneWidget);

    // The QR page stores the login; the room fetches new credentials and
    // connects again while the page is still open.
    final details = site.detailCalls;
    final connects = danmaku.connects.length;
    site.room = liveRoom().copyWith(danmakuData: 'args-6-signed-in');
    await tester.runAsync(() => services.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1'));
    await _settle(tester);
    expect(site.detailCalls, details + 1);
    expect(danmaku.connects.length, connects + 1);
    expect(danmaku.connects.last, 'args-6-signed-in');

    AppNavigator.back();
    await _settle(tester);
    expect(find.byKey(const ValueKey('live-play-name-hint')), findsNothing, reason: 'signed in');
    danmaku.emit(DanmakuReceived(_chat('小路的观众', '登录后')));
    await tester.pump();
    expect(find.textContaining('小路的观众', findRichText: true), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('c1: a stored login whose names still come masked says it expired; 重新登录 opens the login', (tester) async {
    final site = FakeSite(liveRoom());
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, site: site, danmaku: danmaku);
    await tester.runAsync(() => services.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=old; DedeUserID=1'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('live-play-name-hint')), findsNothing);
    for (var i = 0; i < 3; i++) {
      danmaku.emit(DanmakuReceived(_chat('观***', '第$i条')));
    }
    await tester.pump();
    expect(_hint('登录已失效，哔哩哔哩隐藏了昵称'), findsOneWidget);
    expect(_hint('重新登录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-play-name-hint-login')));
    await _settle(tester);
    expect(find.text('扫码登录页'), findsOneWidget);
    AppNavigator.back();
    await _settle(tester);
    await _close(tester, services);
  });

  testWidgets('c2: the fan badge before the name; the card style shows the avatar instead of the dot', (tester) async {
    final site = FakeSite(liveRoom());
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, site: site, danmaku: danmaku, images: _NoImages());
    const face = 'https://i0.hdslb.com/bfs/face/a.jpg@96w_96h.jpg';
    danmaku.emit(DanmakuReceived(_chat('观***', '有牌子', fans: '小路泥', level: '22', avatar: face)));
    await tester.pump();
    // A08.10 G5: the medal is a chip like "本地" and "对方".
    final medal = find.byKey(const ValueKey('live-play-chat-fans'));
    expect(medal, findsOneWidget);
    expect(find.descendant(of: medal, matching: find.text('小路泥 22')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-chat-avatar')), findsNothing, reason: 'compact lines have none');

    await tester.runAsync(() => services.store.settings.set(Settings.danmakuListStyle, 'card'));
    await _settle(tester);
    danmaku.emit(DanmakuReceived(_chat('观***', '没头像')));
    await tester.pump();
    final cards = find.byKey(const ValueKey('live-play-chat-card'));
    expect(cards, findsNWidgets(2));
    // B08: the list is reversed (the newest line first in the tree), so the
    // cards are found by their text.
    Finder card(String text) => find.ancestor(of: find.text(text, findRichText: true), matching: cards);
    final avatar = find.descendant(of: card('有牌子'), matching: find.byType(CommonAvatar));
    expect(tester.widget<CommonAvatar>(avatar).avatarUrl, face);
    expect(tester.getSize(avatar), const Size(24, 24));
    expect(
      find.descendant(of: card('没头像'), matching: find.byType(CommonAvatar)),
      findsNothing,
      reason: 'the dot',
    );
    await _close(tester, services);
  });
}
