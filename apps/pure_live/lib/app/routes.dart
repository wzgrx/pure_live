import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/app/shell.dart';
import 'package:pure_live_app/features/backup/backup_page.dart';
import 'package:pure_live_app/features/discover/area_page.dart';
import 'package:pure_live_app/features/discover/discover_page.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/me/appearance_page.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/me/me_page.dart';
import 'package:pure_live_app/features/room/room_page.dart';
import 'package:pure_live_app/features/search/search_page.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';

/// Location of a room page; the room is a full-screen route outside the shell
/// (principles §4.1).
String roomLocation(RoomRef room) => '/room/${Uri.encodeComponent(room.platform)}/${Uri.encodeComponent(room.roomId)}';

/// Location of an area's room list.
String areaLocation(String platform) => '/discover/area/${Uri.encodeComponent(platform)}';

/// The app's routes: four top-level destinations keep their own stacks and
/// scroll positions; rooms open above them.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/follows',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/follows', builder: (context, state) => const FollowsPage())],
          ),
          StatefulShellBranch(
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
            routes: [GoRoute(path: '/search', builder: (context, state) => const SearchPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MePage(),
                routes: [
                  GoRoute(path: 'appearance', builder: (context, state) => const AppearancePage()),
                  GoRoute(path: 'history', builder: (context, state) => const HistoryPage()),
                  GoRoute(path: 'backup', builder: (context, state) => const BackupPage()),
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
      GoRoute(
        path: '/room/:platform/:roomId',
        builder: (context, state) =>
            RoomPage(room: RoomRef(state.pathParameters['platform']!, state.pathParameters['roomId']!)),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
