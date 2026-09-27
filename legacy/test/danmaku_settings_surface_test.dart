import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:hive_ce/hive.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/get/get.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/modules/live_play/pages/danmaku_settings_page.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_settings_binding.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-danmaku-surface-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService(DanmakuSettingsController()));
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('portrait uses the canonical reactive settings surface', (tester) async {
    final portrait = _TestDanmakuSettingsBinding();
    await tester.pumpWidget(_testApp(DanmakuSettingsContent(controller: portrait, includePipSettings: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('danmaku-settings-content-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('danmaku-template-best')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('danmaku-template-best')));
    await tester.pump();
    _expectBestPreset(portrait);
    await _finishToast(tester);
  });

  testWidgets('fullscreen uses the same surface in an adaptive landscape panel', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fullscreen = _TestDanmakuSettingsBinding();
    await tester.pumpWidget(_testApp(SettingsPanel(controller: fullscreen)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fullscreen-danmaku-settings-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('danmaku-settings-content-embedded')), findsOneWidget);
    expect(find.byKey(const ValueKey('danmaku-template-best')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Restore'), findsOneWidget);
    expect(find.text('PiP danmaku'), findsNothing, reason: 'fullscreen keeps PiP controls on their dedicated page');
    await tester.tap(find.byKey(const ValueKey('danmaku-template-best')));
    await tester.pump();
    _expectBestPreset(fullscreen);
    await _finishToast(tester);

    final panelRect = tester.getRect(find.byKey(const ValueKey('fullscreen-danmaku-settings-panel')));
    expect(panelRect.width, inInclusiveRange(340, 460));
    expect(panelRect.right, greaterThan(990));
  });

  testWidgets('fullscreen settings panel follows the active light theme', (tester) async {
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light),
    );
    final fullscreen = _TestDanmakuSettingsBinding();

    await tester.pumpWidget(_testApp(SettingsPanel(controller: fullscreen), theme: lightTheme));
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(find.byKey(const ValueKey('fullscreen-danmaku-settings-panel')));
    final decoration = panel.decoration! as BoxDecoration;
    final title = tester.widget<Text>(find.text('Danmaku settings'));

    expect(decoration.color, lightTheme.colorScheme.surface);
    expect(title.style?.color, lightTheme.colorScheme.onSurface);
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('danmaku-settings-content-embedded')))).brightness,
      Brightness.light,
    );
  });

  testWidgets('portrait and compact landscape keep one preset state without overflow', (tester) async {
    final shared = _TestDanmakuSettingsBinding();
    final showLandscapePanel = ValueNotifier<bool>(false);
    addTearDown(showLandscapePanel.dispose);
    await tester.pumpWidget(
      _testApp(
        ValueListenableBuilder<bool>(
          valueListenable: showLandscapePanel,
          builder: (context, landscape, _) =>
              landscape ? SettingsPanel(controller: shared) : DanmakuSettingsPage(controller: shared),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final densityBefore = tester.getRect(find.byKey(const ValueKey('danmaku-template-dense')));
    await tester.tap(find.byKey(const ValueKey('danmaku-template-comfort')));
    await tester.pump();
    await _finishToast(tester);
    final densityAfter = tester.getRect(find.byKey(const ValueKey('danmaku-template-dense')));
    final comfort = DanmakuViewingPreset.values.firstWhere((preset) => preset.id == 'comfort');
    expect(shared.danmakuArea.value, comfort.area);
    expect(densityAfter, densityBefore, reason: 'selecting a preset must not reflow the fullscreen controls');

    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    showLandscapePanel.value = true;
    await tester.pumpAndSettle();

    final selected = tester.widget<ChoiceChip>(find.byKey(const ValueKey('danmaku-template-comfort')));
    expect(selected.selected, isTrue);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byKey(const ValueKey('danmaku-settings-content-embedded')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('PiP danmaku'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved template round trips every rendered setting from both layouts', (tester) async {
    final binding = _TestDanmakuSettingsBinding();
    final settings = SettingsService.to.danmaku;
    binding.noEmojiMode.value = true;
    binding.danmakuArea.value = 0.42;
    binding.danmakuTopArea.value = 23;
    binding.danmakuBottomArea.value = 47;
    binding.danmakuSpeed.value = 181;
    binding.danmakuFontSize.value = 21;
    binding.danmakuFontWeight.value = 700;
    binding.danmakuFontBorder.value = 2.5;
    binding.danmakuOpacity.value = 0.64;
    binding.enableDanmakuStroke.value = false;
    binding.danmakuFps.value = 144;
    settings.danmakuAutoFps.value = false;
    final saved = _templateSnapshot(binding, settings);

    await tester.pumpWidget(_testApp(DanmakuSettingsContent(controller: binding, includePipSettings: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pump();
    expect(jsonDecode(settings.savedDanmakuTemplate.value), containsPair('noEmojiMode', true));
    await _finishToast(tester);

    binding.noEmojiMode.value = false;
    binding.danmakuArea.value = 1;
    binding.danmakuTopArea.value = 0;
    binding.danmakuBottomArea.value = 0;
    binding.danmakuSpeed.value = 20;
    binding.danmakuFontSize.value = 10;
    binding.danmakuFontWeight.value = 100;
    binding.danmakuFontBorder.value = 0;
    binding.danmakuOpacity.value = 1;
    binding.enableDanmakuStroke.value = true;
    binding.danmakuFps.value = 30;
    settings.danmakuAutoFps.value = true;

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
    await tester.pump();
    expect(_templateSnapshot(binding, settings), saved);
    await _finishToast(tester);
  });

  testWidgets('invalid saved template is rejected before any setting changes', (tester) async {
    final binding = _TestDanmakuSettingsBinding();
    final settings = SettingsService.to.danmaku;
    binding.noEmojiMode.value = true;
    binding.danmakuArea.value = 0.77;
    binding.danmakuTopArea.value = 11;
    binding.danmakuBottomArea.value = 22;
    binding.danmakuSpeed.value = 130;
    binding.danmakuFontSize.value = 18;
    binding.danmakuFontWeight.value = 600;
    binding.danmakuFontBorder.value = 2;
    binding.danmakuOpacity.value = 0.8;
    binding.enableDanmakuStroke.value = true;
    binding.danmakuFps.value = 90;
    settings.danmakuAutoFps.value = false;
    final before = _templateSnapshot(binding, settings);
    settings.savedDanmakuTemplate.value = jsonEncode({
      'noEmojiMode': false,
      'area': 0.2,
      'top': 1,
      'bottom': 2,
      'speed': 100,
      'fontSize': 15,
      'fontWeight': 400,
      'fontBorder': 1,
      'opacity': 'bad-late-field',
      'stroke': false,
      'fps': 60,
      'autoFps': true,
    });

    await tester.pumpWidget(_testApp(DanmakuSettingsContent(controller: binding, includePipSettings: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
    await tester.pump();

    expect(_templateSnapshot(binding, settings), before);
    await _finishToast(tester);
  });

  testWidgets('switch, slider and counter announce complete adjustable semantics', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();
    try {
      final binding = _TestDanmakuSettingsBinding();
      await tester.pumpWidget(_testApp(DanmakuSettingsContent(controller: binding, includePipSettings: false)));
      await tester.pumpAndSettle();

      final toggle = tester.semantics.find(find.bySemanticsLabel('Pure text')).getSemanticsData();
      expect(toggle.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(toggle.flagsCollection.isToggled, ui.Tristate.isFalse);
      await tester.tap(find.text('Pure text'));
      await tester.pump();
      expect(binding.noEmojiMode.value, isTrue);

      final scroll = find.byKey(const ValueKey('danmaku-settings-content-page'));
      final scrollable = find.descendant(of: scroll, matching: find.byType(Scrollable));
      final slider = find.semantics.byValue('Area, 100%');
      expect(slider, findsOne);
      final sliderData = slider.evaluate().single.getSemanticsData();
      expect(sliderData.hasAction(ui.SemanticsAction.increase), isTrue);
      expect(sliderData.hasAction(ui.SemanticsAction.decrease), isTrue);

      await tester.scrollUntilVisible(find.text('Top margin'), 220, scrollable: scrollable);
      await tester.pump();
      expect(find.bySemanticsLabel('Top margin, 0'), findsOne);
      expect(find.bySemanticsLabel('Increase Top margin'), findsOne);
      expect(find.bySemanticsLabel('Decrease Top margin'), findsOne);
    } finally {
      semanticsHandle.dispose();
    }
  });
}

Future<void> _finishToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Widget _testApp(Widget child, {ThemeData? theme}) {
  return EasyLocalization(
    key: ValueKey<Type>(child.runtimeType),
    supportedLocales: const [Locale('zh')],
    path: 'assets/translations',
    fallbackLocale: const Locale('zh'),
    assetLoader: const _TestAssetLoader(),
    child: Builder(
      builder: (context) => GetMaterialApp(
        locale: context.locale,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        theme: theme ?? ThemeData.dark(),
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void _expectBestPreset(_TestDanmakuSettingsBinding binding) {
  final best = DanmakuViewingPreset.values.firstWhere((preset) => preset.id == 'best');
  expect(binding.danmakuArea.value, best.area);
  expect(binding.danmakuTopArea.value, best.top);
  expect(binding.danmakuBottomArea.value, best.bottom);
  expect(binding.danmakuSpeed.value, best.speed);
  expect(binding.danmakuFontSize.value, best.fontSize);
  expect(binding.danmakuFontWeight.value, best.fontWeight);
  expect(binding.danmakuFontBorder.value, best.fontBorder);
  expect(binding.danmakuOpacity.value, best.opacity);
  expect(binding.enableDanmakuStroke.value, best.stroke);
}

Map<String, Object> _templateSnapshot(_TestDanmakuSettingsBinding binding, DanmakuSettingsController settings) => {
  'noEmojiMode': binding.noEmojiMode.value,
  'area': binding.danmakuArea.value,
  'top': binding.danmakuTopArea.value,
  'bottom': binding.danmakuBottomArea.value,
  'speed': binding.danmakuSpeed.value,
  'fontSize': binding.danmakuFontSize.value,
  'fontWeight': binding.danmakuFontWeight.value,
  'fontBorder': binding.danmakuFontBorder.value,
  'opacity': binding.danmakuOpacity.value,
  'stroke': binding.enableDanmakuStroke.value,
  'fps': binding.danmakuFps.value,
  'autoFps': settings.danmakuAutoFps.value,
};

class _TestDanmakuSettingsBinding implements DanmakuSettingsBinding {
  @override
  final noEmojiMode = false.obs;
  @override
  final danmakuArea = 1.0.obs;
  @override
  final danmakuTopArea = 0.0.obs;
  @override
  final danmakuBottomArea = 0.5.obs;
  @override
  final danmakuSpeed = 120.0.obs;
  @override
  final danmakuFontSize = 16.0.obs;
  @override
  final danmakuFontWeight = 500.obs;
  @override
  final danmakuFontBorder = 1.5.obs;
  @override
  final danmakuOpacity = 1.0.obs;
  @override
  final enableDanmakuStroke = true.obs;
  @override
  final danmakuFps = 60.obs;
}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => const {
    'settings_danmaku_title': 'Danmaku settings',
    'danmaku_templates': 'Templates',
    'danmaku_template_best': 'Best',
    'danmaku_template_comfort': 'Comfort',
    'danmaku_template_dense': 'Dense',
    'reset': 'Default',
    'save_current_template': 'Save',
    'restore_saved_template': 'Restore',
    'increase_value': 'Increase {label}',
    'decrease_value': 'Decrease {label}',
    'danmaku_best_preset_desc': 'Recommended viewing area',
    'danmaku_realtime_hint': 'Changes apply immediately',
    'danmaku_template_applied': 'Applied',
    'danmaku_template_saved': 'Saved',
    'danmaku_template_empty': 'No saved template',
    'danmaku_template_invalid': 'Invalid template',
    'danmaku_area': 'Area',
    'position': 'Position',
    'style': 'Style',
    'danmaku_screen_interaction': 'Interaction',
    'danmaku_repeat_filter': 'Repeated danmaku filter',
    'collapse_repeated_danmaku': 'Merge repeated text',
    'collapse_repeated_danmaku_desc': 'Hide the same audience text inside the time window',
    'repeated_danmaku_window': 'Merge window',
    'danmaku_no_emoji': 'Pure text',
    'margin_top': 'Top margin',
    'margin_bottom': 'Bottom margin',
    'opacity': 'Opacity',
    'speed': 'Speed',
    'font_size': 'Font size',
    'font_weight': 'Font weight',
    'font_weight_normal': 'Normal',
    'font_weight_medium': 'Medium',
    'font_weight_semi_bold': 'Semi-bold',
    'font_weight_bold': 'Bold',
    'font_weight_extra_bold': 'Extra-bold',
    'danmaku_stroke': 'Stroke',
    'stroke': 'Stroke width',
    'danmaku_fps': 'FPS',
    'dynamic_follow_display': 'Dynamic',
    'danmaku_fps_policy_desc': 'Follow the global interface refresh policy',
    'pip_danmaku_fps_policy_desc': 'Follow the global interface refresh policy',
    'danmaku_tap_action': 'Tap action',
    'danmaku_long_press_action': 'Long press action',
    'pip_danmaku': 'PiP danmaku',
    'pip_danmaku_enable': 'Enable PiP danmaku',
    'pip_danmaku_auto_scale': 'Auto scale',
    'pip_danmaku_original_color': 'Original color',
    'pip_danmaku_max_visible': 'Maximum visible',
    'pip_danmaku_interval': 'Interval',
    'close': 'Close',
  };
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._danmaku) : _app = AppSettingsController(), _font = FontSettingsController();

  final DanmakuSettingsController _danmaku;
  final AppSettingsController _app;
  final FontSettingsController _font;

  @override
  AppSettingsController get app => _app;

  @override
  DanmakuSettingsController get danmaku => _danmaku;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips the production service registrations.
  // ignore: must_call_super
  void onInit() {}
}
