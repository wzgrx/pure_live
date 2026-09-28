import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
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
        SettingAnchor(
          id: backupAnchor,
          child: ListTile(
            leading: const LiveIcon(LiveIcons.backup),
            title: Text(t.backup.backupAndRestore),
            subtitle: Text(t.backup.backupAndRestoreSubtitle),
            trailing: const LiveIcon(LiveIcons.subpage),
            onTap: () => context.go('/me/backup'),
          ),
        ),
        SettingAnchor(
          id: webDavAnchor,
          child: ListTile(
            leading: const LiveIcon(LiveIcons.cloud),
            title: const Text('WebDAV'),
            trailing: const LiveIcon(LiveIcons.subpage),
            onTap: () => context.go('/me/backup/webdav'),
          ),
        ),
        SettingAnchor(
          id: lanSyncAnchor,
          child: ListTile(
            leading: const LiveIcon(LiveIcons.lanSync),
            title: Text(t.backup.lanSync),
            trailing: const LiveIcon(LiveIcons.subpage),
            onTap: () => context.go('/me/backup/lan'),
          ),
        ),
        SettingAnchor(
          id: diagnosticsAnchor,
          child: ListTile(
            leading: const LiveIcon(LiveIcons.diagnostics),
            title: Text(t.backup.diagnostics),
            subtitle: Text(t.backup.diagnosticsSubtitle),
            trailing: const LiveIcon(LiveIcons.subpage),
            onTap: () => context.go('/me/diagnostics'),
          ),
        ),
        SettingAnchor(
          id: crashReportsAnchor,
          child: SwitchListTile(
            secondary: const LiveIcon(LiveIcons.debugLog),
            title: Text(t.backup.crashReports),
            subtitle: Text(t.backup.crashReportsSubtitle),
            value: prefs.crashReports,
            onChanged: (value) => ref.read(appPrefsProvider.notifier).setCrashReports(enabled: value),
          ),
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
  Widget build(BuildContext context, WidgetRef ref) => SettingAnchor(
    id: clipboardAnchor,
    child: SwitchListTile(
      title: Text(t.backup.clipboardRooms),
      subtitle: Text(t.backup.clipboardRoomsSubtitle),
      value: ref.watch(appPrefsProvider).clipboardRecognition,
      onChanged: (value) => ref.read(appPrefsProvider.notifier).setClipboardRecognition(enabled: value),
    ),
  );
}
