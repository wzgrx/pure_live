// CHZZK danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.17-CHZZK弹幕/record.md): the protocol and the connection
// against the archived v4's output for the recordings (S09-live, S10-live,
// S11-recent) and the synthetic frames (S12-synthetic), written by
// fixtures/chzzk/danmaku/v4_expected.dart; and the follow-ups of M5.F
// (appendix B-12: super chats, notices, retractions, the live-status check)
// against the recordings S13-recent, S14-live, S15-live,
// S17-live-status-closed and the synthetic frames S16-synthetic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/chzzk/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, String? url, Object data});

/// The frames of a recording, in order: text frames as `String`, binary
/// ones as bytes.
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

/// The received chat frames of a recording (not its HTTP answers).
List<_Frame> _received(String name) => [
  for (final frame in _frames(name))
    if (frame.dir == 'in' && frame.url == null) frame,
];

/// The sent frames of a recording, as text.
List<String> _sent(String name) => [
  for (final frame in _frames(name))
    if (frame.dir == 'out') _textOf(frame.data),
];

String _textOf(Object data) => switch (data) {
  final String text => text,
  final List<int> bytes => utf8.decode(bytes),
  _ => throw FormatException('frame $data'),
};

/// The archived v4's output for a fixture.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// v4's reading of every received frame of a recording, by frame index.
Map<int, Map<String, Object?>> _v4Frames(String name) => {
  for (final frame in (_v4(name)['frames']! as List<Object?>).cast<Map<String, Object?>>())
    frame['frame']! as int: {...frame}..remove('frame'),
};

final Map<String, Object?> _cases = _json('S12-synthetic/cases.json')! as Map<String, Object?>;

/// The v4 output for every synthetic case, one reading per frame.
final Map<String, Object?> _v4Cases = _v4('S12-synthetic')['cases']! as Map<String, Object?>;

const String _chat = 'N2lpu9';
const String _channel = 'af3323d30e11ae42c39d7203c7e07fa2';
const ChzzkDanmakuArgs _args = ChzzkDanmakuArgs(channelId: _channel, chatChannelId: _chat);

/// S08-chat-token's access token.
final String _token =
    ((_json('../S08-chat-token/body.json')! as Map<String, Object?>)['content']!
            as Map<String, Object?>)['accessToken']!
        as String;

/// S10-live's routing answer (six servers, kr-ss1 to kr-ss6).
final String _routing = _frames('S10-live').firstWhere((frame) => frame.url != null).data as String;

List<String> get _sixServers => [for (var n = 1; n <= 6; n++) 'kr-ss$n.chat.naver.com'];

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `chzzk:`; the new ids are the platform's own
/// (difference 1), so the projection adds the prefix back.
///
/// B-12: a donation is one super chat, which carries what v4 split into a
/// gift of 치즈 (when it has an amount) and a chat (when it has text), so it
/// projects back to both. Notices and retractions have no v4 counterpart:
/// they project to kinds of their own, which the differences add.
List<Map<String, Object?>> _asV4(LiveMessage message) {
  expect(message.color, LiveMessageColor.white);
  String? id([String suffix = '']) => message.messageId.isEmpty ? null : 'chzzk:${message.messageId}$suffix';
  final sentAt = message.sentAt?.millisecondsSinceEpoch;
  switch (message.type) {
    case LiveMessageType.chat:
      return [
        {
          'kind': 'chat',
          'id': id(),
          'sentAt': sentAt,
          'userId': message.userId,
          'userName': message.userName,
          'text': message.message,
        },
      ];
    case LiveMessageType.superChat:
      final data = message.data! as LiveSuperChatMessage;
      expect(data.messageId, message.messageId);
      return [
        if (data.price > 0)
          {
            'kind': 'gift',
            'id': id(':gift'),
            'sentAt': sentAt,
            'userId': message.userId,
            'userName': data.userName,
            'giftName': '치즈',
            'count': data.price,
          },
        if (data.message.isNotEmpty)
          {
            'kind': 'chat',
            'id': id(),
            'sentAt': sentAt,
            'userId': message.userId,
            'userName': data.userName,
            'text': data.message,
          },
      ];
    case LiveMessageType.notice:
      return [_notice(message)];
    case LiveMessageType.retraction:
      expect(message.messageId, isEmpty);
      return [
        {'kind': 'retraction', 'messageId': (message.data! as LiveRetraction).messageId},
      ];
    case LiveMessageType.online || LiveMessageType.gift:
      fail('unexpected ${message.type}');
  }
}

/// A notice in the projection's shape (B-12).
Map<String, Object?> _notice(LiveMessage message) => {
  'kind': 'notice',
  'notice': (message.data! as LiveNoticeKind).name,
  'id': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
};

/// A notice as [_notice] projects it.
Map<String, Object?> _noticeOf(
  String text, {
  required String id,
  LiveNoticeKind kind = LiveNoticeKind.system,
  int? sentAt,
  String userId = '',
  String userName = '',
}) => {
  'kind': 'notice',
  'notice': kind.name,
  'id': id,
  'sentAt': sentAt,
  'userId': userId,
  'userName': userName,
  'text': text,
};

/// The time decoding assumes a line without one was received at.
final DateTime _receivedAt = DateTime.fromMillisecondsSinceEpoch(1790612400000);

/// The new reading of one frame in v4's shape: whether the join was accepted
/// or refused, what the connection sends back (the pong, the recent-chat
/// request), the messages.
Map<String, Object?> _readAsV4(Object data, {required String chat}) {
  final frame = ChzzkDanmakuProtocol.decode(data, receivedAt: _receivedAt);
  return {
    'joined': frame.joined ?? false,
    'rejected': frame.joined == false,
    'replies': [
      if (frame.ping) jsonDecode(ChzzkDanmakuProtocol.pong),
      if ((frame.joined ?? false) && frame.sessionId.isNotEmpty)
        jsonDecode(ChzzkDanmakuProtocol.recent(chat, frame.sessionId)),
    ],
    'events': [for (final message in frame.messages) ..._asV4(message)],
  };
}

/// v4's reading with the differences every frame shares: member counts are
/// not an audience (difference 2), an anonymous donor has the site's name
/// and no user in its id (difference 4). v4's gifts of 치즈 stay: a super
/// chat projects back to them (B-12, [_asV4]).
Map<String, Object?> _shared(Map<String, Object?> v4) => {
  ...v4,
  'events': [
    for (final event in (v4['events']! as List<Object?>).cast<Map<String, Object?>>())
      if (event['kind'] == 'chat' || event['kind'] == 'gift')
        if (event['userName'] == '匿名' && event['userId'] == '')
          {
            ...event,
            'userName': ChzzkDanmakuProtocol.anonymousDonor,
            'id': event['sentAt'] == null
                ? null
                : 'chzzk:anonymous:${event['sentAt']}${event['kind'] == 'gift' ? ':gift' : ''}',
          }
        else
          event,
  ],
};

/// What B-12 adds to v4's reading of recorded frames, by frame: S10-live's
/// system line (93102, msgTypeCode 30) is a notice and its blind notice
/// (94008) a retraction.
final Map<String, Map<int, List<Map<String, Object?>>>> _b12Recorded = {
  'S10-live': {
    41: [_noticeOf('이모티콘 모드 ON：텍스트 대신 이모티콘만 전송할 수 있어요.', id: 'SYSTEM_MESSAGE:1790632421633', sentAt: 1790632421633)],
    42: [
      {'kind': 'retraction', 'messageId': '59def5da7a1d81fd130d21baf4b6404c:1790632422968'},
    ],
  },
};

/// [_shared] v4 of [name]'s frame [index] with what B-12 adds.
Map<String, Object?> _sharedB12(String name, int index, Map<String, Object?> v4) {
  final shared = _shared(v4);
  return {
    ...shared,
    'events': [..._events(shared), ...?_b12Recorded[name]?[index]],
  };
}

Map<String, Object?> _reading(Object? reading) => reading! as Map<String, Object?>;

