/// Spacing tokens (spec/design/tokens.json): a 4 dp grid.
abstract final class Space {
  /// Icon to text, badge padding.
  static const double s1 = 4;

  /// Grid gap at compact width, spacing inside cards.
  static const double s2 = 8;

  /// Grid gap at medium and expanded width.
  static const double s3 = 12;

  /// Page margin at compact width, grid gap at large and extra-large width.
  static const double s4 = 16;

  /// Page margin at medium and expanded width.
  static const double s6 = 24;

  /// Page margin at large and extra-large width.
  static const double s8 = 32;

  /// TV horizontal safe margin.
  static const double tvSafeX = 48;

  /// TV vertical safe margin.
  static const double tvSafeY = 28;

  /// TV grid gap.
  static const double tvGutter = 20;
}

/// Corner radius tokens. Video surfaces are never rounded.
abstract final class Radii {
  /// Badges, progress bars, platform logo tiles.
  static const double r1 = 4;

  /// Covers, inputs, menu items; Windows dialogs and menus.
  static const double r2 = 8;

  /// Card containers, side panels, toasts, Android menus.
  static const double r3 = 16;

  /// Android bottom sheets and dialogs.
  static const double r4 = 28;

  /// Buttons, chips, avatars, switches.
  static const double full = 9999;
}

/// Size tokens.
abstract final class Sizes {
  /// Minimum touch and remote target.
  static const double targetTouch = 48;

  /// Minimum pointer target on desktop.
  static const double targetPointer = 32;

  /// Icons in dense information.
  static const double iconDense = 20;

  /// List, toolbar and compact control icons.
  static const double iconMd = 24;

  /// Control icons at expanded width and in fullscreen, TV icons.
  static const double iconLg = 32;

  /// Platform logo on a cover and beside dense text (principles §3.4: the
  /// smallest logo).
  static const double logoSmall = 16;

  /// Platform logo in dense rows and tabs.
  static const double logoMedium = 20;

  /// Platform logo leading a list row, centred on a cover placeholder, and
  /// on TV (principles §3.4). Logos come in these three sizes only.
  static const double logoLarge = 24;

  /// Default chat panel width in the room page at expanded width and above.
  static const double chatWidth = 360;

  /// Maximum readable width of long text pages such as settings.
  static const double readingWidth = 720;
}

/// Motion durations (principles §2.5): three steps.
abstract final class Motion {
  /// Small state changes.
  static const short = Duration(milliseconds: 100);

  /// Most transitions.
  static const medium = Duration(milliseconds: 200);

  /// Large layout changes.
  static const long = Duration(milliseconds: 300);
}
