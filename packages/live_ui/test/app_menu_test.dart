import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

const List<AppMenuEntry<int>> _entries = [
  AppMenuEntry(key: ValueKey('one'), value: 1, icon: Icons.settings, label: '设置'),
  AppMenuEntry(key: ValueKey('two'), value: 2, icon: Icons.info, label: '关于'),
];

Future<List<int>> _pump(WidgetTester tester, {required Alignment at}) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final chosen = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: Align(
          alignment: at,
          child: AppMenuButton<int>(
            tooltip: '菜单',
            icon: const Icon(Icons.menu),
            entries: () => _entries,
            onSelected: chosen.add,
          ),
        ),
      ),
    ),
  );
  return chosen;
}

void main() {
  testWidgets('the small menu: 48 rows, 24 icons in the variant colour, 14 text, 8 corners, highest container', (
    tester,
  ) async {
    final chosen = await _pump(tester, at: Alignment.topLeft);
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byKey(const ValueKey('one')))).colorScheme;
    final button = tester.getRect(find.byType(IconButton));
    final one = tester.getRect(find.byKey(const ValueKey('one')));
    final two = tester.getRect(find.byKey(const ValueKey('two')));
    expect(one.height, 48);
    expect(two.top, one.bottom);
    // Below the button, 4 apart (the menu's own 8 above the first row).
    expect(one.top, closeTo(button.bottom + appMenuGap + 8, 0.5));
    expect(one.width, greaterThanOrEqualTo(appMenuMinWidth));
    final icon = tester.widget<Icon>(find.byIcon(Icons.settings));
    expect(icon.size, 24);
    expect(icon.color, scheme.onSurfaceVariant);
    expect(tester.widget<Text>(find.text('设置')).style?.fontSize, 14);
    expect(tester.getTopLeft(find.text('设置')).dx - tester.getTopRight(find.byIcon(Icons.settings)).dx, 12);
    final material = tester.widget<Material>(
      find.ancestor(of: find.byKey(const ValueKey('one')), matching: find.byType(Material)).first,
    );
    expect(material.color, scheme.surfaceContainerHighest);
    expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(chosen, [2]);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('opens above a button at the bottom; Esc closes it without a choice', (tester) async {
    final chosen = await _pump(tester, at: Alignment.bottomRight);
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byType(IconButton));
    final two = tester.getRect(find.byKey(const ValueKey('two')));
    expect(two.bottom, lessThan(button.top));
    // Lined up with the button's right edge (within Material's 8 margin).
    expect(two.right, closeTo(math.min(button.right, 393 - 8), 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('a menu of choices marks the current one: primary, semibold, a tick at the end', (tester) async {
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen = await showAppMenu<int>(
                context,
                selected: 2,
                entries: const [
                  AppMenuEntry(key: ValueKey('a'), value: 1, label: '综合'),
                  AppMenuEntry(key: ValueKey('b'), value: 2, label: '观众优先'),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byKey(const ValueKey('b')))).colorScheme;
    final current = tester.widget<Text>(find.text('观众优先'));
    expect(current.style?.color, scheme.primary);
    expect(current.style?.fontWeight, FontWeight.w600);
    expect(tester.widget<Text>(find.text('综合')).style?.color, scheme.onSurface);
    expect(
      find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byIcon(AppIcons.selected)),
      findsOneWidget,
    );
    expect(find.byIcon(AppIcons.selected), findsOneWidget);
    expect(tester.getCenter(find.byIcon(AppIcons.selected)).dx, greaterThan(tester.getTopRight(find.text('观众优先')).dx));
    await tester.tap(find.text('综合'));
    await tester.pumpAndSettle();
    expect(chosen, 1);
  });

  testWidgets('the page title: a 17-point name over a 12-point line in the variant colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const PageTitle(title: '观看记录', subtitle: '18 / 50 条'),
          ),
        ),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(PageTitle))).colorScheme;
    final title = tester.widget<Text>(find.text('观看记录'));
    final line = tester.widget<Text>(find.text('18 / 50 条'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(line.style?.fontSize, 12);
    expect(line.style?.color, scheme.onSurfaceVariant);
    expect(tester.getTopLeft(find.text('18 / 50 条')).dx, tester.getTopLeft(find.text('观看记录')).dx);
    expect(tester.getTopLeft(find.text('18 / 50 条')).dy, greaterThan(tester.getTopLeft(find.text('观看记录')).dy));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PageTitle(title: '网页搜索')),
      ),
    );
    expect(find.byKey(const ValueKey('page-subtitle')), findsNothing);
  });

  testWidgets('a destructive row is red and set apart by a line (U.11a, U.11b file menus)', (tester) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Center(
            child: AppMenuButton<int>(
              tooltip: '菜单',
              icon: const Icon(Icons.more_vert),
              entries: () => const [
                AppMenuEntry(value: 1, icon: Icons.restore, label: '恢复全部设置'),
                AppMenuEntry(value: 2, icon: Icons.delete, label: '删除', danger: true, divider: true),
              ],
              onSelected: (value) => chosen = value,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    final error = Theme.of(tester.element(find.text('删除'))).colorScheme.error;
    expect(tester.widget<Text>(find.text('删除')).style?.color, error);
    expect(tester.widget<Icon>(find.byIcon(Icons.delete)).color, error);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PopupMenuDivider)).dy, greaterThan(tester.getTopLeft(find.text('恢复全部设置')).dy));
    expect(tester.getTopLeft(find.byType(PopupMenuDivider)).dy, lessThan(tester.getTopLeft(find.text('删除')).dy));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(chosen, 2);
  });
}
