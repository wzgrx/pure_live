import 'dart:math';

import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/rooms.dart';
import 'package:meta/meta.dart';

/// A user tag; the follow page shows tags as groups (spec/product.md F-FAV-05).
@immutable
final class Tag {
  /// Creates a tag.
  const new({required this.id, required this.name, required this.order, this.description = ''});

  /// Stable id; 3.x ids are kept.
  final String id;

  /// Display name, unique regardless of case.
  final String name;

  /// Optional description.
  final String description;

  /// Custom order, ascending.
  final int order;

  @override
  bool operator ==(Object other) =>
      other is Tag && other.id == id && other.name == name && other.description == description && other.order == order;

  @override
  int get hashCode => Object.hash(id, name, description, order);

  @override
  String toString() => 'Tag($id, $name)';
}

/// Thrown when a tag name is empty or already used (names compare without
/// case, store.md §3).
final class TagNameException implements Exception {
  /// Creates the exception for [name].
  const new(this.name, {required this.duplicate});

  /// The rejected name.
  final String name;

  /// Whether the name is taken (otherwise it is empty).
  final bool duplicate;

  @override
  String toString() => duplicate ? 'TagNameException: "$name" already exists' : 'TagNameException: empty name';
}

/// Tags and tag membership.
final class TagStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;
  final Random _random = Random.secure();

  /// Folds a tag name for uniqueness: trimmed and lower-cased.
  static String fold(String name) => name.trim().toLowerCase();

  SimpleSelectStatement<$TagsTable, TagRow> _ordered() =>
      _db.select(_db.tags)..orderBy([(tag) => OrderingTerm.asc(tag.sortOrder), (tag) => OrderingTerm.asc(tag.name)]);

  static Tag _model(TagRow row) => Tag(id: row.id, name: row.name, description: row.description, order: row.sortOrder);

  /// Every tag in custom order.
  Future<List<Tag>> all() => _ordered().map(_model).get();

  /// Every tag in custom order, re-emitted after each change.
  Stream<List<Tag>> watchAll() => _ordered().map(_model).watch();

  /// Creates a tag at the end; throws [TagNameException] for an empty or
  /// duplicate name.
  Future<Tag> create(String name, {String description = ''}) => _db.transaction(() async {
    final trimmed = await _checkName(name);
    final max = _db.tags.sortOrder.max();
    final last = (await (_db.selectOnly(_db.tags)..addColumns([max])).getSingle()).read(max);
    final tag = Tag(id: _newId(), name: trimmed, description: description.trim(), order: last == null ? 0 : last + 1);
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: tag.id,
            name: tag.name,
            nameFolded: fold(tag.name),
            description: Value(tag.description),
            sortOrder: tag.order,
          ),
        );
    return tag;
  });

  /// Renames tag [id]; throws [TagNameException] for an empty or duplicate
  /// name.
  Future<void> rename(String id, String name) => _db.transaction(() async {
    final trimmed = await _checkName(name, except: id);
    await (_db.update(
      _db.tags,
    )..where((tag) => tag.id.equals(id))).write(TagsCompanion(name: Value(trimmed), nameFolded: Value(fold(trimmed))));
  });

  /// Changes the description of tag [id].
  Future<void> describe(String id, String description) => (_db.update(
    _db.tags,
  )..where((tag) => tag.id.equals(id))).write(TagsCompanion(description: Value(description.trim())));

  /// Deletes tag [id] and its memberships.
  Future<void> delete(String id) => (_db.delete(_db.tags)..where((tag) => tag.id.equals(id))).go();

  /// Stores a custom order: [ids] first in the given order, then the rest.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
    final current = await all();
    final known = {for (final tag in current) tag.id};
    final wanted = ids.where(known.contains).toList();
    final ordered = [...wanted, ...current.map((tag) => tag.id).where((id) => !wanted.contains(id))];
    for (final (index, id) in ordered.indexed) {
      await (_db.update(_db.tags)..where((tag) => tag.id.equals(id))).write(TagsCompanion(sortOrder: Value(index)));
    }
  });

  /// Tag ids of [ref].
  Future<Set<String>> tagsOf(RoomRef ref) async => (await _membership(ref).get()).toSet();

  /// Emits the tag ids of [ref] and each change.
  Stream<Set<String>> watchTagsOf(RoomRef ref) => _membership(ref).watch().map((ids) => ids.toSet());

  Selectable<String> _membership(RoomRef ref) => _db
      .customSelect(
        'SELECT t.tag FROM room_tags t JOIN rooms r ON r.id = t.room WHERE r.platform = ?1 AND r.room_id = ?2',
        variables: [Variable.withString(ref.platform), Variable.withString(ref.roomId)],
        readsFrom: {_db.roomTags, _db.rooms},
      )
      .map((row) => row.read<String>('tag'));

  /// Replaces the tags of [ref] with [tagIds]; unknown tag ids are ignored.
  Future<void> setTagsOf(RoomRef ref, Set<String> tagIds) => _db.transaction(() async {
    final room = await RoomRows.ensure(_db, ref);
    await (_db.delete(_db.roomTags)..where((row) => row.room.equals(room))).go();
    for (final id in await _existing(tagIds)) {
      await _db.into(_db.roomTags).insert(RoomTagsCompanion.insert(room: room, tag: id));
    }
  });

  /// Adds tag [tagId] to every room in [refs] (multi-select "set group").
  Future<void> addRooms(String tagId, Iterable<RoomRef> refs) => _db.transaction(() async {
    if ((await _existing({tagId})).isEmpty) return;
    for (final ref in refs) {
      final room = await RoomRows.ensure(_db, ref);
      await _db
          .into(_db.roomTags)
          .insert(
            RoomTagsCompanion.insert(room: room, tag: tagId),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  /// Removes tag [tagId] from every room in [refs].
  Future<void> removeRooms(String tagId, Iterable<RoomRef> refs) => _db.transaction(() async {
    for (final ref in refs) {
      final room = await RoomRows.find(_db, ref);
      if (room == null) continue;
      await (_db.delete(_db.roomTags)..where((row) => row.room.equals(room.id) & row.tag.equals(tagId))).go();
    }
  });

  Future<Set<String>> _existing(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.tags)..where((tag) => tag.id.isIn(ids))).get();
    return {for (final row in rows) row.id};
  }

  Future<String> _checkName(String name, {String? except}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw TagNameException(name, duplicate: false);
    final clash = await (_db.select(_db.tags)..where((tag) => tag.nameFolded.equals(fold(trimmed)))).getSingleOrNull();
    if (clash != null && clash.id != except) throw TagNameException(trimmed, duplicate: true);
    return trimmed;
  }

  String _newId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return 't${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
