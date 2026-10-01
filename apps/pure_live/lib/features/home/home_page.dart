import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/areas_page.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/home_views.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// The page of each home destination; the app replaces the placeholders as
/// M13 rebuilds the pages (3.x `FavoritePage`, `PopularPage`, `AreasPage`,
/// `RecorderPage`).
typedef HomeTabBuilder = Widget Function(BuildContext context, HomeMenu menu);

/// The home shell (3.x `HomePage`): a bottom bar on phones, a side rail from
/// [homeTabletBreakpoint] (600, U.3b c6; 3.x: above 680), the destinations of
/// the `savedMenuIds` setting on both (U.3b c3).
///
/// Kept from 3.x: selecting follows again refreshes them; back sends the app
/// to the background on Android; after 15 s or more in the background the
/// visible tab refreshes; a room given on the command line opens once the
/// page is up; the main window checks for an update
/// [startupUpdateCheckDelay] after its first frame. The update prompt opens
/// only while home is on top, after any other prompt (U.3c c7).
class HomePage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({this.tabBuilder = buildHomeTab, super.key});

  /// Builds a destination's page.
  final HomeTabBuilder tabBuilder;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  HomeMenu? _selected;
  DateTime? _backgroundedAt;
  Timer? _resumeTimer;
  Timer? _updateTimer;
  final Map<HomeMenu, Widget> _pages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Platform.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0),
            systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor,
          ),
        );
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      }
      final launch = ref.read(appServicesProvider).launch;
      if (launch.room case final room?) unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
      if (launch.isPrimary) _updateTimer = Timer(startupUpdateCheckDelay, _checkForUpdate);
    });
  }

  void _checkForUpdate() {
    if (!mounted) return;
    unawaited(
      checkForUpdateOnStartup(
        context,
        settings: ref.read(appServicesProvider).store.settings,
        feed: ref.read(updateFeedProvider),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _resumeTimer?.cancel();
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final away = _backgroundedAt;
    _backgroundedAt = null;
    final menu = _selected;
    if (away == null || menu == null || DateTime.now().difference(away) < HomeSignals.resumeRefreshAfter) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final previous = HomeSignals.resumedAfterBackground.value;
      HomeSignals.resumedAfterBackground.value = (menu, (previous?.$2 ?? 0) + 1);
    });
  }

  void _select(HomeMenu menu) {
    if (menu == _selected && menu == HomeMenu.favorites) {
      HomeSignals.favoritesReselected.value++;
      return;
    }
    setState(() => _selected = menu);
  }

  Future<void> _onBack(bool didPop, Object? result) async {
    if (didPop || !Platform.isAndroid) return;
    try {
      await const MethodChannel('pure_live/app').invokeMethod<bool>('moveToBack');
    } on PlatformException {
      // Stay in front.
    } on MissingPluginException {
      // No activity.
    }
  }

  // A global key per page, so a page keeps its state when the window
  // crosses the rail width (UI_PLAN §5.1).
  Widget _page(HomeMenu menu) => _pages[menu] ??= KeyedSubtree(
    key: GlobalKey(debugLabel: menu.id),
    child: Builder(builder: (context) => widget.tabBuilder(context, menu)),
  );

  @override
  Widget build(BuildContext context) {
    final saved = watchSetting(ref, Settings.savedMenuIds);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rail = isHomeRailWidth(constraints.maxWidth);
          final menus = visibleHomeMenus(saved);
          // A removed or hidden destination falls back to the first one (3.x).
          final selected = menus.contains(_selected) ? _selected! : menus.first;
          _selected = selected;
          final body = HomeLayoutScope(phone: !rail, child: _page(selected));
          return rail
              ? HomeTabletView(menus: menus, selected: selected, onSelected: _select, body: body)
              : HomeMobileView(menus: menus, selected: selected, onSelected: _select, body: body);
        },
      ),
    );
  }
}

/// The page of each home destination (the same page classes the routes
/// open, as home tabs).
Widget buildHomeTab(BuildContext context, HomeMenu menu) => switch (menu) {
  HomeMenu.favorites => const FavoritePage(route: RouteArgs(RoutePath.kFavorite, inHome: true)),
  HomeMenu.popular => const PopularPage(route: RouteArgs(RoutePath.kPopular, inHome: true)),
  HomeMenu.areas => const AreasPage(route: RouteArgs(RoutePath.kAreas, inHome: true)),
  HomeMenu.record => const RecorderPage(route: RouteArgs(RoutePath.kRecordPage, inHome: true)),
};
