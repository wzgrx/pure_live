import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:live_store/src/block_rules.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/follow_areas.dart';
import 'package:live_store/src/follows.dart';
import 'package:live_store/src/history.dart';
import 'package:live_store/src/iptv.dart';
import 'package:live_store/src/meta_store.dart';
import 'package:live_store/src/room_prefs.dart';
import 'package:live_store/src/room_store.dart';
import 'package:live_store/src/settings/settings_store.dart';
import 'package:live_store/src/store_log.dart';
import 'package:live_store/src/tags.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Database;

/// The v4 main database with its typed stores (spec/modules/store.md §3).
///
/// Open it once at startup and await [open] before building the UI: settings
/// are loaded by then, so [SettingsStore.get] is synchronous.
final class LiveStore {
  new _(this.database, StoreLog log)
    : settings = SettingsStore(database, log: log),
      rooms = RoomStore(database),
      follows = FollowStore(database),
      followAreas = FollowAreaStore(database),
      tags = TagStore(database),
      blockRules = BlockRuleStore(database),
      roomPrefs = RoomPrefStore(database),
      iptv = IptvStore(database),
      meta = MetaStore(database) {
    history = HistoryStore(database, settings);
  }

  /// Path of the database file under the app data root [rootDirectory]:
  /// `<root>/DB/pure_live.db` (store.md §3).
  static String databasePath(String rootDirectory) => p.join(rootDirectory, 'DB', 'pure_live.db');

  /// Opens (or creates) the database under [rootDirectory], running
  /// migrations, and loads the settings. With [background] (the default) the
  /// database runs on its own isolate.
  static Future<LiveStore> open(String rootDirectory, {bool background = true, StoreLog log = StoreLog.silent}) async {
    final file = File(databasePath(rootDirectory));
    await file.parent.create(recursive: true);
    final executor = background
        ? NativeDatabase.createInBackground(file, setup: _setup)
        : NativeDatabase(file, setup: _setup);
    return await openExecutor(executor, log: log);
  }

  // Runs on the database isolate: write-ahead logging lets reads continue
  // during a write transaction.
  static void _setup(Database database) => database.execute('PRAGMA journal_mode = WAL');

  /// Opens a store on [executor], for example `NativeDatabase.memory()` in
  /// tests.
  static Future<LiveStore> openExecutor(QueryExecutor executor, {StoreLog log = StoreLog.silent}) async {
    final store = LiveStore._(StoreDatabase(executor), log);
    try {
      await store.settings.load();
    } on Object {
      await store.database.close();
      rethrow;
    }
    return store;
  }

  /// An empty in-memory store, for tests and previews.
  static Future<LiveStore> inMemory({StoreLog log = StoreLog.silent}) =>
      openExecutor(NativeDatabase.memory(), log: log);

  /// The drift database; for backup and migration code in this package.
  @internal
  final StoreDatabase database;

  /// Settings (store.md §5).
  final SettingsStore settings;

  /// Stored room data shared by follows, history and tags.
  final RoomStore rooms;

  /// Followed rooms.
  final FollowStore follows;

  /// Followed areas.
  final FollowAreaStore followAreas;

  /// Tags (follow groups) and membership.
  final TagStore tags;

  /// Watch history.
  late final HistoryStore history;

  /// Danmaku block words and users.
  final BlockRuleStore blockRules;

  /// Per-room preferences.
  final RoomPrefStore roomPrefs;

  /// IPTV playlists, guide sources and programmes.
  final IptvStore iptv;

  /// Internal bookkeeping.
  final MetaStore meta;

  /// Closes the database; pending writes complete first.
  Future<void> close() async {
    await settings.dispose();
    await database.close();
  }
}
