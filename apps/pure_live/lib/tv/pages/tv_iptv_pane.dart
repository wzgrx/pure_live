import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';

/// One playlist of the IPTV pane: its name and its channels as rooms.
typedef TvPlaylist = ({String id, String name, List<LiveRoom> channels});

/// A channel (an IPTV area) as the room the TV room opens (the IPTV site
/// reads the channel by this id, like the phone's `openArea`).
LiveRoom tvChannelRoom(LiveArea channel) => LiveRoom(
  platform: SiteIds.iptv,
  roomId: channel.areaId,
  title: channel.areaName,
  nick: channel.typeName,
  cover: channel.areaPic,
  liveStatus: LiveStatus.live,
);

/// Loads the playlists of [site]: the built-in hot list first, then the
/// imported ones with their channels (the IPTV site's recommendations and
/// categories, M6). The hot list needs the network on first use; without it the imported
/// lists still show.
Future<List<TvPlaylist>> loadTvPlaylists(LiveSite site) async {
  var hot = const <LiveRoom>[];
  try {
    hot = await site.getRecommendRooms(pageSize: 0);
  } on Object {
    // Offline or the built-in list moved: imported lists only.
  }
  final categories = await site.getCategories(1, 0);
  return [
    if (hot.isNotEmpty) (id: 'hot', name: i18n('iptv_hot_playlist'), channels: hot),
    for (final category in categories)
      (id: category.id, name: category.name, channels: [for (final area in category.children) tvChannelRoom(area)]),
  ];
}

/// IPTV on the TV (pure_live_TV `modules/live/iptv`, over v4's IPTV site):
/// the playlists on the left, the chosen one's channels numbered on the
/// right. A channel plays in the TV room with its playlist as the channel
/// list, so Up and Down zap through the playlist. Importing and managing
/// playlists and guides stays on the IPTV page ("manage").
class TvIptvPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvIptvPane> createState() => _TvIptvPaneState();
}

class _TvIptvPaneState extends ConsumerState<TvIptvPane> {
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  final Map<String, FocusNode> _listNodes = {};
  Future<List<TvPlaylist>>? _playlists;
  String? _current;

  GlobalKey<TvRoomGridState> _grid(String id) => _grids[id] ??= GlobalKey();

  FocusNode _listNode(String id) => _listNodes[id] ??= FocusNode(debugLabel: 'playlist $id');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _listNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _load() {
    final site = ref.read(sitesProvider).maybeOf(SiteIds.iptv);
    _playlists = site == null ? null : loadTvPlaylists(site);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlists;
    if (playlists == null) return TvMessage(icon: Icons.live_tv_rounded, title: i18n('tv_iptv_unavailable'));
    return FutureBuilder<List<TvPlaylist>>(
      future: playlists,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TvMessage(
            icon: Icons.error_outline_rounded,
            title: describeLoadError(snapshot.error),
            action: i18n('retry'),
            onAction: () => setState(_load),
          );
        }
        final lists = snapshot.data;
        if (lists == null) return TvMessage(busy: true, title: i18n('tv_loading'));
        if (lists.isEmpty) {
          return TvMessage(
            icon: Icons.playlist_add_rounded,
            title: i18n('tv_iptv_empty'),
            action: i18n('iptv_manage'),
            onAction: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kIptv)),
          );
        }
        final current = lists.firstWhere((list) => list.id == _current, orElse: () => lists.first);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: TvScale.of(context).text(300), child: _playlistColumn(lists, current)),
            Expanded(
              child: current.channels.isEmpty
                  ? TvMessage(icon: Icons.live_tv_rounded, title: i18n('tv_no_rooms'))
                  : TvRoomGrid(key: _grid(current.id), rooms: current.channels, numbered: true),
            ),
          ],
        );
      },
    );
  }

  Widget _playlistColumn(List<TvPlaylist> lists, TvPlaylist current) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return ListView(
      padding: EdgeInsets.all(scale(20)),
      children: [
        for (final list in lists)
          Padding(
            padding: EdgeInsets.only(bottom: scale(10)),
            child: TvFocusable(
              key: ValueKey('tv-playlist-${list.id}'),
              focusNode: _listNode(list.id),
              scale: 1.03,
              onTap: () => setState(() => _current = list.id),
              onKey: (node, event) {
                if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowRight) {
                  return KeyEventResult.ignored;
                }
                if (list.id != current.id) setState(() => _current = list.id);
                final grid = _grid(list.id);
                WidgetsBinding.instance.addPostFrameCallback((_) => grid.currentState?.enter());
                return KeyEventResult.handled;
              },
              builder: (context, focused) {
                final selected = list.id == current.id;
                final color = focused ? palette.onFocus : (selected ? palette.focus : palette.text);
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: scale.text(18), vertical: scale.text(12)),
                  decoration: BoxDecoration(
                    color: focused
                        ? palette.focus
                        : (selected ? palette.focus.withValues(alpha: 0.2) : palette.card.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(scale(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: scale.style(21, weight: FontWeight.w600, color: color),
                      ),
                      Text(
                        i18n('iptv_channel_count', args: {'count': '${list.channels.length}'}),
                        style: scale.style(16, color: color.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: scale(10)),
          child: TvButton(
            key: const ValueKey('tv-iptv-manage'),
            icon: Icons.tune_rounded,
            label: i18n('iptv_manage'),
            fontSize: 19,
            expand: true,
            onTap: () async {
              await AppNavigator.toNamed<void>(RoutePath.kIptv);
              if (mounted) setState(_load);
            },
          ),
        ),
      ],
    );
  }
}
