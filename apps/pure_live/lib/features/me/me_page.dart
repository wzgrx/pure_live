import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// "我的": history, recordings, multiview, accounts, backup, settings, about
/// (principles §4.1). Entries not in the preview yet say so.
class MePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.me)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text(S.history),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/history'),
              ),
              ListTile(
                leading: const Icon(Icons.fiber_manual_record_outlined),
                title: const Text(S.recordings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/recordings'),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text(S.multiview),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/multiview'),
              ),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text(S.accounts),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/accounts'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text(S.backup),
                subtitle: const Text('备份文件、WebDAV、局域网同步；可以导入 3.x 的备份'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/backup'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text(S.settings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/settings'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text(S.about),
                subtitle: const Text('${S.version} $appVersion · 更新、开源许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/about'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
