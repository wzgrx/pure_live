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
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The font page (3.x `FontFamilyManagerPage`; U.6b c13), one for the app
/// font and one for the danmaku font: the system font, then the cloud list
/// with download (progress, cancel), apply (a weight for multi-file
/// families), change the weight of the font in use, and a "⋮" menu to open
/// the font's folder or delete it (after a confirmation).
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
    final size = _library.sizeOf(family.id);
    final confirmed = await showConfirmDialog(
      context: context,
      title: i18n('settings_font_delete_title'),
      message: i18n(
        'settings_font_delete_message',
        args: {
          'name': family.name,
          'count': '${_library.filesOf(family.id).length}',
          'size': size == null ? '' : formatBytes(size),
        },
      ),
      confirmLabel: i18n('delete'),
      destructive: true,
    );
    if (!confirmed) return;
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

  /// The weight dialog (3.x `FontWeightSelectorDialog`): the one in use
  /// is marked.
  Future<String?> _pickWeight(FontFamily family, List<File> files) {
    final active = _settings.get(_name) == family.id;
    return showChoiceDialog<String>(
      context: context,
      title: i18n('font_selector_title', args: {'name': family.name}),
      hint: i18n('font_selector_subtitle'),
      selected: active ? _settings.get(_file) : '',
      options: [
        (value: '', label: i18n('font_auto_weight'), description: i18n('font_auto_weight_desc')),
        for (final file in files)
          (
            value: p.basename(file.path),
            label: i18n('font_lock_weight', args: {'label': p.basenameWithoutExtension(file.path).split('-').last}),
            description: i18n('font_lock_weight_desc'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = watchSetting(ref, _name);
    final isSystem = current.isEmpty || current == _name.defaultValue;
    final families = _families;
    final systemName = !kIsWeb && Platform.isWindows ? 'Microsoft YaHei' : i18n('font_system_default');
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: i18n(widget.danmaku ? 'change_danmaku_font_family' : 'settings_font'),
        embedded: SettingsPane.of(context),
        actions: [
          IconButton(
            key: const ValueKey('font-open-folder-action'),
            tooltip: i18n('recorder_open_folder'),
            onPressed: () => unawaited(_openFolder()),
            icon: const Icon(AppIcons.openFolder),
          ),
        ],
      ),
      body: SettingsPageBody(
        start: SettingsPane.of(context),
        children: [
          SettingsGroup(
            first: true,
            title: i18n('settings_font_group_system'),
            children: [
              SettingsRow(
                key: const ValueKey('font-system'),
                icon: AppIcons.systemFont,
                title: systemName,
                subtitle: i18n('factory_default_desc'),
                stackTrailing: false,
                enabled: _busy == null,
                trailing: ExcludeFocus(
                  child: IgnorePointer(
                    child: RadioGroup<bool>(
                      groupValue: isSystem,
                      onChanged: (_) {},
                      child: const Radio<bool>(key: ValueKey('font-system-radio'), value: true),
                    ),
                  ),
                ),
                onTap: isSystem ? null : () => unawaited(_useSystem()),
              ),
            ],
          ),
          SettingsGroup(
            card: false,
            title: i18n('settings_font_group_cloud', args: {'count': '${families?.length ?? 0}'}),
            children: [
              if (families == null)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: colors.primary)),
                )
              else
                for (final family in families) _FontCard(state: this, family: family, active: family.id == current),
            ],
          ),
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

  /// "⋮": open the folder, delete (the small menu, U.1d / B03).
  Widget _menu(BuildContext context, {required bool locked}) => AppMenuButton<String>(
    buttonKey: ValueKey('font-more-${family.id}'),
    enabled: !locked,
    tooltip: i18n('more'),
    icon: const Icon(AppIcons.moreVertical),
    onSelected: (action) => unawaited(action == 'delete' ? state._delete(family) : state._openFolder(family.id)),
    entries: () => [
      AppMenuEntry(
        key: ValueKey('font-folder-${family.id}'),
        value: 'folder',
        icon: AppIcons.openFolder,
        label: i18n('settings_font_open_folder'),
      ),
      AppMenuEntry(
        key: ValueKey('font-delete-${family.id}'),
        value: 'delete',
        icon: AppIcons.delete,
        label: i18n('delete'),
        danger: true,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final library = state._library;
    final size = library.sizeOf(family.id);
    final downloaded = size != null;
    final busy = state._busy == family.id;
    final locked = state._busy != null;
    final progress = state._progress;
    final weights = downloaded ? library.filesOf(family.id).length : family.files.length;
    final meta = [
      i18n('settings_font_weights', args: {'count': '$weights'}),
      if (family.license.isNotEmpty) family.license,
      if (size != null) formatBytes(size),
    ].join('  ·  ');
    // A font already loaded this session shows its name in itself (loading
    // a font only for its name would cost memory).
    final ownFont = library.registered.contains(family.id) ? family.id : null;

    final Widget actions;
    if (busy && progress != null) {
      actions = Row(
        key: ValueKey('font-progress-${family.id}'),
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            i18n('settings_font_downloading_short', args: {'done': '${progress.$1}', 'total': '${progress.$2}'}),
            style: context.textStyles.t12.tabular.copyWith(color: colors.onSurfaceVariant),
          ),
          TextButton(
            key: ValueKey('font-cancel-${family.id}'),
            onPressed: () => state._cancel?.cancel(),
            child: Text(i18n('cancel')),
          ),
        ],
      );
    } else {
      actions = Row(
        children: [
          Expanded(
            child: Text(meta, style: context.textStyles.t12.copyWith(color: colors.onSurfaceVariant)),
          ),
          if (!downloaded)
            FilledButton.tonalIcon(
              key: ValueKey('font-download-${family.id}'),
              onPressed: locked ? null : () => unawaited(state._download(family)),
              icon: const Icon(AppIcons.download, size: 18),
              label: Text(i18n(active ? 'settings_font_download_chosen' : 'settings_font_download')),
            )
          else ...[
            if (!active)
              FilledButton.tonal(
                key: ValueKey('font-apply-${family.id}'),
                onPressed: locked ? null : () => unawaited(state._apply(family)),
                child: Text(i18n('apply')),
              )
            else if (weights > 1)
              TextButton(
                key: ValueKey('font-weight-${family.id}'),
                onPressed: locked ? null : () => unawaited(state._apply(family)),
                child: Text(i18n('settings_font_change_weight')),
              ),
            _menu(context, locked: locked),
          ],
        ],
      );
    }

    return Padding(
      key: ValueKey('font-family-${family.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: active ? Border.all(color: colors.primary, width: 2) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      family.name,
                      style: context.textStyles.t16.copyWith(fontWeight: FontWeight.w600, fontFamily: ownFont),
                    ),
                  ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        key: ValueKey('font-active-${family.id}'),
                        avatar: Icon(AppIcons.selected, size: 16, color: colors.onSecondaryContainer),
                        label: Text(i18n('settings_font_in_use')),
                        backgroundColor: colors.secondaryContainer,
                        side: BorderSide.none,
                        labelStyle: context.textStyles.t12.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSecondaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              if (family.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    family.description,
                    style: context.textStyles.t13.copyWith(color: colors.onSurfaceVariant, height: 1.45),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}
