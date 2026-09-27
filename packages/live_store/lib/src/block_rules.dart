import 'package:drift/drift.dart';
import 'package:live_store/src/database/database.dart';
import 'package:meta/meta.dart';

/// What a block rule matches (spec/modules/danmaku.md FLT-2).
enum BlockKind {
  /// A substring of the message text.
  keyword,

  /// A sender name, matched exactly.
  user,
}

/// A danmaku block rule.
@immutable
final class BlockRule {
  /// Creates a rule.
  const new({required this.kind, required this.value, required this.createdAt});

  /// What the rule matches.
  final BlockKind kind;

  /// The value as the user typed it (trimmed).
  final String value;

  /// When the rule was added.
  final DateTime createdAt;

  /// Trimmed, lower-cased [value]; filters compare messages folded the same
  /// way (REG-DANMAKU-002).
  String get folded => BlockRuleStore.fold(value);

  @override
  bool operator ==(Object other) => other is BlockRule && other.kind == kind && other.folded == folded;

  @override
  int get hashCode => Object.hash(kind, folded);

  @override
  String toString() => 'BlockRule(${kind.name}, $value)';
}

/// Block words and blocked users.
final class BlockRuleStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  /// Folds a value for matching and uniqueness: trimmed and lower-cased.
  static String fold(String value) => value.trim().toLowerCase();

  SimpleSelectStatement<$BlockRulesTable, BlockRuleRow> _query(BlockKind? kind) {
    final query = _db.select(_db.blockRules)..orderBy([(rule) => OrderingTerm.asc(rule.id)]);
    if (kind != null) query.where((rule) => rule.kind.equals(kind.name));
    return query;
  }

  static BlockRule _model(BlockRuleRow row) => BlockRule(
    kind: BlockKind.values.byName(row.kind),
    value: row.value,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
  );

  /// Rules of [kind] (every rule when null), oldest first.
  Future<List<BlockRule>> all([BlockKind? kind]) => _query(kind).map(_model).get();

  /// Rules of [kind] (every rule when null), re-emitted after each change.
  Stream<List<BlockRule>> watchAll([BlockKind? kind]) => _query(kind).map(_model).watch();

  /// Adds a rule; returns false when [value] is blank or already blocked
  /// (compared folded).
  Future<bool> add(BlockKind kind, String value, {DateTime? at}) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return await _db.transaction(() async {
      final existing = await (_db.select(
        _db.blockRules,
      )..where((rule) => rule.kind.equals(kind.name) & rule.valueFolded.equals(fold(trimmed)))).getSingleOrNull();
      if (existing != null) return false;
      await _db
          .into(_db.blockRules)
          .insert(
            BlockRulesCompanion.insert(
              kind: kind.name,
              value: trimmed,
              valueFolded: fold(trimmed),
              createdAt: (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
            ),
          );
      return true;
    });
  }

  /// Removes the rule matching [value] (compared folded); returns whether one
  /// was removed.
  Future<bool> remove(BlockKind kind, String value) async {
    final count = await (_db.delete(
      _db.blockRules,
    )..where((rule) => rule.kind.equals(kind.name) & rule.valueFolded.equals(fold(value)))).go();
    return count > 0;
  }
}
