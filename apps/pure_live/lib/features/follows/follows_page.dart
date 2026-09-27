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
import 'package:pure_live_app/l10n/strings.dart';

/// Which follows to show.
enum _Filter { live, all }

/// Followed streamers: live ones as cover cards sorted by audience, offline
/// ones as compact rows without covers (principles §4.1, §4.3).
class FollowsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FollowsPage> createState() => _FollowsPageState();
}

class _FollowsPageState extends ConsumerState<FollowsPage> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final refresh = ref.watch(followRefreshProvider);
    final failed = refresh.value?.failedPlatforms ?? const <String>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.follows),
        actions: [
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
          final live = rooms.where((f) => f.room.lastState == LiveState.live).toList()
            ..sort((a, b) => _audience(b.room).compareTo(_audience(a.room)));
          final offline = rooms.where((f) => f.room.lastState != LiveState.live).toList()
            ..sort((a, b) => (b.room.lastLiveAt ?? DateTime(0)).compareTo(a.room.lastLiveAt ?? DateTime(0)));
          return RefreshIndicator(
            onRefresh: () => ref.read(followRefreshProvider.notifier).refresh(),
            child: _FollowList(
              live: live,
              offline: _filter == _Filter.all ? offline : const [],
              filter: _filter,
              failedPlatforms: failed,
              onFilter: (filter) => setState(() => _filter = filter),
            ),
          );
        },
      ),
    );
  }

  static int _audience(StoredRoom room) =>
      room.audience.online ?? room.audience.popularity ?? room.audience.cumulative ?? 0;
}

class _FollowList extends ConsumerWidget {
  const new({
    required this.live,
    required this.offline,
    required this.filter,
    required this.failedPlatforms,
    required this.onFilter,
  });

  final List<FollowedRoom> live;
  final List<FollowedRoom> offline;
  final _Filter filter;
  final Set<String> failedPlatforms;
  final ValueChanged<_Filter> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final dense = ref.watch(denseFollowsSetting);
    final density = dense ? CardDensity.compact : CardDensity.standard;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth - 2 * layout.margin;
        final columns = layout.columnsFor(inner);
        final cellWidth = (inner - (columns - 1) * layout.gap) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final textHeight = (dense ? 24 : 44) * textScale + 12;
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
              padding: EdgeInsets.symmetric(horizontal: layout.margin, vertical: Space.s2),
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
              padding: EdgeInsets.symmetric(horizontal: layout.margin),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: layout.gap,
                  crossAxisSpacing: layout.gap,
                  mainAxisExtent: cellWidth * 9 / 16 + textHeight,
                ),
                itemCount: live.length,
                itemBuilder: (context, index) {
                  final room = live[index].room;
                  final audience = room.audience.online ?? room.audience.popularity ?? room.audience.cumulative;
                  return RoomCardView(
                    platformId: room.ref.platform,
                    anchorName: room.anchorName,
                    title: room.title,
                    isLive: true,
                    cover: networkImage(room.cover, logicalWidth: cellWidth, devicePixelRatio: dpr),
                    audience: audience == null ? null : formatCount(audience),
                    density: density,
                    onTap: () => context.push(roomLocation(room.ref)),
                    onMenu: () => _showMenu(context, ref, live[index]),
                  );
                },
              ),
            ),
            if (offline.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(layout.margin, Space.s6, layout.margin, Space.s1),
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
                  onTap: () => context.push(roomLocation(room.ref)),
                  onMenu: () => _showMenu(context, ref, offline[index]),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Space.s8)),
          ],
        );
      },
    );
  }

  /// The card menu (principles §4.2); unfollow can be undone.
  Future<void> _showMenu(BuildContext context, WidgetRef ref, FollowedRoom follow) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(follow.room.anchorName), subtitle: Text(platformNames[follow.ref.platform] ?? '')),
            ListTile(
              leading: const Icon(Icons.heart_broken_outlined),
              title: const Text('取消关注'),
              onTap: () => Navigator.pop(context, 'unfollow'),
            ),
          ],
        ),
      ),
    );
    if (action != 'unfollow' || !context.mounted) return;
    final store = ref.read(storeProvider);
    final removed = await store.follows.unfollow(follow.ref);
    if (removed == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已取消关注 ${follow.room.anchorName}'),
        action: SnackBarAction(label: '撤销', onPressed: () => store.follows.restore([removed])),
      ),
    );
  }
}
