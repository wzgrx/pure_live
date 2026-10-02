import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/backup/file_browser.dart';
import 'package:pure_live/features/backup/tv_sync.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_files.dart';
import 'package:pure_live/shared/backup/backup_preview_dialog.dart';
import 'package:pure_live/shared/qr_scan.dart';

/// The page's clock, for file names (tests replace it).
final Provider<DateTime Function()> backupClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The folder backups go to when none was picked (tests replace it).
final Provider<Future<Directory> Function()> backupDefaultFolderProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultBackupFolder,
);

/// Picks a folder or a backup file (tests replace it; the app sets the
/// system pickers, else the in-app browser [showFileBrowser]).
typedef BackupPicker = Future<String?> Function(
  BuildContext context, {
  required String initial,
  required bool pickFile,
});

/// The picker of the page.
final Provider<BackupPicker> backupPickerProvider = Provider<BackupPicker>((ref) => showFileBrowser);

/// Whether "打开备份目录" shows (computers; tests replace it).
final Provider<bool> backupOpensFolderProvider = Provider<bool>(
  (ref) => Platform.isWindows || Platform.isLinux || Platform.isMacOS,
);

enum _Action { create, createFollows, restore, restoreFollows, folder, tv, file }

/// Backup and restore (3.x `lib/modules/backup`, docs/ui/compare/U.11a).
///
/// Routes: `RoutePath.kBackup`.
///
/// The ways to other devices first (the retired cloud account, WebDAV, LAN
/// sync, the TV), then the local backups in 3.x's file format
/// (`BackupService`), the backups found in the backup folder (restored
/// after a preview of what changes) and the folder. One backup action at a
/// time: the running one spins, the others grey out. The log group of 3.x
/// moved to settings (Q1, `RoutePath.kLogs`).
class BackupPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  _Action? _busy;
  String? _folder;
  bool _customFolder = false;
  List<LocalBackupFile>? _files;
  bool _filesFailed = false;

  LiveStore get _store => ref.read(storeProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadFolder());
  }

  /// The chosen folder (3.x's `backupDirectory`, imported from 3.x) or the
  /// default one, then its backups.
  Future<void> _loadFolder() async {
    final saved = _store.settings.get(Settings.backupDirectory).trim();
    final folder = saved.isNotEmpty ? saved : (await ref.read(backupDefaultFolderProvider)()).path;
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _customFolder = saved.isNotEmpty;
    });
    await _loadFiles();
  }

  Future<void> _loadFiles() async {
    final folder = _folder;
    if (folder == null) return;
    if (_filesFailed) setState(() => _files = null);
    List<LocalBackupFile> files;
    var failed = false;
    try {
      files = await listBackupFiles(Directory(folder));
    } on FileSystemException {
      files = const [];
      failed = true;
    }
    if (!mounted || folder != _folder) return;
    setState(() {
      _files = files;
      _filesFailed = failed;
    });
  }

  /// Runs one action at a time; the row shows its progress.
  Future<void> _run(_Action action, Future<void> Function() work) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _create(BackupScope scope) =>
      _run(scope == BackupScope.all ? _Action.create : _Action.createFollows, () async {
        final folder = _folder;
        if (folder == null) return;
        final follows = scope == BackupScope.follows;
        try {
          final dir = Directory(folder);
          await dir.create(recursive: true);
          final file = freeBackupFile(dir, backupFileName(scope, ref.read(backupClockProvider)()));
          final data = await exportBackup(ref.read(backupServiceProvider), _store, scope);
          await BackupService.writeFile(file, data);
          AppNavigator.toast(
            i18n(follows ? 'backup_created_follows' : 'backup_created', args: {'name': file.uri.pathSegments.last}),
          );
        } on FileSystemException catch (error, stack) {
          log('Writing the backup failed', name: 'Backup', error: error, stackTrace: stack);
          AppNavigator.toast(i18n('backup_folder_unwritable'));
        } on Object catch (error, stack) {
          log('Creating the backup failed', name: 'Backup', error: error, stackTrace: stack);
          AppNavigator.toast(i18n(follows ? 'create_favorite_backup_failed' : 'create_backup_failed'));
        }
        await _loadFiles();
      });

  Future<void> _restoreFile(LocalBackupFile entry, BackupScope scope, {_Action action = _Action.file}) =>
      _run(action, () async {
        await restoreWithPreview(
          context,
          service: ref.read(backupServiceProvider),
          store: _store,
          fileName: entry.name,
          scope: scope,
          read: () => BackupService.readFile(entry.file),
          readFailedKey: 'backup_read_failed',
        );
      });

  Future<void> _restoreOther(BackupScope scope) async {
    final folder = _folder;
    if (folder == null || _busy != null) return;
    final path = await ref.read(backupPickerProvider)(context, initial: folder, pickFile: true);
    if (path == null || !mounted) return;
    final file = File(path);
    if (!file.existsSync()) {
      AppNavigator.toast(i18n('backup_read_failed'));
      return;
    }
    final stat = file.statSync();
    await _restoreFile(
      LocalBackupFile(file: file, modified: stat.modified, size: stat.size),
      scope,
      action: scope == BackupScope.all ? _Action.restore : _Action.restoreFollows,
    );
  }

  Future<void> _delete(LocalBackupFile entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(i18n('webdav_confirm_delete'), style: const TextStyle(fontWeight: FontWeight.w600)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(i18n('backup_delete_confirm', args: {'name': entry.name})),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('backup-delete-confirm'),
              style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(i18n('webdav_delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _run(_Action.file, () async {
      try {
        await entry.file.delete();
        AppNavigator.toast(i18n('webdav_delete_success'));
      } on FileSystemException {
        AppNavigator.toast(i18n('webdav_delete_failed'));
      }
      await _loadFiles();
    });
  }

  Future<void> _chooseFolder() async {
    final folder = _folder;
    if (folder == null || _busy != null) return;
    final path = await ref.read(backupPickerProvider)(context, initial: folder, pickFile: false);
    if (path == null || !mounted) return;
    await _run(_Action.folder, () async {
      if (!await isWritableFolder(Directory(path))) {
        AppNavigator.toast(i18n('backup_folder_unwritable'));
        return;
      }
      try {
        await _store.settings.set(Settings.backupDirectory, path);
      } on Object {
        AppNavigator.toast(i18n('backup_directory_update_failed'));
        return;
      }
      if (!mounted) return;
      setState(() {
        _folder = path;
        _customFolder = true;
        _files = null;
      });
      await _loadFiles();
    });
  }

  Future<void> _resetFolder() => _run(_Action.folder, () async {
    try {
      await _store.settings.set(Settings.backupDirectory, '');
    } on Object {
      AppNavigator.toast(i18n('backup_directory_update_failed'));
      return;
    }
    await _loadFolder();
  });

  /// Sends the data to the TV at [origin]; true when it took it.
  Future<bool> _sendToTv(String origin) async {
    try {
      final backup = await ref.read(backupServiceProvider).exportAll();
      return await sendToTv(ref.read(appServicesProvider).http, origin, tvSyncDocument(backup));
    } on Object catch (error, stack) {
      log('Sending to the TV failed', name: 'Backup', error: error, stackTrace: stack);
      return false;
    }
  }

  /// "同步TV数据": the scanner on phones (3.x, Q2), the address elsewhere.
  Future<void> _syncTv() async {
    if (_busy != null) return;
    if (QrScan.available) {
      await _run(
        _Action.tv,
        () =>
            Navigator.of(context)
                .push<void>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => TvSyncScanPage(send: _sendToTv))),
      );
      return;
    }
    final origin = await askTvAddress(context);
    if (origin == null || !mounted) return;
    await _run(_Action.tv, () async {
      final sent = await _sendToTv(origin);
      AppNavigator.toast(i18n(sent ? 'sync_success' : 'backup_tv_failed'));
    });
  }

  /// Whether the row of [action] takes taps (one backup action at a time).
  bool _usable(_Action action) => _busy == null || _busy == action;

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    final files = _files;
    final opensFolder = ref.watch(backupOpensFolderProvider);
    return Scaffold(
      appBar: settingsPageAppBar(context, title: i18n('backup_recover')),
      // 3.x's bounce and classic header (P02).
      body: AppRefreshView(
        onRefresh: () async {
          await _loadFiles();
          return _filesFailed ? const AppRefreshFailure() : null;
        },
        builder: (context, physics) => SettingsPageList(
          key: const ValueKey('backup-list'),
          physics: physics,
          children: [
            SettingsGroup(
              first: true,
              title: i18n('backup_group_devices'),
              children: [
                // The retired Firebase account (U.10c X1): its explanation page.
                SettingsLinkRow(
                  key: const ValueKey('backup-cloud-account'),
                  icon: AppIcons.cloudOff,
                  title: i18n('backup_cloud_retired'),
                  subtitle: i18n('backup_cloud_retired_desc'),
                  onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kMine)),
                ),
                SettingsLinkRow(
                  key: const ValueKey('backup-webdav'),
                  icon: AppIcons.webDav,
                  title: i18n('webdav'),
                  subtitle: i18n('backup_to_webdav'),
                  onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kWebDavPage)),
                ),
                SettingsLinkRow(
                  key: const ValueKey('backup-remote-sync'),
                  icon: AppIcons.deviceSync,
                  title: i18n('remote_sync'),
                  subtitle: i18n('remote_sync_subtitle'),
                  onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRemoteSync)),
                ),
                SettingsLinkRow(
                  key: const ValueKey('backup-tv'),
                  icon: AppIcons.syncTv,
                  title: i18n('sync_tv_data'),
                  subtitle: i18n('sync_tv_data_subtitle'),
                  enabled: _usable(_Action.tv),
                  busy: _busy == _Action.tv && !QrScan.available,
                  onTap: () => unawaited(_syncTv()),
                ),
              ],
            ),
            SettingsGroup(
              title: i18n('local_backup'),
              children: [
                _action(
                  _Action.create,
                  key: 'backup-create',
                  icon: AppIcons.backupCreate,
                  title: 'create_backup',
                  subtitle: 'backup_create_subtitle',
                  onTap: () => unawaited(_create(BackupScope.all)),
                ),
                _action(
                  _Action.restore,
                  key: 'backup-restore',
                  icon: AppIcons.backupRestore,
                  title: 'recover_backup',
                  subtitle: 'backup_restore_subtitle',
                  onTap: () => unawaited(_restoreOther(BackupScope.all)),
                ),
                _action(
                  _Action.createFollows,
                  key: 'backup-create-follows',
                  icon: AppIcons.backupCreate,
                  title: 'create_favorite_backup',
                  subtitle: 'favorite_backup_scope_hint',
                  onTap: () => unawaited(_create(BackupScope.follows)),
                ),
                _action(
                  _Action.restoreFollows,
                  key: 'backup-restore-follows',
                  icon: AppIcons.backupRestore,
                  title: 'recover_favorite_backup',
                  subtitle: 'favorite_backup_scope_hint',
                  onTap: () => unawaited(_restoreOther(BackupScope.follows)),
                ),
              ],
            ),
            SettingsGroup(
              key: const ValueKey('backup-files'),
              title: files == null || files.isEmpty
                  ? i18n('backup_files_title')
                  : i18n('backup_files_count', args: {'count': '${files.length}'}),
              children: [
                if (files == null)
                  SettingsRow(icon: AppIcons.backupFile, title: i18n('refresh_loading'), busy: true)
                else if (_filesFailed)
                  SettingsRow(
                    key: const ValueKey('backup-files-error'),
                    leading: Icon(AppIcons.syncFailed, size: 22, color: Theme.of(context).colorScheme.error),
                    title: i18n('backup_files_error'),
                    subtitle: i18n('backup_files_hint'),
                    subtitleMaxLines: null,
                    below: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('backup-files-retry'),
                        onPressed: () => unawaited(_loadFiles()),
                        icon: const Icon(AppIcons.retry, size: 18),
                        label: Text(i18n('retry')),
                      ),
                    ),
                  )
                else if (files.isEmpty)
                  SettingsRow(
                    key: const ValueKey('backup-files-empty'),
                    icon: AppIcons.backupEmpty,
                    title: i18n('backup_files_empty'),
                    subtitle: i18n('backup_files_hint'),
                    subtitleMaxLines: null,
                  )
                else
                  for (final entry in files)
                    _BackupFileRow(
                      key: ValueKey('backup-file-${entry.name}'),
                      entry: entry,
                      enabled: _usable(_Action.file),
                      onOpen: () =>
                          unawaited(_restoreFile(entry, entry.followsOnly ? BackupScope.follows : BackupScope.all)),
                      onRestoreAll: () => unawaited(_restoreFile(entry, BackupScope.all)),
                      onRestoreFollows: () => unawaited(_restoreFile(entry, BackupScope.follows)),
                      onDelete: () => unawaited(_delete(entry)),
                    ),
              ],
            ),
            SettingsGroup(
              title: i18n('backup_directory'),
              children: [
                SettingsLinkRow(
                  key: const ValueKey('backup-folder'),
                  icon: AppIcons.backupFolder,
                  title: i18n(_customFolder ? 'backup_directory' : 'backup_folder_default'),
                  subtitle: folder ?? i18n('refresh_loading'),
                  subtitleMaxLines: null,
                  enabled: _usable(_Action.folder),
                  busy: _busy == _Action.folder,
                  onTap: () => unawaited(_chooseFolder()),
                ),
                if (_customFolder)
                  SettingsLinkRow(
                    key: const ValueKey('backup-folder-reset'),
                    icon: AppIcons.restoreDefault,
                    title: i18n('backup_folder_reset'),
                    enabled: _busy == null,
                    onTap: () => unawaited(_resetFolder()),
                  ),
                if (folder != null && opensFolder)
                  SettingsLinkRow(
                    key: const ValueKey('backup-open-folder'),
                    icon: AppIcons.backupOpenFolder,
                    title: i18n('backup_open_folder'),
                    onTap: () => unawaited(AppNavigator.openExternal(Uri.directory(folder))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    _Action action, {
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => SettingsLinkRow(
    key: ValueKey(key),
    icon: icon,
    title: i18n(title),
    subtitle: i18n(subtitle),
    subtitleMaxLines: null,
    enabled: _usable(action),
    busy: _busy == action,
    onTap: onTap,
  );
}

enum _FileChoice { restoreAll, restoreFollows, delete }

/// A backup in the folder: name, "time · size · kind"; a tap restores it
/// after a preview, ⋮, a right click and a long press open the same small
/// menu.
class _BackupFileRow extends StatefulWidget {
  const new({
    required this.entry,
    required this.enabled,
    required this.onOpen,
    required this.onRestoreAll,
    required this.onRestoreFollows,
    required this.onDelete,
    super.key,
  });

  final LocalBackupFile entry;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onRestoreAll;
  final VoidCallback onRestoreFollows;
  final VoidCallback onDelete;

  @override
  State<_BackupFileRow> createState() => _BackupFileRowState();
}

class _BackupFileRowState extends State<_BackupFileRow> {
  final GlobalKey _menuButton = GlobalKey();

  static bool _pointer(BuildContext context) => switch (Theme.of(context).platform) {
    TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
    _ => false,
  };

  Future<void> _menu() async {
    final anchor = _menuButton.currentContext;
    if (anchor == null || !widget.enabled) return;
    final choice = await showAppMenu<_FileChoice>(
      anchor,
      entries: [
        if (!widget.entry.followsOnly)
          AppMenuEntry(
            key: const ValueKey('backup-menu-restore-all'),
            value: _FileChoice.restoreAll,
            icon: AppIcons.backupRestore,
            label: i18n('webdav_restore_all_settings'),
          ),
        AppMenuEntry(
          key: const ValueKey('backup-menu-restore-follows'),
          value: _FileChoice.restoreFollows,
          icon: AppIcons.backupFollows,
          label: i18n('webdav_restore_favorites'),
        ),
        AppMenuEntry(
          key: const ValueKey('backup-menu-delete'),
          value: _FileChoice.delete,
          icon: AppIcons.delete,
          label: i18n('webdav_delete'),
          danger: true,
          divider: true,
        ),
      ],
    );
    switch (choice) {
      case _FileChoice.restoreAll:
        widget.onRestoreAll();
      case _FileChoice.restoreFollows:
        widget.onRestoreFollows();
      case _FileChoice.delete:
        widget.onDelete();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return GestureDetector(
      onSecondaryTap: () => unawaited(_menu()),
      onLongPress: () => unawaited(_menu()),
      child: SettingsRow(
        icon: entry.followsOnly ? AppIcons.backupFollows : AppIcons.backupFile,
        title: entry.name,
        subtitle: [
          formatFileTime(entry.modified),
          formatFileSize(entry.size),
          i18n(entry.followsOnly ? 'backup_kind_follows' : 'backup_kind_full'),
        ].join(' · '),
        // Hover hint for the mouse; on touch a long press opens the menu.
        tooltip: _pointer(context) ? i18n('backup_file_tooltip') : null,
        stackTrailing: false,
        enabled: widget.enabled,
        onTap: widget.onOpen,
        trailing: IconButton(
          key: _menuButton,
          tooltip: i18n('webdav_more_actions'),
          icon: const Icon(AppIcons.moreVertical, size: 20),
          onPressed: () => unawaited(_menu()),
        ),
      ),
    );
  }
}
