import 'dart:async';

import 'package:live_core/src/live_message.dart';
import 'package:meta/meta.dart';

/// A platform's danmaku connection (3.x's `LiveDanmaku`). The room page sets
/// the callbacks, calls [start] with the room's danmaku data and [stop] when
/// it leaves.
abstract class LiveDanmaku {
  /// A message arrived.
  void Function(LiveMessage message)? onMessage;

  /// A transient interruption; the connection is recovering by itself.
  void Function(String reason)? onReconnect;

  /// A terminal failure after automatic recovery ended.
  void Function(String reason)? onClose;

  /// Connected and joined.
  void Function()? onReady;

  /// Heartbeat interval in milliseconds; 0 for none.
  int heartbeatTime = 0;

  bool _connected = false;

  /// Whether the connection is up.
  bool get isConnected => _connected;

  /// Marks the connection up.
  @protected
  void markConnected() => _connected = true;

  /// Marks the connection down.
  @protected
  void markDisconnected() => _connected = false;

  /// Sends the platform's heartbeat.
  void heartbeat() {}

  /// Connects with the room's danmaku data (`LiveRoom.danmakuData`).
  Future<void> start(Object? args) async {}

  /// Disconnects.
  Future<void> stop() async => markDisconnected();
}

/// The danmaku of a platform without danmaku: never connects, and drops its
/// callbacks on [stop].
final class EmptyDanmaku extends LiveDanmaku {
  /// Creates it.
  new() {
    heartbeatTime = 60 * 1000;
  }

  @override
  Future<void> stop() async {
    markDisconnected();
    onMessage = null;
    onReconnect = null;
    onClose = null;
    onReady = null;
  }
}
