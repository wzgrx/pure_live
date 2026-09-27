import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

int _uri(List<int> packet) => ByteData.sublistView(Uint8List.fromList(packet)).getUint32(4, Endian.little);

/// A text chat packet as the service sends it (group message, app 31).
Uint8List _chat({required int top, required int sub, required String text, String name = '观众'}) {
  final block = YyWriter()
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..u32(0xffffffec)
    ..u32(text.length * 2);
  text.codeUnits.forEach(block.u16);
  block.u32(0);
  final chatBytes = block.take();
  final message = YyWriter(3104600)
    ..u32(42)
    ..u32(top)
    ..u32(sub)
    ..bytes16(chatBytes)
    ..latin('')
    ..latin('')
    ..bytes16(utf8.encode(name))
    ..u32(0);
  return (YyWriter(533080)
        ..u64(1)
        ..u64(top)
        ..u32(31)
        ..bytes32(message.take()))
      .take();
}

void main() {
  group('marshalling (§7.2)', () {
    test('writer and reader agree on every type; a packet starts with its length, uri and 200', () {
      final packet =
          (YyWriter(794116)
                ..u8(7)
                ..u16(0xbeef)
                ..u32(0xdeadbeef)
                ..u64(0x123456789a)
                ..latin('abc')
                ..bytes32([1, 2]))
              .take();
      final reader = YyReader(packet);
      expect(reader.u32(), packet.length);
      expect(reader.u32(), 794116);
      expect(reader.u16(), 200);
      expect(reader.u8(), 7);
      expect(reader.u16(), 0xbeef);
      expect(reader.u32(), 0xdeadbeef);
      expect(reader.u64(), 0x123456789a);
      expect(reader.latin(), 'abc');
      expect(reader.bytes32(), [1, 2]);
      expect(reader.remaining, 0);
      expect(reader.u8, throwsFormatException);
    });

    test('one frame carries several packets; a truncated one stops the split', () {
      final frame = [..._chat(top: 1, sub: 1, text: 'a'), ..._chat(top: 1, sub: 1, text: 'b')];
      expect(YyProtocol.decode(frame).whereType<YyChat>().map((chat) => chat.text), ['a', 'b']);
      expect(YyProtocol.decode(frame.sublist(0, frame.length - 3)), hasLength(1));
    });
  });

  group('messages (§7.4)', () {
    test('chat fields; XML-wrapped text gives its txt attribute', () {
      final chat = YyProtocol.decode(_chat(top: 5, sub: 6, text: '你好', name: 'viewer')).single as YyChat;
      expect((chat.topSid, chat.subSid, chat.uid, chat.text, chat.userName), (5, 6, 42, '你好', 'viewer'));
      expect(
        YyProtocol.plainText(
          '<?xml version="1.0"?><msg><extra id="yyentmember"><member vip="0"/></extra> '
          '<txt data="我听到这歌&amp;就看到/{tx"/><mobMedal replace="1"></mobMedal></msg>',
        ),
        '我听到这歌&就看到/{tx',
      );
      expect(YyProtocol.plainText('<?xml version="1.0"?><msg></msg>'), '');
      expect(YyProtocol.plainText(' plain '), 'plain');
    });

    test('the join packet routes 2048258 with the anonymous channel properties', () {
      final [router, subscribe] = YyProtocol.join(uid: 7, topSid: 100, subSid: 101, trace: 'F7_yymwebh5_0');
      expect(_uri(router), 513035);
      expect(_uri(subscribe), 538456);
      final reader = YyReader(router, 10)..latin();
      expect(reader.u32(), 2048258);
      reader.u16();
      final payload = YyReader(reader.bytes32());
      expect([payload.u32(), payload.u32(), payload.u32(), payload.u32(), payload.u32()], [7, 100, 101, 2, 2]);
      expect(YyProtocol.endpoint('u-1').toString(), startsWith('wss://h5-sinchl.yy.com/websocket?appid=yymwebh5'));
    });
  });

  group('recorded frames (fixtures/yy/danmaku/S08-live)', () {
    final fixture = DanmakuFixture.load('yy', 'S08-live');
    final top = int.parse(fixture.keys['sid']!);
    final incoming = [for (final frame in fixture.incoming) ...YyProtocol.decode(frame.bytes)];

    test('the client ran the §7.3 sequence', () {
      final sent = [for (final frame in fixture.outgoing) _uri(frame.bytes)];
      expect(sent.take(6), [778244, 775684, 513035, 538456, 537944, 537944]);
      expect(sent.skip(6).toSet(), {794116}, reason: 'then only pings');
    });

    test('the server accepted the anonymous login, the AP login and the join', () {
      expect(incoming.whereType<YyAnonymousLogin>().single.ok, isTrue);
      expect(incoming.whereType<YyApLogin>().single.code, 200);
      final join = incoming.whereType<YyJoin>().single;
      expect((join.status, join.topSid, join.subSid), (4, top, top));
    });

    test('chat lines of this channel decode', () {
      final chats = incoming.whereType<YyChat>().toList();
      expect(chats, hasLength(2));
      expect(chats.every((chat) => chat.topSid == top && chat.text.isNotEmpty && chat.userName.isNotEmpty), isTrue);
      expect(chats.every((chat) => !chat.text.startsWith('<')), isTrue, reason: 'XML wrappers unwrapped');
    });

    test('the connector replays the recording: joins, then emits the chat', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = YyConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
          random: Random(1),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.options.single.exactHeaders, isTrue);
        expect(transport.urls.single.host, 'h5-sinchl.yy.com');
        expect(_uri(socket.sent.single), 778244);
        for (final frame in fixture.incoming) {
          socket.receive(frame.bytes);
          async.flushMicrotasks();
        }
        expect(joined, isTrue);
        final sent = [for (final frame in socket.sent) _uri(frame)];
        expect(sent.take(6), [778244, 775684, 513035, 538456, 537944, 537944]);
        expect(events.whereType<DanmakuChat>(), hasLength(2));
        async.elapse(const Duration(seconds: 5));
        expect(_uri(socket.sent.last), 794116, reason: 'AP ping every 5 s');
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test("another channel's chat is dropped (CONN-5)", () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final connector = YyConnector(
          detail: fixture.detail,
          transport: FakeTransport(plan: [socket]),
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        unawaited(connector.connect());
        async.flushMicrotasks();
        for (final frame in fixture.incoming) {
          socket.receive(frame.bytes);
        }
        socket
          ..receive(_chat(top: top + 1, sub: top + 1, text: 'elsewhere'))
          ..receive(_chat(top: top, sub: top, text: 'here'));
        async.flushMicrotasks();
        expect(events.whereType<DanmakuChat>().map((chat) => chat.text), contains('here'));
        expect(events.whereType<DanmakuChat>().map((chat) => chat.text), isNot(contains('elsewhere')));
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });
  });
}
