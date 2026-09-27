import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/web_login.dart';

import '../web/fake_web.dart';
import 'account_fakes.dart';

void main() {
  group('spec/sites/bilibili.md §8.4 the end of the web sign-in', () {
    test('HTTPS m. or www.bilibili.com ends it; everything else stays in the page', () {
      bool done(String url) => bilibiliWebLogin.isSignedIn(Uri.parse(url));
      expect(done('https://www.bilibili.com/'), isTrue);
      expect(done('https://m.bilibili.com/index.html'), isTrue);
      expect(done('http://www.bilibili.com/'), isFalse);
      expect(done('https://passport.bilibili.com/login'), isFalse);
      expect(done('https://space.bilibili.com/1'), isFalse);
    });

    WebLoginFlow flow(
      Map<String, List<WebCookie>> jar, {
      Object answer = const AccountIdentity(name: '小明', uid: '42'),
      List<String>? saved,
      List<String>? checked,
    }) => WebLoginFlow(
      spec: bilibiliWebLogin,
      cookies: (url) async => jar[url.host] ?? const [],
      verify: (cookie) async {
        checked?.add(cookie);
        if (answer is AccountIdentity) return answer;
        Error.throwWithStackTrace(answer, StackTrace.current);
      },
      save: (cookie, _) async => saved?.add(cookie),
    );

    test('the ending navigation is held; the cookie of that address is verified, then stored', () async {
      final saved = <String>[];
      final checked = <String>[];
      final login = flow(
        {
          'www.bilibili.com': const [
            WebCookie(name: 'SESSDATA', value: 's%2C1'),
            WebCookie(name: 'DedeUserID', value: '42'),
          ],
        },
        saved: saved,
        checked: checked,
      );
      expect(login.allow(Uri.parse('https://passport.bilibili.com/login?x=1')), isTrue);
      expect(login.allow(Uri.parse('https://www.bilibili.com/')), isFalse);
      // A second report of the same end (page started) does not run twice.
      login.onEvent(WebPageStarted(Uri.parse('https://www.bilibili.com/')));
      await pumpEventQueue();
      expect(checked, ['SESSDATA=s%2C1; DedeUserID=42']);
      expect(saved, ['SESSDATA=s%2C1; DedeUserID=42']);
      expect(login.phase, WebLoginPhase.done);
      expect(login.identity?.name, '小明');
    });

    test('no cookie, or one that does not verify, returns to the page with a message', () async {
      final saved = <String>[];
      final empty = flow({}, saved: saved);
      await empty.complete(Uri.parse('https://www.bilibili.com/'));
      expect((empty.phase, empty.message), (WebLoginPhase.browsing, '没有拿到登录信息，请重新登录'));

      final rejected = flow(
        {
          'm.bilibili.com': const [WebCookie(name: 'SESSDATA', value: 'x')],
        },
        answer: const NeedsLogin('bilibili', 'code -101'),
        saved: saved,
      );
      await rejected.complete(Uri.parse('https://m.bilibili.com/'));
      expect(rejected.message, '登录校验没有通过，请重新登录');

      final offline = flow({
        'm.bilibili.com': const [WebCookie(name: 'SESSDATA', value: 'x')],
      }, answer: const NetworkFailure('bilibili', 'offline'));
      await offline.complete(Uri.parse('https://m.bilibili.com/'));
      expect(offline.message, '登录校验失败：网络连接失败');
      expect(saved, isEmpty);
    });
  });

  testWidgets('F-ACC-01: the web sign-in page stores the verified cookie and closes', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (store, _, _) = await memoryAccounts();
    final engine = FakeWebEngine(
      jar: {
        'www.bilibili.com': const [WebCookie(name: 'SESSDATA', value: 's'), WebCookie(name: 'DedeUserID', value: '9')],
      },
    );
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.push('/web-login/bilibili'), child: const Text('去登录')),
          ),
        ),
        GoRoute(
          path: '/web-login/:platform',
          builder: (context, state) => const WebLoginPage(platform: 'bilibili'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(store),
          webEngineProvider.overrideWithValue(engine),
          webLoginVerifierProvider.overrideWith(
            (ref, platform) =>
                (cookie) async => const AccountIdentity(name: '小红', uid: '9'),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('去登录'));
    await settle(tester);
    final page = engine.pages.single;
    expect(page.loads, [Uri.parse('https://passport.bilibili.com/login')]);
    expect(find.byKey(const ValueKey('fake-web-page')), findsOneWidget);

    expect(await page.navigate(Uri.parse('https://www.bilibili.com/')), isFalse);
    await settle(tester);
    expect(store.cookie('bilibili'), 'SESSDATA=s; DedeUserID=9');
    expect(find.text('已登录：小红'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget, reason: 'the page closed');
    expect(page.disposed, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });
}
