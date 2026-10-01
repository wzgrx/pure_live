import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/settings_dialogs.dart';
import 'package:pure_live/pages/settings/settings_model.dart';
import 'package:pure_live/pages/settings/settings_tiles.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/images.dart';

/// The cover and avatar cache (3.x `CacheController`): its size on disk and
/// clearing it.
///
/// The files belong to cached_network_image's cache manager, which keeps
/// an index next to them; deleting the files alone would leave the index
/// pointing at nothing, so the disk part is cleared through [clearDisk],
/// which the app sets to the manager's `emptyCache` (the app does not
/// depend on flutter_cache_manager yet; see the module record).
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
}

/// "12.3 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// The image cache's size with a clear action (3.x `CacheDataSettingsPage`).
class ImageCacheTile extends StatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  State<ImageCacheTile> createState() => _ImageCacheTileState();
}

class _ImageCacheTileState extends State<ImageCacheTile> {
  int? _bytes;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    int? bytes;
    try {
      bytes = await ImageCacheTools.size();
    } on Object {
      bytes = null;
    }
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _busy = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: i18n('confirm_clear_local_cache'),
      message: i18n('settings_image_cache_confirm'),
      confirmLabel: i18n('clear'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ImageCacheTools.clear();
      AppNavigator.toast(i18n('cache_cleared'));
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    }
    await _measure();
  }

  @override
  Widget build(BuildContext context) => SettingActionTile(
    entry: widget.entry,
    icon: Remix.image_line,
    busy: _busy,
    subtitle: _bytes == null ? widget.entry.descriptionText : '${i18n('current_cache_size')}: ${formatBytes(_bytes!)}',
    trailing: TextButton(onPressed: _busy ? null : _clear, child: Text(i18n('clear'))),
    onTap: _busy ? null : _clear,
  );
}

/// Every setting back to its default (new; accounts, follows and history
/// stay).
class ResetAllTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingActionTile(
    entry: entry,
    icon: Remix.restart_line,
    destructive: true,
    onTap: () async {
      final confirmed = await showConfirmDialog(
        context: context,
        title: entry.titleText,
        message: i18n('settings_reset_all_confirm'),
        confirmLabel: i18n('reset'),
        destructive: true,
      );
      if (!confirmed) return;
      await ref.read(storeProvider).settings.resetAll();
      AppNavigator.toast(i18n('settings_reset_done'));
    },
  );
}

/// What is stored, read-only: counts and every section of a backup without
/// accounts, with copy (3.x `LocalConfigPreviewPage`).
class ConfigPreviewPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<ConfigPreviewPage> createState() => _ConfigPreviewPageState();
}

class _ConfigPreviewPageState extends ConsumerState<ConfigPreviewPage> {
  late final Future<(Map<String, Object?>, int, int, int)> _load = () async {
    final store = ref.read(storeProvider);
    final json = await BackupService(store).exportAll();
    final follows = await store.follows.count();
    final history = (await store.history.all()).length;
    final tags = (await store.tags.all()).length;
    return (json, follows, history, tags);
  }();

  static const _encoder = JsonEncoder.withIndent('  ');

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppNavigator.toast(i18n('settings_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _load,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(i18n('local_config_preview')),
            actions: [
              if (data != null)
                IconButton(
                  key: const ValueKey('settings-config-copy'),
                  tooltip: i18n('copy'),
                  icon: const Icon(Icons.copy_all_rounded),
                  onPressed: () => unawaited(_copy(_encoder.convert(data.$1))),
                ),
            ],
          ),
          body: switch (snapshot) {
            AsyncSnapshot(hasError: true) => AppStatusView(
              type: AppStatusType.error,
              title: i18n('settings_config_failed'),
              subtitle: '${snapshot.error}',
            ),
            AsyncSnapshot(data: final data?) => SettingsListView(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, count, icon) in [
                      ('favorites', data.$2, Remix.heart_3_line),
                      ('history', data.$3, Remix.history_line),
                      ('tags', data.$4, Remix.price_tag_3_line),
                    ])
                      Chip(avatar: Icon(icon, size: 18), label: Text('${i18n(label)} $count')),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(i18n('settings_config_preview_hint'), style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: 12),
                context.buildModernCard([
                  for (final MapEntry(:key, :value) in data.$1.entries)
                    if (value is Map || value is List)
                      ExpansionTile(
                        key: ValueKey('settings-config-$key'),
                        title: Text(key, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                          '${value is Map ? value.length : (value! as List).length}',
                          style: context.textStyles.t12,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: SelectableText(
                              _encoder.convert(value),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => unawaited(_copy(_encoder.convert(value))),
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: Text(i18n('copy')),
                            ),
                          ),
                        ],
                      )
                    else
                      ListTile(
                        title: Text(key, style: const TextStyle(fontFamily: 'monospace')),
                        trailing: Text('$value'),
                      ),
                ]),
              ],
            ),
            _ => const AppStatusView(type: AppStatusType.loading),
          },
        );
      },
    );
  }
}
