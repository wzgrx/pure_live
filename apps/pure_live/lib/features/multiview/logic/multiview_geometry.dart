import 'dart:math' as math;
import 'dart:ui';

import 'package:pure_live/features/multiview/logic/multiview_controller.dart';

/// The most cells this device decodes at once (UI_PLAN §9.3: the multi-view's
/// cells follow what the device can do). Phones keep four, the size of
/// every layout (3.x); desktops get 3.x's nine with eight processors or
/// more, six with six or seven, and four below that.
int multiviewMaxCells({required bool mobile, required int processors}) {
  if (mobile) return MultiviewLayout.focus.capacity;
  if (processors >= 8) return MultiviewController.desktopMaxCells;
  if (processors >= 6) return 6;
  return MultiviewLayout.focus.capacity;
}

/// The items of a scrolling rail with some part in sight (3.x
/// `visibleFocusRailCells`): [count] items of [extent] each, scrolled by
/// [offset] in a viewport [viewport] long. Returns the first and the end
/// (exclusive) index.
(int, int) visibleRailRange({
  required int count,
  required double offset,
  required double viewport,
  required double extent,
}) {
  if (count <= 0 || !offset.isFinite || !viewport.isFinite || !extent.isFinite || viewport <= 0 || extent <= 0) {
    return (0, 0);
  }
  final start = math.max<double>(0, offset);
  final first = (start / extent).floor().clamp(0, count);
  final end = ((start + viewport) / extent).ceil().clamp(first, count);
  return (first, end);
}

/// Cells are 16:9 (docs/T12/T12a/T12a.2 c2).
const double cellAspect = 16 / 9;

/// Where the cells of a layout go (docs/T12/T12a/T12a.2): 16:9 cells as large
/// as the area lets them be, centred; 1×2 one above the other or side by
/// side, and 1+3 with its small cells below or beside the large one,
/// whichever shows larger pictures.
final class WallGeometry {
  /// Creates the geometry.
  const new({required this.size, required this.cells, this.rail, this.railVertical = false, this.railExtent = 0});

  /// The cells of [layout] in `width` × `height` (an infinite height: as
  /// tall as the width wants); `gap` between cells and `padding` around them.
  factory of(
    MultiviewLayout layout, {
    required double width,
    double height = double.infinity,
    double gap = 3,
    double padding = 3,
  }) {
    if (layout == MultiviewLayout.focus) {
      return WallGeometry.focus(width: width, height: height, gap: gap, padding: padding);
    }
    final shapes = switch (layout) {
      MultiviewLayout.single => const [(1, 1)],
      MultiviewLayout.dual => const [(1, 2), (2, 1)],
      _ => const [(2, 2)],
    };
    (double, int, int)? best;
    for (final (columns, rows) in shapes) {
      final byWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
      final byHeight = (height - padding * 2 - gap * (rows - 1)) / rows * cellAspect;
      final cellWidth = math.max<double>(0, math.min(byWidth, byHeight));
      if (best == null || cellWidth > best.$1 + 0.5) best = (cellWidth, columns, rows);
    }
    final (cellWidth, columns, rows) = best!;
    final cellHeight = cellWidth / cellAspect;
    final content = Size(
      cellWidth * columns + gap * (columns - 1) + padding * 2,
      cellHeight * rows + gap * (rows - 1) + padding * 2,
    );
    final size = Size(width, height.isFinite ? height : content.height);
    final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
    return WallGeometry(
      size: size,
      cells: [
        for (var row = 0; row < rows; row++)
          for (var column = 0; column < columns; column++)
            Rect.fromLTWH(
              origin.dx + column * (cellWidth + gap),
              origin.dy + row * (cellHeight + gap),
              cellWidth,
              cellHeight,
            ),
      ],
    );
  }

  /// The focus layout: the large cell and a rail of three small cells in
  /// sight (more scroll), below it or beside it.
  factory focus({required double width, double height = double.infinity, double gap = 3, double padding = 3}) {
    // Small cells below: w is a small cell's width.
    final belowByWidth = (width - padding * 2 - gap * 2) / 3;
    final belowByHeight = ((height - padding * 2 - gap) * cellAspect - gap * 2) / 4;
    final below = math.max<double>(0, math.min(belowByWidth, belowByHeight));
    final belowLarge = below * 3 + gap * 2;
    // Small cells beside: s is a small cell's height.
    final besideByWidth = ((width - padding * 2 - gap) / cellAspect - gap * 2) / 4;
    final besideByHeight = (height - padding * 2 - gap * 2) / 3;
    final beside = math.max<double>(0, math.min(besideByWidth, besideByHeight));
    final besideLarge = (beside * 3 + gap * 2) * cellAspect;
    if (belowLarge >= besideLarge) {
      final largeHeight = belowLarge / cellAspect;
      final smallHeight = below / cellAspect;
      final content = Size(belowLarge + padding * 2, largeHeight + gap + smallHeight + padding * 2);
      final size = Size(width, height.isFinite ? height : content.height);
      final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
      return WallGeometry(
        size: size,
        cells: [Rect.fromLTWH(origin.dx, origin.dy, belowLarge, largeHeight)],
        rail: Rect.fromLTWH(origin.dx, origin.dy + largeHeight + gap, belowLarge, smallHeight),
        railExtent: below + gap,
      );
    }
    final largeHeight = beside * 3 + gap * 2;
    final smallWidth = beside * cellAspect;
    final content = Size(besideLarge + gap + smallWidth + padding * 2, largeHeight + padding * 2);
    final size = Size(width, height.isFinite ? height : content.height);
    final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
    return WallGeometry(
      size: size,
      cells: [Rect.fromLTWH(origin.dx, origin.dy, besideLarge, largeHeight)],
      rail: Rect.fromLTWH(origin.dx + besideLarge + gap, origin.dy, smallWidth, largeHeight),
      railVertical: true,
      railExtent: beside + gap,
    );
  }

  /// The wall's size: the area, or the content's height when the area had
  /// none.
  final Size size;

  /// The plain layouts' cells in order; the focus layout's large cell.
  final List<Rect> cells;

  /// The focus layout's rail of small cells (its viewport), else null.
  final Rect? rail;

  /// The rail runs down (small cells beside the large one).
  final bool railVertical;

  /// One rail item along the rail: a small cell and the gap after it.
  final double railExtent;

  /// The width the cells take (the wall without its empty sides).
  double get contentWidth {
    var left = double.infinity;
    var right = 0.0;
    for (final rect in [...cells, ?rail]) {
      left = math.min(left, rect.left);
      right = math.max(right, rect.right);
    }
    return left.isFinite ? right - left : 0;
  }
}
