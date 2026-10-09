import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/douyu/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded session (S13-live): frames in order, with their direction.
final List<({String dir, Uint8List bytes})> _frames = [
  for (final line in File('$_root/S13-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': final String dir, 'b64': final String b64}) (dir: dir, bytes: base64Decode(b64)),
];

/// The catalogue of the recorded answers (D07.3): `betard`'s room gifts
/// (S05-offline), the room's gift list (S17) and the prop table (S18), as
/// `DouyuSite` merges them.
DouyuGiftCatalog _catalogue() =>
    DouyuApi.roomGifts(File('../../fixtures/douyu/S05-offline/body.json').readAsStringSync())
        .merge(DouyuApi.giftList(File('../../fixtures/douyu/S17-gift-list/body.json').readAsStringSync()))
        .merge(DouyuApi.propGifts(File('../../fixtures/douyu/S18-prop-config/body.txt').readAsStringSync()));

/// 3.x's output for S13-live (fixtures/douyu/danmaku/legacy_expected.dart).
final Map<String, Object?> _recorded =
    (_json('S13-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

final String _roomId = _recorded['roomId']! as String;

List<Map<String, Object?>> get _recordedMessages => [
  for (final message in _recorded['messages']! as List<Object?>) Map.of(message! as Map<String, Object?>),
];

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) {
  final data = message.data;
  return {
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
    'data': data is LiveSuperChatMessage
        ? {
            'messageId': data.messageId,
            'userName': data.userName,
            'face': data.face,
            'message': data.message,
            'price': data.price,
            'startTime': data.startTime.millisecondsSinceEpoch,
            'endTime': data.endTime.millisecondsSinceEpoch,
            'backgroundColor': data.backgroundColor,
            'backgroundBottomColor': data.backgroundBottomColor,
          }
        : data is DouyuGift
        ? {'id': data.id, 'name': data.name, 'count': data.count, 'combo': data.combo, 'receiver': data.receiverName}
        : data,
  };
}

/// One case of S14-synthetic/cases.json as the server frames it (the same
/// framing as legacy_expected.dart's `serverFrame`).
List<int> _serverFrame(Map<String, Object?> testCase) {
  final bytes = <int>[];
  for (final packet in testCase['packets']! as List<Object?>) {
    if (packet is Map) {
      final length = packet['headerLength']! as int;
      bytes.addAll(
        (ByteData(12)
              ..setUint32(0, length, Endian.little)
              ..setUint32(4, length, Endian.little)
              ..setUint16(8, DouyuDanmakuProtocol.serverPacketType, Endian.little))
            .buffer
            .asUint8List(),
      );
    } else {
      bytes.addAll(DouyuDanmakuProtocol.packet(packet! as String, type: DouyuDanmakuProtocol.serverPacketType));
    }
  }
  return bytes.sublist(0, bytes.length - (testCase['cut'] as int? ?? 0));
}

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

/// Hands out fake channels and records every handshake.
final class _Connector {
  new({this.fail = false});

  final bool fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<Iterable<String>?> protocols = [];
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
    if (fail) throw const SocketException('refused');
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

/// The messages of [events] of the kinds 3.x reported (gifts are new, M4.D).
List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuReceived && event.message.type != LiveMessageType.gift) event.message,
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

final Uint8List _heartbeat = DouyuDanmakuProtocol.heartbeat();
final DouyuDanmakuArgs _args = DouyuDanmakuArgs(_roomId);

void main() {
  group('protocol', () {
    test("client packets are byte for byte 3.x's and the recorded ones", () {
      final joins = [for (final frame in _recorded['joinFrames']! as List<Object?>) base64Decode(frame! as String)];
      expect(DouyuDanmakuProtocol.joinPackets(_roomId), joins);
      expect(DouyuDanmakuProtocol.heartbeat(), base64Decode(_recorded['heartbeatFrame']! as String));
      final sent = [
        for (final frame in _frames)
          if (frame.dir == 'out') frame.bytes,
      ];
      expect(sent, joins, reason: 'the recording sent loginreq and joingroup');
      expect(DouyuDanmakuProtocol.bodies(_heartbeat), ['type@=mrkl/']);
      expect(ByteData.sublistView(_heartbeat).getUint16(8, Endian.little), DouyuDanmakuProtocol.clientPacketType);
    });

    test('the packet length counts UTF-8 bytes (3.x counted UTF-16 units)', () {
      const body = 'txt@=弹幕/';
      final packet = DouyuDanmakuProtocol.packet(body);
      final view = ByteData.sublistView(packet);
      final length = 8 + utf8.encode(body).length + 1;
      expect(view.getUint32(0, Endian.little), length);
      expect(view.getUint32(4, Endian.little), length);
      expect(packet, hasLength(4 + length));
      expect(packet.sublist(10, 12), [0, 0]);
      expect(packet.last, 0);
      expect(DouyuDanmakuProtocol.bodies(packet), [body]);
      // 3.x's length (8 + 8 UTF-16 units + 1) cut the body short.
      expect(8 + body.length + 1, lessThan(length));
    });

    test('a frame splits by each packet length; a short or overlong one stops it', () {
      final frame = [
        ...DouyuDanmakuProtocol.packet('a@=1/'),
        ...DouyuDanmakuProtocol.packet('b@=2/'),
        ...DouyuDanmakuProtocol.packet('c@=3/'),
      ];
      expect(DouyuDanmakuProtocol.bodies(frame), ['a@=1/', 'b@=2/', 'c@=3/']);
      expect(DouyuDanmakuProtocol.bodies(frame.sublist(0, frame.length - 1)), ['a@=1/', 'b@=2/']);
      final short = (ByteData(12)..setUint32(0, 8, Endian.little)).buffer.asUint8List();
      expect(DouyuDanmakuProtocol.bodies([...short, ...DouyuDanmakuProtocol.packet('a@=1/')]), isEmpty);
      expect(DouyuDanmakuProtocol.bodies(frame.sublist(0, 11)), isEmpty);
      // The last byte is dropped whatever it is, as in 3.x.
      final unterminated = DouyuDanmakuProtocol.packet('a@=1/')..last = 0x2F;
      expect(DouyuDanmakuProtocol.bodies(unterminated), ['a@=1/']);
    });

    test('STT: values unescaped once, nested maps and lists decoded on demand', () {
      expect(DouyuStt.escape('a/b@c'), 'a@Sb@Ac');
      expect(DouyuStt.unescape('a@Sb@Ac'), 'a/b@c');
      expect(DouyuStt.unescape(DouyuStt.escape('@S@A//@=')), '@S@A//@=');
      final fields = DouyuStt.map('type@=chatmsg/txt@=https:@S@Sx.cn@S@A=y/nn@=@ASam/k@=/@=v/novalue/dup@=1/dup@=2/');
      expect(fields, {'type': 'chatmsg', 'txt': 'https://x.cn/@=y', 'nn': '@Sam', 'k': '', 'dup': '2'});
      final raw = DouyuStt.escape('${DouyuStt.escape('a@=1/b@=2/')}/${DouyuStt.escape('a@=3/')}/');
      expect(DouyuStt.list(DouyuStt.map('list@=$raw/')['list']!).map(DouyuStt.map), [
        {'a': '1', 'b': '2'},
        {'a': '3'},
      ]);
      expect(DouyuStt.list('4143/6065/'), ['4143', '6065']);
      expect(DouyuStt.list(''), isEmpty);
    });

    test("3.x's colour table", () {
      expect(
        [for (var col = 0; col <= 7; col++) DouyuDanmakuProtocol.color(col).toString()],
        ['#ffffff', '#ff0000', '#1e87f0', '#7ac84b', '#ff7f00', '#9b39f4', '#ff69b4', '#ffffff'],
      );
    });

    test("3.x's suspected-automated rule", () {
      expect(DouyuDanmakuProtocol.isSuspectedAutomated({}), isTrue);
      expect(DouyuDanmakuProtocol.isSuspectedAutomated({'if': '0'}), isTrue);
      expect(DouyuDanmakuProtocol.isSuspectedAutomated({'if': '1'}), isFalse);
      expect(DouyuDanmakuProtocol.isSuspectedAutomated({'dms': ''}), isFalse);
    });
  });

  group('recorded frames (S13-live) against 3.x', () {
    test('every incoming frame decodes to what 3.x decoded', () {
      var filterCalls = 0;
      final decoded = [
        for (var index = 0; index < _frames.length; index++)
          if (_frames[index].dir == 'in')
            for (final message in DouyuDanmakuProtocol.decode(
              _frames[index].bytes,
              roomId: _roomId,
              filterSuspectedAutomated: () {
                filterCalls++;
                return false;
              },
            ))
              if (message.type != LiveMessageType.gift) {'frame': index, ..._project(message)},
      ];
      final expected = _recordedMessages;
      expect(decoded, hasLength(147));
      expect(decoded, expected);
      expect(filterCalls, 0, reason: 'every recorded chat has dms or if=1');
    });

    test('with the filter on, 3.x kept the same chat', () {
      final kept = [
        for (final frame in _frames)
          if (frame.dir == 'in')
            for (final message in DouyuDanmakuProtocol.decode(
              frame.bytes,
              roomId: _roomId,
              filterSuspectedAutomated: () => true,
            ))
              if (message.type != LiveMessageType.gift) message.messageId,
      ];
      expect(kept, _recorded['keptWithFilter']);
    });

    test("another room's id drops the recorded chat", () {
      final decoded = [
        for (final frame in _frames)
          if (frame.dir == 'in') ...DouyuDanmakuProtocol.decode(frame.bytes, roomId: '1'),
      ];
      expect(decoded, isEmpty, reason: 'every recorded chatmsg and dgb carries rid 9999');
    });

    test('the 125 recorded dgb packets are gifts (M4.D; 3.x ignored them)', () {
      final gifts = [
        for (final frame in _frames)
          if (frame.dir == 'in')
            ...DouyuDanmakuProtocol.decode(frame.bytes, roomId: _roomId).where((m) => m.type == LiveMessageType.gift),
      ];
      expect(gifts, hasLength(125));
      expect(_project(gifts.first), {
        'type': 'gift',
        'userName': '观众3',
        'userId': '5413638',
        'message': '粉丝荧光棒 ×10',
        'color': '#ffffff',
        'messageId': '',
        'sentAt': null,
        // D07.3: the sender's level and fan medal (`level`, `bnn`, `bl`).
        'userLevel': '39',
        'fansLevel': '22',
        'fansName': '集团军',
        'isLocal': false,
        'data': {'id': '824', 'name': '粉丝荧光棒', 'count': 10, 'combo': 10, 'receiver': 'yyfyyf'},
      });
      // Every one of them came from the backpack (`gpf` 1): free, no value.
      final presents = [for (final gift in gifts) gift.data! as DouyuGift];
      expect(presents.every((gift) => gift.backpack && gift.free && gift.totalValue == null), isTrue);
      expect(presents.where((gift) => gift.id == '824'), hasLength(119));
      // A medal-less sender has no fan level either.
      expect(gifts.where((m) => m.fansName.isEmpty).every((m) => m.fansLevel.isEmpty), isTrue);
    });
  });

  group('gifts (S15-gifts, 2026-09-30)', () {
    final sample = _json('S15-gifts/packets.json')! as Map<String, Object?>;
    final roomId = sample['roomId']! as String;
    final frame = [
      for (final body in sample['packets']! as List<Object?>)
        ...DouyuDanmakuProtocol.packet(body! as String, type: DouyuDanmakuProtocol.serverPacketType),
    ];

    test('every recorded dgb is a gift with its name, count, combo and receiver', () {
      final gifts = DouyuDanmakuProtocol.decode(frame, roomId: roomId);
      expect(gifts, hasLength(57));
      expect(gifts.every((m) => m.type == LiveMessageType.gift && m.userName.isNotEmpty), isTrue);
      final first = gifts.first.data! as DouyuGift;
      expect(
        first,
        DouyuGift(
          id: '22171',
          name: '精英宝典',
          count: 1,
          combo: 1,
          receiverName: '若若跑的贼快',
          comboKey: '${gifts.first.userId}:22171',
        ),
      );
      expect(gifts.first.message, '精英宝典 ×1');
      // E05.5: the shared gift; no price in the packet, and no catalogue.
      expect(
        (first.comboTotal, first.unitPrice, first.totalValue, first.unit, first.tier, first.free, first.iconUrl),
        (1, null, null, LiveGiftUnit.other, LiveGiftTier.normal, false, null),
      );
      expect(gifts.first.gift, same(first));
      expect(gifts.first.userLevel, '2');
      // A backpack prop has gfid 0: its id is the pid (D07.3), and it is free.
      final prop = gifts.map((m) => m.data! as DouyuGift).firstWhere((gift) => gift.name == '陪伴印章');
      expect((prop.id, prop.backpack, prop.free), ('3410', true, true));
      expect(prop.comboKey, endsWith(':3410'));
      final names = {for (final m in gifts) (m.data! as DouyuGift).name};
      expect(names, containsAll(['陪伴印章', '粉丝荧光棒', '精英宝典', '精英令', '国庆快乐']));
    });

    test("another room's gift and a gift without a name give nothing", () {
      expect(DouyuDanmakuProtocol.decode(frame, roomId: '1'), isEmpty);
      final unnamed = DouyuDanmakuProtocol.packet(
        'type@=dgb/rid@=$roomId/gfid@=1/gfcnt@=1/nn@=a/uid@=1/',
        type: DouyuDanmakuProtocol.serverPacketType,
      );
      expect(DouyuDanmakuProtocol.decode(unnamed, roomId: roomId), isEmpty);
    });
  });

  group('gift catalogue (D07.3: S05 betard, S17 gift list, S18 prop table)', () {
    final sample = _json('S15-gifts/packets.json')! as Map<String, Object?>;
    final roomId = sample['roomId']! as String;
    final frame = [
      for (final body in sample['packets']! as List<Object?>)
        ...DouyuDanmakuProtocol.packet(body! as String, type: DouyuDanmakuProtocol.serverPacketType),
    ];
    final catalogue = _catalogue();

    LiveMessage dgb(String fields, {DouyuGiftCatalog? gifts}) => DouyuDanmakuProtocol.decode(
      DouyuDanmakuProtocol.packet(
        'type@=dgb/rid@=$roomId/uid@=7/nn@=观众/level@=12/$fields',
        type: DouyuDanmakuProtocol.serverPacketType,
      ),
      roomId: roomId,
      gifts: gifts ?? catalogue,
    ).single;

    test('a paid gift of the gift list: price in fen, value, picture, tier', () {
      final rocket = dgb('gfid@=20004/gfn@=火箭/gfcnt@=1/hits@=1/').gift!;
      expect(
        (rocket.unitPrice, rocket.totalValue, rocket.unit, rocket.free, rocket.tier),
        (50000, 50000, LiveGiftUnit.fen, false, LiveGiftTier.precious),
      );
      expect(
        rocket.iconUrl,
        Uri.parse('https://gfs-op.douyucdn.cn/dygift/2019/02/18/8bab2f98ab4d3429ffe00472a1a817e5.png'),
      );
      // Ten 小心心 (0.1 yuan each): 1 yuan, normal.
      final hearts = dgb('gfid@=24491/gfn@=小心心/gfcnt@=10/hits@=10/').gift!;
      expect((hearts.unitPrice, hearts.totalValue, hearts.tier), (10, 100, LiveGiftTier.normal));
      // 飞机 ×1: 100 yuan, precious; 赞 ×100: 10 yuan, valuable.
      expect(dgb('gfid@=20003/gfn@=飞机/gfcnt@=1/').gift!.tier, LiveGiftTier.precious);
      expect(dgb('gfid@=20006/gfn@=赞/gfcnt@=100/').gift!.tier, LiveGiftTier.valuable);
    });

    test("betard's room gifts: 火箭 by its old id, 100鱼丸 free", () {
      final rocket = dgb('gfid@=196/gfn@=火箭/gfcnt@=2/').gift!;
      expect((rocket.unitPrice, rocket.totalValue, rocket.tier), (50000, 100000, LiveGiftTier.precious));
      expect(rocket.iconUrl, Uri.parse('https://gfs-op.douyucdn.cn/dygift/1609/8fdc7b6395b93729eed49429d2776a73.png'));
      final balls = dgb('gfid@=191/gfn@=100鱼丸/gfcnt@=1/').gift!;
      expect((balls.free, balls.unitPrice, balls.totalValue, balls.tier), (true, null, null, LiveGiftTier.normal));
      expect(balls.iconUrl, isNotNull);
    });

    test('a 鱼丸 gift of the gift list is free', () {
      final star = dgb('gfid@=20008/gfn@=超大丸星/gfcnt@=1/').gift!;
      expect((star.free, star.totalValue, star.unit), (true, null, LiveGiftUnit.other));
    });

    test('S15-gifts: 国庆快乐 priced, 粉丝荧光棒 a free prop with its picture, 精英宝典 known by name only', () {
      final gifts = DouyuDanmakuProtocol.decode(frame, roomId: roomId, gifts: catalogue);
      expect(gifts, hasLength(57), reason: 'the catalogue drops nothing');
      DouyuGift named(String name) => gifts.map((m) => m.data! as DouyuGift).firstWhere((g) => g.name == name);
      final national = named('国庆快乐');
      expect(
        (national.count, national.unitPrice, national.totalValue, national.unit, national.free),
        (9, 10, 90, LiveGiftUnit.fen, false),
      );
      expect(national.iconUrl?.host, 'gfs-op.douyucdn.cn');
      final stick = named('粉丝荧光棒');
      expect(
        (stick.id, stick.backpack, stick.free, stick.totalValue, stick.tier),
        ('824', true, true, null, LiveGiftTier.normal),
      );
      expect(stick.iconUrl, Uri.parse('https://gfs-op.douyucdn.cn/dygift/1705/7d724fb3d7e7d4a463a3e74e9929b919.png'));
      // In no catalogue: the name and nothing else, not free (D-003).
      final book = named('精英宝典');
      expect(
        (book.unitPrice, book.totalValue, book.unit, book.free, book.iconUrl),
        (null, null, LiveGiftUnit.other, false, null),
      );
      // 陪伴印章 (gfid 0, pid 3410): no catalogue knows pids; free all the same.
      final seal = named('陪伴印章');
      expect((seal.id, seal.free, seal.iconUrl), ('3410', true, null));
    });

    test("the combo key and count are the packet's, catalogue or not", () {
      final plain = DouyuDanmakuProtocol.decode(frame, roomId: roomId);
      final priced = DouyuDanmakuProtocol.decode(frame, roomId: roomId, gifts: catalogue);
      expect(
        [for (final m in priced) (m.gift!.comboKey, m.gift!.comboTotal, m.gift!.count, m.message)],
        [for (final m in plain) (m.gift!.comboKey, m.gift!.comboTotal, m.gift!.count, m.message)],
      );
    });

    test('a blank gfn takes the catalogue name; unknown and blank gives nothing', () {
      expect(dgb('gfid@=20004/gfn@=/gfcnt@=1/').message, '火箭 ×1');
      expect(
        DouyuDanmakuProtocol.decode(
          DouyuDanmakuProtocol.packet(
            'type@=dgb/rid@=$roomId/uid@=7/gfid@=99999/gfcnt@=1/',
            type: DouyuDanmakuProtocol.serverPacketType,
          ),
          roomId: roomId,
          gifts: catalogue,
        ),
        isEmpty,
      );
    });

    test('no catalogue: as before (name, count, combo; no price, no picture)', () {
      final rocket = dgb('gfid@=20004/gfn@=火箭/gfcnt@=1/hits@=1/', gifts: DouyuGiftCatalog.empty).gift!;
      expect(rocket, const DouyuGift(id: '20004', name: '火箭', count: 1, combo: 1, comboKey: '7:20004'));
      expect(rocket.tier, LiveGiftTier.normal);
    });
  });

  group('broadcast end (S16-broadcast-end, 2026-10-01, C-6)', () {
    final sample = _json('S16-broadcast-end/packets.json')! as Map<String, Object?>;
    final roomId = sample['roomId']! as String;
    final end = sample['packets']! as List<Object?>;
    Uint8List server(String body) => DouyuDanmakuProtocol.packet(body, type: DouyuDanmakuProtocol.serverPacketType);
    String chat(String text) => 'type@=chatmsg/rid@=$roomId/dms@=4/txt@=$text/';

    test("the recorded rss (ss 0) ends this room's broadcast; a start or another room's does not", () {
      final body = end.single! as String;
      final read = DouyuDanmakuProtocol.read([
        ...server(chat('before')),
        ...server(body),
        ...server(chat('after')),
      ], roomId: roomId);
      expect(read.ended, isTrue);
      expect(read.messages.map((m) => m.message), ['before']);
      expect(DouyuDanmakuProtocol.read(server(body), roomId: '1').ended, isFalse);
      expect(DouyuDanmakuProtocol.read(server(body.replaceFirst('/ss@=0/', '/ss@=1/')), roomId: roomId).ended, isFalse);
    });

    test('the connection ends the run with connectionFailed (Broadcast ended), without reconnecting', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(DouyuDanmakuArgs(roomId));
      final channel = connector.channels.single;
      channel.incoming.add([...server(chat('bye')), ...server(end.single! as String)]);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(_messages(events).map((m) => m.message), ['bye']);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: DouyuDanmakuConnection.broadcastEnded),
      );
      expect(channel.closed, isTrue);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(1), reason: 'no reconnect');
      expect(connection.status, DanmakuStatus.closed);
    });
  });

  group('synthetic frames (S14-synthetic) against 3.x', () {
    final cases = (_json('S14-synthetic/cases.json')! as Map<String, Object?>)['cases']! as List<Object?>;
    final expected = {
      for (final result in (_json('S14-synthetic/expected.json')! as Map<String, Object?>)['value']! as List<Object?>)
        if (result case {'name': final String name, 'messages': final List<Object?> messages})
          name: [for (final message in messages) message! as Map<String, Object?>],
    };

    /// The intentional differences (docs/D-弹幕/D01-平台弹幕协议/D01.3-斗鱼弹幕/record.md), applied to
    /// 3.x's output of the case they concern.
    final differences = <String, List<Map<String, Object?>> Function(List<Map<String, Object?>>)>{
      // 3.x ignored gifts (`dgb`); they are reported now (M4.D).
      'other packet types are ignored': (legacy) {
        expect(legacy, isEmpty);
        return [
          {
            'type': 'gift',
            'userName': 'A',
            'userId': '1',
            'message': 'x ×1',
            'color': '#ffffff',
            'messageId': '',
            'sentAt': null,
            'userLevel': '',
            'fansLevel': '',
            'fansName': '',
            'isLocal': false,
            'data': {'id': '824', 'name': 'x', 'count': 1, 'combo': 0, 'receiver': ''},
          },
        ];
      },
      // 3.x turned a pandora box notice into a super chat of 0 yuan.
      'pandora box notice shares the super chat type (price and duration 0)': (legacy) {
        expect(legacy.single['type'], 'superChat');
        expect((legacy.single['data']! as Map)['price'], 0);
        return [];
      },
      // 3.x never parsed `uat` as a list, so the avatar was always empty.
      'voice super chat': (legacy) {
        final data = legacy.single['data']! as Map<String, Object?>;
        expect(data['face'], '');
        return [
          {
            ...legacy.single,
            'data': {...data, 'face': 'https://apic.douyucdn.cn/upload/avatar_v3/b_small.jpg'},
          },
        ];
      },
      // 3.x unescaped chat twice and re-read it as a structure.
      'chat text holding STT escapes, links and @=': (legacy) {
        expect(legacy.map((message) => message['message']), [
          '@lice 你好',
          '/akura',
          '[https:, t.cn/x]',
          '{a: b}',
          '{x: y}',
          '1/2 @ 3',
        ]);
        const texts = ['@Alice 你好', '@Sakura', 'https://t.cn/x', 'a@=b', 'x@A=y', '1/2 @ 3'];
        return [
          for (var index = 0; index < legacy.length; index++)
            {...legacy[index], 'message': texts[index], if (index == 1) 'userName': '@Sam'},
        ];
      },
    };

    test('every case has 3.x output', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
      expect(differences.keys.every(expected.containsKey), isTrue);
    });

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        final filter = testCase['filter'] == true;
        final decoded = DouyuDanmakuProtocol.decode(
          _serverFrame(testCase),
          roomId: testCase['roomId']! as String,
          filterSuspectedAutomated: () => filter,
        ).map(_project).toList();
        final legacy = expected[name]!;
        expect(decoded, differences[name]?.call(legacy) ?? legacy);
      });
    }
  });

  group('connection', () {
    test('opens the one endpoint, is ready at once, then sends loginreq and joingroup', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      expect(connector.endpoints, [Uri.parse('wss://danmuproxy.douyu.com:8506')]);
      expect(connector.headers.single, isEmpty);
      expect(connector.protocols.single, isNull);
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      expect(connector.channels.single.sent, DouyuDanmakuProtocol.joinPackets(_roomId));
      await connection.close();
    });

    test("3.x's timing: 45 s heartbeat, 135 s silence limit, no join timer, 8 reconnects", () {
      final connection = DouyuDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 45));
      expect(connection.site, SiteIds.douyu);
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 45));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 45 s, 90 s) = 135 s');
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends the mrkl heartbeat on its 45 s timer and on demand', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = DouyuDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 4);
          expect(sent.skip(2).take(2), [_heartbeat, _heartbeat]);
          await connection.close();
          final count = sent.length;
          connection.heartbeat();
          await _wait(const Duration(milliseconds: 20));
          expect(sent, hasLength(count), reason: 'nothing after close');
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            periods.add(period);
            return parent.createPeriodicTimer(zone, const Duration(milliseconds: 5), callback);
          },
        ),
      );
      expect(periods, [const Duration(seconds: 45)]);
    });

    test('replaying the recording reports what 3.x decoded, in order', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      for (final frame in _frames) {
        if (frame.dir == 'in') channel.incoming.add(frame.bytes);
      }
      await _until(() => _messages(events).length == 147);
      expect(_messages(events).map(_project), [for (final message in _recordedMessages) message..remove('frame')]);
      await connection.close();
    });

    test('the suspected-automated setting is read for each message, without reconnecting', () async {
      var enabled = false;
      var reads = 0;
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(
        connector: connector.call,
        filterSuspectedAutomatedMessages: () {
          reads++;
          return enabled;
        },
      );
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      Uint8List chat(String text, [String extra = '']) => DouyuDanmakuProtocol.packet(
        'type@=chatmsg/rid@=$_roomId/uid@=1/nn@=A/txt@=$text/cid@=$text/$extra',
        type: DouyuDanmakuProtocol.serverPacketType,
      );
      channel.incoming.add(chat('first'));
      await _until(() => _messages(events).length == 1);
      enabled = true;
      channel.incoming
        ..add(chat('second'))
        ..add(chat('marked', 'dms@=4/'));
      await _until(() => _messages(events).length == 2);
      expect(_messages(events).map((message) => message.message), ['first', 'marked']);
      expect(reads, 2, reason: 'only suspected chat reads the setting');
      expect(connector.channels, hasLength(1));
      await connection.close();
    });

    test("another room's chat is dropped; text frames are ignored", () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(const DouyuDanmakuArgs('100'));
      final channel = connector.channels.single;
      Uint8List chat(String rid, String text) => DouyuDanmakuProtocol.packet(
        'type@=chatmsg/rid@=$rid/dms@=4/txt@=$text/',
        type: DouyuDanmakuProtocol.serverPacketType,
      );
      channel.incoming
        ..add('type@=chatmsg/rid@=100/dms@=4/txt@=text frame/')
        ..add([...chat('200', 'other room'), ...chat('100', 'this room')]);
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).map((message) => message.message), ['this room']);
      expect(channel.sent, DouyuDanmakuProtocol.joinPackets('100'));
      await connection.close();
    });

    test('a dropped socket reconnects after 2 s, joins again and is ready again', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      // The reconnect timer comes first; later ones are LiveSocket's bounded
      // teardown waits (2 s shutdown timeout) when the new socket opens.
      expect(delays.first, const Duration(seconds: 2), reason: 'one endpoint: 1 s × (1 round + 1)');
      expect(connector.endpoints, [DouyuDanmakuProtocol.endpoint, DouyuDanmakuProtocol.endpoint]);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, DouyuDanmakuProtocol.joinPackets(_roomId));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(fail: true);
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays, [
        for (final seconds in [2, 3, 4, 5, 6, 6, 6, 6]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, hasLength(9));
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('refused')),
      );
      expect(events, hasLength(2));
      expect(connection.status, DanmakuStatus.closed);
    });

    test('close: no event, heartbeat or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming.add(_frames.firstWhere((frame) => frame.dir == 'in').bytes);
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, hasLength(2));
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another room closes the first socket and joins the new room', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(const DouyuDanmakuArgs('100'));
      await connection.connect(const DouyuDanmakuArgs('200'));
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, DouyuDanmakuProtocol.joinPackets('200'));
      Uint8List chat(String text) =>
          DouyuDanmakuProtocol.packet('type@=chatmsg/dms@=4/txt@=$text/', type: DouyuDanmakuProtocol.serverPacketType);
      connector.channels.first.incoming.add(chat('from the first room'));
      connector.channels.last.incoming.add(chat('from the second room'));
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).map((message) => message.message), ['from the second room']);
      await connection.close();
    });

    test("prices gifts by betard's catalogue at once and by the fetched one once it arrives (D07.3)", () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      final more = Completer<DouyuGiftCatalog>();
      var fetches = 0;
      final args = DouyuDanmakuArgs(
        _roomId,
        gifts: DouyuApi.roomGifts(File('../../fixtures/douyu/S05-offline/body.json').readAsStringSync()),
        moreGifts: () {
          fetches++;
          return more.future;
        },
      );
      await connection.connect(args);
      final channel = connector.channels.single;
      Uint8List dgb(String id) => DouyuDanmakuProtocol.packet(
        'type@=dgb/rid@=$_roomId/uid@=1/nn@=A/gfid@=$id/gfn@=礼物/gfcnt@=1/',
        type: DouyuDanmakuProtocol.serverPacketType,
      );
      List<LiveGift> gifts() => [
        for (final event in events)
          if (event case DanmakuReceived(:final message) when message.gift != null) message.gift!,
      ];
      channel.incoming
        ..add(dgb('196'))
        ..add(dgb('20004'));
      await _until(() => gifts().length == 2);
      expect([for (final gift in gifts()) gift.unitPrice], [50000, null], reason: 'only betard so far');
      more.complete(_catalogue());
      await _until(() => connection.gifts.length > 13);
      channel.incoming.add(dgb('20004'));
      await _until(() => gifts().length == 3);
      expect(gifts().last.unitPrice, 50000);
      expect(connection.gifts['196']?.price, 50000, reason: "betard's stay");
      expect(fetches, 1);
      await connection.close();
    });

    test('a failing catalogue fetch leaves the gifts as they are', () async {
      final connector = _Connector();
      final connection = DouyuDanmakuConnection(connector: connector.call);
      await connection.connect(DouyuDanmakuArgs(_roomId, moreGifts: () async => throw StateError('offline')));
      await _wait(const Duration(milliseconds: 20));
      expect(connection.gifts.isEmpty, isTrue);
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test('takes DouyuDanmakuArgs only', () async {
      final connection = DouyuDanmakuConnection(connector: _Connector().call);
      await expectLater(connection.connect(_roomId), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under douyu', () {
      final registry = DanmakuRegistry({SiteIds.douyu: DouyuDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.douyu]);
      expect(registry.connectionFor(' Douyu '), isA<DouyuDanmakuConnection>());
      expect(registry.connectionFor('huya'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the recorded session end to end', () async {
      final received = <List<int>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          received.add(frame as List<int>);
          if (received.length == 2) {
            for (final recorded in _frames) {
              if (recorded.dir == 'in') socket.add(recorded.bytes);
            }
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = DouyuDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          requested.add(endpoint);
          return connectIoSocket(
            Uri.parse('ws://127.0.0.1:${server.port}/'),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).length == 147);
      expect(requested, [DouyuDanmakuProtocol.endpoint]);
      expect(received, DouyuDanmakuProtocol.joinPackets(_roomId));
      expect(_messages(events).map(_project), [for (final message in _recordedMessages) message..remove('frame')]);
      connection.heartbeat();
      await _until(() => received.length == 3);
      expect(received.last, _heartbeat);
      await connection.close();
    });
  });
}
