import 'dart:async';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/base.dart';
import 'package:live_danmaku/src/runtime/reconnect.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:meta/meta.dart';

/// Where and how to open the socket; produced by [SocketConnector.plan].
@immutable
final class SocketPlan {
  /// Creates a plan.
  const new({required this.endpoints, this.headers = const {}});

  /// Endpoints in the order to try.
  final List<Uri> endpoints;

  /// Handshake headers.
  final Map<String, String> headers;
}

enum _End { failed, closed, silent, authTimeout, rejected, stopped }

/// The WebSocket loop shared by Douyu, Huya, Bilibili and Douyin (CONN-3):
/// 10 s handshake limit, join, heartbeat, silence watchdog, reconnection
/// over the endpoints with [ReconnectPolicy], credential refresh after a
/// rejection. Platforms supply the plan, the frames and the decoder.
abstract base class SocketConnector extends ConnectorBase {
  /// Creates the loop.
  new({
    required super.detail,
    required super.transport,
    super.session,
    super.clock,
    this.policy = const ReconnectPolicy(),
    this.connectTimeout = const Duration(seconds: 10),
  });

  /// Reconnection policy.
  final ReconnectPolicy policy;

  /// Limit for one handshake.
  final Duration connectTimeout;

  /// Platform id for the proxy route.
  String get site => room.platform;

  /// Resolves endpoints, headers and credentials; [refresh] asks for new
  /// credentials after a rejection. Throws [DanmakuStartFailure] when the
  /// room cannot be joined.
  @protected
  Future<SocketPlan> plan({required bool refresh});

  /// Frames sent right after the socket opens.
  @protected
  List<List<int>> openFrames();

  /// Whether an open socket counts as joined; otherwise the decoder reports
  /// [FrameResult.joined] within [authTimeout].
  @protected
  bool get joinedOnOpen => true;

  /// Limit for the join reply when [joinedOnOpen] is false.
  @protected
  Duration get authTimeout => const Duration(seconds: 8);

  /// Heartbeat period.
  @protected
  Duration get heartbeatInterval;

  /// Whether a heartbeat goes out as soon as the room is joined.
  @protected
  bool get heartbeatOnJoin => true;

  /// One heartbeat frame.
  @protected
  List<int> heartbeat();

  /// Silence that counts as a dead connection: max(3 × heartbeat, 90 s).
  @protected
  Duration get silenceTimeout {
    final three = heartbeatInterval * 3;
    const floor = Duration(seconds: 90);
    return three > floor ? three : floor;
  }

  /// How many rejections one start tolerates before giving up.
  @protected
  int get maxRejections => 3;

  /// Decodes one received message (`List<int>` or `String`).
  @protected
  FrameResult decode(Object? data, DecodeContext context);

  /// Called once per joined socket, for snapshot requests.
  @protected
  void onJoined(int generation) {}

  @override
  @protected
  Future<void> run(int generation) async {
    status(generation, DanmakuStatus.connecting);
    SocketPlan current;
    try {
      current = await plan(refresh: false);
    } on DanmakuStartFailure catch (failure) {
      terminal(generation, failure.reason, failure.detail);
      return;
    }
    if (isStale(generation)) return;
    var failures = 0;
    var endpoint = 0;
    var rejections = 0;
    var reconnecting = false;
    while (!isStale(generation)) {
      final url = current.endpoints[endpoint % current.endpoints.length];
      final (end, received, wasJoined) = await _attempt(
        generation,
        current,
        url,
        onJoin: () {
          if (reconnecting) reconnecting = false;
        },
      );
      if (isStale(generation) || end == _End.stopped) return;
      if (received) failures = 0;
      if (end == _End.rejected) {
        rejections++;
        if (rejections > maxRejections) {
          terminal(generation, 'rejected');
          return;
        }
        try {
          current = await plan(refresh: true);
        } on DanmakuStartFailure catch (failure) {
          terminal(generation, failure.reason, failure.detail);
          return;
        }
        if (isStale(generation)) return;
      }
      failures++;
      if (!reconnecting && (wasJoined || failures == 1)) {
        reconnecting = true;
        status(generation, DanmakuStatus.reconnecting, [end.name]);
      }
      if (policy.exhausted(failures)) {
        terminal(generation, 'maxRetries', end.name);
        return;
      }
      endpoint++;
      if (!await pause(generation, policy.delay(failures, current.endpoints.length))) return;
    }
  }

  Future<(_End, bool, bool)> _attempt(
    int generation,
    SocketPlan plan,
    Uri url, {
    required void Function() onJoin,
  }) async {
    final _Handle socket;
    try {
      socket = _Handle(await transport.connect(url, site: site, headers: plan.headers, timeout: connectTimeout));
    } on Object {
      return (_End.failed, false, false);
    }
    if (isStale(generation)) {
      unawaited(socket.close());
      return (_End.stopped, false, false);
    }
    final done = Completer<_End>();
    void finish(_End end) {
      if (!done.isCompleted) done.complete(end);
    }

    var received = false;
    var isJoined = false;
    Timer? beat;
    Timer? auth;
    Timer? silence;
    void watch() {
      silence?.cancel();
      silence = Timer(silenceTimeout, () => finish(_End.silent));
    }

    void join() {
      if (isJoined || isStale(generation)) return;
      isJoined = true;
      auth?.cancel();
      onJoin();
      status(generation, DanmakuStatus.connected);
      joined(generation);
      if (heartbeatOnJoin) socket.send(heartbeat());
      beat = Timer.periodic(heartbeatInterval, (_) => socket.send(heartbeat()));
      onJoined(generation);
    }

    final subscription = socket.messages.listen(
      (data) {
        if (isStale(generation) || done.isCompleted) return;
        received = true;
        watch();
        FrameResult result;
        try {
          result = decode(data, context());
        } on Object {
          // One malformed frame must not end the connection.
          result = FrameResult.empty;
        }
        result.replies.forEach(socket.send);
        if (result.joined) join();
        for (final event in result.events) {
          emit(generation, event);
        }
        if (result.rejected) finish(_End.rejected);
      },
      onError: (Object _) => finish(_End.failed),
      onDone: () => finish(_End.closed),
      cancelOnError: true,
    );
    watch();
    openFrames().forEach(socket.send);
    if (joinedOnOpen) {
      join();
    } else {
      auth = Timer(authTimeout, () => finish(_End.authTimeout));
    }
    final end = await Future.any([done.future, stopped.then((_) => _End.stopped)]);
    beat?.cancel();
    auth?.cancel();
    silence?.cancel();
    // Cancelling takes effect at once; its future is not awaited (a socket
    // that never answers the cancel must not hold the loop).
    unawaited(subscription.cancel());
    await socket.close();
    return (end, received, isJoined);
  }
}

/// A socket whose close is bounded and idempotent.
final class _Handle {
  new(this._socket);

  final DanmakuSocket _socket;
  var _closed = false;

  Stream<Object?> get messages => _socket.messages;

  void send(List<int> frame) {
    if (_closed) return;
    try {
      _socket.send(frame);
    } on Object {
      // A socket failing mid-send reports through its stream.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Already gone.
    }
  }
}
