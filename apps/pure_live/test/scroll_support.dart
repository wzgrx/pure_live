// A11.6: reading and moving a list's scroll position in the tests that check
// a list is where it was after a page over it closes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scroll position of the first list in [list] (the list itself or a
/// widget around it).
ScrollPosition scrollPositionOf(WidgetTester tester, Finder list) =>
    tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position;

/// Drags [list] up by [by] (as a finger does, so the position is remembered
/// when it comes to rest) and returns where it stopped, above 0.
Future<double> scrollDown(WidgetTester tester, Finder list, double by) async {
  await tester.drag(list, Offset(0, -by));
  await tester.pumpAndSettle();
  final pixels = scrollPositionOf(tester, list).pixels;
  expect(pixels, greaterThan(0), reason: 'the list scrolled');
  return pixels;
}
