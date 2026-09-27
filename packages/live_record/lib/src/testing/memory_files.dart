import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:path/path.dart' as p;

/// In-memory [RecordFiles] for tests: works under `fake_async`, and can fail
/// or stall writes on demand.
final class MemoryRecordFiles implements RecordFiles {
  final _files = <String, BytesBuilder>{};
  final _directories = <String>{};

  /// Error thrown by the next writes, when set.
  FileSystemException? writeError;

  /// While set, writes wait for this future (a stalled disk).
  Future<void>? stall;

  /// Paths of the sinks still open.
  final Set<String> openSinks = {};

  /// Flushes requested through sinks.
  int flushes = 0;

  /// Every path currently holding a file.
  Iterable<String> get paths => _files.keys;

  /// Content of [path], or null.
  Uint8List? bytesOf(String path) => _files[p.normalize(path)]?.toBytes();

  /// Writes [bytes] to [path] directly (test setup).
  void put(String path, List<int> bytes) {
    final key = p.normalize(path);
    _directories.add(p.dirname(key));
    _files[key] = BytesBuilder(copy: false)..add(bytes);
  }

  Future<void> _gate() async {
    final stalled = stall;
    if (stalled != null) await stalled;
    final error = writeError;
    if (error != null) throw error;
  }

  @override
  Future<RecordSink> create(String path) async {
    final key = p.normalize(path);
    if (_files.containsKey(key)) throw RecordFileExists(path);
    await _gate();
    _directories.add(p.dirname(key));
    _files[key] = BytesBuilder(copy: false);
    openSinks.add(key);
    return _MemorySink(this, key);
  }

  @override
  Future<RecordReader> open(String path) async {
    final bytes = bytesOf(path);
    if (bytes == null) throw FileSystemException('No such file', path, const OSError('No such file', 2));
    return _MemoryReader(bytes);
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(p.normalize(path));

  @override
  Future<int?> length(String path) async => _files[p.normalize(path)]?.length;

  @override
  Future<Uint8List> read(String path) async {
    final bytes = bytesOf(path);
    if (bytes == null) throw FileSystemException('No such file', path, const OSError('No such file', 2));
    return bytes;
  }

  @override
  Future<void> writeAtomic(String path, List<int> bytes) async {
    await _gate();
    put(path, bytes);
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    final builder = _files[p.normalize(path)];
    if (builder == null) throw FileSystemException('No such file', path, const OSError('No such file', 2));
    builder.add(bytes);
  }

  @override
  Future<void> truncate(String path, int length) async {
    final key = p.normalize(path);
    final bytes = bytesOf(key);
    if (bytes == null) throw FileSystemException('No such file', path, const OSError('No such file', 2));
    _files[key] = BytesBuilder(copy: false)..add(Uint8List.sublistView(bytes, 0, length));
  }

  @override
  Future<void> rename(String from, String to) async {
    final source = p.normalize(from);
    final builder = _files.remove(source);
    if (builder == null) throw FileSystemException('No such file', from, const OSError('No such file', 2));
    final target = p.normalize(to);
    _directories.add(p.dirname(target));
    _files[target] = builder;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(p.normalize(path));
  }

  @override
  Future<void> createDirectory(String path) async {
    _directories.add(p.normalize(path));
  }

  @override
  Future<List<String>> list(String directory) async {
    final key = p.normalize(directory);
    return [
      for (final path in _files.keys)
        if (p.dirname(path) == key) p.basename(path),
    ];
  }
}

final class _MemorySink implements RecordSink {
  new(this._files, this.path);

  final MemoryRecordFiles _files;

  @override
  final String path;

  var _closed = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('closed');
    await _files._gate();
    final builder = _files._files[path];
    if (builder == null) throw FileSystemException('Deleted while open', path);
    builder.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> flush() {
    _files.flushes++;
    return _files._gate();
  }

  @override
  Future<void> close() async {
    _closed = true;
    _files.openSinks.remove(path);
  }
}

final class _MemoryReader implements RecordReader {
  new(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset >= _bytes.length) return Uint8List(0);
    final end = offset + count > _bytes.length ? _bytes.length : offset + count;
    return Uint8List.sublistView(_bytes, offset, end);
  }

  @override
  Future<void> close() async {}
}
