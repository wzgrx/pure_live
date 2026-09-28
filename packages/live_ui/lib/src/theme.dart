import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_ui/src/color_tokens.dart';
import 'package:live_ui/src/icons/live_icon.dart';
import 'package:live_ui/src/icons/live_icons.dart';
import 'package:live_ui/src/metrics.dart';

/// The three appearances of spec/design/principles.md §2.2.
enum Appearance {
  /// Light surfaces.
  light,

  /// Dark surfaces.
  dark,

  /// Dark with pure black surfaces (OLED).
  black,
}

/// Values the Material [ColorScheme] has no slot for (spec/design/tokens.json).
@immutable
final class LiveTheme extends ThemeExtension<LiveTheme> {
  /// Creates the extension.
  const new({
    required this.live,
    required this.onLive,
    required this.success,
    required this.warning,
    required this.focusRing,
  });

  /// "Live" badge fill; semantic, not the brand colour.
  final Color live;

  /// Text on [live].
  final Color onLive;

  /// Success state.
  final Color success;

  /// Warning state.
  final Color warning;

  /// Keyboard and remote focus outline.
  final Color focusRing;

  /// Tabular figures and nothing else: merged into the surrounding text style
  /// (a [Text] inside a list tile's subtitle keeps the subtitle's size,
  /// weight and colour).
  static const TextStyle tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  /// [base] with tabular figures, for audience counts, durations, bit rates
  /// and clocks, so numbers do not shift when they refresh (principles
  /// §2.3). Size, weight and colour stay those of [base]: a figure in a
  /// subtitle is never heavier than the title above it.
  static TextStyle numeric(TextStyle base) => base.merge(tabularFigures);

  /// The extension of [context]'s theme.
  static LiveTheme of(BuildContext context) => Theme.of(context).extension<LiveTheme>()!;

  @override
  LiveTheme copyWith({Color? live, Color? onLive, Color? success, Color? warning, Color? focusRing}) => LiveTheme(
    live: live ?? this.live,
    onLive: onLive ?? this.onLive,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    focusRing: focusRing ?? this.focusRing,
  );

