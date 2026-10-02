import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// "云端账号": where 3.x's sign in, mine and user management lead now
/// (3.x `lib/modules/auth`, docs/A-界面设计/A12-账号和数据界面/A12.3-云账号停用说明).
///
/// Routes: `RoutePath.kSignIn`, `RoutePath.kMine`, `RoutePath.kUserManage`.
///
/// 3.x's cloud account ran on Firebase (email and GitHub sign-in, config
/// upload and download, a management list of users); M12 removed Firebase
/// (Google services, M12 issue 10) and it does not come back. The three
/// routes stay so old links land somewhere: the page says the cloud account
/// is gone, how to move an old cloud config, and leads to the syncs that
/// replace it (WebDav, device sync, backup files) and to the platform
/// accounts, which are a different thing.
class AuthPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void open(String path) => unawaited(AppNavigator.toNamed<void>(path));
    final children = <Widget>[
      Container(
        key: const ValueKey('auth-retired'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.cloudOff, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(i18n('auth_retired_title'), style: context.textStyles.t16.emphasis)),
              ],
            ),
            const SizedBox(height: 12),
            Text(i18n('auth_retired_body'), style: context.textStyles.t14.copyWith(height: 1.55)),
            const SizedBox(height: 8),
            Text(
              i18n('auth_retired_cloud_data'),
              style: context.textStyles.t13.copyWith(color: scheme.onSurfaceVariant, height: 1.55),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      SettingsGroup(
        title: i18n('auth_alternatives'),
        children: [
          SettingsLinkRow(
            key: const ValueKey('auth-webdav'),
            icon: AppIcons.webDav,
            title: i18n('webdav'),
            subtitle: i18n('auth_webdav_desc'),
            subtitleMaxLines: null,
            onTap: () => open(RoutePath.kWebDavPage),
          ),
          SettingsLinkRow(
            key: const ValueKey('auth-device-sync'),
            icon: AppIcons.deviceSync,
            title: i18n('remote_sync'),
            subtitle: i18n('remote_sync_subtitle'),
            subtitleMaxLines: null,
            onTap: () => open(RoutePath.kRemoteSync),
          ),
          SettingsLinkRow(
            key: const ValueKey('auth-backup'),
            icon: AppIcons.backupFiles,
            title: i18n('backup_recover'),
            subtitle: i18n('auth_backup_desc'),
            subtitleMaxLines: null,
            onTap: () => open(RoutePath.kBackup),
          ),
        ],
      ),
      // X2 A: old users mix up the two kinds of account.
      SettingsGroup(
        title: i18n('auth_platform_accounts'),
        children: [
          SettingsLinkRow(
            key: const ValueKey('auth-platform-accounts'),
            icon: AppIcons.platformAccounts,
            title: i18n('account_title'),
            subtitle: i18n('auth_platform_accounts_desc'),
            subtitleMaxLines: null,
            onTap: () => open(RoutePath.kSettingsAccount),
          ),
        ],
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(i18n('auth_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          for (final child in children)
            ReadableContent(
              child: SizedBox(width: double.infinity, child: child),
            ),
        ],
      ),
    );
  }
}
