import 'package:flutter/material.dart';

/// Whether focus frames show: the user moves the focus with a keyboard
/// (or a remote), not with touch (UI_PLAN §5.4: "焦点框只在用键盘时显示").
bool get focusFramesShown => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// The keyboard focus frame (docs/T01/T01c/T01c.1 c21): 2 px in the primary
/// colour, [gap] outside [child], drawn while [child] or a widget in it has
/// the focus and the user moves the focus with the keyboard. Material's
/// buttons, chips and tabs get theirs from the theme; this is for custom
/// tappable widgets (avatars, counters, the jump buttons).
class FocusRing extends StatefulWidget {
  /// Frames [child].
  const new({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.gap = 2,
    this.color,
    super.key,
  });

  /// The framed widget; it holds the focusable widget.
  final Widget child;

  /// The corners of [child] (the frame follows them, [gap] further out).
  final BorderRadius borderRadius;

  /// Space between [child] and the frame.
  final double gap;

  /// The frame's colour; null is the primary colour.
  final Color? color;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode mode) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shown = _focused && focusFramesShown;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: CustomPaint(
        foregroundPainter: shown
            ? FocusRingPainter(
                color: widget.color ?? Theme.of(context).colorScheme.primary,
                borderRadius: widget.borderRadius,
                gap: widget.gap,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

/// Paints a [FocusRing]'s frame around its box.
class FocusRingPainter extends CustomPainter {
  /// Creates the painter.
  const new({required this.color, required this.borderRadius, this.gap = 2, this.width = 2});

  /// The frame's colour.
  final Color color;

  /// The box's corners.
  final BorderRadius borderRadius;

  /// Space between the box and the frame.
  final double gap;

  /// The frame's width.
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final outset = gap + width / 2;
    final rect = (Offset.zero & size).inflate(outset);
    final radius = borderRadius + BorderRadius.circular(outset);
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.gap != gap ||
      oldDelegate.width != width;
}
