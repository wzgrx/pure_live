/// Theme mode (spec/design/principles.md §2: pure black is a separate switch
/// that applies whenever the theme is dark).
enum AppThemeMode {
  /// Follow the system.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// First page after launch (spec/design/principles.md §4.1).
enum StartPage {
  /// The follow list; the default.
  follows,

  /// Discover.
  discover,
}

/// Preferred stream quality class (spec/modules/store.md §6.4.1). The player
/// picks the platform quality closest to it.
enum QualityPreference {
  /// Source quality (原画).
  original,

  /// Blu-ray 8 Mbps (蓝光8M).
  bluRay8M,

  /// Blu-ray 4 Mbps (蓝光4M).
  bluRay4M,

  /// Super high (超清).
  superHigh,

  /// Smooth (流畅).
  smooth,
}

/// How video fills its box.
enum VideoFit {
  /// Fit inside, letterboxed.
  contain,

  /// Fill and crop.
  cover,

  /// Stretch.
  fill,

  /// Fit the height.
  fitHeight,

  /// Fit the width.
  fitWidth,

  /// Like [contain], but never upscale.
  scaleDown,
}

/// Display refresh-rate policy on Android.
enum RefreshRateMode {
  /// Leave the rate to the system; the default for new installs.
  powerSaving,

  /// High rate while the user interacts.
  balanced,

  /// High rate while the app is in the foreground.
  performance,
}

/// Room card preset of 3.x (store.md §1.5); v4 keeps only density.
enum CardPreset {
  /// Compact.
  compact,

  /// Normal.
  normal,

  /// Rich.
  rich,

  /// Custom.
  custom,
}

/// What closing the main desktop window does (spec/product.md F-WIN-04);
/// names match 3.x `exitChoose`.
enum CloseAction {
  /// Quit the app.
  exit,

  /// Hide the window; the tray icon brings it back.
  minimize,
}

/// TV mode (spec/design/principles.md §5.1 rule 1): follow the device, or
/// force it on (projectors, boxes that misreport their type) or off.
enum TvMode {
  /// On when the platform reports a television (Android UI mode or the
  /// leanback feature); the default.
  auto,

  /// Always on.
  on,

  /// Always off.
  off,
}
