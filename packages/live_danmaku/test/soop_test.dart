import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'soop:khm11903', session: 3, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

void main() {
  group('packets (§7.2)', () {
    test('login, join and ping match the web client byte for byte', () {
      expect(utf8.decode(SoopProtocol.login()), '\x1b\x09000100000600\x0c\x0c\x0c16\x0c');
      expect(utf8.decode(SoopProtocol.join('4172')), '\x1b\x09000200001000\x0c4172\x0c\x0c\x0c\x0c\x0c');
      expect(utf8.decode(SoopProtocol.ping()), '\x1b\x09000000000100\x0c');
    });

    test('a frame splits into packets by length; UTF-8 lengths count bytes', () {
      final chat = SoopProtocol.packet(5, ['', '안녕', 'viewer(2)', '0', '0', '3', '시청자', '1']);
      final frame = [...SoopProtocol.ping(), ...chat];
      final packets = SoopProtocol.packets(frame);
      expect(packets.map((p) => p.service), [0, 5]);
      final message = SoopProtocol.chat(packets.last, _context)!;
      expect((message.text, message.userId, message.userName), ('안녕', 'viewer', '시청자'));
      expect(SoopProtocol.packets(frame.sublist(0, frame.length - 1)).map((p) => p.service), [0]);
    });

    test('endpoints: TLS on the next port first, then the plain port', () {
      final endpoints = SoopProtocol.endpoints(host: 'chat-6E0A4C63.sooplive.com', port: 9000, bj: 'khm11903');
      expect(endpoints.map((uri) => uri.toString()), [
        'wss://chat-6e0a4c63.sooplive.com:9001/Websocket/khm11903',
        'ws://chat-6e0a4c63.sooplive.com:9000/Websocket/khm11903',
      ]);
    });
  });

  group('recorded frames (fixtures/soop/danmaku/S07-live)', () {
    final fixture = DanmakuFixture.load('soop', 'S07-live');

    test('the client logged in, then joined the chat room after the login answer', () {
      final sent = [for (final frame in fixture.outgoing) ...SoopProtocol.packets(frame.bytes)];
      expect(sent.take(2).map((p) => p.service), [1, 2]);
      expect(sent[1].fields[1], fixture.keys['chatNo']);
      expect(fixture.meta['handshakes'], hasLength(2), reason: 'TLS port refused, plain port answered');
    });

    test('chat lines decode; other services are ignored', () {
      final chats = [
        for (final frame in fixture.incoming)
          for (final packet in SoopProtocol.packets(frame.bytes)) ?SoopProtocol.chat(packet, fixture.context(frame)),
      ];
      expect(chats.length, greaterThan(100));
      expect(chats.every((chat) => chat.text.isNotEmpty && chat.userName.isNotEmpty), isTrue);
    });

    test('the connector replays the recording', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = SoopConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.options.single.protocols, ['chat']);
        expect(transport.options.single.exactHeaders, isTrue);
        expect(transport.urls.single.scheme, 'wss');
        expect(SoopProtocol.packets(socket.sent.single).single.service, 1);
        for (final frame in fixture.incoming) {
          socket.receive(frame.bytes);
        }
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(SoopProtocol.packets(socket.sent[1]).single.service, 2, reason: 'join answers the login');
        expect(events.whereType<DanmakuChat>().length, greaterThan(100));
        async.elapse(const Duration(seconds: 20));
        expect(SoopProtocol.packets(socket.sent.last).single.service, 0, reason: 'ping every 20 s');
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('a room detail without the chat server ends the start (credentials)', () {
      fakeAsync((async) {
        final connector = SoopConnector(
          detail: RoomDetail(
            card: RoomCard(ref: RoomRef('soop', 'khm11903'), title: '', anchorName: '', state: LiveState.live),
            link: Uri.parse('https://play.sooplive.co.kr/khm11903'),
            danmakuKeys: const {'bj': 'khm11903'},
          ),
          transport: FakeTransport(),
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'credentials');
      });
    });
  });
}
