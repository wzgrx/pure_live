import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'picarto:allatir', session: 5, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

void main() {
  group('protocol (§7)', () {
    test('token query and answer, socket URL', () {
      final query = jsonDecode(utf8.decode(PicartoProtocol.tokenQuery('allatir'))) as Map<String, dynamic>;
      expect(query['query'], contains(r'generateJwtToken(channel_name: $name)'));
      expect(query['variables'], {'name': 'allatir'});
      expect(PicartoProtocol.token('{"data":{"generateJwtToken":{"key":"a.b.c"}}}'), 'a.b.c');
      expect(PicartoProtocol.token('{"data":null}'), isNull);
      expect(PicartoProtocol.token('{"data":{"generateJwtToken":{"key":"nodots"}}}'), isNull);
      expect(PicartoProtocol.endpoint('a.b.c'), Uri.parse('wss://chat.picarto.tv/chat/token=a.b.c'));
    });

    test('chat lines, stream viewers; joins and other types are ignored', () {
      final chat =
          PicartoProtocol.decode(
                jsonEncode({
                  't': 'c',
                  'm': [
                    {
                      't': 'c',
                      'c': '1',
                      'u': '721998',
                      'n': 'Viewer',
                      'm': 'KChAU :race_car:',
                      'id': 'x',
                      'd': 1790530911084,
                      'k': 'f1c7f8',
                    },
                  ],
                }),
                context: _context,
              ).single
              as DanmakuChat;
      expect(chat.text, 'KChAU :race_car:');
      expect(chat.userName, 'Viewer');
      expect(chat.id, 'picarto:x');
      expect(chat.color, 0xf1c7f8);
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790530911084));
      final online =
          PicartoProtocol.decode('{"type":"stream","messages":{"viewers":49,"streams":[]}}', context: _context).single
              as DanmakuOnline;
      expect(online.audience, AudienceKind.online);
      expect(online.value, 49);
      expect(PicartoProtocol.decode('{"t":"un","m":{"u":"1"}}', context: _context), isEmpty);
      expect(PicartoProtocol.decode('{"t":"ur","m":{"u":"0"}}', context: _context), isEmpty);
      expect(PicartoProtocol.decode('nonsense', context: _context), isEmpty);
    });
  });

  test('recorded frames (fixtures/picarto/danmaku/S07-live): token, chat and viewers', () {
    final fixture = DanmakuFixture.load('picarto', 'S07-live');
    final token = fixture.incoming.firstWhere((frame) => frame.url != null);
    expect(token.url, PicartoProtocol.graphql);
    final key = PicartoProtocol.token(token.text!)!;
    expect((fixture.meta['handshakes'] as List).single, containsPair('url', PicartoProtocol.endpoint(key).toString()));
    expect(fixture.outgoing, isEmpty, reason: 'the client sends nothing');
    final events = [
      for (final frame in fixture.incoming.where((frame) => frame.url == null))
        ...PicartoProtocol.decode(frame.text, context: fixture.context(frame)),
    ];
    expect(events.whereType<DanmakuChat>(), isNotEmpty);
    expect(events.whereType<DanmakuOnline>().first.value, greaterThan(0));
  });

  group('connector', () {
    RoomDetail room() => RoomDetail(
      card: RoomCard(ref: RoomRef('picarto', 'allatir'), title: 't', anchorName: 'a', state: LiveState.live),
      link: Uri.parse('https://picarto.tv/allatir'),
      danmakuKeys: const {'channelName': 'allatir'},
    );

    test('JWT first, joined on open, nothing sent, the silence watchdog reconnects after 180 s', () {
      fakeAsync((async) {
        final first = FakeSocket();
        final second = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(
            status: 200,
            url: request.url,
            bytes: utf8.encode('{"data":{"generateJwtToken":{"key":"a.b.c"}}}'),
          ),
        );
        final transport = FakeTransport(plan: [first, second], http: http);
        final connector = PicartoConnector(
          detail: room(),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 27)),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(http.requests.single.method, 'POST');
        expect(transport.urls.single, PicartoProtocol.endpoint('a.b.c'));
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 120));
        expect(first.sent, isEmpty);
        expect(transport.urls, hasLength(1));
        async.elapse(const Duration(seconds: 62));
        expect(transport.urls, hasLength(2));
      });
    });

    test('the factory knows Picarto', () {
      expect(danmakuPlatforms, contains('picarto'));
      expect(danmakuConnectorFor(room(), transport: FakeTransport()), isA<PicartoConnector>());
    });
  });
}
