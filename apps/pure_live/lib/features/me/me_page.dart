import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// "我的": history, recordings, multiview, accounts, backup, settings, about
/// (principles §4.1). Entries not in the preview yet say so.
class MePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    Widget later(IconData icon, String title) =>
        ListTile(enabled: false, leading: Icon(icon), title: Text(title), subtitle: const Text(S.comingSoon));
    return Scaffold(
      appBar: AppBar(title: const Text(S.me)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              later(Icons.history, S.history),
              later(Icons.fiber_manual_record_outlined, S.recordings),
              later(Icons.grid_view, S.multiview),
              later(Icons.account_circle_outlined, S.accounts),
              later(Icons.cloud_sync_outlined, S.backup),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text(S.appearance),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/appearance'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text(S.about),
                subtitle: const Text('${S.version} 4.0.0-preview.1 · ${S.previewNotice}'),
                onTap: () => showLicensePage(context: context, applicationName: S.appName),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
