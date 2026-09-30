import 'dart:collection';

import 'package:live_core/live_core.dart';

/// Drops platform backlog and packets delivered twice, always on (3.x
/// `DanmakuMessageGate`).
///
/// - A message with a platform time older than [maxMessageAge], or more than
///   10 minutes in the future (a malformed time), is dropped.
/// - A message with a [LiveMessage.messageId] passes once per
///   [stableIdWindow].
/// - Without an id the key is the type, the user id and name (trimmed, lower
///   case) and the trimmed text (and a retraction's target), once per
///   [fallbackDuplicateWindow]: short on purpose, so a viewer who repeats a
///   line is still seen.
/// - A rejected duplicate keeps its first time: the window does not slide.
/// - Keys older than [stableIdWindow] are forgotten; at most [maxEntries]
///   are kept.
final class DanmakuMessageGate {
  /// Creates the gate with 3.x's windows.
  new({
    this.fallbackDuplicateWindow = const Duration(milliseconds: 2500),
    this.stableIdWindow = const Duration(minutes: 10),
    this.maxMessageAge = const Duration(seconds: 45),
    this.maxEntries = 4096,
  });

  /// Duplicate window for messages without an id.
  final Duration fallbackDuplicateWindow;

  /// Duplicate window for messages with an id; also how long any key is kept.
  final Duration stableIdWindow;

  /// Oldest platform time accepted.
  final Duration maxMessageAge;

  /// Most keys kept.
  final int maxEntries;

  static const Duration _maxFutureSkew = Duration(minutes: -10);

  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  /// Whether [message], received [now] (default: the current time), passes.
  bool accepts(LiveMessage message, {DateTime? now}) {
    final receivedAt = now ?? DateTime.now();
    final sentAt = message.sentAt;
    if (sentAt != null) {
      final age = receivedAt.difference(sentAt);
      if (age > maxMessageAge || age < _maxFutureSkew) return false;
    }
    final stableId = message.messageId.trim();
    final hasStableId = stableId.isNotEmpty;
    final key = hasStableId
        ? 'id:$stableId'
        : 'text:${message.type.index}:${message.userId.trim().toLowerCase()}:'
              '${message.userName.trim().toLowerCase()}:${message.message.trim()}'
              // A retraction's target is its content.
              '${message.data is LiveRetraction ? ':${message.data}' : ''}';
    final window = hasStableId ? stableIdWindow : fallbackDuplicateWindow;
    final previous = _seen.remove(key);
    if (previous != null && receivedAt.difference(previous) <= window) {
      _seen[key] = previous;
      return false;
    }
    _seen[key] = receivedAt;
    final oldest = receivedAt.subtract(stableIdWindow);
    while (_seen.isNotEmpty && _seen.values.first.isBefore(oldest)) {
      _seen.remove(_seen.keys.first);
    }
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  /// Forgets every key (another room).
  void clear() => _seen.clear();
}
