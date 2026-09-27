import 'dart:collection';

import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/pipeline/similarity.dart';

/// FLT-1 the duplicate gate, always on, chat only: drops backlog older than
/// 45 s and timestamps more than 10 min ahead; one delivery per stable id in
/// 10 min; without an id one per (kind, user id, user name, text) in 2.5 s
/// (REG-DANMAKU-008, -009). At most [maxEntries] keys.
final class DanmakuGate {
  /// Creates the gate.
  new({
    this.maxAge = const Duration(seconds: 45),
    this.idWindow = const Duration(minutes: 10),
    this.textWindow = const Duration(milliseconds: 2500),
    this.maxEntries = 4096,
  });

  /// Oldest accepted platform timestamp.
  final Duration maxAge;

  /// Duplicate window for messages with an id.
  final Duration idWindow;

  /// Duplicate window for messages without one.
  final Duration textWindow;

  /// Key limit.
  final int maxEntries;

  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  /// Whether [chat] received at [now] passes.
  bool accepts(DanmakuChat chat, DateTime now) {
    final sentAt = chat.sentAt;
    if (sentAt != null) {
      final age = now.difference(sentAt);
      if (age > maxAge || age < const Duration(minutes: -10)) return false;
    }
    final id = chat.id;
    final key = id != null
        ? 'id:$id'
        : 'text:${chat.userId.trim().toLowerCase()}\u0000${chat.userName.trim().toLowerCase()}\u0000${chat.text.trim()}';
    final window = id != null ? idWindow : textWindow;
    final previous = _seen.remove(key);
    if (previous != null && now.difference(previous) <= window) {
      _seen[key] = previous;
      return false;
    }
    _seen[key] = now;
    final oldest = now.subtract(idWindow);
    while (_seen.isNotEmpty && _seen.values.first.isBefore(oldest)) {
      _seen.remove(_seen.keys.first);
    }
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  /// Forgets everything (room change).
  void clear() => _seen.clear();
}

/// FLT-2 blocked users and words. Both sides are normalised the same way
/// (trimmed, lower-cased) once per list change and once per message, so a
/// word with capitals blocks everywhere (REG-DANMAKU-002).
final class DanmakuBlockList {
  /// Creates the list.
  new({Iterable<String> users = const [], Iterable<String> words = const []})
    : _users = {
        for (final user in users)
          if (normalize(user) case final value when value.isNotEmpty) value,
      },
      _words = [
        for (final word in words)
          if (normalize(word) case final value when value.isNotEmpty) value,
      ];

  final Set<String> _users;
  final List<String> _words;

  /// The one normalisation: trimmed and lower-cased.
  static String normalize(String text) => text.trim().toLowerCase();

  /// Whether nothing is blocked.
  bool get isEmpty => _users.isEmpty && _words.isEmpty;

  /// Whether [event] is a chat or gift from a blocked user, or a chat
  /// containing a blocked word. The app uses the same test to remove shown
  /// list lines when the user blocks someone.
  bool matches(DanmakuEvent event) {
    if (isEmpty || event.isLocal) return false;
    switch (event) {
      case DanmakuChat(:final userName, :final text):
        if (_users.contains(normalize(userName))) return true;
        if (_words.isEmpty) return false;
        final body = normalize(text);
        return _words.any(body.contains);
      case DanmakuGift(:final userName):
        return _users.contains(normalize(userName));
      default:
        return false;
    }
  }
}

/// FLT-3 merges repeated text: whitespace collapsed, lower-cased; the window
/// slides with the last occurrence; at most [maxEntries] texts.
final class RepeatFilter {
  /// Creates the filter.
  new({this.maxEntries = 1024});

  /// Text limit.
  final int maxEntries;

  final LinkedHashMap<String, DateTime> _last = LinkedHashMap();

  static final _spaces = RegExp(r'\s+');

  /// Whether [text] at [now] is new within [window].
  bool accepts(String text, DateTime now, Duration window) {
    final key = text.trim().replaceAll(_spaces, ' ').toLowerCase();
    if (key.isEmpty) return true;
    final previous = _last.remove(key);
    _last[key] = now;
    final oldest = now.subtract(window);
    while (_last.isNotEmpty && _last.values.first.isBefore(oldest)) {
      _last.remove(_last.keys.first);
    }
    while (_last.length > maxEntries) {
      _last.remove(_last.keys.first);
    }
    return previous == null || now.difference(previous) > window;
  }

  /// Forgets everything.
  void clear() => _last.clear();
}

/// FLT-4 drops text too similar to a recent message: exact repeats on a
/// fast path, then [partialRatio] against the newest [maxComparisons]
/// cached texts.
final class SimilarityFilter {
  /// Creates the filter.
  new({this.maxComparisons = 96});

  /// Comparison budget per message.
  final int maxComparisons;

  final LinkedHashMap<String, DateTime> _cache = LinkedHashMap();

  /// How many comparisons the last call made (for performance tests).
  int lastComparisons = 0;

  /// Whether [text] at [now] is new given [threshold] (0–100), cache time
  /// [window] and cache size [capacity].
  bool accepts(String text, DateTime now, {required int threshold, required Duration window, required int capacity}) {
    final key = text.trim();
    lastComparisons = 0;
    if (key.isEmpty) return true;
    _cache.removeWhere((_, seen) => now.difference(seen) > window);
    if (_cache.remove(key) != null) {
      _cache[key] = now;
      return false;
    }
    var skip = _cache.length - maxComparisons;
    String? match;
    for (final cached in _cache.keys) {
      if (skip-- > 0) continue;
      lastComparisons++;
      if (isSimilar(cached, key, threshold)) {
        match = cached;
        break;
      }
    }
    if (match != null) {
      _cache.remove(match);
      _cache[match] = now;
      return false;
    }
    _cache[key] = now;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
    return true;
  }

  /// Forgets everything.
  void clear() => _cache.clear();
}
