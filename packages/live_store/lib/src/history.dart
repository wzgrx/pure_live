import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/settings_store.dart';
import 'package:meta/meta.dart';

/// A watched room.
@immutable
final class HistoryEntry {
  /// Creates an entry.
  const new({required this.room, this.lastWatchedAt});

  /// Stored card data.
  final StoredRoom room;

  /// When the room was last watched; null for 3.x entries recorded before
  /// the time was saved.
  final DateTime? lastWatchedAt;

  /// Shortcut for the room identity.
  RoomRef get ref => room.ref;

  @override
  String toString() => 'HistoryEntry(${ref.key})';
}

/// Watch history (spec/product.md F-HIS-01, store.md §3).
///
/// Newest first; entries without a time come last in their import order.
/// The size is capped by [Settings.historyLimit] (0 = unlimited).
final class HistoryStore {
  /// Wraps [_db]; [_settings] supplies the size limit.
  new(this._db, this._settings);

  final StoreDatabase _db;
  final SettingsStore _settings;

  static const _order = 'h.last_watched_at IS NULL, h.last_watched_at DESC, h.id ASC';

  Selectable<HistoryEntry> _query({RoomRef? only}) {
    final filter = only == null ? '' : 'WHERE r.platform = ?1 AND r.room_id = ?2';
    return _db
        .customSelect(
          'SELECT r.*, h.last_watched_at AS h_last_watched_at FROM history h JOIN rooms r ON r.id = h.room '
          '$filter ORDER BY $_order',
          variables: [
            if (only != null) ...[Variable.withString(only.platform), Variable.withString(only.roomId)],
          ],
          readsFrom: {_db.historyEntries, _db.rooms},
        )
        .map((row) {
          final watched = row.readNullable<int>('h_last_watched_at');
          return HistoryEntry(
            room: RoomRows.toModel(_db.rooms.map(row.data)),
            lastWatchedAt: watched == null ? null : DateTime.fromMillisecondsSinceEpoch(watched, isUtc: true),
          );
        });
  }

  /// Every entry, newest first.
  Future<List<HistoryEntry>> all() => _query().get();

  /// Every entry, newest first, re-emitted after each change.
  Stream<List<HistoryEntry>> watchAll() => _query().watch();

  /// The entry of [ref], or null.
  Future<HistoryEntry?> get(RoomRef ref) => _query(only: ref).getSingleOrNull();

  /// Records that [room] was watched at [at] (default now), moving it to the
  /// top, then trims the history to the limit.
  Future<void> record(RoomSnapshot room, {DateTime? at}) => _db.transaction(() async {
    final time = (at ?? DateTime.now()).toUtc();
    final id = await RoomRows.upsert(_db, room, now: time);
    await (_db.delete(_db.historyEntries)..where((row) => row.room.equals(id))).go();
    await _db
        .into(_db.historyEntries)
        .insert(HistoryEntriesCompanion.insert(room: id, lastWatchedAt: Value(time.millisecondsSinceEpoch)));
    await trim();
  });

  /// Removes [ref] and returns the removed entry (for undo), or null.
  Future<HistoryEntry?> remove(RoomRef ref) => _db.transaction(() async {
    final previous = await get(ref);
    if (previous == null) return null;
    final row = await RoomRows.find(_db, ref);
    await (_db.delete(_db.historyEntries)..where((entry) => entry.room.equals(row!.id))).go();
    return previous;
  });

  /// Clears the entries of [snapshot], the list the user saw when choosing
  /// "clear". Rooms watched again since then (a different time) and rooms
  /// added since stay (store.md §3, REG-STORE-015). Returns the removed
  /// entries for undo.
  Future<List<HistoryEntry>> clear(Iterable<HistoryEntry> snapshot) => _db.transaction(() async {
    final removed = <HistoryEntry>[];
    for (final entry in snapshot) {
      final current = await get(entry.ref);
      if (current == null || current.lastWatchedAt != entry.lastWatchedAt) continue;
      final row = await RoomRows.find(_db, entry.ref);
      await (_db.delete(_db.historyEntries)..where((history) => history.room.equals(row!.id))).go();
      removed.add(current);
    }
    return removed;
  });

  /// Puts back entries returned by [remove] or [clear]; rooms watched again
  /// in the meantime keep their newer entry.
  Future<void> restore(Iterable<HistoryEntry> entries) => _db.transaction(() async {
    for (final entry in entries) {
      final id = await RoomRows.ensure(_db, entry.ref);
      await _db
          .into(_db.historyEntries)
          .insert(
            HistoryEntriesCompanion.insert(
              room: id,
              lastWatchedAt: Value(entry.lastWatchedAt?.toUtc().millisecondsSinceEpoch),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await trim();
  });

  /// Deletes the oldest entries beyond [Settings.historyLimit]; call after
  /// lowering the limit. Returns the number removed.
  Future<int> trim() async {
    final limit = _settings.get(Settings.historyLimit);
    if (limit <= 0) return 0;
    return await _db.customUpdate(
      'DELETE FROM history WHERE id NOT IN (SELECT h.id FROM history h ORDER BY $_order LIMIT ?1)',
      variables: [Variable.withInt(limit)],
      updates: {_db.historyEntries},
      updateKind: UpdateKind.delete,
    );
  }
}
