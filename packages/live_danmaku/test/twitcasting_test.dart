import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'twitcasting:x', session: 6, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

void main() {
  group('protocol (§7)', () {
    test('socket request and answer', () {
      expect(utf8.decode(TwitcastingProtocol.form('841529001')), 'movie_id=841529001');
      expect(
        TwitcastingProtocol.socket('{"url":"wss://1-2-3-4.twitcasting.tv/event.pubsub/v1/streams/1/events?token=t"}'),
        isNotNull,
      );
      expect(TwitcastingProtocol.socket('{"url":"https://twitcasting.tv/"}'), isNull);
      expect(TwitcastingProtocol.socket('nope'), isNull);
    });

    test('comments and gifts; the empty keepalive array', () {
      final events = TwitcastingProtocol.decode(
        jsonEncode([
          {
            'type': 'comment',
            'id': 33856159341,
            'message': '恐ろしい',
            'createdAt': 1790531991000,
            'author': {'id': 'g:1', 'name': 'Nao'},
          },
          {
            'type': 'gift',
            'id': 7,
            'item': {'id': 'tea', 'name': 'お茶'},
            'sender': {'id': 'c:2', 'name': 'S'},
          },
          {'type': 'unknown'},
        ]),
        context: _context,
      );
      final chat = events.whereType<DanmakuChat>().single;
      expect(chat.text, '恐ろしい');
      expect(chat.userName, 'Nao');
      expect(chat.id, 'twitcasting:33856159341');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790531991000));
      expect(events.whereType<DanmakuGift>().single.giftName, 'お茶');
      expect(TwitcastingProtocol.decode('[]', context: _context), isEmpty);
      expect(TwitcastingProtocol.decode('garbage', context: _context), isEmpty);
    });
  });

  test('recorded frames (fixtures/twitcasting/danmaku/S08-live): socket URL, comments, keepalives', () {
    final fixture = DanmakuFixture.load('twitcasting', 'S08-live');
    final pubsub = fixture.incoming.firstWhere((frame) => frame.url != null);
    expect(pubsub.url, TwitcastingProtocol.pubsubUrl);
    final socket = TwitcastingProtocol.socket(pubsub.text!)!;
    expect(((fixture.meta['handshakes'] as List).single as Map)['url'], socket.toString());
    expect(fixture.outgoing, isEmpty);
    final chats = [
      for (final frame in fixture.incoming.where((frame) => frame.url == null))
        ...TwitcastingProtocol.decode(frame.text, context: fixture.context(frame)).whereType<DanmakuChat>(),
    ];
    expect(chats, hasLength(greaterThan(5)));
    expect(chats.every((chat) => chat.userName.isNotEmpty && chat.id!.startsWith('twitcasting:')), isTrue);
    expect(fixture.incoming.map((frame) => frame.text), contains('[]'));
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('twitcasting', 'x'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://twitcasting.tv/x'),
      danmakuKeys: keys,
    );

    test('signed URL first, joined on open, no client frames', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(
            status: 200,
            url: request.url,
            bytes: utf8.encode('{"url":"wss://1.twitcasting.tv/event.pubsub/v1/streams/9/events?token=t"}'),
          ),
        );
        final transport = FakeTransport(plan: [socket], http: http);
        final connector = TwitcastingConnector(
          detail: room({'movieId': '9'}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(utf8.decode(http.requests.single.body!), 'movie_id=9');
        expect(transport.urls.single.path, '/event.pubsub/v1/streams/9/events');
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 60));
        expect(socket.sent, isEmpty);
      });
    });

    test('offline rooms have no movie and do not connect', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final connector = TwitcastingConnector(detail: room(const {}), transport: transport);
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(transport.urls, isEmpty);
      });
    });

    test('the factory knows TwitCasting', () {
      expect(danmakuPlatforms, contains('twitcasting'));
      expect(danmakuConnectorFor(room({'movieId': '9'}), transport: FakeTransport()), isA<TwitcastingConnector>());
    });
  });
}