List<Map<String, Object?>> _events(Object? reading) =>
    (_reading(reading)['events']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _line(String text, String user, int time, {String name = '시청자1'}) => {
  'kind': 'chat',
  'id': 'chzzk:$user:$time',
  'sentAt': time,
  'userId': user,
  'userName': name,
  'text': text,
};

String _user(int n) => n.toRadixString(16).padLeft(32, '0');

const int _t = 1790612400123;

/// The differences of the new decoder from v4 in the synthetic cases, beyond
/// [_shared] (docs/D-弹幕/D01-平台弹幕协议/D01.17-CHZZK弹幕/record.md, "与归档 v4 的差异", and "后续升级"
/// for B-12): v4's reading → the new one, per case. Cases not listed read as
/// v4 read them (donations included: [_asV4] projects a super chat back to
/// v4's gift and chat).
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // B-12: the system line is a notice (v4 showed nothing). Difference 6:
  // the kind decides; v4 took any line whose extras carry payAmount for a
  // donation, a sticker included.
  'a system line (a notice since B-12); images, stickers, parties and shop purchases show nothing': (v4) {
    expect(_events(v4[0]), isEmpty);
    expect(_events(v4[2]).map((event) => event['kind']), ['gift', 'chat']);
    expect(_events(v4[2]).last, containsPair('text', '스티커 후원'));
    return [
      {
        ..._reading(v4[0]),
        'events': [_noticeOf('이모티콘 모드 ON：텍스트 대신 이모티콘만 전송할 수 있어요.', id: 'SYSTEM_MESSAGE:${_t + 1}', sentAt: _t + 1)],
      },
      v4[1],
      {..._reading(v4[2]), 'events': const <Object?>[]},
    ];
  },
  // Difference 5: a subscription is a notice with its months, its tier and
  // the subscriber's message (D07.2; it was chat, which lost the months and
  // the tier); v4 dropped it. B-12: the subscription gift is a notice (v4
  // showed nothing).
  'subscriptions with and without a message, a subscription gift': (v4) {
    expect(_events(v4[0]), isEmpty);
    expect(_events(v4[1]), isEmpty);
    expect(_events(v4[2]), isEmpty);
    return [
      {
        ..._reading(v4[0]),
        'events': [
          _noticeOf(
            '구독자 订阅了 32 个月「팬」：32개월 축하해 주세요',
            id: '${_user(9)}:${_t + 9}',
            kind: LiveNoticeKind.subscription,
            sentAt: _t + 9,
            userId: _user(9),
            userName: '구독자',
          ),
        ],
      },
      {
        ..._reading(v4[1]),
        'events': [
          _noticeOf(
            '구독자2 订阅了频道「팬」',
            id: '${_user(10)}:${_t + 10}',
            kind: LiveNoticeKind.subscription,
            sentAt: _t + 10,
            userId: _user(10),
            userName: '구독자2',
          ),
        ],
      },
      {
        ..._reading(v4[2]),
        'events': [
          _noticeOf(
            '선물자 向频道赠送了 5 张订阅券',
            id: '${_user(11)}:${_t + 11}',
            kind: LiveNoticeKind.subscription,
            sentAt: _t + 11,
            userId: _user(11),
            userName: '선물자',
          ),
        ],
      },
    ];
  },
  // B-12: the blind notice (94008) is a retraction of the line it names by
  // user and time, the pinned notice (94010) a notice; v4 showed neither.
  'a blind (a retraction since B-12), a pinned notice (a notice since B-12); events, kicks and penalties show nothing':
      (v4) {
        expect(v4.map(_events), everyElement(isEmpty));
        return [
          v4[0],
          {
            ..._reading(v4[1]),
            'events': [
              {'kind': 'retraction', 'messageId': '${_user(1)}:$_t'},
            ],
          },
          {
            ..._reading(v4[2]),
            'events': [
              _noticeOf('스트리머 置顶了消息：공지입니다', id: 'notice:${_user(26)}:${_t + 26}', userId: _user(26), userName: '스트리머'),
            ],
          },
          ...v4.sublist(3),
        ];
      },
  // Difference 5 in the recent chat; difference 7: an answer whose retCode
  // is not 0 holds no chat (the site's SDK rejects it), v4 read its list.
  // (B-12: v4's gift for the anonymous donation stays in the reading, as the
  // super chat projects back to it.)
  'the recent chat (15101): its field names; an answer that is not retCode 0': (v4) {
    final events = _events(v4[0]);
    expect(events.map((event) => (event['kind'], event['text'])), [
      ('chat', '입장 전 채팅'),
      ('gift', null),
      ('chat', '익명 후원'),
    ]);
    expect(_events(v4[1]).single['text'], '보이면 안 됨');
    return [
      {
        ..._reading(v4[0]),
        'events': [
          ...events,
          _noticeOf(
            '구독 订阅了 3 个月「팬」：구독 메시지',
            id: '${_user(23)}:${_t + 23}',
            kind: LiveNoticeKind.subscription,
            sentAt: _t + 23,
            userId: _user(23),
            userName: '구독',
          ),
        ],
      },
      {..._reading(v4[1]), 'events': const <Object?>[]},
    ];
  },
  // Difference 9: an accepted join without a session id is joined (the SDK
  // only reads retCode); v4 took it for a refusal. No recent chat is asked.
  'the answer to the join: accepted, without a session id, refused, to be retried, without a code': (v4) {
    expect(_reading(v4[1]), containsPair('rejected', true));
    return [
      v4[0],
      {..._reading(v4[1]), 'joined': true, 'rejected': false},
      ...v4.sublist(2),
    ];
  },
  // Difference 10: text that is a list or an object is not chat (v4 showed
  // "[x]" and "{a: 1}").
  'fields of other types': (v4) {
    expect(_events(v4[1]).single['text'], '[x]');
    expect(_events(v4[2]).single['text'], '{a: 1}');
    return [
      v4[0],
      {..._reading(v4[1]), 'events': const <Object?>[]},
      {..._reading(v4[2]), 'events': const <Object?>[]},
      ...v4.sublist(3),
    ];
  },
  // Difference 8: a time out of range costs only the time (v4 lost the line
  // to a RangeError); a time not above zero gives no id (v4 made one of it).
  'times: milliseconds, zero, negative, beyond DateTime, text, a fraction': (v4) {
    expect(_events(v4[1]).single['id'], 'chzzk:${_user(47)}:0');
    expect(_events(v4[2]).single['id'], 'chzzk:${_user(48)}:-5');
    expect(_events(v4[3]), isEmpty);
    Map<String, Object?> untimed(Object? reading) => {
      ..._reading(reading),
      'events': [
        for (final event in _events(reading)) {...event, 'id': null},
      ],
    };
    return [
      v4[0],
      untimed(v4[1]),
      untimed(v4[2]),
      {
        ..._reading(v4[3]),
        'events': [
          {..._line('너무 큼', _user(49), 0), 'id': null, 'sentAt': null},
        ],
      },
      ...v4.sublist(4),
    ];
  },
};

/// Answers the token, routing and live-status requests: [tokens], [routes]
/// and [statuses] in turn (the last one repeats); a [LiveResponse] is
/// returned, an exception thrown.
final class _Http implements LiveHttp {
  new({List<Object>? tokens, List<Object>? routes, List<Object>? statuses, this.hold})
    : tokens = tokens ?? [_tokenAnswer()],
      routes = routes ?? [_routingAnswer()],
      statuses = statuses ?? [_statusAnswer()];

  final List<Object> tokens;
  final List<Object> routes;
  final List<Object> statuses;

  /// Keeps every request pending until it completes.
  final Completer<void>? hold;
  final List<LiveRequest> requests = [];

  List<LiveRequest> get tokenRequests => [
    for (final request in requests)
      if (request.url.host == 'comm-api.game.naver.com') request,
  ];

  List<LiveRequest> get routingRequests => [
    for (final request in requests)
      if (request.url.host == 'routing.chat.naver.com') request,
  ];

  List<LiveRequest> get statusRequests => [
    for (final request in requests)
      if (request.url.host == 'api.chzzk.naver.com') request,
  ];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final (answers, count) = switch (request.url.host) {
      'routing.chat.naver.com' => (routes, routingRequests.length),
      'api.chzzk.naver.com' => (statuses, statusRequests.length),
      _ => (tokens, tokenRequests.length),
    };
    var answer = answers[min(count, answers.length) - 1];
    await hold?.future;
    if (answer case _Held(:final until, answer: final held)) {
      await until.future;
      answer = held;
    }
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

/// An answer [_Http] gives only once [until] completes.
final class _Held {
  const new(this.until, this.answer);

