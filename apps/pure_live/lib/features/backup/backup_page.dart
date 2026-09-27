import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

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
      if (await exportBackupToFile(ref.read(backupServiceProvider), options)) _toast('备份已保存');
    });
  }

  Future<void> _import(RestoreMode mode) => _run(() async {
    final document = await pickBackupFile();
    if (document == null || !mounted) return;
    await confirmAndRestore(context, service: ref.read(backupServiceProvider), document: document, mode: mode);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('备份与同步')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            children: [
              if (_busy) const LinearProgressIndicator(),
              const SettingsHeader('本地文件'),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('导出备份'),
                subtitle: const Text('完整备份或仅关注；平台登录信息默认不包含，需要时用口令加密'),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('仅恢复关注'),
                subtitle: const Text('支持 v4 和 3.x 的备份文件，只导入关注和关注的分区'),
                onTap: () => _import(RestoreMode.follows),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('完整恢复'),
                subtitle: const Text('导入备份里的全部内容，备份里没有的部分保持不变'),
                onTap: () => _import(RestoreMode.full),
              ),
              const Divider(),
              const SettingsHeader('同步'),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('WebDAV'),
                subtitle: const Text('把备份上传到坚果云、Nextcloud、群晖等网盘，在其它设备上恢复'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/backup/webdav'),
              ),
              ListTile(
                leading: const Icon(Icons.devices_other_outlined),
                title: const Text('局域网同步'),
                subtitle: const Text('同一网络下的两台设备直接传输，接收方确认后才会导入'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/me/backup/lan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
