import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/favorite/favorite_controller.dart';
import 'package:pure_live/pages/favorite/favorite_rules.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// Follows (pure_live_TV `FavoritePage` over v4's follows): live, replay and
/// offline tabs with their counts, then the platforms that have follows;
/// OK on the current tab refreshes the follows shown. The state, the
/// refresh rules and the order are the phone page's
/// (`favoriteControllerProvider`, M13.2).
class TvFavoritesPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvFavoritesPane> createState() => _TvFavoritesPaneState();
}

class _TvFavoritesPaneState extends ConsumerState<TvFavoritesPane> {
  final GlobalKey<TvTabBarState> _groupTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _platformTabs = GlobalKey();
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  FollowGroup _group = FollowGroup.live;
  String _platform = allPlatforms;

  GlobalKey<TvRoomGridState> _grid(String key) => _grids[key] ??= GlobalKey();

  static const List<(FollowGroup, String)> _groups = [
    (FollowGroup.live, 'tv_follow_live'),
    (FollowGroup.replay, 'tv_follow_replay'),
    (FollowGroup.offline, 'tv_follow_offline'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(favoriteControllerProvider);
    final platformOrder = watchSetting(ref, Settings.hotAreasList);
    final preferReal = watchSetting(ref, Settings.preferRealOnlineCounts);
    final realOnline = watchSetting(ref, Settings.realOnlinePlatforms).toSet();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final platforms = platformTabs(controller.rooms, platformOrder);
        if (!platforms.contains(_platform)) _platform = allPlatforms;
        final counts = groupCounts(controller.rooms, _platform);
        final rooms = roomsOf(
          controller.rooms,
          group: _group,
          platform: _platform,
          tagId: allTags,
          assignments: controller.assignments,
          order: FollowOrder(preferRealOnline: preferReal, realOnlinePlatforms: realOnline, tags: controller.tags),
        );
        final gridKey = _grid('${_group.name}/$_platform');
        void refresh() => unawaited(controller.refreshVisible());
        final body = !controller.loaded
            ? TvMessage(busy: true, title: i18n('tv_loading'))
            : rooms.isEmpty
            ? TvMessage(
                icon: Icons.favorite_border_rounded,
                title: i18n(controller.rooms.isEmpty ? 'tv_no_follows' : 'tv_no_rooms'),
                action: controller.rooms.isEmpty ? null : i18n('tv_refresh'),
                onAction: controller.rooms.isEmpty ? null : refresh,
              )
            : TvRoomGrid(
                key: gridKey,
                rooms: rooms,
                onLeaveUp: () {
                  if (_platformTabs.currentState?.focusSelected() ?? false) return;
                  _groupTabs.currentState?.focusSelected();
                },
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvTabBar(
              key: _groupTabs,
              tabs: [
                for (final (group, label) in _groups) TvTab(id: group.name, label: i18n(label), badge: counts[group]),
              ],
              selected: _groups.indexWhere((entry) => entry.$1 == _group),
              busy: controller.refreshing || controller.verifying,
              onSelect: (index) => setState(() => _group = _groups[index].$1),
              onRefresh: refresh,
              onDown: platforms.length > 2 ? null : () => gridKey.currentState?.enter() ?? false,
            ),
            if (platforms.length > 2)
              TvTabBar(
                key: _platformTabs,
                fontSize: 19,
                tabs: [
                  for (final id in platforms)
                    if (id == allPlatforms)
                      TvTab(id: id, label: i18n('tv_all_platforms'), icon: Icons.apps_rounded)
                    else
                      TvTab(id: id, label: platformName(id), logo: id),
                ],
                selected: platforms.indexOf(_platform),
                onSelect: (index) => setState(() => _platform = platforms[index]),
                onRefresh: refresh,
                onDown: () => gridKey.currentState?.enter() ?? false,
              ),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}
