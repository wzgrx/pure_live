import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 400,
  double textScale = 1,
  ThemeData? theme,
  bool tv = false,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = Size(width, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme:
          theme ??
          const LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity).light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 1200), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SettingsRowStyle(
            tv: tv,
            child: ListView(padding: const EdgeInsets.all(16), children: [child]),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 1));
  }
}

double _luminance(Color color) => color.computeLuminance();

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('settings rows (U.6a, U.1c)', () {
    testWidgets('a group: title, card, rows in order, a divider between them', (tester) async {
      await _pump(
        tester,
        SettingsGroup(
          title: '主题',
          children: [
            SettingsLinkRow(key: const ValueKey('a'), title: '主题模式', value: '跟随系统', onTap: () {}),
            SettingsSwitchRow(key: const ValueKey('b'), title: '纯黑背景', value: false, onChanged: (_) {}),
          ],
        ),
      );
      expect(find.text('主题'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('b'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const ValueKey('a'))).dy),
      );
      expect(find.byType(Divider), findsOneWidget);
      // The divider starts where the text starts.
      expect(tester.getTopLeft(find.byType(Divider)).dx, 16 + 56);
    });

    testWidgets('explanations: two lines, secondary colour above 4.5:1 on the card', (tester) async {
      await _pump(
        tester,
        SettingsGroup(
          children: [SettingsLinkRow(title: '外观', subtitle: '主题模式和颜色、加载动画、房间卡片、列表间距、语言、字体和文字大小' * 3, onTap: () {})],
        ),
      );
      final text = tester.widget<HighlightedText>(find.byType(HighlightedText).last);
      expect(text.maxLines, 2);
      for (final seed in [LiveTheme.brandBlue, LiveTheme.legacyBlue, Colors.orange, Colors.teal]) {
        for (final brightness in Brightness.values) {
          final scheme = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          );
          expect(_contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow), greaterThanOrEqualTo(4.5));
          expect(_contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.5), reason: '$seed $brightness');
        }
      }
    });

    testWidgets('an explanation may show whole (a folder path, U.7b c3)', (tester) async {
      await _pump(
        tester,
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              title: '同时录制弹幕',
              subtitle: '在录像旁保存同名 .xml 弹幕文件' * 4,
              subtitleMaxLines: null,
              value: false,
              onChanged: (_) {},
            ),
          ],
        ),
      );
      expect(tester.widget<HighlightedText>(find.byType(HighlightedText).last).maxLines, isNull);
    });

    testWidgets('the frame of settings-like pages: a centred 720 column, the title at the start, 48 high when short', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(852, 393)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().light,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: settingsPageAppBar(context, title: '录制设置', subtitle: '我的网盘'),
              body: const SettingsPageList(children: [SizedBox(key: ValueKey('c'), height: 40)]),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppBar)).height, 48);
      // 3.x's titles sat at the platform's place (the start on Android).
      expect(tester.getTopLeft(find.text('录制设置')).dx, lessThan(80));
      expect(find.text('我的网盘'), findsOneWidget);
      final column = tester.getRect(find.byKey(const ValueKey('c')));
      expect(column.width, 720);
      expect(column.left, closeTo((852 - 720) / 2, 1));
    });

    testWidgets('a switch row: a tap on the row switches; the thumb stays visible when on', (tester) async {
      var value = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SettingsSwitchRow(
            key: const ValueKey('row'),
            title: '动态取色',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );
      await tester.tap(find.text('动态取色'));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);
      // No primary-on-primary thumb (3.x activeThumbColor: primary, U.4f).
      expect(toggle.activeThumbColor, isNull);
    });

    testWidgets('disabled: greyed, the reason replaces the explanation, taps ignored', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SettingsLinkRow(
          title: '主题颜色',
          subtitle: '切换软件的主题颜色',
          enabled: false,
          disabledReason: '动态取色开着',
          onTap: () => taps++,
        ),
      );
      expect(find.text('动态取色开着'), findsOneWidget);
      expect(find.text('切换软件的主题颜色'), findsNothing);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.38);
      await tester.tap(find.text('主题颜色'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('busy: a spinner at the end, taps ignored', (tester) async {
      var taps = 0;
      await _pump(tester, SettingsLinkRow(title: '清空本地缓存', busy: true, onTap: () => taps++), settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      await tester.tap(find.text('清空本地缓存'));
      expect(taps, 0);
    });

    testWidgets('the value moves under the title when narrow or with 1.5× text', (tester) async {
      Widget row() => SettingsLinkRow(title: '主题模式', subtitle: '切换系统/亮色/暗色模式', value: '跟随系统', onTap: () {});
      await _pump(tester, row());
      expect(tester.getTopLeft(find.text('跟随系统')).dy, lessThan(tester.getBottomLeft(find.text('主题模式')).dy + 20));
      expect(tester.getTopLeft(find.text('跟随系统')).dx, greaterThan(tester.getTopRight(find.text('主题模式')).dx));
      await _pump(tester, row(), textScale: 1.5);
      expect(tester.getTopLeft(find.text('跟随系统')).dy, greaterThan(tester.getBottomLeft(find.text('切换系统/亮色/暗色模式')).dy));
      await _pump(tester, row(), width: 340);
      expect(tester.getTopLeft(find.text('跟随系统')).dy, greaterThan(tester.getBottomLeft(find.text('切换系统/亮色/暗色模式')).dy));
    });

    testWidgets('a counter: − and + with names, the number opens its dialog, ends disable', (tester) async {
      final calls = <String>[];
      await _pump(
        tester,
        SettingsCounterRow(
          title: '列间距 (横向)',
          value: '0 px',
          decreaseTooltip: '减小',
          increaseTooltip: '增大',
          onDecrease: null,
          onIncrease: () => calls.add('+'),
          onValueTap: () => calls.add('value'),
        ),
      );
      final buttons = find.byType(IconButton);
      expect(tester.getTopLeft(buttons.first).dx, lessThan(tester.getTopLeft(find.text('0 px')).dx));
      expect(tester.getTopLeft(buttons.last).dx, greaterThan(tester.getTopLeft(find.text('0 px')).dx));
      expect(find.byTooltip('减小'), findsOneWidget);
      expect(tester.widget<IconButton>(buttons.first).onPressed, isNull);
      await tester.tap(buttons.last);
      await tester.tap(find.text('0 px'));
      expect(calls, ['+', 'value']);
    });

    testWidgets('a slider: the value in a pill, the slider under the text, an example below', (tester) async {
      double? moved;
      await _pump(
        tester,
        SettingsSliderRow(
          title: '文字大小',
          value: 1,
          min: 0.5,
          max: 2,
          label: '100%',
          marks: const [0.5, 1, 2],
          onChanged: (value) => moved = value,
          below: const Text('示例'),
        ),
      );
      expect(find.text('100%'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Slider)).dy, greaterThan(tester.getTopLeft(find.text('文字大小')).dy));
      expect(tester.getTopLeft(find.text('示例')).dy, greaterThan(tester.getTopLeft(find.byType(Slider)).dy));
      await tester.tap(find.byType(Slider));
      expect(moved, isNotNull);
    });

    testWidgets('chips: the chosen one is filled; a tap picks', (tester) async {
      String? picked;
      await _pump(
        tester,
        SettingsChipsRow<String>(
          title: '卡片布局',
          options: const [(value: 'cover', label: '封面卡片', key: null), (value: 'compact', label: '紧凑信息行', key: null)],
          selected: 'cover',
          onSelected: (value) => picked = value,
        ),
      );
      // The one chip of the app (U.1c c13).
      final chips = tester.widgetList<AppChip>(find.byType(AppChip)).toList();
      expect(chips.map((chip) => chip.selected), [true, false]);
      await tester.tap(find.text('紧凑信息行'));
      expect(picked, 'compact');
    });

    testWidgets('search words are marked; the focus frame shows only for the keyboard; TV enlarges', (tester) async {
      await _pump(
        tester,
        SettingsHighlight(
          words: const ['字体'],
          child: SettingsLinkRow(title: '更换弹幕字体', onTap: () {}),
        ),
      );
      final rich = tester.widget<RichText>(
        find.descendant(of: find.byType(HighlightedText), matching: find.byType(RichText)),
      );
      final outer = (rich.text as TextSpan).children!.single as TextSpan;
      final spans = outer.children!.cast<TextSpan>();
      expect(spans.map((span) => span.text), ['更换弹幕', '字体']);
      expect(spans.last.style!.backgroundColor, isNotNull);

      await _pump(tester, SettingsLinkRow(title: '外观', onTap: () {}), tv: true);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.05);
      final frame = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (box) => box.position == DecorationPosition.foreground && (box.decoration as BoxDecoration).border != null,
          );
      expect(frame, isNotEmpty);
    });
  });

  group('colour picker (U.6b c10)', () {
    const labels = LiveColorPickerLabels(
      recommended: '推荐',
      primary: '常用色',
      accent: '鲜艳色',
      wheel: '调色盘',
      shades: '选择色阶',
      opacity: '选择透明度',
      code: 'RGB 颜色代码',
      invalidCode: '代码不对',
    );

    testWidgets('recommended first with the brand blue; shades; the code is checked', (tester) async {
      final changes = <Color>[];
      final key = GlobalKey<LiveColorPickerState>();
      await _pump(
        tester,
        LiveColorPicker(key: key, color: LiveTheme.legacyBlue, labels: labels, onChanged: changes.add),
      );
      expect(find.text('推荐'), findsOneWidget);
      // 3.x's blue is in the recommended list: that tab opens with it ticked.
      expect(
        find.descendant(of: find.byKey(const ValueKey('color-recommended-8')), matching: find.byType(Icon)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('color-recommended-0')));
      await tester.pumpAndSettle();
      expect(changes.last, LiveTheme.brandBlue);
      expect(find.text('#2E6FE0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('color-shade-0')));
      await tester.pumpAndSettle();
      expect(changes.last.computeLuminance(), greaterThan(LiveTheme.brandBlue.computeLuminance()));

      await tester.tap(find.byKey(const ValueKey('color-tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('color-accent-0')));
      await tester.pumpAndSettle();
      expect(changes.last, Color(Colors.accents.first.toARGB32()));

      await tester.enterText(find.byKey(const ValueKey('color-code')), '#12');
      expect(key.currentState!.commit(), isNull);
      await tester.pump();
      expect(find.text('代码不对'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('color-code')), '0x009688');
      expect(key.currentState!.commit(), const Color(0xFF009688));
    });

    testWidgets('the wheel and the opacity', (tester) async {
      final changes = <Color>[];
      await _pump(
        tester,
        LiveColorPicker(color: const Color(0x802196F3), opacity: true, labels: labels, onChanged: changes.add),
      );
      expect(find.text('0x802196F3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('color-tab-3')));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('color-wheel-square'))) + const Offset(2, 2));
      await tester.pumpAndSettle();
      // Top left of the square: white.
      expect(changes.last.computeLuminance(), greaterThan(0.9));
      await tester.drag(find.byKey(const ValueKey('color-opacity')), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(changes.last.a, lessThan(0.1));
    });

    test('codes', () {
      expect(parseColorCode('2196F3'), LiveTheme.legacyBlue);
      expect(parseColorCode('#802196F3'), LiveTheme.legacyBlue);
      expect(parseColorCode('#802196F3', opacity: true), const Color(0x802196F3));
      expect(parseColorCode('xyz'), isNull);
      expect(formatColorCode(LiveTheme.brandBlue), '#2E6FE0');
      expect(formatColorCode(LiveTheme.brandBlue, opacity: true), '0xFF2E6FE0');
      expect(LivePalettes.recommended.first.$2, LiveTheme.brandBlue);
      expect(LivePalettes.recommended, hasLength(15));
      expect(LivePalettes.shadesOf(LiveTheme.brandBlue), hasLength(10));
      expect(LivePalettes.shadesOf(LiveTheme.brandBlue)[5], LiveTheme.brandBlue);
    });
  });

  group('theme (U.6b C-3, C-4, C-5)', () {
    test('fidelity keeps the chosen colour as the primary; the brand blue reads with white text', () {
      const theme = LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity);
      final light = theme.light.colorScheme;
      expect(_contrast(light.primary, light.onPrimary), greaterThanOrEqualTo(4.5));
      // Tonal spot turned 3.x's blue grey (#36618E); fidelity stays close.
      final hue = HSVColor.fromColor(light.primary).hue;
      expect((hue - HSVColor.fromColor(LiveTheme.brandBlue).hue).abs(), lessThan(10));
      final tonal = const LiveTheme(primaryColor: LiveTheme.legacyBlue).light.colorScheme.primary;
      expect(HSVColor.fromColor(tonal).saturation, lessThan(HSVColor.fromColor(light.primary).saturation));
    });

    test('pure black darkens only the dark theme', () {
      const theme = LiveTheme(primaryColor: LiveTheme.brandBlue, pureBlack: true);
      expect(theme.dark.colorScheme.surface, LivePureBlack.surface);
      expect(theme.dark.colorScheme.surfaceContainerLow, LivePureBlack.containerLow);
      expect(theme.dark.scaffoldBackgroundColor, LivePureBlack.surface);
      expect(theme.light.colorScheme.surface, isNot(LivePureBlack.surface));
      final dynamic = LiveTheme(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
        pureBlack: true,
      );
      expect(dynamic.dark.colorScheme.surface, LivePureBlack.surface);
      expect(theme, const LiveTheme(primaryColor: LiveTheme.brandBlue, pureBlack: true));
      expect(theme == const LiveTheme(primaryColor: LiveTheme.brandBlue), isFalse);
    });

    test("the app's text size multiplies the system's", () {
      const scaler = AppTextScaler(TextScaler.linear(1.3), 1.5);
      expect(scaler.scale(10), closeTo(19.5, 1e-9));
      expect(const AppTextScaler(TextScaler.noScaling, 0.5).scale(20), 10);
      expect(scaler, const AppTextScaler(TextScaler.linear(1.3), 1.5));
    });
  });
}
