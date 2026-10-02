import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/i18n/i18n.dart';

/// What is imported.
enum IptvImportKind {
  /// A playlist (M3U, M3U8, TXT).
  playlist,

  /// A programme guide (XMLTV, gzip, JSON).
  guide,
}

/// Where an import reads from.
enum IptvImportOrigin {
  /// A file on this device.
  file,

  /// An http(s) address.
  network,

  /// Pasted text (playlists only).
  text,

  /// The built-in default guide (guides only).
  defaultGuide,
}

/// Picks a local file for [kind]; null when the user gave up.
typedef IptvFilePicker = Future<File?> Function(BuildContext context, IptvImportKind kind);

/// How the page picks local files. The app overrides it with the system
/// picker (file_picker, `platform/plugins.dart`, M12.3); the default asks
/// for the file's path, for tests and a device without the plugin.
final Provider<IptvFilePicker> iptvFilePickerProvider = Provider<IptvFilePicker>((ref) => askForFilePath);

/// The file extensions of [kind] (3.x picker filters).
List<String> importExtensions(IptvImportKind kind) =>
    kind == IptvImportKind.playlist ? const ['m3u', 'm3u8', 'txt'] : const ['xml', 'gz', 'json'];

/// The title of the system file picker of [kind] (3.x said "选择备份文件").
String importPickerTitle(IptvImportKind kind) =>
    i18n(kind == IptvImportKind.playlist ? 'iptv_pick_playlist_file' : 'iptv_pick_guide_file');

/// A dialog title with its icon (3.x's IPTV dialogs): 20 px, the icon in the
/// primary colour.
class IptvDialogTitle extends StatelessWidget {
  /// Creates the title.
  const new(this.text, {this.icon, super.key});

  /// The words.
  final String text;

  /// The icon before them.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.t20.emphasis.copyWith(height: 1.3);
    if (icon == null) return Text(text, style: style);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// Asks where an import of [kind] reads from (3.x's "本地导入 / 网络导入"
/// dialog without buttons, plus pasted text for playlists and the default
/// guide for guides; each option says what it takes).
Future<IptvImportOrigin?> chooseImportOrigin(BuildContext context, IptvImportKind kind) =>
    showAppDialog<IptvImportOrigin>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final playlist = kind == IptvImportKind.playlist;
        Widget option(IptvImportOrigin origin, IconData icon, String title, String subtitle) => InkWell(
          key: ValueKey('iptv-origin-${origin.name}'),
          onTap: () => Navigator.pop(dialogContext, origin),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: scheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: dialogContext.textStyles.t15.emphasis),
                        const SizedBox(height: 2),
                        Text(subtitle, style: dialogContext.textStyles.t13.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        // The one dialog (U.1d): options with what each takes; a tap picks one
        // (3.x had no buttons).
        return AppDialog(
          title: i18n(playlist ? 'dialog_import_playlist_title' : 'dialog_import_epg_title'),
          icon: playlist ? AppIcons.playlistAdd : AppIcons.importGuide,
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                IptvImportOrigin.file,
                playlist ? AppIcons.localPlaylistFile : AppIcons.localGuideFile,
                i18n('local_import'),
                i18n(playlist ? 'iptv_origin_file_playlist' : 'iptv_origin_file_guide'),
              ),
              option(
                IptvImportOrigin.network,
                playlist ? AppIcons.networkSource : AppIcons.networkGuide,
                i18n('network_import'),
                i18n(playlist ? 'iptv_origin_network_playlist' : 'iptv_origin_network_guide'),
              ),
              if (playlist)
                option(
                  IptvImportOrigin.text,
                  AppIcons.pasteText,
                  i18n('iptv_origin_text'),
                  i18n('iptv_origin_text_desc'),
                )
              else
                option(
                  IptvImportOrigin.defaultGuide,
                  AppIcons.guide,
                  i18n('iptv_default_guide'),
                  i18n('iptv_default_guide_desc'),
                ),
            ],
          ),
        );
      },
    );

/// The default [IptvFilePicker]: the path of the file, checked to exist.
Future<File?> askForFilePath(BuildContext context, IptvImportKind kind) => showAppDialog<File>(
  context: context,
  builder: (_) => _FilePathDialog(kind: kind),
);

class _FilePathDialog extends StatefulWidget {
  const new({required this.kind});

  final IptvImportKind kind;

