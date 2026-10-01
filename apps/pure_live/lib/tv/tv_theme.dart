import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';

// The TV look (docs/ui/compare/U.15a): the phone's dark colour roles seeded
// with the user's theme colour (choice A2), sizes drafted on the 960 x 540
// canvas of a 1080p television, text one step above the phone (at least 14),
// and room grids whose columns follow the text size.

/// The colours of the TV interface: the phone's dark colour roles (U.15a c4,
/// choice A2), so the TV and the phone are one palette seeded with the
/// user's theme colour. The TV is dark only (U.6b → U.15i).
@immutable
final class TvPalette {
  /// Creates the palette of [scheme] (a dark scheme).
  const new(this.scheme);

  /// The palette of [scheme]; a light scheme is replaced by the dark one of
  /// the same primary colour.
  factory of(ColorScheme scheme) => TvPalette(
    scheme.brightness == Brightness.dark
        ? scheme
        : ColorScheme.fromSeed(seedColor: scheme.primary, brightness: Brightness.dark),
  );

  /// The colour roles.
  final ColorScheme scheme;

  /// The page background (`surface`).
  Color get background => scheme.surface;

  /// The side menu and settings cards (`surfaceContainerLow`).
  Color get low => scheme.surfaceContainerLow;

  /// An idle card or tab (`surfaceContainer`).
  Color get card => scheme.surfaceContainer;

  /// A focused card, a dialog (`surfaceContainerHigh`).
  Color get raised => scheme.surfaceContainerHigh;

  /// A button, a focused row (`surfaceContainerHighest`).
  Color get highest => scheme.surfaceContainerHighest;

  /// Main text.
  Color get text => scheme.onSurface;

  /// Secondary text: names under titles, descriptions, idle icons (P5).
  Color get textSecondary => scheme.onSurfaceVariant;

  /// Accents: the main action's text, a current choice, progress.
  Color get accent => scheme.primary;

  /// Text and ticks on [accent].
  Color get onAccent => scheme.onPrimary;

  /// What is selected (the current tab, the destination): a fill (U.15a c3).
  Color get selected => scheme.primaryContainer;

  /// Text and icons on [selected].
  Color get onSelected => scheme.onPrimaryContainer;

  /// Deleting and unfollowing.
  Color get danger => scheme.error;

  /// Outlines (an unticked box, a switch that is off).
  Color get outline => scheme.outline;

  /// Separators.
  Color get divider => scheme.outlineVariant;

  /// The focus ring (near white, the same on every theme colour).
  Color get focusRing => TvColors.focusRing;

  @override
  bool operator ==(Object other) => other is TvPalette && other.scheme == scheme;

  @override
  int get hashCode => scheme.hashCode;
}

/// Sizes of the TV interface, scaled to the screen.
///
/// New components draw on the 960 x 540 canvas of a 1080p television ([px]:
/// the logical pixels of docs/ui/compare/U.15a); the room keeps pure_live_TV's
/// 1920 x 1080 drafts ([call]) until U.15d redraws it.
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

  /// The panel the 1080p drafts are drawn for.
  static const double designWidth = 1920;

  /// The panel the 1080p drafts are drawn for.
  static const double designHeight = 1080;

  /// Logical pixels per design pixel.
  final double unit;

  /// The text scale in force (the user's size times the panel lift).
  final double textScale;

  /// [design] pixels (1920 x 1080 drafts) as logical pixels.
  double call(num design) => design * unit;

  /// [design] pixels of a box that holds text: grows with the text (3.x's
  /// `.ts(context)`), so labels are never clipped at a large text size.
  double text(num design) => design * unit * textScale;

  /// [canvas] pixels of the 960 x 540 canvas as logical pixels.
  double px(num canvas) => canvas * unit * 2;

  /// [canvas] pixels of a box that holds text (grows with the text).
  double pxText(num canvas) => canvas * unit * 2 * textScale;

  /// A text style of [size] design pixels.
  TextStyle style(num size, {FontWeight? weight, Color? color, double? height}) =>
      TextStyle(fontSize: size * unit, fontWeight: weight, color: color, height: height);

  /// A text style of [size] canvas pixels (U.15a c5: at least 14).
  TextStyle font(num size, {FontWeight? weight, Color? color, double? height}) =>
      TextStyle(fontSize: px(size), fontWeight: weight, color: color, height: height);

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

/// The text sizes of the TV (U.15a c5), in canvas pixels: one step above the
/// phone, never under 14.
abstract final class TvTextSize {
  /// Dialog titles, status titles, page titles.
  static const double title = 22;

  /// A room card's name (the streamer in the card dialog).
  static const double heading = 20;

  /// Settings row titles.
  static const double row = 17;

  /// Body text, buttons, card titles, options.
  static const double body = 16;

  /// Secondary lines: streamer names, descriptions, chips, counts.
  static const double small = 14;
}

/// Corner radii of the TV (U.15a), in canvas pixels.
abstract final class TvRadius {
  /// Cards, rows, options, inputs.
  static const double card = 12;

  /// Settings cards.
  static const double group = 16;

  /// Dialogs.
  static const double dialog = 24;

  /// Pills (buttons, tabs) are fully round.
  static const double pill = 999;
}

/// How long the focus takes to arrive (U.15a c1); leaving does not animate,
/// so a held arrow never leaves a trail of half-lit items.
const Duration tvFocusDuration = Duration(milliseconds: 120);

/// Room grid columns at the user's [textScale] (pure_live_TV
/// `ThemeSettingsController.cardGridDelegate`: four columns, one fewer up
/// to 130 %, two fewer above).
int tvRoomColumns(double textScale, {int base = 4}) {
  final fewer = textScale > 1.3 ? 2 : (textScale > 1.0 ? 1 : 0);
  return math.max(1, base - fewer);
}

/// The palette of the TV interface below it, and whether focused items grow
/// (the `tvFocusZoom` setting, U.15a c2).
class TvTheme extends InheritedWidget {
  /// Provides [palette].
  const new({required this.palette, required super.child, this.zoom = true, super.key});

  /// The colours.
  final TvPalette palette;

  /// Focused cards, buttons and tabs grow by 5 % (off on slow boxes).
  final bool zoom;

  /// The palette of [context] (derived from the theme when no [TvTheme] is
  /// above, so components also work on their own in tests).
  static TvPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvTheme>()?.palette ?? TvPalette.of(Theme.of(context).colorScheme);

  /// Whether focused items grow below [context].
  static bool zoomOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvTheme>()?.zoom ?? true;

  @override
  bool updateShouldNotify(TvTheme oldWidget) => palette != oldWidget.palette || zoom != oldWidget.zoom;
}

/// The default text and icon colours of the palette, over the page
/// background.
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
        data: IconThemeData(color: palette.textSecondary, size: scale.px(24)),
        child: DefaultTextStyle(
          style: scale.font(TvTextSize.body, color: palette.text),
          child: child,
        ),
      ),
    );
  }
}
