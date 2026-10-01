import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// How many rooms a TV page asks for at a time (pure_live_TV pages 12 at a
/// time; a 1080p grid shows about twelve, so two screens).
const int tvPageSize = 24;

/// Shows [feed]'s rooms in a [TvRoomGrid], with the loading, failed and
/// empty states; the grid asks for the next [tvPageSize] rooms near its
/// end.
class TvFeedGrid extends StatelessWidget {
  /// Creates the view of [feed].
  const new({required this.feed, required this.gridKey, this.onLeaveUp, super.key});

  /// The rooms.
  final RoomFeed feed;

  /// The grid's key (the page puts the focus in it).
  final GlobalKey<TvRoomGridState> gridKey;

  /// Up on the first row.
  final VoidCallback? onLeaveUp;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feed,
    builder: (context, _) {
      final rooms = feed.rooms;
      if (rooms.isEmpty) {
        if (!feed.loaded || feed.busy) return TvMessage(busy: true, title: i18n('tv_loading'));
        if (feed.error != null) {
          return TvMessage(
            icon: Icons.error_outline_rounded,
            title: describeLoadError(feed.error),
            action: i18n('retry'),
            onAction: () => unawaited(feed.retry(count: tvPageSize)),
          );
        }
        return TvMessage(
          icon: Icons.live_tv_rounded,
          title: i18n('tv_no_rooms'),
          action: i18n('tv_refresh'),
          onAction: () => unawaited(feed.refresh(count: tvPageSize)),
        );
      }
      return TvRoomGrid(
        key: gridKey,
        rooms: rooms,
        onLeaveUp: onLeaveUp,
        onEndReached: () {
          if (feed.hasMore && !feed.busy) unawaited(feed.ensure(rooms.length + tvPageSize));
        },
      );
    },
  );
}

/// Recommended rooms (pure_live_TV `HotPage`, v4's popular catalogue): one
/// tab per platform of the platform list, the feeds shared with the phone
/// page (`popularCatalogProvider`, M12.2), so the ranking, the hidden
/// unplayable rooms and the per-platform paging are the same.
class TvPopularPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvPopularPane> createState() => _TvPopularPaneState();
}

class _TvPopularPaneState extends ConsumerState<TvPopularPane> {
  late final PopularCatalog _catalog = ref.read(popularCatalogProvider);
  final GlobalKey<TvTabBarState> _tabs = GlobalKey();
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  String? _current;

  GlobalKey<TvRoomGridState> _grid(String platform) => _grids[platform] ??= GlobalKey();

  @override
  void initState() {
    super.initState();
    HomeSignals.resumedAfterBackground.addListener(_resumed);
  }

  @override
  void dispose() {
    HomeSignals.resumedAfterBackground.removeListener(_resumed);
    super.dispose();
  }

  void _resumed() {
    final signal = HomeSignals.resumedAfterBackground.value;
    final current = _current;
    if (signal != null && signal.$1 == HomeMenu.popular && current != null) {
      unawaited(_catalog.feedOf(current).refresh(count: tvPageSize));
    }
  }

  void _select(String platform) {
    setState(() => _current = platform);
    _catalog.currentPlatform = platform;
    unawaited(_catalog.feedOf(platform).open(count: tvPageSize));
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    if (ids.isEmpty) return TvMessage(icon: Icons.apps_rounded, title: i18n('tv_no_platforms'));
    var current = _current;
    if (current == null || !ids.contains(current)) {
      final preferred = _catalog.currentPlatform ?? ref.read(storeProvider).settings.get(Settings.preferPlatform);
      current = _current = ids.contains(preferred) ? preferred : ids.first;
      _catalog.currentPlatform = current;
      final first = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_catalog.feedOf(first).open(count: tvPageSize));
      });
    }
    final feed = _catalog.feedOf(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: feed,
          builder: (context, _) => TvTabBar(
            key: _tabs,
            tabs: [
              for (final id in ids)
                TvTab(
                  id: id,
                  label: platformName(id, fallback: sites.of(id).name),
                  logo: id,
                ),
            ],
            selected: ids.indexOf(current!),
            busy: feed.busy,
            onSelect: (index) => _select(ids[index]),
            onRefresh: () => unawaited(feed.refresh(count: tvPageSize)),
            onDown: () => _grid(current!).currentState?.enter() ?? false,
          ),
        ),
        Expanded(
          child: TvFeedGrid(
            key: ValueKey('tv-popular-$current'),
            feed: feed,
            gridKey: _grid(current),
            onLeaveUp: () => _tabs.currentState?.focusSelected(),
          ),
        ),
      ],
    );
  }
}