  @override
  State<_FilePathDialog> createState() => _FilePathDialogState();
}

class _FilePathDialogState extends State<_FilePathDialog> {
  final _path = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _submit() {
    var path = _path.text.trim();
    // Paths copied from a file manager often come quoted.
    if (path.length > 1 && path.startsWith('"') && path.endsWith('"')) path = path.substring(1, path.length - 1);
    final extensions = importExtensions(widget.kind);
    final String? error;
    if (path.isEmpty) {
      error = i18n('iptv_file_path_empty');
    } else if (!extensions.any((extension) => path.toLowerCase().endsWith('.$extension'))) {
      error = i18n(widget.kind == IptvImportKind.playlist ? 'iptv_unsupported_playlist' : 'iptv_unsupported_guide');
    } else if (!File(path).existsSync()) {
      error = i18n('iptv_file_missing');
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, File(path));
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: importPickerTitle(widget.kind),
    message: i18n('iptv_file_path_desc'),
    wide: true,
    autofocus: false,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('iptv-file-path'),
          controller: _path,
          autofocus: true,
          style: context.textStyles.t14,
          decoration: iptvFieldDecoration(
            context,
            label: i18n('iptv_file_path'),
            hint: Platform.isWindows ? r'D:\TV\list.m3u' : '/storage/emulated/0/Download/list.m3u',
            error: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      const DialogCancelButton(),
      DialogActionButton(key: const ValueKey('iptv-file-path-confirm'), label: i18n('confirm'), onPressed: _submit),
    ],
  );
}

/// Asks whether to replace the saved playlist or guide [name] (3.x
/// "该订阅名称已存在"; docs/ui/compare/U.9 "已有同名播放列表").
Future<bool> confirmReplace(BuildContext context, String name, IptvImportKind kind) => showAppConfirmDialog(
  context: context,
  title: i18n(kind == IptvImportKind.playlist ? 'iptv_replace_playlist_title' : 'iptv_replace_guide_title'),
  message: i18n(kind == IptvImportKind.playlist ? 'iptv_replace_playlist' : 'iptv_replace_guide', args: {'name': name}),
  confirmLabel: i18n('iptv_replace'),
  danger: true,
  confirmKey: const ValueKey('iptv-replace-confirm'),
);

/// Runs an import from the dialogs below; the dialog closes on success.
typedef IptvImportRun = Future<IptvImportResult> Function(String address, String name);

/// A labelled text field of the IPTV dialogs: the label above the box, an
/// outline that turns primary when focused and red with an error.
InputDecoration iptvFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? error,
  String? helper,
}) => dialogFieldDecoration(
  context,
  label: label,
  hint: hint,
  error: error,
  helper: helper,
).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always);

/// The network import dialog (3.x `_NetworkImportDialog`, docs/ui/compare/
/// U.9 c10): "订阅地址" and "名称（可选）" (the file name of the address when
/// empty). While it runs the bar shows and "取消" becomes "关闭" (closing
/// does not stop the import). A failure says why under the address and the
/// button becomes "重试"; it closes with the result when it succeeds.
class IptvNetworkImportDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.kind, required this.run, super.key});

  /// What is imported.
  final IptvImportKind kind;

  /// The import.
  final IptvImportRun run;

  @override
  State<IptvNetworkImportDialog> createState() => _NetworkImportDialogState();
}

