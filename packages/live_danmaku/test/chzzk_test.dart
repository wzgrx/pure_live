// CHZZK danmaku (docs/modules/M5.16-chzzk.md): the protocol and the connection
// against the archived v4's output for the recordings (S09-live, S10-live,
// S11-recent) and the synthetic frames (S12-synthetic), written by
// fixtures/chzzk/danmaku/v4_expected.dart.
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

/// A message in the projection v4_expected.dart writes for v4's chat. v4
/// prefixed message ids with `chzzk:`; the new ids are the platform's own
/// (difference 1), so the projection adds the prefix back.
Map<String, Object?> _asV4(LiveMessage message) {
  expect(message.type, LiveMessageType.chat);
  expect(message.color, LiveMessageColor.white);
  return {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : 'chzzk:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
  };
}

/// The new reading of one frame in v4's shape: whether the join was accepted
/// or refused, what the connection sends back (the pong, the recent-chat
/// request), the messages.
Map<String, Object?> _readAsV4(Object data, {required String chat}) {
  final frame = ChzzkDanmakuProtocol.decode(data);
  return {
    'joined': frame.joined ?? false,
    'rejected': frame.joined == false,
    'replies': [
      if (frame.ping) jsonDecode(ChzzkDanmakuProtocol.pong),
      if ((frame.joined ?? false) && frame.sessionId.isNotEmpty)
        jsonDecode(ChzzkDanmakuProtocol.recent(chat, frame.sessionId)),
    ],
    'events': frame.messages.map(_asV4).toList(),
  };
}

