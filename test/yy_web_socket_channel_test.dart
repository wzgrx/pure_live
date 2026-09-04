import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/utils/yy/yy_web_socket_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('YY handshake preserves the two header names rejected in lowercase', () {
    final request = buildYyWebSocketHandshake(
      Uri.parse('wss://h5-sinchl.yy.com/websocket'),
      nonce: 'SGVsbG9Xb3JsZDEyMzQ1Ng==',
      headers: const <String, dynamic>{'Origin': 'https://www.yy.com'},
    );

    expect(request, contains('\r\nSec-WebSocket-Key: SGVsbG9Xb3JsZDEyMzQ1Ng==\r\n'));
    expect(request, contains('\r\nSec-WebSocket-Version: 13\r\n'));
    expect(request, isNot(contains('\r\nsec-websocket-key:')));
    expect(request, isNot(contains('\r\nsec-websocket-version:')));
  });

  test('case-sensitive connector keeps SOOP protocol and browser header spelling', () {
    final request = buildYyWebSocketHandshake(
      Uri.parse('wss://chat-dee9364c.sooplive.com:9001/Websocket/room'),
      nonce: 'SGVsbG9Xb3JsZDEyMzQ1Ng==',
      protocols: const <String>['chat'],
      headers: const <String, dynamic>{'Origin': 'https://play.sooplive.co.kr'},
    );

    expect(request, contains('\r\nOrigin: https://play.sooplive.co.kr\r\n'));
    expect(request, contains('\r\nSec-WebSocket-Protocol: chat\r\n'));
    expect(request, contains('\r\nSec-WebSocket-Key: SGVsbG9Xb3JsZDEyMzQ1Ng==\r\n'));
    expect(request, isNot(contains('\r\nsec-websocket-protocol:')));
  });

  test('YY channel completes a raw upgrade and emits a binary frame', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requestCompleter = Completer<String>();
    final serverDone = Completer<void>();
    server.listen((socket) {
      final bytes = BytesBuilder(copy: false);
      var upgraded = false;
      late StreamSubscription<List<int>> subscription;
      subscription = socket.listen((chunk) {
        if (upgraded) return;
        bytes.add(chunk);
        final request = latin1.decode(bytes.toBytes());
        final end = request.indexOf('\r\n\r\n');
        if (end < 0) return;
        upgraded = true;
        subscription.pause();
        final headers = request.substring(0, end + 4);
        requestCompleter.complete(headers);
        final nonce = RegExp(
          r'^Sec-WebSocket-Key:\s*(.+)\r?$',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(headers)!.group(1)!.trim();
        socket.add(
          latin1.encode(
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Connection: Upgrade\r\n'
            'Upgrade: websocket\r\n'
            'Sec-WebSocket-Accept: ${WebSocketChannel.signKey(nonce)}\r\n'
            '\r\n',
          ),
        );
        socket.add(const <int>[0x82, 0x03, 0x01, 0x02, 0x03]);
        unawaited(socket.flush());
        subscription.resume();
      }, onDone: () => serverDone.complete());
    });

    final channel = YyWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${server.port}/websocket'));
    await channel.ready.timeout(const Duration(seconds: 2));
    expect(await channel.stream.first.timeout(const Duration(seconds: 2)), orderedEquals(const <int>[1, 2, 3]));
    final request = await requestCompleter.future;
    expect(request, contains('\r\nSec-WebSocket-Key:'));
    expect(request, contains('\r\nSec-WebSocket-Version: 13\r\n'));

    await channel.sink.close();
    await serverDone.future.timeout(const Duration(seconds: 3));
    await server.close();
  });

  test('YY handshake rejects a mismatched accept value', () {
    expect(
      () => validateYyWebSocketHandshake(
        'HTTP/1.1 101 Switching Protocols\r\n'
        'Connection: Upgrade\r\n'
        'Upgrade: websocket\r\n'
        'Sec-WebSocket-Accept: wrong\r\n',
        nonce: 'SGVsbG9Xb3JsZDEyMzQ1Ng==',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
