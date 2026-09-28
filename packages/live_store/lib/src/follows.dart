import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/rooms.dart';
import 'package:meta/meta.dart';

/// How a follow was created.
enum FollowSource {
  /// The user followed the room.
  user,

  /// Imported from 3.x data.
  import,

  /// Restored from a backup.
  backup,
}

/// A followed room.
@immutable
final class FollowedRoom {
  /// Creates an entry.
  const new({
    required this.room,
    required this.followedAt,
    required this.order,
    this.source = FollowSource.user,
    this.tagIds = const {},
  });

  /// Stored card data.
  final StoredRoom room;

  /// When the room was followed.
  final DateTime followedAt;

  /// Custom order, ascending.
  final int order;

  /// How the follow was created.
  final FollowSource source;

  /// Ids of the tags (groups) the room belongs to.
  final Set<String> tagIds;

  /// Shortcut for the room identity.
  RoomRef get ref => room.ref;

  @override
  String toString() => 'FollowedRoom(${ref.key})';
}

/// Followed rooms (spec/product.md §3).
final class FollowStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  static const _separator = '\u001f';

  Selectable<FollowedRoom> _query({RoomRef? only}) {
    final filter = only == null ? '' : 'WHERE r.platform = ?1 AND r.room_id = ?2';
    return _db
        .customSelect(
          'SELECT r.*, f.sort_order AS f_sort_order, f.followed_at AS f_followed_at, f.source AS f_source, '
          '(SELECT group_concat(t.tag, char(31)) FROM room_tags t WHERE t.room = r.id) AS f_tag_ids '
          'FROM follows f JOIN rooms r ON r.id = f.room $filter '
          'ORDER BY f.sort_order, f.followed_at, r.id',
          variables: [
            if (only != null) ...[Variable.withString(only.platform), Variable.withString(only.roomId)],
          ],
          readsFrom: {_db.follows, _db.rooms, _db.roomTags},
        )
        .map((row) {
          final tags = row.readNullable<String>('f_tag_ids');
          return FollowedRoom(
            room: RoomRows.toModel(_db.rooms.map(row.data)),
            order: row.read<int>('f_sort_order'),
            followedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('f_followed_at'), isUtc: true),
            source: FollowSource.values.asNameMap()[row.read<String>('f_source')] ?? FollowSource.user,
            tagIds: tags == null || tags.isEmpty ? const {} : tags.split(_separator).toSet(),
          );
        });
  }

  /// Every follow in custom order.
  Future<List<FollowedRoom>> all() => _query().get();

  /// Every follow in custom order, re-emitted after each change to follows,
  /// their rooms or their tags.
  Stream<List<FollowedRoom>> watchAll() => _query().watch();

  /// The follow of [ref], or null.
  Future<FollowedRoom?> get(RoomRef ref) => _query(only: ref).getSingleOrNull();

  /// Emits the follow of [ref] (null when not followed) and its changes.
  Stream<FollowedRoom?> watch(RoomRef ref) => _query(only: ref).watchSingleOrNull();

  /// Whether [ref] is followed.
  Future<bool> contains(RoomRef ref) async => await get(ref) != null;

  /// Emits whether [ref] is followed, and each change.
  Stream<bool> watchContains(RoomRef ref) => watch(ref).map((follow) => follow != null).distinct();

  /// Number of follows.
  Future<int> count() async {
    final row = await _db.customSelect('SELECT COUNT(*) AS c FROM follows', readsFrom: {_db.follows}).getSingle();
    return row.read<int>('c');
  }

  /// Follows [room] at the end of the list, or updates its card data when it
  /// is already followed. Completes after the write is stored.
  Future<void> follow(RoomSnapshot room, {DateTime? at, FollowSource source = FollowSource.user}) =>
      _db.transaction(() async {
        final time = (at ?? DateTime.now()).toUtc();
        final id = await RoomRows.upsert(_db, room, now: time);
        final existing = await (_db.select(_db.follows)..where((row) => row.room.equals(id))).getSingleOrNull();
        if (existing != null) return;
        await _db
            .into(_db.follows)
            .insert(
              FollowsCompanion.insert(
                room: Value(id),
                sortOrder: await _nextOrder(),
                followedAt: time.millisecondsSinceEpoch,
                source: Value(source.name),
              ),
            );
      });

  /// Unfollows [ref] and returns the removed entry (for undo), or null when it
  /// was not followed. Tags stay with the room, so following again restores
  /// its groups.
  Future<FollowedRoom?> unfollow(RoomRef ref) => _db.transaction(() async {
    final previous = await get(ref);
    if (previous == null) return null;
    final row = await RoomRows.find(_db, ref);
    await (_db.delete(_db.follows)..where((follow) => follow.room.equals(row!.id))).go();
    return previous;
  });

  /// Unfollows every room in [refs] in one transaction (multi-select
  /// "取消关注", spec/product.md F-FAV-09) and returns the removed entries in
  /// list order, for undo. Rooms that were not followed are skipped; a
  /// failed write unfollows none.
  Future<List<FollowedRoom>> unfollowAll(Iterable<RoomRef> refs) => _db.transaction(() async {
    final wanted = refs.toSet();
    final removed = [
      for (final follow in await all())
        if (wanted.contains(follow.ref)) follow,
    ];
    for (final follow in removed) {
      final row = await RoomRows.find(_db, follow.ref);
      await (_db.delete(_db.follows)..where((entry) => entry.room.equals(row!.id))).go();
    }
    return removed;
  });

  /// Puts back entries returned by [unfollow] or [unfollowAll] with their
  /// order and time.
  Future<void> restore(Iterable<FollowedRoom> entries) => _db.transaction(() async {
    for (final entry in entries) {
      final id = await RoomRows.ensure(_db, entry.ref);
      await _db
          .into(_db.follows)
          .insert(
            FollowsCompanion.insert(
              room: Value(id),
              sortOrder: entry.order,
              followedAt: entry.followedAt.toUtc().millisecondsSinceEpoch,
              source: Value(entry.source.name),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  /// Stores a custom order: [refs] first in the given order, then every other
  /// follow in its previous order.
  Future<void> reorder(List<RoomRef> refs) => _db.transaction(() async {
    final current = await all();
    final wanted = refs.toSet();
    final ordered = [
      for (final ref in refs)
        if (current.any((follow) => follow.ref == ref)) ref,
      for (final follow in current)
        if (!wanted.contains(follow.ref)) follow.ref,
    ];
    for (final (index, ref) in ordered.indexed) {
      final row = await RoomRows.find(_db, ref);
      await (_db.update(
        _db.follows,
      )..where((follow) => follow.room.equals(row!.id))).write(FollowsCompanion(sortOrder: Value(index)));
    }
  });

  Future<int> _nextOrder() async {
    final max = _db.follows.sortOrder.max();
    final row = await (_db.selectOnly(_db.follows)..addColumns([max])).getSingle();
    final value = row.read(max);
    return value == null ? 0 : value + 1;
  }
}
