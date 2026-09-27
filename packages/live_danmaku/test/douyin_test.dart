import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _room = '7690219000000000000';
final _context = DecodeContext(room: 'douyin:148108118778', session: 5, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

Uint8List _message(String method, List<int> payload, {int msgId = 0}) =>
    (ProtoWriter()
          ..string(1, method)
          ..bytes(2, payload)
          ..integer(3, msgId))
        .toBytes();

Uint8List _chat({int msgId = 11, String roomId = _room, String text = '你好', int createTime = 0, int eventTime = 0}) {
  final common = ProtoWriter()
    ..string(1, 'WebcastChatMessage')
    ..integer(2, msgId)
    ..integer(3, int.parse(roomId));
  if (createTime > 0) common.integer(4, createTime);
  final user = ProtoWriter()
    ..integer(1, 99)
    ..string(3, '观众');
  final chat = ProtoWriter()
    ..bytes(1, common.toBytes())
    ..bytes(2, user.toBytes())
    ..string(3, text);
  if (eventTime > 0) chat.integer(15, eventTime);
  return chat.toBytes();
}

Uint8List _frame(List<Uint8List> messages, {bool gzipped = true, bool needAck = false, int logId = 7}) {
  final response = ProtoWriter();
  for (final message in messages) {
    response.bytes(1, message);
  }
  response.string(5, 'internal_src:dim|wss_push_room_id:$_room');
  if (needAck) response.integer(9, 1);
  final payload = response.toBytes();
  return (ProtoWriter()
        ..integer(2, logId)
        ..string(6, gzipped ? 'gzip' : 'pb')
        ..string(7, 'msg')
        ..bytes(8, gzipped ? gzip.encode(payload) : payload))
      .toBytes();
}

void main() {
  group('handshake (§7)', () {
    test('signature matches an independent implementation of the legacy X-Bogus variant', () {
      expect(
        DouyinProtocol.signaturePlaintext(_room, '7412345678901234567'),
        'live_id=1,aid=6383,version_code=180800,webcast_sdk_version=1.0.15,room_id=$_room,sub_room_id=,'
        'sub_channel_id=,did_rule=3,user_unique_id=7412345678901234567,device_platform=web,device_type=,ac=,'
        'identity=audience',
      );
      expect(DouyinProtocol.signature(_room, '7412345678901234567', r1: 77, r2: 200), '3WNbnYeUF6qP5UwA');
      expect(DouyinProtocol.signature('1', '2', r1: 0, r2: 0), 'fDpl4KiMGEiS7VP7');
    });

    test('both edges share the query; the signature is percent-encoded (REG-DOUYIN-002)', () {
      final endpoints = DouyinProtocol.endpoints(
        roomId: _room,
        userUniqueId: '7412345678901234567',
        signature: 'a+b/c',
        userAgent: 'Mozilla/5.0 (Test)',
        now: DateTime.fromMillisecondsSinceEpoch(1790519968000),
      );
      expect(endpoints.map((uri) => uri.host), DouyinProtocol.hosts);
      final uri = endpoints.first;
      expect(uri.path, '/webcast/im/push/v2/');
      expect(uri.toString(), contains('signature=a%2Bb%2Fc'));
      expect(uri.queryParameters['signature'], 'a+b/c');
      expect(uri.queryParameters['room_id'], _room);
      expect(uri.queryParameters['cursor'], 'h-1_t-1790519968000_r-1_d-1_u-1');
      expect(uri.queryParameters['browser_version'], '5.0 (Test)');
      expect(uri.queryParameters['need_persist_msg_count'], '15');
      expect(uri.queryParameters['webcast_sdk_version'], '1.0.15');
      expect(endpoints.last.query, uri.query);
    });

    test('headers carry the cookie only when there is one', () {
      expect(DouyinProtocol.headers(webRid: '1', userAgent: 'UA'), {
        'User-Agent': 'UA',
        'Origin': 'https://live.douyin.com',
        'Referer': 'https://live.douyin.com/1',
      });
      expect(DouyinProtocol.headers(webRid: '1', userAgent: 'UA', cookie: ' ttwid=1 ')['Cookie'], 'ttwid=1');
    });

    test('heartbeat and ack frames', () {
      expect(ProtoMessage.decode(DouyinProtocol.heartbeat()).string(7), 'hb');
      final ack = ProtoMessage.decode(DouyinProtocol.ack(12345, 'ext'));
      expect(ack.integer(2), 12345);
      expect(ack.string(7), 'ack');
      expect(ack.string(8), 'ext');
      expect(DouyinProtocol.heartbeatInterval, const Duration(seconds: 10));
      expect(DouyinProtocol.silenceTimeout, const Duration(seconds: 45));
    });
  });

  group('decoding (§7)', () {
    test('gzip and plain payloads; ack when asked, after decoding', () {
      for (final gzipped in [true, false]) {
        final frame = DouyinProtocol.decode(
          _frame([_message('WebcastChatMessage', _chat())], gzipped: gzipped, needAck: true),
          roomId: _room,
          context: _context,
        );
        final chat = frame.events.single as DanmakuChat;
        expect(chat.text, '你好');
        expect(chat.userName, '观众');
        expect(chat.userId, '99');
        expect(chat.id, 'douyin:11');
        final ack = ProtoMessage.decode(frame.ack!);
        expect(ack.integer(2), 7);
        expect(ack.string(8), 'internal_src:dim|wss_push_room_id:$_room');
      }
      expect(DouyinProtocol.decode(_frame(const []), roomId: _room, context: _context).ack, isNull);
    });

    test('ids fall back to the envelope; times from createTime or eventTime', () {
      final envelope =
          DouyinProtocol.decode(
                _frame([_message('WebcastChatMessage', _chat(msgId: 0, createTime: 1790519968000), msgId: 55)]),
                roomId: _room,
                context: _context,
              ).events.single
              as DanmakuChat;
      expect(envelope.id, 'douyin:55');
      expect(envelope.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519968000));
      final event =
          DouyinProtocol.decode(
                _frame([_message('WebcastChatMessage', _chat(eventTime: 1790519968))]),
                roomId: _room,
                context: _context,
              ).events.single
              as DanmakuChat;
      expect(event.sentAt, DateTime.fromMillisecondsSinceEpoch(1790519968000));
    });

    test("another broadcast's chat is dropped (CONN-5)", () {
      final frame = DouyinProtocol.decode(
        _frame([_message('WebcastChatMessage', _chat(roomId: '1'))]),
        roomId: _room,
        context: _context,
      );
      expect(frame.events, isEmpty);
    });

    test('RoomUserSeqMessage: exact total first, then the display text; never totalUser', () {
      Uint8List seq({int total = 0, String text = ''}) {
        final writer = ProtoWriter()..integer(7, 7227121);
        if (total > 0) writer.integer(3, total);
        if (text.isNotEmpty) writer.string(10, text);
        return writer.toBytes();
      }

      int? online(Uint8List payload) {
        final events = DouyinProtocol.decode(
          _frame([_message('WebcastRoomUserSeqMessage', payload)]),
          roomId: _room,
          context: _context,
        ).events;
        return events.isEmpty ? null : (events.single as DanmakuOnline).value;
      }

      expect(online(seq(total: 305503, text: '30.6万')), 305503);
      expect(online(seq(text: '30.6万')), 306000);
      expect(online(seq(text: '暂无')), isNull);
      expect(online(seq()), isNull);
    });

    test('a malformed message does not drop the rest of the frame', () {
      final frame = DouyinProtocol.decode(
        _frame([
          _message('WebcastChatMessage', [0x0A, 0x05]),
          _message('WebcastChatMessage', _chat(text: 'ok')),
        ]),
        roomId: _room,
        context: _context,
      );
      expect(frame.events.map((event) => (event as DanmakuChat).text), ['ok']);
    });

    test('audience numbers', () {
      expect(audienceNumber('1,234'), 1234);
      expect(audienceNumber('1.2万'), 12000);
      expect(audienceNumber('6.4w'), 64000);
      expect(audienceNumber('10万+'), 100000);
      expect(audienceNumber('1亿'), 100000000);
      expect(audienceNumber('none'), isNull);
    });
  });

  group('recorded frames (fixtures/douyin/danmaku/S13-live)', () {
    final fixture = DanmakuFixture.load('douyin', 'S13-live');
    final roomId = fixture.keys['roomId']!;
    final frames = [
      for (final frame in fixture.incoming)
        DouyinProtocol.decode(frame.bytes, roomId: roomId, context: fixture.context(frame)),
    ];
    final events = [for (final frame in frames) ...frame.events];

    test('the handshake URL is signed for this broadcast and visitor', () {
      final handshake = (fixture.meta['handshakes'] as List).first as Map<String, dynamic>;
      final url = Uri.parse(handshake['url'] as String);
      expect(url.host, DouyinProtocol.hosts.first);
      expect(url.queryParameters['room_id'], roomId);
      expect(url.queryParameters['user_unique_id'], fixture.keys['userUniqueId']);
      expect(url.queryParameters['signature'], hasLength(16));
      expect((handshake['headers'] as Map)['Cookie'], '<redacted>');
    });

    test('every push asks for an ack and the client sent one per push', () {
      final pushes = frames.where((frame) => frame.ack != null).length;
      final acks = fixture.outgoing.where((frame) => ProtoMessage.decode(frame.bytes).string(7) == 'ack').length;
      expect(pushes, greaterThan(50));
      expect(acks, pushes);
      expect(fixture.outgoing.where((frame) => ProtoMessage.decode(frame.bytes).string(7) == 'hb'), hasLength(4));
    });

    test('chat and online figures decode', () {
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, hasLength(215));
      expect(chats.first.id, 'douyin:7690224691106976802');
      expect(chats.first.text, '木森大气');
      expect(chats.every((chat) => chat.id!.startsWith('douyin:') && chat.sentAt != null), isTrue);
      final online = events.whereType<DanmakuOnline>().map((figure) => figure.value).toList();
      expect(online, hasLength(16));
      expect(online.first, 305503);
      expect(events.whereType<DanmakuOnline>().every((figure) => figure.audience == AudienceKind.online), isTrue);
    });

    test('the first push replays recent history; the gate keeps only the last 45 s', () {
      final gate = DanmakuGate();
      final chats = events.whereType<DanmakuChat>().toList();
      final accepted = chats.where((chat) => gate.accepts(chat, fixture.capturedAt)).length;
      expect(accepted, lessThanOrEqualTo(chats.length));
      expect(accepted, greaterThan(chats.length ~/ 2));
    });

    test('recorded payloads are gzip', () {
      final push = ProtoMessage.decode(fixture.incoming.firstWhere((frame) => frame.bytes.length > 100).bytes);
      final payload = push.bytes(8)!;
      expect(payload.sublist(0, 2), [0x1f, 0x8b]);
      expect(utf8.decode(gzip.decode(payload), allowMalformed: true), contains('Webcast'));
    });
  });
}
