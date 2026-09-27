import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _start = DateTime.utc(2026, 9, 28);
final _context = DecodeContext(room: 'fc2live:62996200', session: 2, receivedAt: 1, now: _start);

String _comment({int history = 0, String color = 'black', String text = 'こんにちは'}) => jsonEncode({
  'name': 'comment',
  'arguments': {
    'comments': [
      {
        'user_name': '[anonymous]',
        'timestamp': 1790539206140,
        'encrypted_user_id': 'abc123',
        'hash': '0123456789abcdef',
        'comment': text,
        'color': color,
        'size': 'middle',
        'anonymous': 1,
        'history': history,
      },
    ],
  },
});

void main() {
  group('protocol (§7)', () {
    test('commands are JSON in binary frames', () {
      expect(jsonDecode(utf8.decode(Fc2LiveProtocol.command('heartbeat', 3))), {
        'name': 'heartbeat',
        'arguments': <String, Object?>{},
        'id': 3,
      });
    });

    test('connect_complete joins; control_disconnection asks for a new grant', () {
      final counts = <String, int>{};
      expect(
        Fc2LiveProtocol.decode('{"name":"connect_complete","arguments":{}}', context: _context, counts: counts).joined,
        isTrue,
      );
      final stale = Fc2LiveProtocol.decode(
        '{"name":"control_disconnection","arguments":{"code":4500}}',
        context: _context,
        counts: counts,
      );
      expect(stale.rejected, isTrue);
    });

    test('comments: replayed history is dropped; ids, times and colours', () {
      final counts = <String, int>{};
      expect(Fc2LiveProtocol.decode(_comment(history: 1), context: _context, counts: counts).events, isEmpty);
      final chat =
          Fc2LiveProtocol.decode(
                _comment(color: 'red'),
                context: _context,
                counts: counts,
              ).events.single
              as DanmakuChat;
      expect(chat.id, 'fc2live:0123456789abcdef');
      expect(chat.userName, '[anonymous]');
      expect(chat.text, 'こんにちは');
      expect(chat.color, 0xFF0000);
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790539206140, isUtc: true));
      final black = Fc2LiveProtocol.decode(_comment(), context: _context, counts: counts).events.single as DanmakuChat;
      expect(black.color, DanmakuColors.white);
      expect(
        Fc2LiveProtocol.decode(
          _comment(text: ' '),
          context: _context,
          counts: counts,
        ).events,
        isEmpty,
      );
    });

    test('user_count updates are partial: PC and mobile add up', () {
      final counts = <String, int>{};
      final first = Fc2LiveProtocol.decode(
        '{"name":"user_count","arguments":{"pc_user_count":100,"pc_total_count":7000,'
        '"mobile_user_count":20,"mobile_total_count":2000}}',
        context: _context,
        counts: counts,
      ).events.cast<DanmakuOnline>();
      expect(first.map((e) => (e.audience, e.value)), [(AudienceKind.online, 120), (AudienceKind.cumulative, 9000)]);
      final next = Fc2LiveProtocol.decode(
        '{"name":"user_count","arguments":{"mobile_user_count":21}}',
        context: _context,
        counts: counts,
      ).events.cast<DanmakuOnline>();
      expect(next.map((e) => (e.audience, e.value)), [(AudienceKind.online, 121)]);
    });
  });

  group('recorded frames (fixtures/fc2live/danmaku/S06-live)', () {
    final fixture = DanmakuFixture.load('fc2live', 'S06-live');
    final socketFrames = [
      for (final frame in fixture.incoming)
        if (frame.url == null) frame,
    ];

    test('the grant came over HTTP, then the socket; heartbeats were answered', () {
      final http = [
        for (final frame in fixture.incoming)
          if (frame.url != null) frame.url!.path,
      ];
      expect(http, ['/api/memberApi.php', '/api/getControlServer.php']);
      final sent = [for (final frame in fixture.outgoing) jsonDecode(utf8.decode(frame.bytes)) as Map<String, dynamic>];
      expect(sent.map((m) => m['name']).toSet(), {'heartbeat'});
      final answered = socketFrames.where((f) => utf8.decode(f.bytes).contains('"_response_"')).length;
      expect(answered, sent.length);
    });

    test('live comments and viewer counts decode; the replayed history does not', () {
      final counts = <String, int>{};
      final events = [
        for (final frame in socketFrames)
          ...Fc2LiveProtocol.decode(utf8.decode(frame.bytes), context: fixture.context(frame), counts: counts).events,
      ];
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, isNotEmpty);
      expect(chats.every((c) => c.id!.startsWith('fc2live:') && c.text.isNotEmpty), isTrue);
      final history = socketFrames.where((f) => utf8.decode(f.bytes).contains('"history":1')).length;
      expect(history, greaterThan(0), reason: 'the join replays recent comments');
      expect(events.whereType<DanmakuOnline>().where((e) => e.audience == AudienceKind.online), isNotEmpty);
    });

    test('the connector: grant, handshake with the orz cookie, join on connect_complete, heartbeat', () {
      fakeAsync((async) {
        final http = FakeHttp((request) async {
          final frame = fixture.incoming.firstWhere((f) => f.url?.path == request.url.path);
          return LiveResponse(status: 200, bytes: frame.bytes, url: request.url);
        });
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket], http: http);
        final connector = Fc2LiveConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        var joined = false;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.urls.single.queryParameters, contains('control_token'));
        expect(transport.headers.single['Cookie'], startsWith('l_ortkn='));
        expect(http.requests.map((r) => r.site).toSet(), {'fc2live'});
        for (final frame in socketFrames) {
          socket.receive(utf8.decode(frame.bytes));
        }
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(events.whereType<DanmakuChat>(), isNotEmpty);
        expect((jsonDecode(utf8.decode(socket.sent.first)) as Map<String, dynamic>)['name'], 'heartbeat');
        async.elapse(Fc2LiveProtocol.heartbeatInterval);
        expect(socket.sent, hasLength(2));
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('an offline channel ends the start', () {
      fakeAsync((async) {
        final live = fixture.incoming.firstWhere((f) => f.url?.path == '/api/memberApi.php');
        final offline = utf8.decode(live.bytes).replaceFirst('"is_publish":1', '"is_publish":0');
        final http = FakeHttp(
          (request) async => LiveResponse(status: 200, bytes: utf8.encode(offline), url: request.url),
        );
        final connector = Fc2LiveConnector(
          detail: fixture.detail,
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'offline');
      });
    });
  });
}
