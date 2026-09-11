import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/common/services/settings/volume_settings_controller.dart';
import 'package:pure_live/common/services/settings/window_size_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/video_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-video-settings-test-');
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
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('resolution preferences localize stable values and keep whole options tappable', (tester) async {
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
            home: const VideoSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Desktop Default Volume'), 120, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    final volumeTitle = tester.getRect(find.text('Desktop Default Volume'));
    final volumeValue = tester.getRect(find.text('100%'));
    expect(volumeValue.top, greaterThanOrEqualTo(volumeTitle.bottom));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Resolution Preference'), 180, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsNWidgets(2));
    expect(find.text('原画'), findsNothing);

    await tester.tap(find.text('Resolution Preference'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    for (final label in ['Original', 'Blu-ray 8 Mbps', 'Blu-ray 4 Mbps', 'Super HD', 'Smooth']) {
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(label)), findsOneWidget);
    }
    expect(find.text('原画'), findsNothing);
    expect(tester.takeException(), isNull);

    final smoothOption = find.widgetWithText(SimpleDialogOption, 'Smooth');
    await tester.ensureVisible(smoothOption);
    await tester.pumpAndSettle();
    await tester.tap(smoothOption);
    await tester.pumpAndSettle();
    expect(SettingsService.to.player.preferResolution.value, '流畅');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Smooth'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mobile Network Quality'), 120, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile Network Quality'));
    await tester.pumpAndSettle();
    final cellularOption = find.widgetWithText(SimpleDialogOption, 'Blu-ray 4 Mbps');
    await tester.ensureVisible(cellularOption);
    await tester.pumpAndSettle();
    await tester.tap(cellularOption);
    await tester.pumpAndSettle();
    expect(SettingsService.to.player.preferResolutionCellular.value, '蓝光4M');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Blu-ray 4 Mbps'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isWindows);
}

Finder _pageScrollable() {
  return find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestSettingsService extends SettingsService {
  final AppSettingsController _app = AppSettingsController();
  final DanmakuSettingsController _danmaku = DanmakuSettingsController();
  final FontSettingsController _font = FontSettingsController();
  final PlayerSettingsController _player = PlayerSettingsController();
  final VolumeSettingsController _volume = VolumeSettingsController();
  final WindowSizeController _window = WindowSizeController();

  @override
  AppSettingsController get app => _app;

  @override
  DanmakuSettingsController get danmaku => _danmaku;

  @override
  FontSettingsController get font => _font;

  @override
  PlayerSettingsController get player => _player;

  @override
  VolumeSettingsController get vol => _volume;

  @override
  WindowSizeController get window => _window;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
