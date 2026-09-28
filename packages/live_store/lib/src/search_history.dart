import 'package:drift/drift.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/settings_store.dart';
import 'package:meta/meta.dart';

/// A recent search.
@immutable
final class SearchHistoryEntry {
  /// Creates an entry.
  const new({required this.keyword, required this.searchedAt});

  /// The keyword as last searched.
  final String keyword;

  /// When it was last searched.
  final DateTime searchedAt;

  /// The identity of [keyword]: see [SearchHistoryStore.fold].
  String get folded => SearchHistoryStore.fold(keyword);

  @override
  bool operator ==(Object other) =>
      other is SearchHistoryEntry && other.folded == folded && other.searchedAt == searchedAt;

  @override
  int get hashCode => Object.hash(folded, searchedAt);

  @override
  String toString() => 'SearchHistoryEntry($keyword)';
}

/// Recent search keywords (spec/product.md F-SRC-06): newest first, at most
/// [limit], one entry per keyword. Nothing is recorded while
/// [Settings.recordSearchHistory] is off.
final class SearchHistoryStore {
  /// Wraps [_db]; [_settings] says whether to record.
  new(this._db, this._settings);

  final StoreDatabase _db;
  final SettingsStore _settings;

  /// How many keywords are kept.
  static const limit = 20;

  static final _spaces = RegExp(r'\s+');

  /// [keyword] trimmed with inner runs of white space as one space.
  static String normalize(String keyword) => keyword.trim().replaceAll(_spaces, ' ');

  /// The identity of a keyword: normalized and lower-cased, so "LOL" and
  /// "lol " are one entry.
  static String fold(String keyword) => normalize(keyword).toLowerCase();

  SimpleSelectStatement<$SearchHistoryEntriesTable, SearchHistoryRow> _query() =>
      _db.select(_db.searchHistoryEntries)
        ..orderBy([(row) => OrderingTerm.desc(row.searchedAt), (row) => OrderingTerm.asc(row.keywordFolded)]);

  static SearchHistoryEntry _model(SearchHistoryRow row) => SearchHistoryEntry(
    keyword: row.keyword,
    searchedAt: DateTime.fromMillisecondsSinceEpoch(row.searchedAt, isUtc: true),
  );

  /// Every entry, newest first.
  Future<List<SearchHistoryEntry>> all() => _query().map(_model).get();

  /// Every entry, newest first, re-emitted after each change.
  Stream<List<SearchHistoryEntry>> watchAll() => _query().map(_model).watch();

  /// Records that [keyword] was searched at [at] (default now): it moves to
  /// the top with this spelling, and the oldest entries beyond [limit] go.
  /// Blank keywords, and every keyword while recording is off, are ignored.
  /// Returns whether it was recorded.
  Future<bool> record(String keyword, {DateTime? at}) async {
    final text = normalize(keyword);
    if (text.isEmpty || !_settings.get(Settings.recordSearchHistory)) return false;
    final time = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db
          .into(_db.searchHistoryEntries)
          .insertOnConflictUpdate(
            SearchHistoryEntriesCompanion.insert(keywordFolded: fold(text), keyword: text, searchedAt: time),
          );
      await _trim();
    });
    return true;
  }

  /// Removes [keyword] and returns the removed entry (for undo), or null.
  Future<SearchHistoryEntry?> remove(String keyword) => _db.transaction(() async {
    final key = fold(keyword);
    final row = await (_db.select(
      _db.searchHistoryEntries,
    )..where((entry) => entry.keywordFolded.equals(key))).getSingleOrNull();
    if (row == null) return null;
    await (_db.delete(_db.searchHistoryEntries)..where((entry) => entry.keywordFolded.equals(key))).go();
    return _model(row);
  });

  /// Clears the entries of [shown], the list the user saw when choosing
  /// "clear" (every entry when null); keywords searched again since then
  /// stay, as in the watch history (store.md §3). Returns the removed
  /// entries for undo.
  Future<List<SearchHistoryEntry>> clear([Iterable<SearchHistoryEntry>? shown]) => _db.transaction(() async {
    final current = await all();
    final wanted = shown?.toSet();
    final removed = [
      for (final entry in current)
        if (wanted == null || wanted.contains(entry)) entry,
    ];
    for (final entry in removed) {
      await (_db.delete(_db.searchHistoryEntries)..where((row) => row.keywordFolded.equals(entry.folded))).go();
    }
    return removed;
  });

  /// Puts back entries returned by [remove] or [clear]; a keyword searched
  /// again in the meantime keeps its newer entry. Works while recording is
  /// off: undo puts back what the user just removed.
  Future<void> restore(Iterable<SearchHistoryEntry> entries) => _db.transaction(() async {
    for (final entry in entries) {
      final text = normalize(entry.keyword);
      if (text.isEmpty) continue;
      final time = entry.searchedAt.toUtc().millisecondsSinceEpoch;
      final existing = await (_db.select(
        _db.searchHistoryEntries,
      )..where((row) => row.keywordFolded.equals(fold(text)))).getSingleOrNull();
      if (existing != null && existing.searchedAt >= time) continue;
      await _db
          .into(_db.searchHistoryEntries)
          .insertOnConflictUpdate(
            SearchHistoryEntriesCompanion.insert(keywordFolded: fold(text), keyword: text, searchedAt: time),
          );
    }
    await _trim();
  });

  Future<void> _trim() => _db.customUpdate(
    'DELETE FROM search_history WHERE keyword_folded NOT IN '
    '(SELECT keyword_folded FROM search_history ORDER BY searched_at DESC, keyword_folded ASC LIMIT ?1)',
    variables: [Variable.withInt(limit)],
    updates: {_db.searchHistoryEntries},
    updateKind: UpdateKind.delete,
  );
}
