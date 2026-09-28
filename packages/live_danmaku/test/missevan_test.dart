// Missevan danmaku (docs/modules/M5.12-missevan.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S06-live, S07-brotli) and the synthetic frames (S08-synthetic), written by
// fixtures/missevan/danmaku/v4_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/missevan/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, String? url, Object data});

/// The frames of a recorded session, in order: text frames as `String`,
/// binary ones as bytes.
List<_Frame> _frames(String name) {
  var index = 0;
  return [
    for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
      if (jsonDecode(line) case {'dir': final String dir} && final Map<String, Object?> frame)
        (
          index: index++,
          dir: dir,
          url: frame['url'] as String?,
          data: switch (frame) {
            {'text': final String text} => text,
            {'b64': final String b64} => base64Decode(b64),
            _ => throw FormatException('frame $frame'),
          },
        ),
  ];
}

/// The archived v4's output for a fixture.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// v4's reading of every received frame of a session, by frame index.
Map<int, Map<String, Object?>> _v4Frames(String name) => {
  for (final frame in (_v4(name)['frames']! as List<Object?>).cast<Map<String, Object?>>())
    frame['frame']! as int: {...frame}..remove('frame'),
};

final Map<String, Object?> _cases = _json('S08-synthetic/cases.json')! as Map<String, Object?>;

/// The v4 output for every synthetic case, one reading per frame.
final Map<String, Object?> _v4Cases = _v4('S08-synthetic')['cases']! as Map<String, Object?>;

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `missevan:`; the new ids are the platform's
/// own (difference 1), so the projection adds the prefix back.
Map<String, Object?> _asV4(LiveMessage message) {
  if (message.type == LiveMessageType.online) {
    final data = message.data! as LiveAudienceUpdate;
    return {
      'kind': 'online',
      'audience': switch (data.kind) {
        LiveAudienceMetricKind.popularity => 'popularity',
        LiveAudienceMetricKind.onlineViewers => 'online',
        LiveAudienceMetricKind.totalViewers => 'cumulative',
      },
      'value': data.value,
    };
  }
  expect(message.type, LiveMessageType.chat);
  return {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : 'missevan:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'userLevel': message.userLevel.isEmpty ? null : int.parse(message.userLevel),
    'medalLevel': message.fansLevel.isEmpty ? null : int.parse(message.fansLevel),
    'medalName': message.fansName.isEmpty ? null : message.fansName,
  };
}

/// The new reading of one frame in v4's shape: whether text came out of a
/// binary frame, whether the join was accepted or refused, the messages.
Map<String, Object?> _readAsV4(Object data, {required String roomId, required String uuid}) {
  final frame = MissevanDanmakuProtocol.decode(data, roomId: roomId, uuid: uuid);
  return {
    if (data is List<int>) 'text': MissevanDanmakuProtocol.text(data) != null,
    'joined': frame.joined ?? false,
    'rejected': frame.joined == false,
    'events': frame.messages.map(_asV4).toList(),
  };
}

String _textOf(Object data) => switch (data) {
  final String text => text,
  final List<int> bytes => utf8.decode(bytes),
  _ => throw FormatException('frame $data'),
};

