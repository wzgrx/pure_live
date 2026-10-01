import 'dart:convert';
import 'dart:io';

import 'package:live_store/src/block_lists.dart';
import 'package:live_store/src/database.dart';
import 'package:live_store/src/legacy/legacy_rules.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/secrets.dart';
import 'package:live_store/src/settings/settings.dart';
import 'package:live_store/src/settings/settings_store.dart';
import 'package:live_store/src/tags.dart';
import 'package:live_store/src/webdav.dart';
import 'package:path/path.dart' as p;

/// Internal records: the 3.x import ledger and values other modules own.
final class MetaStore {
  /// Creates the store over `db`.
  new(this._db);

  final StoreDatabase _db;

  /// The record [key], or null.
  Future<String?> get(String key) async {
    final rows = await _db.rows('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  /// Stores [value] under [key]; null removes it.
  Future<void> set(String key, String? value) => _db.write({StoreTables.meta}, () async {
    if (value == null) {
      await _db.run('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      await _db.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [key, value]);
    }
  });

  /// A 3.x value another module owns (`recorder_tasks`, the recorder
  /// settings, `localInteraction.*`), as 3.x stored it, or null.
  Future<Object?> legacyValue(String key) async {
    final rows = await _db.rows('SELECT value FROM legacy_values WHERE key = ?', [key]);
    return rows.isEmpty ? null : jsonDecode(rows.single.read<String>('value'));
  }

  /// Keys of every kept 3.x value.
  Future<List<String>> legacyKeys() async => [
    for (final row in await _db.rows('SELECT key FROM legacy_values ORDER BY key')) row.read<String>('key'),
  ];

  /// Drops the kept 3.x values of [keys] (taken over by their owner).
  Future<void> forgetLegacyValues(Iterable<String> keys) => _db.write({StoreTables.legacyValues}, () async {
    for (final key in keys) {
      await _db.run('DELETE FROM legacy_values WHERE key = ?', [key]);
    }
  });

  /// Keeps [values] where nothing is kept yet under the same key.
  Future<void> keepLegacyValues(Map<String, Object?> values) => _db.write({StoreTables.legacyValues}, () async {
    for (final entry in values.entries) {
      await _db.run('INSERT OR IGNORE INTO legacy_values (key, value) VALUES (?, ?)', [
        entry.key,
        jsonEncode(entry.value, toEncodable: _encodable),
      ]);
    }
  });
}

/// Hive's non-JSON values as JSON (3.x stored none of these).
Object? _encodable(Object? value) => switch (value) {
  final Set<Object?> set => set.toList(),
  final DateTime time => time.toIso8601String(),
  final Duration duration => duration.inMicroseconds,
  final List<int> bytes => bytes.toList(),
  _ => '$value',
};

/// Pure Live's storage: one SQLite database (drift, on a background isolate)
/// with follows, history, followed areas, groups, block lists, settings,
/// sealed secrets and WebDAV servers.
///
/// Replaces 3.x's single Hive box and its GetX controllers; each store keeps
/// the operations 3.x's controller offered so the pages (M13) can switch
/// over call by call.
final class LiveStore {
  new _(this.database, this.settings, this.secrets, {DateTime Function()? now})
    : follows = FollowStore(database),
      history = HistoryStore(database, settings),
      followAreas = FollowAreaStore(database),
      tags = TagStore(database, now: now),
      blockLists = BlockListStore(database),
      webdav = WebDavStore(database, secrets),
      meta = MetaStore(database);

  /// Opens (or creates) the store in [directory] (`<directory>/pure_live.db`)
  /// with the platform's [cipher]. Settings and secrets are loaded before
  /// this returns, so the UI can read them synchronously.
  static Future<LiveStore> open(Directory directory, {required SecretCipher cipher}) async {
    await directory.create(recursive: true);
    return await _load(StoreDatabase.file(File(p.join(directory.path, fileName))), cipher);
  }

  /// A store in memory (tests, previews).
  static Future<LiveStore> memory({required SecretCipher cipher, DateTime Function()? now}) =>
      _load(StoreDatabase.memory(), cipher, now: now);

  static Future<LiveStore> _load(StoreDatabase db, SecretCipher cipher, {DateTime Function()? now}) async {
    final settings = await SettingsStore.load(db);
    final secrets = await SecretStore.load(db, cipher);
    await _upgradeThemeColor(settings);
    return LiveStore._(db, settings, secrets, now: now);
  }

  /// Moves a stored 3.x default blue to the brand blue once (U.6b C-3):
  /// installs that imported 3.x data before the default changed. 3.x data
  /// imported later is converted on import (`LegacyRules.themeColor`).
  static Future<void> _upgradeThemeColor(SettingsStore settings) async {
    if (settings.get(Settings.themeColorMigration) >= 1) return;
    final stored = settings.get(Settings.themeColorSwitch);
    await settings.setAll({
      if (settings.isSet(Settings.themeColorSwitch) && LegacyRules.themeColor(stored) != stored)
        Settings.themeColorSwitch: Settings.brandThemeColor,
      Settings.themeColorMigration: 1,
    });
  }

  /// The database file name.
  static const fileName = 'pure_live.db';

  /// The database.
  final StoreDatabase database;

  /// Settings.
  final SettingsStore settings;

  /// Cookies and passwords.
  final SecretStore secrets;

  /// Followed rooms.
  final FollowStore follows;

  /// Watch history.
  final HistoryStore history;

  /// Followed areas.
  final FollowAreaStore followAreas;

  /// Follow groups.
  final TagStore tags;

  /// Danmaku block lists.
  final BlockListStore blockLists;

  /// WebDAV servers.
  final WebDavStore webdav;

  /// Internal records.
  final MetaStore meta;

  /// Closes the database.
  Future<void> close() async {
    await settings.close();
    await secrets.close();
    await database.close();
  }
}
