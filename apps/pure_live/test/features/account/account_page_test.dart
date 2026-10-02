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
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/auth/auth_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';

import '../../support.dart';

// Every cookie, name and id here is an obvious placeholder.

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
  bool failCode = false;
  final List<({BilibiliQrState state, String? cookie})> answers = [];

  @override
  Future<({String key, Uri url})> qrCode() async {
    if (failCode) throw const NetworkFailure(SiteIds.bilibili, 'test');
    codes++;
    return (key: 'key$codes', url: Uri.parse('https://passport.example/scan?key=$codes'));
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
/// Douyu's save time; [unreadable] cookies cannot be opened on this device.
Future<_Harness> _pump(
  WidgetTester tester, {
  String path = RoutePath.kSettingsAccount,
  Map<String, String> cookies = const {},
  Map<String, String?> secrets = const {},
  Set<String> unreadable = const {},
  int douyuSavedAt = 0,
  BilibiliQrApi? qr,
  Size size = const Size(420, 1400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    for (final MapEntry(:key, :value) in cookies.entries) {
      await services.store.secrets.setCookie(key, value);
    }
    if (secrets.isNotEmpty) await services.store.secrets.writeAll(secrets);
    if (douyuSavedAt > 0) await services.store.settings.set(Settings.douyuCookieSavedAt, douyuSavedAt);
    services.store.secrets.unreadable.addAll(unreadable.map(SecretRefs.cookie));
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

String _cardStatus(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('account-status-text'))).data!;

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

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// The sign-out question for [name] (3.x `account_page.dart:244`): "退出登录",
/// "确定退出“[name]”账号吗？", "取消" and a red "退出登录".
void _expectSignOutQuestion(String name) {
  final dialog = find.byType(AppDialog);
  expect(dialog, findsOneWidget);
  expect(find.descendant(of: dialog, matching: find.text('退出登录')), findsNWidgets(2));
  expect(find.descendant(of: dialog, matching: find.text('确定退出“$name”账号吗？')), findsOneWidget);
  expect(
    find.descendant(of: find.byKey(const ValueKey('account-confirm-cancel')), matching: find.text('取消')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: find.byKey(const ValueKey('account-confirm-ok')), matching: find.text('退出登录')),
    findsOneWidget,
  );
}

bool _enabled(WidgetTester tester, Key key) => tester.widget<ButtonStyleButton>(find.byKey(key)).enabled;

void main() {
  group('U.10a platform accounts', () {
    testWidgets('lists every platform in two groups with what its stored cookie is worth', (tester) async {
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
      expect(find.text('平台账号'), findsOneWidget);
      expect(find.text('三方认证'), findsNothing);
      expect(find.textContaining('点平台可以查看、填写或核验'), findsOneWidget);
      // "退出全部账号" is gone (K3 A).
      expect(find.byType(PopupMenuButton<void>), findsNothing);

      // Groups and order (c3, c4).
      final order = [
        find.text('国内平台'),
        for (final id in ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'yy', 'cc'])
          find.byKey(ValueKey('account-$id')),
        find.text('海外平台'),
        for (final id in ['twitch', 'soop']) find.byKey(ValueKey('account-$id')),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_top(tester, order[i]), greaterThan(_top(tester, order[i - 1])), reason: '$i');
      }
      // Names (c5).
      expect(find.text('SOOP'), findsOneWidget);
      expect(find.text('网易CC'), findsOneWidget);

      // Statuses (c2).
      expect(_status(tester, SiteIds.bilibili), '已登录：Alice');
      expect(harness.store.settings.get(Settings.bilibiliUid), 42);
      expect(_status(tester, SiteIds.douyin), '登录已失效，请重新登录或更换 Cookie');
      expect(_status(tester, SiteIds.twitch), '已保存 · 聊天身份 viewer');
      expect(_status(tester, SiteIds.huya), '已保存 · 账号 ID 1234');
      expect(_status(tester, SiteIds.cc), '已保存，暂未用于请求（登录后加入弹幕待验证）');
      expect(_status(tester, SiteIds.soop), '已保存');
      expect(_status(tester, SiteIds.douyu), '未设置');
      expect(_status(tester, SiteIds.kuaishou), '未设置');
      // Colours: fine primary, failure red, warning yellow, not set quiet.
      final theme = Theme.of(tester.element(find.byKey(const ValueKey('account-list'))));
      Color? colorOf(String site) => tester.widget<Text>(find.byKey(ValueKey('account-$site-status'))).style?.color;
      expect(colorOf(SiteIds.huya), theme.colorScheme.primary);
      expect(colorOf(SiteIds.douyin), theme.colorScheme.error);
      expect(colorOf(SiteIds.cc), LiveSemanticColors.warning(Brightness.light));
      expect(colorOf(SiteIds.kuaishou), theme.colorScheme.onSurfaceVariant);
      // Wraps instead of cutting.
      expect(tester.widget<Text>(find.byKey(const ValueKey('account-cc-status'))).maxLines, isNull);

      // Stored: the sign-out button (v3's icon at the end); else a chevron.
      for (final id in ['bilibili', 'douyin', 'twitch', 'huya', 'cc', 'soop']) {
        final button = find.byKey(ValueKey('account-$id-sign-out'));
        expect(button, findsOneWidget, reason: id);
        expect(find.descendant(of: button, matching: find.byIcon(AppIcons.signOut)), findsOneWidget);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      }
      for (final id in ['douyu', 'kuaishou', 'yy']) {
        expect(find.byKey(ValueKey('account-$id-sign-out')), findsNothing, reason: id);
        expect(
          find.descendant(of: find.byKey(ValueKey('account-$id')), matching: find.byIcon(AppIcons.navigate)),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap opens the platform page; Bilibili without a login goes straight to the QR code', (tester) async {
      await _pump(tester, cookies: {SiteIds.soop: 'x=y'});
      // 3.x asked "退出登录" on a tap of a stored login (c1).
      await _tap(tester, find.byKey(const ValueKey('account-soop')));
      expect(find.text('SOOP账号'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget); // the page's button, no dialog
      await tester.pageBack();
      await _settle(tester);

      await _tap(tester, find.byKey(const ValueKey('account-bilibili')));
      // No "请选择登陆方式" (K2 A).
      expect(find.text('请选择登陆方式'), findsNothing);
      expect(find.byKey(const ValueKey('bilibili-qr-card')), findsOneWidget);
    });

    testWidgets('signs out from the list after asking with 3.x words', (tester) async {
      final harness = await _pump(tester, cookies: {SiteIds.soop: 'x=y'});
      await _tap(tester, find.byKey(const ValueKey('account-soop-sign-out')));
      _expectSignOutQuestion('SOOP');
      await _tap(tester, find.byKey(const ValueKey('account-confirm-cancel')));
      expect(harness.store.secrets.cookieFor(SiteIds.soop), 'x=y');

      await _tap(tester, find.byKey(const ValueKey('account-soop-sign-out')));
      expect(find.widgetWithText(DialogActionButton, '退出登录'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
      expect(harness.store.secrets.cookieFor(SiteIds.soop), isNull);
      expect(harness.toasts.last, '已退出SOOP');
      expect(_status(tester, SiteIds.soop), '未设置');
      expect(find.byKey(const ValueKey('account-soop-sign-out')), findsNothing);
    });

    testWidgets('an expired Bilibili login is signed out with a message (3.x)', (tester) async {
      final harness = await _pump(tester, cookies: {SiteIds.bilibili: 'SESSDATA=bad'});
      expect(harness.store.secrets.cookieFor(SiteIds.bilibili), isNull);
      expect(harness.toasts, contains('哔哩哔哩登录已失效，请重新登录'));
      expect(_status(tester, SiteIds.bilibili), '未设置');
    });

    testWidgets('cookies this device cannot read: a notice on top, the rows say so and can be removed', (tester) async {
      await _pump(tester, unreadable: {SiteIds.douyu, SiteIds.huya});
      expect(find.text('斗鱼、虎牙的 Cookie 无法在本机读取（换了设备或重装后会这样），请重新填写。'), findsOneWidget);
      expect(_status(tester, SiteIds.douyu), '无法在本机读取已保存的 Cookie，请重新填写');
      expect(find.byKey(const ValueKey('account-douyu-sign-out')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-huya-sign-out')), findsOneWidget);
    });

    testWidgets('wide: one column at most 720 wide, centred', (tester) async {
      await _pump(tester, size: const Size(1280, 800));
      final row = tester.getRect(find.byKey(const ValueKey('account-bilibili')));
      expect(row.width, lessThanOrEqualTo(720));
      expect(row.center.dx, closeTo(640, 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('U.10b cookie pages', () {
    testWidgets('the cookie page: status, instructions, the box, paste, clear, save, sign out, in this order', (
      tester,
    ) async {
      final harness = await _pump(tester);
      await _tap(tester, find.byKey(const ValueKey('account-huya')));
      expect(find.text('虎牙账号'), findsOneWidget);
      expect(_cardStatus(tester), '未设置：粘贴登录后的 Cookie');
      expect(find.text('登录虎牙网页并进入任意直播间，在浏览器开发者工具的网络请求中复制完整 Cookie。'), findsOneWidget);
      expect(find.text('打开虎牙网页'), findsOneWidget);
      // Nothing stored: no sign-out yet; nothing changed: save is grey.
      expect(find.byKey(const ValueKey('account-cookie-sign-out')), findsNothing);
      expect(_enabled(tester, const ValueKey('account-cookie-save')), isFalse);

      await _enter(tester, 'just some text');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(find.text('这不像 Cookie：应为 name=value; name2=value2 的形式'), findsOneWidget);
      expect(harness.store.secrets.cookieFor(SiteIds.huya), isNull);

      // A copied header line loses its name (c5).
      await _enter(tester, 'Cookie: udb_uid=1; yyuid=99\n');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.huya), 'udb_uid=1; yyuid=99');
      expect(harness.toasts.last, 'Cookie 已保存在本机');
      expect(_cardStatus(tester), '已保存 · 账号 ID 99');
      // L1 A: the stored cookie stays readable in the box.
      expect(find.text('udb_uid=1; yyuid=99'), findsOneWidget);

      final order = [
        find.byKey(const ValueKey('account-status')),
        find.text('打开虎牙网页'),
        find.byKey(const ValueKey('account-cookie-input')),
        find.byKey(const ValueKey('account-cookie-paste')),
        find.byKey(const ValueKey('account-cookie-save')),
        find.byKey(const ValueKey('account-cookie-sign-out')),
        find.textContaining('Cookie 只加密保存在本机'),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_top(tester, order[i]), greaterThan(_top(tester, order[i - 1])), reason: '$i');
      }
      final paste = tester.getRect(find.byKey(const ValueKey('account-cookie-paste')));
      final clear = tester.getRect(find.byKey(const ValueKey('account-cookie-clear-input')));
      expect(paste.top, clear.top);
      expect(paste.left, lessThan(clear.left));
      expect(tester.getSize(find.byKey(const ValueKey('account-cookie-save'))).height, greaterThanOrEqualTo(48));

      // Leaving with changes asks first (3.x words, "继续编辑 / 舍弃").
      await _enter(tester, 'udb_uid=2');
      await tester.pageBack();
      await _settle(tester);
      expect(find.text('舍弃 Cookie 修改？'), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
      expect(find.byKey(const ValueKey('account-huya')), findsOneWidget);
      expect(harness.store.secrets.cookieFor(SiteIds.huya), 'udb_uid=1; yyuid=99');
    });

    testWidgets('signing out on the page asks the same 3.x question as the list; clearing and saving is signing out', (
      tester,
    ) async {
      final harness = await _pump(tester, path: RoutePath.kHuyaCookie, cookies: {SiteIds.huya: 'yyuid=7'});
      await _tap(tester, find.byKey(const ValueKey('account-cookie-sign-out')));
      // UI_PLAN 3.7: one action, one dialog, one set of words (U.10a c8).
      _expectSignOutQuestion('虎牙');
      expect(find.text('退出虎牙？'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('account-confirm-cancel')));
      expect(harness.store.secrets.cookieFor(SiteIds.huya), 'yyuid=7');

      await _tap(tester, find.byKey(const ValueKey('account-cookie-clear-input')));
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      _expectSignOutQuestion('虎牙');
      await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
      expect(harness.store.secrets.cookieFor(SiteIds.huya), isNull);
      expect(harness.toasts.last, '已退出虎牙');
      expect(_cardStatus(tester), '未设置：粘贴登录后的 Cookie');
    });

    testWidgets('the paste button reads the clipboard; Ctrl+S saves', (tester) async {
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

      await tester.tap(find.byKey(const ValueKey('account-cookie-input')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(harness.store.secrets.cookieFor(SiteIds.yy), 'yyuid=5');
    });

    testWidgets('Bilibili and Douyin cookies are checked before they are stored; re-check on the card', (tester) async {
      final harness = await _pump(tester);
      harness.router.go(RoutePath.kSettingsAccount, extra: SiteIds.bilibili);
      await _settle(tester);
      expect(find.text('哔哩哔哩账号'), findsOneWidget);

      await _enter(tester, 'SESSDATA=bad');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.bilibili), isNull);
      expect(harness.toasts.last, '这段 Cookie 没有登录或已失效，未保存');

      await _enter(tester, 'SESSDATA=ok');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=ok');
      expect(harness.store.settings.get(Settings.bilibiliUid), 42);
      expect(harness.toasts.last, '已保存，已登录：Alice');
      expect(_cardStatus(tester), '已登录：Alice');
      expect(find.byKey(const ValueKey('account-recheck')), findsOneWidget);
      expect(find.text('重新核验'), findsOneWidget);

      // Cannot be checked right now: stored and marked unchecked.
      harness.router.go(RoutePath.kDouyinCookie);
      await _settle(tester);
      await _enter(tester, 'sessionid=offline');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.douyin), 'sessionid=offline');
      expect(_cardStatus(tester), '已保存，暂时无法核验账号（网络或平台异常）');
    });

    testWidgets('CC opens its cookie page through the accounts route', (tester) async {
      final harness = await _pump(tester);
      await _tap(tester, find.byKey(const ValueKey('account-cc')));
      expect(find.text('网易CC账号'), findsOneWidget);
      await _enter(tester, 'NTES_SESS=abc');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.cc), 'NTES_SESS=abc');
      expect(_cardStatus(tester), '已保存，暂未用于请求（登录后加入弹幕待验证）');
    });

    testWidgets('Douyu: the session on the card, the renewal group, a passport cookie, renew now, forced renewal', (
      tester,
    ) async {
      final savedAt = _now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
      final harness = await _pump(
        tester,
        path: RoutePath.kDouyuAccountCookie,
        cookies: {SiteIds.douyu: 'dy_auth=login; dy_did=d1'},
        douyuSavedAt: savedAt,
      );
      expect(find.text('斗鱼账号'), findsOneWidget);
      expect(_cardStatus(tester), contains('未配置 LTP0'));
      expect(find.text('打开 passport.douyu.com'), findsOneWidget);
      // The pair is in its own group after the cookie, then the switch,
      // then sign out (c9, c10).
      final order = [
        find.byKey(const ValueKey('account-cookie-save')),
        find.text('续期'),
        find.text('LTP0（用于自动续期）'),
        find.byKey(const ValueKey('douyu-ltp0-input')),
        find.byKey(const ValueKey('douyu-did-input')),
        find.byKey(const ValueKey('douyu-renew-now')),
        find.byKey(const ValueKey('douyu-force-renew')),
        find.byKey(const ValueKey('account-cookie-sign-out')),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_top(tester, order[i]), greaterThan(_top(tester, order[i - 1])), reason: '$i');
      }

      // The passport request's cookie: fields filled, the login kept, the
      // box shows what is stored.
      await _enter(tester, 'LTP0=long; dy_did=d1; acf_ssid=s');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('douyu-ltp0-input'))).controller!.text, 'long');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('douyu-did-input'))).controller!.text, 'd1');
      await _tap(tester, find.byKey(const ValueKey('account-cookie-save')));
      expect(harness.store.secrets.cookieFor(SiteIds.douyu), 'dy_auth=login; dy_did=d1');
      expect(find.text('dy_auth=login; dy_did=d1'), findsOneWidget);
      expect(harness.store.secrets.read(SecretRefs.douyuLtp0), 'long');
      expect(harness.store.secrets.read(SecretRefs.douyuDid), 'd1');
      expect(harness.store.settings.get(Settings.douyuCookieSavedAt), savedAt);
      expect(harness.toasts.last, '已从粘贴内容填入 LTP0 / dy_did，并保留了原来的登录 Cookie');
      expect(_cardStatus(tester), contains('到期前会自动续期'));

      await _tap(tester, find.byKey(const ValueKey('douyu-renew-now')));
      expect(harness.renewals, ['long/d1']);
      expect(harness.store.secrets.cookieFor(SiteIds.douyu), 'dy_auth=renewed; LTP0=long');
      expect(harness.store.settings.get(Settings.douyuCookieSavedAt), _now.millisecondsSinceEpoch ~/ 1000);
      expect(harness.toasts.last, startsWith('续期成功'));

      expect(harness.store.settings.get(Settings.douyuForceRenew), isFalse);
      await _tap(tester, find.text('登录后强制续期'));
      expect(harness.store.settings.get(Settings.douyuForceRenew), isTrue);

      await _tap(tester, find.byKey(const ValueKey('account-cookie-sign-out')));
      _expectSignOutQuestion('斗鱼');
      await _tap(tester, find.byKey(const ValueKey('account-confirm-ok')));
      expect(harness.store.secrets.cookieFor(SiteIds.douyu), isNull);
      expect(harness.store.secrets.read(SecretRefs.douyuLtp0), isNull);
      expect(harness.store.settings.get(Settings.douyuCookieSavedAt), 0);
    });

    testWidgets('Bilibili QR: the state lies over the code; refresh, confirm, verify, store', (tester) async {
      final qr = _FakeQr();
      final harness = await _pump(tester, qr: qr);
      await _tap(tester, find.byKey(const ValueKey('account-bilibili')));
      expect(find.text('哔哩哔哩账号登录'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-code')), findsOneWidget);
      // One sentence, under the code (c11; 3.x said it twice).
      expect(find.text('请使用哔哩哔哩手机客户端扫码登录'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('qr-code'))).width, 200);
      final codeTop = _top(tester, find.byKey(const ValueKey('qr-code')));

      qr.answers
        ..add((state: BilibiliQrState.scanned, cookie: null))
        ..add((state: BilibiliQrState.expired, cookie: null));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const ValueKey('qr-scanned')), findsOneWidget);
      expect(find.text('已扫描，请在手机上确认登录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('qr-expired')), findsOneWidget);
      expect(find.text('二维码已失效'), findsOneWidget);
      expect(find.text('二维码已失效，刷新后重新扫'), findsOneWidget);
      // The code stays where it was.
      expect(_top(tester, find.byKey(const ValueKey('qr-code'))), codeTop);

      await _tap(tester, find.byKey(const ValueKey('bilibili-qr-refresh')));
      expect(qr.codes, 2);
      qr.answers.add((state: BilibiliQrState.confirmed, cookie: 'SESSDATA=ok; DedeUserID=42'));
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(harness.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=ok; DedeUserID=42');
      expect(harness.store.settings.get(Settings.bilibiliUid), 42);
      expect(harness.toasts, contains('已保存，已登录：Alice'));
      expect(_status(tester, SiteIds.bilibili), '已登录：Alice');
    });

    testWidgets('Bilibili QR: a confirmed login the platform rejects is not stored (c13)', (tester) async {
      final qr = _FakeQr();
      final harness = await _pump(tester, path: RoutePath.kBiliBiliQRLogin, qr: qr);
      qr.answers.add((state: BilibiliQrState.confirmed, cookie: 'SESSDATA=bad'));
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(harness.store.secrets.cookieFor(SiteIds.bilibili), isNull);
      expect(find.byKey(const ValueKey('qr-failed')), findsOneWidget);
      expect(find.text('账号核验尚未完成，请继续登录或重试'), findsOneWidget);
      expect(find.byKey(const ValueKey('bilibili-qr-retry')), findsOneWidget);
    });

    testWidgets('Bilibili QR: "扫不了？" offers the cookie everywhere and the web login on phones', (tester) async {
      final qr = _FakeQr()..failCode = true;
      await _pump(tester, path: RoutePath.kBiliBiliQRLogin, qr: qr);
      expect(find.byKey(const ValueKey('qr-failed')), findsOneWidget);
      expect(find.text('二维码加载失败'), findsWidgets);
      expect(find.text('扫不了？'), findsOneWidget);
      // No in-app browser here: no web login (3.x showed it on phones only).
      expect(find.byKey(const ValueKey('bilibili-qr-web-login')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('bilibili-qr-paste-cookie')));
      expect(find.text('哔哩哔哩账号'), findsOneWidget);
      // Back goes to the code.
      await tester.pageBack();
      await _settle(tester);
      expect(find.byKey(const ValueKey('bilibili-qr-card')), findsOneWidget);
    });

    testWidgets('Bilibili QR on a phone with the in-app browser shows the web login first', (tester) async {
      InAppWeb.available = true;
      addTearDown(() => InAppWeb.available = false);
      await _pump(tester, path: RoutePath.kBiliBiliQRLogin);
      final web = find.byKey(const ValueKey('bilibili-qr-web-login'));
      expect(web, findsOneWidget);
      expect(find.text('网页登录（短信、密码）'), findsOneWidget);
      expect(
        tester.getTopLeft(web).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('bilibili-qr-paste-cookie'))).dx),
      );
    });

    testWidgets('wide: the QR code is 220; the cookie page one column at most 720', (tester) async {
      await _pump(tester, path: RoutePath.kBiliBiliQRLogin, size: const Size(1280, 800));
      expect(tester.getSize(find.byKey(const ValueKey('qr-code'))).width, 220);

      await _pump(tester, path: RoutePath.kHuyaCookie, size: const Size(1280, 800));
      final status = tester.getRect(find.byKey(const ValueKey('account-status')));
      expect(status.width, lessThanOrEqualTo(720));
      expect(status.center.dx, closeTo(640, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('without an in-app browser the web login route explains and shows the cookie page', (tester) async {
      await _pump(tester, path: RoutePath.kBiliBiliWebLogin);
      expect(find.byKey(const ValueKey('account-notice')), findsOneWidget);
      expect(find.textContaining('没有可用的内置浏览器'), findsOneWidget);
      expect(find.text('哔哩哔哩账号'), findsOneWidget);
    });

    test('Douyu summary follows the session state', () async {
      await loadStrings();
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
      expect(summary('dy_auth=a', savedAt: _now), startsWith('登录有效'));
      expect(cleanPastedCookie(' Cookie: a=b; c=d \n'), 'a=b; c=d');
      expect(looksLikeCookie('a=b'), isTrue);
      expect(looksLikeCookie('hello'), isFalse);
    });
  });

  group('U.10c cloud account', () {
    testWidgets('the three old routes explain the retirement and lead to the syncs and the platform accounts', (
      tester,
    ) async {
      for (final path in _authPaths) {
        await _pump(tester, path: path);
        expect(find.text('云端账号'), findsOneWidget, reason: path);
        expect(find.text('云端账号已停用'), findsOneWidget, reason: path);
      }
      final order = [
        find.byKey(const ValueKey('auth-retired')),
        find.text('同步与备份'),
        find.byKey(const ValueKey('auth-webdav')),
        find.byKey(const ValueKey('auth-device-sync')),
        find.byKey(const ValueKey('auth-backup')),
        find.byKey(const ValueKey('auth-platform-accounts')),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(_top(tester, order[i]), greaterThan(_top(tester, order[i - 1])), reason: '$i');
      }
      for (final (key, icon) in [
        ('auth-webdav', AppIcons.webDav),
        ('auth-device-sync', AppIcons.deviceSync),
        ('auth-backup', AppIcons.backupFiles),
        ('auth-platform-accounts', AppIcons.platformAccounts),
      ]) {
        expect(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byIcon(icon)),
          findsOneWidget,
          reason: key,
        );
      }
      expect(find.text('哔哩哔哩、斗鱼、虎牙等平台的登录，和云端账号无关'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('auth-platform-accounts')));
      expect(find.text('平台账号'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('auth-webdav')));
      expect(find.text('webdav page'), findsOneWidget);
    });

    testWidgets('wide and landscape: one column at most 720', (tester) async {
      for (final size in const [Size(1280, 800), Size(852, 393)]) {
        await _pump(tester, path: RoutePath.kMine, size: size);
        final card = tester.getRect(find.byKey(const ValueKey('auth-retired')));
        expect(card.width, lessThanOrEqualTo(720));
        expect(card.center.dx, closeTo(size.width / 2, 1));
        expect(tester.takeException(), isNull);
      }
    });
  });

  test('every platform is named on the account pages as in the platform list (SOOP, 网易CC)', () async {
    // 3.x writes "SOOP" in five strings and the platform does too ("Soop"
    // only in site_soop); "网易CC" as 3.x's site_cc and the platform.
    for (final (language, cc) in const [(AppLanguage.zh, '网易CC'), (AppLanguage.en, 'NetEase CC')]) {
      await loadStrings(language);
      expect(i18n('site_soop'), 'SOOP', reason: '$language');
      expect(i18n('site_cc'), cc, reason: '$language');
      for (final platform in accountPlatforms) {
        expect(platform.name, i18n('site_${platform.id}'), reason: '$language ${platform.id}');
      }
    }
    await loadStrings();
  });
}
