import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/images.dart';

/// The cover and avatar cache (3.x `CacheController`): its size on disk and
/// clearing it.
///
/// The files belong to cached_network_image's cache manager, which keeps
/// an index next to them; deleting the files alone would leave the index
/// pointing at nothing, so the disk part is cleared through [clearDisk],
/// which the app sets to the manager's `emptyCache` (M12.3).
abstract final class ImageCacheTools {
  /// The folder cached_network_image's default manager stores files in.
  static Future<Directory> Function() folder = () async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'libCachedImageData'));

  /// Clears the disk cache; null until the app provides it.
  static Future<void> Function()? clearDisk;

  /// Bytes in [folder]; 0 when it does not exist.
  static Future<int> size() async {
    final directory = await folder();
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // A file removed while counting.
        }
      }
    }
    return total;
  }

  /// Drops decoded images from memory and, when wired, the files on disk;
  /// the images on screen load again under a new cache key (3.x bumped
  /// `imageCacheEpoch` after clearing).
  static Future<void> clear() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await clearDisk?.call();
    imageCacheEpoch.value++;
  }

  /// "Refresh covers" (3.x `refreshImageCache()`): the files on disk and the
  /// decoded images go, and the images on screen load again under a new
  /// cache key ([imageCacheEpoch], read by `app.dart`).
  static Future<void> refreshCovers() async {
    await clearDisk?.call();
    PaintingBinding.instance.imageCache.clear();
    imageCacheEpoch.value++;
  }

  /// The timed cover refresh (3.x `refreshImageCache(refreshVisible: false)`):
  /// the files on disk and the decoded images that are not on screen go, so
  /// covers load fresh the next time they are shown; images on screen stay
  /// (no grid-wide reload).
  static Future<void> refreshInBackground() async {
    await clearDisk?.call();
    PaintingBinding.instance.imageCache.clear();
  }
}

/// Refreshes covers every [Settings.thumbnailRefreshInterval] minutes while
/// [Settings.autoRefreshThumbnails] is on (3.x `CacheController`'s
/// thumbnail timer), following changes of both.
final class CoverRefreshTimer {
  /// Creates the timer over the settings; `refresh` is the work (tests).
  new(this._settings, {Future<void> Function()? refresh}) : _refresh = refresh ?? ImageCacheTools.refreshInBackground;

  final SettingsStore _settings;
  final Future<void> Function() _refresh;
  Timer? _timer;
  StreamSubscription<Object>? _enabled;
  StreamSubscription<Object>? _interval;

  /// Starts following the settings.
  void start() {
    _enabled ??= _settings.watch(Settings.autoRefreshThumbnails).listen((_) => _schedule());
    _interval ??= _settings.watch(Settings.thumbnailRefreshInterval).listen((_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_settings.get(Settings.autoRefreshThumbnails)) return;
    final minutes = _settings.get(Settings.thumbnailRefreshInterval).clamp(5, 360);
    _timer = Timer.periodic(Duration(minutes: minutes), (_) => unawaited(_run()));
  }

  Future<void> _run() async {
    try {
      await _refresh();
    } on Object catch (error, stack) {
      log('Timed cover refresh failed', name: 'ImageCache', error: error, stackTrace: stack);
    }
  }

  /// Whether a refresh is scheduled.
  bool get active => _timer?.isActive ?? false;

  /// Stops the timer.
  Future<void> dispose() async {
    _timer?.cancel();
    await _enabled?.cancel();
    await _interval?.cancel();
  }
}

/// "12.34 MB" (3.x showed two decimals).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

/// The cache's size shared by the rows of the cache page (measured in the
/// background; only the rows that show it rebuild).
final class CacheSizeModel {
  new _();

  /// The one model of the app.
  static final CacheSizeModel instance = CacheSizeModel._();

  /// Bytes on disk; null until measured or when measuring failed.
  final ValueNotifier<int?> bytes = ValueNotifier(null);

  /// Whether a measurement runs.
  final ValueNotifier<bool> measuring = ValueNotifier(false);

  /// Measures again; false when it failed.
  Future<bool> measure() async {
    measuring.value = true;
    try {
      bytes.value = await ImageCacheTools.size();
      return true;
    } on Object {
      bytes.value = null;
      return false;
    } finally {
      measuring.value = false;
    }
  }
}

/// "当前缓存大小": the size and a refresh icon on the right; a tap measures
/// again, a spinner while it runs (U.6e e3).
class CacheSizeTile extends StatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  State<CacheSizeTile> createState() => _CacheSizeTileState();
}

