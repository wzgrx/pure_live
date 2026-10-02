import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/i18n/i18n.dart';

/// Lets the user pick a folder ([pickFile] false) or a backup file inside
/// the app, starting at [initial].
///
/// A local stand-in for a system picker (3.x used file_picker, which the
/// app does not have yet): it browses with `dart:io`, so on Android it sees
/// only the folders the app may read.
Future<String?> showFileBrowser(BuildContext context, {required String initial, required bool pickFile}) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => _FileBrowserDialog(initial: initial, pickFile: pickFile),
    );

class _FileBrowserDialog extends StatefulWidget {
  const new({required this.initial, required this.pickFile});

  final String initial;
  final bool pickFile;

  @override
  State<_FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<_FileBrowserDialog> {
  late final _path = TextEditingController(text: widget.initial);
  List<FileSystemEntity>? _entries;
  bool _failed = false;
  late String _current = widget.initial;

  @override
  void initState() {
    super.initState();
    unawaited(_open(widget.initial));
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _open(String path) async {
    final target = path.trim().isEmpty ? _current : p.normalize(path.trim());
    setState(() {
      _current = target;
      _path.text = target;
      _entries = null;
      _failed = false;
    });
    try {
      final entries = await Directory(target).list(followLinks: false).toList();
      final shown = [
        for (final entry in entries)
          if (!p.basename(entry.path).startsWith('.'))
            if (entry is Directory || (widget.pickFile && entry is File && _isBackupName(entry.path))) entry,
      ]..sort(_compare);
      if (mounted && _current == target) setState(() => _entries = shown);
    } on FileSystemException {
      if (mounted && _current == target) setState(() => _failed = true);
    }
  }

  static bool _isBackupName(String path) {
    final name = path.toLowerCase();
    return name.endsWith('.txt') || name.endsWith('.json');
  }

  static int _compare(FileSystemEntity a, FileSystemEntity b) {
    if ((a is Directory) != (b is Directory)) return a is Directory ? -1 : 1;
    return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
  }

  List<String> get _roots => [
    if (Platform.isAndroid) ...['/storage/emulated/0', '/storage/emulated/0/Download'],
    if (Platform.isWindows)
      for (final letter in 'CDEFGH'.split(''))
        if (Directory('$letter:\\').existsSync()) '$letter:\\',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _entries;
    final parent = p.dirname(_current);
    // The one dialog (U.1d), the long-content width; the list scrolls by
    // itself in a fixed height.
    return AppDialog(
      title: i18n(widget.pickFile ? 'select_recover_file' : 'backup_pick_folder'),
      wide: true,
      scrollable: false,
      autofocus: false,
      content: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('backup-browser-path'),
              controller: _path,
              decoration: dialogFieldDecoration(
                context,
                label: i18n('backup_browser_path'),
                suffixIcon: IconButton(
                  tooltip: i18n('backup_browser_open'),
                  icon: const Icon(AppIcons.forward),
                  onPressed: () => _open(_path.text),
                ),
              ),
              onSubmitted: _open,
            ),
            if (_roots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [for (final root in _roots) ActionChip(label: Text(root), onPressed: () => _open(root))],
                ),
              ),
            const SizedBox(height: 8),
            if (parent != _current)
              ListTile(
                dense: true,
                leading: const Icon(AppIcons.toTop),
                title: Text(i18n('backup_browser_up')),
                onTap: () => _open(parent),
              ),
            Expanded(
              child: _failed
                  ? Center(
                      child: Text(
                        i18n('backup_browser_unreadable'),
                        textAlign: TextAlign.center,
                        style: context.textStyles.t13.copyWith(color: colors.error),
                      ),
                    )
                  : entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? Center(child: Text(i18n('backup_browser_empty'), style: context.textStyles.t13Muted))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isDir = entry is Directory;
                        return ListTile(
                          dense: true,
                          leading: Icon(isDir ? AppIcons.webDavFolder : AppIcons.backupFile, color: colors.primary),
                          title: Text(p.basename(entry.path), maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => isDir ? _open(entry.path) : Navigator.pop(context, entry.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        const DialogCancelButton(),
        if (!widget.pickFile)
          DialogActionButton(
            key: const ValueKey('backup-browser-choose'),
            label: i18n('backup_browser_choose'),
            onPressed: _failed ? null : () => Navigator.pop(context, _current),
          ),
      ],
    );
  }
}
