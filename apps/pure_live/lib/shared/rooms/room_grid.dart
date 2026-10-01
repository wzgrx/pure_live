import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// The room grids of the browsing pages (docs/ui/compare/U.4a–U.4e): the
// card, the columns, the skeleton, the jump buttons and a whole feed page
// (popular, area rooms) with its states, phone paging and desktop pages.

/// The padding around a room grid and between the page edge and its cards
/// (U.4a c15: 6 on every page, like 3.x's popular page).
const double roomGridPadding = 6;

/// How a room grid lays out its cards.
@immutable
final class RoomGridGeometry {
  /// Works the geometry out (UI_PLAN §5.3 columns; the card height from the
  /// card settings and the text size).
  factory of(
    BuildContext context, {
    required double width,
    required double spacing,
    required RoomCardAppearance appearance,
    LiveFontSizes fontSizes = const LiveFontSizes(),
    bool dense = true,
    double? minItemWidth,
    int minColumns = 2,
  }) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final columns = GridColumns.count(
      width: width,
      minItemWidth: minItemWidth ?? GridColumns.roomMinWidth(windowWidth),
      spacing: spacing,
      min: minColumns,
    );
    final itemWidth = GridColumns.itemWidth(width: width, columns: columns, spacing: spacing);
    final extent = LiveRoomCardMetrics.extent(
      itemWidth: itemWidth,
      dense: dense,
      appearance: appearance,
      textScaler: MediaQuery.textScalerOf(context),
      fontSizes: fontSizes,
    );
    return RoomGridGeometry._(columns, itemWidth, extent);
  }

  const new _(this.columns, this.itemWidth, this.extent);

  /// Columns.
  final int columns;

  /// The width of a card.
  final double itemWidth;

  /// The height of a card.
  final double extent;

  /// The grid delegate with [spacing] between columns and [mainSpacing]
  /// between rows.
  SliverGridDelegate delegate({required double spacing, required double mainSpacing}) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: mainSpacing,
        mainAxisExtent: extent,
      );
}

/// The card of [room] with the page's settings: opens the room on tap and
/// the card dialog on long press or right click (U.4a).
class RoomGridCard extends ConsumerWidget {
  /// Creates the card.
  const new({
    required this.room,
    this.mixedPlatforms = false,
    this.dense = true,
    this.statusPending = false,
    this.statusPendingLabel,
    this.now,
    this.onOpen,
    super.key,
  });

  /// The room.
  final LiveRoom room;

  /// The list mixes platforms (the platform badge's "automatic").
  final bool mixedPlatforms;

  /// The small card.
  final bool dense;

  /// The live status is being checked.
  final bool statusPending;

  /// Words of the [statusPending] badge.
  final String? statusPendingLabel;

  /// With a time, a live room's streamer line says how long it is on air.
  final DateTime? now;

  /// Opens the room; null opens it as a page.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = watchAudiencePolicy(ref);
    final appearance = watchCardAppearance(ref);
    return LiveRoomCard(
      data: policy.cardOf(room, now: now),
      appearance: appearance,
      dense: dense,
      mixedPlatforms: mixedPlatforms,
      statusPending: statusPending,
      statusPendingLabel: statusPendingLabel,
      onTap: onOpen ?? () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room)),
      onLongPress: () => unawaited(showRoomMenu(context, store: ref.read(storeProvider), room: room)),
    );
  }
}

/// Static placeholder cards filling the box while the first rooms load
/// (U.4a c8): the columns and the size of the real cards, so nothing jumps
/// when they arrive.
class RoomGridSkeleton extends ConsumerWidget {
  /// Creates the placeholder.
  const new({this.dense = true, this.minItemWidth, this.minColumns = 2, super.key});

  /// The small card.
  final bool dense;

  /// The smallest card (the follows page's large cards).
  final double? minItemWidth;

  /// The fewest columns.
  final int minColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = RoomGridGeometry.of(
          context,
          width: constraints.maxWidth,
          spacing: spacing,
          appearance: appearance,
          fontSizes: fontSizes,
          dense: dense,
          minItemWidth: minItemWidth,
          minColumns: minColumns,
        );
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 800.0;
        final rows = (height / (geometry.extent + mainSpacing)).ceil().clamp(1, 12);
        return Semantics(
          key: const ValueKey('room-grid-skeleton'),
          label: i18n('refresh_loading'),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(roomGridPadding),
            gridDelegate: geometry.delegate(spacing: spacing, mainSpacing: mainSpacing),
            itemCount: rows * geometry.columns,
            itemBuilder: (context, _) => RoomCardSkeleton(appearance: appearance, dense: dense),
          ),
        );
      },
    );
  }
}

