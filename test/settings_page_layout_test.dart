import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-settings-layout-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService());
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('wide settings app bar keeps the labelled config shortcut', (tester) async {
    await _openSettings(tester, size: const Size(900, 600));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Config Preview'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow large-text app bar preserves the title and a compact labelled action', (tester) async {
    await _openSettings(tester, size: const Size(320, 480), textScale: 2);

    final title = find.text('Settings');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).width, greaterThanOrEqualTo(80));
    expect(find.text('Config Preview'), findsNothing);
    expect(find.byTooltip('Config Preview'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Config Preview')).width, lessThanOrEqualTo(56));

    final settingsList = find.byType(ListView);
    final scrollable = find.descendant(of: settingsList, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Backup and Restore'), 240, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.text('Backup and Restore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSettings(WidgetTester tester, {required Size size, double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      assetLoader: const _TestAssetLoader(),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => const {
    'settings_title': 'Settings',
    'config_preview': 'Config Preview',
    'theme_settings': 'Theme Settings',
    'theme_customization': 'Theme Customization',
    'theme_customization_desc': 'Customize skins, dark mode, and primary colors',
    'iptv_settings': 'IPTV Settings',
    'manage_iptv_sources': 'Manage IPTV sources',
    'refresh_settings': 'Refresh Settings',
    'refresh_settings_subtitle': 'Refresh favorites and live data',
    'video_settings': 'Video Settings',
    'video': 'Video',
    'video_desc': 'Playback, volume, and danmaku',
    'pip_danmaku': 'PiP Danmaku',
    'pip_danmaku_desc': 'Configure compact danmaku rendering',
    'player_kernel_settings': 'Player Kernel',
    'player_kernel': 'Player Kernel',
    'player_kernel_desc': 'Select the playback engine',
    'network_proxy_settings': 'Network Proxy',
    'custom_network_proxy': 'Custom Network Proxy',
    'custom_network_proxy_desc': 'Configure platform and image requests',
    'local_interaction_settings': 'Local Interaction',
    'local_interaction_title': 'Local Interaction',
    'local_interaction_settings_desc': 'Configure local danmaku input',
    'general_settings': 'General Settings',
    'general': 'General',
    'general_desc': 'Startup and display behavior',
    'navigation_display_settings': 'Navigation Display',
    'navigation_display_settings_desc': 'Choose visible navigation items',
    'platform_settings': 'Platform Settings',
    'platform_settings_desc': 'Configure platform accounts and filters',
    'data_manage': 'Data Management',
    'cache_and_data': 'Cache and Data',
    'cache_and_data_desc': 'Manage cached files and logs',
    'backup_manage': 'Backup',
    'backup_recover': 'Backup and Restore',
    'backup_recover_desc': 'Export or restore settings',
  };
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService() : _font = FontSettingsController();

  final FontSettingsController _font;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production service registrations.
  // ignore: must_call_super
  void onInit() {}
}
