import 'dart:math' as math;
import 'dart:ui' show SemanticsRole, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_ui/src/widgets/window_layout.dart';

// The route behind the small menu ([showSmallMenu], [showAppMenu];
// docs/A-界面设计/A02-组件/A02.3-贴着按钮的小菜单/brief.md). Flutter's `showMenu` only takes the menu's top
// edge and always grows downwards from it, so a menu meant to sit above its
// button first showed as a line far above it and then dropped onto it; and
// the side was chosen from a guessed height. Here the menu is laid out first
// and placed by its real height, and unfolds from the edge at the button.

/// The gap between a button and its small menu.
const double anchoredMenuGap = 4;

/// How far a small menu keeps from the screen's edges and unsafe areas.
const double anchoredMenuMargin = 8;

/// How long the small menu takes to unfold (docs/specs/UI.md §8.6:
/// instant feedback, 100–150 ms).
const Duration anchoredMenuOpenDuration = Duration(milliseconds: 150);

/// How long it takes to fade out: a closing menu goes faster than it came.
const Duration anchoredMenuCloseDuration = Duration(milliseconds: 100);

/// The smallest menu (one 48 row and the 8 above and below it): when neither
/// side of the button has this much room, the menu may cover the button.
const double _leastHeight = kMinInteractiveDimension + 16;

/// Opens [children] in the small menu next to the box of [anchor]
/// (docs/specs/UI.md §7, the look U.2f confirmed): on
/// `surfaceContainerHighest` with 8-point corners, 8 above and below the
/// rows, [constraints] on its width and otherwise as wide as its rows.
///
/// The menu is laid out first and placed by its measured height:
/// [anchoredMenuGap] above the box when [preferAbove] and it fits there,
/// below it when it fits there, otherwise on the side with more room, where
/// it is at most as high as that room and its rows scroll. It lines up with
/// the box's edge nearer the screen's edge and stays [anchoredMenuMargin]
/// inside the screen. It fades in and unfolds from the edge at the box
/// ([anchoredMenuOpenDuration]); with the system's reduced motion it shows
/// at once. A tap outside, Back and Esc close it with null; arrows move
/// between the rows and Enter picks one. [current], the key of a row, is
/// scrolled into view when the rows scroll. A change of the screen's size
/// closes it (its button moved). A fold or hinge that splits the window
/// keeps the menu on its button's side ([DisplayHinge], A04.1).
Future<T?> showAnchoredMenu<T>(
  BuildContext anchor, {
  required List<Widget> children,
  required BoxConstraints constraints,
  bool preferAbove = false,
  GlobalKey? current,
}) {
  final navigator = Navigator.of(anchor);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final box = anchor.findRenderObject()! as RenderBox;
  final localizations = MaterialLocalizations.of(anchor);
  return navigator.push(
    _AnchoredMenuRoute<T>(
      anchor: MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size),
      preferAbove: preferAbove,
      still: MediaQuery.maybeDisableAnimationsOf(anchor) ?? false,
      barrierLabel: localizations.menuDismissLabel,
      capturedThemes: InheritedTheme.capture(from: anchor, to: navigator.context),
      menu: _MenuSurface(
        constraints: constraints,
        current: current,
        semanticLabel: localizations.popupMenuLabel,
        children: children,
      ),
    ),
  );
}

/// Which side of its button the menu went to, found while laying it out and
/// read when painting the unfolding.
final class _MenuSide {
  bool up = false;
}

class _AnchoredMenuRoute<T> extends PopupRoute<T> {
  new({
    required this.anchor,
    required this.preferAbove,
    required this.still,
    required this.barrierLabel,
    required this.capturedThemes,
    required this.menu,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  /// The button, in the navigator's coordinates.
  final Rect anchor;

  final bool preferAbove;

  /// The system asks for reduced motion.
  final bool still;

  final CapturedThemes capturedThemes;

  final Widget menu;

  final _MenuSide _side = _MenuSide();

  Size? _screen;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => still ? Duration.zero : anchoredMenuOpenDuration;

  @override
  Duration get reverseTransitionDuration => still ? Duration.zero : anchoredMenuCloseDuration;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final screen = MediaQuery.sizeOf(context);
    if ((_screen ??= screen) != screen) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (isActive) navigator?.removeRoute(this);
      });
    }
    final padding = MediaQuery.paddingOf(context);
    // The side of a fold its button is on: the menu is laid out in there.
    final area = DisplayHinge.maybeOf(context)?.sideOf(anchor.center, screen) ?? Offset.zero & screen;
    final inset = EdgeInsets.fromLTRB(area.left, area.top, screen.width - area.right, screen.height - area.bottom);
    return Padding(
      padding: inset,
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        child: CustomSingleChildLayout(
          delegate: _AnchoredMenuLayout(
            anchor: anchor.shift(-area.topLeft),
            padding: EdgeInsets.fromLTRB(
              math.max(0, padding.left - inset.left),
              math.max(0, padding.top - inset.top),
              math.max(0, padding.right - inset.right),
              math.max(0, padding.bottom - inset.bottom),
            ),
            preferAbove: preferAbove,
            textDirection: Directionality.of(context),
            side: _side,
          ),
          child: capturedThemes.wrap(still ? menu : _MenuUnfold(animation: animation, side: _side, child: menu)),
        ),
      ),
    );
  }
}

