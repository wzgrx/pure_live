import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The menu at the top left (3.x `MenuButton`): settings, about, history,
/// backup, and on Windows a new window.
class MenuButton extends ConsumerWidget {
  /// Creates the button.
  const new({super.key});

  static const List<String> _routes = [RoutePath.kSettings, RoutePath.kAbout, RoutePath.kHistory, RoutePath.kBackup];
  static const _newWindow = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newWindow = Platform.isWindows && watchSetting(ref, Settings.enableNewWindowPlay);
    PopupMenuItem<int> item(int value, IconData icon, String key) => PopupMenuItem(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MenuListTile(leading: Icon(icon), text: i18n(key)),
    );
    return PopupMenuButton<int>(
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      onSelected: (index) async {
        if (index == _newWindow) {
          final services = ref.read(appServicesProvider);
          try {
            await launchNewWindow(services.store, services.cipher);
          } on Object {
            AppNavigator.toast(i18n('open_new_window_failed'));
          }
          return;
        }
        await AppNavigator.toNamed<void>(_routes[index]);
      },
      itemBuilder: (context) => [
        item(0, Remix.settings_5_line, 'settings_title'),
        item(1, Remix.information_line, 'about'),
        item(2, Remix.history_line, 'history'),
        item(3, Remix.cloud_line, 'backup_recover'),
        if (newWindow) item(_newWindow, Icons.add_to_photos_outlined, 'open_new_window'),
      ],
      child: const SizedBox.square(dimension: kMinInteractiveDimension, child: Icon(Icons.menu_rounded)),
    );
  }
}

/// A row of a popup menu (3.x `MenuListTile`).
class MenuListTile extends StatelessWidget {
  /// Creates the row.
  const new({required this.leading, required this.text, this.trailing, super.key});

  /// The icon.
  final Widget? leading;

  /// The label.
  final String text;

  /// Trailing widget.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (leading case final leading?) ...[leading, const SizedBox(width: 12)],
      Text(text, style: Theme.of(context).textTheme.labelMedium),
      if (trailing case final trailing?) ...[const SizedBox(width: 24), trailing],
    ],
  );
}

/// The search menu at the top right of the phone layout (3.x
/// `CommonAppBarActions`): search, open a link, multi-view.
class CommonAppBarActions extends ConsumerWidget {
  /// Creates the actions.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiView = watchSetting(ref, Settings.enableMultiView);
    final primary = Theme.of(context).colorScheme.primary;
    final style = AppTextStyles.of(context).t14;
    PopupMenuItem<String> item(String route, IconData icon, String key) => PopupMenuItem(
      value: route,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: primary),
          const SizedBox(width: 12),
          Text(i18n(key), style: style),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: i18n('more'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          offset: const Offset(0, 10),
          position: PopupMenuPosition.under,
          onSelected: (route) =>
              route == RoutePath.kMultiview ? AppNavigator.toMultiview() : AppNavigator.toNamed<void>(route),
          itemBuilder: (context) => [
            item(RoutePath.kSearch, Remix.search_line, 'search_live'),
            item(RoutePath.kToolbox, Remix.link, 'open_link'),
            if (multiView) item(RoutePath.kMultiview, Remix.layout_grid_line, 'multiview_title'),
          ],
          child: const SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Icon(Remix.menu_search_line, size: 24),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
