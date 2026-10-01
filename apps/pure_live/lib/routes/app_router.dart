import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/home/home_page.dart';
import 'package:pure_live/pages/about/about_page.dart';
import 'package:pure_live/pages/account/account_page.dart';
import 'package:pure_live/pages/area_rooms/area_rooms_page.dart';
import 'package:pure_live/pages/areas/areas_page.dart';
import 'package:pure_live/pages/auth/auth_page.dart';
import 'package:pure_live/pages/backup/backup_page.dart';
import 'package:pure_live/pages/favorite/favorite_page.dart';
import 'package:pure_live/pages/history/history_page.dart';
import 'package:pure_live/pages/hot_areas/hot_areas_page.dart';
import 'package:pure_live/pages/iptv/iptv_page.dart';
import 'package:pure_live/pages/live_play/live_play_page.dart';
import 'package:pure_live/pages/multiview/multiview_page.dart';
import 'package:pure_live/pages/popular/popular_page.dart';
import 'package:pure_live/pages/record_settings/record_settings_page.dart';
import 'package:pure_live/pages/recorder/recorder_page.dart';
import 'package:pure_live/pages/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/pages/search/search_page.dart';
import 'package:pure_live/pages/settings/settings_page.dart';
import 'package:pure_live/pages/shield/shield_page.dart';
import 'package:pure_live/pages/splash/splash_page.dart';
import 'package:pure_live/pages/tags/tags_page.dart';
import 'package:pure_live/pages/toolbox/toolbox_page.dart';
import 'package:pure_live/pages/version/version_page.dart';
import 'package:pure_live/pages/web_dav/web_dav_page.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// Builds a page from how it was opened.
typedef PageBuilder = Widget Function(RouteArgs route);

/// 3.x's route table (`AppPages.routes`) besides home, in its order: every
/// path points at the page class of its folder under `lib/pages/` (M13
/// replaces the folders, never this table).
final Map<String, PageBuilder> pageRoutes = {
  RoutePath.kSignIn: (route) => AuthPage(route: route),
  RoutePath.kMine: (route) => AuthPage(route: route),
  RoutePath.kUserManage: (route) => AuthPage(route: route),
  RoutePath.kFavorite: (route) => FavoritePage(route: route),
  RoutePath.kPopular: (route) => PopularPage(route: route),
  RoutePath.kAreas: (route) => AreasPage(route: route),
  RoutePath.kSettings: (route) => SettingsPage(route: route),
  RoutePath.kHistory: (route) => HistoryPage(route: route),
  RoutePath.kSearch: (route) => SearchPage(route: route),
  RoutePath.kBackup: (route) => BackupPage(route: route),
  RoutePath.kIptv: (route) => IptvPage(route: route),
  RoutePath.kAbout: (route) => AboutPage(route: route),
  RoutePath.kAreaRooms: (route) => AreaRoomsPage(route: route),
  RoutePath.kLivePlay: (route) => LivePlayPage(route: route),
  RoutePath.kMultiview: (route) => MultiviewPage(route: route),
  RoutePath.kSettingsAccount: (route) => AccountPage(route: route),
  RoutePath.kBiliBiliWebLogin: (route) => AccountPage(route: route),
  RoutePath.kBiliBiliQRLogin: (route) => AccountPage(route: route),
  RoutePath.kSettingsDanmuShield: (route) => ShieldPage(route: route),
  RoutePath.kSettingsHotAreas: (route) => HotAreasPage(route: route),
  RoutePath.kVersionHistory: (route) => AboutPage(route: route),
  RoutePath.kToolbox: (route) => ToolboxPage(route: route),
  RoutePath.kFavoriteAreas: (route) => AreasPage(route: route),
  RoutePath.kHuyaCookie: (route) => AccountPage(route: route),
  RoutePath.kDouyuAccountCookie: (route) => AccountPage(route: route),
  RoutePath.kDouyinCookie: (route) => AccountPage(route: route),
  RoutePath.kDouyuCookie: (route) => AccountPage(route: route),
  RoutePath.kTwitchCookie: (route) => AccountPage(route: route),
  RoutePath.kYyCookie: (route) => AccountPage(route: route),
  RoutePath.kSoop: (route) => AccountPage(route: route),
  RoutePath.kKuaishouCookie: (route) => AccountPage(route: route),
  RoutePath.kWebDavPage: (route) => WebDavPage(route: route),
  RoutePath.kSplash: (route) => SplashPage(route: route),
  RoutePath.kVersionPage: (route) => VersionPage(route: route),
  RoutePath.kRecordPage: (route) => RecorderPage(route: route),
  RoutePath.kRecordSettings: (route) => RecordSettingsPage(route: route),
  RoutePath.kWebSearch: (route) => SearchPage(route: route),
  RoutePath.kSettingsTags: (route) => TagsPage(route: route),
  RoutePath.kRemoteSync: (route) => RemoteReceiverPage(route: route),
};

/// The router of home and [pageRoutes], starting at [initialLocation] (the
/// app passes `splashInitialLocation`: the splash page when `showSplashPage`
/// is on, as 3.x).
GoRouter buildAppRouter({
  String initialLocation = RoutePath.kInitial,
  List<NavigatorObserver> observers = const [],
  GlobalKey<NavigatorState>? navigatorKey,
}) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: initialLocation,
  observers: [liveRouteObserver, ...observers],
  routes: [
    GoRoute(
      path: RoutePath.kInitial,
      pageBuilder: (context, state) =>
          MaterialPage<Object?>(key: state.pageKey, name: RoutePath.kInitial, child: const HomePage()),
    ),
    for (final MapEntry(key: path, value: builder) in pageRoutes.entries)
      GoRoute(
        path: path,
        // The page name is the path, as with GetX's named routes, so route
        // observers keep matching on RoutePath values.
        pageBuilder: (context, state) => MaterialPage<Object?>(
          key: state.pageKey,
          name: path,
          arguments: state.extra,
          // 3.x wrapped every secondary page in its smooth-scroll scope.
          child: PureLiveRouteScrollScope(child: builder(RouteArgs(path, arguments: state.extra))),
        ),
      ),
  ],
);
