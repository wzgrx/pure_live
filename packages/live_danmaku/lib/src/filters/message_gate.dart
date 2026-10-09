import 'dart:collection';

import 'package:live_core/live_core.dart';

/// Drops platform backlog and packets delivered twice, always on (3.x
/// `DanmakuMessageGate`).
///
/// - A message with a platform time older than [maxMessageAge], or more than
///   10 minutes in the future (a malformed time), is dropped. A
///   [LiveMessage.replayed] one (sent again after a resume, or a backlog
///   given on joining) may be up to [maxReplayAge] old instead; a super chat
///   ([LiveMessage.data] a [LiveSuperChatMessage]) is not dropped for its
///   age before its [LiveSuperChatMessage.endTime], since it is shown for
///   its own time (M5.F, B-26, B-22).
/// - A message with a [LiveMessage.messageId] passes once per
///   [stableIdWindow].
/// - Without an id the key is the type, the user id and name (trimmed, lower
///   case) and the trimmed text (and a retraction's target, a gift's running
///   combo count), once per [fallbackDuplicateWindow]: short on purpose, so a
///   viewer who repeats a line is still seen. (D07.1: each hit of a Douyu
///   combo has the same text, `粉丝荧光棒 ×10`, and a higher `hits`.)
/// - A rejected duplicate keeps its first time: the window does not slide.
/// - Keys older than [stableIdWindow] are forgotten; at most [maxEntries]
///   are kept.
final class DanmakuMessageGate {
  /// Creates the gate with 3.x's windows; [maxReplayAge] is 17LIVE's resume
  /// window (its `connectionStateTtl` + `maxIdleInterval`, 120 s + 15 s).
  new({
    this.fallbackDuplicateWindow = const Duration(milliseconds: 2500),
    this.stableIdWindow = const Duration(minutes: 10),
    this.maxMessageAge = const Duration(seconds: 45),
    this.maxReplayAge = const Duration(seconds: 135),
    this.maxEntries = 4096,
  });

  /// Duplicate window for messages without an id.
  final Duration fallbackDuplicateWindow;

  /// Duplicate window for messages with an id; also how long any key is kept.
  final Duration stableIdWindow;

  /// Oldest platform time accepted.
  final Duration maxMessageAge;

  /// Oldest platform time accepted for a [LiveMessage.replayed] message.
  final Duration maxReplayAge;

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
      final limit = message.replayed ? maxReplayAge : maxMessageAge;
      if (age < _maxFutureSkew || (age > limit && !_onDisplay(message, receivedAt))) return false;
    }
    final stableId = message.messageId.trim();
    final hasStableId = stableId.isNotEmpty;
    final key = hasStableId
        ? 'id:$stableId'
        : 'text:${message.type.index}:${message.userId.trim().toLowerCase()}:'
              '${message.userName.trim().toLowerCase()}:${message.message.trim()}'
              // A retraction's target is its content.
              '${message.data is LiveRetraction ? ':${message.data}' : ''}'
              // A combo's next hit is not the same gift again.
              '${switch (message.gift?.comboTotal) {
                final int total => ':combo:$total',
                null => '',
              }}';
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

  /// Whether [message] is a super chat still on display at [now].
  static bool _onDisplay(LiveMessage message, DateTime now) => switch (message.data) {
    LiveSuperChatMessage(:final endTime) => now.isBefore(endTime),
    _ => false,
  };

  /// Forgets every key (another room).
  void clear() => _seen.clear();
}
