import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/popular/pagination_bar.dart';
import 'package:pure_live/pages/popular/popular_catalog.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Rooms of the first phone load and of each "load more" (3.x's phone
/// page size).
const int phonePageSize = 20;

/// Whether a window of [width] uses desktop pages (3.x: wider than 680 and
/// not a phone OS); otherwise the list grows at the end.
bool usesDesktopPages(double width) => width > 680 && !isPhoneDevice;

/// Columns of the room grid (3.x `PopularGridView`).
int popularColumns(double width) => width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));

/// The note of a platform whose directory is not the whole site (the
/// adapter's `LiveDirectoryNotice`), rewritten for the popular page.
String? popularNoticeOf(LiveSite site) {
  if (site is! LiveDirectoryNotice) return null;
  final key = 'popular_scope_${site.id}';
  return i18nExists(key) ? i18n(key) : i18n((site as LiveDirectoryNotice).directoryNoticeKey);
}

/// One platform's recommendations (3.x `PopularGridView` over
/// `BasePageView`): skeleton cards while the first rooms load, the error
/// or empty state, then the grid; on phones pull to refresh and more rooms
/// at the end, on desktops numbered pages.
class PopularPlatformView extends ConsumerStatefulWidget {
  /// Creates the view of [platform].
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  ConsumerState<PopularPlatformView> createState() => _PopularPlatformViewState();
}

class _PopularPlatformViewState extends ConsumerState<PopularPlatformView> {
  final ScrollController _scroll = createPureLiveScrollController();
  final ValueNotifier<(bool, bool)> _jumps = ValueNotifier((false, false));
  bool _noticeOpen = false;

