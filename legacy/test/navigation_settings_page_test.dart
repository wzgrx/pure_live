import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/navigation_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;
  late _NavigationTestAppSettings app;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-navigation-settings-test-');
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
    app = _NavigationTestAppSettings();
    Get.put<SettingsService>(_TestSettingsService(app));
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('hidden tabs have no drag handle and reorder callbacks stay bounded', (tester) async {
    app.savedMenuIds.value = [HomeMenu.favorites.id];
    await _pumpNavigationSettings(tester, english: english, size: const Size(420, 800));

    final reorderable = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(() => reorderable.onReorderItem!(3, 0), returnsNormally);
    expect(() => reorderable.onReorderItem!(0, 4), returnsNormally);
    expect(app.savedMenuIds, [HomeMenu.favorites.id]);

    final hiddenRow = find.byKey(ValueKey(HomeMenu.record.id));
    expect(find.descendant(of: hiddenRow, matching: find.byType(ReorderableDragStartListener)), findsNothing);
    final onlyVisibleRow = find.byKey(ValueKey(HomeMenu.favorites.id));
    expect(find.descendant(of: onlyVisibleRow, matching: find.byType(ReorderableDragStartListener)), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('visible tabs reorder and the last tab remains enabled', (tester) async {
    app.savedMenuIds.value = HomeMenu.values.map((menu) => menu.id).toList();
    await _pumpNavigationSettings(tester, english: english, size: const Size(420, 800));

    final reorderable = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    reorderable.onReorderItem!(0, 3);
    await tester.pump();
    expect(app.savedMenuIds, [HomeMenu.popular.id, HomeMenu.areas.id, HomeMenu.favorites.id, HomeMenu.record.id]);

    app.savedMenuIds.value = [HomeMenu.favorites.id];
    await tester.pump();
    final favoriteSwitch = find.byKey(const ValueKey('navigation-menu-switch-favorites'));
    tester.widget<Switch>(favoriteSwitch).onChanged!(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.savedMenuIds, [HomeMenu.favorites.id]);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('narrow very-large text keeps every menu title and control row reachable', (tester) async {
    app.savedMenuIds.value = HomeMenu.values.map((menu) => menu.id).toList();
    await _pumpNavigationSettings(tester, english: english, size: const Size(320, 480), textScale: 3);

    for (final menu in HomeMenu.values) {
      final row = find.byKey(ValueKey(menu.id));
      await _scrollPageUntilHitTestable(tester, row);
      final title = find.byKey(ValueKey('navigation-menu-title-${menu.id}'));
      final controls = find.byKey(ValueKey('navigation-menu-controls-${menu.id}'));
      expect(tester.getRect(controls).top, greaterThanOrEqualTo(tester.getRect(title).bottom));
      expect(tester.getRect(controls).bottom, lessThanOrEqualTo(tester.getRect(row).bottom));
      expect(tester.takeException(), isNull);
    }
  }, skip: !Platform.isWindows);
}

Future<void> _pumpNavigationSettings(
  WidgetTester tester, {
  required Map<String, dynamic> english,
  required Size size,
  double textScale = 1,
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
          home: const NavigationSettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollPageUntilHitTestable(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
  );
  for (var attempt = 0; attempt < 40; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final next = (position.pixels + position.viewportDimension * 0.4).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
    await tester.pump();
  }
  fail('Menu row did not become hit-testable after bounded page scrolling.');
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _NavigationTestAppSettings extends AppSettingsController {
  final RxList<String> _menuIds = HomeMenu.values.map((menu) => menu.id).toList().obs;

  @override
  RxList<String> get savedMenuIds => _menuIds;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._app) : _font = FontSettingsController();

  final AppSettingsController _app;
  final FontSettingsController _font;

  @override
  AppSettingsController get app => _app;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
