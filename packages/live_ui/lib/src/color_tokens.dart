// GENERATED from spec/design/tokens.json by packages/live_ui/tool/generate_tokens.py.
// Do not edit by hand; change the tokens and regenerate.

import 'dart:ui';

/// Colour tokens of one theme (spec/design/tokens.json).
final class ColorTokens {
  /// Creates a token set.
  const new({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.inversePrimary,
    required this.success,
    required this.warning,
    required this.focusRing,
  });

  /// Token `primary`.
  final Color primary;

  /// Token `onPrimary`.
  final Color onPrimary;

  /// Token `primaryContainer`.
  final Color primaryContainer;

  /// Token `onPrimaryContainer`.
  final Color onPrimaryContainer;

  /// Token `secondary`.
  final Color secondary;

  /// Token `onSecondary`.
  final Color onSecondary;

  /// Token `secondaryContainer`.
  final Color secondaryContainer;

  /// Token `onSecondaryContainer`.
  final Color onSecondaryContainer;

  /// Token `tertiary`.
  final Color tertiary;

  /// Token `onTertiary`.
  final Color onTertiary;

  /// Token `tertiaryContainer`.
  final Color tertiaryContainer;

  /// Token `onTertiaryContainer`.
  final Color onTertiaryContainer;

  /// Token `error`.
  final Color error;

  /// Token `onError`.
  final Color onError;

  /// Token `errorContainer`.
  final Color errorContainer;

  /// Token `onErrorContainer`.
  final Color onErrorContainer;

  /// Token `surface`.
  final Color surface;

  /// Token `surfaceDim`.
  final Color surfaceDim;

  /// Token `surfaceBright`.
  final Color surfaceBright;

  /// Token `surfaceContainerLowest`.
  final Color surfaceContainerLowest;

  /// Token `surfaceContainerLow`.
  final Color surfaceContainerLow;

  /// Token `surfaceContainer`.
  final Color surfaceContainer;

  /// Token `surfaceContainerHigh`.
  final Color surfaceContainerHigh;

  /// Token `surfaceContainerHighest`.
  final Color surfaceContainerHighest;

  /// Token `onSurface`.
  final Color onSurface;

  /// Token `onSurfaceVariant`.
  final Color onSurfaceVariant;

  /// Token `outline`.
  final Color outline;

  /// Token `outlineVariant`.
  final Color outlineVariant;

  /// Token `inverseSurface`.
  final Color inverseSurface;

  /// Token `inverseOnSurface`.
  final Color inverseOnSurface;

  /// Token `inversePrimary`.
  final Color inversePrimary;

  /// Token `success`.
  final Color success;

  /// Token `warning`.
  final Color warning;

  /// Token `focusRing`.
  final Color focusRing;

