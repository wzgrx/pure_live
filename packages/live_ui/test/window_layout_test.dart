import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// A04.1 (docs/A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配): height classes,
// a phone's split screen, a foldable's hinge and the text size limit
// (research V03.2 §3.3 D1, D3).

void _view(WidgetTester tester, Size size, {List<DisplayFeature> features = const []}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..displayFeatures = features;
  addTearDown(tester.view.reset);
}

/// A fold down the middle of a window [width] wide and [height] high, half
/// open like a book.
DisplayFeature _bookFold(double width, double height) => DisplayFeature(
  bounds: Rect.fromLTWH(width / 2, 0, 0, height),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

void main() {
  test('height classes: compact below 480, medium below 900, expanded from 900', () {
    expect(WindowHeightClass.of(0), WindowHeightClass.compact);
    expect(WindowHeightClass.of(479.9), WindowHeightClass.compact);
    expect(WindowHeightClass.of(480), WindowHeightClass.medium);
    expect(WindowHeightClass.of(899.9), WindowHeightClass.medium);
    expect(WindowHeightClass.of(900), WindowHeightClass.expanded);
    expect(windowCompactHeight, 480);
    expect(windowExpandedHeight, 900);
  });

  test("the research's sizes: only a short and not narrow window is a landscape phone", () {
    const compact = WindowWidthClass.compact;
    const medium = WindowWidthClass.medium;
    const expanded = WindowWidthClass.expanded;
    const large = WindowWidthClass.large;
    const short = WindowHeightClass.compact;
    const mid = WindowHeightClass.medium;
    const tall = WindowHeightClass.expanded;
    final cases = <Size, (WindowClass, bool)>{
      // A small free window.
      const Size(360, 400): (const WindowClass(compact, short), false),
      // A phone's split screen: short, but laid out upright.
      const Size(400, 420): (const WindowClass(compact, short), false),
      // K90 upright, and sideways less the camera hole (not "expanded").
      const Size(400, 869): (const WindowClass(compact, mid), false),
      const Size(821, 400): (const WindowClass(medium, short), true),
      // A 720p phone sideways.
      const Size(800, 360): (const WindowClass(medium, short), true),
      // A phone held sideways split in two: short, too narrow to be one.
      const Size(410, 392): (const WindowClass(compact, short), false),
      const Size(599, 400): (const WindowClass(compact, short), false),
      const Size(600, 479): (const WindowClass(medium, short), true),
      const Size(600, 480): (const WindowClass(medium, mid), false),
      // A foldable's inner screen, both ways.
      const Size(673, 841): (const WindowClass(medium, mid), false),
      const Size(841, 673): (const WindowClass(expanded, mid), false),
      // Tablets.
      const Size(1280, 800): (const WindowClass(large, mid), false),
      const Size(1500, 1000): (const WindowClass(large, tall), false),
    };
    for (final MapEntry(key: size, value: (classes, landscape)) in cases.entries) {
      expect(WindowClass.of(size), classes, reason: '$size');
      expect(WindowClass.of(size).isPhoneLandscape, landscape, reason: '$size');
      expect(WindowClass.of(size).isShort, size.height < 480, reason: '$size');
    }
  });

  testWidgets('the scope reads the area it is given, not the screen; dependents rebuild on a new class only', (
    tester,
  ) async {
    _view(tester, const Size(821, 869));
    final box = ValueNotifier(const Size(400, 420));
    addTearDown(box.dispose);
    final seen = <WindowClass>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder(
            valueListenable: box,
            builder: (context, size, child) => SizedBox.fromSize(size: size, child: child),
            child: WindowClassScope(
              child: Builder(
                builder: (context) {
                  seen.add(WindowClassScope.of(context));
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(seen, [const WindowClass(WindowWidthClass.compact, WindowHeightClass.compact)]);
    // Within the same classes: no rebuild.
    box.value = const Size(420, 440);
    await tester.pump();
    expect(seen, hasLength(1));
    box.value = const Size(821, 400);
    await tester.pump();
    expect(seen.last, const WindowClass(WindowWidthClass.medium, WindowHeightClass.compact));
    expect(seen.last.isPhoneLandscape, isTrue);
  });

  testWidgets('without a scope: the window; app bars are 48 high in a short area, 56 otherwise', (tester) async {
    _view(tester, const Size(821, 400));
    late BuildContext bare;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          bare = context;
          return const SizedBox.shrink();
        },
      ),
    );
    expect(WindowClassScope.of(bare).isPhoneLandscape, isTrue);
    expect(WindowClassScope.toolbarHeightOf(bare), compactToolbarHeight);

    for (final (size, height) in [(const Size(400, 420), 48.0), (const Size(400, 869), 56.0)]) {
      _view(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: WindowClassScope(
            child: Builder(
              builder: (context) => Scaffold(appBar: settingsPageAppBar(context, title: '设置')),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppBar)).height, height, reason: '$size');
    }
  });

  testWidgets("a page's state lies on its side on a landscape phone, not in a phone's split screen", (tester) async {
    for (final (size, sideways) in [(const Size(821, 400), true), (const Size(400, 420), false)]) {
      _view(tester, size);
      await tester.pumpWidget(
        const MaterialApp(
          home: WindowClassScope(
            child: Scaffold(
              body: AppStatusView(type: AppStatusType.empty, title: '空', subtitle: '没有内容'),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('空')).textAlign,
        sideways ? TextAlign.start : TextAlign.center,
        reason: '$size',
      );
    }
  });

  group('fold and hinge', () {
    const window = Size(673, 841);

    test('a half open fold or a hinge splits the window; a flat fold and the camera hole do not', () {
      const flat = DisplayFeature(
        bounds: Rect.fromLTWH(336.5, 0, 0, 841),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      );
      const cutout = DisplayFeature(
        bounds: Rect.fromLTWH(300, 0, 40, 40),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      );
      const hinge = DisplayFeature(
        bounds: Rect.fromLTWH(330, 0, 13, 841),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      );
      const tabletop = DisplayFeature(
        bounds: Rect.fromLTWH(0, 420, 673, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      // A half open fold that does not run across the window (another
      // window beside this one in a split screen) splits nothing here.
      const partial = DisplayFeature(
        bounds: Rect.fromLTWH(336.5, 400, 0, 200),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      expect(DisplayHinge.find([flat, cutout, partial], window), isNull);
      expect(DisplayHinge.find([cutout, _bookFold(673, 841)], window)?.vertical, isTrue);
      expect(DisplayHinge.find([hinge], window), const DisplayHinge(Rect.fromLTWH(330, 0, 13, 841)));
      expect(DisplayHinge.find([tabletop], window)?.vertical, isFalse);
    });

    test('each side of the hinge; a row split at it, or not when a pane would be too narrow', () {
      const hinge = DisplayHinge(Rect.fromLTWH(330, 0, 13, 841));
      expect(hinge.sideOf(const Offset(100, 100), window), const Rect.fromLTRB(0, 0, 330, 841));
      expect(hinge.sideOf(const Offset(500, 100), window), const Rect.fromLTRB(343, 0, 673, 841));
      const tabletop = DisplayHinge(Rect.fromLTWH(0, 420, 673, 0));
      expect(tabletop.sideOf(const Offset(100, 600), window), const Rect.fromLTRB(0, 420, 673, 841));
      expect(hinge.splitRow(left: 0, width: 673), (start: 330.0, gap: 13.0));
      // A row that starts 10 in (a safe area): the start pane is 10 shorter.
      expect(hinge.splitRow(left: 10, width: 653), (start: 320.0, gap: 13.0));
      expect(hinge.splitRow(left: 0, width: 673, minPane: 340), isNull);
      expect(tabletop.splitRow(left: 0, width: 673), isNull);
    });

    testWidgets('a small menu stays on its button’s side of the fold', (tester) async {
      _view(tester, const Size(840, 600), features: [_bookFold(840, 600)]);
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().light,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 372,
                  top: 100,
                  child: AppMenuButton<int>(
                    tooltip: '菜单',
                    icon: const Icon(Icons.menu),
                    entries: () => const [
                      AppMenuEntry(key: ValueKey('one'), value: 1, icon: Icons.settings, label: '一个很长的菜单项'),
                    ],
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('菜单'));
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byKey(const ValueKey('one')));
      expect(row.right, lessThanOrEqualTo(420));
      expect(row.top, greaterThan(148));
    });

    testWidgets('a dialog sits on one half of the fold, not across it', (tester) async {
      _view(tester, const Size(840, 600), features: [_bookFold(840, 600)]);
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold();
            },
          ),
        ),
      );
      unawaited(
        showAppDialog<void>(
          context: page,
          builder: (_) => const AppDialog(title: '标题', content: Text('内容')),
        ),
      );
      await tester.pumpAndSettle();
      final dialog = tester.getRect(find.byType(AppDialog));
      expect(dialog.right <= 420 || dialog.left >= 420, isTrue, reason: '$dialog');
    });

    testWidgets('panels open on one side of the fold: the side panel at the end, the sheet below a tabletop fold', (
      tester,
    ) async {
      _view(tester, const Size(840, 600), features: [_bookFold(840, 600)]);
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold();
            },
          ),
        ),
      );
      unawaited(showAdaptivePanel<void>(page, builder: (_) => const SizedBox.expand(key: ValueKey('content'))));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(const ValueKey('side-panel')));
      expect(panel.left, greaterThanOrEqualTo(420));
      expect(panel.right, 840);
      Navigator.of(page).pop();
      await tester.pumpAndSettle();

      tester.view.displayFeatures = [
        const DisplayFeature(
          bounds: Rect.fromLTWH(0, 300, 840, 0),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await tester.pump();
      unawaited(
        showAdaptivePanel<void>(
          page,
          side: false,
          builder: (_) => const SizedBox(key: ValueKey('content'), height: 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('content'))).top, greaterThanOrEqualTo(300));
    });
  });
}
