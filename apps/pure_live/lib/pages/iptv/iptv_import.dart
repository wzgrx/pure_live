import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/iptv/iptv_data.dart';

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

/// How the page picks local files. The app has no file-picker plugin yet
/// (3.x used `file_picker`), so the default asks for the file's path; the
/// app can override this once it has one.
final Provider<IptvFilePicker> iptvFilePickerProvider = Provider<IptvFilePicker>((ref) => askForFilePath);

/// The file extensions of [kind] (3.x picker filters).
List<String> importExtensions(IptvImportKind kind) =>
    kind == IptvImportKind.playlist ? const ['m3u', 'm3u8', 'txt'] : const ['xml', 'gz', 'json'];

/// Asks where an import of [kind] reads from (3.x's "local / network"
/// dialog, plus pasted text and the default guide).
Future<IptvImportOrigin?> chooseImportOrigin(BuildContext context, IptvImportKind kind) => showDialog<IptvImportOrigin>(
  context: context,
  builder: (dialogContext) {
    final colors = Theme.of(dialogContext).colorScheme;
    final playlist = kind == IptvImportKind.playlist;
    Widget option(IptvImportOrigin origin, IconData icon, String title, String subtitle) => ListTile(
      key: ValueKey('iptv-origin-${origin.name}'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: colors.primary),
      title: Text(title, style: dialogContext.textStyles.t15SemiBold),
      subtitle: Text(subtitle, style: dialogContext.textStyles.t12Muted),
      onTap: () => Navigator.pop(dialogContext, origin),
    );
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      title: Text(
        i18n(playlist ? 'dialog_import_playlist_title' : 'dialog_import_epg_title'),
        style: dialogContext.textStyles.t16Bold,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              IptvImportOrigin.network,
              Icons.public_rounded,
              i18n('network_import'),
              i18n(playlist ? 'iptv_origin_network_playlist' : 'iptv_origin_network_guide'),
            ),
            option(
              IptvImportOrigin.file,
              Icons.folder_open_rounded,
              i18n('local_import'),
              importExtensions(kind).map((extension) => '.$extension').join(' / '),
            ),
            if (playlist)
              option(
                IptvImportOrigin.text,
                Icons.content_paste_rounded,
                i18n('iptv_origin_text'),
                i18n('iptv_origin_text_desc'),
              )
            else
              option(
                IptvImportOrigin.defaultGuide,
                Icons.auto_awesome_rounded,
                i18n('iptv_default_guide'),
                i18n('iptv_default_guide_desc'),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(i18n('cancel')))],
    );
  },
);

/// The default [IptvFilePicker]: the path of the file, checked to exist.
Future<File?> askForFilePath(BuildContext context, IptvImportKind kind) => showDialog<File>(
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
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    title: Text(i18n('local_import'), style: context.textStyles.t16Bold),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('iptv_file_path_desc'), style: context.textStyles.t13Muted),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('iptv-file-path'),
            controller: _path,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: i18n('iptv_file_path'),
              hintText: Platform.isWindows ? r'D:\TV\list.m3u' : '/storage/emulated/0/Download/list.m3u',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(onPressed: _submit, child: Text(i18n('confirm'))),
    ],
  );
}

/// Asks whether to replace the saved playlist or guide [name] (3.x
/// "该订阅名称已存在" dialog).
Future<bool> confirmReplace(BuildContext context, String name, IptvImportKind kind) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(i18n('provider_name_exists_tip'), style: dialogContext.textStyles.t16Bold),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            i18n(
              kind == IptvImportKind.playlist ? 'iptv_replace_playlist' : 'iptv_replace_guide',
              args: {'name': name},
            ),
            style: dialogContext.textStyles.t14,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('iptv-replace-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('iptv_replace')),
          ),
        ],
      ),
    ) ??
    false;

/// Runs an import from the dialogs below; the dialog closes on success.
typedef IptvImportRun = Future<IptvImportResult> Function(String address, String name);

/// The network import dialog (3.x `_NetworkImportDialog`): the address and
/// an optional name (the file name of the address when empty). It stays
/// open with the reason when the import fails, and closes with the result
/// when it succeeds.
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
      _message = result.status == IptvImportStatus.cancelled
          ? i18n('iptv_replace_declined')
          : failureText(result, guide: widget.kind == IptvImportKind.guide);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final defaultName = _defaultName;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(
        i18n(widget.kind == IptvImportKind.playlist ? 'iptv_network_playlist_title' : 'iptv_network_guide_title'),
        style: context.textStyles.t16Bold,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('iptv-import-url'),
              controller: _url,
              readOnly: _running,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: i18n('download_url'),
                hintText: 'https://',
                errorText: _urlError,
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('iptv-import-name'),
              controller: _name,
              readOnly: _running,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: i18n('iptv_import_name'),
                hintText: defaultName.isEmpty ? i18n('iptv_import_name_hint') : defaultName,
                helperText: i18n('iptv_import_name_helper'),
                helperMaxLines: 2,
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                key: const ValueKey('iptv-import-message'),
                style: context.textStyles.t13.copyWith(color: colors.error),
              ),
            ],
            if (_running) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(i18n('iptv_import_running'), style: context.textStyles.t12Muted),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n(_running ? 'close' : 'cancel'))),
        FilledButton(
          key: const ValueKey('iptv-import-submit'),
          onPressed: _running ? null : () => unawaited(_submit()),
          child: Text(i18n('iptv_import')),
        ),
      ],
    );
  }
}

/// Imports pasted playlist text (3.x `importFromWebString`, used by shared
/// text; here also by hand). The name is required: the text has no file
/// name.
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
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    title: Text(i18n('iptv_origin_text'), style: context.textStyles.t16Bold),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('iptv-import-text'),
            controller: _text,
            readOnly: _running,
            minLines: 5,
            maxLines: 10,
            style: context.textStyles.t13.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: '#EXTM3U\n#EXTINF:-1 group-title="…",CCTV-1\nhttps://…',
              errorText: _textError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('iptv-import-text-name'),
            controller: _name,
            readOnly: _running,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: i18n('iptv_import_name'),
              errorText: _nameError,
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
          if (_running) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('iptv-import-text-submit'),
        onPressed: _running ? null : () => unawaited(_submit()),
        child: Text(i18n('iptv_import')),
      ),
    ],
  );
}
