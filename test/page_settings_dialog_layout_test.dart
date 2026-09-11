import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/page_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/page_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late PageSettingsController pageController;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-page-settings-layout-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    pageController = PageSettingsController();
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('page-size editor opens and cancellation preserves options', (tester) async {
    await _openPage(tester, pageController: pageController, size: const Size(900, 600));
    final original = pageController.pageSizeOptions.toList();

    await tester.tap(find.text('Page Size Options'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Current Active Options'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(pageController.pageSizeOptions, original);
  });

  testWidgets('page-size editor keeps every action reachable in narrow large text', (tester) async {
    await _openPage(tester, pageController: pageController, size: const Size(320, 480), textScale: 2);

    await tester.ensureVisible(find.text('Page Size Options'));
    await tester.pumpAndSettle();
    expect(find.text('Page Size Options').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Page Size Options'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Current Active Options'), findsOneWidget);
    expect(find.text('Adaptive Auto'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPage(
  WidgetTester tester, {
  required PageSettingsController pageController,
  required Size size,
  double textScale = 1,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  Get.reset();
  Get.put<SettingsService>(_TestSettingsService(pageController));
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
          home: const PageSettingsPage(),
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
    'page_settings': 'Page Settings',
    'paging_controller': 'Pagination',
    'show_page_size_selector': 'Show page-size selector',
    'show_page_size_selector_subtitle': 'Let users select a page size',
    'show_goto_button': 'Show go-to-page action',
    'show_goto_button_subtitle': 'Jump directly to a page',
    'show_scroll_to_top': 'Show scroll-to-top action',
    'show_scroll_to_top_subtitle': 'Return to the first result',
    'page_size_options_manage': 'Page Size Options',
    'current_options': 'Current Active Options',
    'adaptive_recommend': 'Adaptive Auto',
    'custom_input': 'Custom Input',
    'items_per_page': 'items/page',
    'add': 'Add',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
  };
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._page) : _font = FontSettingsController();

  final PageSettingsController _page;
  final FontSettingsController _font;

  @override
  PageSettingsController get page => _page;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production service registrations.
  // ignore: must_call_super
  void onInit() {}
}
