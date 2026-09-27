import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:live_ui/src/metrics.dart';

/// Width classes of spec/design/principles.md §5.1, in dp of available width.
enum WidthClass {
  /// < 600: phones in portrait.
  compact,

  /// 600–839: small tablets, unfolded foldables.
  medium,

  /// 840–1199: tablets in portrait, TV canvas.
  expanded,

  /// 1200–1599: tablets in landscape, small desktop windows.
  large,

  /// ≥ 1600: desktop windows.
  extraLarge;

  /// The class of [width].
  static WidthClass of(double width) => switch (width) {
    < 600 => compact,
    < 840 => medium,
    < 1200 => expanded,
    < 1600 => large,
    _ => extraLarge,
  };

  /// Whether this class is at least [other].
  bool atLeast(WidthClass other) => index >= other.index;
}

/// Height classes; compact height wins over width (landscape phones).
enum HeightClass {
  /// < 480: phones in landscape.
  compact,

  /// 480–899.
  medium,

  /// ≥ 900.
  expanded;

  /// The class of [height].
  static HeightClass of(double height) => switch (height) {
    < 480 => compact,
    < 900 => medium,
    _ => expanded,
  };
}

/// How the four top-level destinations are shown (principles §5.2).
enum NavigationKind {
  /// Bottom navigation bar.
  bar,

  /// Collapsed navigation rail, labels under icons.
  rail,

  /// Expanded navigation rail with labels beside icons.
  extendedRail,
}

/// Layout decisions for one window size.
@immutable
final class WindowLayout {
  /// Derives the layout from the available [size].
  new(Size size) : width = WidthClass.of(size.width), height = HeightClass.of(size.height), _size = size;

  final Size _size;

  /// Width class.
  final WidthClass width;

  /// Height class.
  final HeightClass height;

  /// Landscape phones: compact height, whatever the width says.
  bool get isShortLandscape => height == HeightClass.compact && _size.width > _size.height;

  /// Navigation form.
  NavigationKind get navigation {
    if (width == WidthClass.compact && !isShortLandscape) return NavigationKind.bar;
    if (width.atLeast(WidthClass.large) && !isShortLandscape) return NavigationKind.extendedRail;
    return NavigationKind.rail;
  }

  /// Page margin.
  double get margin => switch (width) {
    WidthClass.compact => Space.s4,
    WidthClass.medium || WidthClass.expanded => Space.s6,
    WidthClass.large || WidthClass.extraLarge => Space.s8,
  };

  /// Grid gap.
  double get gap => switch (width) {
    WidthClass.compact => Space.s2,
    WidthClass.medium || WidthClass.expanded => Space.s3,
    WidthClass.large || WidthClass.extraLarge => Space.s4,
  };

  /// Smallest card width the grid allows.
  double get minCardWidth => switch (width) {
    WidthClass.compact => 160,
    WidthClass.medium || WidthClass.expanded => 180,
    WidthClass.large || WidthClass.extraLarge => 200,
  };

  /// Columns for a card grid whose content area is [contentWidth] wide:
  /// clamp(⌊(content + gap) ÷ (min card + gap)⌋, 2, 8).
  int columnsFor(double contentWidth) =>
      math.max(2, math.min(8, ((contentWidth + gap) / (minCardWidth + gap)).floor()));
}

/// Builds with the [WindowLayout] of the parent's constraints, never the
/// whole screen (principles §5.1, rule 5).
class WindowLayoutBuilder extends StatelessWidget {
  /// Creates the builder.
  const new({required this.builder, super.key});

  /// Builds the child for a layout.
  final Widget Function(BuildContext context, WindowLayout layout) builder;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) => builder(context, WindowLayout(constraints.biggest)));
}
