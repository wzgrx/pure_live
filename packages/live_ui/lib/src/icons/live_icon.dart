import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/drawn_glyphs.dart';
import 'package:live_ui/src/icons/live_icons.dart';
import 'package:live_ui/src/metrics.dart';

/// The variable axes of principles §2.6 as an [IconThemeData]: fill 0,
/// weight 400, grade 0 on light surfaces and -25 on dark and pure black
/// (less glare from light icons on dark ground), optical size [size].
/// `PureTheme` puts it in the theme; [LiveIcon] reads it.
IconThemeData iconAxes({required bool dark, double size = Sizes.iconMd}) =>
    IconThemeData(fill: 0, weight: 400, grade: dark ? -25 : 0, opticalSize: size);

/// A [LiveIcons] glyph with the axes of principles §2.6:
///
/// - fill 0, or 1 when [filled] (the current destination, danmaku on, a
///   followed room, muted). A toggle keeps its glyph and changes only this.
/// - weight and grade from the nearest [IconTheme], and where a component
///   replaced it without them, from the theme ([iconAxes]): 400, grade 0 on
///   light and -25 on dark; the controls on a picture use 500
///   (`VideoControlIcons`).
/// - optical size equal to the size shown (20 to 48), so strokes keep their
///   drawn weight at 20, 24, 32, 40 and 48 dp.
///
/// Size and colour work as for [Icon]: [size] or the nearest [IconTheme].
class LiveIcon extends StatelessWidget {
  /// Shows [icon].
  const new(this.icon, {this.size, this.color, this.filled, this.semanticLabel, super.key});

  /// Which glyph.
  final LiveIcons icon;

  /// Size in logical pixels; the nearest [IconTheme]'s by default.
  final double? size;

  /// Colour; the nearest [IconTheme]'s by default.
  final Color? color;

  /// Fill 1 when true, 0 when false; the nearest [IconTheme]'s fill (0 in
  /// the theme) when null.
  final bool? filled;

  /// Read by screen readers; decorative (silent) when null.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    // IconTheme.of fills unset axes with Flutter's fallback (grade 0, optical
    // size 48); a component that replaced the theme's icon theme (the
    // navigation rail does) would lose the dark grade. The nearest icon
    // theme as given, then the theme's, then principles §2.6.
    final local = context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data;
    final theme = Theme.of(context);
    final base = theme.iconTheme;
    final nominal = size ?? iconTheme.size ?? Sizes.iconMd;
    final shown = (iconTheme.applyTextScaling ?? false) ? MediaQuery.textScalerOf(context).scale(nominal) : nominal;
    final fill = switch (filled) {
      true => 1.0,
      false => 0.0,
      null => local?.fill ?? base.fill ?? 0.0,
    };
    final weight = local?.weight ?? base.weight ?? 400.0;
    final grade = local?.grade ?? base.grade ?? (theme.brightness == Brightness.dark ? -25.0 : 0.0);
    final opticalSize = shown.clamp(20.0, 48.0);
    if (icon.glyph case final glyph?) {
      return Icon(
        glyph,
        size: shown,
        fill: fill,
        weight: weight,
        grade: grade,
        opticalSize: opticalSize,
        color: color,
        semanticLabel: semanticLabel,
        applyTextScaling: false,
      );
    }
    var ink = color ?? iconTheme.color!;
    final opacity = iconTheme.opacity ?? 1.0;
    if (opacity != 1.0) ink = ink.withValues(alpha: ink.a * opacity);
    final stroke = symbolStroke(weight: weight, grade: grade, opticalSize: opticalSize);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: shown,
          child: CustomPaint(
            painter: _GlyphPainter(icon.outline!, stroke: stroke, filled: fill >= 0.5, color: ink),
          ),
        ),
      ),
    );
  }
}

/// Paints a drawn glyph's outline, scaled from the 24 dp grid.
class _GlyphPainter extends CustomPainter {
  const new(this.outline, {required this.stroke, required this.filled, required this.color});

  final GlyphBuilder outline;
  final double stroke;
  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(outline(stroke, filled: filled), Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.outline != outline || old.stroke != stroke || old.filled != filled || old.color != color;
}
