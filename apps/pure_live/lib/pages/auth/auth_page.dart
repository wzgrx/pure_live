import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Sign in, mine and user management (3.x `lib/modules/auth`).
///
/// Routes: `RoutePath.kSignIn`, `RoutePath.kMine`, `RoutePath.kUserManage`.
///
/// 3.x's cloud account ran on Firebase (email and GitHub sign-in, config
/// upload and download, a management list of users); M12 removed Firebase
/// (Google services, M12 issue 10). The three routes stay so old links
/// land somewhere: the page says the cloud account is gone and leads to
/// the syncs that replace it (WebDAV, LAN sync, backup files).
class AuthPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open(String path) => unawaited(AppNavigator.toNamed<void>(path));
    return Scaffold(
      appBar: AppBar(title: Text(i18n('auth_title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Container(
            key: const ValueKey('auth-retired'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Remix.cloud_off_line, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(i18n('auth_retired_title'), style: context.textStyles.t16Bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(i18n('auth_retired_body'), style: context.textStyles.t13.copyWith(height: 1.45)),
                const SizedBox(height: 8),
                Text(i18n('auth_retired_cloud_data'), style: context.textStyles.t12Muted.copyWith(height: 1.45)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('auth_alternatives')),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.cloud_line,
              title: i18n('webdav'),
              subtitle: i18n('auth_webdav_desc'),
              isLong: true,
              onTap: () => open(RoutePath.kWebDavPage),
            ),
            context.buildTile(
              icon: Remix.qr_scan_2_line,
              title: i18n('remote_sync'),
              subtitle: i18n('remote_sync_subtitle'),
              isLong: true,
              onTap: () => open(RoutePath.kRemoteSync),
            ),
            context.buildTile(
              icon: Remix.save_3_line,
              title: i18n('backup_recover'),
              subtitle: i18n('auth_backup_desc'),
              isLong: true,
              onTap: () => open(RoutePath.kBackup),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('auth_platform_accounts')),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.account_circle_line,
              title: i18n('third_party_auth'),
              subtitle: i18n('third_party_auth_subtitle'),
              isLong: true,
              onTap: () => open(RoutePath.kSettingsAccount),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
