import 'package:live_store/src/database.dart';

/// What a danmaku block rule matches.
enum BlockKind {
  /// A keyword in the text (3.x `shieldList`).
  keyword,

  /// A sender name (3.x `blockedDanmakuUsers`).
  user,
}

/// Danmaku block lists: entries are trimmed, never empty, and unique without
/// regard to case; the first spelling wins (3.x
/// `_normalizeDanmakuBlockValues`).
final class BlockListStore {
  /// Creates the store over `db`.
  new(this._db);

  final StoreDatabase _db;

  static const Set<String> _tables = {StoreTables.blockRules};

  /// Longest keyword the settings page accepts (3.x
  /// `FavoriteRoomController.maxShieldKeywordLength`; imports keep longer
  /// ones, as 3.x did).
  static const int maxKeywordLength = 40;

  /// The entries of [kind], in the order they were added.
  Future<List<String>> list(BlockKind kind) async => [
    for (final row in await _db.rows('SELECT value FROM block_rules WHERE kind = ? ORDER BY position, rowid', [
      kind.name,
    ]))
      row.read<String>('value'),
  ];

  /// [list], again after every change.
  Stream<List<String>> watch(BlockKind kind) => _db.watch(_tables, () => list(kind));

  /// Adds [value]; false when it is empty or already there.
  Future<bool> add(BlockKind kind, String value) => _db.write(_tables, () async {
    final text = value.trim();
    if (text.isEmpty) return false;
    final exists = await _db.rows('SELECT 1 FROM block_rules WHERE kind = ? AND folded = ?', [
      kind.name,
      text.toLowerCase(),
    ]);
    if (exists.isNotEmpty) return false;
    await _db.run(
      'INSERT INTO block_rules (kind, folded, value, position) '
      'VALUES (?, ?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM block_rules WHERE kind = ?))',
      [kind.name, text.toLowerCase(), text, kind.name],
    );
    return true;
  });

  /// Removes [value] (compared without regard to case).
  Future<void> remove(BlockKind kind, String value) => _db.write(
    _tables,
    () => _db.run('DELETE FROM block_rules WHERE kind = ? AND folded = ?', [kind.name, value.trim().toLowerCase()]),
  );

  /// Replaces the list of [kind] (restore, migration).
  Future<void> replaceAll(BlockKind kind, Iterable<String> values) => _db.write(_tables, () async {
    await _db.run('DELETE FROM block_rules WHERE kind = ?', [kind.name]);
    final seen = <String>{};
    var position = 0;
    for (final raw in values) {
      final text = raw.trim();
      if (text.isEmpty || !seen.add(text.toLowerCase())) continue;
      await _db.run('INSERT INTO block_rules (kind, folded, value, position) VALUES (?, ?, ?, ?)', [
        kind.name,
        text.toLowerCase(),
        text,
        position++,
      ]);
    }
  });
}
