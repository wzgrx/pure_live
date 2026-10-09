// KilaKila danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.14-克拉克拉弹幕/record.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S07-live, S08-live-full) and the synthetic frames (S09-synthetic), written
// by fixtures/kilakila/danmaku/v4_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kilakila/danmaku';

const String _namespace = KilakilaDanmakuProtocol.namespace;

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, int t, String text});

/// The frames of a recorded session, in order.
List<_Frame> _frames(String name) => [
  for (final (index, line) in File('$_root/$name/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 't': final int t, 'text': final String text})
      (index: index, dir: dir, t: t, text: text),
];

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// The archived v4's output for a session.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

String _roomOf(String name) => (_meta(name)['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;

/// v4's result per incoming frame of a recorded session, by frame index.
Map<int, Map<String, Object?>> _v4Frames(String name) => {
  for (final frame in (_v4(name)['frames']! as List<Object?>).cast<Map<String, Object?>>())
    frame['frame']! as int: frame,
};

final Map<String, Object?> _cases = _json('S09-synthetic/cases.json')! as Map<String, Object?>;

final String _syntheticRoom = _cases['roomId']! as String;

/// v4's result for every synthetic case: one per frame.
final Map<String, Object?> _v4Cases = _v4('S09-synthetic')['cases']! as Map<String, Object?>;

/// A frame of cases.json as the server sends it.
Object _serverFrame(Object? frame) => switch (frame) {
  final String text => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `kilakila:` (difference 1); the projection adds
/// the prefix back. v4 had no audience; the new one is written as
/// `{"kind": "online", "value": …}`.
Map<String, Object?> _eventAsV4(LiveMessage message) {
  if (message.type == LiveMessageType.online) {
    final data = message.data! as LiveAudienceUpdate;
    expect(data.kind, LiveAudienceMetricKind.onlineViewers);
    return {'kind': 'online', 'value': data.value};
  }
  if (message.type == LiveMessageType.gift) {
    // B-10: gifts are reported again (v4 reported every 220), in v4's shape.
    final gift = message.data! as KilakilaGift;
    return {
      'kind': 'gift',
      'id': message.messageId.isEmpty ? null : 'kilakila:${message.messageId}',
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
  expect(message.color, LiveMessageColor.white);
  expect([message.fansLevel, message.fansName], ['', '']);
  return {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : 'kilakila:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'userLevel': message.userLevel.isEmpty ? null : int.parse(message.userLevel),
  };
}

/// A decoded frame in v4's projection; `dropped` (v4 had no such result) is
/// false for v4.
Map<String, Object?> _asV4(KilakilaDanmakuFrame frame) => {
  'joined': frame.joined,
  'rejected': frame.refusal != null,
  'dropped': frame.dropped,
  'events': [for (final message in frame.messages) _eventAsV4(message)],
};

Map<String, Object?> _v4Result(Object? v4) => switch (v4) {
  final Map<String, Object?> thrown when thrown.containsKey('throws') => thrown,
  final Map<String, Object?> result => {
    'joined': result['joined'],
    'rejected': result['rejected'],
    'dropped': false,
    'events': result['events'],
  },
  _ => throw FormatException('v4 $v4'),
};

Map<String, Object?> _decoded(Object frame, {String? roomId}) =>
    _asV4(KilakilaDanmakuProtocol.decode(frame, roomId: roomId ?? _syntheticRoom));

/// A synthetic chat line as the v4 projection shows it.
Map<String, Object?> _chat(String text, String mid, {int? sentAt = 1790629525534}) => {
  'kind': 'chat',
  'id': 'kilakila:$mid',
  'sentAt': sentAt,
  'userId': '7300000000001',
  'userName': 'Viewer One',
  'text': text,
  'userLevel': 38,
};

const Map<String, Object?> _nothing = {'joined': false, 'rejected': false, 'dropped': false, 'events': <Object?>[]};
const Map<String, Object?> _refused = {'joined': false, 'rejected': true, 'dropped': false, 'events': <Object?>[]};
const Map<String, Object?> _dropped = {'joined': false, 'rejected': false, 'dropped': true, 'events': <Object?>[]};

Map<String, Object?> _online(int value) => {
  ..._nothing,
  'events': [
    {'kind': 'online', 'value': value},
  ],
};

List<Object?> _events(Object? v4) => (v4! as Map<String, Object?>)['events']! as List<Object?>;

/// The differences of the new decoder from v4 in the synthetic cases
/// (docs/D-弹幕/D01-平台弹幕协议/D01.14-克拉克拉弹幕/record.md, "与归档 v4 的差异"): v4's results (with
/// `dropped: false`) → the new ones, per case. Cases not listed decode as v4
/// did.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // Difference 6: a Socket.IO error packet on the namespace is a refusal.
  'a Socket.IO error packet on the namespace is a refusal': (v4) {
    expect(v4, List.filled(4, _nothing));
    return [_refused, _refused, _refused, _nothing];
  },
  // Difference 7: the server leaving the namespace or closing the transport.
  'the server leaves the namespace or closes the transport': (v4) {
    expect(v4, List.filled(4, _nothing));
    return [_dropped, _dropped, _nothing, _nothing];
  },
  // Difference 4: chat text must be text (v4 printed numbers and booleans).
  'chat text: trimmed and kept with its line breaks; blank, missing or not text is no line': (v4) {
    expect(_events(v4[4]).single, containsPair('text', '123'));
    expect(_events(v4[5]).single, containsPair('text', 'true'));
    return [v4[0], v4[1], v4[2], v4[3], _nothing, _nothing, v4[6]];
  },
  // Difference 5: user ids are numbers or text (v4 printed `{x: 1}`).
  'names and user ids: text or numbers; other types are empty': (v4) {
    expect(_events(v4[1]).single, containsPair('userId', '{x: 1}'));
    return [
      v4[0],
      {
        ..._nothing,
        'events': [
          {...(_events(v4[1]).single! as Map<String, Object?>), 'userId': ''},
        ],
      },
      v4[2],
      v4[3],
      v4[4],
    ];
  },
  // Difference 4: a time out of range loses only the time; v4 lost the
  // frame (RangeError).
  'a time out of range': (v4) {
    expect(v4, [
      {'throws': 'RangeError'},
    ]);
    return [
      {
        ..._nothing,
        'events': [_chat('far future', '1047000000000000025', sentAt: null)],
      },
    ];
  },
  // Difference 2 until M5.F; B-10: a 220 that is not a combo hit is a gift
  // as v4 reported it, and the gift line 10004 (which v4 ignored) is one too.
  'gifts are not shown: 220 and the gift line 10004': (v4) {
    expect(_events(v4[0]).single, containsPair('kind', 'gift'));
    expect(v4[1], _nothing);
    return [
      v4[0],
      {
        ..._nothing,
        'events': [
          {
            'kind': 'gift',
            'id': 'kilakila:1047000000000000035',
            'sentAt': 1790629525534,
            'userId': '7300000000003',
            'userName': 'Viewer Three',
            'giftId': '',
            'giftName': '克拉应援棒',
            'count': 1,
            'icon': null,
          },
        ],
      },
    ];
  },
  // Difference 3: the room state's watchNumber is the audience.
  'the room state 637: watchNumber is the listeners now': (v4) {
    expect(v4, List.filled(2, _nothing));
    return [_online(315), _online(317)];
  },
  'room state boundaries: zero, negative, text, missing, bad escapes, bad UTF-8, plain JSON, an object': (v4) {
    expect(v4, List.filled(10, _nothing));
    return [_online(0), _nothing, _nothing, _nothing, _nothing, _nothing, _online(7), _nothing, _nothing, _nothing];
  },
};

// ---- the connection ----

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
}

/// Hands out fake channels and records every handshake.
final class _Connector {
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
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

/// No heartbeat or watchdog and a short backoff: only what the test does
/// happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  joinTimeout: Duration(seconds: 8),
  reconnectBaseDelay: Duration(milliseconds: 5),
);

const String _room = '2269142054376308832';
const KilakilaDanmakuArgs _args = KilakilaDanmakuArgs(roomId: _room);

const String _joinOk =
    '42$_namespace,["connect_error","{\\"result_type\\":0,\\"code\\":0,\\"message\\":\\"join success\\"}"]';
const String _joinRefused = '42$_namespace,["connect_error","{\\"code\\":3,\\"message\\":\\"room closed\\"}"]';

KilakilaDanmakuConnection _connection(
  _Connector connector, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy? proxy,
}) => KilakilaDanmakuConnection(connector: connector.call, policy: policy, proxy: proxy ?? const FixedProxyPolicy());

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

/// The server's greeting and join answer, as S07 and S08 recorded them.
void _accept(_FakeChannel channel) => channel.incoming
  ..add(
    '0{"sid":"00000000-0000-4000-8000-000000000000","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":60000}',
  )
  ..add('40')
  ..add('41')
  ..add(_joinOk)
  ..add('40$_namespace');

void main() {
  group('protocol', () {
    test("the socket, its headers, the join and the ping are v4's and the recordings'", () {
      for (final name in ['S07-live', 'S08-live-full']) {
        final roomId = _roomOf(name);
        final v4 = _v4(name)['connector']! as Map<String, Object?>;
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        final endpoint = KilakilaDanmakuProtocol.endpoint(roomId).toString();
        expect(endpoint, (v4['endpoints']! as List<Object?>).single);
        expect(endpoint, handshake['url']);
        final join = KilakilaDanmakuProtocol.join(roomId);
        expect(join, (v4['openFrames']! as List<Object?>).single);
        final frames = _frames(name);
        expect(frames.first, (index: 0, dir: 'out', t: frames.first.t, text: join));
        expect(KilakilaDanmakuProtocol.ping, v4['heartbeat']);
        // The origin is v4's and the recordings'; the user agent is the
        // adapter's (difference 9).
        final headers = handshake['headers']! as Map<String, Object?>;
        expect(KilakilaDanmakuProtocol.handshakeHeaders['origin'], headers['origin']);
        expect((v4['headers']! as Map<String, Object?>)['origin'], headers['origin']);
        expect(headers['user-agent'], contains('Chrome/140'));
        expect(KilakilaDanmakuProtocol.handshakeHeaders['user-agent'], KilakilaApi.userAgent);
        expect(KilakilaDanmakuProtocol.handshakeHeaders.keys, ['origin', 'user-agent']);
      }
    });

    test('S08 sent only the join and the ping, every 25 s from the open, each answered by 3', () {
      final frames = _frames('S08-live-full');
      final sent = frames.where((frame) => frame.dir == 'out').toList();
      expect(sent.first.text, KilakilaDanmakuProtocol.join(_room));
      expect(sent.skip(1).map((frame) => frame.text), List.filled(5, '2'));
      final open = frames.firstWhere((frame) => frame.text.startsWith('0{')).t;
      for (final (index, ping) in sent.skip(1).indexed) {
        expect(ping.t - open, closeTo((index + 1) * 25000, 500));
        final answer = frames[ping.index + 1];
        expect((answer.dir, answer.text), ('in', '3'));
      }
      expect(KilakilaDanmakuProtocol.heartbeatInterval.inSeconds, 25);
      final greeting = jsonDecode(frames.firstWhere((frame) => frame.text.startsWith('0{')).text.substring(1));
      expect(greeting, containsPair('pingInterval', 25000));
    });

    test('a chat line fills the message model', () {
      final line = _frames('S08-live-full')[6].text;
      final frame = KilakilaDanmakuProtocol.decode(line, roomId: _room);
      final message = frame.messages.single;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, '心存善良，万物晴朗☀');
      expect(message.userName, '观众1友友友友友友友友友');
      expect(message.userId, '9808547595636');
      expect(message.userLevel, '161');
      expect(message.messageId, '1047028601860070400');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790629525534));
      expect(message.color, LiveMessageColor.white);
      expect([message.fansLevel, message.fansName, message.isLocal, message.data], ['', '', false, null]);
      expect([frame.joined, frame.refusal, frame.dropped], [false, null, false]);
    });

    test('the room state 637 gives the listeners now as onlineViewers', () {
      final frame = KilakilaDanmakuProtocol.decode(_frames('S08-live-full')[8].text, roomId: _room);
      final message = frame.messages.single;
      expect(message.type, LiveMessageType.online);
      expect([message.userName, message.message, message.messageId], ['', '', '']);
      final data = message.data! as LiveAudienceUpdate;
      expect([data.kind, data.value], [LiveAudienceMetricKind.onlineViewers, 315]);
    });

    test('refusal texts: the message, else the code; error packets: their text', () {
      String? refusal(String frame) => KilakilaDanmakuProtocol.decode(frame, roomId: _room).refusal;
      expect(refusal(_joinRefused), 'room closed');
      expect(refusal('42$_namespace,["connect_error","{\\"code\\":2,\\"message\\":\\"\\"}"]'), 'code 2');
      expect(refusal('42$_namespace,["connect_error","{}"]'), 'code null');
      expect(refusal('44$_namespace,"Not authorized"'), 'Not authorized');
      expect(refusal('44$_namespace,{"message":"Invalid namespace"}'), 'Invalid namespace');
      expect(refusal('44$_namespace,{"data":1}'), '{"data":1}');
      expect(refusal('44$_namespace,oops'), 'oops');
      expect(refusal('44$_namespace'), 'error');
      expect(refusal(_joinOk), isNull);
    });
  });

  group('recordings against v4', () {
    test('S07-live: joins where v4 joined; chats and gifts as v4 decoded them, but no combo hit (B-10)', () {
      final v4 = _v4Frames('S07-live');
      final roomId = _roomOf('S07-live');
      final received = _frames('S07-live').where((frame) => frame.dir == 'in').toList();
      expect(received, hasLength(v4.length));
      var chats = 0;
      final gifts = <int>[];
      for (final frame in received) {
        final expected = _v4Result(v4[frame.index]);
        final v4Events = expected['events']! as List<Object?>;
        for (final event in v4Events.cast<Map<String, Object?>>()) {
          if (event['kind'] == 'gift') gifts.add(frame.index);
        }
        chats += v4Events.where((event) => (event! as Map<String, Object?>)['kind'] == 'chat').length;
        // B-10: frame 15 is a combo hit (isDoubleHit true, count 1 so far):
        // v4 reported it, the combo's line (not recorded) would.
        final kept = frame.index == 15 ? const <Object?>[] : v4Events;
        expect(_decoded(frame.text, roomId: roomId), {...expected, 'events': kept}, reason: 'frame ${frame.index}');
      }
      expect(chats, 5);
      expect(gifts, [15, 44, 54]);
      expect(_frames('S07-live')[15].text, contains(r'\\\"isDoubleHit\\\":true'));
    });

    test('S08-live-full: chats as v4 decoded them, and the listeners of every room state', () {
      final v4 = _v4Frames('S08-live-full');
      final received = _frames('S08-live-full').where((frame) => frame.dir == 'in').toList();
      expect(received, hasLength(v4.length));
      final audience = <int>[];
      var chats = 0;
      for (final frame in received) {
        final expected = _v4Result(v4[frame.index]);
        final decoded = _decoded(frame.text, roomId: _room);
        final events = decoded['events']! as List<Object?>;
        final online = [
          for (final event in events.cast<Map<String, Object?>>())
            if (event['kind'] == 'online') event['value']! as int,
        ];
        audience.addAll(online);
        final v4Events = expected['events']! as List<Object?>;
        chats += v4Events.length;
        expect(
          {
            ...decoded,
            'events': [
              for (final event in events.cast<Map<String, Object?>>())
                if (event['kind'] != 'online') event,
            ],
          },
          expected,
          reason: 'frame ${frame.index}',
        );
        if (online.isNotEmpty) expect(frame.text, contains(r'\\\"t\\\":637'));
      }
      expect(chats, 7);
      expect(audience, [
        ...List.filled(5, 315),
        316,
        316,
        312,
        312,
        312,
        312,
        314,
        ...List.filled(7, 315),
        ...List.filled(5, 316),
        ...List.filled(6, 317),
      ]);
    });
  });

  group('synthetic frames against v4 (S09-synthetic)', () {
    final cases = [
      for (final entry in _cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames}) (name: name, frames: frames),
    ];

    test('every case has v4 output, and every difference names a case', () {
      expect(cases, hasLength(24));
      expect(_v4Cases.keys, [for (final entry in cases) entry.name]);
      expect(_differences.keys.toSet().difference(_v4Cases.keys.toSet()), isEmpty);
    });

    for (final (:name, :frames) in cases) {
      test(name, () {
        final v4 = [for (final result in _v4Cases[name]! as List<Object?>) _v4Result(result)];
        expect(v4, hasLength(frames.length));
        final expected = _differences[name]?.call(v4) ?? v4;
        expect([for (final frame in frames) _decoded(_serverFrame(frame))], expected);
      });
    }
  });

  group('B-10: gifts and paid questions', () {
    final s10Room = _roomOf('S10-live-gifts-questions');
    final s11Room = _roomOf('S11-live-question-board');
    final recorded = DateTime.parse(_meta('S10-live-gifts-questions')['capturedAt']! as String);

    List<LiveMessage> read(String frame, {String? roomId, DateTime? now}) =>
        KilakilaDanmakuProtocol.decode(frame, roomId: roomId ?? s10Room, now: now ?? recorded).messages;

    /// A `text_message` of broadcast [room] with [content].
    String message(
      Map<String, Object?> content, {
      String? room,
      Object? created = 1790782866386,
      Object? mid = '1047671760008977409',
    }) {
      final payload = jsonEncode({
        'body': {
          'response': {'room_id': room ?? s10Room, 'mid': ?mid, 'created_at': ?created, 'content': jsonEncode(content)},
        },
      });
      return '42$_namespace,${jsonEncode(['text_message', payload])}';
    }

    Map<String, Object?> giftContent({
      int type = KilakilaDanmakuProtocol.giftType,
      Object? hit = false,
      Object? count = 2,
      Object? price = 200,
      Object? name = '草莓项链',
      Object? receiver = '主播',
      Object? pic = 'https://img.hongrenshuo.com.cn/gift.png',
      bool withItem = true,
    }) => {
      't': type,
      'u': 7300000000003,
      'n': '观众3',
      'l': 46,
      'c': withItem
          ? {
              'name': ?name,
              'doubleCount': ?count,
              'price': ?price,
              'isDoubleHit': ?hit,
              'giftReceiverName': ?receiver,
              'id': 415356,
              'pic': ?pic,
            }
          : 'gift',
    };

    Map<String, Object?> board({
      int type = 240,
      Object? uiType = 2,
      Object? goldPrice = 3000,
      Object? content = '藏于流年的抱憾 辛苦啦',
      Object? head = 'https://img.hongrenshuo.com.cn/7300000000004.png?t=1',
      Object? nickname = '观众4',
      bool withQuestion = true,
    }) => {
      't': type,
      'u': 3152613118014,
      'n': '主播',
      'uc': {
        'uiType': uiType,
        if (withQuestion)
          'question': {
            'questionId': '2269910643068895305',
            'questionUid': '7300000000004',
            'questionHeadUrl': ?head,
            'questionNickname': ?nickname,
            'content': ?content,
            'goldPrice': ?goldPrice,
            'amount': 30,
            'avatarFrame': <Object?>[],
          },
      },
    };

    test('recorded (S10): once per gift sent, the paid question on the board a super chat, the asking not', () {
      final frames = _frames('S10-live-gifts-questions');
      expect(frames, hasLength(10));
      final decoded = [for (final frame in frames) read(frame.text)];
      final kinds = [
        for (final messages in decoded) [for (final message in messages) message.type],
      ];
      expect(kinds, [
        [LiveMessageType.gift], // 220, not a combo: 7 gifts at once
        <LiveMessageType>[], // 220, a combo hit
        [LiveMessageType.gift], // 10004: that combo's line
        [LiveMessageType.gift], // 220, not a combo: a free guard badge
        <LiveMessageType>[], // 241: a question asked (the page ignores it)
        <LiveMessageType>[], // 301, uiType 0: the board cleared
        <LiveMessageType>[], // 220, a combo hit
        [LiveMessageType.gift], // 10004: that combo's line
        [LiveMessageType.superChat], // 240, uiType 2: the paid question
        [LiveMessageType.gift], // 220 without isDoubleHit
      ]);
      List<Object?> gift(LiveMessage message) {
        final gift = message.data! as KilakilaGift;
        return [
          message.userName,
          message.userId,
          message.message,
          gift.id,
          gift.name,
          gift.count,
          gift.price,
          gift.free,
          gift.receiverName,
          gift.icon?.host,
        ];
      }

      const host = '嘟子〰️琅声雅集ᰔᩚ';
      expect(gift(decoded[0].single), [
        '观众1',
        '3794368537419',
        '桃花风车 ×7',
        '411690',
        '桃花风车',
        7,
        700,
        false,
        host,
        'img.hongrenshuo.com.cn',
      ]);
      expect(gift(decoded[2].single), [
        '观众2',
        '2248408448274',
        '克拉之星 ×6',
        '60355',
        '克拉之星',
        6,
        0,
        true,
        host,
        'img.hongrenshuo.com.cn',
      ]);
      expect(gift(decoded[3].single), [
        '观众3',
        '7877897429571',
        '守护灯牌 ×1',
        '404769',
        '守护灯牌',
        1,
        0,
        true,
        '',
        'img.kilamanbo.com',
      ]);
      // The line gives the price of one (68); the hit gave the send's (204).
      expect(gift(decoded[7].single).sublist(2, 7), ['飞天小猪 ×3', '15545', '飞天小猪', 3, 204]);
      expect(frames[6].text, contains(r'\\\"price\\\":204'));
      expect(frames[7].text, contains(r'\\\"price\\\":68'));
      expect(gift(decoded[9].single).sublist(2, 8), ['天空之城 ×1', '72', '天空之城', 1, 10000, false]);
      // E05.5: the shared gift; the price of one only where it is known.
      expect(
        decoded[7].single.gift,
        isA<LiveGift>().having((gift) => (gift.unitPrice, gift.totalValue), 'price', (68, 204)),
      );
      expect(
        decoded[0].single.gift,
        KilakilaGift(
          id: '411690',
          name: '桃花风车',
          count: 7,
          price: 700,
          icon: (decoded[0].single.data! as KilakilaGift).icon,
          receiverName: host,
        ),
      );
      expect((decoded[2].single.gift!.free, decoded[3].single.gift!.receiverName), (true, ''));
      final line = decoded[2].single;
      expect(
        (line.messageId, line.sentAt, line.userLevel, line.color),
        ('1047671317728008192', DateTime.fromMillisecondsSinceEpoch(1790782760938), '47', LiveMessageColor.white),
      );

      final question = decoded[8].single;
      expect(
        (question.userName, question.userId, question.message, question.messageId, question.sentAt),
        (
          '观众4',
          '1210544661531',
          'bgm 从前说 小阿七 谢谢',
          '2269922853660917911',
          DateTime.fromMillisecondsSinceEpoch(1790782866386),
        ),
      );
      final superChat = question.data! as LiveSuperChatMessage;
      expect(superChat.messageId, '2269922853660917911');
      expect(superChat.userName, '观众4');
      expect(
        superChat.face,
        'https://img.hongrenshuo.com.cn/1210544661531.png?t=1786707713000&x-oss-process=image/resize,m_fill,h_96,w_96',
      );
      expect(superChat.message, 'bgm 从前说 小阿七 谢谢');
      expect(superChat.price, 1000);
      expect(superChat.priceText, '1,000红豆');
      // D07.2: the unit of the platform table (superChatUnits).
      expect(superChat.unit, LiveGiftUnit.redBean);
      expect(superChatUnits[SiteIds.kilakila], superChat.unit);
      expect(superChat.startTime, DateTime.fromMillisecondsSinceEpoch(1790782866386));
      expect(superChat.endTime, DateTime.fromMillisecondsSinceEpoch(1790782866386 + 5 * 60 * 1000));
      expect((superChat.backgroundColor, superChat.backgroundBottomColor), ('', ''));
      // The asking (241) was by the same viewer at the same price.
      expect(frames[4].text, allOf(contains('1210544661531'), contains(r'\\\"goldPrice\\\":1000')));
    });

    test('recorded (S11): free questions give nothing; the same paid question shown twice is the same super chat', () {
      final frames = _frames('S11-live-question-board');
      final decoded = [for (final frame in frames) read(frame.text, roomId: s11Room)];
      expect(decoded.map((messages) => messages.length), [0, 0, 1, 0, 0, 1]);
      final [first, again] = [decoded[2].single, decoded[5].single];
      final one = first.data! as LiveSuperChatMessage;
      final two = again.data! as LiveSuperChatMessage;
      expect(one, two, reason: 'one questionId');
      expect(one.hashCode, two.hashCode);
      expect(two.startTime.isAfter(one.startTime), isTrue);
      expect((one.price, one.priceText, one.userName), (100, '100红豆', '观众2'));
      expect(one.message, startsWith('点歌规则：点问答板提问👇\n有灯牌2990🫘/无灯牌4990🫘'));
      expect(one.message, endsWith('🏠灯牌7级戳管理进群'));
      expect((first.messageId, again.messageId), ('2269901091061629225', '2269901091061629225'));
    });

    test('synthetic gifts: the rules and bad data', () {
      LiveMessage? one(Map<String, Object?> content, {String? room}) {
        final messages = read(message(content, room: room));
        return messages.isEmpty ? null : messages.single;
      }

      KilakilaGift? gift(Map<String, Object?> content) => one(content)?.data as KilakilaGift?;

      expect(
        gift(giftContent()),
        KilakilaGift(
          id: '415356',
          name: '草莓项链',
          count: 2,
          price: 200,
          receiverName: '主播',
          icon: Uri.parse('https://img.hongrenshuo.com.cn/gift.png'),
        ),
      );
      expect(gift(giftContent(hit: true)), isNull, reason: 'a combo hit');
      expect(gift(giftContent(hit: 'true')), isNotNull, reason: 'only true is a hit');
      expect(gift(giftContent(hit: null))!.price, 200);
      expect(gift(giftContent(type: KilakilaDanmakuProtocol.giftLineType, hit: true))!.price, 400, reason: '2 × 200');
      expect(gift(giftContent(type: KilakilaDanmakuProtocol.giftLineType, count: '3', price: '68'))!.price, 204);
      for (final count in [0, -1, null, 'x', 1.5]) {
        expect(gift(giftContent(count: count))!.count, 1, reason: '$count');
      }
      for (final price in [-5, null, 'x']) {
        expect(gift(giftContent(price: price))!.price, 0, reason: '$price');
      }
      for (final name in [null, '', '  ', 42]) {
        expect(gift(giftContent(name: name)), isNull, reason: '$name');
      }
      expect(gift(giftContent(name: ' 草莓项链 '))!.name, '草莓项链');
      expect(gift(giftContent(pic: 'http://img.hongrenshuo.com.cn/gift.png'))!.icon, isNull);
      expect(gift(giftContent(pic: 7))!.icon, isNull);
      // E05.5: the shared text (was the page's “我送了豆咖2个草莓项链”).
      expect(one(giftContent(receiver: null))!.message, '草莓项链 ×2');
      expect(one(giftContent(receiver: ' '))!.gift?.receiverName, '');
      expect(one(giftContent())!.gift?.receiverName, '主播');
      expect(gift(giftContent(withItem: false)), isNull);
      expect(one(giftContent(), room: '2260000000000000009'), isNull, reason: 'another broadcast');
      expect(one({...giftContent(), 't': '220'}), isNull, reason: 'the page switches on the number');
      final full = one(giftContent())!;
      expect(
        (full.type, full.userName, full.userId, full.userLevel, full.messageId, full.color),
        (LiveMessageType.gift, '观众3', '7300000000003', '46', '1047671760008977409', LiveMessageColor.white),
      );
      expect(full.sentAt, DateTime.fromMillisecondsSinceEpoch(1790782866386));
      expect(read(message(giftContent(), created: null)).single.sentAt, isNull);
      expect(const KilakilaGift(id: '1', name: 'a', count: 1, price: 0).free, isTrue);
      expect('${gift(giftContent())}', 'KilakilaGift(草莓项链 ×2, 200)');
    });

    test('synthetic questions: every board type, the uiTypes that show a question, prices, text, decoding, time', () {
      LiveSuperChatMessage? superChat(Map<String, Object?> content, {Object? created = 1790782866386}) {
        final messages = read(message(content, created: created));
        return messages.isEmpty ? null : messages.single.data! as LiveSuperChatMessage;
      }

      for (final type in [240, 300, 301, 532, 534, 706]) {
        expect(superChat(board(type: type))?.price, 3000, reason: '$type');
      }
      for (final type in [241, 302, 230, 250]) {
        expect(superChat(board(type: type)), isNull, reason: '$type');
      }
      for (final uiType in [2, 3, 6, 7, 10, 11, 14, 15, '2', 10.0]) {
        expect(superChat(board(uiType: uiType)), isNotNull, reason: '$uiType');
      }
      for (final uiType in [0, 1, 4, 5, 8, 9, 12, 13, 16, null, 'x']) {
        expect(superChat(board(uiType: uiType)), isNull, reason: '$uiType');
      }
      expect(superChat(board(withQuestion: false)), isNull);
      for (final price in [0, -5, null, 'free', 2.5]) {
        expect(superChat(board(goldPrice: price)), isNull, reason: '$price');
      }
      expect(superChat(board(goldPrice: '300'))!.price, 300, reason: 'the page decodes every field to text');
      expect(superChat(board(goldPrice: 1234567))!.priceText, '1,234,567红豆');
      expect(superChat(board(goldPrice: 999))!.priceText, '999红豆');
      for (final text in [null, '', ' \n ', 42]) {
        expect(superChat(board(content: text)), isNull, reason: '$text');
      }
      expect(superChat(board(content: '  你好\n世界  '))!.message, '你好\n世界');
      expect(superChat(board(content: '%E4%BD%A0%E5%A5%BD'))!.message, '你好', reason: 'decodeURIComponent');
      expect(superChat(board(nickname: '%E8%A7%82%E4%BC%97'))!.userName, '观众');
      expect(superChat(board(content: '100%')), isNull, reason: 'a bad escape loses the message, as on the page');
      expect(superChat(board(nickname: '%E0%A4%A')), isNull);
      expect(superChat(board(head: 'http://img.hongrenshuo.com.cn/a.png'))!.face, '');
      expect(superChat(board(head: null))!.face, '');
      expect(superChat(board(nickname: null))!.userName, '');
      final noTime = superChat(board(), created: null)!;
      expect(noTime.startTime, recorded, reason: 'the time of reading');
      expect(noTime.endTime, recorded.add(const Duration(minutes: 5)));
      expect(superChat(board(), created: 'soon')!.startTime, recorded);
      final withTime = read(message(board())).single;
      expect(withTime.userId, '7300000000004');
      expect(withTime.color, LiveMessageColor.white);
      expect(KilakilaDanmakuProtocol.amount(0), '0');
      expect(KilakilaDanmakuProtocol.amount(1000), '1,000');
      expect(KilakilaDanmakuProtocol.amount(-12345), '-12,345');
      expect(KilakilaDanmakuProtocol.questionDisplay, const Duration(minutes: 5));
    });

    test("decodeURIComponent keeps what is not an escape (Dart's decoder threw on any non-ASCII character)", () {
      // A room state whose URL-encoded JSON also holds plain Chinese: before
      // M5.F the ArgumentError escaped decode().
      final state = message({'t': 637, 'c': '%7B%22watchNumber%22%3A5%2C%22title%22%3A%22中文%22%7D'});
      final online = read(state).single.data! as LiveAudienceUpdate;
      expect(online.value, 5);
      expect(read(message({'t': 637, 'c': '%7B%22watchNumber%22%3A5%7D%E4'})), isEmpty, reason: 'a cut UTF-8 escape');
      expect(read(message(board(content: '已有🫘 %E4%BD%A0 50%25'))).single.message, '已有🫘 你 50%');
    });

    test('not reported: the asking (241), entries, leaves, likes and the first light-up', () {
      for (final type in [241, 101, 603, 102, 210, 211]) {
        expect(read(message({'t': type, 'u': 1, 'n': 'x', 'c': 'y'})), isEmpty, reason: '$type');
      }
    });

    test('the connection reports the gifts and the super chat of S10 in order', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(KilakilaDanmakuArgs(roomId: s10Room));
      final channel = connector.channels.single;
      _accept(channel);
      for (final frame in _frames('S10-live-gifts-questions')) {
        channel.incoming.add(frame.text);
      }
      await _until(() => _messages(events).length == 6);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map((message) => message.type), [
        LiveMessageType.gift,
        LiveMessageType.gift,
        LiveMessageType.gift,
        LiveMessageType.gift,
        LiveMessageType.superChat,
        LiveMessageType.gift,
      ]);
      await connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      final v4 = _v4('S07-live')['connector']! as Map<String, Object?>;
      final connection = KilakilaDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 25));
      final policy = connection.policy;
      expect(policy.heartbeatInterval.inSeconds, v4['heartbeatSeconds']);
      expect(policy.joinTimeout!.inSeconds, v4['authTimeoutSeconds']);
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 25 s, 90 s) = 90 s');
      expect(v4['silenceTimeoutSeconds'], 90);
      expect(policy.connectTimeout.inSeconds, v4['connectTimeoutSeconds']);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(KilakilaDanmakuConnection.maxRefusals, v4['maxRejections']);
      expect(connection.site, SiteIds.kilakila);
      final registry = DanmakuRegistry({SiteIds.kilakila: KilakilaDanmakuConnection.new});
      expect(registry.supports('KilaKila '), isTrue);
      expect(registry.connectionFor(SiteIds.kilakila), isA<KilakilaDanmakuConnection>());
    });

    test(
      'handshake: the broadcast socket with its headers and route; the join on open; ready once confirmed',
      () async {
        final connector = _Connector();
        const route = HttpProxyRoute('127.0.0.1', 7897);
        final connection = _connection(connector, proxy: const FixedProxyPolicy(perSite: {SiteIds.kilakila: route}));
        final events = _record(connection);
        await connection.connect(const KilakilaDanmakuArgs(roomId: ' $_room '));
        expect(connector.endpoints, [KilakilaDanmakuProtocol.endpoint(_room)]);
        expect(connector.headers.single, KilakilaDanmakuProtocol.handshakeHeaders);
        expect(connector.routes.single, route);
        final channel = connector.channels.single;
        expect(channel.sent, [KilakilaDanmakuProtocol.join(_room)]);
        expect(events, isEmpty, reason: 'not joined before the server confirms');
        expect(connection.isConnected, isFalse);
        _accept(channel);
        await _until(() => events.isNotEmpty);
        await _wait(const Duration(milliseconds: 10));
        expect(events, [const DanmakuReady()], reason: 'connect_error code 0 and 40 are one join');
        expect(connection.isConnected, isTrue);
        await connection.close();
        expect(channel.closed, isTrue);
      },
    );

    test("the namespace's 40 alone is the join too", () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming.add('40$_namespace');
      await _until(() => events.isNotEmpty);
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('replaying S08-live-full reports its 7 chats and 30 audience updates in order, and nothing else', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      final expected = <Object?>[];
      for (final frame in _frames('S08-live-full')) {
        if (frame.dir != 'in') continue;
        channel.incoming.add(frame.text);
        expected.addAll(_decoded(frame.text, roomId: _room)['events']! as List<Object?>);
      }
      expect(expected, hasLength(37));
      await _until(() => _messages(events).length == expected.length);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map(_eventAsV4), expected);
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(channel.sent, [KilakilaDanmakuProtocol.join(_room)]);
      await connection.close();
    });

    test('the Engine.IO ping goes out at every tick from the open, before the join too, and on demand', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = KilakilaDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 3);
          expect(sent.take(3), [KilakilaDanmakuProtocol.join(_room), '2', '2']);
          connection.heartbeat();
          await _until(() => sent.length >= 4);
          expect(sent.skip(1), everyElement('2'));
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
      expect(periods, [const Duration(seconds: 25)]);
    });

    test('a join not confirmed in time replaces the socket, which joins again', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 100),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.isNotEmpty);
      // A late confirmation on the given-up socket, before the reconnect
      // (200 ms later), joins nothing.
      final first = connector.channels.single;
      first.incoming.add('40$_namespace');
      await _wait(const Duration(milliseconds: 20));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      expect(connection.isConnected, isFalse);
      await _until(() => connector.channels.length == 2);
      expect(first.closed, isTrue);
      final second = connector.channels.last;
      expect(second.sent, [KilakilaDanmakuProtocol.join(_room)]);
      _accept(second);
      await _until(() => events.whereType<DanmakuReady>().isNotEmpty);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('a refused join reconnects with a protocolError notice; a later join clears the count', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      for (var round = 0; round < 3; round++) {
        final channels = connector.channels.length;
        connector.channels.last.incoming
          ..add('0{"sid":"x"}')
          ..add(_joinRefused)
          // A confirmation after the refusal, on the same socket, is ignored.
          ..add('40$_namespace');
        await _until(() => connector.channels.length == channels + 1);
      }
      _accept(connector.channels.last);
      await _until(() => events.whereType<DanmakuReady>().isNotEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(
        events.where(
          (event) => event == const DanmakuReconnecting(DanmakuInterruption.protocolError, detail: 'room closed'),
        ),
        hasLength(3),
      );
      expect(connector.channels.take(3).every((channel) => channel.closed), isTrue);
      expect(connector.channels.every((channel) => channel.sent.first == KilakilaDanmakuProtocol.join(_room)), isTrue);
      // Joined again: three more refusals are tolerated.
      for (var round = 0; round < 3; round++) {
        final channels = connector.channels.length;
        connector.channels.last.incoming.add(_joinRefused);
        await _until(() => connector.channels.length == channels + 1);
      }
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      await connection.close();
    });

    test('the fourth refusal in a row ends with connectionFailed', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      for (var socket = 1; socket <= 4; socket++) {
        await _until(() => connector.channels.length == socket);
        connector.channels.last.incoming.add(_joinRefused);
      }
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(connector.channels, hasLength(4));
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: room closed'),
      );
      expect(
        events.whereType<DanmakuReconnecting>().where((event) => event.reason == DanmakuInterruption.protocolError),
        hasLength(3),
      );
      expect(connection.status, DanmakuStatus.closed);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(4), reason: 'no reconnect after the end');
      expect(connector.channels.last.closed, isTrue);
    });

    test('a server leaving the namespace or closing the transport is reconnected and joined again', () async {
      for (final drop in ['41$_namespace', '1']) {
        final connector = _Connector();
        final connection = _connection(connector);
        final events = _record(connection);
        await connection.connect(_args);
        _accept(connector.channels.single);
        await _until(() => connection.isConnected);
        connector.channels.single.incoming
          ..add(drop)
          // Frames the old socket still delivers are not this room's.
          ..add(_frames('S08-live-full')[6].text);
        await _until(() => connector.channels.length == 2);
        expect(connection.isConnected, isFalse);
        _accept(connector.channels.last);
        await _until(() => events.whereType<DanmakuReady>().length == 2);
        expect(events, [
          const DanmakuReady(),
          const DanmakuReconnecting(DanmakuInterruption.disconnected),
          const DanmakuReady(),
        ], reason: drop);
        await connection.close();
      }
    });

    test('arguments without a broadcast end at once, without a handshake', () async {
      for (final roomId in ['', '  ', 'abc', '0123', '-1', '12a']) {
        final connector = _Connector();
        final connection = _connection(connector);
        final events = _record(connection);
        await connection.connect(KilakilaDanmakuArgs(roomId: roomId));
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast'),
        ], reason: roomId);
        expect(connector.endpoints, isEmpty);
      }
      await expectLater(
        KilakilaDanmakuConnection().connect(const PicartoDanmakuArgs(channelName: 'a', channelId: 1)),
        throwsArgumentError,
      );
    });

    test('after close nothing is reported; another connect replaces the broadcast', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      _accept(first);
      await _until(() => connection.isConnected);
      await connection.connect(const KilakilaDanmakuArgs(roomId: '2268805595228274844'));
      expect(first.closed, isTrue);
      expect(connector.endpoints.last, KilakilaDanmakuProtocol.endpoint('2268805595228274844'));
      expect(connector.channels.last.sent, [KilakilaDanmakuProtocol.join('2268805595228274844')]);
      // The old room's frames go nowhere.
      first.incoming.add(_frames('S08-live-full')[6].text);
      _accept(connector.channels.last);
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      await connection.close();
      final count = events.length;
      connector.channels.last.incoming
        ..add(_frames('S08-live-full')[6].text)
        ..add(_frames('S08-live-full')[8].text);
      await _wait(const Duration(milliseconds: 20));
      expect(events, hasLength(count));
      expect(_messages(events), isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a real local server: the path and query, the headers, the text frames, ping and pong', () async {
      final handshake = <String, String?>{};
      final received = <Object?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        handshake['path'] = '${request.uri.path}?${request.uri.query}';
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((data) {
          received.add(data);
          if (data == '2') socket.add('3');
          if (data is String && data.startsWith('40$_namespace')) {
            socket
              ..add(_joinOk)
              ..add('40$_namespace');
            for (final index in [6, 8]) {
              socket.add(_frames('S08-live-full')[index].text);
            }
          }
        });
        socket
          ..add(
            '0{"sid":"00000000-0000-4000-8000-000000000000","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":60000}',
          )
          ..add('40')
          ..add('41');
      });
      final connection = KilakilaDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.host, KilakilaDanmakuProtocol.host);
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
      await connection.connect(_args);
      await _until(() => _messages(events).length == 2);
      connection.heartbeat();
      await _until(() => received.length == 2);
      final endpoint = KilakilaDanmakuProtocol.endpoint(_room);
      expect(handshake['path'], '${endpoint.path}?${endpoint.query}');
      expect(handshake['origin'], KilakilaApi.origin);
      // dart:io's handshake keeps its own user agent in front of the one given.
      expect(handshake['user-agent'], endsWith(KilakilaApi.userAgent));
      expect(received, [KilakilaDanmakuProtocol.join(_room), '2'], reason: 'text frames');
      expect(events.first, const DanmakuReady());
      expect(_messages(events).map((message) => message.type), [LiveMessageType.chat, LiveMessageType.online]);
      await connection.close();
    });
  });
}
