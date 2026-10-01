import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/iptv/iptv_cards.dart';
import 'package:pure_live/pages/iptv/iptv_data.dart';
import 'package:pure_live/pages/iptv/iptv_import.dart';
import 'package:pure_live/pages/iptv/iptv_settings.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// IPTV: playlists, programme guides and their syncs (3.x
/// `lib/modules/iptv`: `IptvPage` "IPTV 设置" and `IptvManagePage`
/// "订阅源管理", now one page).
///
/// Routes: `RoutePath.kIptv`.
///
/// The data lives in `pure_live.db` (`StoreIptvLibrary`, M12.1) and changes
/// through `AppServices.iptvImporter`; the page shows it again after every
/// write, the background auto-sync included.
class IptvPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<IptvPage> createState() => _IptvPageState();
}

/// `meta` key set once the default guide was imported on a first visit
/// (3.x imported it on every visit without a guide).
const String defaultGuideMetaKey = 'iptv.defaultGuideLoaded';

class _IptvPageState extends ConsumerState<IptvPage> {
  /// Items with an operation running (`p:<id>`, `g:<id>`).
  final _busy = <String>{};
  bool _importing = false;
  ({int done, int total})? _syncAll;
  bool _defaultGuideChecked = false;
  bool _defaultGuideLoading = false;
  bool _defaultGuideFailed = false;

  IptvImporter? get _importer => ref.read(iptvImporterProvider);

  LiveStore get _store => ref.read(storeProvider);

  bool _blocked(String key) => _syncAll != null || _busy.contains(key);

  void _toast(String? message) {
    if (message != null && message.isNotEmpty) AppNavigator.toast(message);
  }

  // Guide selection -----------------------------------------------------------

  /// Keeps the selected guide valid: the first guide when none (or a
  /// deleted one) is selected (3.x selected the first only when none was),
  /// none when there are no guides; the stored name follows renames.
  void _checkSelection(IptvOverview overview) {
    final settings = _store.settings;
    final id = settings.get(Settings.selectedSourceId);
    final EpgSource? target;
    if (overview.guides.isEmpty) {
      target = null;
    } else {
      target = overview.guide(id) ?? overview.guides.first.source;
    }
    final name = target?.name ?? '';
    if (target?.id == id && name == settings.get(Settings.selectedSourceName)) return;
    if (target == null && id.isEmpty) return;
    unawaited(_select(target, announce: false));
  }

