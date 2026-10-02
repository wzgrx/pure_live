import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// The small menu next to its button (docs/A-界面设计/A02-组件/A02.3-贴着按钮的小菜单/brief.md): where it goes
// by its measured height, which way it unfolds, scrolling and keys, on a
// landscape phone (852 × 393), a portrait phone (393 × 852) and a tablet
// (1280 × 800).

const List<String> _qualities = ['原画', '蓝光8M', '蓝光4M', '蓝光', '超清', '高清', '流畅'];

const Size _landscape = Size(852, 393);
const Size _portrait = Size(393, 852);
const Size _tablet = Size(1280, 800);

Finder _item(int index) => find.byKey(ValueKey('stream-menu-item-$index'));

/// The menu's surface.
Finder get _menu => find.ancestor(of: _item(0), matching: find.byType(Material)).first;

/// The button's outline (the 32-high chip inside its 48-high tap area).
Finder get _chip => find.descendant(of: find.byType(StreamMenuButton), matching: find.byType(DecoratedBox)).first;

/// A 56-high bar with the button at [at]: along the bottom (the fullscreen
/// bar) or, with [top], 120 from the top (the portrait info row).
Future<List<int>> _bar(
  WidgetTester tester, {
  Size size = _landscape,
  int count = 7,
  int current = 0,
  bool preferAbove = true,
  Alignment at = const Alignment(0.6, 0),
  double? top,
  bool reduceMotion = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final chosen = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              height: 56,
              top: top,
              bottom: top == null ? 0 : null,
              child: Align(
                alignment: at,
                // In a row, as in the bars (the button takes its own width).
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StreamMenuButton(
                      label: _qualities[current],
                      entries: _qualities.take(count).toList(),
                      current: current,
                      onSelected: chosen.add,
                      tooltip: '清晰度',
                      onVideo: true,
                      preferAbove: preferAbove,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return chosen;
}

/// What of [finder]'s box is painted: its rectangle cut by every clip above it.
Rect _visible(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  var rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  RenderObject child = box;
  for (var parent = box.parent; parent != null; parent = parent.parent) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null && parent is RenderBox) {
      rect = rect.intersect(MatrixUtils.transformRect(parent.getTransformTo(null), clip));
    }
    child = parent;
  }
  return rect;
}

/// The opacity the menu is painted with.
double _opacity(WidgetTester tester) {
  var opacity = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
    find.ancestor(of: _menu, matching: find.byType(FadeTransition)),
  )) {
    opacity *= fade.opacity.value;
  }
  return opacity;
}

