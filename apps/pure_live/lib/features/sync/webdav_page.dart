import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/bytes.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/sync/webdav_client.dart';
import 'package:pure_live_app/features/sync/webdav_profiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// WebDAV profiles of this installation.
final webDavProfileStoreProvider = Provider<WebDavProfileStore>(
  (ref) => WebDavProfileStore(ref.watch(storeProvider).meta, ref.watch(secretStoreProvider)),
);

/// Creates a client for a profile; requests use the app's HTTP transport and
/// therefore its proxy policy (site id `webdav`).
final webDavClientFactoryProvider = Provider<WebDavClient Function(WebDavProfile profile)>((ref) {
  final http = ref.watch(liveHttpProvider);
  final profiles = ref.watch(webDavProfileStoreProvider);
  return (profile) =>
      WebDavClient(http, base: profile.base, username: profile.username, password: profiles.passwordOf(profile));
});

/// Chinese text for a failed WebDAV request.
String webDavErrorText(Object error) => switch (error) {
  WebDavException(error: WebDavError.unauthorized) => t.sync.webdav.error.unauthorized,
  WebDavException(error: WebDavError.forbidden) => t.sync.webdav.error.forbidden,
  WebDavException(error: WebDavError.notFound) => t.sync.webdav.error.notFound,
  WebDavException(error: WebDavError.insufficientStorage) => t.sync.webdav.error.storage,
  WebDavException(error: WebDavError.network) => t.sync.webdav.error.network,
  WebDavException(error: WebDavError.invalidResponse) => t.sync.webdav.error.invalid,
  WebDavException(:final status) => t.sync.webdav.error.http(status: status ?? '?'),
  _ => backupErrorText(error),
};

/// WebDAV (F-DAV-01, store.md §10): several accounts, test the connection,
/// upload a full or follows-only v4 backup (accounts only behind a
/// passphrase), browse and delete remote files, restore in full or follows
/// only after the same dry run as a local restore.
class WebDavPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends ConsumerState<WebDavPage> {
  List<WebDavProfile> _profiles = const [];
  WebDavProfile? _current;
  List<String> _directory = const [];
  List<WebDavEntry>? _entries;
  String? _listError;
  bool _loading = true;
  String? _busy;
  // Results of requests started for an older profile or directory are
  // dropped (store.md §10).
  int _generation = 0;

