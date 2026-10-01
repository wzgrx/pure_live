import 'dart:async';
import 'dart:convert';
import 'dart:developer';

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

/// WebDAV (3.x `lib/modules/web_dav`).
///
/// Routes: `RoutePath.kWebDavPage`.
///
/// The servers (`LiveStore.webdav`, passwords sealed), browsing the
/// current server's folders, uploading a full or follows-only backup to
/// the open folder, restoring a file after a preview, deleting.
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

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final epoch = ++_epoch;
    final dir = _dir;
    setState(() {
      _entries = null;
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

  void _openDir(List<String> dir) {
    if (_busy != null) return;
    setState(() => _dir = dir);
    unawaited(_load());
  }

  bool get _idle => _busy == null && !_configBusy;

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
    final confirmed = await _confirm(
      i18n('webdav_confirm_delete'),
      i18n('webdav_confirm_delete_config', args: {'name': config.name}),
    );
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

  Future<bool> _confirm(String title, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          title: Text(title),
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
      AppNavigator.toast(
        i18n('webdav_failed_with', args: {'action': i18n('webdav_upload_failed'), 'reason': webDavFailureText(error)}),
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
    final confirmed = await _confirm(
      i18n('webdav_confirm_delete'),
      i18n('webdav_confirm_delete_item', args: {'name': entry.name}),
    );
    if (!confirmed || !mounted) return;
    await _fileAction('webdav_deleting', (client) async {
      try {
        await client.remove(entry.path, dir: entry.isDir);
        AppNavigator.toast(i18n('webdav_delete_success'));
      } on Object catch (error) {
        AppNavigator.toast(
          i18n(
            'webdav_failed_with',
            args: {'action': i18n('webdav_delete_failed'), 'reason': webDavFailureText(error)},
          ),
        );
      }
      if (mounted && identical(client, _client)) await _load();
    });
  }

  Future<void> _showFileMenu(WebDavEntry entry) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(entry.name, style: sheetContext.textStyles.t15SemiBold),
              subtitle: _fileInfo(entry),
            ),
            const Divider(height: 1),
            if (!entry.isDir) ...[
              ListTile(
                leading: const Icon(Remix.file_upload_line),
                title: Text(i18n('webdav_restore_all_settings')),
                onTap: () => Navigator.pop(sheetContext, 0),
              ),
              ListTile(
                leading: const Icon(Remix.heart_pulse_line),
                title: Text(i18n('webdav_restore_favorites')),
                onTap: () => Navigator.pop(sheetContext, 1),
              ),
            ],
            ListTile(
              leading: Icon(Remix.delete_bin_line, color: Theme.of(sheetContext).colorScheme.error),
              title: Text(i18n('webdav_delete')),
              onTap: () => Navigator.pop(sheetContext, 2),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 0:
        await _restore(entry, BackupScope.all);
      case 1:
        await _restore(entry, BackupScope.follows);
      case 2:
        await _delete(entry);
    }
  }

  Widget? _fileInfo(WebDavEntry entry) {
    final parts = [
      if (entry.modified case final time?) formatFileTime(time) else i18n('webdav_unknown_time'),
      if (entry.size case final size?) formatFileSize(size),
    ];
    return Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final canUpload = _client != null && _entries != null && _idle;
    return PopScope(
      canPop: _dir.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _dir.isNotEmpty) _openDir(_dir.sublist(0, _dir.length - 1));
      },
      child: Scaffold(
        key: _scaffold,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i18n('webdav')),
              if (current != null) Text(current.name, style: context.textStyles.t12Muted),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('webdav-servers'),
              tooltip: i18n('webdav_open_config_list'),
              icon: const Icon(Remix.server_line),
              onPressed: () => _scaffold.currentState?.openEndDrawer(),
            ),
            IconButton(
              tooltip: i18n('webdav_refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: _client == null || !_idle ? null : () => unawaited(_load()),
            ),
            PopupMenuButton<int>(
              tooltip: i18n('webdav_more_actions'),
              onSelected: (value) {
                if (value == 0) {
                  unawaited(_upload(BackupScope.follows));
                } else {
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const WebDavHelpPage()));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, enabled: canUpload, child: Text(i18n('webdav_upload_favorites'))),
                PopupMenuItem(value: 1, child: Text(i18n('webdav_help_tutorial'))),
              ],
            ),
          ],
        ),
        endDrawer: _drawer(context),
        floatingActionButton: _client == null
            ? null
            : FloatingActionButton.extended(
                key: const ValueKey('webdav-upload'),
                onPressed: canUpload ? () => unawaited(_upload(BackupScope.all)) : null,
                icon: _busy == 'webdav_uploading'
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(i18n(_busy == 'webdav_uploading' ? 'webdav_uploading' : 'webdav_upload_current')),
              ),
        body: Column(
          children: [
            if (_client != null) _breadcrumbs(context),
            if (_busy case final label?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  children: [
                    Text(i18n(label), style: context.textStyles.t12Muted),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(semanticsLabel: i18n(label)),
                  ],
                ),
              ),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final configs = _configs;
    if (configs == null) return const AppStatusView(type: AppStatusType.loading, title: '', subtitle: '');
    if (configs.isEmpty) {
      return EmptyView(
        key: const ValueKey('webdav-no-config'),
        icon: Icons.cloud_off_outlined,
        title: i18n('webdav_no_config_create_first'),
        subtitle: i18n('webdav_intro'),
        buttonText: i18n('webdav_create_new_config'),
        buttonIcon: Icons.add_rounded,
        onButtonPressed: () => unawaited(_edit()),
      );
    }
    if (_current == null || _savedInvalid) {
      return EmptyView(
        icon: Icons.cloud_queue,
        title: i18n(_savedInvalid ? 'webdav_saved_address_invalid' : 'webdav_select_config_from_sidebar'),
        buttonText: i18n('webdav_open_config_list'),
        buttonIcon: Icons.menu_open_rounded,
        onButtonPressed: () => _scaffold.currentState?.openEndDrawer(),
      );
    }
    if (_error case final error?) {
      return AppStatusView(
        type: AppStatusType.error,
        title: i18n('webdav_load_dir_failed'),
        subtitle: webDavFailureText(error),
        onButtonPressed: () => unawaited(_load()),
      );
    }
    final entries = _entries;
    if (entries == null) return const AppStatusView(type: AppStatusType.loading, title: '', subtitle: '');
    if (entries.isEmpty) {
      return EmptyView(
        key: const ValueKey('webdav-empty'),
        icon: Icons.folder_open_outlined,
        title: i18n('webdav_folder_empty'),
        subtitle: i18n('webdav_folder_empty_hint'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final colors = Theme.of(context).colorScheme;
          final isBackup = !entry.isDir && entry.name.toLowerCase().startsWith('purelive');
          return ListTile(
            key: ValueKey('webdav-entry-${entry.name}'),
            leading: Icon(
              entry.isDir
                  ? Icons.folder_outlined
                  : isBackup
                  ? Remix.file_shield_2_line
                  : Icons.insert_drive_file_outlined,
              color: colors.primary,
              size: 28,
            ),
            title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: _fileInfo(entry),
            trailing: IconButton(
              tooltip: i18n('webdav_more_actions'),
              icon: const Icon(Icons.more_vert),
              onPressed: _idle ? () => unawaited(_showFileMenu(entry)) : null,
            ),
            onTap: !_idle
                ? null
                : entry.isDir
                ? () => _openDir(entry.path)
                : () => unawaited(_showFileMenu(entry)),
          );
        },
      ),
    );
  }

  Widget _breadcrumbs(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget crumb(String label, List<String> target) {
      final here = target.length == _dir.length;
      return TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: here ? null : () => _openDir(target),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: here ? colors.primary : colors.onSurface, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        key: const ValueKey('webdav-breadcrumbs'),
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          // Reversed, so the current folder stays in view.
          for (var i = _dir.length; i >= 1; i--) ...[
            crumb(_dir[i - 1], _dir.sublist(0, i)),
            const Icon(Icons.navigate_next, size: 18),
          ],
          crumb(i18n('webdav_my_files'), const []),
        ],
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final configs = _configs ?? const <WebDavConfig>[];
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(i18n('webdav_servers'), style: context.textStyles.t16Bold),
            ),
            for (final config in configs)
              ListTile(
                key: ValueKey('webdav-server-${config.name}'),
                selected: config.name == _current?.name,
                leading: Icon(config.name == _current?.name ? Icons.cloud_done_outlined : Icons.cloud_outlined),
                title: Text(config.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(config.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: _idle ? () => unawaited(_select(config)) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: i18n('webdav_edit_config', args: {'name': config.name}),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _idle ? () => unawaited(_edit(existing: config)) : null,
                    ),
                    IconButton(
                      tooltip: i18n('webdav_delete'),
                      icon: Icon(Icons.delete_outline, color: colors.error),
                      onPressed: _idle ? () => unawaited(_removeConfig(config)) : null,
                    ),
                  ],
                ),
              ),
            ListTile(
              key: const ValueKey('webdav-add-server'),
              leading: const Icon(Icons.add),
              title: Text(i18n('webdav_add_new_config')),
              onTap: _idle ? () => unawaited(_edit()) : null,
            ),
          ],
        ),
      ),
    );
  }
}