void main() {
  group('landscape phone 852 × 393, the fullscreen bar', () {
    testWidgets('seven qualities: above the button by their measured height, 4 apart, scrolling in the room there', (
      tester,
    ) async {
      final chosen = await _bar(tester);
      final chip = tester.getRect(_chip);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      final menu = tester.getRect(_menu);
      expect(menu.bottom, moreOrLessEquals(chip.top - 4, epsilon: 0.5), reason: 'right above the button');
      expect(menu.top, greaterThanOrEqualTo(8), reason: 'inside the screen');
      final scroll = tester.state<ScrollableState>(find.descendant(of: _menu, matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(0), reason: 'the rows past the room scroll');

      await tester.drag(_menu, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(_menu), menu, reason: 'scrolling does not move the menu');
      expect(tester.getRect(_item(6)).bottom, lessThanOrEqualTo(menu.bottom));
      await tester.tap(_item(6));
      await tester.pumpAndSettle();
      expect(chosen, [6]);
      expect(_item(0), findsNothing);
    });

    testWidgets('three lines: above the button, 4 apart, lined up with its right edge (the nearer screen edge)', (
      tester,
    ) async {
      await _bar(tester, count: 3);
      final chip = tester.getRect(_chip);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      final menu = tester.getRect(_menu);
      expect(menu.bottom, moreOrLessEquals(chip.top - 4, epsilon: 0.5));
      expect(menu.right, moreOrLessEquals(chip.right, epsilon: 0.5));
      expect(menu.height, 3 * 48 + 16, reason: 'no scrolling: as high as its rows');
    });

    testWidgets('it unfolds from the button: upwards from below, fading in, in about 150 ms', (tester) async {
      await _bar(tester, count: 3);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = _visible(tester, _menu);
      final fading = _opacity(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final full = tester.getRect(_menu);
      expect(_visible(tester, _menu), full, reason: 'open after 160 ms');
      expect(_opacity(tester), 1);
      expect(mid.bottom, moreOrLessEquals(full.bottom, epsilon: 0.5), reason: 'the edge at the button stays');
      expect(mid.top, greaterThan(full.top + 8), reason: 'the far edge moves up');
      expect(fading, inExclusiveRange(0, 1));
    });

    testWidgets('reduced motion: the whole menu in the first frame', (tester) async {
      await _bar(tester, count: 3, reduceMotion: true);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pump();
      final full = tester.getRect(_menu);
      expect(_visible(tester, _menu), full);
      expect(_opacity(tester), 1);
      expect(full.bottom, moreOrLessEquals(tester.getRect(_chip).top - 4, epsilon: 0.5));
    });

    testWidgets('a long list opens with the current entry in view', (tester) async {
      await _bar(tester, current: 6);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      final menu = tester.getRect(_menu);
      final current = tester.getRect(_item(6));
      expect(current.top, greaterThanOrEqualTo(menu.top));
      expect(current.bottom, lessThanOrEqualTo(menu.bottom));
    });

    testWidgets('a titled menu with a line under each entry: above by its measured height', (tester) async {
      tester.view
        ..physicalSize = _portrait
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: Builder(
                builder: (anchor) => IconButton(
                  key: const ValueKey('mode'),
                  icon: const Icon(Icons.aspect_ratio),
                  onPressed: () async => chosen = await showSmallMenu(
                    anchor,
                    title: '竖屏全屏画面模式',
                    entries: const ['沉浸背景', '适应', '填充', '裁剪'],
                    descriptions: const ['画面上下用模糊的画面填满', '完整保留直播内容，空白区域保持纯色', '拉伸到整个屏幕', '铺满整个屏幕，可能裁掉左右部分内容'],
                    current: 0,
                    entryKey: 'mode',
                    preferAbove: true,
                    width: 340,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final button = tester.getRect(find.byKey(const ValueKey('mode')));
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();
      final menu = tester.getRect(
        find.ancestor(of: find.byKey(const ValueKey('mode-0')), matching: find.byType(Material)).first,
      );
      expect(menu.bottom, moreOrLessEquals(button.top - 4, epsilon: 0.5));
      expect(menu.width, 340);
      expect(menu.right, moreOrLessEquals(_portrait.width - 8, epsilon: 0.5), reason: '8 inside the screen');
      expect(find.byKey(const ValueKey('small-menu-title')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mode-3')));
      await tester.pumpAndSettle();
      expect(chosen, 3);
    });
  });

  testWidgets('turning the screen closes the menu (its button moved)', (tester) async {
    final chosen = await _bar(tester, count: 3);
    await tester.tap(find.byType(StreamMenuButton));
    await tester.pumpAndSettle();
    expect(_item(0), findsOneWidget);
    tester.view.physicalSize = _portrait;
    await tester.pumpAndSettle();
    expect(_item(0), findsNothing);
    expect(chosen, isEmpty);
    await tester.tap(find.byType(StreamMenuButton));
    await tester.pumpAndSettle();
    expect(_item(0), findsOneWidget, reason: 'it opens again');
  });

  testWidgets('the app menu (showAppMenu) the same way: above a button low on a landscape phone, scrolling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = _landscape
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Align(
            alignment: const Alignment(-0.8, 0.9),
            child: Builder(
              builder: (anchor) => IconButton(
                key: const ValueKey('fit'),
                icon: const Icon(Icons.aspect_ratio),
                onPressed: () async => chosen = await showAppMenu<int>(
                  anchor,
                  preferAbove: true,
                  selected: 7,
                  entries: [
                    for (var i = 0; i < 8; i++) AppMenuEntry(key: ValueKey('fit-$i'), value: i, label: '比例 $i'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byKey(const ValueKey('fit')));
    await tester.tap(find.byKey(const ValueKey('fit')));
    await tester.pumpAndSettle();
    final menu = tester.getRect(
      find.ancestor(of: find.byKey(const ValueKey('fit-0')), matching: find.byType(Material)).first,
    );
    expect(menu.bottom, moreOrLessEquals(button.top - appMenuGap, epsilon: 0.5));
    expect(menu.top, greaterThanOrEqualTo(8));
    expect(menu.left, moreOrLessEquals(button.left, epsilon: 0.5), reason: 'lined up with its left edge');
    final current = tester.getRect(find.byKey(const ValueKey('fit-7')));
    expect(current.bottom, lessThanOrEqualTo(menu.bottom), reason: 'the current entry scrolled into view');
    await tester.tap(find.byKey(const ValueKey('fit-7')));
    await tester.pumpAndSettle();
    expect(chosen, 7);
  });

  group('portrait phone 393 × 852, the info row', () {
    testWidgets('opens below the button, unfolding downwards, lined up with its left edge', (tester) async {
      await _bar(tester, size: _portrait, count: 3, preferAbove: false, top: 220, at: const Alignment(-0.6, 0));
      final chip = tester.getRect(_chip);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = _visible(tester, _menu);
      await tester.pumpAndSettle();
      final full = tester.getRect(_menu);
      expect(full.top, moreOrLessEquals(chip.bottom + 4, epsilon: 0.5));
      expect(full.left, moreOrLessEquals(chip.left, epsilon: 0.5));
      expect(mid.top, moreOrLessEquals(full.top, epsilon: 0.5), reason: 'the edge at the button stays');
      expect(mid.bottom, lessThan(full.bottom - 8), reason: 'the far edge moves down');
    });

    testWidgets('keys: arrows move, Enter picks; Back and Esc close without a choice', (tester) async {
      final chosen = await _bar(tester, size: _portrait, count: 3, preferAbove: false, top: 220);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, [1]);
      expect(_item(0), findsNothing);

      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_item(0), findsNothing, reason: 'Back closes it');

      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_item(0), findsNothing, reason: 'Esc closes it');
      expect(chosen, [1]);
    });
  });

  group('tablet 1280 × 800', () {
    testWidgets('below when it fits there', (tester) async {
      await _bar(tester, size: _tablet, preferAbove: false, top: 300);
      final chip = tester.getRect(_chip);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      final menu = tester.getRect(_menu);
      expect(menu.top, moreOrLessEquals(chip.bottom + 4, epsilon: 0.5));
      expect(menu.height, 7 * 48 + 16);
    });

    testWidgets('above when only the space above takes it', (tester) async {
      await _bar(tester, size: _tablet, preferAbove: false, top: 560);
      final chip = tester.getRect(_chip);
      await tester.tap(find.byType(StreamMenuButton));
      await tester.pumpAndSettle();
      final menu = tester.getRect(_menu);
      expect(menu.bottom, moreOrLessEquals(chip.top - 4, epsilon: 0.5));
      expect(menu.height, 7 * 48 + 16);
    });
  });
}
