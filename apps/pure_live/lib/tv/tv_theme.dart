import 'dart:math' as math;

import 'package:flutter/material.dart';

// The TV look (pure_live_TV b9d2f739 `lib/core/theme/`): a palette derived
// from one accent, sizes drafted against a 1920x1080 panel, text lifted on
// small panels, and room grids whose columns follow the text size.

/// The colours of the TV interface, derived from the app theme's primary
/// colour (pure_live_TV `TvThemeData`: deep tinted surfaces on dark, warm
/// paper tones on light, all in the accent's hue).
@immutable
final class TvPalette {
  /// Creates a palette.
  const new({
    required this.background,
    required this.focus,
    required this.text,
    required this.textSecondary,
    required this.card,
    required this.focusedCard,
    required this.isLight,
  });

  /// The palette of [scheme]'s brightness and primary colour.
  factory of(ColorScheme scheme) {
    final seed = scheme.primary;
    final light = scheme.brightness == Brightness.light;
    return light
        ? TvPalette(
            background: _tinted(seed, 0.955, 0.30),
            focus: _vivid(seed),
            text: _tinted(seed, 0.13, 0.28),
            textSecondary: _tinted(seed, 0.13, 0.28).withValues(alpha: 0.72),
            card: _tinted(seed, 0.99, 0.22),
            focusedCard: _tinted(seed, 0.88, 0.45),
            isLight: true,
          )
        : TvPalette(
            background: _tinted(seed, 0.055),
            focus: _vivid(seed),
            text: _tinted(seed, 0.96, 0.10),
            textSecondary: _tinted(seed, 0.96, 0.10).withValues(alpha: 0.72),
            card: _tinted(seed, 0.105),
            focusedCard: _tinted(seed, 0.20, 0.48),
            isLight: false,
          );
  }

  /// The page background.
  final Color background;

  /// The focus ring, selected fills and accents.
  final Color focus;

  /// Main text.
  final Color text;

  /// Secondary text.
  final Color textSecondary;

  /// An idle card or row.
  final Color card;

  /// A focused card.
  final Color focusedCard;

  /// A light palette (no glow: a halo on white reads as a grey smear).
  final bool isLight;

  /// Text on [focus].
  Color get onFocus => readableOn(focus);

  /// Text on [focusedCard].
  Color get onFocusedCard => readableOn(focusedCard);

  /// A faint fill for rows that are neither focused nor selected.
  Color get subtleFill => text.withValues(alpha: 0.06);

  /// Near-black or white, whichever reads better on [background].
  static Color readableOn(Color background) {
    const ink = Color(0xFF101014);
    const paper = Color(0xFFFFFFFF);
    return _contrast(paper, background) >= _contrast(ink, background) ? paper : ink;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static Color _vivid(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    return HSLColor.fromAHSL(1, hsl.hue, hsl.saturation.clamp(0.55, 0.95), 0.52).toColor();
  }

  static Color _tinted(Color seed, double lightness, [double? saturation]) {
    final hsl = HSLColor.fromColor(seed);
    final s = (saturation ?? hsl.saturation).clamp(0.22, 0.42);
    return HSLColor.fromAHSL(1, hsl.hue, s, lightness).toColor();
  }
}

/// Sizes of the TV interface: lengths are drafted against a 1920x1080
/// panel (pure_live_TV `TvTextScale.designSize`) and scaled to the screen.
@immutable
final class TvScale {
  /// Creates the scale: [unit] logical pixels per design pixel and the
  /// text scale in force.
  const new({required this.unit, required this.textScale});

  /// The scale of [context]'s screen and text.
  factory of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final unit = math.min(size.width / designWidth, size.height / designHeight);
    return TvScale(unit: unit > 0 ? unit : 1, textScale: MediaQuery.textScalerOf(context).scale(1));
  }

  /// The panel the sizes are drafted for.
  static const double designWidth = 1920;

  /// The panel the sizes are drafted for.
  static const double designHeight = 1080;

  /// Logical pixels per design pixel.
  final double unit;

  /// The text scale in force (the user's size times the panel lift).
  final double textScale;

  /// [design] pixels as logical pixels.
  double call(num design) => design * unit;

  /// [design] pixels of a box that holds text: grows with the text (3.x's
  /// `.ts(context)`), so labels are never clipped at a large text size.
  double text(num design) => design * unit * textScale;

  /// A text style of [size] design pixels.
  TextStyle style(num size, {FontWeight? weight, Color? color, double? height}) =>
      TextStyle(fontSize: size * unit, fontWeight: weight, color: color, height: height);

  /// How much text is lifted on a panel smaller than 1080 lines
  /// (pure_live_TV `legibilityLift`: a 720p box draws at 1080 / 720, at
  /// most 1.6). Boxes keep scaling with the screen.
  static double legibilityLift(BuildContext context) {
    final media = MediaQuery.of(context);
    final lines = media.size.height * media.devicePixelRatio;
    if (!lines.isFinite || lines <= 0) return 1;
    return (designHeight / lines).clamp(1.0, 1.6);
  }
}

/// Room grid columns at the user's [textScale] (pure_live_TV
/// `ThemeSettingsController.cardGridDelegate`: four columns, one fewer up
/// to 130 %, two fewer above).
int tvRoomColumns(double textScale, {int base = 4}) {
  final fewer = textScale > 1.3 ? 2 : (textScale > 1.0 ? 1 : 0);
  return math.max(1, base - fewer);
}

/// Width over height of a room card at [columns] (pure_live_TV
/// `roomCardAspectRatio`).
double tvRoomAspectRatio(int columns) => switch (columns) {
  5 => 1.25,
  6 => 1.5,
  _ => 1.3,
};

/// The palette and sizes of the TV interface below it.
class TvTheme extends InheritedWidget {
  /// Provides [palette].
  const new({required this.palette, required super.child, super.key});

  /// The colours.
  final TvPalette palette;

  /// The palette of [context] (derived from the theme when no [TvTheme] is
  /// above, so pages also work on their own in tests).
  static TvPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvTheme>()?.palette ?? TvPalette.of(Theme.of(context).colorScheme);

  @override
  bool updateShouldNotify(TvTheme oldWidget) => palette != oldWidget.palette;
}

/// The default text and icon colours of the palette (pure_live_TV
/// `TvPaletteDefaults`), over a filled background.
class TvBackground extends StatelessWidget {
  /// Paints the background under [child].
  const new({required this.child, super.key});

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return ColoredBox(
      color: palette.background,
      child: IconTheme(
        data: IconThemeData(color: palette.text, size: scale(28)),
        child: DefaultTextStyle(
          style: scale.style(22, weight: FontWeight.w500, color: palette.text),
          child: child,
        ),
      ),
    );
  }
}