class _NetworkImportDialogState extends State<IptvNetworkImportDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  bool _running = false;
  bool _failed = false;
  String? _urlError;
  String? _message;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _defaultName {
    final uri = Uri.tryParse(_url.text.trim());
    return uri == null || uri.path.isEmpty ? '' : IptvImporter.baseName(uri.path);
  }

  Future<void> _submit() async {
    if (_running) return;
    final url = _url.text.trim();
    final urlError = url.isEmpty
        ? i18n('enter_download_link')
        : !isHttpUrl(url)
        ? i18n('invalid_download_link')
        : null;
    if (urlError != null) {
      setState(() => _urlError = urlError);
      return;
    }
    setState(() {
      _running = true;
      _failed = false;
      _urlError = null;
      _message = null;
    });
    final name = _name.text.trim();
    IptvImportResult result;
    try {
      result = await widget.run(url, name.isEmpty ? _defaultName : name);
    } on Object catch (error) {
      result = IptvImportResult(IptvImportStatus.failed, error: error);
    }
    if (!mounted) return;
    if (result.isImported) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _running = false;
      if (result.status == IptvImportStatus.cancelled) {
        // Declining the replacement is not a failure (3.x said it was).
        _message = i18n('iptv_replace_declined');
      } else {
        _failed = true;
        _urlError = failureText(result, guide: widget.kind == IptvImportKind.guide);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final defaultName = _defaultName;
    return AppDialog(
      title: i18n(widget.kind == IptvImportKind.playlist ? 'iptv_network_playlist_title' : 'iptv_network_guide_title'),
      wide: true,
      autofocus: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('iptv-import-url'),
            controller: _url,
            readOnly: _running,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: context.textStyles.t14,
            decoration: iptvFieldDecoration(
              context,
              label: i18n('iptv_import_url'),
              hint: 'https://',
              error: _urlError,
            ),
            onSubmitted: (_) => unawaited(_submit()),
          ),
          if (!_running) ...[
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('iptv-import-name'),
              controller: _name,
              style: context.textStyles.t14,
              decoration: iptvFieldDecoration(
                context,
                label: i18n('iptv_import_name'),
                hint: defaultName.isEmpty ? i18n('iptv_import_name_hint') : defaultName,
                helper: i18n('iptv_import_name_helper'),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              key: const ValueKey('iptv-import-message'),
              style: context.textStyles.t13.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (_running) ...[
            const SizedBox(height: 16),
            ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator(minHeight: 4)),
            const SizedBox(height: 8),
            Text(i18n('iptv_import_running'), style: context.textStyles.t13),
          ],
        ],
      ),
      actions: [
        DialogCancelButton(label: i18n(_running ? 'close' : 'cancel')),
        DialogActionButton(
          key: const ValueKey('iptv-import-submit'),
          label: i18n(_failed ? 'retry' : 'iptv_import'),
          busy: _running,
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }
}

/// Imports pasted playlist text (3.x `importFromWebString`, used by shared
/// text; here also by hand, docs/ui/compare/U.9 c9). The name is required:
/// the text has no file name.
class IptvTextImportDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.run, super.key});

  /// The import (`address` is the text).
  final IptvImportRun run;

  @override
  State<IptvTextImportDialog> createState() => _TextImportDialogState();
}

class _TextImportDialogState extends State<IptvTextImportDialog> {
  final _text = TextEditingController();
  final _name = TextEditingController();
  bool _running = false;
  String? _textError;
  String? _nameError;
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_running) return;
    final text = _text.text.trim();
    final name = _name.text.trim();
    setState(() {
      _textError = text.isEmpty ? i18n('iptv_text_empty') : null;
      _nameError = name.isEmpty ? i18n('enter_file_name') : null;
    });
    if (_textError != null || _nameError != null) return;
    setState(() {
      _running = true;
      _message = null;
    });
    IptvImportResult result;
    try {
      result = await widget.run(text, name);
    } on Object catch (error) {
      result = IptvImportResult(IptvImportStatus.failed, error: error);
    }
    if (!mounted) return;
    if (result.isImported) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _running = false;
      _message = result.status == IptvImportStatus.cancelled
          ? i18n('iptv_replace_declined')
          : failureText(result, guide: false);
    });
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: i18n('iptv_origin_text'),
    wide: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('iptv-import-text'),
          controller: _text,
          readOnly: _running,
          minLines: 5,
          maxLines: 10,
          style: context.textStyles.t13.copyWith(fontFamily: 'monospace'),
          decoration: iptvFieldDecoration(
            context,
            label: i18n('iptv_import_text'),
            hint: '#EXTM3U\n#EXTINF:-1 group-title="…",CCTV-1\nhttps://…',
            error: _textError,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('iptv-import-text-name'),
          controller: _name,
          readOnly: _running,
          style: context.textStyles.t14,
          decoration: iptvFieldDecoration(context, label: i18n('iptv_import_text_name'), error: _nameError),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
        if (_running) ...[
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator(minHeight: 4)),
        ],
      ],
    ),
    actions: [
      DialogCancelButton(label: i18n(_running ? 'close' : 'cancel')),
      DialogActionButton(
        key: const ValueKey('iptv-import-text-submit'),
        label: i18n('iptv_import'),
        busy: _running,
        onPressed: () => unawaited(_submit()),
      ),
    ],
  );
}
