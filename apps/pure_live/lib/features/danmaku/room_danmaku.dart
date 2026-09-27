import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart' show BlockKind;
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// One change of the chat list, for incremental list updates (LST-1).
@immutable
final class ChatLogChange {
  const new({this.appended = 0, this.trimmed = 0, this.removed, this.cleared = false, this.local = false});

  /// Lines added at the end.
  final int appended;

  /// Oldest lines dropped because the buffer is full.
  final int trimmed;

  /// The test that removed lines (a block), so a frozen list can remove the
  /// same lines from its snapshot (LST-3).
  final bool Function(DanmakuEvent line)? removed;

  /// Everything was cleared (room change).
  final bool cleared;

  /// The appended line is the user's own local line: shown at once, and the
  /// list follows again (LST-2).
  final bool local;
}

/// The room's chat list: the 500-line history of `live_danmaku` (chats and
/// gifts in arrival order) plus change notifications.
final class ChatLog {
  new({int capacity = 500}) : _history = DanmakuHistory(capacity: capacity);

  final DanmakuHistory _history;
  final List<void Function(ChatLogChange change)> _listeners = [];

  /// Lines, oldest first.
  Iterable<DanmakuEvent> get lines => _history.lines;

  /// Number of lines.
  int get length => _history.length;

  /// The line at [index] (0 is the oldest).
  DanmakuEvent operator [](int index) => _history[index];

  /// Calls [listener] after every change.
  void addListener(void Function(ChatLogChange change) listener) => _listeners.add(listener);

  /// Stops calling [listener].
  void removeListener(void Function(ChatLogChange change) listener) => _listeners.remove(listener);

  void _notify(ChatLogChange change) {
    for (final listener in [..._listeners]) {
      listener(change);
    }
  }

  /// Appends [lines].
  void addAll(List<DanmakuEvent> lines) {
    if (lines.isEmpty) return;
    final change = _history.addAll(lines);
    _notify(ChatLogChange(appended: change.appended, trimmed: change.trimmed));
  }

  /// Appends the user's own local [line] (F-LI-01).
  void addLocal(DanmakuEvent line) {
    final change = _history.addAll([line]);
    _notify(ChatLogChange(appended: change.appended, trimmed: change.trimmed, local: true));
  }

  /// Removes the lines [test] matches, keeping the others in order.
  void removeWhere(bool Function(DanmakuEvent line) test) {
    final change = _history.removeWhere(test);
    if (change.removed > 0) _notify(ChatLogChange(removed: test));
  }

  /// Empties the list.
  void clear() {
    _history.clear();
    _notify(const ChatLogChange(cleared: true));
  }
}

/// Where the chat connection is, for the status line of the chat panel.
enum ChatConnection {
  /// Danmaku is off or the room is not live: no connection (F-DM-01).
  off,

  /// Opening the connection.
  connecting,

  /// Joined.
  connected,

  /// Lost it, retrying.
  reconnecting,

  /// Gave up; a manual reconnect starts over (CONN-3).
  closed,

  /// The platform has no chat.
  unsupported,
}

/// The chat of one open room (spec/modules/danmaku.md §6): the connection
/// (following the display switch, F-DM-01), the chat list, pinned super chats,
/// audience figures and the feed of the on-video layer. The room page owns
/// it; a room change makes a new one (CONN-4 clears the list and caches).
final class RoomDanmaku {
  new({
    required this._source,
    required this.room,
    required DanmakuFilterSettings filters,
    required bool enabled,
    this._overlay,
    this._overlayVisible = true,
    DateTime Function()? now,
  }) : _filters = filters,
       _blocks = DanmakuBlockList(users: filters.blockedUsers, words: filters.blockedWords),
       _now = now ?? DateTime.now {
    // REN-7: frozen until playback reports playing.
    _overlay?.pause(pausedForVideo);
    if (enabled) unawaited(_connect());
  }

  final DanmakuSource _source;

  /// The room.
  final RoomDetail room;

  final DateTime Function() _now;
  final SuperChatBoard _board = SuperChatBoard();
  final NoticeThrottle _throttle = NoticeThrottle();

  /// Chats and gifts, oldest first (LST-1).
  final ChatLog chat = ChatLog();

  /// Pinned super chats, earliest end first (LST-5).
  final ValueNotifier<List<DanmakuSuperChat>> superChats = ValueNotifier(const []);

  /// Latest figure per kind (LST-6); a separate listenable so a figure
  /// update rebuilds only the label that shows it.
  final ValueNotifier<Map<AudienceKind, int>> audience = ValueNotifier(const {});