Object _caseFrame(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

/// A frame as the server sends it, with one uncompressed Brotli meta-block
/// (as S06-live's frames are).
List<int> _frame(Object message) {
  final plain = utf8.encode(message is String ? message : jsonEncode(message));
  final n = plain.length - 1;
  return [
    1,
    plain.length & 0xff,
    (plain.length >> 8) & 0xff,
    (plain.length >> 16) & 0xff,
    (n & 0x0f) << 4,
    (n >> 4) & 0xff,
    ((n >> 12) & 0x0f) | 0x10,
    ...plain,
    0x03,
  ];
}

Map<String, Object?> _answer(String uuid, {int code = 0, String roomId = _roomId}) => {
  'type': 'room',
  'event': 'join',
  'uuid': uuid,
  'room_id': int.parse(roomId),
  'code': code,
  if (code == 0)
    'info': {
      'room': {
        'status': {'open': 1},
      },
    }
  else
    'info': '无法找到该聊天室',
};

Map<String, Object?> _chatLine(String text, {String roomId = _roomId, String id = 'm-1'}) => {
  'type': 'message',
  'event': 'new',
  'room_id': int.parse(roomId),
  'msg_id': id,
  'message': text,
  'user': {'user_id': 7300001, 'username': '观众甲'},
};

const String _roomId = '246709466';
const String _otherRoomId = '453091860';

final MissevanDanmakuArgs _args = MissevanDanmakuArgs(
  roomId: _roomId,
  url: Uri.parse('wss://im.missevan.com/ws?room_id=$_roomId'),
);

const String _sessionA = '15347729|aaaaaaaaaaaaaaaaaaaaaaaaa';
const String _sessionB = '15347729|bbbbbbbbbbbbbbbbbbbbbbbbb';
const String _sessionC = '15347729|ccccccccccccccccccccccccc';
const String _sessionD = '15347729|ddddddddddddddddddddddddd';

/// A guest session answer setting [session] (and its signature, as the site
/// does).
LiveResponse _guest(String session) => LiveResponse(
  status: 200,
  url: MissevanApi.guestSession,
  headers: {
    'set-cookie': [
      'FM_SESS=$session; path=/; max-age=259200; domain=.missevan.com; secure; httponly',
      'FM_SESS.sig=AAAAAAAAAAAAAAAAAAAAAAAAAAA; path=/; max-age=259200; domain=.missevan.com; secure; httponly',
    ],
  },
  bytes: utf8.encode(File('../../fixtures/missevan/S05-user-info/body.json').readAsStringSync()),
);

/// Answers guest session requests in turn (the last one repeats): a
/// [LiveResponse] is returned, an exception thrown.
final class _SessionHttp implements LiveHttp {
  new(this.answers, {this.hold});

  final List<Object> answers;

  /// Keeps every request pending until it completes.
  final Completer<void>? hold;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final answer = answers[requests.length - 1 < answers.length ? requests.length - 1 : answers.length - 1];
    await hold?.future;
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    return switch (answer) {
      final LiveResponse response => response,
      final Exception error => throw error,
      _ => throw StateError('answer $answer'),
    };
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

final class _FakeChannel implements SocketChannel {
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  /// The joins sent, decoded.
  List<Map<String, Object?>> get joins => [
    for (final frame in sent)
      if (frame is String && frame.startsWith('{')) jsonDecode(frame) as Map<String, Object?>,
  ];

  /// Answers the last join.
  void answer({int code = 0}) => incoming.add(_frame(_answer(joins.last['uuid']! as String, code: code)));
}

/// Hands out fake channels and records every handshake.
final class _Connector {
  new({this.fail});

  /// Thrown for every handshake, with the endpoint.
  final Exception Function(Uri endpoint)? fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<ProxyRoute> routes = [];
  final List<_FakeChannel> channels = [];

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    routes.add(route);
    final failure = fail;
    if (failure != null) throw failure(endpoint);
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

MissevanDanmakuConnection _connection(_SessionHttp http, _Connector connector, {ProxyPolicy? proxy}) =>
    MissevanDanmakuConnection(http: http, connector: connector.call, proxy: proxy ?? const FixedProxyPolicy());

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuReceived) event.message,
];

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

/// A timer of 100 ms or more held by [_heldTimers] until the test fires it.
final class _HeldTimer implements Timer {
  new(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// Runs [body] with every one-shot timer of 100 ms or more (session retries,
/// the join timer, reconnect backoff, handshake and close limits) held in
/// [held] until the test fires it.
Future<void> _heldTimers(List<_HeldTimer> held, Future<void> Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration < const Duration(milliseconds: 100)) return parent.createTimer(zone, duration, callback);
      final timer = _HeldTimer(duration, callback);
      held.add(timer);
      return timer;
    },
  ),
);

/// The active held timers of [duration].
List<_HeldTimer> _active(List<_HeldTimer> held, Duration duration) => [
  for (final timer in held)
    if (timer.isActive && timer.duration == duration) timer,
];

/// Waits for an active held timer of [duration] and fires it.
Future<void> _fire(List<_HeldTimer> held, Duration duration) async {
  await _until(() => _active(held, duration).isNotEmpty);
  _active(held, duration).first.fire();
}

/// Runs [body] with every one-shot timer of 100 ms or more recorded into
/// [delays] and fired at once.
Future<void> _fastTimers(List<Duration> delays, Future<void> Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration < const Duration(milliseconds: 100)) return parent.createTimer(zone, duration, callback);
      delays.add(duration);
      return parent.createTimer(zone, Duration.zero, callback);
    },
  ),
);

/// The differences of the new decoder from v4 in the synthetic cases
/// (docs/modules/M5.12-missevan.md, "与归档 v4 的差异"): v4's reading → the
/// new one, per case. Cases not listed read as v4 read them.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // Difference 2: gifts are not reported (v3 showed none on any platform).
  'an array: two chat lines, a gift, a cross-room gift and the statistics': (v4) => [_withoutGifts(v4.single)],
  'connects, entries, ranks, global notices and gifts show nothing': (v4) {
    expect((_reading(v4[4])['events']! as List<Object?>).single, containsPair('kind', 'gift'));
    return [for (final reading in v4) _withoutGifts(reading)];
  },
  // Difference 3: only the answer to this socket's join (its uuid) counts;
  // v4 took any room/join as the answer.
  'the answer to the join: accepted, refused, another uuid, no uuid, no code': (v4) => [
    v4[0],
    v4[1],
    {..._reading(v4[2]), 'joined': false},
    {..._reading(v4[3]), 'joined': false},
    v4[4],
    v4[5],
  ],
  // Difference 4: a line whose text is a list is not chat (v4 showed
  // "[x]"); a medal name that is not text costs only the name (v4 lost the
  // line to a TypeError).
  'chat fields of other types': (v4) {
    expect(_reading(v4[2])['events'], [containsPair('text', '[x]')]);
    expect(_reading(v4[7])['events'], isEmpty);
    return [
      v4[0],
      v4[1],
      {..._reading(v4[2]), 'events': const <Object?>[]},
      ...v4.sublist(3, 7),
      {
        ..._reading(v4[7]),
        'events': [_chat('粉丝牌名是数字', 'bbbbbbbb-0000-4000-8000-000000000019', medalName: null, medalLevel: 3)],
      },
      v4[8],
      v4[9],
    ];
  },
  // Difference 5: a time out of range costs only the time (v4 lost the line
  // to a RangeError); `create_time` is not read (the site reads `time`).
  'times: milliseconds, zero, negative, beyond DateTime, text, create_time': (v4) {
    expect(_reading(v4[3])['events'], isEmpty);
    expect(_reading(v4[5])['events'], [containsPair('sentAt', 1790612400123)]);
    return [
      ...v4.sublist(0, 3),
      {
        ..._reading(v4[3]),
        'events': [_chat('太大', 'bbbbbbbb-0000-4000-8000-000000000023')],
      },
      v4[4],
      {
        ..._reading(v4[5]),
        'events': [_chat('create_time', 'bbbbbbbb-0000-4000-8000-000000000025')],
      },
    ];
  },
};

