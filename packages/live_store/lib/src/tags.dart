import 'package:live_core/live_core.dart';
import 'package:live_store/src/database.dart';
import 'package:meta/meta.dart';

/// A follow group (3.x `LiveTag`).
@immutable
final class StoreTag {
  /// Creates a tag.
  const new({required this.id, required this.name, this.description = ''});

  /// Reads 3.x's `{id, name, description, order}`; a malformed field reads
  /// as empty instead of failing the whole list (3.x cast them).
  factory fromJson(Map<String, Object?> json) => StoreTag(
    id: '${json['id'] ?? ''}'.trim(),
    name: '${json['name'] ?? ''}'.trim(),
    description: '${json['description'] ?? ''}'.trim(),
  );

  /// Stable id (3.x used microsecond timestamps).
  final String id;

  /// Name; unique without regard to case.
  final String name;

  /// Description.
  final String description;

  /// 3.x's JSON, with [order] as its position.
  Map<String, Object?> toJson(int order) => {'id': id, 'name': name, 'description': description, 'order': order};

  @override
  bool operator ==(Object other) =>
      other is StoreTag && other.id == id && other.name == name && other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);

  @override
  String toString() => 'StoreTag($id, $name)';
}

/// Why a tag name was refused (3.x `TagNameValidation`).
enum TagNameValidation {
  /// Accepted.
  valid,

  /// Empty after trimming.
  empty,

  /// Another tag has the name (case-insensitive).
  duplicate,
}

