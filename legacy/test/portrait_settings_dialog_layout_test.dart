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
import 'package:pure_live/modules/settings/pages/portrait_live_settings_page.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-portrait-settings-test-');
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

  testWidgets('portrait enum summaries stack below titles in narrow very-large text', (tester) async {
    await _pumpPortraitSettings(tester, english: english);

    for (final entry in <(String, String)>[
      ('Room layout mode', 'Balanced (recommended)'),
      ('Fullscreen orientation', 'Follow source (recommended)'),
      ('Portrait fullscreen display', 'Ambient background (recommended)'),
      ('Portrait danmaku layout', 'Follow global'),
    ]) {
      final tile = _tileWithTitle(entry.$1);
      await _scrollPageUntilHitTestable(tester, tile);
      final titleRect = tester.getRect(find.descendant(of: tile, matching: find.text(entry.$1)));
      final valueRect = tester.getRect(find.descendant(of: tile, matching: find.text(entry.$2)));
      expect(valueRect.top, greaterThanOrEqualTo(titleRect.bottom));
      expect(tester.takeException(), isNull);
    }
  }, skip: !Platform.isWindows);

  testWidgets('portrait enum dialogs keep every choice reachable and whole rows selectable', (tester) async {
    var presentationRefreshes = 0;
    await _pumpPortraitSettings(tester, english: english, presentationRefreshOverride: () => presentationRefreshes++);

    await _selectLastOption(
      tester,
      title: 'Room layout mode',
      optionLabels: const ['Balanced (recommended)', 'Immersive', 'Compatible 16:9'],
    );
    expect(SettingsService.to.player.portraitLayoutMode, PortraitLayoutMode.compatibility);

    await _selectLastOption(
      tester,
      title: 'Fullscreen orientation',
      optionLabels: const ['Follow source (recommended)', 'Follow system', 'Always landscape'],
    );
    expect(SettingsService.to.player.portraitFullscreenPolicy, PortraitFullscreenPolicy.landscape);
    expect(presentationRefreshes, 1);

    await _selectLastOption(
      tester,
      title: 'Portrait fullscreen display',
      optionLabels: const ['Complete frame', 'Ambient background (recommended)', 'Balanced fill', 'Crop to fill'],
    );
    expect(SettingsService.to.player.portraitFullscreenDisplayMode, PortraitFullscreenDisplayMode.cover);

    await _selectLastOption(
      tester,
      title: 'Portrait danmaku layout',
      optionLabels: const ['Follow global', 'Upper 25%', 'Reduced 50%', 'Hide on portrait sources'],
    );
    expect(SettingsService.to.player.portraitDanmakuMode, PortraitDanmakuMode.hidden);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}

Future<void> _pumpPortraitSettings(
  WidgetTester tester, {
  required Map<String, dynamic> english,
  VoidCallback? presentationRefreshOverride,
}) async {
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
          home: PortraitLiveSettingsPage(presentationRefreshOverride: presentationRefreshOverride),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pageScrollable() => find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

Finder _tileWithTitle(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

Future<void> _scrollPageUntilHitTestable(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(_pageScrollable());
  for (var attempt = 0; attempt < 40; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final next = position.pixels + position.viewportDimension * 0.75;
    position.jumpTo(next > position.maxScrollExtent ? position.maxScrollExtent : next);
    await tester.pump();
  }
  fail('Target did not become hit-testable after bounded page scrolling.');
}

Future<void> _openDialog(WidgetTester tester, String title) async {
  final tile = _tileWithTitle(title);
  await _scrollPageUntilHitTestable(tester, tile);
  await tester.tap(tile.hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _assertDialogOptions(WidgetTester tester, List<String> optionLabels) async {
  final dialog = find.byType(AlertDialog);
  for (final label in optionLabels) {
    expect(find.descendant(of: dialog, matching: find.text(label)), findsOneWidget);
  }
  final lastOption = find.widgetWithText(SimpleDialogOption, optionLabels.last);
  final dialogScrollable = find.descendant(of: dialog, matching: find.byType(Scrollable)).first;
  final scrollable = tester.state<ScrollableState>(dialogScrollable);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(tester.getRect(lastOption).bottom, lessThanOrEqualTo(480));
  expect(tester.takeException(), isNull);
}

Future<void> _selectLastOption(WidgetTester tester, {required String title, required List<String> optionLabels}) async {
  await _openDialog(tester, title);
  await _assertDialogOptions(tester, optionLabels);
  await tester.tap(find.widgetWithText(SimpleDialogOption, optionLabels.last));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
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
