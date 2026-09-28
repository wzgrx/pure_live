// Picarto danmaku (docs/modules/M5.10-picarto.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S07-live, S09-keepalive, S10-token-refused) and the synthetic frames
// (S11-synthetic), written by fixtures/picarto/danmaku/v4_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/picarto/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, String? url, String text});

/// The frames of a recorded session, in order.
List<_Frame> _frames(String name) {
  var index = 0;
  return [
    for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
      if (jsonDecode(line)
          case {'dir': final String dir, 'text': final String text} && final Map<String, Object?> frame)
        (index: index++, dir: dir, url: frame['url'] as String?, text: text),
  ];
}

/// The archived v4's output for a recorded session.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// v4's events per incoming frame of a session, by frame index.
Map<int, Object?> _v4Frames(String name) => {
  for (final frame in _v4(name)['frames']! as List<Object?>)
    if (frame case {'frame': final int index, 'events': final Object? events}) index: events,
};

final Map<String, Object?> _cases = _json('S11-synthetic/cases.json')! as Map<String, Object?>;

final int _channelId = _cases['channelId']! as int;

/// The v4 output for every synthetic case: a list per frame, or
/// {"throws": …} where v4's decode threw.
final Map<String, Object?> _v4Cases = _v4('S11-synthetic')['cases']! as Map<String, Object?>;

const PicartoDanmakuArgs _args = PicartoDanmakuArgs(channelName: 'allatir', channelId: 942670);

/// A frame of cases.json as the server sends it.
Object _serverFrame(Object? frame) => switch (frame) {
  final String text => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

String _text(Object frame) => frame is String ? frame : utf8.decode(frame as List<int>, allowMalformed: true);

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `picarto:`; the new ids are the platform's own
/// (difference 1), so the projection adds the prefix back.
Map<String, Object?> _asV4(LiveMessage message) {
  if (message.type == LiveMessageType.online) {
    final data = message.data! as LiveAudienceUpdate;
    expect(data.kind, LiveAudienceMetricKind.onlineViewers);
    return {'kind': 'online', 'audience': 'online', 'value': data.value};
  }
  expect(message.type, LiveMessageType.chat);
  return {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : 'picarto:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'color': message.color.toString(),
  };
}

List<Map<String, Object?>> _decodedAsV4(Object frame, {int? channelId}) => [
  for (final message in PicartoDanmakuProtocol.decode(_text(frame), channelId: channelId ?? _channelId).messages)
    _asV4(message),
];

String _answer(String token) => jsonEncode({
  'data': {
    'generateJwtToken': {'key': token},
  },
});

const String _tokenA = 'aaaa.bbbb.cccc';
const String _tokenB = 'dddd.eeee.ffff';
const String _tokenC = 'gggg.hhhh.iiii';
const String _tokenD = 'jjjj.kkkk.llll';

const String _refusal = '{"success":false,"code":"JWT_TOKEN"}';
const String _pong = '{"success":true,"code":"PONG"}';

/// Answers token requests in turn (the last one repeats): a `String` is a
/// 200 body, a [LiveResponse] is returned, anything else is thrown.
final class _TokenHttp implements LiveHttp {
  new(this.answers, {this.hold});

  final List<Object> answers;

  /// Keeps every request pending until it completes.
  final Completer<void>? hold;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final answer = answers[min(requests.length - 1, answers.length - 1)];
    await hold?.future;
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    return switch (answer) {
      final String body => LiveResponse(status: 200, bytes: utf8.encode(body), url: request.url),
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
}

/// Hands out fake channels and records every handshake.
final class _Connector {
  new({this.fail});

  /// Thrown for every handshake, with the endpoint.
  final Exception Function(Uri endpoint)? fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<Iterable<String>?> protocols = [];
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
    this.protocols.add(protocols);
    routes.add(route);
    final failure = fail;
    if (failure != null) throw failure(endpoint);
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

PicartoDanmakuConnection _connection(_TokenHttp http, _Connector connector, {ProxyPolicy? proxy}) =>
    PicartoDanmakuConnection(http: http, connector: connector.call, proxy: proxy ?? const FixedProxyPolicy());

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

/// Runs [body] with every one-shot timer of 100 ms or more (token retries,
/// reconnect backoff) recorded into [delays] and fired at once.
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

/// Runs [body] with every timer of a second or more held back, so no
/// reconnect can happen.
Future<void> _withoutBackoff(Future<void> Function() body) async {
  final held = <Timer>[];
  try {
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration < const Duration(seconds: 1)) return parent.createTimer(zone, duration, callback);
          final timer = parent.createTimer(zone, const Duration(days: 1), callback);
          held.add(timer);
          return timer;
        },
      ),
    );
  } finally {
    for (final timer in held) {
      timer.cancel();
    }
  }
}

