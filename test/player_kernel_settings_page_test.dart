import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/player_kernel_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    await HivePrefUtil.setString('videoPlayerKey', 'ijk');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      Get.put(SettingsService(), permanent: true);
      await Future<void>.delayed(Duration.zero);
      await HivePrefUtil.flush();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  tearDown(() {
    Get.deleteAll(force: true);
    Get.reset();
  });

  tearDownAll(Hive.close);

  testWidgets('Windows replaces a stale IJK preference and presents MPV as a fixed integrated engine', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en')],
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
            home: const PlayerKernelSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(SettingsService.to.player.videoPlayerKey.v, 'mpv');
    expect(HivePrefUtil.getString('videoPlayerKey'), 'mpv');
    expect(find.text('MPV Player'), findsOneWidget);
    expect(find.text('IJK Player'), findsNothing);
    expect(find.text('This platform uses the integrated MPV engine.'), findsOneWidget);

    final engineTile = find.ancestor(of: find.text('Player Engine'), matching: find.byType(ListTile));
    expect(engineTile, findsOneWidget);
    expect(tester.widget<ListTile>(engineTile).onTap, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}
