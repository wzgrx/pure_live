import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-theme-boundary-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
  });

  tearDown(() async {
    Get.reset();
    await HivePrefUtil.flush();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('theme values share canonical supported contracts', () {
    expect(ThemeSettingsController.normalizeThemeMode(' dark '), 'Dark');
    expect(ThemeSettingsController.normalizeThemeMode('retired'), ThemeSettingsController.defaultThemeModeName);
    expect(ThemeSettingsController.normalizeLanguage(' english '), 'English');
    expect(ThemeSettingsController.normalizeLanguage('fr'), ThemeSettingsController.defaultLanguageName);
    expect(ThemeSettingsController.normalizeThemeColor('#a1b2c3'), 'A1B2C3');
    expect(ThemeSettingsController.normalizeThemeColor('0x80a1b2c3'), '80A1B2C3');
    expect(ThemeSettingsController.normalizeThemeColor('not-a-color'), ThemeSettingsController.defaultThemeColorHex);
    expect(ThemeSettingsController.normalizeLoadingStyle(' wave '), 'wave');
    expect(ThemeSettingsController.normalizeLoadingStyle('retired'), AppConsts.defaultLoadingStyleKey);
    expect(ThemeSettingsController.normalizeLoadingStyleColor(''), isEmpty);
    expect(ThemeSettingsController.normalizeLoadingStyleColor('#80445566'), '80445566');
    expect(ThemeSettingsController.normalizeLoadingStyleColor('bad'), isEmpty);
    expect(ThemeSettingsController.normalizeSpacing(-1), ThemeSettingsController.minSpacing);
    expect(ThemeSettingsController.normalizeSpacing(80), ThemeSettingsController.maxSpacing);
    expect(ThemeSettingsController.normalizeSpacing(double.nan), ThemeSettingsController.defaultSpacing);
  });

  test('persisted theme values are repaired before first-frame consumers', () async {
    await HivePrefUtil.setString('themeMode', 'retired');
    await HivePrefUtil.setString('themeColorSwitch', 'not-a-color');
    await HivePrefUtil.setString('language', 'fr');
    await HivePrefUtil.setDouble('crossAxisSpacing', -8);
    await HivePrefUtil.setDouble('mainAxisSpacing', 80);
    await HivePrefUtil.setString('loadingStyle', 'removed-style');
    await HivePrefUtil.setString('loadingStyleColorSwitch', 'invalid');

    final theme = Get.put(ThemeSettingsController());

    expect(theme.themeMode, ThemeMode.system);
    expect(
      theme.themeColor.toARGB32(),
      Color(int.parse('FF${ThemeSettingsController.defaultThemeColorHex}', radix: 16)).toARGB32(),
    );
    expect(theme.language, const Locale('zh'));
    expect(theme.resolvedLoadingStyle, AppConsts.defaultLoadingStyleKey);
    expect(theme.loadingStyleColor, isNull);
    expect(theme.resolvedCrossAxisSpacing, ThemeSettingsController.minSpacing);
    expect(theme.resolvedMainAxisSpacing, ThemeSettingsController.maxSpacing);

    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.flush();
    expect(HivePrefUtil.getString('themeMode'), ThemeSettingsController.defaultThemeModeName);
    expect(HivePrefUtil.getString('themeColorSwitch'), ThemeSettingsController.defaultThemeColorHex);
    expect(HivePrefUtil.getString('language'), ThemeSettingsController.defaultLanguageName);
    expect(HivePrefUtil.getDouble('crossAxisSpacing'), ThemeSettingsController.minSpacing);
    expect(HivePrefUtil.getDouble('mainAxisSpacing'), ThemeSettingsController.maxSpacing);
    expect(HivePrefUtil.getString('loadingStyle'), AppConsts.defaultLoadingStyleKey);
    expect(HivePrefUtil.getString('loadingStyleColorSwitch'), isEmpty);
  });

  test('runtime direct writes are repaired and export stays canonical', () async {
    Get.put<FontSettingsController>(_NoopFontSettingsController());
    final theme = Get.put(ThemeSettingsController());

    theme.themeModeName.value = 'invalid';
    theme.themeColorSwitch.value = 'invalid';
    theme.languageName.value = 'invalid';
    theme.crossAxisSpacing.value = double.infinity;
    theme.mainAxisSpacing.value = -10;
    theme.loadingStyle.value = 'invalid';
    theme.loadingStyleColorSwitch.value = 'invalid';
    await Future<void>.delayed(Duration.zero);

    expect(theme.themeModeName.value, ThemeSettingsController.defaultThemeModeName);
    expect(theme.themeColorSwitch.value, ThemeSettingsController.defaultThemeColorHex);
    expect(theme.languageName.value, ThemeSettingsController.defaultLanguageName);
    expect(theme.crossAxisSpacing.value, ThemeSettingsController.defaultSpacing);
    expect(theme.mainAxisSpacing.value, ThemeSettingsController.minSpacing);
    expect(theme.loadingStyle.value, AppConsts.defaultLoadingStyleKey);
    expect(theme.loadingStyleColorSwitch.value, isEmpty);
    expect(theme.toJson(), {
      'themeMode': ThemeSettingsController.defaultThemeModeName,
      'enableDynamicTheme': false,
      'themeColorSwitch': ThemeSettingsController.defaultThemeColorHex,
      'language': ThemeSettingsController.defaultLanguageName,
      'crossAxisSpacing': ThemeSettingsController.defaultSpacing,
      'mainAxisSpacing': ThemeSettingsController.minSpacing,
      'loadingStyle': AppConsts.defaultLoadingStyleKey,
      'loadingStyleColorSwitch': '',
    });
  });

  test('current and legacy backup parsing canonicalize values with strict scalar types', () {
    final parsed = ThemeSettingsController.parseConfig({
      'themeMode': ' dark ',
      'themeColorSwitch': '#a1b2c3',
      'language': ' english ',
      'crossAxisSpacing': -3,
      'mainAxisSpacing': 90,
      'loadingStyle': ' wave ',
      'loadingStyleColorSwitch': '0x80445566',
    });
    expect(parsed['themeModeName'], 'Dark');
    expect(parsed['themeColorSwitch'], 'A1B2C3');
    expect(parsed['languageName'], 'English');
    expect(parsed['crossAxisSpacing'], ThemeSettingsController.minSpacing);
    expect(parsed['mainAxisSpacing'], ThemeSettingsController.maxSpacing);
    expect(parsed['loadingStyle'], 'wave');
    expect(parsed['loadingStyleColorSwitch'], '80445566');
    expect(ThemeSettingsController.parseConfig({'languageName': 'English'})['languageName'], 'English');

    final extracted = ThemeSettingsController.extractConfig({
      'theme': {
        'themeMode': 'unknown',
        'themeColorSwitch': 'invalid',
        'languageName': 'English',
        'loadingStyle': 'removed',
      },
    });
    expect(extracted['themeMode'], ThemeSettingsController.defaultThemeModeName);
    expect(extracted['themeColorSwitch'], ThemeSettingsController.defaultThemeColorHex);
    expect(extracted['language'], 'English');
    expect(extracted['loadingStyle'], AppConsts.defaultLoadingStyleKey);

    expect(() => ThemeSettingsController.parseConfig({'themeMode': 1}), throwsA(isA<TypeError>()));
    expect(() => ThemeSettingsController.parseConfig({'crossAxisSpacing': '8'}), throwsA(isA<TypeError>()));
    expect(
      () => ThemeSettingsController.parseConfig({'mainAxisSpacing': double.infinity}),
      throwsA(isA<FormatException>()),
    );
    expect(() => ThemeSettingsController.parseConfig({'loadingStyleColorSwitch': 1}), throwsA(isA<TypeError>()));
    expect(() => BackupController.validateBackupIdentity({'languageName': 'English'}), returnsNormally);
  });
}

class _NoopFontSettingsController extends FontSettingsController {
  @override
  // Test fixture avoids font I/O and theme rebuilds.
  // ignore: must_call_super
  void onInit() {}

  @override
  void refreshSystemTheme() {}
}
