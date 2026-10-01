import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The font manager (3.x `FontFamilyManagerPage`), one for the app font and
/// one for the danmaku font: the system font, then the cloud list with
/// download (progress, cancel), choose (weight for multi-file families),
/// delete, open the folder, back to the system font.
class FontManagerPage extends ConsumerStatefulWidget {
  /// Creates the page; [danmaku] manages the danmaku font.
  const new({this.danmaku = false, super.key});

  /// Whether the danmaku font is managed.
  final bool danmaku;

  @override
  ConsumerState<FontManagerPage> createState() => _FontManagerPageState();
}

class _FontManagerPageState extends ConsumerState<FontManagerPage> {
  late final FontLibrary _library = ref.read(fontLibraryProvider);
  List<FontFamily>? _families;
  String? _busy;
  (int, int)? _progress;
  CancelToken? _cancel;

  StringSetting get _name => widget.danmaku ? Settings.danmakuFontFamilyName : Settings.fontFamilyName;

  StringSetting get _file => widget.danmaku ? Settings.danmakuFontFamilyFileName : Settings.fontFamilyFileName;

  SettingsStore get _settings => ref.read(storeProvider).settings;

  @override
  void initState() {
    super.initState();
    _library.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    _cancel?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final families = await _library.families();
    if (mounted) setState(() => _families = families);
  }

  Future<void> _useSystem() async {
    await _settings.reset(_name);
    await _settings.reset(_file);
    AppNavigator.toast(i18n('font_reset_default'));
  }

  Future<void> _apply(FontFamily family) async {
    var fileName = '';
    final files = _library.filesOf(family.id);
    if (files.length > 1) {
      final picked = await _pickWeight(family, files);
      if (picked == null) return;
      fileName = picked;
    }
    if (!await _library.load(family.id, fileName: fileName)) {
      AppNavigator.toast(i18n('font_not_downloaded_or_corrupted'));
      return;
    }
    await _settings.set(_name, family.id);
    await _settings.set(_file, fileName);
    AppNavigator.toast(
      fileName.isEmpty
          ? i18n('font_toast_global', args: {'name': family.name})
          : i18n(
              'font_toast_exclusive',
              args: {'name': family.name, 'subName': p.basenameWithoutExtension(fileName).split('-').last},
            ),
    );
  }

  Future<void> _download(FontFamily family) async {
    if (_busy != null) return;
    final cancel = CancelToken();
    setState(() {
      _busy = family.id;
      _progress = (0, family.files.length);
      _cancel = cancel;
    });
    try {
      await _library.download(
        family,
        cancel: cancel,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
      if (mounted) await _apply(family);
    } on DownloadException catch (error) {
      if (error.reason != DownloadFailure.cancelled) AppNavigator.toast(i18n('font_load_failed'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = null;
          _cancel = null;
        });
      }
    }
  }

  Future<void> _delete(FontFamily family) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('delete')),
        content: Text(i18n('settings_font_delete_confirm', args: {'name': family.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('font-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await _library.delete(family.id, _settings)) AppNavigator.toast(i18n('font_delete_failed'));
  }

  Future<void> _openFolder([String? id]) async {
    final folder = id == null ? _library.root : _library.folderOf(id);
    var opened = false;
    try {
      await folder.create(recursive: true);
      opened = await AppNavigator.openFile(folder.path);
    } on Object {
      opened = false;
    }
    if (!opened) AppNavigator.toast(i18n('open_font_dir_failed'));
  }

  Future<String?> _pickWeight(FontFamily family, List<File> files) => showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(i18n('font_selector_title', args: {'name': family.name})),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(i18n('font_selector_subtitle'), style: dialogContext.textStyles.t13),
        ),
        SimpleDialogOption(
          key: const ValueKey('font-weight-auto'),
          onPressed: () => Navigator.pop(dialogContext, ''),
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: Text(i18n('font_auto_weight')),
            subtitle: Text(i18n('font_auto_weight_desc')),
          ),
        ),
        for (final file in files)
          SimpleDialogOption(
            key: ValueKey('font-weight-${p.basename(file.path)}'),
            onPressed: () => Navigator.pop(dialogContext, p.basename(file.path)),
            child: ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: Text(
                i18n('font_lock_weight', args: {'label': p.basenameWithoutExtension(file.path).split('-').last}),
              ),
              subtitle: Text(i18n('font_lock_weight_desc')),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = watchSetting(ref, _name);
    final isSystem = current.isEmpty || current == _name.defaultValue;
    final families = _families;
    final systemName = !kIsWeb && Platform.isWindows ? 'Microsoft YaHei' : i18n('font_system_default');
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n(widget.danmaku ? 'change_danmaku_font_family' : 'font_family_settings')),
        actions: [
          IconButton(
            key: const ValueKey('font-open-folder-action'),
            tooltip: i18n('recorder_open_folder'),
            onPressed: () => unawaited(_openFolder()),
            icon: const Icon(Remix.folder_open_line),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          context.buildGroupTitle(i18n('factory_default_group')),
          context.buildModernCard([
            context.buildTile(
              icon: Icons.settings_suggest_outlined,
              title: systemName,
              subtitle: i18n('factory_default_desc'),
              trailing: isSystem ? Icon(Icons.check_circle, color: theme.colorScheme.primary) : null,
              onTap: isSystem || _busy != null ? null : () => unawaited(_useSystem()),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('cloud_font_group')),
          if (families == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final family in families) _FontCard(state: this, family: family, active: family.id == current),
        ],
      ),
    );
  }
}

