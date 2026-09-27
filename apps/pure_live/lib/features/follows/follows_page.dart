import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follow_status.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Which follows to show: live, all, or all by group (principles §4.1).
enum _Filter { live, all, group }

/// The sort menu entry that opens the custom order page.
const _editOrder = 'editOrder';

/// Menu labels of the orders (F-FAV-01).
const Map<FollowSort, String> followSortLabels = {
  FollowSort.audience: '按人数',
  FollowSort.liveTime: '按开播时间',
  FollowSort.platform: '按平台',
  FollowSort.custom: '自定义顺序',
};

/// Followed streamers: live ones as cover cards, the rest as compact rows
/// without covers (principles §4.1, §4.3), in the remembered order
/// (F-FAV-01). Until the first refresh after launch publishes, nothing is
/// shown as live (F-FAV-03).
class FollowsPage extends ConsumerStatefulWidget {
  const new({this.filter, this.request, super.key});

  /// `live` opens the live tab (the combined live alert, F-NEW-01).
  final String? filter;

  /// Changes with each outside request, so a repeated request applies
  /// [filter] again after the user switched tabs.
  final String? request;

  @override
  ConsumerState<FollowsPage> createState() => _FollowsPageState();
}

class _FollowsPageState extends ConsumerState<FollowsPage> {
  late _Filter _filter = _requested ?? _Filter.all;

  _Filter? get _requested => widget.filter == 'live' ? _Filter.live : null;

  @override
  void didUpdateWidget(FollowsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = _requested;
    if (requested != null && (widget.request != oldWidget.request || widget.filter != oldWidget.filter)) {
      _filter = requested;
    }
  }

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final refresh = ref.watch(followRefreshProvider);
    final session = FollowSession.of(refresh);
    final sites = ref.watch(sitesProvider);
    final sort = ref.watch(followSortSetting);
    final platforms = ref.watch(enabledPlatformsProvider);
    final entries = [
      for (final follow in follows.value ?? const <FollowedRoom>[])
        (follow: follow, status: session.statusOf(follow, supported: sites.containsKey(follow.ref.platform))),
    ];
    final live = sortLive(
      entries.where((entry) => entry.status == FollowStatus.live),
      sort,
      platforms: platforms,
      liveSince: session.liveSince,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.follows),
        actions: [
          PopupMenuButton<Object>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            onSelected: (choice) async {
              final setting = ref.read(followSortSetting.notifier);
              if (choice is FollowSort) {
                await setting.set(choice);
                return;
              }
              // "调整顺序" switches to the custom order it edits.
              await setting.set(FollowSort.custom);
              if (context.mounted) unawaited(context.push('/follows/order'));
            },
            itemBuilder: (context) => [
              for (final MapEntry(key: option, value: label) in followSortLabels.entries)
                CheckedPopupMenuItem<Object>(value: option, checked: option == sort, child: Text(label)),
              const PopupMenuDivider(),
              const PopupMenuItem<Object>(value: _editOrder, child: Text('调整自定义顺序')),
            ],
          ),
          IconButton(
            tooltip: '一键多画面',
            icon: const Icon(Icons.grid_view),
            // Live follows in their shown order fill the grid (ENT-1).
            onPressed: () => unawaited(context.push('/multiview', extra: [for (final entry in live) entry.follow.ref])),
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
          return RefreshIndicator(
            onRefresh: () => ref.read(followRefreshProvider.notifier).refresh(),
            child: _FollowList(
              live: live,
              rows: sortRows(entries.where((entry) => entry.status != FollowStatus.live), sort, platforms: platforms),
              session: session,
              filter: _filter,
              onFilter: (filter) => setState(() => _filter = filter),
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
    required this.rows,
    required this.session,
    required this.filter,
    required this.onFilter,
  });

  /// Live follows in the chosen order.
  final List<FollowEntry> live;

  /// The rest in the chosen order.
  final List<FollowEntry> rows;
  final FollowSession session;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  @override
  ConsumerState<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends ConsumerState<_FollowList> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'follows-grid');
  final Map<String, TvGridFocus> _groupFocus = {};

