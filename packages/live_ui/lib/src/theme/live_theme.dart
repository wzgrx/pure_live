import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// The page transitions of 3.x (`appPageTransitionsTheme`).
///
/// Android keeps the system back dispatch but lets an unclaimed gesture commit
/// through the Navigator's regular pop: Flutter's gesture-owned shared element
/// transition can keep input after its visual commit on some Android/ColorOS
/// versions (Pure Live #852; flutter/flutter#153577).
const PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
  },
);

/// Resolves the app-wide font without overriding a platform's own default.
///
/// A downloaded font is registered under its stored id and wins. Windows keeps
/// Microsoft YaHei as its CJK default; every other platform gets null so
/// Flutter follows the device's system font and fallback chain.
String? resolveAppFontFamily({
  required String selectedName,
  required Iterable<String> customFonts,
  required bool isWindows,
}) {
  if (customFonts.contains(selectedName)) return selectedName;
  if (isWindows) return 'Microsoft YaHei';
  return null;
}

/// The five font sizes of the font settings (3.x `FontSettingsController`);
/// every text style of the theme is derived from them.
@immutable
final class LiveFontSizes {
  /// Creates the sizes; the defaults are those of 3.x.
  const new({
    this.bodySmall = 12,
    this.bodyMedium = 13,
    this.bodyLarge = 14,
    this.titleMedium = 15,
    this.titleLarge = 20,
  });

  /// The sizes [textTheme] was built with by [LiveTheme] (the defaults
  /// where a style has no size).
  factory of(TextTheme textTheme) {
    const defaults = LiveFontSizes();
    return LiveFontSizes(
      bodySmall: textTheme.bodySmall?.fontSize ?? defaults.bodySmall,
      bodyMedium: textTheme.bodyMedium?.fontSize ?? defaults.bodyMedium,
      bodyLarge: textTheme.bodyLarge?.fontSize ?? defaults.bodyLarge,
      titleMedium: textTheme.titleMedium?.fontSize ?? defaults.titleMedium,
      titleLarge: textTheme.titleLarge?.fontSize ?? defaults.titleLarge,
    );
  }

  /// Small helper text (`fontSizeBodySmall`).
  final double bodySmall;

  /// Body text (`fontSizeBodyMedium`).
  final double bodyMedium;

  /// Emphasised body text (`fontSizeBodyLarge`).
  final double bodyLarge;

  /// Card titles (`fontSizeTitleMedium`).
  final double titleMedium;

  /// App bar titles (`fontSizeTitleLarge`).
  final double titleLarge;

  @override
  bool operator ==(Object other) =>
      other is LiveFontSizes &&
      other.bodySmall == bodySmall &&
      other.bodyMedium == bodyMedium &&
      other.bodyLarge == bodyLarge &&
      other.titleMedium == titleMedium &&
      other.titleLarge == titleLarge;

  @override
  int get hashCode => Object.hash(bodySmall, bodyMedium, bodyLarge, titleMedium, titleLarge);
}

/// The app theme (3.x `MyTheme` plus the overrides 3.x's `main.dart` put on
/// top of it).
///
/// Either a seed colour ([primaryColor], the user's theme colour) or a whole
/// [colorScheme] (the system's dynamic palette, see `toFlutterColorScheme`)
/// is given, never both.
@immutable
final class LiveTheme {
  /// Creates the theme.
  ///
  /// [schemeVariant] picks how a seed colour becomes the palette (null keeps
  /// Material's default, tonal spot; the app passes fidelity so the primary
  /// stays the chosen colour, U.6b C-3). [pureBlack] darkens the dark
  /// theme's surfaces to black (U.6b C-4); the light theme ignores it.
  const new({
    this.primaryColor,
    this.colorScheme,
    this.fontSizes = const LiveFontSizes(),
    this.fontFamily,
    this.schemeVariant,
    this.pureBlack = false,
  }) : assert(colorScheme == null || primaryColor == null, 'give a seed colour or a colour scheme, not both');

  /// The default theme colour (U.6b C-3): a brand blue that, with
  /// [DynamicSchemeVariant.fidelity], keeps 4.5:1 for white text.
  static const Color brandBlue = Color(0xFF2E6FE0);

  /// 3.x's default theme colour (`Colors.blue`), moved to [brandBlue].
  static const Color legacyBlue = Color(0xFF2196F3);

  /// Regular weight.
  static const FontWeight regular = FontWeight.w400;

  /// Medium weight.
  static const FontWeight medium = FontWeight.w500;

  /// Semi-bold weight.
  static const FontWeight semiBold = FontWeight.w600;

