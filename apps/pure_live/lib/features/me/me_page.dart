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
              leading: const LiveIcon(LiveIcons.history),
              title: Text(t.app.history),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/history'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.recordingCenter),
              title: Text(t.app.recordings),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/recordings'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.multiview),
              title: Text(t.app.multiview),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.push('/multiview'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.liveTv),
              title: Text(t.iptv.title),
              subtitle: Text(t.me.iptvSubtitle),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.push(iptvLocation),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.accounts),
              title: Text(t.app.accounts),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/accounts'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.data),
              title: Text(t.app.backup),
              subtitle: Text(t.me.backupSubtitle),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/backup'),
            ),
            const Divider(),
            ListTile(
              leading: const LiveIcon(LiveIcons.settings),
              title: Text(t.app.settings),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/settings'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.info),
              title: Text(t.app.about),
              subtitle: Text(t.me.aboutSubtitle(version: appVersion)),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/about'),
            ),
          ],
        ),
      ),
    );
  }
}
