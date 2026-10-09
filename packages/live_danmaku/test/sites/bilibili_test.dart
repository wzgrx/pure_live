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

/// A brotli stream of [data] in uncompressed meta-blocks of at most [block]
/// bytes (RFC 7932 section 9.2), as fixtures/bilibili/danmaku/legacy_expected.dart
/// writes them: the smallest valid encoder.
Uint8List _brotliStream(List<int> data, {int block = 65536}) {
  final out = BytesBuilder();
  var bits = 0;
  var count = 0;
  void put(int value, int width) {
    bits |= value << count;
    count += width;
    while (count >= 8) {
      out.addByte(bits & 0xff);
      bits >>= 8;
      count -= 8;
    }
  }

  void align() {
    if (count > 0) put(0, 8 - count);
  }

  put(0, 1);
  for (var offset = 0; offset < data.length; offset += block) {
    final end = min(offset + block, data.length);
    put(0, 1);
    put(0, 2);
    put(end - offset - 1, 16);
    put(1, 1);
    align();
    out.add(data.sublist(offset, end));
  }
  put(1, 1);
  put(1, 1);
  align();
  return out.takeBytes();
}

/// A protover 3 notice holding [inner] (a packet stream).
Uint8List _brotli(List<int> inner, {int block = 65536}) => _packet(5, _brotliStream(inner, block: block), version: 3);

