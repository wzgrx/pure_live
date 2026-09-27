import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'missevan:1', session: 2, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

/// A frame as the server sends it: flag 1, the UTF-8 length, then Brotli.
/// These use a stored (uncompressed) meta-block, which is valid Brotli.
List<int> _frame(Object message) {
  final plain = utf8.encode(jsonEncode(message));
  final stored = <int>[
    // WBITS 16 (0), ISLAST 0, MNIBBLES 4 (00), MLEN-1 (16 bits), ISUNCOMPRESSED 1.
    ((plain.length - 1) & 0x0f) << 4,
    ((plain.length - 1) >> 4) & 0xff,
    (((plain.length - 1) >> 12) & 0x0f) | 0x10,
    ...plain,
    0x03, // ISLAST, ISLASTEMPTY
  ];
  return [1, plain.length & 0xff, (plain.length >> 8) & 0xff, (plain.length >> 16) & 0xff, ...stored];
}

Map<String, Object?> _message(String text, {int room = 1}) => {
  'type': 'message',
  'event': 'new',
  'room_id': room,
  'msg_id': 'm-1',
  'message': text,
  'user': {
    'user_id': 7,
    'username': '听众',
    'titles': [
      {'type': 'level', 'level': 16},
      {'type': 'medal', 'name': '在花间', 'level': 8},
    ],
  },
};

