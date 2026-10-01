import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/pages/tv_areas_pane.dart';
import 'package:pure_live/tv/pages/tv_favorites_pane.dart';
import 'package:pure_live/tv/pages/tv_history_pane.dart';
import 'package:pure_live/tv/pages/tv_iptv_pane.dart';
import 'package:pure_live/tv/pages/tv_popular_pane.dart';
import 'package:pure_live/tv/pages/tv_search_page.dart';
import 'package:pure_live/tv/pages/tv_settings_pane.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// The destinations of the TV side menu (pure_live_TV `TvMenuType` and its
/// mode switch), in order; [settings] sits at the bottom.
enum TvPane {
  /// Follows (the landing destination, as on pure_live_TV and 3.x).
  favorites('tv_menu_favorites', Icons.favorite_rounded),

  /// Recommended rooms per platform.
  popular('tv_menu_popular', Icons.local_fire_department_rounded),

  /// Areas per platform, followed areas first.
  areas('tv_menu_areas', Icons.grid_view_rounded),

  /// Watch history.
  history('tv_menu_history', Icons.history_rounded),

  /// Search.
  search('tv_menu_search', Icons.search_rounded),

  /// IPTV playlists and channels.
  iptv('tv_menu_iptv', Icons.live_tv_rounded),

  /// Videos (M14.3); not shown yet.
  video('tv_menu_video', Icons.movie_rounded, available: false),

  /// Music (M14.4); not shown yet.
  music('tv_menu_music', Icons.library_music_rounded, available: false),

  /// Wallpapers (M14.5); not shown yet.
  wallpaper('tv_menu_wallpaper', Icons.wallpaper_rounded, available: false),

  /// The TV settings.
  settings('tv_menu_settings', Icons.settings_rounded);

  new(this.labelKey, this.icon, {this.available = true});

  /// The label's translation key.
  final String labelKey;

  /// The icon.
  final IconData icon;

  /// Shown in the menu (the video, music and wallpaper modules come later).
  final bool available;

  /// The destinations in the menu's upper part.
  static List<TvPane> get menu => [
    for (final pane in values)
      if (pane.available && pane != settings) pane,
  ];
}

/// What a pane can ask of the TV home.
abstract interface class TvHomeHost {
  /// Puts the focus back on the side menu.
  void focusMenu();

  /// Sets what Back does inside [pane] first (search: back from the results
  /// to the field; areas: from the rooms to the areas); the handler returns
  /// whether it used the press. Null removes it.
  void setBackHandler(TvPane pane, bool Function()? handler);

  /// Whether [pane] is shown.
  bool isShown(TvPane pane);
}

/// The TV home host of the pane below (null for a page opened on its own).
class TvHomeScope extends InheritedWidget {
  /// Provides [host] to [pane]'s content.
  const new({required this.host, required this.pane, required this.shown, required super.child, super.key});

  /// The home.
  final TvHomeHost host;

  /// The pane this content is.
  final TvPane pane;

  /// Whether the pane is shown now.
  final bool shown;

  /// The scope above [context], if any.
  static TvHomeScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvHomeScope>();

  @override
  bool updateShouldNotify(TvHomeScope oldWidget) => shown != oldWidget.shown || pane != oldWidget.pane;
}

/// The TV home (pure_live_TV `HomePage`): a side menu with a clock on the
/// left and the destination on the right.
///
/// The remote:
/// - Up and Down walk the menu; OK opens the destination and moves into it
///   (one press less than pure_live_TV, where OK only switched); Right
///   enters it too, back on the item focused there last;
/// - Back steps out one level at a time: the destination's own level (if it
///   has one), then the side menu, then "press Back again to leave".
///
/// Destinations visited stay alive (pure_live_TV's keep-alive stack), so
/// coming back keeps their tab, scroll and focus.
class TvHomePage extends ConsumerStatefulWidget {
  /// Creates the home.
  const new({super.key});

