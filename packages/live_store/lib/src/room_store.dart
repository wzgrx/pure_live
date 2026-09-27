import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/rooms.dart';

/// Stored room data shared by follows, history and tags.
final class RoomStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  /// The stored room [ref], or null.
  Future<StoredRoom?> get(RoomRef ref) async {
    final row = await RoomRows.find(_db, ref);
    return row == null ? null : RoomRows.toModel(row);
  }

  /// Emits the stored room [ref] (null when unknown) and its changes.
  Stream<StoredRoom?> watch(RoomRef ref) =>
      (_db.select(_db.rooms)..where((row) => row.platform.equals(ref.platform) & row.roomId.equals(ref.roomId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : RoomRows.toModel(row));

  /// Applies refresh results to rooms the store already knows (followed,
  /// watched or tagged) in one transaction; unknown rooms are skipped, so a
  /// refresh never adds rows. Returns the number of rooms updated.
  Future<int> update(Iterable<RoomSnapshot> snapshots, {DateTime? at}) => _db.transaction(() async {
    var updated = 0;
    for (final snapshot in snapshots) {
      if (await RoomRows.find(_db, snapshot.ref) == null) continue;
      await RoomRows.upsert(_db, snapshot, now: at);
      updated++;
    }
    return updated;
  });

  /// Deletes rooms that nothing refers to any more (not followed, not in the
  /// history, without tags or preferences). Returns the number removed.
  Future<int> prune() => _db.customUpdate(
    'DELETE FROM rooms WHERE id NOT IN (SELECT room FROM follows) '
    'AND id NOT IN (SELECT room FROM history) AND id NOT IN (SELECT room FROM room_tags) '
    'AND id NOT IN (SELECT room FROM room_prefs)',
    updates: {_db.rooms},
    updateKind: UpdateKind.delete,
  );
}
