import 'dart:convert';
import 'dart:io';

import 'package:live_store/src/accounts.dart';
import 'package:live_store/src/block_lists.dart';
import 'package:live_store/src/database.dart';
import 'package:live_store/src/legacy/legacy_rules.dart';
import 'package:live_store/src/local_events.dart';
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
      accounts = AccountRoster(secrets, now: now),
      localEvents = LocalEventStore(database),
      meta = MetaStore(database);

  /// Opens (or creates) the store in [directory] (`<directory>/pure_live.db`)
  /// with the platform's [cipher]. Settings and secrets are loaded before
  /// this returns, so the UI can read them synchronously.
  ///
  /// [shared]: other processes open the same folder (desktop windows,
  /// docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口 c14); their writes are waited for, and
  /// [syncExternal] picks them up.
  static Future<LiveStore> open(Directory directory, {required SecretCipher cipher, bool shared = false}) async {
    await directory.create(recursive: true);
    return await _load(StoreDatabase.file(File(p.join(directory.path, fileName)), shared: shared), cipher);
  }

  int? _dataVersion;
  Future<bool>? _syncing;
  bool _syncAgain = false;

  /// Takes in what another process sharing the database wrote since the last
  /// call (U.13 c14): settings and secrets are read again and every watcher
  /// queries again. True when something had changed; calls while one runs
  /// are folded into one more pass.
  Future<bool> syncExternal() {
    final running = _syncing;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    return _syncing = _sync().whenComplete(() => _syncing = null);
  }

  Future<bool> _sync() async {
    var changed = false;
    do {
      _syncAgain = false;
      final version = await database.dataVersion();
      if (_dataVersion == version) continue;
      _dataVersion = version;
      changed = true;
      await settings.reload();
      await secrets.reload();
      await database.notifyAllTables();
    } while (_syncAgain);
    return changed;
  }

  /// A store in memory (tests, previews).
  static Future<LiveStore> memory({required SecretCipher cipher, DateTime Function()? now}) =>
      _load(StoreDatabase.memory(), cipher, now: now);

  static Future<LiveStore> _load(StoreDatabase db, SecretCipher cipher, {DateTime Function()? now}) async {
    // Counted before reading, so a write of another process meanwhile is
    // taken in by the first [syncExternal].
    final version = await db.dataVersion();
    final settings = await SettingsStore.load(db);
    final secrets = await SecretStore.load(db, cipher);
    await _upgradeThemeColor(settings);
    await _adoptGiftSwitch(settings, MetaStore(db));
    return LiveStore._(db, settings, secrets, now: now).._dataVersion = version;
  }

  /// The meta key the room kept "在聊天列表显示礼物" under before it became
  /// [Settings.showChatGifts] (B-21; A08.6 c3).
  static const legacyShowGiftsKey = 'live_play.showGifts';

  /// Takes the room's old gift switch over once (A08.6 c3): "off" (`0`)
  /// becomes the setting unless one is stored already; the meta record is
  /// removed either way, so it is never read again.
  static Future<void> _adoptGiftSwitch(SettingsStore settings, MetaStore meta) async {
    final stored = await meta.get(legacyShowGiftsKey);
    if (stored == null) return;
    if (stored == '0' && !settings.isSet(Settings.showChatGifts)) await settings.set(Settings.showChatGifts, false);
    await meta.set(legacyShowGiftsKey, null);
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

  /// The remembered sign-ins (V01.2), sealed in [secrets].
  final AccountRoster accounts;

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

  /// The local interaction's history (D08.1).
  final LocalEventStore localEvents;

  /// Internal records.
  final MetaStore meta;

  /// Closes the database.
  Future<void> close() async {
    await settings.close();
    await secrets.close();
    await database.close();
  }
}
