import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_sync.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';
import 'package:pure_live_app/features/iptv/xtream.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Location of the IPTV page; a full-screen route above the tabs.
const iptvLocation = '/iptv';

/// Location of the guide source page.
const iptvGuideLocation = '/iptv/guide';

/// Playlist management (F-IPTV-01, F-IPTV-03, F-IPTV-04): import from a file
/// or URL, sync one or all, rename, per-playlist User-Agent and auto sync,
/// delete; the automatic sync settings and the global User-Agent.
class IptvPage extends ConsumerStatefulWidget {
  const new({this.initialImport, super.key});

  /// A shared playlist to confirm and import on open.
  final IptvImportRequest? initialImport;

  @override
  ConsumerState<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends ConsumerState<IptvPage> {
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialImport case final request?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_importShared(request));
      });
    }
  }

  IptvSync get _sync => ref.read(iptvSyncProvider);

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs [action] marked busy under [key]; failures become a message.
  Future<void> _run(String key, Future<String?> Function() action) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final message = await action();
      if (message != null) _toast(message);
    } on Object catch (error) {
      _toast(iptvErrorText(error));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  static String _summary(String name, IptvSyncResult result) => result.issues > 0
      ? t.iptv.importSummarySkipped(name: name, channels: result.channels, lines: result.items, skipped: result.issues)
      : t.iptv.importSummary(name: name, channels: result.channels, lines: result.items);

  Future<void> _importUrl({String url = ''}) async {
    final source = await askSource(context, title: t.iptv.importFromUrl, url: url);
    if (source == null || source.url.isEmpty) return;
    await _run('import', () async {
      final result = await _sync.importUrl(source.url, name: source.name);
      final name = (await ref.read(storeProvider).iptv.playlist(result.id))?.name ?? '';
      return t.iptv.imported(summary: _summary(name, result));
    });
  }

  /// F-IPTV-07: an Xtream Codes account; the password goes to the secret
  /// store only.
  Future<void> _importXtream() async {
    final account = await showDialog<XtreamAccount>(context: context, builder: (context) => const _XtreamDialog());
    if (account == null || !mounted) return;
    await _run('import', () async {
      final result = await _sync.importXtream(account);
      final name = (await ref.read(storeProvider).iptv.playlist(result.id))?.name ?? account.defaultName;
      return t.iptv.signedInAndImported(summary: _summary(name, result));
    });
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(dialogTitle: t.iptv.pickPlaylist);
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    await _run('import', () async {
      final result = await _sync.importFile(fileName: file.name, bytes: await file.readAsBytes());
      final name = (await ref.read(storeProvider).iptv.playlist(result.id))?.name ?? file.name;
      return t.iptv.imported(summary: _summary(name, result));
    });
  }

  Future<void> _importShared(IptvImportRequest request) async {
    final url = request.url;
    if (url != null) return await _importUrl(url: url);
    final bytes = request.bytes;
    if (bytes == null) return;
    final fileName = request.fileName ?? t.iptv.sharedFileName;
    final dot = fileName.lastIndexOf('.');
    final source = await askSource(
      context,
      title: t.iptv.importShared,
      name: dot > 0 ? fileName.substring(0, dot) : fileName,
      askUrl: false,
    );
    if (source == null) return;
    await _run('import', () async {
      final result = await _sync.importFile(fileName: fileName, bytes: bytes, name: source.name);
      return t.iptv.imported(summary: _summary(source.name.isEmpty ? fileName : source.name, result));
    });
  }

  Future<void> _syncAll() => _run('all', () async {
    final failed = await _sync.syncAll();
    return failed == 0 ? t.iptv.allSynced : t.iptv.syncedWithFailures(n: failed);
  });

  Future<void> _syncOne(IptvPlaylistRecord playlist) => _run(
    'p${playlist.id}',
    () async => t.iptv.syncedPlaylist(summary: _summary(playlist.name, await _sync.syncPlaylist(playlist))),
  );

  Future<void> _menu(IptvPlaylistRecord playlist, _PlaylistAction action) async {
    final iptv = ref.read(storeProvider).iptv;
    switch (action) {
      case _PlaylistAction.sync:
        await _syncOne(playlist);
      case _PlaylistAction.rename:
        final name = await askText(context, title: t.common.rename, initial: playlist.name);
        if (name != null && name.isNotEmpty) await iptv.renamePlaylist(playlist.id, name);
      case _PlaylistAction.userAgent:
        final agent = await askText(
          context,
          title: t.iptv.playlistUserAgent,
          initial: playlist.userAgent ?? '',
          hint: t.iptv.userAgentEmpty,
          helper: t.iptv.playlistUserAgentHint,
        );
        if (agent != null) await iptv.setPlaylistUserAgent(playlist.id, agent);
      case _PlaylistAction.autoSync:
        await iptv.setPlaylistAutoSync(playlist.id, enabled: !playlist.autoSync);
      case _PlaylistAction.copySource:
        await Clipboard.setData(ClipboardData(text: playlist.source));
        _toast(t.iptv.sourceCopied);
      case _PlaylistAction.delete:
        final confirmed = await confirm(
          context,
          title: t.iptv.deletePlaylist,
          message: t.iptv.deletePlaylistConfirm(name: playlist.name, n: playlist.channelCount),
        );
        if (confirmed) await _sync.deletePlaylist(playlist);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(iptvPlaylistsProvider);
    final guides = ref.watch(iptvGuideSourcesProvider).value ?? const [];
    final selectedGuide = guides.where((guide) => guide.selected).firstOrNull;
    final busy = _busy.isNotEmpty;
    return Scaffold(
      appBar: PageAppBar(
        maxContentWidth: Sizes.readingWidth,
        title: Text(t.iptv.title),
        actions: [
          IconButton(
            tooltip: t.iptv.syncAll,
            icon: const LiveIcon(LiveIcons.sync),
            onPressed: _busy.contains('all') || (playlists.value?.isEmpty ?? true) ? null : _syncAll,
          ),
        ],
        bottom: busy
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: PageBody(
        maxContentWidth: Sizes.readingWidth,
        child: ListView(
          children: [
            SettingsHeader(t.iptv.playlists),
            ...switch (playlists) {
              AsyncData(:final value) when value.isEmpty => [
                ListTile(
                  leading: const LiveIcon(LiveIcons.liveTv),
                  title: Text(t.iptv.noPlaylists),
                  subtitle: Text(t.iptv.playlistsHint),
                ),
              ],
              AsyncData(:final value) => [
                for (final playlist in value)
                  _PlaylistTile(
                    playlist: playlist,
                    busy: _busy.contains('p${playlist.id}') || _busy.contains('all'),
                    onSync: () => _syncOne(playlist),
                    onAction: (action) => _menu(playlist, action),
                  ),
              ],
              AsyncError() => [ListTile(title: Text(t.iptv.playlistsLoadFailed))],
              _ => [const Padding(padding: EdgeInsets.all(Space.s4), child: LinearProgressIndicator())],
            },
            Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: PageMargin.tilePadding(PageMargin.of(context)).start,
                vertical: Space.s2,
              ),
              child: Wrap(
                spacing: Space.s2,
                runSpacing: Space.s2,
                children: [
                  FilledButton.tonalIcon(
                    icon: const LiveIcon(LiveIcons.link),
                    label: Text(t.iptv.importFromUrl),
                    onPressed: _busy.contains('import') ? null : _importUrl,
                  ),
                  OutlinedButton.icon(
                    icon: const LiveIcon(LiveIcons.folderOpen),
                    label: Text(t.iptv.importFromFile),
                    onPressed: _busy.contains('import') ? null : _importFile,
                  ),
                  OutlinedButton.icon(
                    icon: const LiveIcon(LiveIcons.key),
                    label: Text(t.iptv.xtreamAccount),
                    onPressed: _busy.contains('import') ? null : _importXtream,
                  ),
                ],
              ),
            ),
            SettingsHeader(t.iptv.guide),
            ListTile(
              leading: const LiveIcon(LiveIcons.guide),
              title: Text(t.iptv.guideSources),
              subtitle: Text(
                selectedGuide == null
                    ? (guides.isEmpty ? t.iptv.noGuideAdded : t.iptv.noGuideSelected)
                    : t.iptv.currentGuide(name: selectedGuide.name),
              ),
              trailing: const LiveIcon(LiveIcons.subpage),
              onTap: () => context.push(iptvGuideLocation),
            ),
            SettingsHeader(t.common.sync),
            SwitchSettingTile(setting: Settings.iptvAutoSync, title: t.iptv.autoSync, subtitle: t.iptv.autoSyncHint),
            ChoiceSettingTile<int>(
              setting: Settings.iptvAutoSyncHours,
              title: t.iptv.syncInterval,
              labels: {
                6: t.iptv.every6h,
                12: t.iptv.every12h,
                24: t.iptv.daily,
                48: t.iptv.every2d,
                72: t.iptv.every3d,
                168: t.iptv.weekly,
              },
            ),
            SettingBuilder<String>(
              setting: Settings.iptvUserAgent,
              builder: (context, value, set) => ListTile(
                title: Text(t.iptv.customUserAgent),
                subtitle: Text(value.isEmpty ? t.iptv.userAgentUnset : value, maxLines: 2),
                trailing: const LiveIcon(LiveIcons.edit),
                onTap: () async {
                  final agent = await askText(
                    context,
                    title: t.iptv.customUserAgent,
                    initial: value,
                    hint: t.iptv.userAgentExample,
                    helper: t.iptv.userAgentHint,
                  );
                  if (agent != null) set(agent);
                },
              ),
            ),
            const SizedBox(height: Space.s6),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistAction { sync, rename, userAgent, autoSync, copySource, delete }

class _PlaylistTile extends StatelessWidget {
  const new({required this.playlist, required this.busy, required this.onSync, required this.onAction});

  final IptvPlaylistRecord playlist;
  final bool busy;
  final VoidCallback onSync;
  final ValueChanged<_PlaylistAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = playlist.lastError;
    final status = playlist.lastSyncAt == null && error == null
        ? t.iptv.notSyncedHint
        : t.iptv.channelsAndSynced(n: playlist.channelCount, synced: syncedText(playlist.lastSyncAt));
    return ListTile(
      leading: LiveIcon(playlist.isRemote ? LiveIcons.cloud : LiveIcons.file),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          if (error != null)
            Text(
              t.iptv.lastSyncFailed(error: error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (playlist.isRemote && !playlist.autoSync) Text(t.iptv.noAutoSync),
        ],
      ),
      isThreeLine: error != null || (playlist.isRemote && !playlist.autoSync),
      trailing: busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<_PlaylistAction>(
              icon: const LiveIcon(LiveIcons.more),
              tooltip: t.common.more,
              onSelected: onAction,
              itemBuilder: (context) => [
                PopupMenuItem(value: _PlaylistAction.sync, child: Text(t.common.sync)),
                PopupMenuItem(value: _PlaylistAction.rename, child: Text(t.common.rename)),
                const PopupMenuItem(value: _PlaylistAction.userAgent, child: Text('User-Agent')),
                if (playlist.isRemote) ...[
                  CheckedMenuItem(
                    value: _PlaylistAction.autoSync,
                    checked: playlist.autoSync,
                    child: Text(t.iptv.autoSync),
                  ),
                  // An Xtream source is a reference; its address holds the password.
                  if (!isXtreamSource(playlist.source))
                    PopupMenuItem(value: _PlaylistAction.copySource, child: Text(t.iptv.copySource)),
                ],
                PopupMenuItem(value: _PlaylistAction.delete, child: Text(t.common.delete)),
              ],
            ),
      onTap: busy ? null : onSync,
    );
  }
}

/// Text shared into the app that is a playlist (spec/modules/iptv.md §6): a
/// single http(s) URL ending in `.m3u`, `.m3u8`, `.txt` or `.json`, or M3U
/// content itself; null for anything else.
IptvImportRequest? iptvShareRequest(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('#EXTM3U') || trimmed.contains('\n#EXTINF:')) {
    return IptvImportRequest(bytes: utf8.encode(trimmed), fileName: t.iptv.sharedFileName);
  }
  if (trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) return null;
  final path = uri.path.toLowerCase();
  const extensions = ['.m3u', '.m3u8', '.txt', '.json'];
  return extensions.any(path.endsWith) ? IptvImportRequest(url: trimmed) : null;
}

class _XtreamDialog extends StatefulWidget {
  const new();

  @override
  State<_XtreamDialog> createState() => _XtreamDialogState();
}

class _XtreamDialogState extends State<_XtreamDialog> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final account = XtreamAccount.tryParse(server: _server.text, username: _user.text, password: _password.text);
    if (account == null) {
      setState(() => _error = t.iptv.xtreamHint);
      return;
    }
    Navigator.pop(context, account);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.iptv.xtreamSignIn),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('xtream-server'),
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: t.iptv.serverAddress, hintText: 'http://example.com:8080'),
          ),
          TextField(
            key: const ValueKey('xtream-user'),
            controller: _user,
            decoration: InputDecoration(labelText: t.common.username),
          ),
          TextField(
            key: const ValueKey('xtream-password'),
            controller: _password,
            obscureText: _hidden,
            decoration: InputDecoration(
              labelText: t.common.password,
              suffixIcon: IconButton(
                tooltip: _hidden ? t.iptv.showPassword : t.iptv.hidePassword,
                icon: LiveIcon(LiveIcons.showPassword, filled: !_hidden),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.s2),
          Text(
            _error ?? t.iptv.xtreamStorageNote,
            style: TextStyle(
              color: _error == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
      FilledButton(onPressed: _submit, child: Text(t.iptv.signInAndImport)),
    ],
  );
}
