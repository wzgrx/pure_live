import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/shared/backup/backup_data.dart';

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
