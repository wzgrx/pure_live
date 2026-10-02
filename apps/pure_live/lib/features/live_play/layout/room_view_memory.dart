import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';

/// What the room's views keep while the page builds them anew (B09 c4,
/// audit B-12). The normal layout and the fullscreen are two trees, and a
/// turned phone or a resized window picks another layout, so the chat tabs,
/// the chat list and the portrait room's panel are built again each time:
/// they start from here instead of from scratch (the first tab, the newest
/// line, the first stop). The page keeps one per room; a room switched to in
/// the page starts afresh but keeps the panel's stop.
final class RoomViewMemory {
  /// An empty memory; [panelStop] from the room before.
  new({this.panelStop});

  /// The chat panel's tab (0: the chat).
  int chatTab = 0;

  /// The chat list as it was left while it held its lines, or null while it
  /// followed the newest line.
  ChatListMemory? chatList;

  /// The portrait room panel's stop: 0 the lowest, 1 the middle, 2 the
  /// highest; null for the one the layout mode starts at.
  int? panelStop;
}

/// A chat list that held its lines (scrolled away from the newest one): the
/// lines it showed, where it was scrolled and what it had counted.
final class ChatListMemory {
  /// Creates the memory.
  const new({
    required this.feed,
    required this.shown,
    required this.seen,
    required this.removals,
    required this.offset,
  });

  /// The feed the lines came from (another room's are not taken).
  final ChatFeed feed;

  /// The lines shown, oldest first.
  final List<ChatLine> shown;

  /// The feed's count of added lines when they were last seen.
  final int seen;

  /// The feed's count of removals already applied to [shown].
  final int removals;

  /// The scroll offset (from the newest line: the list is reversed).
  final double offset;
}