class _CacheSizeTileState extends State<CacheSizeTile> {
  final CacheSizeModel _model = CacheSizeModel.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_model.measure());
  }

  Future<void> _measure() async {
    if (!await _model.measure()) AppNavigator.toast(i18n('cache_operation_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_model.bytes, _model.measuring]),
      builder: (context, _) {
        final bytes = _model.bytes.value;
        return SettingsRow(
          key: widget.entry.rowKey,
          icon: AppIcons.settingsCacheSize,
          title: widget.entry.titleText,
          subtitle: widget.entry.descriptionText,
          busy: _model.measuring.value,
          onTap: () => unawaited(_measure()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (bytes != null)
                Text(
                  formatBytes(bytes),
                  style: context.textStyles.t14.tabular.copyWith(color: colors.onSurfaceVariant),
                ),
              Icon(AppIcons.settingsRecount, size: 20, color: colors.onSurfaceVariant),
            ],
          ),
        );
      },
    );
  }
}

/// "清空本地缓存" (3.x): in red; asks first, saying how big the cache is;
/// while clearing only this row spins ("正在清除…"); then says how much was
/// freed, or how much is left when files were in use (U.6e e7).
class ClearCacheTile extends StatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  State<ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends State<ClearCacheTile> {
  bool _clearing = false;

  Future<void> _clear() async {
    final model = CacheSizeModel.instance;
    final before = model.bytes.value;
    final confirmed = await showConfirmDialog(
      context: context,
      title: i18n('confirm_clear_local_cache'),
      message: [
        i18n('confirm_clear_local_cache_desc'),
        if (before != null) i18n('settings_cache_now', args: {'size': formatBytes(before)}),
      ].join('\n'),
      confirmLabel: i18n('clear'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ImageCacheTools.clear();
      await model.measure();
      final after = model.bytes.value ?? 0;
      if (after > 0) {
        AppNavigator.toast(i18n('cache_clear_incomplete', args: {'size': (after / 1024 / 1024).toStringAsFixed(2)}));
      } else {
        AppNavigator.toast(i18n('settings_cache_cleared_freed', args: {'size': formatBytes(before ?? 0)}));
      }
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    }
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) => SettingActionTile(
    entry: widget.entry,
    icon: AppIcons.settingsClearCache,
    destructive: true,
    busy: _clearing,
    subtitle: _clearing ? i18n('settings_cache_clearing') : null,
    onTap: _clearing ? null : () => unawaited(_clear()),
  );
}

/// Re-downloads the covers and avatars on screen (3.x cache page's
/// "refresh thumbnails"); runs at once, so no chevron (U.6e e2).
class RefreshCoversTile extends StatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  State<RefreshCoversTile> createState() => _RefreshCoversTileState();
}

class _RefreshCoversTileState extends State<RefreshCoversTile> {
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await ImageCacheTools.refreshCovers();
      AppNavigator.toast(i18n('thumbnails_refreshed'));
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    }
    if (mounted) setState(() => _busy = false);
    unawaited(CacheSizeModel.instance.measure());
  }

  @override
  Widget build(BuildContext context) => SettingActionTile(
    entry: widget.entry,
    icon: AppIcons.settingsRefreshCovers,
    busy: _busy,
    onTap: _busy ? null : () => unawaited(_refresh()),
  );
}

/// Picks a folder for the download folder; null when the user cancelled.
typedef DownloadDirectoryPicker = Future<String?> Function();

/// The system folder picker of the download folder (file_picker in the app).
final Provider<DownloadDirectoryPicker?> downloadDirectoryPickerProvider = Provider((ref) => null);

/// The default download folder's path (null until read).
final FutureProvider<String> defaultDownloadPathProvider = FutureProvider(
  (ref) async => (await defaultDownloadDirectory(dataRoot: ref.read(appServicesProvider).dataRoot)).path,
);

/// Where update packages, downloaded files and fonts go (3.x cache page's
/// "download folder"): the path in use, "默认 / 自定义" on the right; a tap
/// opens the system's folder picker (checked for writing) (U.6e e5).
class DownloadDirectoryTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  Future<void> _choose(WidgetRef ref) async {
    final pick = ref.read(downloadDirectoryPickerProvider);
    String? picked;
    try {
      picked = pick == null ? null : await pick();
    } on Object {
      AppNavigator.toast(i18n('download_directory_pick_failed'));
      return;
    }
    if (picked == null || picked.trim().isEmpty) return;
    if (!await canWriteDirectory(Directory(picked))) {
      AppNavigator.toast(i18n('download_directory_permission_hint'));
      return;
    }
    await ref.read(storeProvider).settings.set(Settings.downloadDirectoryPath, picked.trim());
    AppNavigator.toast(i18n('download_directory_updated'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = watchSetting(ref, Settings.downloadDirectoryPath).trim();
    final canPick = ref.watch(downloadDirectoryPickerProvider) != null;
    final defaultPath = ref.watch(defaultDownloadPathProvider).value;
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsDownloadFolder,
      title: entry.titleText,
      subtitle: custom.isEmpty ? (defaultPath ?? i18n('download_directory_default_label')) : custom,
      value: i18n(custom.isEmpty ? 'default_option' : 'settings_download_custom'),
      enabled: canPick,
      onTap: () => unawaited(_choose(ref)),
    );
  }
}