  @override
  LiveTheme lerp(LiveTheme? other, double t) {
    if (other == null) return this;
    return LiveTheme(
      live: Color.lerp(live, other.live, t)!,
      onLive: Color.lerp(onLive, other.onLive, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}

/// Builds [ThemeData] from the design tokens.
abstract final class PureTheme {
  /// The theme for [appearance] on [platform]. [seed] (wallpaper or system
  /// accent colour, principles §2.2 动态取色) replaces the primary, secondary,
  /// tertiary and neutral roles; semantic colours and pure black stay.
  /// [fontFamily] replaces the platform font (a font the user downloaded,
  /// F-SET-01); the platform fonts stay as the fallback. [locale] is the
  /// interface language (principles §2.3): text styles carry it so the
  /// font fallback picks Simplified or Traditional glyphs, and Traditional
  /// Chinese on Windows uses Microsoft JhengHei UI instead of YaHei UI.
  static ThemeData of(
    Appearance appearance, {
    TargetPlatform? platform,
    Color? seed,
    String? fontFamily,
    Locale? locale,
  }) => _build(appearance, platform, tv: false, seed: seed, fontFamily: fontFamily, locale: locale);

  /// The TV theme (principles §5.3): dark or pure black only (a light
  /// [appearance] gets dark), type one step larger with body text at least
  /// 14 sp, 32 dp icons, a near-white focus ring and focus that shows on
  /// buttons, chips, tabs, list rows and fields at ten feet.
  static ThemeData tv(Appearance appearance, {TargetPlatform? platform, String? fontFamily, Locale? locale}) => _build(
    appearance == Appearance.light ? Appearance.dark : appearance,
    platform,
    tv: true,
    fontFamily: fontFamily,
    locale: locale,
  );

  /// Dynamic colour: the seed's fidelity scheme for the colour and neutral
  /// roles; error roles from the tokens; pure black keeps its surfaces.
  static ColorScheme _seeded(ColorScheme base, Color seed, {required bool black}) {
    final seeded = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: base.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final colors = base.copyWith(
      primary: seeded.primary,
      onPrimary: seeded.onPrimary,
      primaryContainer: seeded.primaryContainer,
      onPrimaryContainer: seeded.onPrimaryContainer,
      secondary: seeded.secondary,
      onSecondary: seeded.onSecondary,
      secondaryContainer: seeded.secondaryContainer,
      onSecondaryContainer: seeded.onSecondaryContainer,
      tertiary: seeded.tertiary,
      onTertiary: seeded.onTertiary,
      tertiaryContainer: seeded.tertiaryContainer,
      onTertiaryContainer: seeded.onTertiaryContainer,
      inversePrimary: seeded.inversePrimary,
    );
    if (black) return colors;
    return colors.copyWith(
      surface: seeded.surface,
      onSurface: seeded.onSurface,
      surfaceDim: seeded.surfaceDim,
      surfaceBright: seeded.surfaceBright,
      surfaceContainerLowest: seeded.surfaceContainerLowest,
      surfaceContainerLow: seeded.surfaceContainerLow,
      surfaceContainer: seeded.surfaceContainer,
      surfaceContainerHigh: seeded.surfaceContainerHigh,
      surfaceContainerHighest: seeded.surfaceContainerHighest,
      onSurfaceVariant: seeded.onSurfaceVariant,
      outline: seeded.outline,
      outlineVariant: seeded.outlineVariant,
      inverseSurface: seeded.inverseSurface,
      onInverseSurface: seeded.onInverseSurface,
    );
  }

  static ThemeData _build(
    Appearance appearance,
    TargetPlatform? platform, {
    required bool tv,
    Color? seed,
    String? fontFamily,
    Locale? locale,
  }) {
    final tokens = switch (appearance) {
      Appearance.light => ColorTokens.light,
      Appearance.dark => ColorTokens.dark,
      Appearance.black => ColorTokens.black,
    };
    final brightness = appearance == Appearance.light ? Brightness.light : Brightness.dark;
    final base = ColorScheme(
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      primaryContainer: tokens.primaryContainer,
      onPrimaryContainer: tokens.onPrimaryContainer,
      secondary: tokens.secondary,
      onSecondary: tokens.onSecondary,
      secondaryContainer: tokens.secondaryContainer,
      onSecondaryContainer: tokens.onSecondaryContainer,
      tertiary: tokens.tertiary,
      onTertiary: tokens.onTertiary,
      tertiaryContainer: tokens.tertiaryContainer,
      onTertiaryContainer: tokens.onTertiaryContainer,
      error: tokens.error,
      onError: tokens.onError,
      errorContainer: tokens.errorContainer,
      onErrorContainer: tokens.onErrorContainer,
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      surfaceDim: tokens.surfaceDim,
      surfaceBright: tokens.surfaceBright,
      surfaceContainerLowest: tokens.surfaceContainerLowest,
      surfaceContainerLow: tokens.surfaceContainerLow,
      surfaceContainer: tokens.surfaceContainer,
      surfaceContainerHigh: tokens.surfaceContainerHigh,
      surfaceContainerHighest: tokens.surfaceContainerHighest,
      onSurfaceVariant: tokens.onSurfaceVariant,
      outline: tokens.outline,
      outlineVariant: tokens.outlineVariant,
      inverseSurface: tokens.inverseSurface,
      onInverseSurface: tokens.inverseOnSurface,
      inversePrimary: tokens.inversePrimary,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
    );
    final scheme = seed == null ? base : _seeded(base, seed, black: appearance == Appearance.black);
    final target = platform ?? defaultTargetPlatform;
    final text = _textTheme(
      target,
      tv: tv,
      fontFamily: fontFamily,
      locale: locale,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final desktop =
        !tv && (target == TargetPlatform.windows || target == TargetPlatform.linux || target == TargetPlatform.macOS);
    final overlayRadius = BorderRadius.circular(desktop ? Radii.r2 : Radii.r4);
    // On TV the ring is near-white onSurface: ≥ 3:1 against every surface
    // and against the unfocused state (principles §5.3).
    final focusRing = tv ? scheme.onSurface : tokens.focusRing;
    final dark = brightness == Brightness.dark;
    // Principles §2.6: an icon beside a button's or chip's label is 20 dp,
    // the smallest size Material Symbols draws for (Material's 18 would
    // shrink the 20 dp design).
    const labelIcons = ButtonStyle(iconSize: WidgetStatePropertyAll(Sizes.iconDense));

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      platform: target,
      // Material's typography names Roboto; merged under [text] it would put
      // Roboto on theme styles but not on component styles built from [text],
      // two fonts on one screen. Without it Android uses the system font
      // (vendor fonts included), as principles §2.3 asks.
      typography: _familyless(Typography.material2021(platform: target)),
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
      // Principles §2.6: the variable axes every icon starts from (LiveIcon
      // sets the optical size to the size shown). The colours are Material's
      // defaults, the same objects, so icon buttons still see them as unset.
      iconTheme: iconAxes(dark: dark).copyWith(color: dark ? kDefaultIconLightColor : kDefaultIconDarkColor),
      // The buttons Material builds itself (an app bar's back button) show
      // Symbols too.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const LiveIcon(LiveIcons.back),
        closeButtonIconBuilder: (_) => const LiveIcon(LiveIcons.close),
        drawerButtonIconBuilder: (_) => const LiveIcon(LiveIcons.railExpand),
        endDrawerButtonIconBuilder: (_) => const LiveIcon(LiveIcons.railExpand),
      ),
      filledButtonTheme: const FilledButtonThemeData(style: labelIcons),
      textButtonTheme: const TextButtonThemeData(style: labelIcons),
      outlinedButtonTheme: const OutlinedButtonThemeData(style: labelIcons),
      elevatedButtonTheme: const ElevatedButtonThemeData(style: labelIcons),
      segmentedButtonTheme: const SegmentedButtonThemeData(style: labelIcons, selectedIcon: LiveIcon(LiveIcons.check)),
      materialTapTargetSize: desktop ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        selectedLabelTextStyle: text.labelMedium!.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: text.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.r3)),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge,
        side: BorderSide(color: scheme.outlineVariant),
        iconTheme: const IconThemeData(size: Sizes.iconDense),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: overlayRadius.topLeft)),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: overlayRadius),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(desktop ? Radii.r2 : Radii.r3)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.r3)),
      ),
      // Inputs are r2 (principles §2.4), the search box included: it is an
      // input, and full rounding is kept for buttons, chips, avatars and
      // switches.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.r2), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
      ),
      searchBarTheme: SearchBarThemeData(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.r2))),
      ),
      // No tick marks: with many steps they merge into a dotted line.
      sliderTheme: SliderThemeData(tickMarkShape: SliderTickMarkShape.noTickMark),
      scrollbarTheme: ScrollbarThemeData(
        // Desktop keeps a thin scrollbar visible (principles §2.1).
        thumbVisibility: WidgetStatePropertyAll(desktop),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(Radii.r1),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      extensions: [
        LiveTheme(
          live: FixedColors.live,
          onLive: FixedColors.onLive,
          success: tokens.success,
          warning: tokens.warning,
          focusRing: focusRing,
        ),
      ],
    );
    return tv ? _tvFocus(theme, scheme, focusRing) : theme;
  }

  /// Focus that reads from the sofa: list rows and ink get a stronger focus
  /// fill, buttons, chips and fields a 3 dp ring (a fill alone disappears on
  /// buttons that set their own colours).
  static ThemeData _tvFocus(ThemeData theme, ColorScheme scheme, Color ring) {
    final focusFill = scheme.onSurface.withValues(alpha: 0.24);
    final side = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused) ? BorderSide(color: ring, width: 3) : null,
    );
    final overlay = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.focused) ? focusFill : null,
    );
    // Principles §2.6 and §5.3: icons are 32 dp at ten feet; beside a label
    // (buttons, chips) 24 dp, one step above the 20 dp elsewhere, like the type.
    const labelIcon = WidgetStatePropertyAll(Sizes.iconMd);
    final buttons = ButtonStyle(side: side, overlayColor: overlay, iconSize: labelIcon);
    final outlined = ButtonStyle(
      overlayColor: overlay,
      iconSize: labelIcon,
      side: WidgetStateProperty.resolveWith<BorderSide?>(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: ring, width: 3)
            : BorderSide(color: states.contains(WidgetState.disabled) ? scheme.outlineVariant : scheme.outline),
      ),
    );
    return theme.copyWith(
      focusColor: focusFill,
      iconTheme: theme.iconTheme.copyWith(size: Sizes.iconLg, opticalSize: Sizes.iconLg),
      iconButtonTheme: IconButtonThemeData(
        style: buttons.copyWith(iconSize: const WidgetStatePropertyAll(Sizes.iconLg)),
      ),
      textButtonTheme: TextButtonThemeData(style: buttons),
      filledButtonTheme: FilledButtonThemeData(style: buttons),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttons),
      outlinedButtonTheme: OutlinedButtonThemeData(style: outlined),
      segmentedButtonTheme: theme.segmentedButtonTheme.copyWith(
        style: const ButtonStyle(iconSize: labelIcon).copyWith(overlayColor: overlay),
      ),
      chipTheme: theme.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: ring, width: 3)
              : BorderSide(color: scheme.outlineVariant),
        ),
        iconTheme: const IconThemeData(size: Sizes.iconMd),
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(overlayColor: overlay),
      searchBarTheme: theme.searchBarTheme.copyWith(side: side, overlayColor: overlay),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.r2),
          borderSide: BorderSide(color: ring, width: 3),
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(minVerticalPadding: Space.s2),
    );
  }

  /// Whether [locale] reads Traditional Chinese: script Hant, or Chinese of
  /// Taiwan, Hong Kong or Macau without a script.
  static bool isTraditionalChinese(Locale? locale) {
    if (locale == null || locale.languageCode != 'zh') return false;
    final script = locale.scriptCode;
    if (script != null) return script == 'Hant';
    return const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
  }

  /// [typography] with every font family removed; colours and baselines stay.
  static Typography _familyless(Typography typography) {
    TextStyle? plain(TextStyle? style) => style == null
        ? null
        : TextStyle(
            inherit: style.inherit,
            color: style.color,
            decoration: style.decoration,
            textBaseline: style.textBaseline,
            leadingDistribution: style.leadingDistribution,
            debugLabel: style.debugLabel,
          );
    TextTheme theme(TextTheme t) => TextTheme(
      displayLarge: plain(t.displayLarge),
      displayMedium: plain(t.displayMedium),
      displaySmall: plain(t.displaySmall),
      headlineLarge: plain(t.headlineLarge),
      headlineMedium: plain(t.headlineMedium),
      headlineSmall: plain(t.headlineSmall),
      titleLarge: plain(t.titleLarge),
      titleMedium: plain(t.titleMedium),
      titleSmall: plain(t.titleSmall),
      bodyLarge: plain(t.bodyLarge),
      bodyMedium: plain(t.bodyMedium),
      bodySmall: plain(t.bodySmall),
      labelLarge: plain(t.labelLarge),
      labelMedium: plain(t.labelMedium),
      labelSmall: plain(t.labelSmall),
    );
    return Typography.material2021(
      platform: null,
      black: theme(typography.black),
      white: theme(typography.white),
      englishLike: typography.englishLike,
      dense: typography.dense,
      tall: typography.tall,
    );
  }

  /// Type scale of spec/design/tokens.json; the system font with explicit CJK
  /// fallbacks (principles §2.3). Every role, on TV too, has a line height of
  /// at least 1.4 times its size, rounded up to an even number (Chinese
  /// needs the room); on TV every role is one step larger and body text is
  /// at least 14 sp (principles §5.3).
  static TextTheme _textTheme(TargetPlatform platform, {bool tv = false, String? fontFamily, Locale? locale}) {
    // Principles §2.3: the UI variants of the Windows CJK fonts; Traditional
    // Chinese swaps YaHei for JhengHei and the SC fallbacks for TC ones.
    final traditional = isTraditionalChinese(locale);
    final windowsFont = traditional ? 'Microsoft JhengHei UI' : 'Microsoft YaHei UI';
    final family = fontFamily ?? (platform == TargetPlatform.windows ? windowsFont : null);
    final fallback = traditional
        ? const ['Microsoft JhengHei UI', 'Microsoft JhengHei', 'PingFang TC', 'Noto Sans TC', 'Noto Sans CJK TC']
        : const ['Microsoft YaHei UI', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Noto Sans CJK SC'];
    TextStyle style(double size, double height, FontWeight weight) => TextStyle(
      locale: locale,
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    );
    const semibold = FontWeight.w600;
    const regular = FontWeight.w400;
    if (tv) {
      return TextTheme(
        displayLarge: style(64, 90, regular),
        displayMedium: style(57, 80, regular),
        displaySmall: style(45, 64, semibold),
        headlineLarge: style(36, 52, semibold),
        headlineMedium: style(32, 46, semibold),
        headlineSmall: style(28, 40, semibold),
        titleLarge: style(24, 34, semibold),
        titleMedium: style(18, 26, semibold),
        titleSmall: style(16, 24, semibold),
        bodyLarge: style(18, 26, regular),
        bodyMedium: style(16, 24, regular),
        bodySmall: style(14, 20, regular),
        labelLarge: style(16, 24, semibold),
        labelMedium: style(14, 20, semibold),
        labelSmall: style(14, 20, semibold),
      );
    }
    return TextTheme(
      displayLarge: style(57, 80, regular),
      displayMedium: style(45, 64, regular),
      displaySmall: style(36, 52, semibold),
      headlineLarge: style(32, 46, semibold),
      headlineMedium: style(28, 40, semibold),
      headlineSmall: style(24, 34, semibold),
      titleLarge: style(22, 32, semibold),
      titleMedium: style(16, 24, semibold),
      titleSmall: style(14, 20, semibold),
      bodyLarge: style(16, 24, regular),
      bodyMedium: style(14, 20, regular),
      bodySmall: style(12, 18, regular),
      labelLarge: style(14, 20, semibold),
      labelMedium: style(12, 18, semibold),
      labelSmall: style(12, 18, semibold),
    );
  }
}
