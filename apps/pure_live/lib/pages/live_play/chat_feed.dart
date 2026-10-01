import 'package:live_core/live_core.dart';

/// What a line of the chat list is.
enum ChatLineKind {
  /// A viewer's message.
  chat,

  /// A paid message (also on the super-chat tab).
  superChat,

  /// A platform notice (subscriptions, raids, room announcements).
  notice,

  /// The app's own status (danmaku connecting, reconnecting).
  system,
}

/// One line of the chat list.
final class ChatLine {
  /// A viewer's message.
  new chat(LiveMessage this.message) : kind = ChatLineKind.chat, text = message.message, superChat = null;

  /// A paid message.
  new superChat(LiveSuperChatMessage this.superChat)
    : kind = ChatLineKind.superChat,
      text = superChat.message,
      message = null;

  /// A platform notice.
  new notice(LiveMessage this.message) : kind = ChatLineKind.notice, text = message.message, superChat = null;

  /// The app's status text.
  new system(this.text) : kind = ChatLineKind.system, message = null, superChat = null;

  /// The kind.
  final ChatLineKind kind;

  /// The text.
  final String text;

  /// The message, for chats and notices.
  final LiveMessage? message;

  /// The paid message, for super chats.
  final LiveSuperChatMessage? superChat;

  /// A sequence number given by the feed (stable list keys).
  int id = 0;
}

/// The chat list: the last [capacity] lines (3.x kept 500), with the
/// platform's retractions applied.
final class ChatFeed {
  /// Creates an empty feed.
  new({this.capacity = 500});

  /// The most lines kept.
  final int capacity;

  final List<ChatLine> _lines = [];
  int _next = 0;

  /// Lines, oldest first.
  List<ChatLine> get lines => List.unmodifiable(_lines);

  /// Number of lines.
  int get length => _lines.length;

  /// Lines added so far (the list's "new messages" count).
  int get added => _next;

  /// Adds [line] at the end, dropping the oldest beyond [capacity].
  void add(ChatLine line) {
    line.id = _next++;
    _lines.add(line);
    if (_lines.length > capacity) _lines.removeRange(0, _lines.length - capacity);
  }

  /// Takes back what [retraction] names: one message by id, a user's
  /// messages, or all chat (status lines stay).
  void retract(LiveRetraction retraction) {
    if (retraction.isAll) {
      _lines.removeWhere((line) => line.kind == ChatLineKind.chat);
      return;
    }
    final messageId = retraction.messageId;
    final userId = retraction.userId;
    _lines.removeWhere((line) {
      final message = line.message;
      if (message == null || line.kind != ChatLineKind.chat) return false;
      if (messageId != null) return message.messageId == messageId;
      return userId != null && message.userId == userId;
    });
  }

  /// Removes the lines [test] accepts.
  void removeWhere(bool Function(ChatLine line) test) => _lines.removeWhere(test);

  /// Removes everything.
  void clear() => _lines.clear();
}
