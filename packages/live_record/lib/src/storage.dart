import 'package:live_record/src/files.dart';
import 'package:live_record/src/naming.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// What one storage sweep found and did (spec §15).
@immutable
final class StorageSweep {
  /// Creates a result.
  const new({required this.totalBytes, this.deleted = const [], this.freedBytes = 0, this.directoriesRemoved = 0});

  /// Size of the recording root before the sweep, protected files included.
  final int totalBytes;

  /// Files deleted, oldest first.
  final List<String> deleted;

  /// Bytes the deleted files held.
  final int freedBytes;

  /// Empty directories removed afterwards.
  final int directoriesRemoved;

  /// Size after the sweep.
  int get remainingBytes => totalBytes - freedBytes;
}

/// Keeps the recording [root] at or below [limitBytes] (spec §15: the
/// "cache limit" is the size cap of the recording folder).
///
/// Works from one scan: every file counts towards the total except the root
/// marker; files inside a directory for which [isProtected] is true (a
/// session resolving, recording, reconnecting or finalising) count but are
/// never deleted. Other files go oldest modification first until the total
/// fits; a file that cannot be deleted (in use) is skipped, so the work is
/// bounded by the snapshot. [isProtected] is asked again right before each
/// deletion, so a session that starts during the sweep is respected. When
/// anything was deleted, empty directories are removed deepest first,
/// protected ones and the root excepted.
Future<StorageSweep> enforceStorageLimit({
  required RecordFiles files,
  required String root,
  required int limitBytes,
  bool Function(String directory) isProtected = _never,
}) async {
  final base = p.normalize(root);
  final marker = p.join(base, RecordRoot.markerName);
  final tree = await files.scan(base);
  final entries = [
    for (final entry in tree.files)
      if (!p.equals(entry.path, marker)) entry,
  ];
  final total = entries.fold(0, (sum, entry) => sum + entry.size);
  if (total <= limitBytes) return StorageSweep(totalBytes: total);

  bool guarded(String path) {
    for (var dir = p.dirname(path); p.isWithin(base, dir) || p.equals(base, dir); dir = p.dirname(dir)) {
      if (isProtected(dir)) return true;
      if (p.equals(base, dir)) break;
    }
    return false;
  }

  final candidates = [...entries]..sort((a, b) => a.modified.compareTo(b.modified));
  var remaining = total;
  var freed = 0;
  final deleted = <String>[];
  for (final entry in candidates) {
    if (remaining <= limitBytes) break;
    if (guarded(entry.path)) continue;
    try {
      await files.delete(entry.path);
    } on Exception {
      // Held open elsewhere: skip it rather than retrying (bounded work).
      continue;
    }
    deleted.add(entry.path);
    remaining -= entry.size;
    freed += entry.size;
  }

  var removed = 0;
  if (deleted.isNotEmpty) {
    final directories = [...tree.directories]..sort((a, b) => p.split(b).length.compareTo(p.split(a).length));
    for (final dir in directories) {
      if (!p.isWithin(base, dir) || guarded(p.join(dir, '_'))) continue;
      if (await files.deleteDirectoryIfEmpty(dir)) removed++;
    }
  }
  return StorageSweep(totalBytes: total, deleted: deleted, freedBytes: freed, directoriesRemoved: removed);
}

bool _never(String _) => false;
