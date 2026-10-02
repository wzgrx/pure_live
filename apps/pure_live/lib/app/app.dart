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
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/desktop/title_bar.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/live_play/mini/floating_window.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
import 'package:pure_live/features/splash/splash_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/tv_router.dart';
import 'package:pure_live/shared/images.dart';
import 'package:pure_live/tv/tv_app.dart';

/// The app (3.x `MyApp`): theme, language, text size and the shared
/// widgets' configuration from the settings, the route table (from the
/// splash page when it is on), Android's adaptive refresh rate, the
/// start-up work after the first frame ([AppStartup]), the links between
/// features that may not import each other (the room switcher's refresh of
/// the follows, F.1c) and the images given up when the system runs short of
/// memory ([releaseImageMemory], F.1d).
///
/// The interface follows `uiMode` (M14.1): on a television (or when chosen)
/// the TV routes and frame ([buildTvRouter], [TvAppFrame]), else the phone
/// and desktop ones. A change of the setting rebuilds the routes at once.
class PureLiveApp extends ConsumerStatefulWidget {
  /// Creates the app with the words loaded before the first frame.
  const new({required this.strings, this.router, this.bundle, super.key});

  /// The words of the starting language.
  final AppStrings strings;

  /// The router; null builds [buildAppRouter] (or [buildTvRouter] for the
  /// TV interface) from [splashInitialLocation].
  final GoRouter? router;

  /// Where translations load from (tests); null is the root bundle.
  final AssetBundle? bundle;

  @override
  ConsumerState<PureLiveApp> createState() => _PureLiveAppState();
}

class _PureLiveAppState extends ConsumerState<PureLiveApp> with WidgetsBindingObserver {
  late bool _tv = showsTvInterface(
    ref.read(appServicesProvider).store.settings,
    television: ref.read(televisionDeviceProvider),
  );
  late GoRouter _router = widget.router ?? _buildRouter(tv: _tv);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _refreshRate = AdaptiveRefreshRateController(applyHighRefreshRate);
  late AppStrings _strings = widget.strings;
  String? _lastToast;
  DateTime _lastToastAt = DateTime.fromMillisecondsSinceEpoch(0);
  late final FontLibrary _fonts;

