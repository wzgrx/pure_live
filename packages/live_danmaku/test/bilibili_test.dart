import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fixture.dart';

final _context = DecodeContext(room: 'bilibili:5050', session: 2, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

Uint8List _packet(int op, List<int> body, {int version = 0}) {
  final bytes = Uint8List(16 + body.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, bytes.length)
    ..setUint16(4, 16)
    ..setUint16(6, version)
    ..setUint32(8, op)
    ..setUint32(12, 1);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

Uint8List _notice(Map<String, Object?> json) => _packet(5, utf8.encode(jsonEncode(json)));

Uint8List _zlib(List<int> inner) => _packet(5, zlib.encode(inner), version: 2);

Map<String, Object?> _danmu({String name = '观众', String text = '你好', Object? rich}) => {
  'cmd': 'DANMU_MSG:4:0:2:2:2:0',
  'info': [
    [0, 1, 25, 0xE33FFF, 1790519728614, 1790504102, 0, 'abcd', 0, 0, 0, '', 0, '{}', '{}', ?rich],
    text,
    [473644038, name, 0, 0, 0, 10000, 1, ''],
    [27, '大母鹅', 'anchor', 5050],
    [20, 0, 9868950, '>50000', 0],
  ],
};

BilibiliFrame _decode(List<int> message) => BilibiliProtocol.decode(message, context: _context);

const _info = BilibiliDanmakuInfo(
  roomId: 5050,
  uid: 0,
  token: 'token-value',
  servers: [],
  buvid: 'buvid-value',
  headers: {},
);

void main() {
  group('framing (§7.3)', () {
    test('client packets: big-endian header, protover 0, seq 1', () {
      final packet = BilibiliProtocol.packet(7, [1, 2, 3]);
      final view = ByteData.sublistView(packet);
      expect(view.getUint32(0), 19);
      expect(view.getUint16(4), 16);
      expect(view.getUint16(6), 0);
      expect(view.getUint32(8), 7);
      expect(view.getUint32(12), 1);
      expect(BilibiliProtocol.heartbeat(), hasLength(16));
      expect(ByteData.sublistView(BilibiliProtocol.heartbeat()).getUint32(8), 2);
    });

    test('auth packet body (§7.2): protover 2, support_ack, queue_uuid, scene, platform, type, key', () {
      final body = BilibiliProtocol.authBody(_info, queueUuid: '0a1b2c3d');
      expect(body, {
        'uid': 0,
        'roomid': 5050,
        'protover': 2,
        'buvid': 'buvid-value',
        'support_ack': true,
        'queue_uuid': '0a1b2c3d',
        'scene': 'room',
        'platform': 'web',
        'type': 2,
        'key': 'token-value',
      });
      expect(BilibiliProtocol.queueUuid(Random(1)), matches(RegExp(r'^[0-9a-f]{8}$')));
      final packet = BilibiliProtocol.auth(_info, queueUuid: '0a1b2c3d');
      expect(ByteData.sublistView(packet).getUint32(8), 7);
      expect(jsonDecode(utf8.decode(packet.sublist(16))), body);
    });

    test('several packets per message and nested zlib packet streams (REG-BILIBILI-008)', () {
      final inner = [..._notice(_danmu(text: 'a')), ..._notice(_danmu(text: 'b'))];
      final message = [
        ..._zlib(inner),
        ..._packet(3, [0, 0, 0, 42]),
      ];
      final frame = _decode(message);
      expect(frame.events.whereType<DanmakuChat>().map((chat) => chat.text), ['a', 'b']);
      expect((frame.events.last as DanmakuOnline).value, 42);
      expect((frame.events.last as DanmakuOnline).audience, AudienceKind.popularity);
    });

    test('limits: zero length, short header, truncation and deep nesting drop only the rest (REG-BILIBILI-009)', () {
      final good = _notice(_danmu(text: 'kept'));
      final zero = Uint8List(16);
      expect(_decode([...good, ...zero]).events.whereType<DanmakuChat>().map((chat) => chat.text), ['kept']);
      expect(_decode([...good, ...zero]).skipped, 1);
      expect(_decode(good.sublist(0, good.length - 1)).events, isEmpty);
      final shortHeader = _packet(5, const [])..buffer.asByteData().setUint16(4, 8);
      expect(_decode(shortHeader).skipped, 1);
      final deep = _zlib(_zlib(_zlib(_notice(_danmu()))));
      expect(_decode(deep).events, isEmpty);
      expect(_decode(_zlib(_zlib(_notice(_danmu())))).events, hasLength(1));
      final many = [for (var i = 0; i < BilibiliProtocol.maxPackets + 1; i++) ...BilibiliProtocol.heartbeat()];
      expect(_decode(many).skipped, 1);
    });

    test('brotli packets (protover 3) are skipped', () {
      expect(_decode(_packet(5, [1, 2, 3], version: 3)).skipped, 1);
    });
  });

  group('messages (§7.4, §7.5)', () {
    test('DANMU_MSG fields', () {
      final chat = _decode(_notice(_danmu())).events.single as DanmakuChat;
      expect(chat.text, '你好');
      expect(chat.userName, '观众');
      expect(chat.userId, '473644038');
      expect(chat.color, 0xE33FFF);
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519728614));
      expect(chat.id, 'bilibili:1790504102');
      expect(chat.medalLevel, 27);
      expect(chat.medalName, '大母鹅');
      expect(chat.userLevel, 20);
    });

    test('names: the rich user object wins over a masked legacy name; all masked is reported', () {
      final rich = {
        'user': {
          'base': {'name': '完整昵称'},
        },
      };
      final open = _decode(_notice(_danmu(name: '完***', rich: rich)));
      expect((open.events.single as DanmakuChat).userName, '完整昵称');
      expect(open.masked, isFalse);
      final richString = jsonEncode({
        'user': {
          'base': {
            'name': '',
            'origin_info': {'name': '原名'},
          },
        },
      });
      expect((_decode(_notice(_danmu(name: 'x***', rich: richString))).events.single as DanmakuChat).userName, '原名');
      final masked = _decode(_notice(_danmu(name: '完***')));
      expect((masked.events.single as DanmakuChat).userName, '完***');
      expect(masked.masked, isTrue);
      expect(BilibiliProtocol.isMasked('a＊＊'), isTrue);
    });

    test('heartbeat popularity: a real figure is reported, the placeholder 1 for guests is not (REG-BILIBILI-015)', () {
      Uint8List reply(int value) =>
          _packet(3, [value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff]);
      final real = _decode(reply(619543)).events.single as DanmakuOnline;
      expect((real.audience, real.value), (AudienceKind.popularity, 619543));
      expect(_decode(reply(1)).events, isEmpty);
      expect(_decode(reply(0)).events, isEmpty);
    });

    test('WATCHED_CHANGE is cumulative; SUPER_CHAT_MESSAGE and SEND_GIFT', () {
      final watched = _decode(
        _notice({
          'cmd': 'WATCHED_CHANGE',
          'data': {'num': 1042471},
        }),
      ).events.single;
      expect((watched as DanmakuOnline).audience, AudienceKind.cumulative);
      expect(watched.value, 1042471);
      final superChat =
          _decode(
                _notice({
                  'cmd': 'SUPER_CHAT_MESSAGE',
                  'data': {
                    'id': 99,
                    'message': '醒目',
                    'price': 30,
                    'start_time': 1790519700,
                    'end_time': 1790519760,
                    'background_color': '#EDF5FF',
                    'background_bottom_color': '#2A60B2',
                    'user_info': {'uname': '付费', 'face': 'https://i0.hdslb.com/face.jpg'},
                  },
                }),
              ).events.single
              as DanmakuSuperChat;
      expect(superChat.id, 'bilibili:sc:99');
      expect(superChat.price, 30);
      expect(superChat.backgroundColor, 0xEDF5FF);
      expect(superChat.bottomColor, 0x2A60B2);
      expect(superChat.avatar, Uri.parse('https://i0.hdslb.com/face.jpg@200w.jpg'));
      expect(superChat.endAt.difference(superChat.startAt), const Duration(minutes: 1));
      final gift =
          _decode(
                _notice({
                  'cmd': 'SEND_GIFT',
                  'data': {
                    'giftName': '小心心',
                    'num': 3,
                    'uname': '观众',
                    'uid': 1,
                    'giftId': 30607,
                    'coin_type': 'gold',
                    'total_coin': 3000,
                    'tid': 'abc',
                  },
                }),
              ).events.single
              as DanmakuGift;
      expect((gift.giftName, gift.count, gift.yuan, gift.id), ('小心心', 3, 3.0, 'bilibili:gift:abc'));
    });

    test('auth reply: empty or code 0 joins, another code rejects', () {
      expect(_decode(_packet(8, const [])).authorized, isTrue);
      expect(_decode(_packet(8, utf8.encode('{"code":0}'))).authorized, isTrue);
      expect(_decode(_packet(8, utf8.encode('{"code":-101}'))).authorized, isFalse);
      expect(_decode(_notice(_danmu())).authorized, isNull);
    });

    test('ACK (§7.5): only for complete p_is_ack notices; the chat still decodes', () {
      final notice = {..._danmu(), 'p_is_ack': true, 'msg_id': 'm1', 'p_msg_type': 1};
      final frame = _decode(_notice(notice));
      expect(frame.events, hasLength(1));
      final ack = frame.acks.single;
      expect(ByteData.sublistView(ack).getUint32(8), 24);
      expect(jsonDecode(utf8.decode(ack.sublist(16))), {
        'msg_id': 'm1',
        'cmd': 'DANMU_MSG:4:0:2:2:2:0',
        'p_msg_type': 1,
      });
      final incomplete = _decode(_notice({..._danmu(), 'p_is_ack': true, 'msg_id': 'm1'}));
      expect(incomplete.acks, isEmpty);
      expect(incomplete.events, hasLength(1));
    });
  });

  group('recorded frames (fixtures/bilibili/danmaku/S13-live)', () {
    final fixture = DanmakuFixture.load('bilibili', 'S13-live');
    final frames = [
      for (final frame in fixture.incoming)
        if (frame.text == null) BilibiliProtocol.decode(frame.bytes, context: fixture.context(frame)),
    ];
    final events = [for (final frame in frames) ...frame.events];

    test('the client authenticated with protover 2 and heartbeats', () {
      final sent = fixture.outgoing.toList();
      final auth = jsonDecode(utf8.decode(sent.first.bytes.sublist(16))) as Map<String, dynamic>;
      expect(auth['roomid'], 5050);
      expect(auth['protover'], 2);
      expect(auth['support_ack'], isTrue);
      expect(
        sent.skip(1).every((frame) => ByteData.sublistView(Uint8List.fromList(frame.bytes)).getUint32(8) == 2),
        isTrue,
      );
    });

    test('the server accepted the auth and answered in zlib', () {
      expect(frames.first.authorized, isTrue);
      expect(frames.every((frame) => frame.skipped == 0), isTrue);
    });

    test('chat, popularity and cumulative figures decode; guest names are masked', () {
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, hasLength(44));
      expect(chats.first.text, '流口水');
      expect(chats.first.medalName, '大母鹅');
      expect(chats.every((chat) => chat.id!.startsWith('bilibili:') && chat.sentAt != null), isTrue);
      expect(chats.every((chat) => BilibiliProtocol.isMasked(chat.userName)), isTrue);
      expect(frames.any((frame) => frame.masked), isTrue);
      final online = events.whereType<DanmakuOnline>().toList();
      // The recorded guest heartbeats answered the placeholder 1.
      expect(online.where((figure) => figure.audience == AudienceKind.popularity), isEmpty);
      expect(online.where((figure) => figure.audience == AudienceKind.cumulative), hasLength(11));
    });

    test('the super chat snapshot request answered an empty list', () {
      final snapshot = fixture.incoming.singleWhere((frame) => frame.text != null);
      expect(snapshot.url!.path, '/av/v1/SuperChat/getMessageList');
      final body = jsonDecode(snapshot.text!) as Map<String, dynamic>;
      expect((body['data'] as Map<String, dynamic>)['list'], isNull);
    });
  });
}
