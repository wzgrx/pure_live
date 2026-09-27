import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/pip_danmaku_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-pip-preview-test-');
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

  tearDown(() {
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('font size slider value rebuilds the PiP preview immediately', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const Scaffold(body: SizedBox(width: 350, child: PipDanmakuPreview())),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    dynamic painter = _previewPainter(tester);
    expect(painter.fontSize, closeTo(12, 0.01));

    SettingsService.to.danmaku.pipDanmakuFontSize.value = 22;
    await tester.pump();

    painter = _previewPainter(tester);
    expect(painter.fontSize, closeTo(22, 0.01));
  });

  testWidgets('mobile settings scroll independently while preview stays pinned', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const PipDanmakuSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final preview = find.byKey(const ValueKey('pip-danmaku-preview-pane'));
    final settings = find.byKey(const ValueKey('pip-danmaku-settings-scroll'));
    final before = tester.getTopLeft(preview);
    await tester.drag(settings, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getTopLeft(preview), before);
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(of: settings, matching: find.byType(Scrollable)),
    );
    expect(scrollableState.position.pixels, greaterThan(0));
  });

  testWidgets('desktop keeps preview and settings in independent columns', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPipSettingsPage(tester);

    final preview = find.byKey(const ValueKey('pip-danmaku-preview-pane'));
    final settings = find.byKey(const ValueKey('pip-danmaku-settings-scroll'));
    final previewBefore = tester.getRect(preview);
    final settingsBefore = tester.getRect(settings);

    expect(previewBefore.right, lessThan(settingsBefore.left));
    await tester.drag(settings, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getRect(preview), previewBefore);
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(of: settings, matching: find.byType(Scrollable)),
    );
    expect(scrollableState.position.pixels, greaterThan(0));
  });

  testWidgets('switch rows expose labeled toggle semantics and full-row hit targets', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();
    try {
      await _pumpPipSettingsPage(tester);

      final enableSemantics = tester.semantics.find(find.bySemanticsLabel('Enable'));
      final enabledData = enableSemantics.getSemanticsData();
      expect(enabledData.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(enabledData.flagsCollection.isToggled, ui.Tristate.isTrue);

      await tester.tap(find.text('Enable'));
      await tester.pump();

      expect(SettingsService.to.danmaku.enablePipDanmaku.value, isFalse);
      final disabledData = tester.semantics.find(find.bySemanticsLabel('Enable')).getSemanticsData();
      expect(disabledData.flagsCollection.isToggled, ui.Tristate.isFalse);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('slider semantics announce the setting name and formatted value', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();
    try {
      await _pumpPipSettingsPage(tester);
      final settings = find.byKey(const ValueKey('pip-danmaku-settings-scroll'));
      final scrollable = find.descendant(of: settings, matching: find.byType(Scrollable));
      final fontSizeSlider = find.byType(SfSlider).first;
      await tester.scrollUntilVisible(fontSizeSlider, 180, scrollable: scrollable);
      await tester.pump();

      final semanticsFinder = find.semantics.byValue('Font size, 12.0');
      expect(semanticsFinder, findsOne);
      final semantics = semanticsFinder.evaluate().single.getSemanticsData();
      expect(semantics.hasAction(ui.SemanticsAction.increase), isTrue);
      expect(semantics.hasAction(ui.SemanticsAction.decrease), isTrue);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('color and counter rows expose named actions and values', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SettingsService.to.danmaku.pipDanmakuUseOriginalColor.value = false;
    final semanticsHandle = tester.ensureSemantics();
    try {
      await _pumpPipSettingsPage(tester);
      final settings = find.byKey(const ValueKey('pip-danmaku-settings-scroll'));
      final scrollable = find.descendant(of: settings, matching: find.byType(Scrollable));

      final color = find.bySemanticsLabel('Unified danmaku color, #FFFFFFFF');
      await tester.scrollUntilVisible(color, 180, scrollable: scrollable);
      await tester.pump();
      expect(color, findsOne);
      expect(tester.semantics.find(color).getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);

      await tester.scrollUntilVisible(find.text('Maximum visible'), 180, scrollable: scrollable);
      await tester.pump();
      final maximumVisible = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Maximum visible, 6',
      );
      expect(maximumVisible, findsOne);
      expect(find.bySemanticsLabel('Increase Maximum visible'), findsOne);
      expect(find.bySemanticsLabel('Decrease Maximum visible'), findsOne);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('reset cancellation preserves values and confirmation restores every PiP default', (tester) async {
    final settings = SettingsService.to.danmaku;
    settings.enablePipDanmaku.value = false;
    settings.pipDanmakuAutoScale.value = false;
    settings.pipDanmakuNoEmojiMode.value = true;
    settings.pipDanmakuUseOriginalColor.value = false;
    settings.pipDanmakuColor.value = 0xFF123456;
    settings.pipDanmakuFontSize.value = 19;
    settings.pipDanmakuFontWeight.value = 800;
    settings.pipDanmakuSpeed.value = 180;
    settings.pipDanmakuOpacity.value = 0.4;
    settings.pipDanmakuArea.value = 0.8;
    settings.pipDanmakuMaxVisibleCount.value = 13;
    settings.pipDanmakuEmitInterval.value = 1.2;
    settings.pipDanmakuFps.value = 144;
    settings.pipDanmakuAutoFps.value = false;
    final customized = _pipSettingsSnapshot(settings);

    await _pumpPipSettingsPage(tester);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Every PiP danmaku option will be restored to its default.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_pipSettingsSnapshot(settings), customized);

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_pipSettingsSnapshot(settings), _defaultPipSettingsSnapshot());
  });

  test('reset confirmation translations describe the complete settings reset', () {
    final english = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final chinese = jsonDecode(File('assets/translations/zh.json').readAsStringSync()) as Map<String, dynamic>;

    expect(
      english['pip_danmaku_reset_confirm'],
      allOf(contains('switch'), contains('display rules'), contains('font size and weight'), contains('frame rate')),
    );
    expect(
      chinese['pip_danmaku_reset_confirm'],
      allOf(contains('开关'), contains('显示规则'), contains('字号和字重'), contains('帧率')),
    );
  });

  testWidgets('pure-text switch refreshes preview content immediately', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const Scaffold(body: SizedBox(width: 350, child: PipDanmakuPreview())),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    dynamic painter = _previewPainter(tester);
    expect((painter.painters.first.text as TextSpan).text, contains('🎉'));

    SettingsService.to.danmaku.pipDanmakuNoEmojiMode.value = true;
    await tester.pump();

    painter = _previewPainter(tester);
    expect((painter.painters.first.text as TextSpan).text, isNot(contains('🎉')));
  });

  testWidgets('preview follows the outline used by the compact renderer', (tester) async {
    final settings = SettingsService.to.danmaku;
    settings.enableDanmakuStroke.value = false;
    settings.danmakuFontBorder.value = 3;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const Scaffold(body: SizedBox(width: 350, child: PipDanmakuPreview())),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    dynamic painter = _previewPainter(tester);
    expect(painter.showStroke, isFalse);
    expect(painter.strokeWidth, 3);
    expect(painter.strokePainters, isEmpty);

    settings.enableDanmakuStroke.value = true;
    await tester.pump();

    painter = _previewPainter(tester);
    expect(painter.showStroke, isTrue);
    expect(painter.strokeWidth, 3);
    expect(painter.strokePainters, hasLength(painter.painters.length));
  });

  testWidgets('auto scale keeps preview motion aligned with the compact renderer', (tester) async {
    SettingsService.to.danmaku.pipDanmakuSpeed.value = 120;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 280, child: PipDanmakuPreview()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    dynamic painter = _previewPainter(tester);
    expect(painter.fontSize, closeTo(9.6, 0.01));
    expect(
      painter.speed,
      closeTo(96, 0.01),
      reason: 'the live compact overlay scales both font size and base speed at 280/350 width',
    );
    expect(painter.trackHeight, closeTo(19.6, 0.01));
    expect(painter.overlapSafeGap, closeTo(16, 0.01));

    SettingsService.to.danmaku.pipDanmakuAutoScale.value = false;
    await tester.pump();

    painter = _previewPainter(tester);
    expect(painter.fontSize, closeTo(12, 0.01));
    expect(painter.speed, closeTo(120, 0.01));
    expect(painter.trackHeight, closeTo(22, 0.01));
    expect(painter.overlapSafeGap, closeTo(18, 0.01));
  });
}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'pip_danmaku_preview_text': 'preview',
    'pip_danmaku_disabled': 'disabled',
    'pip_danmaku': 'PiP danmaku',
    'pip_danmaku_desc': 'Adjust while preview remains visible',
    'pip_danmaku_preview': 'Preview',
    'pip_danmaku_reset': 'Reset',
    'pip_danmaku_reset_confirm': 'Every PiP danmaku option will be restored to its default.',
    'pip_danmaku_enable': 'Enable',
    'pip_danmaku_auto_scale': 'Auto scale',
    'danmaku_no_emoji': 'Pure text',
    'pip_danmaku_original_color': 'Original color',
    'pip_danmaku_color': 'Unified danmaku color',
    'font_size': 'Font size',
    'font_weight': 'Font weight',
    'font_weight_medium': 'Medium',
    'font_weight_normal': 'Normal',
    'font_weight_semi_bold': 'Semi-bold',
    'font_weight_bold': 'Bold',
    'font_weight_extra_bold': 'Extra-bold',
    'speed': 'Speed',
    'opacity': 'Opacity',
    'danmaku_area': 'Area',
    'pip_danmaku_max_visible': 'Maximum visible',
    'pip_danmaku_interval': 'Interval',
    'increase_value': 'Increase {label}',
    'decrease_value': 'Decrease {label}',
    'danmaku_fps': 'FPS',
    'dynamic_follow_display': 'Dynamic',
    'pip_danmaku_fps_policy_desc': 'Follow the global interface refresh policy',
    'cancel': 'Cancel',
    'reset': 'Reset',
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

dynamic _previewPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(PipDanmakuPreview), matching: find.byType(CustomPaint)),
  );
  return customPaint.painter;
}