class _FontCard extends StatelessWidget {
  const new({required this.state, required this.family, required this.active});

  final _FontManagerPageState state;
  final FontFamily family;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = state._library.sizeOf(family.id);
    final busy = state._busy == family.id;
    final locked = state._busy != null;
    final progress = state._progress;
    return Card(
      key: ValueKey('font-family-${family.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: active
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active ? theme.colorScheme.primary : theme.dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(family.name, style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (size != null) _Badge(formatBytes(size), color: theme.colorScheme.primary),
                if (family.license.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _Badge(family.license, color: theme.colorScheme.onSurfaceVariant),
                ],
              ],
            ),
            if (family.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(family.description, style: context.textStyles.t12.copyWith(color: theme.hintColor, height: 1.4)),
            ],
            const SizedBox(height: 8),
            if (busy && progress != null) ...[
              LinearProgressIndicator(value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      i18n('settings_font_downloading', args: {'done': '${progress.$1}', 'total': '${progress.$2}'}),
                      style: context.textStyles.t12,
                    ),
                  ),
                  TextButton(
                    key: ValueKey('font-cancel-${family.id}'),
                    onPressed: () => state._cancel?.cancel(),
                    child: Text(i18n('cancel')),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${family.files.length} ${i18n('font_units_suffix')}',
                      style: context.textStyles.t12.copyWith(color: theme.hintColor),
                    ),
                  ),
                  if (size != null) ...[
                    IconButton(
                      key: ValueKey('font-folder-${family.id}'),
                      tooltip: i18n('recorder_open_folder'),
                      onPressed: locked ? null : () => unawaited(state._openFolder(family.id)),
                      icon: const Icon(Remix.folder_open_line, size: 18),
                    ),
                    IconButton(
                      key: ValueKey('font-delete-${family.id}'),
                      tooltip: i18n('delete'),
                      onPressed: locked ? null : () => unawaited(state._delete(family)),
                      icon: Icon(Remix.delete_bin_6_line, size: 18, color: theme.colorScheme.error),
                    ),
                    const SizedBox(width: 4),
                    if (active)
                      Chip(
                        avatar: Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
                        label: Text(i18n('font_currently_active')),
                      )
                    else
                      FilledButton.tonal(
                        key: ValueKey('font-apply-${family.id}'),
                        onPressed: locked ? null : () => unawaited(state._apply(family)),
                        child: Text(i18n('apply')),
                      ),
                  ] else
                    FilledButton.tonalIcon(
                      key: ValueKey('font-download-${family.id}'),
                      onPressed: locked ? null : () => unawaited(state._download(family)),
                      icon: const Icon(Remix.download_cloud_2_line, size: 16),
                      label: Text(i18n(active ? 'settings_font_download_chosen' : 'download')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 140),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textStyles.t11.copyWith(color: color, fontWeight: FontWeight.w700),
    ),
  );
}
