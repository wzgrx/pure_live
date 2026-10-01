import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/area_rooms/follow_area_button.dart';
import 'package:pure_live/pages/area_rooms/room_cards.dart';
import 'package:pure_live/pages/area_rooms/room_feed.dart';
import 'package:pure_live/pages/areas/areas_common.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// The rooms of an area (3.x `lib/modules/area_rooms`).
///
/// Route: `RoutePath.kAreaRooms`; arguments `[LiveSite, LiveArea]` (3.x
/// crashed without them; here the page says the area is missing).
class AreaRoomsPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    if (route.arguments case [final LiveSite site, final LiveArea area]) {
      return AreaRoomsView(site: site, area: area);
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n('areas_title'))),
      body: AppStatusView(type: AppStatusType.error, title: i18n('area_rooms_missing_area')),
    );
  }
}

/// The rooms of [area] on [site]: a grid of room cards loading page after
/// page as the list ends, pull to refresh (and a refresh button for mouse
/// users), the directory's explanation where the platform has one, a "back
/// to top" button, and the button to follow the area.
class AreaRoomsView extends ConsumerStatefulWidget {
  /// Shows [area]'s rooms on [site].
  const new({required this.site, required this.area, this.loader, super.key});

  /// The platform.
  final LiveSite site;

  /// The area.
  final LiveArea area;

  /// Loads pages; null uses [areaRoomLoader] (tests pass their own).
  final RoomPageLoader? loader;

  @override
  ConsumerState<AreaRoomsView> createState() => _AreaRoomsViewState();
}

