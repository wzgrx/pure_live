import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/bilibili/danmaku';

final Uri _gateway = Uri.parse(BilibiliApi.danmakuGateway);
final Uri _node = Uri.parse('wss://node.example:2245/sub');
const Map<String, String> _headers = {
  'user-agent': BilibiliApi.userAgent,
  'origin': 'https://live.bilibili.com',
  'referer': 'https://live.bilibili.com/5050',
  'cookie': 'buvid3=buvid-fixture',
};

/// A fake socket that records what the connection sends.
final class _Channel implements SocketChannel {
  new(this._connector);

  final _Connector _connector;
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Uint8List> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    final bytes = Uint8List.fromList(data as List<int>);
    sent.add(bytes);
    _connector.onSend?.call(bytes);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  /// Delivers [frame] and lets the connection handle it.
  Future<void> receive(List<int> frame) async {
    incoming.add(Uint8List.fromList(frame));
    await Future<void>.delayed(Duration.zero);
  }
}

/// Hands out fake sockets and records every handshake.
final class _Connector {
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<_Channel> channels = [];
  void Function(Uint8List bytes)? onSend;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    final channel = _Channel(this);
    channels.add(channel);
    return channel;
  }
}

/// Yields the digits of [hex] as `nextInt(16)`, then repeats them.
final class _Hex implements Random {
  new(this.hex);

  final String hex;
  int _next = 0;

  @override
  int nextInt(int max) => int.parse(hex[_next++ % hex.length], radix: 16);

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

/// No heartbeat and no join timer: only what the test sends happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

BilibiliDanmakuArgs _args({
  String token = 'token-1',
  List<Uri>? servers,
  Map<String, String> headers = _headers,
  Future<BilibiliDanmakuArgs> Function()? refresh,
}) => BilibiliDanmakuArgs(
  roomId: 5050,
  uid: 0,
  token: token,
  servers: servers ?? [_gateway, _node],
  buvid: 'buvid-fixture',
  headers: headers,
  refresh: refresh,
);

Uint8List _packet(int operation, List<int> body, {int version = 0}) {
  final bytes = Uint8List(16 + body.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, bytes.length)
    ..setUint16(4, 16)
    ..setUint16(6, version)
    ..setUint32(8, operation)
    ..setUint32(12, 1);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

Uint8List _auth(String body) => _packet(8, utf8.encode(body));

Uint8List _notice(Object? json, {int version = 0}) => _packet(5, utf8.encode(jsonEncode(json)), version: version);

Map<String, Object?> _danmu(String text) => {
  'cmd': 'DANMU_MSG',
  'info': [
    [0, 1, 25, 0xE33FFF, 1790519893202, 1790519804, 0, '8z3o13gj', 0, 0, 0, '', 0, '{}', '{}'],
    text,
    [1000, 'viewer'],
  ],
};

int _operation(List<int> packet) => ByteData.sublistView(Uint8List.fromList(packet)).getUint32(8);

Object? _body(List<int> packet) => jsonDecode(utf8.decode(packet.sublist(16)));

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

Iterable<String> _texts(List<DanmakuEvent> events) =>
    events.whereType<DanmakuReceived>().map((event) => event.message.message);

/// Waits until [condition] holds, at most two seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// The projection fixtures/bilibili/danmaku/legacy_expected.dart writes.
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'data': switch (message.data) {
    null => null,
    final LiveAudienceUpdate update => {'kind': update.kind.name, 'value': update.value},
    final LiveSuperChatMessage chat => {
      'messageId': chat.messageId,
      'userName': chat.userName,
      'face': chat.face,
      'message': chat.message,
      'price': chat.price,
      'startTime': chat.startTime.millisecondsSinceEpoch,
      'endTime': chat.endTime.millisecondsSinceEpoch,
      'backgroundColor': chat.backgroundColor,
      'backgroundBottomColor': chat.backgroundBottomColor,
    },
    final other => '$other',
  },
};

/// Replays received frames through a connection and records its effects in
/// order, as the generator recorded 3.x's: messages, packets sent, ready,
/// credential refreshes.
final class _Replay {
  new();

  final _Connector connector = _Connector();
  final List<Map<String, Object?>> effects = [];
  late final BilibiliDanmakuConnection connection = BilibiliDanmakuConnection(
    connector: connector.call,
    policy: _quiet,
    random: _Hex('e2f61841'),
  );