  @override
  ConsumerState<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends ConsumerState<TvHomePage> with WidgetsBindingObserver implements TvHomeHost {
  TvPane _pane = TvPane.favorites;
  final Set<TvPane> _visited = {TvPane.favorites};
  final Map<TvPane, FocusNode> _menuNodes = {};
  final Map<TvPane, FocusNode> _paneNodes = {};
  final Map<TvPane, FocusNode> _memory = {};
  final Map<TvPane, bool Function()> _backHandlers = {};
  DateTime? _backPressedAt;
  DateTime? _backgroundedAt;
  Timer? _updateTimer;

  /// How long a second Back leaves the app.
  static const Duration exitWindow = Duration(seconds: 2);

  FocusNode _menuNode(TvPane pane) => _menuNodes[pane] ??= FocusNode(debugLabel: 'tv menu ${pane.name}');

  FocusNode _paneNode(TvPane pane) =>
      _paneNodes[pane] ??= FocusNode(debugLabel: 'tv pane ${pane.name}', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_remember);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _menuNode(_pane).requestFocus();
      final launch = ref.read(appServicesProvider).launch;
      if (launch.room case final room?) unawaited(openTvRoom(room));
      if (launch.isPrimary) _updateTimer = Timer(startupUpdateCheckDelay, _checkForUpdate);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_remember);
    _updateTimer?.cancel();
    for (final node in [..._menuNodes.values, ..._paneNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  void _checkForUpdate() {
    if (!mounted) return;
    unawaited(
      checkForUpdateOnStartup(
        context,
        settings: ref.read(appServicesProvider).store.settings,
        feed: ref.read(updateFeedProvider),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away == null || DateTime.now().difference(away) < HomeSignals.resumeRefreshAfter) return;
    // The phone's signal: follows refresh themselves, popular and areas
    // refresh the platform shown (3.x).
    final menu = switch (_pane) {
      TvPane.favorites => HomeMenu.favorites,
      TvPane.popular => HomeMenu.popular,
      TvPane.areas => HomeMenu.areas,
      _ => null,
    };
    if (menu == null) return;
    final previous = HomeSignals.resumedAfterBackground.value;
    HomeSignals.resumedAfterBackground.value = (menu, (previous?.$2 ?? 0) + 1);
  }

  /// Remembers the focused item of each destination.
  /// Also sends a focus that left the destination for the menu (Left on
  /// its first column, by geometry) to the selected entry, not to whichever
  /// entry happened to be level with it.
  void _remember() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return;
    final paneNode = _paneNodes[_pane];
    final inPane = paneNode != null && paneNode.hasFocus;
    final cameFromPane = _inPane;
    _inPane = inPane;
    if (inPane) {
      _memory[_pane] = primary;
      return;
    }
    final selected = _menuNode(_pane);
    if (cameFromPane && primary != selected && _menuNodes.containsValue(primary)) selected.requestFocus();
  }

  bool _inPane = false;

  @override
  void focusMenu() => _menuNode(_pane).requestFocus();

  @override
  void setBackHandler(TvPane pane, bool Function()? handler) {
    if (handler == null) {
      _backHandlers.remove(pane);
    } else {
      _backHandlers[pane] = handler;
    }
  }

  @override
  bool isShown(TvPane pane) => pane == _pane;

  /// Moves the focus into the destination: back on its last item, else on
  /// its first. False when it has nothing to focus yet.
  bool _enter() {
    final remembered = _memory[_pane];
    if (remembered != null && remembered.context != null && remembered.canRequestFocus) {
      remembered.requestFocus();
      return true;
    }
    final first = _paneNode(_pane).traversalDescendants.where((node) => node.context != null).firstOrNull;
    if (first == null) return false;
    first.requestFocus();
    return true;
  }

  void _select(TvPane pane) {
    if (pane == _pane) {
      if (pane == TvPane.favorites) HomeSignals.favoritesReselected.value++;
      _enter();
      return;
    }
    setState(() {
      _pane = pane;
      _visited.add(pane);
    });
    // The destination builds in this frame; move in once it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_enter()) _menuNode(pane).requestFocus();
    });
  }

