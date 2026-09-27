import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:live_danmaku/src/runtime/exact_websocket.dart';
import 'package:live_net/live_net.dart';

/// Time for the connectors and the pipeline; injectable for tests.
abstract interface class DanmakuClock {
  /// Wall-clock time, compared with platform timestamps.
  DateTime now();

  /// Monotonic microseconds for `DanmakuEvent.receivedAt`.
  int micros();
}

/// The process clocks: `DateTime.now` and `Timeline.now` (monotonic and
/// shared by every isolate of the process).
final class SystemDanmakuClock implements DanmakuClock {
  /// Creates the clock.
  const new();

  @override
  DateTime now() => DateTime.now();

  @override
  int micros() => Timeline.now;
}

/// A frame to send as a WebSocket text frame (socket.io, IRC-style
/// protocols); its bytes are the UTF-8 of [text], so recorders and test
/// doubles that only see `List<int>` keep working.
final class TextFrame extends UnmodifiableListView<int> {
  /// Wraps [text].
  new(this.text) : super(utf8.encode(text));

  /// The frame text.
  final String text;
}

/// One open WebSocket.
abstract interface class DanmakuSocket {
  /// Received messages: `List<int>` for binary frames, `String` for text.
  Stream<Object?> get messages;

  /// Sends a binary frame, or a text frame for a [TextFrame]; ignored after
  /// the socket closed.
  void send(List<int> frame);

  /// Sends a text frame (Twitch IRC); ignored after the socket closed.
  void sendText(String text);

  /// Closes the socket.
  Future<void> close();

  /// Close code once closed, when the peer sent one.
  int? get closeCode;
}

/// How connectors reach the network: WebSockets and plain HTTP.
abstract interface class DanmakuTransport {
  /// HTTP for polling and snapshots.
  LiveHttp get http;

  /// Opens a WebSocket to [url] for [site]'s chat within [timeout],
  /// offering [protocols]. [exactHeaders] sends the handshake exactly as
  /// written ([ExactWebSocket]), for edges that refuse `dart:io`'s
  /// lower-cased upgrade headers.
  Future<DanmakuSocket> connect(
    Uri url, {
    required String site,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    List<String> protocols = const [],
    bool exactHeaders = false,
  });
}

/// [DanmakuTransport] on `dart:io`: each WebSocket goes through the
/// platform's [ProxyPolicy] route (the app's proxy setting), like
/// [IoLiveHttp] does for HTTP.
final class IoDanmakuTransport implements DanmakuTransport {
  /// Creates the transport; [http] defaults to an [IoLiveHttp] on the same
  /// [proxy].
  new({this.proxy = const FixedProxyPolicy(), LiveHttp? http}) : http = http ?? IoLiveHttp(proxy: proxy);

  /// Route per platform.
  final ProxyPolicy proxy;

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
    final route = proxy.routeFor(site, url);
    if (exactHeaders) {
      return await ExactWebSocket.connect(url, route: route, headers: headers, protocols: protocols, timeout: timeout);
    }
    // The client only carries the upgrade handshake; closing it with force
    // aborts a handshake that outlived [timeout].
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => route.directive;
    final connecting = WebSocket.connect(
      url.toString(),
      headers: headers,
      protocols: protocols.isEmpty ? null : protocols,
      customClient: client,
    );
    try {
      final socket = await connecting.timeout(timeout);
      // The upgraded socket is detached from the client.
      client.close();
      return _IoSocket(socket);
    } on Object {
      client.close(force: true);
      // A handshake finishing after the timeout must not leak its socket.
      unawaited(connecting.then((late) => late.close(), onError: (Object _) {}));
      rethrow;
    }
  }
}

final class _IoSocket implements DanmakuSocket {
  new(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  void send(List<int> frame) {
    if (_socket.readyState != WebSocket.open) return;
    _socket.add(frame is TextFrame ? frame.text : frame);
  }

  @override
  void sendText(String text) {
    if (_socket.readyState == WebSocket.open) _socket.add(text);
  }

  @override
  Future<void> close() async {
    await _socket.close(WebSocketStatus.normalClosure);
  }

  @override
  int? get closeCode => _socket.closeCode;
}