  /// Connection state.
  final ValueNotifier<ChatConnection> connection = ValueNotifier(ChatConnection.off);

  /// The latest notice worth showing (LST-7: once per status in 3 s).
  final ValueNotifier<DanmakuSystem?> notice = ValueNotifier(null);

  DanmakuFilterSettings _filters;
  DanmakuBlockList _blocks;
  OnVideoDanmaku? _overlay;
  bool _overlayVisible;
  var _playing = false;
  DanmakuFeed? _feed;
  StreamSubscription<DanmakuBatch>? _subscription;
  var _generation = 0;
  Timer? _expiry;
  var _disposed = false;

  /// The filter settings in force.
  DanmakuFilterSettings get filters => _filters;

  /// Whether a connection is open or opening.
  bool get isConnected => connection.value != ChatConnection.off;

  DanmakuScreenBudget get _budget =>
      _overlayVisible && _overlay != null ? DanmakuScreenBudget.room : DanmakuScreenBudget.none;

  /// Connects or disconnects (F-DM-01, CONN-6). Disconnecting keeps the list.
  void setEnabled({required bool enabled}) {
    if (_disposed || enabled == isConnected) return;
    if (enabled) {
      unawaited(_connect());
    } else {
      unawaited(_disconnect());
    }
  }

  /// Starts over after the connection gave up (CONN-3: a manual refresh
  /// connects again); keeps the list.
  Future<void> reconnect() async {
    if (_disposed) return;
    await _disconnect();
    if (!_disposed) await _connect();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    connection.value = ChatConnection.connecting;
    final DanmakuFeed feed;
    try {
      feed = await _source.open(room, settings: _filters, budget: _budget);
    } on Object {
      if (generation == _generation && !_disposed) connection.value = ChatConnection.closed;
      return;
    }
    // A later disconnect, reconnect or dispose made this one stale (INV-ROOM-11).
    if (generation != _generation || _disposed) {
      unawaited(feed.close());
      return;
    }
    _feed = feed;
    _subscription = feed.batches.listen(
      (batch) {
        if (generation == _generation && !_disposed) _receive(batch);
      },
      onDone: () {
        if (generation == _generation && !_disposed && connection.value != ChatConnection.unsupported) {
          connection.value = ChatConnection.closed;
        }
      },
    );
  }

  Future<void> _disconnect() async {
    _generation++;
    final feed = _feed;
    _feed = null;
    if (!_disposed) connection.value = ChatConnection.off;
    _overlay?.clear();
    // Close first: the worker stops the connection even if the cancel below
    // takes its time.
    final closing = feed?.close();
    final cancelled = _subscription?.cancel();
    _subscription = null;
    await cancelled;
    await closing;
  }

  void _receive(DanmakuBatch batch) {
    final lines = <DanmakuEvent>[...batch.list, ...batch.gifts];
    if (batch.gifts.isNotEmpty && batch.list.isNotEmpty) {
      lines.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    }
    chat.addAll(lines);
    _feedOverlay(batch.screen);
    final now = _now();
    if (batch.superChats.isNotEmpty && _board.addAll(batch.superChats, now)) {
      superChats.value = _board.items;
      _scheduleExpiry(now);
    }
    if (batch.online.isNotEmpty) audience.value = {...audience.value, ...batch.online};
    for (final system in batch.system) {
      _onSystem(system, now);
    }
  }

  void _onSystem(DanmakuSystem system, DateTime now) {
    final state = switch (system.status) {
      DanmakuStatus.connecting => ChatConnection.connecting,
      DanmakuStatus.connected => ChatConnection.connected,
      DanmakuStatus.reconnecting => ChatConnection.reconnecting,
      DanmakuStatus.closed || DanmakuStatus.timeout => ChatConnection.closed,
      DanmakuStatus.unsupported => ChatConnection.unsupported,
      DanmakuStatus.replayMode || DanmakuStatus.bilibiliGuestMasked => null,
    };
    if (state != null) connection.value = state;
    // Connection progress shows in the status line; notices are for the rest.
    if (system.status == DanmakuStatus.connecting || system.status == DanmakuStatus.connected) return;
    if (_throttle.accepts(system, now)) notice.value = system;
  }

  /// REN-7: the layer gets chat only while playing; local lines always.
  void _feedOverlay(List<DanmakuChat> screen) {
    final overlay = _overlay;
    if (overlay == null || !_overlayVisible || screen.isEmpty) return;
    final shown = _playing
        ? screen
        : [
            for (final line in screen)
              if (line.isLocal) line,
          ];
    if (shown.isNotEmpty) overlay.addAll(shown.map(onVideoItem));
  }

