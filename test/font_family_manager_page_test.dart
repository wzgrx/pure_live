import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/font_model.dart';
import 'package:pure_live/common/services/medels/download_status.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/font_family_manager_page.dart';
import 'package:remixicon/remixicon.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;
  late _TestFontSettingsController font;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-font-family-page-test-');
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
    font = _TestFontSettingsController();
    font.fontList.assign(
      FontModel(
        id: 'fixture-family',
        name: 'Fixture International Sans Family',
        files: const ['fixture-family/Regular.ttf', 'fixture-family/Bold.ttf'],
        desc: 'A deliberately complete font description that remains readable together with every status and action.',
        official: 'https://example.invalid/font',
        license: const {'name': 'SIL Open Font License 1.1'},
      ),
    );
    Get.put<SettingsService>(_TestSettingsService(font));
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('narrow very-large text keeps folder, default font, metadata and action reachable', (tester) async {
    await _pumpFontPage(tester, english);

    expect(find.byIcon(Remix.folder_open_line), findsOneWidget);
    expect(find.text('Microsoft YaHei'), findsOneWidget);
    await _scrollUntilBuiltAndHitTestable(tester, find.text('Fixture International Sans Family'));
    expect(find.text('SIL Open Font License 1.1'), findsOneWidget);
    expect(find.text('2 weight variant asset files'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('active font can reset consistently and keeps local actions reachable', (tester) async {
    font.fontFamilyName.value = 'fixture-family';
    font.fontFamilyFileName.value = 'Regular.ttf';
    font.fontFolderSizes['fixture-family'] = '12.3 MB';
    await _pumpFontPage(tester, english);

    await _scrollUntilBuiltAndHitTestable(tester, find.text('Fixture International Sans Family'));
    expect(find.text('Currently Active'), findsOneWidget);
    expect(find.byTooltip('Apply'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(scrollable.position.minScrollExtent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('font-family-default')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microsoft YaHei').hitTestable());
    await tester.pumpAndSettle();
    expect(font.fontFamilyName.value, FontSettingsController.defaultFontFamilyName);
    expect(font.fontFamilyFileName.value, isEmpty);
    expect(font.resetAppFontCalled, isTrue);

    await _scrollUntilBuiltAndHitTestable(tester, find.text('Fixture International Sans Family'));
    expect(find.byIcon(Remix.delete_bin_6_line), findsOneWidget);
    expect(find.byTooltip('Apply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  test('default font reset persists one stable selection identity', () async {
    await HivePrefUtil.setString('fontFamilyName', 'fixture-family');
    await HivePrefUtil.setString('fontFamilyFileName', 'Regular.ttf');
    final persisted = _PersistenceFontSettingsController();

    expect(persisted.fontFamilyName.value, 'fixture-family');
    expect(persisted.fontFamilyFileName.value, 'Regular.ttf');
    await persisted.resetAppFontFamily().timeout(const Duration(seconds: 5));
    await HivePrefUtil.flush().timeout(const Duration(seconds: 5));

    expect(persisted.fontFamilyName.value, FontSettingsController.defaultFontFamilyName);
    expect(persisted.fontFamilyFileName.value, isEmpty);
    expect(HivePrefUtil.getString('fontFamilyName'), FontSettingsController.defaultFontFamilyName);
    expect(HivePrefUtil.getString('fontFamilyFileName'), isEmpty);
  }, skip: !Platform.isWindows);

  test('weight selector accepts font extensions regardless of case', () {
    expect(FontFamilyFilePolicy.isSupportedPath('Fixture-Regular.ttf'), isTrue);
    expect(FontFamilyFilePolicy.isSupportedPath('Fixture-Bold.OTF'), isTrue);
    expect(FontFamilyFilePolicy.isSupportedPath('Fixture-Black.TTF'), isTrue);
    expect(FontFamilyFilePolicy.isSupportedPath('Fixture.woff2'), isFalse);
  });

  testWidgets('weight selector scrolls as one dialog and selects the final file at very-large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selectedPath;
    final files = List<File>.generate(7, (index) => File('FixtureSans-Weight$index.TTF'));

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
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: IconButton(
                    tooltip: 'Open selector',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => FontWeightSelectorDialog(
                        fontName: 'Fixture International Sans Family',
                        downloadedFiles: files,
                        onAutoSelected: () async {},
                        onFileSelected: (file) async => selectedPath = file.path,
                      ),
                    ),
                    icon: const Icon(Icons.font_download_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open selector'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('font-weight-selector-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final finalOption = find.byKey(const ValueKey('font-weight-FixtureSans-Weight6.TTF'));
    expect(finalOption, findsOneWidget);
    final dialogScrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('font-weight-selector-scroll')), matching: find.byType(Scrollable)),
    );
    dialogScrollable.position.jumpTo(dialogScrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock Style - Weight6').hitTestable());
    await tester.pumpAndSettle();
    expect(selectedPath, files.last.path);
    expect(find.byType(FontWeightSelectorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}

Future<void> _pumpFontPage(WidgetTester tester, Map<String, dynamic> english) async {
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
          home: const FontFamilyManagerPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilBuiltAndHitTestable(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final next = (position.pixels + position.viewportDimension * 0.35).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
    await tester.pump();
  }
  fail('Font card did not become hit-testable after bounded page scrolling.');
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestFontSettingsController extends FontSettingsController {
  bool resetAppFontCalled = false;
  final RxString _fontFamilyName = FontSettingsController.defaultFontFamilyName.obs;
  final RxString _fontFamilyFileName = ''.obs;
  final RxList<FontModel> _fontList = <FontModel>[].obs;
  final Rx<FontModel?> _curFontModel = Rx<FontModel?>(null);
  final Rx<DownloadState> _fontState = DownloadState.notDownloaded.obs;
  final RxMap<String, String> _fontFolderSizes = <String, String>{}.obs;

  @override
  RxString get fontFamilyName => _fontFamilyName;

  @override
  RxString get fontFamilyFileName => _fontFamilyFileName;

  @override
  RxList<FontModel> get fontList => _fontList;

  @override
  Rx<FontModel?> get curFontModel => _curFontModel;

  @override
  Rx<DownloadState> get fontState => _fontState;

  @override
  RxMap<String, String> get fontFolderSizes => _fontFolderSizes;

  @override
  Future<void> refreshFontDiskSizes({bool force = false}) async {}

  @override
  Future<void> resetAppFontFamily() async {
    resetAppFontCalled = true;
    fontFamilyName.value = FontSettingsController.defaultFontFamilyName;
    fontFamilyFileName.value = '';
  }

  @override
  void refreshSystemTheme() {}
}

class _PersistenceFontSettingsController extends FontSettingsController {
  @override
  void refreshSystemTheme() {}
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._font);

  final FontSettingsController _font;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
