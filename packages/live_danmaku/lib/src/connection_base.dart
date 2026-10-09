import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:meta/meta.dart';

/// The lifecycle every platform connection shares (what each 3.x
/// `LiveDanmaku` wrote by hand with `_generation`, `_stopped` and nulled
/// callbacks).
///
/// Each [connect] is one [DanmakuRun]. A run reports through its methods
/// and goes silent for good once [close] or another [connect] begins, or
/// once it reported [DanmakuClosed]; so does every timer or request that
/// outlives it. A platform implements [start] (open the transport, join)
/// and [stop] (release it); [A] is its `*DanmakuArgs` type.
abstract base class DanmakuConnectionBase<A extends Object> implements DanmakuConnection {
  /// Creates the connection; [heartbeatInterval] is informational (3.x
  /// `heartbeatTime`).
  new({this.heartbeatInterval = Duration.zero});

  @override
  final Duration heartbeatInterval;

  final StreamController<DanmakuEvent> _events = StreamController.broadcast(sync: true);
  DanmakuStatus _status = DanmakuStatus.idle;
  DanmakuRun? _run;
  int _generation = 0;

  @override
  Stream<DanmakuEvent> get events => _events.stream;

  @override
  DanmakuStatus get status => _status;

  @override
  bool get isConnected => _status == DanmakuStatus.connected;

  /// Opens the transport for [args] and joins, reporting through [run].
  /// Completes once the first attempt has finished. Throw
  /// [DanmakuStartFailure] for a known reason not to proceed.
  @protected
  Future<void> start(A args, DanmakuRun run);

  /// Releases the transport of the current run (sockets, timers, requests).
  /// Called before every [start], by [close] and after [DanmakuClosed]; it
  /// must be safe to call when nothing is open.
  @protected
  Future<void> stop() async {}

  @override
  void heartbeat() {}

  @override
  Future<void> connect(Object? args) async {
    if (args is! A) throw ArgumentError.value(args, 'args', 'Expected $A');
    final run = _begin();
    _status = DanmakuStatus.connecting;
    await stop();
    if (!run.isActive) return;
    try {
      await start(args, run);
    } on DanmakuStartFailure catch (failure) {
      run.closed(failure.reason, detail: failure.detail);
    } on Object {
      // A run that was stopped meanwhile has nothing to report.
      if (!run.isActive) return;
      _finish();
      _status = DanmakuStatus.idle;
      await stop();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _finish();
    _status = DanmakuStatus.idle;
    await stop();
  }

  DanmakuRun _begin() {
    _finish();
    return _run = DanmakuRun._(this, _generation);
  }

  void _finish() {
    _generation++;
    final run = _run;
    _run = null;
    if (run != null && !run._ended.isCompleted) run._ended.complete();
  }
}

/// One [DanmakuConnection.connect] of a [DanmakuConnectionBase]: what the
/// platform code reports through. Every method does nothing once the run
/// is over ([isActive] is false).
final class DanmakuRun {
  new _(this._owner, this._generation);

  final DanmakuConnectionBase<Object> _owner;
  final int _generation;
  final Completer<void> _ended = Completer();

  /// Whether this run is still the connection's current one.
  bool get isActive => _owner._generation == _generation && !_ended.isCompleted;

  /// Completes when the run is over: stopped, replaced or closed.
  Future<void> get ended => _ended.future;

  /// Whether the connection counts as joined now.
  bool get isConnected => isActive && _owner.isConnected;

  /// The room is joined: reports [DanmakuReady].
  void ready() {
    if (!isActive) return;
    _owner._status = DanmakuStatus.connected;
    _owner._events.add(const DanmakuReady());
  }

  /// Reports a message, its text and names without invisible placeholder
  /// characters ([cleanDanmakuText]).
  void message(LiveMessage message) {
    if (isActive) _owner._events.add(DanmakuReceived(cleanDanmakuText(message)));
  }

  /// Reports a transient interruption ([DanmakuReconnecting]).
  void reconnecting(DanmakuInterruption reason, {String detail = ''}) {
    if (!isActive) return;
    _owner._status = DanmakuStatus.reconnecting;
    _owner._events.add(DanmakuReconnecting(reason, detail: detail));
  }

  /// No longer joined, without a notice (3.x `markDisconnected` while a join
  /// is being renegotiated).
  void markDisconnected() {
    if (isActive && _owner._status == DanmakuStatus.connected) _owner._status = DanmakuStatus.connecting;
  }

  /// Ends the run for good: reports [DanmakuClosed] and releases the
  /// transport.
  void closed(DanmakuCloseReason reason, {String detail = ''}) {
    if (!isActive) return;
    final owner = _owner.._status = DanmakuStatus.closed;
    owner._events.add(DanmakuClosed(reason, detail: detail));
    if (!isActive) return;
    owner._finish();
    unawaited(owner.stop());
  }

  /// Waits [duration] unless the run ends first; true when it is still
  /// active (3.x's delays between steps, which ignored `stop`).
  Future<bool> delay(Duration duration) async {
    if (!isActive) return false;
    final elapsed = Completer<void>();
    final timer = Timer(duration, elapsed.complete);
    await Future.any([elapsed.future, _ended.future]);
    timer.cancel();
    return isActive;
  }
}

/// [message] with its text, sender name and fan badge name, and those of
/// its super chat, without invisible placeholder characters (live_core's
/// [stripInvisiblePlaceholders]: U+FFFC and the like, which fonts draw as a
/// box); the same message when it has none. Every platform's messages pass
/// through it in [DanmakuRun.message].
LiveMessage cleanDanmakuText(LiveMessage message) {
  final text = stripInvisiblePlaceholders(message.message);
  final name = stripInvisiblePlaceholders(message.userName);
  final badge = stripInvisiblePlaceholders(message.fansName);
  final data = switch (message.data) {
    final LiveSuperChatMessage chat => _cleanSuperChat(chat),
    final other => other,
  };
  if (identical(text, message.message) &&
      identical(name, message.userName) &&
      identical(badge, message.fansName) &&
      identical(data, message.data)) {
    return message;
  }
  return LiveMessage(
    type: message.type,
    userName: name,
    message: text,
    color: message.color,
    userId: message.userId,
    data: data,
    userLevel: message.userLevel,
    fansLevel: message.fansLevel,
    fansName: badge,
    isLocal: message.isLocal,
    messageId: message.messageId,
    sentAt: message.sentAt,
    style: message.style,
    replayed: message.replayed,
    emotes: message.emotes,
    sourceRoomId: message.sourceRoomId,
    nameColor: message.nameColor,
    badges: message.badges,
  );
}

LiveSuperChatMessage _cleanSuperChat(LiveSuperChatMessage chat) {
  final text = stripInvisiblePlaceholders(chat.message);
  final name = stripInvisiblePlaceholders(chat.userName);
  if (identical(text, chat.message) && identical(name, chat.userName)) return chat;
  return LiveSuperChatMessage(
    userName: name,
    face: chat.face,
    message: text,
    price: chat.price,
    startTime: chat.startTime,
    endTime: chat.endTime,
    backgroundColor: chat.backgroundColor,
    backgroundBottomColor: chat.backgroundBottomColor,
    messageId: chat.messageId,
    priceText: chat.priceText,
    unit: chat.unit,
    image: chat.image,
  );
}
