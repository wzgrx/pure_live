import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/metrics.dart';
import 'package:live_ui/src/widgets/app_chip.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';

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

/// `AppBar.centerTitle` of the pages whose title 3.x centred: the recorder,
/// the follows, the areas, popular, the history and the toolbox (3.x set
/// `centerTitle: true` on each; its theme's own `centerTitle` never took
/// effect, `main.dart:162-169` replaced the whole app bar theme). Every
/// other page keeps the platform's alignment, the start on Android.
const bool centredPageTitle = true;

/// A button's outline: the keyboard focus frame (2 points in the primary
/// colour, docs/A-界面设计/A02-组件/A02.1-通用组件 c21) while the keyboard focus is on it,
/// else [outline] ([disabledOutline] when disabled), or none. Equal frames
/// compare equal, so a rebuilt theme does not animate.
@immutable
final class FocusFrame implements WidgetStateProperty<BorderSide?> {
  /// Creates the frame in [primary].
  const new(this.primary, {this.outline, this.disabledOutline});

  /// The frame's colour.
  final Color primary;

  /// The outline when not focused (an outlined button); null: none.
  final Color? outline;

  /// The outline when disabled.
  final Color? disabledOutline;

  @override
  BorderSide? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.focused) && focusFramesShown) return BorderSide(color: primary, width: 2);
    if (states.contains(WidgetState.disabled) && disabledOutline != null) return BorderSide(color: disabledOutline!);
    return outline == null ? null : BorderSide(color: outline!);
  }

  @override
  bool operator ==(Object other) =>
      other is FocusFrame &&
      other.primary == primary &&
      other.outline == outline &&
      other.disabledOutline == disabledOutline;

  @override
  int get hashCode => Object.hash(primary, outline, disabledOutline);
}

/// The tint of a tab under the pointer and when pressed (U.1c c12).
@immutable
final class _TabOverlay implements WidgetStateProperty<Color?> {
  const new(this.ink);

  final Color ink;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) return ink.withValues(alpha: 0.12);
    if (states.contains(WidgetState.hovered)) return ink.withValues(alpha: 0.08);
    return Colors.transparent;
  }

  @override
  bool operator ==(Object other) => other is _TabOverlay && other.ink == ink;

  @override
  int get hashCode => ink.hashCode;
}

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

  /// Semi-bold weight. The design uses only [regular] and this (UI.md §8.2:
  /// Microsoft YaHei has no 500, so a medium weight renders as a blurred
  /// faux bold on Windows); 3.x's 500 and 700 became 600 (A01.2).
  static const FontWeight semiBold = FontWeight.w600;

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
      // 3.x's 500 (theme.dart:76-77, :83) is 600 here (A01.2, UI.md §8.2).
      titleMedium: scale(localized.titleMedium, sizes.titleMedium).copyWith(fontWeight: semiBold),
      titleSmall: scale(localized.titleSmall, sizes.bodyLarge).copyWith(fontWeight: semiBold),
      bodyLarge: scale(localized.bodyLarge, sizes.bodyLarge),
      bodyMedium: scale(localized.bodyMedium, sizes.bodyMedium),
      bodySmall: scale(localized.bodySmall, sizes.bodySmall),
      labelLarge: scale(localized.labelLarge, sizes.bodyMedium).copyWith(fontWeight: semiBold),
      labelMedium: scale(localized.labelMedium, sizes.bodySmall),
      // Nothing smaller than the small size (A01.4 c5: 12 by default;
      // Material makes labelSmall one smaller).
      labelSmall: scale(localized.labelSmall, sizes.bodySmall),
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
      // 3.x's main.dart (:162-169) replaced MyTheme's app bar theme (flat,
      // centred title, theme.dart:119) with this one, so app bars keep the
      // platform's title alignment (the start on Android); the pages 3.x
      // centred say so with [centredPageTitle].
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
      pageTransitionsTheme: appPageTransitionsTheme,
      // U.1c c12, c21: the tab's own 8-point block lights up under the
      // pointer and when pressed; the keyboard frame comes from `TabLabel`.
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        tabAlignment: TabAlignment.center,
        labelStyle: textTheme.titleMedium?.copyWith(fontWeight: semiBold),
        unselectedLabelStyle: textTheme.titleMedium?.copyWith(fontWeight: regular),
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant.withValues(alpha: 0.8),
        splashBorderRadius: AppRadii.menu,
        overlayColor: _TabOverlay(colors.onSurface),
      ),
      chipTheme: appChipTheme(colors, textTheme),
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: FocusFrame(colors.primary))),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: FocusFrame(
            colors.primary,
            outline: colors.outline,
            disabledOutline: colors.onSurface.withValues(alpha: 0.12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: FocusFrame(colors.primary))),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.card),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: semiBold),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.button),
        ).copyWith(side: FocusFrame(colors.primary)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: semiBold),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.textButton),
        ).copyWith(side: FocusFrame(colors.primary)),
      ),
      // The list row (U.1c c16): one row for lists, panels and settings;
      // title 15 regular, explanation 12 in the variant ink, icons in the
      // variant ink, at least 56 high; the chosen row on the secondary
      // container.
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.listRow),
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontSize: fontSizes.titleMedium,
          fontWeight: regular,
          color: colors.onSurface,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
        leadingAndTrailingTextStyle: textTheme.labelMedium,
        iconColor: colors.onSurfaceVariant,
        minTileHeight: 56,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
        border: const OutlineInputBorder(borderRadius: AppRadii.input),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.input,
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      // A panel from the bottom (docs/A-界面设计/A02-组件/A02.2-弹窗组件 c10, U.2f): the
      // surface colour, 16-point top corners, a handle.
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 1,
        showDragHandle: true,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.panelTop),
      ),
      // The dialog (U.1d c1, c5): title 20/600, text 14 (3.x had 13).
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colors.surfaceContainerHigh,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: semiBold, color: colors.onSurface),
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.dialog),
        insetPadding: const EdgeInsets.all(16),
      ),
      // The toast (U.1d c11–c13): floating, the inverse colours, 8-point
      // corners, 14-point text, 16 above the bottom bar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: colors.onInverseSurface),
        actionTextColor: colors.inversePrimary,
        closeIconColor: colors.onInverseSurface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.menu),
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