  void _scheduleExpiry(DateTime now) {
    _expiry?.cancel();
    final next = _board.nextExpiry;
    if (next == null) return;
    final wait = next.difference(now);
    _expiry = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 1), () {
      if (_disposed) return;
      final at = _now();
      if (_board.expire(at)) superChats.value = _board.items;
      _scheduleExpiry(at);
    });
  }

  /// Whether the picture is playing (REN-7). The layer freezes while not.
  void setPlaying({required bool playing}) {
    if (playing == _playing) return;
    _playing = playing;
    final overlay = _overlay;
    if (overlay == null) return;
    if (playing) {
      overlay.resume(pausedForVideo);
    } else {
      overlay.pause(pausedForVideo);
    }
  }

  /// The on-video layer, if attached.
  OnVideoDanmaku? get overlay => _overlay;

  /// Attaches the on-video layer (null detaches it).
  set overlay(OnVideoDanmaku? value) {
    if (identical(value, _overlay)) return;
    _overlay?.clear();
    _overlay = value;
    if (value != null) {
      if (_playing) {
        value.resume(pausedForVideo);
      } else {
        value.pause(pausedForVideo);
      }
    }
    _feed?.update(budget: _budget);
  }

  /// Shows or hides danmaku on the video; the list keeps receiving, and the
  /// worker stops sampling screen candidates while hidden (SMP-3).
  void setOverlayVisible({required bool visible}) {
    if (visible == _overlayVisible) return;
    _overlayVisible = visible;
    if (!visible) _overlay?.clear();
    _feed?.update(budget: _budget);
  }

  /// FLT-6: new filters apply to the next message; lines the new block list
  /// matches leave the list (FLT-2, LST-3).
  void setFilters(DanmakuFilterSettings filters) {
    final previous = _filters;
    _filters = filters;
    _feed?.update(settings: filters);
    if (listEquals(previous.blockedUsers, filters.blockedUsers) &&
        listEquals(previous.blockedWords, filters.blockedWords)) {
      return;
    }
    _blocks = DanmakuBlockList(users: filters.blockedUsers, words: filters.blockedWords);
    if (!_blocks.isEmpty) {
      chat.removeWhere(_blocks.matches);
      _overlay?.removeWhere(_blocks.matches);
    }
  }

  /// Blocks [value] now, before the store confirms it: the list drops the
  /// matching lines and the worker filters from the next message.
  void block(BlockKind kind, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final folded = DanmakuBlockList.normalize(trimmed);
    final users = _filters.blockedUsers;
    final words = _filters.blockedWords;
    bool known(List<String> list) => list.any((item) => DanmakuBlockList.normalize(item) == folded);
    if (kind == BlockKind.user && !known(users)) {
      setFilters(_filters.copyWith(blockedUsers: [...users, trimmed]));
    } else if (kind == BlockKind.keyword && !known(words)) {
      setFilters(_filters.copyWith(blockedWords: [...words, trimmed]));
    }
  }

  /// Longest local line (F-LI-01).
  static const localMaxLength = 100;

  /// F-LI-01: shows [text] as the user's own line, in the list and on the
  /// video, on this device only; nothing is sent to the platform and no
  /// filter applies (local lines are never filtered or sampled). False when
  /// there is nothing to show.
  bool sendLocal(String text, {String? userName}) {
    final value = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_disposed || value.isEmpty) return false;
    final line = DanmakuChat(
      room: room.ref.key,
      session: 0,
      receivedAt: _now().microsecondsSinceEpoch,
      userName: userName ?? t.danmaku.localSender,
      text: String.fromCharCodes(value.runes.take(localMaxLength)),
      isLocal: true,
    );
    chat.addLocal(line);
    _feedOverlay([line]);
    return true;
  }

  /// Whether [line] is blocked by the filters in force.
  bool isBlocked(DanmakuEvent line) => _blocks.matches(line);

  /// Closes the connection and stops the timers.
  Future<void> dispose() async {
    if (_disposed) return;
    await _disconnect();
    _disposed = true;
    _expiry?.cancel();
    _overlay?.clear();
    superChats.dispose();
    audience.dispose();
    connection.dispose();
    notice.dispose();
  }
}

/// The figure a room header shows: concurrent viewers where the platform
/// sends them, else its heat score (Bilibili, Huya), else viewers so far.
(AudienceKind, int)? headlineAudience(Map<AudienceKind, int> figures) {
  for (final kind in const [AudienceKind.online, AudienceKind.popularity, AudienceKind.cumulative]) {
    final value = figures[kind];
    if (value != null) return (kind, math.max(0, value));
  }
  return null;
}
