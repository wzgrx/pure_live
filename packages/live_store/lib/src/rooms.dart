import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/database.dart';
import 'package:live_store/src/settings/settings.dart';
import 'package:live_store/src/settings/settings_store.dart';

/// Room ids 3.x treated as "no room" (favorite_room_controller.dart:162-180).
const Set<String> _invalidRoomIds = {'0', 'null', 'undefined', 'nan', 'none'};

/// Whether [room] can be followed or recorded in history: a platform and a
/// room id that is not empty, `0`, `null`, `undefined`, `nan` or `none`
/// (3.x's `_isValidFavoriteRoom`).
bool isStorableRoom(LiveRoom room) {
  final platform = room.platform.trim();
  final id = room.roomId.trim().toLowerCase();
  return platform.isNotEmpty && platform != 'unknown' && id.isNotEmpty && !_invalidRoomIds.contains(id);
}

String _encodeRoom(LiveRoom room) => jsonEncode(room.toJson());

LiveRoom _decodeRoom(String json) => LiveRoom.fromJson((jsonDecode(json) as Map).cast<String, Object?>());

/// [kept] with its empty fields taken from [other], the same room (3.x's
/// "empty fields complement each other" merge); [kept]'s spelling of the
/// room id stays.
LiveRoom fillEmptyFields(LiveRoom kept, LiveRoom other) =>
    LiveRoom.fromJson({...other.mergeFrom(kept).toJson(), 'roomId': kept.roomId});

/// [rooms] valid and without duplicates (first occurrence wins, later ones
/// only fill its empty fields), in order.
List<LiveRoom> uniqueRooms(Iterable<LiveRoom> rooms) {
  final byIdentity = <String, LiveRoom>{};
  for (final room in rooms) {
    if (!isStorableRoom(room)) continue;
    final existing = byIdentity[room.identityKey];
    byIdentity[room.identityKey] = existing == null ? room : fillEmptyFields(existing, room);
  }
  return byIdentity.values.toList();
}

/// Followed rooms, in the user's order (3.x `FavoriteRoomController`'s
/// `favoriteRooms`).
///
/// Every write waits until it is committed; a failed write leaves the stored
/// list unchanged (3.x rolled back its in-memory copy by hand).
final class FollowStore {
  /// Creates the store over `db`.
  new(this._db);

  final StoreDatabase _db;

  static const Set<String> _tables = {StoreTables.follows};

  /// The followed rooms.
  Future<List<LiveRoom>> all() async => [
    for (final row in await _db.rows('SELECT room FROM follows ORDER BY position, rowid'))
      _decodeRoom(row.read<String>('room')),
  ];

  /// [all], again after every change.
  Stream<List<LiveRoom>> watchAll() => _db.watch(_tables, all);

  /// Number of followed rooms.
  Future<int> count() async => (await _db.rows('SELECT COUNT(*) AS n FROM follows')).single.read<int>('n');

  /// Whether [room] is followed.
  Future<bool> contains(LiveRoom room) async => await find(room.platform, room.roomId) != null;

  /// [contains], again after every change.
  Stream<bool> watchContains(LiveRoom room) => _db.watch(_tables, () => contains(room));

  /// The followed room [platform]/[roomId] (3.x `getRoomById`).
  Future<LiveRoom?> find(String platform, String roomId) async {
    final rows = await _db.rows('SELECT room FROM follows WHERE identity = ?', [
      LiveRoom.identityKeyFor(platform: platform, roomId: roomId),
    ]);
    return rows.isEmpty ? null : _decodeRoom(rows.single.read<String>('room'));
  }

  /// Follows [room] at the end; false when it is invalid or already
  /// followed (3.x `addRoomDurably`).
  Future<bool> add(LiveRoom room) => _db.write(_tables, () async {
    if (!isStorableRoom(room) || await contains(room)) return false;
    await _db.run(
      'INSERT INTO follows (identity, position, room) '
      'VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM follows), ?)',
      [room.identityKey, _encodeRoom(room)],
    );
    return true;
  });

  /// Unfollows [room]; false when it was not followed.
  Future<bool> remove(LiveRoom room) => _db.write(_tables, () async {
    final before = await count();
    await _db.run('DELETE FROM follows WHERE identity = ?', [room.identityKey]);
    return await count() != before;
  });

