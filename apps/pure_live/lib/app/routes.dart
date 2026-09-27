import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/shell.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/about/about_page.dart';
import 'package:pure_live_app/features/about/update_page.dart';
import 'package:pure_live_app/features/accounts/accounts_page.dart';
import 'package:pure_live_app/features/backup/backup_page.dart';
import 'package:pure_live_app/features/danmaku/block_list_page.dart';
import 'package:pure_live_app/features/danmaku/danmaku_settings.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/discover/area_page.dart';
import 'package:pure_live_app/features/discover/discover_page.dart';
import 'package:pure_live_app/features/follows/follow_order_page.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/health/platform_status_page.dart';
import 'package:pure_live_app/features/iptv/guide_page.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';
import 'package:pure_live_app/features/me/appearance_page.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/me/me_page.dart';
import 'package:pure_live_app/features/multiview/multiview_page.dart';
import 'package:pure_live_app/features/onboarding/onboarding_page.dart';
import 'package:pure_live_app/features/recording/recording_page.dart';
import 'package:pure_live_app/features/room/room_page.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/search/search_page.dart';
import 'package:pure_live_app/features/settings/platforms_page.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';
import 'package:pure_live_app/features/sync/lan_sync_page.dart';
import 'package:pure_live_app/features/sync/webdav_page.dart';
import 'package:pure_live_app/features/system/mini_player.dart';

/// Location of a room page; the room is a full-screen route outside the shell
/// (principles §4.1).
String roomLocation(RoomRef room) => '/room/${Uri.encodeComponent(room.platform)}/${Uri.encodeComponent(room.roomId)}';

/// The follows page on its live tab; the combined live alert opens it
/// (F-NEW-01).
const followsLiveLocation = '/follows?filter=live';

/// Search with [text] filled in and submitted.
String searchLocation(String text) => Uri(path: '/search', queryParameters: {'q': text}).toString();

/// Location of an area's room list.
String areaLocation(String platform) => '/discover/area/${Uri.encodeComponent(platform)}';

/// The app's routes: four top-level destinations keep their own stacks and
/// scroll positions; rooms open above them.
final routerProvider = Provider<GoRouter>((ref) {
  final startPage = ref.read(storeProvider).settings.get(Settings.startPage);
  // Every navigator reports its popups, which hide the mini window (PIP-4).
  final popups = ref.read(popupTrackerProvider);
  final router = GoRouter(
    initialLocation: startPage == StartPage.discover ? '/discover' : '/follows',
    observers: [PopupRouteObserver(popups)],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            observers: [PopupRouteObserver(popups)],
            routes: [
              GoRoute(
                path: '/follows',
                builder: (context, state) =>
                    FollowsPage(filter: state.uri.queryParameters['filter'], request: state.uri.queryParameters['at']),
                routes: [
                  GoRoute(path: 'groups', builder: (context, state) => const GroupsPage()),
                  GoRoute(path: 'order', builder: (context, state) => const FollowOrderPage()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [PopupRouteObserver(popups)],
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverPage(),
                routes: [
                  GoRoute(
                    path: 'area/:platform',
                    builder: (context, state) =>
                        AreaPage(platform: state.pathParameters['platform']!, area: state.extra as Area?),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [PopupRouteObserver(popups)],
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => SearchPage(initialQuery: state.uri.queryParameters['q']),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [PopupRouteObserver(popups)],
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MePage(),
                routes: [
                  GoRoute(path: 'appearance', builder: (context, state) => const AppearancePage()),
                  GoRoute(path: 'history', builder: (context, state) => const HistoryPage()),
                  GoRoute(
                    path: 'backup',
                    builder: (context, state) => const BackupPage(),
                    routes: [
                      GoRoute(path: 'webdav', builder: (context, state) => const WebDavPage()),
                      GoRoute(
                        path: 'lan',
                        builder: (context, state) => LanSyncPage(
                          receive: state.uri.queryParameters['receive'] == '1',
                          target: state.uri.queryParameters['target'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(path: 'diagnostics', builder: (context, state) => const DiagnosticsPage()),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
                    routes: [
                      GoRoute(path: 'update', builder: (context, state) => const UpdatePage()),
                      GoRoute(path: 'status', builder: (context, state) => const PlatformStatusPage()),
                    ],
                  ),
                  GoRoute(path: 'recordings', builder: (context, state) => const RecordingPage()),
                  GoRoute(path: 'accounts', builder: (context, state) => const AccountsPage()),
                  GoRoute(path: 'platforms', builder: (context, state) => const PlatformsPage()),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsPage(),
                    routes: [
                      GoRoute(
                        path: ':group',
                        builder: (context, state) =>
                            SettingsGroupPage(group: SettingsGroup.values.byName(state.pathParameters['group']!)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: welcomeLocation, builder: (context, state) => const OnboardingPage()),
      GoRoute(path: blockListLocation, builder: (context, state) => const BlockListPage()),
      GoRoute(
        path: iptvLocation,
        builder: (context, state) => IptvPage(initialImport: state.extra as IptvImportRequest?),
        routes: [GoRoute(path: 'guide', builder: (context, state) => const IptvGuidePage())],
      ),
      GoRoute(
        path: '/multiview',
        builder: (context, state) => MultiviewPage(rooms: (state.extra as List<RoomRef>?) ?? const []),
      ),
      GoRoute(
        path: '/room/:platform/:roomId',
        builder: (context, state) => RoomPage(
          room: RoomRef(state.pathParameters['platform']!, state.pathParameters['roomId']!),
          // The list the room was opened from, for switching (F-NEW-04).
          origin: state.extra is RoomOrigin ? state.extra! as RoomOrigin : null,
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
