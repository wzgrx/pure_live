import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/features/popular/popular_grid.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Popular rooms (3.x `lib/modules/popular`): one tab per platform of the
/// "platform display" setting, each with its recommended rooms.
///
/// Routes: `RoutePath.kPopular`; also the home tab.
///
/// Kept from 3.x (docs/ui/compare/U.4b c1): the platform tabs sit where the
/// title would be, the first tab is the preferred platform, a changed
/// platform list keeps the platform shown, a tab loads once it settles
/// (80 ms) and the next platform is fetched 700 ms later, a changed
/// audience setting refreshes the platform shown, and a return after 15 s
/// in the background refreshes it. New: the ⌄ at the end of the tabs opens
/// "all platforms" (c2), and an empty platform list says where to choose
/// them (c3). See docs/modules/M13.1-popular.md for earlier changes.
class PopularPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends ConsumerState<PopularPage> with TickerProviderStateMixin {
  late final PopularCatalog _catalog = ref.read(popularCatalogProvider);
  TabController? _tabs;
  List<String> _ids = const [];
  Timer? _settleTimer;
  Timer? _warmTimer;

  @override
  void initState() {
    super.initState();
    HomeSignals.resumedAfterBackground.addListener(_resumed);
    _catalog.onRankingChanged = _refreshCurrent;
  }

  @override
  void dispose() {
    HomeSignals.resumedAfterBackground.removeListener(_resumed);
    if (_catalog.onRankingChanged == _refreshCurrent) _catalog.onRankingChanged = null;
    _settleTimer?.cancel();
    _warmTimer?.cancel();
    _tabs?.dispose();
    super.dispose();
  }

  String? get _current {
    final tabs = _tabs;
    if (tabs == null || _ids.isEmpty) return null;
    return _ids[tabs.index.clamp(0, _ids.length - 1)];
  }

  int get _firstCount {
    final width = MediaQuery.sizeOf(context).width;
    if (!usesDesktopPages(width)) return phonePageSize;
    return _catalog.pageSize ?? pageSizesOf(ref.read(storeProvider).settings, width).size;
  }

  void _resumed() {
    final signal = HomeSignals.resumedAfterBackground.value;
    if (widget.route.inHome && signal != null && signal.$1 == HomeMenu.popular) _refreshCurrent();
  }

  void _refreshCurrent() {
    final current = _current;
    if (!mounted || current == null) return;
    unawaited(_catalog.feedOf(current).refresh(count: _firstCount));
  }

  /// Rebuilds the tabs when the platform list changes, keeping the platform
  /// shown (3.x `_initTabController`).
  void _syncTabs(List<String> ids) {
    if (listEquals(ids, _ids) && _tabs != null) return;
    final old = _tabs;
    final oldPlatform = _catalog.currentPlatform ?? _current;
    _ids = ids;
    if (ids.isEmpty) {
      _tabs = null;
    } else {
      var index = oldPlatform == null ? -1 : ids.indexOf(oldPlatform);
      if (index < 0 && old == null) {
        index = ids.indexOf(ref.read(storeProvider).settings.get(Settings.preferPlatform));
      }
      if (index < 0) index = old == null ? 0 : old.index.clamp(0, ids.length - 1);
      final tabs = TabController(
        length: ids.length,
        vsync: this,
        initialIndex: index,
        animationDuration: pureLiveTabTransitionDuration,
      )..addListener(_tabChanged);
      _tabs = tabs;
      _catalog.currentPlatform = ids[index];
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(index));
    }
    if (old != null) {
      old.removeListener(_tabChanged);
      // The old bar lets go of it in this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _tabChanged() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    final settled = ((tabs.animation?.value ?? tabs.index.toDouble()) - tabs.index).abs() < 0.001;
    if (!settled) return;
    final platform = _ids[tabs.index];
    if (_catalog.currentPlatform == platform) return;
    _catalog.currentPlatform = platform;
    _settleTimer?.cancel();
    _warmTimer?.cancel();
    final index = tabs.index;
    _settleTimer = Timer(const Duration(milliseconds: 80), () => _load(index));
  }

