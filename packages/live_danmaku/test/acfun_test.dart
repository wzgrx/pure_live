import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(room: 'acfun:41254970', session: 5, receivedAt: 1, now: DateTime.utc(2026, 9, 28));
final _security = Uint8List.fromList(List.generate(16, (i) => i * 7 + 3));
final _sessionKey = Uint8List.fromList(List.generate(16, (i) => 200 - i));

AcfunChatSession _session() => AcfunChatSession(
  userId: 1700000000000001,
  token: 'visitor-token',
  security: _security,
  deviceId: 'web_abcdefghijklmnop',
  liveId: 'LIVE1',
  tickets: const ['ticket-a', 'ticket-b'],
  attach: 'attach-1',
);

/// A server frame: downstream payload sealed with [key] (mode 2 unless
/// [mode] says otherwise).
Uint8List _down(String command, List<int> data, {required List<int> key, int mode = 2, int seq = 9, int error = 0}) {
  final plain =
      (ProtoWriter()
            ..string(1, command)
            ..integer(2, seq)
            ..integer(3, error)
            ..bytes(4, data))
          .toBytes();
  final header =
      (ProtoWriter()
            ..integer(1, 13)
            ..integer(7, plain.length)
            ..integer(8, mode)
            ..integer(10, seq))
          .toBytes();
  return AcfunProtocol.frame(header, AcfunProtocol.seal(plain, key, Random(1)));
}

/// A client frame opened with [key]: its header and upstream payload.
({ProtoMessage header, ProtoMessage up}) _up(List<int> frame, List<int> key) {
  final (:header, :payload) = AcfunProtocol.unframe(frame);
  return (header: header, up: ProtoMessage.decode(AcfunProtocol.open(payload, key)));
}

Uint8List _registerAnswer() => _down(
  AcfunProtocol.register,
  (ProtoWriter()
        ..bytes(2, _sessionKey)
        ..integer(3, 77))
      .toBytes(),
  key: _security,
  mode: 1,
  seq: 1,
);

Uint8List _ack(String type, {int code = 0, List<int> payload = const []}) =>
    (ProtoWriter()
          ..string(1, type)
          ..integer(2, code)
          ..bytes(4, payload))
        .toBytes();

Uint8List _user(int id, String name) =>
    (ProtoWriter()
          ..integer(1, id)
          ..string(2, name))
        .toBytes();

/// `ZtLiveScMessage` of [type] with [body], gzipped when [zipped].
Uint8List _push(String type, List<int> body, {bool zipped = false}) =>
    (ProtoWriter()
          ..string(1, type)
          ..integer(2, zipped ? 2 : 1)
          ..bytes(3, zipped ? gzip.encode(body) : body)
          ..string(4, 'LIVE1'))
        .toBytes();

Uint8List _signals(List<(String, List<List<int>>)> items) {
  final out = ProtoWriter();
  for (final (type, payloads) in items) {
    final item = ProtoWriter()..string(1, type);
    for (final payload in payloads) {
      item.bytes(2, payload);
    }
    out.bytes(1, item.toBytes());
  }
  return out.toBytes();
}