  /// Bold weight.
  static const FontWeight bold = FontWeight.w700;

  /// The error colour of a dark dynamic palette (3.x replaced the system's).
  static const Color darkDynamicError = Color(0xFFFF6347);

  /// The seed colour.
  final Color? primaryColor;

  /// A complete palette (dynamic colour), used for both brightnesses as given.
  final ColorScheme? colorScheme;

  /// The font sizes.
  final LiveFontSizes fontSizes;

  /// The font family, see [resolveAppFontFamily].
  final String? fontFamily;

  /// How [primaryColor] becomes the palette; null is Material's default.
  final DynamicSchemeVariant? schemeVariant;

  /// Black surfaces in the dark theme ([LivePureBlack]).
  final bool pureBlack;

  /// The light theme.
  ThemeData get light => _build(Brightness.light);

  /// The dark theme.
  ThemeData get dark => _build(Brightness.dark);

  TextTheme _textTheme(TextTheme base) {
    final localized = fontFamily != null ? base.apply(fontFamily: fontFamily) : base;
    TextStyle scale(TextStyle? style, double size) => (style ?? const TextStyle()).copyWith(fontSize: size);
    final sizes = fontSizes;
    return localized.copyWith(
      displayLarge: scale(localized.displayLarge, sizes.bodySmall * 4.75),
      displayMedium: scale(localized.displayMedium, sizes.bodySmall * 3.75),
      displaySmall: scale(localized.displaySmall, sizes.bodySmall * 3.0),
      headlineLarge: scale(localized.headlineLarge, sizes.titleLarge * 1.6),
      headlineMedium: scale(localized.headlineMedium, sizes.titleLarge * 1.4),
      headlineSmall: scale(localized.headlineSmall, sizes.titleLarge * 1.2),
      titleLarge: scale(localized.titleLarge, sizes.titleLarge).copyWith(fontWeight: semiBold),
      titleMedium: scale(localized.titleMedium, sizes.titleMedium).copyWith(fontWeight: medium),
      titleSmall: scale(localized.titleSmall, sizes.bodyLarge).copyWith(fontWeight: medium),
      bodyLarge: scale(localized.bodyLarge, sizes.bodyLarge),
      bodyMedium: scale(localized.bodyMedium, sizes.bodyMedium),
      bodySmall: scale(localized.bodySmall, sizes.bodySmall),
      labelLarge: scale(localized.labelLarge, sizes.bodyMedium).copyWith(fontWeight: medium),
      labelMedium: scale(localized.labelMedium, sizes.bodySmall),
      labelSmall: scale(localized.labelSmall, sizes.bodySmall - 1),
    );
  }

  ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    var scheme = colorScheme;
    if (isDark && scheme != null) scheme = scheme.copyWith(error: darkDynamicError);
    final seed = primaryColor;
    if (scheme == null && seed != null && (schemeVariant != null || (isDark && pureBlack))) {
      scheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: schemeVariant ?? DynamicSchemeVariant.tonalSpot,
      );
    }
    if (isDark && pureBlack && scheme != null) scheme = LivePureBlack.apply(scheme);
    final textTheme = _textTheme(isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme);
    final base = ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      colorSchemeSeed: scheme == null ? primaryColor : null,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
    );
    final colors = base.colorScheme;
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      // 3.x's main.dart replaced MyTheme's app bar theme (flat, centred title)
      // with this one, so app bars keep the platform's title alignment and
      // Material's defaults; this is what 3.x showed.
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
      pageTransitionsTheme: appPageTransitionsTheme,
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        tabAlignment: TabAlignment.center,
        labelStyle: textTheme.titleMedium?.copyWith(fontWeight: semiBold),
        unselectedLabelStyle: textTheme.titleMedium?.copyWith(fontWeight: regular),
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant.withValues(alpha: 0.8),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: semiBold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: medium),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: medium),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        leadingAndTrailingTextStyle: textTheme.labelMedium,
        selectedColor: colors.primary,
        selectedTileColor: colors.primary.withValues(alpha: 0.06),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        showDragHandle: true,
        backgroundColor: colors.surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colors.surfaceContainerHigh,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: semiBold),
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveTheme &&
      other.primaryColor == primaryColor &&
      other.colorScheme == colorScheme &&
      other.fontSizes == fontSizes &&
      other.fontFamily == fontFamily &&
      other.schemeVariant == schemeVariant &&
      other.pureBlack == pureBlack;

  @override
  int get hashCode => Object.hash(primaryColor, colorScheme, fontSizes, fontFamily, schemeVariant, pureBlack);
}
