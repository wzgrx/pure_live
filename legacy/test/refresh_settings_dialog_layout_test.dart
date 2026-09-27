import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/refresh_config_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/refresh_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-refresh-settings-layout-test-');
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
    Get.put<SettingsService>(_TestSettingsService());
    final controller = Get.put(RefreshConfigController());
    controller.autoRefreshFavorite.value = true;
    controller.autoRefreshThumbnails.value = true;
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('all refresh selectors remain reachable in narrow very-large text', (tester) async {
    await _pumpSettings(tester, english);

    await _selectLastOption(tester, tileTitle: 'Refresh Interval', expectedOptions: 12, lastLabel: '6 h');
    expect(Get.find<RefreshConfigController>().autoRefreshInterval.value, 360);

    await _selectLastOption(tester, tileTitle: 'Concurrent home refresh tasks', expectedOptions: 20, lastLabel: '20');
    expect(Get.find<RefreshConfigController>().maxConcurrentRefresh.value, 20);

    await _selectLastOption(tester, tileTitle: 'Thumbnail Refresh Interval', expectedOptions: 8, lastLabel: '6 h');
    expect(Get.find<RefreshConfigController>().thumbnailRefreshInterval.value, 360);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}

Future<void> _pumpSettings(WidgetTester tester, Map<String, dynamic> english) async {
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
          home: const RefreshSettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pageScrollable() => find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

Future<void> _selectLastOption(
  WidgetTester tester, {
  required String tileTitle,
  required int expectedOptions,
  required String lastLabel,
}) async {
  final title = find.text(tileTitle);
  await tester.scrollUntilVisible(title, 120, scrollable: _pageScrollable());
  await tester.pumpAndSettle();
  await tester.tap(title.hitTestable());
  await tester.pumpAndSettle();

  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  expect(find.descendant(of: dialog, matching: find.byType(RadioListTile<int>)), findsNWidgets(expectedOptions));
  final lastOption = find.descendant(of: dialog, matching: find.widgetWithText(RadioListTile<int>, lastLabel));
  final dialogScrollable = find.descendant(of: dialog, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(lastOption, 100, scrollable: dialogScrollable);
  await tester.pumpAndSettle();
  expect(tester.getRect(lastOption).bottom, lessThanOrEqualTo(480));
  expect(tester.takeException(), isNull);
  await tester.tap(lastOption);
  await tester.pumpAndSettle();
  expect(dialog, findsNothing);
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _TestSettingsService extends SettingsService {
  final FontSettingsController _font = FontSettingsController();

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