/// "To top" and "to bottom" over a list once it scrolls (3.x
/// `BasePageView`'s mini buttons): "to top" past 400, "to bottom" while more
/// than 400 remain; at the bottom right of the list (U.4e c4).
class JumpButtons extends StatefulWidget {
  /// Creates the buttons for [controller].
  const new({required this.controller, required this.heroTag, super.key});

  /// The list's position.
  final ScrollController controller;

  /// Unique per page (two lists may be alive at once).
  final String heroTag;

  @override
  State<JumpButtons> createState() => _JumpButtonsState();
}

class _JumpButtonsState extends State<JumpButtons> {
  bool _top = false;
  bool _bottom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(JumpButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final controller = widget.controller;
    if (!controller.hasClients || controller.positions.length != 1) {
      if (_top || _bottom) setState(() => _top = _bottom = false);
      return;
    }
    final position = controller.position;
    final top = position.pixels > 400;
    final bottom = position.maxScrollExtent - position.pixels > 400;
    if (top != _top || bottom != _bottom) {
      setState(() {
        _top = top;
        _bottom = bottom;
      });
    }
  }

  void _jump({required bool up}) {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final target = up ? 0.0 : controller.position.maxScrollExtent;
    final distance = (target - controller.offset).abs();
    controller.animateTo(
      target,
      duration: Duration(milliseconds: (180 + distance / 8).round().clamp(220, 520)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surfaceContainerLow;
    Widget button({required bool shown, required bool up}) => AnimatedScale(
      scale: shown ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: FloatingActionButton.small(
        key: ValueKey(up ? 'jump-top' : 'jump-bottom'),
        heroTag: '${widget.heroTag}-${up ? 'top' : 'bottom'}',
        elevation: 3,
        backgroundColor: background,
        tooltip: i18n(up ? 'popular_to_top' : 'popular_to_bottom'),
        onPressed: shown ? () => _jump(up: up) : null,
        child: Icon(up ? AppIcons.toTop : AppIcons.toBottom),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        button(shown: _top, up: true),
        button(shown: _bottom, up: false),
      ],
    );
  }
}

/// A short explanation over a list in a tinted bar with ⓘ (U.4b c6): at
/// most two lines; a tap shows all of it.
class NoticeBar extends StatefulWidget {
  /// Creates the bar.
  const new({required this.text, super.key});

  /// The words.
  final String text;

  @override
  State<NoticeBar> createState() => _NoticeBarState();
}

class _NoticeBarState extends State<NoticeBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(AppIcons.info, size: 16, color: scheme.primary),
                ),
                Expanded(
                  child: Text(
                    widget.text,
                    maxLines: _open ? null : 2,
                    overflow: _open ? null : TextOverflow.ellipsis,
                    style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ),
              ],
            ),
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
            Icon(AppIcons.mobileData, color: colors.primary, size: 18),
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

/// The state of a list that failed to load (3.x `AppStatusView`): a login
/// for a platform that wants one ("前往登录" with the login icon, U.4e
/// c6), else "网络请求失败" with the reason in one sentence and "重试"
/// (U.4b c5).
Widget loadErrorStatus(Object error, {required VoidCallback onRetry}) {
  if (isLoginError(error)) {
    return AppStatusView(
      type: AppStatusType.error,
      icon: AppIcons.loginRequired,
      title: i18n('login_required_title'),
      subtitle: i18n('login_required_subtitle'),
      buttonText: i18n('go_to_login'),
      buttonIcon: AppIcons.login,
      onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsAccount)),
    );
  }
  return AppStatusView(
    type: AppStatusType.error,
    icon: AppIcons.networkError,
    title: i18n('network_error_title'),
    subtitle: describeLoadError(error),
    buttonText: i18n('retry'),
    onButtonPressed: onRetry,
  );
}

/// What an empty feed says.
typedef FeedEmptyWords = ({IconData icon, String title, String Function({required bool desktop}) subtitle});