  WebDavProfileStore get _store => ref.read(webDavProfileStoreProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  Future<void> _loadProfiles({String? select}) async {
    final profiles = await _store.load();
    final currentId = select ?? await _store.currentId();
    if (!mounted) return;
    final current = profiles.where((profile) => profile.id == currentId).firstOrNull ?? profiles.firstOrNull;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
    await _select(current);
  }

  Future<void> _select(WebDavProfile? profile) async {
    setState(() {
      _generation++;
      _current = profile;
      _directory = profile?.directory ?? const [];
      _entries = null;
      _listError = null;
    });
    if (profile != null) {
      await _store.setCurrent(profile.id);
      await _list();
    }
  }

  WebDavClient _client(WebDavProfile profile) => ref.read(webDavClientFactoryProvider)(profile);

  Future<void> _list() async {
    final profile = _current;
    if (profile == null) return;
    final generation = ++_generation;
    final directory = _directory;
    setState(() {
      _entries = null;
      _listError = null;
    });
    try {
      final entries = await _client(profile).list(directory);
      if (!mounted || generation != _generation) return;
      setState(() => _entries = [...entries.where((entry) => entry.isDirectory || _isBackupName(entry.name))]);
    } on WebDavException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _listError = error.error == WebDavError.notFound ? t.sync.webdav.noDirectory : webDavErrorText(error),
      );
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('webdav', 'list failed', error, stack);
      if (!mounted || generation != _generation) return;
      setState(() => _listError = webDavErrorText(error));
    }
  }

  // v4 files and the 3.x `purelive_*.txt`; the format is decided by content.
  static bool _isBackupName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.txt');
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(String label, Future<void> Function(int generation) action) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    final generation = _generation;
    try {
      await action(generation);
    } on Object catch (error, stack) {
      final log = ref.read(appLogProvider);
      if (error is WebDavException || error is FormatException || error is BackupTooNewException) {
        log.warning('webdav', '$label failed', error);
      } else {
        log.error('webdav', '$label failed', error, stack);
      }
      _toast(webDavErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _test() => _run(t.sync.webdav.test, (_) async {
    final exists = await _client(_current!).check(_current!.directory);
    _toast(exists ? t.sync.webdav.connected : t.sync.webdav.connectedNoDirectory);
  });

  Future<void> _upload() async {
    final options = await showExportOptions(context, title: t.sync.webdav.uploadBackup, action: t.sync.webdav.upload);
    if (options == null) return;
    await _run(t.sync.webdav.upload, (generation) async {
      final profile = _current!;
      final directory = _directory;
      final now = DateTime.now();
      final document = await ref
          .read(backupServiceProvider)
          .export(scope: options.scope, passphrase: options.passphrase, now: now);
      final client = _client(profile);
      await client.ensureDirectory(directory);
      await client.put([...directory, BackupService.fileName(options.scope, now)], encodeBackup(document));
      if (generation != _generation) return;
      _toast(t.sync.webdav.uploaded);
      unawaited(_list());
    });
  }

  Future<void> _restore(WebDavEntry entry, RestoreMode mode) => _run(t.sync.webdav.restore, (generation) async {
    final bytes = await _client(_current!).get(entry.path);
    if (!mounted || generation != _generation) return;
    await confirmAndRestore(
      context,
      service: ref.read(backupServiceProvider),
      document: decodeBackup(bytes),
      mode: mode,
      source: t.sync.webdav.fromWebdav(name: entry.name),
    );
  });

  Future<void> _delete(WebDavEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.sync.webdav.deleteRemote),
        content: Text(t.sync.webdav.deleteRemoteConfirm(name: entry.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.common.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(t.common.delete, (generation) async {
      await _client(_current!).delete(entry.path);
      if (generation != _generation) return;
      _toast(t.sync.webdav.deleted);
      unawaited(_list());
    });
  }

  void _open(List<String> directory) {
    setState(() => _directory = directory);
    unawaited(_list());
  }

  Future<void> _edit([WebDavProfile? profile]) async {
    final result = await showDialog<WebDavProfile>(
      context: context,
      builder: (context) => _ProfileDialog(profile: profile, store: _store, taken: _profiles),
    );
    if (result != null) await _loadProfiles(select: result.id);
  }

  Future<void> _remove(WebDavProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.sync.webdav.deleteAccount),
        content: Text(t.sync.webdav.deleteAccountConfirm(name: profile.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.common.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(profile.id);
    await _loadProfiles();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV'),
        actions: [
          IconButton(
            tooltip: t.sync.webdav.help,
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
          ),
          IconButton(tooltip: t.sync.webdav.addAccount, icon: const Icon(Icons.add), onPressed: _edit),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: _loading
              ? const LoadingView()
              : current == null
              ? MessageView(
                  icon: Icons.cloud_off_outlined,
                  title: t.sync.webdav.noAccounts,
                  message: t.sync.webdav.noAccountsHint,
                  actionLabel: t.sync.webdav.addAccount,
                  onAction: _edit,
                )
              : AbsorbPointer(absorbing: _busy != null, child: _body(current)),
        ),
      ),
    );
  }

  Widget _body(WebDavProfile current) {
    final entries = _entries;
    final path = _directory.isEmpty ? '/' : '/${_directory.join('/')}/';
    return RefreshIndicator(
      onRefresh: _list,
      child: ListView(
        children: [
          if (_busy != null) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(current.name),
            subtitle: Text('${current.baseUrl}${current.username.isEmpty ? '' : ' · ${current.username}'}'),
            trailing: PopupMenuButton<String>(
              tooltip: t.sync.webdav.account,
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await _edit(current);
                  case 'delete':
                    await _remove(current);
                  default:
                    await _select(_profiles.firstWhere((profile) => profile.id == value));
                }
              },
              itemBuilder: (context) => [
                for (final profile in _profiles)
                  if (profile.id != current.id)
                    PopupMenuItem(
                      value: profile.id,
                      child: Text(t.sync.webdav.switchTo(name: profile.name)),
                    ),
                PopupMenuItem(value: 'edit', child: Text(t.common.edit)),
                PopupMenuItem(value: 'delete', child: Text(t.common.delete)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                OutlinedButton.icon(
                  onPressed: _test,
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(t.sync.webdav.test),
                ),
                FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(t.sync.webdav.uploadBackup),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(t.sync.webdav.remoteFiles(path: path)),
            subtitle: Text(t.sync.webdav.remoteFilesHint),
            trailing: IconButton(tooltip: t.common.refresh, icon: const Icon(Icons.refresh), onPressed: _list),
          ),
          if (_directory.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(t.sync.webdav.up),
              onTap: () => _open(_directory.sublist(0, _directory.length - 1)),
            ),
          if (_listError case final error?)
            Padding(padding: const EdgeInsets.all(Space.s4), child: Text(error))
          else if (entries == null)
            const Padding(
              padding: EdgeInsets.all(Space.s6),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (entries.isEmpty)
            Padding(padding: const EdgeInsets.all(Space.s4), child: Text(t.sync.webdav.noBackups))
          else
            for (final entry in entries) _entryTile(entry),
        ],
      ),
    );
  }

  Widget _entryTile(WebDavEntry entry) {
    if (entry.isDirectory) {
      return ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(entry.name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(entry.path),
      );
    }
    final details = [
      if (entry.modified case final time?) _formatTime(time),
      if (entry.size case final size?) formatBytes(size),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: PopupMenuButton<String>(
        tooltip: t.sync.webdav.actions,
        onSelected: (value) => switch (value) {
          'full' => _restore(entry, RestoreMode.full),
          'follows' => _restore(entry, RestoreMode.follows),
          _ => _delete(entry),
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'full', child: Text(t.backup.restoreFull)),
          PopupMenuItem(value: 'follows', child: Text(t.backup.restoreFollows)),
          PopupMenuItem(value: 'delete', child: Text(t.common.delete)),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = time.toLocal();
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

void _showHelp(BuildContext context) => unawaited(
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.sync.webdav.helpTitle),
      content: SingleChildScrollView(child: Text(t.sync.webdav.helpBody)),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.common.gotIt))],
    ),
  ),
);

