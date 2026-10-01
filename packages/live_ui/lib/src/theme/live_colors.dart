import 'package:flutter/material.dart';

/// Colours of everything drawn over the video: the control bars, their text
/// and icons, the status messages and the gesture cards (docs/ui/UI_PLAN.md
/// §6.1: the picture area is black with white controls in every theme).
///
/// Pages use these roles instead of `Colors.white` and friends, so the look
/// over the picture is decided here once.
abstract final class OnVideoColors {
  /// Behind the picture (letterboxing, fullscreen, picture-in-picture).
  static const Color ground = Color(0xFF000000);

  /// Text and icons of the controls.
  static const Color foreground = Color(0xFFFFFFFF);

  /// Secondary text over the picture (a programme line, a hint).
  static const Color secondary = Color(0xB3FFFFFF);

  /// A control over the picture that cannot be used now.
  static const Color disabled = Color(0x61FFFFFF);

  /// The darkest end of the shade under a control bar: 60 % black, on which
  /// white text keeps 5.7:1 even over a white picture.
  static const Color scrim = Color(0x99000000);

  /// The middle of the shade, where it reaches into the picture.
  static const Color scrimMid = Color(0x4D000000);

  /// The faded end of the shade.
  static const Color clear = Color(0x00000000);

  /// The dimming behind a message over the picture (failed, offline).
  static const Color dim = Color(0x8A000000);

  /// The audio-only cover's dimming over the room's cover picture.
  static const Color coverDim = Color(0xB3000000);

  /// The card of the brightness and volume gestures.
  static const Color panel = Color(0xDD000000);

  /// The empty part of a level bar on [panel].
  static const Color track = Color(0x3DFFFFFF);

  /// A filled chip on the picture (stream picker, aspect ratio).
  static const Color chip = Color(0x29FFFFFF);

  /// The outline of a chip on the picture.
  static const Color chipOutline = Color(0x66FFFFFF);

  /// A control that is switched away from its default (3.x's yellow for
  /// audio only and a fixed orientation).
  static const Color active = Color(0xFFFFD166);

  /// The soft shadow under icons and text on the picture.
  static const Color shadow = Color(0x99000000);

  /// [shadow] as text and icon shadows.
  static const List<Shadow> shadows = [Shadow(color: shadow, blurRadius: 6)];

  /// Icons of the control bars: white, with [shadows].
  static const IconThemeData icons = IconThemeData(color: foreground, size: 24, shadows: shadows);

  /// The shade of a bar along the [edge] of the picture: [scrim] at the edge,
  /// fading out into the picture.
  static LinearGradient shade({required VerticalDirection edge}) => LinearGradient(
    begin: edge == VerticalDirection.up ? Alignment.topCenter : Alignment.bottomCenter,
    end: edge == VerticalDirection.up ? Alignment.bottomCenter : Alignment.topCenter,
    colors: const [scrim, scrimMid, clear],
    stops: const [0, 0.55, 1],
  );
}

/// Fixed semantic colours: they keep their meaning whatever the user's theme
/// colour is (UI_PLAN §6.1; values and contrast from the archived v4 design
/// tokens).
abstract final class LiveSemanticColors {
  /// The "直播" mark: 4.8:1 with white text. Always shown with the word, not
  /// as a dot alone.
  static const Color live = Color(0xFFD92D20);

  /// Text and dots on [live].
  static const Color onLive = Color(0xFFFFFFFF);

  /// The recording dot and the "录制中" mark.
  static const Color recording = Color(0xFFD92D20);

  /// Text and dots on [recording].
  static const Color onRecording = Color(0xFFFFFFFF);

  /// The soft ring around a recording button.
  static const Color recordingHalo = Color(0x40D92D20);

  /// Success text and icons in light themes (4.6:1 on every surface).
  static const Color successLight = Color(0xFF1B7236);

  /// Success text and icons in dark themes.
  static const Color successDark = Color(0xFF6FDD8B);

  /// Warning text and icons in light themes (4.6:1 on every surface).
  static const Color warningLight = Color(0xFF915600);

  /// Warning text and icons in dark themes.
  static const Color warningDark = Color(0xFFFFB95C);

  /// The success colour for [brightness].
  static Color success(Brightness brightness) => brightness == Brightness.dark ? successDark : successLight;

  /// The warning colour for [brightness].
  static Color warning(Brightness brightness) => brightness == Brightness.dark ? warningDark : warningLight;
}

/// Text on a colour the platform chose (super chat cards, a viewer's
/// danmaku colour): dark ink on light colours, white on dark ones.
abstract final class InkOnColor {
  /// Dark text.
  static const Color dark = Color(0xDD000000);

