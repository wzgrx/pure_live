import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/soop/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded session (S07-live): frames in order, with their direction.
final List<({String dir, Uint8List bytes})> _frames = [
  for (final line in File('$_root/S07-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': final String dir, 'b64': final String b64}) (dir: dir, bytes: base64Decode(b64)),
];

final Map<String, Object?> _meta = _json('S07-live/meta.json')! as Map<String, Object?>;

final Map<String, Object?> _keys = _meta['danmakuKeys']! as Map<String, Object?>;

/// 3.x's output for S07-live (fixtures/soop/danmaku/legacy_expected.dart).
final Map<String, Object?> _recorded =
    (_json('S07-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

List<Map<String, Object?>> get _recordedMessages => [
  for (final message in _recorded['messages']! as List<Object?>) Map.of(message! as Map<String, Object?>),
];

List<Map<String, Object?>> get _recordedWithoutFrames => [
  for (final message in _recordedMessages) message..remove('frame'),
];

/// The chat packets of S07, in order, as their fields.
final List<List<String>> _recordedChatFields = [
  for (final frame in _frames)
    if (frame.dir == 'in')
      for (final packet in SoopDanmakuProtocol.packets(frame.bytes))
        if (packet.service == SoopDanmakuProtocol.chatService) utf8.decode(packet.body).split('\f'),
];

/// B-6: 3.x left the sender's id empty; it is field 2 without the `(n)` of
/// a second session. Read here independently of the decoder, in the order
/// of 3.x's messages (every recorded chat packet gives one).
List<Map<String, Object?>> _withSenderIds(List<Map<String, Object?>> messages) {
  expect(messages, hasLength(_recordedChatFields.length));
  return [
    for (final (index, message) in messages.indexed)
      {...message, 'userId': _recordedChatFields[index][2].replaceFirst(RegExp(r'\(\d+\)$'), '')},
  ];
}

/// S07 as decoded since B-6: 3.x's messages with the sender's id.
List<Map<String, Object?>> get _recordedB6 => _withSenderIds(_recordedMessages);

List<Map<String, Object?>> get _recordedB6WithoutFrames => _withSenderIds(_recordedWithoutFrames);

String _packetText(Object? base64) => utf8.decode(base64Decode(base64! as String));

/// The arguments M4.7 builds for the recorded room, with a synthetic cookie.
final SoopDanmakuArgs _args = SoopApi.danmakuArgs(
  {'CHDOMAIN': _keys['chatHost'], 'CHPT': _keys['chatPort'], 'CHATNO': _keys['chatNo']},
  roomId: _keys['bj']! as String,
  cookie: 'PdboxTicket=synthetic.ticket',
)!;

final String _chatNo = _keys['chatNo']! as String;

final String _join = SoopDanmakuProtocol.join(_chatNo);

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'data': message.data,
};

List<int> _hex(String text) => [
  for (var index = 0; index < text.length; index += 2) int.parse(text.substring(index, index + 2), radix: 16),
];

/// One case of S08-synthetic/cases.json as the server frames it (the same
/// framing as legacy_expected.dart's `serverFrame`).
List<int> _serverFrame(Map<String, Object?> testCase) {
  final bytes = <int>[];
  for (final item in testCase['packets']! as List<Object?>) {
    final packet = item! as Map<String, Object?>;
    if (packet['hex'] case final String raw) {
      bytes.addAll(_hex(raw));
      continue;
    }
    final body = packet['bodyHex'] is String
        ? _hex(packet['bodyHex']! as String)
        : utf8.encode((packet['fields']! as List<Object?>).cast<String>().join('\f'));
    bytes
      ..addAll(_hex(packet['prefix'] as String? ?? '1b09'))
      ..addAll(ascii.encode(packet['serviceText'] as String? ?? (packet['service']! as int).toString().padLeft(4, '0')))
      ..addAll(ascii.encode(packet['lengthText'] as String? ?? body.length.toString().padLeft(6, '0')))
      ..addAll(ascii.encode(packet['reserved'] as String? ?? '00'))
      ..addAll(body);
  }
  return bytes.sublist(0, bytes.length - (testCase['cut'] as int? ?? 0));
}

/// A chat packet as the server frames it.
List<int> _chat(String text, [String nick = 'viewer']) => _serverFrame({
  'packets': [
    {
      'service': 5,
      'fields': [
        '',
        text,
        'abc123',
        '0',
        '0',
        '3',
        nick,
        '65568|163840',
        '-1',
        'E12E2E',
        'E04949',
        '-1',
        '-1',
        '',
        '-1',
        '',
      ],
    },
  ],
});

final class _FakeChannel implements SocketChannel {
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// Hands out fake channels and records every handshake; endpoints whose
/// scheme is in [refuse] fail.
final class _Connector {
  new({this.refuse = const {}});

  final Set<String> refuse;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<Iterable<String>?> protocols = [];
  final List<ProxyRoute> routes = [];
  final List<_FakeChannel> channels = [];

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    this.protocols.add(protocols);
    routes.add(route);
    if (refuse.contains(endpoint.scheme)) throw const SocketException('Connection closed by peer');
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuReceived) event.message,
];

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

/// Runs [body] with every timer of a second or more (backoff) recorded into
/// [delays] and fired at once.
Future<void> _fastBackoff(List<Duration> delays, Future<void> Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration < const Duration(seconds: 1)) return parent.createTimer(zone, duration, callback);
      delays.add(duration);
      return parent.createTimer(zone, Duration.zero, callback);
    },
  ),
);

