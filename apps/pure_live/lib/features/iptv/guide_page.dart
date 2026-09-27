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
import 'package:pure_live_app/i18n/strings.g.dart';

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

  static String _summary(IptvSyncResult result) =>
      t.iptv.guideSummary(channels: result.channels, programmes: result.items);

  Future<void> _addUrl({String url = ''}) async {
    final source = await askSource(context, title: t.iptv.addGuide, url: url, action: t.common.add);
    if (source == null || source.url.isEmpty) return;
    await _run(
      'add',
      () async => t.iptv.guideAdded(summary: _summary(await _sync.addGuideUrl(source.url, name: source.name))),
    );
  }

  Future<void> _addFile() async {
    final picked = await FilePicker.pickFiles(dialogTitle: t.iptv.pickGuide);
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    await _run(
      'add',
      () async => t.iptv.guideAdded(
        summary: _summary(await _sync.addGuideFile(fileName: file.name, bytes: await file.readAsBytes())),
      ),
    );
  }

  Future<void> _menu(IptvGuideSourceRecord source, _GuideAction action) async {
    final iptv = ref.read(storeProvider).iptv;
    switch (action) {
      case _GuideAction.sync:
        await _run('g${source.id}', () async => t.iptv.guideSynced(summary: _summary(await _sync.syncGuide(source))));
      case _GuideAction.rename:
        final name = await askText(context, title: t.common.rename, initial: source.name);
        if (name != null && name.isNotEmpty) await iptv.renameGuideSource(source.id, name);
      case _GuideAction.autoSync:
        await iptv.setGuideAutoSync(source.id, enabled: !source.autoSync);
      case _GuideAction.copySource:
        await Clipboard.setData(ClipboardData(text: source.source));
        _toast(t.iptv.sourceCopied);
      case _GuideAction.delete:
        if (await confirm(
          context,
          title: t.iptv.deleteGuide,
          message: t.iptv.deleteGuideConfirm(name: source.name),
        )) {
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
        title: Text(t.iptv.guide),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
                child: Text(t.iptv.guideHint),
              ),
              SettingsHeader(t.iptv.guideSources),
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
                      RadioListTile<int>(value: _none, title: Text(t.iptv.noGuide)),
                  ],
                ),
              ),
              if (sources.value?.isEmpty ?? false)
                ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(t.iptv.noGuides),
                  subtitle: Text(t.iptv.guideFormats),
                ),
              if (offered.isNotEmpty) ...[
                SettingsHeader(t.iptv.playlistGuide),
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
                      label: Text(t.iptv.addFromUrl),
                      onPressed: _busy.contains('add') ? null : _addUrl,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: Text(t.iptv.addFromFile),
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
          Text(t.iptv.channelsAndSynced(n: source.channelCount, synced: syncedText(source.lastSyncAt))),
          if (error != null)
            Text(
              t.iptv.lastSyncFailed(error: error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
      isThreeLine: error != null,
      secondary: busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<_GuideAction>(
              tooltip: t.common.more,
              onSelected: onAction,
              itemBuilder: (context) => [
                PopupMenuItem(value: _GuideAction.sync, child: Text(t.common.sync)),
                PopupMenuItem(value: _GuideAction.rename, child: Text(t.common.rename)),
                if (source.isRemote) ...[
                  CheckedPopupMenuItem(
                    value: _GuideAction.autoSync,
                    checked: source.autoSync,
                    child: Text(t.iptv.autoSync),
                  ),
                  PopupMenuItem(value: _GuideAction.copySource, child: Text(t.iptv.copySource)),
                ],
                PopupMenuItem(value: _GuideAction.delete, child: Text(t.common.delete)),
              ],
            ),
    );
  }
}