void main() {
  group('protocol (§7)', () {
    test('session cookie, headers, join and heartbeat', () {
      expect(MissevanProtocol.session(['FM_SESS=20260928|abc; path=/; secure', 'FM_SESS.sig=x']), '20260928|abc');
      expect(MissevanProtocol.session(['a=1; FM_SESS=v2']), 'v2');
      expect(MissevanProtocol.session(['other=1']), isNull);
      expect(MissevanProtocol.headers('s')['cookie'], 'FM_SESS=s');
      final join = jsonDecode(utf8.decode(MissevanProtocol.join('453091860', 'u'))) as Map<String, dynamic>;
      expect(join, {'action': 'join', 'uuid': 'u', 'type': 'room', 'room_id': 453091860});
      expect(utf8.decode(MissevanProtocol.heartbeat()), '❤️');
      expect(
        MissevanProtocol.uuid(Random(1)),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(MissevanProtocol.endpoint('5'), Uri.parse('wss://im.missevan.com/ws?room_id=5'));
    });

    test('frames: Brotli behind a flag and the UTF-8 length; a wrong length or flag is dropped', () {
      expect(MissevanProtocol.text(_frame({'a': '猫耳'})), '{"a":"猫耳"}');
      final wrongLength = [
        ..._frame({'a': 1}),
      ]..[1] += 1;
      expect(MissevanProtocol.text(wrongLength), isNull);
      final wrongFlag = [
        ..._frame({'a': 1}),
      ]..[0] = 0;
      expect(MissevanProtocol.text(wrongFlag), isNull);
      expect(MissevanProtocol.text([1, 2, 3]), isNull);
      expect(MissevanProtocol.decode('❤️', roomId: '1', context: _context).events, isEmpty);
    });

    test('join reply, chat with level and medal, another room dropped', () {
      final joined = MissevanProtocol.decode(
        _frame({'type': 'room', 'event': 'join', 'code': 0}),
        roomId: '1',
        context: _context,
      );
      expect(joined.joined, isTrue);
      expect(
        MissevanProtocol.decode(
          _frame({'type': 'room', 'event': 'join', 'code': 5}),
          roomId: '1',
          context: _context,
        ).rejected,
        isTrue,
      );
      final chat =
          MissevanProtocol.decode(_frame(_message('你好')), roomId: '1', context: _context).events.single as DanmakuChat;
      expect(chat.text, '你好');
      expect(chat.userName, '听众');
      expect(chat.userId, '7');
      expect(chat.id, 'missevan:m-1');
      expect(chat.userLevel, 16);
      expect(chat.medalName, '在花间');
      expect(chat.medalLevel, 8);
      expect(MissevanProtocol.decode(_frame(_message('x', room: 2)), roomId: '1', context: _context).events, isEmpty);
    });

    test('arrays, gifts, cross-room gifts and heat', () {
      final events = MissevanProtocol.decode(
        _frame([
          _message('a'),
          {
            'type': 'gift',
            'event': 'send',
            'room_id': 1,
            'user': {'user_id': 3, 'username': 'u'},
            'gift': {'gift_id': 92264, 'name': '花语笺', 'price': 28, 'num': 2},
          },
          {
            'type': 'gift',
            'event': 'cross_send',
            'room_id': 1,
            'gift': {'name': 'x', 'num': 1},
          },
          {
            'type': 'room',
            'event': 'statistics',
            'room_id': 1,
            'statistics': {'score': 105019, 'online': 22},
          },
        ]),
        roomId: '1',
        context: _context,
      ).events;
      expect(events.whereType<DanmakuChat>(), hasLength(1));
      final gift = events.whereType<DanmakuGift>().single;
      expect(gift.giftName, '花语笺');
      expect(gift.count, 2);
      expect(gift.yuan, isNull);
      final figures = {for (final figure in events.whereType<DanmakuOnline>()) figure.audience: figure.value};
      expect(figures, {AudienceKind.popularity: 105019, AudienceKind.online: 22});
    });
  });

  group('recorded frames (fixtures/missevan/danmaku/S06-live)', () {
    final fixture = DanmakuFixture.load('missevan', 'S06-live');
    final roomId = fixture.keys['roomId']!;

    test('guest session request, handshake with the cookie, join and heartbeat', () {
      final session = fixture.incoming.firstWhere((frame) => frame.url != null);
      expect(session.url, MissevanProtocol.sessionUrl);
      final handshake = (fixture.meta['handshakes'] as List).single as Map<String, dynamic>;
      expect(handshake['url'], fixture.keys['websocket']);
      expect((handshake['headers'] as Map)['cookie'], '<redacted>');
      final sent = fixture.outgoing.map((frame) => utf8.decode(frame.bytes)).toList();
      expect((jsonDecode(sent.first) as Map)['action'], 'join');
      expect(sent, contains('❤️'));
    });

    test('every binary frame decodes; the join is accepted; chats and heat come through', () {
      var joined = false;
      final chats = <DanmakuChat>[];
      final heat = <DanmakuOnline>[];
      for (final frame in fixture.incoming.where((frame) => frame.url == null)) {
        final data = frame.text == null ? frame.bytes : frame.text!;
        if (frame.text == null) expect(MissevanProtocol.text(data), isNotNull, reason: 'frame at ${frame.millis} ms');
        final result = MissevanProtocol.decode(data, roomId: roomId, context: fixture.context(frame));
        joined |= result.joined;
        chats.addAll(result.events.whereType<DanmakuChat>());
        heat.addAll(result.events.whereType<DanmakuOnline>());
      }
      expect(joined, isTrue);
      expect(chats, isNotEmpty);
      expect(chats.every((chat) => chat.id!.startsWith('missevan:') && chat.userName.isNotEmpty), isTrue);
      expect(heat.map((figure) => figure.audience).toSet(), {AudienceKind.popularity, AudienceKind.online});
    });
  });

  group('connector', () {
    RoomDetail room() => RoomDetail(
      card: RoomCard(ref: RoomRef('missevan', '453091860'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://fm.missevan.com/live/453091860'),
      danmakuKeys: const {'roomId': '453091860', 'websocket': 'wss://im.missevan.com/ws?room_id=453091860'},
    );

    test('guest session, handshake cookie, join, joined on the reply, heartbeat every 30 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(
            status: 200,
            url: request.url,
            headers: const {
              'set-cookie': ['FM_SESS=20260928|guest; path=/; secure; httponly'],
            },
            bytes: utf8.encode('{"code":0}'),
          ),
        );
        final transport = FakeTransport(plan: [socket], http: http);
        final connector = MissevanConnector(
          detail: room(),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
          random: Random(3),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(http.requests.single.url, MissevanProtocol.sessionUrl);
        expect(transport.urls.single, Uri.parse('wss://im.missevan.com/ws?room_id=453091860'));
        expect(transport.headers.single['cookie'], 'FM_SESS=20260928|guest');
        expect((jsonDecode(utf8.decode(socket.sent.single)) as Map)['action'], 'join');
        socket.receive(_frame({'type': 'room', 'event': 'join', 'code': 0}));
        async.flushMicrotasks();
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(utf8.decode(socket.sent.last), '❤️');
      });
    });

    test('no guest session: the start fails without connecting', () {
      fakeAsync((async) {
        final transport = FakeTransport(
          http: FakeHttp((request) async => LiveResponse(status: 200, url: request.url, bytes: const [])),
        );
        final connector = MissevanConnector(detail: room(), transport: transport);
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(transport.urls, isEmpty);
        expect((events.last as DanmakuSystem).args.first, 'credentials');
      });
    });

    test('the factory knows Missevan', () {
      expect(danmakuPlatforms, contains('missevan'));
      expect(danmakuConnectorFor(room(), transport: FakeTransport()), isA<MissevanConnector>());
    });
  });
}