  Future<void> _select(EpgSource? source, {bool announce = true}) async {
    try {
      await _store.settings.setAll({
        Settings.selectedSourceId: source?.id ?? '',
        Settings.selectedSourceName: source?.name ?? '',
      });
      if (announce && mounted) _toast(i18n('epg_source_switched'));
    } on Object catch (error, stack) {
      log('Selecting the guide failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (announce && mounted) _toast(i18n('iptv_save_failed'));
    }
  }

  Future<void> _chooseGuide(IptvOverview overview) async {
    final current = _store.settings.get(Settings.selectedSourceId);
    final chosen = await showDialog<EpgSource>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          title: Text(i18n('select_epg_source'), style: dialogContext.textStyles.t16Bold),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: overview.guides.isEmpty
                ? Padding(padding: const EdgeInsets.all(12), child: Text(i18n('no_epg_sources_found')))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final info in overview.guides)
                        ListTile(
                          key: ValueKey('iptv-choose-${info.source.id}'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          selected: info.source.id == current,
                          selectedTileColor: colors.primary.withValues(alpha: 0.08),
                          leading: Icon(
                            info.source.id == current
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                          ),
                          title: Text(guideName(info.source)),
                          subtitle: Text(info.source.source, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(dialogContext, info.source),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(i18n('cancel')))],
        );
      },
    );
    if (chosen != null && mounted && chosen.id != current) await _select(chosen);
  }

  // Default guide -------------------------------------------------------------

  /// On the first visit without any guide, imports the default guide (3.x
  /// did it on every visit without one, so a deleted default came back).
  Future<void> _maybeLoadDefaultGuide(IptvOverview overview) async {
    if (_defaultGuideChecked) return;
    _defaultGuideChecked = true;
    if (overview.guides.isNotEmpty) return;
    try {
      if (await _store.meta.get(defaultGuideMetaKey) != null) return;
    } on Object {
      return;
    }
    if (mounted) await _loadDefaultGuide();
  }

  Future<void> _loadDefaultGuide() async {
    final importer = _importer;
    if (importer == null || _defaultGuideLoading) return;
    setState(() {
      _defaultGuideLoading = true;
      _defaultGuideFailed = false;
    });
    final result = await importer.importGuideFromUrl(
      IptvImporter.defaultGuideUrl,
      name: IptvImporter.hotName,
      force: true,
    );
    if (result.isImported) {
      try {
        await _store.meta.set(defaultGuideMetaKey, '1');
      } on Object catch (error, stack) {
        log('Saving the default guide flag failed', name: 'IptvPage', error: error, stackTrace: stack);
      }
    } else {
      log('Default guide: $result', name: 'IptvPage');
    }
    if (!mounted) return;
    setState(() {
      _defaultGuideLoading = false;
      _defaultGuideFailed = !result.isImported;
    });
    _toast(result.isImported ? i18n('iptv_default_guide_done') : null);
  }

  // Imports -------------------------------------------------------------------

  Future<IptvImportResult> _guarded(Future<IptvImportResult> Function() run) async {
    setState(() => _importing = true);
    try {
      return await run();
    } on Object catch (error, stack) {
      log('IPTV import failed', name: 'IptvPage', error: error, stackTrace: stack);
      return IptvImportResult(IptvImportStatus.failed, error: error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  IptvReplaceConfirm _confirmFor(IptvImportKind kind) =>
      (name) async => mounted && await confirmReplace(context, name, kind);

  Future<void> _import(IptvImportKind kind) async {
    final importer = _importer;
    if (importer == null) return;
    if (_importing || _defaultGuideLoading) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    final origin = await chooseImportOrigin(context, kind);
    if (origin == null || !mounted) return;
    final playlist = kind == IptvImportKind.playlist;
    switch (origin) {
      case IptvImportOrigin.defaultGuide:
        await _loadDefaultGuide();
      case IptvImportOrigin.file:
        final file = await ref.read(iptvFilePickerProvider)(context, kind);
        if (file == null || !mounted) return;
        final result = await _guarded(
          () => playlist
              ? importer.importPlaylistFile(file, confirmReplace: _confirmFor(kind))
              : importer.importGuideFile(file, confirmReplace: _confirmFor(kind)),
        );
        await _announce(kind, result);
      case IptvImportOrigin.network:
      case IptvImportOrigin.text:
        // The dialog shows failures itself; once it is closed (the import
        // keeps running), the result comes as a toast.
        var open = true;
        Future<IptvImportResult> run(String address, String name) async {
          final result = await _guarded(
            () => origin == IptvImportOrigin.text
                ? importer.importPlaylistText(address, name, confirmReplace: _confirmFor(kind))
                : playlist
                ? importer.importPlaylistFromUrl(address, name: name, confirmReplace: _confirmFor(kind))
                : importer.importGuideFromUrl(address, name: name, confirmReplace: _confirmFor(kind)),
          );
          if (!open) await _announce(kind, result);
          return result;
        }

        final result = await showDialog<IptvImportResult>(
          context: context,
          barrierDismissible: false,
          builder: (_) => origin == IptvImportOrigin.text
              ? IptvTextImportDialog(run: run)
              : IptvNetworkImportDialog(kind: kind, run: run),
        );
        open = false;
        if (result != null) await _announce(kind, result);
    }
  }

  Future<void> _announce(IptvImportKind kind, IptvImportResult result) async {
    final guide = kind == IptvImportKind.guide;
    if (!result.isImported) {
      _toast(failureText(result, guide: guide));
      return;
    }
    var name = '';
    try {
      final library = _importer!.library;
      final id = result.id ?? '';
      name = guide ? guideName((await library.guideSource(id))!) : playlistName((await library.playlist(id))!);
    } on Object {
      // The name is only for the message.
    }
    if (guide) {
      _toast(i18n('iptv_guide_imported', args: {'name': name}));
    } else if (result.issues.isEmpty) {
      _toast(i18n('iptv_playlist_imported', args: {'name': name}));
    } else {
      _toast(i18n('iptv_playlist_imported_skipped', args: {'name': name, 'count': '${result.issues.length}'}));
    }
  }

  // Item operations -----------------------------------------------------------

  Future<void> _runItem(String key, Future<void> Function() action) async {
    if (_blocked(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
    } on Object catch (error, stack) {
      log('IPTV operation failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (mounted) _toast(i18n('iptv_save_failed'));
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<IptvImportResult> _syncOne(Object item) {
    final importer = _importer!;
    return item is IptvPlaylist ? importer.syncPlaylist(item) : importer.syncGuide(item as EpgSource);
  }

  Future<void> _sync(Object item, String key, String name) => _runItem(key, () async {
    final result = await _syncOne(item);
    if (!mounted) return;
    _toast(
      result.isImported
          ? i18n('iptv_synced', args: {'name': name})
          : i18n(
              'iptv_sync_failed_named',
              args: {
                'name': name,
                'reason': failureText(result, guide: item is EpgSource) ?? '',
              },
            ),
    );
  });

  /// Syncs every network playlist and guide (3.x synced only those with
  /// automatic sync on).
  Future<void> _syncEverything(IptvOverview overview) async {
    if (_syncAll != null || _importer == null) return;
    final items = <Object>[
      for (final info in overview.playlists)
        if (info.playlist.isRemote) info.playlist,
      for (final info in overview.guides)
        if (info.source.isRemote) info.source,
    ];
    if (items.isEmpty) {
      _toast(i18n('iptv_sync_all_none'));
      return;
    }
    if (_busy.isNotEmpty || _importing) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    setState(() => _syncAll = (done: 0, total: items.length));
    var failed = 0;
    for (final (index, item) in items.indexed) {
      if (!mounted) return;
      try {
        if (!(await _syncOne(item)).isImported) failed++;
      } on Object catch (error, stack) {
        log('IPTV sync failed', name: 'IptvPage', error: error, stackTrace: stack);
        failed++;
      }
      if (mounted) setState(() => _syncAll = (done: index + 1, total: items.length));
    }
    if (!mounted) return;
    setState(() => _syncAll = null);
    _toast(
      failed == 0
          ? i18n('iptv_sync_all_done', args: {'count': '${items.length}'})
          : i18n('iptv_sync_all_partial', args: {'failed': '$failed', 'count': '${items.length}'}),
    );
  }

  Future<void> _setAutoUpdate(Object item, String key, bool value) => _runItem(key, () async {
    final library = _importer!.library;
    if (item is IptvPlaylist) {
      await library.updatePlaylist(item.copyWith(autoUpdate: value));
    } else if (item is EpgSource) {
      await library.updateGuideSource(item.copyWith(autoUpdate: value));
    }
    if (mounted) _toast(i18n(value ? 'iptv_auto_sync_on' : 'iptv_auto_sync_off'));
  });

  Future<void> _delete(Object item, String key, String name, int channels) async {
    if (_blocked(key)) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    final guide = item is EpgSource;
    final selected = guide && item.id == _store.settings.get(Settings.selectedSourceId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(
            i18n(guide ? 'iptv_delete_guide' : 'iptv_delete_playlist'),
            style: dialogContext.textStyles.t16Bold,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              [
                i18n(
                  guide ? 'iptv_delete_guide_message' : 'iptv_delete_playlist_message',
                  args: {'name': name, 'count': '$channels'},
                ),
                if (selected) i18n('iptv_delete_selected_guide'),
              ].join('\n\n'),
              style: dialogContext.textStyles.t14,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('iptv-delete-confirm'),
              style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(i18n('webdav_delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _runItem(key, () async {
      final importer = _importer!;
      final deleted = item is IptvPlaylist
          ? await importer.deletePlaylist(item)
          : await importer.deleteGuide(item as EpgSource);
      if (!deleted) {
        if (mounted) _toast(i18n('iptv_changed_meanwhile'));
        return;
      }
      if (selected) {
        // 3.x kept the deleted guide selected (the page showed its name and
        // the live room looked it up in vain).
        await _select((await importer.library.guideSources()).firstOrNull, announce: false);
      }
      if (mounted) _toast(i18n('iptv_deleted', args: {'name': name}));
    });
  }

  Future<void> _cardAction(IptvCardAction action, String address, VoidCallback delete) async {
    switch (action) {
      case IptvCardAction.open:
        final remote = isHttpUrl(address);
        final uri = remote ? Uri.tryParse(address) : null;
        var opened = false;
        try {
          opened = remote ? uri != null && await AppNavigator.openExternal(uri) : await AppNavigator.openFile(address);
        } on Object {
          opened = false;
        }
        if (!opened && mounted) _toast(i18n('manage_page_open_failed'));
      case IptvCardAction.copy:
        await Clipboard.setData(ClipboardData(text: address));
        if (mounted) _toast(i18n('iptv_address_copied'));
      case IptvCardAction.delete:
        delete();
    }
  }

  // Settings ------------------------------------------------------------------

  Future<void> _set<T extends Object>(Setting<T> setting, T value, {String? message}) async {
    try {
      await _store.settings.set(setting, value);
      if (mounted) _toast(message);
    } on Object catch (error, stack) {
      log('Saving ${setting.key} failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (mounted) _toast(i18n('iptv_save_failed'));
    }
  }

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(iptvOverviewProvider, (_, next) {
      final overview = next.value;
      if (overview == null) return;
      _checkSelection(overview);
      unawaited(_maybeLoadDefaultGuide(overview));
    });
    final importer = ref.watch(iptvImporterProvider);
    final state = ref.watch(iptvOverviewProvider);
    final overview = state.value;
    final syncAll = _syncAll;
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('iptv_title')),
        actions: [
          IconButton(
            key: const ValueKey('iptv-sync-all'),
            tooltip: i18n('iptv_sync_all'),
            onPressed: overview == null || syncAll != null ? null : () => unawaited(_syncEverything(overview)),
            icon: syncAll != null
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: importer == null
          ? AppStatusView(type: AppStatusType.error, title: i18n('iptv_unavailable'))
          : ListView(
              physics: const PureLiveScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (overview == null && state.isLoading) ...[
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 12),
                ],
                if (syncAll != null) ...[
                  _readable(_SyncProgress(done: syncAll.done, total: syncAll.total)),
                  const SizedBox(height: 12),
                ],
                if (state.hasError && overview == null)
                  _readable(
                    IptvNotice(
                      icon: Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                      title: i18n('iptv_initial_load_failed'),
                      actions: [
                        TextButton(onPressed: () => ref.invalidate(iptvOverviewProvider), child: Text(i18n('retry'))),
                      ],
                    ),
                  ),
                ..._enableNotice(),
                if (overview != null) ...[
                  _readable(_overviewCard(overview)),
                  const SizedBox(height: 20),
                  ..._playlistSection(overview),
                  const SizedBox(height: 8),
                  ..._guideSection(overview),
                  const SizedBox(height: 8),
                ],
                ..._settingsSection(),
              ],
            ),
    );
  }

  Widget _readable(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );

  List<Widget> _enableNotice() {
    final platforms = watchSetting(ref, Settings.hotAreasList);
    if (platforms.contains(SiteIds.iptv)) return const [];
    return [
      _readable(
        IptvNotice(
          key: const ValueKey('iptv-not-enabled'),
          icon: Icons.info_outline_rounded,
          title: i18n('iptv_not_enabled'),
          text: i18n('iptv_not_enabled_desc'),
          actions: [
            FilledButton.tonal(
              key: const ValueKey('iptv-enable'),
              onPressed: () =>
                  unawaited(_set(Settings.hotAreasList, [...platforms, SiteIds.iptv], message: i18n('iptv_enabled'))),
              child: Text(i18n('iptv_enable')),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _overviewCard(IptvOverview overview) {
    final colors = Theme.of(context).colorScheme;
    final importBusy = _importing || _defaultGuideLoading;
    Widget button(IptvImportKind kind, IconData icon, String label) => FilledButton.tonalIcon(
      key: ValueKey('iptv-import-${kind.name}'),
      onPressed: () => unawaited(_import(kind)),
      icon: importBusy
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(label),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: [colors.primary.withValues(alpha: 0.12), colors.surfaceContainerLow]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: IptvStat(
                  icon: Icons.playlist_play_rounded,
                  value: '${overview.playlists.length}',
                  label: i18n('iptv_stat_playlists'),
                ),
              ),
              Expanded(
                child: IptvStat(
                  icon: Icons.live_tv_rounded,
                  value: '${overview.channelCount}',
                  label: i18n('iptv_stat_channels'),
                ),
              ),
              Expanded(
                child: IptvStat(
                  icon: Icons.event_note_rounded,
                  value: '${overview.guides.length}',
                  label: i18n('iptv_stat_guides'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              button(IptvImportKind.playlist, Icons.playlist_add_rounded, i18n('import_playlist')),
              button(IptvImportKind.guide, Icons.post_add_rounded, i18n('import_epg_source')),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _playlistSection(IptvOverview overview) {
    final now = ref.watch(iptvClockProvider)();
    return [
      context.buildGroupTitle(i18n('iptv_section_playlists', args: {'count': '${overview.playlists.length}'})),
      if (overview.playlists.isEmpty)
        _readable(
          IptvNotice(
            icon: Icons.playlist_add_rounded,
            title: i18n('iptv_no_playlists'),
            text: i18n('iptv_no_playlists_desc'),
            actions: [
              TextButton(
                onPressed: () => unawaited(_import(IptvImportKind.playlist)),
                child: Text(i18n('import_playlist')),
              ),
            ],
          ),
        ),
      for (final info in overview.playlists) _readable(_playlistCard(info.playlist, info.channels, now)),
    ];
  }

  Widget _playlistCard(IptvPlaylist playlist, int channels, DateTime now) {
    final key = 'p:${playlist.id}';
    final name = playlistName(playlist);
    void delete() => unawaited(_delete(playlist, key, name, channels));
    return IptvSourceCard(
      id: playlist.id,
      isGuide: false,
      name: name,
      address: playlist.source,
      badge: playlistBadge(playlist),
      isRemote: playlist.isRemote,
      details:
          '${i18n('iptv_channel_count', args: {'count': '$channels'})} · ${updatedText(playlist.lastRefresh, now)}',
      autoUpdate: playlist.autoUpdate,
      busy: _busy.contains(key),
      blocked: _blocked(key),
      onSync: () => unawaited(_sync(playlist, key, name)),
      onAutoUpdate: (value) => unawaited(_setAutoUpdate(playlist, key, value)),
      onAction: (action) => unawaited(_cardAction(action, playlist.source, delete)),
    );
  }

  List<Widget> _guideSection(IptvOverview overview) {
    final now = ref.watch(iptvClockProvider)();
    final selectedId = watchSetting(ref, Settings.selectedSourceId);
    final selected = overview.guide(selectedId);
    return [
      context.buildGroupTitle(i18n('iptv_section_guides', args: {'count': '${overview.guides.length}'})),
      context.buildModernCard([
        context.buildTile(
          icon: Icons.tv_rounded,
          title: i18n('active_epg_source'),
          subtitle: selected == null ? i18n('please_select_epg_source') : guideName(selected),
          subtitleColor: selected == null ? Colors.orange : null,
          onTap: () => unawaited(_chooseGuide(overview)),
        ),
      ]),
      const SizedBox(height: 12),
      if (_defaultGuideLoading)
        _readable(
          IptvNotice(
            key: const ValueKey('iptv-default-guide-loading'),
            icon: Icons.downloading_rounded,
            title: i18n('iptv_default_guide_loading'),
            text: i18n('iptv_default_guide_loading_desc'),
          ),
        )
      else if (_defaultGuideFailed)
        _readable(
          IptvNotice(
            key: const ValueKey('iptv-default-guide-failed'),
            icon: Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            title: i18n('iptv_default_epg_unavailable'),
            actions: [
              TextButton(onPressed: () => unawaited(_loadDefaultGuide()), child: Text(i18n('retry'))),
              TextButton(
                onPressed: () => unawaited(_import(IptvImportKind.guide)),
                child: Text(i18n('import_epg_source')),
              ),
            ],
          ),
        )
      else if (overview.guides.isEmpty)
        _readable(
          IptvNotice(
            icon: Icons.event_note_rounded,
            title: i18n('iptv_no_guides'),
            text: i18n('iptv_no_guides_desc'),
            actions: [
              TextButton(onPressed: () => unawaited(_loadDefaultGuide()), child: Text(i18n('iptv_default_guide'))),
              TextButton(
                onPressed: () => unawaited(_import(IptvImportKind.guide)),
                child: Text(i18n('import_epg_source')),
              ),
            ],
          ),
        ),
      for (final info in overview.guides) _readable(_guideCard(info.source, info.channels, now, selectedId)),
    ];
  }

  Widget _guideCard(EpgSource source, int channels, DateTime now, String selectedId) {
    final key = 'g:${source.id}';
    final name = guideName(source);
    void delete() => unawaited(_delete(source, key, name, channels));
    return IptvSourceCard(
      id: source.id,
      isGuide: true,
      name: name,
      address: source.source,
      badge: guideBadge(source),
      isRemote: source.isRemote,
      details:
          '${i18n('iptv_guide_channel_count', args: {'count': '$channels'})} · ${updatedText(source.lastRefresh, now)}',
      autoUpdate: source.autoUpdate,
      busy: _busy.contains(key),
      blocked: _blocked(key),
      selected: source.id == selectedId,
      onSelect: () => unawaited(_select(source)),
      onSync: () => unawaited(_sync(source, key, name)),
      onAutoUpdate: (value) => unawaited(_setAutoUpdate(source, key, value)),
      onAction: (action) => unawaited(_cardAction(action, source.source, delete)),
    );
  }

  List<Widget> _settingsSection() {
    final autoSync = watchSetting(ref, Settings.isAutoSyncEnabled);
    final hours = IptvImporter.normalizeAutoSyncHours(watchSetting(ref, Settings.autoSyncHoursInterval));
    final userAgent = watchSetting(ref, Settings.customIptvUserAgent);
    return [
      context.buildGroupTitle(i18n('iptv_section_settings')),
      context.buildModernCard([
        context.buildSwitchTile(
          icon: Icons.autorenew_rounded,
          title: i18n('iptv_auto_sync_title'),
          subtitle: i18n('iptv_auto_sync_desc'),
          isLong: true,
          value: autoSync,
          onChanged: (value) => unawaited(_set(Settings.isAutoSyncEnabled, value)),
        ),
        if (autoSync)
          context.buildTile(
            icon: Icons.schedule_rounded,
            title: i18n('sync_interval_title'),
            subtitle: i18n('sync_interval_hours', args: {'hour': '$hours'}),
            onTap: () async {
              final chosen = await chooseSyncInterval(context, hours);
              if (chosen != null && chosen != hours) {
                await _set(Settings.autoSyncHoursInterval, chosen, message: i18n('settings_saved'));
              }
            },
          ),
        context.buildTile(
          icon: Icons.badge_outlined,
          title: i18n('custom_ua_title'),
          subtitle: userAgent.isEmpty ? i18n('iptv_ua_default') : userAgent,
          onTap: () async {
            final value = await editUserAgent(context, userAgent);
            if (value != null && value != userAgent) {
              await _set(Settings.customIptvUserAgent, value, message: i18n('iptv_ua_saved'));
            }
          },
        ),
      ]),
    ];
  }
}

class _SyncProgress extends StatelessWidget {
  const new({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        i18n('iptv_sync_all_running', args: {'done': '$done', 'total': '$total'}),
        style: context.textStyles.t13Muted,
      ),
      const SizedBox(height: 6),
      LinearProgressIndicator(value: total == 0 ? null : done / total, minHeight: 4),
    ],
  );
}
