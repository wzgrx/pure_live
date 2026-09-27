import 'dart:async';
import 'dart:io';

import 'package:live_net/live_net.dart';

/// A text WebSocket that an adapter holds while a stream grant is played
/// (niconico seats, FC2 control sockets); injectable for tests.
abstract interface class TextSocket {
  /// Received text messages; the stream ends when the socket closes.
  Stream<String> get messages;

  /// Sends one text message; ignored after close.
  void send(String text);

  /// Closes the socket.
  Future<void> close();
}

/// Opens a [TextSocket] to `url` with request `headers`.
typedef TextSocketConnect = Future<TextSocket> Function(Uri url, Map<String, String> headers);

/// [TextSocketConnect] on `dart:io` through [route] (the platform's proxy
/// route, so the socket takes the same path as the adapter's HTTP). A
/// [pingInterval] keeps idle sockets alive with WebSocket pings.
TextSocketConnect ioTextSocketConnect(ProxyRoute route, {Duration? pingInterval}) => (url, headers) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..findProxy = (_) => route.directive;
  try {
    final socket = await WebSocket.connect(
      url.toString(),
      headers: headers,
      customClient: client,
    ).timeout(const Duration(seconds: 15));
    client.close();
    socket.pingInterval = pingInterval;
    return _IoTextSocket(socket);
  } on Object {
    client.close(force: true);
    rethrow;
  }
};

final class _IoTextSocket implements TextSocket {
  new(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages => _socket.where((data) => data is String).cast<String>();

  @override
  void send(String text) {
    if (_socket.readyState == WebSocket.open) _socket.add(text);
  }

  @override
  Future<void> close() =>
      _socket.close(WebSocketStatus.normalClosure).timeout(const Duration(seconds: 2), onTimeout: () {});
}