  final Completer<void> until;
  final Object answer;
}

LiveResponse _tokenAnswer({int status = 200, String? body}) => LiveResponse(
  status: status,
  url: ChzzkDanmakuProtocol.tokenUrl(_chat),
  bytes: utf8.encode(body ?? File('../../fixtures/chzzk/S08-chat-token/body.json').readAsStringSync()),
);

LiveResponse _routingAnswer({int status = 200, String? body}) =>
    LiveResponse(status: status, url: ChzzkDanmakuProtocol.routingUrl, bytes: utf8.encode(body ?? _routing));

/// S14-live's recorded live-status answer (an open live, chat N2mCH5).
final String _recordedStatus = _frames('S14-live').first.data as String;

/// A live-status answer: S14-live's, naming the chat [chat].
LiveResponse _statusAnswer({String chat = _chat, int status = 200, String? body}) => LiveResponse(
  status: status,
  url: ChzzkDanmakuProtocol.liveStatusUrl(_channel),
  bytes: utf8.encode(body ?? _recordedStatus.replaceAll('"chatChannelId":"N2mCH5"', '"chatChannelId":"$chat"')),
);

/// Always picks [value] (modulo the bound).
final class _Pick implements Random {
  const new(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
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

  /// The sent frames, decoded.
  List<Map<String, Object?>> get messages => [
    for (final frame in sent) jsonDecode(frame as String) as Map<String, Object?>,
  ];

  /// The commands sent, in order.
  List<Object?> get commands => [for (final message in messages) message['cmd']];

  /// Answers the join as the server does (S10-live's answer, with [sid]).
  void accept({String sid = 'sid-1'}) => incoming.add(
    jsonEncode({
      'svcid': 'game',
      'bdy': {'accTkn': null, 'auth': 'READ', 'uuid': '00000000-0000-4000-8000-000000000001', 'sid': sid},
      'cmd': 10100,
      'retCode': 0,
      'retMsg': 'SUCCESS',
      'tid': '1',
      'cid': _chat,
    }),
  );

  /// Refuses the join with [code].
  void refuse(int code, [String message = 'Incorrect parameter']) =>
      incoming.add(jsonEncode({'cmd': 10100, 'retCode': code, 'retMsg': message, 'tid': '1'}));
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

ChzzkDanmakuConnection _connection(_Http http, _Connector connector, {ProxyPolicy? proxy, int pick = 4}) =>
    ChzzkDanmakuConnection(
      http: http,
      connector: connector.call,
      proxy: proxy ?? const FixedProxyPolicy(),
      random: _Pick(pick),
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

/// Runs [body] with every one-shot timer of 100 ms or more (token retries,
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

String _chatFrame(String text, {int n = 1, int cmd = 93101}) => jsonEncode({
  'svcid': 'game',
  'ver': '1',
  'bdy': [
    {
      'svcid': 'game',
      'cid': _chat,
      'mbrCnt': 10,
      'uid': _user(n),
      'profile': jsonEncode({'nickname': '시청자$n'}),
      'msg': text,
      'msgTypeCode': 1,
      'msgStatusType': 'NORMAL',
      'extras': '{}',
      'msgTime': _t + n,
    },
  ],
  'cmd': cmd,
  'tid': null,
  'cid': _chat,
});

void main() {
  group('protocol', () {
    test("the token is S08-chat-token's accessToken, as v4 read it; the recordings' token answers too", () {
      final body = File('../../fixtures/chzzk/S08-chat-token/body.json').readAsStringSync();
      expect(ChzzkDanmakuProtocol.accessToken(jsonDecode(body)), _token);
      final s08 = _json('../S08-chat-token/meta.json')! as Map<String, Object?>;
      expect(
        ChzzkDanmakuProtocol.tokenUrl(_chat),
        Uri.parse((s08['request']! as Map<String, Object?>)['url']! as String),
      );
      for (final name in ['S09-live', 'S10-live']) {
        final answer = _frames(name).firstWhere((frame) => '${frame.url}'.contains('/chats/access-token'));
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        expect(Uri.parse(answer.url!), ChzzkDanmakuProtocol.tokenUrl(chat));
        expect(ChzzkDanmakuProtocol.accessToken(jsonDecode(answer.data as String)), _v4(name)['accessToken']);
        expect(ChzzkDanmakuProtocol.tokenUrl(chat).toString(), (_v4(name)['connector']! as Map)['tokenUrl']);
      }
      for (final answer in <Object?>[
        {'code': 50001, 'message': '서버 오류입니다.', 'content': null},
        {'code': 200, 'content': null},
        {
          'code': 200,
          'content': {'accessToken': ''},
        },
        {
          'code': 200,
          'content': {'accessToken': 7},
        },
        {'code': '200', 'content': <String, Object?>{}},
        'text',
        null,
      ]) {
        expect(ChzzkDanmakuProtocol.accessToken(answer), isNull, reason: '$answer');
      }
    });

    test("the servers are S10-live's routing answer; bad hosts are skipped, the SDK's list is the fallback", () {
      expect(
        ChzzkDanmakuProtocol.routingUrl.toString(),
        'https://routing.chat.naver.com/routing/getRouting?serviceId=game',
      );
      expect(ChzzkDanmakuProtocol.servers(jsonDecode(_routing)), _sixServers);
      expect(ChzzkDanmakuProtocol.defaultServers, [for (var n = 1; n <= 5; n++) 'kr-ss$n.chat.naver.com']);
      Map<String, Object?> answer(List<Object?> list, {Object? code = 200}) => {
        'result': {'sessionServerList': list, 'expireTime': 86400},
        'code': code,
      };
      expect(
        ChzzkDanmakuProtocol.servers(
          answer([
            'kr-ss2.chat.naver.com',
            'kr-ss2.chat.naver.com',
            'evil.example.com',
            'chat.naver.com',
            'KR-SS3.chat.naver.com',
            'kr-ss4.chat.naver.com/chat',
            'kr ss5.chat.naver.com',
            7,
            null,
            'w-kr-ss1.chat.naver.com',
          ]),
        ),
        ['kr-ss2.chat.naver.com', 'w-kr-ss1.chat.naver.com'],
      );
      expect(
        ChzzkDanmakuProtocol.servers(answer([for (var n = 1; n <= 20; n++) 'kr-ss$n.chat.naver.com'])),
        hasLength(ChzzkDanmakuProtocol.maxServers),
      );
      for (final bad in <Object?>[
        answer([]),
        answer(['evil.example.com']),
        answer(_sixServers, code: 500),
        {'code': 200, 'result': null},
        'text',
        null,
      ]) {
        expect(ChzzkDanmakuProtocol.servers(bad), isNull, reason: '$bad');
      }
      expect(ChzzkDanmakuProtocol.endpoints(_sixServers, 4).map((uri) => uri.toString()), [
        for (final n in [5, 6, 1, 2, 3, 4]) 'wss://kr-ss$n.chat.naver.com/chat',
      ]);
    });

    test('v4 took one server from the chat channel id (sum % 9 + 1); the site picks one of the routing list', () {
      // Difference 11: v4's formula names kr-ss7 to kr-ss9, which the
      // routing answer does not list; the recordings used kr-ss1 and kr-ss5.
      expect((_v4('S09-live')['connector']! as Map)['endpoint'], 'wss://kr-ss1.chat.naver.com/chat');
      expect((_v4('S10-live')['connector']! as Map)['endpoint'], 'wss://kr-ss2.chat.naver.com/chat');
      expect(
        (_meta('S10-live')['handshakes']! as List).single,
        containsPair('url', 'wss://kr-ss5.chat.naver.com/chat'),
      );
      for (final name in ['S09-live', 'S10-live']) {
        final url = ((_meta(name)['handshakes']! as List).single as Map)['url']! as String;
        expect(ChzzkDanmakuProtocol.endpoints(_sixServers, 0).map((uri) => uri.toString()), contains(url));
      }
    });

    test('handshake headers: the recorded ones, as v4 sent them', () {
      for (final name in ['S09-live', 'S10-live', 'S11-recent']) {
        final handshake = (_meta(name)['handshakes']! as List).single as Map;
        expect(ChzzkDanmakuProtocol.handshakeHeaders, handshake['headers'], reason: name);
      }
      expect(ChzzkDanmakuProtocol.handshakeHeaders, (_v4('S09-live')['connector']! as Map)['handshakeHeaders']);
      expect(ChzzkDanmakuProtocol.handshakeHeaders, {'origin': ChzzkApi.origin, 'user-agent': ChzzkApi.userAgent});
    });

    test("the join, the recent-chat request and the ping are the recorded ones byte for byte, and v4's", () {
      for (final name in ['S09-live', 'S10-live']) {
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        final token = _v4(name)['accessToken']! as String;
        final sent = _sent(name);
        final answer = jsonDecode(_received(name).first.data as String) as Map<String, Object?>;
        final sid = (answer['bdy']! as Map<String, Object?>)['sid']! as String;
        expect(ChzzkDanmakuProtocol.join(chat, token), sent[0], reason: name);
        expect(ChzzkDanmakuProtocol.join(chat, token), (_v4(name)['connector']! as Map)['join']);
        expect(ChzzkDanmakuProtocol.recent(chat, sid), sent[1], reason: name);
        expect(sent.skip(2), everyElement(ChzzkDanmakuProtocol.ping), reason: name);
        expect(sent.skip(2), isNotEmpty);
        expect(ChzzkDanmakuProtocol.ping, (_v4(name)['connector']! as Map)['ping']);
      }
      // S09 sent them as binary (v4), S10 as text (the site): the server
      // accepts both; this client sends text (difference 12).
      expect(
        _frames('S09-live').where((frame) => frame.dir == 'out').map((frame) => frame.data),
        everyElement(isA<List<int>>()),
      );
      expect(
        _frames('S10-live').where((frame) => frame.dir == 'out').map((frame) => frame.data),
        everyElement(isA<String>()),
      );
      expect(jsonDecode(ChzzkDanmakuProtocol.pong), {'ver': '3', 'cmd': 10000});
    });

    test('a chat channel id is base64url, at most 64 characters', () {
      for (final id in ['N2lpu9', 'N2l_uf', 'N2l-x_', 'N2m13O', 'a' * 64]) {
        expect(ChzzkDanmakuProtocol.isChatChannelId(id), isTrue, reason: id);
      }
      for (final id in ['', ' N2lpu9', 'N2l/pu9', 'N2l+pu9', 'N2l?x', 'a' * 65, '채팅']) {
        expect(ChzzkDanmakuProtocol.isChatChannelId(id), isFalse, reason: id);
      }
    });

    test("S09's arguments are what room entry gives for S06-live-detail-live", () {
      final detail =
          (jsonDecode(File('../../fixtures/chzzk/S06-live-detail-live/body.json').readAsStringSync())
                  as Map<String, Object?>)['content']!
              as Map<String, Object?>;
      final keys = _meta('S09-live')['danmakuKeys']! as Map<String, Object?>;
      expect(keys['chatChannelId'], detail['chatChannelId']);
      expect(keys['channelId'], (detail['channel']! as Map<String, Object?>)['channelId']);
      expect(keys, {'channelId': _args.channelId, 'chatChannelId': _args.chatChannelId});
    });

    test('a chat line fills the message model', () {
      final frame = ChzzkDanmakuProtocol.decode(_received('S09-live')[1].data);
      final message = frame.messages.first;
      expect(message.type, LiveMessageType.chat);
      expect(message.userName, '观众1');
      expect(message.userId, '605lz6d3a8k0x1zx4r75f5mt1p7tf990');
      expect(message.message, '헉');
      expect(message.color, LiveMessageColor.white);
      expect(message.messageId, '605lz6d3a8k0x1zx4r75f5mt1p7tf990:1790525942218');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790525942218));
      expect(message.userLevel, isEmpty);
      expect(message.fansName, isEmpty);
      expect(message.data, isNull);
      expect(frame.messages, hasLength(5));
    });

    test('member counts are not the audience: nothing is reported; audience.dart keeps the lists', () {
      // v4 reported every live frame's last mbrCnt as the online audience.
      // It counts the chat's connections: S10 began with 4228 against the
      // detail's 4724 viewers, and it ignores cvExposure (difference 2).
      final v4Online = [
        for (final reading in _v4Frames('S09-live').values)
          for (final event in _events(reading))
            if (event['kind'] == 'online') event['value'],
      ];
      expect(v4Online, hasLength(35));
      // B-12 adds super chats, notices and retractions; audience figures
      // stay out.
      for (final name in ['S09-live', 'S10-live', 'S11-recent', 'S13-recent', 'S14-live', 'S15-live']) {
        for (final frame in _frames(name)) {
          if (frame.url != null || frame.dir != 'in') continue;
          expect(
            ChzzkDanmakuProtocol.decode(frame.data).messages.map((message) => message.type),
            everyElement(isNot(anyOf(LiveMessageType.online, LiveMessageType.gift))),
            reason: '$name ${frame.index}',
          );
        }
      }
      final capability = AudiencePlatformCapability.of(SiteIds.chzzk);
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomList);
      expect(capability.hasPopularity, isFalse);
    });

    test('S11: donations (named, anonymous, video) are super chats (B-12) in cheese, a subscription a notice (D07.2); '
        'clean-bot lines are not shown', () {
      final answers = [for (final frame in _received('S11-recent')) ChzzkDanmakuProtocol.decode(frame.data)];
      final all = [for (final answer in answers) ...answer.messages];
      // B-12: donations were chat lines without their amount.
      final donations = [
        for (final message in all)
          if (message.type == LiveMessageType.superChat) message.data! as LiveSuperChatMessage,
      ];
      expect(donations, hasLength(8));
      final anonymous = donations.where((data) => data.userName == ChzzkDanmakuProtocol.anonymousDonor).toList();
      expect(ChzzkDanmakuProtocol.anonymousDonor, '익명의 후원자', reason: "the site's name for anonymous donors");
      expect(anonymous, hasLength(6));
      expect(anonymous.map((data) => data.messageId), everyElement(startsWith('anonymous:')));
      expect(anonymous.map((data) => data.face), everyElement(isEmpty));
      expect(
        [
          for (final message in all)
            if (anonymous.any((data) => data.messageId == message.messageId)) message.userId,
        ],
        [for (final _ in anonymous) ''],
        reason: 'no user id',
      );
      expect(anonymous.last.message, '싸이(PSY) - 예술이야 [가사/Lyrics]', reason: 'a video donation names its video');
      expect(anonymous.last.priceText, '1,820 치즈');
      expect(donations.map((data) => data.unit), everyElement(LiveGiftUnit.cheese));
      final named = donations.singleWhere((data) => data.message.startsWith('이번주 토요일'));
      expect(named.userName, '观众115');
      expect(named.messageId, '97faaf557acce48371affa77236380eb:1790632655370');
      // D07.2: the subscription is a notice, no longer chat.
      final subscription = answers[2].messages.singleWhere((message) => message.message.endsWith('나이스한 아침이야'));
      expect(subscription.type, LiveMessageType.notice);
      expect(subscription.data, LiveNoticeKind.subscription);
      expect(subscription.message, '观众132 订阅了 32 个月「나나양 좋아」：나이스한 아침이야');
      expect(subscription.userName, '观众132');
      expect(subscription.userId, '27b600565084c7dfcf6e30b587f37ac7');
      final answer = jsonDecode(_received('S11-recent')[0].data as String) as Map<String, Object?>;
      final list = (answer['bdy']! as Map<String, Object?>)['messageList']! as List<Object?>;
      final hidden = [
        for (final line in list.cast<Map<String, Object?>>())
          if (line['messageStatusType'] == 'CBOTBLIND') line['content'],
      ];
      expect(hidden, hasLength(2));
      expect(all.map((message) => message.message), isNot(anyElement(isIn(hidden))));
      expect(answers.map((answer) => answer.messages.length), [48, 26, 50]);
    });

    test('a frame is a JSON object named by cmd; the answers, the ping and the end are read', () {
      final accepted = ChzzkDanmakuProtocol.decode(_received('S10-live')[0].data);
      expect(accepted.joined, isTrue);
      expect(accepted.sessionId, (jsonDecode(_sent('S10-live')[1]) as Map<String, Object?>)['sid']);
      final refused = ChzzkDanmakuProtocol.decode(
        '{"cmd":10100,"retCode":105,"retMsg":"Incorrect parameter","tid":"1"}',
      );
      expect(refused.joined, isFalse);
      expect(refused.refusal, '105 Incorrect parameter');
      expect(refused.retry, isFalse);
      for (final code in [302, 303, 304]) {
        expect(ChzzkDanmakuProtocol.decode('{"cmd":10100,"retCode":$code}').retry, isTrue, reason: '$code');
      }
      expect(ChzzkDanmakuProtocol.decode('{"cmd":10100}').refusal, isEmpty);
      expect(ChzzkDanmakuProtocol.decode('{"ver":"2","cmd":0}').ping, isTrue);
      expect(ChzzkDanmakuProtocol.decode('{"ver":"2","cmd":90102}').closed, isTrue);
      final pong = ChzzkDanmakuProtocol.decode(
        _received('S09-live').singleWhere((frame) => '${frame.data}'.contains('"cmd":10000')).data,
      );
      expect(pong.ping || pong.closed || pong.joined != null || pong.messages.isNotEmpty, isFalse);
    });
  });