Iterable<String> _decoded(List<int> message) =>
    BilibiliDanmakuProtocol.decode(message).items
        .whereType<BilibiliDanmakuMessage>()
        .map((item) => item.message.message);

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
  new({this.queueUuid = 'e2f61841'});

  /// The auth packet's `queue_uuid`, as recorded.
  final String queueUuid;
  final _Connector connector = _Connector();
  final List<Map<String, Object?>> effects = [];
  late final BilibiliDanmakuConnection connection = BilibiliDanmakuConnection(
    connector: connector.call,
    policy: _quiet,
    random: _Hex(queueUuid),
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

  BilibiliDanmakuArgs args({String token = 'token', String buvid = 'buvid', int roomId = 5050}) => BilibiliDanmakuArgs(
    roomId: roomId,
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

/// Replays a recording's received messages through a new connection that
/// uses the recorded credentials and `queue_uuid`: the auth packet it sent,
/// and the effects of each received line (1-based).
Future<({Uint8List auth, Map<int, List<Map<String, Object?>>> effects})> _replayRecording(String sample) async {
  final lines = _lines(sample);
  final recorded = _body(base64.decode(lines.first['b64']! as String))! as Map<String, dynamic>;
  final replay = _Replay(queueUuid: recorded['queue_uuid'] as String);
  await replay.open(
    replay.args(
      token: recorded['key'] as String,
      buvid: recorded['buvid'] as String,
      roomId: recorded['roomid'] as int,
    ),
  );
  final auth = base64.decode(replay.effects.single['send']! as String);
  final effects = <int, List<Map<String, Object?>>>{};
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in' || line['b64'] == null) continue;
    effects[index + 1] = await replay.receive(base64.decode(line['b64']! as String));
  }
  await replay.connection.close();
  return (auth: auth, effects: effects);
}

/// The protocol versions of the packets at the top of [message].
List<int> _versions(List<int> message) {
  final view = ByteData.sublistView(Uint8List.fromList(message));
  return [
    for (var offset = 0; offset + 16 <= message.length; offset += view.getUint32(offset)) view.getUint16(offset + 6),
  ];
}

/// Every notice's JSON text in [message], compressed packets unpacked.
List<String> _notices(List<int> message) {
  final data = Uint8List.fromList(message);
  final view = ByteData.sublistView(data);
  final texts = <String>[];
  for (var offset = 0; offset + 16 <= data.length; offset += view.getUint32(offset)) {
    if (view.getUint32(offset + 8) != 5) continue;
    final body = data.sublist(offset + view.getUint16(offset + 4), offset + view.getUint32(offset));
    texts.addAll(switch (view.getUint16(offset + 6)) {
      2 => _notices(zlib.decode(body)),
      3 => _notices(brotliDecode(body)),
      _ => [utf8.decode(body)],
    });
  }
  return texts;
}

Map<String, dynamic> _expectedValue(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

/// Whether [effect] reports online viewers: `ONLINE_RANK_COUNT`, which 3.x
/// ignored (M4.D2, appendix C-1).
bool _isOnlineViewers(Map<String, Object?> effect) => switch (effect) {
  {'message': {'type': 'online', 'data': {'kind': 'onlineViewers'}}} => true,
  _ => false,
};

/// [effects] as 3.x had them: without the online viewers (C-1), and
/// without what B06 added to chats ([_withoutB06]).
List<Map<String, Object?>> _as3x(List<Map<String, Object?>> effects) => [
  for (final effect in effects)
    if (!_isOnlineViewers(effect)) _withoutB06(effect),
];

/// [effect] without what task B06 added to a chat, which 3.x did not read:
/// the fan badge (`fansName`, `fansLevel`) and the avatar (`data`, a
/// [DanmakuSender]). The B06 tests check them.
Map<String, Object?> _withoutB06(Map<String, Object?> effect) => switch (effect) {
  {'message': final Map<String, Object?> message} when message['type'] == 'chat' => {
    'message': {...message, 'fansName': '', 'fansLevel': '', 'data': null},
  },
  _ => effect,
};

/// The online viewers [effects] report (C-1).
List<Object?> _onlineViewers(Iterable<Map<String, Object?>> effects) => [
  for (final effect in effects)
    if (_isOnlineViewers(effect)) ((effect['message']! as Map)['data']! as Map)['value'],
];

void main() {
  group('protocol', () {
    test("client packets are 3.x's: big-endian header, version 0, sequence 1", () {
      final packet = BilibiliDanmakuProtocol.packet(7, 'abc');
      expect(packet.take(16), [0, 0, 0, 19, 0, 16, 0, 0, 0, 0, 0, 7, 0, 0, 0, 1]);
      expect(utf8.decode(packet.sublist(16)), 'abc');
      expect(base64.encode(BilibiliDanmakuProtocol.heartbeat()), 'AAAAEAAQAAAAAAACAAAAAQ==');
    });

    test('the auth packet: 3.x fields and order, protover 3 (B-3), a fresh queue_uuid', () {
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
        // B-3: brotli, as 3.x and the web player; M5.1 asked for 2 (zlib).
        'protover': 3,
        'buvid': 'buvid-fixture',
        'support_ack': true,
        'queue_uuid': '0a1b2c3d',
        'scene': 'room',
        'platform': 'web',
        'type': 2,
        'key': 'token-1',
      });
      expect(BilibiliDanmakuProtocol.protocolVersion, 3);
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

    test('B-3: brotli packets (protover 3) are decoded like zlib ones, nested and next to other packets', () {
      final stream = [..._notice(_danmu('first')), ..._notice(_danmu('second'))];
      expect(_decoded(_brotli(stream)), ['first', 'second']);
      expect(_decoded(_brotli(stream, block: 5)), ['first', 'second'], reason: 'meta-blocks split the packets');
      expect(_decoded([..._brotli(_notice(_danmu('compressed'))), ..._notice(_danmu('plain'))]), [
        'compressed',
        'plain',
      ]);
      expect(_decoded(_brotli(_packet(5, zlib.encode(_notice(_danmu('zlib inside'))), version: 2))), ['zlib inside']);
      expect(_decoded(_packet(5, zlib.encode(_brotli(_notice(_danmu('brotli inside')))), version: 2)), [
        'brotli inside',
      ]);
      final empty = BilibiliDanmakuProtocol.decode([..._brotli(const []), ..._notice(_danmu('after empty'))]);
      expect(empty.error, isNull);
      expect(empty.items, hasLength(1));
      final ack = BilibiliDanmakuProtocol.decode(
        _brotli(_notice({..._danmu('ack me'), 'msg_id': 'id-1', 'p_is_ack': true, 'p_msg_type': 1})),
      ).items;
      expect(ack.first, isA<BilibiliDanmakuAck>());
      expect(_body((ack.first as BilibiliDanmakuAck).packet), {'msg_id': 'id-1', 'cmd': 'DANMU_MSG', 'p_msg_type': 1});
      expect((ack.last as BilibiliDanmakuMessage).message.message, 'ack me');
    });

    test('B-3: a bad brotli packet ends its message: what came before is kept, the fault is returned', () {
      final valid = _brotliStream(_notice(_danmu('lost')));
      final bad = {
        'corrupt': [1, 2, 3, 4, 5],
        'truncated': valid.sublist(0, valid.length - 2),
        'trailing bytes': [...valid, 0],
        'not a packet stream': _brotliStream(utf8.encode('{"cmd":"DANMU_MSG"}')),
      };
      for (final MapEntry(key: name, value: body) in bad.entries) {
        final result = BilibiliDanmakuProtocol.decode([
          ..._notice(_danmu('before')),
          ..._packet(5, body, version: 3),
          ..._notice(_danmu('after')),
        ]);
        expect(result.items.map((item) => (item as BilibiliDanmakuMessage).message.message), ['before'], reason: name);
        expect(result.error, isA<FormatException>(), reason: name);
      }
      expect(_decoded(_notice(_danmu('next message'))), ['next message'], reason: 'nothing is carried over');

      final tooDeep = BilibiliDanmakuProtocol.decode(_brotli(_brotli(_brotli(_notice(_danmu('too deep'))))));
      expect(tooDeep.error?.message, contains('nesting'));
      expect(_decoded(_brotli(_brotli(_notice(_danmu('two levels'))))), ['two levels']);
    });

    test('B-3: brotli output is limited like zlib output', () {
      // The reference encoder's streams of 16 MiB + 1 and 16 MiB zero bytes.
      final bomb = _packet(5, base64.decode('y///P/gnAOKxQCD3/o///3/wTwDEYRGA7v0fAAACAAM='), version: 3);
      final result = BilibiliDanmakuProtocol.decode([..._notice(_danmu('kept')), ...bomb]);
      expect(result.error?.message, contains('limit of ${BilibiliDanmakuProtocol.maxInflatedBytes} bytes'));
      expect(result.items, hasLength(1));
      final full = _packet(5, base64.decode('y///P/gnAOKxQCD3/o///3/wTwDEYRGA7v3f'), version: 3);
      expect(
        BilibiliDanmakuProtocol.decode(full).error?.message,
        startsWith('Invalid Bilibili danmaku frame'),
        reason: 'inflated in full: its zero bytes are no packet',
      );
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

    group('B06: names, fan badges and avatars', () {
      List<LiveMessage> chats(Object? notice) => [
        for (final item in BilibiliDanmakuProtocol.decode(_notice(notice)).items)
          if (item case BilibiliDanmakuMessage(:final message) when message.type == LiveMessageType.chat) message,
      ];

      /// Every `DANMU_MSG` of [sample] as the server sent it.
      List<Map<String, dynamic>> recorded(String sample) => [
        for (final line in _lines(sample))
          if (line['dir'] == 'in' && line['b64'] != null)
            for (final text in _notices(base64.decode(line['b64']! as String)))
              if (jsonDecode(text) case final Map<String, dynamic> notice when notice['cmd'] == 'DANMU_MSG') notice,
      ];

      test('a guest (uid 0) gets every name masked, in every field; the fan badge and the avatar are not', () {
        for (final (sample, count) in [('S13-protover2-paired', 66), ('S13-live', 44)]) {
          final notices = recorded(sample);
          expect(notices, hasLength(count), reason: sample);
          var badges = 0;
          var avatars = 0;
          for (final notice in notices) {
            final info = notice['info'] as List<dynamic>;
            final user = ((info[0] as List<dynamic>)[15] as Map<String, dynamic>)['user'] as Map<String, dynamic>;
            final base = user['base'] as Map<String, dynamic>;
            // Every place a name could come from is masked, and nothing
            // else names the sender: the server masks by connection.
            final names = [(info[2] as List<dynamic>)[1], base['name'], (base['origin_info'] as Map)['name']];
            expect(names.every((name) => BilibiliDanmakuProtocol.isMaskedName('$name')), isTrue, reason: '$names');
            expect((info[2] as List<dynamic>)[0], 0);
            expect(user['uid'], 0);
            expect(notice['dm_v2'], '');
            expect(notice.keys.toSet(), {'cmd', 'info', 'dm_v2'}, reason: 'no top-level uinfo or data');

            final message = chats(notice).single;
            expect(BilibiliDanmakuProtocol.isMaskedName(message.userName), isTrue);
            final medal = user['medal'];
            if (medal is Map) {
              badges++;
              expect((message.fansName, message.fansLevel), (medal['name'], '${medal['level']}'));
              expect(message.fansName, (info[3] as List<dynamic>)[1], reason: 'info[3] says the same');
            } else {
              expect((message.fansName, message.fansLevel), ('', ''));
              expect(info[3], isEmpty);
            }
            // S13-live's recorder scrambled the addresses (not http), so
            // they give no avatar.
            final face = '${base['face']}'.replaceFirst('http://', 'https://');
            expect(message.data, face.startsWith('https://') ? DanmakuSender(avatar: '$face@96w_96h.jpg') : isNull);
            if (face.startsWith('https://')) avatars++;
          }
          expect(badges, count - (sample == 'S13-live' ? 3 : 5), reason: sample);
          expect(avatars, sample == 'S13-live' ? 0 : count, reason: sample);
        }
      });

      test('c3: a logged-in chat (shaped like the recording) gives the full name and the uid', () {
        final notice = jsonDecode(jsonEncode(recorded('S13-protover2-paired').first)) as Map<String, dynamic>;
        final info = notice['info'] as List<dynamic>;
        final user = ((info[0] as List<dynamic>)[15] as Map<String, dynamic>)['user'] as Map<String, dynamic>;
        final base = user['base'] as Map<String, dynamic>;
        // What a logged-in connection gets instead of the guest's 观***.
        info[2] = [12345, '小路的观众'];
        user['uid'] = 12345;
        base['name'] = '小路的观众';
        (base['origin_info'] as Map<String, dynamic>)['name'] = '小路的观众';
        final message = chats(notice).single;
        expect((message.userName, message.userId, message.message), ('小路的观众', '12345', '我吗'));
        expect((message.fansName, message.fansLevel), ('小路泥', '22'));

        // The rich name wins over info[2][1]; a masked one is passed over.
        base['name'] = '新名字';
        expect(chats(notice).single.userName, '新名字');
        base['name'] = '小***';
        (base['origin_info'] as Map<String, dynamic>)['name'] = '小***';
        expect(chats(notice).single.userName, '小路的观众', reason: 'info[2][1] unmasked');
      });

      test('the fan badge: user.medal, else info[3]; no name, no badge; a level of 0 is left out', () {
        Map<String, Object?> chat({Object? medal, List<Object?> legacy = const [], Object? face}) => {
          'cmd': 'DANMU_MSG',
          'info': [
            [
              0, 1, 25, 0xFFFFFF, 1790519893202, 1790519804, 0, '8z3o13gj', 0, 0, 0, '', 0, '{}', '{}', //
              {
                'user': {
                  'base': {'name': '观众', 'face': ?face},
                  'medal': medal,
                },
              },
            ],
            '你好',
            [1000, '观众'],
            legacy,
          ],
        };
        LiveMessage one(Map<String, Object?> notice) => chats(notice).single;
        expect(one(chat(medal: {'name': ' 小路泥 ', 'level': 22})).fansName, '小路泥');
        expect(one(chat(medal: {'name': '小路泥', 'level': '7'})).fansLevel, '7');
        expect(one(chat(medal: {'name': '小路泥', 'level': 0})).fansLevel, '');
        expect(one(chat(legacy: [21, '大母鹅', '主播', 433351])).fansName, '大母鹅');
        expect(one(chat(legacy: [21, '大母鹅'])).fansLevel, '21');
        expect(one(chat(medal: {'name': '', 'level': 3}, legacy: [21, '大母鹅'])).fansName, '大母鹅');
        expect(one(chat(medal: {'name': 5, 'level': 3})).fansName, '', reason: 'not text');
        expect((one(chat()).fansName, one(chat()).fansLevel), ('', ''));
        expect(one(chat(legacy: [0, ''])).fansName, '');
        // The old shape (rich user as JSON text, no medal) and none at all.
        expect(one(_danmu('旧')).fansName, '');
        expect(one(_danmu('旧')).data, isNull);
      });

      test('the avatar: user.base.face (else origin_info.face), https, 96 × 96 on hdslb.com', () {
        Map<String, Object?> chat(Object? base) => {
          'cmd': 'DANMU_MSG',
          'info': [
            [0, 1, 25, 0xFFFFFF, 1790519893202, 1790519804, 0, '8z3o13gj', 0, 0, 0, '', 0, '{}', '{}', base],
            '你好',
            [1000, '观众'],
          ],
        };
        Object? avatar(Object? rich) => chats(chat(rich)).single.data;
        expect(
          avatar({
            'user': {
              'base': {'face': 'http://i0.hdslb.com/bfs/face/a.jpg'},
            },
          }),
          const DanmakuSender(avatar: 'https://i0.hdslb.com/bfs/face/a.jpg@96w_96h.jpg'),
        );
        expect(
          avatar({
            'user': {
              'base': {
                'face': '',
                'origin_info': {'face': 'https://i1.hdslb.com/bfs/face/b.png'},
              },
            },
          }),
          const DanmakuSender(avatar: 'https://i1.hdslb.com/bfs/face/b.png@96w_96h.jpg'),
        );
        expect(
          avatar(
            jsonEncode({
              'user': {
                'base': {'face': 'https://i0.hdslb.com/bfs/face/c.jpg@40w.jpg'},
              },
            }),
          ),
          const DanmakuSender(avatar: 'https://i0.hdslb.com/bfs/face/c.jpg@40w.jpg'),
          reason: 'JSON text; an address already sized is kept',
        );
        expect(
          avatar({
            'user': {
              'base': {'face': 'https://cdn.example/d.jpg'},
            },
          }),
          const DanmakuSender(avatar: 'https://cdn.example/d.jpg'),
        );
        expect(
          avatar({
            'user': {
              'base': {'face': 'javascript:alert(1)'},
            },
          }),
          isNull,
        );
        expect(avatar(null), isNull);
      });
    });

    group('M4.D', () {
      List<LiveMessage> messages(Object? notice) => [
        for (final item in BilibiliDanmakuProtocol.decode(_notice(notice)).items)
          if (item case BilibiliDanmakuMessage(:final message)) message,
      ];

      test('a super chat carries its id; SUPER_CHAT_MESSAGE_DELETE takes each listed id back', () {
        final chat = messages({
          'cmd': 'SUPER_CHAT_MESSAGE',
          'data': {
            'id': 19298954,
            'message': 'hi',
            'price': 30,
            'start_time': 1790781481,
            'end_time': 1790781541,
            'user_info': {'uname': '观众', 'face': ''},
          },
        }).single;
        expect(chat.messageId, '19298954');
        expect((chat.data! as LiveSuperChatMessage).messageId, '19298954');

        final deleted = messages({
          'cmd': 'SUPER_CHAT_MESSAGE_DELETE',
          'data': {
            'ids': [19298954, '19298955', null],
          },
          'roomid': 5050,
        });
        expect([for (final message in deleted) message.type], [LiveMessageType.retraction, LiveMessageType.retraction]);
        expect(
          [for (final message in deleted) message.data],
          [const LiveRetraction.message('19298954'), const LiveRetraction.message('19298955')],
        );
        expect(deleted.first.messageId, isEmpty);
        expect(messages({'cmd': 'SUPER_CHAT_MESSAGE_DELETE', 'data': <String, Object?>{}}), isEmpty);
      });

      test("RECALL_DANMU_MSG: type 2 takes back a user's chats, 3 the whole chat; uid 0 and other types nothing", () {
        Object? recall(Map<String, Object?> data) {
          final result = messages({'cmd': 'RECALL_DANMU_MSG', 'data': data});
          expect(result.every((message) => message.type == LiveMessageType.retraction), isTrue);
          return result.isEmpty ? null : result.single.data;
        }

        expect(
          recall({
            'recall_type': 2,
            'target_id': 1,
            'uinfo': {'uid': 12345},
          }),
          const LiveRetraction.user('12345'),
        );
        expect(recall({'recall_type': 2, 'target_id': 678}), const LiveRetraction.user('678'));
        expect(recall({'recall_type': 3}), const LiveRetraction.all());
        expect(recall({'recall_type': 2, 'target_id': 0}), isNull, reason: 'guests see every uid as 0');
        expect(recall({'recall_type': 1, 'target_id': 678}), isNull);
        expect(recall({'recall_type': 0}), isNull);
      });

      test('WARNING and CUT_OFF are system notices with the reason', () {
        final warning = messages({'cmd': 'WARNING', 'msg': '违反直播规范', 'roomid': 5050}).single;
        expect(warning.type, LiveMessageType.notice);
        expect(warning.data, LiveNoticeKind.system);
        expect(warning.message, '直播间收到警告：违反直播规范');
        expect(messages({'cmd': 'CUT_OFF', 'msg': ' ', 'roomid': 5050}).single.message, '直播被切断');
      });
    });

    group('M4.D2', () {
      List<LiveMessage> messages(Object? notice) => [
        for (final item in BilibiliDanmakuProtocol.decode(_notice(notice)).items)
          if (item case BilibiliDanmakuMessage(:final message)) message,
      ];

      test('C-1: ONLINE_RANK_COUNT is the online viewers: online_count, else count', () {
        Object? online(Map<String, Object?> data) {
          final result = messages({'cmd': 'ONLINE_RANK_COUNT', 'data': data});
          if (result.isEmpty) return null;
          final update = result.single.data! as LiveAudienceUpdate;
          expect(result.single.type, LiveMessageType.online);
          expect(update.kind, LiveAudienceMetricKind.onlineViewers);
          return update.value;
        }

        // As recorded (545068, 2026-10-01).
        expect(online({'count': 1738, 'count_text': '1738', 'online_count': 1739, 'online_count_text': '1739'}), 1739);
        expect(online({'count': '42'}), 42);
        expect(online({'count': -1}), isNull);
        expect(online({}), isNull);
      });

      test('C-2: SEND_GIFT, COMBO_SEND and GUARD_BUY are gifts holding a BilibiliGift', () {
        final gift = messages({
          'cmd': 'SEND_GIFT',
          'data': {
            'giftName': '小心心',
            'giftId': 30607,
            'num': 3,
            'uname': '观众',
            'uid': 1,
            'coin_type': 'gold',
            'total_coin': 3000,
            'tid': '1790814397120300001',
            'timestamp': 1790814397,
            'batch_combo_id': 'batch:gift:combo_id:1',
          },
        }).single;
        expect(gift.type, LiveMessageType.gift);
        expect((gift.userName, gift.userId, gift.message), ('观众', '1', '小心心 ×3'));
        expect(gift.messageId, 'bilibili:gift:1790814397120300001');
        expect(gift.sentAt, DateTime.fromMillisecondsSinceEpoch(1790814397000));
        expect(
          gift.data,
          const BilibiliGift(id: '30607', name: '小心心', count: 3, goldCoins: 3000, comboId: 'batch:gift:combo_id:1'),
        );
        // E05.5: the shared gift.
        final shared = gift.gift!;
        expect(
          (shared.kind, shared.comboKey, shared.totalValue, shared.unit, shared.free, shared.tier),
          (LiveGiftKind.gift, 'batch:gift:combo_id:1', 3000, LiveGiftUnit.goldSeed, false, LiveGiftTier.normal),
        );
        final silver = messages({
          'cmd': 'SEND_GIFT',
          'data': {'giftName': '辣条', 'num': 0, 'coin_type': 'silver', 'total_coin': 100},
        }).single;
        expect(silver.data, const BilibiliGift(id: '', name: '辣条', count: 1, free: true));
        expect(silver.gift?.totalValue, isNull, reason: 'silver seeds are not kept');

        final combo = messages({
          'cmd': 'COMBO_SEND',
          'data': {
            'gift_name': '小心心',
            'gift_id': 30607,
            'total_num': 20,
            'combo_total_coin': 20000,
            'uname': '观众',
            'uid': 1,
            'batch_combo_id': 'batch:gift:combo_id:1',
          },
        }).single;
        expect(combo.message, '小心心 ×20');
        expect(combo.messageId, isEmpty);
        expect((combo.data! as BilibiliGift).goldCoins, 20000);
        expect((combo.gift?.free, combo.gift?.tier), (false, LiveGiftTier.valuable), reason: '20 yuan');

        // As recorded (1775719573, 2026-10-01), with a synthetic user.
        final guard = messages({
          'cmd': 'GUARD_BUY',
          'data': {
            'uid': 1000001,
            'username': '观众',
            'guard_level': 3,
            'num': 1,
            'price': 198000,
            'gift_id': 10003,
            'gift_name': '舰长',
            'start_time': 1790813934,
            'end_time': 1790813934,
          },
        }).single;
        expect((guard.userName, guard.userId, guard.message), ('观众', '1000001', '舰长 ×1'));
        expect(
          guard.data,
          const BilibiliGift(
            id: '10003',
            name: '舰长',
            count: 1,
            goldCoins: 198000,
            kind: LiveGiftKind.membership,
            unitPrice: 198000,
          ),
        );
        expect(guard.gift?.tier, LiveGiftTier.precious, reason: '198 yuan');
        expect(messages({'cmd': 'SEND_GIFT', 'data': <String, Object?>{}}), isEmpty);
      });

      test('D07.1: every message of a combo is reported; COMBO_SEND carries the combo so far', () async {
        Uint8List send(String combo, {String cmd = 'SEND_GIFT'}) => _notice({
          'cmd': cmd,
          'data': {
            if (cmd == 'SEND_GIFT') 'giftName': '小心心' else 'gift_name': '小心心',
            'num': 1,
            'total_num': 5,
            'uname': '观众',
            'batch_combo_id': combo,
          },
        });
        final replay = _Replay();
        await replay.open(replay.args());
        Future<List<String>> gifts(List<int> frame) async => [
          for (final effect in await replay.receive(frame))
            if (effect case {'message': {'type': 'gift', 'message': final String text}}) text,
        ];

        // It used to report only the first message of a combo (C-2), so the
        // app's count stayed at the first send's.
        expect(await gifts(send('a')), ['小心心 ×1']);
        expect(await gifts(send('a')), ['小心心 ×1']);
        expect(await gifts(send('a', cmd: 'COMBO_SEND')), ['小心心 ×5']);
        expect(await gifts(send('')), ['小心心 ×1']);

        final summary = messages({
          'cmd': 'COMBO_SEND',
          'data': {'gift_name': '小心心', 'gift_id': 30607, 'total_num': 5, 'uname': '观众', 'batch_combo_id': 'a'},
        }).single;
        expect((summary.gift?.count, summary.gift?.comboTotal, summary.gift?.comboKey), (5, 5, 'a'));
        final single = messages({
          'cmd': 'SEND_GIFT',
          'data': {'giftName': '小心心', 'num': 1, 'uname': '观众', 'batch_combo_id': 'a'},
        }).single;
        expect((single.gift?.count, single.gift?.comboTotal), (1, null), reason: 'no running count in SEND_GIFT');
        await replay.connection.close();
      });
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
      // B-3: the auth packet asks for protover 3 now; S13-live was recorded
      // with 2. Otherwise the same bytes.
      final protover3 = [
        ...recordedAuth.take(16),
        ...utf8.encode(utf8.decode(recordedAuth.sublist(16)).replaceFirst('"protover":2,', '"protover":3,')),
      ];
      expect(protover3, hasLength(recordedAuth.length));
      expect(protover3, isNot(recordedAuth));
      expect(replay.effects, [
        {'send': base64.encode(protover3)},
      ], reason: 'the recorded auth packet with protover 3');

      final frames = (_expectedValue('S13-live')['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
      final byLine = {for (final frame in frames) frame['line'] as int: frame};
      var messages = 0;
      final online = <Object?>[];
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line['dir'] != 'in' || line['b64'] == null) continue;
        final expected = byLine[index + 1];
        expect(expected, isNotNull, reason: 'line ${index + 1} has 3.x output');
        final effects = await replay.receive(base64.decode(line['b64']! as String));
        expect(_as3x(effects), _expected(expected!), reason: 'line ${index + 1}');
        messages += _as3x(effects).where((effect) => effect.containsKey('message')).length;
        online.addAll(_onlineViewers(effects));
      }
      expect(byLine, hasLength(161));
      expect(messages, 57, reason: '44 chats, 11 watched counts, 2 heartbeat replies');
      expect(online, hasLength(20), reason: 'C-1: every ONLINE_RANK_COUNT');
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
      // Intentional differences (docs/D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕/record.md): M2's colour
      // fix, and super chats read like M4.1's snapshot.
      final differences = <String, Map<String, Object?> Function(Map<String, Object?> message)>{
        'chat-colors/blue': (message) => {...message, 'color': '#0000ff'},
        'chat-colors/five digits': (message) => {...message, 'color': '#0a0a0a'},
        // M4.D: the message carries the super chat's id too.
        'super-chat/0': (message) => {
          ...message,
          'messageId': '19298954',
          'data': {...message['data']! as Map<String, Object?>, 'messageId': '19298954'},
        },
        'super-chat/1': (message) => {
          ...message,
          'messageId': '19298954',
          'data': {
            ...message['data']! as Map<String, Object?>,
            'messageId': '19298954',
            'face': 'https://i0.hdslb.com/bfs/face/member/noface.jpg@200w.jpg',
          },
        },
      };
      final applied = <String>{};
      final online = <Object?>[];
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
          expect(_as3x(effects), expected, reason: '$name, line ${frame['line']}');
          online.addAll(_onlineViewers(effects));
        }
        await replay.connection.close();
      }
      expect(applied, differences.keys.toSet(), reason: 'every difference is still needed');
      expect(online, [1], reason: "C-1: the acknowledgement vector's ONLINE_RANK_COUNT");
      expect(vectors, hasLength(28));
    });

    test('B-3 S13-protover3: the recorded auth packet, then every received message as 3.x handled it', () async {
      final lines = _lines('S13-protover3');
      final replay = await _replayRecording('S13-protover3');
      expect(replay.auth, base64.decode(lines.first['b64']! as String), reason: 'the bytes this connection sent');
      expect((_body(replay.auth)! as Map)['protover'], 3);

      final frames = (_expectedValue('S13-protover3')['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect({for (final frame in frames) frame['line']}, replay.effects.keys.toSet());
      // M5.1 difference 3: super chats carry `data.id` as their messageId
      // (3.x left it empty), the message itself too since M4.D. The ids are
      // public: the snapshot lists them.
      const ids = ['19367477', '19367516', '19367528', '19367530', '19367547', '19367548'];
      var superChats = 0;
      Object? adjust(Object? effect) {
        if (effect case {'message': final Map<String, dynamic> message} when message['type'] == 'superChat') {
          final data = message['data']! as Map<String, dynamic>;
          expect(data['messageId'], '');
          final id = ids[superChats++];
          return {
            'message': {
              ...message,
              'messageId': id,
              'data': {...data, 'messageId': id},
            },
          };
        }
        return effect;
      }

      for (final frame in frames) {
        final line = frame['line'] as int;
        expect(_as3x(replay.effects[line]!), [
          for (final effect in _expected(frame)) adjust(effect),
        ], reason: 'line $line');
      }
      expect(superChats, 6);
      expect(_onlineViewers(replay.effects.values.expand((effects) => effects)), [
        3795,
        3805,
        3846,
        3831,
        3856,
      ], reason: "C-1: every ONLINE_RANK_COUNT's online_count");

      final effects = replay.effects.values.expand((effects) => effects).toList();
      final messages = [for (final effect in effects) ?effect['message'] as Map<String, Object?>?];
      final online = [
        for (final message in messages)
          if (message['type'] == 'online') (message['data']! as Map<String, Object?>)['kind'],
      ];
      expect(messages.where((message) => message['type'] == 'chat'), hasLength(66));
      expect(online.where((kind) => kind == 'popularity'), hasLength(4));
      expect(online.where((kind) => kind == 'totalViewers'), hasLength(3));
      // B06: the fan badge and the avatar, which 3.x did not read.
      expect(messages.firstWhere((message) => message['type'] == 'chat'), {
        'type': 'chat',
        'userName': '观***',
        'userId': '0',
        'message': '我吗',
        'color': '#ffffff',
        'userLevel': '',
        'fansLevel': '22',
        'fansName': '小路泥',
        'isLocal': false,
        'messageId': 'bilibili:1790780343',
        'sentAt': 1790781387263,
        'data': 'DanmakuSender(https://i0.hdslb.com/bfs/face/cd395d684ff63a33dd0baeb3656423d37cd61533.jpg@96w_96h.jpg)',
      });
      expect(messages.firstWhere((message) => message['type'] == 'superChat'), {
        'type': 'superChat',
        'userName': 'SUPER_CHAT_MESSAGE',
        'userId': '',
        'message': 'SUPER_CHAT_MESSAGE',
        'color': '#ffffff',
        'userLevel': '',
        'fansLevel': '',
        'fansName': '',
        'isLocal': false,
        'messageId': '19367477',
        'sentAt': null,
        'data': {
          'messageId': '19367477',
          'userName': '森水戊花曦众书茶星',
          'face': 'https://i2.hdslb.com/bfs/face/ba351cfd2b32b0d23d5696db1d097b1fe1a2f75d.jpg@200w.jpg',
          'message': '假期最后一天的小路：玩完了；回来后统计工作量的小路：玩完了',
          'price': 30,
          'startTime': 1790781481000,
          'endTime': 1790781541000,
          'backgroundColor': '#EDF5FF',
          'backgroundBottomColor': '#2A60B2',
        },
      });

      // The recorded client packets after the auth: heartbeats and the
      // acknowledgement every super chat asks for, as this connection sends
      // them.
      final acks = [
        for (final effect in effects)
          if (effect['send'] case final String packet when _operation(base64.decode(packet)) == 24) packet,
      ];
      expect(acks, hasLength(6));
      final out = [
        for (final line in lines.skip(1))
          if (line['dir'] == 'out') line['b64']! as String,
      ];
      expect(out.where((packet) => _operation(base64.decode(packet)) == 24), acks);
      expect(
        out.where((packet) => _operation(base64.decode(packet)) != 24),
        everyElement(base64.encode(BilibiliDanmakuProtocol.heartbeat())),
      );
      expect(_body(base64.decode(acks.first)), {
        'msg_id': '214386819788254208:1000:1000',
        'cmd': 'SUPER_CHAT_MESSAGE',
        'p_msg_type': 1,
      });
    });

    test(
      'B-3 S13-protover2-paired: the zlib connection of the same moment gives the same notices and effects',
      () async {
        final brotli = _lines('S13-protover3');
        final zlib = _lines('S13-protover2-paired');
        expect(zlib.map((line) => line['dir']), brotli.map((line) => line['dir']));
        var compressed = 0;
        for (var index = 0; index < brotli.length; index++) {
          if (brotli[index]['dir'] != 'in') continue;
          final a = base64.decode(brotli[index]['b64']! as String);
          final b = base64.decode(zlib[index]['b64']! as String);
          expect(_notices(a), _notices(b), reason: 'line ${index + 1}');
          // One packet per message: a bad brotli packet costs only itself.
          expect(_versions(a), hasLength(1));
          if (_operation(a) == 5 && _versions(a).single != 0) {
            compressed++;
            expect(_versions(a).single, 3);
            expect(_versions(b).single, 2);
          }
        }
        expect(compressed, greaterThan(50));
        final replayed = await _replayRecording('S13-protover2-paired');
        expect((_body(replayed.auth)! as Map)['protover'], 3, reason: 'this connection asks for 3');
        expect(replayed.effects, (await _replayRecording('S13-protover3')).effects);
        expect(
          File('$_root/S13-protover2-paired/expected.json').readAsStringSync(),
          File('$_root/S13-protover3/expected.json').readAsStringSync(),
          reason: '3.x handled both the same way',
        );
      },
    );

    test('B-3 S13-brotli-vectors: every vector as 3.x handled it', () async {
      final lines = _lines('S13-brotli-vectors');
      final vectors = (_expectedValue('S13-brotli-vectors')['vectors'] as List<dynamic>).cast<Map<String, dynamic>>();
      var messages = 0;
      for (final vector in vectors) {
        final name = vector['vector'] as String;
        final replay = _Replay();
        await replay.open(replay.args());
        replay.effects.clear();
        for (final frame in (vector['frames'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final line = lines[(frame['line'] as int) - 1];
          expect(line['vector'], name);
          final effects = await replay.receive(base64.decode(line['b64']! as String));
          expect(effects.map(_withoutB06), _expected(frame), reason: '$name, line ${frame['line']}');
          messages += effects.where((effect) => effect.containsKey('message')).length;
        }
        await replay.connection.close();
      }
      expect(vectors, hasLength(10));
      expect(messages, greaterThan(10));
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
          joinTimeout: Duration(seconds: 1),
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
      await Future<void>.delayed(const Duration(milliseconds: 1300));
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

    test('a real WebSocket server: auth (protover 3), reply, brotli and zlib notices, heartbeat', () async {
      final operations = <int>[];
      final protocols = <Object?>[];
      final sockets = <WebSocket>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          final packet = frame as List<int>;
          operations.add(_operation(packet));
          if (_operation(packet) == 7) {
            protocols.add((_body(packet)! as Map)['protover']);
            socket
              ..add(_auth('{"code":0}'))
              // B-3: what the server answers to protover 3; zlib still works.
              ..add(_brotli([..._notice(_danmu('弹幕')), ..._notice(_danmu('第二条'))]))
              ..add(_packet(5, zlib.encode(_notice(_danmu('zlib'))), version: 2));
          }
        });
      });
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      final connection = BilibiliDanmakuConnection(
        policy: const DanmakuSocketPolicy(heartbeatInterval: Duration(milliseconds: 20)),
      );
      final events = _record(connection);
      await connection.connect(_args(servers: [Uri.parse('ws://127.0.0.1:${server.port}/sub')], headers: const {}));
      await _until(() => _texts(events).length == 3 && operations.where((operation) => operation == 2).length >= 2);
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['弹幕', '第二条', 'zlib']);
      expect(operations.take(2), [7, 2]);
      expect(protocols, [3]);
      await connection.close();
    });
  });
}
