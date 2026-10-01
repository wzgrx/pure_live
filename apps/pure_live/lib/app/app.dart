import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';

/// The app (3.x `MyApp`): theme, language, text size and the shared
/// widgets' configuration from the settings, the route table, and Android's
/// adaptive refresh rate.
class PureLiveApp extends ConsumerStatefulWidget {
  /// Creates the app with the words loaded before the first frame.
  const new({required this.strings, this.router, this.bundle, super.key});

  /// The words of the starting language.
  final AppStrings strings;

  /// The router; null builds [buildAppRouter].
  final GoRouter? router;

  /// Where translations load from (tests); null is the root bundle.
  final AssetBundle? bundle;

  @override
  ConsumerState<PureLiveApp> createState() => _PureLiveAppState();
}

class _PureLiveAppState extends ConsumerState<PureLiveApp> {
  late final GoRouter _router = widget.router ?? buildAppRouter();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _refreshRate = AdaptiveRefreshRateController(applyHighRefreshRate);
  late AppStrings _strings = widget.strings;

  @override
  void initState() {
    super.initState();
    currentStrings = _strings;
    AppNavigator.router = _router;
    AppNavigator.toast = (message) {
      final messenger = _messenger.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating),
        );
    };
  }

  @override
  void dispose() {
    AppNavigator.router = null;
    super.dispose();
  }

  /// Loads the words when the language changes (3.x `context.setLocale`).
  Future<void> _follow(AppLanguage language) async {
    if (language == _strings.language) return;
    final strings = await AppStrings.load(language, widget.bundle ?? rootBundle);
    if (!mounted) return;
    setState(() => _strings = currentStrings = strings);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(appServicesProvider).store.settings;
    final stored = watchSetting(ref, Settings.language);
    final language = AppLanguage.resolve(
      stored: settings.isSet(Settings.language) ? stored : null,
      preferred: PlatformDispatcher.instance.locales,
    );
    if (language != _strings.language) unawaited(_follow(language));

    final themeMode = switch (watchSetting(ref, Settings.themeMode)) {
      'Dark' => ThemeMode.dark,
      'Light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final dynamicTheme = watchSetting(ref, Settings.enableDynamicTheme);
    final seed = parseThemeColor(watchSetting(ref, Settings.themeColorSwitch));
    final sizes = LiveFontSizes(
      bodySmall: watchSetting(ref, Settings.fontSizeBodySmall),
      bodyMedium: watchSetting(ref, Settings.fontSizeBodyMedium),
      bodyLarge: watchSetting(ref, Settings.fontSizeBodyLarge),
      titleMedium: watchSetting(ref, Settings.fontSizeTitleMedium),
      titleLarge: watchSetting(ref, Settings.fontSizeTitleLarge),
    );
    final fontFamily = resolveAppFontFamily(
      selectedName: watchSetting(ref, Settings.fontFamilyName),
      // Downloaded fonts are registered by the font page (M13).
      customFonts: const [],
      isWindows: Platform.isWindows,
    );
    final textScale = watchSetting(ref, Settings.textScaleFactor);
    final refreshMode = RefreshRateMode.values.asNameMap()[watchSetting(ref, Settings.refreshRateMode)];
    final uiConfig = LiveUiConfig(
      strings: _strings.ui,
      loadingStyle: watchSetting(ref, Settings.loadingStyle),
      loadingColor: parseThemeColorOrNull(watchSetting(ref, Settings.loadingStyleColorSwitch)),
    );

    return LiveDynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = dynamicTheme && lightDynamic != null && darkDynamic != null;
        final light = useDynamic
            ? LiveTheme(colorScheme: lightDynamic, fontSizes: sizes, fontFamily: fontFamily)
            : LiveTheme(primaryColor: seed, fontSizes: sizes, fontFamily: fontFamily);
        final dark = useDynamic
            ? LiveTheme(colorScheme: darkDynamic, fontSizes: sizes, fontFamily: fontFamily)
            : LiveTheme(primaryColor: seed, fontSizes: sizes, fontFamily: fontFamily);
        return MaterialApp.router(
          title: 'PureLive',
          onGenerateTitle: (_) => i18n('app_name'),
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messenger,
          routerConfig: _router,
          scrollBehavior: const AppScrollBehavior(),
          theme: light.light,
          darkTheme: dark.dark,
          themeMode: themeMode,
          locale: language.locale,
          supportedLocales: [for (final value in AppLanguage.values) value.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            Widget result = MaterialUiThemeBridge(child: child ?? const SizedBox.shrink());
            if (Platform.isAndroid && refreshMode != null) {
              result = AdaptiveRefreshRateScope(controller: _refreshRate, mode: refreshMode, child: result);
            }
            return LiveUiScope(
              config: uiConfig,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                child: result,
              ),
            );
          },
        );
      },
    );
  }
}

/// `AARRGGBB` or `#RRGGBB` as stored by the theme settings (3.x `HexColor`);
/// 3.x's blue when unreadable.
Color parseThemeColor(String hex) => parseThemeColorOrNull(hex) ?? const Color(0xFF2196F3);

/// [parseThemeColor], or null for an empty or unreadable value.
Color? parseThemeColorOrNull(String hex) {
  var digits = hex.trim().replaceFirst('#', '');
  if (digits.length == 6) digits = 'FF$digits';
  if (digits.length != 8) return null;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? null : Color(value);
}

/// The scroll behaviour of 3.x (`MyCustomScrollBehavior`): Pure Live's
/// physics, the keyboard closes on drag, and the mouse does not drag lists
/// (it fights the bounce at the ends; the wheel still scrolls).
class AppScrollBehavior extends MaterialScrollBehavior {
  /// Creates the behaviour.
  const new();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const PureLiveScrollPhysics();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(BuildContext context) =>
      ScrollViewKeyboardDismissBehavior.onDrag;

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}