  /// Secondary dark text.
  static const Color darkMuted = Color(0x8A000000);

  /// Light text.
  static const Color light = Color(0xFFFFFFFF);

  /// The ink that reads on [background].
  static Color on(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? light : dark;
}

/// Text helpers of the design system.
extension LiveTextStyleX on TextStyle {
  /// Digits of equal width, so counts and clocks do not jump as they change
  /// (UI_PLAN §6.2).
  TextStyle get tabular => copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// The regular weight (400); the design uses only 400 and 600.
  TextStyle get regular => copyWith(fontWeight: FontWeight.w400);

  /// The emphasis weight (600).
  TextStyle get emphasis => copyWith(fontWeight: FontWeight.w600);
}

/// The surfaces of the "pure black" dark theme (U.6b C-4): black behind the
/// pages, a few near-black layers for cards and sheets, so OLED screens
/// stay dark and the layers still read apart.
abstract final class LivePureBlack {
  /// Pages (`surface`).
  static const Color surface = Color(0xFF000000);

  /// Cards and settings groups (`surfaceContainerLow`).
  static const Color containerLow = Color(0xFF0E0E10);

  /// `surfaceContainer`.
  static const Color container = Color(0xFF161618);

  /// Dialogs, search fields (`surfaceContainerHigh`).
  static const Color containerHigh = Color(0xFF1E1E21);

  /// Menus and chips (`surfaceContainerHighest`).
  static const Color containerHighest = Color(0xFF26262A);

  /// [scheme] (a dark scheme) with the black surfaces.
  static ColorScheme apply(ColorScheme scheme) => scheme.copyWith(
    surface: surface,
    surfaceDim: surface,
    surfaceBright: containerHighest,
    surfaceContainerLowest: surface,
    surfaceContainerLow: containerLow,
    surfaceContainer: container,
    surfaceContainerHigh: containerHigh,
    surfaceContainerHighest: containerHighest,
  );
}

/// The colour swatches of the colour picker (3.x `AppConsts.themeColors`
/// and flex_color_picker's Material lists).
abstract final class LivePalettes {
  /// The app's colours, first in the picker (3.x's "自定义" tab, renamed
  /// "推荐" in U.6b): the brand blue, then 3.x's fourteen in its order.
  static const List<(String name, Color color)> recommended = [
    ('Brand', Color(0xFF2E6FE0)),
    ('Crimson', Color.fromARGB(255, 220, 20, 60)),
    ('Orange', Color(0xFFFF9800)),
    ('Chrome', Color.fromARGB(255, 230, 184, 0)),
    ('Grass', Color(0xFF8BC34A)),
    ('Teal', Color(0xFF009688)),
    ('SeaFoam', Color.fromARGB(255, 112, 193, 207)),
    ('Ice', Color.fromARGB(255, 115, 155, 208)),
    ('Blue', Color(0xFF2196F3)),
    ('Indigo', Color(0xFF3F51B5)),
    ('Violet', Color(0xFF673AB7)),
    ('Primary', Color(0xFF6200EE)),
    ('Orchid', Color.fromARGB(255, 218, 112, 214)),
    ('Variant', Color(0xFF3700B3)),
    ('Secondary', Color(0xFF03DAC6)),
  ];

  /// Material's primary colours and grey (the "常用色" tab).
  static final List<ColorSwatch<int>> primaries = [...Colors.primaries, Colors.grey];

  /// Material's accent colours (the "鲜艳色" tab).
  static const List<ColorSwatch<int>> accents = Colors.accents;

  /// Ten shades of [color], light to dark, with [color] itself in the
  /// middle (index 5), for colours that are not a Material swatch.
  static List<Color> shadesOf(Color color) {
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    return [
      for (final t in const [0.9, 0.76, 0.6, 0.44, 0.22]) Color.lerp(color, white, t)!,
      color,
      for (final t in const [0.12, 0.24, 0.36, 0.5]) Color.lerp(color, black, t)!,
    ];
  }

  /// The shades of a Material [swatch], light to dark.
  static List<Color> swatchShades(ColorSwatch<int> swatch) {
    final keys = swatch[50] == null
        ? const [100, 200, 400, 700]
        : const [50, 100, 200, 300, 400, 500, 600, 700, 800, 900];
    return [for (final key in keys) ?swatch[key]];
  }
}

/// Colours of the television style (UI_PLAN §5.5).
abstract final class LiveTvColors {
  /// The near-white frame of the focused item.
  static const Color focusFrame = Color(0xFFF2F2F2);
}
