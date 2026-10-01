import 'package:flutter/widgets.dart';
import 'package:live_ui/live_ui.dart';

/// The home destinations (3.x `HomeMenu`); [id] is what the `savedMenuIds`
/// setting stores.
enum HomeMenu {
  /// Follows.
  favorites('favorites', 'favorites_title', Remix.heart_3_line, Remix.heart_3_fill),

  /// Popular.
  popular('popular', 'popular_title', Remix.fire_line, Remix.fire_fill),

  /// Areas.
  areas('areas', 'areas_title', Remix.apps_2_line, Remix.apps_2_fill),

  /// Recording centre.
  record('record', 'record_center', Remix.download_2_line, Remix.download_2_fill);

  new(this.id, this.titleKey, this.icon, this.selectedIcon);

  /// The stored id.
  final String id;

  /// The label's translation key.
  final String titleKey;

  /// The icon.
  final IconData icon;

  /// The icon when selected.
  final IconData selectedIcon;

  /// The menu of [id], or null.
  static HomeMenu? fromId(String id) => values.where((menu) => menu.id == id).firstOrNull;

  /// The menus of [ids] in their order, unknown and repeated ids dropped.
  static List<HomeMenu> fromIds(Iterable<String> ids) => [for (final menu in ids.map(fromId).nonNulls.toSet()) menu];
}

/// Widths above this use the side rail (3.x `Get.width > 680`).
const double homeTabletBreakpoint = 680;

/// The destinations shown for [saved] at [tablet] width: the rail leaves
/// out the recording centre, which it offers as an action instead (3.x).
List<HomeMenu> visibleHomeMenus(Iterable<String> saved, {required bool tablet}) => [
  for (final menu in HomeMenu.fromIds(saved))
    if (!tablet || menu != HomeMenu.record) menu,
];

/// Signals from the home shell to its pages (3.x reached the pages'
/// controllers through GetX).
abstract final class HomeSignals {
  /// Bumped when the follows tab is selected again (3.x refreshed the
  /// follows; the follows page, M13, listens).
  static final ValueNotifier<int> favoritesReselected = ValueNotifier(0);

  /// The menu shown when the app came back after at least
  /// [resumeRefreshAfter] in the background (3.x refreshed popular and
  /// areas; the pages, M13, listen).
  static final ValueNotifier<(HomeMenu, int)?> resumedAfterBackground = ValueNotifier(null);

  /// How long the app must have been away before a resume refreshes.
  static const Duration resumeRefreshAfter = Duration(seconds: 15);
}