Map<String, Object?> _reading(Object? reading) => reading! as Map<String, Object?>;

Map<String, Object?> _withoutGifts(Object? reading) => {
  ..._reading(reading),
  'events': [
    for (final event in _reading(reading)['events']! as List<Object?>)
      if (_reading(event)['kind'] != 'gift') event,
  ],
};

/// A synthetic chat line of the default user as the v4 projection shows it.
Map<String, Object?> _chat(
  String text,
  String id, {
  int? sentAt,
  int? userLevel = 16,
  int? medalLevel = 8,
  String? medalName = '在花间',
}) => {
  'kind': 'chat',
  'id': 'missevan:$id',
  'sentAt': sentAt,
  'userId': '7300001',
  'userName': '观众甲',
  'text': text,
  'userLevel': userLevel,
  'medalLevel': medalLevel,
  'medalName': medalName,
};

void main() {
  group('protocol', () {
    test("the guest session is FM_SESS of S05-user-info's Set-Cookie, as v4 read it; the signature is not", () {
      final recorded = (_json('../S05-user-info/meta.json')! as Map<String, Object?>)['response']!;
      final setCookie = ((recorded as Map<String, Object?>)['headers']! as Map<String, Object?>)['set-cookie']!;
      final cookies = (setCookie as List<Object?>).cast<String>();
      expect(MissevanDanmakuProtocol.session(cookies), _v4('S06-live')['guestSession']);
      expect(MissevanDanmakuProtocol.session(cookies.reversed), _v4('S06-live')['guestSession']);
      expect(MissevanDanmakuProtocol.session([' FM_SESS=a|b ; path=/']), 'a|b');
      for (final headers in <List<String>>[
        [],
        ['FM_SESS.sig=x; path=/'],
        ['FM_SESS=; path=/'],
        ['FM_SESS="a b"; path=/'],
        ['FM_SESS=a,b; path=/'],
        ['FM_SESS=a b; path=/'],
        ['other=1; FM_SESS=v'],
      ]) {
        expect(MissevanDanmakuProtocol.session(headers), isNull, reason: '$headers');
      }
    });

    test("the socket's address is the detail's (S04-live) and the recorded handshakes' (S06, S07), v4's", () {
      final detail = (_json('../S04-live/body.json')! as Map<String, Object?>)['info']! as Map<String, dynamic>;
      final args = MissevanApi.danmakuArgs(detail, roomId: _otherRoomId);
      expect(MissevanDanmakuProtocol.endpoint(args.url, roomId: _otherRoomId), args.url);
      expect(args.url.toString(), 'wss://im.missevan.com/ws?room_id=$_otherRoomId');
      for (final name in ['S06-live', 'S07-brotli']) {
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        final roomId = _v4(name)['roomId']! as String;
        final url = Uri.parse(handshake['url']! as String);
        expect(MissevanDanmakuProtocol.endpoint(url, roomId: roomId), url);
        expect(url.toString(), (_v4(name)['connector']! as Map<String, Object?>)['endpoint']);
      }
    });

    test('an address without room_id gets it; one for another room, host or scheme is replaced', () {
      Uri endpoint(String url) => MissevanDanmakuProtocol.endpoint(Uri.parse(url), roomId: _roomId);
      final standard = Uri.parse('wss://im.missevan.com/ws?room_id=$_roomId');
      // The guest session answer lists this form (S05-user-info); the server
      // answers it with HTTP 400 (2026-09-29).
      expect(endpoint('wss://im.missevan.com/ws'), standard);
      expect(endpoint('wss://im2.missevan.com/ws?x=1'), Uri.parse('wss://im2.missevan.com/ws?x=1&room_id=$_roomId'));
      expect(endpoint('wss://missevan.com/ws?room_id=$_roomId'), Uri.parse('wss://missevan.com/ws?room_id=$_roomId'));
      for (final url in [
        'wss://im.missevan.com/ws?room_id=$_otherRoomId',
        'wss://im.missevan.com/ws?room_id=$_roomId&room_id=$_otherRoomId',
        'ws://im.missevan.com/ws?room_id=$_roomId',
        'https://im.missevan.com/ws?room_id=$_roomId',
        'wss://im.missevan.com.example/ws?room_id=$_roomId',
        'wss://evilmissevan.com/ws?room_id=$_roomId',
        'wss://user@im.missevan.com/ws?room_id=$_roomId',
        'wss://im.missevan.com/ws?room_id=%zz',
      ]) {
        expect(endpoint(url), standard, reason: url);
      }
    });

    test('handshake headers: the API headers with the session cookie, as the S07 handshake was recorded', () {
      final headers = MissevanDanmakuProtocol.handshakeHeaders(MissevanApi.headers, _sessionA);
      expect(headers, {...MissevanApi.headers, 'cookie': 'FM_SESS=$_sessionA'});
      final handshake = (_meta('S07-brotli')['handshakes']! as List<Object?>).single! as Map<String, Object?>;
      expect({...headers, 'cookie': '<redacted>'}, handshake['headers']);
      expect(MissevanDanmakuProtocol.handshakeHeaders({'Cookie': 'a=1', 'origin': 'o'}, _sessionB), {
        'origin': 'o',
        'cookie': 'FM_SESS=$_sessionB',
      });
      // v4 sent the cookie, the origin and a Chrome UA; the origin is the one
      // the server checks.
      final v4 = (_v4('S06-live')['connector']! as Map<String, Object?>)['handshakeHeaders']! as Map<String, Object?>;
      expect(v4['origin'], headers['origin']);
      expect(v4['cookie'], 'FM_SESS=${_v4('S06-live')['guestSession']}');
    });

    test("the join is the recorded one byte for byte (S06 as binary, S07 as text) and v4's; a rejoin says so", () {
      for (final name in ['S06-live', 'S07-brotli']) {
        final v4 = _v4(name);
        final sent = _frames(name).firstWhere((frame) => frame.dir == 'out').data;
        final join = MissevanDanmakuProtocol.join(v4['roomId']! as String, uuid: v4['uuid']! as String);
        expect(join, _textOf(sent));
        expect(join, (v4['connector']! as Map<String, Object?>)['join']);
      }
      expect(jsonDecode(MissevanDanmakuProtocol.join(_roomId, uuid: 'u', reconnect: true)), {
        'action': 'join',
        'uuid': 'u',
        'type': 'room',
        'room_id': 246709466,
        'reconnect': 1,
      });
      expect(
        MissevanDanmakuProtocol.uuid(Random(1)),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(MissevanDanmakuProtocol.uuid(Random(1)), isNot(MissevanDanmakuProtocol.uuid(Random(2))));
    });

    test("the heartbeat is v4's and the recorded one, every 30 s; the server's echo shows nothing", () {
      for (final name in ['S06-live', 'S07-brotli']) {
        final frames = _frames(name);
        final sent = [
          for (final frame in frames.skip(2))
            if (frame.dir == 'out') _textOf(frame.data),
        ];
        expect(sent, everyElement(MissevanDanmakuProtocol.heartbeat));
        expect(sent, isNotEmpty);
        expect(
          frames.where((frame) => frame.dir == 'in' && frame.data == MissevanDanmakuProtocol.heartbeat),
          hasLength(sent.length),
        );
        final v4 = _v4(name)['connector']! as Map<String, Object?>;
        expect(v4['heartbeat'], MissevanDanmakuProtocol.heartbeat);
        expect(v4['heartbeatSeconds'], MissevanDanmakuProtocol.heartbeatInterval.inSeconds);
      }
      final echo = MissevanDanmakuProtocol.decode(MissevanDanmakuProtocol.heartbeat, roomId: _roomId, uuid: 'u');
      expect(echo.messages, isEmpty);
      expect(echo.joined, isNull);
    });

    test('a chat line and the statistics fill the message model', () {
      final message = MissevanDanmakuProtocol.chat({
        'type': 'message',
        'event': 'new',
        'msg_id': 'x-1',
        'message': ' 你好 ',
        'time': 1790612400123,
        'user': {
          'user_id': 7300001,
          'username': '观众甲',
          'titles': [
            {'type': 'noble', 'name': '偶像', 'level': 3},
            {'type': 'medal', 'name': '在花间', 'level': 8},
            {'type': 'level', 'level': 16},
          ],
        },
      })!;
      expect(message.type, LiveMessageType.chat);
      expect(message.userName, '观众甲');
      expect(message.userId, '7300001');
      expect(message.message, '你好');
      expect(message.messageId, 'x-1');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790612400123));
      expect(message.color, LiveMessageColor.white);
      expect([message.userLevel, message.fansName, message.fansLevel], ['16', '在花间', '8']);
      expect(message.data, isNull);
      expect(message.isLocal, isFalse);
      final figures = MissevanDanmakuProtocol.audience({'score': 105019, 'online': 22, 'vip': 6});
      expect(figures.map((figure) => figure.type), everyElement(LiveMessageType.online));
      expect(figures.map((figure) => (figure.message, figure.userName)), everyElement(('', '')));
      expect(
        [for (final figure in figures) (figure.data! as LiveAudienceUpdate).kind],
        [LiveAudienceMetricKind.popularity, LiveAudienceMetricKind.onlineViewers],
      );
      expect([for (final figure in figures) (figure.data! as LiveAudienceUpdate).value], [105019, 22]);
    });

    test('the listeners come only with the chat: audience.dart calls them room-realtime', () {
      final capability = AudiencePlatformCapability.of(SiteIds.missevan);
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomRealtime);
      expect(capability.hasPopularity, isTrue);
      expect(capability.onlineAvailableInRoomLists, isFalse);
      // The detail's `online` is always 0 (S04-live, REG-MISSEVAN-002).
      final detail = (_json('../S04-live/body.json')! as Map<String, Object?>)['info']! as Map<String, Object?>;
      final room = detail['room']! as Map<String, Object?>;
      expect((room['statistics']! as Map<String, Object?>)['online'], 0);
    });

    test('a frame is flag 1, the declared UTF-8 length and Brotli; anything else reads as nothing', () {
      final frame = _frame({'a': '猫耳'});
      expect(MissevanDanmakuProtocol.text(frame), '{"a":"猫耳"}');
      expect(MissevanDanmakuProtocol.text(Uint8List.fromList(frame)), '{"a":"猫耳"}');
      expect(MissevanDanmakuProtocol.text([...frame]..[1] += 1), isNull);
      expect(MissevanDanmakuProtocol.text([...frame]..[1] -= 1), isNull);
      expect(MissevanDanmakuProtocol.text([...frame]..[0] = 0), isNull);
      expect(MissevanDanmakuProtocol.text(frame.sublist(0, 4)), isNull);
      expect(MissevanDanmakuProtocol.text([...frame, 0]), isNull);
      expect(MissevanDanmakuProtocol.text(null), isNull);
      expect(MissevanDanmakuProtocol.text('text'), 'text');
    });
  });

  group('recorded frames against v4', () {
    for (final name in ['S06-live', 'S07-brotli']) {
      test('$name: every received frame reads as v4 read it', () {
        final v4 = _v4Frames(name);
        final roomId = _v4(name)['roomId']! as String;
        final uuid = _v4(name)['uuid']! as String;
        final frames = _frames(name).where((frame) => frame.dir == 'in' && frame.url == null).toList();
        expect(frames.map((frame) => frame.index), v4.keys);
        for (final frame in frames) {
          expect(
            _readAsV4(frame.data, roomId: roomId, uuid: uuid),
            v4[frame.index],
            reason: 'frame ${frame.index}',
          );
        }
      });
    }

    test('S06-live: joined at the answer; three chat lines and heat and listeners; another room skipped', () {
      final frames = _frames('S06-live');
      final readings = [
        for (final frame in frames.where((frame) => frame.dir == 'in' && frame.url == null))
          MissevanDanmakuProtocol.decode(frame.data, roomId: _roomId, uuid: _v4('S06-live')['uuid']! as String),
      ];
      expect(readings.where((reading) => reading.joined ?? false), hasLength(1));
      final messages = readings.expand((reading) => reading.messages).toList();
      expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(3));
      expect(messages.first.messageId, '354cf329-f325-412d-b50e-1e49f3b375c5', reason: 'no missevan: prefix');
      expect(messages.map((message) => message.data).whereType<LiveAudienceUpdate>().map((data) => data.value), [
        105019,
        22,
      ]);
      // Frame 9 is a global gift notice about room 167409308.
      final notice = MissevanDanmakuProtocol.text(frames[9].data)!;
      expect(jsonDecode(notice), containsPair('room_id', 167409308));
    });

    test("S07-brotli: the server's own frames are compressed Brotli and read in full", () {
      final meta = _meta('S07-brotli');
      final reencoded = (meta['reencoded']! as List<Object?>).cast<int>().toSet();
      final own = [
        for (final frame in _frames('S07-brotli'))
          if (frame.dir == 'in' && frame.data is List<int> && !reencoded.contains(frame.index)) frame.data as List<int>,
      ];
      expect(own, hasLength(4));
      for (final data in own) {
        final length = data[1] | data[2] << 8 | data[3] << 16;
        expect(data.length - 4, lessThan(length), reason: 'smaller than the text: compressed');
        expect(utf8.encode(MissevanDanmakuProtocol.text(data)!), hasLength(length));
      }
      final uuid = _v4('S07-brotli')['uuid']! as String;
      final messages = [
        for (final frame in _frames('S07-brotli'))
          if (frame.dir == 'in')
            ...MissevanDanmakuProtocol.decode(frame.data, roomId: '180370487', uuid: uuid).messages,
      ];
      expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(9));
      expect(
        [
          for (final message in messages)
            if (message.data case final LiveAudienceUpdate data) data.value,
        ],
        [6374, 9],
      );
    });
  });

  group('synthetic frames (S08-synthetic) against v4', () {
    final roomId = _cases['roomId']! as String;
    final uuid = _cases['uuid']! as String;
    final cases = [
      for (final entry in _cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames})
          (name: name, frames: frames.cast<Map<String, Object?>>()),
    ];

    test('every case has v4 output, and every difference names a case', () {
      expect(_v4Cases.keys, cases.map((entry) => entry.name));
      expect(cases.map((entry) => entry.name), containsAll(_differences.keys));
    });

    for (final (:name, :frames) in cases) {
      test(name, () {
        final v4 = _v4Cases[name]! as List<Object?>;
        final expected = _differences[name]?.call(v4) ?? v4;
        expect([for (final frame in frames) _readAsV4(_caseFrame(frame), roomId: roomId, uuid: uuid)], expected);
      });
    }

    test('refusals carry their code and text', () {
      final frames = cases.firstWhere((entry) => entry.name.startsWith('the answer to the join')).frames;
      final refused = MissevanDanmakuProtocol.decode(_caseFrame(frames[1]), roomId: roomId, uuid: uuid);
      expect(refused.joined, isFalse);
      expect(refused.refusal, '500030004 无法找到该聊天室');
      final noCode = MissevanDanmakuProtocol.decode(_caseFrame(frames[4]), roomId: roomId, uuid: uuid);
      expect(noCode.joined, isFalse);
      expect(noCode.refusal, '');
    });
  });

  group('connection', () {
    test('asks a guest session, opens the socket with its cookie, joins, and is ready on the answer', () async {
      final http = ReplayHttp.fixtures('../../fixtures/missevan', ['S05-user-info']);
      final connector = _Connector();
      final connection = MissevanDanmakuConnection(http: http, connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final request = http.requests.single;
      expect(request.site, SiteIds.missevan);
      expect(request.method, 'GET');
      expect(request.url, MissevanApi.guestSession);
      expect(request.headers, MissevanApi.headers);
      expect(request.followRedirects, isFalse);
      expect(request.timeout, MissevanDanmakuConnection.sessionTimeout);
      final session = _v4('S06-live')['guestSession']! as String;
      expect(connector.endpoints, [_args.url]);
      expect(connector.headers.single, {...MissevanApi.headers, 'cookie': 'FM_SESS=$session'});
      expect(connector.routes.single, isA<DirectRoute>());
      final channel = connector.channels.single;
      final join = channel.joins.single;
      expect(join.keys, ['action', 'uuid', 'type', 'room_id']);
      expect(join, containsPair('room_id', 246709466));
      expect(events, isEmpty, reason: 'not joined before the answer');
      expect(connection.status, DanmakuStatus.connecting);
      channel.answer();
      await _until(() => events.isNotEmpty);
      // A repeated answer does not report the room joined again.
      channel.answer();
      await _wait(const Duration(milliseconds: 10));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.connected);
      await connection.close();
    });

    for (final (name, count) in const [('S06-live', 5), ('S07-brotli', 11)]) {
      test("replaying $name reports what v4 read, in order; its recorded join answer is not this socket's", () async {
        final roomId = _v4(name)['roomId']! as String;
        final connector = _Connector();
        final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector);
        final events = _record(connection);
        await connection.connect(
          MissevanDanmakuArgs(roomId: roomId, url: Uri.parse('wss://im.missevan.com/ws?room_id=$roomId')),
        );
        final channel = connector.channels.single;
        final expected = <Object?>[];
        for (final frame in _frames(name)) {
          if (frame.dir != 'in' || frame.url != null) continue;
          channel.incoming.add(frame.data);
          expected.addAll(_v4Frames(name)[frame.index]!['events']! as List<Object?>);
        }
        expect(expected, hasLength(count));
        await _until(() => _messages(events).length == count);
        await _wait(const Duration(milliseconds: 10));
        expect(_messages(events).map(_asV4), expected);
        expect(events.whereType<DanmakuReady>(), isEmpty, reason: 'the recorded answer names another uuid');
        channel.answer();
        await _until(() => connection.isConnected);
        await connection.close();
      });
    }

    test("only this room's chat and figures; another join's answer does not count", () async {
      final connector = _Connector();
      final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector);
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming
        ..add(_frame(_answer('another-uuid')))
        ..add(_frame(_chatLine('别的房间', roomId: _otherRoomId)))
        ..add(
          _frame([
            _chatLine('这个房间'),
            {
              'type': 'room',
              'event': 'statistics',
              'room_id': 246709466,
              'statistics': {'score': 12, 'online': 3},
            },
          ]),
        );
      await _until(() => _messages(events).length == 3);
      await _wait(const Duration(milliseconds: 10));
      expect(events.whereType<DanmakuReady>(), isEmpty);
      expect(_messages(events).map((message) => message.message), ['这个房间', '', '']);
      await connection.close();
    });

    test('timing: 30 s heartbeat, max(3 × 30 s, 90 s) = 90 s silence limit, 5 s join timer, 8 reconnects', () {
      final connection = MissevanDanmakuConnection(http: _SessionHttp([_guest(_sessionA)]));
      expect(connection.heartbeatInterval, const Duration(seconds: 30));
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 30));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives 90 s');
      expect(policy.joinTimeout, const Duration(seconds: 5));
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(connection.site, SiteIds.missevan);
    });

    test('sends the heartbeat on its 30 s timer and on demand, as text; nothing after close', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 3);
          expect(sent.skip(1).take(2), [MissevanDanmakuProtocol.heartbeat, MissevanDanmakuProtocol.heartbeat]);
          await connection.close();
          final count = sent.length;
          connection.heartbeat();
          await _wait(const Duration(milliseconds: 20));
          expect(sent, hasLength(count), reason: 'nothing after close');
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            periods.add(period);
            return parent.createPeriodicTimer(zone, const Duration(milliseconds: 5), callback);
          },
        ),
      );
      expect(periods, [const Duration(seconds: 30)]);
    });

    test('the proxy policy routes the handshake', () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        _SessionHttp([_guest(_sessionA)]),
        connector,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.missevan: route}),
      );
      await connection.connect(_args);
      expect(connector.routes.single, route);
      await connection.close();
    });

    test("the arguments' address is checked: room_id added, a foreign host replaced; the room id trimmed", () async {
      final connector = _Connector();
      final http = _SessionHttp([_guest(_sessionA)]);
      final connection = _connection(http, connector);
      await connection.connect(MissevanDanmakuArgs(roomId: ' $_roomId ', url: Uri.parse('wss://im.missevan.com/ws')));
      await connection.connect(
        MissevanDanmakuArgs(roomId: _roomId, url: Uri.parse('wss://chat.example.com/ws?room_id=$_roomId')),
      );
      expect(connector.endpoints, List.filled(2, _args.url));
      expect(connector.channels.first.joins.single['room_id'], 246709466);
      await connection.close();
    });

    test('a room id that is not one ends with connectionFailed and asks nothing', () async {
      for (final roomId in ['', 'abc', '0123', '1234567890123456789']) {
        final http = _SessionHttp([_guest(_sessionA)]);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await connection.connect(MissevanDanmakuArgs(roomId: roomId, url: _args.url));
        expect(http.requests, isEmpty, reason: roomId);
        expect(connector.endpoints, isEmpty);
        expect(
          events.single,
          isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed),
        );
        expect(connection.status, DanmakuStatus.closed);
      }
    });

    test('a guest session is asked three times, 0.5 s and 1 s apart; the third answer is used', () async {
      final held = <_HeldTimer>[];
      final http = _SessionHttp([
        const TransportFailure(SiteIds.missevan, TransportReason.connect),
        LiveResponse(status: 503, bytes: utf8.encode('busy'), url: MissevanApi.guestSession),
        _guest(_sessionC),
      ]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      await _heldTimers(held, () async {
        final connecting = connection.connect(_args);
        await _fire(held, const Duration(milliseconds: 500));
        await _until(() => http.requests.length == 2);
        await _fire(held, const Duration(seconds: 1));
        await connecting;
        await connection.close();
      });
      expect(http.requests, hasLength(3));
      expect(connector.headers.single['cookie'], 'FM_SESS=$_sessionC');
    });

    test('no guest session after three answers ends with credentialsUnavailable and opens nothing', () async {
      for (final answers in <List<Object>>[
        [LiveResponse(status: 200, bytes: utf8.encode('{"code":0}'), url: MissevanApi.guestSession)],
        [
          LiveResponse(
            status: 302,
            headers: const {
              'set-cookie': ['FM_SESS=$_sessionA; path=/'],
              'location': ['https://fm.missevan.com/'],
            },
            bytes: const [],
            url: MissevanApi.guestSession,
          ),
        ],
        [LiveResponse(status: 403, bytes: const [], url: MissevanApi.guestSession)],
        [const TransportFailure(SiteIds.missevan, TransportReason.timeout)],
      ]) {
        final delays = <Duration>[];
        final http = _SessionHttp(answers);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await _fastTimers(delays, () => connection.connect(_args));
        expect(http.requests, hasLength(3));
        expect(connector.endpoints, isEmpty);
        expect(
          events.single,
          isA<DanmakuClosed>()
              .having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable)
              .having((event) => event.detail, 'detail', isNotEmpty),
        );
        expect(connection.status, DanmakuStatus.closed);
      }
    });

    test('close while the session is asked: the request is cancelled, nothing opens or is reported', () async {
      final hold = Completer<void>();
      final http = _SessionHttp([_guest(_sessionA)], hold: hold);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      hold.complete();
      await connecting;
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a join unanswered for 5 s drops the socket; the next one joins again, with a new uuid', () async {
      final held = <_HeldTimer>[];
      final connector = _Connector();
      final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        final first = connector.channels.single;
        first.incoming.add(_frame({'type': 'user', 'event': 'connect'}));
        await _wait(const Duration(milliseconds: 5));
        await _fire(held, const Duration(seconds: 5));
        // The runtime's backoff: one endpoint, 1 s × (1 round + 1).
        await _fire(held, const Duration(seconds: 2));
        await _until(() => connector.channels.length == 2);
        expect(first.closed, isTrue);
        connector.channels.last.answer();
        await _until(() => connection.isConnected);
        expect(_active(held, const Duration(seconds: 5)), isEmpty, reason: 'answered: no join timer');
        await connection.close();
      });
      final joins = [for (final channel in connector.channels) channel.joins.single];
      expect(joins.map((join) => join['uuid']).toSet(), hasLength(2));
      expect(joins.map((join) => join['reconnect']), [null, null], reason: 'never joined before');
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
    });

    test('a dropped socket reconnects after 2 s with the same session and rejoins with reconnect: 1', () async {
      final held = <_HeldTimer>[];
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.answer();
        await _until(() => connection.isConnected);
        await connector.channels.single.incoming.close();
        // One endpoint: 1 s × (1 round + 1).
        await _fire(held, const Duration(seconds: 2));
        await _until(() => connector.channels.length == 2);
        connector.channels.last.answer();
        await _until(() => events.whereType<DanmakuReady>().length == 2);
      });
      expect(http.requests, hasLength(1), reason: 'the session lasts three days');
      expect(connector.headers.map((headers) => headers['cookie']), List.filled(2, 'FM_SESS=$_sessionA'));
      expect(connector.channels.last.joins.single['reconnect'], 1);
      expect(connector.channels.first.joins.single.containsKey('reconnect'), isFalse);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('a refused join asks a new session and reopens at once, without a notice', () async {
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single..answer(code: 500030004);
      await _until(() => connector.channels.length == 2);
      expect(first.closed, isTrue);
      connector.channels.last
        ..answer()
        ..incoming.add(_frame(_chatLine('之后')));
      await _until(() => _messages(events).isNotEmpty);
      expect(http.requests, hasLength(2));
      expect(connector.headers.map((headers) => headers['cookie']), ['FM_SESS=$_sessionA', 'FM_SESS=$_sessionB']);
      expect(connector.endpoints, List.filled(2, _args.url));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).single.message, '之后');
      await connection.close();
    });

    test('the fourth refusal in one connect ends with connectionFailed, naming the refusal', () async {
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB), _guest(_sessionC), _guest(_sessionD)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      for (var socket = 1; socket <= 4; socket++) {
        await _until(() => connector.channels.length == socket && connector.channels.last.joins.isNotEmpty);
        connector.channels.last.answer(code: 500030004);
      }
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(http.requests, hasLength(4));
      expect(connector.channels, hasLength(4));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
      expect(
        events.single,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed)
            .having((event) => event.detail, 'detail', 'Join refused: 500030004 无法找到该聊天室'),
      );
      expect(connection.status, DanmakuStatus.closed);
    });

    test('a refused join without a new session ends with credentialsUnavailable', () async {
      final held = <_HeldTimer>[];
      final http = _SessionHttp([_guest(_sessionA), const TransportFailure(SiteIds.missevan, TransportReason.connect)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.answer(code: 500030004);
        await _fire(held, const Duration(milliseconds: 500));
        await _fire(held, const Duration(seconds: 1));
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(http.requests, hasLength(4), reason: 'the first session, then three attempts');
      expect(connector.channels.single.closed, isTrue);
      expect(
        events.single,
        isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable),
      );
    });

    test('refusals are counted per connect', () async {
      final http = _SessionHttp([_guest(_sessionA)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      for (var round = 0; round < 2; round++) {
        await connection.connect(_args);
        for (var refusal = 0; refusal < 3; refusal++) {
          final opened = connector.channels.length;
          connector.channels.last.answer(code: 500030004);
          await _until(() => connector.channels.length == opened + 1 && connector.channels.last.joins.isNotEmpty);
        }
      }
      connector.channels.last.answer();
      await _until(() => connection.isConnected);
      expect(connector.channels, hasLength(8));
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up with reconnectsExhausted', () async {
      final delays = <Duration>[];
      final connector = _Connector(
        fail: (endpoint) =>
            WebSocketException("Connection to '$endpoint' was not upgraded to websocket, HTTP status code: 403"),
      );
      final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays.where((delay) => delay >= const Duration(seconds: 2)), [
        for (final seconds in [2, 3, 4, 5, 6, 6, 6, 6]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, hasLength(9));
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('403'))
            .having((event) => event.detail, 'detail', isNot(contains(_sessionA))),
      );
      expect(events, hasLength(2));
    });

    test('close: no event, heartbeat or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single..answer();
      await _until(() => connection.isConnected);
      await connection.close();
      await connection.close();
      channel.incoming
        ..add(_frame(_chatLine('关闭之后')))
        ..add(_frame(_answer(channel.joins.single['uuid']! as String, code: 500030004)));
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, hasLength(1), reason: 'only the join');
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another room closes the first socket and asks a session for the new one', () async {
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await connection.connect(
        MissevanDanmakuArgs(roomId: _otherRoomId, url: Uri.parse('wss://im.missevan.com/ws?room_id=$_otherRoomId')),
      );
      expect(http.requests, hasLength(2));
      expect(connector.endpoints.last, Uri.parse('wss://im.missevan.com/ws?room_id=$_otherRoomId'));
      expect(connector.headers.last['cookie'], 'FM_SESS=$_sessionB');
      expect(first.closed, isTrue);
      first.incoming
        ..add(_frame(_chatLine('旧房间')))
        ..add(_frame(_answer(first.joins.single['uuid']! as String, code: 500030004)));
      connector.channels.last
        ..answer()
        ..incoming.add(_frame(_chatLine('新房间', roomId: _otherRoomId)));
      await _until(() => _messages(events).isNotEmpty);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).single.message, '新房间');
      expect(connector.channels, hasLength(2), reason: "the old socket's refusal is ignored");
      await connection.close();
    });

    test('takes MissevanDanmakuArgs only', () async {
      final connection = _connection(_SessionHttp([_guest(_sessionA)]), _Connector());
      await expectLater(connection.connect(_roomId), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under missevan', () {
      final http = _SessionHttp([_guest(_sessionA)]);
      final registry = DanmakuRegistry({SiteIds.missevan: () => MissevanDanmakuConnection(http: http)});
      expect(registry.platforms, [SiteIds.missevan]);
      expect(registry.connectionFor(' Missevan '), isA<MissevanDanmakuConnection>());
      expect(registry.connectionFor('twitch'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the cookie and origin, the join, the recorded frames, the echo', () async {
      final received = <Object?>[];
      final queries = <String>[];
      final cookies = <String?>[];
      final origins = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        queries.add(request.uri.query);
        cookies.add(request.headers.value('cookie'));
        origins.add(request.headers.value('origin'));
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          received.add(frame);
          if (frame == MissevanDanmakuProtocol.heartbeat) {
            socket.add(MissevanDanmakuProtocol.heartbeat);
            return;
          }
          final join = jsonDecode(frame as String) as Map<String, Object?>;
          socket.add(_frame(_answer(join['uuid']! as String, roomId: '180370487')));
          for (final recorded in _frames('S07-brotli')) {
            if (recorded.dir == 'in' && recorded.url == null && recorded.index > 3) socket.add(recorded.data);
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = MissevanDanmakuConnection(
        http: _SessionHttp([_guest(_sessionA)]),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          requested.add(endpoint);
          return connectIoSocket(
            endpoint.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(connection);
      await connection.connect(
        MissevanDanmakuArgs(roomId: '180370487', url: Uri.parse('wss://im.missevan.com/ws?room_id=180370487')),
      );
      await _until(() => _messages(events).length == 11);
      expect(requested, [Uri.parse('wss://im.missevan.com/ws?room_id=180370487')]);
      expect(queries, ['room_id=180370487']);
      expect(cookies, ['FM_SESS=$_sessionA']);
      expect(origins, [MissevanApi.origin]);
      expect((jsonDecode(received.single! as String) as Map<String, Object?>)['room_id'], 180370487);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).where((message) => message.type == LiveMessageType.chat), hasLength(9));
      connection.heartbeat();
      await _until(() => received.length == 2);
      expect(received.last, MissevanDanmakuProtocol.heartbeat);
      await _wait(const Duration(milliseconds: 20));
      expect(_messages(events), hasLength(11), reason: 'the echo shows nothing');
      await connection.close();
    });
  });
}
