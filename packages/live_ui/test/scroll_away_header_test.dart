import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// principles §5.2: the top bar of landscape phones scrolls away, except
/// while it holds the actions of a mode (multi-select).
void main() {
  Widget page({required bool pinned}) => MaterialApp(
    home: Scaffold(
      body: ScrollAwayHeader(
        pinned: pinned,
        header: const SizedBox(height: 56, child: Text('顶栏')),
        body: ListView(children: [for (var i = 0; i < 60; i++) SizedBox(height: 48, child: Text('$i'))]),
      ),
    ),
  );

  double headerHeight(WidgetTester tester) => tester.getSize(find.byType(AnimatedAlign)).height;

  Future<void> scroll(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(ListView), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets('scrolling down hides it, scrolling up brings it back', (tester) async {
    await tester.pumpWidget(page(pinned: false));
    expect(headerHeight(tester), 56);
    await scroll(tester, -300);
    expect(headerHeight(tester), 0);
    await scroll(tester, 100);
    expect(headerHeight(tester), 56);
  });

  testWidgets('pinned, it stays; unpinned again, it shows until the next scroll down', (tester) async {
    await tester.pumpWidget(page(pinned: false));
    await scroll(tester, -300);
    expect(headerHeight(tester), 0);
    await tester.pumpWidget(page(pinned: true));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), 56, reason: 'pinning shows it at once');
    await scroll(tester, -300);
    expect(headerHeight(tester), 56);
    await tester.pumpWidget(page(pinned: false));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), 56);
    await scroll(tester, -300);
    expect(headerHeight(tester), 0);
  });
}