class _AreaRoomsViewState extends ConsumerState<AreaRoomsView> {
  late final AreaRoomFeed _feed;
  final ScrollController _scroll = createPureLiveScrollController();
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _feed = AreaRoomFeed(
      load: widget.loader ?? areaRoomLoader(widget.site, widget.area),
      area: widget.area,
      showUnplayable: ref.read(storeProvider).settings.get(Settings.showUnplayableInDiscover),
    )..addListener(_changed);
    _scroll.addListener(_scrolled);
    _feed.refresh().ignore();
  }

  @override
  void dispose() {
    _feed
      ..removeListener(_changed)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    final show = _scroll.hasClients && _scroll.offset > 400;
    if (show != _showTop) setState(() => _showTop = show);
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) _feed.loadMore().ignore();
  }

  Future<void> _toTop() async {
    if (!_scroll.hasClients) return;
    final distance = _scroll.offset;
    await _scroll.animateTo(
      0,
      duration: Duration(milliseconds: (180 + distance / 8).round().clamp(220, 520)),
      curve: Curves.easeOutCubic,
    );
  }

  String? get _notice {
    final site = widget.site;
    return site is LiveDirectoryNotice ? i18nOr((site as LiveDirectoryNotice).directoryNoticeKey, '') : null;
  }

  Widget _status() {
    final error = _feed.error;
    if (!_feed.hasLoaded || (_feed.isRefreshing && error == null)) {
      return AppStatusView(type: AppStatusType.loading, title: i18n('refresh_loading'));
    }
    if (error != null) {
      final login = isLoginError(error);
      return AppStatusView(
        type: AppStatusType.error,
        icon: login ? Icons.account_circle_outlined : Icons.wifi_off_rounded,
        title: i18n(login ? 'login_required_title' : 'network_error_title'),
        subtitle: describeLoadError(error),
        buttonText: i18n(login ? 'go_to_login' : 'retry'),
        onButtonPressed: login
            ? () => AppNavigator.toNamed<void>(RoutePath.kSettingsAccount).ignore()
            : () => _feed.refresh().ignore(),
      );
    }
    return EmptyView(
      icon: Icons.live_tv_rounded,
      title: i18n('empty_areas_room_title'),
      subtitle: _feed.hiddenCount > 0
          ? i18n('area_rooms_hidden_unplayable', args: {'count': '${_feed.hiddenCount}'})
          : i18n('empty_areas_room_subtitle'),
      buttonText: _feed.hiddenCount > 0 ? i18n('area_rooms_show_hidden') : i18n('refresh'),
      onButtonPressed: _feed.hiddenCount > 0 ? () => _feed.showUnplayable = true : () => _feed.refresh().ignore(),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    if (_feed.error != null && !_feed.refreshFailed) {
      return Center(
        child: TextButton.icon(
          key: const ValueKey('area-rooms-retry-more'),
          icon: const Icon(Icons.refresh_rounded),
          label: Text('${describeLoadError(_feed.error!)} · ${i18n('retry')}'),
          onPressed: () => _feed.retry().ignore(),
        ),
      );
    }
    if (_feed.isLoadingMore) {
      return const Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_feed.hasMore) {
      // Reached without a scroll (a short page): load on sight.
      if (_feed.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _feed.loadMore().ignore();
        });
      }
      return Center(
        child: TextButton(onPressed: () => _feed.loadMore().ignore(), child: Text(i18n('area_rooms_load_more'))),
      );
    }
    return Center(
      child: Text(i18n('area_rooms_no_more'), style: context.textStyles.t12.copyWith(color: theme.hintColor)),
    );
  }

  Widget _grid(BuildContext context, List<LiveRoom> rooms) {
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final spacing = gridSpacing(ref);
    final preferReal = watchSetting(ref, Settings.preferRealOnlineCounts);
    final realPlatforms = watchSetting(ref, Settings.realOnlinePlatforms);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
        final itemWidth = (width - 12 - spacing.cross * (columns - 1)) / columns;
        return CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing.cross,
                  mainAxisSpacing: spacing.main,
                  mainAxisExtent: RoomCardLayoutMetrics.gridMainAxisExtent(
                    itemWidth: itemWidth,
                    appearance: appearance,
                    dense: true,
                    textScaler: MediaQuery.textScalerOf(context),
                    fontSizes: fontSizes,
                  ),
                ),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return RoomCard(
                    key: ValueKey(room.identityKey),
                    data: roomCardData(room, preferRealOnline: preferReal, realOnlinePlatforms: realPlatforms),
                    appearance: appearance,
                    dense: true,
                    onTap: () => AppNavigator.toLiveRoomDetail(liveRoom: room).ignore(),
                    onLongPress: () => showRoomMenu(context, ref, room).ignore(),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 96),
              sliver: SliverToBoxAdapter(child: SizedBox(height: 40, child: _footer(context))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = _feed.rooms;
    final notice = _notice;
    final hidden = _feed.hiddenCount;
    final wide = MediaQuery.sizeOf(context).width > homeTabletBreakpoint;
    return Scaffold(
      appBar: AppBar(
        title: Text(areaDisplayName(widget.area)),
        actions: [
          IconButton(
            key: const ValueKey('area-rooms-refresh'),
            tooltip: i18n('refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _feed.isRefreshing ? null : () => _feed.refresh().ignore(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (notice != null && notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(notice, style: theme.textTheme.bodySmall),
            ),
          if (rooms.isNotEmpty && hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined, size: 16, color: theme.hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      i18n('area_rooms_hidden_unplayable', args: {'count': '$hidden'}),
                      style: context.textStyles.t12.copyWith(color: theme.hintColor),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('area-rooms-show-hidden'),
                    onPressed: () => _feed.showUnplayable = true,
                    child: Text(i18n('area_rooms_show_hidden')),
                  ),
                ],
              ),
            ),
          if (_feed.isRefreshing && rooms.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          if (rooms.isNotEmpty && _feed.refreshFailed && _feed.error != null)
            Material(
              key: const ValueKey('area-rooms-refresh-error'),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.info_outline_rounded, color: theme.colorScheme.onErrorContainer),
                title: Text(
                  describeLoadError(_feed.error!),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                trailing: TextButton(onPressed: () => _feed.refresh().ignore(), child: Text(i18n('retry'))),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _feed.refresh,
              child: rooms.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Center(child: _status()),
                        ),
                      ),
                    )
                  : _grid(context, rooms),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showTop && watchSetting(ref, Settings.pageShowScrollTop)
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FloatingActionButton.small(
                      key: const ValueKey('area-rooms-top'),
                      heroTag: null,
                      tooltip: i18n('area_rooms_back_to_top'),
                      onPressed: () => _toTop().ignore(),
                      child: const Icon(Icons.vertical_align_top_rounded),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: wide
                  ? 24
                  : (MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 12),
            ),
            child: FollowAreaButton(area: widget.area),
          ),
        ],
      ),
    );
  }
}
