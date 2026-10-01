import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/favorite/favorite_controller.dart';
import 'package:pure_live/pages/favorite/favorite_rules.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Follows (3.x `lib/modules/favorite`): live, replay and offline tabs in
/// the app bar, a platform rail with the platforms that have follows, a
/// tag strip, and the room grid of each platform (swipe between them).
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

class _FavoritePageState extends ConsumerState<FavoritePage> with SingleTickerProviderStateMixin {
  late final FavoriteController _controller = ref.read(favoriteControllerProvider);
  late final TabController _status = TabController(
    length: FollowGroup.values.length,
    initialIndex: _controller.group.index,
    vsync: this,
    animationDuration: pureLiveTabTransitionDuration,
  );

  @override
  void initState() {
    super.initState();
    _status.addListener(_statusChanged);
    _controller.requestedGroup.addListener(_showRequested);
  }

  @override
  void dispose() {
    _controller.requestedGroup.removeListener(_showRequested);
    _status
      ..removeListener(_statusChanged)
      ..dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final phoneTab = widget.route.inHome && MediaQuery.sizeOf(context).width <= homeTabletBreakpoint;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        actions: phoneTab ? const [CommonAppBarActions()] : null,
        title: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final counts = groupCounts(_controller.rooms, _controller.platform);
            return TabBar(
              key: const ValueKey('favorite-status-tabs'),
              controller: _status,
              tabAlignment: TabAlignment.fill,
              dividerHeight: 0,
              physics: const PureLiveBoundedScrollPhysics(),
              tabs: [
                for (final group in FollowGroup.values)
                  _StatusTab(label: i18n(_groupTitleKeys[group]!), count: _controller.loaded ? counts[group]! : 0),
              ],
            );
          },
        ),
      ),
      body: ListenableBuilder(listenable: _controller, builder: (context, _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final controller = _controller;
    final Widget content;
    if (!controller.loaded) {
      content = const _Skeleton();
    } else if (controller.rooms.isEmpty) {
      content = AppStatusView(
        type: AppStatusType.empty,
        icon: Remix.heart_3_fill,
        title: i18n('empty_favorite_title'),
        subtitle: i18n('empty_favorite_subtitle'),
        buttonText: i18n('search_live'),
        buttonIcon: Icons.search_rounded,
        onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch)),
      );
    } else {
      final platforms = controller.platforms;
      content = _PlatformTabs(key: ValueKey(platforms.join('|')), controller: controller, platforms: platforms);
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
                    backgroundColor: Colors.transparent,
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

/// A status tab with its number of follows.
class _StatusTab extends StatelessWidget {
  const new({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: context.textStyles.t11.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ],
    ),
  );
}

/// The platform rail, the refresh button, the tag strip and one grid per
/// platform; rebuilt with a new key when the platforms change, keeping the
/// shown platform by id (3.x `_FavoriteSiteTabs`).
class _PlatformTabs extends ConsumerStatefulWidget {
  const new({required this.controller, required this.platforms, super.key});

  final FavoriteController controller;
  final List<String> platforms;

  @override
  ConsumerState<_PlatformTabs> createState() => _PlatformTabsState();
}

class _PlatformTabsState extends ConsumerState<_PlatformTabs> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final index = widget.platforms.indexOf(widget.controller.platform);
    _tabs = TabController(
      length: widget.platforms.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    )..addListener(_changed);
    // A platform that lost its last follow falls back to "all".
    if (index < 0) WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted || _tabs.indexIsChanging) return;
    widget.controller.selectPlatform(widget.platforms[_tabs.index]);
  }

  Future<void> _refresh() async {
    await widget.controller.refreshVisible();
    final failed = widget.controller.lastFailed;
    if (failed > 0) AppNavigator.toast(i18n('favorite_refresh_failed', args: {'count': '$failed'}));
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final controller = widget.controller;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ScrollableTabBar(
                key: const ValueKey('favorite-platform-tabs'),
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                physics: const PureLiveBoundedScrollPhysics(),
                tabs: [
                  for (final id in widget.platforms) Tab(text: platformName(id, fallback: sites.maybeOf(id)?.name)),
                ],
              ),
            ),
            _RefreshButton(controller: controller, onPressed: () => unawaited(_refresh())),
          ],
        ),
        _TagStrip(controller: controller),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const PureLiveBoundedScrollPhysics(),
            children: [
              for (final id in widget.platforms)
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
}

/// Refreshes the shown platform and tag; shows the progress while it runs
/// (3.x had only the hidden "select follows again" on desktop).
class _RefreshButton extends StatelessWidget {
  const new({required this.controller, required this.onPressed});

  final FavoriteController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
    valueListenable: controller.progress,
    builder: (context, value, _) => IconButton(
      key: const ValueKey('favorite-refresh'),
      tooltip: i18n('favorite_refresh'),
      onPressed: value == null ? onPressed : null,
      icon: value == null
          ? const Icon(Remix.refresh_line)
          : SizedBox.square(dimension: 18, child: CircularProgressIndicator(value: value, strokeWidth: 2)),
    ),
  );
}

