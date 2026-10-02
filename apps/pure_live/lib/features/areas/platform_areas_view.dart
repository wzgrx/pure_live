import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_card.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

/// Room under the grid for the floating "关注分区" button.
const double areasButtonClearance = 80;

/// One platform's areas (3.x `AreaGridView`, docs/ui/compare/U.4d): a tab
/// per category in the secondary style (c2), swiped horizontally; no tabs
/// when the platform has one category (c4); Douyin has category tabs too
/// (3.x put its few areas in one grid; with C-12's ~156 game areas that grid
/// ran to two or three hundred cards); the cards name only the area (c3); skeleton cards while loading (c8); pull
/// to refresh on phones and tablets, numbered pages with ← → on desktops
/// (3.x); a failed refresh keeps the areas and shows the error above them.
class PlatformAreasView extends ConsumerStatefulWidget {
  /// Shows [catalog].
  const new({required this.catalog, super.key});

  /// The platform's catalogue.
  final AreaCatalog catalog;

  @override
  ConsumerState<PlatformAreasView> createState() => _PlatformAreasViewState();
}

class _PlatformAreasViewState extends ConsumerState<PlatformAreasView>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _tabIds = const [];

  AreaCatalog get _catalog => widget.catalog;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_changed);
    _syncTabs();
  }

  @override
  void didUpdateWidget(PlatformAreasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      oldWidget.catalog.removeListener(_changed);
      widget.catalog.addListener(_changed);
      _syncTabs();
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_changed);
    _tabs?.removeListener(_onTab);
    _tabs?.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(_syncTabs);
  }

  /// Keeps one tab per category; the selection follows the catalogue's (kept
  /// by id across refreshes).
  void _syncTabs() {
    final ids = [for (final category in _catalog.categories) category.id];
    final same = ids.length == _tabIds.length && ids.indexed.every((entry) => entry.$2 == _tabIds[entry.$1]);
    if (!same) {
      final old = _tabs;
      if (old != null) {
        old.removeListener(_onTab);
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _tabIds = ids;
      _tabs = ids.length < 2
          ? null
          : (TabController(
              length: ids.length,
              initialIndex: _catalog.selected,
              vsync: this,
              animationDuration: pureLiveTabTransitionDuration,
            )..addListener(_onTab));
    } else if (_tabs case final tabs? when tabs.index != _catalog.selected && !tabs.indexIsChanging) {
      tabs.animateTo(_catalog.selected);
    }
  }

  void _onTab() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    _catalog.select(tabs.index);
  }

  Widget _status(BuildContext context) {
    final error = _catalog.error;
    // The lists' one failed state (U.1c): restricted, offline or failed.
    if (error != null) return loadErrorStatus(error, onRetry: () => _catalog.refresh().ignore());
    return EmptyView(
      icon: AppIcons.areas,
      title: i18n('empty_areas_title'),
      subtitle: i18n('empty_areas_subtitle'),
      buttonText: i18n('refresh'),
      onButtonPressed: () => _catalog.refresh().ignore(),
    );
  }

  /// The categories in the second row of tabs (U.4d c2, choice X1; the
  /// shared [SecondaryTabBar], U.1c c12).
  Widget _categoryTabs(BuildContext context, TabController tabs, List<LiveCategory> categories) => SecondaryTabBar(
    key: const ValueKey('area-category-tabs'),
    controller: tabs,
    physics: const PureLiveBoundedScrollPhysics(),
    tabs: [for (final category in categories) TabLabel(label: category.name)],
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categories = _catalog.categories;
    if (!_catalog.hasLoaded || (_catalog.isLoading && categories.isEmpty)) return const _AreasSkeleton();
    if (categories.isEmpty) return _status(context);
    final tabs = _tabs;
    final error = _catalog.error;
    final Widget content;
    if (tabs == null) {
      content = _AreaPages(
        key: ValueKey('area-page-${categories.single.id}'),
        areas: categories.single.children,
        onRefresh: _catalog.refresh,
        busy: _catalog.isLoading,
      );
    } else {
      content = TabBarView(
        controller: tabs,
        physics: const PureLivePageScrollPhysics(),
        children: [
          for (final category in categories)
            _AreaPages(
              key: ValueKey('area-page-${category.id}'),
              areas: category.children,
              onRefresh: _catalog.refresh,
              busy: _catalog.isLoading,
            ),
        ],
      );
    }
    return Column(
      children: [
        if (tabs != null) _categoryTabs(context, tabs, categories),
        if (_catalog.isLoading) const LinearProgressIndicator(minHeight: 2.5),
        if (error != null)
          refreshErrorBanner(
            context,
            error,
            key: const ValueKey('areas-refresh-error'),
            onRetry: _catalog.isLoading ? null : () => _catalog.refresh().ignore(),
            onClose: _catalog.clearError,
          ),
        Expanded(child: content),
      ],
    );
  }
}

/// The areas of one category: the whole grid with pull to refresh, or on
/// desktops numbered pages (3.x `BasePageView`).
class _AreaPages extends ConsumerStatefulWidget {
  const new({required this.areas, required this.onRefresh, required this.busy, super.key});

  final List<LiveArea> areas;
  final Future<void> Function() onRefresh;
  final bool busy;

  @override
  ConsumerState<_AreaPages> createState() => _AreaPagesState();
}

class _AreaPagesState extends ConsumerState<_AreaPages> {
  final ScrollController _scroll = createPureLiveScrollController();
  int _page = 1;
  int? _pageSize;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _page = page);
  }

  Widget _empty({ScrollPhysics physics = const AlwaysScrollableScrollPhysics()}) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: physics,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: EmptyView(
            icon: AppIcons.areas,
            title: i18n('empty_areas_title'),
            subtitle: i18n('empty_areas_subtitle'),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final desktop = usesDesktopPages(windowWidth);
    final areas = widget.areas;
    if (!desktop) {
      // 3.x's bounce and classic header (P02).
      return AppRefreshView(
        onRefresh: widget.onRefresh,
        builder: (context, physics) =>
            areas.isEmpty ? _empty(physics: physics) : AreaGrid(areas: areas, controller: _scroll, physics: physics),
      );
    }
    final showSizes = watchSetting(ref, Settings.pageShowSizeSelector);
    final showGoto = watchSetting(ref, Settings.pageShowGotoButton);
    watchSetting(ref, Settings.pageDefaultSize);
    watchSetting(ref, Settings.pageSizeOptions);
    final sizes = pageSizesOf(ref.read(storeProvider).settings, windowWidth);
    final pageSize = _pageSize ?? sizes.size;
    final lastPage = areas.isEmpty ? 1 : (areas.length / pageSize).ceil();
    final page = _page.clamp(1, lastPage);
    final shown = areas.sublist((page - 1) * pageSize, (page * pageSize).clamp(0, areas.length));
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
            Expanded(
              child: shown.isEmpty ? _empty() : AreaGrid(areas: shown, controller: _scroll),
            ),
            PaginationBar(
              page: page,
              lastPage: lastPage,
              canNext: page < lastPage,
              busy: widget.busy,
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
              onRefresh: () => widget.onRefresh().ignore(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page while the areas load (U.4d c8): grey pills for the category
/// row and grey cards, no shimmer.
class _AreasSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('areas-skeleton'),
      children: [
        Container(
          height: kTextTabBarHeight,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 24,
            children: [
              for (final width in const [30.0, 30.0, 58.0, 58.0, 30.0])
                Container(
                  width: width,
                  height: 14,
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(7)),
                ),
            ],
          ),
        ),
        const Expanded(child: AreaGridSkeleton()),
      ],
    );
  }
}
