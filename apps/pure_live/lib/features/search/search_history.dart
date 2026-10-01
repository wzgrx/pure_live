import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';

/// Recent search words, newest first (new in v4; 3.x kept none).
///
/// Kept in the store's internal records ([MetaStore], key [key]) as a JSON
/// list, so it lives with the rest of the user's data without a new
/// setting; it is not part of backups.
final class SearchHistory extends ChangeNotifier {
  /// Creates the history over the store's records.
  new(this._meta);

  final MetaStore _meta;

  /// The record key.
  static const String key = 'search.history';

  /// How many words are kept.
  static const int limit = 20;

  /// The longest word kept (longer ones, such as share texts, are cut).
  static const int maxLength = 200;

  List<String> _words = const [];
  bool _disposed = false;

  /// The words, newest first.
  List<String> get words => _words;

  /// Reads the stored words; bad records read as empty.
  Future<void> load() async {
    List<String> words;
    try {
      final decoded = jsonDecode(await _meta.get(key) ?? '[]');
      words = decoded is List ? _clean(decoded.whereType<String>()) : const [];
    } on FormatException {
      words = const [];
    }
    _set(words);
  }

  /// Puts [word] first (an equal word, case ignored, moves up).
  Future<void> add(String word) async {
    final text = word.trim();
    if (text.isEmpty) return;
    await _save(_clean([text, ..._words]));
  }

  /// Removes [word].
  Future<void> remove(String word) => _save([
    for (final item in _words)
      if (item != word) item,
  ]);

  /// Removes every word.
  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> words) async {
    _set(words);
    await _meta.set(key, jsonEncode(words));
  }

  void _set(List<String> words) {
    if (_disposed) return;
    _words = List.unmodifiable(words);
    notifyListeners();
  }

  static List<String> _clean(Iterable<String> words) {
    final seen = <String>{};
    return [
      for (final raw in words)
        if (_cut(raw.trim()) case final word when word.isNotEmpty && seen.add(word.toLowerCase())) word,
    ].take(limit).toList();
  }

  static String _cut(String word) => word.length <= maxLength ? word : word.substring(0, maxLength);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
