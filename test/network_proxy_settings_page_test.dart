import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/proxy_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/network_proxy_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;
  late _TestProxySettingsController proxy;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-proxy-page-test-');
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
    proxy = _TestProxySettingsController();
    proxy.enableAppProxy.value = true;
    proxy.enableProxy.value = true;
    proxy.appProxyHost.value = '127.0.0.1';
    proxy.appProxyPort.value = 7897;
    proxy.proxyHost.value = '192.168.1.2';
    proxy.proxyPort.value = 1080;
    Get.put<SettingsService>(_TestSettingsService(proxy));
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('narrow very-large text keeps both proxy endpoints reachable', (tester) async {
    await _pumpPage(tester, english);

    expect(find.text('Application Layer Proxy (Fixes startup & list refreshing)'), findsOneWidget);
    final appHost = find.byKey(const ValueKey('app-proxy-host'));
    final appPort = find.byKey(const ValueKey('app-proxy-port'));
    await _scrollUntilBuilt(tester, appPort);
    expect(find.text('Proxy Address'), findsWidgets);
    _expectStackedEndpointFields(tester, appHost, appPort);
    expect(tester.takeException(), isNull);

    final playerHost = find.byKey(const ValueKey('player-proxy-host'));
    final playerPort = find.byKey(const ValueKey('player-proxy-port'));
    await _scrollUntilBuilt(tester, playerPort);
    expect(playerHost, findsOneWidget);
    expect(playerPort, findsOneWidget);
    _expectStackedEndpointFields(tester, playerHost, playerPort);
    expect(tester.takeException(), isNull);
  });

  testWidgets('half-edited or out-of-range port does not replace the last valid value', (tester) async {
    await _pumpPage(tester, english);
    final appPort = find.byKey(const ValueKey('app-proxy-port'));
    await _scrollUntilBuilt(tester, appPort);

    await tester.enterText(appPort, '');
    await tester.pump();
    expect(proxy.appProxyPort.value, 7897);
    expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);

    await tester.enterText(appPort, '65536');
    await tester.pump();
    expect(proxy.appProxyPort.value, 7897);
    expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);

    await tester.enterText(appPort, '7890');
    await tester.pump();
    expect(proxy.appProxyPort.value, 7890);
    expect(find.text('Enter a port from 1 to 65535'), findsNothing);

    final playerPort = find.byKey(const ValueKey('player-proxy-port'));
    await _scrollUntilBuilt(tester, playerPort);
    await tester.enterText(playerPort, '0');
    await tester.pump();
    expect(proxy.proxyPort.value, 1080);
    expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);

    await tester.enterText(playerPort, '8443');
    await tester.pump();
    expect(proxy.proxyPort.value, 8443);
    expect(find.text('Enter a port from 1 to 65535'), findsNothing);
  });

  testWidgets('wide desktop keeps the compact host and port row', (tester) async {
    await _pumpPage(tester, english, size: const Size(900, 900), textScale: 1);
    final appHost = find.byKey(const ValueKey('app-proxy-host'));
    final appPort = find.byKey(const ValueKey('app-proxy-port'));
    await _scrollUntilBuilt(tester, appPort);

    final hostRect = tester.getRect(appHost);
    final portRect = tester.getRect(appPort);
    expect(hostRect.top, portRect.top);
    expect(hostRect.width, greaterThan(portRect.width));
    expect(tester.takeException(), isNull);
  });
}

void _expectStackedEndpointFields(WidgetTester tester, Finder host, Finder port) {
  final hostRect = tester.getRect(host);
  final portRect = tester.getRect(port);
  expect(portRect.top, greaterThan(hostRect.bottom));
  expect(hostRect.width, greaterThan(220));
  expect(portRect.width, greaterThan(220));
}

Future<void> _scrollUntilBuilt(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pump();
  }
  fail('Proxy endpoint did not build after bounded scrolling.');
}

Future<void> _pumpPage(
  WidgetTester tester,
  Map<String, dynamic> english, {
  Size size = const Size(320, 480),
  double textScale = 3,
}) async {
  tester.view.physicalSize = size;
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
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const NetworkProxySettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestProxySettingsController extends ProxySettingsController {
  @override
  // This in-memory fixture intentionally skips Dio connection observers.
  // ignore: must_call_super
  void onInit() {}
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._proxy) : _font = FontSettingsController();

  final ProxySettingsController _proxy;
  final FontSettingsController _font;

  @override
  ProxySettingsController get proxy => _proxy;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
