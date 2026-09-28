import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Backup and sync (spec/modules/store.md §7, product §14): export a v4 backup
/// to a file, import a v4 or 3.x backup, and the WebDAV and LAN sync pages.
/// 3.x users bring their follows into the preview this way, since a
/// separately installed preview cannot read the 3.x app's files.
class BackupPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      _toast(backupErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() async {
    final options = await showExportOptions(context);
    if (options == null) return;
    await _run(() async {
      if (await exportBackupToFile(ref.read(backupServiceProvider), options)) _toast(t.backup.saved);
    });
  }

  Future<void> _import(RestoreMode mode) => _run(() async {
    final document = await pickBackupFile();
    if (document == null || !mounted) return;
    await confirmAndRestore(context, service: ref.read(backupServiceProvider), document: document, mode: mode);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageAppBar(maxContentWidth: Sizes.readingWidth, title: Text(t.app.backup)),
    body: PageBody(
      maxContentWidth: Sizes.readingWidth,
      child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            SettingsHeader(t.backup.localFiles),
            ListTile(
              leading: const LiveIcon(LiveIcons.importFile),
              title: Text(t.backup.exportTitle),
              subtitle: Text(t.backup.exportSubtitle),
              onTap: _export,
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.download),
              title: Text(t.backup.restoreFollows),
              subtitle: Text(t.backup.restoreFollowsSubtitle),
              onTap: () => _import(RestoreMode.follows),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.restore),
              title: Text(t.backup.restoreFull),
              subtitle: Text(t.backup.restoreFullSubtitle),
              onTap: () => _import(RestoreMode.full),
            ),
            const Divider(),
            SettingsHeader(t.common.sync),
            ListTile(
              leading: const LiveIcon(LiveIcons.cloud),
              title: const Text('WebDAV'),
              subtitle: Text(t.backup.webdavSubtitle),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/backup/webdav'),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.lanSync),
              title: Text(t.backup.lanSync),
              subtitle: Text(t.backup.lanSyncSubtitle),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.go('/me/backup/lan'),
            ),
          ],
        ),
      ),
    ),
  );
}
