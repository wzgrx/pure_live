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
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/app/page_toasts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/app/system_bars.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/live_play/mini/floating_window.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
import 'package:pure_live/features/splash/splash_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_path.dart';
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
  // The one toast (docs/A-界面设计/A02-组件/A02.2-弹窗组件 c11–c13): the same words are not
  // repeated while they show (3.x `ToastUtil`; pure_live_TV the same).
  late final AppToaster _toaster = AppToaster(() => _messenger.currentState);
  // A02.4 c3: an undo toast closes with its page.
  VoidCallback? _stopPageToasts;
  late final FontLibrary _fonts;
  VoidCallback? _stopHomeWatch;

  @override
  void initState() {
    super.initState();
    currentStrings = _strings;
    AppNavigator.router = _router;
    _stopPageToasts = closeToastsOnNewPage(_router, () => _messenger.currentState);
    AppNavigator.toast = (message) => _toaster.show(AppToast(message));
    AppNavigator.showToast = _toaster.show;
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
    _stopHomeWatch = _watchHome(_router);
  }

  /// R04.1: marks home's first frame and, when its first tab's page does not
  /// report its own first content (every tab but popular, and the TV
  /// interface), reports it ([StartupTiming] has the rule). Returns the
  /// function that stops waiting for home; null without a timing.
  VoidCallback? _watchHome(GoRouter router) {
    final timing = StartupTiming.current;
    if (timing == null || timing.reported) return null;
    final delegate = router.routerDelegate;
    var done = false;
    void changed({bool drawn = false}) {
      if (done || delegate.currentConfiguration.uri.path != RoutePath.kInitial) return;
      done = true;
      delegate.removeListener(changed);
      unawaited(_homeShown(timing, drawn: drawn));
    }

    delegate.addListener(changed);
    // Without the splash page home is the first route, drawn by now.
    WidgetsBinding.instance.addPostFrameCallback((_) => changed(drawn: true));
    return () {
      done = true;
      delegate.removeListener(changed);
    };
  }

  Future<void> _homeShown(StartupTiming timing, {required bool drawn}) async {
    if (!drawn) await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    timing.mark('home');
    final first = _tv
        ? null
        : visibleHomeMenus(ref.read(appServicesProvider).store.settings.get(Settings.savedMenuIds)).first;
    switch (first) {
      case HomeMenu.popular:
        // The popular page reports its first rooms.
        break;
      case HomeMenu.favorites:
        await followsFirstContent(ref.read(favoriteControllerProvider), timing);
      case HomeMenu.areas || HomeMenu.record:
        await timing.firstContent(tab: first!.id, content: 'home');
      case null:
        await timing.firstContent(tab: 'tv', content: 'home');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPageToasts?.call();
    _stopHomeWatch?.call();
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
    _stopPageToasts?.call();
    _stopHomeWatch?.call();
    _stopHomeWatch = null;
    _router = tv ? buildTvRouter() : buildAppRouter();
    AppNavigator.router = _router;
    _stopPageToasts = closeToastsOnNewPage(_router, () => _messenger.currentState);
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
      imageCacheManager: AppImageCache.manager,
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
          // The TV is dark only (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 A2, U.6b → U.15i).
          themeMode: tv ? ThemeMode.dark : themeMode,
          locale: language.locale,
          supportedLocales: [for (final value in AppLanguage.values) value.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            // The room's in-app floating window over every page (U.2j); not
            // on the television, whose room is always full screen. The pages
            // read their size classes from the area they get (A04.1), not
            // from the whole screen.
            Widget result = MaterialUiThemeBridge(
              child: WindowClassScope(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child ?? const SizedBox.shrink(),
                    if (!tv) const Positioned.fill(child: FloatingRoomLayer()),
                  ],
                ),
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
                // C-5); both together at most 2× (A04.1, appTextScaleLimit).
                data: MediaQuery.of(context)
                    .copyWith(textScaler: AppTextScaler(MediaQuery.textScalerOf(context), textScale)),
                // See-through system bars, icons for the theme (A06.5).
                child: SystemBarsScope(child: framed),
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