  @override
  void initState() {
    super.initState();
    currentStrings = _strings;
    AppNavigator.router = _router;
    AppNavigator.toast = (message) {
      final messenger = _messenger.currentState;
      if (messenger == null) return;
      // The TV does not repeat the same words within the 3 s a toast shows
      // (pure_live_TV `ToastUtil`, docs/ui/compare/U.15a).
      final now = DateTime.now();
      if (_tv && message == _lastToast && now.difference(_lastToastAt) < const Duration(seconds: 3)) return;
      _lastToast = message;
      _lastToastAt = now;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating),
        );
    };
    imageCacheEpoch.addListener(_imagesCleared);
    _fonts = ref.read(fontLibraryProvider)..addListener(_imagesCleared);
    WidgetsBinding.instance.addObserver(this);
    // F.1c: the room switcher's refresh is the follows' silent full refresh
    // (3.x `refresh_favorite_rooms`).
    // B05: its last refresh time and failures show on the button.
    RoomSwitchPanel.follows = FollowsRefresher(
      refresh: () async {
        final follows = ref.read(favoriteControllerProvider);
        await follows.refreshAll(visible: false);
        return follows.lastFailed;
      },
      lastRefreshedAt: () => ref.read(favoriteControllerProvider).lastFullRefreshAt,
    );
    // 3.x started the follow check, the login check and the exit timer with
    // its services; here once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appStartupProvider).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RoomSwitchPanel.follows = null;
    imageCacheEpoch.removeListener(_imagesCleared);
    _fonts.removeListener(_imagesCleared);
    AppNavigator.router = null;
    super.dispose();
  }

  void _imagesCleared() {
    if (mounted) setState(() {});
  }

  @override
  void didHaveMemoryPressure() => releaseImageMemory();

  GoRouter _buildRouter({required bool tv}) {
    final location = splashInitialLocation(ref.read(appServicesProvider).store.settings);
    return tv ? buildTvRouter(initialLocation: location) : buildAppRouter(initialLocation: location);
  }

  /// Switches the interface (the `uiMode` setting changed): new routes from
  /// home, the old router released once the new one is in.
  void _switchInterface({required bool tv}) {
    _tv = tv;
    if (widget.router != null) return;
    final old = _router;
    _router = tv ? buildTvRouter() : buildAppRouter();
    AppNavigator.router = _router;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Loads the words when the language changes (3.x `context.setLocale`).
  Future<void> _follow(AppLanguage language) async {
    if (language == _strings.language) return;
    final strings = await AppStrings.load(language, widget.bundle ?? rootBundle);
    if (!mounted) return;
    setState(() => _strings = currentStrings = strings);
    DesktopShell.current?.relabel();
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
    final pureBlack = watchSetting(ref, Settings.pureBlackTheme);
    final sizes = LiveFontSizes(
      bodySmall: watchSetting(ref, Settings.fontSizeBodySmall),
      bodyMedium: watchSetting(ref, Settings.fontSizeBodyMedium),
      bodyLarge: watchSetting(ref, Settings.fontSizeBodyLarge),
      titleMedium: watchSetting(ref, Settings.fontSizeTitleMedium),
      titleLarge: watchSetting(ref, Settings.fontSizeTitleLarge),
    );
    final fontFamily = resolveAppFontFamily(
      selectedName: watchSetting(ref, Settings.fontFamilyName),
      // Fonts downloaded on the font page and registered with Flutter.
      customFonts: _fonts.registered,
      isWindows: Platform.isWindows,
    );
    final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
        .showsTv(television: ref.watch(televisionDeviceProvider));
    if (tv != _tv) _switchInterface(tv: tv);
    final textScale = watchSetting(ref, Settings.textScaleFactor);
    final refreshMode = RefreshRateMode.values.asNameMap()[watchSetting(ref, Settings.refreshRateMode)];
    final uiConfig = LiveUiConfig(
      strings: _strings.ui,
      loadingStyle: watchSetting(ref, Settings.loadingStyle),
      loadingColor: parseThemeColorOrNull(watchSetting(ref, Settings.loadingStyleColorSwitch)),
      imageHeaders: networkImageHeaders,
      imageCacheEpoch: imageCacheEpoch.value,
    );

    return LiveDynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = dynamicTheme && lightDynamic != null && darkDynamic != null;
        // The chosen colour stays the primary colour (fidelity, U.6b C-3;
        // 3.x's tonal spot turned its blue into a grey blue).
        final light = useDynamic
            ? LiveTheme(colorScheme: lightDynamic, fontSizes: sizes, fontFamily: fontFamily)
            : LiveTheme(
                primaryColor: seed,
                schemeVariant: DynamicSchemeVariant.fidelity,
                fontSizes: sizes,
                fontFamily: fontFamily,
              );
        final dark = useDynamic
            ? LiveTheme(colorScheme: darkDynamic, fontSizes: sizes, fontFamily: fontFamily, pureBlack: pureBlack)
            : LiveTheme(
                primaryColor: seed,
                schemeVariant: DynamicSchemeVariant.fidelity,
                fontSizes: sizes,
                fontFamily: fontFamily,
                pureBlack: pureBlack,
              );
        return MaterialApp.router(
          title: 'PureLive',
          onGenerateTitle: (_) => i18n('app_name'),
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messenger,
          routerConfig: _router,
          scrollBehavior: const AppScrollBehavior(),
          theme: light.light,
          darkTheme: dark.dark,
          // The TV is dark only (docs/ui/compare/U.15a A2, U.6b → U.15i).
          themeMode: tv ? ThemeMode.dark : themeMode,
          locale: language.locale,
          supportedLocales: [for (final value in AppLanguage.values) value.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            // The room's in-app floating window over every page (U.2j); not
            // on the television, whose room is always full screen.
            Widget result = MaterialUiThemeBridge(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child ?? const SizedBox.shrink(),
                  if (!tv) const Positioned.fill(child: FloatingRoomLayer()),
                ],
              ),
            );
            if (Platform.isAndroid && refreshMode != null) {
              result = AdaptiveRefreshRateScope(controller: _refreshRate, mode: refreshMode, child: result);
            }
            Widget framed = DesktopFrame(enabled: DesktopShell.current != null, child: result);
            if (tv) framed = TvAppFrame(child: framed);
            return LiveUiScope(
              config: uiConfig,
              child: MediaQuery(
                // On top of the system's text size (3.x replaced it, U.6b
                // C-5).
                data: MediaQuery.of(context)
                    .copyWith(textScaler: AppTextScaler(MediaQuery.textScalerOf(context), textScale)),
                child: framed,
              ),
            );
          },
        );
      },
    );
  }
}

/// The system runs short of memory (3.x `DesktopManager.didHaveMemoryPressure`,
/// F.1d): Flutter already empties [cache] (default: the app's); the record of
/// the images on screen goes too. Pictures on screen stay; they are decoded
/// again when shown anew.
void releaseImageMemory([ImageCache? cache]) {
  (cache ?? PaintingBinding.instance.imageCache)
    ..clear()
    ..clearLiveImages();
}

/// `AARRGGBB` or `#RRGGBB` as stored by the theme settings (3.x `HexColor`);
/// the brand blue when unreadable.
Color parseThemeColor(String hex) => parseThemeColorOrNull(hex) ?? LiveTheme.brandBlue;

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
