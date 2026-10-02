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

  /// The round backing of the lock button at the side of a fullscreen
  /// picture (3.x `LockButton`: 38 % black).
  static const Color lockBacking = Color(0x61000000);

  /// The followed chip on the picture ("✓ 已关注" in fullscreen, U.2c).
  static const Color followChip = Color(0x2EFFFFFF);

  /// The portrait fullscreen's entry hint (3.x: 66 % black).
  static const Color hint = Color(0xA8000000);

  /// The hint's outline (16 % white).
  static const Color hintOutline = Color(0x29FFFFFF);

  /// The veil over the ambient background (3.x: 15 % black).
  static const Color ambientVeil = Color(0x26000000);

  /// The ambient background before (or without) the cover: 3.x's gradient.
  static const LinearGradient ambientFallback = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF342B3A), Color(0xFF171B27), Color(0xFF2A202B)],
  );

  /// The outline of a text field on the picture (the fullscreen local
  /// danmaku composer, white 24 %).
  static const Color fieldOutline = Color(0x3DFFFFFF);

  /// A dark stage standing for the picture where there is none: the local
  /// danmaku style's preview (3.x's gradient, top left to bottom right).
  static const List<Color> stage = [Color(0xFF27344D), Color(0xFF101623), Color(0xFF06080E)];

  /// The faint television drawn in the middle of [stage] (white 10 %).
  static const Color stageMark = Color(0x1AFFFFFF);

  /// The "实时预览" mark on [stage] (black 38 %).
  static const Color stageBadge = Color(0x61000000);

  /// The dark end of a banner over the picture (the local gift effect,
  /// black 78 %).
  static const Color bannerEnd = Color(0xC7000000);

  /// The thin outline of a banner over the picture (white 45 %).
  static const Color bannerOutline = Color(0x73FFFFFF);

  /// Errors on the picture (a failed multi-view cell): the dark theme's
  /// error tone, readable on black in every theme.
  static const Color error = Color(0xFFFFB4AB);

  /// Marks on [error] (the "!" of a failed recording's glyph, U.2a2): the
  /// dark theme's on-error tone.
  static const Color onError = Color(0xFF690005);

  /// The user's colour on the picture (the selected multi-view cell's
  /// outline, the picked cell's dashed frame): the light tone of the
  /// primary colour in both themes, since the picture is always black.
  static Color accent(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? scheme.inversePrimary : scheme.primary;

  /// The soft shadow under icons and text on the picture.
  static const Color shadow = Color(0x99000000);

  /// [shadow] as text and icon shadows.
  static const List<Shadow> shadows = [Shadow(color: shadow, blurRadius: 6)];

  /// Icons of the control bars: white, with [shadows].
  static const IconThemeData icons = IconThemeData(color: foreground, size: 24, shadows: shadows);

  /// The lighter dimming of a state over a moving picture (45 %: the
  /// reconnecting message, docs/ui/compare/U.2g c13).
  static const Color dimLight = Color(0x73000000);

  /// The text of a state's main button (on a [foreground] fill, U.2g c2).
  static const Color buttonInk = Color(0xFF191C20);

  /// The fill of a state's second button (outlined with [buttonOutline]).
  static const Color buttonFill = Color(0x59000000);

  /// The outline of a state's second button.
  static const Color buttonOutline = Color(0x73FFFFFF);

  /// The ring around a streamer's picture in a state (offline, carousel).
  static const Color avatarRing = Color(0x47FFFFFF);

  /// The round disc under a mini window's buttons (U.2j: 45 % black, 3.x
  /// `Colors.black45`), so they read on a bright picture without a blur.
  static const Color button = Color(0x73000000);

  /// The shadow of the in-app floating window (U.2j c10: square corners and
  /// a floating shadow instead of clipping the video round).
  static const List<BoxShadow> floatingShadow = [
    BoxShadow(color: Color(0x61000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

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

  /// The gold of a super chat's price and "SC" mark (3.x `SuperChatCard`'s
  /// amber icons, docs/ui/compare/U.2e).
  static const Color superChatGold = Color(0xFFFFC107);

  /// Text and dots on [live].
  static const Color onLive = Color(0xFFFFFFFF);

  /// The recording dot and the "录制中" mark.
  static const Color recording = Color(0xFFD92D20);

  /// Text and dots on [recording].
  static const Color onRecording = Color(0xFFFFFFFF);

  /// The soft ring around a recording button (its resting tone: the halo
  /// breathes between 15 % and 45 % of [recording], docs/ui/compare/U.2a2).
  static const Color recordingHalo = Color(0x4DD92D20);

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

  /// The ground of a reminder bar (mobile data, docs/ui/compare/U.1c c8),
  /// light themes; its text is the theme's `onSurface`.
  static const Color warningContainerLight = Color(0xFFFFF4E5);

  /// [warningContainerLight] in dark themes.
  static const Color warningContainerDark = Color(0xFF3A2A0E);

  /// The reminder bar's ground for [brightness].
  static Color warningContainer(Brightness brightness) =>
      brightness == Brightness.dark ? warningContainerDark : warningContainerLight;

  /// A warm container next to the theme's primary container (IPTV guides
  /// beside playlists, docs/ui/compare/U.9), light themes.
  static const Color warmContainerLight = Color(0xFFFFDDB8);

  /// Text and icons on [warmContainerLight].
  static const Color onWarmContainerLight = Color(0xFF4A2800);

  /// The warm container in dark themes.
  static const Color warmContainerDark = Color(0xFF5C3A12);

  /// Text and icons on [warmContainerDark].
  static const Color onWarmContainerDark = Color(0xFFFFDDB8);

  /// The warm container for [brightness].
  static Color warmContainer(Brightness brightness) =>
      brightness == Brightness.dark ? warmContainerDark : warmContainerLight;

  /// Text and icons on [warmContainer] for [brightness].
  static Color onWarmContainer(Brightness brightness) =>
      brightness == Brightness.dark ? onWarmContainerDark : onWarmContainerLight;

  /// The soft ground of a "recording" note in light themes (the close
  /// dialog's "正在录制 2 个直播间", docs/ui/compare/U.13 c9); its text is the
  /// theme's error colour.
  static const Color recordingNoteLight = Color(0xFFFCEEEE);

  /// [recordingNoteLight] in dark themes.
  static const Color recordingNoteDark = Color(0xFF3A1A18);

  /// The recording note's ground for [brightness].
  static Color recordingNote(Brightness brightness) =>
      brightness == Brightness.dark ? recordingNoteDark : recordingNoteLight;
}

/// The desktop title bar's fixed colours (docs/ui/compare/U.13): its close
/// button turns Windows' red under the pointer in every theme (3.x
/// `CustomTitleBar`).
abstract final class WindowButtonColors {
  /// The close button under the pointer (`#E81123`, as Windows draws it).
  static const Color closeHover = Color(0xFFE81123);

  /// The close icon on [closeHover].
  static const Color onCloseHover = Color(0xFFFFFFFF);
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

  /// Opaque dark ink for [contrastOn].
  static const Color ink = Color(0xFF18181A);

  /// Secondary dark ink (62 %).
  static const Color inkMuted = Color(0x9E18181A);

  /// Secondary light ink (80 %).
  static const Color lightMuted = Color(0xCCFFFFFF);

  /// Whether dark [ink] has the higher contrast on [background] (WCAG
  /// ratios). 3.x split at a luminance of 0.55, which put white on mid
  /// golds at 1.9:1 (docs/ui/compare/U.2e S2).
  static bool darkInkOn(Color background) {
    final luminance = background.withValues(alpha: 1).computeLuminance();
    final darkRatio = (luminance + 0.05) / (ink.computeLuminance() + 0.05);
    final lightRatio = 1.05 / (luminance + 0.05);
    return darkRatio >= lightRatio;
  }

  /// [ink] or [light], whichever reads better on [background].
  static Color contrastOn(Color background) => darkInkOn(background) ? ink : light;

  /// The secondary form of [contrastOn].
  static Color contrastMutedOn(Color background) => darkInkOn(background) ? inkMuted : lightMuted;
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