  late final PopularCatalog _catalog = ref.read(popularCatalogProvider);
  late final RoomFeed _feed = _catalog.feedOf(widget.platform);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncJumps);
    _feed.addListener(_feedChanged);
  }

  @override
  void dispose() {
    _feed.removeListener(_feedChanged);
    _scroll.dispose();
    _jumps.dispose();
    super.dispose();
  }

  void _feedChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncJumps();
      _fillViewport();
    });
  }

  // 3.x: "to top" past 400 px, "to bottom" while more than 400 px remain.
  void _syncJumps() {
    if (!_scroll.hasClients) {
      _jumps.value = (false, false);
      return;
    }
    final position = _scroll.position;
    _jumps.value = (position.pixels > 400, position.maxScrollExtent - position.pixels > 400);
  }

  bool get _desktop => usesDesktopPages(MediaQuery.sizeOf(context).width);

  int get _pageSize {
    final sizes = pageSizesOf(ref.read(storeProvider).settings, MediaQuery.sizeOf(context).width);
    return _catalog.pageSize ?? sizes.size;
  }

  int get _firstCount => _desktop ? _pageSize : phonePageSize;

  Future<void> _refresh() => _feed.refresh(count: _firstCount);

  void _loadMore() {
    if (_desktop || !_feed.hasMore || _feed.busy || _feed.error != null) return;
    unawaited(_feed.ensure(_feed.rooms.length + phonePageSize));
  }

  // A list shorter than the screen cannot be scrolled to its end: ask for
  // more right away (3.x's footer needed a drag).
  void _fillViewport() {
    if (_desktop || !_scroll.hasClients || _feed.rooms.isEmpty) return;
    if (_scroll.position.maxScrollExtent <= 0) _loadMore();
  }

  void _toTopOrRefresh() {
    if (!_scroll.hasClients) return;
    if (_scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: Duration(milliseconds: (180 + _scroll.offset / 8).round().clamp(220, 520)),
        curve: Curves.easeOutCubic,
      );
    } else {
      unawaited(_refresh());
    }
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    final distance = (_scroll.position.maxScrollExtent - _scroll.offset).abs();
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: Duration(milliseconds: (180 + distance / 8).round().clamp(220, 520)),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToPage(int page) async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _feed.goToPage(page, size: _pageSize);
  }

  void _setPageSize(int size) {
    final old = _pageSize;
    if (size == old) return;
    // Keep the first room of the page in view (3.x).
    final first = (_feed.page - 1) * old;
    _catalog.pageSize = size;
    unawaited(_goToPage(first ~/ size + 1));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(storeProvider).settings;
    // Rebuild when the card settings change.
    watchSetting(ref, Settings.roomCardMobilePreset);
    watchSetting(ref, Settings.roomCardDesktopPreset);
    watchSetting(ref, Settings.roomCardMobileConfig);
    watchSetting(ref, Settings.roomCardDesktopConfig);
    final crossSpacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final showJumps = watchSetting(ref, Settings.pageShowScrollTop);
    final showSizes = watchSetting(ref, Settings.pageShowSizeSelector);
    final showGoto = watchSetting(ref, Settings.pageShowGotoButton);
    watchSetting(ref, Settings.pageDefaultSize);
    watchSetting(ref, Settings.pageSizeOptions);
    final appearance = cardAppearanceOf(settings);
    final policy = _catalog.policy;
    final site = ref.read(sitesProvider).of(widget.platform);
    final notice = popularNoticeOf(site);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final desktop = usesDesktopPages(MediaQuery.sizeOf(context).width);
        final columns = popularColumns(width);
        final sizes = pageSizesOf(settings, MediaQuery.sizeOf(context).width);
        final pageSize = _catalog.pageSize ?? sizes.size;
        final rooms = desktop ? _feed.pageRooms(_feed.page, pageSize) : _feed.rooms;
        final hasContent = _feed.rooms.isNotEmpty;

        Widget grid() => _RoomGrid(
          rooms: rooms,
          columns: columns,
          crossSpacing: crossSpacing,
          mainSpacing: mainSpacing,
          scroll: _scroll,
          cacheExtent: width > 680 ? 480 : 320,
          card: (room) => RoomCard(
            key: ValueKey(room.identityKey),
            data: policy.cardOf(room),
            appearance: appearance,
            dense: true,
            onTap: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room)),
            onLongPress: () => unawaited(showRoomMenu(context, store: ref.read(storeProvider), room: room)),
          ),
          footer: desktop ? _hiddenNote(context) : _phoneFooter(context),
        );

        final Widget body;
        if (!hasContent && (!_feed.loaded || (_feed.busy && _feed.error == null))) {
          body = _Skeleton(columns: columns, crossSpacing: crossSpacing, mainSpacing: mainSpacing);
        } else if (!hasContent && _feed.error != null) {
          body = _scrollableStatus(desktop, constraints, _errorStatus(_feed.error!));
        } else if (!hasContent) {
          body = _scrollableStatus(desktop, constraints, _emptyStatus(context));
        } else if (desktop) {
          body = CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                if (_feed.page > 1 && !_feed.busy) unawaited(_goToPage(_feed.page - 1));
              },
              const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                if (!_feed.busy && _canGoNext(pageSize)) unawaited(_goToPage(_feed.page + 1));
              },
            },
            child: Focus(
              autofocus: true,
              child: Column(
                children: [
                  Expanded(child: grid()),
                  PopularPaginationBar(
                    page: _feed.page,
                    lastPage: _feed.hasMore ? null : _feed.lastPage(pageSize),
                    canNext: _canGoNext(pageSize),
                    busy: _feed.busy,
                    pageSize: pageSize,
                    pageSizes: showSizes ? sizes.options : null,
                    showGoto: showGoto,
                    onPage: (page) => unawaited(_goToPage(page)),
                    onPageSize: _setPageSize,
                    onRefresh: () => unawaited(_refresh()),
                  ),
                ],
              ),
            ),
          );
        } else {
          body = RefreshIndicator(
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical && notification.metrics.extentAfter < 600) _loadMore();
                return false;
              },
              child: grid(),
            ),
          );
        }

        return Stack(
          children: [
            Column(
              children: [
                if (notice != null) _noticeBar(context, notice),
                if (hasContent) const MobileDataBanner(),
                if (_feed.errorOnRefresh && _feed.error != null && hasContent) _refreshErrorBanner(context),
                Expanded(child: body),
              ],
            ),
            if (hasContent && _feed.busy)
              const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2.5)),
            if (showJumps && hasContent) Positioned(right: 16, bottom: desktop ? 70 : 20, child: _jumpButtons(context)),
          ],
        );
      },
    );
  }

  bool _canGoNext(int pageSize) => _feed.rooms.length > _feed.page * pageSize || _feed.hasMore;

  Widget _noticeBar(BuildContext context, String notice) {
    final styles = context.textStyles;
    return InkWell(
      key: const ValueKey('popular-notice'),
      onTap: () => setState(() => _noticeOpen = !_noticeOpen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: Theme.of(context).hintColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                notice,
                style: styles.t12Muted,
                maxLines: _noticeOpen ? null : 1,
                overflow: _noticeOpen ? null : TextOverflow.ellipsis,
              ),
            ),
            Icon(_noticeOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _refreshErrorBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Semantics(
        liveRegion: true,
        child: MaterialBanner(
          key: const ValueKey('popular-refresh-error'),
          backgroundColor: colors.errorContainer,
          leading: Icon(Icons.info_outline_rounded, color: colors.onErrorContainer),
          content: Text(
            i18n('popular_refresh_failed', args: {'reason': describeLoadError(_feed.error)}),
            style: TextStyle(color: colors.onErrorContainer),
          ),
          actions: [
            TextButton(onPressed: _feed.clearError, child: Text(i18n('close'))),
            TextButton(onPressed: _feed.busy ? null : () => unawaited(_refresh()), child: Text(i18n('retry'))),
          ],
        ),
      ),
    );
  }

  Widget _errorStatus(Object error) {
    if (error is NeedsLogin) {
      return AppStatusView(
        type: AppStatusType.error,
        icon: Icons.account_circle_outlined,
        title: i18n('login_required_title'),
        subtitle: i18n('login_required_subtitle'),
        buttonText: i18n('go_to_login'),
        buttonIcon: Icons.login_rounded,
        onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsAccount)),
      );
    }
    return AppStatusView(
      type: AppStatusType.error,
      icon: Icons.wifi_off_rounded,
      title: i18n('network_error_title'),
      subtitle: describeLoadError(error),
      buttonText: i18n('retry'),
      onButtonPressed: () => unawaited(_refresh()),
    );
  }

  Widget _emptyStatus(BuildContext context) {
    final hidden = _feed.hiddenCount;
    return AppStatusView(
      type: AppStatusType.empty,
      icon: Icons.local_fire_department_rounded,
      title: i18n('empty_live_title'),
      subtitle: hidden > 0 ? i18n('popular_hidden_count', args: {'count': '$hidden'}) : i18n('empty_live_subtitle'),
      buttonText: hidden > 0 ? i18n('popular_show_hidden') : i18n('refresh'),
      buttonIcon: hidden > 0 ? Icons.visibility_rounded : null,
      onButtonPressed: hidden > 0 ? _showHidden : () => unawaited(_refresh()),
    );
  }

  void _showHidden() => unawaited(ref.read(storeProvider).settings.set(Settings.showUnplayableInDiscover, true));

  Widget _scrollableStatus(bool desktop, BoxConstraints constraints, Widget status) {
    final view = SingleChildScrollView(
      key: const ValueKey('popular-status'),
      physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight * (desktop ? 1 : 0.8)),
        child: Center(child: status),
      ),
    );
    return desktop ? view : RefreshIndicator(onRefresh: _refresh, child: view);
  }

  Widget? _hiddenNote(BuildContext context) {
    final hidden = _feed.hiddenCount;
    if (hidden == 0) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              i18n('popular_hidden_count', args: {'count': '$hidden'}),
              style: context.textStyles.t12Muted,
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(onPressed: _showHidden, child: Text(i18n('popular_show_hidden'))),
        ],
      ),
    );
  }

  Widget _phoneFooter(BuildContext context) {
    final styles = context.textStyles;
    final Widget state;
    if (_feed.error != null && !_feed.errorOnRefresh) {
      state = TextButton.icon(
        key: const ValueKey('popular-load-more-retry'),
        onPressed: () => unawaited(_feed.retry(count: _feed.rooms.length + phonePageSize)),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(i18n('popular_load_more_failed')),
      );
    } else if (_feed.busy) {
      state = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_feed.hasMore) {
      state = TextButton(onPressed: _loadMore, child: Text(i18n('popular_load_more')));
    } else {
      state = Text(i18n('refresh_no_more_data'), style: styles.t12Muted);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [state, ?_hiddenNote(context)]),
    );
  }

  Widget _jumpButtons(BuildContext context) => ValueListenableBuilder(
    valueListenable: _jumps,
    builder: (context, jumps, _) {
      final (top, bottom) = jumps;
      final background = Theme.of(context).cardColor;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: top ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton(
                heroTag: 'popular_to_top_${widget.platform}',
                mini: true,
                elevation: 3,
                tooltip: i18n('popular_to_top'),
                backgroundColor: background,
                onPressed: _toTopOrRefresh,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ),
          AnimatedScale(
            scale: bottom ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton(
              heroTag: 'popular_to_bottom_${widget.platform}',
              mini: true,
              elevation: 3,
              tooltip: i18n('popular_to_bottom'),
              backgroundColor: background,
              onPressed: _toBottom,
              child: const Icon(Icons.arrow_downward_rounded),
            ),
          ),
        ],
      );
    },
  );
}

