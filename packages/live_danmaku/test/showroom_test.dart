import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'showroom:1', session: 7, receivedAt: 1, now: DateTime.utc(2026, 9, 27));
const _key = 'abc:123';

String _msg(Map<String, Object?> json, {String key = _key}) => 'MSG\t$key\t${jsonEncode(json)}';

void main() {
  group('protocol (§7)', () {
    test('subscribe and ping are text frames', () {
      expect(ShowroomProtocol.subscribe(_key).text, 'SUB\tabc:123');
      expect(ShowroomProtocol.ping().text, 'PING\tshowroom');
      expect(ShowroomProtocol.endpoint('online.showroom-live.com'), Uri.parse('wss://online.showroom-live.com/'));
    });

    test('comments (t 1), gifts (t 2); other types, other keys and acks are ignored', () {
      final chat =
          ShowroomProtocol.decode(
                _msg({'t': 1, 'u': 7103752, 'ac': 'なっち', 'cm': 'www', 'created_at': 1790532796}),
                key: _key,
                context: _context,
              ).single
              as DanmakuChat;
      expect(chat.text, 'www');
      expect(chat.userName, 'なっち');
      expect(chat.userId, '7103752');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790532796000));
      final gift =
          ShowroomProtocol.decode(
                _msg({'t': 2, 'u': 1, 'ac': 'K', 'g': 3000421, 'n': 4, 'created_at': 1}),
                key: _key,
                context: _context,
              ).single
              as DanmakuGift;
      expect(gift.giftId, '3000421');
      expect(gift.count, 4);
      for (final other in [
        _msg({'t': 18, 'm': 'visit'}),
        _msg({'t': 1, 'cm': 'x'}, key: 'other:1'),
        'ACK\tshowroom',
        'MSG\tbroken',
      ]) {
        expect(
          ShowroomProtocol.decode(other, key: _key, context: _context),
          isEmpty,
          reason: other,
        );
      }
    });
  });

  test('recorded frames (fixtures/showroom/danmaku/S06-live)', () {
    final fixture = DanmakuFixture.load('showroom', 'S06-live');
    final key = fixture.keys['bcsvrKey']!;
    final sent = fixture.outgoing.map((frame) => utf8.decode(frame.bytes)).toList();
    expect(sent.first, 'SUB\t$key');
    expect(sent, contains('PING\tshowroom'));
    final chats = [
      for (final frame in fixture.incoming)
        ...ShowroomProtocol.decode(frame.text ?? frame.bytes, key: key, context: fixture.context(frame)),
    ].whereType<DanmakuChat>().toList();
    expect(chats, hasLength(greaterThan(10)));
    expect(chats.every((chat) => chat.userName.isNotEmpty), isTrue);
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('showroom', '1'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://www.showroom-live.com/r/x'),
      danmakuKeys: keys,
    );

    test('subscribes on open, joined at once, pings every 60 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = ShowroomConnector(
          detail: room(const {'bcsvrKey': _key, 'bcsvrHost': 'online.showroom-live.com'}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect((socket.sent.single as TextFrame).text, 'SUB\t$_key');
        async.elapse(const Duration(seconds: 60));
        expect((socket.sent.last as TextFrame).text, 'PING\tshowroom');
      });
    });

    test('offline rooms (no key) and foreign hosts do not connect', () {
      fakeAsync((async) {
        for (final keys in [
          const <String, String>{},
          const {'bcsvrKey': _key, 'bcsvrHost': 'evil.example.test'},
        ]) {
          final transport = FakeTransport();
          final connector = ShowroomConnector(detail: room(keys), transport: transport);
          connector.events.listen((_) {});
          bool? joined;
          unawaited(connector.connect().then((value) => joined = value));
          async.flushMicrotasks();
          expect(joined, isFalse);
          expect(transport.urls, isEmpty);
        }
      });
    });

    test('the factory knows SHOWROOM', () {
      expect(danmakuPlatforms, contains('showroom'));
      expect(danmakuConnectorFor(room(const {'bcsvrKey': _key}), transport: FakeTransport()), isA<ShowroomConnector>());
    });
  });
}
