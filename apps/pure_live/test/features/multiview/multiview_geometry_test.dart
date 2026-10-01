import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/logic/multiview_geometry.dart';

void _expect16by9(Iterable<Rect> rects) {
  for (final rect in rects) {
    expect(rect.width / rect.height, moreOrLessEquals(16 / 9, epsilon: 0.01), reason: '$rect');
  }
}

void main() {
  test('the most cells follow the device (UI_PLAN §9.3)', () {
    expect(multiviewMaxCells(mobile: true, processors: 16), 4);
    expect(multiviewMaxCells(mobile: false, processors: 8), MultiviewController.desktopMaxCells);
    expect(multiviewMaxCells(mobile: false, processors: 6), 6);
    expect(multiviewMaxCells(mobile: false, processors: 4), 4);
  });

  test('rail items in sight (3.x focus_rail_visibility)', () {
    expect(visibleRailRange(count: 5, offset: 0, viewport: 300, extent: 100), (0, 3));
    expect(visibleRailRange(count: 5, offset: 150, viewport: 300, extent: 100), (1, 5));
    expect(visibleRailRange(count: 5, offset: 0, viewport: 0, extent: 100), (0, 0));
    expect(visibleRailRange(count: 0, offset: 0, viewport: 300, extent: 100), (0, 0));
  });

  test('portrait: 16:9 cells as tall as the width wants; 1×2 one above the other (c2)', () {
    final quad = WallGeometry.of(MultiviewLayout.quad, width: 393);
    expect(quad.cells, hasLength(4));
    _expect16by9(quad.cells);
    expect(quad.cells[0].width, moreOrLessEquals((393 - 9) / 2));
    expect(quad.size.height, moreOrLessEquals(quad.cells[0].height * 2 + 9));
    expect(quad.cells[1].left, greaterThan(quad.cells[0].right));
    expect(quad.cells[2].top, greaterThan(quad.cells[0].bottom));

    final dual = WallGeometry.of(MultiviewLayout.dual, width: 393, height: 364);
    _expect16by9(dual.cells);
    expect(dual.cells[1].top, greaterThan(dual.cells[0].bottom), reason: 'above each other');
    expect(dual.cells[0].left, dual.cells[1].left);

    final focus = WallGeometry.of(MultiviewLayout.focus, width: 393);
    _expect16by9(focus.cells);
    expect(focus.cells.single.width, moreOrLessEquals(393 - 6));
    expect(focus.railVertical, isFalse);
    expect(focus.rail!.top, greaterThan(focus.cells.single.bottom));
    // Three small cells fill the rail.
    expect(focus.rail!.width, moreOrLessEquals(focus.railExtent * 3 - 3));
  });

  test('landscape: side by side; the 1+3 rail beside the large cell; centred in the area', () {
    final dual = WallGeometry.of(MultiviewLayout.dual, width: 612, height: 313);
    _expect16by9(dual.cells);
    expect(dual.cells[1].left, greaterThan(dual.cells[0].right));

    final quad = WallGeometry.of(MultiviewLayout.quad, width: 852, height: 393);
    _expect16by9(quad.cells);
    // The height decides; the sides stay black and even.
    final left = quad.cells[0].left;
    final right = 852 - quad.cells[1].right;
    expect(left, moreOrLessEquals(right));
    expect(left, greaterThan(40));

    final focus = WallGeometry.of(MultiviewLayout.focus, width: 852, height: 393);
    expect(focus.railVertical, isTrue);
    expect(focus.rail!.left, greaterThan(focus.cells.single.right));
    expect(focus.rail!.height, moreOrLessEquals(focus.cells.single.height));
    expect(focus.rail!.width / (focus.railExtent - 3), moreOrLessEquals(16 / 9, epsilon: 0.01));
  });
}