/// v4's reading with the differences every frame shares: member counts are
/// not an audience (difference 2), donations are no gifts (difference 3),
/// an anonymous donor has the site's name and no user in its id
/// (difference 4).
Map<String, Object?> _shared(Map<String, Object?> v4) => {
  ...v4,
  'events': [
    for (final event in (v4['events']! as List<Object?>).cast<Map<String, Object?>>())
      if (event['kind'] == 'chat')
        if (event['userName'] == '匿名' && event['userId'] == '')
          {
            ...event,
            'userName': ChzzkDanmakuProtocol.anonymousDonor,
            'id': event['sentAt'] == null ? null : 'chzzk:anonymous:${event['sentAt']}',
          }
        else
          event,
  ],
};

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
/// [_shared] (docs/modules/M5.16-chzzk.md, "与归档 v4 的差异"): v4's reading →
/// the new one, per case. Cases not listed read as v4 read them.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // Difference 6: the kind decides; v4 took any line whose extras carry
  // payAmount for a donation, a sticker included.
  'system lines, images, stickers, parties and shop purchases show nothing': (v4) {
    expect(_events(v4[2]).single, containsPair('text', '스티커 후원'));
    return [
      v4[0],
      v4[1],
      {..._reading(v4[2]), 'events': const <Object?>[]},
    ];
  },
  // Difference 5: a subscription's message is chat; v4 dropped it.
  'subscriptions with and without a message, a subscription gift': (v4) {
    expect(_events(v4[0]), isEmpty);
    return [
      {
        ..._reading(v4[0]),
        'events': [_line('32개월 축하해 주세요', _user(9), _t + 9, name: '구독자')],
      },
      v4[1],
      v4[2],
    ];
  },
  // Difference 5 in the recent chat; difference 7: an answer whose retCode
  // is not 0 holds no chat (the site's SDK rejects it), v4 read its list.
  'the recent chat (15101): its field names; an answer that is not retCode 0': (v4) {
    final events = _events(v4[0]);
    expect(events.map((event) => event['text']), ['입장 전 채팅', '익명 후원']);
    expect(_events(v4[1]).single['text'], '보이면 안 됨');
    return [
      {
        ..._reading(v4[0]),
        'events': [...events, _line('구독 메시지', _user(23), _t + 23, name: '구독')],
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

/// Answers the token and routing requests: [tokens] and [routes] in turn
/// (the last one repeats); a [LiveResponse] is returned, an exception thrown.
final class _Http implements LiveHttp {
  new({List<Object>? tokens, List<Object>? routes, this.hold})
    : tokens = tokens ?? [_tokenAnswer()],
      routes = routes ?? [_routingAnswer()];

  final List<Object> tokens;
  final List<Object> routes;

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

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final routing = request.url.host == 'routing.chat.naver.com';
    final answers = routing ? routes : tokens;
    final count = routing ? routingRequests.length : tokenRequests.length;
    final answer = answers[min(count, answers.length) - 1];
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

LiveResponse _tokenAnswer({int status = 200, String? body}) => LiveResponse(
  status: status,
  url: ChzzkDanmakuProtocol.tokenUrl(_chat),
  bytes: utf8.encode(body ?? File('../../fixtures/chzzk/S08-chat-token/body.json').readAsStringSync()),
);

LiveResponse _routingAnswer({int status = 200, String? body}) =>
    LiveResponse(status: status, url: ChzzkDanmakuProtocol.routingUrl, bytes: utf8.encode(body ?? _routing));

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
      for (final name in ['S09-live', 'S10-live', 'S11-recent']) {
        for (final frame in _frames(name)) {
          if (frame.url != null || frame.dir != 'in') continue;
          expect(
            ChzzkDanmakuProtocol.decode(frame.data).messages.map((message) => message.type),
            everyElement(LiveMessageType.chat),
          );
        }
      }
      final capability = AudiencePlatformCapability.of(SiteIds.chzzk);
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomList);
      expect(capability.hasPopularity, isFalse);
    });

    test('S11: donations (named, anonymous, video) and a subscription are chat; clean-bot lines are not', () {
      final answers = [for (final frame in _received('S11-recent')) ChzzkDanmakuProtocol.decode(frame.data)];
      final all = [for (final answer in answers) ...answer.messages];
      final anonymous = all.where((message) => message.userName == ChzzkDanmakuProtocol.anonymousDonor).toList();
      expect(ChzzkDanmakuProtocol.anonymousDonor, '익명의 후원자', reason: "the site's name for anonymous donors");
      expect(anonymous, hasLength(6));
      expect(anonymous.map((message) => message.userId), everyElement(isEmpty));
      expect(anonymous.map((message) => message.messageId), everyElement(startsWith('anonymous:')));
      expect(anonymous.last.message, '싸이(PSY) - 예술이야 [가사/Lyrics]', reason: 'a video donation names its video');
      final named = all.singleWhere((message) => message.message.startsWith('이번주 토요일'));
      expect(named.userName, '观众115');
      expect(named.userId, '97faaf557acce48371affa77236380eb');
      final subscription = answers[2].messages.singleWhere((message) => message.message == '나이스한 아침이야');
      expect(subscription.userName, '观众132');
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
      test('$name: every received frame reads as v4 read it, without member counts', () {
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        final v4 = _v4Frames(name);
        final frames = _received(name);
        expect(v4.keys, [for (final frame in frames) frame.index]);
        for (final frame in frames) {
          expect(_readAsV4(frame.data, chat: chat), _shared(v4[frame.index]!), reason: 'frame ${frame.index}');
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

    test('S10-live: the system line, the chat-mode event and the blind notice show nothing; the pongs neither', () {
      final frames = _received('S10-live');
      final texts = [for (final frame in frames) frame.data as String];
      for (final cmd in ['"cmd":93006', '"cmd":94008', '"cmd":10000']) {
        final matching = [
          for (final (index, text) in texts.indexed)
            if (text.contains(cmd)) index,
        ];
        expect(matching, isNotEmpty, reason: cmd);
        for (final index in matching) {
          expect(ChzzkDanmakuProtocol.decode(texts[index]).messages, isEmpty, reason: cmd);
        }
      }
      final system = texts.singleWhere((text) => text.contains('"msgTypeCode":30'));
      expect(system, contains('"cmd":93102'));
      expect(ChzzkDanmakuProtocol.decode(system).messages, isEmpty);
      expect([for (final text in texts) ...ChzzkDanmakuProtocol.decode(text).messages], hasLength(106));
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
          expect(extra.single, containsPair('text', '나이스한 아침이야'));
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

    for (final (name, count) in const [('S09-live', 125), ('S10-live', 106)]) {
      test('replaying $name reports what v4 read, in order, and asks the recent chat of its session', () async {
        final chat = (_meta(name)['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
        final connector = _Connector();
        final connection = _connection(_Http(), connector);
        final events = _record(connection);
        await connection.connect(ChzzkDanmakuArgs(channelId: _channel, chatChannelId: chat));
        final channel = connector.channels.single;
        final expected = <Object?>[];
        for (final frame in _received(name)) {
          channel.incoming.add(frame.data);
          expected.addAll(_events(_shared(_v4Frames(name)[frame.index]!)));
        }
        expect(expected, hasLength(count));
        await _until(() => _messages(events).length == count);
        await _wait(const Duration(milliseconds: 10));
        expect(_messages(events).map(_asV4), expected);
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
      await _until(() => _messages(events).length == 106);
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
      expect(_messages(events), hasLength(106), reason: 'the pongs show nothing');
      await connection.close();
    });
  });
}
