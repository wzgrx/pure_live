import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/backup/backup_data.dart';

/// The name of a new backup file, 3.x's names (`purelive_<date>.txt`,
/// `purelive_favorites_<date>.txt`) so 3.x's file picker still lists them.
String backupFileName(BackupScope scope, DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}-${two(now.month)}-${two(now.day)}T${two(now.hour)}_${two(now.minute)}_${two(now.second)}';
  return '${scope == BackupScope.follows ? 'purelive_favorites' : 'purelive'}_$date.txt';
}

/// A file named [name] in [folder] that does not exist yet: `_2`, `_3` … are
/// added before the extension (3.x overwrote a backup made in the same
/// second).
File freeBackupFile(Directory folder, String name) {
  final base = p.basenameWithoutExtension(name);
  final extension = p.extension(name);
  var file = File(p.join(folder.path, name));
  for (var i = 2; file.existsSync(); i++) {
    file = File(p.join(folder.path, '${base}_$i$extension'));
  }
  return file;
}

/// A backup file found in the backup folder.
final class LocalBackupFile {
  /// Creates the entry.
  const new({required this.file, required this.modified, required this.size});

  /// The file.
  final File file;

  /// Last change.
  final DateTime modified;

  /// Size in bytes.
  final int size;

  /// The file name.
  String get name => p.basename(file.path);

  /// Whether the name says it is a follows-only backup.
  bool get followsOnly => name.toLowerCase().startsWith('purelive_favorites');
}

/// The backups in [folder] (`purelive*.txt` / `.json`), newest first.
/// Throws [FileSystemException] when the folder cannot be read.
Future<List<LocalBackupFile>> listBackupFiles(Directory folder) async {
  if (!folder.existsSync()) return const [];
  final found = <LocalBackupFile>[];
  await for (final entity in folder.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path).toLowerCase();
    if (!name.startsWith('purelive') || !(name.endsWith('.txt') || name.endsWith('.json'))) continue;
    try {
      final stat = entity.statSync();
      found.add(LocalBackupFile(file: entity, modified: stat.modified, size: stat.size));
    } on FileSystemException {
      continue;
    }
  }
  found.sort((a, b) => b.modified.compareTo(a.modified));
  return found;
}

/// The folder backups go to when the user picked none: on Android the
/// public `Download/PureLive` when the app may write there, else the app's
/// own external folder; elsewhere `Documents/PureLive`. 3.x had no default
/// and asked for a folder on every backup.
Future<Directory> defaultBackupFolder() async {
  final candidates = <Directory>[];
  if (Platform.isAndroid) {
    candidates.add(Directory('/storage/emulated/0/Download/PureLive'));
    if (await _tryDirectory(getExternalStorageDirectory) case final dir?) {
      candidates.add(Directory(p.join(dir.path, 'backup')));
    }
  } else {
    if (await _tryDirectory(getApplicationDocumentsDirectory) case final dir?) {
      candidates.add(Directory(p.join(dir.path, 'PureLive')));
    }
  }
  if (await _tryDirectory(getApplicationSupportDirectory) case final dir?) {
    candidates.add(Directory(p.join(dir.path, 'backup')));
  }
  for (final candidate in candidates) {
    if (await isWritableFolder(candidate)) return candidate;
  }
  return candidates.isNotEmpty ? candidates.last : Directory(p.join(Directory.systemTemp.path, 'PureLive'));
}

Future<Directory?> _tryDirectory(Future<Directory?> Function() find) async {
  try {
    return await find();
  } on Object {
    return null;
  }
}

/// Whether files can be written in [folder] (made when missing).
Future<bool> isWritableFolder(Directory folder) async {
  try {
    await folder.create(recursive: true);
    final probe = File(p.join(folder.path, '.purelive_probe'));
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Human-readable size: B, KB, MB.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// `yyyy-MM-dd HH:mm` in local time.
String formatFileTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Lets the user pick a folder ([pickFile] false) or a backup file inside
/// the app, starting at [initial].
///
/// A local stand-in for a system picker (3.x used file_picker, which the
/// app does not have yet): it browses with `dart:io`, so on Android it sees
/// only the folders the app may read.
Future<String?> showFileBrowser(BuildContext context, {required String initial, required bool pickFile}) =>
    showDialog<String>(
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
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(i18n(widget.pickFile ? 'select_recover_file' : 'backup_pick_folder')),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('backup-browser-path'),
              controller: _path,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: i18n('backup_browser_path'),
                suffixIcon: IconButton(
                  tooltip: i18n('backup_browser_open'),
                  icon: const Icon(Icons.arrow_forward),
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
                leading: const Icon(Icons.arrow_upward),
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
                          leading: Icon(
                            isDir ? Icons.folder_outlined : Icons.description_outlined,
                            color: colors.primary,
                          ),
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
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
        if (!widget.pickFile)
          FilledButton(
            key: const ValueKey('backup-browser-choose'),
            onPressed: _failed ? null : () => Navigator.pop(context, _current),
            child: Text(i18n('backup_browser_choose')),
          ),
      ],
    );
  }
}