  group('recorded frames against v4', () {
    for (final name in ['S09-live', 'S10-live']) {
      test('$name: every received frame reads as v4 read it, without member counts; B-12 adds to S10', () {
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        final v4 = _v4Frames(name);
        final frames = _received(name);
        expect(v4.keys, [for (final frame in frames) frame.index]);
        for (final frame in frames) {
          expect(
            _readAsV4(frame.data, chat: chat),
            _sharedB12(name, frame.index, v4[frame.index]!),
            reason: 'frame ${frame.index}',
          );
        }
      });
    }

    test('S09-live: joined at the answer; 50 recent and 75 live lines', () {
      final frames = [for (final frame in _received('S09-live')) ChzzkDanmakuProtocol.decode(frame.data)];
      expect(frames.where((frame) => frame.joined ?? false), hasLength(1));
      expect(frames[1].messages.length + frames[2].messages.length, 55);
      expect(frames[2].messages, hasLength(50), reason: 'the recent chat');
      expect([for (final frame in frames) ...frame.messages], hasLength(125));
    });

    test('S10-live: the system line is a notice and the blind notice a retraction (B-12); the chat-mode event and '
        'the pongs show nothing', () {
      final frames = _received('S10-live');
      final texts = [for (final frame in frames) frame.data as String];
      for (final cmd in ['"cmd":93006', '"cmd":10000']) {
        final matching = [
          for (final (index, text) in texts.indexed)
            if (text.contains(cmd)) index,
        ];
        expect(matching, isNotEmpty, reason: cmd);
        for (final index in matching) {
          expect(ChzzkDanmakuProtocol.decode(texts[index]).messages, isEmpty, reason: cmd);
        }
      }
      // B-12: both showed nothing.
      final system = texts.singleWhere((text) => text.contains('"msgTypeCode":30'));
      expect(system, contains('"cmd":93102'));
      final notice = ChzzkDanmakuProtocol.decode(system).messages.single;
      expect(notice.type, LiveMessageType.notice);
      expect(notice.data, LiveNoticeKind.system);
      expect(notice.message, '이모티콘 모드 ON：텍스트 대신 이모티콘만 전송할 수 있어요.');
      expect(notice.userName, isEmpty);
      expect(notice.userId, isEmpty);
      expect(notice.messageId, 'SYSTEM_MESSAGE:1790632421633');
      expect(notice.sentAt, DateTime.fromMillisecondsSinceEpoch(1790632421633));
      final blind = ChzzkDanmakuProtocol.decode(texts.singleWhere((text) => text.contains('"cmd":94008')));
      expect(blind.messages.single.type, LiveMessageType.retraction);
      expect(
        blind.messages.single.data,
        const LiveRetraction.message('59def5da7a1d81fd130d21baf4b6404c:1790632422968'),
      );
      final messages = [for (final text in texts) ...ChzzkDanmakuProtocol.decode(text).messages];
      expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(106));
      expect(messages, hasLength(108));
    });

    test('S11-recent: every answer reads as v4 read it, and the subscription too (difference 5)', () {
      final v4 = _v4Frames('S11-recent');
      for (final frame in _received('S11-recent')) {
        final chat = v4[frame.index]!['chatChannelId']! as String;
        final expected = _shared({...v4[frame.index]!}..remove('chatChannelId'));
        final actual = _readAsV4(frame.data, chat: chat);
        final known = {for (final event in _events(expected)) jsonEncode(event)};
        final extra = [
          for (final event in _events(actual))
            if (!known.contains(jsonEncode(event))) event,
        ];
        if (chat == 'N2m13O') {
          // D07.2: a notice of the months and the tier, with the words.
          expect(extra.single, containsPair('text', '观众132 订阅了 32 个月「나나양 좋아」：나이스한 아침이야'));
          expect(extra.single, containsPair('notice', 'subscription'));
        } else {
          expect(extra, isEmpty, reason: chat);
        }
        expect({...actual, 'events': _events(actual).where((event) => !extra.contains(event)).toList()}, expected);
      }
    });
  });

  group('synthetic frames (S12-synthetic) against v4', () {
    final chat = _cases['chatChannelId']! as String;
    final cases = (_cases['cases']! as List<Object?>).cast<Map<String, Object?>>();

    test('every case has v4 output, and every difference names a case', () {
      expect(_v4Cases.keys, [for (final entry in cases) entry['name']]);
      expect(_differences.keys, everyElement(isIn(_v4Cases.keys)));
    });

    for (final entry in cases) {
      final name = entry['name']! as String;
      test(name, () {
        final frames = (entry['frames']! as List<Object?>).cast<Map<String, Object?>>();
        final v4 = [for (final reading in _v4Cases[name]! as List<Object?>) _shared(_reading(reading))];
        final expected = _differences[name]?.call(v4) ?? v4;
        final actual = [
          for (final frame in frames)
            _readAsV4(switch (frame) {
              {'text': final String text} => text,
              {'b64': final String b64} => base64Decode(b64),
              _ => throw FormatException('frame $frame'),
            }, chat: chat),
        ];
        expect(actual, expected);
      });
    }

    test('the end of the session and the retried refusals are read as such', () {
      final frames = [
        for (final frame
            in (cases.firstWhere((entry) => '${entry['name']}'.startsWith("the server's ping"))['frames']! as List)
                .cast<Map<String, Object?>>())
          ChzzkDanmakuProtocol.decode(frame['text']),
      ];
      expect(frames.map((frame) => (frame.ping, frame.closed)), [(true, false), (false, false), (false, true)]);
      final answers = [
        for (final frame
            in (cases.firstWhere((entry) => '${entry['name']}'.startsWith('the answer to the join'))['frames']! as List)
                .cast<Map<String, Object?>>())
          ChzzkDanmakuProtocol.decode(frame['text']),
      ];
      expect(answers.map((answer) => (answer.joined, answer.retry, answer.refusal)), [
        (true, false, ''),
        (true, false, ''),
        (false, false, '105 Incorrect parameter'),
        (false, true, '302 Moved'),
        (false, true, '303'),
        (false, true, '304 Moved'),
        (false, false, ''),
      ]);
    });
  });

  group('connection', () {
    test('asks the token and the servers, opens a random server, joins, and is ready on the answer', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      final token = http.tokenRequests.single;
      expect(token.site, SiteIds.chzzk);
      expect(token.method, 'GET');
      expect(token.url, ChzzkDanmakuProtocol.tokenUrl(_chat));
      expect(token.headers, ChzzkApi.headers);
      expect(token.followRedirects, isFalse);
      expect(token.timeout, ChzzkDanmakuConnection.tokenTimeout);
      final routing = http.routingRequests.single;
      expect(routing.site, SiteIds.chzzk);
      expect(routing.url, ChzzkDanmakuProtocol.routingUrl);
      expect(routing.headers, ChzzkApi.headers);
      expect(routing.followRedirects, isFalse);
      expect(routing.timeout, const Duration(milliseconds: 1500));
      expect(connector.endpoints, [Uri.parse('wss://kr-ss5.chat.naver.com/chat')]);
      expect(connector.headers.single, ChzzkDanmakuProtocol.handshakeHeaders);
      expect(connector.routes.single, isA<DirectRoute>());
      final channel = connector.channels.single;
      expect(channel.sent, [ChzzkDanmakuProtocol.join(_chat, _token)]);
      expect(events, isEmpty, reason: 'not joined before the answer');
      expect(connection.status, DanmakuStatus.connecting);
      channel.accept();
      await _until(() => events.isNotEmpty);
      expect(channel.sent.last, ChzzkDanmakuProtocol.recent(_chat, 'sid-1'));
      // A repeated answer does not report the room joined again.
      channel.accept();
      await _wait(const Duration(milliseconds: 10));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.connected);
      await connection.close();
    });

