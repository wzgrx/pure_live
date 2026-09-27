import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/loading_style_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;
  late _TestSettingsService settings;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-loading-style-test-');
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
    settings = _TestSettingsService();
    Get.put<SettingsService>(settings);
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('narrow very-large text preserves color controls, final style selection and reset', (tester) async {
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
            home: const LoadingStyleSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Change Loading Color'), findsNWidgets(2));
    expect(find.text('Customize the color of the loading animation'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final grid = find.byType(CustomScrollView);
    final position = tester
        .state<ScrollableState>(find.descendant(of: grid, matching: find.byType(Scrollable)).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 50));

    final lastStyle = AppConsts.allStyles.last;
    final lastLabel = find.text(lastStyle['nameEn']!);
    expect(lastLabel, findsOneWidget);
    await tester.tap(find.ancestor(of: lastLabel, matching: find.byType(InkWell)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.theme.loadingStyle.value, lastStyle['key']);

    await tester.tap(find.byTooltip('Restore Default'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.theme.loadingStyle.value, AppConsts.defaultLoadingStyleKey);
    expect(settings.theme.loadingStyleColorSwitch.value, isEmpty);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService() : _theme = ThemeSettingsController(), _font = FontSettingsController();

  final ThemeSettingsController _theme;
  final FontSettingsController _font;

  @override
  ThemeSettingsController get theme => _theme;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