/// One feed of rooms as a page body (3.x `BasePageView` over a room grid):
/// static skeleton cards while the first rooms load, the error or empty
/// state, then the cards; on phones and tablets pull to refresh and more
/// rooms at the end, on desktops numbered pages with ← → (U.4b c1); the
/// directory's [notice], the mobile-data notice, a failed refresh above the
/// cards, the progress line and the jump buttons.
///
/// The page loads the first rooms ([RoomFeed.open]) unless [openOnShow].
class RoomFeedView extends ConsumerStatefulWidget {
  /// Creates the view of [feed].
  const new({
    required this.feed,
    required this.keyPrefix,
    required this.empty,
    required this.hiddenNote,
    required this.onShowHidden,
    this.notice,
    this.pageSize,
    this.onPageSize,
    this.openOnShow = false,
    super.key,
  });

  /// The rooms.
  final RoomFeed feed;

  /// Prefix of the widget keys (`popular`, `area-rooms`).
  final String keyPrefix;

  /// The empty state.
  final FeedEmptyWords empty;

  /// "N rooms that cannot play here are hidden".
  final String Function(int count) hiddenNote;

  /// Shows the hidden rooms.
  final VoidCallback onShowHidden;

  /// The directory's explanation (partial directories).
  final String? notice;

  /// The desktop page size picked earlier; null uses the setting.
  final int? pageSize;

  /// Remembers a picked desktop page size.
  final ValueChanged<int>? onPageSize;

  /// Loads the first rooms when first shown.
  final bool openOnShow;

  @override
  ConsumerState<RoomFeedView> createState() => _RoomFeedViewState();
}

class _RoomFeedViewState extends ConsumerState<RoomFeedView> {
  final ScrollController _scroll = createPureLiveScrollController();
  int? _pageSize;
  bool _opened = false;

  RoomFeed get _feed => widget.feed;

