import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'twitch:zarbex', session: 2, receivedAt: 1, now: DateTime.utc(2026, 9, 28));

RoomDetail _room(String login) => RoomDetail(
  card: RoomCard(ref: RoomRef('twitch', login), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://www.twitch.tv/$login'),
  danmakuKeys: {'login': login},
);

void main() {
  group('IRC lines (§7.2)', () {
    test('tags, prefix, command, middle and trailing parameters; escapes resolved', () {
      final message = TwitchProtocol.parse(
        r'@badge-info=;display-name=Some\sOne;color=#FF69B4;id=abc;tmi-sent-ts=1790534862574;user-id=42;'
        r'msg=a\:b\\c :someone!someone@someone.tmi.twitch.tv PRIVMSG #zarbex :hello : world',
      )!;
      expect(message.command, 'PRIVMSG');
      expect(message.prefix, 'someone!someone@someone.tmi.twitch.tv');
      expect(message.nick, 'someone');
      expect(message.params, ['#zarbex', 'hello : world']);
      expect(message.tags['display-name'], 'Some One');
      expect(message.tags['msg'], r'a;b\c');
      expect(message.tags['badge-info'], '');
      final ping = TwitchProtocol.parse('PING :tmi.twitch.tv')!;
      expect((ping.command, ping.prefix), ('PING', null));
      expect(ping.params, ['tmi.twitch.tv']);
      expect(TwitchProtocol.parse('   '), isNull);
      expect(TwitchProtocol.parse('@only-tags'), isNull);
    });

    test('login lines: capabilities, the anonymous password and nick, the channel', () {
      expect(TwitchProtocol.login(nick: 'justinfan1234', channel: 'zarbex'), [
        'CAP REQ :twitch.tv/tags twitch.tv/commands',
        'PASS SCHMOOPIIE',
        'NICK justinfan1234',
        'JOIN #zarbex',
      ]);
      expect(TwitchProtocol.anonymousNick(Random(1)), matches(RegExp(r'^justinfan\d{4,5}$')));
    });

    test('a chat line: display name, id, colour, time; /me unwrapped; other channels ignored', () {
      final line = TwitchProtocol.parse(
        '@color=#1E90FF;display-name=Viewer;id=u-1;tmi-sent-ts=1790534993943;user-id=7 '
        ':viewer!viewer@viewer.tmi.twitch.tv PRIVMSG #zarbex :\u0001ACTION waves\u0001',
      )!;
      final chat = TwitchProtocol.chat(line, channel: 'zarbex', context: _context)!;
      expect(
        (chat.userName, chat.userId, chat.text, chat.id, chat.color),
        ('Viewer', '7', 'waves', 'twitch:u-1', 0x1E90FF),
      );
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790534993943, isUtc: true));
      final bare = TwitchProtocol.parse(':someone!someone@someone.tmi.twitch.tv PRIVMSG #zarbex :hi')!;
      final plain = TwitchProtocol.chat(bare, channel: 'zarbex', context: _context)!;
      expect((plain.userName, plain.color, plain.id), ('someone', DanmakuColors.white, null));
      final elsewhere = TwitchProtocol.parse(':a!a@a.tmi.twitch.tv PRIVMSG #other :hi')!;
      expect(TwitchProtocol.chat(elsewhere, channel: 'zarbex', context: _context), isNull);
    });
  });

  group('connector', () {
    test('answers PING, rejects on RECONNECT, joins on ROOMSTATE only once', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket, FakeSocket()]);
        final connector = TwitchConnector(
          detail: _room('zarbex'),
          transport: transport,
          clock: FakeClock(async, DateTime.utc(2026, 9, 28)),
          random: Random(1),
        );
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.urls.single, TwitchProtocol.endpoint);
        expect(socket.sentText, hasLength(4));
        expect(socket.sentText.last, 'JOIN #zarbex');
        socket.receive('@room-id=1 :tmi.twitch.tv ROOMSTATE #zarbex\r\nPING :tmi.twitch.tv\r\n');
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(socket.sentText.last, 'PONG :tmi.twitch.tv');
        async.elapse(const Duration(seconds: 60));
        expect(socket.sentText.last, 'PING :tmi.twitch.tv', reason: 'client ping every 60 s');
        socket.receive(':tmi.twitch.tv RECONNECT\r\n');
        async.flushMicrotasks();
        expect(socket.closed, isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(transport.urls, hasLength(2));
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('a detail without a usable login ends the start (noRoom)', () {
      fakeAsync((async) {
        final connector = TwitchConnector(
          detail: _room('not a login'),
          transport: FakeTransport(),
          clock: FakeClock(async, DateTime.utc(2026, 9, 28)),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'noRoom');
      });
    });
  });

  group('recorded frames (fixtures/twitch/danmaku/S07-live)', () {
    final fixture = DanmakuFixture.load('twitch', 'S07-live');

    test('the client logged in anonymously and joined the channel', () {
      final sent = [for (final frame in fixture.outgoing) frame.text];
      expect(sent.take(4), [
        'CAP REQ :twitch.tv/tags twitch.tv/commands',
        'PASS SCHMOOPIIE',
        startsWith('NICK justinfan'),
        'JOIN #${fixture.keys['login']}',
      ]);
    });

    test('chat lines decode with pseudonymous senders', () {
      final chats = [
        for (final frame in fixture.incoming)
          for (final message in TwitchProtocol.messages(frame.text!))
            ?TwitchProtocol.chat(message, channel: fixture.keys['login']!, context: fixture.context(frame)),
      ];
      expect(chats.length, greaterThan(10));
      expect(chats.every((chat) => chat.userName.isNotEmpty && chat.id!.startsWith('twitch:')), isTrue);
    });

    test('the connector replays the recording', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = TwitchConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        for (final frame in fixture.incoming) {
          socket.receive(frame.text!);
        }
        async.flushMicrotasks();
        expect(joined, isTrue, reason: 'ROOMSTATE for the channel');
        expect(events.whereType<DanmakuChat>().length, greaterThan(10));
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });
  });
}
