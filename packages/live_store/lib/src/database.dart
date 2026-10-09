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

  /// The local interaction's history (D08.1): local danmaku, gifts, coins
  /// added, one row each. Schema 2.
  static const localEvents = 'local_events';
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
  ..._localEventsSchema,
];

/// Schema 2 (D08.1): the local interaction's history. `id` never comes back
/// after a delete (AUTOINCREMENT), so an undone clear puts the rows back
/// under their own ids.
const String _localEventsTable =
    'CREATE TABLE local_events (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, kind TEXT NOT NULL, '
    "platform TEXT NOT NULL DEFAULT '', room_id TEXT NOT NULL DEFAULT '', room_name TEXT NOT NULL DEFAULT '', "
    "text TEXT NOT NULL DEFAULT '', gift_id TEXT NOT NULL DEFAULT '', count INTEGER NOT NULL DEFAULT 0, "
    'coins INTEGER NOT NULL DEFAULT 0, style TEXT)';

const List<String> _localEventsSchema = [
  _localEventsTable,
  'CREATE INDEX local_events_room ON local_events (platform, room_id, at)',
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
  /// docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口 c14), so a write waits up to [busyTimeout] for
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

  /// 1: 4.0.0's tables; 2: `local_events` (D08.1).
  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in _schema) {
        await customStatement(statement);
      }
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) {
        for (final statement in _localEventsSchema) {
          await customStatement(statement);
        }
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
