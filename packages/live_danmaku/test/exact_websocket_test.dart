import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

String _accept(String key) =>
    base64.encode(sha1.convert(ascii.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')).bytes);

/// A server frame (unmasked).
List<int> _frame(int opcode, List<int> payload, {bool fin = true}) => [
  (fin ? 0x80 : 0) | opcode,
  if (payload.length < 126) payload.length else ...[126, payload.length >> 8, payload.length & 0xff],
  ...payload,
];

/// Unmasks the client frames in [bytes] (after the handshake).
List<({int opcode, List<int> payload})> _clientFrames(List<int> bytes) {
  final frames = <({int opcode, List<int> payload})>[];
  var offset = 0;
  while (offset + 6 <= bytes.length) {
    final opcode = bytes[offset] & 0x0f;
    var length = bytes[offset + 1] & 0x7f;
    var header = 2;
    if (length == 126) {
      length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      header = 4;
    }
    final mask = bytes.sublist(offset + header, offset + header + 4);
    final start = offset + header + 4;
    if (start + length > bytes.length) break;
    frames.add((opcode: opcode, payload: [for (var i = 0; i < length; i++) bytes[start + i] ^ mask[i & 3]]));
    offset = start + length;
  }
  return frames;
}

/// A raw TCP server that answers one WebSocket handshake by hand, so the
/// test sees the request bytes exactly as sent.
final class _RawServer {
  new _(this._server);

  static Future<_RawServer> start() async => _RawServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final Completer<String> request = Completer<String>();
  final BytesBuilder received = BytesBuilder();
  Socket? client;

  int get port => _server.port;

  void serve({String? protocol, List<List<int>> afterHandshake = const []}) {
    _server.listen((socket) {
      client = socket;
      final head = BytesBuilder();
      var upgraded = false;
      socket.listen((data) {
        if (upgraded) {
          received.add(data);
          return;
        }
        head.add(data);
        final text = latin1.decode(head.toBytes());
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        upgraded = true;
        request.complete(text.substring(0, end));
        final key = RegExp(r'Sec-WebSocket-Key: (\S+)').firstMatch(text)!.group(1)!;
        socket.add(
          latin1.encode(
            'HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nConnection: Upgrade\r\n'
            'Sec-WebSocket-Accept: ${_accept(key)}\r\n'
            '${protocol == null ? '' : 'Sec-WebSocket-Protocol: $protocol\r\n'}\r\n',
          ),
        );
        afterHandshake.forEach(socket.add);
      });
    });
  }

  Future<void> close() async {
    await client?.close();
    await _server.close();
  }
}

void main() {
  test('the handshake keeps the header case and order it is given', () {
    final text = ExactWebSocket.handshake(
      Uri.parse('wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10'),
      nonce: 'bm9uY2U=',
      headers: const {'User-Agent': 'UA', 'Origin': 'https://www.yy.com', 'connection': 'close'},
      protocols: const ['chat'],
    );
    expect(text.split('\r\n'), [
      'GET /websocket?appid=yymwebh5&version=3.2.10 HTTP/1.1',
      'Host: h5-sinchl.yy.com',
      'User-Agent: UA',
      'Origin: https://www.yy.com',
      'Connection: Upgrade',
      'Upgrade: websocket',
      'Sec-WebSocket-Key: bm9uY2U=',
      'Sec-WebSocket-Version: 13',
      'Sec-WebSocket-Protocol: chat',
      '',
      '',
    ]);
    expect(
      ExactWebSocket.handshake(Uri.parse('ws://chat.example.test:9000/Websocket/bj'), nonce: 'x').split('\r\n')[1],
      'Host: chat.example.test:9000',
    );
  });

  test('a bad accept key or a plain HTTP answer is refused', () {
    expect(
      () => ExactWebSocket.verifyHandshake('HTTP/1.1 200 OK\r\nContent-Length: 0', nonce: 'x'),
      throwsA(isA<WebSocketException>()),
    );
    expect(
      () => ExactWebSocket.verifyHandshake(
        'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: wrong',
        nonce: 'x',
      ),
      throwsA(isA<WebSocketException>()),
    );
    expect(
      ExactWebSocket.verifyHandshake(
        'HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nSec-WebSocket-Accept: ${_accept('x')}\r\n'
        'Sec-WebSocket-Protocol: chat',
        nonce: 'x',
        protocols: const ['chat'],
      ),
      'chat',
    );
  });

  test('raw server: exact request bytes, frames both ways, fragments and ping', () async {
    final server = await _RawServer.start();
    addTearDown(server.close);
    server.serve(
      protocol: 'chat',
      afterHandshake: [
        _frame(2, [1, 2, 3]),
        _frame(1, utf8.encode('hel'), fin: false),
        _frame(0, utf8.encode('lo')),
        _frame(9, utf8.encode('p')),
      ],
    );
    final socket = await ExactWebSocket.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/Websocket/room'),
      headers: const {'Origin': 'https://play.example.test'},
      protocols: const ['chat'],
    );
    expect(socket.protocol, 'chat');
    final request = await server.request.future;
    expect(request, contains('\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n'));
    expect(request, contains('\r\nOrigin: https://play.example.test\r\n'));
    final messages = <Object?>[];
    final subscription = socket.messages.listen(messages.add);
    socket
      ..send([9, 8, 7])
      ..sendText('JOIN #room');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(messages, [
      [1, 2, 3],
      'hello',
    ]);
    final frames = _clientFrames(server.received.toBytes());
    expect(frames.map((f) => f.opcode), [2, 1, 10], reason: 'binary, text, pong');
    expect(frames[0].payload, [9, 8, 7]);
    expect(utf8.decode(frames[1].payload), 'JOIN #room');
    expect(frames[2].payload, utf8.encode('p'));
    await socket.close();
    await subscription.cancel();
  });

  test('dart:io server: echo through a CONNECT proxy', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen(socket.add);
    });
    // A minimal CONNECT proxy.
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(proxy.close);
    final connects = <String>[];
    proxy.listen((client) {
      final head = BytesBuilder();
      Socket? upstream;
      client.listen((data) async {
        if (upstream != null) {
          upstream!.add(data);
          return;
        }
        head.add(data);
        final text = latin1.decode(head.toBytes());
        if (!text.contains('\r\n\r\n')) return;
        connects.add(text.split('\r\n').first);
        final target = text.split(' ')[1].split(':');
        upstream = await Socket.connect(target[0], int.parse(target[1]));
        upstream!.listen(client.add, onDone: client.destroy);
        client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
      }, onDone: () => upstream?.destroy());
    });
    final socket = await ExactWebSocket.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/'),
      route: HttpProxyRoute('127.0.0.1', proxy.port),
    );
    final replies = socket.messages.take(2).toList();
    socket
      ..sendText('ping text')
      ..send(Uint8List.fromList(List<int>.generate(300, (i) => i & 0xff)));
    final echoed = await replies.timeout(const Duration(seconds: 5));
    expect(echoed.first, 'ping text');
    expect(echoed.last, List<int>.generate(300, (i) => i & 0xff));
    expect(connects, ['CONNECT 127.0.0.1:${server.port} HTTP/1.1']);
    await socket.close();
  });

  test('a server that never answers the handshake times out', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    silent.listen((_) {});
    await expectLater(
      ExactWebSocket.connect(Uri.parse('ws://127.0.0.1:${silent.port}/'), timeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
