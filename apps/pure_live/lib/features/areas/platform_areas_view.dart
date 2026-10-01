import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/areas/area_card.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// One platform's areas (3.x `AreaGridView`): a tab per category, swiped
/// horizontally, each a grid of areas with pull to refresh; a filter that
/// searches every category of the platform (new); a failed refresh keeps
/// the areas and shows the error above them (new).
///
/// 3.x showed Douyin's categories as one flat grid; since Douyin lists its
/// games too (156 areas under "games", upgrade C-12) it has tabs like the
/// other platforms. A platform with one category shows no category tabs.
class PlatformAreasView extends StatefulWidget {
  /// Shows [catalog].
  const new({required this.catalog, super.key});

  /// The platform's catalogue.
  final AreaCatalog catalog;

  @override
  State<PlatformAreasView> createState() => _PlatformAreasViewState();
}

class _PlatformAreasViewState extends State<PlatformAreasView>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _tabIds = const [];
  final TextEditingController _filter = TextEditingController();
  bool _filtering = false;

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
    _filter.dispose();
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

  void _toggleFilter() => setState(() {
    _filtering = !_filtering;
    if (!_filtering) _filter.clear();
  });

  Widget _status(BuildContext context) {
    if (!_catalog.hasLoaded || _catalog.isLoading) {
      return AppStatusView(type: AppStatusType.loading, title: i18n('refresh_loading'));
    }
    final error = _catalog.error;
    if (error != null) {
      final login = isLoginError(error);
      return AppStatusView(
        type: AppStatusType.error,
        icon: login ? Icons.account_circle_outlined : Icons.wifi_off_rounded,
        title: i18n(login ? 'login_required_title' : 'network_error_title'),
        subtitle: describeLoadError(error),
        buttonText: i18n(login ? 'go_to_login' : 'retry'),
        buttonIcon: login ? Icons.login_rounded : null,
        onButtonPressed: login
            ? () => AppNavigator.toNamed<void>(RoutePath.kSettingsAccount).ignore()
            : () => _catalog.refresh().ignore(),
      );
    }
    return EmptyView(
      icon: Remix.apps_2_line,
      title: i18n('empty_areas_title'),
      subtitle: i18n('empty_areas_subtitle'),
      buttonText: i18n('refresh'),
      onButtonPressed: () => _catalog.refresh().ignore(),
    );
  }

  Widget _grid(List<LiveArea> areas, {required String emptyTitle, String? emptySubtitle}) {
    final content = areas.isEmpty
        ? LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: EmptyView(icon: Remix.apps_2_line, title: emptyTitle, subtitle: emptySubtitle ?? ''),
                ),
              ),
            ),
          )
        : AreaGrid(areas: areas);
    return RefreshIndicator(onRefresh: _catalog.refresh, child: content);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categories = _catalog.categories;
    if (categories.isEmpty) return _status(context);
    final theme = Theme.of(context);
    final keyword = _filter.text.trim();
    final tabs = _tabs;
    final error = _catalog.error;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: tabs == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(categories.single.name, style: context.textStyles.t14Bold),
                    )
                  : ScrollableTabBar(
                      key: const ValueKey('area-category-tabs'),
                      controller: tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      physics: const PureLiveBoundedScrollPhysics(),
                      tabs: [for (final category in categories) Tab(text: category.name)],
                    ),
            ),
            IconButton(
              key: const ValueKey('areas-filter-toggle'),
              tooltip: i18n('areas_filter_hint'),
              icon: Icon(_filtering ? Icons.close_rounded : Icons.search_rounded),
              onPressed: _toggleFilter,
            ),
            IconButton(
              key: const ValueKey('areas-refresh'),
              tooltip: i18n('refresh'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _catalog.isLoading ? null : () => _catalog.refresh().ignore(),
            ),
          ],
        ),
        if (_filtering)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: TextField(
              key: const ValueKey('areas-filter-field'),
              controller: _filter,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: i18n('areas_filter_hint'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (_catalog.isLoading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        if (error != null)
          Material(
            key: const ValueKey('areas-refresh-error'),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.info_outline_rounded, color: theme.colorScheme.onErrorContainer),
              title: Text(describeLoadError(error), style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              trailing: TextButton(onPressed: () => _catalog.refresh().ignore(), child: Text(i18n('retry'))),
            ),
          ),
        Expanded(
          child: keyword.isNotEmpty
              ? _grid(
                  filterAreas(_catalog.allAreas, keyword),
                  emptyTitle: i18n('areas_filter_empty', args: {'keyword': keyword}),
                )
              : tabs == null
              ? _grid(categories.single.children, emptyTitle: i18n('empty_areas_title'))
              : TabBarView(
                  controller: tabs,
                  physics: const PureLiveBoundedScrollPhysics(),
                  children: [
                    for (final category in categories)
                      KeyedSubtree(
                        key: ValueKey('area-page-${category.id}'),
                        child: _grid(category.children, emptyTitle: i18n('empty_areas_title')),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
