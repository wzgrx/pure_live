import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'chzzk:x', session: 3, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

Map<String, dynamic> _sent(List<int> frame) => jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;

String _chat({
  String msg = '안녕',
  int type = 1,
  String status = 'NORMAL',
  Map<String, Object?> extras = const {},
  int members = 10,
}) => jsonEncode({
  'svcid': 'game',
  'cmd': 93101,
  'bdy': [
    {
      'uid': 'u1',
      'profile': jsonEncode({'nickname': '시청자'}),
      'msg': msg,
      'msgTypeCode': type,
      'msgStatusType': status,
      'extras': jsonEncode(extras),
      'msgTime': 1790525967581,
      'mbrCnt': members,
    },
  ],
});

void main() {
  group('protocol (§7)', () {
    test('server number, token URL and messages', () {
      expect(ChzzkProtocol.endpoint('N2lpu9'), Uri.parse('wss://kr-ss1.chat.naver.com/chat'));
      expect(
        ChzzkProtocol.tokenUrl('N2lpu9').toString(),
        'https://comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=N2lpu9&chatType=STREAMING',
      );
      final join = _sent(ChzzkProtocol.join('N2lpu9', 'tok'));
      expect(join['cmd'], 100);
      expect(join['cid'], 'N2lpu9');
      expect((join['bdy'] as Map)['accTkn'], 'tok');
      expect((join['bdy'] as Map)['auth'], 'READ');
      expect(_sent(ChzzkProtocol.ping()), {'ver': '3', 'cmd': 0});
      expect(_sent(ChzzkProtocol.pong()), {'ver': '3', 'cmd': 10000});
      expect(ChzzkProtocol.accessToken('{"code":200,"content":{"accessToken":"a"}}'), 'a');
      expect(ChzzkProtocol.accessToken('{"code":401,"content":null}'), isNull);
    });

    test('join reply: retCode 0 joins and asks for recent chat; anything else rejects', () {
      final ok = ChzzkProtocol.decode(
        '{"cmd":10100,"retCode":0,"bdy":{"sid":"s1"}}',
        chatChannelId: 'c',
        context: _context,
      );
      expect(ok.joined, isTrue);
      expect(_sent(ok.replies.single)['cmd'], 5101);
      expect(_sent(ok.replies.single)['sid'], 's1');
      final refused = ChzzkProtocol.decode('{"cmd":10100,"retCode":42}', chatChannelId: 'c', context: _context);
      expect(refused.rejected, isTrue);
      final ping = ChzzkProtocol.decode('{"ver":"2","cmd":0}', chatChannelId: 'c', context: _context);
      expect(_sent(ping.replies.single)['cmd'], 10000);
    });

    test('chat: text, name from profile, id, time, online count; hidden and sticker lines dropped', () {
      final events = ChzzkProtocol.decode(_chat(), chatChannelId: 'c', context: _context).events;
      final chat = events.whereType<DanmakuChat>().single;
      expect(chat.text, '안녕');
      expect(chat.userName, '시청자');
      expect(chat.id, 'chzzk:u1:1790525967581');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790525967581));
      final online = events.whereType<DanmakuOnline>().single;
      expect(online.audience, AudienceKind.online);
      expect(online.value, 10);
      expect(
        ChzzkProtocol.decode(
          _chat(status: 'HIDDEN'),
          chatChannelId: 'c',
          context: _context,
        ).events,
        [isA<DanmakuOnline>()],
      );
      expect(ChzzkProtocol.decode(_chat(type: 3), chatChannelId: 'c', context: _context).events, [
        isA<DanmakuOnline>(),
      ]);
    });

    test('donation (93102): a cheese gift plus the text; anonymous donors have no id', () {
      final frame = _chat(
        msg: '응원해요',
        type: 10,
        extras: {'payAmount': 1000, 'isAnonymous': true},
      ).replaceFirst('93101', '93102');
      final events = ChzzkProtocol.decode(frame, chatChannelId: 'c', context: _context).events;
      final gift = events.whereType<DanmakuGift>().single;
      expect(gift.giftName, '치즈');
      expect(gift.count, 1000);
      expect(gift.yuan, isNull);
      expect(gift.userName, '匿名');
      expect(gift.userId, isEmpty);
      expect(events.whereType<DanmakuChat>().single.text, '응원해요');
    });

    test('malformed input is ignored', () {
      for (final data in ['not json', '[1]', '{"cmd":93101,"bdy":"x"}', 42]) {
        expect(ChzzkProtocol.decode(data, chatChannelId: 'c', context: _context).events, isEmpty);
      }
    });
  });

  group('recorded frames (fixtures/chzzk/danmaku/S09-live)', () {
    final fixture = DanmakuFixture.load('chzzk', 'S09-live');
    final channel = fixture.keys['chatChannelId']!;

    test('token request, join with that token, recent chat request, pings', () {
      final token = fixture.incoming.firstWhere((frame) => frame.url != null);
      expect(token.url!.path, '/nng_main/v1/chats/access-token');
      final accessToken = ChzzkProtocol.accessToken(token.text!);
      final sent = fixture.outgoing.map((frame) => _sent(frame.bytes)).toList();
      expect(sent.first['cmd'], 100);
      expect((sent.first['bdy'] as Map)['accTkn'], accessToken);
      expect(sent[1]['cmd'], 5101);
      expect(sent.where((message) => message['cmd'] == 0), isNotEmpty);
      expect(fixture.meta['handshakes'], [
        {'url': ChzzkProtocol.endpoint(channel).toString(), 'headers': ChzzkProtocol.headers},
      ]);
    });

    test('the join is accepted; chat, recent chat and online figures decode', () {
      var joined = false;
      final chats = <DanmakuChat>[];
      final online = <DanmakuOnline>[];
      for (final frame in fixture.incoming.where((frame) => frame.url == null)) {
        final result = ChzzkProtocol.decode(
          frame.text ?? frame.bytes,
          chatChannelId: channel,
          context: fixture.context(frame),
        );
        joined |= result.joined;
        chats.addAll(result.events.whereType<DanmakuChat>());
        online.addAll(result.events.whereType<DanmakuOnline>());
      }
      expect(joined, isTrue);
      expect(chats.length, greaterThan(50));
      expect(chats.every((chat) => chat.userName.isNotEmpty && chat.text.isNotEmpty), isTrue);
      expect(chats.every((chat) => chat.id!.startsWith('chzzk:')), isTrue);
      expect(online, isNotEmpty);
      expect(online.first.value, greaterThan(1000));
    });
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('chzzk', 'a' * 32), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://chzzk.naver.com/live/${'a' * 32}'),
      danmakuKeys: keys,
    );

    test('token, join, joined on 10100, ping every 20 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(
            status: 200,
            url: request.url,
            bytes: utf8.encode('{"code":200,"content":{"accessToken":"tok"}}'),
          ),
        );
        final transport = FakeTransport(plan: [socket], http: http);
        final connector = ChzzkConnector(
          detail: room({'chatChannelId': 'N2lpu9'}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(http.requests.single.url, ChzzkProtocol.tokenUrl('N2lpu9'));
        expect(transport.urls.single, Uri.parse('wss://kr-ss1.chat.naver.com/chat'));
        expect(_sent(socket.sent.single)['cmd'], 100);
        socket.receive('{"cmd":10100,"retCode":0,"bdy":{"sid":"s"}}');
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(socket.sent.map((frame) => _sent(frame)['cmd']), [100, 5101]);
        async.elapse(const Duration(seconds: 20));
        expect(socket.sent.map((frame) => _sent(frame)['cmd']), [100, 5101, 0]);
      });
    });

    test('no chat channel: the start fails without connecting', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final connector = ChzzkConnector(detail: room(const {}), transport: transport);
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

    test('the factory knows CHZZK', () {
      expect(danmakuPlatforms, contains('chzzk'));
      expect(danmakuConnectorFor(room({'chatChannelId': 'x'}), transport: FakeTransport()), isA<ChzzkConnector>());
    });
  });
}