/// A local stand-in for a SOOP chat edge: it upgrades only a handshake
/// spelled as browsers and 3.x write it (a lower-cased one stays pending,
/// as the real edges do), selects `chat`, records the client's frames and
/// the request head, and answers with frames of its own.
final class _ChatServer {
  new _(this._server) {
    _server.listen(_accept);
  }

  static Future<_ChatServer> start({bool upgrade = true, String? reply}) async {
    final server = _ChatServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0))
      .._upgrade = upgrade
      .._reply = reply;
    addTearDown(server.close);
    return server;
  }

  final ServerSocket _server;
  bool _upgrade = true;
  String? _reply;
  final List<String> requests = [];
  final List<({int opcode, Uint8List payload})> received = [];
  final List<Socket> sockets = [];
  final List<Completer<void>> closedSockets = [];

  /// Called with every data frame the client sends.
  void Function(_ChatServer server, Socket socket, Object message)? onMessage;

  int get port => _server.port;

  static const _required = [
    '\r\nConnection: Upgrade\r\n',
    '\r\nUpgrade: websocket\r\n',
    '\r\nSec-WebSocket-Version: 13\r\n',
    '\r\nSec-WebSocket-Protocol: chat\r\n',
  ];

  void _accept(Socket socket) {
    sockets.add(socket);
    // Writes to a client that already dropped the connection fail here.
    socket.done.ignore();
    final closed = Completer<void>();
    closedSockets.add(closed);
    var buffer = <int>[];
    var open = false;
    socket.listen(
      (data) {
        buffer = [...buffer, ...data];
        if (!open) {
          final text = latin1.decode(buffer);
          final end = text.indexOf('\r\n\r\n');
          if (end < 0) return;
          final head = text.substring(0, end + 2);
          requests.add(head);
          buffer = buffer.sublist(end + 4);
          final key = RegExp(r'\r\nSec-WebSocket-Key: (\S+)\r\n').firstMatch(head)?.group(1);
          if (_reply case final reply?) {
            socket.add(latin1.encode(reply));
            return;
          }
          if (!_upgrade || key == null || !_required.every(head.contains)) return;
          open = true;
          socket.add(
            latin1.encode(
              'HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nConnection: Upgrade\r\n'
              'Sec-WebSocket-Accept: ${ExactWebSocket.acceptKey(key)}\r\nSec-WebSocket-Protocol: chat\r\n\r\n',
            ),
          );
        }
        buffer = _readFrames(socket, buffer);
      },
      onDone: closed.complete,
      onError: (Object _) => closed.complete(),
    );
  }

  /// Client frames are masked; returns what is left of [bytes].
  List<int> _readFrames(Socket socket, List<int> bytes) {
    var rest = bytes;
    while (rest.length >= 2) {
      final opcode = rest[0] & 0x0f;
      var length = rest[1] & 0x7f;
      var offset = 2;
      if (length == 126) {
        if (rest.length < 4) break;
        length = (rest[2] << 8) | rest[3];
        offset = 4;
      }
      expect(rest[1] & 0x80, 0x80, reason: 'client frames are masked');
      if (rest.length < offset + 4 + length) break;
      final mask = rest.sublist(offset, offset + 4);
      final payload = Uint8List.fromList([
        for (var index = 0; index < length; index++) rest[offset + 4 + index] ^ mask[index & 3],
      ]);
      rest = rest.sublist(offset + 4 + length);
      received.add((opcode: opcode, payload: payload));
      switch (opcode) {
        case 1:
          onMessage?.call(this, socket, utf8.decode(payload));
        case 2:
          onMessage?.call(this, socket, payload);
        case 8:
          send(socket, 8, payload);
          unawaited(socket.close());
      }
    }
    return rest;
  }

  /// Texts the client sent, in order.
  List<String> get texts => [
    for (final frame in received)
      if (frame.opcode == 1) utf8.decode(frame.payload),
  ];

  /// Sends an unmasked frame.
  static void send(Socket socket, int opcode, List<int> payload, {bool fin = true}) {
    final length = payload.length;
    socket.add([
      (fin ? 0x80 : 0) | opcode,
      if (length < 126)
        length
      else if (length < 65536) ...[
        126,
        length >> 8,
        length & 0xff,
      ] else ...[
        127,
        for (var shift = 56; shift >= 0; shift -= 8) (length >> shift) & 0xff,
      ],
      ...payload,
    ]);
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

/// A connector that opens [server] with the case-sensitive handshake
/// whatever endpoint it is given, recording the endpoints and headers.
SocketConnector _local(_ChatServer server, List<Uri> endpoints, List<Map<String, String>> seen) =>
    (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
      endpoints.add(endpoint);
      seen.add(headers);
      return connectExactWebSocket(
        Uri.parse('ws://127.0.0.1:${server.port}${endpoint.path}'),
        headers: headers,
        protocols: protocols,
        route: route,
        connectTimeout: connectTimeout,
      );
    };

/// A local HTTP proxy (B-6): answers `CONNECT` for [port] and pipes the
/// tunnel to 127.0.0.1:[upstream]; every other port is refused with 502.
/// It never dials out.
final class _ConnectProxy {
  new _(this._server, this.port, this.upstream) {
    _server.listen(_accept);
  }

  static Future<_ConnectProxy> start({required int port, required int upstream}) async {
    final proxy = _ConnectProxy._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), port, upstream);
    addTearDown(proxy.close);
    return proxy;
  }

  final ServerSocket _server;

  /// The tunnelled port.
  final int port;

  /// Where the tunnel leads.
  final int upstream;

  /// The request heads, in order.
  final List<String> requests = [];
  final List<Socket> _sockets = [];

  int get localPort => _server.port;

  void _accept(Socket client) {
    _sockets.add(client);
    client.done.ignore();
    var head = <int>[];
    Socket? tunnel;
    client.listen(
      (data) {
        if (tunnel case final upstream?) {
          upstream.add(data);
          return;
        }
        head = [...head, ...data];
        final text = latin1.decode(head);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        requests.add(text.substring(0, end));
        final rest = head.sublist(end + 4);
        if (!text.startsWith('CONNECT ') || !text.split('\r\n').first.contains(':$port ')) {
          client.add(latin1.encode('HTTP/1.1 502 Bad Gateway\r\n\r\n'));
          unawaited(client.close());
          return;
        }
        unawaited(
          Socket.connect(InternetAddress.loopbackIPv4, upstream).then((socket) {
            _sockets.add(socket);
            socket.done.ignore();
            tunnel = socket;
            socket.listen(client.add, onDone: () => client.destroy(), onError: (Object _) => client.destroy());
            client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
            if (rest.isNotEmpty) socket.add(rest);
          }),
        );
      },
      onDone: () => tunnel?.destroy(),
      onError: (Object _) => tunnel?.destroy(),
    );
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

void main() {
  group('protocol', () {
    test("client packets are 3.x's and the recorded ones", () {
      final joins = _recorded['joinPackets']! as Map<String, Object?>;
      for (final MapEntry(key: chatNo, value: packets) in joins.entries) {
        final [login, join] = [for (final packet in packets! as List<Object?>) _packetText(packet)];
        expect(SoopDanmakuProtocol.login, login);
        expect(SoopDanmakuProtocol.join(chatNo), join, reason: chatNo);
      }
      expect(SoopDanmakuProtocol.heartbeat, _packetText(_recorded['heartbeatPacket']));
      final sent = [
        for (final frame in _frames)
          if (frame.dir == 'out') utf8.decode(frame.bytes),
      ];
      expect(sent, [SoopDanmakuProtocol.login, _join, SoopDanmakuProtocol.heartbeat]);
      // The join's length counts UTF-8 bytes.
      expect(SoopDanmakuProtocol.join('채팅'), '\x1b\t000200001200\f채팅\f\f\f\f\f');
    });

    test('splits every recorded frame into whole packets', () {
      final services = <int, int>{};
      for (final frame in _frames) {
        if (frame.dir != 'in') continue;
        final packets = SoopDanmakuProtocol.packets(frame.bytes);
        expect(
          packets.fold<int>(0, (sum, packet) => sum + SoopDanmakuProtocol.headerLength + packet.body.length),
          frame.bytes.length,
        );
        for (final packet in packets) {
          services.update(packet.service, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      expect(services, {1: 1, 2: 1, 4: 2045, 5: 144, 12: 3, 19: 1, 21: 1, 54: 1, 90: 1, 94: 1, 110: 1, 127: 1386});
      final joined = SoopDanmakuProtocol.packets(_frames[3].bytes).single;
      expect(joined.service, 2);
      expect(utf8.decode(joined.body).split('\f').sublist(1, 3), [_chatNo, _keys['bj']]);
    });

    test('endpoints: TLS on CHPT + 1, then the plain port, as recorded', () {
      final recorded = [
        for (final handshake in _meta['handshakes']! as List<Object?>) (handshake! as Map<String, Object?>)['url'],
      ];
      expect(SoopDanmakuProtocol.endpoints(_args).map((endpoint) => '$endpoint'), recorded);
    });

    test("handshake headers are 3.x's, spelled and ordered as 3.x wrote them", () {
      expect(
        [
          for (final MapEntry(:key, :value) in SoopDanmakuProtocol.handshakeHeaders(_args.headers).entries)
            '$key: $value',
        ],
        [
          'Accept: */*',
          'Origin: https://play.sooplive.co.kr',
          'Referer: https://www.sooplive.co.kr/',
          'Sec-Fetch-Dest: empty',
          'Sec-Fetch-Mode: cors',
          'Sec-Fetch-Site: same-site',
          'User-Agent: ${SoopApi.userAgent}',
          'Cookie: PdboxTicket=synthetic.ticket',
        ],
      );
      expect(SoopApi.userAgent, contains(' Chrome/128.0.0.0 '), reason: "3.x's danmaku UA");
      expect(SoopDanmakuProtocol.headerName('SEC-websocket-KEY'), 'Sec-Websocket-Key');
      expect(SoopDanmakuProtocol.headerName('x--a'), 'X--A');
      expect(SoopDanmakuProtocol.plainHeaders({'Origin': 'o', 'COOKIE': 'c', 'cookie': 'd'}), {'Origin': 'o'});
    });

    test('decodes chat only: text, nick, white, the sender (B-6); no message id, time or level (3.x)', () {
      final message = SoopDanmakuProtocol.decode(_chat(' 안녕 ', ' 시청자 ')).single;
      expect(_project(message), {
        'type': 'chat',
        'userName': '시청자',
        // B-6: 3.x left it empty.
        'userId': 'abc123',
        'message': '안녕',
        'color': '#ffffff',
        'messageId': '',
        'sentAt': null,
        'userLevel': '',
        'fansLevel': '',
        'fansName': '',
        'isLocal': false,
        'data': null,
      });
      expect(SoopDanmakuProtocol.chat(utf8.encode('\fonly\f\f\f\f\fsix')), isNotNull);
      expect(SoopDanmakuProtocol.chat(utf8.encode('\fonly\f\f\f\fsix')), isNull);
    });
  });

  group('recorded frames (S07) against 3.x', () {
    test('the 3586 incoming frames give the same 144 chat lines, in the same frames, now with the sender (B-6)', () {
      final decoded = <Map<String, Object?>>[];
      for (var index = 0; index < _frames.length; index++) {
        final frame = _frames[index];
        if (frame.dir != 'in') continue;
        decoded.addAll([
          for (final message in SoopDanmakuProtocol.decode(frame.bytes)) {'frame': index, ..._project(message)},
        ]);
      }
      expect(decoded, hasLength(144));
      // B-6: 3.x had no sender id; everything else is 3.x's.
      expect(_recordedMessages.map((message) => message['userId']).toSet(), {''});
      expect(
        [
          for (final message in decoded) {...message}..remove('userId'),
        ],
        [
          for (final message in _recordedMessages) {...message}..remove('userId'),
        ],
      );
      expect(decoded, _recordedB6);
      expect(decoded.take(3).map((message) => message['userId']), ['loo3672', 'ztmanwb269', 'pwxzbx779']);
      expect(_recordedChatFields.take(3).map((fields) => fields[2]), ['loo3672(2)', 'ztmanwb269', 'pwxzbx779(2)']);
    });
  });

  group('synthetic frames (S08) against 3.x', () {
    final cases = (_json('S08-synthetic/cases.json')! as Map<String, Object?>)['cases']! as List<Object?>;
    final expected = {
      for (final item in (_json('S08-synthetic/expected.json')! as Map<String, Object?>)['value']! as List<Object?>)
        (item! as Map<String, Object?>)['name']! as String:
            (item as Map<String, Object?>)['messages']! as List<Object?>,
    };

    test('every case has 3.x output', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
    });

    /// B-6: what changed against 3.x, by case (3.x's output is asserted
    /// first).
    Map<String, Object?> chat(String userName, String message, [String userId = '']) => {
      'type': 'chat',
      'userName': userName,
      'userId': userId,
      'message': message,
      'color': '#ffffff',
      'messageId': '',
      'sentAt': null,
      'userLevel': '',
      'fansLevel': '',
      'fansName': '',
      'isLocal': false,
      'data': null,
    };
    final b6 = <String, (List<Object?>, List<Object?>)>{
      'the texts -1 and 1 are dropped, others with digits kept': (
        [chat('d', '11'), chat('e', '+1'), chat('f', '2')],
        [chat('a', '-1'), chat('b', '1'), chat('c', '1'), chat('d', '11'), chat('e', '+1'), chat('f', '2')],
      ),
      'a text holding a bar is dropped': (
        [chat('c', 'no bar')],
        [chat('a', 'a|b'), chat('b', '|'), chat('c', 'no bar')],
      ),
      'malformed UTF-8 becomes replacement characters': (
        [chat('v\u{FFFD}(', 'ok\u{FFFD}')],
        [chat('v\u{FFFD}(', 'ok\u{FFFD}', 'id')],
      ),
      'Hangul and emoji': ([chat('시청자', '안녕하세요 🎉')], [chat('시청자', '안녕하세요 🎉', 'gvwxyz12')]),
      'chat after empty viewer-list packets, as recorded': ([chat('观众1', '지금도')], [chat('观众1', '지금도', 'mnopqr123')]),
    };

    test('every B-6 change names a case', () {
      expect(expected.keys, containsAll(b6.keys));
    });

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        final decoded = SoopDanmakuProtocol.decode(_serverFrame(testCase)).map(_project).toList();
        if (b6[name] case (final legacy, final now)) {
          expect(expected[name], legacy, reason: "3.x's output");
          expect(decoded, now, reason: 'B-6');
        } else {
          expect(decoded, expected[name]);
        }
      });
    }
  });

  group('B-6: chat texts, the sender and the separators', () {
    test('the recorded chat packets: 16 fields split by form feeds; a bar only between the two flags of field 7', () {
      expect(_recordedChatFields, hasLength(144));
      for (final fields in _recordedChatFields) {
        expect(fields, hasLength(16));
        for (final (index, field) in fields.indexed) {
          if (index == 7) {
            expect(field, matches(RegExp(r'^\d+\|\d+$')));
          } else {
            expect(field, isNot(contains('|')), reason: 'field $index');
          }
        }
      }
    });

    test('recorded (S09): four chats of 1, dropped by 3.x, and a nick holding a bar', () {
      final frames = [
        for (final line in File('$_root/S09-live-ones-and-bars/frames.jsonl').readAsLinesSync())
          base64Decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String),
      ];
      final legacy =
          ((_json('S09-live-ones-and-bars/expected.json')! as Map<String, Object?>)['value']!
                  as Map<String, Object?>)['messages']!
              as List<Object?>;
      expect(
        [for (final message in legacy) (message! as Map<String, Object?>)['message']],
        ['저번에 한다던 낚시겜은 안해?'],
        reason: "3.x's output: every 1 dropped",
      );
      final decoded = [
        for (final (index, frame) in frames.indexed)
          for (final message in SoopDanmakuProtocol.decode(frame)) {'frame': index, ..._project(message)},
      ];
      expect(
        [for (final message in decoded) (message['frame'], message['message'], message['userId'], message['userName'])],
        [
          (0, '저번에 한다던 낚시겜은 안해?', 'onubqa3484', '观众2|'),
          (1, '1', 'ocwyyo7379', '观众1'),
          (2, '1', 'y7i0u6s1qt', '观众3'),
          (3, '1', 'tsoplt5114', '观众4'),
          (4, '1', 'jslq08', '观众5'),
        ],
      );
      // B-6: the one chat 3.x showed is 3.x's with the sender.
      expect(decoded.first, {...legacy.single! as Map<String, Object?>, 'userId': 'onubqa3484'});
      for (final frame in frames) {
        final fields = utf8.decode(SoopDanmakuProtocol.packets(frame).single.body).split('\f');
        expect(fields, hasLength(16));
        expect(fields[7], matches(RegExp(r'^\d+\|\d+$')));
      }
    });

    test('texts 1 and -1 and texts with a bar are chat like any other (the web player shows them)', () {
      List<String> fields(String text, String id, String nick) => [
        '',
        text,
        id,
        '0',
        '0',
        '3',
        nick,
        '589856|163840',
        '-1',
        'C25111',
        'CF8362',
        '-1',
        '-1',
        '',
        '-1',
        '',
      ];
      final frame = _serverFrame({
        'packets': [
          {'service': 5, 'fields': fields('1', 'voter01(2)', '观众1')},
          {'service': 5, 'fields': fields('-1', 'voter02', '观众2')},
          {'service': 5, 'fields': fields(' 1|2|3 ', 'voter03', '观众3')},
          {'service': 5, 'fields': fields('|', 'voter04', '观众4')},
          {'service': 5, 'fields': fields('ㅋㅋ | ㅋㅋ', 'voter05', '观众5')},
        ],
      });
      expect(
        [
          for (final message in SoopDanmakuProtocol.decode(frame))
            (message.message, message.userId, message.userName, message.type, message.color),
        ],
        [
          ('1', 'voter01', '观众1', LiveMessageType.chat, LiveMessageColor.white),
          ('-1', 'voter02', '观众2', LiveMessageType.chat, LiveMessageColor.white),
          ('1|2|3', 'voter03', '观众3', LiveMessageType.chat, LiveMessageColor.white),
          ('|', 'voter04', '观众4', LiveMessageType.chat, LiveMessageColor.white),
          ('ㅋㅋ | ㅋㅋ', 'voter05', '观众5', LiveMessageType.chat, LiveMessageColor.white),
        ],
      );
    });

    test("the sender's id: field 2 without the (n) of a second session, as the web's realID reads it", () {
      for (final (field, id) in [
        ('loo3672(2)', 'loo3672'),
        ('ztmanwb269', 'ztmanwb269'),
        ('abc_12(13)', 'abc_12'),
        (' spaced(3) ', 'spaced'),
        ('user99', 'user99'),
        ('(2)', '2'),
        ('', ''),
        ('   ', ''),
        ('한글', '한글'),
        ('a-b(2)', 'b'),
      ]) {
        expect(SoopDanmakuProtocol.userId(field), id, reason: field);
      }
      // Seven fields are enough; the id is read.
      expect(SoopDanmakuProtocol.chat(utf8.encode('\fhi\fid(2)\f\f\f\fnick'))?.userId, 'id');
    });

    test('the dedup gate tells two viewers with the same nick and text apart by their ids', () {
      final now = DateTime.utc(2026, 9, 27, 17, 38, 40);
      final gate = DanmakuMessageGate();
      final [first, second, again] = [
        for (final id in ['alpha01', 'beta02', 'alpha01(2)'])
          SoopDanmakuProtocol.decode(
            _serverFrame({
              'packets': [
                {
                  'service': 5,
                  'fields': ['', '1', id, '0', '0', '3', '같은닉', '65568|163840', '-1', '', '', '-1', '-1', '', '-1', ''],
                },
              ],
            }),
          ).single,
      ];
      expect(gate.accepts(first, now: now), isTrue);
      expect(gate.accepts(second, now: now), isTrue, reason: 'another viewer with the same nick');
      expect(gate.accepts(again, now: now), isFalse, reason: "the first viewer's second session repeating itself");
    });
  });

  group('balloons and subscriptions (D07.7, S10-balloons)', () {
    final frames = [
      for (final line in File('../../fixtures/soop/danmaku/S10-balloons/frames.jsonl').readAsLinesSync())
        base64.decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String),
    ];
    List<int> packet(int service, List<String> fields) {
      final body = utf8.encode('\f${fields.join('\f')}');
      return [...utf8.encode('\x1b\t${'$service'.padLeft(4, '0')}${'${body.length}'.padLeft(6, '0')}00'), ...body];
    }

    test('S10: every recorded packet as the web player reads it', () {
      final messages = [for (final frame in frames) ...SoopDanmakuProtocol.decode(frame)];
      expect(messages, hasLength(22));
      expect(
        [
          for (final m in messages)
            (m.type, m.userName, m.userId, m.data is LiveGift ? (m.data! as LiveGift).count : m.message),
        ],
        [
          (LiveMessageType.gift, '시청자1', 'viewer001', 10),
          for (final (n, count) in [(2, 10), (3, 10), (4, 10), (2, 33), (5, 10), (6, 10), (3, 10), (7, 100)])
            (LiveMessageType.gift, '시청자$n', 'viewer00$n', count),
          (LiveMessageType.notice, '시청자8', 'viewer008', '시청자8 订阅了频道，已订阅 33 个月'),
          (LiveMessageType.notice, '시청자9', 'viewer009', '시청자9 订阅了频道'),
          (LiveMessageType.notice, '시청자10', 'viewer010', '시청자10 订阅了频道，已订阅 62 个月'),
          (LiveMessageType.notice, '시청자11', 'viewer011', '시청자11 订阅了频道，已订阅 32 个月'),
          (LiveMessageType.notice, '시청자12', 'viewer012', '시청자12 订阅了频道，已订阅 52 个月'),
          for (final (n, count) in [(13, 100), (14, 100), (15, 10), (16, 19), (17, 10), (18, 10), (17, 10), (19, 10)])
            (LiveMessageType.gift, '시청자$n', 'viewer0$n', count),
        ],
      );
      final adBalloon = messages.first;
      expect(adBalloon.messageId, matches(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-')));
      expect(
        adBalloon.data,
        LiveGift(
          name: '애드벌룬',
          count: 10,
          kind: LiveGiftKind.tip,
          iconUrl: Uri.parse('https://res.sooplive.com/new_player/items/img_adballoon.png'),
        ),
        reason: 'ad balloons have no value this app can place',
      );
      expect(
        messages[1].data,
        const LiveGift(
          name: '별풍선',
          count: 10,
          kind: LiveGiftKind.tip,
          unitPrice: 1,
          totalValue: 10,
          unit: LiveGiftUnit.starBalloon,
        ),
      );
      expect(messages[1].message, '별풍선 ×10');
      expect(messages[1].messageId, matches(RegExp('^[0-9a-f]{8}-')));
      expect(messages.map((m) => m.messageId).toSet(), hasLength(22));
      final notices = [
        for (final m in messages)
          if (m.type == LiveMessageType.notice) m,
      ];
      expect(notices.map((m) => m.data), everyElement(LiveNoticeKind.subscription));
      expect(notices.map((m) => m.messageId), everyElement(startsWith('subscription:')));
      expect((messages[8].data! as LiveGift).tier, LiveGiftTier.valuable, reason: '100 star balloons, about 59 yuan');
    });

    test('relayed and video balloons, as the web player reads them; what is not a balloon', () {
      final relayed = SoopDanmakuProtocol.decode(
        packet(33, [
          '1',
          'bj',
          '2',
          'fan(2)',
          '팬',
          '5',
          '0',
          '0',
          'x',
          '0',
          '0',
          '',
          'f00d0000-0000-4000-8000-000000000000',
        ]),
      ).single;
      expect(
        (relayed.userId, relayed.userName, relayed.messageId),
        ('fan', '팬', 'f00d0000-0000-4000-8000-000000000000'),
      );
      expect((relayed.data! as LiveGift).totalValue, 5);
      final video = SoopDanmakuProtocol.decode(packet(105, ['4650', 'bj', 'fan', '팬', '200', '0'])).single;
      expect(
        video.data,
        const LiveGift(
          name: '영상풍선',
          count: 200,
          kind: LiveGiftKind.tip,
          unitPrice: 1,
          totalValue: 200,
          unit: LiveGiftUnit.starBalloon,
        ),
      );
      expect(video.messageId, '');
      expect(SoopDanmakuProtocol.decode(packet(18, ['bj', 'fan', '팬', '0'])), isEmpty, reason: 'no count');
      expect(SoopDanmakuProtocol.decode(packet(18, ['bj', '', '팬', '10'])), isEmpty, reason: 'no sender');
      expect(SoopDanmakuProtocol.decode(packet(18, ['bj', 'fan', '팬', 'x'])), isEmpty);
      expect(SoopDanmakuProtocol.decode(packet(18, ['bj', 'fan'])), isEmpty, reason: 'short');
      expect(
        SoopDanmakuProtocol.decode(packet(18, ['bj', 'fan', '팬', '3', '0', '0', '0', '0', '0', '0', '0', 'no uuid']))
            .single
            .messageId,
        '',
      );
      expect(SoopDanmakuProtocol.decode(packet(91, ['90', 'bj', '', '팬'])), isEmpty);
      expect(
        SoopDanmakuProtocol.decode(packet(108, ['x', 'fan', '팬', 'bj', 'bj'])),
        isEmpty,
        reason: 'gift subscriptions: not recorded',
      );
      // A frame of several packets: chat and a balloon in order.
      final chat = _chat('안녕');
      final mixed = SoopDanmakuProtocol.decode([
        ...chat,
        ...packet(18, ['bj', 'fan', '팬', '1']),
      ]);
      expect(mixed.map((m) => m.type), [LiveMessageType.chat, LiveMessageType.gift]);
    });

    test('the connection reports the recorded balloons and subscriptions in order', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      frames.forEach(connector.channels.single.incoming.add);
      await _until(() => _messages(events).length == 22);
      expect(_messages(events).where((m) => m.type == LiveMessageType.gift), hasLength(17));
      await connection.close();
    });
  });

  group('connection', () {
    test(
      'opens the TLS port with the chat subprotocol and 3.x headers, is ready at once, logs in, joins 200 ms later',
      () async {
        final timers = <Duration>[];
        final connector = _Connector();
        final events = <DanmakuEvent>[];
        await runZoned(
          () async {
            final connection = SoopDanmakuConnection(connector: connector.call);
            connection.events.listen(events.add);
            await connection.connect(_args);
            expect(connector.endpoints, [_args.url]);
            expect(connector.protocols.single, ['chat']);
            expect(connector.headers.single, SoopDanmakuProtocol.handshakeHeaders(_args.headers));
            expect(connector.headers.single['Cookie'], 'PdboxTicket=synthetic.ticket');
            expect(connector.routes.single, const DirectRoute());
            expect(events, [const DanmakuReady()]);
            expect(connection.isConnected, isTrue);
            final sent = connector.channels.single.sent;
            expect(sent, [SoopDanmakuProtocol.login]);
            await _until(() => sent.length == 2);
            expect(sent, [SoopDanmakuProtocol.login, _join]);
            await connection.close();
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              timers.add(duration);
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        expect(timers, contains(const Duration(milliseconds: 200)));
      },
    );

    test("3.x's timing: 20 s heartbeat, 90 s silence limit, no join timer, 8 reconnects", () {
      final connection = SoopDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 20));
      expect(connection.site, SiteIds.soop);
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 20));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 20 s, 90 s) = 90 s');
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends the keep-alive on its 20 s timer and on demand, as text', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = SoopDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.where((frame) => frame == SoopDanmakuProtocol.heartbeat).length >= 2);
          connection.heartbeat();
          await connection.close();
          final count = sent.length;
          connection.heartbeat();
          await _wait(const Duration(milliseconds: 20));
          expect(sent, hasLength(count), reason: 'nothing after close');
          expect(sent.every((frame) => frame is String), isTrue);
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            periods.add(period);
            return parent.createPeriodicTimer(zone, const Duration(milliseconds: 5), callback);
          },
        ),
      );
      expect(periods, [const Duration(seconds: 20)]);
    });

    test(
      'replaying the recording reports what 3.x decoded (with the sender, B-6), in order; text frames are ignored',
      () async {
        final connector = _Connector();
        final connection = SoopDanmakuConnection(connector: connector.call);
        final events = _record(connection);
        await connection.connect(_args);
        final channel = connector.channels.single..incoming.add(utf8.decode(_chat('as text')));
        for (final frame in _frames) {
          if (frame.dir == 'in') channel.incoming.add(frame.bytes);
        }
        await _until(() => _messages(events).length == 144);
        // B-6: 3.x's messages with the sender.
        expect(_messages(events).map(_project), _recordedB6WithoutFrames);
        await connection.close();
      },
    );

    test('where the TLS port drops the handshake, the plain port follows after 1 s, without the cookie', () async {
      final delays = <Duration>[];
      final connector = _Connector(refuse: {'wss'});
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await _until(() => connection.isConnected);
      });
      expect(
        delays.first,
        const Duration(seconds: 1),
        reason: 'two endpoints: the next one after 1 s × (0 rounds + 1)',
      );
      expect(connector.endpoints, [_args.url, _args.plainUrl]);
      expect(connector.headers.first['Cookie'], 'PdboxTicket=synthetic.ticket');
      expect(connector.headers.last, {
        for (final MapEntry(:key, :value) in SoopDanmakuProtocol.handshakeHeaders(_args.headers).entries)
          if (key != 'Cookie') key: value,
      });
      expect(connector.protocols.last, ['chat']);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await _until(() => connector.channels.single.sent.length == 2);
      expect(connector.channels.single.sent, [SoopDanmakuProtocol.login, _join]);
      await connection.close();
    });

    test("B-6: the socket takes soop's proxy route (3.x always dialled directly)", () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final proxied = SoopDanmakuConnection(
        proxy: const FixedProxyPolicy(perSite: {SiteIds.soop: route}),
        connector: connector.call,
      );
      await proxied.connect(_args);
      expect(connector.routes, [route]);
      await proxied.close();
      final other = SoopDanmakuConnection(
        proxy: const FixedProxyPolicy(perSite: {SiteIds.chzzk: route}),
        connector: connector.call,
      );
      await other.connect(_args);
      expect(connector.routes.last, const DirectRoute(), reason: 'another platform');
      await other.close();
      final unset = SoopDanmakuConnection(connector: connector.call);
      await unset.connect(_args);
      expect(connector.routes.last, const DirectRoute(), reason: 'no proxy given');
      await unset.close();
    });

    test(
      'B-6: through an HTTP proxy end to end: the TLS port refused, the plain port tunnelled without the cookie',
      () async {
        final server = await _ChatServer.start();
        server.onMessage = (server, socket, message) {
          if (message == _join) {
            for (final frame in _frames) {
              if (frame.dir == 'in') _ChatServer.send(socket, 2, frame.bytes);
            }
          }
        };
        final proxy = await _ConnectProxy.start(port: _args.plainUrl.port, upstream: server.port);
        final connection = SoopDanmakuConnection(
          proxy: FixedProxyPolicy(perSite: {SiteIds.soop: HttpProxyRoute('127.0.0.1', proxy.localPort)}),
        );
        final events = _record(connection);
        await connection.connect(_args);
        await _until(() => _messages(events).length == 144);
        final host = _args.url.host;
        expect(proxy.requests, [
          'CONNECT $host:${_args.url.port} HTTP/1.1\r\nHost: $host:${_args.url.port}',
          'CONNECT $host:${_args.plainUrl.port} HTTP/1.1\r\nHost: $host:${_args.plainUrl.port}',
        ]);
        final head = server.requests.single;
        expect(head, startsWith('GET /Websocket/${_keys['bj']} HTTP/1.1\r\nHost: $host:${_args.plainUrl.port}\r\n'));
        expect(head, contains('\r\nOrigin: https://play.sooplive.co.kr\r\n'));
        expect(head.toLowerCase(), isNot(contains('cookie')));
        expect(server.texts, [SoopDanmakuProtocol.login, _join]);
        expect(events.whereType<DanmakuReady>(), hasLength(1));
        expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
        expect(_messages(events).map(_project), _recordedB6WithoutFrames);
        await connection.close();
      },
    );

    test('a room whose CHIP names the chat host connects to chat-<hex>.sooplive.com (7-6)', () async {
      final args = SoopApi.danmakuArgs({
        'CHIP': '110.10.76.99',
        'CHPT': _keys['chatPort'],
        'CHATNO': _chatNo,
      }, roomId: _keys['bj']! as String)!;
      final connector = _Connector(refuse: {'wss'});
      final connection = SoopDanmakuConnection(connector: connector.call);
      await _fastBackoff([], () async {
        await connection.connect(args);
        await _until(() => connection.isConnected);
      });
      final recorded = [
        for (final handshake in _meta['handshakes']! as List<Object?>) (handshake! as Map<String, Object?>)['url'],
      ];
      expect(connector.endpoints.map((endpoint) => '$endpoint'), recorded);
      expect(connector.endpoints.first.host, endsWith('.sooplive.com'));
      await connection.close();
    });

    test('a dropped socket reconnects, logs in and joins again, and is ready again', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await _until(() => connector.channels.single.sent.length == 2);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connector.channels.last.sent.length == 2);
      });
      expect(connector.endpoints, [_args.url, _args.plainUrl]);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [SoopDanmakuProtocol.login, _join]);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('a join still pending when its socket is replaced is not sent to the new one', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      await _fastBackoff([], () async {
        await connection.connect(_args);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connector.channels.last.sent.length == 2);
        // Room for a second join: the first socket's timer would have sent
        // one to this socket before its own.
        await _wait(const Duration(milliseconds: 400));
      });
      expect(connector.channels.first.sent, [SoopDanmakuProtocol.login]);
      expect(connector.channels.last.sent, [SoopDanmakuProtocol.login, _join]);
      await connection.close();
    });

    test('reconnects alternate the two ports and wait 1, 2, 2, 3, 3, 4, 4, 5 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(refuse: {'wss', 'ws'});
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays, [
        for (final seconds in [1, 2, 2, 3, 3, 4, 4, 5]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, [
        for (var round = 0; round < 4; round++) ...[_args.url, _args.plainUrl],
        _args.url,
      ]);
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('Connection closed by peer')),
      );
      expect(events, hasLength(2));
      expect(connection.status, DanmakuStatus.closed);
    });

    test('close: no join, event, heartbeat or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming.add(_chat('after close'));
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 400));
      expect(channel.closed, isTrue);
      expect(channel.sent, [SoopDanmakuProtocol.login], reason: 'the join was still waiting');
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another room closes the first socket and joins the new room', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      final other = SoopApi.danmakuArgs({
        'CHDOMAIN': 'chat-01020304.sooplive.com',
        'CHPT': '8000',
        'CHATNO': '77',
      }, roomId: 'other')!;
      await connection.connect(_args);
      await connection.connect(other);
      expect(connector.endpoints, [_args.url, other.url]);
      expect(connector.channels.first.closed, isTrue);
      connector.channels.first.incoming.add(_chat('from the first room'));
      connector.channels.last.incoming.add(_chat('from the second room'));
      await _until(() => _messages(events).isNotEmpty && connector.channels.last.sent.length == 2);
      expect(_messages(events).map((message) => message.message), ['from the second room']);
      expect(connector.channels.first.sent, [SoopDanmakuProtocol.login]);
      expect(connector.channels.last.sent, [SoopDanmakuProtocol.login, SoopDanmakuProtocol.join('77')]);
      await connection.close();
    });

    test('a room without chat data ends with connectionFailed (3.x "服务器连接失败"); other types throw', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(null);
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No chat server')]);
      expect(connection.status, DanmakuStatus.closed);
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect(_chatNo), throwsArgumentError);
      await connection.connect(_args);
      expect(connection.isConnected, isTrue, reason: 'a later room connects');
      await connection.close();
    });

    test('registers in DanmakuRegistry under soop', () {
      final registry = DanmakuRegistry({SiteIds.soop: SoopDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.soop]);
      expect(registry.connectionFor(' SOOP '), isA<SoopDanmakuConnection>());
      expect(registry.connectionFor('douyu'), isA<EmptyDanmakuConnection>());
    });

    test('a local case-sensitive chat edge: the recorded session end to end', () async {
      final server = await _ChatServer.start();
      server.onMessage = (server, socket, message) {
        if (message == _join) {
          for (final frame in _frames) {
            if (frame.dir == 'in') _ChatServer.send(socket, 2, frame.bytes);
          }
        }
      };
      final endpoints = <Uri>[];
      final headers = <Map<String, String>>[];
      final connection = SoopDanmakuConnection(connector: _local(server, endpoints, headers));
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).length == 144);
      expect(endpoints, [_args.url]);
      expect(server.texts, [SoopDanmakuProtocol.login, _join]);
      final head = server.requests.single;
      expect(head, startsWith('GET /Websocket/${_keys['bj']} HTTP/1.1\r\nHost: 127.0.0.1:${server.port}\r\n'));
      for (final MapEntry(:key, :value) in SoopDanmakuProtocol.handshakeHeaders(_args.headers).entries) {
        expect(head, contains('\r\n$key: $value\r\n'));
      }
      // B-6: 3.x's messages with the sender.
      expect(_messages(events).map(_project), _recordedB6WithoutFrames);
      connection.heartbeat();
      await _until(() => server.texts.length == 3);
      expect(server.texts.last, SoopDanmakuProtocol.heartbeat);
      await connection.close();
      expect(events.whereType<DanmakuReady>(), hasLength(1));
    });
  });
}
