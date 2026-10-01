import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The phone layout (3.x `HomeMobileView`): the page and a bottom bar; the
/// bar is hidden with one destination or none.
class HomeMobileView extends StatelessWidget {
  /// Creates the layout.
  const new({required this.menus, required this.selected, required this.onSelected, required this.body, super.key});

  /// The destinations.
  final List<HomeMenu> menus;

  /// The destination shown.
  final HomeMenu? selected;

  /// A destination was tapped.
  final ValueChanged<HomeMenu> onSelected;

  /// The page.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final index = selected == null ? 0 : menus.indexOf(selected!);
    return Scaffold(
      bottomNavigationBar: menus.length <= 1
          ? null
          : NavigationBar(
              selectedIndex: index < 0 ? 0 : index,
              onDestinationSelected: (index) => onSelected(menus[index]),
              destinations: [
                for (final menu in menus)
                  NavigationDestination(
                    icon: Icon(menu.icon),
                    selectedIcon: Icon(menu.selectedIcon),
                    label: i18n(menu.titleKey),
                  ),
              ],
            ),
      body: body,
    );
  }
}

/// The tablet and desktop layout (3.x `HomeTabletView`): a scrollable side
/// rail with the menu, multi-view, open link, search and recording centre
/// actions above the destinations.
class HomeTabletView extends ConsumerWidget {
  /// Creates the layout.
  const new({
    required this.menus,
    required this.selected,
    required this.showRecord,
    required this.onSelected,
    required this.body,
    super.key,
  });

  /// The destinations (without the recording centre).
  final List<HomeMenu> menus;

  /// The destination shown.
  final HomeMenu? selected;

  /// Whether the recording centre is among the saved menus (shown as an
  /// action here).
  final bool showRecord;

  /// A destination was tapped.
  final ValueChanged<HomeMenu> onSelected;

  /// The page.
  final Widget body;

  Widget _action({required VoidCallback onPressed, required String tooltip, required IconData icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
      icon: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiView = watchSetting(ref, Settings.enableMultiView);
    final index = selected == null ? -1 : menus.indexOf(selected!);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // The rail scrolls in short windows; its position must not
            // attach to the page's primary scroll controller.
            PrimaryScrollController.none(
              child: NavigationRail(
                groupAlignment: -1,
                scrollable: true,
                leadingAtTop: false,
                labelType: NavigationRailLabelType.all,
                leading: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(padding: EdgeInsets.all(12), child: MenuButton()),
                    if (multiView)
                      _action(
                        onPressed: AppNavigator.toMultiview,
                        tooltip: i18n('multiview_title'),
                        icon: Remix.layout_grid_line,
                      ),
                    _action(
                      onPressed: () => AppNavigator.toNamed<void>(RoutePath.kToolbox),
                      tooltip: i18n('toolbox_title'),
                      icon: Remix.link,
                    ),
                    _action(
                      onPressed: () => AppNavigator.toNamed<void>(RoutePath.kSearch),
                      tooltip: i18n('search_live'),
                      icon: CustomIcons.search,
                    ),
                    if (showRecord)
                      _action(
                        onPressed: () => AppNavigator.toNamed<void>(RoutePath.kRecordPage),
                        tooltip: i18n('record_center'),
                        icon: Remix.download_2_line,
                      ),
                  ],
                ),
                destinations: [
                  for (final menu in menus)
                    NavigationRailDestination(
                      icon: Icon(menu.icon),
                      selectedIcon: Icon(menu.selectedIcon),
                      label: Text(i18n(menu.titleKey)),
                    ),
                ],
                selectedIndex: index < 0 ? null : index,
                onDestinationSelected: (index) => onSelected(menus[index]),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: menus.isEmpty
                  ? AppStatusView(
                      type: AppStatusType.empty,
                      icon: Remix.menu_2_fill,
                      title: i18n('no_menu_title'),
                      subtitle: i18n('no_menu_subtitle'),
                    )
                  : body,
            ),
          ],
        ),
      ),
    );
  }
}
