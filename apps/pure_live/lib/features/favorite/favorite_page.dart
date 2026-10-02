import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/favorite_rules.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The page width from which the platform tabs join the status tabs in the
/// app bar (docs/ui/compare/U.4c c3, choice C3).
const double favoriteOneRowWidth = 840;

/// The smallest large card when "compact mode" is off (U.4c c6: one column
/// on phones, like 3.x).
const double favoriteLargeCardMinWidth = 300;

/// The smallest row of the offline tab on wide screens (U.4c c5).
const double favoriteRowMinWidth = 320;

/// Follows (3.x `lib/modules/favorite`, docs/ui/compare/U.4c): the live,
/// replay and offline tabs where the title would be, the platform tabs
/// ("all" and every platform with follows) and the tag strip, and one grid
/// per platform (swipe between them).
///
/// Kept from 3.x (c1): tag order, the start check, "view offline", pull to
/// refresh and refresh on selecting follows again, the desktop pages. Both
/// tab rows show their numbers (c4); from [favoriteOneRowWidth] the
/// platform tabs sit in the app bar right of the status tabs (c3); offline
/// follows are compact rows (c5); the grid follows popular's (c6); "all"
/// cards show their platform (c10).
///
/// Routes: `RoutePath.kFavorite`; also the first home tab.
class FavoritePage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends ConsumerState<FavoritePage> with TickerProviderStateMixin {
  late final FavoriteController _controller = ref.read(favoriteControllerProvider);
  late final TabController _status = TabController(
    length: FollowGroup.values.length,
    initialIndex: _controller.group.index,
    vsync: this,
    animationDuration: pureLiveTabTransitionDuration,
  );
  TabController? _platformTabs;
  List<String> _platforms = const [];

  @override
  void initState() {
    super.initState();
    _status.addListener(_statusChanged);
    _controller
      ..requestedGroup.addListener(_showRequested)
      ..addListener(_changed);
    _syncPlatforms();
  }

  @override
  void dispose() {
    _controller
      ..requestedGroup.removeListener(_showRequested)
      ..removeListener(_changed);
    _status
      ..removeListener(_statusChanged)
      ..dispose();
    _platformTabs
      ?..removeListener(_platformChanged)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(_syncPlatforms);
  }

  /// One platform tab per platform with follows, keeping the platform shown
  /// by id (3.x `_FavoriteSiteTabs`); a platform that lost its last follow
  /// falls back to "all".
  void _syncPlatforms() {
    final platforms = _controller.rooms.isEmpty ? const <String>[] : _controller.platforms;
    if (listEquals(platforms, _platforms) && (_platformTabs != null || platforms.isEmpty)) return;
    final old = _platformTabs;
    _platforms = platforms;
    _platformTabs = null;
    if (old != null) {
      old.removeListener(_platformChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (platforms.isEmpty) return;
    final index = platforms.indexOf(_controller.platform);
    _platformTabs = TabController(
      length: platforms.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    )..addListener(_platformChanged);
    if (index < 0) WidgetsBinding.instance.addPostFrameCallback((_) => _platformChanged());
  }

  void _platformChanged() {
    final tabs = _platformTabs;
    if (!mounted || tabs == null || tabs.indexIsChanging) return;
    _controller.selectPlatform(_platforms[tabs.index]);
  }

  void _statusChanged() {
    if (_status.indexIsChanging) return;
    _controller.selectGroup(FollowGroup.values[_status.index]);
  }

  void _showRequested() {
    final group = _controller.requestedGroup.value;
    if (group == null) return;
    _controller.requestedGroup.value = null;
    _status.animateTo(group.index);
  }

  Future<void> _refresh() async {
    await _controller.refreshVisible();
    final failed = _controller.lastFailed;
    if (failed > 0) AppNavigator.toast(i18n('favorite_refresh_failed', args: {'count': '$failed'}));
  }

  Widget _statusTabs({required bool oneRow}) {
    final counts = groupCounts(_controller.rooms, _controller.platform);
    return TabBar(
      key: const ValueKey('favorite-status-tabs'),
      controller: _status,
      isScrollable: oneRow,
      tabAlignment: oneRow ? TabAlignment.start : TabAlignment.fill,
      labelPadding: oneRow ? const EdgeInsets.symmetric(horizontal: 12) : _statusTabPadding,
      dividerHeight: 0,
      physics: const PureLiveBoundedScrollPhysics(),
      tabs: [
        for (final group in FollowGroup.values)
          _CountTab(label: i18n(_groupTitleKeys[group]!), count: _controller.loaded ? counts[group]! : null),
      ],
    );
  }

  Widget _platformTabBar() {
    final sites = ref.read(sitesProvider);
    final group = _controller.group;
    int countOf(String id) => [
      for (final room in _controller.rooms)
        if (groupOf(room) == group && onPlatform(room, id)) room,
    ].length;
    return ScrollableTabBar(
      key: const ValueKey('favorite-platform-tabs'),
      controller: _platformTabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerHeight: 0,
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      physics: const PureLiveBoundedScrollPhysics(),
      tabs: [
        for (final id in _platforms)
          _CountTab(
            label: id == allPlatforms ? i18n('site_all') : platformName(id, fallback: sites.maybeOf(id)?.name),
            count: countOf(id),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final phoneTab = showsHomeBarButtons(context, inHome: widget.route.inHome);
      final oneRow = constraints.maxWidth >= favoriteOneRowWidth;
      final hasPlatforms = _platformTabs != null;
      final Widget title;
      if (oneRow && hasPlatforms) {
        title = Row(
          children: [
            _statusTabs(oneRow: true),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: _platformTabBar()),
          ],
        );
      } else {
        title = _statusTabs(oneRow: oneRow);
      }
      return Scaffold(
        appBar: AppBar(
          centerTitle: !oneRow,
          automaticallyImplyLeading: !widget.route.inHome,
          leading: phoneTab ? const MenuButton() : null,
          actions: phoneTab ? const [CommonAppBarActions()] : null,
          // The three tabs need the width more than the gaps around them.
          titleSpacing: phoneTab ? 4 : (oneRow ? 8 : null),
          title: title,
          bottom: hasPlatforms && !oneRow
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kTextTabBarHeight),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _platformTabBar()),
                )
              : null,
        ),
        body: _body(context),
      );
    },
  );

