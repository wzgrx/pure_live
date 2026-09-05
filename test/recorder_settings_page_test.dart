import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Map<String, dynamic> translations;
  late RecordSettingsController settings;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-recorder-settings-page-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_SettingsService());
    settings = Get.put<RecordSettingsController>(_RecorderSettings());
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final size in [const Size(360, 780), const Size(900, 500)]) {
    testWidgets('resume setting is visible independently of polling at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('zh')],
          path: 'assets/translations',
          fallbackLocale: const Locale('zh'),
          assetLoader: _Translations(translations),
          child: Builder(
            builder: (context) => GetMaterialApp(
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const RecordSettingsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resume = find.widgetWithText(SwitchListTile, translations['auto_start_boot'] as String);
      await tester.scrollUntilVisible(resume, 500, maxScrolls: 30);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<SwitchListTile>(resume).value, isFalse);
      final description = tester.widget<Text>(find.text(translations['auto_start_boot_desc'] as String));
      expect(description.maxLines, isNull, reason: 'resume conditions must not be truncated to one line');
      await tester.tap(find.descendant(of: resume, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(settings.autoStartOnBoot.value, isTrue);
      expect(settings.enablePolling.value, isFalse);
      settings.enablePolling.value = true;
      await tester.pumpAndSettle();
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(resume).value, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _Translations extends AssetLoader {
  _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

// UI state uses memory under FakeAsync; persistence is tested with real Hive IO
// in recorder_settings_persistence_test.dart. Storage platform APIs are not used.
class _RecorderSettings extends RecordSettingsController {
  final _resume = false.obs;
  final _polling = false.obs;
  @override
  RxBool get autoStartOnBoot => _resume;
  @override
  RxBool get enablePolling => _polling;
  @override
  Future<void> initRecordPath() async {}
  @override
  Future<void> refreshStorageInfo() async {}
}

class _SettingsService extends SettingsService {
  @override
  final font = FontSettingsController();
  @override
  // Test only the recorder page, not unrelated production service registration.
  // ignore: must_call_super
  void onInit() {}
}
