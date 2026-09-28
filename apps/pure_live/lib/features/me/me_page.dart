import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// "我的": history, recordings, multiview, accounts, backup, settings, about
/// (principles §4.1). Entries not in the preview yet say so.
class MePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(maxContentWidth: Sizes.readingWidth, title: Text(t.app.tabs.me)),
      body: PageBody(
        maxContentWidth: Sizes.readingWidth,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(t.app.history),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/history'),
            ),
            ListTile(
              leading: const Icon(Icons.fiber_manual_record_outlined),
              title: Text(t.app.recordings),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/recordings'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(t.app.multiview),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/multiview'),
            ),
            ListTile(
              leading: const Icon(Icons.live_tv_outlined),
              title: Text(t.iptv.title),
              subtitle: Text(t.me.iptvSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(iptvLocation),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(t.app.accounts),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/accounts'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(t.app.backup),
              subtitle: Text(t.me.backupSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/backup'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(t.app.settings),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/settings'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t.app.about),
              subtitle: Text(t.me.aboutSubtitle(version: appVersion)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/about'),
            ),
          ],
        ),
      ),
    );
  }
}
