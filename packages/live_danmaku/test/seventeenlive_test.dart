import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: '17live:1', session: 7, receivedAt: 1, now: DateTime.utc(2026, 9, 28));
const _room = '29046769';

String _packed(Map<String, Object?> payload) => base64.encode(gzip.encode(utf8.encode(jsonEncode(payload))));

String _message(Map<String, Object?> payload, {String channel = _room, String id = 'abc:0'}) => jsonEncode({
  'action': 15,
  'channel': channel,
  'messages': [
    {'id': id, 'data': _packed(payload)},
  ],
});

void main() {
  group('protocol (§7)', () {
    test('auth answer, socket, ATTACH', () {
      expect(SeventeenliveProtocol.token('{"provider":1,"token":"app.tok"}'), 'app.tok');
      expect(SeventeenliveProtocol.token('{"provider":2,"token":"pubnub"}'), isNull);
      expect(SeventeenliveProtocol.token('<html>'), isNull);
      final url = SeventeenliveProtocol.endpoint('app.tok');
      expect(url.scheme, 'wss');
      expect(url.host, '17media.realtime.ably.net');
      expect(url.queryParameters, {'access_token': 'app.tok', 'format': 'json', 'heartbeats': 'true', 'v': '3'});
      expect(jsonDecode(SeventeenliveProtocol.attach(_room).text), {'action': 10, 'channel': _room});
    });

    test('ATTACHED joins; errors reject; heartbeats and other channels are nothing', () {
      expect(
        SeventeenliveProtocol.decode('{"action":11,"channel":"$_room"}', roomId: _room, context: _context).joined,
        isTrue,
      );
      for (final refused in [
        '{"action":9,"error":{"code":40142,"message":"Token expired"}}',
        '{"action":6,"error":{"code":40142}}',
        '{"action":13,"channel":"$_room","error":{"code":40160}}',
      ]) {
        expect(
          SeventeenliveProtocol.decode(refused, roomId: _room, context: _context).rejected,
          isTrue,
          reason: refused,
        );
      }
      expect(SeventeenliveProtocol.decode('{"action":0}', roomId: _room, context: _context).events, isEmpty);
      expect(
        SeventeenliveProtocol.decode(
          _message({
            'type': 3,
            'commentMsg': {
              'comment': {'text': 'x'},
            },
          }, channel: '1'),
          roomId: _room,
          context: _context,
        ).events,
        isEmpty,
      );
    });

    test('comments (3), gifts (13) and viewers (38) from gzip + base64 payloads; other types are ignored', () {
      final chat =
          SeventeenliveProtocol.decode(
                _message({
                  'type': 3,
                  'commentMsg': {
                    'comment': {'text': 'こんばんは'},
                    'content': 'こんばんは',
                    'sendTime': 1790539305272,
                    'displayUser': {'userID': 'u-1', 'displayName': 'みかさ'},
                  },
                }),
                roomId: _room,
                context: _context,
              ).events.single
              as DanmakuChat;
      expect((chat.text, chat.userName, chat.userId, chat.id), ('こんばんは', 'みかさ', 'u-1', '17live:abc:0'));
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790539305272));
      final gift =
          SeventeenliveProtocol.decode(
                _message({
                  'type': 13,
                  'giftMsg': {
                    'giftID': '2609_jp_cp_akanya',
                    'displayUser': {'userID': 'u-2', 'displayName': 'toshi'},
                  },
                }),
                roomId: _room,
                context: _context,
              ).events.single
              as DanmakuGift;
      expect(
        (gift.giftId, gift.giftName, gift.count, gift.userName),
        ('2609_jp_cp_akanya', '2609_jp_cp_akanya', 1, 'toshi'),
      );
      final online =
          SeventeenliveProtocol.decode(
                _message({
                  'type': 38,
                  'liveinfo': {'liveViewerCount': 95},
                }),
                roomId: _room,
                context: _context,
              ).events.single
              as DanmakuOnline;
      expect((online.audience, online.value), (AudienceKind.online, 95));
      for (final type in [6, 28, 74, 79]) {
        expect(
          SeventeenliveProtocol.decode(_message({'type': type}), roomId: _room, context: _context).events,
          isEmpty,
        );
      }
      expect(SeventeenliveProtocol.payload('{"type":3}'), {'type': 3});
      expect(SeventeenliveProtocol.payload('H4sInotgzip'), isNull);
    });
  });

  test('recorded frames (fixtures/17live/danmaku/S05-live): token, ATTACH, comments', () {
    final fixture = DanmakuFixture.load('17live', 'S05-live');
    final auth = fixture.incoming.firstWhere((frame) => frame.url != null);
    expect(auth.url, SeventeenliveProtocol.auth);
    final token = SeventeenliveProtocol.token(auth.text!)!;
    expect(
      (fixture.meta['handshakes'] as List).single,
      containsPair('url', SeventeenliveProtocol.endpoint(token).toString()),
    );
    expect(fixture.outgoing.map((frame) => utf8.decode(frame.bytes)), [SeventeenliveProtocol.attach(_room).text]);
    var joined = false;
    final chats = <DanmakuChat>[];
    for (final frame in fixture.incoming.where((frame) => frame.url == null)) {
      final result = SeventeenliveProtocol.decode(frame.text, roomId: _room, context: fixture.context(frame));
      joined = joined || result.joined;
      chats.addAll(result.events.whereType<DanmakuChat>());
    }
    expect(joined, isTrue);
    expect(chats, hasLength(greaterThanOrEqualTo(5)));
    expect(chats.every((chat) => chat.userName.isNotEmpty && chat.id != null), isTrue);
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('17live', _room), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://17.live/ja/live/$_room'),
      danmakuKeys: keys,
    );

    test('token first, ATTACH on open, joined on ATTACHED, nothing sent afterwards, watchdog at 90 s', () {
      fakeAsync((async) {
        final first = FakeSocket();
        final second = FakeSocket();
        final http = FakeHttp(
          (request) async =>
              LiveResponse(status: 200, url: request.url, bytes: utf8.encode('{"provider":1,"token":"app.tok"}')),
        );
        final transport = FakeTransport(plan: [first, second], http: http);
        final connector = SeventeenliveConnector(
          detail: room(const {'roomId': _room}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 28)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(http.requests.single.method, 'POST');
        expect(transport.urls.single, SeventeenliveProtocol.endpoint('app.tok'));
        expect([for (final frame in first.sent) (frame as TextFrame).text], [SeventeenliveProtocol.attach(_room).text]);
        expect(joined, isNull);
        first.receive('{"action":11,"channel":"$_room"}');
        async.flushMicrotasks();
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 60));
        expect(first.sent, hasLength(1));
        expect(transport.urls, hasLength(1));
        async.elapse(const Duration(seconds: 32));
        expect(transport.urls, hasLength(2));
      });
    });

    test('a non-Ably provider does not connect', () {
      fakeAsync((async) {
        final http = FakeHttp(
          (request) async =>
              LiveResponse(status: 200, url: request.url, bytes: utf8.encode('{"provider":2,"token":"x"}')),
        );
        final transport = FakeTransport(http: http);
        final connector = SeventeenliveConnector(detail: room(const {'roomId': _room}), transport: transport);
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(transport.urls, isEmpty);
      });
    });

    test('the factory knows 17LIVE', () {
      expect(danmakuPlatforms, contains('17live'));
      expect(danmakuConnectorFor(room(const {}), transport: FakeTransport()), isA<SeventeenliveConnector>());
    });
  });
}
