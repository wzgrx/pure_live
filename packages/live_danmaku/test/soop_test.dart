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

    test('decodes chat only: text, nick, white; no id, time or level (3.x)', () {
      final message = SoopDanmakuProtocol.decode(_chat(' 안녕 ', ' 시청자 ')).single;
      expect(_project(message), {
        'type': 'chat',
        'userName': '시청자',
        'userId': '',
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
    test('the 3586 incoming frames give the same 144 chat lines, in the same frames', () {
      final decoded = <Map<String, Object?>>[];
      for (var index = 0; index < _frames.length; index++) {
        final frame = _frames[index];
        if (frame.dir != 'in') continue;
        decoded.addAll([
          for (final message in SoopDanmakuProtocol.decode(frame.bytes)) {'frame': index, ..._project(message)},
        ]);
      }
      expect(decoded, hasLength(144));
      expect(decoded, _recordedMessages);
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

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        expect(SoopDanmakuProtocol.decode(_serverFrame(testCase)).map(_project).toList(), expected[name]);
      });
    }
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

    test('replaying the recording reports what 3.x decoded, in order; text frames are ignored', () async {
      final connector = _Connector();
      final connection = SoopDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single..incoming.add(utf8.decode(_chat('as text')));
      for (final frame in _frames) {
        if (frame.dir == 'in') channel.incoming.add(frame.bytes);
      }
      await _until(() => _messages(events).length == 144);
      expect(_messages(events).map(_project), _recordedWithoutFrames);
      await connection.close();
    });

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
      expect(_messages(events).map(_project), _recordedWithoutFrames);
      connection.heartbeat();
      await _until(() => server.texts.length == 3);
      expect(server.texts.last, SoopDanmakuProtocol.heartbeat);
      await connection.close();
      expect(events.whereType<DanmakuReady>(), hasLength(1));
    });
  });
}
