import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _nonce = 'SGVsbG9Xb3JsZDEyMzQ1Ng==';

/// One client frame as the server reads it.
typedef _Frame = ({bool fin, int opcode, bool masked, List<int> payload});

/// A raw TCP server for one client: reads the request head, answers what the
/// test writes, and reads the client's frames.
final class _RawServer {
  new _(this._server) {
    _server.listen((socket) {
      _socket = socket;
      socket.listen(
        (data) {
          _buffer.addAll(data);
          _pump();
        },
        onDone: () {
          _peerDone = true;
          _pump();
        },
        onError: (Object _) {},
      );
      _connected.complete();
    });
  }

  static Future<_RawServer> start() async => _RawServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final Completer<void> _connected = Completer();
  final List<int> _buffer = [];
  final List<void Function()> _waiters = [];
  Socket? _socket;
  bool _peerDone = false;

  int get port => _server.port;

  Uri get url => Uri.parse('ws://127.0.0.1:$port/websocket?appid=yymwebh5');

  void _pump() {
    for (final waiter in List.of(_waiters)) {
      waiter();
    }
  }

  Future<T> _take<T>(T? Function() read) {
    final result = Completer<T>();
    void attempt() {
      if (result.isCompleted) return;
      final value = read();
      if (value != null) {
        result.complete(value);
      } else if (_peerDone) {
        result.completeError(StateError('the client closed the connection'));
      }
    }

    _waiters.add(attempt);
    attempt();
    return result.future.whenComplete(() => _waiters.remove(attempt)).timeout(const Duration(seconds: 5));
  }

  /// The request head, without its blank line.
  Future<String> head() => _take(() {
    final text = latin1.decode(_buffer);
    final end = text.indexOf('\r\n\r\n');
    if (end < 0) return null;
    _buffer.removeRange(0, end + 4);
    return text.substring(0, end);
  });

  /// Answers the upgrade of [head] and writes [extra] in the same packet.
  Future<void> accept(String head, {List<String> fields = const [], List<int> extra = const []}) async {
    final key = RegExp(r'^Sec-WebSocket-Key: (.+)$', multiLine: true).firstMatch(head)!.group(1)!;
    send([
      ...latin1.encode(
        [
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
          'Sec-WebSocket-Accept: ${ExactWebSocket.acceptKey(key)}',
          ...fields,
          '',
          '',
        ].join('\r\n'),
      ),
      ...extra,
    ]);
  }

  /// Reads the next client frame, unmasked.
  Future<_Frame> frame() => _take(() {
    if (_buffer.length < 2) return null;
    var length = _buffer[1] & 0x7f;
    var offset = 2;
    if (length == 126) {
      if (_buffer.length < 4) return null;
      length = (_buffer[2] << 8) | _buffer[3];
      offset = 4;
    } else if (length == 127) {
      if (_buffer.length < 10) return null;
      length = 0;
      for (var i = 2; i < 10; i++) {
        length = (length << 8) | _buffer[i];
      }
      offset = 10;
    }
    final masked = _buffer[1] & 0x80 != 0;
    final mask = masked ? _buffer.sublist(offset, offset + 4) : const [0, 0, 0, 0];
    if (masked) offset += 4;
    if (_buffer.length < offset + length) return null;
    final payload = [for (var i = 0; i < length; i++) _buffer[offset + i] ^ mask[i & 3]];
    final frame = (fin: _buffer[0] & 0x80 != 0, opcode: _buffer[0] & 0x0f, masked: masked, payload: payload);
    _buffer.removeRange(0, offset + length);
    return frame;
  });

  /// Whether the client closed its end.
  Future<bool> clientClosed() => _take(() => _peerDone ? true : null);

  void send(List<int> bytes) => _socket!.add(bytes);

  Future<void> close() async {
    await _socket?.close();
    _socket?.destroy();
    await _server.close();
  }
}

