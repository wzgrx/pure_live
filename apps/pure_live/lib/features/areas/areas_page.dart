import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/features/areas/favorite_areas_view.dart';
import 'package:pure_live/features/areas/platform_areas_view.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Areas and followed areas (3.x `lib/modules/areas`).
///
/// Routes: `RoutePath.kAreas` (also the home tab), `RoutePath.kFavoriteAreas`.
class AreasPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) =>
      route.path == RoutePath.kFavoriteAreas ? FavoriteAreasView(route: route) : AreasView(route: route);
}

/// The areas of the platforms on the user's list (3.x `AreasPage` +
/// `AreasController`): one tab per platform in the saved order, starting at
/// the preferred platform; each platform's catalogue loads when its tab is
/// first shown, and the next platform's a moment after (3.x's warm-up).
class AreasView extends ConsumerStatefulWidget {
  /// Creates the view.
  const new({required this.route, super.key});

  /// How the page was opened.
  final RouteArgs route;

  @override
  ConsumerState<AreasView> createState() => _AreasViewState();
}

class _AreasViewState extends ConsumerState<AreasView> with TickerProviderStateMixin {
  final Map<String, AreaCatalog> _catalogs = {};
  List<String> _ids = const [];
  TabController? _tabs;
  Timer? _warm;

  @override
  void initState() {
    super.initState();
    HomeSignals.resumedAfterBackground.addListener(_onResumed);
  }

  @override
  void dispose() {
    HomeSignals.resumedAfterBackground.removeListener(_onResumed);
    _warm?.cancel();
    _tabs?.removeListener(_onTab);
    _tabs?.dispose();
    for (final catalog in _catalogs.values) {
      catalog.dispose();
    }
    super.dispose();
  }

  AreaCatalog _catalog(String id) =>
      _catalogs[id] ??= AreaCatalog(ref.read(sitesProvider).of(id), pictures: ref.read(areaPicturesProvider));

  String? get _currentId {
    final tabs = _tabs;
    if (tabs == null || _ids.isEmpty) return null;
    return _ids[tabs.index.clamp(0, _ids.length - 1)];
  }

  /// Follows the platform list: keeps the shown platform when it is still
  /// listed, else the preferred one on first show, else the first.
  void _sync(List<String> ids) {
    if (_listEquals(ids, _ids) && (_tabs != null || ids.isEmpty)) return;
    final previous = _tabs == null ? ref.read(storeProvider).settings.get(Settings.preferPlatform) : _currentId;
    final old = _tabs;
    _ids = ids;
    _tabs = null;
    if (old != null) {
      old.removeListener(_onTab);
      // The old tab bar is still mounted in this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    for (final id in _catalogs.keys.where((id) => !ids.contains(id)).toList()) {
      _catalogs.remove(id)!.dispose();
    }
    if (ids.isEmpty) return;
    final index = ids.indexOf(previous ?? '');
    _tabs = TabController(
      length: ids.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    )..addListener(_onTab);
    // Not during build: loading notifies the platform pages.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCurrent();
    });
  }

  void _onTab() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    _loadCurrent();
  }

  void _loadCurrent() {
    final id = _currentId;
    if (id == null) return;
    _warm?.cancel();
    final catalog = _catalog(id);
    catalog.ensureLoaded().then((_) {
      if (!mounted || _currentId != id || catalog.categories.isEmpty) return;
      _warm = Timer(const Duration(milliseconds: 800), () => _warmNext(id));
    }).ignore();
  }

  void _warmNext(String id) {
    if (!mounted || _currentId != id || _ids.length < 2) return;
    final index = _ids.indexOf(id);
    final next = index + 1 < _ids.length ? index + 1 : index - 1;
    if (next >= 0) _catalog(_ids[next]).ensureLoaded().ignore();
  }

  void _onResumed() {
    final signal = HomeSignals.resumedAfterBackground.value;
    if (!widget.route.inHome || signal?.$1 != HomeMenu.areas) return;
    final id = _currentId;
    if (id != null) _catalog(id).refresh().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final ids = ref.read(sitesProvider).availableIds(watchSetting(ref, Settings.hotAreasList));
    _sync(ids);
    final phoneTab = showsHomeBarButtons(context, inHome: widget.route.inHome);
    final tabs = _tabs;
    return Scaffold(
      appBar: AppBar(
        centerTitle: centredPageTitle,
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        actions: phoneTab ? const [CommonAppBarActions()] : null,
        title: tabs == null
            ? Text(i18n('areas_title'))
            : ScrollableTabBar(
                key: const ValueKey('areas-platform-tabs'),
                controller: tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                physics: const PureLiveBoundedScrollPhysics(),
                // The last tab fades (A09.4 v4-phone; the same as popular's,
                // A09.12 c1).
                endFade: tabStripEndFade,
                tabs: [
                  for (final id in ids)
                    TabLabel(label: platformName(id, fallback: ref.read(sitesProvider).of(id).name)),
                ],
              ),
      ),
      body: tabs == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: AppIcons.areas,
              title: i18n('areas_no_platforms'),
              subtitle: i18n('areas_no_platforms_subtitle'),
              buttonText: i18n('platform_display'),
              buttonIcon: AppIcons.platformSettings,
              onButtonPressed: () => AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas).ignore(),
            )
          : TabBarView(
              controller: tabs,
              // Each platform pages its categories horizontally; the platform
              // tabs switch by tap only, so two horizontal drags never fight
              // (3.x).
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final id in ids) PlatformAreasView(key: ValueKey('areas-$id'), catalog: _catalog(id))],
            ),
      floatingActionButton: tabs == null ? null : const _FollowedAreasButton(),
    );
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The "followed areas" button (3.x's floating pill, docs/A-界面设计/A09-浏览界面/A09.4-分区
/// c1); on desktops above the page bar (c7).
class _FollowedAreasButton extends StatelessWidget {
  const new();

  /// The page bar's height and a gap above it.
  static const double _abovePager = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > homeTabletBreakpoint;
    final label = i18n('favorite_areas');
    return Padding(
      padding: EdgeInsets.only(bottom: usesDesktopPages(width) ? _abovePager : (wide ? 24 : 0)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('areas-followed-button'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => AppNavigator.toNamed<void>(RoutePath.kFavoriteAreas).ignore(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.followArea, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: context.textStyles.t12Bold.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
