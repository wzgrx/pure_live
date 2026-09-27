import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final _start = DateTime.utc(2026, 9, 27, 12);

RoomDetail _room(String platform, String id, Map<String, String> keys) => RoomDetail(
  card: RoomCard(ref: RoomRef(platform, id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.test/$id'),
  danmakuKeys: keys,
);

List<DanmakuStatus> _statuses(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuSystem) event.status,
];

Uint8List _douyuChat(String text) => DouyuProtocol.packet('type@=chatmsg/rid@=1/txt@=$text/', type: 690);

final class _Credentials implements DanmakuCredentials {
  new(this.tokens);

  final List<String?> tokens;
  int calls = 0;

  @override
  Future<BilibiliDanmakuInfo> bilibili(RoomDetail room) async {
    final token = calls < tokens.length ? tokens[calls] : tokens.last;
    calls++;
    if (token == null) throw const NetworkFailure('bilibili', 'down');
    return BilibiliDanmakuInfo(
      roomId: 5050,
      uid: 0,
      token: token,
      servers: [Uri.parse('wss://a.test/sub'), Uri.parse('wss://b.test/sub')],
      buvid: 'b',
      headers: const {'user-agent': 'UA'},
    );
  }

  @override
  Future<String?> cookie(String platform) async => null;
}

Uint8List _biliPacket(int op, List<int> body) {
  final bytes = Uint8List(16 + body.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, bytes.length)
    ..setUint16(4, 16)
    ..setUint32(8, op)
    ..setUint32(12, 1);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

int _op(List<int> packet) => ByteData.sublistView(Uint8List.fromList(packet)).getUint32(8);

void main() {
  group('socket loop (CONN-3) on Douyu', () {
    test('joins on open, heartbeats every 45 s, decodes frames', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = DouyuConnector(
          detail: _room('douyu', '1', {'rid': '1'}),
          transport: transport,
          session: 4,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(transport.urls.single, DouyuProtocol.endpoint);
        expect(socket.sent.expand(DouyuProtocol.bodies), [
          'type@=loginreq/roomid@=1/',
          'type@=joingroup/rid@=1/gid@=-9999/',
        ]);
        async.elapse(const Duration(seconds: 44));
        expect(socket.sent, hasLength(2));
        async.elapse(const Duration(seconds: 1));
        expect(DouyuProtocol.bodies(socket.sent.last), ['type@=mrkl/']);
        socket.receive(_douyuChat('hi'));
        async.flushMicrotasks();
        expect(events.whereType<DanmakuChat>().single.text, 'hi');
        expect(events.whereType<DanmakuChat>().single.session, 4);
        expect(_statuses(events), [DanmakuStatus.connecting, DanmakuStatus.connected]);
        unawaited(connector.close());
        async.flushMicrotasks();
        expect(socket.closed, isTrue);
      });
    });

    test('a drop reconnects after 2 s; a message resets the count; 8 retries then the terminal state', () {
      fakeAsync((async) {
        final first = FakeSocket();
        final second = FakeSocket();
        final transport = FakeTransport(plan: [first, second]);
        final connector = DouyuConnector(
          detail: _room('douyu', '1', {'rid': '1'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        unawaited(connector.connect());
        async.flushMicrotasks();
        first.drop();
        async.flushMicrotasks();
        expect(_statuses(events).last, DanmakuStatus.reconnecting);
        async.elapse(const Duration(milliseconds: 1999));
        expect(transport.urls, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(transport.urls, hasLength(2));
        expect(_statuses(events).last, DanmakuStatus.connected);
        // A message on the new socket resets the failures: the next drop
        // waits 2 s again.
        second.receive(_douyuChat('x'));
        async.flushMicrotasks();
        second.drop();
        async.elapse(const Duration(seconds: 2));
        expect(transport.urls, hasLength(3));
        // Every later handshake is refused: 2+3+4+5+6+6+6 more seconds.
        async.elapse(const Duration(seconds: 3 + 4 + 5 + 6 + 6 + 6 + 6));
        expect(transport.urls, hasLength(10));
        expect(events.whereType<DanmakuSystem>().last.status, DanmakuStatus.closed);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'maxRetries');
        async.elapse(const Duration(minutes: 1));
        expect(transport.urls, hasLength(10));
      });
    });

    test('silence of max(3 × heartbeat, 90 s) counts as a dead connection', () {
      fakeAsync((async) {
        final first = FakeSocket();
        final transport = FakeTransport(plan: [first, FakeSocket()]);
        final connector = DouyuConnector(
          detail: _room('douyu', '1', {'rid': '1'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        connector.events.listen((_) {});
        unawaited(connector.connect());
        async.elapse(const Duration(seconds: 100));
        first.receive(_douyuChat('x'));
        async.elapse(const Duration(seconds: 134));
        expect(first.closed, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(first.closed, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(transport.urls, hasLength(2));
      });
    });

    test('close stops a pending retry', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final connector = DouyuConnector(
          detail: _room('douyu', '1', {'rid': '1'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        connector.events.listen((_) {});
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        var closed = false;
        unawaited(connector.close().then((_) => closed = true));
        async.flushMicrotasks();
        expect(closed, isTrue);
        expect(joined, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(transport.urls, hasLength(1));
        expect(connector.connect, throwsStateError);
      });
    });
  });

  group('Bilibili connector', () {
    test('auth first, joined on op 8, heartbeat at once and every 30 s, snapshot once', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final http = FakeHttp(
          (request) async => LiveResponse(status: 200, url: request.url, bytes: utf8.encode('{"data":{"list":[]}}')),
        );
        final transport = FakeTransport(plan: [socket], http: http);
        final credentials = _Credentials(['tok']);
        final connector = BilibiliConnector(
          detail: _room('bilibili', '5050', {'roomId': '5050'}),
          transport: transport,
          credentials: credentials,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(transport.urls.single, Uri.parse('wss://a.test/sub'));
        expect(transport.headers.single, {'user-agent': 'UA'});
        expect(socket.sent.map(_op), [7]);
        expect(joined, isNull);
        socket.receive(_biliPacket(8, utf8.encode('{"code":0}')));
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(socket.sent.map(_op), [7, 2]);
        async.elapse(const Duration(seconds: 30));
        expect(socket.sent.map(_op), [7, 2, 2]);
        expect(http.requests.single.url.path, '/av/v1/SuperChat/getMessageList');
        expect(_statuses(events), [DanmakuStatus.connecting, DanmakuStatus.connected]);
      });
    });

    test('no auth reply within 8 s moves to the next endpoint', () {
      fakeAsync((async) {
        final transport = FakeTransport(plan: [FakeSocket(), FakeSocket()]);
        final connector = BilibiliConnector(
          detail: _room('bilibili', '5050', {'roomId': '5050'}),
          transport: transport,
          credentials: _Credentials(['tok']),
          clock: FakeClock(async, _start),
        );
        connector.events.listen((_) {});
        unawaited(connector.connect());
        async
          ..elapse(const Duration(seconds: 8))
          ..elapse(const Duration(seconds: 1));
        expect(transport.urls.map((url) => url.host), ['a.test', 'b.test']);
      });
    });

    test('a rejected auth fetches a new token; more than 3 rejections end the start', () {
      fakeAsync((async) {
        final sockets = [for (var i = 0; i < 5; i++) FakeSocket()];
        final transport = FakeTransport(plan: [...sockets]);
        final credentials = _Credentials(['t1', 't2', 't3', 't4', 't5']);
        final connector = BilibiliConnector(
          detail: _room('bilibili', '5050', {'roomId': '5050'}),
          transport: transport,
          credentials: credentials,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        unawaited(connector.connect());
        for (final socket in sockets.take(4)) {
          async.flushMicrotasks();
          final auth = jsonDecode(utf8.decode(socket.sent.first.sublist(16))) as Map<String, dynamic>;
          expect(auth['key'], 't${credentials.calls}');
          socket.receive(_biliPacket(8, utf8.encode('{"code":-1}')));
          async.elapse(const Duration(seconds: 3));
        }
        expect(credentials.calls, 4);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'rejected');
      });
    });

    test('three failed credential requests, 500 ms and 1000 ms apart, end the start', () {
      fakeAsync((async) {
        final credentials = _Credentials([null]);
        final connector = BilibiliConnector(
          detail: _room('bilibili', '5050', {'roomId': '5050'}),
          transport: FakeTransport(),
          credentials: credentials,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.elapse(const Duration(milliseconds: 1499));
        expect(credentials.calls, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(credentials.calls, 3);
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'credentials');
      });
    });
  });

  group('Douyin connector', () {
    test('signed URL on the first edge, heartbeat at once and every 10 s, acks, 45 s silence', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket, FakeSocket()]);
        final connector = DouyinConnector(
          detail: _room('douyin', '1', {'webRid': '1', 'roomId': '76902', 'userUniqueId': '7412345678901234567'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        connector.events.listen((_) {});
        unawaited(connector.connect());
        async.flushMicrotasks();
        final url = transport.urls.single;
        expect(url.host, DouyinProtocol.hosts.first);
        expect(url.queryParameters['room_id'], '76902');
        expect(url.queryParameters['signature'], hasLength(16));
        expect(transport.headers.single['Referer'], 'https://live.douyin.com/1');
        expect(socket.sent.map((frame) => ProtoMessage.decode(frame).string(7)), ['hb']);
        async.elapse(const Duration(seconds: 10));
        expect(socket.sent, hasLength(2));
        final push =
            (ProtoWriter()
                  ..integer(2, 9)
                  ..string(7, 'msg')
                  ..bytes(8, (ProtoWriter()..integer(9, 1)).toBytes()))
                .toBytes();
        socket.receive(push);
        async.flushMicrotasks();
        expect(ProtoMessage.decode(socket.sent.last).string(7), 'ack');
        async.elapse(const Duration(seconds: 45));
        expect(socket.closed, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(transport.urls.last.host, DouyinProtocol.hosts.last);
      });
    });

    test('without this broadcast room_id the start fails without connecting', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final connector = DouyinConnector(
          detail: _room('douyin', '1', {'webRid': '1'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        unawaited(connector.connect());
        async.flushMicrotasks();
        expect(transport.urls, isEmpty);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'noRoom');
      });
    });
  });

  group('Huya connector', () {
    test('registers and heartbeats at once; no uid, no connection', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final transport = FakeTransport(plan: [socket]);
        final connector = HuyaConnector(
          detail: _room('huya', '998', {'uid': '294636272'}),
          transport: transport,
          clock: FakeClock(async, _start),
        );
        connector.events.listen((_) {});
        unawaited(connector.connect());
        async.flushMicrotasks();
        expect(transport.headers.single, {'Origin': 'https://www.huya.com'});
        expect(socket.sent.map((frame) => TarsStruct.decode(frame).integer(0)), [16, 20]);
        async.elapse(const Duration(seconds: 60));
        expect(socket.sent, hasLength(3));

        final none = FakeTransport();
        final missing = HuyaConnector(detail: _room('huya', '1', const {}), transport: none);
        missing.events.listen((_) {});
        unawaited(missing.connect());
        async.flushMicrotasks();
        expect(none.urls, isEmpty);
      });
    });
  });

  group('Kuaishou poller', () {
    LiveResponse feed(LiveRequest request, {int result = 1, String cursor = 'c1'}) => LiveResponse(
      status: 200,
      url: request.url,
      bytes: utf8.encode(
        jsonEncode({
          'result': result,
          'cursor': cursor,
          'pullCycleSeconds': 2,
          'liveStreamFeeds': [
            {'type': 'comment', 'content': 'hi ${request.url.queryParameters['cursor']}', 'time': 1},
          ],
        }),
      ),
    );

    test('polls serially at the server interval with the previous cursor', () {
      fakeAsync((async) {
        final http = FakeHttp((request) async => feed(request, cursor: 'c${DateTime.now().microsecond}'));
        final connector = KuaishouConnector(
          detail: _room('kuaishou', 'x', {'liveStreamId': 'L1'}),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(http.requests.single.url.queryParameters, {'liveStreamId': 'L1'});
        async.elapse(const Duration(seconds: 2));
        expect(http.requests, hasLength(2));
        expect(http.requests.last.url.queryParameters['cursor'], isNotEmpty);
        expect(events.whereType<DanmakuChat>(), hasLength(2));
        unawaited(connector.close());
        async.elapse(const Duration(seconds: 10));
        expect(http.requests, hasLength(2));
      });
    });

    test('start: three tries 0.6 s and 1.4 s apart, then the terminal state', () {
      fakeAsync((async) {
        final http = FakeHttp((request) async => feed(request, result: 2));
        final connector = KuaishouConnector(
          detail: _room('kuaishou', 'x', {'liveStreamId': 'L1'}),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.elapse(const Duration(milliseconds: 1999));
        // Each try asks both endpoints.
        expect(http.requests, hasLength(4));
        async.elapse(const Duration(milliseconds: 1));
        expect(http.requests, hasLength(6));
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.status, DanmakuStatus.closed);
      });
    });

    test('failures back off 1, 2, 4, 8, 8 … s and the ninth ends it', () {
      fakeAsync((async) {
        var failing = false;
        final http = FakeHttp((request) async => feed(request, result: failing ? 2 : 1));
        final connector = KuaishouConnector(
          detail: _room('kuaishou', 'x', {'liveStreamId': 'L1'}),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        unawaited(connector.connect());
        async.flushMicrotasks();
        failing = true;
        final rounds = <Duration>[];
        var last = async.elapsed;
        var seen = http.requests.length;
        for (var i = 0; i < 800 && events.whereType<DanmakuSystem>().last.status != DanmakuStatus.closed; i++) {
          async.elapse(const Duration(milliseconds: 100));
          if (http.requests.length > seen) {
            rounds.add(async.elapsed - last);
            last = async.elapsed;
            seen = http.requests.length;
          }
        }
        expect(rounds.map((gap) => gap.inMilliseconds), [2000, 1000, 2000, 4000, 8000, 8000, 8000, 8000, 8000]);
        expect(_statuses(events).where((status) => status == DanmakuStatus.reconnecting), hasLength(1));
        expect(events.whereType<DanmakuSystem>().last.args.first, 'maxRetries');
      });
    });
  });
}
