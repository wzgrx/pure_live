import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/app_refresh_rate_mode.dart';
import 'package:pure_live/common/services/display_mode_service.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/exit_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/startup_controller.dart';
import 'package:pure_live/common/services/settings/window_size_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/general_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> translations;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-general-settings-layout-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    DisplayModeService.info.value = null;
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService(), permanent: true);
  });

  tearDown(() {
    Get.deleteAll(force: true);
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('refresh-rate choices remain readable and selectable in narrow very-large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
              child: child!,
            ),
            home: const GeneralSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Interface refresh rate'), findsOneWidget);
    await tester.tap(find.text('Interface refresh rate'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Power saving (default)'), findsOneWidget);
    expect(find.text('Low power'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Medium power'), findsOneWidget);
    expect(find.text('Highest (device maximum)'), findsOneWidget);
    expect(find.text('High power'), findsOneWidget);

    final dialogScroll = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Highest (device maximum)'), 120, scrollable: dialogScroll);
    await tester.ensureVisible(find.text('Highest (device maximum)'));
    await tester.pumpAndSettle();
    final performanceLabelTopLeft = tester.getTopLeft(find.text('Highest (device maximum)'));
    expect(performanceLabelTopLeft.dy, inInclusiveRange(0, 479));
    expect(tester.takeException(), isNull);

    await tester.tapAt(performanceLabelTopLeft + const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(SettingsService.to.app.refreshRateMode, AppRefreshRateMode.performance);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isWindows);
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _TestSettingsService extends SettingsService {
  final AppSettingsController _app = _TestAppSettingsController();
  final ExitSettingsController _exit = ExitSettingsController();
  final FontSettingsController _font = FontSettingsController();
  final StartupController _startup = StartupController();
  final WindowSizeController _window = WindowSizeController();

  @override
  AppSettingsController get app => _app;

  @override
  ExitSettingsController get exit => _exit;

  @override
  FontSettingsController get font => _font;

  @override
  StartupController get startup => _startup;

  @override
  WindowSizeController get window => _window;

  @override
  // Test fixture intentionally skips production service registrations.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {
    _exit.onClose();
    super.onClose();
  }
}

class _TestAppSettingsController extends AppSettingsController {
  final RxString _refreshRateModeName = AppRefreshRateMode.powerSaving.storageValue.obs;

  @override
  RxString get refreshRateModeName => _refreshRateModeName;
}