/// Places the menu by its measured size (see [showAnchoredMenu]).
class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  new({
    required this.anchor,
    required this.padding,
    required this.preferAbove,
    required this.textDirection,
    required this.side,
  });

  final Rect anchor;

  /// The screen's unsafe areas.
  final EdgeInsets padding;

  final bool preferAbove;

  final TextDirection textDirection;

  final _MenuSide side;

  ({double above, double below}) _room(Size screen) => (
    above: anchor.top - anchoredMenuGap - padding.top - anchoredMenuMargin,
    below: screen.height - padding.bottom - anchoredMenuMargin - anchor.bottom - anchoredMenuGap,
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final screen = constraints.biggest;
    final (:above, :below) = _room(screen);
    // The menu goes where it fits, or else to the side with more room: at
    // most as high as the larger side, it never needs more than its side.
    var height = math.max(above, below);
    if (height < _leastHeight) height = screen.height - padding.vertical - 2 * anchoredMenuMargin;
    return BoxConstraints(
      maxWidth: math.max(0, screen.width - padding.horizontal - 2 * anchoredMenuMargin),
      maxHeight: math.max(0, height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final (:above, :below) = _room(size);
    final height = childSize.height;
    final up = preferAbove ? height <= above || above > below : height > below && above > below;
    side.up = up;
    final top = padding.top + anchoredMenuMargin;
    final bottom = size.height - padding.bottom - anchoredMenuMargin;
    final y = up ? anchor.top - anchoredMenuGap - height : anchor.bottom + anchoredMenuGap;
    // Lined up with the button's edge nearer the screen's edge.
    final toRight = size.width - anchor.right;
    final end = anchor.left > toRight || (anchor.left == toRight && textDirection == TextDirection.rtl);
    final x = end ? anchor.right - childSize.width : anchor.left;
    final left = padding.left + anchoredMenuMargin;
    final right = size.width - padding.right - anchoredMenuMargin;
    return Offset(math.max(left, math.min(x, right - childSize.width)), math.max(top, math.min(y, bottom - height)));
  }

  @override
  bool shouldRelayout(_AnchoredMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      padding != oldDelegate.padding ||
      preferAbove != oldDelegate.preferAbove ||
      textDirection != oldDelegate.textDirection;
}

/// Fades the menu in and unfolds it from the edge at its button: upwards
/// from below over a button, downwards from above under one. It only fades
/// out when it closes.
class _MenuUnfold extends StatefulWidget {
  const new({required this.animation, required this.side, required this.child});

  final Animation<double> animation;

  final _MenuSide side;

  final Widget child;

  @override
  State<_MenuUnfold> createState() => _MenuUnfoldState();
}

class _MenuUnfoldState extends State<_MenuUnfold> {
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  // Closing keeps it whole (the threshold is 1 for every value above 0).
  late final CurvedAnimation _unfold = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: const Threshold(0),
  );

  @override
  void dispose() {
    _fade.dispose();
    _unfold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ClipRect(clipper: _UnfoldClipper(_unfold, widget.side), child: widget.child),
  );
}

/// The part of the menu shown so far, grown from the edge at the button;
/// wide enough for the shadow.
class _UnfoldClipper extends CustomClipper<Rect> {
  new(this.unfold, this.side) : super(reclip: unfold);

  static const double _shadow = 16;

  final Animation<double> unfold;

  final _MenuSide side;

  @override
  Rect getClip(Size size) {
    final value = unfold.value;
    return side.up
        ? Rect.fromLTRB(
            -_shadow,
            lerpDouble(size.height, -_shadow, value)!,
            size.width + _shadow,
            size.height + _shadow,
          )
        : Rect.fromLTRB(-_shadow, -_shadow, size.width + _shadow, lerpDouble(0, size.height + _shadow, value)!);
  }

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  @override
  bool shouldReclip(_UnfoldClipper oldClipper) => oldClipper.unfold != unfold || oldClipper.side != side;
}

/// The menu's surface: the rows in a column that scrolls when the menu is
/// held lower than they are.
class _MenuSurface extends StatefulWidget {
  const new({required this.constraints, required this.current, required this.semanticLabel, required this.children});

  final BoxConstraints constraints;

  final GlobalKey? current;

  final String semanticLabel;

  final List<Widget> children;

  @override
  State<_MenuSurface> createState() => _MenuSurfaceState();
}

class _MenuSurfaceState extends State<_MenuSurface> {
  @override
  void initState() {
    super.initState();
    if (widget.current == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final row = widget.current?.currentContext;
      if (!mounted || row == null) return;
      // Only when it is out of view: the list starts at the top.
      Scrollable.ensureVisible(row, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material's menu: elevation 3 in the shadow colour, no tint.
    return Material(
      type: MaterialType.card,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 3,
      shadowColor: scheme.shadow,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: widget.constraints,
        child: IntrinsicWidth(
          // Material's menu width step.
          stepWidth: 56,
          child: Semantics(
            role: SemanticsRole.menu,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: widget.semanticLabel,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListBody(children: widget.children),
            ),
          ),
        ),
      ),
    );
  }
}
