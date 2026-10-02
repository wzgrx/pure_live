import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Table names, used for change notifications.
abstract final class StoreTables {
  /// Followed rooms.
  static const follows = 'follows';

  /// Watch history.
  static const history = 'history';

  /// Followed areas.
  static const followAreas = 'follow_areas';

  /// Follow groups.
  static const tags = 'tags';

  /// Room to group assignments.
  static const roomTags = 'room_tags';

  /// Danmaku keyword and user blocks.
  static const blockRules = 'block_rules';

  /// Settings values.
  static const settings = 'settings';

  /// Sealed secrets.
  static const secrets = 'secrets';

  /// WebDAV servers (passwords are secrets).
  static const webdav = 'webdav_profiles';

  /// Internal records: migration ledger, current WebDAV server.
  static const meta = 'meta';

  /// 3.x values another module owns (recorder settings and tasks, local
  /// interaction), kept verbatim until that module reads them.
  static const legacyValues = 'legacy_values';
}

const List<String> _schema = [
  'CREATE TABLE follows (identity TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, room TEXT NOT NULL)',
  'CREATE TABLE history (identity TEXT NOT NULL PRIMARY KEY, seq INTEGER NOT NULL, room TEXT NOT NULL)',
  'CREATE TABLE follow_areas (identity TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, area TEXT NOT NULL)',
  'CREATE TABLE tags (id TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL, description TEXT NOT NULL)',
  'CREATE TABLE room_tags (room TEXT NOT NULL, tag_id TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (room, tag_id))',
  'CREATE TABLE block_rules (kind TEXT NOT NULL, folded TEXT NOT NULL, value TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (kind, folded))',
  'CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE secrets (ref TEXT NOT NULL PRIMARY KEY, sealed BLOB NOT NULL)',
  'CREATE TABLE webdav_profiles (name TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, address TEXT NOT NULL, username TEXT NOT NULL)',
  'CREATE TABLE meta (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE legacy_values (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
];

/// The SQLite database behind `LiveStore`, written with drift's raw SQL API
/// (no code generation): a handful of small tables, queries kept next to
/// the store that owns them.
final class StoreDatabase extends GeneratedDatabase {
  /// Opens [executor].
  new(super.executor);

  /// The database file at [file], opened on a background isolate.
  ///
  /// [shared]: other processes open the same file (another desktop window,
  /// docs/T17/T17a/T17a.1 c14), so a write waits up to [busyTimeout] for
  /// theirs instead of failing at once.
  factory file(File file, {bool shared = false}) => StoreDatabase(
    NativeDatabase.createInBackground(
      file,
      setup: shared ? (db) => db.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}') : null,
    ),
  );

  /// A database in memory, for tests and previews.
  factory memory() => StoreDatabase(NativeDatabase.memory());

  /// How long a write to a database opened `shared` waits for another
  /// process's.
  static const Duration busyTimeout = Duration(seconds: 5);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in _schema) {
        await customStatement(statement);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  /// Rows of [sql].
  Future<List<QueryRow>> rows(String sql, [List<Object?> args = const []]) =>
      customSelect(sql, variables: [for (final arg in args) Variable(arg)]).get();

  /// Runs [sql].
  Future<void> run(String sql, [List<Object?> args = const []]) => customStatement(sql, args);

  /// Runs [action] in one transaction and then tells the watchers of
  /// [tables]; nothing is written when [action] throws.
  Future<T> write<T>(Set<String> tables, Future<T> Function() action) async {
    final result = await transaction(action);
    if (tables.isNotEmpty) notifyUpdates({for (final table in tables) TableUpdate(table)});
    return result;
  }

  /// SQLite's `data_version`: it changes when another connection (another
  /// process sharing the file) committed since the last read, never for
  /// this connection's own writes.
  Future<int> dataVersion() async => (await rows('PRAGMA data_version')).single.read<int>('data_version');

  /// Tells the watchers of every table that their rows may have changed
  /// (another process wrote to the file).
  Future<void> notifyAllTables() async {
    final names = [
      for (final row in await rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
        row.read<String>('name'),
    ];
    if (names.isNotEmpty) notifyUpdates({for (final name in names) TableUpdate(name)});
  }

  /// [load] now and again after every write to [tables].
  Stream<T> watch<T>(Set<String> tables, Future<T> Function() load) => Stream.multi((controller) {
    var closed = false;
    var running = false;
    var again = false;
    Future<void> emit() async {
      if (running) {
        again = true;
        return;
      }
      running = true;
      try {
        do {
          again = false;
          final value = await load();
          if (!closed) controller.add(value);
        } while (again && !closed);
      } on Object catch (error, stack) {
        if (!closed) controller.addError(error, stack);
      } finally {
        running = false;
      }
    }

    final updates = tableUpdates(
      TableUpdateQuery.allOf([for (final table in tables) TableUpdateQuery.onTableName(table)]),
    ).listen((_) => unawaited(emit()));
    unawaited(emit());
    controller.onCancel = () {
      closed = true;
      return updates.cancel();
    };
  });
}
