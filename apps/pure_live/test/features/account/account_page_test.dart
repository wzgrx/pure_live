import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/account/account_page.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/auth/auth_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// "Now" of every test (Douyu's session ends are computed from it).
final DateTime _now = DateTime(2026, 10, 1, 20);

/// Answers like the platforms: `SESSDATA=ok` signs in Alice (uid 42),
/// `SESSDATA=bad` signs in nobody, anything else cannot be checked.
Future<AccountIdentity> _verifier(String site, String cookie) async {
  if (cookie.contains('=ok')) return (name: 'Alice', uid: site == SiteIds.bilibili ? 42 : null);
  if (cookie.contains('=bad')) throw NeedsLogin(site, 'test');
  throw NetworkFailure(site, 'test');
}

/// A QR login whose answers the test queues.
final class _FakeQr implements BilibiliQrApi {
  int codes = 0;
  final List<({BilibiliQrState state, String? cookie})> answers = [];

  @override
  Future<({String key, Uri url})> qrCode() async {
    codes++;
    return (key: 'key$codes', url: Uri.parse('https://passport.bilibili.com/h5-app/passport/login/scan?key=$codes'));
  }

  @override
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key) async =>
      answers.isEmpty ? (state: BilibiliQrState.waiting, cookie: null) : answers.removeAt(0);
}

final class _Harness {
  new(this.services, this.toasts, this.router, this.renewals);

  final AppServices services;
  final List<String> toasts;
  final GoRouter router;
  final List<String> renewals;

  LiveStore get store => services.store;
}

const List<String> _accountPaths = [
  RoutePath.kSettingsAccount,
  RoutePath.kBiliBiliQRLogin,
  RoutePath.kBiliBiliWebLogin,
  RoutePath.kHuyaCookie,
  RoutePath.kDouyuAccountCookie,
  RoutePath.kDouyinCookie,
  RoutePath.kDouyuCookie,
  RoutePath.kTwitchCookie,
  RoutePath.kYyCookie,
  RoutePath.kSoop,
  RoutePath.kKuaishouCookie,
];

const List<String> _authPaths = [RoutePath.kSignIn, RoutePath.kMine, RoutePath.kUserManage];

