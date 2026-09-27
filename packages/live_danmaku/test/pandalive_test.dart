import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'pandalive:daisy00', session: 7, receivedAt: 1, now: DateTime.utc(2026, 9, 27));
const _channel = '24133575';

String _push(Map<String, Object?> data, {String channel = _channel, int offset = 1}) => jsonEncode({
  'result': {
    'channel': channel,
    'data': {'data': data, 'offset': offset},
  },
});

const _play =
    '{"result":true,"message":"x","channel":"24133575","token":"a.b.c","media":{"userId":"daisy00","isLive":true}}';

void main() {
  group('protocol (§7)', () {
    test('commands: connect with the token, subscribe to the channel, numbered pings', () {
      expect(jsonDecode(PandaliveProtocol.connect('a.b.c').text), {
        'params': {'token': 'a.b.c', 'name': 'js'},
        'id': 1,
      });
      expect(jsonDecode(PandaliveProtocol.subscribe(_channel).text), {
        'method': 1,
        'params': {'channel': _channel},
        'id': 2,
      });
      expect(jsonDecode(PandaliveProtocol.ping(5).text), {'method': 7, 'id': 5});
    });

    test('live/play: the session of a public broadcast, the code of a refusal', () {
      expect(PandaliveProtocol.session(_play), (channel: _channel, token: 'a.b.c'));
      const refused = '{"result":false,"message":"x","errorData":{"code":"needAdult"}}';
      expect(PandaliveProtocol.session(refused), isNull);
      expect(PandaliveProtocol.refusal(refused), 'needAdult');
      expect(PandaliveProtocol.session('<html>'), isNull);
    });

    test('replies: the subscribe answer joins, an error rejects, several replies share a frame', () {
      final both = PandaliveProtocol.decode(
        '{"id":1,"result":{"client":"c","ttl":1798}}\n{"id":2,"result":{}}',
        channel: _channel,
        context: _context,
      );
      expect(both.joined, isTrue);
      expect(both.rejected, isFalse);
      final expired = PandaliveProtocol.decode(
        '{"id":1,"error":{"code":109,"message":"token expired"}}',
        channel: _channel,
        context: _context,
      );
      expect(expired.rejected, isTrue);
      expect(PandaliveProtocol.decode('{"id":3}', channel: _channel, context: _context).events, isEmpty);
    });

    test('chat (bj, chatter, manager, support), emoticons, gifts; other types and channels are ignored', () {
      final chat =
          PandaliveProtocol.decode(
                _push({
                  'type': 'chatter',
                  'message': 'ㅎㅎ',
                  'created_at': 1790533910,
                  'id': 'viewer1',
                  'nk': '시청자',
                }, offset: 1532),
                channel: _channel,
                context: _context,
              ).events.single
              as DanmakuChat;
      expect(chat.text, 'ㅎㅎ');
      expect(chat.userName, '시청자');
      expect(chat.userId, 'viewer1');
      expect(chat.id, 'pandalive:24133575:1532');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790533910000));
      final emoticon =
          PandaliveProtocol.decode(
                _push({
                  'type': 'manager',
                  'message': '',
                  'emoticon': {
                    'block': {'name': 'pandaS응원gif'},
                  },
                  'id': 'm',
                  'nk': 'M',
                }),
                channel: _channel,
                context: _context,
              ).events.single
              as DanmakuChat;
      expect(emoticon.text, '[pandaS응원gif]');
      for (final (type, extra, id, name) in [
        ('SponCoin', <String, Object?>{}, 'heart', '하트'),
        ('SponCoin', <String, Object?>{'heart': <String, Object?>{}}, 'signature', '시그니처하트'),
        ('ItemCoin', <String, Object?>{}, 'item', '스페셜하트'),
      ]) {
        final gift =
            PandaliveProtocol.decode(
                  _push({
                    'type': type,
                    'message': jsonEncode({'nick': '팬', 'id': 'fan1', 'coin': 2852, ...extra}),
                    'created_at': 1790534029,
                  }),
                  channel: _channel,
                  context: _context,
                ).events.single
                as DanmakuGift;
        expect((gift.giftId, gift.giftName, gift.count, gift.userName, gift.userId), (id, name, 2852, '팬', 'fan1'));
      }
      for (final other in [
        _push({'type': 'MediaUpdate', 'message': '{"likeCnt":40}'}),
        _push({'type': 'Recommend', 'message': '{"nick":"x"}'}),
        _push({'type': 'chatter', 'message': 'x', 'nk': 'y'}, channel: '999'),
        _push({'type': 'chatter', 'message': '  ', 'nk': 'y'}),
        '{"result":{"type":7,"data":{"code":3005,"reason":"expired"}}}',
        'nonsense',
      ]) {
        expect(
          PandaliveProtocol.decode(other, channel: _channel, context: _context).events,
          isEmpty,
          reason: other,
        );
      }
    });
  });

  test('recorded frames (fixtures/pandalive/danmaku/S07-live): token, commands, chat', () {
    final fixture = DanmakuFixture.load('pandalive', 'S07-live');
    final play = fixture.incoming.firstWhere((frame) => frame.url != null);
    expect(play.url, PandaliveProtocol.play);
    final session = PandaliveProtocol.session(play.text!)!;
    final sent = [for (final frame in fixture.outgoing) jsonDecode(utf8.decode(frame.bytes)) as Map<String, dynamic>];
    expect(sent[0], {
      'params': {'token': session.token, 'name': 'js'},
      'id': 1,
    });
    expect(sent[1], {
      'method': 1,
      'params': {'channel': session.channel},
      'id': 2,
    });
    expect(sent.skip(2).map((command) => command['method']), everyElement(7));
    var joined = false;
    final chats = <DanmakuChat>[];
    for (final frame in fixture.incoming.where((frame) => frame.url == null)) {
      final result = PandaliveProtocol.decode(frame.text, channel: session.channel, context: fixture.context(frame));
      joined = joined || result.joined;
      chats.addAll(result.events.whereType<DanmakuChat>());
    }
    expect(joined, isTrue);
    expect(chats, hasLength(greaterThan(10)));
    expect(chats.map((chat) => chat.id).toSet(), hasLength(chats.length));
    expect(chats.every((chat) => chat.userName.isNotEmpty && chat.text.isNotEmpty), isTrue);
  });

  group('connector', () {
    RoomDetail room(Map<String, String> keys) => RoomDetail(
      card: RoomCard(ref: RoomRef('pandalive', 'daisy00'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://www.pandalive.co.kr/play/daisy00'),
      danmakuKeys: keys,
    );

    test('live/play first, then connect and subscribe; joined on the subscribe reply; pings every 25 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(status: 200, url: request.url, bytes: utf8.encode(_play)),
        );
        final transport = FakeTransport(plan: [socket], http: http);
        final connector = PandaliveConnector(
          detail: room(const {'userId': 'daisy00', 'channel': _channel}),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        final request = http.requests.single;
        expect(request.url, PandaliveProtocol.play);
        expect(Uri.splitQueryString(utf8.decode(request.body!)), containsPair('userId', 'daisy00'));
        expect(transport.urls.single, PandaliveProtocol.endpoint);
        expect(
          [for (final frame in socket.sent) (frame as TextFrame).text],
          [PandaliveProtocol.connect('a.b.c').text, PandaliveProtocol.subscribe(_channel).text],
        );
        expect(joined, isNull);
        socket.receive('{"id":1,"result":{"client":"c"}}\n{"id":2,"result":{}}');
        async.flushMicrotasks();
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 25));
        expect((socket.sent.last as TextFrame).text, PandaliveProtocol.ping(3).text);
        async.elapse(const Duration(seconds: 25));
        expect((socket.sent.last as TextFrame).text, PandaliveProtocol.ping(4).text);
      });
    });

    test('a refused live/play (19+) does not connect', () {
      fakeAsync((async) {
        final http = FakeHttp(
          (request) async => LiveResponse(
            status: 400,
            url: request.url,
            bytes: utf8.encode('{"result":false,"message":"x","errorData":{"code":"needAdult"}}'),
          ),
        );
        final transport = FakeTransport(http: http);
        final connector = PandaliveConnector(detail: room(const {'userId': 'daisy00'}), transport: transport);
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(transport.urls, isEmpty);
      });
    });

    test('the factory knows PandaTV', () {
      expect(danmakuPlatforms, contains('pandalive'));
      expect(danmakuConnectorFor(room(const {}), transport: FakeTransport()), isA<PandaliveConnector>());
    });
  });
}
