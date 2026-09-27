import 'dart:collection';

import 'package:live_danmaku/src/model.dart';
import 'package:meta/meta.dart';

/// One change to a [DanmakuHistory], for incremental list updates (LST-1).
@immutable
final class HistoryChange {
  /// Creates a change.
  const new({this.appended = 0, this.trimmed = 0, this.removed = 0, this.cleared = false});

  /// Lines added at the end.
  final int appended;

  /// Lines that fell off the start because the buffer was full.
  final int trimmed;

  /// Lines removed by a block-list change.
  final int removed;

  /// Whether everything was cleared.
  final bool cleared;

  /// Whether nothing changed.
  bool get isEmpty => appended == 0 && trimmed == 0 && removed == 0 && !cleared;
}

/// LST-1 the room's chat history: a ring buffer of [capacity] lines (500)
/// that reports each batch as an increment instead of copying the list.
final class DanmakuHistory {
  /// Creates the buffer.
  new({this.capacity = 500});

  /// Most lines kept.
  final int capacity;

  final ListQueue<DanmakuEvent> _lines = ListQueue();

  /// Lines, oldest first.
  Iterable<DanmakuEvent> get lines => _lines;

  /// Number of lines.
  int get length => _lines.length;

  /// The line at [index] (0 is the oldest).
  DanmakuEvent operator [](int index) => _lines.elementAt(index);

  /// Appends [events]; the oldest lines beyond [capacity] are trimmed.
  HistoryChange addAll(Iterable<DanmakuEvent> events) {
    var appended = 0;
    var trimmed = 0;
    for (final event in events) {
      _lines.add(event);
      appended++;
      if (_lines.length > capacity) {
        _lines.removeFirst();
        trimmed++;
      }
    }
    return HistoryChange(appended: appended, trimmed: trimmed);
  }

  /// Removes the lines [test] matches (LST-3: the rest keep their order).
  HistoryChange removeWhere(bool Function(DanmakuEvent event) test) {
    final before = _lines.length;
    _lines.removeWhere(test);
    return HistoryChange(removed: before - _lines.length);
  }

  /// Clears the history (room change).
  HistoryChange clear() {
    _lines.clear();
    return const HistoryChange(cleared: true);
  }
}

/// LST-5 the room's super chats: deduplicated by the §1 equality, removed
/// at their end time, kept across a same-room reload, cleared on a room
/// change. The app sets one timer for [nextExpiry].
final class SuperChatBoard {
  final List<DanmakuSuperChat> _items = [];

  /// Current super chats, earliest end first.
  List<DanmakuSuperChat> get items => List.unmodifiable(_items);

  /// Adds the new ones among [chats] that have not ended at [now]; true
  /// when the board changed.
  bool addAll(Iterable<DanmakuSuperChat> chats, DateTime now) {
    var changed = false;
    for (final chat in chats) {
      if (!chat.endAt.isAfter(now) || _items.contains(chat)) continue;
      _items.add(chat);
      changed = true;
    }
    if (changed) _items.sort((a, b) => a.endAt.compareTo(b.endAt));
    return changed;
  }

  /// Removes the ones ended at [now]; true when the board changed.
  bool expire(DateTime now) {
    final before = _items.length;
    _items.removeWhere((chat) => !chat.endAt.isAfter(now));
    return _items.length != before;
  }

  /// When the next one ends, or null when the board is empty.
  DateTime? get nextExpiry => _items.isEmpty ? null : _items.first.endAt;

  /// Empties the board (room change).
  void clear() => _items.clear();
}

/// LST-7 shows the same status notice at most once in [window] (3 s).
final class NoticeThrottle {
  /// Creates the throttle.
  new({this.window = const Duration(seconds: 3)});

  /// Quiet time per status.
  final Duration window;

  final Map<DanmakuStatus, DateTime> _shown = {};

  /// Whether [notice] should be shown at [now].
  bool accepts(DanmakuSystem notice, DateTime now) {
    final last = _shown[notice.status];
    if (last != null && now.difference(last) < window) return false;
    _shown[notice.status] = now;
    return true;
  }

  /// Forgets what was shown.
  void clear() => _shown.clear();
}