/// Rows of cards with their natural height (3.x: a fixed caption height
/// clipped scaled text).
class _RoomGrid extends StatelessWidget {
  const new({
    required this.rooms,
    required this.columns,
    required this.crossSpacing,
    required this.mainSpacing,
    required this.scroll,
    required this.cacheExtent,
    required this.card,
    required this.footer,
  });

  final List<LiveRoom> rooms;
  final int columns;
  final double crossSpacing;
  final double mainSpacing;
  final ScrollController scroll;
  final double cacheExtent;
  final Widget Function(LiveRoom room) card;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final rows = (rooms.length + columns - 1) ~/ columns;
    return CustomScrollView(
      key: const ValueKey('popular-grid'),
      controller: scroll,
      physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
      semanticChildCount: rooms.length,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(6),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, row) => Padding(
                padding: EdgeInsets.only(bottom: row + 1 < rows ? mainSpacing : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) SizedBox(width: crossSpacing),
                      Expanded(
                        child: row * columns + column < rooms.length
                            ? RepaintBoundary(
                                child: IndexedSemantics(
                                  index: row * columns + column,
                                  child: card(rooms[row * columns + column]),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
              childCount: rows,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
            ),
          ),
        ),
        if (footer case final footer?) SliverToBoxAdapter(child: footer),
      ],
    );
  }
}

