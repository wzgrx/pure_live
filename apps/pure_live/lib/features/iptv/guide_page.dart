import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_sync.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// Programme guide sources (F-IPTV-02): add from a URL or file, choose the
/// current one, sync, rename, delete; guides that playlists name are offered.
class IptvGuidePage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<IptvGuidePage> createState() => _IptvGuidePageState();
}

enum _GuideAction { sync, rename, autoSync, copySource, delete }

/// Value of the "no guide" radio.
const _none = -1;

class _IptvGuidePageState extends ConsumerState<IptvGuidePage> {
  final Set<String> _busy = {};

  IptvSync get _sync => ref.read(iptvSyncProvider);

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

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

  static String _summary(IptvSyncResult result) => '${result.channels} 个频道，${result.items} 个节目';

  Future<void> _addUrl({String url = ''}) async {
    final source = await askSource(context, title: '添加节目单', url: url, action: '添加');
    if (source == null || source.url.isEmpty) return;
    await _run('add', () async => '已添加：${_summary(await _sync.addGuideUrl(source.url, name: source.name))}');
  }

  Future<void> _addFile() async {
    final picked = await FilePicker.pickFiles(dialogTitle: '选择节目单（XMLTV、JSON，可以是 .gz）');
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    await _run(
      'add',
      () async => '已添加：${_summary(await _sync.addGuideFile(fileName: file.name, bytes: await file.readAsBytes()))}',
    );
  }

  Future<void> _menu(IptvGuideSourceRecord source, _GuideAction action) async {
    final iptv = ref.read(storeProvider).iptv;
    switch (action) {
      case _GuideAction.sync:
        await _run('g${source.id}', () async => '已同步：${_summary(await _sync.syncGuide(source))}');
      case _GuideAction.rename:
        final name = await askText(context, title: '重命名', initial: source.name);
        if (name != null && name.isNotEmpty) await iptv.renameGuideSource(source.id, name);
      case _GuideAction.autoSync:
        await iptv.setGuideAutoSync(source.id, enabled: !source.autoSync);
      case _GuideAction.copySource:
        await Clipboard.setData(ClipboardData(text: source.source));
        _toast('已复制来源地址');
      case _GuideAction.delete:
        if (await confirm(context, title: '删除节目单', message: '删除“${source.name}”和它的节目？')) {
          await _sync.deleteGuide(source);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(iptvGuideSourcesProvider);
    final playlists = ref.watch(iptvPlaylistsProvider).value ?? const [];
    final known = {for (final source in sources.value ?? const <IptvGuideSourceRecord>[]) source.source};
    final offered = {
      for (final playlist in playlists)
        if (playlist.guideUrl case final url? when !known.contains(url)) url,
    };
    final selected = (sources.value ?? const []).where((source) => source.selected).firstOrNull?.id ?? _none;
    return Scaffold(
      appBar: AppBar(
        title: const Text('节目单'),
        bottom: _busy.isEmpty
            ? null
            : const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
                child: Text('选一个节目单作为当前节目单；频道会按 tvg-id 和名称自动匹配。节目单只保存前后两天的节目。'),
              ),
              const SettingsHeader('节目单源'),
              RadioGroup<int>(
                groupValue: selected,
                onChanged: (id) {
                  final all = sources.value ?? const <IptvGuideSourceRecord>[];
                  unawaited(_sync.selectGuide(all.where((source) => source.id == id).firstOrNull));
                },
                child: Column(
                  children: [
                    for (final source in sources.value ?? const <IptvGuideSourceRecord>[])
                      _GuideTile(
                        source: source,
                        busy: _busy.contains('g${source.id}'),
                        onAction: (action) => _menu(source, action),
                      ),
                    if (sources.value?.isNotEmpty ?? false)
                      const RadioListTile<int>(value: _none, title: Text('不使用节目单')),
                  ],
                ),
              ),
              if (sources.value?.isEmpty ?? false)
                const ListTile(
                  leading: Icon(Icons.event_note_outlined),
                  title: Text('还没有节目单'),
                  subtitle: Text('支持 XMLTV（.xml、.xml.gz）和 JSON 节目单'),
                ),
              if (offered.isNotEmpty) ...[
                const SettingsHeader('播放列表提供的节目单'),
                for (final url in offered)
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: _busy.contains('add') ? null : () => _addUrl(url: url),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(Space.s4),
                child: Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('从网址添加'),
                      onPressed: _busy.contains('add') ? null : _addUrl,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('从文件添加'),
                      onPressed: _busy.contains('add') ? null : _addFile,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideTile extends StatelessWidget {
  const new({required this.source, required this.busy, required this.onAction});

  final IptvGuideSourceRecord source;
  final bool busy;
  final ValueChanged<_GuideAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = source.lastError;
    return RadioListTile<int>(
      value: source.id,
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${source.channelCount} 个频道 · ${syncedText(source.lastSyncAt)}'),
          if (error != null) Text('上次同步失败：$error', style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      isThreeLine: error != null,
      secondary: busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<_GuideAction>(
              tooltip: '更多',
              onSelected: onAction,
              itemBuilder: (context) => [
                const PopupMenuItem(value: _GuideAction.sync, child: Text('同步')),
                const PopupMenuItem(value: _GuideAction.rename, child: Text('重命名')),
                if (source.isRemote) ...[
                  CheckedPopupMenuItem(
                    value: _GuideAction.autoSync,
                    checked: source.autoSync,
                    child: const Text('自动同步'),
                  ),
                  const PopupMenuItem(value: _GuideAction.copySource, child: Text('复制来源地址')),
                ],
                const PopupMenuItem(value: _GuideAction.delete, child: Text('删除')),
              ],
            ),
    );
  }
}
