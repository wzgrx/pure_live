import 'package:flutter/foundation.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';

/// How many of the room's messages the user's blocks hid (D02.2 c4: the
/// block list, "屏蔽只有表情的弹幕", "屏蔽超长弹幕"), for "本场已屏蔽 N 条".
///
/// Counted only, never stored: a new room has a new controller and starts
/// at 0. The value changes at once; the listeners hear of it at most once
/// a frame, as the chat list's ([ChatFeed], B08: a busy room sends 200
/// messages a second).
final class BlockedCount extends ChangeNotifier implements ValueListenable<int> {
  /// Creates the count at 0; [schedule] decides when the listeners hear of
  /// changes ([scheduleChatFlushForNextFrame] by default).
  new({ChatFlushScheduler? schedule}) : _schedule = schedule ?? scheduleChatFlushForNextFrame;

  final ChatFlushScheduler _schedule;
  bool _pending = false;
  bool _disposed = false;

  @override
  int get value => _value;
  int _value = 0;

  /// One more message hidden.
  void add() {
    _value++;
    if (_pending || _disposed) return;
    _pending = true;
    _schedule(_flush);
  }

  void _flush() {
    _pending = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