class _ProfileDialog extends StatefulWidget {
  const new({required this.profile, required this.store, required this.taken});

  final WebDavProfile? profile;
  final WebDavProfileStore store;
  final List<WebDavProfile> taken;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController(
    text: widget.profile?.name ?? (widget.taken.isEmpty ? t.sync.webdav.defaultName : ''),
  );
  late final _url = TextEditingController(text: widget.profile?.baseUrl ?? 'https://');
  late final _user = TextEditingController(text: widget.profile?.username ?? '');
  final _password = TextEditingController();
  late final _directory = TextEditingController(text: widget.profile?.remoteDir ?? 'pure_live');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_name, _url, _user, _password, _directory]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final editing = widget.profile;
    final profile = WebDavProfile(
      id: editing?.id ?? WebDavProfileStore.newId(),
      name: _name.text,
      baseUrl: _url.text,
      username: _user.text,
      remoteDir: _directory.text,
    );
    try {
      // Editing keeps the stored password unless a new one is typed.
      final saved = await widget.store.save(
        profile,
        password: editing != null && _password.text.isEmpty ? null : _password.text,
      );
      if (mounted) Navigator.pop(context, saved);
    } on WebDavProfileException catch (error) {
      setState(() {
        _saving = false;
        _error = switch (error.error) {
          WebDavProfileError.emptyName => t.sync.webdav.nameRequired,
          WebDavProfileError.duplicateName => t.sync.webdav.nameTaken,
          WebDavProfileError.invalidUrl => t.sync.webdav.badUrl,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.profile == null ? t.sync.webdav.addTitle : t.sync.webdav.editTitle),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: t.common.name),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: t.sync.lan.address, hintText: 'https://dav.jianguoyun.com/dav/'),
            ),
            TextField(
              controller: _user,
              decoration: InputDecoration(labelText: t.common.username),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.common.password,
                helperText: widget.profile == null ? t.sync.webdav.passwordStored : t.sync.webdav.passwordKeep,
              ),
            ),
            TextField(
              controller: _directory,
              decoration: InputDecoration(labelText: t.sync.webdav.directory, helperText: t.sync.webdav.directoryRoot),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
      FilledButton(onPressed: _saving ? null : _save, child: Text(t.common.save)),
    ],
  );
}
