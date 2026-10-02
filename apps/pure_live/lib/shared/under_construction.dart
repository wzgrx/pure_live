import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Title keys of the pages (3.x's page titles).
const Map<String, String> routeTitleKeys = {
  RoutePath.kFavorite: 'favorites_title',
  RoutePath.kPopular: 'popular_title',
  RoutePath.kAreas: 'areas_title',
  RoutePath.kAreaRooms: 'areas_title',
  RoutePath.kFavoriteAreas: 'favorite_areas',
  RoutePath.kSettings: 'settings_title',
  RoutePath.kHistory: 'history',
  RoutePath.kSearch: 'search_live',
  RoutePath.kWebSearch: 'web_search',
  RoutePath.kBackup: 'backup_recover',
  RoutePath.kAbout: 'about',
  RoutePath.kVersionHistory: 'version',
  RoutePath.kMultiview: 'multiview_title',
  RoutePath.kSettingsAccount: 'platform_settings',
  RoutePath.kBiliBiliWebLogin: 'bilibili_login',
  RoutePath.kBiliBiliQRLogin: 'qrcode_login',
  RoutePath.kSettingsDanmuShield: 'block_list',
  RoutePath.kSettingsHotAreas: 'platform_display',
  RoutePath.kToolbox: 'toolbox_title',
  RoutePath.kWebDavPage: 'webdav',
  RoutePath.kSplash: 'welcome_use',
  RoutePath.kVersionPage: 'check_update',
  RoutePath.kRecordPage: 'record_center',
  RoutePath.kRecordSettings: 'record_settings',
  RoutePath.kSettingsTags: 'tag_management',
  RoutePath.kRemoteSync: 'remote_sync',
};

/// The placeholder of a page not rebuilt yet (M13): its title, the route
/// and the arguments it got, so navigation can be checked before the page
/// exists. Home tabs keep 3.x's app bar on phones.
class UnderConstruction extends StatelessWidget {
  /// Creates the placeholder.
  const new({required this.route, super.key});

  /// The route.
  final RouteArgs route;

  /// A short description of [arguments].
  static String describe(Object? arguments) => switch (arguments) {
    null => '',
    final LiveRoom room => '${room.platform} ${room.roomId} ${room.nick}'.trim(),
    final LiveArea area => '${area.platform} ${area.areaName}'.trim(),
    final List<Object?> list => list.map(describe).where((text) => text.isNotEmpty).join(' / '),
    final LiveSite site => site.name,
    _ => '$arguments',
  };

  @override
  Widget build(BuildContext context) {
    final key = routeTitleKeys[route.path];
    final phoneTab = showsHomeBarButtons(context, inHome: route.inHome);
    final detail = describe(route.arguments);
    final building = currentStrings?.language == AppLanguage.en ? 'Under construction' : '建设中';
    return Scaffold(
      appBar: AppBar(
        centerTitle: route.inHome && centredPageTitle,
        automaticallyImplyLeading: !route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        actions: phoneTab ? const [CommonAppBarActions()] : null,
        title: Text(key == null ? route.path : i18n(key)),
      ),
      body: AppStatusView(
        type: AppStatusType.empty,
        title: building,
        subtitle: [route.path, if (detail.isNotEmpty) detail].join('\n'),
      ),
    );
  }
}