/// Static placeholder cards while the first rooms load (3.x showed a
/// spinner; no animation per card, which 3.x found costly).
class _Skeleton extends StatelessWidget {
  const new({required this.columns, required this.crossSpacing, required this.mainSpacing});

  final int columns;
  final double crossSpacing;
  final double mainSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final block = dark ? Colors.grey.shade800 : Colors.grey.shade200;
    final surface = dark ? Colors.grey.shade900 : Colors.white;
    Widget line(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(5)),
      ),
    );
    Widget card() => Container(
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: block),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [line(0.85), const SizedBox(height: 8), line(0.5)],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: const ValueKey('popular-skeleton'),
      label: i18n('refresh_loading'),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(6),
        itemCount: math.max(2, 8 ~/ columns),
        itemBuilder: (context, _) => Padding(
          padding: EdgeInsets.only(bottom: mainSpacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) SizedBox(width: crossSpacing),
                Expanded(child: card()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The mobile-data notice above a list (3.x `_buildCellularBanner`): shown
/// while the last load ran on mobile data; "never show" hides it for the
/// session.
class MobileDataBanner extends StatelessWidget {
  /// Creates the notice.
  const new({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([MobileDataNotice.onMobileData, MobileDataNotice.dismissed]),
    builder: (context, _) {
      if (!MobileDataNotice.onMobileData.value || MobileDataNotice.dismissed.value) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      return Container(
        key: const ValueKey('mobile-data-notice'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.signal_cellular_alt_rounded, color: colors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(i18n('cellular_warning_msg'), style: context.textStyles.t13)),
            TextButton(
              key: const ValueKey('mobile-data-never'),
              onPressed: () => MobileDataNotice.dismissed.value = true,
              child: Text(i18n('never_show')),
            ),
          ],
        ),
      );
    },
  );
}
