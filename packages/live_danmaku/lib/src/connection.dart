import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// What a [DanmakuConnection] is doing.
enum DanmakuStatus {
  /// Not started, or stopped by [DanmakuConnection.close].
  idle,

  /// [DanmakuConnection.connect] was called and the room is not joined yet.
  connecting,

  /// Joined; messages flow (3.x `isConnected`).
  connected,

  /// Interrupted and recovering by itself (after [DanmakuReconnecting]).
  reconnecting,

  /// Recovery ended (after [DanmakuClosed]); `connect` starts over.
  closed,
}

/// Why a connection is recovering ([DanmakuReconnecting]); the UI turns it
/// into text (3.x passed Chinese text from the protocol code).
enum DanmakuInterruption {
  /// The socket failed or went silent (3.x "与服务器断开连接，正在尝试重连").
  disconnected,

  /// The platform did not confirm the join in time (3.x YY "YY 弹幕协议握手超时").
  handshakeTimeout,

  /// The platform answered with a protocol failure (3.x YY: the failure
  /// text, then "正在尝试重连").
  protocolError,
}

/// Why a connection ended ([DanmakuClosed]); the UI turns it into text.
enum DanmakuCloseReason {
  /// Every reconnect failed (3.x "服务器连接失败重连超过最大次数，与服务器断开连接：…").
  reconnectsExhausted,

  /// The connection could not start (3.x SOOP without chat data: "服务器连接失败").
  connectionFailed,

  /// The platform's credentials could not be fetched (3.x Bilibili
  /// "弹幕连接信息仍在更新，请稍后刷新房间").
  credentialsUnavailable,
}

/// Something a [DanmakuConnection] reports, in order, on
/// [DanmakuConnection.events].
@immutable
sealed class DanmakuEvent {
  const new();
}

/// The room is joined (3.x `onReady`); comes again after every reconnect.
final class DanmakuReady extends DanmakuEvent {
  /// Creates the event.
  const new();

  @override
  bool operator ==(Object other) => other is DanmakuReady;

  @override
  int get hashCode => (DanmakuReady).hashCode;

  @override
  String toString() => 'DanmakuReady()';
}

/// A message arrived (3.x `onMessage`): chat, super chat or an audience
/// figure.
final class DanmakuReceived extends DanmakuEvent {
  /// Creates the event.
  const new(this.message);

  /// The message.
  final LiveMessage message;

  @override
  String toString() => 'DanmakuReceived(${message.type.name}: ${message.message})';
}

/// A transient interruption; the connection is recovering by itself (3.x
/// `onReconnect`). Messages and [DanmakuReady] follow once it recovers.
final class DanmakuReconnecting extends DanmakuEvent {
  /// Creates the event.
  const new(this.reason, {this.detail = ''});

  /// Why.
  final DanmakuInterruption reason;

  /// Diagnostic detail (a socket failure, a protocol message), or empty.
  final String detail;

  @override
  bool operator ==(Object other) => other is DanmakuReconnecting && other.reason == reason && other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'DanmakuReconnecting(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// Recovery ended for good (3.x `onClose`): nothing follows until the next
/// [DanmakuConnection.connect].
final class DanmakuClosed extends DanmakuEvent {
  /// Creates the event.
  const new(this.reason, {this.detail = ''});

  /// Why.
  final DanmakuCloseReason reason;

  /// Diagnostic detail (the last socket failure), or empty.
  final String detail;

  @override
  bool operator ==(Object other) => other is DanmakuClosed && other.reason == reason && other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'DanmakuClosed(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// One platform's danmaku connection to one room at a time (3.x
/// `LiveDanmaku`).
///
/// The room page subscribes to [events] once, calls [connect] with the
/// room's `LiveRoom.danmakuData` and [close] when it leaves. A connection
/// can be connected again after [close] or after [DanmakuClosed]; a
/// [connect] while connected replaces the previous room.
///
/// Events are delivered synchronously, in order, and never after [close]
/// was called or another [connect] began.
abstract interface class DanmakuConnection {
  /// What happens, in order (a broadcast stream).
  Stream<DanmakuEvent> get events;

  /// Current state.
  DanmakuStatus get status;

  /// Whether the room is joined (3.x `isConnected`).
  bool get isConnected;

  /// Heartbeat period of the platform; zero when it has none (3.x
  /// `heartbeatTime`).
  Duration get heartbeatInterval;

  /// Connects to the room described by [args] (the platform's
  /// `*DanmakuArgs`), after stopping any previous room (3.x `start`).
  ///
  /// Completes once the first attempt has finished, joined or not: later
  /// attempts are reported on [events]. Throws [ArgumentError] when [args]
  /// is not the platform's type, and whatever the platform throws before
  /// its first attempt; a start that cannot proceed for a known reason ends
  /// with [DanmakuClosed] instead.
  Future<void> connect(Object? args);

  /// Sends the platform's heartbeat now (3.x `heartbeat`); the connection
  /// also sends it every [heartbeatInterval]. Does nothing when there is no
  /// socket or no heartbeat.
  void heartbeat();

  /// Stops: no event follows, sockets and timers are released (3.x
  /// `stop`). Calling it again, or before [connect], does nothing.
  Future<void> close();
}

/// Thrown by a platform while starting when the room cannot be joined for a
/// known reason; the connection reports it as [DanmakuClosed] and
/// [DanmakuConnection.connect] completes normally (3.x called `onClose` and
/// returned).
final class DanmakuStartFailure implements Exception {
  /// Creates the failure.
  const new(this.reason, {this.detail = ''});

  /// Why.
  final DanmakuCloseReason reason;

  /// Diagnostic detail, without cookies or tokens.
  final String detail;

  @override
  String toString() => 'DanmakuStartFailure(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}
