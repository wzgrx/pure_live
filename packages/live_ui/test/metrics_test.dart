// A01.2: the corner radii and durations are named once (AppRadii,
// AppDurations) with the values the theme had; text takes its size from the
// five font roles, so the font settings reach every title and row.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_ui/src/widgets/anchored_menu.dart';

/// Every font setting at its largest (Settings.fontSize*: 15, 17, 18, 20, 26).
const _largest = LiveFontSizes(bodySmall: 15, bodyMedium: 17, bodyLarge: 18, titleMedium: 20, titleLarge: 26);

double _size(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!.fontSize!;

Future<void> _pump(WidgetTester tester, {LiveFontSizes sizes = const LiveFontSizes(), bool tv = false}) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: LiveTheme(primaryColor: LiveTheme.brandBlue, fontSizes: sizes).light,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: settingsPageAppBar(context, title: '页面标题'),
          body: SettingsRowStyle(
            tv: tv,
            child: ListView(
              children: [
                const PageTitle(title: '标题栏标题'),
                const PanelHeader(title: '面板标题'),
                SettingsLinkRow(title: '行标题', subtitle: 'Note', value: '行的值', onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the theme takes its corners from AppRadii, with the values it had', () {
    final theme = const LiveTheme(primaryColor: LiveTheme.brandBlue).light;
    RoundedRectangleBorder rounded(double radius) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    expect(theme.dialogTheme.shape, rounded(24));
    expect(theme.cardTheme.shape, rounded(16));
    expect(theme.listTileTheme.shape, rounded(12));
    expect(theme.snackBarTheme.shape, rounded(8));
    expect(theme.chipTheme.shape, rounded(8));
    expect(
      theme.bottomSheetTheme.shape,
      const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    );
    expect(theme.elevatedButtonTheme.style!.shape!.resolve({}), rounded(12));
    expect(theme.textButtonTheme.style!.shape!.resolve({}), rounded(8));
    expect((theme.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, BorderRadius.circular(12));
    expect(theme.tabBarTheme.splashBorderRadius, BorderRadius.circular(8));
    expect(AppRadii.menu, BorderRadius.circular(8));
    expect(AppRadii.panelSide, const BorderRadius.horizontal(left: Radius.circular(16)));
  });

  test('durations: 100, 150, 200 and 300 ms; a small menu closes faster than it opens', () {
    expect(AppDurations.instant, const Duration(milliseconds: 100));
    expect(AppDurations.fast, const Duration(milliseconds: 150));
    expect(AppDurations.normal, const Duration(milliseconds: 200));
    expect(AppDurations.slow, const Duration(milliseconds: 300));
    expect(anchoredMenuOpenDuration, AppDurations.fast);
    expect(anchoredMenuCloseDuration, lessThan(anchoredMenuOpenDuration));
  });

  test('weights are 400 and 600 only (UI.md §8.2)', () {
    final text = const LiveTheme(primaryColor: LiveTheme.brandBlue).light.textTheme;
    for (final style in [
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(style!.fontWeight ?? FontWeight.w400, anyOf(FontWeight.w400, FontWeight.w600));
    }
  });

  testWidgets('by default the titles and rows keep their sizes', (tester) async {
    await _pump(tester);
    expect(_size(tester, '页面标题'), 20);
    expect(_size(tester, '标题栏标题'), 17);
    expect(_size(tester, '面板标题'), 17);
    expect(_size(tester, '行标题'), 15);
    expect(_size(tester, 'Note'), 12);
    expect(_size(tester, '行的值'), 14);
  });

  testWidgets('the largest font settings make them all larger, in proportion', (tester) async {
    await _pump(tester, sizes: _largest);
    expect(_size(tester, '页面标题'), 26);
    expect(_size(tester, '标题栏标题'), closeTo(26 * 17 / 20, 1e-9));
    expect(_size(tester, '面板标题'), closeTo(20 * 17 / 15, 1e-9));
    expect(_size(tester, '行标题'), 20);
    expect(_size(tester, 'Note'), 15);
    expect(_size(tester, '行的值'), 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the TV rows stay one step larger and follow the settings too', (tester) async {
    await _pump(tester, tv: true);
    expect(_size(tester, '行标题'), closeTo(17, 1e-9));
    expect(_size(tester, 'Note'), closeTo(14, 1e-9));
    expect(_size(tester, '行的值'), closeTo(16, 1e-9));
    await _pump(tester, sizes: _largest, tv: true);
    expect(_size(tester, '行标题'), closeTo(20 * 17 / 15, 1e-9));
    expect(_size(tester, 'Note'), closeTo(15 * 14 / 12, 1e-9));
    expect(_size(tester, '行的值'), closeTo(18 * 16 / 14, 1e-9));
  });
}