/// "All" and the tags the shown follows have (3.x `FavoriteTagStrip`);
/// hidden when there are none.
class _TagStrip extends StatelessWidget {
  const new({required this.controller});

  final FavoriteController controller;

  @override
  Widget build(BuildContext context) {
    final tags = controller.visibleTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
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
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
          ),
          selected: selected,
          selectedColor: theme.colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) => controller.selectTag(id),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('favorite-tag-strip'),
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const PureLiveBoundedScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [chip(allTags, i18n('recorder_tab_all')), for (final tag in tags) chip(tag.id, tag.name)],
      ),
    );
  }
}

/// The follows of one platform in the shown tab (3.x `RoomGridView`).
class _FollowGrid extends ConsumerWidget {
  const new({required this.controller, required this.platform, required this.onRefresh, super.key});

  final FavoriteController controller;
  final String platform;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dense = watchSetting(ref, Settings.enableDenseFavorites);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainAxisSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final policy = watchAudiencePolicy(ref);
    final showScrollTop = watchSetting(ref, Settings.pageShowScrollTop);
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final store = ref.read(storeProvider);
    final rooms = controller.roomsFor(controller.group, platform);
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final pull = Platform.isAndroid || Platform.isIOS || width <= homeTabletBreakpoint;
        const physics = PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics());
        final Widget scrollable;
        if (rooms.isEmpty) {
          scrollable = CustomScrollView(
            key: PageStorageKey('favorite-empty-$platform'),
            physics: physics,
            slivers: [SliverFillRemaining(hasScrollBody: false, child: _emptyState())],
          );
        } else {
          var columns = width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
          if (dense) columns = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
          final itemWidth = (width - 24 - spacing * (columns - 1)) / columns;
          scrollable = GridView.builder(
            key: PageStorageKey('favorite-grid-$platform-${controller.group.name}'),
            primary: false,
            padding: const EdgeInsets.all(12),
            physics: physics,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: mainAxisSpacing,
              mainAxisExtent: RoomCardLayoutMetrics.gridMainAxisExtent(
                itemWidth: itemWidth,
                appearance: appearance,
                dense: dense,
                textScaler: MediaQuery.textScalerOf(context),
                fontSizes: fontSizes,
              ),
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final retired = SiteIds.isRetired(room.platform);
              return RoomCard(
                key: ValueKey(room.identityKey),
                data: policy.cardOf(room, now: now),
                appearance: appearance,
                dense: dense,
                statusPending: !retired && (controller.verifying || room.isLiveStatusPending),
                statusPendingLabel: controller.verifying
                    ? i18n('favorite_status_verifying')
                    : i18n('favorite_status_unknown'),
                onTap: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room)),
                onLongPress: () => unawaited(showRoomMenu(context, store: store, room: room)),
              );
            },
          );
        }
        final body = pull ? RefreshIndicator(onRefresh: onRefresh, child: scrollable) : scrollable;
        return showScrollTop && rooms.isNotEmpty ? _ScrollTopScope(child: body) : body;
      },
    );
  }

  Widget _emptyState() {
    final counts = groupCounts(controller.rooms, platform);
    final total = counts.values.fold(0, (sum, count) => sum + count);
    final group = controller.group;
    final canShowOffline = group != FollowGroup.offline && counts[FollowGroup.offline]! > 0;
    return AppStatusView(
      type: AppStatusType.empty,
      icon: Remix.heart_3_fill,
      title: i18n(_emptyTitleKeys[group]!),
      subtitle: total == 0
          ? i18n('favorite_empty_platform_subtitle')
          : i18n('favorite_empty_filter_subtitle', args: {'count': '$total'}),
      buttonText: canShowOffline ? i18n('favorite_show_offline') : i18n('refresh'),
      buttonIcon: canShowOffline ? Icons.visibility_rounded : null,
      onButtonPressed: canShowOffline ? () => controller.showGroup(FollowGroup.offline) : () => unawaited(onRefresh()),
    );
  }
}

/// A "back to top" button over a grid once it is scrolled down (3.x
/// `showScrollToTopBtn`).
class _ScrollTopScope extends StatefulWidget {
  const new({required this.child});

  final Widget child;

  @override
  State<_ScrollTopScope> createState() => _ScrollTopScopeState();
}

class _ScrollTopScopeState extends State<_ScrollTopScope> {
  ScrollPosition? _position;
  bool _visible = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    final visible = notification.metrics.pixels > 600;
    if (notification.context case final context?) _position = Scrollable.maybeOf(context)?.position;
    if (visible != _visible) setState(() => _visible = visible);
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: _onScroll,
    child: Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          right: 16,
          bottom: 20,
          child: AnimatedScale(
            scale: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: i18n('favorite_scroll_top'),
              onPressed: () => unawaited(
                _position?.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
              ),
              child: const Icon(Remix.arrow_up_line),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Placeholder cards while the follows are read for the first time.
class _Skeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 960 ? 3 : (constraints.maxWidth > 640 ? 2 : 1);
        return GridView.builder(
          key: const ValueKey('favorite-skeleton'),
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.25,
          ),
          itemCount: columns * 3,
          itemBuilder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
          ),
        );
      },
    );
  }
}
