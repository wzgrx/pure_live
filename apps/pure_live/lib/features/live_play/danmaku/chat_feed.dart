import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

/// What a line of the chat list is.
enum ChatLineKind {
  /// A viewer's message.
  chat,

  /// A paid message (also on the super-chat tab).
  superChat,

  /// A platform notice (subscriptions, raids, room announcements).
  notice,

  /// A gift a viewer sent (B-21).
  gift,

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

  /// A gift.
  new gift(LiveMessage this.message) : kind = ChatLineKind.gift, text = message.message, superChat = null;

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

  /// Taken off the feed (a retraction, a block, the gift switch). Lines
  /// that only fall off the old end of the feed are not marked.
  bool removed = false;

  List<ChatSegment>? _segments;
  EmoteTable? _segmentsOf;

  /// The text and emoticons of the line with [table], parsed once (B08: the
  /// list parsed them again every time it built the line).
  List<ChatSegment> segments(EmoteTable table) {
    if (_segments case final cached? when identical(_segmentsOf, table)) return cached;
    _segmentsOf = table;
    return _segments = switch (message) {
      final message? => chatSegments(message, table),
      null => [ChatTextSegment(text)],
    };
  }
}

/// Hands [flush] to the time the feed's listeners hear of its changes.
typedef ChatFlushScheduler = void Function(VoidCallback flush);

/// The app's [ChatFlushScheduler]: at the start of the next frame, so the
/// list builds the new lines in that frame. Without a binding (plain unit
/// tests) at once.
void scheduleChatFlushForNextFrame(VoidCallback flush) {
  if (kDebugMode && BindingBase.debugBindingType() == null) {
    flush();
    return;
  }
  SchedulerBinding.instance
    ..scheduleFrameCallback((_) => flush())
    ..scheduleFrame();
}

/// The chat list: the last [capacity] lines (3.x kept 500), with the
/// platform's retractions applied.
///
/// The lines change at once; the listeners hear of it at most once a frame
/// (B08: a busy room sends 200 messages a second, and the whole room page
/// used to hear of each one).
final class ChatFeed extends ChangeNotifier {
  /// Creates an empty feed; [schedule] decides when the listeners hear of
  /// changes ([scheduleChatFlushForNextFrame] by default).
  new({this.capacity = 500, ChatFlushScheduler? schedule}) : _schedule = schedule ?? scheduleChatFlushForNextFrame;

  /// The most lines kept.
  final int capacity;

  final ChatFlushScheduler _schedule;
  final List<ChatLine> _lines = [];
  int _next = 0;
  int _removals = 0;
  final List<bool Function(ChatLine line)> _removalTests = [];
  static const int _keptRemovalTests = 64;
  bool _pending = false;
  bool _disposed = false;

  /// Lines, oldest first.
  List<ChatLine> get lines => List.unmodifiable(_lines);

  /// Number of lines.
  int get length => _lines.length;

  /// Lines added so far (the list's "new messages" count).
  int get added => _next;

  /// How many removals there were (retractions, blocks, the gift switch),
  /// whether or not they found a line here.
  int get removals => _removals;

  /// The tests of the removals after the first [count] of them, oldest
  /// first, for a list that holds older lines than the feed (3.x: a held
  /// list loses the blocked lines too); null when they are no longer all
  /// kept.
  List<bool Function(ChatLine line)>? removalsSince(int count) {
    final missing = _removals - count;
    if (missing < 0 || missing > _removalTests.length) return null;
    return _removalTests.sublist(_removalTests.length - missing);
  }

  /// Whether a change waits for the listeners.
  bool get pending => _pending;

  /// Adds [line] at the end, dropping the oldest beyond [capacity].
  void add(ChatLine line) {
    line.id = _next++;
    _lines.add(line);
    if (_lines.length > capacity) _lines.removeRange(0, _lines.length - capacity);
    _changed();
  }

  /// Takes back what [retraction] names: one message by id, a user's
  /// messages, or all chat (status lines and gifts stay).
  void retract(LiveRetraction retraction) {
    if (retraction.isAll) {
      removeWhere((line) => line.kind == ChatLineKind.chat);
      return;
    }
    final messageId = retraction.messageId;
    final userId = retraction.userId;
    removeWhere((line) {
      final message = line.message;
      if (message == null || line.kind != ChatLineKind.chat) return false;
      if (messageId != null) return message.messageId == messageId;
      return userId != null && message.userId == userId;
    });
  }

  /// Removes the lines [test] accepts.
  void removeWhere(bool Function(ChatLine line) test) {
    _lines.removeWhere((line) {
      if (!test(line)) return false;
      line.removed = true;
      return true;
    });
    _removals++;
    _removalTests.add(test);
    if (_removalTests.length > _keptRemovalTests) _removalTests.removeAt(0);
    _changed();
  }

  /// Removes everything.
  void clear() => removeWhere((_) => true);

  /// Tells the listeners now instead of at the next frame (a line composed
  /// on this device shows at once).
  void flush() => _deliver();

  void _changed() {
    if (_pending || _disposed) return;
    _pending = true;
    _schedule(_deliver);
  }

  void _deliver() {
    if (!_pending || _disposed) return;
    _pending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