  /// Applies refreshed [rooms] to the followed ones with
  /// [LiveRoom.mergeFrom]: an empty or placeholder name, title or cover
  /// keeps the stored one (UPGRADES X-2). Rooms not followed are ignored.
  /// Returns how many follows changed.
  Future<int> update(Iterable<LiveRoom> rooms) => _db.write(_tables, () async {
    var changed = 0;
    for (final incoming in rooms) {
      final current = await find(incoming.platform, incoming.roomId);
      if (current == null) continue;
      final merged = current.mergeFrom(incoming);
      final encoded = _encodeRoom(merged);
      if (encoded == _encodeRoom(current)) continue;
      await _db.run('UPDATE follows SET room = ? WHERE identity = ?', [encoded, current.identityKey]);
      changed++;
    }
    return changed;
  });

  /// Replaces the whole list (restore, reorder, bulk delete); invalid and
  /// duplicate rooms are dropped (3.x `replaceRoomsDurably`).
  Future<void> replaceAll(Iterable<LiveRoom> rooms) => _db.write(_tables, () async {
    await _db.run('DELETE FROM follows');
    await _insertAll(rooms);
  });

  /// Rewrites the list through [update] in one transaction (3.x
  /// `mutateRoomsDurably`); false when nothing changed.
  Future<bool> mutate(List<LiveRoom> Function(List<LiveRoom> current) update) => _db.write(_tables, () async {
    final before = await all();
    final after = uniqueRooms(update(List.of(before)));
    if (jsonEncode([for (final r in before) r.toJson()]) == jsonEncode([for (final r in after) r.toJson()])) {
      return false;
    }
    await _db.run('DELETE FROM follows');
    await _insertAll(after);
    return true;
  });

  Future<void> _insertAll(Iterable<LiveRoom> rooms) async {
    var position = 0;
    for (final room in uniqueRooms(rooms)) {
      await _db.run('INSERT INTO follows (identity, position, room) VALUES (?, ?, ?)', [
        room.identityKey,
        position++,
        _encodeRoom(room),
      ]);
    }
  }
}

/// Watch history, newest first, at most [Settings.historyLimit] entries
/// (0 keeps everything; 3.x `HistoryController`).
final class HistoryStore {
  /// Creates the store over `db`; `settings` gives the limit.
  new(this._db, this._settings);

  final StoreDatabase _db;
  final SettingsStore _settings;

  static const Set<String> _tables = {StoreTables.history};

  /// The history, newest first.
  Future<List<LiveRoom>> all() async => [
    for (final row in await _db.rows('SELECT room FROM history ORDER BY seq DESC'))
      _decodeRoom(row.read<String>('room')),
  ];

  /// [all], again after every change.
  Stream<List<LiveRoom>> watchAll() => _db.watch(_tables, all);

  /// Records that [room] was watched [now]: it moves to the front with
  /// `lastWatchedAt` and the list is cut to the limit (3.x
  /// `upsertHistoryRoom`). False for an invalid room.
  Future<bool> record(LiveRoom room, {DateTime? now}) => _db.write(_tables, () async {
    if (!isStorableRoom(room)) return false;
    final watchedAt = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _db.run('DELETE FROM history WHERE identity = ?', [room.identityKey]);
    await _db.run(
      'INSERT INTO history (identity, seq, room) VALUES (?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM history), ?)',
      [room.identityKey, _encodeRoom(room.copyWith(lastWatchedAt: watchedAt))],
    );
    await _trim();
    return true;
  });

  /// Removes [room].
  Future<void> remove(LiveRoom room) =>
      _db.write(_tables, () => _db.run('DELETE FROM history WHERE identity = ?', [room.identityKey]));

  /// Removes the entries of [shown] (what the page showed when the user
  /// chose "clear"): an entry watched again since then has a newer
  /// `lastWatchedAt` and stays (3.x `clearHistorySnapshotDurably`).
  Future<void> clear(Iterable<LiveRoom> shown) => _db.write(_tables, () async {
    for (final room in shown) {
      final rows = await _db.rows('SELECT room FROM history WHERE identity = ?', [room.identityKey]);
      if (rows.isEmpty) continue;
      if (_decodeRoom(rows.single.read<String>('room')).lastWatchedAt != room.lastWatchedAt) continue;
      await _db.run('DELETE FROM history WHERE identity = ?', [room.identityKey]);
    }
  });