void main() {
  group('link (§7.2, §7.3)', () {
    test('register is sealed with acSecurity and carries the service token in the header', () {
      final link = AcfunLink(_session(), random: Random(2));
      final (:header, :up) = _up(link.register(), _security);
      expect(header.integer(1), 13);
      expect(header.integer(2), 1700000000000001);
      expect(header.integer(8), 1, reason: 'service-token mode');
      expect(header.message(9)!.integer(1), 1);
      expect(header.message(9)!.string(2), 'visitor-token');
      expect(header.integer(10), 1);
      expect(header.string(12), 'ACFUN_APP');
      expect(up.string(1), 'Basic.Register');
      expect((up.integer(2), up.integer(3), up.string(9)), (1, 1, 'mainApp'));
      final request = up.message(4)!;
      expect(request.message(1)!.string(1), 'link-sdk');
      expect(request.message(2)!.integer(1), 6, reason: 'H5');
      expect(request.message(11)!.string(2), 'PC_WEB');
      expect(request.message(11)!.integer(4), 1700000000000001);
      expect(
        header.integer(7),
        AcfunProtocol.open(AcfunProtocol.unframe(link.register()).payload, _security).length,
        reason: 'decodedPayloadLen is the plain length',
      );
    });

    test('the register answer brings the session key; later frames use it and count up', () {
      final link = AcfunLink(_session(), random: Random(2))..register();
      expect(link.keepAlive, throwsStateError);
      final answer = link.read(_registerAnswer());
      expect((answer.command, answer.errorCode, link.registered), ('Basic.Register', 0, true));
      final keep = _up(link.keepAlive(), _sessionKey);
      expect((keep.header.integer(8), keep.header.integer(3), keep.header.integer(10)), (2, 77, 2));
      expect(keep.header.message(9), isNull);
      expect(keep.up.string(1), 'Basic.KeepAlive');
      final enter = _up(link.enterRoom(), _sessionKey);
      expect(enter.up.string(1), 'Global.ZtLiveInteractive.CsCmd');
      final command = enter.up.message(4)!;
      expect((command.string(1), command.string(3), command.string(4)), ('ZtLiveCsEnterRoom', 'ticket-a', 'LIVE1'));
      final body = command.message(2)!;
      expect((body.string(4), body.string(5)), ('attach-1', 'kwai-acfun-live-link'));
      final beat = _up(link.heartbeat(sequence: 3, now: DateTime.utc(2026, 9, 28), ticket: 1), _sessionKey);
      final beatCommand = beat.up.message(4)!;
      expect((beatCommand.string(1), beatCommand.string(3)), ('ZtLiveCsHeartbeat', 'ticket-b'));
      expect(beatCommand.message(2)!.integer(2), 3);
      expect(beatCommand.message(2)!.integer(1), DateTime.utc(2026, 9, 28).millisecondsSinceEpoch);
      expect(beat.header.integer(10), 4);
    });

    test('a push is acknowledged with its own sequence id and no payload', () {
      final link = AcfunLink(_session(), random: Random(2))..read(_registerAnswer());
      final push = link.read(_down(AcfunProtocol.message, const [1], key: _sessionKey, seq: 846000001));
      final ack = _up(link.pushAck(push), _sessionKey);
      expect(ack.header.integer(10), 846000001);
      expect(ack.up.string(1), 'Push.ZtLiveInteractive.Message');
      expect(ack.up.bytes(4), isNull);
    });

    test('frames that do not add up, and a wrong key, are FormatExceptions', () {
      final link = AcfunLink(_session(), random: Random(2));
      final frame = _registerAnswer();
      expect(() => link.read(frame.sublist(0, frame.length - 1)), throwsFormatException);
      expect(() => link.read([0, 1, ...frame.sublist(2)]), throwsFormatException);
      expect(
        () => link.read(_down(AcfunProtocol.message, const [1], key: _sessionKey)),
        throwsFormatException,
        reason: 'no session key yet',
      );
      final wrong = AcfunLink(
        AcfunChatSession(
          userId: 1,
          token: '',
          security: Uint8List(16),
          deviceId: '',
          liveId: '',
          tickets: const [],
          attach: '',
        ),
      );
      expect(() => wrong.read(frame), throwsFormatException);
    });
  });

  group('push messages (§7.4)', () {
    test('comments, gifts by the gift list, bananas and the audience figure', () {
      final comment =
          (ProtoWriter()
                ..string(1, '顶不住了')
                ..integer(2, 1790000000000)
                ..bytes(3, _user(123456, '观众1')))
              .toBytes();
      final gift =
          (ProtoWriter()
                ..bytes(1, _user(222, 'viewer'))
                ..integer(2, 1790000000001)
                ..integer(3, 17)
                ..integer(4, 3))
              .toBytes();
      final unknownGift =
          (ProtoWriter()
                ..bytes(1, _user(222, 'viewer'))
                ..integer(3, 999))
              .toBytes();
      final banana =
          (ProtoWriter()
                ..bytes(1, _user(333, '香蕉人'))
                ..integer(2, 5))
              .toBytes();
      final actions = AcfunProtocol.push(
        _push(
          'ZtLiveScActionSignal',
          _signals([
            ('CommonActionSignalComment', [comment]),
            ('CommonActionSignalGift', [gift, unknownGift]),
            ('AcfunActionSignalThrowBanana', [banana]),
            ('CommonActionSignalLike', [_user(1, 'x')]),
          ]),
          zipped: true,
        ),
        _context,
        gifts: {17: AcfunGift(name: '快乐水', icon: Uri.parse('https://static.yximgs.com/a.webp'))},
      );
      expect((actions.ticketInvalid, actions.liveClosed), (false, false));
      final chat = actions.events.first as DanmakuChat;
      expect(
        (chat.userId, chat.userName, chat.text, chat.room, chat.session),
        ('123456', '观众1', '顶不住了', 'acfun:41254970', 5),
      );
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true));
      final gifts = actions.events.whereType<DanmakuGift>().toList();
      expect(gifts.map((g) => (g.giftId, g.giftName, g.count, g.userName)), [
        ('17', '快乐水', 3, 'viewer'),
        ('1', '香蕉', 5, '香蕉人'),
      ], reason: 'a gift missing from the list is dropped');
      expect(gifts.first.icon, Uri.parse('https://static.yximgs.com/a.webp'));
      expect(actions.events, hasLength(3));

      final states = AcfunProtocol.push(
        _push(
          'ZtLiveScStateSignal',
          (ProtoWriter()
                ..bytes(
                  1,
                  (ProtoWriter()
                        ..string(1, 'CommonStateSignalDisplayInfo')
                        ..bytes(2, (ProtoWriter()..string(1, '1.2万')).toBytes()))
                      .toBytes(),
                )
                ..bytes(1, (ProtoWriter()..string(1, 'CommonStateSignalTopUsers')).toBytes()))
              .toBytes(),
        ),
        _context,
      );
      final online = states.events.single as DanmakuOnline;
      expect((online.audience, online.value), (AudienceKind.online, 12000));
    });

    test('a dead ticket and a closed broadcast are flagged', () {
      expect(AcfunProtocol.push(_push('ZtLiveScTicketInvalid', const []), _context).ticketInvalid, isTrue);
      final closed = _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 1)).toBytes());
      expect(AcfunProtocol.push(closed, _context).liveClosed, isTrue);
      final reopened = _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 2)).toBytes());
      expect(AcfunProtocol.push(reopened, _context).liveClosed, isFalse);
    });
  });

  group('HTTP start (§7.1)', () {
    test('startPlay: tickets, attach; a closed room is null; other results throw', () {
      final play = AcfunProtocol.startPlay(
        '{"result":1,"data":{"liveId":"L","availableTickets":["a","b"],"enterRoomAttach":"x"}}',
      )!;
      expect((play.liveId, play.attach), ('L', 'x'));
      expect(play.tickets, ['a', 'b']);
      expect(AcfunProtocol.startPlay('{"result":129004,"error_msg":"直播已关播"}'), isNull);
      expect(() => AcfunProtocol.startPlay('{"result":380023}'), throwsFormatException);
      expect(
        () => AcfunProtocol.startPlay('{"result":1,"data":{"liveId":"L","availableTickets":[]}}'),
        throwsFormatException,
      );
    });

    test('visitor/login needs result 0 and the whole session', () {
      final visitor = AcfunProtocol.visitor(
        '{"result":0,"userId":1700000000000001,"acfun.api.visitor_st":"t","acSecurity":"AAECAwQFBgcICQoLDA0ODw=="}',
      );
      expect((visitor.userId, visitor.token), (1700000000000001, 't'));
      expect(visitor.security, List.generate(16, (i) => i));
      expect(() => AcfunProtocol.visitor('{"result":-1}'), throwsFormatException);
      expect(() => AcfunProtocol.visitor('{"result":0,"userId":1}'), throwsFormatException);
    });

    test('device ids look like the web ones', () {
      expect(AcfunProtocol.deviceId(Random(1)), matches(RegExp(r'^web_[A-Za-z0-9]{16}$')));
    });
  });

  group('recorded frames (fixtures/acfun/danmaku/S07-live)', () {
    final fixture = DanmakuFixture.load('acfun', 'S07-live');
    Frame http(String path) => fixture.frames.firstWhere((frame) => frame.url?.path.endsWith(path) ?? false);
    final visitor = AcfunProtocol.visitor(http('/visitor/login').text!);
    final play = AcfunProtocol.startPlay(http('/startPlay').text!)!;
    final gifts = AcfunProtocol.gifts(http('/gift/list').text!);
    final session = AcfunChatSession(
      userId: visitor.userId,
      token: visitor.token,
      security: visitor.security,
      deviceId: 'web_fixture',
      liveId: play.liveId,
      tickets: play.tickets,
      attach: play.attach,
    );

    test('the HTTP start: a live room with tickets and the gift list', () {
      expect(play.liveId, fixture.keys['liveId']);
      expect(play.tickets, isNotEmpty);
      expect(gifts[1]?.name, '香蕉');
      expect(gifts.length, greaterThan(20));
    });

    test('the client registered, kept alive, entered the room and acknowledged every push', () {
      final sent = [
        for (final frame in fixture.outgoing)
          if (frame.url == null) frame,
      ];
      final register = _up(sent.first.bytes, visitor.security);
      expect(register.up.string(1), 'Basic.Register');
      final link = AcfunLink(session);
      final received = [
        for (final frame in fixture.incoming)
          if (frame.url == null) link.read(frame.bytes),
      ];
      expect(received.first.command, 'Basic.Register');
      expect(received.every((packet) => packet.errorCode == 0), isTrue);
      final key = AcfunProtocol.unframe(sent[1].bytes);
      expect(key.header.integer(8), 2);
      final commands = [for (final frame in sent.skip(1)) link.readUp(frame.bytes)];
      expect(commands.take(2), ['Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd']);
      final pushes = received.where((packet) => packet.command.startsWith('Push')).length;
      expect(commands.where((command) => command.startsWith('Push')).length, pushes);
    });

    test('pushes decode: comments and the audience figure; the enter-room answer names 10 s', () {
      final link = AcfunLink(session);
      final events = <DanmakuEvent>[];
      Duration? heartbeat;
      for (final frame in fixture.incoming) {
        if (frame.url != null) continue;
        final packet = link.read(frame.bytes);
        if (packet.command == AcfunProtocol.message) {
          events.addAll(AcfunProtocol.push(packet.payload, fixture.context(frame), gifts: gifts).events);
        } else if (packet.command == AcfunProtocol.roomCommand) {
          final ack = AcfunProtocol.ack(packet.payload);
          expect(ack.code, 0);
          if (ack.type == 'ZtLiveCsEnterRoomAck') heartbeat = AcfunProtocol.heartbeatOf(ack.payload);
        }
      }
      expect(heartbeat, const Duration(seconds: 10));
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, isNotEmpty);
      expect(chats.every((chat) => chat.text.isNotEmpty && chat.userName.isNotEmpty && chat.userId.isNotEmpty), isTrue);
      expect(events.whereType<DanmakuOnline>(), isNotEmpty);
    });

    test('the connector replays the recording', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(
          plan: [socket],
          http: FakeHttp((request) async {
            final path = request.url.path;
            final frame = http(path.substring(path.lastIndexOf('/')));
            return LiveResponse(status: 200, url: request.url, bytes: utf8.encode(frame.text!));
          }),
        );
        final connector = AcfunConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        final requests = (transport.http as FakeHttp).requests;
        expect(requests.map((r) => r.url.path), [
          '/rest/app/visitor/login',
          '/rest/zt/live/web/startPlay',
          '/rest/zt/live/web/gift/list',
        ]);
        expect(utf8.decode(requests[1].body!), 'authorId=${fixture.keys['author']}&pullStreamType=FLV');
        expect(transport.urls.single, AcfunProtocol.endpoint);
        expect(_up(socket.sent.single, visitor.security).up.string(1), 'Basic.Register');
        for (final frame in fixture.incoming) {
          if (frame.url == null) socket.receive(frame.bytes);
        }
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(events.whereType<DanmakuChat>(), isNotEmpty);
        final link = AcfunLink(session)..read(fixture.incoming.firstWhere((frame) => frame.url == null).bytes);
        expect(link.readUp(socket.sent[1]), 'Basic.KeepAlive');
        expect(link.readUp(socket.sent[2]), 'Global.ZtLiveInteractive.CsCmd');
        final before = socket.sent.length;
        async.elapse(const Duration(seconds: 10));
        expect(socket.sent.length, before + 1, reason: 'room heartbeat every 10 s');
        expect(link.readUp(socket.sent.last), 'Global.ZtLiveInteractive.CsCmd');
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('a refused enter-room starts over with a new visitor session and tickets', () {
      fakeAsync((async) {
        final first = FakeSocket();
        final second = FakeSocket();
        final http = FakeHttp((request) async {
          final path = request.url.path;
          final frame = fixture.frames.firstWhere(
            (frame) => frame.url?.path.endsWith(path.substring(path.lastIndexOf('/'))) ?? false,
          );
          return LiveResponse(status: 200, url: request.url, bytes: utf8.encode(frame.text!));
        });
        final transport = FakeTransport(plan: [first, second], http: http);
        final connector = AcfunConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        unawaited(connector.connect());
        async.flushMicrotasks();
        first.receive(
          _down(
            AcfunProtocol.register,
            (ProtoWriter()
                  ..bytes(2, _sessionKey)
                  ..integer(3, 77))
                .toBytes(),
            key: visitor.security,
            mode: 1,
            seq: 1,
          ),
        );
        async.flushMicrotasks();
        expect(first.sent, hasLength(3), reason: 'register, keep-alive, enter room');
        first.receive(_down(AcfunProtocol.roomCommand, _ack('ZtLiveCsEnterRoomAck', code: 2), key: _sessionKey));
        async.flushMicrotasks();
        expect(first.closed, isTrue);
        expect(http.requests.map((r) => r.url.path.split('/').last), [
          'login',
          'startPlay',
          'list',
          'login',
          'startPlay',
        ], reason: 'the gift list is kept');
        async.elapse(const Duration(seconds: 3));
        expect(transport.urls, hasLength(2));
        expect(_up(second.sent.single, visitor.security).up.string(1), 'Basic.Register');
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('the keep-alive rides on the heartbeat answers every 50 s', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(
          plan: [socket],
          http: FakeHttp((request) async {
            final path = request.url.path;
            final frame = http(path.substring(path.lastIndexOf('/')));
            return LiveResponse(status: 200, url: request.url, bytes: utf8.encode(frame.text!));
          }),
        );
        final connector = AcfunConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        socket.receive(
          _down(
            AcfunProtocol.register,
            (ProtoWriter()
                  ..bytes(2, _sessionKey)
                  ..integer(3, 77))
                .toBytes(),
            key: visitor.security,
            mode: 1,
            seq: 1,
          ),
        );
        final enter = _ack('ZtLiveCsEnterRoomAck', payload: (ProtoWriter()..integer(1, 10000)).toBytes());
        socket.receive(_down(AcfunProtocol.roomCommand, enter, key: _sessionKey, seq: 3));
        async.flushMicrotasks();
        expect(joined, isTrue);
        String command(List<int> frame) => _up(frame, _sessionKey).up.string(1)!;
        final keepAlives = <int>[];
        for (var second = 10; second <= 100; second += 10) {
          async.elapse(const Duration(seconds: 10));
          expect(command(socket.sent.last), AcfunProtocol.roomCommand, reason: 'heartbeat at $second s');
          final before = socket.sent.length;
          socket.receive(_down(AcfunProtocol.roomCommand, _ack('ZtLiveCsHeartbeatAck'), key: _sessionKey));
          async.flushMicrotasks();
          if (socket.sent.length > before) {
            expect(command(socket.sent.last), AcfunProtocol.keepAlive);
            keepAlives.add(second);
          }
        }
        expect(keepAlives, [50, 100]);
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('a room that is not live ends the start (noRoom)', () {
      fakeAsync((async) {
        final transport = FakeTransport(
          http: FakeHttp((request) async {
            final body = request.url.path.endsWith('/visitor/login')
                ? http('/visitor/login').text!
                : '{"result":129004,"error_msg":"直播已关播"}';
            return LiveResponse(status: 200, url: request.url, bytes: utf8.encode(body));
          }),
        );
        final connector = AcfunConnector(
          detail: fixture.detail,
          transport: transport,
          clock: FakeClock(async, fixture.capturedAt),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'noRoom');
        expect(transport.urls, isEmpty);
      });
    });
  });
}

extension on AcfunLink {
  /// The command of a client frame, opened with this link's keys.
  String readUp(List<int> frame) {
    final (:header, :payload) = AcfunProtocol.unframe(frame);
    final key = header.integer(8) == 1 ? session.security : null;
    if (key != null) return ProtoMessage.decode(AcfunProtocol.open(payload, key)).string(1) ?? '';
    // Mode 2: the session key is private to the link; read() of a
    // downstream-shaped copy recovers the command (field 1 in both).
    return read(frame).command;
  }
}
