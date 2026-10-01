import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/popular/popular_catalog.dart';
import 'package:pure_live/pages/popular/popular_grid.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Popular rooms (3.x `lib/modules/popular`): one tab per platform of the
/// "platform display" setting, each with its recommended rooms.
///
/// Routes: `RoutePath.kPopular`; also the home tab.
///
/// Kept from 3.x: the first tab is the preferred platform, a changed
/// platform list keeps the platform shown, a tab loads once it settles
/// (80 ms) and the next platform is fetched 700 ms later, a changed
/// audience setting refreshes the platform shown, and a return after 15 s
/// in the background refreshes it. See docs/modules/M13.1-popular.md for
/// what changed.
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
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PlatformSheet(ids: _ids, current: tabs.index),
    );
    if (picked != null && mounted && _tabs == tabs) tabs.animateTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    _syncTabs(ids);
    final phoneTab = widget.route.inHome && MediaQuery.sizeOf(context).width <= homeTabletBreakpoint;
    final tabs = _tabs;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        actions: phoneTab ? const [CommonAppBarActions()] : null,
        title: Text(i18n('popular_title')),
        bottom: tabs == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: Row(
                  children: [
                    Expanded(
                      child: ScrollableTabBar(
                        key: const ValueKey('popular-platform-tabs'),
                        controller: tabs,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        physics: const PureLiveBoundedScrollPhysics(),
                        tabs: [for (final id in ids) Tab(text: platformName(id, fallback: sites.of(id).name))],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('popular-all-platforms'),
                      tooltip: i18n('popular_all_platforms'),
                      icon: const Icon(Icons.apps_rounded),
                      onPressed: _pickPlatform,
                    ),
                  ],
                ),
              ),
      ),
      body: tabs == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: Icons.live_tv_rounded,
              title: i18n('popular_no_platforms'),
              subtitle: i18n('popular_no_platforms_hint'),
              buttonText: i18n('platform_display'),
              onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas)),
            )
          : TabBarView(
              controller: tabs,
              physics: const PureLiveBoundedScrollPhysics(),
              children: [for (final id in ids) PopularPlatformView(key: ValueKey('popular-$id'), platform: id)],
            ),
    );
  }
}

/// Every platform at a glance, to jump to one of many tabs (new).
class _PlatformSheet extends StatelessWidget {
  const new({required this.ids, required this.current});

  final List<String> ids;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(i18n('popular_all_platforms'), style: context.textStyles.t16Medium)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas));
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(i18n('platform_display')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, id) in ids.indexed)
                    ChoiceChip(
                      key: ValueKey('popular-platform-$id'),
                      avatar: PlatformLogo(id, size: 20),
                      label: Text(platformName(id, fallback: id.toUpperCase())),
                      selected: index == current,
                      selectedColor: theme.colorScheme.primaryContainer,
                      onSelected: (_) => Navigator.pop(context, index),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
