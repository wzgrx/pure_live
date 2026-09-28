import 'dart:ui';

/// Builds the outline of a glyph that live_ui draws, on the 24 dp grid of
/// Material Symbols Rounded, for a stroke width in grid units and a fill
/// state (principles §2.6: both states exist, and they differ only in fill).
typedef GlyphBuilder = Path Function(double stroke, {required bool filled});

/// The stroke of Material Symbols Rounded on its 24 dp grid for the given
/// axes, so a drawn glyph sits beside the font's glyphs with the same
/// weight: 2 at weight 400, grade 0 and optical size 24.
///
/// Measured from MaterialSymbolsRounded 2.960 (the `remove` glyph is one
/// stroke tall) at weights 400 and 500, grades 0 and -25 and optical sizes
/// 20, 24, 32, 40 and 48; this model matches every sample within 0.01. From
/// 20 to 24 the stroke grows with the optical size, above 24 it thins
/// (the glyph keeps its size on the grid while the icon grows), and the
/// effect of weight and grade halves between 24 and 48.
double symbolStroke({required double weight, required double grade, required double opticalSize}) {
  final opsz = opticalSize.clamp(20.0, 48.0);
  final above = opsz > 24 ? (opsz - 24) / 24 : 0.0;
  final base = opsz <= 24 ? 1.8 + (opsz - 20) * 0.05 : 2 - above * 0.5;
  final perWeight = (0.275 - above * 0.072) / 100;
  final perGrade = (0.25 - above * 0.125) / 25;
  return base + (weight.clamp(100.0, 700.0) - 400) * perWeight + grade.clamp(-50.0, 200.0) * perGrade;
}

/// A round-capped line from [x0] to [x1] (centres of the caps) at height [y].
RRect _capsule(double x0, double x1, double y, double stroke) =>
    RRect.fromLTRBR(x0 - stroke / 2, y - stroke / 2, x1 + stroke / 2, y + stroke / 2, Radius.circular(stroke / 2));

/// 弹幕: a screen with three lines of text passing across it at different
/// places, like comments flying over the picture. Outlined, the frame is a
/// stroke (outer corners 2, inner corners square, as in Symbols' `subtitles`)
/// and the lines are strokes inside it; filled, the screen is solid and the
/// lines are cut out of it.
///
/// Grid: frame 2–22 × 3–21 (20 × 18, inside the 20 dp live area); lines at
/// y 8, 12 and 16, 2 dp apart and 2 dp from the frame, staggered right,
/// left and right: 11–18, 6–14 and 9–17 with their round caps.
Path danmakuGlyph(double stroke, {required bool filled}) {
  // The frame's centre line; at stroke 2 its outer edge is 2–22 × 3–21.
  const frame = Rect.fromLTRB(3, 4, 21, 20);
  const radius = 1.0;
  final path = Path()
    ..fillType = PathFillType.evenOdd
    ..addRRect(
      RRect.fromRectAndRadius(frame.inflate(stroke / 2), const Radius.circular(radius) + Radius.circular(stroke / 2)),
    );
  if (!filled) {
    final inner = radius - stroke / 2;
    path.addRRect(RRect.fromRectAndRadius(frame.deflate(stroke / 2), Radius.circular(inner > 0 ? inner : 0)));
  }
  [_capsule(12, 17, 8, stroke), _capsule(7, 13, 12, stroke), _capsule(10, 16, 16, stroke)].forEach(path.addRRect);
  return path;
}