  Widget _body(BuildContext context) {
    final controller = _controller;
    final tabs = _platformTabs;
    final Widget content;
    if (!controller.loaded) {
      content = RoomGridSkeleton(
        key: const ValueKey('favorite-skeleton'),
        dense: ref.read(storeProvider).settings.get(Settings.enableDenseFavorites),
      );
    } else if (controller.rooms.isEmpty || tabs == null) {
      content = AppStatusView(
        type: AppStatusType.empty,
        icon: AppIcons.emptyFollows,
        title: i18n('empty_favorite_title'),
        subtitle: i18n('empty_favorite_subtitle'),
        buttonText: i18n('search_live'),
        buttonIcon: AppIcons.search,
        onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch)),
      );
    } else {
      content = Column(
        children: [
          _TagStrip(controller: controller),
          Expanded(
            child: TabBarView(
              controller: tabs,
              physics: const PureLiveBoundedScrollPhysics(),
              children: [
                for (final id in _platforms)
                  _FollowGrid(
                    key: ValueKey('favorite-grid-$id'),
                    controller: controller,
                    platform: id,
                    onRefresh: _refresh,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<double?>(
            valueListenable: controller.progress,
            builder: (context, value, _) => value == null
                ? const SizedBox.shrink()
                : LinearProgressIndicator(
                    key: const ValueKey('favorite-refresh-progress'),
                    value: value,
                    minHeight: 2.5,
                    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                  ),
          ),
        ),
      ],
    );
  }
}

const Map<FollowGroup, String> _groupTitleKeys = {
  FollowGroup.live: 'online_room_title',
  FollowGroup.replay: 'recording_room_title',
  FollowGroup.offline: 'offline_room_title',
};

const Map<FollowGroup, String> _emptyTitleKeys = {
  FollowGroup.live: 'favorite_empty_online_title',
  FollowGroup.replay: 'favorite_empty_recording_title',
  FollowGroup.offline: 'favorite_empty_offline_title',
};

/// Horizontal padding of a status tab: the three tabs share the app bar's
/// title between the menu button and the actions, and the default 16 on
/// each side left a phone's label too little room (M13.16).
const EdgeInsets _statusTabPadding = EdgeInsets.symmetric(horizontal: 4);

/// A tab with its number after the label (U.4c c4): 12 points, tabular
/// figures, in the tab's colour. The label is never cut: on a very narrow
/// bar the whole tab shrinks instead.
class _CountTab extends StatelessWidget {
  const new({required this.label, required this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, softWrap: false),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                key: ValueKey('favorite-status-count-$label'),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "All" and the tags the shown follows have (3.x `FavoriteTagStrip`, its
/// look kept; U.4c c2: the row is 48 high instead of 60); hidden when there
/// are none.
class _TagStrip extends StatelessWidget {
  const new({required this.controller});

  final FavoriteController controller;

  @override
  Widget build(BuildContext context) {
    final tags = controller.visibleTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String id, String label) {
      final selected = controller.tagId == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: ValueKey('favorite-tag-${id.isEmpty ? 'all' : id}'),
          showCheckmark: false,
          label: Text(label, maxLines: 1),
          labelStyle: context.textStyles.t12.copyWith(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
          selected: selected,
          selectedColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) => controller.selectTag(id),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('favorite-tag-strip'),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const PureLiveBoundedScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [chip(allTags, i18n('recorder_tab_all')), for (final tag in tags) chip(tag.id, tag.name)],
      ),
    );
  }
}

/// The follows of one platform in the shown tab (3.x `RoomGridView`): cards
/// for live and replay follows, rows for offline ones; on desktops numbered
/// pages with ← → and the page bar's refresh (3.x), elsewhere pull to
/// refresh.
class _FollowGrid extends ConsumerStatefulWidget {
  const new({required this.controller, required this.platform, required this.onRefresh, super.key});

  final FavoriteController controller;
  final String platform;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_FollowGrid> createState() => _FollowGridState();
}

class _FollowGridState extends ConsumerState<_FollowGrid> {
  final ScrollController _scroll = createPureLiveScrollController();
  int _page = 1;
  int? _pageSize;

  FavoriteController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final dense = watchSetting(ref, Settings.enableDenseFavorites);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final policy = watchAudiencePolicy(ref);
    final showJumps = watchSetting(ref, Settings.pageShowScrollTop);
    final showSizes = watchSetting(ref, Settings.pageShowSizeSelector);
    final showGoto = watchSetting(ref, Settings.pageShowGotoButton);
    final store = ref.read(storeProvider);
    final group = _controller.group;
    final all = _controller.roomsFor(group, widget.platform);
    final now = DateTime.now();
    final windowWidth = MediaQuery.sizeOf(context).width;
    final desktop = usesDesktopPages(windowWidth);
    final sizes = pageSizesOf(store.settings, windowWidth);
    final pageSize = _pageSize ?? sizes.size;
    final lastPage = all.isEmpty ? 1 : (all.length / pageSize).ceil();
    final page = _page.clamp(1, lastPage);
    final rooms = desktop ? all.sublist((page - 1) * pageSize, (page * pageSize).clamp(0, all.length)) : all;
    final mixed = widget.platform == allPlatforms;

    return LayoutBuilder(
      builder: (context, constraints) {
        const physics = PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics());
        final Widget scrollable;
        if (rooms.isEmpty) {
          scrollable = CustomScrollView(
            key: PageStorageKey('favorite-empty-${widget.platform}'),
            physics: physics,
            slivers: [SliverFillRemaining(hasScrollBody: false, child: _emptyState(desktop: desktop))],
          );
        } else if (group == FollowGroup.offline) {
          final columns = GridColumns.count(
            width: constraints.maxWidth,
            minItemWidth: favoriteRowMinWidth,
            spacing: spacing,
            min: 1,
          );
          final rowHeight = RoomRow.height - 16 + MediaQuery.textScalerOf(context).scale(15 + 13) * 1.4;
          scrollable = GridView.builder(
            key: PageStorageKey('favorite-rows-${widget.platform}'),
            controller: _scroll,
            padding: const EdgeInsets.all(roomGridPadding),
            physics: physics,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: mainSpacing,
              mainAxisExtent: rowHeight < RoomRow.height ? RoomRow.height : rowHeight,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final pending = _pendingLabel(room);
              final mark = roomMark(room);
              final note = pending ?? mark;
              return RoomRow(
                key: ValueKey(room.identityKey),
                data: policy.cardOf(room),
                trailing: note == null ? null : _RowNote(text: note),
                onTap: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room, playlist: all)),
                onLongPress: () => unawaited(showRoomMenu(context, store: store, room: room)),
              );
            },
          );
        } else {
          final geometry = RoomGridGeometry.of(
            context,
            width: constraints.maxWidth,
            spacing: spacing,
            appearance: appearance,
            fontSizes: fontSizes,
            dense: dense,
            minItemWidth: dense ? null : favoriteLargeCardMinWidth,
            minColumns: dense ? 2 : 1,
          );
          scrollable = GridView.builder(
            key: PageStorageKey('favorite-grid-${widget.platform}-${group.name}'),
            controller: _scroll,
            padding: const EdgeInsets.all(roomGridPadding),
            physics: physics,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            gridDelegate: geometry.delegate(spacing: spacing, mainSpacing: mainSpacing),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final pending = _pendingLabel(room);
              return RoomGridCard(
                key: ValueKey(room.identityKey),
                room: room,
                dense: dense,
                mixedPlatforms: mixed,
                statusPending: pending != null,
                statusPendingLabel: pending,
                now: now,
                // The group's rooms go along (U.2b2).
                onOpen: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room, playlist: all)),
              );
            },
          );
        }
        final list = Stack(
          children: [
            Positioned.fill(child: scrollable),
            if (showJumps && rooms.isNotEmpty)
              Positioned(
                right: 16,
                bottom: 16,
                child: JumpButtons(controller: _scroll, heroTag: 'favorite-${widget.platform}'),
              ),
          ],
        );
        if (!desktop) return RefreshIndicator(onRefresh: widget.onRefresh, child: list);
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              if (page > 1) _goTo(page - 1);
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (page < lastPage) _goTo(page + 1);
            },
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                Expanded(child: list),
                ValueListenableBuilder<double?>(
                  valueListenable: _controller.progress,
                  builder: (context, progress, _) => PaginationBar(
                    page: page,
                    lastPage: lastPage,
                    canNext: page < lastPage,
                    busy: progress != null,
                    pageSize: pageSize,
                    pageSizes: showSizes ? sizes.options : null,
                    showGoto: showGoto,
                    onPage: _goTo,
                    onPageSize: (size) {
                      final first = (page - 1) * pageSize;
                      setState(() {
                        _pageSize = size;
                        _page = first ~/ size + 1;
                      });
                    },
                    onRefresh: () => unawaited(widget.onRefresh()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Verifying" during the start check, "status pending" after a failed
  /// check; null otherwise (a retired platform is never pending).
  String? _pendingLabel(LiveRoom room) {
    if (SiteIds.isRetired(room.platform)) return null;
    if (_controller.verifying) return i18n('favorite_status_verifying');
    if (room.isLiveStatusPending) return i18n('favorite_status_unknown');
    return null;
  }

  Widget _emptyState({required bool desktop}) {
    final counts = groupCounts(_controller.rooms, widget.platform);
    final total = counts.values.fold(0, (sum, count) => sum + count);
    final group = _controller.group;
    final canShowOffline = group != FollowGroup.offline && counts[FollowGroup.offline]! > 0;
    final String subtitle;
    if (group == FollowGroup.live && total > 0 && counts[FollowGroup.live] == 0) {
      subtitle = i18n('favorite_empty_none_live', args: {'count': '$total'});
    } else {
      subtitle = i18n(desktop ? 'favorite_empty_hint_desktop' : 'favorite_empty_hint_phone');
    }
    return AppStatusView(
      type: AppStatusType.empty,
      icon: AppIcons.emptyFollows,
      title: i18n(_emptyTitleKeys[group]!),
      subtitle: subtitle,
      buttonText: canShowOffline ? i18n('favorite_show_offline') : i18n('refresh'),
      buttonIcon: canShowOffline ? AppIcons.showHidden : null,
      onButtonPressed: canShowOffline
          ? () => _controller.showGroup(FollowGroup.offline)
          : () => unawaited(widget.onRefresh()),
      // U.1c C1: a second action is a text button.
      secondaryButtonText: canShowOffline ? i18n('refresh') : null,
      onSecondaryButtonPressed: canShowOffline ? () => unawaited(widget.onRefresh()) : null,
    );
  }
}

/// A short note at the end of an offline row: the pending check or the
/// room's mark (carousel, banned, retired platform …).
class _RowNote extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}
