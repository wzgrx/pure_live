import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/grid_columns.dart';

// The window's size classes and its fold (docs/specs/UI.md §5.1,
// research V03.2 §3, A04.1): layouts read the
// constraints their parent gives, not the whole screen, and keep their
// content off a fold or hinge that splits the window.

/// The height of an app bar in a short window (a phone held sideways, a
/// phone's split screen; U.6a): [kToolbarHeight] otherwise.
const double compactToolbarHeight = 48;

/// Tells the widgets below the [WindowClass] of the area it is laid out in
/// (UI.md §5.1: only the parent's constraints, 3.x read the whole screen).
/// The app puts one over all its pages; a pane can put its own.
///
/// Dependents rebuild only when a class changes, not on every pixel of a
/// window being dragged.
class WindowClassScope extends StatelessWidget {
  /// Creates the scope over [child].
  const new({required this.child, super.key});

  /// The widgets below.
  final Widget child;

  /// The classes of the nearest scope's area; without a scope, of the
  /// window ([MediaQuery.sizeOf]).
  static WindowClass of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WindowClassData>()?.value ??
      WindowClass.of(MediaQuery.sizeOf(context));

  /// The height of an app bar in [context]: [compactToolbarHeight] in a
  /// short area, [kToolbarHeight] otherwise.
  static double toolbarHeightOf(BuildContext context) => of(context).isShort ? compactToolbarHeight : kToolbarHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // An unbounded side (inside a scroll view) is as large as the window.
      final window = MediaQuery.sizeOf(context);
      final size = Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : window.width,
        constraints.maxHeight.isFinite ? constraints.maxHeight : window.height,
      );
      return _WindowClassData(value: WindowClass.of(size), child: child);
    },
  );
}

class _WindowClassData extends InheritedWidget {
  const new({required this.value, required super.child});

  final WindowClass value;

  @override
  bool updateShouldNotify(_WindowClassData oldWidget) => value != oldWidget.value;
}

/// A fold or hinge that splits the window in two (UI.md §5.1 item 4): a
/// hinge that hides part of the screen, or a fold that is half open (book
/// or tabletop posture). A flat fold does not split anything (the screen is
/// one surface), nor does the camera's cut-out. Its [bounds] are in the
/// window's logical pixels, as in `MediaQuery.displayFeatures`.
@immutable
final class DisplayHinge {
  /// A hinge at [bounds].
  const new(this.bounds);

  /// Where the hinge is, in the window.
  final Rect bounds;

  /// A vertical hinge (left and right halves: book posture, dual screens).
  bool get vertical => bounds.height >= bounds.width;

  /// The hinge among [features] that splits a window [window] large, or
  /// null.
  static DisplayHinge? find(Iterable<DisplayFeature> features, Size window) {
    final area = Offset.zero & window;
    for (final feature in features) {
      if (feature.type == DisplayFeatureType.cutout) continue;
      final bounds = feature.bounds;
      final splits = bounds.shortestSide > 0 || feature.state == DisplayFeatureState.postureHalfOpened;
      if (!splits) continue;
      final across = bounds.top <= area.top && bounds.bottom >= area.bottom;
      final along = bounds.left <= area.left && bounds.right >= area.right;
      if (across || along) return DisplayHinge(bounds);
    }
    return null;
  }

  /// The hinge splitting the window [context] is in, or null. Depends only
  /// on the window's size and display features (not on the keyboard).
  static DisplayHinge? maybeOf(BuildContext context) =>
      find(MediaQuery.displayFeaturesOf(context), MediaQuery.sizeOf(context));

  /// The side of this hinge that the point [anchor] is on (or nearer), in a
  /// window [window] large; both in the window's logical pixels.
  Rect sideOf(Offset anchor, Size window) {
    final area = Offset.zero & window;
    if (vertical) {
      return anchor.dx < bounds.center.dx
          ? Rect.fromLTRB(area.left, area.top, math.max(area.left, bounds.left), area.bottom)
          : Rect.fromLTRB(math.min(area.right, bounds.right), area.top, area.right, area.bottom);
    }
    return anchor.dy < bounds.center.dy
        ? Rect.fromLTRB(area.left, area.top, area.right, math.max(area.top, bounds.top))
        : Rect.fromLTRB(area.left, math.min(area.bottom, bounds.bottom), area.right, area.bottom);
  }

  /// Two panes of a row [width] wide whose left edge is [left] from the
  /// window's, split by this hinge: the start pane ends where the hinge
  /// begins and the end pane starts where it ends (`gap` between them).
  /// Null when the hinge is not vertical, misses the row, or leaves a pane
  /// narrower than [minPane].
  ({double start, double gap})? splitRow({required double left, required double width, double minPane = 320}) {
    if (!vertical) return null;
    final start = bounds.left - left;
    final end = bounds.right - left;
    if (start < minPane || width - end < minPane) return null;
    return (start: start, gap: end - start);
  }

  @override
  bool operator ==(Object other) => other is DisplayHinge && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'DisplayHinge($bounds)';
}