  Future<void> _back() async {
    final handler = _backHandlers[_pane];
    if (handler != null && handler()) return;
    if (_paneNode(_pane).hasFocus) {
      focusMenu();
      return;
    }
    final now = DateTime.now();
    final last = _backPressedAt;
    if (last == null || now.difference(last) > exitWindow) {
      _backPressedAt = now;
      AppNavigator.toast(i18n('tv_press_back_again'));
      return;
    }
    _backPressedAt = null;
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('pure_live/app').invokeMethod<bool>('moveToBack');
    } on PlatformException {
      // Stay in front.
    } on MissingPluginException {
      // No activity.
    }
  }

  KeyEventResult _menuKey(TvPane pane, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    return _enter() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Widget _content(TvPane pane) => switch (pane) {
    TvPane.favorites => const TvFavoritesPane(),
    TvPane.popular => const TvPopularPane(),
    TvPane.areas => const TvAreasPane(),
    TvPane.history => const TvHistoryPane(),
    TvPane.search => const TvSearchPane(),
    TvPane.iptv => const TvIptvPane(),
    TvPane.settings => const TvSettingsPane(),
    TvPane.video ||
    TvPane.music ||
    TvPane.wallpaper => TvMessage(icon: Icons.construction_rounded, title: i18n('tv_under_construction')),
  };

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    const panes = TvPane.values;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: TvBackground(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusTraversalGroup(
                child: Container(
                  key: const ValueKey('tv-home-menu'),
                  width: scale.text(240),
                  color: palette.card.withValues(alpha: 0.55),
                  padding: EdgeInsets.symmetric(vertical: scale(28), horizontal: scale(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Clock(),
                      SizedBox(height: scale(24)),
                      Expanded(
                        child: SingleChildScrollView(
                          clipBehavior: Clip.none,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [for (final pane in TvPane.menu) _menuItem(pane)],
                          ),
                        ),
                      ),
                      _menuItem(TvPane.settings),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FocusTraversalGroup(
                  child: IndexedStack(
                    index: panes.indexOf(_pane),
                    sizing: StackFit.expand,
                    children: [
                      for (final pane in panes)
                        if (_visited.contains(pane))
                          Focus(
                            focusNode: _paneNode(pane),
                            skipTraversal: true,
                            canRequestFocus: false,
                            child: TvHomeScope(
                              host: this,
                              pane: pane,
                              shown: pane == _pane,
                              child: KeyedSubtree(key: ValueKey('tv-pane-${pane.name}'), child: _content(pane)),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(TvPane pane) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final selected = pane == _pane;
    return Padding(
      padding: EdgeInsets.only(bottom: scale(12)),
      child: TvFocusable(
        key: ValueKey('tv-menu-${pane.name}'),
        focusNode: _menuNode(pane),
        radius: 40,
        scale: 1.04,
        onTap: () => _select(pane),
        onKey: (node, event) => _menuKey(pane, event),
        builder: (context, focused) {
          final foreground = focused ? palette.onFocus : (selected ? palette.focus : palette.text);
          return Container(
            padding: EdgeInsets.symmetric(horizontal: scale.text(18), vertical: scale.text(12)),
            decoration: BoxDecoration(
              color: focused ? palette.focus : (selected ? palette.focus.withValues(alpha: 0.2) : Colors.transparent),
              borderRadius: BorderRadius.circular(scale(40)),
            ),
            child: Row(
              children: [
                Icon(pane.icon, color: foreground, size: scale.text(28)),
                SizedBox(width: scale(14)),
                Expanded(
                  child: Text(
                    i18n(pane.labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scale.style(23, weight: selected ? FontWeight.w700 : FontWeight.w500, color: foreground),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The wall clock at the top of the menu (pure_live_TV `TvDigitalClock`):
/// hours and minutes, the date below.
class _Clock extends StatefulWidget {
  const new();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    String two(int value) => value.toString().padLeft(2, '0');
    return Column(
      children: [
        Text(
          '${two(_now.hour)}:${two(_now.minute)}',
          style: scale.style(40, weight: FontWeight.w700, color: palette.text, height: 1),
        ),
        SizedBox(height: scale(6)),
        Text('${_now.year}/${two(_now.month)}/${two(_now.day)}', style: scale.style(18, color: palette.textSecondary)),
      ],
    );
  }
}
