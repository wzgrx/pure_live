import 'dart:convert';
import 'dart:typed_data';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fixture.dart';

final _context = DecodeContext(room: 'douyu:9999', session: 7, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

List<DanmakuEvent> _decode(String body, {String rid = '9999'}) =>
    DouyuProtocol.decode(DouyuProtocol.packet(body, type: 690), rid: rid, context: _context);

void main() {
  group('framing (§7.2)', () {
    test(r'a packet is len len type(689) 0 0 body \0, little endian, UTF-8 length', () {
      final packet = DouyuProtocol.packet('type@=mrkl/');
      final view = ByteData.sublistView(packet);
      expect(packet.length, 4 + 8 + 11 + 1);
      expect(view.getUint32(0, Endian.little), 8 + 11 + 1);
      expect(view.getUint32(4, Endian.little), 8 + 11 + 1);
      expect(view.getUint16(8, Endian.little), 689);
      expect(packet[10], 0);
      expect(packet[11], 0);
      expect(packet.last, 0);
      // Non-ASCII bodies count bytes, not UTF-16 units (legacy bug).
      final chinese = DouyuProtocol.packet('txt@=弹幕/');
      expect(ByteData.sublistView(chinese).getUint32(0, Endian.little), 8 + utf8.encode('txt@=弹幕/').length + 1);
      expect(DouyuProtocol.bodies(chinese), ['txt@=弹幕/']);
    });

    test('join and heartbeat packets', () {
      expect(DouyuProtocol.join('9999').map(DouyuProtocol.bodies).expand((bodies) => bodies), [
        'type@=loginreq/roomid@=9999/',
        'type@=joingroup/rid@=9999/gid@=-9999/',
      ]);
      expect(DouyuProtocol.bodies(DouyuProtocol.heartbeat()), ['type@=mrkl/']);
      expect(DouyuProtocol.heartbeatInterval, const Duration(seconds: 45));
    });

    test('one frame carries several packets; a short or overlong length stops the split (REG-DOUYU-017)', () {
      final frame = [
        ...DouyuProtocol.packet('a@=1/'),
        ...DouyuProtocol.packet('b@=2/'),
        ...DouyuProtocol.packet('c@=3/'),
      ];
      expect(DouyuProtocol.bodies(frame), ['a@=1/', 'b@=2/', 'c@=3/']);
      final truncated = frame.sublist(0, frame.length - 3);
      expect(DouyuProtocol.bodies(truncated), ['a@=1/', 'b@=2/']);
      final short = Uint8List(12)..buffer.asByteData().setUint32(0, 8, Endian.little);
      expect(DouyuProtocol.bodies(short), isEmpty);
    });
  });

  group('STT (§7.3)', () {
    test('escapes and maps; nested maps and lists decode only on demand', () {
      expect(Stt.escape('a/b@c'), 'a@Sb@Ac');
      expect(Stt.unescape('a@Sb@Ac'), 'a/b@c');
      final fields = Stt.map('type@=chatmsg/txt@=https:@S@Sexample.com@S@A=x/nn@=a@Ab/');
      // A pasted link and an "@=" inside chat text stay text.
      expect(fields['txt'], 'https://example.com/@=x');
      expect(fields['nn'], 'a@b');
      expect(Stt.encode({'type': 'x', 'txt': 'a/b'}), 'type@=x/txt@=a@Sb/');
      final raw = Stt.escape('${Stt.escape('a@=1/b@=2/')}/${Stt.escape('a@=3/')}/');
      final list = Stt.list(Stt.map('list@=$raw/')['list']!);
      expect(list.map(Stt.map), [
        {'a': '1', 'b': '2'},
        {'a': '3'},
      ]);
    });
  });

  group('messages (§7.4)', () {
    test('chatmsg fields, id, seconds and milliseconds timestamps, colour table', () {
      final chat =
          _decode(
                'type@=chatmsg/rid@=9999/uid@=123/nn@=观众/txt@=你好/cid@=abc/col@=2/cst@=1790519453584/'
                'level@=24/bnn@=小僵尸/bl@=13/dms@=4/if@=1/',
              ).single
              as DanmakuChat;
      expect(chat.id, 'douyu:abc');
      expect(chat.userId, '123');
      expect(chat.userName, '观众');
      expect(chat.text, '你好');
      expect(chat.color, 0x1E87F0);
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519453584));
      expect(chat.userLevel, 24);
      expect(chat.medalName, '小僵尸');
      expect(chat.medalLevel, 13);
      expect(chat.suspectedBot, isFalse);
      expect(chat.room, 'douyu:9999');
      expect(chat.session, 7);
      final seconds = _decode('type@=chatmsg/rid@=9999/txt@=x/cst@=1790519453/').single as DanmakuChat;
      expect(seconds.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519453000));
      expect(
        [for (var col = 0; col <= 7; col++) DouyuProtocol.color(col)],
        [0xFFFFFF, 0xFF0000, 0x1E87F0, 0x7AC84B, 0xFF7F00, 0x9B39F4, 0xFF69B4, 0xFFFFFF],
      );
    });

    test("another room's chat and empty text are dropped; a missing rid is kept (CONN-5)", () {
      expect(_decode('type@=chatmsg/rid@=1/txt@=x/'), isEmpty);
      expect(_decode('type@=chatmsg/rid@=9999/txt@=/'), isEmpty);
      expect(_decode('type@=chatmsg/txt@=x/'), hasLength(1));
    });

    test('suspected bots are marked, never dropped by the decoder (FLT-5, REG-DANMAKU-006)', () {
      bool bot(String body) => (_decode('type@=chatmsg/rid@=9999/txt@=x/$body').single as DanmakuChat).suspectedBot;
      expect(bot(''), isTrue);
      expect(bot('if@=0/'), isTrue);
      expect(bot('if@=1/'), isFalse);
      expect(bot('dms@=4/'), isFalse);
    });

    test('comm_chatmsg: a paid, timed one is a super chat; pandora box notices are not', () {
      final nested = Stt.escape('nn@=付费观众/txt@=加油/ic@=avatar_v3@S202603@Sabc/');
      final superChat =
          _decode('type@=comm_chatmsg/btype@=superDanmu/chatmsg@=$nested/cprice@=3000/cet@=60/now@=1790519453000/')
                  .single
              as DanmakuSuperChat;
      expect(superChat.userName, '付费观众');
      expect(superChat.text, '加油');
      expect(superChat.price, 30);
      expect(superChat.avatar, Uri.parse('https://apic.douyucdn.cn/upload/avatar_v3/202603/abc_small.jpg'));
      expect(superChat.startAt, DateTime.fromMillisecondsSinceEpoch(1790519453000));
      expect(superChat.endAt, DateTime.fromMillisecondsSinceEpoch(1790519513000));
      // Recorded 2026-09-27: pandora notices share the type with price 0.
      expect(
        _decode('btype@=pandora/chatmsg@=$nested/range@=2/cprice@=0/type@=comm_chatmsg/cet@=0/now@=1790518114673/'),
        isEmpty,
      );
      expect(_decode('type@=comm_chatmsg/cprice@=3000/cet@=60/'), isEmpty);
    });

    test('voice_trlt: list[0] fields and the uat avatar', () {
      final item = Stt.escape(
        'acptime@=1790519453/etime@=1790519513/realPrice@=5000/content@=语音/un@=观众/'
        'uat@=${Stt.escape('${Stt.escape('a.jpg')}/${Stt.escape('b.douyucdn.cn/c.jpg')}/')}/',
      );
      final superChat = _decode('type@=voice_trlt/list@=${Stt.escape('$item/')}/').single as DanmakuSuperChat;
      expect(superChat.price, 50);
      expect(superChat.text, '语音');
      expect(superChat.userName, '观众');
      expect(superChat.avatar, Uri.parse('https://b.douyucdn.cn/c.jpg'));
      expect(superChat.endAt.difference(superChat.startAt), const Duration(seconds: 60));
    });

    test('dgb gifts carry name, id and count', () {
      final gift = _decode('type@=dgb/rid@=9999/gfid@=824/gfn@=粉丝荧光棒/gfcnt@=10/uid@=1/nn@=观众/').single as DanmakuGift;
      expect((gift.giftId, gift.giftName, gift.count, gift.userName), ('824', '粉丝荧光棒', 10, '观众'));
      expect(_decode('type@=dgb/rid@=1/gfn@=x/'), isEmpty);
    });

    test('one bad packet does not lose the rest of the frame (REG-DOUYU-021)', () {
      final frame = [
        ...DouyuProtocol.packet('type@=chatmsg/rid@=9999/txt@=a/'),
        ...DouyuProtocol.packet('type@=comm_chatmsg/chatmsg@=/cprice@=x/'),
        ...DouyuProtocol.packet('type@=chatmsg/rid@=9999/txt@=b/'),
      ];
      final events = DouyuProtocol.decode(frame, rid: '9999', context: _context);
      expect(events.whereType<DanmakuChat>().map((chat) => chat.text), ['a', 'b']);
    });
  });

  group('recorded frames (fixtures/douyu/danmaku/S13-live)', () {
    final fixture = DanmakuFixture.load('douyu', 'S13-live');
    final rid = fixture.keys['rid']!;
    final events = [
      for (final frame in fixture.incoming)
        ...DouyuProtocol.decode(frame.bytes, rid: rid, context: fixture.context(frame)),
    ];

    test('the client sent loginreq and joingroup for the room', () {
      final sent = fixture.outgoing.expand((frame) => DouyuProtocol.bodies(frame.bytes)).toList();
      expect(sent.take(2), ['type@=loginreq/roomid@=$rid/', 'type@=joingroup/rid@=$rid/gid@=-9999/']);
    });

    test('every chat and gift decodes', () {
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, hasLength(147));
      expect(events.whereType<DanmakuGift>(), hasLength(125));
      expect(chats.every((chat) => chat.text.isNotEmpty && chat.id!.startsWith('douyu:')), isTrue);
      expect(chats.map((chat) => chat.id).toSet(), hasLength(chats.length));
      final first = chats.first;
      expect(first.id, 'douyu:a589a1c28c3b4cea1004170000000000');
      expect(first.userId, '46780819');
      expect(first.text, 'gg');
      expect(first.userLevel, 24);
      expect(first.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519453584));
      expect(chats.where((chat) => chat.color != DanmakuColors.white), isNotEmpty);
      expect(chats.where((chat) => chat.medalName != null), isNotEmpty);
    });

    test('bot marks: most recorded chat has dms or if=1', () {
      final bots = events.whereType<DanmakuChat>().where((chat) => chat.suspectedBot).length;
      expect(bots, lessThan(events.whereType<DanmakuChat>().length ~/ 4));
    });

    test('backlog older than 45 s in the recording is what the gate drops (REG-DANMAKU-009)', () {
      final stamped = events.whereType<DanmakuChat>().where((chat) => chat.sentAt != null).toList();
      expect(stamped.length, greaterThan(100));
      final gate = DanmakuGate();
      final stale = <DanmakuChat>[];
      for (final chat in stamped) {
        final receivedAt = fixture.capturedAt.add(Duration(microseconds: chat.receivedAt));
        final accepted = gate.accepts(chat, receivedAt);
        if (receivedAt.difference(chat.sentAt!) > const Duration(seconds: 45)) {
          stale.add(chat);
          expect(accepted, isFalse);
        } else {
          expect(accepted, isTrue);
        }
      }
      expect(stale.length, lessThan(stamped.length ~/ 10));
    });
  });
}
