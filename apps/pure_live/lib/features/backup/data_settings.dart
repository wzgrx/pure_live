import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_live_app/core/app_prefs.dart';

/// The 数据与同步 entries of the settings (principles §4.4): backup, WebDAV,
/// LAN sync, diagnostics and the crash prompt (off by default).
class DataSyncTiles extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.save_outlined),
          title: const Text('备份与恢复'),
          subtitle: const Text('导出或导入备份文件，支持 3.x 的备份'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/backup'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('WebDAV'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/backup/webdav'),
        ),
        ListTile(
          leading: const Icon(Icons.devices_other_outlined),
          title: const Text('局域网同步'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/backup/lan'),
        ),
        ListTile(
          leading: const Icon(Icons.medical_information_outlined),
          title: const Text('诊断与日志'),
          subtitle: const Text('导出诊断包，查看最近的日志'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/diagnostics'),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text('崩溃报告'),
          subtitle: const Text('出错后，下次启动时提示导出诊断包；不会自动上传'),
          value: prefs.crashReports,
          onChanged: (value) => ref.read(appPrefsProvider.notifier).setCrashReports(enabled: value),
        ),
      ],
    );
  }
}

/// 剪贴板识别 (F-SHR-02): look for share codes and room links when the app
/// returns to the foreground.
class ClipboardRecognitionTile extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    title: const Text('识别剪贴板里的直播间'),
    subtitle: const Text('回到应用时，识别复制的分享口令或直播间链接并询问是否打开'),
    value: ref.watch(appPrefsProvider).clipboardRecognition,
    onChanged: (value) => ref.read(appPrefsProvider.notifier).setClipboardRecognition(enabled: value),
  );
}