  Future<void> open(BilibiliDanmakuArgs args) async {
    connection.events.listen(
      (event) => effects.add(switch (event) {
        DanmakuReady() => {'ready': true},
        DanmakuReceived(:final message) => {'message': _project(message)},
        _ => {'event': '$event'},
      }),
    );
    connector.onSend = (bytes) => effects.add({'send': base64.encode(bytes)});
    await connection.connect(args);
  }

  BilibiliDanmakuArgs args({String token = 'token', String buvid = 'buvid'}) => BilibiliDanmakuArgs(
    roomId: 5050,
    uid: 0,
    token: token,
    servers: [_gateway],
    buvid: buvid,
    headers: _headers,
    refresh: () {
      effects.add({'refresh': true});
      return Completer<BilibiliDanmakuArgs>().future;
    },
  );

  /// The effects of receiving [frame].
  Future<List<Map<String, Object?>>> receive(List<int> frame) async {
    effects.clear();
    await connector.channels.last.receive(frame);
    return List.of(effects);
  }
}

/// 3.x's effects of one frame, without its log lines (the new decoder does
/// not log).
List<Object?> _expected(Map<String, dynamic> frame) => [
  for (final effect in frame['effects'] as List<dynamic>)
    if (!(effect as Map<String, dynamic>).containsKey('log')) effect,
];

List<Map<String, Object?>> _lines(String sample) => [
  for (final line in File('$_root/$sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, Object?>,
];

Map<String, dynamic> _expectedValue(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

void main() {
  group('protocol', () {
    test("client packets are 3.x's: big-endian header, version 0, sequence 1", () {
      final packet = BilibiliDanmakuProtocol.packet(7, 'abc');
      expect(packet.take(16), [0, 0, 0, 19, 0, 16, 0, 0, 0, 0, 0, 7, 0, 0, 0, 1]);
      expect(utf8.decode(packet.sublist(16)), 'abc');
      expect(base64.encode(BilibiliDanmakuProtocol.heartbeat()), 'AAAAEAAQAAAAAAACAAAAAQ==');
    });

    test('the auth packet: 3.x fields and order, protover 2, a fresh queue_uuid', () {
      final args = _args();
      final payload = BilibiliDanmakuProtocol.authPayload(args, queueUuid: '0a1b2c3d');
      expect(payload.keys, [
        'uid',
        'roomid',
        'protover',
        'buvid',
        'support_ack',
        'queue_uuid',
        'scene',
        'platform',
        'type',
        'key',
      ]);
      expect(payload, {
        'uid': 0,
        'roomid': 5050,
        'protover': 2,
        'buvid': 'buvid-fixture',
        'support_ack': true,
        'queue_uuid': '0a1b2c3d',
        'scene': 'room',
        'platform': 'web',
        'type': 2,
        'key': 'token-1',
      });
      final packet = BilibiliDanmakuProtocol.auth(args, queueUuid: '0a1b2c3d');
      expect(_operation(packet), 7);
      expect(_body(packet), payload);
      expect(BilibiliDanmakuProtocol.queueUuid(Random(1)), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(BilibiliDanmakuProtocol.queueUuid(_Hex('e2f61841')), 'e2f61841');
    });

    test('decode keeps what came before a fault and reports it', () {
      final zeroLength = Uint8List(16);
      ByteData.sublistView(zeroLength).setUint16(4, 16);
      final result = BilibiliDanmakuProtocol.decode([..._notice(_danmu('before')), ...zeroLength]);
      expect(result.items.map((item) => (item as BilibiliDanmakuMessage).message.message), ['before']);
      expect(result.error, isA<FormatException>());
      expect(BilibiliDanmakuProtocol.decode(_notice(_danmu('fine'))).error, isNull);
    });

    test('brotli packets (protover 3) are skipped, the rest of the message is decoded', () {
      final result = BilibiliDanmakuProtocol.decode([
        ..._packet(5, [0x1b, 0x03, 0x00], version: 3),
        ..._notice(_danmu('after brotli')),
      ]);
      expect(result.error, isNull);
      expect(result.items.map((item) => (item as BilibiliDanmakuMessage).message.message), ['after brotli']);
    });

    test("3.x's limits: message size, packet count, inflated size", () {
      final large = BilibiliDanmakuProtocol.decode(Uint8List(BilibiliDanmakuProtocol.maxMessageBytes + 1));
      expect(large.error?.message, contains('too large'));
      expect(large.items, isEmpty);

      final heartbeats = [for (var i = 0; i <= BilibiliDanmakuProtocol.maxPackets; i++) ..._packet(2, const [])];
      expect(BilibiliDanmakuProtocol.decode(heartbeats).error?.message, contains('too many packets'));
      final allowed = heartbeats.sublist(16);
      expect(BilibiliDanmakuProtocol.decode(allowed).error, isNull);

      final bomb = _packet(5, zlib.encode(Uint8List(BilibiliDanmakuProtocol.maxInflatedBytes + 1)), version: 2);
      final inflated = BilibiliDanmakuProtocol.decode([..._notice(_danmu('kept')), ...bomb]);
      expect(inflated.error?.message, contains('exceeds'));
      expect(inflated.items, hasLength(1));
    });

    test('masked names: two or more ASCII or full-width stars', () {
      expect(BilibiliDanmakuConnection.isMaskedName('观***'), isTrue);
      expect(BilibiliDanmakuConnection.isMaskedName('用＊＊'), isTrue);
      expect(BilibiliDanmakuConnection.isMaskedName('a*b*c'), isFalse);
      expect(BilibiliDanmakuConnection.isMaskedName('观众'), isFalse);
    });
  });

  group("3.x's frozen output", () {
    test('S13-live: the recorded handshake, then every received message as 3.x handled it', () async {
      final lines = _lines('S13-live');
      final recordedAuth = base64.decode(lines.first['b64']! as String);
      final auth = _body(recordedAuth)! as Map<String, dynamic>;
      final replay = _Replay();
      await replay.open(replay.args(token: auth['key'] as String, buvid: auth['buvid'] as String));
      expect(replay.connector.endpoints, [_gateway]);
      expect(replay.connector.headers.single, _headers);
      expect(replay.effects, [
        {'send': base64.encode(recordedAuth)},
      ], reason: 'the same bytes as the recorded auth packet');

      final frames = (_expectedValue('S13-live')['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
      final byLine = {for (final frame in frames) frame['line'] as int: frame};
      var messages = 0;
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line['dir'] != 'in' || line['b64'] == null) continue;
        final expected = byLine[index + 1];
        expect(expected, isNotNull, reason: 'line ${index + 1} has 3.x output');
        final effects = await replay.receive(base64.decode(line['b64']! as String));
        expect(effects, _expected(expected!), reason: 'line ${index + 1}');
        messages += effects.where((effect) => effect.containsKey('message')).length;
      }
      expect(byLine, hasLength(161));
      expect(messages, 57, reason: '44 chats, 11 watched counts, 2 heartbeat replies');
      expect(
        lines.where((line) => line['dir'] == 'out').skip(1).map((line) => line['b64']),
        everyElement(base64.encode(BilibiliDanmakuProtocol.heartbeat())),
        reason: 'the recorded heartbeats',
      );
      await replay.connection.close();
    });

    test('S13-vectors: every vector as 3.x handled it, except the intentional differences', () async {
      final lines = _lines('S13-vectors');
      final vectors = (_expectedValue('S13-vectors')['vectors'] as List<dynamic>).cast<Map<String, dynamic>>();
      // Intentional differences (docs/modules/M5.1-bilibili.md): M2's colour
      // fix, and super chats read like M4.1's snapshot.
      final differences = <String, Map<String, Object?> Function(Map<String, Object?> message)>{
        'chat-colors/blue': (message) => {...message, 'color': '#0000ff'},
        'chat-colors/five digits': (message) => {...message, 'color': '#0a0a0a'},
        'super-chat/0': (message) => {
          ...message,
          'data': {...message['data']! as Map<String, Object?>, 'messageId': '19298954'},
        },
        'super-chat/1': (message) => {
          ...message,
          'data': {
            ...message['data']! as Map<String, Object?>,
            'messageId': '19298954',
            'face': 'https://i0.hdslb.com/bfs/face/member/noface.jpg@200w.jpg',
          },
        },
      };
      final applied = <String>{};
      Object? adjust(String vector, int index, Object? effect) {
        if (effect is! Map<String, dynamic> || !effect.containsKey('message')) return effect;
        final message = effect['message'] as Map<String, dynamic>;
        final key = vector == 'super-chat' ? '$vector/$index' : '$vector/${message['message']}';
        final change = differences[key];
        if (change == null) return effect;
        applied.add(key);
        return {'message': change(message)};
      }

      for (final vector in vectors) {
        final name = vector['vector'] as String;
        final replay = _Replay();
        await replay.open(replay.args());
        replay.effects.clear();
        for (final frame in (vector['frames'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final line = lines[(frame['line'] as int) - 1];
          expect(line['vector'], name);
          final effects = await replay.receive(base64.decode(line['b64']! as String));
          var index = 0;
          final expected = [
            for (final effect in _expected(frame))
              adjust(name, (effect! as Map<String, dynamic>).containsKey('message') ? index++ : -1, effect),
          ];
          expect(effects, expected, reason: '$name, line ${frame['line']}');
        }
        await replay.connection.close();
      }
      expect(applied, differences.keys.toSet(), reason: 'every difference is still needed');
      expect(vectors, hasLength(28));
    });
  });

  group('connection', () {
    test("3.x's timing and the registry entry", () async {
      final connection = BilibiliDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 30));
      expect(BilibiliDanmakuConnection.defaultPolicy.joinTimeout, const Duration(seconds: 8));
      expect(BilibiliDanmakuConnection.defaultPolicy.inactivityTimeout, isNull, reason: 'max(3 × 30 s, 90 s)');
      expect(BilibiliDanmakuConnection.defaultPolicy.maxReconnects, 8);
      expect(connection.site, SiteIds.bilibili);
      final registry = DanmakuRegistry({SiteIds.bilibili: BilibiliDanmakuConnection.new});
      expect(registry.connectionFor('bilibili'), isA<BilibiliDanmakuConnection>());
      await expectLater(connection.connect('not bilibili args'), throwsArgumentError);
    });

    test("handshake: first endpoint with the credentials' headers, auth, ready only on the reply", () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet, random: _Hex('0a1b2c3d'));
      final events = _record(connection);
      await connection.connect(_args());
      expect(connector.endpoints, [_gateway]);
      expect(connector.headers.single, _headers);
      final channel = connector.channels.single;
      expect(channel.sent, [BilibiliDanmakuProtocol.auth(_args(), queueUuid: '0a1b2c3d')]);
      expect(connection.status, DanmakuStatus.connecting);

      await channel.receive(_notice(_danmu('before auth')));
      expect(_texts(events), ['before auth'], reason: '3.x reported messages before the auth reply too');
      expect(connection.isConnected, isFalse);

      await channel.receive(_auth('{"code":0}'));
      expect(channel.sent.skip(1).map(_operation), [2], reason: 'a heartbeat right after the auth reply');
      expect(events.last, const DanmakuReady());
      expect(connection.isConnected, isTrue);

      await channel.receive(_auth('{"code":0}'));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(channel.sent, hasLength(2));
      await connection.close();
    });

    test('without servers the general gateway is used', () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
      await connection.connect(_args(servers: const []));
      expect(connector.endpoints, [_gateway]);
      await connection.close();
    });

    test('heartbeats every interval, before the auth reply as well (3.x)', () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 10),
          inactivityTimeout: Duration(seconds: 5),
        ),
      );
      await connection.connect(_args());
      final channel = connector.channels.single;
      await _until(() => channel.sent.where((packet) => _operation(packet) == 2).length >= 2);
      expect(connection.isConnected, isFalse);
      expect(_operation(channel.sent.first), 7);
      await connection.close();
    });