/// The differences of the new decoder from v4 in the synthetic cases
/// (docs/modules/M5.10-picarto.md, "与归档 v4 的差异"): v4's output → the new
/// output, per case. Cases not listed decode as v4 did.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // Difference 2: `_id` stands in for a missing `id`, as the site reads it.
  'the message id: id, else _id, else none': (v4) => [
    [
      {..._chatAt(v4, 0, 0), 'id': 'picarto:5f0000000000000000000001'},
      _chatAt(v4, 0, 1),
      _chatAt(v4, 0, 2),
    ],
  ],
  // Difference 3: a time out of range loses only its time; v4 lost the
  // frame (RangeError).
  'a time out of range': (v4) {
    expect(v4, [
      {'throws': 'RangeError'},
    ]);
    return [
      [
        _chat('before', 'aaaaaaaa-0000-11f1-8000-000000000015'),
        _chat('far future', 'aaaaaaaa-0000-11f1-8000-000000000016', sentAt: null),
        _chat('after', 'aaaaaaaa-0000-11f1-8000-000000000017'),
      ],
    ];
  },
  // Difference 4: colours as the site's CSS reads them: `f80` is #ff8800
  // (v4 #000f80); eight digits are not a colour (v4 took them as ARGB).
  'name colours: 6 digits in either case, #, the 3-digit CSS form; anything else is white': (v4) => [
    [
      for (final chat in (v4.single! as List<Object?>).cast<Map<String, Object?>>())
        switch (chat['text']) {
          'short' => {...chat, 'color': '#ff8800'},
          'eight digits' => {...chat, 'color': '#ffffff'},
          _ => chat,
        },
    ],
  ],
  // Difference 5: a colour that is not text is white; v4 lost the frame
  // (TypeError).
  'a colour that is a number': (v4) {
    expect(v4, [
      {'throws': 'TypeError'},
    ]);
    return [
      [
        _chat('a number', 'aaaaaaaa-0000-11f1-8000-000000000030'),
        _chat('after it', 'aaaaaaaa-0000-11f1-8000-000000000032', color: '#2f5ea9'),
      ],
    ];
  },
  // Difference 6: user fields that are neither text nor numbers are empty
  // (v4 printed them).
  'user fields: numbers, missing, and other types': (v4) => [
    [
      _chatAt(v4, 0, 0),
      _chatAt(v4, 0, 1),
      {..._chatAt(v4, 0, 2), 'userId': '', 'userName': ''},
    ],
  ],
  // Difference 7: lines of another type (`system`, `w`) are not chat.
  'lines of another type in a chat frame, and lines that are not objects': (v4) => [
    [
      for (final chat in (v4.single! as List<Object?>).cast<Map<String, Object?>>())
        if (chat['text'] != 'system line' && chat['text'] != 'whisper line') chat,
    ],
  ],
  // Difference 8: history pages are skipped, as the site's client skips
  // them.
  'a page of history (paginated or p) is not live chat': (v4) => [const <Object?>[], const <Object?>[], v4[2]],
  // Difference 9: `type`/`messages` and `t`/`m` are read alike, as the
  // site's client reads them.
  'the other spellings the site reads: type and messages': (v4) {
    expect(v4, [const <Object?>[], const <Object?>[]]);
    return [
      [_chat('spelled out', 'aaaaaaaa-0000-11f1-8000-000000000064')],
      [
        {'kind': 'online', 'audience': 'online', 'value': 61},
      ],
    ];
  },
  // Difference 10: another channel's state is not this room's audience.
  "stream: another channel's state, no id, an id as text": (v4) => [const <Object?>[], v4[1], v4[2]],
};

Map<String, Object?> _chatAt(List<Object?> v4, int frame, int index) =>
    Map.of((v4[frame]! as List<Object?>)[index]! as Map<String, Object?>);

