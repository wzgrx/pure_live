import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_card.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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

/// The platform tabs of the followed areas (docs/ui/compare/U.4f c4, choice
/// Z1): "all", then the platforms that have followed areas, in the order of
/// "platform display" ([platformOrder]) and the others after them; none
/// without followed areas.
List<String> favoriteAreaTabs(Iterable<LiveArea> areas, List<String> platformOrder) {
  final present = {for (final area in areas) area.platform};
  if (present.isEmpty) return const [];
  final ordered = <String>[SiteIds.all];
  for (final id in [...platformOrder, ...SiteIds.supported, ...(present.toList()..sort())]) {
    final key = id.trim().toLowerCase();
    if (present.contains(key) && !ordered.contains(key)) ordered.add(key);
  }
  return ordered;
}

/// The followed areas (3.x `FavoriteAreasPage`, docs/ui/compare/U.4f):
/// "all" and the platforms that have followed areas, swiped between, the
/// last one kept while the page lives; the area grid of the areas page with
/// "platform · category" under each name in "all" and the category in a
/// platform's tab (c3); a long press or right click opens the area dialog,
/// whose "取消关注" asks first (c2); with nothing followed it says how to
/// follow and leads to the areas (c5).
class FavoriteAreasView extends ConsumerStatefulWidget {
  /// Creates the view.
  const new({required this.route, super.key});

  /// How the page was opened.
  final RouteArgs route;

  @override
  ConsumerState<FavoriteAreasView> createState() => _FavoriteAreasViewState();
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
    if (ids.length == _ids.length && ids.indexed.every((entry) => entry.$2 == _ids[entry.$1])) return;
    final index = resolveFavoriteAreaSiteIndex(siteIds: ids, selectedSiteId: _selectedId, fallback: _tabs?.index ?? 0);
    final old = _tabs;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _ids = ids;
    if (ids.isEmpty) {
      _tabs = null;
      return;
    }
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

  void _toAreas() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      AppNavigator.toNamed<void>(RoutePath.kAreas).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final followed = ref.watch(followedAreasProvider);
    final areas = followed.value ?? const <LiveArea>[];
    _sync(favoriteAreaTabs(areas, watchSetting(ref, Settings.hotAreasList)));
    final tabs = _tabs;
    String label(String id) =>
        id == SiteIds.all ? i18n('site_all') : platformName(id, fallback: sites.maybeOf(id)?.name);

    final Widget body;
    if (followed.isLoading && !followed.hasValue) {
      body = const AreaGridSkeleton();
    } else if (tabs == null) {
      body = AppStatusView(
        type: AppStatusType.empty,
        icon: AppIcons.areas,
        title: i18n('empty_areas_title'),
        subtitle: i18n('favorite_areas_empty_hint'),
        buttonText: i18n('favorite_areas_go_to_areas'),
        buttonIcon: AppIcons.areas,
        onButtonPressed: _toAreas,
      );
    } else {
      body = Column(
        children: [
          ScrollableTabBar(
            key: const ValueKey('favorite-areas-platform-tabs'),
            controller: tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            physics: const PureLiveBoundedScrollPhysics(),
            tabs: [for (final id in _ids) TabLabel(label: label(id))],
          ),
          Expanded(
            child: TabBarView(
              controller: tabs,
              physics: const PureLiveBoundedScrollPhysics(),
              children: [
                for (final id in _ids)
                  AreaGrid(
                    key: PageStorageKey('favorite_areas_$id'),
                    areas: id == SiteIds.all
                        ? areas
                        : [
                            for (final area in areas)
                              if (area.platform == id) area,
                          ],
                    caption: id == SiteIds.all ? AreaCaption.platformAndCategory : AreaCaption.category,
                    bottomPadding: 16,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n('favorite_areas'))),
      body: body,
    );
  }
}
