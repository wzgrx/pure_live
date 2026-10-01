import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/about/about_page.dart';
import 'package:pure_live/features/account/account_page.dart';
import 'package:pure_live/features/area_rooms/area_rooms_page.dart';
import 'package:pure_live/features/areas/areas_page.dart';
import 'package:pure_live/features/auth/auth_page.dart';
import 'package:pure_live/features/backup/backup_page.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/history/history_page.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/hot_areas/hot_areas_page.dart';
import 'package:pure_live/features/iptv/iptv_page.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/features/record_settings/record_settings_page.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/features/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/features/search/search_page.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/features/shield/shield_page.dart';
import 'package:pure_live/features/splash/splash_page.dart';
import 'package:pure_live/features/tags/tags_page.dart';
import 'package:pure_live/features/toolbox/toolbox_page.dart';
import 'package:pure_live/features/version/version_page.dart';
import 'package:pure_live/features/web_dav/web_dav_page.dart';
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
  RoutePath.kLocalInteraction: (route) => LocalInteractionSettingsPage(route: route),
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
        pageBuilder: (context, state) {
          // 3.x wrapped every secondary page in its smooth-scroll scope.
          final child = PureLiveRouteScrollScope(child: builder(RouteArgs(path, arguments: state.extra)));
          return path == RoutePath.kLivePlay
              ? liveRoomPage(key: state.pageKey, arguments: state.extra, child: child)
              : MaterialPage<Object?>(key: state.pageKey, name: path, arguments: state.extra, child: child);
        },
      ),
  ],
);

/// The live room's page: the app's fade-forwards transition for the room
/// itself, while the page under it stays where it is (M13.16).
///
/// With a `MaterialPage` the page under the room slides in from a quarter
/// of the screen to the left for 450 ms (an emphasized curve) when the room
/// closes, so a tab tapped where it rests right after leaving a room hit
/// whatever was there instead (often the tab already chosen: "the tap did
/// nothing"). A page route that is not a Material one is not followed by
/// the page under it (`MaterialRouteTransitionMixin.canTransitionTo`).
Page<Object?> liveRoomPage({required LocalKey key, required Widget child, Object? arguments}) =>
    CustomTransitionPage<Object?>(
      key: key,
      name: RoutePath.kLivePlay,
      arguments: arguments,
      transitionDuration: const Duration(milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds),
      reverseTransitionDuration: const Duration(
        milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => const FadeForwardsPageTransitionsBuilder()
          .buildTransitions<Object?>(null, context, animation, secondaryAnimation, child),
      child: child,
    );