/// Pumps [path] over an in-memory store holding [cookies], [secrets] and
/// Douyu's save time.
Future<_Harness> _pump(
  WidgetTester tester, {
  String path = RoutePath.kSettingsAccount,
  Map<String, String> cookies = const {},
  Map<String, String?> secrets = const {},
  int douyuSavedAt = 0,
  BilibiliQrApi? qr,
}) async {
  tester.view
    ..physicalSize = const Size(420, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    for (final MapEntry(:key, :value) in cookies.entries) {
      await services.store.secrets.setCookie(key, value);
    }
    if (secrets.isNotEmpty) await services.store.secrets.writeAll(secrets);
    if (douyuSavedAt > 0) await services.store.settings.set(Settings.douyuCookieSavedAt, douyuSavedAt);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final renewals = <String>[];
  final router = GoRouter(
    initialLocation: path,
    routes: [
      for (final account in _accountPaths)
        GoRoute(
          path: account,
          builder: (_, state) => AccountPage(route: RouteArgs(account, arguments: state.extra)),
        ),
      for (final auth in _authPaths)
        GoRoute(
          path: auth,
          builder: (_, _) => AuthPage(route: RouteArgs(auth)),
        ),
      GoRoute(
        path: RoutePath.kWebDavPage,
        builder: (_, _) => const Scaffold(body: Text('webdav page')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        accountClockProvider.overrideWithValue(() => _now),
        accountVerifierProvider.overrideWithValue(_verifier),
        bilibiliQrApiProvider.overrideWithValue(qr ?? _FakeQr()),
        douyuRenewerProvider.overrideWithValue(({required cookie, required ltp0, required did}) async {
          renewals.add('$ltp0/$did');
          return 'dy_auth=renewed; LTP0=$ltp0';
        }),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Harness(services, toasts, router, renewals);
}

/// Lets the store (real async work) and the checks finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _status(WidgetTester tester, String site) =>
    tester.widget<Text>(find.byKey(ValueKey('account-$site-status'))).data!;

Future<void> _enter(WidgetTester tester, String text, {Key key = const ValueKey('account-cookie-input')}) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  testWidgets('lists every platform with what its stored cookie is worth', (tester) async {
    final harness = await _pump(
      tester,
      cookies: {
        SiteIds.bilibili: 'SESSDATA=ok; DedeUserID=42',
        SiteIds.douyin: 'sessionid=bad',
        SiteIds.twitch: 'auth-token=abc; login=Viewer',
        SiteIds.huya: 'udb_uid=1; yyuid=1234',
        SiteIds.cc: 'a=b',
        SiteIds.soop: 'x=y',
      },
    );
    expect(_status(tester, SiteIds.bilibili), '已登录：Alice');
    expect(harness.store.settings.get(Settings.bilibiliUid), 42);
    expect(_status(tester, SiteIds.douyin), '登录已失效，请重新登录或更换 Cookie');
    expect(_status(tester, SiteIds.twitch), '已保存 · 聊天身份 viewer');
    expect(_status(tester, SiteIds.huya), '已保存 · 账号 ID 1234');
    expect(_status(tester, SiteIds.cc), contains('暂未用于请求'));
    expect(_status(tester, SiteIds.soop), 'Cookie 已保存在本机');
    expect(_status(tester, SiteIds.douyu), '未设置');
    expect(_status(tester, SiteIds.kuaishou), '未设置');
    expect(find.byKey(const ValueKey('account-douyin-sign-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-douyu-sign-out')), findsNothing);
  });

  testWidgets('an expired Bilibili login is signed out with a message (3.x)', (tester) async {
    final harness = await _pump(tester, cookies: {SiteIds.bilibili: 'SESSDATA=bad'});
    expect(harness.store.secrets.cookieFor(SiteIds.bilibili), isNull);
    expect(harness.toasts, contains('哔哩哔哩登录已失效，请重新登录'));
    expect(_status(tester, SiteIds.bilibili), '未登录');
  });

  testWidgets('signs out of one platform and of all after asking', (tester) async {
    final harness = await _pump(
      tester,
      cookies: {SiteIds.soop: 'x=y', SiteIds.douyu: 'dy_auth=a'},
      secrets: {SecretRefs.douyuLtp0: 'L'},
    );
    await _tap(tester, find.byKey(const ValueKey('account-soop-sign-out')));
    expect(find.text('确定退出“Soop”账号吗？'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('account-confirm-cancel')));
    expect(harness.store.secrets.cookieFor(SiteIds.soop), 'x=y');

    await _tap(tester, find.byKey(const ValueKey('account-soop-sign-out')));
    await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
    expect(harness.store.secrets.cookieFor(SiteIds.soop), isNull);
    expect(harness.toasts.last, '已退出Soop');
    expect(_status(tester, SiteIds.soop), '未设置');

    await _tap(tester, find.byKey(const ValueKey('account-menu')));
    await _tap(tester, find.byKey(const ValueKey('account-sign-out-all')));
    await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
    expect(harness.store.secrets.cookieSites, isEmpty);
    expect(harness.store.secrets.read(SecretRefs.douyuLtp0), isNull);
  });

  testWidgets('a cookie page stores the pasted header, refuses non-cookies and asks before discarding', (tester) async {
    final harness = await _pump(tester);
    await _tap(tester, find.byKey(const ValueKey('account-huya')));
    expect(find.text('虎牙 账号'), findsOneWidget);

    await _enter(tester, 'just some text');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(find.textContaining('这不像 Cookie'), findsOneWidget);
    expect(harness.store.secrets.cookieFor(SiteIds.huya), isNull);

    await _enter(tester, 'Cookie: udb_uid=1; yyuid=99\n');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.huya), 'udb_uid=1; yyuid=99');
    expect(harness.toasts.last, 'Cookie 已保存在本机');
    expect(find.text('已保存 · 账号 ID 99'), findsOneWidget);

    await _enter(tester, 'udb_uid=2');
    await tester.pageBack();
    await _settle(tester);
    expect(find.text('舍弃 Cookie 修改？'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
    expect(find.byKey(const ValueKey('account-huya')), findsOneWidget);
    expect(harness.store.secrets.cookieFor(SiteIds.huya), 'udb_uid=1; yyuid=99');
  });

  testWidgets('the paste button reads the clipboard', (tester) async {
    final harness = await _pump(tester, path: RoutePath.kYyCookie);
    String? clipboard = 'yyuid=5';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return clipboard == null ? null : {'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _tap(tester, find.byKey(const ValueKey('account-cookie-paste')));
    expect(find.text('yyuid=5'), findsOneWidget);
    clipboard = null;
    await _tap(tester, find.byKey(const ValueKey('account-cookie-paste')));
    expect(find.text('yyuid=5'), findsOneWidget);
    expect(harness.toasts.last, '剪贴板里没有文字');
  });

  testWidgets('Bilibili and Douyin cookies are checked before they are stored', (tester) async {
    final harness = await _pump(tester, path: RoutePath.kBiliBiliWebLogin);
    expect(find.textContaining('网页登录需要内置浏览器'), findsOneWidget);

    await _enter(tester, 'SESSDATA=bad');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.bilibili), isNull);
    expect(harness.toasts.last, '这段 Cookie 没有登录或已失效，未保存');

    await _enter(tester, 'SESSDATA=ok');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=ok');
    expect(harness.store.settings.get(Settings.bilibiliUid), 42);
    expect(harness.toasts.last, '已登录：Alice');
    expect(find.text('已登录：Alice'), findsOneWidget);

    // Cannot be checked right now: stored and marked unchecked.
    harness.router.go(RoutePath.kDouyinCookie);
    await _settle(tester);
    await _enter(tester, 'sessionid=offline');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.douyin), 'sessionid=offline');
    expect(find.text('已保存，暂时无法核验账号（网络或平台异常）'), findsOneWidget);

    // Emptying the box and saving signs out after asking.
    await _enter(tester, '');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
    expect(harness.store.secrets.cookieFor(SiteIds.douyin), isNull);
  });

  testWidgets('CC opens its cookie page through the accounts route', (tester) async {
    final harness = await _pump(tester);
    await _tap(tester, find.byKey(const ValueKey('account-cc')));
    expect(find.text('网易CC 账号'), findsOneWidget);
    await _enter(tester, 'NTES_SESS=abc');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.cc), 'NTES_SESS=abc');
  });

  testWidgets('Douyu: a passport cookie only brings the renewal pair; renew now; forced renewal', (tester) async {
    final savedAt = _now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
    final harness = await _pump(
      tester,
      path: RoutePath.kDouyuAccountCookie,
      cookies: {SiteIds.douyu: 'dy_auth=login; dy_did=d1'},
      douyuSavedAt: savedAt,
    );
    expect(find.textContaining('未配置 LTP0'), findsOneWidget);

    // The passport request's cookie: fields filled, the login kept.
    await _enter(tester, 'LTP0=long; dy_did=d1; acf_ssid=s');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('douyu-ltp0-input'))).controller!.text, 'long');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('douyu-did-input'))).controller!.text, 'd1');
    await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
    expect(harness.store.secrets.cookieFor(SiteIds.douyu), 'dy_auth=login; dy_did=d1');
    expect(harness.store.secrets.read(SecretRefs.douyuLtp0), 'long');
    expect(harness.store.secrets.read(SecretRefs.douyuDid), 'd1');
    expect(harness.store.settings.get(Settings.douyuCookieSavedAt), savedAt);
    expect(harness.toasts.last, contains('保留了原来的登录 Cookie'));
    expect(find.textContaining('到期前会自动续期'), findsOneWidget);

    await _tap(tester, find.text('立即续期'));
    expect(harness.renewals, ['long/d1']);
    expect(harness.store.secrets.cookieFor(SiteIds.douyu), 'dy_auth=renewed; LTP0=long');
    expect(harness.store.settings.get(Settings.douyuCookieSavedAt), _now.millisecondsSinceEpoch ~/ 1000);
    expect(harness.toasts.last, startsWith('续期成功'));

    expect(harness.store.settings.get(Settings.douyuForceRenew), isFalse);
    await _tap(tester, find.text('登录后强制续期'));
    expect(harness.store.settings.get(Settings.douyuForceRenew), isTrue);

    await _tap(tester, find.byKey(const ValueKey('account-cookie-sign-out')));
    await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
    expect(harness.store.secrets.cookieFor(SiteIds.douyu), isNull);
    expect(harness.store.secrets.read(SecretRefs.douyuLtp0), isNull);
    expect(harness.store.settings.get(Settings.douyuCookieSavedAt), 0);
  });

  testWidgets('Bilibili QR login: scanned, expired and refreshed, then confirmed and stored', (tester) async {
    final qr = _FakeQr();
    final harness = await _pump(tester, qr: qr);
    await _tap(tester, find.byKey(const ValueKey('account-bilibili')));
    expect(find.byKey(const ValueKey('bilibili-qr-code')), findsOneWidget);
    expect(find.text('请使用 哔哩哔哩 手机客户端扫码登录'), findsOneWidget);

    qr.answers
      ..add((state: BilibiliQrState.scanned, cookie: null))
      ..add((state: BilibiliQrState.expired, cookie: null));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('已扫描，请在手机上确认登录'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('二维码已失效'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('bilibili-qr-refresh')));
    expect(qr.codes, 2);
    qr.answers.add((state: BilibiliQrState.confirmed, cookie: 'SESSDATA=ok; DedeUserID=42'));
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(harness.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=ok; DedeUserID=42');
    expect(harness.store.settings.get(Settings.bilibiliUid), 42);
    expect(harness.toasts, contains('已登录：Alice'));
    // Back on the list, signed in.
    expect(_status(tester, SiteIds.bilibili), '已登录：Alice');
  });

  testWidgets('Douyu summary follows the session state', (tester) async {
    await tester.runAsync(loadStrings);
    String summary(String cookie, {String? ltp0, DateTime? savedAt}) => douyuSummary(
      AccountSnapshot(cookie: cookie, douyuLtp0: ltp0, douyuSavedAt: savedAt),
      now: _now,
    );
    expect(summary('dy_did=1'), contains('游客'));
    expect(summary('dy_auth=a', savedAt: _now.subtract(const Duration(days: 8))), contains('已过期'));
    expect(
      summary('dy_auth=a; dy_did=d', ltp0: 'L', savedAt: _now.subtract(const Duration(days: 8))),
      contains('自动用 LTP0'),
    );
    expect(cleanPastedCookie(' Cookie: a=b; c=d \n'), 'a=b; c=d');
    expect(looksLikeCookie('a=b'), isTrue);
    expect(looksLikeCookie('hello'), isFalse);
  });

  testWidgets('the cloud account routes explain the retirement and lead to the syncs', (tester) async {
    await _pump(tester, path: RoutePath.kMine);
    expect(find.text('云端账号已停用'), findsOneWidget);
    await _tap(tester, find.text('WebDav'));
    expect(find.text('webdav page'), findsOneWidget);
  });
}
