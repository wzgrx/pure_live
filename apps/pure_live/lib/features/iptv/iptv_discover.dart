import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';

/// The "网络电视" tab of 发现 (F-IPTV-05): every channel, or channels by
/// playlist group; without playlists, the way to import one.
class IptvDiscover extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(iptvPlaylistsProvider).value?.isEmpty ?? false) {
      return MessageView(
        icon: Icons.live_tv_outlined,
        title: '还没有播放列表',
        message: '导入 M3U、TXT 或 JSON 播放列表后，频道会按分组出现在这里，可以像直播间一样关注。',
        actionLabel: '导入播放列表',
        onAction: () => context.push(iptvLocation),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerHeight: 0,
                  tabs: [
                    Tab(text: '全部频道', height: 40),
                    Tab(text: '分组', height: 40),
                  ],
                ),
              ),
              IconButton(
                tooltip: '管理播放列表',
                icon: const Icon(Icons.playlist_add),
                onPressed: () => context.push(iptvLocation),
              ),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                RoomGrid(query: RecommendedQuery(IptvSite.platformId), emptyText: '播放列表里还没有频道'),
                _Groups(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Groups extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = categoriesProvider(IptvSite.platformId);
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    return ref
        .watch(provider)
        .when(
          loading: () => const LoadingView(),
          error: (error, _) {
            final text = describeError(error);
            return MessageView.error(
              title: text.title,
              message: text.message,
              onAction: () => ref.invalidate(provider),
            );
          },
          data: (playlists) => ListView(
            padding: EdgeInsets.symmetric(horizontal: layout.margin, vertical: Space.s2),
            children: [
              for (final playlist in playlists)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.s2),
                        child: Text(playlist.name, style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (playlist.areas.isEmpty) const Text('这个播放列表还没有同步'),
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s2,
                        children: [
                          for (final area in playlist.areas)
                            ActionChip(
                              label: Text(area.name),
                              onPressed: () => context.push(areaLocation(IptvSite.platformId), extra: area),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
  }
}
