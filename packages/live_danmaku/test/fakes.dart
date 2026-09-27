import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';

/// A clock driven by [FakeAsync].
final class FakeClock implements DanmakuClock {
  /// Follows [async], starting at [start].
  new(this.async, this.start);

  /// The fake time source.
  final FakeAsync async;

  /// Wall time at elapsed zero.
  final DateTime start;

  @override
  DateTime now() => start.add(async.elapsed);

  @override
  int micros() => async.elapsed.inMicroseconds;
}

/// A socket the test drives: [receive] feeds frames, [drop] closes it from
/// the server side; [sent] collects what the connector sent.
final class FakeSocket implements DanmakuSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();

  /// Frames the connector sent (text frames as their UTF-8 bytes).
  final List<List<int>> sent = [];

  /// Text frames the connector sent.
  final List<String> sentText = [];

  /// Whether the connector closed the socket.
  bool closed = false;

  @override
  Stream<Object?> get messages => _incoming.stream;

  /// Delivers [data] as a received message.
  void receive(Object data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// Ends the stream as a server-side close would.
  void drop() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  void send(List<int> frame) {
    if (!closed) sent.add(frame);
  }

  @override
  void sendText(String text) {
    if (closed) return;
    sentText.add(text);
    sent.add(utf8.encode(text));
  }

  @override
  Future<void> close() async {
    closed = true;
    drop();
  }

  @override
  int? get closeCode => null;
}

/// A transport whose handshakes the test answers: each connect takes the
/// next result of [plan] (a socket, or null for a refused handshake).
final class FakeTransport implements DanmakuTransport {
  /// Creates the transport.
  new({List<FakeSocket?>? plan, LiveHttp? http}) : plan = plan ?? [], http = http ?? FakeHttp();

  /// Handshake results in order; empty means refuse.
  final List<FakeSocket?> plan;

  /// URLs connected to, in order.
  final List<Uri> urls = [];

  /// Headers of each handshake.
  final List<Map<String, String>> headers = [];

  /// Subprotocols and exact-header flag of each handshake.
  final List<({List<String> protocols, bool exactHeaders})> options = [];

  @override
  final LiveHttp http;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    required String site,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    List<String> protocols = const [],
    bool exactHeaders = false,
  }) async {
    urls.add(url);
    this.headers.add(headers);
    options.add((protocols: protocols, exactHeaders: exactHeaders));
    final socket = plan.isEmpty ? null : plan.removeAt(0);
    if (socket == null) throw const SocketLikeFailure();
    return socket;
  }
}

/// The failure a refused handshake raises.
final class SocketLikeFailure implements Exception {
  /// Creates the failure.
  const new();
}

/// HTTP answered by [handler]; unanswered requests fail.
final class FakeHttp implements LiveHttp {
  /// Creates the fake.
  new([this.handler]);

  /// Answers a request.
  final Future<LiveResponse> Function(LiveRequest request)? handler;

  /// Requests seen.
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final answer = handler;
    if (answer == null) throw TransportFailure(request.site, TransportReason.connect);
    return await answer(request);
  }

  @override
  void close() {}
}
