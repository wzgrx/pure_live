import 'dart:math' as math;

/// The window width classes (docs/ui/UI_PLAN.md §5.1, Android's window size
/// classes).
enum WindowWidthClass {
  /// Narrower than 600 (phones held upright).
  compact,

  /// 600–839 (small tablets, unfolded phones).
  medium,

  /// 840–1199 (phones held sideways, tablets).
  expanded,

  /// 1200–1599 (desktop windows, large tablets).
  large,

  /// 1600 and wider.
  extraLarge;

  /// The class of a window [width] logical pixels wide.
  static WindowWidthClass of(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    if (width < 1600) return large;
    return extraLarge;
  }
}

/// How many columns a grid takes (docs/ui/UI_PLAN.md §5.3, U.4a c15):
/// `clamp(⌊(content + gap) ÷ (smallest item + gap)⌋, min, max)`, where the
/// content is the grid's own width less its padding on both sides.
///
/// The columns change only when the width crosses a step, so cards do not
/// jump between fixed breakpoints while a window is dragged (3.x used 640,
/// 960 and 1280 and read the whole screen).
abstract final class GridColumns {
  /// Columns of a grid [width] wide (the grid's own constraint) whose items
  /// are at least [minItemWidth], [spacing] apart, inside [padding] on each
  /// side; between [min] and [max].
  static int count({
    required double width,
    required double minItemWidth,
    double spacing = 6,
    double padding = 6,
    int min = 2,
    int max = 8,
  }) {
    if (!width.isFinite || width <= 0) return min;
    final content = math.max<double>(0, width - padding * 2);
    final columns = ((content + spacing) / (minItemWidth + spacing)).floor();
    return columns.clamp(min, max);
  }

  /// The smallest room card in a window [windowWidth] wide: 160 compact,
  /// 180 medium and expanded, 200 large and extra large.
  static double roomMinWidth(double windowWidth) => switch (WindowWidthClass.of(windowWidth)) {
    WindowWidthClass.compact => 160,
    WindowWidthClass.medium || WindowWidthClass.expanded => 180,
    WindowWidthClass.large || WindowWidthClass.extraLarge => 200,
  };

  /// The smallest area card (a square picture, U.4d c5): 110 compact, 130
  /// medium and expanded, 150 large and extra large.
  static double areaMinWidth(double windowWidth) => switch (WindowWidthClass.of(windowWidth)) {
    WindowWidthClass.compact => 110,
    WindowWidthClass.medium || WindowWidthClass.expanded => 130,
    WindowWidthClass.large || WindowWidthClass.extraLarge => 150,
  };

  /// Columns of a room card grid: 2–8; a 393 wide phone has 2, like 3.x.
  static int rooms({required double width, required double windowWidth, double spacing = 6, double padding = 6}) =>
      count(width: width, minItemWidth: roomMinWidth(windowWidth), spacing: spacing, padding: padding);

  /// Columns of an area grid: 3–10; a 393 wide phone has 3 and a 1280 window
  /// with the side rail 7, like 3.x.
  static int areas({required double width, required double windowWidth, double spacing = 6, double padding = 6}) =>
      count(width: width, minItemWidth: areaMinWidth(windowWidth), spacing: spacing, padding: padding, min: 3, max: 10);

  /// The width of one item when [columns] share [width].
  static double itemWidth({required double width, required int columns, double spacing = 6, double padding = 6}) =>
      math.max<double>(0, (width - padding * 2 - spacing * (columns - 1)) / columns);
}