  @override
  void initState() {
    super.initState();
    _pageSize = widget.pageSize;
    _feed.addListener(_feedChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.openOnShow && !_opened) {
      _opened = true;
      final count = _firstCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_feed.open(count: count));
      });
    }
  }

  @override
  void didUpdateWidget(RoomFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed) {
      oldWidget.feed.removeListener(_feedChanged);
      widget.feed.addListener(_feedChanged);
    }
    if (widget.pageSize != null && widget.pageSize != oldWidget.pageSize) _pageSize = widget.pageSize;
  }

  @override
  void dispose() {
    _feed.removeListener(_feedChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _feedChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillViewport();
    });
  }

  bool get _desktop => usesDesktopPages(MediaQuery.sizeOf(context).width);

  int get _currentPageSize =>
      _pageSize ?? pageSizesOf(ref.read(storeProvider).settings, MediaQuery.sizeOf(context).width).size;

  int get _firstCount => _desktop ? _currentPageSize : phonePageSize;

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

  Future<void> _goToPage(int page) async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _feed.goToPage(page, size: _currentPageSize);
  }

  void _setPageSize(int size) {
    final old = _currentPageSize;
    if (size == old) return;
    // Keep the first room of the page in view (3.x).
    final first = (_feed.page - 1) * old;
    setState(() => _pageSize = size);
    widget.onPageSize?.call(size);
    unawaited(_goToPage(first ~/ size + 1));
  }

  bool _canGoNext(int pageSize) => _feed.rooms.length > _feed.page * pageSize || _feed.hasMore;

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(storeProvider).settings;
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final showJumps = watchSetting(ref, Settings.pageShowScrollTop);
    final showSizes = watchSetting(ref, Settings.pageShowSizeSelector);
    final showGoto = watchSetting(ref, Settings.pageShowGotoButton);
    watchSetting(ref, Settings.pageDefaultSize);
    watchSetting(ref, Settings.pageSizeOptions);
    final prefix = widget.keyPrefix;
    final desktop = _desktop;
    final sizes = pageSizesOf(settings, MediaQuery.sizeOf(context).width);
    final pageSize = _pageSize ?? sizes.size;
    final hasContent = _feed.rooms.isNotEmpty;

    final Widget body;
    if (!hasContent && (!_feed.loaded || (_feed.busy && _feed.error == null))) {
      body = KeyedSubtree(key: ValueKey('$prefix-skeleton'), child: const RoomGridSkeleton());
    } else if (!hasContent && _feed.error != null) {
      body = _status(desktop, loadErrorStatus(_feed.error!, onRetry: () => unawaited(_refresh())));
    } else if (!hasContent) {
      body = _status(desktop, _emptyStatus(desktop));
    } else {
      final rooms = desktop ? _feed.pageRooms(_feed.page, pageSize) : _feed.rooms;
      final grid = LayoutBuilder(
        builder: (context, constraints) {
          final geometry = RoomGridGeometry.of(
            context,
            width: constraints.maxWidth,
            spacing: spacing,
            appearance: appearance,
            fontSizes: fontSizes,
          );
          return CustomScrollView(
            key: ValueKey('$prefix-grid'),
            controller: _scroll,
            physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            semanticChildCount: rooms.length,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(roomGridPadding),
                sliver: SliverGrid.builder(
                  gridDelegate: geometry.delegate(spacing: spacing, mainSpacing: mainSpacing),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) =>
                      RoomGridCard(key: ValueKey(rooms[index].identityKey), room: rooms[index]),
                ),
              ),
              if (desktop ? _hiddenNote(context) : _phoneFooter(context) case final footer?)
                SliverToBoxAdapter(child: footer),
            ],
          );
        },
      );
      final list = Stack(
        children: [
          Positioned.fill(child: grid),
          if (showJumps)
            Positioned(
              right: 16,
              bottom: 16,
              child: JumpButtons(controller: _scroll, heroTag: '$prefix-${_feed.platform}'),
            ),
        ],
      );
      if (desktop) {
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
                Expanded(child: list),
                PaginationBar(
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
            child: list,
          ),
        );
      }
    }

    return Stack(
      children: [
        Column(
          children: [
            if (widget.notice case final notice? when notice.isNotEmpty)
              NoticeBar(key: ValueKey('$prefix-notice'), text: notice),
            if (hasContent) const MobileDataBanner(),
            if (_feed.errorOnRefresh && _feed.error != null && hasContent) _refreshErrorBanner(context),
            Expanded(child: body),
          ],
        ),
        if (hasContent && _feed.busy)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2.5)),
      ],
    );
  }

  Widget _refreshErrorBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Semantics(
        liveRegion: true,
        child: MaterialBanner(
          key: ValueKey('${widget.keyPrefix}-refresh-error'),
          backgroundColor: colors.errorContainer,
          leading: Icon(AppIcons.info, color: colors.onErrorContainer),
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

  Widget _emptyStatus(bool desktop) {
    final hidden = _feed.hiddenCount;
    final empty = widget.empty;
    return AppStatusView(
      type: AppStatusType.empty,
      icon: empty.icon,
      title: empty.title,
      subtitle: hidden > 0 ? widget.hiddenNote(hidden) : empty.subtitle(desktop: desktop),
      buttonText: hidden > 0 ? i18n('popular_show_hidden') : i18n('refresh'),
      buttonIcon: hidden > 0 ? AppIcons.showHidden : null,
      onButtonPressed: hidden > 0 ? widget.onShowHidden : () => unawaited(_refresh()),
      // U.1c C1: a second action is a text button.
      secondaryButtonText: hidden > 0 ? i18n('refresh') : null,
      onSecondaryButtonPressed: hidden > 0 ? () => unawaited(_refresh()) : null,
    );
  }

  Widget _status(bool desktop, Widget status) => LayoutBuilder(
    builder: (context, constraints) {
      final view = SingleChildScrollView(
        key: ValueKey('${widget.keyPrefix}-status'),
        physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight * (desktop ? 1 : 0.8)),
          child: Center(child: status),
        ),
      );
      return desktop ? view : RefreshIndicator(onRefresh: _refresh, child: view);
    },
  );

  Widget? _hiddenNote(BuildContext context) {
    final hidden = _feed.hiddenCount;
    if (hidden == 0) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(widget.hiddenNote(hidden), style: context.textStyles.t12Muted, textAlign: TextAlign.center),
          ),
          TextButton(
            key: ValueKey('${widget.keyPrefix}-show-hidden'),
            onPressed: widget.onShowHidden,
            child: Text(i18n('popular_show_hidden')),
          ),
        ],
      ),
    );
  }

  Widget _phoneFooter(BuildContext context) {
    final Widget state;
    if (_feed.error != null && !_feed.errorOnRefresh) {
      state = TextButton.icon(
        key: ValueKey('${widget.keyPrefix}-load-more-retry'),
        onPressed: () => unawaited(_feed.retry(count: _feed.rooms.length + phonePageSize)),
        icon: const Icon(AppIcons.refresh, size: 18),
        label: Text(i18n('popular_load_more_failed')),
      );
    } else if (_feed.busy) {
      state = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_feed.hasMore) {
      state = TextButton(onPressed: _loadMore, child: Text(i18n('popular_load_more')));
    } else {
      state = Text(i18n('refresh_no_more_data'), style: context.textStyles.t12Muted);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [state, ?_hiddenNote(context)]),
    );
  }
}