  /// Applies refreshed rooms; the watch time and stored names stay (3.x
  /// `applyRefreshedRoomsDurably` with `preserveHistoryMetadata`).
  Future<void> update(Iterable<LiveRoom> rooms) => _db.write(_tables, () async {
    for (final incoming in rooms) {
      final rows = await _db.rows('SELECT room FROM history WHERE identity = ?', [incoming.identityKey]);
      if (rows.isEmpty) continue;
      final current = _decodeRoom(rows.single.read<String>('room'));
      final merged = current
          .mergeFrom(incoming.withAudienceFallbackFrom(current))
          .copyWith(lastWatchedAt: current.lastWatchedAt);
      await _db.run('UPDATE history SET room = ? WHERE identity = ?', [_encodeRoom(merged), current.identityKey]);
    }
  });

  /// Sets the limit and cuts the list to it (3.x `setHistoryLimitDurably`);
  /// a negative value means the default, 50.
  Future<void> setLimit(int limit) async {
    await _settings.set(Settings.historyLimit, limit < 0 ? Settings.historyLimit.defaultValue : limit);
    await _db.write(_tables, _trim);
  }

  /// Replaces the whole history, newest first (restore, migration).
  Future<void> replaceAll(Iterable<LiveRoom> rooms) => _db.write(_tables, () async {
    await _db.run('DELETE FROM history');
    final unique = uniqueRooms(rooms);
    for (var index = 0; index < unique.length; index++) {
      await _db.run('INSERT INTO history (identity, seq, room) VALUES (?, ?, ?)', [
        unique[index].identityKey,
        unique.length - index,
        _encodeRoom(unique[index]),
      ]);
    }
    await _trim();
  });

  Future<void> _trim() async {
    final limit = _settings.get(Settings.historyLimit);
    if (limit == 0) return;
    await _db.run(
      'DELETE FROM history WHERE identity NOT IN (SELECT identity FROM history ORDER BY seq DESC LIMIT ?)',
      [limit],
    );
  }
}

/// Followed areas (3.x `favoriteAreas`); identity is
/// [LiveArea.identityKey].
final class FollowAreaStore {
  /// Creates the store over `db`.
  new(this._db);

  final StoreDatabase _db;

  static const Set<String> _tables = {StoreTables.followAreas};

  /// The followed areas, in order.
  Future<List<LiveArea>> all() async => [
    for (final row in await _db.rows('SELECT area FROM follow_areas ORDER BY position, rowid'))
      LiveArea.fromJson((jsonDecode(row.read<String>('area')) as Map).cast<String, Object?>()),
  ];

  /// [all], again after every change.
  Stream<List<LiveArea>> watchAll() => _db.watch(_tables, all);

  /// Whether [area] is followed.
  Future<bool> contains(LiveArea area) async {
    final key = area.identityKey;
    if (key == null) return false;
    return (await _db.rows('SELECT 1 FROM follow_areas WHERE identity = ?', [key])).isNotEmpty;
  }

  /// Follows [area]; false without an identity or when already followed.
  Future<bool> add(LiveArea area) => _db.write(_tables, () async {
    final key = area.identityKey;
    if (key == null || await contains(area)) return false;
    await _db.run(
      'INSERT INTO follow_areas (identity, position, area) '
      'VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM follow_areas), ?)',
      [key, jsonEncode(area.toJson())],
    );
    return true;
  });

  /// Unfollows [area].
  Future<bool> remove(LiveArea area) => _db.write(_tables, () async {
    final key = area.identityKey;
    if (key == null || !await contains(area)) return false;
    await _db.run('DELETE FROM follow_areas WHERE identity = ?', [key]);
    return true;
  });

  /// Replaces the list; areas without identity and duplicates are dropped.
  Future<void> replaceAll(Iterable<LiveArea> areas) => _db.write(_tables, () async {
    await _db.run('DELETE FROM follow_areas');
    final seen = <String>{};
    var position = 0;
    for (final area in areas) {
      final key = area.identityKey;
      if (key == null || !seen.add(key)) continue;
      await _db.run('INSERT INTO follow_areas (identity, position, area) VALUES (?, ?, ?)', [
        key,
        position++,
        jsonEncode(area.toJson()),
      ]);
    }
  });
}
