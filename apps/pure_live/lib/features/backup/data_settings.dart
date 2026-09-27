import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

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
          title: Text(t.backup.backupAndRestore),
          subtitle: Text(t.backup.backupAndRestoreSubtitle),
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
          title: Text(t.backup.lanSync),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/backup/lan'),
        ),
        ListTile(
          leading: const Icon(Icons.medical_information_outlined),
          title: Text(t.backup.diagnostics),
          subtitle: Text(t.backup.diagnosticsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/diagnostics'),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: Text(t.backup.crashReports),
          subtitle: Text(t.backup.crashReportsSubtitle),
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
    title: Text(t.backup.clipboardRooms),
    subtitle: Text(t.backup.clipboardRoomsSubtitle),
    value: ref.watch(appPrefsProvider).clipboardRecognition,
    onChanged: (value) => ref.read(appPrefsProvider.notifier).setClipboardRecognition(enabled: value),
  );
}
