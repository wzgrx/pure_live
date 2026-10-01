import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/backup/backup_data.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Where a backup file comes from, in words.
String backupSourceText(RestorePreview preview) {
  if (preview.followsOnlyFile) return i18n('backup_source_follows');
  return switch (preview.version) {
    null => i18n('backup_source_flat'),
    final version when version < 4 => i18n('backup_source_v3', args: {'version': '$version'}),
    _ => i18n('backup_source_v4'),
  };
}

/// One line of the preview: `关注的直播间：12 → 15（新增 4，移除 1）`.
String restorePartText(RestorePart part) {
  final counts = i18n('backup_preview_count', args: {'current': '${part.current}', 'incoming': '${part.incoming}'});
  final detail = part.unchanged
      ? i18n('backup_preview_same')
      : i18n('backup_preview_diff', args: {'added': '${part.added}', 'removed': '${part.removed}'});
  return i18n('backup_preview_part', args: {'part': i18n(part.kind.labelKey), 'counts': counts, 'detail': detail});
}

/// Shows what restoring [fileName] changes and asks to go on; true to
/// restore.
Future<bool> confirmRestore(BuildContext context, {required String fileName, required RestorePreview preview}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final styles = dialogContext.textStyles;
      final colors = Theme.of(dialogContext).colorScheme;
      final follows = preview.scope == BackupScope.follows;
      Widget line(String text, {Color? color, IconData icon = Icons.circle, double iconSize = 6}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              height: 20,
              child: Center(
                child: Icon(icon, size: iconSize, color: color ?? colors.primary),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: styles.t13.copyWith(color: color)),
            ),
          ],
        ),
      );
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(i18n(follows ? 'recover_favorite_backup' : 'recover_backup'), style: styles.t16Bold),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            key: const ValueKey('backup-preview'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fileName, style: styles.t14SemiBold, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(backupSourceText(preview), style: styles.t12Muted),
              if (preview.followsOnlyFile)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(i18n('backup_preview_follows_file'), style: styles.t13Primary),
                ),
              const SizedBox(height: 12),
              Text(i18n('backup_preview_title'), style: styles.t13SemiBold),
              const SizedBox(height: 4),
              if (preview.settingsInFile > 0)
                line(
                  i18n(
                    'backup_preview_settings',
                    args: {'count': '${preview.settingsInFile}', 'changed': '${preview.settingsChanged}'},
                  ),
                ),
              for (final part in preview.parts) line(restorePartText(part)),
              if (preview.accounts > 0) line(i18n('backup_preview_accounts', args: {'count': '${preview.accounts}'})),
              if (preview.kept.isNotEmpty) ...[
                const SizedBox(height: 8),
                line(
                  i18n(
                    'backup_preview_kept',
                    args: {
                      'parts': [for (final kind in preview.kept) i18n(kind.labelKey)].join('、'),
                    },
                  ),
                  color: colors.onSurfaceVariant,
                  icon: Icons.check,
                  iconSize: 14,
                ),
              ],
              if (follows)
                line(
                  i18n('webdav_favorites_unchanged_hint'),
                  color: colors.onSurfaceVariant,
                  icon: Icons.check,
                  iconSize: 14,
                ),
              if (preview.skipped > 0)
                line(
                  i18n('backup_preview_skipped', args: {'count': '${preview.skipped}'}),
                  color: colors.error,
                  icon: Icons.warning_amber_rounded,
                  iconSize: 14,
                ),
              if (!preview.changesSomething)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(i18n('backup_preview_nothing'), style: styles.t13Muted),
                ),
              const SizedBox(height: 8),
              Text(i18n('backup_preview_warning'), style: styles.t12Muted),
            ],
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(i18n('cancel')),
          ),
          FilledButton(
            key: const ValueKey('backup-restore-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('backup_restore_now')),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The restore flow of both pages: [read] the file, show what it changes,
/// restore after the user agrees, say how it went. [readFailedKey] is the
/// message when the file cannot be read (a local file, a download). True
/// when something was restored.
Future<bool> restoreWithPreview(
  BuildContext context, {
  required BackupService service,
  required LiveStore store,
  required String fileName,
  required BackupScope scope,
  required Future<Map<String, Object?>> Function() read,
  required String readFailedKey,
}) async {
  final Map<String, Object?> json;
  final RestorePreview preview;
  try {
    json = await read();
  } on FormatException {
    AppNavigator.toast(i18n('backup_not_backup'));
    return false;
  } on Object catch (error, stack) {
    log('Reading the backup failed', name: 'Backup', error: error, stackTrace: stack);
    AppNavigator.toast(i18n(readFailedKey));
    return false;
  }
  try {
    preview = await previewRestore(store, json, scope);
  } on FormatException {
    AppNavigator.toast(i18n(scope == BackupScope.follows ? 'backup_no_follows' : 'backup_not_backup'));
    return false;
  }
  if (!context.mounted || !await confirmRestore(context, fileName: fileName, preview: preview)) return false;
  final follows = preview.scope == BackupScope.follows;
  try {
    await restoreBackup(service, store, json, preview.scope);
    // BackupService signals a restore already running with a StateError.
    // ignore: avoid_catching_errors
  } on StateError {
    AppNavigator.toast(i18n('backup_restore_busy'));
    return false;
  } on Object catch (error, stack) {
    log('Restoring the backup failed', name: 'Backup', error: error, stackTrace: stack);
    AppNavigator.toast(i18n(follows ? 'recover_favorite_backup_failed' : 'recover_backup_failed'));
    return false;
  }
  AppNavigator.toast(i18n(follows ? 'recover_favorite_backup_success' : 'recover_backup_success'));
  return true;
}