/// A synthetic chat line as the v4 projection shows it.
Map<String, Object?> _chat(String text, String id, {int? sentAt = 1790531380528, String color = '#ffffff'}) => {
  'kind': 'chat',
  'id': 'picarto:$id',
  'sentAt': sentAt,
  'userId': '7300001',
  'userName': 'ViewerOne',
  'text': text,
  'color': color,
};

void main() {
  group('protocol', () {
    test("the token request is v4's and the recorded one (S06-chat-token)", () {
      final v4 = _v4('S07-live')['connector']! as Map<String, Object?>;
      final request = v4['tokenRequest']! as Map<String, Object?>;
      expect(PicartoDanmakuProtocol.tokenEndpoint.toString(), request['url']);
      expect(PicartoDanmakuProtocol.tokenBody('allatir'), request['body']);
      final recorded = _json('../S06-chat-token/meta.json')! as Map<String, Object?>;
      final sent = recorded['request']! as Map<String, Object?>;
      expect(PicartoDanmakuProtocol.tokenEndpoint.toString(), sent['url']);
      expect(PicartoDanmakuProtocol.tokenBody('allatir'), jsonDecode(sent['body']! as String));
      // v4 sent origin, UA, referer and the JSON type; the new request sends
      // PicartoApi.headers, the same three, and LiveRequest.json adds the type.
      final v4Headers = (request['headers']! as Map<String, Object?>)..remove('content-type');
      expect(PicartoApi.headers, v4Headers);
    });

    test('tokens are read as v4 read them; only JWTs (three base64url parts) are taken', () {
      for (final name in ['S07-live', 'S09-keepalive']) {
        final answer = _frames(name).firstWhere((frame) => frame.url != null);
        expect(answer.url, PicartoDanmakuProtocol.tokenEndpoint.toString());
        expect(PicartoDanmakuProtocol.token(jsonDecode(answer.text)), _v4(name)['token']);
      }
      final recorded = jsonDecode(File('../../fixtures/picarto/S06-chat-token/body.json').readAsStringSync());
      expect(PicartoDanmakuProtocol.token(recorded), hasLength(529 - 41));
      expect(PicartoDanmakuProtocol.token(jsonDecode(_answer(_tokenA))), _tokenA);
      // An unknown channel (2026-09-28: {"key": null}) and other shapes.
      for (final answer in [
        '{"data":{"generateJwtToken":{"key":null}}}',
        '{"data":{"generateJwtToken":null}}',
        '{"data":null}',
        '{"errors":[{"message":"x"}]}',
        '[]',
        '"a.b.c"',
      ]) {
        expect(PicartoDanmakuProtocol.token(jsonDecode(answer)), isNull, reason: answer);
      }
      // v4 took any three dot-separated parts; the token goes into the path.
      for (final key in ['a.b', 'a.b.c.d', 'a..c', 'a/b.c.d?e', 'a.b.c#x', ' a.b.c']) {
        expect(PicartoDanmakuProtocol.token(jsonDecode(_answer(key))), isNull, reason: key);
      }
    });

    test("the socket's address and headers are v4's and the recorded handshakes'", () {
      for (final name in ['S07-live', 'S09-keepalive']) {
        final v4 = _v4(name);
        final token = v4['token']! as String;
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        expect(PicartoDanmakuProtocol.endpoint(token).toString(), v4['endpoint']);
        expect(PicartoDanmakuProtocol.endpoint(token).toString(), handshake['url']);
        expect(PicartoDanmakuProtocol.handshakeHeaders, handshake['headers']);
        expect(PicartoDanmakuProtocol.handshakeHeaders, (v4['connector']! as Map<String, Object?>)['handshakeHeaders']);
      }
    });

    test("the keep-alive is the site's ping, every 50 s; v4 sent nothing", () {
      final sent = [
        for (final frame in _frames('S09-keepalive'))
          if (frame.dir == 'out') frame.text,
      ];
      expect(sent, List.filled(3, PicartoDanmakuProtocol.heartbeat));
      expect(PicartoDanmakuProtocol.heartbeatInterval, const Duration(seconds: 50));
      final v4 = _v4('S07-live')['connector']! as Map<String, Object?>;
      expect(v4['heartbeat'], isNull);
      expect(v4['openFrames'], isEmpty);
      expect(_frames('S07-live').where((frame) => frame.dir == 'out'), isEmpty);
    });

    test('a chat line fills the message model', () {
      final message = PicartoDanmakuProtocol.chat({
        't': 'c',
        'u': '7300001',
        'n': 'ViewerOne',
        'm': ' hi ',
        'id': 'x-1',
        'd': 1790531380528,
        'k': '66AFFF',
      })!;
      expect(message.type, LiveMessageType.chat);
      expect(message.userName, 'ViewerOne');
      expect(message.userId, '7300001');
      expect(message.message, 'hi');
      expect(message.messageId, 'x-1');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790531380528));
      expect(message.color, const LiveMessageColor(0x66, 0xAF, 0xFF));
      expect(message.data, isNull);
      expect(message.isLocal, isFalse);
      expect([message.userLevel, message.fansLevel, message.fansName], ['', '', '']);
      final audience = PicartoDanmakuProtocol.audience({'id': 942670, 'viewers': 7}, channelId: 942670)!;
      expect(audience.type, LiveMessageType.online);
      expect(audience.message, '');
      expect(audience.userName, '');
      expect((audience.data! as LiveAudienceUpdate).kind, LiveAudienceMetricKind.onlineViewers);
      expect((audience.data! as LiveAudienceUpdate).value, 7);
    });
  });

  group('recorded frames against v4', () {
    test('S07-live: one chat line and the audience of six state frames, as v4 decoded them', () {
      final v4 = _v4Frames('S07-live');
      final frames = _frames('S07-live').where((frame) => frame.dir == 'in' && frame.url == null).toList();
      expect(frames.map((frame) => frame.index), v4.keys);
      for (final frame in frames) {
        expect(_decodedAsV4(frame.text), v4[frame.index], reason: 'frame ${frame.index}');
        expect(PicartoDanmakuProtocol.decode(frame.text, channelId: _channelId).tokenRefused, isFalse);
      }
      final chat = PicartoDanmakuProtocol.decode(_frames('S07-live')[5].text, channelId: _channelId).messages.single;
      expect(chat.messageId, 'd075e300-ba9b-11f1-8b7e-a3860776556d', reason: 'no picarto: prefix (difference 1)');
    });

    test('S09-keepalive: joins, leaves and answers to the keep-alive show nothing; the audience as v4', () {
      final v4 = _v4Frames('S09-keepalive');
      final frames = _frames('S09-keepalive').where((frame) => frame.dir == 'in' && frame.url == null).toList();
      expect(frames.map((frame) => frame.index), v4.keys);
      for (final frame in frames) {
        final decoded = PicartoDanmakuProtocol.decode(frame.text, channelId: _channelId);
        expect(decoded.messages.map(_asV4), v4[frame.index], reason: 'frame ${frame.index}');
        expect(decoded.tokenRefused, isFalse);
      }
      expect(frames.where((frame) => frame.text == _pong), hasLength(3));
    });

    test('S10-token-refused: every answer is a refusal; v4 read nothing in them', () {
      final v4 = _v4Frames('S10-token-refused');
      final frames = _frames('S10-token-refused').where((frame) => frame.dir == 'in').toList();
      expect(frames.map((frame) => frame.text), [_refusal, _refusal]);
      for (final frame in frames) {
        expect(v4[frame.index], isEmpty);
        final decoded = PicartoDanmakuProtocol.decode(frame.text, channelId: _channelId);
        expect(decoded.messages, isEmpty);
        expect(decoded.tokenRefused, isTrue);
      }
    });
  });

  group('synthetic frames (S11-synthetic) against v4', () {
    final cases = [
      for (final entry in _cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames}) (name: name, frames: frames),
    ];

    test('every case has v4 output, and every difference names a case', () {
      expect(_v4Cases.keys, cases.map((entry) => entry.name));
      expect(cases.map((entry) => entry.name), containsAll(_differences.keys));
    });

    for (final (:name, :frames) in cases) {
      test(name, () {
        final v4 = _v4Cases[name]! as List<Object?>;
        final expected = _differences[name]?.call(v4) ?? v4;
        final decoded = [for (final frame in frames) _decodedAsV4(_serverFrame(frame))];
        expect(decoded, expected);
        final refused = [
          for (final frame in frames)
            PicartoDanmakuProtocol.decode(_text(_serverFrame(frame)), channelId: _channelId).tokenRefused,
        ];
        expect(refused, [for (final frame in frames) frame == _refusal]);
      });
    }
  });

  group('connection', () {
    test('asks a token, opens its socket with the handshake headers and is ready without sending', () async {
      final http = ReplayHttp.fixtures('../../fixtures/picarto', ['S06-chat-token']);
      final connector = _Connector();
      final connection = PicartoDanmakuConnection(http: http, connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final request = http.requests.single;
      expect(request.site, SiteIds.picarto);
      expect(request.method, 'POST');
      expect(request.url, PicartoDanmakuProtocol.tokenEndpoint);
      expect(request.headers, {...PicartoApi.headers, 'content-type': 'application/json; charset=utf-8'});
      expect(jsonDecode(utf8.decode(request.body!)), PicartoDanmakuProtocol.tokenBody('allatir'));
      expect(request.timeout, PicartoDanmakuConnection.tokenTimeout);
      final recorded = jsonDecode(File('../../fixtures/picarto/S06-chat-token/body.json').readAsStringSync());
      expect(connector.endpoints, [PicartoDanmakuProtocol.endpoint(PicartoDanmakuProtocol.token(recorded)!)]);
      expect(connector.headers.single, PicartoDanmakuProtocol.handshakeHeaders);
      expect(connector.protocols.single, isNull);
      expect(connector.routes.single, isA<DirectRoute>());
      expect(connector.channels.single.sent, isEmpty);
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.connected);
      await connection.close();
    });

    test('the channel is trimmed; a blank one ends with connectionFailed and asks nothing', () async {
      final http = _TokenHttp([_answer(_tokenA)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(const PicartoDanmakuArgs(channelName: ' allatir ', channelId: 942670));
      expect(jsonDecode(utf8.decode(http.requests.single.body!)), PicartoDanmakuProtocol.tokenBody('allatir'));
      await connection.connect(const PicartoDanmakuArgs(channelName: '  ', channelId: 942670));
      expect(http.requests, hasLength(1));
      expect(connector.channels, hasLength(1));
      expect(
        events.last,
        isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed),
      );
      expect(connection.status, DanmakuStatus.closed);
    });

    test('the proxy policy routes the handshake', () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        _TokenHttp([_answer(_tokenA)]),
        connector,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.picarto: route}),
      );
      await connection.connect(_args);
      expect(connector.routes.single, route);
      await connection.close();
    });

    test('a token is asked three times, 0.5 s and 1 s apart; the third answer is used', () async {
      final delays = <Duration>[];
      final http = _TokenHttp([
        const TransportFailure(SiteIds.picarto, TransportReason.connect),
        LiveResponse(status: 503, bytes: utf8.encode('busy'), url: PicartoDanmakuProtocol.tokenEndpoint),
        _answer(_tokenA),
      ]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _fastTimers(delays, () => connection.connect(_args));
      expect(delays, [const Duration(milliseconds: 500), const Duration(seconds: 1)]);
      expect(http.requests, hasLength(3));
      expect(connector.endpoints, [PicartoDanmakuProtocol.endpoint(_tokenA)]);
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('no token after three answers ends with credentialsUnavailable and opens nothing', () async {
      for (final answers in <List<Object>>[
        ['{"data":{"generateJwtToken":{"key":null}}}'],
        ['not json'],
        [const TransportFailure(SiteIds.picarto, TransportReason.timeout)],
      ]) {
        final delays = <Duration>[];
        final http = _TokenHttp(answers);
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

    test('close while the token is asked: the request is cancelled, nothing opens or is reported', () async {
      final hold = Completer<void>();
      final http = _TokenHttp([_answer(_tokenA)], hold: hold);
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

    test('timing: 50 s keep-alive, max(3 × 50 s, 90 s) = 150 s silence limit, no join timer, 8 reconnects', () {
      final connection = PicartoDanmakuConnection(http: _TokenHttp([_answer(_tokenA)]));
      expect(connection.heartbeatInterval, const Duration(seconds: 50));
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 50));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives 150 s');
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends the keep-alive on its 50 s timer and on demand, as text', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 2);
          expect(sent.take(2), [PicartoDanmakuProtocol.heartbeat, PicartoDanmakuProtocol.heartbeat]);
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
      expect(periods, [const Duration(seconds: 50)]);
    });

    test('replaying S07-live and S09-keepalive reports what v4 decoded, in order; binary frames read alike', () async {
      final connector = _Connector();
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      final expected = <Object?>[];
      var binary = false;
      for (final name in ['S07-live', 'S09-keepalive']) {
        final v4 = _v4Frames(name);
        for (final frame in _frames(name)) {
          if (frame.dir != 'in' || frame.url != null) continue;
          channel.incoming.add((binary = !binary) ? utf8.encode(frame.text) : frame.text);
          expected.addAll(v4[frame.index]! as List<Object?>);
        }
      }
      expect(expected, hasLength(11));
      await _until(() => _messages(events).length == expected.length);
      expect(_messages(events).map(_asV4), expected);
      expect(channel.sent, isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await connection.close();
    });

    test("only this channel's state is its audience (the arguments' channel id)", () async {
      final connector = _Connector();
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector);
      final events = _record(connection);
      await connection.connect(const PicartoDanmakuArgs(channelName: 'OtherChannel', channelId: 122866));
      connector.channels.single.incoming
        ..add('{"type":"stream","messages":{"id":942670,"viewers":53}}')
        ..add('{"type":"stream","messages":{"id":122866,"viewers":34}}');
      await _until(() => _messages(events).isNotEmpty);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map(_asV4), [
        {'kind': 'online', 'audience': 'online', 'value': 34},
      ]);
      await connection.close();
    });

    test('a refused token is replaced and the socket reopened at once, without a notice', () async {
      final http = _TokenHttp([_answer(_tokenA), _answer(_tokenB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _withoutBackoff(() async {
        await connection.connect(_args);
        final first = connector.channels.single;
        // S10-token-refused: the refusal comes at once, and again for every
        // later frame.
        first.incoming
          ..add(_refusal)
          ..add(_refusal);
        await _until(() => connector.channels.length == 2 && connection.isConnected);
        expect(first.closed, isTrue);
        connector.channels.last.incoming.add(_frames('S07-live')[5].text);
        await _until(() => _messages(events).isNotEmpty);
      });
      expect(http.requests, hasLength(2));
      expect(connector.endpoints, [PicartoDanmakuProtocol.endpoint(_tokenA), PicartoDanmakuProtocol.endpoint(_tokenB)]);
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      expect(_messages(events).single.message, startsWith('You guys can say no'));
      await connection.close();
    });

    test('the fourth refusal in one connect ends with credentialsUnavailable', () async {
      final http = _TokenHttp([_answer(_tokenA), _answer(_tokenB), _answer(_tokenC), _answer(_tokenD)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _withoutBackoff(() async {
        await connection.connect(_args);
        for (var socket = 1; socket <= 4; socket++) {
          await _until(() => connector.channels.length == socket && connection.isConnected);
          connector.channels.last.incoming.add(_refusal);
        }
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(http.requests, hasLength(4));
      expect(connector.channels, hasLength(4));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable)
            .having((event) => event.detail, 'detail', 'Chat token refused'),
      );
      expect(events.whereType<DanmakuReady>(), hasLength(4));
      expect(connection.status, DanmakuStatus.closed);
    });

    test('a refused token without a new one ends with credentialsUnavailable', () async {
      final delays = <Duration>[];
      final http = _TokenHttp([_answer(_tokenA), const TransportFailure(SiteIds.picarto, TransportReason.connect)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        connector.channels.single.incoming.add(_refusal);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(http.requests, hasLength(4), reason: 'the first token, then three attempts');
      expect(connector.channels, hasLength(1));
      expect(connector.channels.single.closed, isTrue);
      expect(connection.isConnected, isFalse);
      expect(
        events.last,
        isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.credentialsUnavailable),
      );
    });

    test('refusals are counted per connect', () async {
      final http = _TokenHttp([_answer(_tokenA), _answer(_tokenB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      await _withoutBackoff(() async {
        for (var round = 0; round < 2; round++) {
          await connection.connect(_args);
          for (var refusal = 0; refusal < 3; refusal++) {
            final opened = connector.channels.length;
            connector.channels.last.incoming.add(_refusal);
            await _until(() => connector.channels.length == opened + 1 && connection.isConnected);
          }
        }
      });
      expect(connector.channels, hasLength(8));
      expect(connection.status, DanmakuStatus.connected);
      await connection.close();
    });

    test('a dropped socket reconnects after 2 s with the same token, joins again and is ready again', () async {
      final delays = <Duration>[];
      final http = _TokenHttp([_answer(_tokenA), _answer(_tokenB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(delays.first, const Duration(seconds: 2), reason: 'one endpoint: 1 s × (1 round + 1)');
      expect(http.requests, hasLength(1), reason: 'tokens do not expire; the site reconnects with the same one');
      expect(connector.endpoints, List.filled(2, PicartoDanmakuProtocol.endpoint(_tokenA)));
      expect(connector.channels.first.closed, isTrue);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up; the detail does not repeat the token', () async {
      final delays = <Duration>[];
      final connector = _Connector(
        fail: (endpoint) => WebSocketException("Connection to '$endpoint' was not upgraded to websocket"),
      );
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector);
      final events = _record(connection);
      await _fastTimers(delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays, [
        for (final seconds in [2, 3, 4, 5, 6, 6, 6, 6]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, hasLength(9));
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('chat.picarto.tv/chat/token=…'))
            .having((event) => event.detail, 'detail', isNot(contains(_tokenA))),
      );
      expect(events, hasLength(2));
    });

    test('close: no event, keep-alive or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming
        ..add(_frames('S07-live')[5].text)
        ..add(_refusal);
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, isEmpty);
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another room closes the first socket and asks a token for the new room', () async {
      final http = _TokenHttp([_answer(_tokenA), _answer(_tokenB)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connection.connect(const PicartoDanmakuArgs(channelName: 'OtherChannel', channelId: 122866));
      expect(jsonDecode(utf8.decode(http.requests.last.body!)), PicartoDanmakuProtocol.tokenBody('OtherChannel'));
      expect(connector.endpoints.last, PicartoDanmakuProtocol.endpoint(_tokenB));
      expect(connector.channels.first.closed, isTrue);
      connector.channels.first.incoming
        ..add(_frames('S07-live')[5].text)
        ..add(_refusal);
      connector.channels.last.incoming.add('{"type":"stream","messages":{"id":122866,"viewers":34}}');
      await _until(() => _messages(events).isNotEmpty);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).single.type, LiveMessageType.online);
      expect(connector.channels, hasLength(2), reason: "the old socket's refusal is ignored");
      await connection.close();
    });

    test('takes PicartoDanmakuArgs only', () async {
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), _Connector());
      await expectLater(connection.connect('allatir'), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under picarto', () {
      final http = _TokenHttp([_answer(_tokenA)]);
      final registry = DanmakuRegistry({SiteIds.picarto: () => PicartoDanmakuConnection(http: http)});
      expect(registry.platforms, [SiteIds.picarto]);
      expect(registry.connectionFor(' Picarto '), isA<PicartoDanmakuConnection>());
      expect(registry.connectionFor('twitch'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: token in the path, the recorded frames, the keep-alive answered', () async {
      final received = <Object?>[];
      final paths = <String>[];
      final origins = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        paths.add(request.uri.path);
        origins.add(request.headers.value('origin'));
        final socket = await WebSocketTransformer.upgrade(request);
        for (final frame in _frames('S07-live')) {
          if (frame.dir == 'in' && frame.url == null) socket.add(frame.text);
        }
        socket.listen((frame) {
          received.add(frame);
          if (frame == PicartoDanmakuProtocol.heartbeat) socket.add(_pong);
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = PicartoDanmakuConnection(
        http: _TokenHttp([_answer(_tokenA)]),
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
      await connection.connect(_args);
      final v4 = _v4Frames('S07-live').values.expand((events) => events! as List<Object?>).toList();
      await _until(() => _messages(events).length == v4.length);
      expect(requested, [PicartoDanmakuProtocol.endpoint(_tokenA)]);
      expect(paths, ['/chat/token=$_tokenA']);
      expect(origins, [PicartoApi.origin]);
      expect(_messages(events).map(_asV4), v4);
      connection.heartbeat();
      await _until(() => received.isNotEmpty);
      expect(received, [PicartoDanmakuProtocol.heartbeat]);
      await _wait(const Duration(milliseconds: 20));
      expect(_messages(events), hasLength(v4.length), reason: 'the answer to the keep-alive shows nothing');
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await connection.close();
    });
  });
}