    test('the token and the servers are asked together', () async {
      final hold = Completer<void>();
      final http = _Http(hold: hold);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.length == 2);
      expect(connector.endpoints, isEmpty);
      hold.complete();
      await connecting;
      expect(connector.endpoints, hasLength(1));
      await connection.close();
    });

    // B-12: S10's system line and blind notice add a notice and a retraction
    // to its 106 chat lines.
    for (final (name, count) in const [('S09-live', 125), ('S10-live', 108)]) {
      test('replaying $name reports what v4 read (and B-12 adds), in order, and asks the recent chat of its '
          'session', () async {
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        final connector = _Connector();
        final connection = _connection(_Http(), connector);
        final events = _record(connection);
        await connection.connect(ChzzkDanmakuArgs(channelId: _channel, chatChannelId: chat));
        final channel = connector.channels.single;
        final expected = <Object?>[];
        for (final frame in _received(name)) {
          channel.incoming.add(frame.data);
          expected.addAll(_events(_sharedB12(name, frame.index, _v4Frames(name)[frame.index]!)));
        }
        expect(expected, hasLength(count));
        await _until(() => _messages(events).length == count);
        await _wait(const Duration(milliseconds: 10));
        expect([for (final message in _messages(events)) ..._asV4(message)], expected);
        expect(events.whereType<DanmakuReady>(), hasLength(1));
        expect(channel.sent.skip(1).first, _sent(name)[1], reason: "the recorded session's recent-chat request");
        await connection.close();
      });
    }

    test('timing: 20 s ping, 30 s silence limit, 5 s join timer, 8 reconnects', () {
      final connection = ChzzkDanmakuConnection(http: _Http());
      expect(connection.heartbeatInterval, const Duration(seconds: 20));
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 20));
      expect(policy.inactivityTimeout, const Duration(seconds: 30));
      expect(policy.joinTimeout, const Duration(seconds: 5));
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(connection.site, SiteIds.chzzk);
    });

    test('pings on its 20 s timer and on demand, answers the server ping; nothing after close', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = _connection(_Http(), connector)..heartbeat();
          await connection.connect(_args);
          final channel = connector.channels.single;
          await _until(() => channel.sent.length >= 3);
          expect(channel.sent.skip(1).take(2), [ChzzkDanmakuProtocol.ping, ChzzkDanmakuProtocol.ping]);
          channel.incoming.add('{"ver":"2","cmd":0}');
          await _until(() => channel.sent.contains(ChzzkDanmakuProtocol.pong));
          await connection.close();
          final count = channel.sent.length;
          connection.heartbeat();
          channel.incoming.add('{"ver":"2","cmd":0}');
          await _wait(const Duration(milliseconds: 20));
          expect(channel.sent, hasLength(count), reason: 'nothing after close');
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            periods.add(period);
            return parent.createPeriodicTimer(zone, const Duration(milliseconds: 5), callback);
          },
        ),
      );
      expect(periods, [const Duration(seconds: 20)]);
    });

    test('the proxy policy routes the handshake', () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        _Http(),
        connector,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.chzzk: route}),
      );
      await connection.connect(_args);
      expect(connector.routes.single, route);
      await connection.close();
    });

    test("without the routing answer the SDK's five servers are used", () async {
      for (final route in <Object>[
        _routingAnswer(status: 503),
        _routingAnswer(body: 'not json'),
        _routingAnswer(body: '{"code":200,"result":{"sessionServerList":["evil.example.com"]}}'),
        const TransportFailure(SiteIds.chzzk, TransportReason.timeout),
      ]) {
        final connector = _Connector();
        final connection = _connection(_Http(routes: [route]), connector, pick: 7);
        await connection.connect(_args);
        expect(connector.endpoints, [Uri.parse('wss://kr-ss3.chat.naver.com/chat')], reason: '$route');
        await connection.close();
      }
    });

    test('the chat channel id is checked and trimmed; a bad one ends with connectionFailed and asks nothing', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      await connection.connect(const ChzzkDanmakuArgs(channelId: _channel, chatChannelId: ' N2lpu9 '));
      expect(http.tokenRequests.single.url, ChzzkDanmakuProtocol.tokenUrl(_chat));
      expect(connector.channels.single.sent.single, ChzzkDanmakuProtocol.join(_chat, _token));
      await connection.close();
      for (final bad in ['', '   ', 'N2l/pu9', 'N2l pu9']) {
        final quiet = _Http();
        final other = _Connector();
        final refused = _connection(quiet, other);
        final events = _record(refused);
        await refused.connect(ChzzkDanmakuArgs(channelId: _channel, chatChannelId: bad));
        expect(quiet.requests, isEmpty, reason: bad);
        expect(other.endpoints, isEmpty);
        expect(
          events.single,
          isA<DanmakuClosed>()
              .having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed)
              .having((event) => event.detail, 'detail', 'No chat channel'),
        );
      }
    });

    test('the token is asked three times, 0.5 s and 1 s apart; the third answer is used', () async {
      final held = <_HeldTimer>[];
      final http = _Http(
        tokens: [
          _tokenAnswer(status: 500, body: '{"code":50001,"message":"서버 오류입니다.","content":null}'),
          const TransportFailure(SiteIds.chzzk, TransportReason.connect),
          _tokenAnswer(),
        ],
      );
      final connector = _Connector();
      final connection = _connection(http, connector);
      await _heldTimers(held, () async {
        final connecting = connection.connect(_args);
        await _fire(held, const Duration(milliseconds: 500));
        await _fire(held, const Duration(seconds: 1));
        await connecting;
      });
      expect(http.tokenRequests, hasLength(3));
      expect(http.routingRequests, hasLength(1));
      expect(connector.channels.single.sent.single, ChzzkDanmakuProtocol.join(_chat, _token));
      await connection.close();
    });

    test('no token after three answers ends with credentialsUnavailable and opens nothing', () async {
      for (final answer in <Object>[
        _tokenAnswer(status: 500, body: '{"code":50001,"message":"서버 오류입니다.","content":null}'),
        _tokenAnswer(body: '{"code":200,"message":null,"content":{"accessToken":null}}'),
        _tokenAnswer(body: '<html>'),
        _tokenAnswer(status: 302, body: ''),
        const TransportFailure(SiteIds.chzzk, TransportReason.connect),
      ]) {
        final delays = <Duration>[];
        final http = _Http(tokens: [answer]);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await _fastTimers(delays, () => connection.connect(_args));
        expect(http.tokenRequests, hasLength(3), reason: '$answer');
        expect(delays.where((delay) => delay < const Duration(seconds: 2)), [
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
        ]);
        expect(connector.endpoints, isEmpty);
        expect(
          events.single,
          isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable),
        );
        expect(connection.status, DanmakuStatus.closed);
      }
    });

    test('close while the token is asked: both requests are cancelled, nothing opens or is reported', () async {
      final hold = Completer<void>();
      final http = _Http(hold: hold);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.length == 2);
      await connection.close();
      expect(http.requests.map((request) => request.cancel!.isCancelled), [true, true]);
      hold.complete();
      await connecting;
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a join unanswered for 5 s drops the socket; the next server joins with the same token', () async {
      final held = <_HeldTimer>[];
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        final first = connector.channels.single;
        await _fire(held, const Duration(seconds: 5));
        // The runtime's backoff: six endpoints, the next one after 1 s.
        await _fire(held, const Duration(seconds: 1));
        await _until(() => connector.channels.length == 2);
        expect(first.closed, isTrue);
        connector.channels.last.accept();
        await _until(() => connection.isConnected);
        expect(_active(held, const Duration(seconds: 5)), isEmpty, reason: 'answered: no join timer');
        await connection.close();
      });
      expect(connector.endpoints.map((uri) => uri.host), ['kr-ss5.chat.naver.com', 'kr-ss6.chat.naver.com']);
      expect([
        for (final channel in connector.channels) channel.sent.first,
      ], List.filled(2, ChzzkDanmakuProtocol.join(_chat, _token)));
      expect(http.tokenRequests, hasLength(1));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
    });

    test('a dropped socket reconnects after 1 s to the next server, rejoins and asks the recent chat again', () async {
      final held = <_HeldTimer>[];
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.accept();
        await _until(() => connection.isConnected);
        await connector.channels.single.incoming.close();
        await _fire(held, const Duration(seconds: 1));
        await _until(() => connector.channels.length == 2);
        connector.channels.last.accept(sid: 'sid-2');
        await _until(() => events.whereType<DanmakuReady>().length == 2);
      });
      expect(http.requests, hasLength(2), reason: 'the token and the servers are kept');
      expect(connector.channels.first.commands, [100, 5101]);
      expect(connector.channels.last.sent, [
        ChzzkDanmakuProtocol.join(_chat, _token),
        ChzzkDanmakuProtocol.recent(_chat, 'sid-2'),
      ]);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('a refused join ends with connectionFailed, naming the refusal; nothing reconnects', () async {
      final held = <_HeldTimer>[];
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        final channel = connector.channels.single..refuse(105);
        await _until(() => events.isNotEmpty);
        // The server says goodbye and closes the socket.
        await channel.incoming.close();
        await _wait(const Duration(milliseconds: 20));
      });
      expect(
        events.single,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed)
            .having((event) => event.detail, 'detail', 'Join refused: 105 Incorrect parameter'),
      );
      expect(connector.channels.single.closed, isTrue);
      expect(connector.channels, hasLength(1));
      expect(held.where((timer) => timer.isActive && timer.duration == const Duration(seconds: 5)), isEmpty);
      expect(connection.status, DanmakuStatus.closed);
    });

    test('a refusal the site retries (302, 303, 304) reconnects to the next server', () async {
      final held = <_HeldTimer>[];
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.refuse(303, 'Moved');
        await _fire(held, const Duration(seconds: 1));
        await _until(() => connector.channels.length == 2);
        connector.channels.last.accept();
        await _until(() => connection.isConnected);
      });
      expect(connector.channels.first.closed, isTrue);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('the end of the session (90102) ends with connectionFailed', () async {
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single
        ..accept()
        ..incoming.add('{"ver":"2","cmd":90102}');
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty && connector.channels.single.closed);
      expect(events.first, const DanmakuReady());
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed)
            .having((event) => event.detail, 'detail', 'Closed by the server'),
      );
      expect(connector.channels.single.closed, isTrue);
    });

    test('reconnects go round the six servers, 1 s five times and 2 s three times, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(
        fail: (endpoint) =>
            WebSocketException("Connection to '$endpoint' was not upgraded to websocket, HTTP status code: 503"),
      );
      final connection = _connection(_Http(), connector, pick: 0);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays.where((delay) => delay >= const Duration(seconds: 1)), [
        for (final seconds in [1, 1, 1, 1, 1, 2, 2, 2]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints.map((uri) => uri.host), [
        for (final n in [1, 2, 3, 4, 5, 6, 1, 2, 3]) 'kr-ss$n.chat.naver.com',
      ]);
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('503'))
            .having((event) => event.detail, 'detail', isNot(contains(_token))),
      );
      expect(events, hasLength(2));
    });

    test('close: no event, ping or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single..accept();
      await _until(() => connection.isConnected);
      await connection.close();
      await connection.close();
      channel
        ..incoming.add(_chatFrame('닫은 뒤'))
        ..refuse(105);
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.commands, [100, 5101]);
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another chat closes the first socket and asks a token for the new one', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await connection.connect(const ChzzkDanmakuArgs(channelId: _channel, chatChannelId: 'N2lxdt'));
      expect(http.tokenRequests.map((request) => request.url.queryParameters['channelId']), [_chat, 'N2lxdt']);
      expect(first.closed, isTrue);
      expect(jsonDecode(connector.channels.last.sent.single as String), containsPair('cid', 'N2lxdt'));
      first.incoming.add(_chatFrame('옛 채팅'));
      first.refuse(105);
      connector.channels.last
        ..accept()
        ..incoming.add(_chatFrame('새 채팅'));
      await _until(() => _messages(events).isNotEmpty);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).single.message, '새 채팅');
      expect(events.whereType<DanmakuClosed>(), isEmpty, reason: "the old socket's refusal is ignored");
      await connection.close();
    });

    test('takes ChzzkDanmakuArgs only', () async {
      final connection = _connection(_Http(), _Connector());
      await expectLater(connection.connect(_chat), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under chzzk', () {
      final http = _Http();
      final registry = DanmakuRegistry({SiteIds.chzzk: () => ChzzkDanmakuConnection(http: http)});
      expect(registry.platforms, [SiteIds.chzzk]);
      expect(registry.connectionFor(' CHZZK '), isA<ChzzkDanmakuConnection>());
      expect(registry.connectionFor('twitch'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the headers, the join, the recorded frames, the ping and the pong', () async {
      final received = <Map<String, Object?>>[];
      final handshakes = <Map<String, String?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final recorded = _received('S10-live');
      server.listen((request) async {
        handshakes.add({
          'path': request.uri.path,
          'origin': request.headers.value('origin'),
          'user-agent': request.headers.value('user-agent'),
        });
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          final message = jsonDecode(frame as String) as Map<String, Object?>;
          received.add(message);
          switch (message['cmd']) {
            case 100:
              socket.add(recorded.first.data);
            case 5101:
              for (final frame in recorded.skip(1)) {
                socket.add(frame.data);
              }
              socket.add('{"ver":"2","cmd":0}');
            case 0:
              socket.add('{"ver":"2","cmd":10000}');
          }
        });
      });
      final requested = <Uri>[];
      final connection = ChzzkDanmakuConnection(
        http: _Http(),
        random: const _Pick(4),
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
      await connection.connect(const ChzzkDanmakuArgs(channelId: _channel, chatChannelId: 'N2l_uf'));
      // B-12: 106 chat lines, a notice and a retraction.
      await _until(() => _messages(events).length == 108);
      await _until(() => received.any((message) => message['cmd'] == 10000));
      expect(requested, [Uri.parse('wss://kr-ss5.chat.naver.com/chat')]);
      expect(handshakes, [
        // dart:io adds the UA to its own (`Dart/3.13 (dart:io), …`), for
        // every platform on the default handshake; the server accepts it.
        {'path': '/chat', 'origin': ChzzkApi.origin, 'user-agent': endsWith(ChzzkApi.userAgent)},
      ]);
      expect(received.take(2).map((message) => message['cmd']), [100, 5101]);
      expect(received.first['cid'], 'N2l_uf');
      expect((received.first['bdy']! as Map<String, Object?>)['accTkn'], _token);
      final answer = jsonDecode(recorded.first.data as String) as Map<String, Object?>;
      expect(received[1]['sid'], (answer['bdy']! as Map<String, Object?>)['sid']);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      connection.heartbeat();
      await _until(() => received.any((message) => message['cmd'] == 0));
      await _wait(const Duration(milliseconds: 20));
      expect(_messages(events), hasLength(108), reason: 'the pongs show nothing');
      await connection.close();
    });
  });

  group('B-12 (M5.F): super chats, notices, retractions, the live-status check', () {
    final b12 = (_json('S16-synthetic/cases.json')! as Map<String, Object?>)['cases']! as List<Object?>;

    /// The messages of every frame of the S16 case whose name starts with
    /// [prefix], frame by frame.
    List<List<LiveMessage>> synthetic(String prefix) {
      final entry = b12.cast<Map<String, Object?>>().singleWhere((entry) => '${entry['name']}'.startsWith(prefix));
      return [
        for (final frame in (entry['frames']! as List<Object?>).cast<Map<String, Object?>>())
          ChzzkDanmakuProtocol.decode(frame['text'], receivedAt: _receivedAt).messages,
      ];
    }

    List<LiveMessage> decoded(String name) => [
      for (final frame in _received(name)) ...ChzzkDanmakuProtocol.decode(frame.data, receivedAt: _receivedAt).messages,
    ];

    LiveSuperChatMessage paid(LiveMessage message) {
      expect(message.type, LiveMessageType.superChat);
      expect(message.userName, 'SUPER_CHAT_MESSAGE', reason: "the envelope of 3.x's super chats");
      expect(message.message, 'SUPER_CHAT_MESSAGE');
      expect(message.color, LiveMessageColor.white);
      final data = message.data! as LiveSuperChatMessage;
      expect(data.messageId, message.messageId);
      expect(data.backgroundColor, isEmpty, reason: 'the site colours donations in its style sheet');
      expect(data.backgroundBottomColor, isEmpty);
      return data;
    }

    test("a donation is a super chat: S11's named donation, field by field", () {
      final message = decoded('S11-recent').singleWhere(
        (message) => message.type == LiveMessageType.superChat && paid(message).message.startsWith('이번주 토요일'),
      );
      final data = paid(message);
      final at = DateTime.fromMillisecondsSinceEpoch(1790632655370);
      expect(message.userId, '97faaf557acce48371affa77236380eb');
      expect(message.messageId, '97faaf557acce48371affa77236380eb:1790632655370');
      expect(message.sentAt, at);
      expect(data.userName, '观众115');
      expect(data.face, isEmpty, reason: 'the recorded profile has no image');
      expect(data.message, '이번주 토요일 콘서트에 가는데 넌 집에서 데이터쪼가리나 잡으세요라~');
      expect(data.price, 1000);
      expect(data.priceText, '1,000 치즈');
      expect(data.startTime, at);
      expect(data.endTime, at.add(const Duration(minutes: 1)));
    });

    test("the site's amount tiers give 1, 2, 5, 30 and 60 minutes; amounts are written as the site writes them", () {
      final messages = synthetic("donations at the site's amount tiers").single;
      expect(messages.map((message) => paid(message).priceText), [
        '1 치즈',
        '9,999 치즈',
        '10,000 치즈',
        '99,999 치즈',
        '100,000 치즈',
        '499,999 치즈',
        '500,000 치즈',
        '999,999 치즈',
        '1,000,000 치즈',
        '1,234,567 치즈',
      ]);
      expect(messages.map((message) => paid(message).endTime.difference(paid(message).startTime).inMinutes), [
        1,
        1,
        2,
        2,
        5,
        5,
        30,
        30,
        60,
        60,
      ]);
      expect(messages.map((message) => paid(message).price), [
        1,
        9999,
        10000,
        99999,
        100000,
        499999,
        500000,
        999999,
        1000000,
        1234567,
      ]);
      expect(ChzzkDanmakuProtocol.superChatDuration(0), const Duration(minutes: 1));
      expect(ChzzkDanmakuProtocol.cheeseText(0), '0 치즈');
    });

    test('donations with odd fields: text amounts, negative or missing amounts, no time, faces, broken extras', () {
      final frames = synthetic('donations with odd fields');
      expect(frames.map((messages) => messages.length), [1, 1, 1, 0, 1, 1, 1, 1]);
      expect(paid(frames[0].single).price, 2000);
      expect(paid(frames[0].single).priceText, '2,000 치즈');
      for (final index in [1, 2, 7]) {
        final data = paid(frames[index].single);
        expect((data.price, data.priceText), (0, ''), reason: '$index');
        expect(data.endTime.difference(data.startTime), const Duration(minutes: 1));
      }
      expect(paid(frames[1].single).message, '음수 금액');
      expect(paid(frames[7].single).userName, '깨진', reason: 'broken extras: not anonymous, no amount');
      final untimed = frames[4].single;
      expect(untimed.sentAt, isNull);
      expect(untimed.messageId, isEmpty);
      expect(paid(untimed).startTime, _receivedAt, reason: 'no time: when it was received');
      expect(paid(untimed).endTime, _receivedAt.add(const Duration(minutes: 1)));
      expect(paid(frames[5].single).face, startsWith('https://nng-phinf.pstatic.net/'));
      expect(paid(frames[6].single).face, isEmpty, reason: 'not an image of NAVER');
    });

    test('S13: mission and mission-participation donations are anonymous super chats; the restriction line for '
        'managers shows nothing; the pinned notices say whose line is pinned', () {
      final answers = [
        for (final frame in _received('S13-recent'))
          ChzzkDanmakuProtocol.decode(frame.data, receivedAt: _receivedAt).messages,
      ];
      final notices = [
        for (final answer in answers)
          [
            for (final message in answer)
              if (message.type == LiveMessageType.notice) message,
          ],
      ];
      expect(notices.map((notices) => notices.single.message), [
        '덕 개 置顶了消息：타 스트리머 언급 금지, 훈수 금지, 뻐꾸기 금지, 빨간 약 금지',
        '인간젤리 置顶了 观众72 的消息：효니 탑 보고싶다',
        '观众92 置顶了消息：도방 허용',
      ]);
      final pinned = notices[1].single;
      expect(pinned.data, LiveNoticeKind.system);
      expect(pinned.userName, '观众72', reason: "the pinned line's author");
      expect(pinned.userId, '47f63ab9dbf76b8d1d5c9920be5dc6fb');
      expect(pinned.messageId, 'notice:47f63ab9dbf76b8d1d5c9920be5dc6fb:1790777396491');
      expect(pinned.sentAt, isNull, reason: 'the time is when the line was written, not pinned');
      expect(answers.map((answer) => answer.last.type), everyElement(LiveMessageType.notice), reason: 'last');
      expect(
        [for (final answer in answers) ...answer].where((message) => message.message.startsWith('채팅 참여가 제한')),
        isEmpty,
        reason: 'extras.visibleRoles: for the streamer and managers only',
      );
      final donations = [
        for (final message in answers[2])
          if (message.type == LiveMessageType.superChat) paid(message),
      ];
      expect(donations.map((data) => (data.userName, data.message, data.priceText)), [
        ('익명의 후원자', '양주 유니폼얼마나팔렷는지 솔직히 궁금합니다..', '1,000 치즈'),
        ('익명의 후원자', 'ercc 진출시', '40,000 치즈'),
        ('익명의 후원자', '막라 1등 맞추기', '20,000 치즈'),
      ]);
      expect(donations.map((data) => data.endTime.difference(data.startTime).inMinutes), [1, 2, 2]);
      expect(donations.map((data) => data.messageId), [
        'anonymous:1790781877882',
        'anonymous:1790781881959',
        'anonymous:1790781904031',
      ]);
    });

    test('S14: each 94008 of a restriction retracts one line by user and time, the lines shown before included; '
        'restriction events and lines show nothing', () {
      final messages = decoded('S14-live');
      const restricted = '8a910497bc63a4b6c3068c48aee0a250';
      final shown = [
        for (final message in messages)
          if (message.type == LiveMessageType.chat && message.userId == restricted) message.messageId,
      ];
      expect(shown, hasLength(4), reason: 'one in the recent chat, three pushed live');
      final retracted = [
        for (final message in messages)
          if (message.type == LiveMessageType.retraction) (message.data! as LiveRetraction).messageId,
      ];
      expect(retracted, hasLength(27), reason: '1 clean-bot blind, 6 + 20 lines hidden by two restrictions');
      expect(retracted.where((id) => id!.startsWith('$restricted:')), hasLength(20));
      expect(shown, everyElement(isIn(retracted)));
      expect(
        messages.where((message) => message.type == LiveMessageType.retraction),
        everyElement(
          isA<LiveMessage>()
              .having((message) => message.messageId, 'messageId', isEmpty)
              .having((message) => message.sentAt, 'sentAt', isNull)
              .having((message) => message.userId, 'userId', isEmpty),
        ),
      );
      expect(messages.where((message) => message.message.startsWith('채팅 참여가 제한')), isEmpty);
      final donation = paid(messages.singleWhere((message) => message.type == LiveMessageType.superChat));
      expect((donation.userName, donation.message, donation.price), ('익명의 후원자', 'EMS 도 한명 섭외?', 1000));
      expect(
        messages.singleWhere((message) => message.type == LiveMessageType.notice).message,
        startsWith('观众134 置顶了消息：타스 비하'),
      );
    });

    test('S15: an anonymous gift of subscriptions to two viewers is two notices; the gift events show nothing', () {
      final frames = [
        for (final frame in _received('S15-live'))
          (frame.index, ChzzkDanmakuProtocol.decode(frame.data, receivedAt: _receivedAt).messages),
      ];
      final gifts = [
        for (final (_, messages) in frames)
          for (final message in messages)
            if (message.type == LiveMessageType.notice && message.data == LiveNoticeKind.subscription) _notice(message),
      ];
      expect(gifts, [
        _noticeOf(
          '익명의 후원자 向 观众213 赠送了「치코」订阅券',
          id: 'anonymous:1790782707028',
          kind: LiveNoticeKind.subscription,
          sentAt: 1790782707028,
          userName: '익명의 후원자',
        ),
        _noticeOf(
          '익명의 후원자 向 观众154 赠送了「치코」订阅券',
          id: 'anonymous:1790782707112',
          kind: LiveNoticeKind.subscription,
          sentAt: 1790782707112,
          userName: '익명의 후원자',
        ),
      ]);
      for (final (index, messages) in frames) {
        if ((_frames('S15-live')[index].data as String).contains('"cmd":93006')) {
          expect(messages, isEmpty, reason: 'frame $index');
        }
      }
    });

    test('S16: subscription gifts to the channel and to viewers, named and anonymous; broken ones', () {
      final frames = synthetic('subscription gifts');
      expect(frames.map((messages) => messages.map((message) => message.message).toList()), [
        ['선물왕 向频道赠送了 5 张「팬」订阅券'],
        ['익명의 후원자 向频道赠送了 2 张「치코」订阅券'],
        ['보내는이 向 받는이 赠送了「팬」订阅券'],
        ['익명의 후원자 向 13 파스텔 赠送了「치코」订阅券'],
        ['빈선물 向频道赠送了订阅券'],
        ['종류없음 赠送了「팬」订阅券'],
        <String>[],
        ['깨진선물 赠送了订阅券'],
        ['익명의 후원자 向频道赠送了 3 张「팬」订阅券'],
      ]);
      expect(frames[0].single.userId, _user(80));
      expect(frames[0].single.messageId, '${_user(80)}:${_t + 80}');
      expect(frames[1].single.userId, isEmpty);
      expect(frames[1].single.messageId, 'anonymous:${_t + 81}');
      expect(
        [for (final messages in frames) ...messages].map((message) => (message.type, message.data)),
        everyElement((LiveMessageType.notice, LiveNoticeKind.subscription)),
      );
    });

    test('S16: system lines are notices of their title and description; for managers, blank or blinded: nothing', () {
      final frames = synthetic('system lines');
      expect(frames.map((messages) => messages.map(_notice).toList()), [
        [_noticeOf('이모티콘 모드 OFF：이제 텍스트도 전송할 수 있어요.', id: 'SYSTEM_MESSAGE:${_t + 90}', sentAt: _t + 90)],
        [_noticeOf('팔로워 전용 모드 ON', id: 'SYSTEM_MESSAGE:${_t + 91}', sentAt: _t + 91)],
        [_noticeOf('설명만 있는 줄', id: 'SYSTEM_MESSAGE:${_t + 92}', sentAt: _t + 92)],
        <Object?>[],
        [_noticeOf('역할 목록 비어 있음', id: 'SYSTEM_MESSAGE:${_t + 94}', sentAt: _t + 94)],
        <Object?>[],
        <Object?>[],
      ]);
    });

    test('S16: pinned notices by their author, by someone else, without a profile; unpinned or broken: nothing', () {
      final frames = synthetic('pinned notices');
      expect(frames.map((messages) => messages.map(_notice).toList()), [
        [
          _noticeOf(
            '스트리머 置顶了消息：방송 규칙입니다',
            id: 'notice:${_user(100)}:${_t + 100}',
            userId: _user(100),
            userName: '스트리머',
          ),
        ],
        [
          _noticeOf(
            '매니저 置顶了 시청자101 的消息：고정된 시청자 채팅',
            id: 'notice:${_user(101)}:${_t + 101}',
            userId: _user(101),
            userName: '시청자101',
          ),
        ],
        [_noticeOf('置顶消息：프로필 없는 공지', id: 'notice:${_user(103)}:${_t + 103}', userId: _user(103))],
        <Object?>[],
        [_noticeOf('매니저 置顶了消息：최근 채팅의 공지', id: 'notice:${_user(105)}:${_t + 105}', userId: _user(105), userName: '매니저')],
        <Object?>[],
        <Object?>[],
        <Object?>[],
      ]);
    });

    test('S16: blinds retract by user and time; CANCEL, a missing user or time, a body not an object: nothing', () {
      final frames = synthetic('blinds (94008)');
      expect(frames.map((messages) => [for (final message in messages) message.data]), [
        [LiveRetraction.message('${_user(110)}:${_t + 110}')],
        [LiveRetraction.message('${_user(111)}:${_t + 111}')],
        [LiveRetraction.message('${_user(112)}:${_t - 3600000}')],
        <Object?>[],
        [const LiveRetraction.message('anonymous:${_t + 114}')],
        <Object?>[],
        <Object?>[],
        [LiveRetraction.message('${_user(117)}:${_t + 117}')],
        <Object?>[],
      ]);
    });

    test("the live-status: S14's and S15's open lives name their chats; S17's closed live and bad answers none", () {
      for (final name in ['S14-live', 'S15-live']) {
        final keys = _meta(name)['danmakuKeys']! as Map<String, Object?>;
        final status = _frames(name).first;
        expect(Uri.parse(status.url!), ChzzkDanmakuProtocol.liveStatusUrl(keys['channelId']! as String));
        expect(ChzzkDanmakuProtocol.liveChatChannel(jsonDecode(status.data as String)), keys['chatChannelId']);
      }
      expect(
        ChzzkDanmakuProtocol.liveStatusUrl(_channel).toString(),
        'https://api.chzzk.naver.com/polling/v3.1/channels/$_channel/live-status',
      );
      final closed = jsonDecode(File('$_root/S17-live-status-closed/body.json').readAsStringSync());
      expect(closed, containsPair('content', containsPair('status', 'CLOSE')));
      expect(ChzzkDanmakuProtocol.liveChatChannel(closed), isNull);
      for (final answer in <Object?>[
        {
          'code': 200,
          'content': {'status': 'CLOSE', 'chatChannelId': 'N2lxdt'},
        },
        {
          'code': 200,
          'content': {'status': 'OPEN', 'chatChannelId': null},
        },
        {
          'code': 200,
          'content': {'status': 'OPEN', 'chatChannelId': 'N2l/xdt'},
        },
        {
          'code': 200,
          'content': {'status': 'OPEN', 'chatChannelId': 7},
        },
        {
          'code': 9004,
          'content': {'status': 'OPEN', 'chatChannelId': 'N2lxdt'},
        },
        {'code': 200, 'content': null},
        'text',
        null,
      ]) {
        expect(ChzzkDanmakuProtocol.liveChatChannel(answer), isNull, reason: '$answer');
      }
    });

    test('the connection reports super chats, notices and retractions; a rejoin does not report the recent '
        "chat's super chats and notices again", () async {
      final held = <_HeldTimer>[];
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      final recent = _received('S13-recent')[2].data;
      final first = ChzzkDanmakuProtocol.decode(recent, receivedAt: _receivedAt).messages;
      final chat = first.where((message) => message.type == LiveMessageType.chat).length;
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single
          ..accept()
          ..incoming.add(recent)
          ..incoming.add('{"cmd":94008,"bdy":{"messageTime":1790781881959,"blindType":"BLIND","userId":"anonymous"}}');
        await _until(() => _messages(events).any((message) => message.type == LiveMessageType.retraction));
        await connector.channels.single.incoming.close();
        await _fire(held, const Duration(seconds: 1));
        await _until(() => connector.channels.length == 2);
        connector.channels.last
          ..accept(sid: 'sid-2')
          ..incoming.add(recent);
        await _until(() => _messages(events).length == first.length + 1 + chat);
        await _wait(const Duration(milliseconds: 20));
      });
      final messages = _messages(events);
      expect(messages, hasLength(first.length + 1 + chat));
      expect(first.map((message) => message.type).toSet(), {
        LiveMessageType.chat,
        LiveMessageType.superChat,
        LiveMessageType.notice,
      });
      expect(messages.sublist(0, first.length).map((message) => message.messageId), [
        for (final message in first) message.messageId,
      ]);
      expect(messages[first.length].data, const LiveRetraction.message('anonymous:1790781881959'));
      expect(messages.sublist(first.length + 1).map((message) => message.messageId), [
        for (final message in first)
          if (message.type == LiveMessageType.chat) message.messageId,
      ], reason: 'again: chat only (the duplicate gate sees it)');
      await connection.close();
    });

    test("a donation without a time starts at the connection's clock", () async {
      final connector = _Connector();
      final now = DateTime.fromMillisecondsSinceEpoch(1790782985534);
      final connection = ChzzkDanmakuConnection(
        http: _Http(),
        connector: connector.call,
        random: const _Pick(4),
        clock: () => now,
      );
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming.add(
        jsonEncode({
          'cmd': 93102,
          'bdy': [
            {
              'uid': 'anonymous',
              'msg': '시간 없음',
              'msgTypeCode': 10,
              'msgStatusType': 'NORMAL',
              'extras': '{"isAnonymous":true,"payAmount":10000}',
            },
          ],
        }),
      );
      await _until(() => _messages(events).isNotEmpty);
      final data = paid(_messages(events).single);
      expect((data.startTime, data.endTime), (now, now.add(const Duration(minutes: 2))));
      await connection.close();
    });

    test('after 3 min without a line pushed live the live-status is read once; the same chat: waits again', () async {
      final held = <_HeldTimer>[];
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        expect(_active(held, ChzzkDanmakuConnection.quietPeriod), isEmpty, reason: 'not before the join');
        connector.channels.single.accept();
        await _until(() => connection.isConnected);
        await _fire(held, const Duration(minutes: 3));
        await _until(() => http.statusRequests.length == 1);
        await _until(() => _active(held, const Duration(minutes: 3)).isNotEmpty);
        await _fire(held, const Duration(minutes: 3));
        await _until(() => http.statusRequests.length == 2);
        await _until(() => _active(held, const Duration(minutes: 3)).isNotEmpty);
      });
      final status = http.statusRequests.first;
      expect(status.site, SiteIds.chzzk);
      expect(status.url, ChzzkDanmakuProtocol.liveStatusUrl(_channel));
      expect(status.headers, ChzzkApi.headers);
      expect(status.followRedirects, isFalse);
      expect(status.timeout, const Duration(seconds: 5));
      expect(http.tokenRequests, hasLength(1));
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      await connection.close();
      expect(_active(held, const Duration(minutes: 3)), isEmpty, reason: 'close cancels the wait');
    });

    test('another chat channel in the live-status: its token, a new socket there, ready again; the old socket is '
        'ignored', () async {
      final held = <_HeldTimer>[];
      final http = _Http(statuses: [_statusAnswer(chat: 'N2lxdt')]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.accept();
        await _until(() => connection.isConnected);
        await _fire(held, const Duration(minutes: 3));
        await _until(() => connector.channels.length == 2);
        connector.channels.first.incoming.add(_chatFrame('옛 채팅'));
        connector.channels.last
          ..accept(sid: 'sid-2')
          ..incoming.add(_chatFrame('새 채팅', n: 2));
        await _until(() => _messages(events).isNotEmpty);
        await _wait(const Duration(milliseconds: 20));
      });
      expect(http.tokenRequests.map((request) => request.url), [
        ChzzkDanmakuProtocol.tokenUrl(_chat),
        ChzzkDanmakuProtocol.tokenUrl('N2lxdt'),
      ]);
      expect(http.routingRequests, hasLength(1), reason: 'the servers are kept');
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [
        ChzzkDanmakuProtocol.join('N2lxdt', _token),
        ChzzkDanmakuProtocol.recent('N2lxdt', 'sid-2'),
      ]);
      expect(connector.endpoints.map((uri) => uri.host), ['kr-ss5.chat.naver.com', 'kr-ss5.chat.naver.com']);
      expect(_messages(events).single.message, '새 채팅');
      expect(events.where((event) => event is! DanmakuReceived), [const DanmakuReady(), const DanmakuReady()]);
      await connection.close();
    });

    test(
      'a line pushed live restarts the wait, a pong or event does not; without a channel id there is no wait',
      () async {
        final held = <_HeldTimer>[];
        final http = _Http();
        final connector = _Connector();
        final connection = _connection(http, connector);
        await _heldTimers(held, () async {
          await connection.connect(_args);
          final channel = connector.channels.single..accept();
          await _until(() => _active(held, const Duration(minutes: 3)).isNotEmpty);
          final first = _active(held, const Duration(minutes: 3)).single;
          channel
            ..incoming.add('{"ver":"2","cmd":10000}')
            ..incoming.add('{"cmd":93006,"bdy":{"type":"LIVE_MID_ROLL_AD"}}');
          await _wait(const Duration(milliseconds: 20));
          expect(_active(held, const Duration(minutes: 3)).single, same(first));
          channel.incoming.add(_chatFrame('살아 있음'));
          await _until(() => !first.isActive);
          expect(_active(held, const Duration(minutes: 3)), hasLength(1));
          await connection.close();
          final quiet = _Http();
          final other = _Connector();
          final ownerless = _connection(quiet, other);
          await ownerless.connect(const ChzzkDanmakuArgs(channelId: '', chatChannelId: _chat));
          other.channels.single
            ..accept()
            ..incoming.add(_chatFrame('주인 없음'));
          await _until(() => ownerless.isConnected);
          await _wait(const Duration(milliseconds: 20));
          expect(_active(held, const Duration(minutes: 3)), isEmpty);
          await ownerless.close();
        });
        expect(http.statusRequests, isEmpty);
      },
    );

    test('a failed, closed or empty live-status, or no token for the new chat: the socket stays and the wait '
        'starts again', () async {
      final held = <_HeldTimer>[];
      final http = _Http(
        statuses: [
          _statusAnswer(status: 503, body: ''),
          _statusAnswer(body: File('$_root/S17-live-status-closed/body.json').readAsStringSync()),
          const TransportFailure(SiteIds.chzzk, TransportReason.timeout),
          _statusAnswer(chat: 'N2lxdt'),
        ],
        tokens: [
          _tokenAnswer(),
          _tokenAnswer(status: 500, body: '{"code":50001,"content":null}'),
        ],
      );
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.accept();
        await _until(() => connection.isConnected);
        for (var round = 1; round <= 4; round++) {
          await _fire(held, const Duration(minutes: 3));
          await _until(() => http.statusRequests.length == round);
          if (round == 4) {
            await _fire(held, const Duration(milliseconds: 500));
            await _fire(held, const Duration(seconds: 1));
          }
          await _until(() => _active(held, const Duration(minutes: 3)).isNotEmpty);
        }
      });
      expect(http.tokenRequests.map((request) => request.url.queryParameters['channelId']), [
        _chat,
        'N2lxdt',
        'N2lxdt',
        'N2lxdt',
      ]);
      expect(connector.channels, hasLength(1));
      expect(connector.channels.single.closed, isFalse);
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('close while the live-status is asked: nothing moves, nothing is reported', () async {
      final held = <_HeldTimer>[];
      final hold = Completer<void>();
      final http = _Http(statuses: [_Held(hold, _statusAnswer(chat: 'N2lxdt'))]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _heldTimers(held, () async {
        await connection.connect(_args);
        connector.channels.single.accept();
        await _until(() => connection.isConnected);
        await _fire(held, const Duration(minutes: 3));
        await _until(() => http.statusRequests.length == 1);
        await connection.close();
        hold.complete();
        await _wait(const Duration(milliseconds: 20));
      });
      expect(http.statusRequests.single.cancel!.isCancelled, isTrue);
      expect(http.tokenRequests, hasLength(1));
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
    });
  });
}
