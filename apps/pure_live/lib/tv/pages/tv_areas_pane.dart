import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_area_card.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// The tab of the followed areas.
const String _followedTab = 'followed';

/// Areas (pure_live_TV `AreasPage` and `FavoriteAreasPage` over v4's area
/// catalogues, M13.5): the followed areas first, then one tab per platform
/// with its categories in a second row and the areas in a grid. OK opens an
/// area's rooms (an IPTV channel plays, CC's official entries open in the
/// browser, as on the phone); a held OK follows or unfollows the area.
class TvAreasPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvAreasPane> createState() => _TvAreasPaneState();
}

class _TvAreasPaneState extends ConsumerState<TvAreasPane> {
  final GlobalKey<TvTabBarState> _platformTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _categoryTabs = GlobalKey();
  final Map<String, GlobalKey<TvGridState>> _grids = {};
  final Map<String, AreaCatalog> _catalogs = {};
  String? _current;

  GlobalKey<TvGridState> _grid(String key) => _grids[key] ??= GlobalKey();

  AreaCatalog _catalog(String platform) => _catalogs[platform] ??= AreaCatalog(
    ref.read(sitesProvider).of(platform),
    pictures: ref.read(areaPicturesProvider),
  );

  @override
  void dispose() {
    for (final catalog in _catalogs.values) {
      catalog.dispose();
    }
    super.dispose();
  }

  void _select(String tab) {
    setState(() => _current = tab);
    if (tab != _followedTab) unawaited(_catalog(tab).ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final platforms = [
      for (final id in sites.availableIds(watchSetting(ref, Settings.hotAreasList)))
        if (id != SiteIds.iptv) id,
    ];
    final followed = ref.watch(followedAreasProvider).value ?? const <LiveArea>[];
    final tabs = [_followedTab, ...platforms];
    var current = _current;
    if (current == null || !tabs.contains(current)) {
      final preferred = ref.read(storeProvider).settings.get(Settings.preferPlatform);
      current = _current = followed.isNotEmpty
          ? _followedTab
          : (platforms.contains(preferred) ? preferred : (platforms.firstOrNull ?? _followedTab));
      final first = current;
      if (first != _followedTab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_catalog(first).ensureLoaded());
        });
      }
    }
    final tab = current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvTabBar(
          key: _platformTabs,
          tabs: [
            for (final id in tabs)
              if (id == _followedTab)
                TvTab(id: id, label: i18n('tv_followed_areas'), icon: TvIcons.followedArea)
              else
                TvTab(
                  id: id,
                  label: platformName(id, fallback: sites.of(id).name),
                  logo: id,
                ),
          ],
          selected: tabs.indexOf(tab),
          onSelect: (index) => _select(tabs[index]),
          onRefresh: tab == _followedTab ? null : () => unawaited(_catalog(tab).refresh()),
          onDown: tab == _followedTab ? () => _grid(_followedTab).currentState?.enter() ?? false : null,
        ),
        Expanded(child: tab == _followedTab ? _followedAreas(followed) : _platformAreas(tab)),
      ],
    );
  }

  Widget _followedAreas(List<LiveArea> areas) {
    if (areas.isEmpty) {
      return TvStatusView(
        icon: TvIcons.followArea,
        title: i18n('empty_areas_title'),
        subtitle: i18n('tv_no_followed_areas'),
      );
    }
    return _AreaGrid(
      gridKey: _grid(_followedTab),
      areas: areas,
      showPlatform: true,
      onLeaveUp: () => _platformTabs.currentState?.focusSelected(),
    );
  }

  Widget _platformAreas(String platform) {
    final catalog = _catalog(platform);
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final categories = catalog.categories;
        if (categories.isEmpty) {
          if (!catalog.hasLoaded || catalog.isLoading) return const TvSkeletonGrid(columns: 6);
          if (catalog.error != null) {
            return TvStatusView.failure(catalog.error, onRetry: () => unawaited(catalog.refresh()));
          }
          return TvStatusView(
            icon: TvIcons.noAreas,
            title: i18n('tv_no_areas'),
            actions: [
              TvStatusAction(icon: AppIcons.refresh, label: i18n('retry'), onTap: () => unawaited(catalog.refresh())),
            ],
          );
        }
        final selected = catalog.selected;
        final areas = categories[selected].children;
        final gridKey = _grid('$platform/${categories[selected].id}');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvTabBar(
              key: _categoryTabs,
              small: true,
              tabs: [
                for (final (index, category) in categories.indexed)
                  TvTab(id: '$index:${category.id}', label: category.name),
              ],
              selected: selected,
              busy: catalog.isLoading,
              onSelect: catalog.select,
              onRefresh: () => unawaited(catalog.refresh()),
              onDown: () => gridKey.currentState?.enter() ?? false,
            ),
            Expanded(
              child: areas.isEmpty
                  ? TvStatusView(icon: TvIcons.noAreas, title: i18n('tv_no_areas'))
                  : _AreaGrid(
                      key: ValueKey(gridKey),
                      gridKey: gridKey,
                      areas: areas,
                      onLeaveUp: () => _categoryTabs.currentState?.focusSelected(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Areas in a [TvGrid] (U.15a c6 `TvAreaCard`): six columns (fewer as the
/// text grows), the picture over the name, a heart on the followed ones.
class _AreaGrid extends ConsumerWidget {
  const new({required this.gridKey, required this.areas, this.showPlatform = false, this.onLeaveUp, super.key});

  final GlobalKey<TvGridState> gridKey;
  final List<LiveArea> areas;
  final bool showPlatform;
  final VoidCallback? onLeaveUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = TvScale.of(context);
    final pictures = ref.watch(areaPicturesProvider);
    final followed = ref.watch(followedAreaKeysProvider).value ?? const <String>{};
    final columns = tvRoomColumns(watchSetting(ref, Settings.textScaleFactor), base: 6);
    return TvGrid(
      key: gridKey,
      itemCount: areas.length,
      columns: columns,
      aspectRatio: showPlatform ? 0.7 : 0.78,
      crossSpacing: scale.px(16),
      mainSpacing: scale.px(16),
      onLeaveUp: onLeaveUp,
      itemBuilder: (context, index, node, onKey) {
        final area = areas[index];
        final picture = pictures.pictureFor(area);
        return TvAreaCard(
          key: ValueKey('tv-area-$index'),
          focusNode: node,
          onKey: onKey,
          name: areaDisplayName(area),
          picture: picture.isEmpty ? null : picture,
          subtitle: showPlatform ? platformName(area.platform) : null,
          followed: !showPlatform && followed.contains(area.identityKey),
          onTap: () => openArea(ref, area),
          onLongPress: () => unawaited(toggleAreaFollow(context, ref, area)),
        );
      },
    );
  }
}