/// A server frame (unmasked unless [mask] is given).
List<int> _serverFrame(int opcode, List<int> payload, {bool fin = true, List<int>? mask, int rsv = 0}) {
  final length = payload.length;
  return [
    (fin ? 0x80 : 0) | rsv | opcode,
    if (length < 126)
      (mask == null ? 0 : 0x80) | length
    else if (length < 65536) ...[
      (mask == null ? 0 : 0x80) | 126,
      length >> 8,
      length & 0xff,
    ] else ...[
      (mask == null ? 0 : 0x80) | 127,
      for (var shift = 56; shift >= 0; shift -= 8) (length >> shift) & 0xff,
    ],
    ...?mask,
    for (var i = 0; i < length; i++) payload[i] ^ (mask == null ? 0 : mask[i & 3]),
  ];
}

/// Connects to [server] and completes the upgrade; [fields] go into the
/// answer.
Future<(ExactWebSocket, String)> _open(
  _RawServer server, {
  Map<String, String> headers = const {},
  List<String> protocols = const [],
  List<String> fields = const [],
  List<int> extra = const [],
}) async {
  final socket = ExactWebSocket.connect(server.url, headers: headers, protocols: protocols);
  final head = await server.head();
  await server.accept(head, fields: fields, extra: extra);
  return (await socket, head);
}

