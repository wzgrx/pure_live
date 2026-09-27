import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'kilakila:1', session: 4, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

String _event(String name, Object payload) => '42/live_chat_room_guest,${jsonEncode([name, jsonEncode(payload)])}';

String _message(Map<String, Object?> content, {String room = '9'}) => _event('text_message', {
  'header': {'type': 9},
  'body': {
    'response': {'room_id': room, 'mid': 77, 'created_at': 1790528439786, 'content': jsonEncode(content)},
  },
});

void main() {
  group('protocol (§7)', () {
    test('socket URL, namespace join and ping are text frames', () {
      expect(
        KilakilaProtocol.endpoint('9').toString(),
        'wss://wim.hongrenshuo.com.cn/socket.io/?roomId=9&appId=111&clientType=1&EIO=3&transport=websocket',
      );
      final join = KilakilaProtocol.join('9');
      expect(join, isA<TextFrame>());
      expect(join.text, '40/live_chat_room_guest?roomId=9&appId=111&clientType=1,');
      expect(utf8.decode(join), join.text);
      expect(KilakilaProtocol.ping().text, '2');
    });

    test('join answers: the namespace ack and connect_error code 0 join; another code rejects', () {
      expect(KilakilaProtocol.decode('40/live_chat_room_guest', roomId: '9', context: _context).joined, isTrue);
      expect(
        KilakilaProtocol.decode(
          _event('connect_error', {'code': 0, 'message': 'join success'}),
          roomId: '9',
          context: _context,
        ).joined,
        isTrue,
      );
      expect(
        KilakilaProtocol.decode(_event('connect_error', {'code': 403}), roomId: '9', context: _context).rejected,
        isTrue,
      );
      for (final other in ['0{"sid":"x"}', '40', '41', '3', '42/other,["a","{}"]']) {
        expect(
          KilakilaProtocol.decode(other, roomId: '9', context: _context),
          same(FrameResult.empty),
          reason: other,
        );
      }
    });

    test('chat (t 200) and gift (t 220); other types and other rooms are dropped', () {
      final chat =
          KilakilaProtocol.decode(
                _message({'t': 200, 'u': 3632776065087, 'n': '月亮', 'c': '那个绿色头像', 'l': 48}),
                roomId: '9',
                context: _context,
              ).events.single
              as DanmakuChat;
      expect(chat.text, '那个绿色头像');
      expect(chat.userName, '月亮');
      expect(chat.userId, '3632776065087');
      expect(chat.userLevel, 48);
      expect(chat.id, 'kilakila:77');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790528439786));
      final gift =
          KilakilaProtocol.decode(
                _message({
                  't': 220,
                  'u': '3647255392265',
                  'n': '送礼人',
                  'c': {'name': '清风雨露', 'id': 415506, 'doubleCount': 3, 'price': 6990},
                }),
                roomId: '9',
                context: _context,
              ).events.single
              as DanmakuGift;
      expect(gift.giftName, '清风雨露');
      expect(gift.count, 3);
      expect(gift.yuan, isNull);
      expect(KilakilaProtocol.decode(_message({'t': 603}), roomId: '9', context: _context).events, isEmpty);
      expect(
        KilakilaProtocol.decode(
          _message({'t': 200, 'c': 'x'}, room: '8'),
          roomId: '9',
          context: _context,
        ).events,
        isEmpty,
      );
    });
  });

  group('recorded frames (fixtures/kilakila/danmaku/S07-live)', () {
    final fixture = DanmakuFixture.load('kilakila', 'S07-live');
    final roomId = fixture.keys['roomId']!;

    test('namespace join first, pings answered', () {
      final sent = fixture.outgoing.map((frame) => utf8.decode(frame.bytes)).toList();
      expect(sent.first, KilakilaProtocol.join(roomId).text);
      expect(sent, contains('2'));
      expect(fixture.incoming.map((frame) => frame.text), contains('3'));
      expect(((fixture.meta['handshakes'] as List).single as Map)['url'], KilakilaProtocol.endpoint(roomId).toString());
    });

    test('joins; chat and gifts decode', () {
      var joined = false;
      final events = <DanmakuEvent>[];
      for (final frame in fixture.incoming) {
        final result = KilakilaProtocol.decode(frame.text, roomId: roomId, context: fixture.context(frame));
        joined |= result.joined;
        events.addAll(result.events);
      }
      expect(joined, isTrue);
      expect(events.whereType<DanmakuChat>(), isNotEmpty);
      expect(events.whereType<DanmakuGift>(), isNotEmpty);
      expect(events.whereType<DanmakuChat>().every((chat) => chat.userName.isNotEmpty), isTrue);
    });
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('kilakila', '3674092253247'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://live.hongrenshuo.com.cn/index/roomuser/uid/3674092253247'),
      danmakuKeys: keys,
    );

    test('text-frame join, joined on the namespace ack, ping every 25 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = KilakilaConnector(
          detail: room({'roomId': '9'}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.urls.single, KilakilaProtocol.endpoint('9'));
        expect(socket.sent.single, isA<TextFrame>());
        socket.receive('40/live_chat_room_guest');
        async.flushMicrotasks();
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 25));
        expect((socket.sent.last as TextFrame).text, '2');
      });
    });

    test('without a current broadcast the start fails', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final connector = KilakilaConnector(detail: room(const {}), transport: transport);
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(transport.urls, isEmpty);
      });
    });

    test('the factory knows KilaKila', () {
      expect(danmakuPlatforms, contains('kilakila'));
      expect(danmakuConnectorFor(room({'roomId': '9'}), transport: FakeTransport()), isA<KilakilaConnector>());
    });
  });
}
