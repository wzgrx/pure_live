import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/web_dav/web_dav_client.dart';
import 'package:pure_live/features/web_dav/web_dav_config_dialog.dart';
import 'package:pure_live/features/web_dav/web_dav_help.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_files.dart';
import 'package:pure_live/shared/backup/backup_preview_dialog.dart';

/// The HTTP client of the WebDAV calls (tests replace it).
final Provider<LiveHttp> webDavHttpProvider = Provider<LiveHttp>((ref) => ref.watch(appServicesProvider).http);

/// The page's clock, for file names (tests replace it).
final Provider<DateTime Function()> webDavClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

enum _Menu { uploadFollows, help }

enum _FileChoice { restoreAll, restoreFollows, delete }

/// WebDAV (3.x `lib/modules/web_dav`, docs/ui/compare/U.11b).
///
/// Routes: `RoutePath.kWebDavPage`.
///
/// The servers (`LiveStore.webdav`, passwords sealed, in the drawer on the
/// right), browsing the current server's folders, uploading a full or
/// follows-only backup to the open folder, restoring a file after a preview
/// (a tap on it), deleting. Back leaves the page from any folder (3.x, R4).
class WebDavPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends ConsumerState<WebDavPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final ScrollController _crumbs = ScrollController();
  List<WebDavConfig>? _configs;
  WebDavConfig? _current;
  WebDavClient? _client;
  List<String> _dir = const [];
  List<WebDavEntry>? _entries;
  Object? _error;
  bool _savedInvalid = false;
  bool _configBusy = false;

  /// The running file action's label key (upload, restore, delete).
  String? _busy;
  int _epoch = 0;

  LiveStore get _store => ref.read(storeProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfigs());
  }

  @override
  void dispose() {
    _epoch++;
    _crumbs.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    final configs = await _store.webdav.all();
    final current = await _store.webdav.current();
    if (!mounted) return;
    setState(() => _configs = configs);
    _use(current);
  }

  /// Makes [config] the shown server and lists its base folder.
  void _use(WebDavConfig? config) {
    _epoch++;
    final valid = config != null && WebDavConfig.isValidAddress(config.address);
    setState(() {
      _current = config;
      _savedInvalid = config != null && !valid;
      _client = valid ? WebDavClient(ref.read(webDavHttpProvider), config) : null;
      _dir = const [];
      _entries = null;
      _error = null;
    });
    if (valid) unawaited(_load());
  }

  /// Lists the folder; [keepRows] leaves the rows on screen meanwhile (a
  /// pull, whose header shows the progress).
  Future<void> _load({bool keepRows = false}) async {
    final client = _client;
    if (client == null) return;
    final epoch = ++_epoch;
    final dir = _dir;
    setState(() {
      if (!keepRows) _entries = null;
      _error = null;
    });
    try {
      final entries = await client.list(dir);
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        if (a.isDir) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        final at = a.modified;
        final bt = b.modified;
        if (at == null || bt == null) return at == null ? (bt == null ? 0 : 1) : -1;
        return bt.compareTo(at);
      });
      if (mounted && epoch == _epoch) setState(() => _entries = entries);
    } on Object catch (error, stack) {
      log('Listing the WebDAV folder failed', name: 'WebDav', error: error, stackTrace: stack);
      if (mounted && epoch == _epoch) setState(() => _error = error);
    }
  }

  /// A pull to refresh (P02): the rows stay under the header while the
  /// folder loads; a failure still shows the error state.
  Future<Object?> _pullLoad() async {
    await _load(keepRows: true);
    final error = _error;
    return error == null ? null : AppRefreshFailure(webDavFailureText(error));
  }

  void _openDir(List<String> dir) {
    if (_busy != null) return;
    setState(() => _dir = dir);
    unawaited(_load());
  }

  bool get _idle => _busy == null && !_configBusy;

  /// A failure with a way to try again (U.11b c12): 4 s, "重试".
  void _failed(String message, VoidCallback retry) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return AppNavigator.toast(message);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: i18n('retry'), onPressed: retry),
        ),
      );
  }

  Future<void> _mutateConfigs(Future<void> Function() change) async {
    if (!_idle) return;
    setState(() => _configBusy = true);
    try {
      await change();
    } finally {
      if (mounted) setState(() => _configBusy = false);
    }
  }

  Future<void> _select(WebDavConfig config) => _mutateConfigs(() async {
    try {
      await _store.webdav.select(config.name);
    } on Object {
      AppNavigator.toast(i18n('webdav_config_select_failed'));
      return;
    }
    if (!mounted) return;
    _scaffold.currentState?.closeEndDrawer();
    _use(config);
  });

  Future<void> _edit({WebDavConfig? existing}) async {
    if (!_idle) return;
    final http = ref.read(webDavHttpProvider);
    final entered = await showWebDavConfigDialog(
      context,
      existing: existing,
      taken: {for (final config in _configs ?? const <WebDavConfig>[]) config.name},
      check: (config) => WebDavClient(http, config).check(),
    );
    if (entered == null || !mounted) return;
    await _mutateConfigs(() async {
      try {
        if (existing == null) {
          if (!await _store.webdav.add(entered)) {
            AppNavigator.toast(i18n('webdav_config_name_exists'));
            return;
          }
        } else {
          await _store.webdav.update(entered);
        }
        final becomesCurrent = existing == null || existing.name == _current?.name;
        if (becomesCurrent) await _store.webdav.select(entered.name);
        final configs = await _store.webdav.all();
        if (!mounted) return;
        setState(() => _configs = configs);
        if (becomesCurrent) _use(entered);
      } on Object catch (error, stack) {
        log('Saving the WebDAV server failed', name: 'WebDav', error: error, stackTrace: stack);
        AppNavigator.toast(i18n('webdav_config_save_failed'));
      }
    });
  }

  Future<void> _removeConfig(WebDavConfig config) async {
    if (!_idle) return;
    final confirmed = await _confirmDelete(i18n('webdav_confirm_delete_config', args: {'name': config.name}));
    if (!confirmed || !mounted) return;
    await _mutateConfigs(() async {
      try {
        await _store.webdav.remove(config.name);
        final configs = await _store.webdav.all();
        if (!mounted) return;
        setState(() => _configs = configs);
        if (config.name == _current?.name) _use(null);
      } on Object {
        AppNavigator.toast(i18n('webdav_config_delete_failed'));
      }
    });
  }

  /// 3.x's delete question with a red "删除".
  Future<bool> _confirmDelete(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(i18n('webdav_confirm_delete'), style: const TextStyle(fontWeight: FontWeight.w600)),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('webdav_cancel'))),
            FilledButton(
              key: const ValueKey('webdav-confirm'),
              style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(i18n('webdav_delete')),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _fileAction(String label, Future<void> Function(WebDavClient client) action) async {
    final client = _client;
    if (client == null || !_idle) return;
    setState(() => _busy = label);
    try {
      await action(client);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _upload(BackupScope scope) => _fileAction('webdav_uploading', (client) async {
    final dir = _dir;
    final taken = {for (final entry in _entries ?? const <WebDavEntry>[]) entry.name};
    final name = _freeName(backupFileName(scope, ref.read(webDavClockProvider)()), taken);
    try {
      final data = await exportBackup(ref.read(backupServiceProvider), _store, scope);
      await client.write([...dir, name], utf8.encode(jsonEncode(data)));
    } on Object catch (error, stack) {
      log('Uploading the backup failed', name: 'WebDav', error: error, stackTrace: stack);
      _failed(
        i18n('webdav_failed_with', args: {'action': i18n('webdav_upload_failed'), 'reason': webDavFailureText(error)}),
        () => unawaited(_upload(scope)),
      );
      return;
    }
    AppNavigator.toast(
      i18n(scope == BackupScope.follows ? 'webdav_upload_favorites_success' : 'webdav_upload_success'),
    );
    if (mounted && identical(client, _client) && dir == _dir) await _load();
  });

  static String _freeName(String name, Set<String> taken) {
    if (!taken.contains(name)) return name;
    final dot = name.lastIndexOf('.');
    for (var i = 2; ; i++) {
      final candidate = '${name.substring(0, dot)}_$i${name.substring(dot)}';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> _restore(WebDavEntry entry, BackupScope scope) =>
      _fileAction(scope == BackupScope.follows ? 'webdav_restoring_favorites' : 'webdav_restoring', (client) async {
        await restoreWithPreview(
          context,
          service: ref.read(backupServiceProvider),
          store: _store,
          fileName: entry.name,
          scope: scope,
          readFailedKey: 'webdav_download_failed',
          read: () async {
            final data = jsonDecode(utf8.decode(await client.read(entry.path), allowMalformed: true));
            if (data is! Map<String, Object?>) throw const FormatException('Not a backup file');
            return data;
          },
        );
      });

  Future<void> _delete(WebDavEntry entry) async {
    if (!_idle) return;
    final confirmed = await _confirmDelete(i18n('webdav_confirm_delete_item', args: {'name': entry.name}));
    if (!confirmed || !mounted) return;
    await _fileAction('webdav_deleting', (client) async {
      try {
        await client.remove(entry.path, dir: entry.isDir);
        AppNavigator.toast(i18n('webdav_delete_success'));
      } on Object catch (error) {
        _failed(
          i18n(
            'webdav_failed_with',
            args: {'action': i18n('webdav_delete_failed'), 'reason': webDavFailureText(error)},
          ),
          () => unawaited(_delete(entry)),
        );
      }
      if (mounted && identical(client, _client)) await _load();
    });
  }

  /// A tap: a folder opens; a file restores after its preview (a
  /// follows-only backup restores the follows), as on the backup page (R2).
  void _open(WebDavEntry entry) {
    if (!_idle) return;
    if (entry.isDir) return _openDir(entry.path);
    final follows = entry.name.toLowerCase().startsWith('purelive_favorites');
    unawaited(_restore(entry, follows ? BackupScope.follows : BackupScope.all));
  }

  Future<void> _fileMenu(BuildContext anchor, WebDavEntry entry) async {
    if (!_idle) return;
    final choice = await showAppMenu<_FileChoice>(
      anchor,
      entries: [
        if (!entry.isDir) ...[
          AppMenuEntry(
            key: const ValueKey('webdav-menu-restore-all'),
            value: _FileChoice.restoreAll,
            icon: AppIcons.backupRestore,
            label: i18n('webdav_restore_all_settings'),
          ),
          AppMenuEntry(
            key: const ValueKey('webdav-menu-restore-follows'),
            value: _FileChoice.restoreFollows,
            icon: AppIcons.backupFollows,
            label: i18n('webdav_restore_favorites'),
          ),
        ],
        AppMenuEntry(
          key: const ValueKey('webdav-menu-delete'),
          value: _FileChoice.delete,
          icon: AppIcons.delete,
          label: i18n('webdav_delete'),
          danger: true,
          divider: !entry.isDir,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _FileChoice.restoreAll:
        await _restore(entry, BackupScope.all);
      case _FileChoice.restoreFollows:
        await _restore(entry, BackupScope.follows);
      case _FileChoice.delete:
        await _delete(entry);
      case null:
        break;
    }
  }

  void _openHelp() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const WebDavHelpPage()));

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final canUpload = _client != null && _entries != null && _idle;
    final uploading = _busy == 'webdav_uploading';
    return Scaffold(
      key: _scaffold,
      appBar: settingsPageAppBar(
        context,
        title: i18n('webdav'),
        subtitle: current?.name ?? (_configs == null ? null : i18n('webdav_no_server')),
        centerTitle: false,
        actions: [
          IconButton(
            key: const ValueKey('webdav-servers'),
            tooltip: i18n('webdav_open_config_list'),
            icon: const Icon(AppIcons.webDavServers),
            onPressed: () => _scaffold.currentState?.openEndDrawer(),
          ),
          IconButton(
            key: const ValueKey('webdav-refresh'),
            tooltip: i18n('webdav_refresh'),
            icon: const Icon(AppIcons.refresh),
            onPressed: _client == null || !_idle ? null : () => unawaited(_load()),
          ),
          AppMenuButton<_Menu>(
            key: const ValueKey('webdav-more'),
            tooltip: i18n('webdav_more_actions'),
            icon: const Icon(AppIcons.moreVertical),
            entries: () => [
              AppMenuEntry(
                key: const ValueKey('webdav-menu-upload-follows'),
                value: _Menu.uploadFollows,
                icon: AppIcons.backupFollows,
                label: i18n('webdav_upload_favorites'),
                enabled: canUpload,
              ),
              AppMenuEntry(
                key: const ValueKey('webdav-menu-help'),
                value: _Menu.help,
                icon: AppIcons.help,
                label: i18n('webdav_help_tutorial'),
              ),
            ],
            onSelected: (choice) => switch (choice) {
              _Menu.uploadFollows => unawaited(_upload(BackupScope.follows)),
              _Menu.help => _openHelp(),
            },
          ),
        ],
      ),
      endDrawer: _drawer(context),
      floatingActionButton: _client == null || _error != null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('webdav-upload'),
              onPressed: canUpload ? () => unawaited(_upload(BackupScope.all)) : null,
              icon: uploading
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.webDavUpload),
              label: Text(i18n(uploading ? 'webdav_uploading' : 'webdav_upload_current')),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // One reading column at most 720 wide, centred (c11).
          final side = math.max(0, (constraints.maxWidth - readableContentMaxWidth) / 2).toDouble();
          return Column(
            children: [
              if (_client != null) _breadcrumbs(context, side),
              if (_busy case final label? when label != 'webdav_uploading')
                Padding(
                  padding: EdgeInsets.fromLTRB(16 + side, 4, 16 + side, 8),
                  child: Column(
                    children: [
                      Text(i18n(label), style: context.textStyles.t12),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(semanticsLabel: i18n(label)),
                    ],
                  ),
                ),
              Expanded(child: _content(context, side)),
            ],
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, double side) {
    final configs = _configs;
    if (configs == null) return const AppStatusView(type: AppStatusType.loading, title: '', subtitle: '');
    if (configs.isEmpty) {
      return AppStatusView(
        key: const ValueKey('webdav-no-config'),
        type: AppStatusType.empty,
        icon: AppIcons.cloudOff,
        title: i18n('webdav_no_config_create_first'),
        subtitle: i18n('webdav_intro'),
        buttonText: i18n('webdav_create_new_config'),
        buttonIcon: AppIcons.add,
        onButtonPressed: () => unawaited(_edit()),
        secondaryButtonText: i18n('webdav_help_tutorial'),
        onSecondaryButtonPressed: _openHelp,
      );
    }
    if (_current == null || _savedInvalid) {
      return AppStatusView(
        key: const ValueKey('webdav-no-server'),
        type: AppStatusType.empty,
        icon: AppIcons.webDavServer,
        title: i18n(_savedInvalid ? 'webdav_saved_address_invalid' : 'webdav_select_config_from_sidebar'),
        buttonText: i18n('webdav_open_config_list'),
        buttonIcon: AppIcons.webDavServers,
        onButtonPressed: () => _scaffold.currentState?.openEndDrawer(),
      );
    }
    if (_error case final error?) {
      return AppStatusView(
        key: const ValueKey('webdav-error'),
        type: AppStatusType.error,
        title: i18n('webdav_load_dir_failed'),
        subtitle: webDavFailureText(error),
        buttonText: i18n('retry'),
        buttonIcon: AppIcons.retry,
        onButtonPressed: () => unawaited(_load()),
        secondaryButtonText: i18n('webdav_edit_current'),
        onSecondaryButtonPressed: () => unawaited(_edit(existing: _current)),
      );
    }
    final entries = _entries;
    if (entries == null) return const AppStatusView(type: AppStatusType.loading, title: '', subtitle: '');
    if (entries.isEmpty) {
      return AppRefreshView(
        onRefresh: _pullLoad,
        builder: (context, physics) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: physics,
            child: SizedBox(
              height: constraints.maxHeight,
              child: AppStatusView(
                key: const ValueKey('webdav-empty'),
                type: AppStatusType.empty,
                icon: AppIcons.webDavFolderEmpty,
                title: i18n('webdav_folder_empty'),
                subtitle: i18n('webdav_folder_empty_hint'),
              ),
            ),
          ),
        ),
      );
    }
    final busy = !_idle;
    return AppRefreshView(
      onRefresh: _pullLoad,
      builder: (context, physics) => ListView.builder(
        key: const ValueKey('webdav-list'),
        physics: physics,
        padding: EdgeInsets.fromLTRB(side, 0, side, 96),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _EntryRow(
            key: ValueKey('webdav-entry-${entry.name}'),
            entry: entry,
            enabled: !busy,
            onTap: () => _open(entry),
            onMenu: (anchor) => unawaited(_fileMenu(anchor, entry)),
          );
        },
      ),
    );
  }

  Widget _breadcrumbs(BuildContext context, double side) {
    final colors = Theme.of(context).colorScheme;
    Widget crumb(String label, List<String> target) {
      final here = target.length == _dir.length;
      return TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(48, 48),
          foregroundColor: colors.onSurface,
          disabledForegroundColor: colors.primary,
        ),
        onPressed: here ? null : () => _openDir(target),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.t13.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    // From the left edge of the column (3.x left 48 empty, W11); a long
    // path scrolls so the open folder stays in view (3.x).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbs.hasClients) _crumbs.jumpTo(_crumbs.position.maxScrollExtent);
    });
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: SingleChildScrollView(
        key: const ValueKey('webdav-breadcrumbs'),
        controller: _crumbs,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 8 + side),
        child: Row(
          children: [
            crumb(i18n('webdav_my_files'), const []),
            for (var i = 1; i <= _dir.length; i++) ...[
              Icon(AppIcons.pathSeparator, size: 18, color: colors.onSurfaceVariant),
              crumb(_dir[i - 1], _dir.sublist(0, i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final configs = _configs ?? const <WebDavConfig>[];
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: colors.surfaceContainer,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Text(i18n('webdav_servers'), style: context.textStyles.t16.copyWith(fontWeight: FontWeight.w600)),
            ),
            for (final config in configs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  key: ValueKey('webdav-server-${config.name}'),
                  selected: config.name == _current?.name,
                  selectedTileColor: colors.secondaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(config.name == _current?.name ? AppIcons.webDavServerCurrent : AppIcons.webDavServer),
                  title: Text(
                    config.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(config.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: _idle ? () => unawaited(_select(config)) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('webdav-edit-${config.name}'),
                        tooltip: i18n('webdav_edit_config', args: {'name': config.name}),
                        icon: const Icon(AppIcons.edit),
                        onPressed: _idle ? () => unawaited(_edit(existing: config)) : null,
                      ),
                      IconButton(
                        key: ValueKey('webdav-remove-${config.name}'),
                        tooltip: i18n('webdav_delete'),
                        icon: Icon(AppIcons.delete, color: colors.error),
                        onPressed: _idle ? () => unawaited(_removeConfig(config)) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ListTile(
              key: const ValueKey('webdav-add-server'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(AppIcons.add),
              title: Text(i18n('webdav_add_new_config')),
              onTap: _idle ? () => unawaited(_edit()) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A folder or file of the server: icon, name (two lines), "time · size",
/// ⋮; a right click or a long press opens the same menu as ⋮.
class _EntryRow extends StatefulWidget {
  const new({required this.entry, required this.enabled, required this.onTap, required this.onMenu, super.key});

  final WebDavEntry entry;
  final bool enabled;
  final VoidCallback onTap;
  final void Function(BuildContext anchor) onMenu;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  final GlobalKey _more = GlobalKey();

  void _menu() {
    final anchor = _more.currentContext;
    if (anchor != null && widget.enabled) widget.onMenu(anchor);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final colors = Theme.of(context).colorScheme;
    final isBackup = !entry.isDir && entry.name.toLowerCase().startsWith('purelive');
    final info = [
      if (entry.modified case final time?) formatFileTime(time) else i18n('webdav_unknown_time'),
      if (!entry.isDir)
        if (entry.size case final size?) formatFileSize(size),
    ].join(' · ');
    final row = InkWell(
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? _menu : null,
      onSecondaryTap: widget.enabled ? _menu : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Icon(
              entry.isDir
                  ? AppIcons.webDavFolder
                  : isBackup
                  ? AppIcons.webDavBackupFile
                  : AppIcons.webDavOtherFile,
              color: colors.primary,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.t15),
                  const SizedBox(height: 2),
                  Text(
                    info,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.t12.tabular.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              key: _more,
              tooltip: i18n('webdav_more_actions'),
              icon: const Icon(AppIcons.moreVertical),
              onPressed: widget.enabled ? _menu : null,
            ),
          ],
        ),
      ),
    );
    return widget.enabled ? row : Opacity(opacity: 0.38, child: row);
  }
}
