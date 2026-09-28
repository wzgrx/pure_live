import 'dart:collection';

import 'package:live_core/live_core.dart';

/// Collapses the same text sent by many viewers in a short time into its
/// first message (3.x `RepeatedDanmakuFilter`; off by default, see
/// `DanmakuFilterSettings`).
///
/// - Only chat from the platform counts: other types and local messages
///   always pass, and so does a text that is empty after trimming.
/// - Texts are compared trimmed, with runs of whitespace as one space, in
///   lower case.
/// - A text passes when it was not seen within `window`; every sighting,
///   passed or not, restarts its window (a burst stays collapsed while it
///   lasts).
/// - Calling with `enabled: false` passes everything and forgets what was
///   seen; at most [maxEntries] texts are kept.
final class RepeatedDanmakuFilter {
  /// Creates the filter.
  new({this.maxEntries = 1024});

  /// Most texts kept.
  final int maxEntries;

  static final RegExp _whitespace = RegExp(r'\s+');

  final LinkedHashMap<String, DateTime> _lastSeen = LinkedHashMap();

  /// Whether [message], received [now] (default: the current time), passes.
  bool accepts(LiveMessage message, {required bool enabled, required Duration window, DateTime? now}) {
    if (!enabled) {
      _lastSeen.clear();
      return true;
    }
    if (message.type != LiveMessageType.chat || message.isLocal) return true;
    final normalized = message.message.trim().replaceAll(_whitespace, ' ').toLowerCase();
    if (normalized.isEmpty) return true;
    final receivedAt = now ?? DateTime.now();
    final previous = _lastSeen.remove(normalized);
    _lastSeen[normalized] = receivedAt;
    final oldest = receivedAt.subtract(window);
    while (_lastSeen.isNotEmpty && _lastSeen.values.first.isBefore(oldest)) {
      _lastSeen.remove(_lastSeen.keys.first);
    }
    while (_lastSeen.length > maxEntries) {
      _lastSeen.remove(_lastSeen.keys.first);
    }
    return previous == null || receivedAt.difference(previous) > window;
  }

  /// Forgets every text (another room).
  void clear() => _lastSeen.clear();
}
