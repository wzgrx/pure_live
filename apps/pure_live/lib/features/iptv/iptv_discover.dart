import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The "网络电视" tab of 发现 (F-IPTV-05): every channel, or channels by
/// playlist group; without playlists, the way to import one.
class IptvDiscover extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(iptvPlaylistsProvider).value?.isEmpty ?? false) {
      return MessageView(
        icon: LiveIcons.liveTv,
        title: t.iptv.noPlaylists,
        message: t.iptv.noPlaylistsHint,
        actionLabel: t.iptv.importPlaylist,
        onAction: () => context.push(iptvLocation),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: PageTabBar(
                  dividerHeight: 0,
                  tabs: [
                    Tab(text: t.iptv.allChannels, height: 40),
                    Tab(text: t.iptv.groups, height: 40),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.iptv.managePlaylists,
                icon: const LiveIcon(LiveIcons.addPlaylist),
                onPressed: () => context.push(iptvLocation),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                RoomGrid(query: const RecommendedQuery(IptvSite.platformId), emptyText: t.iptv.noChannels),
                const _Groups(),
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
          error: (error, _) => ErrorView(error, onRetry: () => ref.invalidate(provider)),
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
                      if (playlist.areas.isEmpty) Text(t.iptv.playlistNotSynced),
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s2,
                        children: [
                          for (final area in playlist.areas)
                            ActionChip(
                              label: Text(areaName(area)),
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