  @override
  void dispose() {
    _focus.dispose();
    for (final focus in _groupFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final filter = widget.filter;
    final session = widget.session;
    final failedPlatforms = session.result?.failedPlatforms ?? const <String>{};
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final dense = ref.watch(denseFollowsSetting);
    final preferOnline = ref.watch(preferRealOnlineSetting);
    final density = dense ? CardDensity.compact : CardDensity.standard;
    final recording = ref.watch(recordingRoomsProvider).value ?? const <String>{};
    final period = ref.watch(coverPeriodProvider);
    final tags = filter == _Filter.group ? ref.watch(tagsProvider).value ?? const <Tag>[] : const <Tag>[];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final now = DateTime.now();
    // Up and down in a room opened here step through the live follows as
    // shown (F-NEW-04); rooms opened from the rows use it too.
    final origin = RoomOrigin([
      for (final entry in live)
        RoomEntry(entry.follow.ref, name: entry.follow.room.anchorName, title: entry.follow.room.title),
    ], label: '开播的关注');
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = CardGridGeometry.of(context, constraints.maxWidth, density: density);
        final margin = TvScope.of(context).enabled ? grid.padding.left : layout.margin;

        void open(FollowEntry entry) {
          final room = entry.follow.ref;
          if (entry.status == FollowStatus.unsupported) {
            // F-FAV-08: say so instead of opening a room that cannot load.
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('${platformName(room.platform)}已下线或这个版本还不支持，关注会一直保留')));
            return;
          }
          unawaited(context.push(roomLocation(room), extra: origin));
        }

        void menu(FollowEntry entry) =>
            unawaited(showRoomCardMenu(context, ref, room: entry.follow.ref, anchorName: entry.follow.room.anchorName));

