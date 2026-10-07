import 'dart:async';

import 'package:live_cli/src/patrol/checks.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// Joins [args]' room on [connection] for [duration] (read only, nothing is
/// sent) and counts what arrived; the connection is closed afterwards.
Future<DanmakuSample> sampleDanmaku(DanmakuConnection connection, Object? args, Duration duration) async {
  final watch = Stopwatch()..start();
  Duration? ready;
  var chats = 0;
  var online = 0;
  var reconnects = 0;
  String? closed;
  String? error;
  final ended = Completer<void>();
  final subscription = connection.events.listen((event) {
    switch (event) {
      case DanmakuReady():
        ready ??= watch.elapsed;
      case DanmakuReceived(:final message) when message.type == LiveMessageType.chat:
        chats++;
      case DanmakuReceived(:final message) when message.type == LiveMessageType.online:
        online++;
      case DanmakuReceived():
        break;
      case DanmakuReconnecting():
        reconnects++;
      case DanmakuClosed(:final reason):
        closed = reason.name;
        if (!ended.isCompleted) ended.complete();
    }
  });
  try {
    await connection.connect(args).timeout(duration);
    final left = duration - watch.elapsed;
    if (left > Duration.zero && !ended.isCompleted) {
      await Future.any([ended.future, Future<void>.delayed(left)]);
    }
  } on TimeoutException {
    error = '连接超过 ${duration.inSeconds} 秒';
  } on Object catch (failure) {
    error = describeError(failure);
  } finally {
    await subscription.cancel();
    await connection.close();
  }
  return DanmakuSample(
    ready: ready,
    chats: chats,
    online: online,
    reconnects: reconnects,
    closed: closed,
    error: error,
  );
}