/// "恢复默认下载目录": always there, greyed out while the default is in use
/// (U.6e e6).
class DownloadResetTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = watchSetting(ref, Settings.downloadDirectoryPath).trim();
    return SettingActionTile(
      entry: entry,
      icon: AppIcons.settingsDownloadReset,
      subtitle: i18n('settings_download_reset_desc'),
      disabledReason: i18n('settings_download_is_default'),
      onTap: custom.isEmpty
          ? null
          : () async {
              await ref.read(storeProvider).settings.reset(Settings.downloadDirectoryPath);
              AppNavigator.toast(i18n('download_directory_updated'));
            },
    );
  }
}

/// What is stored, read-only (3.x `LocalConfigPreviewPage`, U.6e e8–e12):
/// the counts, then every section of a backup without accounts and WebDAV
/// as a tree that scrolls with the page; a title while loading and on
/// error, an error that says what failed with "重新读取"; "备份与恢复" in
/// the app bar.
class ConfigPreviewPage extends ConsumerStatefulWidget {
  /// Creates the page; [onBack] is the back button when the page is the
  /// first of its navigator (the settings' one-column layout).
  const new({this.onBack, super.key});

  /// Back to the settings overview.
  final VoidCallback? onBack;

  @override
  ConsumerState<ConfigPreviewPage> createState() => _ConfigPreviewPageState();
}

typedef _Preview = ({Map<String, Object?> json, int follows, int history, int tags});

class _ConfigPreviewPageState extends ConsumerState<ConfigPreviewPage> {
  late Future<_Preview> _load = _read();

  Future<_Preview> _read() async {
    final store = ref.read(storeProvider);
    final json = await BackupService(store).exportAll();
    return (
      json: json,
      follows: await store.follows.count(),
      history: (await store.history.all()).length,
      tags: (await store.tags.all()).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final embedded = SettingsPane.of(context);
    return Scaffold(
      key: const ValueKey('settings-page-configPreview'),
      appBar: settingsAppBar(
        context,
        title: i18n('local_config_preview'),
        embedded: embedded,
        leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack),
        actions: [
          IconButton(
            key: const ValueKey('settings-config-backup'),
            tooltip: i18n('backup_recover'),
            icon: const Icon(AppIcons.settingsToBackup),
            onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kBackup)),
          ),
        ],
      ),
      body: FutureBuilder<_Preview>(
        future: _load,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(hasError: true) => AppStatusView(
            key: const ValueKey('settings-config-error'),
            type: AppStatusType.error,
            icon: AppIcons.failed,
            title: i18n('settings_config_read_failed'),
            subtitle: i18n('load_error_unknown'),
            details: '${snapshot.error}',
            buttonText: i18n('settings_config_reload'),
            buttonIcon: AppIcons.settingsReload,
            onButtonPressed: () => setState(() => _load = _read()),
          ),
          AsyncSnapshot(data: final data?) => _PreviewBody(data: data, start: embedded),
          _ => const AppStatusView(key: ValueKey('settings-config-loading'), type: AppStatusType.loading),
        },
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const new({required this.data, required this.start});

  final _Preview data;
  final bool start;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final modules = data.json.values.whereType<Map<Object?, Object?>>().length;
    final stats = [
      ('favorites', data.follows),
      ('history', data.history),
      ('tags', data.tags),
      ('config_modules', modules),
    ];
    final title = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.primary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = math.min(720, constraints.maxWidth - (start ? 48 : 32)).toDouble();
        final side = start ? 24.0 : math.max(16, (constraints.maxWidth - content) / 2).toDouble();
        final columns = content >= 560 ? 4 : 2;
        return CustomScrollView(
          key: const ValueKey('settings-config-scroll'),
          physics: const PureLiveScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 8, side, 0),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  width: content,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Text(i18n('settings_config_overview'), style: title),
                      ),
                      GridView.count(
                        crossAxisCount: columns,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: columns == 4 ? 1.7 : 2.2,
                        children: [
                          for (final (label, count) in stats)
                            DecoratedBox(
                              key: ValueKey('settings-config-stat-$label'),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: const BorderRadius.all(Radius.circular(16)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$count',
                                      style: context.textStyles.t20.tabular.copyWith(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    Text(
                                      i18n(label),
                                      style: context.textStyles.t12.copyWith(color: colors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      SettingsNote(
                        i18n('settings_config_format', args: {'version': '${data.json['backupVersion'] ?? '?'}'}),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                        child: Text(i18n('settings_config_all'), style: title),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 32),
              sliver: SliverConstrainedCrossAxis(
                maxExtent: content,
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                  ),
                  sliver: SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    sliver: JsonTreeSliver(data: data.json),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
