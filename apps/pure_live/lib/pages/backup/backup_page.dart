import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/backup/backup_data.dart';
import 'package:pure_live/pages/backup/backup_files.dart';
import 'package:pure_live/pages/backup/backup_preview_dialog.dart';
import 'package:pure_live/pages/backup/tv_sync.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// The page's clock, for file names (tests replace it).
final Provider<DateTime Function()> backupClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The folder backups go to when none was picked (tests replace it).
final Provider<Future<Directory> Function()> backupDefaultFolderProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultBackupFolder,
);

/// Picks a folder or a backup file (tests replace it; the app browses in
/// app until it has a system picker, see [showFileBrowser]).
typedef BackupPicker = Future<String?> Function(
  BuildContext context, {
  required String initial,
  required bool pickFile,
});

/// The picker of the page.
final Provider<BackupPicker> backupPickerProvider = Provider<BackupPicker>((ref) => showFileBrowser);

enum _Action { create, createFollows, restore, restoreFollows, folder, tv, file }

/// Backup and restore (3.x `lib/modules/backup`).
///
/// Routes: `RoutePath.kBackup`.
///
/// Local backups in 3.x's file format (`BackupService`), the backups found
/// in the backup folder, restores with a preview of what changes, and the
/// ways to other devices: WebDAV, LAN sync and the TV.
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

  /// Runs one action at a time; the tile shows its progress.
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
          title: Text(i18n('webdav_confirm_delete')),
          content: Text(i18n('backup_delete_confirm', args: {'name': entry.name})),
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

  Future<void> _syncTv() async {
    if (_busy != null) return;
    final origin = await askTvAddress(context);
    if (origin == null || !mounted) return;
    await _run(_Action.tv, () async {
      var sent = false;
      try {
        final backup = await ref.read(backupServiceProvider).exportAll();
        sent = await sendToTv(ref.read(appServicesProvider).http, origin, tvSyncDocument(backup));
      } on Object catch (error, stack) {
        log('Sending to the TV failed', name: 'Backup', error: error, stackTrace: stack);
      }
      AppNavigator.toast(i18n(sent ? 'sync_success' : 'backup_tv_failed'));
    });
  }

  Widget? _progress(_Action action) => _busy == action
      ? SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: i18n('refresh_loading')),
        )
      : null;

  VoidCallback? _when(VoidCallback action) => _busy == null ? action : null;

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('backup_recover'))),
      body: RefreshIndicator(
        onRefresh: _loadFiles,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            context.buildGroupTitle(i18n('local_backup')),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.file_download_line,
                title: i18n('create_backup'),
                subtitle: i18n('backup_create_subtitle'),
                isLong: true,
                trailing: _progress(_Action.create),
                onTap: _when(() => unawaited(_create(BackupScope.all))),
              ),
              context.buildTile(
                icon: Remix.heart_add_line,
                title: i18n('create_favorite_backup'),
                subtitle: i18n('favorite_backup_scope_hint'),
                isLong: true,
                trailing: _progress(_Action.createFollows),
                onTap: _when(() => unawaited(_create(BackupScope.follows))),
              ),
              context.buildTile(
                icon: Remix.file_upload_line,
                title: i18n('recover_backup'),
                subtitle: i18n('backup_restore_subtitle'),
                isLong: true,
                trailing: _progress(_Action.restore),
                onTap: _when(() => unawaited(_restoreOther(BackupScope.all))),
              ),
              context.buildTile(
                icon: Remix.heart_pulse_line,
                title: i18n('recover_favorite_backup'),
                subtitle: i18n('favorite_backup_scope_hint'),
                isLong: true,
                trailing: _progress(_Action.restoreFollows),
                onTap: _when(() => unawaited(_restoreOther(BackupScope.follows))),
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('backup_directory')),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.folder_open_line,
                title: i18n(_customFolder ? 'backup_directory' : 'backup_folder_default'),
                subtitle: folder ?? i18n('refresh_loading'),
                isLong: true,
                trailing: _progress(_Action.folder),
                onTap: _when(() => unawaited(_chooseFolder())),
              ),
              if (_customFolder)
                context.buildTile(
                  icon: Remix.arrow_go_back_line,
                  title: i18n('backup_folder_reset'),
                  onTap: _when(() => unawaited(_resetFolder())),
                ),
              if (folder != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
                context.buildTile(
                  icon: Remix.external_link_line,
                  title: i18n('backup_open_folder'),
                  onTap: () => unawaited(AppNavigator.openExternal(Uri.directory(folder))),
                ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('backup_files_title')),
            _filesCard(context),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('cloud_backup')),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.cloud_line,
                title: i18n('webdav'),
                subtitle: i18n('backup_to_webdav'),
                isLong: true,
                onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kWebDavPage)),
              ),
              context.buildTile(
                icon: Remix.qr_scan_2_line,
                title: i18n('remote_sync'),
                subtitle: i18n('remote_sync_subtitle'),
                onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRemoteSync)),
              ),
              context.buildTile(
                icon: Remix.tv_2_line,
                title: i18n('sync_tv_data'),
                subtitle: i18n('sync_tv_data_subtitle'),
                isLong: true,
                trailing: _progress(_Action.tv),
                onTap: _when(() => unawaited(_syncTv())),
              ),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _filesCard(BuildContext context) {
    final files = _files;
    if (files == null) {
      return context.buildModernCard([
        CardTile(
          child: ListTile(
            title: Text(i18n('refresh_loading')),
            leading: const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ]);
    }
    if (_filesFailed || files.isEmpty) {
      return context.buildModernCard([
        CardTile(
          child: ListTile(
            key: const ValueKey('backup-files-empty'),
            leading: Icon(_filesFailed ? Icons.error_outline : Icons.inventory_2_outlined),
            title: Text(i18n(_filesFailed ? 'backup_files_error' : 'backup_files_empty')),
            subtitle: Text(i18n('backup_files_hint')),
          ),
        ),
      ]);
    }
    return context.buildModernCard([
      for (final entry in files)
        CardTile(
          child: ListTile(
            key: ValueKey('backup-file-${entry.name}'),
            leading: Icon(
              entry.followsOnly ? Remix.heart_line : Remix.file_text_line,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                formatFileTime(entry.modified),
                formatFileSize(entry.size),
                i18n(entry.followsOnly ? 'backup_kind_follows' : 'backup_kind_full'),
              ].join(' · '),
            ),
            trailing: _busy == _Action.file
                ? null
                : PopupMenuButton<int>(
                    tooltip: i18n('webdav_more_actions'),
                    onSelected: (value) => switch (value) {
                      0 => unawaited(_restoreFile(entry, BackupScope.all)),
                      1 => unawaited(_restoreFile(entry, BackupScope.follows)),
                      _ => unawaited(_delete(entry)),
                    },
                    itemBuilder: (_) => [
                      if (!entry.followsOnly) PopupMenuItem(value: 0, child: Text(i18n('webdav_restore_all_settings'))),
                      PopupMenuItem(value: 1, child: Text(i18n('webdav_restore_favorites'))),
                      PopupMenuItem(value: 2, child: Text(i18n('webdav_delete'))),
                    ],
                  ),
            onTap: _when(
              () => unawaited(_restoreFile(entry, entry.followsOnly ? BackupScope.follows : BackupScope.all)),
            ),
          ),
        ),
    ]);
  }
}
