import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/account/account_controller.dart';
import 'package:pure_live/modules/account/account_page.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;
  late CookieSettingsController cookies;
  late _TestBilibiliAccountService bilibili;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-account-navigation-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    cookies = CookieSettingsController();
    Get.put<SettingsService>(_TestSettingsService(cookies));
    bilibili = _TestBilibiliAccountService();
    Get.put<BiliBiliAccountService>(bilibili);
    Get.put<AccountController>(_TestAccountController());
  });

  tearDown(() async {
    await HivePrefUtil.flush();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  test('canonical and legacy Douyin cookie paths are both registered exactly once', () {
    final names = AppPages.routes.map((route) => route.name).toList(growable: false);
    expect(names.where((name) => name == RoutePath.kDouyinCookie), hasLength(1));
    expect(names.where((name) => name == RoutePath.kDouyuCookie), hasLength(1));
  });

  testWidgets('Douyin account row opens the canonical cookie route', (tester) async {
    await _pumpAccountPage(tester, english);
    final douyin = find.text('Douyin');
    await _scrollPageUntilHitTestable(tester, douyin);
    await tester.tap(douyin.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canonical-douyin-cookie')), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-douyu-cookie')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configured Bilibili account exposes a visible verification state before identity returns', (
    tester,
  ) async {
    bilibili.logined.value = true;
    bilibili.name.value = '';
    await _pumpAccountPage(tester, english);
    expect(find.text('Verifying account…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logged-in platform confirmation remains reachable in narrow very-large text', (tester) async {
    cookies.huyaCookie.value = 'fixture-cookie';
    await _pumpAccountPage(tester, english);
    final huya = find.text('Huya');
    await _scrollPageUntilHitTestable(tester, huya);
    await tester.tap(huya.hitTestable());
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Cancel')).hitTestable(), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Confirm')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled Douyu account row has no navigation affordance', (tester) async {
    await _pumpAccountPage(tester, english);
    final douyu = find.text('Douyu');
    await _scrollPageUntilHitTestable(tester, douyu);
    final tile = find.ancestor(of: douyu, matching: find.byType(ListTile));

    expect(tester.widget<ListTile>(tile).enabled, isFalse);
    expect(find.descendant(of: tile, matching: find.text('Disabled')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.byIcon(Icons.chevron_right_rounded)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAccountPage(WidgetTester tester, Map<String, dynamic> english) async {
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _Translations(english),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          initialRoute: '/',
          getPages: [
            GetPage(name: '/', page: () => const AccountPage()),
            GetPage(
              name: RoutePath.kDouyinCookie,
              page: () => const Scaffold(key: ValueKey('canonical-douyin-cookie')),
            ),
            GetPage(
              name: RoutePath.kDouyuCookie,
              page: () => const Scaffold(key: ValueKey('legacy-douyu-cookie')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollPageUntilHitTestable(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
  );
  for (var attempt = 0; attempt < 100; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final next = (position.pixels + position.viewportDimension * 0.4).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) break;
    position.jumpTo(next);
    await tester.pump();
  }
  fail('Account row did not become hit-testable after bounded page scrolling.');
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._cookies) : _font = FontSettingsController();

  final CookieSettingsController _cookies;
  final FontSettingsController _font;

  @override
  CookieSettingsController get cookieManager => _cookies;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}

class _TestBilibiliAccountService extends BiliBiliAccountService {
  @override
  // Avoid timers and account network activity in a route/layout fixture.
  // ignore: must_call_super
  void onInit() {}
}

class _TestAccountController extends AccountController {
  @override
  // Avoid delayed Douyin account network activity in a route/layout fixture.
  // ignore: must_call_super
  void onInit() {}
}
