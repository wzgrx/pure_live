import 'dart:io';

import 'package:path/path.dart' as p;

/// The recording directory the app manages (3.x `CacheService`).
///
/// A directory chosen by the user is a parent: recordings go into its
/// [managedFolderName] child, which carries an ownership marker, so choosing
/// a broad folder such as Downloads never makes unrelated files cache
/// entries. Directories in use are protected from cleanup.
final class RecordStorage {
  /// Creates the storage. [defaultDirectory] is the app's records folder
  /// (M12); [configuredPath] the user's choice ('' for the default).
  new({required this.defaultDirectory, required this.configuredPath, this.isAndroid = false});

  /// Folder created under a user-chosen parent.
  static const managedFolderName = 'PureLiveRecords';

  /// Marker file of a managed root.
  static const ownershipMarkerName = '.pure_live_recording_root';

  /// The app's default records folder.
  final Future<String> Function() defaultDirectory;

  /// The user's configured parent.
  final String Function() configuredPath;

  /// Whether Android private paths are ignored as a choice (3.x).
  final bool isAndroid;

  final _protected = <String, int>{};

  /// The managed root, created with its marker.
  Future<Directory> recordDirectory() => _resolve(configuredPath());

  /// Resolves [configured] and proves it writable (3.x `prepareRecordDir`).
  Future<Directory> prepare(String? configured) async {
    final directory = await _resolve(configured);
    final probe = await directory.createTemp('.pure_live_write_probe_${pid}_');
    try {
      await File(p.join(probe.path, 'probe')).writeAsString('ok', flush: true);
      return directory;
    } finally {
      if (probe.existsSync()) await probe.delete(recursive: true);
    }
  }

  /// Whether the configured root is writable.
  Future<bool> canWrite() async {
    try {
      await prepare(configuredPath());
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<Directory> _resolve(String? configuredValue) async {
    final fallback = await defaultDirectory();
    final configured = configuredValue?.trim() ?? '';
    final Directory directory;
    if (configured.isEmpty || _same(configured, fallback) || _isAndroidPrivate(configured)) {
      directory = Directory(fallback);
    } else if (p.basename(p.normalize(configured)).toLowerCase() == managedFolderName.toLowerCase() &&
        File(p.join(configured, ownershipMarkerName)).existsSync()) {
      directory = Directory(configured);
    } else {
      directory = Directory(p.join(configured, managedFolderName));
    }
    await directory.create(recursive: true);
    final marker = File(p.join(directory.path, ownershipMarkerName));
    if (!marker.existsSync()) await marker.writeAsString('Pure Live managed recording directory.\n', flush: true);
    return directory;
  }

  bool _isAndroidPrivate(String path) {
    if (!isAndroid) return false;
    final normalized = p.normalize(path).replaceAll(r'\', '/').toLowerCase();
    return RegExp(r'^/data/(?:user|user_de)/\d+(?:/|$)').hasMatch(normalized) ||
        RegExp(r'^/data/data(?:/|$)').hasMatch(normalized);
  }

  String _key(String value) {
    if (value.trim().isEmpty) return '';
    final normalized = p.normalize(p.absolute(value));
    return Platform.isWindows || Platform.isMacOS ? normalized.toLowerCase() : normalized;
  }

  bool _same(String left, String right) => _key(left) == _key(right);

  /// Protects [directory] from cleanup until a matching [release].
  void protect(String directory) {
    final key = _key(directory);
    if (key.isNotEmpty) _protected.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  /// Releases one protection of [directory].
  void release(String directory) {
    final key = _key(directory);
    final count = _protected[key] ?? 0;
    if (count <= 1) {
      _protected.remove(key);
    } else {
      _protected[key] = count - 1;
    }
  }

  /// Whether [path] is in a protected directory.
  bool isProtected(String path) {
    final key = _key(path);
    return _protected.keys.any((root) => root == key || p.isWithin(root, key));
  }

  Future<List<File>> _files() async {
    final root = await recordDirectory();
    return [
      await for (final entity in root.list(recursive: true, followLinks: false))
        if (entity is File && p.basename(entity.path) != ownershipMarkerName) entity,
    ];
  }

  /// Size of the managed files, MiB.
  Future<double> sizeMB() async {
    var bytes = 0;
    for (final file in await _files()) {
      try {
        bytes += file.lengthSync();
      } on FileSystemException {
        // Rotated during the snapshot.
      }
    }
    return bytes / 1024 / 1024;
  }

  /// Deletes the oldest unprotected files until the total is at most
  /// [maxMB] (one snapshot; protected output counts but is never deleted).
  Future<void> enforceLimit({required double maxMB}) async {
    final maxBytes = (maxMB.clamp(0, double.infinity) * 1024 * 1024).round();
    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    for (final file in await _files()) {
      try {
        final stat = file.statSync();
        total += stat.size;
        if (!isProtected(file.path)) entries.add((file: file, size: stat.size, modified: stat.modified));
      } on FileSystemException {
        // Rotated during the snapshot.
      }
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } on FileSystemException {
        // Locked; continue with the finite snapshot.
      }
    }
  }

  /// Deletes every unprotected managed file and empty folder, keeping the
  /// marker.
  Future<void> clearAll() async {
    final root = await recordDirectory();
    final entities = await root.list(recursive: true, followLinks: false).toList();
    for (final file in entities.whereType<File>()) {
      if (p.basename(file.path) == ownershipMarkerName || isProtected(file.path)) continue;
      try {
        await file.delete();
      } on FileSystemException {
        // Locked by a writer.
      }
    }
    final directories = entities.whereType<Directory>().toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      if (isProtected(directory.path)) continue;
      try {
        if (await directory.list(followLinks: false).isEmpty) await directory.delete();
      } on FileSystemException {
        // In use.
      }
    }
  }
}
