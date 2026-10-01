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
