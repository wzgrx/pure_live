import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/areas/area_card.dart';
import 'package:pure_live/pages/areas/areas_common.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The followed areas (3.x `FavoriteAreasPage`): an "all" tab, then one tab
/// per platform on the user's list; each tab counts its areas (new). A long
/// press unfollows (new; 3.x only unfollowed from an area's rooms).
class FavoriteAreasView extends ConsumerStatefulWidget {
  /// Creates the view.
  const new({required this.route, super.key});

  /// How the page was opened.
  final RouteArgs route;

  @override
  ConsumerState<FavoriteAreasView> createState() => _FavoriteAreasViewState();
}

/// The tab to show among [siteIds]: [selectedSiteId] when it is still there,
/// else [fallback] clamped (3.x `resolveFavoriteAreaSiteIndex`).
int resolveFavoriteAreaSiteIndex({
  required List<String> siteIds,
  required String selectedSiteId,
  required int fallback,
}) {
  if (siteIds.isEmpty) return 0;
  final selected = siteIds.indexOf(selectedSiteId);
  return selected >= 0 ? selected : fallback.clamp(0, siteIds.length - 1);
}

class _FavoriteAreasViewState extends ConsumerState<FavoriteAreasView> with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _ids = const [];
  String _selectedId = SiteIds.all;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  void _sync(List<String> ids) {
    if (ids.length == _ids.length && ids.indexed.every((entry) => entry.$2 == _ids[entry.$1]) && _tabs != null) return;
    final index = resolveFavoriteAreaSiteIndex(siteIds: ids, selectedSiteId: _selectedId, fallback: _tabs?.index ?? 0);
    final old = _tabs;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _ids = ids;
    final tabs = TabController(
      length: ids.length,
      initialIndex: index,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    );
    tabs.addListener(() {
      if (identical(_tabs, tabs)) _selectedId = _ids[tabs.index];
    });
    _tabs = tabs;
    _selectedId = ids[index];
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = [SiteIds.all, ...sites.availableIds(watchSetting(ref, Settings.hotAreasList))];
    _sync(ids);
    final followed = ref.watch(followedAreasProvider);
    final areas = followed.value ?? const <LiveArea>[];
    int countOf(String id) => id == SiteIds.all ? areas.length : areas.where((area) => area.platform == id).length;
    String label(String id) {
      final name = id == SiteIds.all ? i18n('site_all') : platformName(id, fallback: sites.maybeOf(id)?.name);
      final count = countOf(id);
      return count > 0 ? '$name $count' : name;
    }

    return Scaffold(
      appBar: AppBar(title: Text(i18n('favorite_areas'))),
      body: Column(
        children: [
          ScrollableTabBar(
            key: const ValueKey('favorite-areas-platform-tabs'),
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            physics: const PureLiveBoundedScrollPhysics(),
            tabs: [for (final id in ids) Tab(text: label(id))],
          ),
          Expanded(
            child: followed.isLoading && !followed.hasValue
                ? AppStatusView(type: AppStatusType.loading, title: i18n('refresh_loading'))
                : TabBarView(
                    controller: _tabs,
                    physics: const PureLiveBoundedScrollPhysics(),
                    children: [
                      for (final id in ids)
                        _FollowedAreasTab(
                          key: PageStorageKey('favorite_areas_$id'),
                          areas: id == SiteIds.all
                              ? areas
                              : [
                                  for (final area in areas)
                                    if (area.platform == id) area,
                                ],
                          showPlatform: id == SiteIds.all,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FollowedAreasTab extends StatelessWidget {
  const new({required this.areas, required this.showPlatform, super.key});

  final List<LiveArea> areas;
  final bool showPlatform;

  @override
  Widget build(BuildContext context) => areas.isEmpty
      ? EmptyView(
          icon: Remix.apps_2_line,
          title: i18n('empty_areas_title'),
          subtitle: i18n('areas_followed_empty_subtitle'),
        )
      : AreaGrid(areas: areas, showPlatform: showPlatform);
}
