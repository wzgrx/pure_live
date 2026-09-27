import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Location of the first-run wizard.
const welcomeLocation = '/welcome';

/// The first-run wizard (F-NEW-08, store.md §11): the preview is a separate
/// installation that cannot read the 3.x data, so it offers the three ways
/// to bring data in (file, WebDAV, LAN) or to start empty. Shown once.
class OnboardingPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  bool _busy = false;

  void _finish() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/follows');
    }
  }

  Future<void> _importFile() async {
    setState(() => _busy = true);
    try {
      final document = await pickBackupFile();
      if (document == null || !mounted) return;
      final report = await confirmAndRestore(context, service: ref.read(backupServiceProvider), document: document);
      if (report != null && mounted) _finish();
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(backupErrorText(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
      margin: const EdgeInsets.only(bottom: Space.s3),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : onTap,
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(Space.s6),
              children: [
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: Space.s6),
                Text('欢迎使用${S.appName} v4', style: theme.textTheme.headlineSmall),
                const SizedBox(height: Space.s3),
                const Text('预览版是单独安装的，读不到 3.x 里的数据。可以把 3.x 或其它设备上的关注和设置导入进来，也可以直接开始。'),
                const SizedBox(height: Space.s6),
                option(Icons.upload_file, '从备份文件导入', '3.x 的“备份与恢复”导出的文件，或 v4 的备份文件', _importFile),
                option(
                  Icons.cloud_outlined,
                  '从 WebDAV 导入',
                  '之前上传到坚果云、Nextcloud 等网盘的备份',
                  () => context.go('/me/backup/webdav'),
                ),
                option(
                  Icons.devices_other_outlined,
                  '从另一台设备导入',
                  '同一网络下，由另一台设备通过局域网同步发送过来',
                  () => context.go('/me/backup/lan?receive=1'),
                ),
                const SizedBox(height: Space.s3),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _busy ? null : _finish, child: const Text('跳过，直接开始')),
                ),
                const SizedBox(height: Space.s3),
                Text('以后可以在 我的 › 备份与同步 里随时导入。', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
