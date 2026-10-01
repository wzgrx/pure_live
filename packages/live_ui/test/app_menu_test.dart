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
}
