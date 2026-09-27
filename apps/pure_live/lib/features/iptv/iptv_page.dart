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
import 'package:pure_live_app/features/settings/setting_tiles.dart';

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

  static String _summary(String name, IptvSyncResult result) =>
      '“$name”：${result.channels} 个频道，${result.items} 条线路${result.issues > 0 ? '，跳过 ${result.issues} 行' : ''}';

  Future<void> _importUrl({String url = ''}) async {
    final source = await askSource(context, title: '从网址导入', url: url);
    if (source == null || source.url.isEmpty) return;
    await _run('import', () async {
      final result = await _sync.importUrl(source.url, name: source.name);
      final name = (await ref.read(storeProvider).iptv.playlist(result.id))?.name ?? '';
      return '已导入${_summary(name, result)}';
    });
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(dialogTitle: '选择播放列表（M3U、TXT、JSON）');
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    await _run('import', () async {
      final result = await _sync.importFile(fileName: file.name, bytes: await file.readAsBytes());
      final name = (await ref.read(storeProvider).iptv.playlist(result.id))?.name ?? file.name;
      return '已导入${_summary(name, result)}';
    });
  }

  Future<void> _importShared(IptvImportRequest request) async {
    final url = request.url;
    if (url != null) return await _importUrl(url: url);
    final bytes = request.bytes;
    if (bytes == null) return;
    final fileName = request.fileName ?? '分享的播放列表.m3u';
    final dot = fileName.lastIndexOf('.');
    final source = await askSource(
      context,
      title: '导入分享的播放列表',
      name: dot > 0 ? fileName.substring(0, dot) : fileName,
      askUrl: false,
    );
    if (source == null) return;
    await _run('import', () async {
      final result = await _sync.importFile(fileName: fileName, bytes: bytes, name: source.name);
      return '已导入${_summary(source.name.isEmpty ? fileName : source.name, result)}';
    });
  }

  Future<void> _syncAll() => _run('all', () async {
    final failed = await _sync.syncAll();
    return failed == 0 ? '全部同步完成' : '同步完成，$failed 个来源失败';
  });

  Future<void> _syncOne(IptvPlaylistRecord playlist) =>
      _run('p${playlist.id}', () async => '已同步${_summary(playlist.name, await _sync.syncPlaylist(playlist))}');

  Future<void> _menu(IptvPlaylistRecord playlist, _PlaylistAction action) async {
    final iptv = ref.read(storeProvider).iptv;
    switch (action) {
      case _PlaylistAction.sync:
        await _syncOne(playlist);
      case _PlaylistAction.rename:
        final name = await askText(context, title: '重命名', initial: playlist.name);
        if (name != null && name.isNotEmpty) await iptv.renamePlaylist(playlist.id, name);
      case _PlaylistAction.userAgent:
        final agent = await askText(
          context,
          title: '这个列表的 User-Agent',
          initial: playlist.userAgent ?? '',
          hint: '留空则用全局设置',
          helper: '下载列表和播放频道时发送；频道自己指定的优先',
        );
        if (agent != null) await iptv.setPlaylistUserAgent(playlist.id, agent);
      case _PlaylistAction.autoSync:
        await iptv.setPlaylistAutoSync(playlist.id, enabled: !playlist.autoSync);
      case _PlaylistAction.copySource:
        await Clipboard.setData(ClipboardData(text: playlist.source));
        _toast('已复制来源地址');
      case _PlaylistAction.delete:
        final confirmed = await confirm(
          context,
          title: '删除播放列表',
          message: '删除“${playlist.name}”和它的 ${playlist.channelCount} 个频道？关注的频道会保留，但会显示“频道不存在”。',
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
      appBar: AppBar(
        title: const Text('网络电视'),
        actions: [
          IconButton(
            tooltip: '全部同步',
            icon: const Icon(Icons.sync),
            onPressed: _busy.contains('all') || (playlists.value?.isEmpty ?? true) ? null : _syncAll,
          ),
        ],
        bottom: busy
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              const SettingsHeader('播放列表'),
              ...switch (playlists) {
                AsyncData(:final value) when value.isEmpty => [
                  const ListTile(
                    leading: Icon(Icons.live_tv_outlined),
                    title: Text('还没有播放列表'),
                    subtitle: Text('从文件或网址导入 M3U、TXT、JSON 播放列表，频道会出现在“发现 › 网络电视”里'),
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
                AsyncError() => [const ListTile(title: Text('读取播放列表失败'))],
                _ => [const Padding(padding: EdgeInsets.all(Space.s4), child: LinearProgressIndicator())],
              },
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
                child: Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('从网址导入'),
                      onPressed: _busy.contains('import') ? null : _importUrl,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('从文件导入'),
                      onPressed: _busy.contains('import') ? null : _importFile,
                    ),
                  ],
                ),
              ),
              const SettingsHeader('节目单'),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('节目单源'),
                subtitle: Text(
                  selectedGuide == null
                      ? (guides.isEmpty ? '未添加，导入 XMLTV 或 JSON 节目单后可以看节目和回看' : '未选择')
                      : '当前：${selectedGuide.name}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(iptvGuideLocation),
              ),
              const SettingsHeader('同步'),
              const SwitchSettingTile(setting: Settings.iptvAutoSync, title: '自动同步', subtitle: '启动 3 秒后同步到期的网址列表和节目单'),
              const ChoiceSettingTile<int>(
                setting: Settings.iptvAutoSyncHours,
                title: '同步间隔',
                labels: {6: '每 6 小时', 12: '每 12 小时', 24: '每天', 48: '每 2 天', 72: '每 3 天', 168: '每周'},
              ),
              SettingBuilder<String>(
                setting: Settings.iptvUserAgent,
                builder: (context, value, set) => ListTile(
                  title: const Text('自定义 User-Agent'),
                  subtitle: Text(value.isEmpty ? '未设置（使用播放器默认值）' : value, maxLines: 2),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final agent = await askText(
                      context,
                      title: '自定义 User-Agent',
                      initial: value,
                      hint: '例如 okhttp/4.12.0',
                      helper: '下载列表、节目单和播放频道时发送；列表或频道自己指定的优先',
                    );
                    if (agent != null) set(agent);
                  },
                ),
              ),
              const SizedBox(height: Space.s6),
            ],
          ),
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
        ? '未同步，点同步获取频道'
        : '${playlist.channelCount} 个频道 · ${syncedText(playlist.lastSyncAt)}';
    return ListTile(
      leading: Icon(playlist.isRemote ? Icons.cloud_outlined : Icons.description_outlined),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          if (error != null) Text('上次同步失败：$error', style: TextStyle(color: theme.colorScheme.error)),
          if (playlist.isRemote && !playlist.autoSync) const Text('不参与自动同步'),
        ],
      ),
      isThreeLine: error != null || (playlist.isRemote && !playlist.autoSync),
      trailing: busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<_PlaylistAction>(
              tooltip: '更多',
              onSelected: onAction,
              itemBuilder: (context) => [
                const PopupMenuItem(value: _PlaylistAction.sync, child: Text('同步')),
                const PopupMenuItem(value: _PlaylistAction.rename, child: Text('重命名')),
                const PopupMenuItem(value: _PlaylistAction.userAgent, child: Text('User-Agent')),
                if (playlist.isRemote) ...[
                  CheckedPopupMenuItem(
                    value: _PlaylistAction.autoSync,
                    checked: playlist.autoSync,
                    child: const Text('自动同步'),
                  ),
                  const PopupMenuItem(value: _PlaylistAction.copySource, child: Text('复制来源地址')),
                ],
                const PopupMenuItem(value: _PlaylistAction.delete, child: Text('删除')),
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
    return IptvImportRequest(bytes: utf8.encode(trimmed), fileName: '分享的播放列表.m3u');
  }
  if (trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) return null;
  final path = uri.path.toLowerCase();
  const extensions = ['.m3u', '.m3u8', '.txt', '.json'];
  return extensions.any(path.endsWith) ? IptvImportRequest(url: trimmed) : null;
}
