// Missevan danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.13-猫耳FM弹幕/record.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S06-live, S07-brotli) and the synthetic frames (S08-synthetic), written by
// fixtures/missevan/danmaku/v4_expected.dart; the follow-ups of M5.F (B-1, B-9)
// against the recorded S09-events and synthetic frames.
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
  if (message.data case final MissevanGift gift) {
    // B-9: gifts are reported again, as v4 reported them.
    return {
      'kind': 'gift',
      'sentAt': message.sentAt?.millisecondsSinceEpoch,
      'userId': message.userId,
      'userName': message.userName,
      'giftId': gift.id,
      'giftName': gift.name,
      'count': gift.count,
      'icon': gift.icon?.toString(),
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

  /// Keeps every request pending until it completes; set later to hold only
  /// the later requests.
  Completer<void>? hold;
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
  new({this.fail, this.failures = const []});

  /// Thrown for every handshake, with the endpoint.
  final Exception Function(Uri endpoint)? fail;

  /// Thrown by the next handshakes, one each, in order (B-1); more can be
  /// added later.
  final List<Exception> failures;
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
    if (failures.isNotEmpty) throw failures.removeAt(0);
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

MissevanDanmakuConnection _connection(
  _SessionHttp http,
  _Connector connector, {
  ProxyPolicy? proxy,
  DateTime Function()? now,
}) => MissevanDanmakuConnection(
  http: http,
  connector: connector.call,
  proxy: proxy ?? const FixedProxyPolicy(),
  now: now,
);

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
/// (docs/D-弹幕/D01-平台弹幕协议/D01.13-猫耳FM弹幕/record.md, "与归档 v4 的差异"): v4's reading → the
/// new one, per case. Cases not listed read as v4 read them.
///
/// Difference 2 (gifts not reported) is gone with B-9: gifts are reported
/// again (not shown yet), and the two cases with a gift read as v4 read them.
/// That case's paid question has the shape of the site's store (`content`),
/// not the server's (`question`, S09-events), so it still shows nothing.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
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

typedef _Recorded = ({int index, String room, Object data});

/// The frames of S09-events (B-9), recorded in several rooms; each line names
/// its room.
List<_Recorded> _events() {
  var index = 0;
  return [
    for (final line in File('$_root/S09-events/frames.jsonl').readAsLinesSync())
      if (jsonDecode(line) case {'room': final String room, 'b64': final String b64})
        (index: index++, room: room, data: base64Decode(b64)),
  ];
}

/// When S09-events' second batch began: "now" for the tests that need one.
final DateTime _recordedAt = DateTime.utc(2026, 9, 30, 15, 26, 41);

/// A message in a short form for comparing whole frames.
String _short(LiveMessage message) => switch (message.data) {
  final LiveSuperChatMessage paid =>
    'superChat ${paid.userName}: ${paid.message} (${paid.priceText}) #${message.messageId}',
  final LiveNoticeKind kind => 'notice ${kind.name} ${message.message}',
  final LiveRetraction target => 'retraction $target',
  MissevanGift() => 'gift ${message.userName}: ${message.message} #${message.messageId}',
  final LiveAudienceUpdate update => 'online ${update.kind.name} ${update.value}',
  _ => '${message.type.name} ${message.userName}: ${message.message} #${message.messageId}',
};

/// What one frame of room [roomId] shows, in the short form.
List<String> _read(Object data, {String roomId = _roomId}) => [
  for (final message in MissevanDanmakuProtocol.decode(
    data,
    roomId: roomId,
    uuid: 'u',
    receivedAt: _recordedAt,
  ).messages)
    _short(message),
];

/// A synthetic item of this room, as the server would send it.
List<int> _item(String type, String event, [Map<String, Object?> fields = const {}]) =>
    _frame({'type': type, 'event': event, 'room_id': int.parse(_roomId), ...fields});

/// A synthetic `message_tip` in the site's markup around [text].
String _tip(String text) => [
  "<img src='https://static.maoercdn.com/live/pk/notification/win.png' width='15' height='15' /> ",
  "<font color='#ffffff'>$text</font><font color='#BDBDBD'>详情</font>",
  "<img src='https://static.maoercdn.com/live/pk/notification/arrow.png' width='15' height='15' />",
].join();

/// What each S09-events frame shows (B-9), by frame.
const Map<int, List<String>> _s09 = {
  0: [], // question/answer: the site moves the question within its panel
  1: ['chat 观众3: 是呀 #2e2dcc2b-7ae3-4aed-a7da-ef7183f07003'],
  2: ['superChat 观众4: 那我要听【告白气球】 (50 钻) #6abd2844d7d16a8779a983a0'],
  3: ['chat 观众3: 都开始减肥了，那就是快了） #21a91e30-3b4d-4937-82e9-70af5aabc6ae'],
  4: ['gift 观众5: 喵喵耳机 ×1 #6abd28483bf59b1727913799'],
  5: ['notice system 恭喜胜利！你在幻影PK中击败 观众7 实力出众！'],
  6: [
    'notice system 观众9 与 观众8 心意共鸣，获花神赐福！誓约次数 +1，请继续缔结誓约，增加誓约次数，共登 [誓约榜] 榜首，瓜分终极奖池。',
    'notice system 恭喜主播获得 PK 胜利，继续支持主播吧',
  ],
  7: [], // pk/punish_finish
  8: [], // pk/close without a result
  9: ['notice system 主播正在匹配 PK 对手，请耐心等候'],
  10: ['notice system PK 已开始，快送礼支持主播吧'],
  11: [], // pk/update without a 花神赐福 tip
  12: ['notice system 【祈福开启】PK双方合力凝聚 60000 祈福值，祈福值最高者将获得花神的赐福！'],
  13: [], // global_pk/update without a tip
  14: ['notice system 恭喜胜利！你在幻影PK中击败 观众18 实力出众！', 'notice system 祈福未达，花神隐去。羁绊仍在，期待下次唤醒......'],
  15: ['notice system 幻影PK即将开启，2分钟后自动匹配对手，迎接挑战吧！'],
  16: ['gift 观众25: 幻彩礼炮 ×1 #6abd2807a625be764d218212'],
  17: ['gift 观众25: 幻彩礼炮 ×1 #'], // a later send of the combo: its oid is all zeros
  18: ['gift 观众26: 书写星辰 ×1 #6abd2756de6d323fb1c9caa3'],
  19: [], // super_fan/renewal
  20: ['notice system 已选择跳过本场幻影PK，等待再次开启。'],
  21: ['notice system 雷达启动！正在召唤你的对手...'],
  22: ['notice system 匹配成功！与 观众28 的对决正式展开--PK开始！'],
  23: ['notice system 我方已逃跑，本场PK判定失败'],
  24: [], // gift/cross_send: to another room of the team live
  25: ['notice system 观众9 续费了大咖贵族'],
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
        fail: (endpoint) => WebSocketException("Connection to '$endpoint' was not upgraded to websocket", 403),
      );
      final http = _SessionHttp([_guest(_sessionA)]);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays.where((delay) => delay >= const Duration(seconds: 2)), [
        for (final seconds in [2, 3, 4, 5, 6, 6, 6, 6]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, hasLength(9));
      // B-1: the first 403 (dart:io's exception carries the status) asked a
      // new session (the same answer here); the rest of the streak does not
      // ask again.
      expect(http.requests, hasLength(2));
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

  group('paid questions, clears, notices and gifts (B-9)', () {
    test('S09-events: every recorded frame reads as the site shows it', () {
      final frames = _events();
      expect(frames.map((frame) => frame.index), _s09.keys);
      for (final frame in frames) {
        expect(_read(frame.data, roomId: frame.room), _s09[frame.index], reason: 'frame ${frame.index}');
      }
      // Read in another room, none of them shows anything.
      for (final frame in frames.where((frame) => frame.index != 11 && frame.index != 12)) {
        expect(_read(frame.data, roomId: '1'), isEmpty, reason: 'frame ${frame.index}');
      }
    });

    test('a paid question is a super chat: every field', () {
      final frame = _events()[2];
      final message = MissevanDanmakuProtocol.decode(
        frame.data,
        roomId: frame.room,
        uuid: 'u',
        receivedAt: _recordedAt,
      ).messages.single;
      final created = DateTime.fromMillisecondsSinceEpoch(1790781508650);
      expect(message.type, LiveMessageType.superChat);
      expect([message.userName, message.message], ['SUPER_CHAT_MESSAGE', 'SUPER_CHAT_MESSAGE']);
      expect(message.userId, '46699999');
      expect(message.messageId, '6abd2844d7d16a8779a983a0');
      expect(message.sentAt, created);
      expect(message.color, LiveMessageColor.white);
      final paid = message.data! as LiveSuperChatMessage;
      expect(paid.messageId, '6abd2844d7d16a8779a983a0');
      expect(paid.userName, '观众4');
      expect(paid.face, 'https://static.maoercdn.com/avatars/321799/98/80o6r29211p0pl526q73819n68n08zz5623920.pbt');
      expect(paid.message, '那我要听【告白气球】');
      expect(paid.price, 50);
      expect(paid.priceText, '50 钻');
      expect(paid.startTime, created);
      expect(paid.endTime, created.add(const Duration(seconds: 60)));
      expect(MissevanDanmakuProtocol.questionDuration, const Duration(seconds: 60));
      expect([paid.backgroundColor, paid.backgroundBottomColor], ['', '']);
    });

    test('questions: the asker from either place, time and price fallbacks, bad data', () {
      Map<String, Object?> question([Map<String, Object?> fields = const {}]) => {
        'question_id': 'q-1',
        'user_id': 7300001,
        'username': '观众甲',
        'iconurl': '//static.maoercdn.com/avatars/a.png',
        'question': ' 唱首歌吧 ',
        'price': 30,
        ...fields,
      };
      LiveMessage? read(Object? question, [Map<String, Object?> user = const {}]) => MissevanDanmakuProtocol.decode(
        _item('question', 'ask', {'question': question, 'user': user}),
        roomId: _roomId,
        uuid: 'u',
        receivedAt: _recordedAt,
      ).messages.singleOrNull;
      // No created_time: it starts when it arrived. The asker comes from the
      // question when `user` lacks it; a protocol-relative avatar gets https.
      final paid = read(question())!.data! as LiveSuperChatMessage;
      expect([paid.userName, paid.message, paid.price, paid.priceText], ['观众甲', '唱首歌吧', 30, '30 钻']);
      expect(paid.face, 'https://static.maoercdn.com/avatars/a.png');
      expect(paid.startTime, _recordedAt);
      expect(paid.endTime, _recordedAt.add(MissevanDanmakuProtocol.questionDuration));
      expect(read(question())!.sentAt, isNull, reason: 'the platform gave no time');
      // `user` wins over the question's copy; a price as text counts.
      final fromUser = read(question({'price': '52', 'created_time': 1790781508650}), {
        'user_id': 7300002,
        'username': '观众乙',
        'iconurl': 'https://static.maoercdn.com/avatars/b.png',
      })!;
      expect(fromUser.userId, '7300002');
      expect((fromUser.data! as LiveSuperChatMessage).userName, '观众乙');
      expect((fromUser.data! as LiveSuperChatMessage).face, 'https://static.maoercdn.com/avatars/b.png');
      expect((fromUser.data! as LiveSuperChatMessage).price, 52);
      expect(fromUser.sentAt, DateTime.fromMillisecondsSinceEpoch(1790781508650));
      // A free question still shows; an avatar that is not https does not.
      final free = read(question({'price': 0, 'iconurl': 'http://static.maoercdn.com/a.png'}))!;
      expect((free.data! as LiveSuperChatMessage).price, 0);
      expect((free.data! as LiveSuperChatMessage).face, '');
      // Times out of range fall back to the arrival.
      for (final time in [0, -1, 8640000000000001, '1790781508650', 1.5]) {
        expect((read(question({'created_time': time}))!.data! as LiveSuperChatMessage).startTime, _recordedAt);
      }
      for (final (reason, value) in <(String, Object?)>[
        ('blank text', question({'question': '  '})),
        (
          'text of another type',
          question({
            'question': ['x'],
          }),
        ),
        ('no price', question({'price': null})),
        ('negative price', question({'price': -1})),
        ('price not whole', question({'price': 1.5})),
        ('not an object', 'question'),
        ('missing', null),
      ]) {
        expect(read(value), isNull, reason: reason);
      }
      // The site's other question events show nothing.
      for (final event in ['answer', 'like', 'cancel']) {
        expect(_read(_item('question', event, {'question': question()})), isEmpty, reason: event);
      }
    });

    test('admin clears (synthetic, not seen live): the ids the chat carries, or all of it', () {
      // The chat carries the platform's id the clear names (S09-events frame 1).
      final chat = MissevanDanmakuProtocol.decode(_events()[1].data, roomId: '258058950', uuid: 'u').messages.single;
      expect(chat.messageId, '2e2dcc2b-7ae3-4aed-a7da-ef7183f07003');
      final clear = MissevanDanmakuProtocol.decode(
        _frame({
          'type': 'admin',
          'event': 'message_clear',
          'room_id': 258058950,
          'opt': 2,
          'msg_ids': [chat.messageId, 'm-2', chat.messageId, '', ' ', 12345, null, true],
        }),
        roomId: '258058950',
        uuid: 'u',
      ).messages;
      expect(clear.map((message) => message.data), [
        LiveRetraction.message(chat.messageId),
        const LiveRetraction.message('m-2'),
        const LiveRetraction.message('12345'),
      ]);
      for (final retraction in clear) {
        expect(retraction.type, LiveMessageType.retraction);
        expect([retraction.messageId, retraction.message, retraction.userName, retraction.userId], ['', '', '', '']);
        expect(retraction.sentAt, isNull);
      }
      expect(_read(_item('admin', 'message_clear', {'opt': 1})), ['retraction LiveRetraction.all()']);
      expect(
        _read(
          _item('admin', 'message_clear', {
            'opt': '2',
            'msg_ids': ['a'],
          }),
        ),
        ['retraction LiveRetraction.message(a)'],
      );
      for (final (reason, fields) in <(String, Map<String, Object?>)>[
        (
          'no opt',
          {
            'msg_ids': ['a'],
          },
        ),
        (
          'another opt',
          {
            'opt': 3,
            'msg_ids': ['a'],
          },
        ),
        ('ids not a list', {'opt': 2, 'msg_ids': 'a'}),
        ('no ids', {'opt': 2}),
        ('empty ids', {'opt': 2, 'msg_ids': <Object?>[]}),
      ]) {
        expect(_read(_item('admin', 'message_clear', fields)), isEmpty, reason: reason);
      }
      expect(_read(_item('admin', 'other', {'opt': 1})), isEmpty);
      expect(
        _read(_frame({'type': 'admin', 'event': 'message_clear', 'room_id': 1, 'opt': 1})),
        isEmpty,
        reason: 'another room',
      );
    });

    test('noble titles: the recorded renewal, and registration and team-live ones (synthetic)', () {
      final renewal = MissevanDanmakuProtocol.decode(_events()[25].data, roomId: '869048238', uuid: 'u');
      final notice = renewal.messages.single;
      expect(notice.type, LiveMessageType.notice);
      expect(notice.data, LiveNoticeKind.system);
      expect(notice.message, '观众9 续费了大咖贵族');
      expect([notice.userName, notice.userId, notice.messageId], ['观众9', '34192889', '']);
      expect(notice.sentAt, DateTime.fromMillisecondsSinceEpoch(1790782768531));
      expect(notice.color, LiveMessageColor.white);
      List<String> noble(String event, [Map<String, Object?> fields = const {}]) => _read(
        _item('noble', event, {
          'user': {'user_id': 7300001, 'username': '观众甲'},
          'noble': {'name': '神话', 'level': 7},
          'room': {'room_id': 100000001, 'creator_username': '主播乙'},
          ...fields,
        }),
      );
      expect(noble('registration'), ['notice system 观众甲 开通了神话贵族']);
      expect(noble('renewal'), ['notice system 观众甲 续费了神话贵族']);
      expect(noble('cross_registration'), ['notice system 观众甲 开通了主播乙的神话贵族']);
      expect(noble('cross_renewal'), ['notice system 观众甲 续费了主播乙的神话贵族']);
      expect(noble('cross_renewal', {'room': null}), ['notice system 观众甲 续费了神话贵族']);
      expect(noble('registration', {'user': null}), ['notice system 开通了神话贵族']);
      expect(noble('registration', {'user': 'x'}), ['notice system 开通了神话贵族']);
      for (final (reason, lines) in [
        ('another event', noble('update')),
        (
          'no name',
          noble('registration', {
            'noble': {'level': 7},
          }),
        ),
        (
          'blank name',
          noble('registration', {
            'noble': {'name': ' '},
          }),
        ),
        ('noble not an object', noble('registration', {'noble': '神话'})),
      ]) {
        expect(lines, isEmpty, reason: reason);
      }
    });

    test('random PKs: the site lines a viewer sees (synthetic results and invitations)', () {
      List<String> pk(String event, [Map<String, Object?> pk = const {}, Map<String, Object?> fields = const {}]) =>
          _read(_item('pk', event, {'pk': pk, ...fields}));
      expect(pk('finish', {'result': 0}), ['notice system 主播 PK 失败，再接再厉哦']);
      expect(pk('finish', {'result': 2}), ['notice system 主播 PK 平局，再接再厉哦']);
      expect(pk('close', {'result': '1'}), ['notice system 恭喜主播获得 PK 胜利，继续支持主播吧']);
      expect(pk('finish', {'result': 3}), isEmpty);
      expect(pk('finish'), isEmpty);
      expect(pk('invite_refuse'), ['notice system 对方未接受邀请']);
      expect(pk('invite_timeout', {'from_room_id': int.parse(_roomId)}), ['notice system 对方未接受邀请']);
      expect(pk('invite_timeout', {'from_room_id': 100000001}), isEmpty, reason: 'invited by another room');
      expect(pk('invite_timeout'), isEmpty);
      for (final event in ['match_fail', 'match_stop', 'update', 'mute', 'rank_invite_request', 'other']) {
        expect(pk(event), isEmpty, reason: event);
      }
      expect(_read(_item('pk', 'match_start')), ['notice system 主播正在匹配 PK 对手，请耐心等候'], reason: 'no pk');
      expect(_read(_item('pk', 'finish', {'pk': 'x', 'raid': 'x'})), isEmpty);
      // The 花神赐福 line comes first, only for the site's events.
      final raid = {
        'progress': {'message_tip': _tip('祈福达成')},
      };
      expect(pk('finish', {'result': 1}, {'raid': raid}), ['notice system 祈福达成', 'notice system 恭喜主播获得 PK 胜利，继续支持主播吧']);
      expect(pk('match_start', const {}, {'raid': raid}), ['notice system 主播正在匹配 PK 对手，请耐心等候']);
      expect(pk('update', const {}, {'raid': raid}), ['notice system 祈福达成']);
      expect(
        pk('update', const {}, {
          'raid': {'progress': <String, Object?>{}},
        }),
        isEmpty,
      );
    });

    test('幻影 PKs: the tip, else the site line for the event (synthetic)', () {
      List<String> global(String event, [Map<String, Object?> pk = const {}, Map<String, Object?> fields = const {}]) =>
          _read(_item('global_pk', event, {'pk': pk, ...fields}));
      expect(global('match_start'), ['notice system 幻影 PK 匹配中，敬请期待……']);
      expect(global('match_ready'), ['notice system 幻影 PK 即将开启，准备迎战！']);
      expect(global('match_skip'), ['notice system 本场幻影 PK 已跳过']);
      expect(global('match_fail'), ['notice system 本场幻影 PK 未匹配到合适的对手']);
      expect(global('match_success'), ['notice system 匹配成功！幻影 PK 正式开战！']);
      expect(global('finish', {'result': 1}), ['notice system 恭喜胜利！']);
      expect(global('finish', {'result': 0}), ['notice system 本场幻影 PK 遗憾落败']);
      expect(global('finish', {'result': 2}), ['notice system 本场幻影 PK 战成平局']);
      expect(global('finish'), ['notice system 幻影 PK 已结束']);
      expect(global('update', {'message_tip': _tip('对战更新')}), ['notice system 对战更新']);
      expect(global('match_start', {'message_tip': _tip('雷达启动')}), ['notice system 雷达启动']);
      expect(global('match_start', {'message_tip': '<img src="x" />'}), ['notice system 幻影 PK 匹配中，敬请期待……']);
      // The site writes a bare "PK 小助手提示" for these: nothing to show.
      for (final event in ['update', 'close', 'punish_finish', 'mute', 'match_stop']) {
        expect(global(event), isEmpty, reason: event);
      }
      expect(global('other', {'message_tip': _tip('x')}), isEmpty, reason: 'an event the site does not read');
      expect(_read(_item('global_pk', 'match_start')), isEmpty, reason: 'no pk');
      expect(
        global(
          'close',
          {'message_tip': _tip('结束')},
          {
            'raid': {
              'progress': {'message_tip': _tip('花神')},
            },
          },
        ),
        ['notice system 结束', 'notice system 花神'],
      );
    });

    test('team PKs (synthetic, not seen live): the tip only', () {
      expect(
        _read(
          _item('team_pk', 'update', {
            'pk': {'message_tip': _tip('团播 PK')},
          }),
        ),
        ['notice system 团播 PK'],
      );
      expect(_read(_item('team_pk', 'update', {'pk': <String, Object?>{}})), isEmpty);
      expect(_read(_item('team_pk', 'update')), isEmpty);
    });

    test("a tip's words: links, images and tags left out, entities decoded, white space folded", () {
      expect(MissevanDanmakuProtocol.plainText(_tip(' 你好 ')), '你好');
      expect(
        MissevanDanmakuProtocol.plainText(
          [
            '<font color="#FFD643"> A </font><FONT COLOR=#bdbdbd>详情</FONT>',
            "<font color='#ffffff'>&amp;&lt;b&gt;&quot;&apos;&#39;&#20320;&#x597D;&nbsp;x&copy;&#0;&#xD800;</font>",
            '<br>下一行<br/>又一行\n\t末尾',
          ].join(),
        ),
        'A &<b>"\'\'你好 x&copy;&#0;&#xD800; 下一行 又一行 末尾',
      );
      expect(MissevanDanmakuProtocol.plainText('<font>甲</font><font>乙</font>'), '甲乙', reason: 'no space added');
      expect(MissevanDanmakuProtocol.plainText(null), '');
      expect(MissevanDanmakuProtocol.plainText(12), '');
    });

    test('gifts: the recorded ones (a combo, a lucky gift) and bad data', () {
      final frames = _events();
      LiveMessage read(int index) =>
          MissevanDanmakuProtocol.decode(frames[index].data, roomId: frames[index].room, uuid: 'u').messages.single;
      final first = read(16);
      expect(first.type, LiveMessageType.gift);
      expect([first.userName, first.userId, first.message], ['观众25', '2891648', '幻彩礼炮 ×1']);
      expect(first.messageId, '6abd2807a625be764d218212');
      expect(first.sentAt, DateTime.fromMillisecondsSinceEpoch(1790781447947));
      expect(
        first.data,
        MissevanGift(
          id: '30087',
          name: '幻彩礼炮',
          count: 1,
          price: 0,
          icon: Uri.parse('https://static.maoercdn.com/live/gifts/icons/30087.png'),
          comboKey: '6abd2807a625be764d218212',
          comboTotal: 1,
        ),
      );
      expect(read(17).messageId, '', reason: 'a later send of the combo');
      // D07.6: the combo's id and its count so far.
      final second = read(17).gift!;
      expect((second.comboKey, second.comboTotal, second.count), ('6abd2807a625be764d218212', 2, 1));
      expect(read(17).data, isNot(first.data));
      expect((read(4).gift!.comboKey, read(4).gift!.comboTotal), ('', null), reason: 'no combo object');
      final lucky = read(18).data! as MissevanGift;
      expect(
        lucky,
        MissevanGift(
          id: '92398',
          name: '书写星辰',
          count: 1,
          price: 28,
          icon: Uri.parse('https://static.maoercdn.com/live/gifts/icons/91611.png'),
          luckyGift: MissevanGift(
            id: '80171',
            name: '悠闲假日',
            count: 1,
            price: 52,
            icon: Uri.parse('https://static.maoercdn.com/live/gifts/icons/80171.png'),
          ),
        ),
      );
      expect('$lucky', 'MissevanGift(书写星辰 ×1)');
      // E05.5: the shared gift: diamonds each and together, the icon, free at
      // price 0.
      expect(
        (lucky.unitPrice, lucky.totalValue, lucky.unit, lucky.free, lucky.iconUrl, lucky.tier),
        (28, 28, LiveGiftUnit.diamond, false, lucky.icon, LiveGiftTier.normal),
      );
      expect((first.gift?.free, first.gift?.totalValue), (true, 0));
      expect(lucky.hashCode, isNot(first.data.hashCode));
      final odd = MissevanDanmakuProtocol.gift({
        'gift': {'name': ' 花 ', 'num': 0, 'price': -3, 'icon_url': 'http://static.maoercdn.com/g.png'},
        'user': 'x',
        'oid': 7,
        'lucky': {'num': 1},
      })!;
      expect(odd.data, const MissevanGift(id: '', name: '花', count: 1, price: 0));
      // A combo without an id, an id of zeros or a count that is not a
      // positive number: no key, no count.
      for (final combo in [
        'x',
        {'num': 3},
        {'id': '000000000000000000000000', 'num': 0},
        {'id': 7, 'num': '-2'},
      ]) {
        final gift = MissevanDanmakuProtocol.gift({
          'gift': {'name': '花'},
          'combo': combo,
        })!.gift!;
        expect(
          (gift.comboKey, gift.comboTotal),
          (combo is Map && combo['id'] == 7 ? '7' : '', combo is Map && combo['num'] == 3 ? 3 : null),
          reason: '$combo',
        );
      }

      expect([odd.userName, odd.userId, odd.messageId, odd.message], ['', '', '7', '花 ×1']);
      final three = MissevanDanmakuProtocol.gift({
        'gift': {'name': '花', 'num': '3', 'price': '1000'},
      })!.gift!;
      expect((three.unitPrice, three.totalValue, three.tier), (1000, 3000, LiveGiftTier.precious), reason: '300 yuan');
      expect(odd.sentAt, isNull);
      expect(
        (MissevanDanmakuProtocol.gift({
                  'gift': {'name': '花', 'num': '3', 'price': '10', 'icon_url': '//static.maoercdn.com/g.png'},
                })!.data!
                as MissevanGift)
            .icon,
        Uri.parse('https://static.maoercdn.com/g.png'),
      );
      for (final gift in [
        null,
        'x',
        <String, Object?>{},
        {'name': ' '},
      ]) {
        expect(MissevanDanmakuProtocol.gift({'gift': gift}), isNull, reason: '$gift');
      }
    });

    test(
      'the connection reports them in order, with the question dated by the clock only when it has no time',
      () async {
        final connector = _Connector();
        final connection = _connection(_SessionHttp([_guest(_sessionA)]), connector, now: () => _recordedAt);
        final events = _record(connection);
        await connection.connect(
          MissevanDanmakuArgs(roomId: '258058950', url: Uri.parse('wss://im.missevan.com/ws?room_id=258058950')),
        );
        final channel = connector.channels.single;
        for (final frame in _events().where((frame) => frame.room == '258058950')) {
          channel.incoming.add(frame.data);
        }
        channel.incoming
          ..add(
            _frame({
              'type': 'question',
              'event': 'ask',
              'room_id': 258058950,
              'question': {'question_id': 'q-2', 'question': '没有时间', 'price': 30},
            }),
          )
          ..add(
            _frame({
              'type': 'admin',
              'event': 'message_clear',
              'room_id': 258058950,
              'opt': 2,
              'msg_ids': ['21a91e30-3b4d-4937-82e9-70af5aabc6ae'],
            }),
          );
        await _until(() => _messages(events).length == 7);
        await _wait(const Duration(milliseconds: 10));
        expect(_messages(events).map(_short), [
          for (final index in [0, 1, 2, 3, 4, 5]) ..._s09[index]!,
          'superChat : 没有时间 (30 钻) #q-2',
          'retraction LiveRetraction.message(21a91e30-3b4d-4937-82e9-70af5aabc6ae)',
        ]);
        final undated = _messages(events)[5].data! as LiveSuperChatMessage;
        expect(undated.startTime, _recordedAt);
        await connection.close();
      },
    );
  });

  group('a refused handshake asks a new session (B-1)', () {
    WebSocketException refused(int status) =>
        WebSocketException("Connection to 'https://im.missevan.com:0/ws?room_id=$_roomId#' was not upgraded", status);

    test('a 403 asks a new session at once; the reconnect after the backoff carries it', () async {
      final held = <_HeldTimer>[];
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connector = _Connector(failures: [refused(403)]);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        await _until(() => http.requests.length == 2);
        expect(connector.endpoints, hasLength(1), reason: 'the backoff still waits');
        await _fire(held, const Duration(seconds: 2));
        await _until(() => connector.channels.isNotEmpty);
        connector.channels.single.answer();
        await _until(() => connection.isConnected);
      });
      expect(http.requests.map((request) => request.url), List.filled(2, MissevanApi.guestSession));
      expect(http.requests.last.followRedirects, isFalse);
      expect(connector.headers.map((headers) => headers['cookie']), ['FM_SESS=$_sessionA', 'FM_SESS=$_sessionB']);
      expect(connector.headers.last, {...MissevanApi.headers, 'cookie': 'FM_SESS=$_sessionB'});
      expect(connector.endpoints, List.filled(2, _args.url));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      expect(connector.channels.single.joins.single.containsKey('reconnect'), isFalse, reason: 'never joined before');
      await connection.close();
    });

    test('401 too; once per streak of failures, again after a socket opened', () async {
      final held = <_HeldTimer>[];
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB), _guest(_sessionC)]);
      final connector = _Connector(failures: [refused(401), refused(403)]);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        await _until(() => http.requests.length == 2);
        // One endpoint: 1 s × (failures + 1).
        await _fire(held, const Duration(seconds: 2));
        await _until(() => connector.endpoints.length == 2);
        await _fire(held, const Duration(seconds: 3));
        await _until(() => connector.channels.length == 1);
        expect(http.requests, hasLength(2), reason: 'the second refusal of the streak asks nothing');
        connector.channels.single.answer();
        await _until(() => connection.isConnected);
        // The server drops the socket, then refuses the session: a new streak.
        connector.failures.add(refused(403));
        await connector.channels.single.incoming.close();
        await _fire(held, const Duration(seconds: 2));
        await _until(() => http.requests.length == 3);
        await _fire(held, const Duration(seconds: 3));
        await _until(() => connector.channels.length == 2);
        connector.channels.last.answer();
        await _until(() => events.whereType<DanmakuReady>().length == 2);
      });
      expect(connector.headers.map((headers) => headers['cookie']), [
        'FM_SESS=$_sessionA',
        'FM_SESS=$_sessionB',
        'FM_SESS=$_sessionB',
        'FM_SESS=$_sessionB',
        'FM_SESS=$_sessionC',
      ]);
      expect(connector.channels.last.joins.single['reconnect'], 1);
      expect(events, [
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('other failures ask nothing: no answer, 400, 404, 500, a failed upgrade', () async {
      final delays = <Duration>[];
      final http = _SessionHttp([_guest(_sessionA)]);
      final connector = _Connector(
        failures: [
          const SocketException('refused'),
          refused(400),
          refused(404),
          refused(500),
          const WebSocketException('WebSocket was not upgraded: HTTP/1.1 403 Forbidden'),
        ],
      );
      final connection = _connection(http, connector);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => connector.channels.isNotEmpty);
      });
      expect(http.requests, hasLength(1));
      expect(connector.headers.map((headers) => headers['cookie']), everyElement('FM_SESS=$_sessionA'));
      await connection.close();
    });

    test('no new session: the run ends with credentialsUnavailable and opens nothing more', () async {
      final delays = <Duration>[];
      final http = _SessionHttp([_guest(_sessionA), const TransportFailure(SiteIds.missevan, TransportReason.connect)]);
      final connector = _Connector(failures: [refused(403)]);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      await _wait(const Duration(milliseconds: 20));
      expect(http.requests, hasLength(4), reason: 'the first session, then three attempts');
      expect(delays, containsAllInOrder([const Duration(milliseconds: 500), const Duration(seconds: 1)]));
      expect(connector.endpoints, hasLength(1));
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable)
            .having((event) => event.detail, 'detail', isNotEmpty),
      );
      expect(connection.status, DanmakuStatus.closed);
    });

    test('close while the session is asked: the request is cancelled, nothing opens or is reported', () async {
      final held = <_HeldTimer>[];
      final hold = Completer<void>();
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connector = _Connector(failures: [refused(403)]);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        http.hold = hold;
        await _until(() => http.requests.length == 2);
        await connection.close();
        hold.complete();
        await _wait(const Duration(milliseconds: 20));
      });
      expect(http.requests.last.cancel!.isCancelled, isTrue);
      expect(connector.endpoints, hasLength(1));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test("a local server that refuses the stale session: dart:io's 403, then the new cookie joins", () async {
      final cookies = <String?>[];
      final sockets = <WebSocket>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        final cookie = request.headers.value('cookie');
        cookies.add(cookie);
        if (cookie != 'FM_SESS=$_sessionB') {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          if (frame == MissevanDanmakuProtocol.heartbeat) return;
          final join = jsonDecode(frame as String) as Map<String, Object?>;
          socket
            ..add(_frame(_answer(join['uuid']! as String)))
            ..add(_frame(_chatLine('新会话')));
        });
      });
      final http = _SessionHttp([_guest(_sessionA), _guest(_sessionB)]);
      final connection = MissevanDanmakuConnection(
        http: http,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) =>
            connectIoSocket(
              endpoint.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
              headers: headers,
              protocols: protocols,
              route: route,
              connectTimeout: connectTimeout,
            ),
      );
      final events = _record(connection);
      final backoff = <Duration>[];
      // The reconnect waits 2 s: run it at once (the handshake's own
      // timeout stays real).
      await runZoned(
        () async {
          await connection.connect(_args);
          await _until(() => _messages(events).isNotEmpty);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration != const Duration(seconds: 2)) return parent.createTimer(zone, duration, callback);
            backoff.add(duration);
            return parent.createTimer(zone, Duration.zero, callback);
          },
        ),
      );
      expect(backoff, isNotEmpty);
      expect(cookies, ['FM_SESS=$_sessionA', 'FM_SESS=$_sessionB']);
      expect(http.requests, hasLength(2));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).single.message, '新会话');
      await connection.close();
    });
  });
}