        Widget liveGrid(List<FollowEntry> cards, TvGridFocus focus) => SliverPadding(
          padding: EdgeInsets.fromLTRB(grid.padding.left, Space.s1, grid.padding.right, 0),
          sliver: SliverGrid.builder(
            gridDelegate: grid.delegate,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final entry = cards[index];
              final room = entry.follow.room;
              final audience = shownAudience(room.audience, preferOnline: preferOnline);
              final since = session.liveSince(entry.follow);
              return RoomCardView(
                platformId: room.ref.platform,
                anchorName: room.anchorName,
                title: room.title,
                isLive: true,
                cover: networkImage(room.cover, logicalWidth: grid.cellWidth, devicePixelRatio: dpr, period: period),
                audience: audience == null ? null : formatCount(audience),
                liveFor: since == null ? null : formatLiveDuration(now.difference(since)),
                recording: recording.contains(room.ref.key),
                density: density,
                focusNode: focus.node(index),
                onFocusChange: (focused) {
                  if (focused) focus.focused(index);
                },
                onKeyEvent: (node, event) => focus.handleKey(
                  index,
                  event,
                  count: cards.length,
                  columns: grid.columns,
                  rowExtent: grid.rowExtent,
                ),
                onTap: () => open(entry),
                onMenu: () => menu(entry),
              );
            },
          ),
        );

        Widget rowList(List<FollowEntry> rows) => SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final entry = rows[index];
            final room = entry.follow.room;
            final last = room.lastLiveAt;
            final lastText = last == null ? null : '上次开播 ${formatAgo(last, now)}';
            final (String? tag, String subtitle) = switch (entry.status) {
              FollowStatus.unsupported => ('未支持', '${platformName(room.ref.platform)} · 暂不支持'),
              FollowStatus.unknown => ('状态未知', lastText ?? '没能获取开播状态'),
              FollowStatus.missing => ('房间不存在', lastText ?? '平台找不到这个房间'),
              FollowStatus.replay => ('轮播', lastText ?? '正在轮播'),
              FollowStatus.checking => (null, lastText ?? '正在检查开播状态'),
              FollowStatus.offline || FollowStatus.live => (null, lastText ?? S.offline),
            };
            return OfflineRoomRow(
              platformId: room.ref.platform,
              anchorName: room.anchorName.isEmpty ? room.ref.roomId : room.anchorName,
              avatar: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
              subtitle: subtitle,
              tag: tag,
              recording: recording.contains(room.ref.key),
              onTap: () => open(entry),
              onMenu: () => menu(entry),
            );
          },
        );

        Widget heading(String text, {String? detail, double top = Space.s6}) => SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, top, margin, Space.s1),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: theme.textTheme.titleSmall),
                if (detail != null && detail.isNotEmpty)
                  Text(detail, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );

        final slivers = <Widget>[
          if (failedPlatforms.isNotEmpty)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text('${failedPlatforms.map(platformName).join('、')} 刷新失败，这些主播的状态暂时未知'),
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
                runSpacing: Space.s2,
                children: [
                  ChoiceChip(
                    label: Text(session.checking ? '开播' : '开播 ${live.length}'),
                    selected: filter == _Filter.live,
                    onSelected: (_) => widget.onFilter(_Filter.live),
                  ),
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: filter == _Filter.all,
                    onSelected: (_) => widget.onFilter(_Filter.all),
                  ),
                  ChoiceChip(
                    label: const Text('分组'),
                    selected: filter == _Filter.group,
                    onSelected: (_) => widget.onFilter(_Filter.group),
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
          // F-FAV-03: one line while the first refresh runs; no card claims
          // a state from an earlier run.
          if (session.checking)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, Space.s1, margin, Space.s1),
              sliver: const SliverToBoxAdapter(
                child: Row(
                  children: [
                    SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: Space.s2),
                    Text('正在检查开播状态'),
                  ],
                ),
              ),
            ),
          ...switch (filter) {
            _Filter.live => [
              if (live.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: MessageView(title: session.checking ? '正在检查开播状态' : '关注的主播都没开播'),
                  ),
                ),
              liveGrid(live, _focus),
            ],
            _Filter.all => [
              liveGrid(live, _focus),
              if (widget.rows.isNotEmpty)
                heading(session.checking ? '全部关注 ${widget.rows.length}' : '未开播 ${widget.rows.length}'),
              rowList(widget.rows),
            ],
            _Filter.group => _groups(tags, heading, liveGrid, rowList),
          },
          const SliverToBoxAdapter(child: SizedBox(height: Space.s8)),
        ];
        return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers);
      },
    );
  }

  /// The group view (F-FAV-05): one section per tag in the user's order, then
  /// the follows without tags; a follow in several groups shows in each.
  List<Widget> _groups(
    List<Tag> tags,
    Widget Function(String text, {String? detail, double top}) heading,
    Widget Function(List<FollowEntry> cards, TvGridFocus focus) liveGrid,
    Widget Function(List<FollowEntry> rows) rowList,
  ) {
    final sections = <(String id, String title, String description, bool Function(FollowEntry entry) member)>[
      for (final tag in tags) (tag.id, tag.name, tag.description, (entry) => entry.follow.tagIds.contains(tag.id)),
      ('', '未分组', '', (entry) => entry.follow.tagIds.every((id) => !tags.any((tag) => tag.id == id))),
    ];
    return [
      if (tags.isEmpty)
        SliverToBoxAdapter(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('还没有分组'),
            subtitle: const Text('在“管理分组”新建分组，再从主播的更多菜单里设置分组'),
            onTap: () => context.push('/follows/groups'),
          ),
        ),
      for (final (id, title, description, member) in sections)
        ...() {
          final cards = widget.live.where(member).toList();
          final rows = widget.rows.where(member).toList();
          if (id.isEmpty && cards.isEmpty && rows.isEmpty) return const <Widget>[];
          final focus = _groupFocus.putIfAbsent(id, () => TvGridFocus(debugLabel: 'follows-group-$id'));
          return [
            heading('$title · ${cards.length + rows.length}', detail: description, top: Space.s4),
            if (cards.isEmpty && rows.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
                  child: Text('这个分组还没有主播'),
                ),
              ),
            liveGrid(cards, focus),
            rowList(rows),
          ];
        }(),
    ];
  }
}
