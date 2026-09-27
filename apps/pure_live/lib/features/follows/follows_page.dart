import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Which follows to show: live, all, or one group.
enum _Filter { live, all, group }

/// Followed streamers: live ones as cover cards sorted by audience, offline
/// ones as compact rows without covers (principles §4.1, §4.3).
class FollowsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FollowsPage> createState() => _FollowsPageState();
}

class _FollowsPageState extends ConsumerState<FollowsPage> {
  _Filter _filter = _Filter.all;
  String? _groupId;

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final refresh = ref.watch(followRefreshProvider);
    final failed = refresh.value?.failedPlatforms ?? const <String>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.follows),
        actions: [
          IconButton(
            tooltip: '一键多画面',
            icon: const Icon(Icons.grid_view),
            onPressed: () {
              // Live follows in their shown order fill the grid (ENT-1).
              final live = [
                for (final follow in follows.value ?? const <FollowedRoom>[])
                  if (follow.room.lastState == LiveState.live) follow,
              ]..sort((a, b) => followAudience(b.room).compareTo(followAudience(a.room)));
              unawaited(context.push('/multiview', extra: [for (final f in live) f.ref]));
            },
          ),
          if (refresh.isLoading)
            const Padding(
              padding: EdgeInsets.all(Space.s4),
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              tooltip: '刷新开播状态',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(followRefreshProvider.notifier).refresh(),
            ),
        ],
      ),
      body: follows.when(
        loading: () => const LoadingView(),
        error: (error, _) => MessageView.error(title: '读取关注失败', message: '$error'),
        data: (rooms) {
          if (rooms.isEmpty) {
            return MessageView(
              icon: Icons.favorite_border,
              title: S.followsEmptyTitle,
              message: S.followsEmptyMessage,
              actionLabel: S.goDiscover,
              onAction: () => context.go('/discover'),
            );
          }
          final shown = _filter == _Filter.group && _groupId != null
              ? rooms.where((f) => f.tagIds.contains(_groupId)).toList()
              : rooms;
          final live = shown.where((f) => f.room.lastState == LiveState.live).toList()
            ..sort((a, b) => followAudience(b.room).compareTo(followAudience(a.room)));
          final offline = shown.where((f) => f.room.lastState != LiveState.live).toList()
            ..sort((a, b) => (b.room.lastLiveAt ?? DateTime(0)).compareTo(a.room.lastLiveAt ?? DateTime(0)));
          return RefreshIndicator(
            onRefresh: () => ref.read(followRefreshProvider.notifier).refresh(),
            child: _FollowList(
              live: live,
              offline: _filter == _Filter.live ? const [] : offline,
              filter: _filter,
              groupId: _groupId,
              failedPlatforms: failed,
              onFilter: (filter, {groupId}) => setState(() {
                _filter = filter;
                _groupId = groupId;
              }),
            ),
          );
        },
      ),
    );
  }
}

class _FollowList extends ConsumerStatefulWidget {
  const new({
    required this.live,
    required this.offline,
    required this.filter,
    required this.groupId,
    required this.failedPlatforms,
    required this.onFilter,
  });

  final List<FollowedRoom> live;
  final List<FollowedRoom> offline;
  final _Filter filter;
  final String? groupId;
  final Set<String> failedPlatforms;
  final void Function(_Filter filter, {String? groupId}) onFilter;

  @override
  ConsumerState<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends ConsumerState<_FollowList> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'follows-grid');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final offline = widget.offline;
    final filter = widget.filter;
    final groupId = widget.groupId;
    final failedPlatforms = widget.failedPlatforms;
    final onFilter = widget.onFilter;
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final dense = ref.watch(denseFollowsSetting);
    final density = dense ? CardDensity.compact : CardDensity.standard;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final now = DateTime.now();
    // Up and down in a room opened here step through the live follows as
    // shown (F-NEW-04); rooms opened from the offline list use it too.
    final origin = RoomOrigin([
      for (final follow in live) RoomEntry(follow.ref, name: follow.room.anchorName, title: follow.room.title),
    ], label: '开播的关注');
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = CardGridGeometry.of(context, constraints.maxWidth, density: density);
        final margin = TvScope.of(context).enabled ? grid.padding.left : layout.margin;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (failedPlatforms.isNotEmpty)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text('${failedPlatforms.map((p) => platformNames[p] ?? p).join('、')} 刷新失败，显示的是上次的状态'),
                  actions: [
                    TextButton(
                      onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: margin, vertical: Space.s2),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: Space.s2,
                  children: [
                    ChoiceChip(
                      label: Text('开播 ${live.length}'),
                      selected: filter == _Filter.live,
                      onSelected: (_) => onFilter(_Filter.live),
                    ),
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: filter == _Filter.all,
                      onSelected: (_) => onFilter(_Filter.all),
                    ),
                    for (final tag in ref.watch(tagsProvider).value ?? const <Tag>[])
                      ChoiceChip(
                        label: Text(tag.name),
                        selected: filter == _Filter.group && groupId == tag.id,
                        onSelected: (_) => onFilter(_Filter.group, groupId: tag.id),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: const Text('管理分组'),
                      onPressed: () => context.push('/follows/groups'),
                    ),
                  ],
                ),
              ),
            ),
            if (live.isEmpty && filter == _Filter.live)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: MessageView(title: '关注的主播都没开播'),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(grid.padding.left, Space.s1, grid.padding.right, 0),
              sliver: SliverGrid.builder(
                gridDelegate: grid.delegate,
                itemCount: live.length,
                itemBuilder: (context, index) {
                  final room = live[index].room;
                  final audience = room.audience.online ?? room.audience.popularity ?? room.audience.cumulative;
                  return RoomCardView(
                    platformId: room.ref.platform,
                    anchorName: room.anchorName,
                    title: room.title,
                    isLive: true,
                    cover: networkImage(room.cover, logicalWidth: grid.cellWidth, devicePixelRatio: dpr),
                    audience: audience == null ? null : formatCount(audience),
                    density: density,
                    focusNode: _focus.node(index),
                    onFocusChange: (focused) {
                      if (focused) _focus.focused(index);
                    },
                    onKeyEvent: (node, event) => _focus.handleKey(
                      index,
                      event,
                      count: live.length,
                      columns: grid.columns,
                      rowExtent: grid.rowExtent,
                    ),
                    onTap: () => context.push(roomLocation(room.ref), extra: origin),
                    onMenu: () =>
                        unawaited(showRoomCardMenu(context, ref, room: room.ref, anchorName: room.anchorName)),
                  );
                },
              ),
            ),
            if (offline.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, Space.s6, margin, Space.s1),
                sliver: SliverToBoxAdapter(
                  child: Text('未开播 ${offline.length}', style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
            SliverList.builder(
              itemCount: offline.length,
              itemBuilder: (context, index) {
                final room = offline[index].room;
                final last = room.lastLiveAt;
                return OfflineRoomRow(
                  platformId: room.ref.platform,
                  anchorName: room.anchorName,
                  avatar: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
                  subtitle: last == null ? S.offline : '上次开播 ${formatAgo(last, now)}',
                  onTap: () => context.push(roomLocation(room.ref), extra: origin),
                  onMenu: () => unawaited(showRoomCardMenu(context, ref, room: room.ref, anchorName: room.anchorName)),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Space.s8)),
          ],
        );
      },
    );
  }
}