  Future<void> _load(int index) async {
    if (!mounted || index >= _ids.length || _tabs?.index != index) return;
    final count = _firstCount;
    final feed = _catalog.feedOf(_ids[index]);
    await feed.open(count: count);
    if (!mounted || _tabs?.index != index || feed.rooms.isEmpty || _ids.length < 2) return;
    // Fetch the next platform while the user looks at this one (3.x).
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _tabs?.index != index) return;
      final next = index + 1 < _ids.length ? index + 1 : index - 1;
      unawaited(_catalog.feedOf(_ids[next]).open(count: count));
    });
  }

  Future<void> _pickPlatform() async {
    final tabs = _tabs;
    if (tabs == null) return;
    final picked = await showAdaptivePanel<int>(
      context,
      side: MediaQuery.sizeOf(context).width >= 600,
      builder: (context) => PlatformPicker(ids: _ids, current: tabs.index),
    );
    if (picked != null && mounted && _tabs == tabs) tabs.animateTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    _syncTabs(ids);
    final phoneTab = showsHomeBarButtons(context, inHome: widget.route.inHome);
    final tabs = _tabs;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        actions: phoneTab ? const [CommonAppBarActions()] : null,
        titleSpacing: phoneTab ? 4 : 16,
        // The platform tabs take the title's place (3.x).
        title: tabs == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: ScrollableTabBar(
                      key: const ValueKey('popular-platform-tabs'),
                      controller: tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerHeight: 0,
                      physics: const PureLiveBoundedScrollPhysics(),
                      tabs: [for (final id in ids) Tab(text: platformName(id, fallback: sites.of(id).name))],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('popular-all-platforms'),
                    tooltip: i18n('popular_all_platforms'),
                    icon: const Icon(AppIcons.dropDown, size: 22),
                    onPressed: _pickPlatform,
                  ),
                ],
              ),
      ),
      body: tabs == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: AppIcons.coverPlaceholder,
              title: i18n('popular_no_platforms'),
              subtitle: i18n('popular_no_platforms_hint'),
              buttonText: i18n('platform_display'),
              buttonIcon: AppIcons.platformSettings,
              onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas)),
            )
          : TabBarView(
              controller: tabs,
              physics: const PureLivePageScrollPhysics(),
              children: [for (final id in ids) PopularPlatformView(key: ValueKey('popular-$id'), platform: id)],
            ),
    );
  }
}

/// "All platforms" (U.4b c2): every platform of the tabs with its logo and
/// name, the current one ticked; a tap switches to it and closes the panel;
/// "平台显示" opens the settings that hide and order them. The same content
/// rises from the bottom on phones and sits on the right on wide screens.
class PlatformPicker extends StatelessWidget {
  /// Creates the picker of [ids] with [current] selected.
  const new({required this.ids, required this.current, super.key});

  /// The platforms of the tabs.
  final List<String> ids;

  /// The index of the platform shown.
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('popular-platform-picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: i18n('popular_all_platforms'),
          closeTooltip: i18n('close'),
          actions: [
            TextButton.icon(
              key: const ValueKey('popular-platform-settings'),
              onPressed: () {
                Navigator.pop(context);
                unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas));
              },
              icon: const Icon(AppIcons.platformSettings, size: 18),
              label: Text(i18n('platform_display')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            i18n('popular_all_platforms_hint', args: {'count': '${ids.length}'}),
            style: context.textStyles.t13.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = GridColumns.count(
                width: constraints.maxWidth,
                minItemWidth: 84,
                spacing: 8,
                padding: 12,
                min: 3,
                max: 6,
              );
              return GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                  mainAxisExtent: 76 + MediaQuery.textScalerOf(context).scale(13) * 1.4,
                ),
                itemCount: ids.length,
                itemBuilder: (context, index) => _PlatformTile(
                  id: ids[index],
                  selected: index == current,
                  onTap: () => Navigator.pop(context, index),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const new({required this.id, required this.selected, required this.onTap});

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('popular-platform-$id'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          selected: selected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(9), child: PlatformLogo(id, size: 36)),
                      if (selected)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            key: const ValueKey('popular-platform-selected'),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.secondaryContainer, width: 2),
                            ),
                            child: Icon(AppIcons.selected, size: 12, color: scheme.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  platformName(id, fallback: id.toUpperCase()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textStyles.t13.copyWith(
                    height: 1.4,
                    color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