Future<void> _pumpPipSettingsPage(WidgetTester tester) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh'),
      assetLoader: const _TestAssetLoader(),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          home: const PipDanmakuSettingsPage(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Map<String, Object> _pipSettingsSnapshot(DanmakuSettingsController settings) => {
  'enable': settings.enablePipDanmaku.value,
  'autoScale': settings.pipDanmakuAutoScale.value,
  'noEmoji': settings.pipDanmakuNoEmojiMode.value,
  'originalColor': settings.pipDanmakuUseOriginalColor.value,
  'color': settings.pipDanmakuColor.value,
  'fontSize': settings.pipDanmakuFontSize.value,
  'fontWeight': settings.pipDanmakuFontWeight.value,
  'speed': settings.pipDanmakuSpeed.value,
  'opacity': settings.pipDanmakuOpacity.value,
  'area': settings.pipDanmakuArea.value,
  'maxVisible': settings.pipDanmakuMaxVisibleCount.value,
  'interval': settings.pipDanmakuEmitInterval.value,
  'fps': settings.pipDanmakuFps.value,
  'autoFps': settings.pipDanmakuAutoFps.value,
};

Map<String, Object> _defaultPipSettingsSnapshot() => {
  'enable': DanmakuSettingsController.defaultEnablePipDanmaku,
  'autoScale': DanmakuSettingsController.defaultPipDanmakuAutoScale,
  'noEmoji': DanmakuSettingsController.defaultPipDanmakuNoEmojiMode,
  'originalColor': DanmakuSettingsController.defaultPipDanmakuUseOriginalColor,
  'color': DanmakuSettingsController.defaultPipDanmakuColor,
  'fontSize': DanmakuSettingsController.defaultPipDanmakuFontSize,
  'fontWeight': DanmakuSettingsController.defaultPipDanmakuFontWeight,
  'speed': DanmakuSettingsController.defaultPipDanmakuSpeed,
  'opacity': DanmakuSettingsController.defaultPipDanmakuOpacity,
  'area': DanmakuSettingsController.defaultPipDanmakuArea,
  'maxVisible': DanmakuSettingsController.defaultPipDanmakuMaxVisibleCount,
  'interval': DanmakuSettingsController.defaultPipDanmakuEmitInterval,
  'fps': DanmakuSettingsController.defaultPipDanmakuFps,
  'autoFps': DanmakuSettingsController.defaultPipDanmakuAutoFps,
};
