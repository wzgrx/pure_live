import 'dart:async';
import 'dart:convert';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/task.dart';

/// Where tasks persist (spec §13). The app stores them with `live_store`
/// (`record_tasks`); [MemoryRecordTaskStore] and [JsonFileRecordTaskStore]
/// are the built-in implementations. Only [RecordTask.toJson] fields are kept:
/// never URLs, headers, cookies or keys.
abstract interface class RecordTaskStore {
  /// Every stored task.
  Future<List<RecordTask>> load();

  /// Inserts or replaces tasks by key; completes when they are stored.
  Future<void> save(Iterable<RecordTask> tasks);

  /// Removes the task with [key].
  Future<void> remove(String key);
}

/// [RecordTaskStore] in memory (tests, and apps that do not persist).
final class MemoryRecordTaskStore implements RecordTaskStore {
  /// Creates a store holding [tasks].
  new([Iterable<RecordTask> tasks = const []]) {
    for (final task in tasks) {
      _json[task.key] = task.toJson();
    }
  }

  final _json = <String, Map<String, Object?>>{};

  /// Number of [save] calls (tests check write coalescing).
  int saves = 0;

  /// The stored JSON of every task (as it would reach disk).
  Map<String, Map<String, Object?>> get stored => Map.unmodifiable(_json);

  @override
  Future<List<RecordTask>> load() async => [for (final json in _json.values) RecordTask.fromJson(json)];

  @override
  Future<void> save(Iterable<RecordTask> tasks) async {
    saves++;
    for (final task in tasks) {
      // Round-trip through JSON so tests see exactly what persists.
      _json[task.key] = jsonDecode(jsonEncode(task.toJson())) as Map<String, Object?>;
    }
  }

  @override
  Future<void> remove(String key) async {
    _json.remove(key);
  }
}

/// [RecordTaskStore] in one JSON file, rewritten atomically (`.tmp` + rename)
/// on every change; writes run one at a time.
final class JsonFileRecordTaskStore implements RecordTaskStore {
  /// Creates a store at [path].
  new(this.path, {this._files = const IoRecordFiles()});

  /// File path.
  final String path;
  final RecordFiles _files;
  Map<String, Map<String, Object?>>? _json;
  Future<void> _chain = Future.value();

  Future<Map<String, Map<String, Object?>>> _loaded() async {
    final existing = _json;
    if (existing != null) return existing;
    final json = <String, Map<String, Object?>>{};
    try {
      if (await _files.exists(path)) {
        final document = jsonDecode(utf8.decode(await _files.read(path))) as Map<String, Object?>;
        for (final entry in document['tasks'] as List? ?? const []) {
          final task = (entry as Map).cast<String, Object?>();
          final key = task['room'];
          if (key is String) json[key] = task;
        }
      }
    } on FormatException {
      // A damaged file starts empty; the next write replaces it.
    }
    return _json = json;
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(Map<String, Map<String, Object?>> json) => _files.writeAtomic(
    path,
    utf8.encode(const JsonEncoder.withIndent('  ').convert({'version': 1, 'tasks': json.values.toList()})),
  );

  @override
  Future<List<RecordTask>> load() async {
    final json = await _loaded();
    final tasks = <RecordTask>[];
    for (final entry in json.values) {
      try {
        tasks.add(RecordTask.fromJson(entry));
      } on Object {
        // Skip an unreadable task rather than losing the others.
      }
    }
    return tasks;
  }

  @override
  Future<void> save(Iterable<RecordTask> tasks) {
    final snapshot = [for (final task in tasks) task.toJson()];
    return _serial(() async {
      final json = await _loaded();
      for (final task in snapshot) {
        json[task['room']! as String] = task;
      }
      await _write(json);
    });
  }

  @override
  Future<void> remove(String key) => _serial(() async {
    final json = await _loaded();
    if (json.remove(key) != null) await _write(json);
  });
}