/// Follow groups and which rooms are in them (3.x
/// `TagManagementController`: `user_custom_tags_v5` and
/// `room_to_tags_mapping_v1`). Rooms are keyed by [LiveRoom.identityKey].
final class TagStore {
  /// Creates the store over `db`.
  new(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final StoreDatabase _db;
  final DateTime Function() _now;
  int _lastId = 0;

  static const Set<String> _tables = {StoreTables.tags, StoreTables.roomTags};

  /// Longest tag name the dialogs take (3.x `maxLength: 15`; I03.2 c8: one
  /// definition for the tag editor and the room tags dialog).
  static const int maxNameLength = 15;

  /// Longest tag description or note the dialogs take (3.x `maxLength: 40`).
  static const int maxDescriptionLength = 40;

  /// The tags, in order.
  Future<List<StoreTag>> all() async => [
    for (final row in await _db.rows('SELECT id, name, description FROM tags ORDER BY position, rowid'))
      StoreTag(
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        description: row.read<String>('description'),
      ),
  ];

  /// [all], again after every change.
  Stream<List<StoreTag>> watchAll() => _db.watch(_tables, all);

  /// Whether [name] can be used (for the tag at [excludingId] when renaming).
  Future<TagNameValidation> validateName(String name, {String? excludingId}) async {
    final clean = name.trim();
    if (clean.isEmpty) return TagNameValidation.empty;
    final folded = clean.toLowerCase();
    final clash = (await all()).any((tag) => tag.id != excludingId && tag.name.toLowerCase() == folded);
    return clash ? TagNameValidation.duplicate : TagNameValidation.valid;
  }

  /// Adds a tag at the end; null when the name is refused.
  Future<StoreTag?> add(String name, {String description = ''}) => _db.write(_tables, () async {
    if (await validateName(name) != TagNameValidation.valid) return null;
    final tags = await all();
    final tag = StoreTag(id: _newId({for (final t in tags) t.id}), name: name.trim(), description: description.trim());
    await _db.run(
      'INSERT INTO tags (id, position, name, description) '
      'VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM tags), ?, ?)',
      [tag.id, tag.name, tag.description],
    );
    return tag;
  });

  /// Renames tag [id]; false when it does not exist or the name is refused.
  Future<bool> update(String id, {required String name, String description = ''}) => _db.write(_tables, () async {
    if (await validateName(name, excludingId: id) != TagNameValidation.valid) return false;
    await _db.run('UPDATE tags SET name = ?, description = ? WHERE id = ?', [name.trim(), description.trim(), id]);
    return (await all()).any((tag) => tag.id == id);
  });

  /// Deletes tag [id] and removes it from every room.
  Future<void> delete(String id) => _db.write(_tables, () async {
    await _db.run('DELETE FROM tags WHERE id = ?', [id]);
    await _db.run('DELETE FROM room_tags WHERE tag_id = ?', [id]);
  });

  /// Puts the tags in the order of [ids]; tags not named keep their
  /// relative order after them.
  Future<void> reorder(List<String> ids) => _db.write(_tables, () async {
    final tags = await all();
    final ordered = [
      for (final id in ids) ...tags.where((tag) => tag.id == id),
      ...tags.where((tag) => !ids.contains(tag.id)),
    ];
    for (var index = 0; index < ordered.length; index++) {
      await _db.run('UPDATE tags SET position = ? WHERE id = ?', [index, ordered[index].id]);
    }
  });

  /// Moves tag [id] to the front (3.x `pinToTop`).
  Future<void> pinToTop(String id) => reorder([id]);

  /// The tag ids of [room], in assignment order.
  Future<List<String>> tagsOf(LiveRoom room) async => [
    for (final row in await _db.rows('SELECT tag_id FROM room_tags WHERE room = ? ORDER BY position', [
      room.identityKey,
    ]))
      row.read<String>('tag_id'),
  ];

  /// Every room's tag ids, keyed by [LiveRoom.identityKey].
  Future<Map<String, List<String>>> assignments() async {
    final map = <String, List<String>>{};
    for (final row in await _db.rows('SELECT room, tag_id FROM room_tags ORDER BY room, position')) {
      map.putIfAbsent(row.read<String>('room'), () => []).add(row.read<String>('tag_id'));
    }
    return map;
  }

  /// [assignments], again after every change.
  Stream<Map<String, List<String>>> watchAssignments() => _db.watch(_tables, assignments);

  /// Sets the tags of [room]; unknown ids are dropped (3.x `setRoomTags`).
  Future<void> setTagsOf(LiveRoom room, List<String> tagIds) =>
      _db.write(_tables, () => _assign(room.identityKey, tagIds));

  /// Replaces every tag and assignment (restore, migration). Tags without
  /// an id or with a repeated one get a new id (3.x `_normalizeTags`);
  /// [assignments] keys are identity keys.
  Future<void> replaceAll(List<StoreTag> tags, Map<String, List<String>> assignments) => _db.write(_tables, () async {
    await _db.run('DELETE FROM tags');
    await _db.run('DELETE FROM room_tags');
    final used = <String>{};
    var position = 0;
    for (final tag in tags) {
      final id = tag.id.isEmpty || used.contains(tag.id) ? _newId(used) : tag.id;
      used.add(id);
      await _db.run('INSERT INTO tags (id, position, name, description) VALUES (?, ?, ?, ?)', [
        id,
        position++,
        tag.name,
        tag.description,
      ]);
    }
    for (final entry in assignments.entries) {
      await _assign(entry.key, entry.value);
    }
  });

  /// Moves the assignments of [from] to [to] (identity migration), joining
  /// both when [to] already has tags.
  Future<void> moveRoom(String from, String to) => _db.write(_tables, () async {
    if (from == to) return;
    final rows = await _db.rows('SELECT tag_id FROM room_tags WHERE room IN (?, ?) ORDER BY room = ? DESC, position', [
      to,
      from,
      to,
    ]);
    await _db.run('DELETE FROM room_tags WHERE room = ?', [from]);
    await _assign(to, [for (final row in rows) row.read<String>('tag_id')]);
  });

  Future<void> _assign(String room, List<String> tagIds) async {
    final known = {for (final tag in await all()) tag.id};
    await _db.run('DELETE FROM room_tags WHERE room = ?', [room]);
    final seen = <String>{};
    var position = 0;
    for (final raw in tagIds) {
      final id = raw.trim();
      if (!known.contains(id) || !seen.add(id)) continue;
      await _db.run('INSERT INTO room_tags (room, tag_id, position) VALUES (?, ?, ?)', [room, id, position++]);
    }
  }

  String _newId(Set<String> used) {
    var candidate = _now().microsecondsSinceEpoch;
    if (candidate <= _lastId) candidate = _lastId + 1;
    while (used.contains('$candidate')) {
      candidate++;
    }
    _lastId = candidate;
    return '$candidate';
  }
}