    test('no auth reply within the join timeout: the next endpoint, a new auth', () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args());
      await _until(() => connector.channels.length == 2);
      expect(connector.endpoints, [_gateway, _node]);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent.map(_operation), [7]);
      await connector.channels.last.receive(_auth('{"code":0}'));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connector.channels, hasLength(2), reason: 'the reply stopped the join timer');
      await connection.close();
    });

    test('a dropped socket reconnects and joins again', () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args());
      await connector.channels.single.receive(_auth('{"code":0}'));
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connection.isConnected, isFalse);
      expect(connector.channels.last.sent.map(_operation), [7]);
      await connector.channels.last.receive(_auth('{"code":0}'));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('an acknowledgement is sent before the message is reported', () async {
      final connector = _Connector();
      final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
      final order = <String>[];
      connection.events.listen((event) => order.add('event'));
      connector.onSend = (bytes) => order.add('send ${_operation(bytes)}');
      await connection.connect(_args());
      order.clear();
      await connector.channels.single.receive(
        _notice({..._danmu('ack me'), 'msg_id': 'id-1', 'p_is_ack': true, 'p_msg_type': 1}),
      );
      expect(order, ['send 24', 'event']);
      expect(_body(connector.channels.single.sent.last), {'msg_id': 'id-1', 'cmd': 'DANMU_MSG', 'p_msg_type': 1});
      await connection.close();
    });

    group('credentials', () {
      test('a start without a token refreshes first: three attempts, 1× and 2× the step apart', () async {
        final connector = _Connector();
        // A monotonic clock, as timers use; wall time can step backwards.
        final clock = Stopwatch()..start();
        final calls = <Duration>[];
        final refreshed = _args(token: 'token-2', servers: [_node], headers: const {'cookie': 'fresh'});
        final answers = <FutureOr<BilibiliDanmakuArgs> Function()>[
          () => _args(token: ''),
          () => throw const NetworkFailure(SiteIds.bilibili, 'offline'),
          () => refreshed,
        ];
        final connection = BilibiliDanmakuConnection(
          connector: connector.call,
          policy: _quiet,
          credentialRetryDelay: const Duration(milliseconds: 20),
        );
        await connection.connect(
          _args(
            token: '',
            refresh: () async {
              calls.add(clock.elapsed);
              return await answers[calls.length - 1]();
            },
          ),
        );
        expect(calls, hasLength(3));
        // 1 ms of slack for timer granularity.
        expect(calls[1] - calls[0], greaterThanOrEqualTo(const Duration(milliseconds: 19)));
        expect(calls[2] - calls[1], greaterThanOrEqualTo(const Duration(milliseconds: 39)));
        expect(connector.endpoints, [_node]);
        expect(connector.headers.single, {'cookie': 'fresh'});
        expect((_body(connector.channels.single.sent.single)! as Map)['key'], 'token-2');
        await connection.close();
      });

      test('still no token: closed as unavailable without opening a socket (3.x)', () async {
        final connector = _Connector();
        var calls = 0;
        final connection = BilibiliDanmakuConnection(
          connector: connector.call,
          policy: _quiet,
          credentialRetryDelay: const Duration(milliseconds: 1),
        );
        final events = _record(connection);
        await connection.connect(
          _args(
            token: '',
            refresh: () async {
              calls++;
              return _args(token: '');
            },
          ),
        );
        expect(calls, 3);
        expect(events, [const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable, detail: 'No token')]);
        expect(connection.status, DanmakuStatus.closed);
        expect(connector.endpoints, isEmpty);

        await connection.connect(_args(token: ''));
        expect(events.last, const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable, detail: 'No token'));
        expect(connector.endpoints, isEmpty, reason: 'without a refresh function as well');
      });

      test('close during the start stops the refreshes', () async {
        final connector = _Connector();
        var calls = 0;
        final connection = BilibiliDanmakuConnection(
          connector: connector.call,
          policy: _quiet,
          credentialRetryDelay: const Duration(seconds: 5),
        );
        final events = _record(connection);
        final connecting = connection.connect(
          _args(
            token: '',
            refresh: () async {
              calls++;
              return _args(token: '');
            },
          ),
        );
        await _until(() => calls == 1);
        await connection.close();
        await connecting.timeout(const Duration(milliseconds: 200));
        expect(calls, 1);
        expect(events, isEmpty);
        expect(connector.endpoints, isEmpty);
      });

      test('a rejected auth refreshes the credentials and reopens with them, without a notice', () async {
        final connector = _Connector();
        final refresh = Completer<BilibiliDanmakuArgs>();
        var calls = 0;
        final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(
          _args(
            refresh: () {
              calls++;
              return refresh.future;
            },
          ),
        );
        final first = connector.channels.single;
        await first.receive(_auth('{"code":0}'));
        expect(connection.isConnected, isTrue);

        await first.receive(_auth('{"code":-101}'));
        expect(calls, 1);
        expect(connection.isConnected, isFalse);
        expect(connection.status, DanmakuStatus.connecting);
        await first.receive(_auth('{"code":-101}'));
        expect(calls, 1, reason: 'a refresh is already running');

        refresh.complete(_args(token: 'token-2', servers: [_node]));
        await _until(() => connector.channels.length == 2);
        expect(first.closed, isTrue);
        expect(connector.endpoints.last, _node);
        final second = connector.channels.last;
        expect((_body(second.sent.single)! as Map)['key'], 'token-2');
        await second.receive(_auth('{"code":0}'));
        expect(events, [const DanmakuReady(), const DanmakuReady()]);
        await connection.close();
      });

      test('no new credentials after a rejection: closed as unavailable (3.x kept the rejected socket)', () async {
        final connector = _Connector();
        final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(_args(refresh: () async => throw const NetworkFailure(SiteIds.bilibili, 'offline')));
        await connector.channels.single.receive(_auth('{"code":-101}'));
        await _until(() => events.isNotEmpty);
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable, detail: 'Auth rejected (code -101)'),
        ]);
        expect(connector.channels.single.closed, isTrue);
        expect(connection.status, DanmakuStatus.closed);

        await connection.connect(_args(refresh: () async => _args(token: '')));
        await connector.channels.last.receive(_auth('{"code":-352}'));
        await _until(() => events.length == 2);
        expect(
          events.last,
          const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable, detail: 'Auth rejected (code -352)'),
        );
      });

      test('at most three refreshes per connect; the next rejection ends it', () async {
        final connector = _Connector();
        var calls = 0;
        final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
        final events = _record(connection);
        late BilibiliDanmakuArgs Function() fresh;
        fresh = () => _args(token: 'token-${++calls + 1}', refresh: () async => fresh());
        await connection.connect(_args(refresh: () async => fresh()));
        for (var round = 1; round <= 3; round++) {
          await connector.channels.last.receive(_auth('{"code":-101}'));
          await _until(() => connector.channels.length == round + 1);
          expect((_body(connector.channels.last.sent.single)! as Map)['key'], 'token-${round + 1}');
        }
        await connector.channels.last.receive(_auth('{"code":-101}'));
        await _until(() => events.isNotEmpty);
        expect(calls, 3);
        expect(events.single, isA<DanmakuClosed>());
        expect(connector.channels, hasLength(4));
      });

      test('after close or another connect, a pending refresh does nothing', () async {
        final connector = _Connector();
        final refresh = Completer<BilibiliDanmakuArgs>();
        final connection = BilibiliDanmakuConnection(connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(_args(refresh: () => refresh.future));
        await connector.channels.single.receive(_auth('{"code":-101}'));
        await connection.connect(_args(token: 'room-2', servers: [_node]));
        refresh.complete(_args(token: 'stale', servers: [Uri.parse('wss://stale.example/sub')]));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connector.endpoints, [_gateway, _node]);
        expect((_body(connector.channels.last.sent.single)! as Map)['key'], 'room-2');
        await connection.close();

        final late = Completer<BilibiliDanmakuArgs>();
        await connection.connect(_args(refresh: () => late.future));
        await connector.channels.last.receive(_auth('{"code":-101}'));
        await connection.close();
        late.complete(_args(token: 'stale'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connector.channels, hasLength(3));
        expect(events, isEmpty);
        expect(connection.status, DanmakuStatus.idle);
      });
    });

    test('a real WebSocket server: auth, reply, zlib notice, heartbeat', () async {
      final operations = <int>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          final packet = frame as List<int>;
          operations.add(_operation(packet));
          if (_operation(packet) == 7) {
            socket
              ..add(_auth('{"code":0}'))
              ..add(_packet(5, zlib.encode([..._notice(_danmu('弹幕')), ..._notice(_danmu('第二条'))]), version: 2));
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final connection = BilibiliDanmakuConnection(
        policy: const DanmakuSocketPolicy(heartbeatInterval: Duration(milliseconds: 20)),
      );
      final events = _record(connection);
      await connection.connect(_args(servers: [Uri.parse('ws://127.0.0.1:${server.port}/sub')], headers: const {}));
      await _until(() => _texts(events).length == 2 && operations.where((operation) => operation == 2).length >= 2);
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['弹幕', '第二条']);
      expect(operations.take(2), [7, 2]);
      await connection.close();
    });
  });
}
