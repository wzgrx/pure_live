import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/accounts_page.dart';
import 'package:pure_live_app/features/accounts/platform_account_page.dart';
import 'package:pure_live_app/features/accounts/web_login.dart';
import 'package:pure_live_app/features/sync/qr_code_view.dart';

import '../web/fake_web.dart';
import 'account_fakes.dart';

void main() {
  late AccountStore store;
  late FakeWebEngine engine;
  late FakeBilibiliLogin bilibili;
  late List<String> verified;

  Future<void> pumpApp(
    WidgetTester tester, {
    String at = '/me/accounts',
    Map<String, String> secrets = const {},
    WebAvailability web = WebAvailability.available,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // In the fake zone: a store made in runAsync completes its writes on the
    // real event loop, which the fake clock never reaches.
    (store, _, _) = await memoryAccounts(secrets);
    engine = FakeWebEngine(state: web);
    bilibili = FakeBilibiliLogin();
    verified = [];
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/me/accounts',
          builder: (context, state) => const AccountsPage(),
          routes: [
            GoRoute(
              path: ':platform',
              builder: (context, state) => PlatformAccountPage(platform: state.pathParameters['platform']!),
            ),
          ],
        ),
        GoRoute(
          path: '/web-login/:platform',
          builder: (context, state) => WebLoginPage(platform: state.pathParameters['platform']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store),
          accountSettingsProvider.overrideWithValue(MemoryAccountSettings()),
          enabledPlatformsProvider.overrideWithValue(platformOrder),
          webEngineProvider.overrideWithValue(engine),
          bilibiliLoginProvider.overrideWithValue(bilibili),
          accountVerifierProvider.overrideWith(
            (ref, platform) => switch (platform) {
              'bilibili' => () async {
                verified.add(platform);
                return const AccountIdentity(name: '小明', uid: '42');
              },
              'douyin' => () async {
                verified.add(platform);
                throw const NeedsLogin('douyin', '20003');
              },
              _ => null,
            },
          ),
          douyuRenewerProvider.overrideWithValue(({required cookie, required ltp0, required did}) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('F-ACC-01: every account platform with its state; names come from the platforms', (tester) async {
    await pumpApp(
      tester,
      secrets: {
        SecretRefs.cookie('bilibili'): 'SESSDATA=secret-value; DedeUserID=42',
        SecretRefs.cookie('douyin'): 'sessionid=secret-value',
        SecretRefs.cookie('huya'): 'udb=secret-value',
      },
    );
    for (final name in ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', 'YY', 'SOOP', 'Twitch']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    for (final name in ['网易CC', 'AcFun', '网络电视']) {
      expect(find.text(name), findsNothing, reason: '$name has no account in v4');
    }
    expect(verified, unorderedEquals(['bilibili', 'douyin']), reason: 'checked once on open');
    expect(find.text('已登录 · 小明（UID 42）'), findsOneWidget);
    expect(find.text('Cookie 已失效，请重新登录'), findsOneWidget);
    expect(find.text('已填 Cookie'), findsOneWidget);
    expect(find.textContaining('secret-value'), findsNothing, reason: 'constitution rule 8');
  });

  testWidgets('F-ACC-01: 退出 asks first; cancelling keeps the login', (tester) async {
    await pumpApp(tester, at: '/me/accounts/huya', secrets: {SecretRefs.cookie('huya'): 'udb=v'});
    expect(find.text('校验'), findsNothing, reason: 'huya has no user-info endpoint');
    await tester.tap(find.text('退出登录'));
    await settle(tester);
    expect(find.text('退出虎牙账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.text('退出虎牙账号？'), findsNothing);
    expect(store.cookie('huya'), 'udb=v');

    await tester.tap(find.text('退出登录'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await settle(tester);
    expect(store.cookie('huya'), isNull);
    expect(find.text('已退出登录'), findsOneWidget);
    expect(engine.cleared, 0, reason: 'only a web sign-in platform clears the browser');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-ACC-01: signing out of B 站 also clears the browser cookies (bilibili.md §8.2)', (tester) async {
    await pumpApp(tester, at: '/me/accounts/bilibili', secrets: {SecretRefs.cookie('bilibili'): 'SESSDATA=s'});
    expect(find.textContaining('会删除本机保存的登录信息'), findsNothing);
    await tester.tap(find.text('退出登录'));
    await settle(tester);
    expect(find.textContaining('并清除内置浏览器里的登录状态'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await settle(tester);
    expect(store.cookie('bilibili'), isNull);
    expect(engine.cleared, 1);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-ACC-01: a pasted cookie is stored and the box empties; the stored one is never shown', (tester) async {
    await pumpApp(tester, at: '/me/accounts/kuaishou');
    expect(find.text('未登录'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('cookie-input')),
      ' Cookie: userId=1; kuaishou.live.web_st=abc \n',
    );
    await tester.tap(find.text('保存'));
    await settle(tester);
    expect(store.cookie('kuaishou'), 'userId=1; kuaishou.live.web_st=abc');
    expect(find.text('已填 Cookie'), findsOneWidget);
    expect(find.textContaining('web_st=abc'), findsNothing);
    expect(find.text('已保存的 Cookie 不显示；粘贴新的会替换它'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-ACC-01: B 站 QR sign-in in place, polling stops with the page', (tester) async {
    await pumpApp(tester, at: '/me/accounts/bilibili');
    expect(find.text('网页登录'), findsOneWidget, reason: 'the fake browser is available');
    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump();
    expect(find.text('用哔哩哔哩手机客户端扫描二维码'), findsOneWidget);
    expect(find.byType(QrCodeView), findsOneWidget);

    bilibili.answers.add((state: BilibiliQrState.confirmed, cookie: 'SESSDATA=s; DedeUserID=42'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
    expect(store.cookie('bilibili'), 'SESSDATA=s; DedeUserID=42');
    expect(find.text('已登录：小明'), findsNothing, reason: 'the fake login names 测试');
    expect(find.text('已登录：测试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-ACC-01: Douyu offers 立即续期 only with LTP0 and dy_did', (tester) async {
    await pumpApp(tester, at: '/me/accounts/douyu', secrets: {SecretRefs.cookie('douyu'): 'dy_auth=w'});
    expect(find.text('立即续期'), findsNothing);
    expect(find.byKey(const ValueKey('douyu-ltp0')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('douyu-ltp0')), 'l');
    await tester.enterText(find.byKey(const ValueKey('douyu-did')), 'd');
    await tester.ensureVisible(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);
    expect((store.douyuLtp0, store.douyuDid), ('l', 'd'));
    await tester.ensureVisible(find.text('立即续期'));
    await tester.pump();
    await tester.tap(find.text('立即续期'));
    await settle(tester);
    expect(find.text('斗鱼没有返回新的登录信息，续期没有生效'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-ACC-01: without a browser the web sign-in is hidden', (tester) async {
    await pumpApp(tester, at: '/me/accounts/bilibili', web: WebAvailability.unsupported);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('网页登录'), findsNothing);
  });

  testWidgets('F-ACC-01: Windows without WebView2 keeps the entry and explains the install', (tester) async {
    await pumpApp(tester, at: '/me/accounts/bilibili', web: WebAvailability.missingRuntime);
    await tester.tap(find.text('网页登录'));
    await settle(tester);
    expect(find.text('需要 WebView2 运行时'), findsOneWidget);
    expect(find.textContaining('常青版引导程序'), findsOneWidget);
    expect(engine.pages, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
