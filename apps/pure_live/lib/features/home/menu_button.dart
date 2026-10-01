import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The entries of the app menu ([MenuButton]) in their order (U.3a c3: the
/// watch history moved to "more").
enum AppMenuItem {
  /// Settings.
  settings(AppIcons.settings, 'settings_title'),

  /// About.
  about(AppIcons.about, 'about'),

  /// Backup and restore.
  backup(AppIcons.backup, 'backup_recover'),

  /// An independent player window (a desktop that opens windows, with the
  /// setting on; U.13 c12).
  newWindow(AppIcons.newPlayerWindow, 'open_new_window');

  new(this.icon, this.labelKey);

  /// The icon.
  final IconData icon;

  /// The label's translation key.
  final String labelKey;
}

/// The app menu's entries; [newWindow] where the desktop opens windows and
/// the setting "新建独立播放窗口" is on (U.13 c12).
List<AppMenuItem> appMenuItems({required bool newWindow}) => [
  AppMenuItem.settings,
  AppMenuItem.about,
  AppMenuItem.backup,
  if (newWindow) AppMenuItem.newWindow,
];

/// The menu at the top left of the phone tabs and at the top of the rail
/// (3.x `MenuButton`, its icon kept): settings, about, backup, and on
/// desktops a new player window; the small menu of U.2f (U.3a c2).
class MenuButton extends ConsumerWidget {
  /// Creates the button.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newWindow = DesktopWindow.canOpenNewWindow && watchSetting(ref, Settings.enableNewWindowPlay);
    return AppMenuButton<AppMenuItem>(
      key: const ValueKey('home-menu'),
      tooltip: i18n('menu'),
      icon: const Icon(AppIcons.appMenu),
      entries: () => [
        for (final item in appMenuItems(newWindow: newWindow))
          AppMenuEntry(
            key: ValueKey('home-menu-${item.name}'),
            value: item,
            icon: item.icon,
            label: i18n(item.labelKey),
          ),
      ],
      onSelected: (item) => unawaited(_run(ref, item)),
    );
  }

  static Future<void> _run(WidgetRef ref, AppMenuItem item) async {
    switch (item) {
      case AppMenuItem.settings:
        await AppNavigator.toNamed<void>(RoutePath.kSettings);
      case AppMenuItem.about:
        await AppNavigator.toNamed<void>(RoutePath.kAbout);
      case AppMenuItem.backup:
        await AppNavigator.toNamed<void>(RoutePath.kBackup);
      case AppMenuItem.newWindow:
        // A new home window over the same data (U.13 c14).
        await DesktopWindow.openNewWindow();
    }
  }
}

/// The ways to find a room that every home layout offers, in their order
/// (U.3a c4, U.3b c4): search on its own button, the others in "more" on
/// phones; all four as buttons on the rail.
enum HomeAction {
  /// Search rooms.
  search(AppIcons.search, 'search_live'),

  /// The watch history (U.5c Z1: "观看记录").
  history(AppIcons.watchHistory, 'watch_history'),

  /// Open a shared link (U.3a c5: "链接解析" everywhere).
  openLink(AppIcons.openLink, 'toolbox_title'),

  /// Multi-view (when the setting is on).
  multiview(AppIcons.multiview, 'multiview_title');

  new(this.icon, this.labelKey);

  /// The icon.
  final IconData icon;

  /// The label's translation key.
  final String labelKey;

  /// Opens its page.
  Future<void> run() => switch (this) {
    HomeAction.search => AppNavigator.toNamed<void>(RoutePath.kSearch),
    HomeAction.history => AppNavigator.toNamed<void>(RoutePath.kHistory),
    HomeAction.openLink => AppNavigator.toNamed<void>(RoutePath.kToolbox),
    HomeAction.multiview => AppNavigator.toMultiview(),
  };
}

/// The home actions shown with [multiView] on or off.
List<HomeAction> homeActions({required bool multiView}) => [
  for (final action in HomeAction.values)
    if (action != HomeAction.multiview || multiView) action,
];

/// The buttons at the top right of the phone tabs: search in one tap and
/// "more" with the watch history, the link parser and multi-view (U.3a c4;
/// 3.x `CommonAppBarActions` had one search menu).
class CommonAppBarActions extends ConsumerWidget {
  /// Creates the buttons.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiView = watchSetting(ref, Settings.enableMultiView);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('home-search'),
          tooltip: i18n(HomeAction.search.labelKey),
          onPressed: () => unawaited(HomeAction.search.run()),
          icon: const Icon(AppIcons.search),
        ),
        AppMenuButton<HomeAction>(
          key: const ValueKey('home-more'),
          tooltip: i18n('more'),
          icon: const Icon(AppIcons.more),
          entries: () => [
            for (final action in homeActions(multiView: multiView))
              if (action != HomeAction.search)
                AppMenuEntry(
                  key: ValueKey('home-more-${action.name}'),
                  value: action,
                  icon: action.icon,
                  label: i18n(action.labelKey),
                ),
          ],
          onSelected: (action) => unawaited(action.run()),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
