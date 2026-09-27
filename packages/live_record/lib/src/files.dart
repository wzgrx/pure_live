import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A file open for sequential writing.
abstract interface class RecordSink {
  /// Path of the file.
  String get path;

  /// Appends [bytes]; completes when the operating system has them.
  Future<void> write(List<int> bytes);

  /// Flushes the file to storage.
  Future<void> flush();

  /// Closes the file; completes when it is really closed (Windows locks, REG-RECORD-024).
  Future<void> close();
}

/// A file open for random reads (crash recovery scans).
abstract interface class RecordReader {
  /// File length in bytes.
  int get length;

  /// Up to [count] bytes at [offset].
  Future<Uint8List> read(int offset, int count);

  /// Closes the file.
  Future<void> close();
}

/// Thrown by [RecordFiles.create] when the path is taken (spec §6.9: never overwrite).
final class RecordFileExists implements Exception {
  /// Creates the exception.
  const new(this.path);

  /// The existing path.
  final String path;

  @override
  String toString() => 'RecordFileExists($path)';
}

/// A file found by [RecordFiles.scan].
@immutable
final class RecordFileEntry {
  /// Creates an entry.
  const new(this.path, this.size, this.modified);

  /// Full path.
  final String path;

  /// Length in bytes.
  final int size;

  /// Last modification time.
  final DateTime modified;
}

/// Everything under one directory, from one scan (spec §15 storage limit).
@immutable
final class RecordTree {
  /// Creates a tree.
  const new({this.files = const [], this.directories = const []});

  /// Every file, at any depth.
  final List<RecordFileEntry> files;

  /// Every directory below the scanned one, at any depth (not the scanned one itself).
  final List<String> directories;
}

/// File operations the recorder uses. [IoRecordFiles] works on disk;
/// `MemoryRecordFiles` (package:live_record/testing.dart) keeps everything in
/// memory for tests under a fake clock.
abstract interface class RecordFiles {
  /// Creates [path] exclusively and opens it for writing; throws
  /// [RecordFileExists] when it exists. Parent directories are created.
  Future<RecordSink> create(String path);

  /// Opens [path] for reading.
  Future<RecordReader> open(String path);

  /// Whether a file exists at [path].
  Future<bool> exists(String path);

  /// Length of the file at [path], or null when there is none.
  Future<int?> length(String path);

  /// Whole content of [path].
  Future<Uint8List> read(String path);

  /// Replaces [path] with [bytes] atomically: writes `<path>.tmp`, then renames.
  Future<void> writeAtomic(String path, List<int> bytes);

  /// Appends [bytes] to an existing file.
  Future<void> append(String path, List<int> bytes);

  /// Truncates [path] to [length] bytes.
  Future<void> truncate(String path, int length);

  /// Renames [from] to [to] (callers check that [to] is free).
  Future<void> rename(String from, String to);

  /// Deletes [path] if it exists.
  Future<void> delete(String path);

  /// Creates [path] and its parents.
  Future<void> createDirectory(String path);

  /// Names (not paths) of the files directly inside [directory]; empty when it does not exist.
  Future<List<String>> list(String directory);

  /// Every file and directory below [directory], without following links;
  /// empty when it does not exist. Files that vanish during the scan are left out.
  Future<RecordTree> scan(String directory);

  /// Deletes the directory [path] when it is empty; returns whether it did.
  Future<bool> deleteDirectoryIfEmpty(String path);
}

/// [RecordFiles] on the local file system (`dart:io`).
final class IoRecordFiles implements RecordFiles {
  /// Creates the file system.
  const new();

  @override
  Future<RecordSink> create(String path) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final file = File(path);
    try {
      // Exclusive create: fails when another writer or an old file holds the name.
      await file.create(exclusive: true);
    } on PathExistsException {
      throw RecordFileExists(path);
    } on FileSystemException catch (error) {
      if (file.existsSync()) throw RecordFileExists(path);
      throw FileSystemException(error.message, path, error.osError);
    }
    final handle = await file.open(mode: FileMode.writeOnlyAppend);
    return _IoSink(path, handle);
  }

  @override
  Future<RecordReader> open(String path) async {
    final handle = await File(path).open();
    return _IoReader(handle, await handle.length());
  }

  @override
  Future<bool> exists(String path) async => File(path).existsSync();

  @override
  Future<int?> length(String path) async {
    final file = File(path);
    return file.existsSync() ? await file.length() : null;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<void> writeAtomic(String path, List<int> bytes) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, mode: FileMode.writeOnlyAppend, flush: true);
  }

  @override
  Future<void> truncate(String path, int length) async {
    final handle = await File(path).open(mode: FileMode.append);
    try {
      await handle.truncate(length);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<List<String>> list(String directory) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    return [
      await for (final entity in dir.list(followLinks: false))
        if (entity is File) p.basename(entity.path),
    ];
  }

  @override
  Future<RecordTree> scan(String directory) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const RecordTree();
    final files = <RecordFileEntry>[];
    final directories = <String>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          directories.add(entity.path);
        } else if (entity is File) {
          // A file renamed or deleted by a writer since the listing stats as notFound.
          final stat = entity.statSync();
          if (stat.type == FileSystemEntityType.file) {
            files.add(RecordFileEntry(entity.path, stat.size, stat.modified));
          }
        }
      }
    } on FileSystemException {
      // A directory vanished during the listing: use what was found.
    }
    return RecordTree(files: files, directories: directories);
  }

  @override
  Future<bool> deleteDirectoryIfEmpty(String path) async {
    final dir = Directory(path);
    try {
      if (!dir.existsSync() || !await dir.list(followLinks: false).isEmpty) return false;
      await dir.delete();
      return true;
    } on FileSystemException {
      // In use or filled meanwhile: keep it.
      return false;
    }
  }
}

final class _IoSink implements RecordSink {
  new(this.path, this._handle);

  @override
  final String path;
  final RandomAccessFile _handle;

  @override
  Future<void> write(List<int> bytes) async {
    await _handle.writeFrom(bytes);
  }

  @override
  Future<void> flush() async {
    await _handle.flush();
  }

  @override
  Future<void> close() => _handle.close();
}

final class _IoReader implements RecordReader {
  new(this._handle, this.length);

  final RandomAccessFile _handle;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    await _handle.setPosition(offset);
    return await _handle.read(count);
  }

  @override
  Future<void> close() => _handle.close();
}
