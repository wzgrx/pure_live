import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

import 'symbols_font.dart';

void main() {
  setUpAll(loadSymbolsFont);

  /// The [Icon] a [LiveIcon] built, pumped under [theme] inside [wrap].
  Future<Icon> iconOf(
    WidgetTester tester,
    LiveIcon icon, {
    ThemeData? theme,
    Widget Function(Widget child)? wrap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? PureTheme.of(Appearance.light, platform: TargetPlatform.android),
        home: Scaffold(body: Center(child: (wrap ?? (child) => child)(icon))),
      ),
    );
    return tester.widget<Icon>(find.descendant(of: find.byWidget(icon), matching: find.byType(Icon)));
  }

  group('axes (principles §2.6)', () {
    testWidgets('light: fill 0, weight 400, grade 0, optical size 24', (tester) async {
      final icon = await iconOf(tester, const LiveIcon(LiveIcons.follow));
      expect((icon.fill, icon.weight, icon.grade, icon.opticalSize, icon.size), (0, 400, 0, 24, 24));
    });

    testWidgets('dark and pure black: grade -25', (tester) async {
      for (final appearance in [Appearance.dark, Appearance.black]) {
        final icon = await iconOf(tester, const LiveIcon(LiveIcons.follow), theme: PureTheme.of(appearance));
        expect(icon.grade, -25, reason: '$appearance');
        expect(icon.weight, 400);
      }
    });

    testWidgets('on, selected, followed, muted: fill 1 with the same glyph', (tester) async {
      final off = await iconOf(tester, const LiveIcon(LiveIcons.mute, filled: false));
      final on = await iconOf(tester, const LiveIcon(LiveIcons.mute, filled: true));
      expect((off.fill, on.fill), (0, 1));
      expect(on.icon, off.icon);
    });

    testWidgets('the optical size follows the size shown: 20, 24, 32, 40, 48', (tester) async {
      for (final size in [Sizes.iconDense, Sizes.iconMd, Sizes.iconLg, Sizes.iconXl, Sizes.iconXxl]) {
        final icon = await iconOf(tester, LiveIcon(LiveIcons.search, size: size));
        expect((icon.size, icon.opticalSize), (size, size));
      }
      // Smaller icons (inside a badge) use the smallest optical size.
      expect((await iconOf(tester, const LiveIcon(LiveIcons.audience, size: 12))).opticalSize, 20);
    });

    testWidgets('an icon button passes its size on: 32 dp on TV', (tester) async {
      final icon = await iconOf(
        tester,
        const LiveIcon(LiveIcons.refresh),
        theme: PureTheme.tv(Appearance.dark),
        wrap: (child) => IconButton(onPressed: () {}, icon: child),
      );
      expect((icon.size, icon.opticalSize, icon.grade), (32, 32, -25));
    });

    testWidgets('controls on a picture: weight 500 and grade 0 in every theme, 24 or 32 dp', (tester) async {
      for (final appearance in Appearance.values) {
        final icon = await iconOf(
          tester,
          const LiveIcon(LiveIcons.fullscreen),
          theme: PureTheme.of(appearance),
          wrap: (child) => VideoControlIcons(
            size: Sizes.iconLg,
            child: IconButton(onPressed: () {}, icon: child),
          ),
        );
        expect((icon.weight, icon.grade, icon.size, icon.opticalSize, icon.color), (500, 0, 32, 32, null));
        final color = tester.widget<RichText>(find.byType(RichText).last).text.style!.color;
        expect(color, Colors.white, reason: '$appearance');
      }
    });

    testWidgets('a component that replaces the icon theme keeps the dark grade (the rail)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.dark),
          home: Scaffold(
            body: NavigationRail(
              selectedIndex: 0,
              destinations: const [
                NavigationRailDestination(
                  icon: LiveIcon(LiveIcons.follows),
                  selectedIcon: LiveIcon(LiveIcons.follows, filled: true),
                  label: Text('a'),
                ),
                NavigationRailDestination(icon: LiveIcon(LiveIcons.discover), label: Text('b')),
              ],
            ),
          ),
        ),
      );
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect([for (final icon in icons) (icon.fill, icon.grade)], [(1, -25), (0, -25)]);
    });

    testWidgets('the back button Material builds shows the Symbols glyph', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar()))),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((widget) => widget is LiveIcon && widget.icon == LiveIcons.back), findsOneWidget);
    });

    testWidgets('a checked menu item shows the Symbols check on the chosen entry only', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: Scaffold(
            body: PopupMenuButton<int>(
              icon: const LiveIcon(LiveIcons.more),
              itemBuilder: (context) => [
                const CheckedMenuItem(value: 1, checked: true, child: Text('one')),
                const CheckedMenuItem(value: 2, checked: false, child: Text('two')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      final check = find.byWidgetPredicate((widget) => widget is LiveIcon && widget.icon == LiveIcons.check);
      expect(check, findsOneWidget);
      expect(find.ancestor(of: check, matching: find.widgetWithText(CheckedMenuItem<int>, 'one')), findsOneWidget);
      expect(find.byType(Icon), findsNWidgets(2), reason: 'the menu button and the check, both Symbols');
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        expect(icon.icon!.fontFamily, 'MaterialSymbolsRounded');
      }
    });

    test('the stroke model matches the font within 0.01 grid units', () {
      // (weight, grade, optical size, stroke on the 24 dp grid), measured
      // from MaterialSymbolsRounded 2.960 (drawn_glyphs.dart).
      const measured = [
        (400.0, 0.0, 20.0, 1.8),
        (400.0, 0.0, 24.0, 2.0),
        (400.0, 0.0, 32.0, 1.833),
        (400.0, 0.0, 48.0, 1.5),
        (400.0, -25.0, 24.0, 1.75),
        (400.0, -25.0, 48.0, 1.375),
        (500.0, 0.0, 24.0, 2.275),
        (500.0, 0.0, 32.0, 2.084),
        (500.0, -25.0, 24.0, 2.025),
        (500.0, -25.0, 40.0, 1.727),
      ];
      for (final (weight, grade, opsz, stroke) in measured) {
        expect(symbolStroke(weight: weight, grade: grade, opticalSize: opsz), closeTo(stroke, 0.01));
      }
    });
  });

  group('the catalog', () {
    test('every icon is a Rounded glyph of the Symbols font or a drawn glyph', () {
      for (final icon in LiveIcons.values) {
        expect((icon.glyph == null) != (icon.outline == null), isTrue, reason: icon.name);
        if (icon.glyph case final glyph?) {
          expect((glyph.fontFamily, glyph.fontPackage), ('MaterialSymbolsRounded', 'material_symbols_icons'));
        }
      }
    });

    test("the README's table lists every icon once", () {
      final readme = File('README.md').readAsStringSync();
      final rows = RegExp(r'^\| `(\w+)` \|', multiLine: true).allMatches(readme).map((m) => m[1]).toList();
      expect(rows, [for (final icon in LiveIcons.values) icon.name]);
    });

    testWidgets('a drawn glyph is a leaf of the given size with the semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: const Center(child: LiveIcon(LiveIcons.danmaku, size: 32, semanticLabel: '弹幕')),
        ),
      );
      expect(tester.getSize(find.byType(LiveIcon)), const Size.square(32));
      expect(find.bySemanticsLabel('弹幕'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      handle.dispose();
    });

    test('the danmaku glyph: 2 dp strokes inside 2–22 × 3–21, the fill only cuts the lines out', () {
      final outlined = LiveIcons.danmaku.outline!(2, filled: false);
      final filled = LiveIcons.danmaku.outline!(2, filled: true);
      expect(outlined.getBounds(), const Rect.fromLTRB(2, 3, 22, 21));
      expect(filled.getBounds(), outlined.getBounds());
      // The frame is a 2 dp stroke; inside it the outlined glyph is empty
      // and the filled one solid, except on the lines.
      expect(outlined.contains(const Offset(2.5, 12)), isTrue);
      expect(outlined.contains(const Offset(4.5, 12)), isFalse);
      expect(filled.contains(const Offset(4.5, 12)), isTrue);
      for (final line in const [Offset(17.5, 8), Offset(6.5, 12), Offset(13, 16)]) {
        expect(outlined.contains(line), isTrue);
        expect(filled.contains(line), isFalse);
      }
    });
  });

  // Pixel-exact goldens are made on Linux (WSL); other hosts rasterise
  // antialiased edges a little differently.
  testWidgets(
    'fill 0 and 1 in light (grade 0) and dark (grade -25), sizes and the controls (golden)',
    skip: !Platform.isLinux,
    (tester) async {
      tester.view
        ..physicalSize = const Size(560, 720) * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      const toggles = [
        LiveIcons.follows,
        LiveIcons.danmaku,
        LiveIcons.mute,
        LiveIcons.alerts,
        LiveIcons.audioOnly,
        LiveIcons.chatPanel,
        LiveIcons.lock,
        LiveIcons.star,
        LiveIcons.record,
        LiveIcons.search,
      ];
      Widget row(List<Widget> icons) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [for (final icon in icons) SizedBox(width: 52, child: Center(child: icon))],
        ),
      );
      Widget half(Appearance appearance) => Theme(
        data: PureTheme.of(appearance, platform: TargetPlatform.android),
        child: Builder(
          builder: (context) => Material(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row([for (final icon in toggles) LiveIcon(icon, filled: false)]),
                  row([for (final icon in toggles) LiveIcon(icon, filled: true)]),
                  row([
                    for (final size in [Sizes.iconDense, Sizes.iconMd, Sizes.iconLg, Sizes.iconXl, Sizes.iconXxl])
                      LiveIcon(LiveIcons.danmaku, size: size),
                    for (final size in [Sizes.iconDense, Sizes.iconMd, Sizes.iconLg, Sizes.iconXl, Sizes.iconXxl])
                      LiveIcon(LiveIcons.subpage, size: size),
                  ]),
                  ColoredBox(
                    color: VideoBarScrim.color,
                    child: VideoControlIcons(
                      size: Sizes.iconLg,
                      child: row([
                        const LiveIcon(LiveIcons.play),
                        const LiveIcon(LiveIcons.refresh),
                        const LiveIcon(LiveIcons.danmaku, filled: true),
                        const LiveIcon(LiveIcons.danmaku),
                        const LiveIcon(LiveIcons.tune),
                        const LiveIcon(LiveIcons.mute, filled: true),
                        const LiveIcon(LiveIcons.audioOnly),
                        const LiveIcon(LiveIcons.pip),
                        const LiveIcon(LiveIcons.fullscreen),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(_Crop(children: [half(Appearance.light), half(Appearance.dark)]));
      await expectLater(find.byKey(_Crop.area), matchesGoldenFile('goldens/icon_axes.png'));
    },
  );

  testWidgets('every icon in light and dark (golden)', skip: !Platform.isLinux, (tester) async {
    const columns = 16;
    final rows = (LiveIcons.values.length / columns).ceil();
    tester.view
      ..physicalSize = Size(columns * 40.0 + 16, (rows * 40.0 + 16) * 2) * 1.5
      ..devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    Widget half(Appearance appearance) => Theme(
      data: PureTheme.of(appearance, platform: TargetPlatform.android),
      child: Builder(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: columns * 40,
              child: Wrap(
                children: [
                  for (final icon in LiveIcons.values)
                    SizedBox.square(dimension: 40, child: Center(child: LiveIcon(icon))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(_Crop(children: [half(Appearance.light), half(Appearance.dark)]));
    await expectLater(find.byKey(_Crop.area), matchesGoldenFile('goldens/icon_catalog.png'));
  });
}

/// [children] in a column at the top left, as small as they are, in their
/// own layer so a golden holds just them.
class _Crop extends StatelessWidget {
  const new({required this.children});

  static const Key area = ValueKey('crop');

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: area,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}
