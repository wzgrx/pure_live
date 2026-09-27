import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/rooms.dart';

/// Per-room preferences (store.md §3): `volume` (0–1), `portraitLayout`, and
/// later keys. Values are JSON.
final class RoomPrefStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  /// Key of the per-room volume, a number from 0 to 1.
  static const volume = 'volume';

  /// Key of the per-room portrait layout name.
  static const portraitLayout = 'portraitLayout';

  /// The value of [key] for [ref], or null.
  Future<Object?> get(RoomRef ref, String key) async {
    final row = await _db
        .customSelect(
          'SELECT p.value FROM room_prefs p JOIN rooms r ON r.id = p.room '
          'WHERE r.platform = ?1 AND r.room_id = ?2 AND p.key = ?3',
          variables: [Variable.withString(ref.platform), Variable.withString(ref.roomId), Variable.withString(key)],
          readsFrom: {_db.roomPrefs, _db.rooms},
        )
        .getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('value'));
  }

  /// Stores [value] (JSON-encodable) for [ref]; null removes it.
  Future<void> set(RoomRef ref, String key, Object? value) => _db.transaction(() async {
    if (value == null) {
      final room = await RoomRows.find(_db, ref);
      if (room == null) return;
      await (_db.delete(_db.roomPrefs)..where((row) => row.room.equals(room.id) & row.key.equals(key))).go();
      return;
    }
    final room = await RoomRows.ensure(_db, ref);
    await _db
        .into(_db.roomPrefs)
        .insertOnConflictUpdate(RoomPrefsCompanion.insert(room: room, key: key, value: jsonEncode(value)));
  });

  /// The stored volume of [ref] (0–1), or null.
  Future<double?> volumeOf(RoomRef ref) async {
    final value = await get(ref, volume);
    return value is num && value.isFinite ? value.toDouble().clamp(0, 1).toDouble() : null;
  }

  /// The orientation override of [ref] (GEO-7), automatic when none.
  Future<PortraitOverride> portraitOverrideOf(RoomRef ref) async {
    final value = await get(ref, portraitLayout);
    return PortraitOverride.values.firstWhere((item) => item.name == value, orElse: () => PortraitOverride.automatic);
  }

  /// Stores the override of [ref]; automatic removes it.
  Future<void> setPortraitOverride(RoomRef ref, PortraitOverride value) =>
      set(ref, portraitLayout, value == PortraitOverride.automatic ? null : value.name);

  /// Stores the volume of [ref], clamped to 0–1; null removes it.
  Future<void> setVolume(RoomRef ref, double? value) =>
      set(ref, volume, value == null || !value.isFinite ? null : value.clamp(0, 1).toDouble());
}

/// A room's orientation override (GEO-7); names match 3.x
/// `portraitRoomOverrides` values.
enum PortraitOverride {
  /// Follow the detected geometry.
  automatic,

  /// Treat the source as portrait.
  portrait,

  /// Treat the source as landscape.
  landscape,
}
