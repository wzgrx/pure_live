import 'package:flutter/widgets.dart';
import 'package:live_ui/live_ui.dart';

/// The home destinations (3.x `HomeMenu`); [id] is what the `savedMenuIds`
/// setting stores.
enum HomeMenu {
  /// Follows.
  favorites('favorites', 'favorites_title', AppIcons.homeFavorites, AppIcons.homeFavoritesSelected),

  /// Popular.
  popular('popular', 'popular_title', AppIcons.homePopular, AppIcons.homePopularSelected),

  /// Areas (three shapes, U.3a c7).
  areas('areas', 'areas_title', AppIcons.homeAreas, AppIcons.homeAreasSelected),

  /// Recording centre.
  record('record', 'record_center', AppIcons.homeRecord, AppIcons.homeRecordSelected);

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

/// Widths from this up use the side rail (Android's medium window class,
/// docs/T07/T07a/T07a.5 c6; 3.x switched above 680).
const double homeTabletBreakpoint = 600;

/// Whether a home of [width] uses the side rail ([homeTabletBreakpoint]).
bool isHomeRailWidth(double width) => width >= homeTabletBreakpoint;

/// The destinations shown for [saved]: the bottom bar and the side rail
/// show the same ones, the recording centre included (U.3b c3; 3.x made it
/// a button on the rail that covered the window). Nothing usable saved
/// shows them all (3.x showed an empty page on the rail).
List<HomeMenu> visibleHomeMenus(Iterable<String> saved) {
  final menus = HomeMenu.fromIds(saved);
  return menus.isEmpty ? HomeMenu.values : menus;
}

/// Tells the home tabs which layout the shell chose (the shell decides from
/// its own width; the tabs used to read the whole screen, 3.x `Get.width`).
class HomeLayoutScope extends InheritedWidget {
  /// Marks [child] as laid out with the bottom bar ([phone]) or the rail.
  const new({required this.phone, required super.child, super.key});

  /// Whether the bottom bar layout is used.
  final bool phone;

  /// The scope above [context], or null outside the home shell.
  static HomeLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeLayoutScope>();

  @override
  bool updateShouldNotify(HomeLayoutScope oldWidget) => oldWidget.phone != phone;
}

/// Whether a page shows the home buttons in its bar (menu at the left,
/// search and more at the right): only as a home tab ([inHome]) of the
/// phone layout; on the rail the rail has them (3.x).
bool showsHomeBarButtons(BuildContext context, {required bool inHome}) {
  if (!inHome) return false;
  return HomeLayoutScope.maybeOf(context)?.phone ?? !isHomeRailWidth(MediaQuery.sizeOf(context).width);
}

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