  /// The light theme.
  static const light = ColorTokens(
    primary: Color(0xFF0056C2),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF2E6FE0),
    onPrimaryContainer: Color(0xFFFCFAFF),
    secondary: Color(0xFF4B5E89),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFB8CBFE),
    onSecondaryContainer: Color(0xFF425580),
    tertiary: Color(0xFF006572),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF00808F),
    onTertiaryContainer: Color(0xFFF5FDFF),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: Color(0xFFFAF8FF),
    surfaceDim: Color(0xFFD9D9E3),
    surfaceBright: Color(0xFFFAF8FF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF2F3FD),
    surfaceContainer: Color(0xFFEDEDF7),
    surfaceContainerHigh: Color(0xFFE7E7F1),
    surfaceContainerHighest: Color(0xFFE1E2EC),
    onSurface: Color(0xFF191B22),
    onSurfaceVariant: Color(0xFF424753),
    outline: Color(0xFF737785),
    outlineVariant: Color(0xFFC2C6D6),
    inverseSurface: Color(0xFF2E3038),
    inverseOnSurface: Color(0xFFEFF0FA),
    inversePrimary: Color(0xFFAFC6FF),
    success: Color(0xFF1B7236),
    warning: Color(0xFF915600),
    focusRing: Color(0xFF0056C2),
  );

  /// The dark theme.
  static const dark = ColorTokens(
    primary: Color(0xFFAFC6FF),
    onPrimary: Color(0xFF002D6D),
    primaryContainer: Color(0xFF2E6FE0),
    onPrimaryContainer: Color(0xFFFCFAFF),
    secondary: Color(0xFFB3C6F8),
    onSecondary: Color(0xFF1B2F58),
    secondaryContainer: Color(0xFF354873),
    onSecondaryContainer: Color(0xFFA5B8E9),
    tertiary: Color(0xFF4AD8EE),
    onTertiary: Color(0xFF00363D),
    tertiaryContainer: Color(0xFF00808F),
    onTertiaryContainer: Color(0xFFF5FDFF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF11131A),
    surfaceDim: Color(0xFF11131A),
    surfaceBright: Color(0xFF373941),
    surfaceContainerLowest: Color(0xFF0C0E15),
    surfaceContainerLow: Color(0xFF191B22),
    surfaceContainer: Color(0xFF1D1F26),
    surfaceContainerHigh: Color(0xFF272A31),
    surfaceContainerHighest: Color(0xFF32353C),
    onSurface: Color(0xFFE1E2EC),
    onSurfaceVariant: Color(0xFFC2C6D6),
    outline: Color(0xFF8C909F),
    outlineVariant: Color(0xFF424753),
    inverseSurface: Color(0xFFE1E2EC),
    inverseOnSurface: Color(0xFF2E3038),
    inversePrimary: Color(0xFF0059C8),
    success: Color(0xFF6FDD8B),
    warning: Color(0xFFFFB95C),
    focusRing: Color(0xFFAFC6FF),
  );

  /// The black theme.
  static const black = ColorTokens(
    primary: Color(0xFFAFC6FF),
    onPrimary: Color(0xFF002D6D),
    primaryContainer: Color(0xFF2E6FE0),
    onPrimaryContainer: Color(0xFFFCFAFF),
    secondary: Color(0xFFB3C6F8),
    onSecondary: Color(0xFF1B2F58),
    secondaryContainer: Color(0xFF354873),
    onSecondaryContainer: Color(0xFFA5B8E9),
    tertiary: Color(0xFF4AD8EE),
    onTertiary: Color(0xFF00363D),
    tertiaryContainer: Color(0xFF00808F),
    onTertiaryContainer: Color(0xFFF5FDFF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF000000),
    surfaceDim: Color(0xFF000000),
    surfaceBright: Color(0xFF373941),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF0E0E10),
    surfaceContainer: Color(0xFF161618),
    surfaceContainerHigh: Color(0xFF1E1E21),
    surfaceContainerHighest: Color(0xFF1E1E21),
    onSurface: Color(0xFFE6E6E8),
    onSurfaceVariant: Color(0xFFC2C6D6),
    outline: Color(0xFF8C909F),
    outlineVariant: Color(0xFF424753),
    inverseSurface: Color(0xFFE1E2EC),
    inverseOnSurface: Color(0xFF2E3038),
    inversePrimary: Color(0xFF0059C8),
    success: Color(0xFF6FDD8B),
    warning: Color(0xFFFFB95C),
    focusRing: Color(0xFFAFC6FF),
  );
}

/// Tokens that are the same in every theme.
abstract final class FixedColors {
  /// Token `live`.
  static const live = Color(0xFFD92D20);

  /// Token `onLive`.
  static const onLive = Color(0xFFFFFFFF);

  /// Token `brandBlue`.
  static const brandBlue = Color(0xFF2E6FE0);

  /// Token `brandCyan`.
  static const brandCyan = Color(0xFF45D4EA);

  /// Token `brandNight`.
  static const brandNight = Color(0xFF0B1B3F);

  /// Token `playerGround`.
  static const playerGround = Color(0xFF000000);

  /// Token `playerInk`.
  static const playerInk = Color(0xFFFFFFFF);

  /// Token `playerScrim`.
  static const playerScrim = Color(0x99000000);
}