void main() {
  group('handshake', () {
    test("keeps the caller's headers and the upgrade fields as browsers spell them (3.x YY)", () {
      final request = ExactWebSocket.handshake(
        Uri.parse('wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=u'),
        nonce: _nonce,
        headers: const {'User-Agent': 'Mozilla/5.0', 'Origin': 'https://www.yy.com'},
      );
      expect(
        request,
        'GET /websocket?appid=yymwebh5&version=3.2.10&uuid=u HTTP/1.1\r\n'
        'Host: h5-sinchl.yy.com\r\n'
        'User-Agent: Mozilla/5.0\r\n'
        'Origin: https://www.yy.com\r\n'
        'Connection: Upgrade\r\n'
        'Upgrade: websocket\r\n'
        'Cache-Control: no-cache\r\n'
        'Sec-WebSocket-Key: $_nonce\r\n'
        'Sec-WebSocket-Version: 13\r\n'
        '\r\n',
      );
    });

    test('a port, a subprotocol and the fields it controls itself (3.x SOOP)', () {
      final request = ExactWebSocket.handshake(
        Uri.parse('wss://chat-dee9364c.sooplive.com:9001/Websocket/room'),
        nonce: _nonce,
        protocols: const ['chat'],
        headers: const {
          'Origin': 'https://play.sooplive.co.kr',
          'host': 'elsewhere',
          'connection': 'keep-alive',
          'sec-websocket-key': 'mine',
          'Cache-Control': 'max-age=0',
          'X-Custom': 'kept',
        },
      );
      expect(request.split('\r\n'), [
        'GET /Websocket/room HTTP/1.1',
        'Host: chat-dee9364c.sooplive.com:9001',
        'Origin: https://play.sooplive.co.kr',
        'X-Custom: kept',
        'Connection: Upgrade',
        'Upgrade: websocket',
        'Cache-Control: no-cache',
        'Sec-WebSocket-Key: $_nonce',
        'Sec-WebSocket-Version: 13',
        'Sec-WebSocket-Protocol: chat',
        '',
        '',
      ]);
      expect(
        ExactWebSocket.handshake(Uri.parse('ws://example.com'), nonce: _nonce),
        startsWith('GET / HTTP/1.1\r\nHost: example.com\r\n'),
      );
      expect(
        ExactWebSocket.handshake(Uri.parse('ws://example.com:443/'), nonce: _nonce),
        contains('\r\nHost: example.com:443\r\n'),
      );
    });

    test('a header name or value with a line break is refused (3.x SOOP guard)', () {
      for (final headers in [
        {'Cookie': 'a\r\nX: y'},
        {'X-Test': 'a\nb'},
        {'Bad\rName': 'v'},
      ]) {
        expect(
          () => ExactWebSocket.handshake(Uri.parse('ws://h.example/'), nonce: 'bm9uY2U=', headers: headers),
          throwsArgumentError,
        );
      }
    });

    test('the accept value of RFC 6455 and across SHA-1 block boundaries', () {
      expect(ExactWebSocket.acceptKey('dGhlIHNhbXBsZSBub25jZQ=='), 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=');
      // Python's hashlib over nonce + GUID: 36, 55, 56, 63, 64, 119 and 120 bytes.
      expect(ExactWebSocket.acceptKey(''), 'Kfh9QIsMVZcl6xEPYxPHzW8SZ8w=');
      expect(ExactWebSocket.acceptKey('x' * 19), 'qQsxh2Nb/vsnD9od6HBiP6Igif0=');
      expect(ExactWebSocket.acceptKey('x' * 20), '7jD6MP55bPPoLSNhT1mD/AE8sjc=');
      expect(ExactWebSocket.acceptKey('x' * 27), 'WWp/NRXr3+N4xy7O/17rN1JrRGc=');
      expect(ExactWebSocket.acceptKey('x' * 28), 'atUL8kQGe4qplhq19Y5TKRw/Uj4=');
      expect(ExactWebSocket.acceptKey('x' * 83), 'dkd2ySOIPSpsGLKtMj2xKG4ec9U=');
      expect(ExactWebSocket.acceptKey('x' * 84), '8HQbcddkUtTeWQOigWcTDmzRVvs=');
    });

    test('the answer is checked as 3.x did', () {
      final accept = ExactWebSocket.acceptKey(_nonce);
      String answer(List<String> lines) => ['HTTP/1.1 101 Switching Protocols', ...lines].join('\r\n');
      final valid = ['Connection: Upgrade', 'Upgrade: websocket', 'Sec-WebSocket-Accept: $accept'];
      expect(ExactWebSocket.verifyHandshake(answer(valid), nonce: _nonce), isNull);
      expect(
        ExactWebSocket.verifyHandshake(
          'HTTP/1.0 101\r\nconnection: keep-alive, UPGRADE\r\nupgrade: WebSocket\r\n'
          'sec-websocket-accept: $accept\r\nSec-WebSocket-Protocol: chat',
          nonce: _nonce,
          requestedProtocols: const ['chat'],
        ),
        'chat',
      );
      void rejects(String head, [List<String> protocols = const []]) => expect(
        () => ExactWebSocket.verifyHandshake(head, nonce: _nonce, requestedProtocols: protocols),
        throwsA(isA<WebSocketException>()),
        reason: head,
      );
      rejects(['HTTP/1.1 200 OK', ...valid].join('\r\n'));
      rejects(['HTTP/1.1 1010 Nope', ...valid].join('\r\n'));
      rejects(answer(['Connection: keep-alive', 'Upgrade: websocket', 'Sec-WebSocket-Accept: $accept']));
      rejects(answer(['Connection: Upgrade', 'Sec-WebSocket-Accept: $accept']));
      rejects(answer(['Connection: Upgrade', 'Upgrade: websocket', 'Sec-WebSocket-Accept: wrong']));
      rejects(answer(['Connection: Upgrade', 'Upgrade: websocket']));
      rejects(answer([...valid, 'Sec-WebSocket-Accept: $accept']));
      rejects(answer([...valid, 'Sec-WebSocket-Protocol: chat']));
      rejects(answer([...valid, 'Sec-WebSocket-Protocol: other']), ['chat']);
    });
  });

  group('socket', () {
    late _RawServer server;

    setUp(() async => server = await _RawServer.start());
    tearDown(() => server.close());

    test('sends the request as written and reads frames sent with the answer', () async {
      final (socket, head) = await _open(
        server,
        headers: const {'User-Agent': 'UA', 'Origin': 'https://www.yy.com'},
        extra: _serverFrame(2, [1, 2, 3]),
      );
      final key = RegExp(r'^Sec-WebSocket-Key: (.+)$', multiLine: true).firstMatch(head)!.group(1)!;
      expect(
        '$head\r\n\r\n',
        ExactWebSocket.handshake(
          server.url,
          nonce: key,
          headers: const {'User-Agent': 'UA', 'Origin': 'https://www.yy.com'},
        ),
      );
      expect(base64Decode(key), hasLength(16));
      expect(await socket.stream.first, [1, 2, 3]);
    });

    test('text, fragments, masked frames, 16- and 64-bit lengths; pings are answered', () async {
      final (socket, _) = await _open(server);
      final received = <Object?>[];
      socket.stream.listen(received.add);
      final big = List<int>.generate(70000, (i) => i & 0xff);
      server
        ..send(_serverFrame(1, utf8.encode('你好')))
        ..send([
          ..._serverFrame(2, [1], fin: false),
          ..._serverFrame(9, [7, 7]),
          ..._serverFrame(0, [2], fin: false),
          ..._serverFrame(0, [3]),
        ])
        ..send(_serverFrame(2, List.filled(300, 9), mask: const [1, 2, 3, 4]))
        ..send(_serverFrame(2, big))
        ..send(_serverFrame(10, const []));
      final pong = await server.frame();
      expect((pong.opcode, pong.masked), (10, true));
      expect(pong.payload, [7, 7]);
      await _until(() => received.length == 4);
      expect(received[0], '你好');
      expect(received[1], [1, 2, 3]);
      expect(received[2], List.filled(300, 9));
      expect(received[3], big);
    });

    test('client frames are masked, with 7-, 16- and 64-bit lengths', () async {
      final (socket, _) = await _open(server);
      final big = List<int>.generate(70000, (i) => (i * 7) & 0xff);
      socket
        ..add('弹幕')
        ..add([1, 2, 3])
        ..add(List.filled(200, 5))
        ..add(big);
      final frames = [for (var i = 0; i < 4; i++) await server.frame()];
      expect(frames.every((frame) => frame.fin && frame.masked), isTrue);
      expect(frames.map((frame) => frame.opcode), [1, 2, 2, 2]);
      expect(utf8.decode(frames[0].payload), '弹幕');
      expect(frames[1].payload, [1, 2, 3]);
      expect(frames[2].payload, List.filled(200, 5));
      expect(frames[3].payload, big);
      expect(() => socket.add(42), throwsArgumentError);
    });

    test("the server's close is echoed; code and reason are kept", () async {
      final (socket, _) = await _open(server);
      final done = socket.stream.toList();
      server.send(_serverFrame(8, [0x03, 0xe8, ...utf8.encode('再见')]));
      final echo = await server.frame();
      expect(echo.opcode, 8);
      expect(echo.payload, [0x03, 0xe8, ...utf8.encode('再见')]);
      expect(await done, isEmpty);
      expect((socket.closeCode, socket.closeReason), (1000, '再见'));
      expect(() => socket.add('late'), throwsStateError);
      expect(await server.clientClosed(), isTrue);
    });

    test('close sends the code and ends once the server answers', () async {
      final (socket, _) = await _open(server);
      final closing = socket.close(1000, 'bye');
      final frame = await server.frame();
      expect(frame.opcode, 8);
      expect(frame.payload, [0x03, 0xe8, ...utf8.encode('bye')]);
      server.send(_serverFrame(8, frame.payload));
      await closing.timeout(const Duration(milliseconds: 500));
      await socket.close();
    });

    test('close without an answer ends after a second', () async {
      final (socket, _) = await _open(server);
      final watch = Stopwatch()..start();
      await socket.close();
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect((await server.frame()).payload, isEmpty);
      expect(await server.clientClosed(), isTrue);
    });

    for (final (name, frame, code) in [
      ('reserved bits', _serverFrame(2, const [1], rsv: 0x40), 1002),
      ('an unknown opcode', _serverFrame(3, const [1]), 1002),
      ('a continuation without a start', _serverFrame(0, const [1]), 1002),
      ('a fragmented control frame', _serverFrame(9, const [1], fin: false), 1002),
      ('a control frame over 125 bytes', _serverFrame(9, List.filled(126, 0)), 1002),
      ('a one-byte close payload', _serverFrame(8, const [3]), 1002),
      (
        'a new message inside a fragmented one',
        [
          ..._serverFrame(2, const [1], fin: false),
          ..._serverFrame(2, const [2]),
        ],
        1002,
      ),
      ('invalid UTF-8 text', _serverFrame(1, const [0xff, 0xfe]), 1007),
    ]) {
      test('$name: an error on the stream, a close with $code', () async {
        final (socket, _) = await _open(server);
        final errors = <Object>[];
        final done = Completer<void>();
        socket.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
        server.send(frame);
        final close = await server.frame();
        expect(close.opcode, 8);
        expect((close.payload[0] << 8) | close.payload[1], code);
        await done.future.timeout(const Duration(seconds: 2));
        expect(errors, [isA<Exception>()]);
      });
    }

    test('an oversized frame length is a protocol error', () async {
      final (socket, _) = await _open(server);
      final errors = <Object>[];
      socket.stream.listen((_) {}, onError: errors.add);
      server.send([0x82, 127, 0, 0, 0, 0, 0x01, 0, 0, 1]);
      final close = await server.frame();
      expect((close.payload[0] << 8) | close.payload[1], 1002);
      await _until(() => errors.isNotEmpty);
    });

    test('the handshake timer ends with the upgrade', () async {
      final connecting = ExactWebSocket.connect(server.url, connectTimeout: const Duration(milliseconds: 100));
      await server.accept(await server.head());
      final socket = await connecting;
      final received = <Object?>[];
      final errors = <Object>[];
      socket.stream.listen(received.add, onError: errors.add);
      await _wait(const Duration(milliseconds: 250));
      server.send(_serverFrame(1, utf8.encode('still open')));
      await _until(() => received.isNotEmpty);
      expect(received, ['still open']);
      expect(errors, isEmpty);
    });
  });

  group('failed handshakes', () {
    late _RawServer server;

    setUp(() async => server = await _RawServer.start());
    tearDown(() => server.close());

    Future<void> fails(Matcher matcher, Future<void> Function(String head) answer, {Duration? timeout}) async {
      final connecting = ExactWebSocket.connect(server.url, connectTimeout: timeout ?? const Duration(seconds: 2));
      final expectation = expectLater(connecting, throwsA(matcher));
      await answer(await server.head());
      await expectation;
    }

    test('not upgraded', () async {
      await fails(isA<WebSocketException>(), (_) async => server.send(latin1.encode('HTTP/1.1 403 Forbidden\r\n\r\n')));
    });

    test('a wrong accept value', () async {
      await fails(
        isA<WebSocketException>(),
        (_) async => server.send(
          latin1.encode(
            'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n'
            'Sec-WebSocket-Accept: wrong\r\n\r\n',
          ),
        ),
      );
    });

    test('closed during the handshake', () async {
      await fails(isA<WebSocketException>(), (_) => server.close());
    });

    test('an answer head over 32 KiB', () async {
      await fails(isA<WebSocketException>(), (_) async => server.send(latin1.encode('HTTP/1.1 101 ${'x' * 40000}')));
    });

    test('no answer within the connect timeout', () async {
      await fails(isA<TimeoutException>(), (_) async {}, timeout: const Duration(milliseconds: 100));
    });

    test('an unsupported scheme or a refused connection', () async {
      await expectLater(ExactWebSocket.connect(Uri.parse('http://127.0.0.1/')), throwsA(isA<WebSocketException>()));
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(ExactWebSocket.connect(Uri.parse('ws://127.0.0.1:$port/')), throwsA(isA<SocketException>()));
      await server.close();
    });
  });

  test('a dart:io server; the connector goes direct whatever the route (3.x)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closeCodes = Completer<int?>();
    final requests = <HttpHeaders>[];
    server.listen((request) async {
      requests.add(request.headers);
      final socket = await WebSocketTransformer.upgrade(request, protocolSelector: (protocols) => protocols.last);
      socket.listen(socket.add, onDone: () => closeCodes.complete(socket.closeCode));
    });
    addTearDown(() => server.close(force: true));
    final channel = await connectExactWebSocket(
      Uri.parse('ws://127.0.0.1:${server.port}/chat'),
      headers: const {'Origin': 'https://play.sooplive.co.kr'},
      protocols: const ['binary', 'chat'],
      route: const HttpProxyRoute('203.0.113.1', 9),
      connectTimeout: const Duration(seconds: 2),
    );
    expect((channel as ExactWebSocket).protocol, 'chat');
    expect(requests.single.value('origin'), 'https://play.sooplive.co.kr');
    final echoes = channel.stream.take(2).toList();
    channel
      ..add('text')
      ..add([1, 2, 3]);
    expect(await echoes, [
      'text',
      [1, 2, 3],
    ]);
    await channel.close(1000);
    expect(await closeCodes.future.timeout(const Duration(seconds: 2)), 1000);
  });
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}
