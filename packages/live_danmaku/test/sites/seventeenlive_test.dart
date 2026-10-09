// 17LIVE danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.30-17LIVE弹幕/record.md): the protocol and the
// connection against the archived v4's output for the recordings (S05-live,
// S06-live) and the synthetic frames (S07-synthetic), written by
// fixtures/17live/danmaku/v4_expected.dart; the M5.F follow-ups (B-14: paid
// barrages, resume, stream end, mute) against the recordings S08-resume,
// S09-resume-bad-key and S10-events and synthetic frames; B-25 (no count of
// 0 while the stream is paused) and B-26 (the backlog after a resume is
// replayed).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _fixtures = '../../fixtures/17live';
const _root = '$_fixtures/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, String? url, Object data});

Object _dataOf(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

/// The lines of a recording, in order: text frames as `String`, binary ones
/// as bytes; `url` marks the HTTP answer.
List<_Frame> _frames(String name) => [
  for (final (index, line) in File('$_root/$name/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir} && final Map<String, Object?> frame)
      (index: index, dir: dir, url: frame['url'] as String?, data: _dataOf(frame)),
];

/// The received socket frames of a recording (not its HTTP answer).
List<_Frame> _received(String name) => [
  for (final frame in _frames(name))
    if (frame.dir == 'in' && frame.url == null) frame,
];

/// The sent frames of a recording.
List<String> _sent(String name) => [
  for (final frame in _frames(name))
    if (frame.dir == 'out') frame.data as String,
];

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// The lines of a recording as they are (S08-resume: `socket`, `mark`;
/// S10-events: `room`).
List<Map<String, Object?>> _lines(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) jsonDecode(line)! as Map<String, Object?>,
];

/// S10-events: one frame of some room per line.
List<({String room, String text})> _events10() => [
  for (final line in _lines('S10-events')) (room: line['room']! as String, text: line['text']! as String),
];

/// The payload of a `MESSAGE` frame holding one message.
Map<Object?, Object?>? _payloadOf(String frame) => SeventeenLiveDanmakuProtocol.payload(
  ((jsonDecode(frame)! as Map<String, Object?>)['messages']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .single['data'],
);

String _roomOf(String name) => (_meta(name)['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;

/// The recorded `messenger/auth` answer.
LiveResponse _authAnswer(String name) {
  final frame = _frames(name).firstWhere((frame) => frame.url != null);
  return LiveResponse(status: 200, url: Uri.parse(frame.url!), bytes: utf8.encode(frame.data as String));
}

/// The archived v4's output for a fixture.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

/// v4's reading of every received socket frame of a recording, by line.
Map<int, Map<String, Object?>> _v4Frames(String name) => {
  for (final frame in (_v4(name)['frames']! as List<Object?>).cast<Map<String, Object?>>())
    frame['frame']! as int: {...frame}..remove('frame'),
};

final Map<String, Object?> _cases = _json('S07-synthetic/cases.json')! as Map<String, Object?>;

/// The v4 output for every synthetic case, one reading per frame.
final Map<String, Object?> _v4Cases = _v4('S07-synthetic')['cases']! as Map<String, Object?>;

List<Map<String, Object?>> _caseFrames(String name) => [
  for (final entry in (_cases['cases']! as List<Object?>).cast<Map<String, Object?>>())
    if (entry['name'] == name) ...(entry['frames']! as List<Object?>).cast<Map<String, Object?>>(),
];

/// S06-live's room (花音, the room of S04-live-live) and S05-live's.
const String _room = '27484154';
const String _archivedRoom = '29046769';
const SeventeenLiveDanmakuArgs _args = SeventeenLiveDanmakuArgs(roomId: _room);

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `17live:`; the new ids are Ably's own
/// (difference 1), so the projection adds the prefix back.
Map<String, Object?> _asV4(LiveMessage message) => switch (message.type) {
  LiveMessageType.chat => {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : '17live:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
  },
  LiveMessageType.online => {
    'kind': 'online',
    'audience': 'online',
    'value': (message.data! as LiveAudienceUpdate).value,
  },
  // B-14: a paid barrage's super chat; v4 had none.
  LiveMessageType.superChat => {
    'kind': 'superChat',
    'id': message.messageId,
    'price': (message.data! as LiveSuperChatMessage).price,
    'text': message.message,
  },
  _ => throw StateError('unexpected ${message.type}'),
};

/// The new reading of one frame in v4's shape: whether it joined, the
/// messages. v4's `rejected` has no single counterpart; the refusals are
/// checked one by one.
Map<String, Object?> _readAsV4(Object data, {String roomId = _room}) {
  final frame = SeventeenLiveDanmakuProtocol.decode(data, roomId: roomId);
  return {'joined': frame.signal == SeventeenLiveSignal.attached, 'events': frame.messages.map(_asV4).toList()};
}

/// v4's reading with the difference every frame shares: gifts are not
/// reported (difference 3).
Map<String, Object?> _shared(Object? v4) {
  final reading = v4! as Map<String, Object?>;
  return {
    'joined': reading['joined'],
    'events': [
      for (final event in (reading['events']! as List<Object?>).cast<Map<String, Object?>>())
        if (event['kind'] != 'gift') event,
    ],
  };
}

List<Map<String, Object?>> _events(Object? reading) =>
    ((reading! as Map<String, Object?>)['events']! as List<Object?>).cast<Map<String, Object?>>();

const int _t = 1790636400123;

String _user(int n) => '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Map<String, Object?> _line(String id, int n, String text, {Object? sentAt = _t}) => {
  'kind': 'chat',
  'id': '17live:$id',
  'sentAt': sentAt == _t ? _t + n : sentAt,
  'userId': _user(n),
  'userName': '观众$n',
  'text': text,
};

const Map<String, Object?> _nothing = {'joined': false, 'events': <Object?>[]};

/// The differences of the new decoder from v4 in the synthetic cases, beyond
/// [_shared] (docs/D-弹幕/D01-平台弹幕协议/D01.30-17LIVE弹幕/record.md, "与归档 v4 的差异"): v4's reading →
/// the new one, per case. Cases not listed read as v4 read them.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // B-14: the paid barrage (barrageStyle, barrage.point 30) is a super chat
  // besides its chat line; v4 had the chat line only.
  'comments: a coloured one, a barrage, a name only in openID, no display user': (v4) {
    expect(_events(v4[1]).single['text'], '弾幕です');
    return [
      _shared(v4[0]),
      {
        'joined': false,
        'events': [
          ..._events(v4[1]),
          {'kind': 'superChat', 'id': 'case01b:0', 'price': 30, 'text': '弾幕です'},
        ],
      },
      _shared(v4[2]),
      _shared(v4[3]),
    ];
  },
  // Difference 4: the website hides these comments; v4 showed them.
  'hidden comments: isDirty, isDirtyWord, isDirtyUser': (v4) {
    expect([for (final reading in v4.take(3)) _events(reading).single['text']], ['見えない1', '見えない2', '見えない3']);
    return [_nothing, _nothing, _nothing, _shared(v4[3])];
  },
  // Difference 5: the text is content, what the website shows (v4 took
  // comment.text first); text that is not a string is none (v4 wrote the
  // number).
  'comment text: content first, comment.text without it, blank, not text': (v4) {
    expect(_events(v4[0]).single['text'], '別の本文');
    expect(_events(v4[4]).single['text'], '12345');
    return [
      {
        'joined': false,
        'events': [_line('case03a:0', 9, '表示される本文')],
      },
      _shared(v4[1]),
      _shared(v4[2]),
      _shared(v4[3]),
      _nothing,
    ];
  },
  // Difference 7: a time beyond DateTime leaves the comment without a time;
  // v4 threw RangeError and lost the frame.
  'a time beyond DateTime': (v4) {
    expect(v4.single, {'throws': 'RangeError'});
    return [
      {
        'joined': false,
        'events': [_line('case05a:0', 19, '遠い未来', sentAt: null)],
      },
    ];
  },
  // Difference 6: a message without an id takes the frame's id and its
  // index, Ably's rule; v4 left it without one.
  'message ids: the message id, else the frame id and index, else none': (v4) {
    expect(_events(v4[1]).map((event) => event['id']), [null, null]);
    return [
      _shared(v4[0]),
      {
        'joined': false,
        'events': [_line('case06b:0', 21, 'idなし'), _line('case06b:1', 22, 'idなし2')],
      },
      _shared(v4[2]),
    ];
  },
  // Difference 8: only gzip + base64 text is a payload, as on the website;
  // v4 also read plain JSON text and objects.
  'payloads that are not gzip + base64': (v4) {
    expect(_events(v4[0]).single['text'], 'そのままのJSON');
    expect(_events(v4[1]).single['text'], 'オブジェクト');
    return [_nothing, _nothing, for (final reading in v4.skip(2)) _shared(reading)];
  },
};

/// A `messenger/auth` answer granting [token].
LiveResponse _granted(String token, {Object? provider = 1, int status = 200}) => LiveResponse(
  status: status,
  url: SeventeenLiveDanmakuProtocol.authUrl,
  bytes: utf8.encode(
    jsonEncode({
      'provider': ?provider,
      'token': token,
      'permissions': ['*'],
    }),
  ),
);

LiveResponse _body(String body, {int status = 200}) =>
    LiveResponse(status: status, url: SeventeenLiveDanmakuProtocol.authUrl, bytes: utf8.encode(body));

/// Answers `messenger/auth` from a script: each entry is a response, an
/// error to throw, or a completer to wait for; the last entry repeats.
final class _Http implements LiveHttp {
  new(this.script);

  final List<Object> script;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final step = script[(requests.length - 1).clamp(0, script.length - 1)];
    return switch (step) {
      final LiveResponse response => response,
      final Completer<LiveResponse> pending => await Future.any([
        pending.future,
        request.cancel!.whenCancelled.then(
          (_) => throw const TransportFailure(SiteIds.seventeenLive, TransportReason.cancelled),
        ),
      ]),
      _ => throw step as Exception,
    };
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

final class _Channel implements SocketChannel {
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

  /// Delivers [frame] and lets the connection handle it.
  Future<void> receive(Object frame) async {
    incoming.add(frame);
    await Future<void>.delayed(Duration.zero);
  }

  /// The server's `CONNECTED` and the `ATTACHED` of [room].
  Future<void> join([String room = _room]) async {
    await receive(_connectedFrame);
    await receive(_attachedFrame(room));
  }
}

/// Hands out fake sockets and records every handshake; [fail] gives the
/// error to throw for an endpoint, or null to open it.
final class _Connector {
  new({this.fail});

  final Exception? Function(Uri endpoint)? fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<ProxyRoute> routes = [];
  final List<_Channel> channels = [];

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
    if (failure?.call(endpoint) case final error?) throw error;
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }

  /// The tokens of the handshakes, in order.
  List<String?> get tokens => [for (final endpoint in endpoints) endpoint.queryParameters['access_token']];

  /// The hosts of the handshakes, in order.
  List<String> get hosts => [for (final endpoint in endpoints) endpoint.host];
}

/// S06-live's `CONNECTED` (scrubbed).
final String _connectedFrame = _received('S06-live').first.data as String;

String _attachedFrame(String room) => jsonEncode({
  'action': 11,
  'channel': room,
  'channelSerial': '01790636303769-000@4ab3ylSkAC7Jsb05105702',
  'flags': 786432,
});

/// A `MESSAGE` of [payloads] on [room]'s channel.
String _ablyMessage(List<Map<String, Object?>> payloads, {String room = _room, String id = 'frame000001'}) =>
    jsonEncode({
      'action': 15,
      'id': id,
      'channel': room,
      'timestamp': _t,
      'messages': [
        for (final (index, payload) in payloads.indexed)
          {'id': '$id:$index', 'action': 0, 'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))))},
      ],
    });

Map<String, Object?> _comment(String text, {int n = 1, Map<String, Object?> more = const {}}) => {
  'type': 3,
  'commentMsg': {
    'isDirty': false,
    'isDirtyUser': false,
    'sendTime': _t + n,
    'level': 10 + n,
    'comment': {'text': text, 'textColor': '#FFFFFFFF'},
    'content': text,
    'displayUser': {'userID': _user(n), 'displayName': '观众$n', 'level': 10 + n},
    ...more,
  },
};

String _error(int action, int code, String message, {String? channel}) => jsonEncode({
  'action': action,
  'channel': ?channel,
  'error': {'message': message, 'code': code, 'statusCode': code ~/ 100},
});

/// No heartbeat, watchdog or join timer and a short backoff: only what the
/// test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

SeventeenLiveDanmakuConnection _connection(
  _Connector connector,
  _Http http, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) => SeventeenLiveDanmakuConnection(http: http, connector: connector.call, policy: policy, proxy: proxy);

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

String _attach([String room = _room]) => '{"action":10,"channel":"$room"}';

/// B-14: the attach of a channel attached before, from [serial].
String _resumeAttach(String? serial, [String room = _room]) => serial == null
    ? '{"action":10,"channel":"$room","flags":32}'
    : '{"action":10,"channel":"$room","channelSerial":"$serial","flags":32}';

/// The serial of [_attachedFrame] and the key of [_connectedFrame].
const String _joinedSerial = '01790636303769-000@4ab3ylSkAC7Jsb05105702';
const String _connectedKey = 'KMHu-BpmDaCyjV!aAkFypXTcZHBDW_PeCuyrh-sUc2qJ';

void main() {
  group('protocol', () {
    test('the token request, the sockets, the handshake headers, the commands and the timing', () {
      final cancel = CancelToken();
      final request = SeventeenLiveDanmakuProtocol.authRequest(timeout: const Duration(seconds: 7), cancel: cancel);
      expect(request.site, '17live');
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://api-dsa.17app.co/api/v1/messenger/auth'));
      expect(request.headers, {...SeventeenLiveApi.catalogHeaders, 'content-type': 'application/json'});
      expect(request.headers['origin'], 'https://17.live');
      expect(request.headers['referer'], 'https://17.live/');
      expect(utf8.decode(request.body!), '{}');
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 7));
      expect(request.cancel, same(cancel));
      expect(SeventeenLiveDanmakuProtocol.endpoints.map((endpoint) => '$endpoint'), [
        'wss://17media.realtime.ably.net/?format=json&heartbeats=true&v=3',
        'wss://17-media-a-fallback.ably-realtime.com/?format=json&heartbeats=true&v=3',
        'wss://17-media-b-fallback.ably-realtime.com/?format=json&heartbeats=true&v=3',
        'wss://17-media-c-fallback.ably-realtime.com/?format=json&heartbeats=true&v=3',
      ]);
      expect(
        '${SeventeenLiveDanmakuProtocol.withToken(SeventeenLiveDanmakuProtocol.endpoints[1], 'app.to-k_en')}',
        'wss://17-media-a-fallback.ably-realtime.com/?access_token=app.to-k_en&format=json&heartbeats=true&v=3',
      );
      expect(SeventeenLiveDanmakuProtocol.handshakeHeaders, {
        'origin': 'https://17.live',
        'user-agent': SeventeenLiveApi.userAgent,
      });
      expect(SeventeenLiveDanmakuProtocol.attach('27484154'), '{"action":10,"channel":"27484154"}');
      expect(SeventeenLiveDanmakuProtocol.reauthorize('app.token'), '{"action":17,"auth":{"accessToken":"app.token"}}');
      expect(SeventeenLiveDanmakuProtocol.heartbeatInterval, const Duration(seconds: 15));
      expect(SeventeenLiveDanmakuProtocol.inactivityTimeout, const Duration(seconds: 25));
      expect(SeventeenLiveDanmakuProtocol.joinTimeout, const Duration(seconds: 10));
      expect(SeventeenLiveDanmakuProtocol.maxRefusals, 3);
    });

    test("v4's token request, socket, headers and ATTACH; the recorded handshakes", () {
      for (final name in ['S05-live', 'S06-live']) {
        final v4 = _v4(name);
        final connector = v4['connector']! as Map<String, Object?>;
        final token = SeventeenLiveDanmakuProtocol.grant(_authAnswer(name));
        expect(token, v4['token'], reason: name);
        expect(connector['authUrl'], '${SeventeenLiveDanmakuProtocol.authUrl}');
        expect(connector['authMethod'], 'POST');
        expect(connector['authBody'], '{}');
        final socket = SeventeenLiveDanmakuProtocol.withToken(SeventeenLiveDanmakuProtocol.endpoints.first, token);
        expect('$socket', connector['endpoint'], reason: name);
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        expect('$socket', handshake['url'], reason: name);
        expect(SeventeenLiveDanmakuProtocol.handshakeHeaders, handshake['headers'], reason: name);
        expect(SeventeenLiveDanmakuProtocol.handshakeHeaders, connector['handshakeHeaders']);
        expect([SeventeenLiveDanmakuProtocol.attach(_roomOf(name))], _sent(name), reason: name);
        expect(SeventeenLiveDanmakuProtocol.attach(_roomOf(name)), connector['attach']);
        expect(connector['heartbeatSeconds'], 15);
      }
      // v4 sent fewer headers (difference 10): Origin, UA, a JSON Accept,
      // the content type and the Referer; the new request adds the platform's
      // Accept-Language.
      final v4Headers = (_v4('S06-live')['connector']! as Map<String, Object?>)['authHeaders']! as Map<String, Object?>;
      expect(v4Headers.keys.toSet(), {'origin', 'user-agent', 'accept', 'content-type', 'referer'});
      const headers = SeventeenLiveDanmakuProtocol.authHeaders;
      for (final key in ['origin', 'user-agent', 'content-type', 'referer']) {
        expect(headers[key], v4Headers[key], reason: key);
      }
    });

    test("S06-live's room is the room of S04-live-live, whose entry gives its arguments", () async {
      final http = ReplayHttp.fixtures(_fixtures, const ['S04-live-live']);
      final room = await SeventeenLiveSite(http).getRoomDetail(roomId: _room);
      expect(room.danmakuData, const SeventeenLiveDanmakuArgs(roomId: _room));
      expect(_roomOf('S06-live'), _room);
      expect(_roomOf('S05-live'), _archivedRoom);
    });

    test('messenger/auth: the token of an Ably answer; other providers, statuses and shapes', () {
      expect(SeventeenLiveDanmakuProtocol.grant(_granted('qvDtFQ.abc_DEF-123')), 'qvDtFQ.abc_DEF-123');
      expect(
        () => SeventeenLiveDanmakuProtocol.grant(_granted('pubnub', provider: 2)),
        throwsA(isA<SeventeenLiveChatRefusal>().having((refusal) => '$refusal', 'text', 'messenger/auth: provider 2')),
      );
      expect(
        () => SeventeenLiveDanmakuProtocol.grant(_granted('x', provider: null)),
        throwsA(
          isA<SeventeenLiveChatRefusal>().having((refusal) => '$refusal', 'text', 'messenger/auth: provider missing'),
        ),
      );
      expect(
        () => SeventeenLiveDanmakuProtocol.grant(_granted('x', provider: '1')),
        throwsA(isA<SeventeenLiveChatRefusal>().having((refusal) => refusal.provider, 'provider', '1')),
      );
      expect(() => SeventeenLiveDanmakuProtocol.grant(_granted('x', status: 403)), throwsA(isA<RiskControl>()));
      expect(() => SeventeenLiveDanmakuProtocol.grant(_granted('x', status: 502)), throwsA(isA<NetworkFailure>()));
      expect(() => SeventeenLiveDanmakuProtocol.grant(_body('<html>')), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveDanmakuProtocol.grant(_body('[1]')), throwsFormatException);
      for (final token in <Object?>['', 'with space', 'tab\there', 'ｆｕｌｌ', 'a' * 4097, 42, null]) {
        expect(
          () => SeventeenLiveDanmakuProtocol.grant(_body(jsonEncode({'provider': 1, 'token': token}))),
          throwsFormatException,
          reason: '$token',
        );
      }
      expect(SeventeenLiveDanmakuProtocol.grant(_granted('a' * 4096)), hasLength(4096));
    });

    test('a frame is one Ably protocol message: its signal and error', () {
      SeventeenLiveDanmakuFrame read(Object? data, {String room = _room}) =>
          SeventeenLiveDanmakuProtocol.decode(data, roomId: room);
      expect(read(_connectedFrame).signal, SeventeenLiveSignal.connected);
      expect(read(_attachedFrame(_room)).signal, SeventeenLiveSignal.attached);
      expect(read(_attachedFrame('999999999999')).signal, SeventeenLiveSignal.none);
      expect(read('{"action":0}').signal, SeventeenLiveSignal.none);
      expect(read('{"action":16,"channel":"$_room","presence":[]}').signal, SeventeenLiveSignal.none);
      expect(read('{"action":7}').signal, SeventeenLiveSignal.none);
      expect(read('{"action":17}').signal, SeventeenLiveSignal.reauthorize);
      final expired = read(_error(9, 40142, ' Key/token status changed (expire) '));
      expect(expired.signal, SeventeenLiveSignal.connectionError);
      expect(
        expired.error,
        const SeventeenLiveAblyError(code: 40142, statusCode: 401, message: 'Key/token status changed (expire)'),
      );
      expect(expired.error!.isTokenError, isTrue);
      expect('${expired.error}', '40142 Key/token status changed (expire)');
      expect(read('{"action":9}').error, const SeventeenLiveAblyError(code: 0));
      expect(read('{"action":9,"error":{"code":"40142","message":7}}').error, const SeventeenLiveAblyError(code: 0));
      expect(read(_error(9, 40160, 'denied', channel: _room)).signal, SeventeenLiveSignal.channelError);
      expect(read(_error(9, 40160, 'denied', channel: '1')).signal, SeventeenLiveSignal.none);
      expect(read(_error(6, 40142, 'expired')).signal, SeventeenLiveSignal.disconnected);
      expect(read('{"action":6}').error, isNull);
      expect(read('{"action":13,"channel":"$_room"}').signal, SeventeenLiveSignal.detached);
      expect(read('{"action":13,"channel":"1"}').signal, SeventeenLiveSignal.none);
      expect(read(utf8.encode(_attachedFrame(_room))).signal, SeventeenLiveSignal.attached);
      for (final broken in <Object?>[
        'not json',
        '[1]',
        '"text"',
        '',
        42,
        null,
        <int>[0xff, 0xfe],
      ]) {
        final frame = read(broken);
        expect(
          (frame.signal, frame.error, frame.messages.length),
          (SeventeenLiveSignal.none, null, 0),
          reason: '$broken',
        );
      }
      for (final (code, token) in [(40139, false), (40140, true), (40149, true), (40150, false), (40101, false)]) {
        expect(SeventeenLiveAblyError(code: code).isTokenError, token, reason: '$code');
      }
    });

    test('a payload is base64 of gzipped JSON, as the website reads it', () {
      final comment = _comment('こんばんは');
      String packed(List<int> bytes) => base64Encode(gzip.encode(bytes));
      expect(SeventeenLiveDanmakuProtocol.payload(packed(utf8.encode(jsonEncode(comment)))), comment);
      for (final data in <Object?>[
        jsonEncode(comment),
        comment,
        'H4sInotgzip',
        base64Encode(utf8.encode('not gzip')),
        packed(utf8.encode('[1,2]')),
        packed(utf8.encode('{"broken":')),
        packed([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d]),
        '',
        null,
        42,
      ]) {
        expect(SeventeenLiveDanmakuProtocol.payload(data), isNull, reason: '$data');
      }
    });

    test('a comment fills the message model: text, name, user, level, colour, time, id', () {
      final message = SeventeenLiveDanmakuProtocol.message(
        _comment(
          '  こんばんは  ',
          more: {
            'comment': {'text': 'こんばんは', 'textColor': '#FF33CDBB'},
          },
        ),
        id: 'abc:0',
      )!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'こんばんは');
      expect(message.userName, '观众1');
      expect(message.userId, _user(1));
      expect(message.userLevel, '11');
      expect(message.color, const LiveMessageColor(0x33, 0xcd, 0xbb));
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(_t + 1));
      expect(message.messageId, 'abc:0');
      expect(message.fansLevel, isEmpty);
      expect(message.data, isNull);
    });

    test('comment fields one by one: hidden, text, name, level, colour, time', () {
      LiveMessage? read(Map<String, Object?> more) => SeventeenLiveDanmakuProtocol.message(_comment('本文', more: more));
      for (final flag in ['isDirty', 'isDirtyWord', 'isDirtyUser']) {
        expect(read({flag: true}), isNull, reason: flag);
        expect(read({flag: 'true'}), isNotNull, reason: '$flag as text');
      }
      expect(read({'isFraud': true}), isNotNull);
      expect(read({'content': '表示'})!.message, '表示');
      expect(read({'content': null})!.message, '本文');
      expect(read({'content': '   '})!.message, '本文');
      expect(
        read({
          'content': 7,
          'comment': {'text': 8},
        }),
        isNull,
      );
      expect(read({'content': '', 'comment': 'text'}), isNull);
      expect(
        read({
          'displayUser': {'openID': 'open', 'userID': 'u'},
        })!.userName,
        'open',
      );
      expect(
        read({
          'displayUser': {'displayName': '', 'openID': 'open'},
        })!.userName,
        'open',
      );
      expect(
        read({
          'displayUser': {'displayName': 5},
        })!.userName,
        isEmpty,
      );
      final bare = read({'displayUser': 'nobody'})!;
      expect((bare.userName, bare.userId, bare.userLevel), ('', '', '11'));
      expect(
        read({
          'displayUser': {'level': 0},
          'level': 3,
        })!.userLevel,
        '3',
      );
      expect(read({'displayUser': <String, Object?>{}, 'level': -1})!.userLevel, isEmpty);
      final colours = <Object?, LiveMessageColor>{
        '#FFFFFFFF': LiveMessageColor.white,
        '#80102030': const LiveMessageColor(0x10, 0x20, 0x30),
        '#3366cc': const LiveMessageColor(0x33, 0x66, 0xcc),
        '3366CC': const LiveMessageColor(0x33, 0x66, 0xcc),
        ' #3366CC ': const LiveMessageColor(0x33, 0x66, 0xcc),
        '#FFF': LiveMessageColor.white,
        '#GG0000': LiveMessageColor.white,
        '': LiveMessageColor.white,
        0xFF0000: LiveMessageColor.white,
        null: LiveMessageColor.white,
      };
      for (final MapEntry(key: value, value: colour) in colours.entries) {
        expect(SeventeenLiveDanmakuProtocol.color(value), colour, reason: '$value');
        expect(
          read({
            'comment': {'text': '本文', 'textColor': value},
          })!.color,
          colour,
          reason: '$value',
        );
      }
      expect(read({'sendTime': 0})!.sentAt, isNull);
      expect(read({'sendTime': -1})!.sentAt, isNull);
      expect(read({'sendTime': '1790636400123'})!.sentAt, isNull);
      expect(read({'sendTime': 8640000000000000})!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
      expect(read({'sendTime': 8640000000000001})!.sentAt, isNull);
      final barrage = read({
        'barrageStyle': true,
        'barrage': {'type': 2, 'point': 30},
      })!;
      expect((barrage.type, barrage.message), (LiveMessageType.chat, '本文'));
      expect(SeventeenLiveDanmakuProtocol.message(const {'type': 3, 'commentMsg': 'x'}), isNull);
    });

    test('the live figures (38) are the viewers now; every other type shows nothing', () {
      final online = SeventeenLiveDanmakuProtocol.message(const {
        'type': 38,
        'liveinfo': {'type': 1, 'liveViewerCount': 1196, 'achievementValue': 346367},
      })!;
      expect(online.type, LiveMessageType.online);
      expect(online.data, isA<LiveAudienceUpdate>());
      final update = online.data! as LiveAudienceUpdate;
      expect((update.kind, update.value), (LiveAudienceMetricKind.onlineViewers, 1196));
      for (final info in <Object?>[
        {'liveViewerCount': -1},
        {'liveViewerCount': '5'},
        <String, Object?>{},
        'x',
        null,
      ]) {
        expect(SeventeenLiveDanmakuProtocol.message({'type': 38, 'liveinfo': info}), isNull, reason: '$info');
      }
      for (final type in <Object?>[0, 2, 5, 6, 13, 18, 28, 32, 54, 74, 79, 80, 1001, '3', '38', null]) {
        expect(SeventeenLiveDanmakuProtocol.message({'type': type, 'commentMsg': _comment('x')['commentMsg']}), isNull);
      }
    });

    test('the viewers now stay a room figure: audience.dart keeps 17live as it was', () {
      final capability = AudiencePlatformCapability.of('17live');
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomRealtime);
      expect(capability.hasTotalViewers, isTrue);
      expect(capability.hasPopularity, isFalse);
    });
  });

  group('recorded frames against v4', () {
    for (final name in ['S05-live', 'S06-live']) {
      test('$name: every received socket frame reads as v4 read it, without gifts', () {
        final v4 = _v4Frames(name);
        final frames = _received(name);
        expect(v4.keys, [for (final frame in frames) frame.index]);
        for (final frame in frames) {
          expect(v4[frame.index]!['rejected'], isFalse);
          expect(_readAsV4(frame.data, roomId: _roomOf(name)), _shared(v4[frame.index]), reason: 'line ${frame.index}');
        }
      });
    }

    test('S05-live: joined once; the 8 comments of the archived recording', () {
      final frames = [
        for (final frame in _received('S05-live'))
          SeventeenLiveDanmakuProtocol.decode(frame.data, roomId: _archivedRoom),
      ];
      expect(frames.where((frame) => frame.signal == SeventeenLiveSignal.attached), hasLength(1));
      final messages = [for (final frame in frames) ...frame.messages];
      expect(messages, hasLength(8));
      expect(messages.map((message) => message.type).toSet(), {LiveMessageType.chat});
      expect(messages.first.message, 'だまれ');
      expect(messages.first.messageId, '6Do04M3cWw6i:0');
    });

    test('S06-live: 26 comments and 9 viewer counts; gifts, entries, reactions and the rest show nothing', () {
      final frames = [
        for (final frame in _received('S06-live')) SeventeenLiveDanmakuProtocol.decode(frame.data, roomId: _room),
      ];
      expect(frames.map((frame) => frame.signal).where((signal) => signal != SeventeenLiveSignal.none), [
        SeventeenLiveSignal.connected,
        SeventeenLiveSignal.attached,
      ]);
      final messages = [for (final frame in frames) ...frame.messages];
      final chat = [
        for (final message in messages)
          if (message.type == LiveMessageType.chat) message,
      ];
      final online = [
        for (final message in messages)
          if (message.type == LiveMessageType.online) message,
      ];
      expect((chat.length, online.length, messages.length), (26, 9, 35));
      expect(chat.every((message) => message.color == LiveMessageColor.white), isTrue);
      expect(chat.every((message) => message.userLevel.isNotEmpty && message.sentAt != null), isTrue);
      expect(chat.where((message) => message.userId == '20015b43-ab03-43d8-a37e-32250131d6bc'), hasLength(9));
      expect(
        online.map((message) => (message.data! as LiveAudienceUpdate).value).every((value) => value > 1000),
        isTrue,
      );
      // v4 read 18 gifts (difference 3); the lucky bags (32), entries (18),
      // reactions (28), rankings (54), rewards (79), missions (80), stream
      // info (6) and 74 are read by neither.
      final v4Events = [for (final reading in _v4Frames('S06-live').values) ..._events(reading)];
      expect(v4Events.where((event) => event['kind'] == 'gift'), hasLength(18));
      final types = <Object?>{
        for (final frame in _received('S06-live'))
          if (jsonDecode(frame.data as String) case {'action': 15, 'messages': final List<Object?> items})
            for (final item in items.cast<Map<String, Object?>>())
              SeventeenLiveDanmakuProtocol.payload(item['data'])!['type'],
      };
      expect(types, {3, 6, 13, 18, 28, 32, 38, 54, 74, 79, 80});
    });
  });

  group('synthetic frames (S07-synthetic) against v4', () {
    final names = [
      for (final entry in (_cases['cases']! as List<Object?>).cast<Map<String, Object?>>()) entry['name']! as String,
    ];

    test('every case has v4 output, and every difference names a case', () {
      expect(_v4Cases.keys, names);
      expect(names, containsAll(_differences.keys));
      for (final name in names) {
        expect((_v4Cases[name]! as List<Object?>).length, _caseFrames(name).length, reason: name);
      }
    });

    for (final name in names) {
      test(name, () {
        final v4 = _v4Cases[name]! as List<Object?>;
        final expected = _differences[name]?.call(v4) ?? [for (final reading in v4) _shared(reading)];
        expect([for (final frame in _caseFrames(name)) _readAsV4(_dataOf(frame))], expected);
      });
    }

    test('refusals, detaches and re-authorisation: v4 rejected them all alike', () {
      const name = 'protocol messages: refusals, detaches and re-authorisation';
      final v4 = [
        for (final reading in _v4Cases[name]! as List<Object?>) (reading! as Map<String, Object?>)['rejected'],
      ];
      final frames = [
        for (final frame in _caseFrames(name)) SeventeenLiveDanmakuProtocol.decode(_dataOf(frame), roomId: _room),
      ];
      expect(v4, [true, true, true, true, true, true, false, true, false, true, false, false, false]);
      expect(
        [for (final frame in frames) frame.signal],
        [
          SeventeenLiveSignal.connectionError, // 40142: a new token
          SeventeenLiveSignal.connectionError, // 40101: fatal
          SeventeenLiveSignal.connectionError, // 40400: fatal
          SeventeenLiveSignal.channelError, // 40160 of the room: fatal
          SeventeenLiveSignal.none, // another channel's error (v4 rejected it)
          SeventeenLiveSignal.disconnected, // 40142: a new token
          SeventeenLiveSignal.disconnected, // reconnect
          SeventeenLiveSignal.disconnected, // 80003: reconnect (v4 took a new token)
          SeventeenLiveSignal.detached, // attach again
          SeventeenLiveSignal.detached, // attach again (v4 took a new token)
          SeventeenLiveSignal.reauthorize, // v4 ignored it
          SeventeenLiveSignal.connectionError, // no error object: fatal, code 0
          SeventeenLiveSignal.none, // CLOSED
        ],
      );
      expect(
        [for (final frame in frames) frame.error?.isTokenError],
        [
          true, false, false, false, null, true, null, false, null, false, null, false, null, //
        ],
      );
    });
  });

  group('connection', () {
    test('asks one token, opens the primary host with it, attaches at CONNECTED and is ready at ATTACHED', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final request = http.requests.single;
      final expected = SeventeenLiveDanmakuProtocol.authRequest();
      expect(
        (request.site, request.method, request.url, request.headers),
        (expected.site, 'POST', expected.url, expected.headers),
      );
      expect(utf8.decode(request.body!), '{}');
      expect(request.followRedirects, isFalse);
      expect(request.timeout, _quiet.connectTimeout);
      expect(
        connector.endpoints.single,
        Uri.parse('wss://17media.realtime.ably.net/?access_token=AAAAAA.token-1&format=json&heartbeats=true&v=3'),
      );
      expect(connector.headers.single, SeventeenLiveDanmakuProtocol.handshakeHeaders);
      final channel = connector.channels.single;
      expect(channel.sent, isEmpty, reason: 'ably-js attaches once CONNECTED');
      await channel.receive(_connectedFrame);
      expect(channel.sent, [_attach()]);
      expect(connection.isConnected, isFalse);
      expect(events, isEmpty);
      await channel.receive(_attachedFrame('999999999999'));
      expect(events, isEmpty);
      await channel.receive(_attachedFrame(_room));
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      await channel.receive(_attachedFrame(_room));
      await channel.receive(
        _ablyMessage([
          _comment('こんばんは'),
          _comment('x', n: 2, more: {'isDirty': true}),
        ]),
      );
      await channel.receive(_ablyMessage([_comment('別の部屋')], room: '1'));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).map((message) => message.message), ['こんばんは']);
      await connection.close();
    });

    for (final name in ['S05-live', 'S06-live']) {
      test('replaying $name reports what v4 read, in order, and sends the recorded ATTACH', () async {
        final room = _roomOf(name);
        final http = _Http([_authAnswer(name)]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(SeventeenLiveDanmakuArgs(roomId: room));
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        expect('${connector.endpoints.single}', handshake['url']);
        final channel = connector.channels.single;
        for (final frame in _received(name)) {
          await channel.receive(frame.data);
        }
        expect(channel.sent, _sent(name));
        expect(events.whereType<DanmakuReady>(), hasLength(1));
        expect(events.first, const DanmakuReady());
        final v4 = [
          for (final reading in _v4Frames(name).values) ..._events(reading).where((event) => event['kind'] != 'gift'),
        ];
        expect(_messages(events).map(_asV4), v4);
        await connection.close();
      });
    }

    test('timing: the server heartbeat as the watchdog tick, 25 s of silence, 10 s to attach, 8 reconnects', () {
      const policy = SeventeenLiveDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 15));
      expect(policy.inactivityTimeout, const Duration(seconds: 25));
      expect(policy.joinTimeout, const Duration(seconds: 10));
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(
        SeventeenLiveDanmakuConnection(http: _Http([_granted('AAAAAA.token-1')])).heartbeatInterval,
        const Duration(seconds: 15),
      );
    });

    test('sends no heartbeat, on the tick or on demand; a silent socket is replaced, with the same token', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 10),
          inactivityTimeout: Duration(milliseconds: 60),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(first.sent, [_attach()]);
      await _until(() => connector.channels.length == 2);
      expect(first.closed, isTrue);
      expect(connector.hosts, ['17media.realtime.ably.net', '17-media-a-fallback.ably-realtime.com']);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1']);
      expect(http.requests, hasLength(1));
      expect(events, [const DanmakuReady(), const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await connection.close();
    });

    test('a dropped socket reconnects to the next host with the same token, attaches and is ready again', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      await second.join();
      // B-14: the new socket resumes the connection and the channel.
      expect(second.sent, [_resumeAttach(_joinedSerial)]);
      expect(connector.endpoints.last.queryParameters['resume'], _connectedKey);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1']);
      expect(http.requests, hasLength(1));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('failed handshakes go round the four hosts with one token, then give up; no token in the detail', () async {
      final http = _Http([_granted('AAAAAA.token/1+')]);
      final connector = _Connector(
        fail: (endpoint) => WebSocketException(
          "Connection to '${endpoint.replace(scheme: 'https')}' was not upgraded to websocket, HTTP status code: 503 "
          '(${endpoint.queryParameters['access_token']})',
        ),
      );
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(connector.hosts, [
        for (var attempt = 0; attempt < 9; attempt++)
          ['17media.realtime.ably.net', ...SeventeenLiveDanmakuProtocol.fallbackHosts][attempt % 4],
      ]);
      expect(connector.tokens.toSet(), {'AAAAAA.token/1+'});
      expect(http.requests, hasLength(1));
      final closed = events.whereType<DanmakuClosed>().single;
      expect(closed.reason, DanmakuCloseReason.reconnectsExhausted);
      expect(closed.detail, contains('access_token=<token>'));
      expect(closed.detail, endsWith('503 (<token>)'));
      expect(closed.detail, isNot(contains('token%2F1')));
      expect(closed.detail, isNot(contains('token/1')));
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
    });

    test('the room id is checked and trimmed; a bad one ends with connectionFailed and asks nothing', () async {
      for (final roomId in ['', 'abc', '0123', '1234567890123', '12 34', '２７４８４１５４']) {
        final http = _Http([_granted('AAAAAA.token-1')]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(SeventeenLiveDanmakuArgs(roomId: roomId));
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable room id'),
        ], reason: roomId);
        expect(http.requests, isEmpty);
        expect(connector.endpoints, isEmpty);
      }
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: ' 27484154 '));
      await connector.channels.single.receive(_connectedFrame);
      expect(connector.channels.single.sent, [_attach()]);
      await connection.close();
    });

    test('a failed token request fails that handshake: the next host asks again', () async {
      final http = _Http([
        const SocketException('offline'),
        _granted('x', status: 502),
        _body('{"provider":1}'),
        _granted('AAAAAA.token-2'),
      ]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connector.channels.isNotEmpty);
      expect(http.requests, hasLength(4));
      expect(connector.hosts, [
        '17-media-c-fallback.ably-realtime.com',
      ], reason: 'the fourth attempt, at the third fallback');
      expect(connector.tokens, ['AAAAAA.token-2']);
      await connector.channels.single.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('another push service than Ably ends with connectionFailed and opens nothing', () async {
      final http = _Http([_granted('pubnub-key', provider: 2)]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.isNotEmpty);
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'messenger/auth: provider 2')]);
      expect(connector.endpoints, isEmpty);
      expect(connection.status, DanmakuStatus.closed);
      await _wait(const Duration(milliseconds: 30));
      expect(http.requests, hasLength(1));
    });

    test('a token error drops the token and the socket; the next handshake asks a new one', () async {
      for (final refusal in [
        _error(9, 40142, 'Key/token status changed (expire)'),
        _error(6, 40142, 'Token expired'),
      ]) {
        final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(_args);
        await connector.channels.single.join();
        await connector.channels.single.receive(refusal);
        await _until(() => connector.channels.length == 2);
        expect(connector.channels.first.closed, isTrue);
        expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-2'], reason: refusal);
        await connector.channels.last.join();
        expect(events, [
          const DanmakuReady(),
          const DanmakuReconnecting(DanmakuInterruption.disconnected),
          const DanmakuReady(),
        ]);
        await connection.close();
      }
    });

    test('the fourth token refusal in a row ends with connectionFailed; an attach starts the count again', () async {
      final http = _Http([for (var n = 1; n <= 12; n++) _granted('AAAAAA.token-$n')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      Future<void> refuse() async {
        final channel = connector.channels.last;
        await channel.receive(_connectedFrame);
        final sockets = connector.channels.length;
        await channel.receive(_error(9, 40142, 'Key/token status changed (expire)'));
        if (events.whereType<DanmakuClosed>().isEmpty) await _until(() => connector.channels.length > sockets);
      }

      for (var n = 0; n < 3; n++) {
        await refuse();
      }
      await connector.channels.last.join();
      for (var n = 0; n < 3; n++) {
        await refuse();
      }
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      await refuse();
      expect(
        events.last,
        const DanmakuClosed(
          DanmakuCloseReason.connectionFailed,
          detail: 'Token refused: 40142 Key/token status changed (expire)',
        ),
      );
      expect(connector.channels, hasLength(7));
      expect(http.requests, hasLength(7));
      expect(connector.channels.last.closed, isTrue);
    });

    test('any other connection error or a channel error ends the run; another channel error is ignored', () async {
      for (final (frame, detail) in [
        (
          _error(9, 40400, 'No application found with id AAAAAA'),
          'Ably error 40400 No application found with id AAAAAA',
        ),
        (
          _error(9, 40101, 'token invalid - could not decode legacy token: invalid token size'),
          'Ably error 40101 token invalid - could not decode legacy token: invalid token size',
        ),
        ('{"action":9}', 'Ably error 0'),
        (_error(9, 40160, 'Channel denied', channel: _room), 'Channel refused: 40160 Channel denied'),
      ]) {
        final http = _Http([_granted('AAAAAA.token-1')]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(_args);
        final channel = connector.channels.single;
        await channel.receive(_connectedFrame);
        await channel.receive(_error(9, 40160, 'Channel denied', channel: '999999999999'));
        expect(events, isEmpty);
        await channel.receive(frame);
        expect(events, [DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: detail)], reason: frame);
        expect(channel.closed, isTrue);
        await _wait(const Duration(milliseconds: 20));
        expect((connector.channels.length, http.requests.length), (1, 1));
      }
    });

    test('a DISCONNECTED without a token error reconnects with the same token', () async {
      for (final frame in ['{"action":6}', _error(6, 80003, 'Connection disconnected')]) {
        final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        await connection.connect(_args);
        await connector.channels.single.join();
        await connector.channels.single.receive(frame);
        await _until(() => connector.channels.length == 2);
        expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1'], reason: frame);
        expect(http.requests, hasLength(1));
        await connection.close();
      }
    });

    test('a server-sent DETACHED attaches again on the same socket; the room stays joined', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await channel.receive('{"action":13,"channel":"$_room","error":{"code":90198,"message":"Channel detached"}}');
      // B-14: attached again from the last serial, as ably-js does.
      expect(channel.sent, [_attach(), _resumeAttach(_joinedSerial)]);
      expect(connection.isConnected, isTrue);
      await channel.receive(_attachedFrame(_room));
      await channel.receive(_ablyMessage([_comment('戻った')]));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).single.message, '戻った');
      // Detached twice before the attach is answered: a new socket, which
      // attaches without the serial (B-14: ably-js suspends the channel).
      await channel.receive('{"action":13,"channel":"$_room"}');
      await channel.receive('{"action":13,"channel":"$_room"}');
      await _until(() => connector.channels.length == 2);
      expect(channel.sent, [_attach(), _resumeAttach(_joinedSerial), _resumeAttach(_joinedSerial)]);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1']);
      await connector.channels.last.receive(_connectedFrame);
      expect(connector.channels.last.sent, [_resumeAttach(null)]);
      await connection.close();
    });

    test(
      'the fourth detach or token refusal in a row, without an attach between, ends with connectionFailed',
      () async {
        final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(_args);
        final first = connector.channels.single;
        await first.join();
        await first.receive('{"action":13,"channel":"$_room"}');
        await first.receive('{"action":13,"channel":"$_room"}');
        await _until(() => connector.channels.length == 2);
        final second = connector.channels.last;
        await second.receive(_connectedFrame);
        await second.receive(_error(9, 40142, 'Token expired'));
        await _until(() => connector.channels.length == 3);
        final third = connector.channels.last;
        await third.receive(_connectedFrame);
        expect(events.whereType<DanmakuClosed>(), isEmpty);
        await third.receive('{"action":13,"channel":"$_room","error":{"code":90198,"message":"Channel detached"}}');
        expect(
          events.last,
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Channel detached: 90198 Channel detached'),
        );
        expect(third.closed, isTrue);
        expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1', 'AAAAAA.token-2']);
      },
    );

    test('an attach after a DETACHED unanswered within the join limit drops the socket', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 200),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await _wait(const Duration(milliseconds: 300));
      expect(connector.channels, hasLength(1), reason: 'attached in time');
      await channel.receive('{"action":13,"channel":"$_room"}');
      await _wait(const Duration(milliseconds: 20));
      expect(connector.channels, hasLength(1));
      await _until(() => connector.channels.length == 2);
      expect(events, [const DanmakuReady(), const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      // The new socket's join timer: no ATTACHED within the limit either.
      await connector.channels.last.receive(_connectedFrame);
      await _until(() => connector.channels.length == 3);
      await connection.close();
    });

    test('AUTH asks a new token and sends it on the same socket; later sockets use it', () async {
      final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await channel.receive('{"action":17}');
      await _until(() => channel.sent.length == 2);
      expect(channel.sent.last, '{"action":17,"auth":{"accessToken":"AAAAAA.token-2"}}');
      expect(http.requests, hasLength(2));
      await channel.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-2']);
      expect(http.requests, hasLength(2));
      expect(events.first, const DanmakuReady());
      await connection.close();
    });

    test('AUTH whose token cannot be had sends nothing and keeps the socket', () async {
      final http = _Http([_granted('AAAAAA.token-1'), const SocketException('offline')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await channel.receive('{"action":17}');
      await _until(() => http.requests.length == 2);
      await _wait(const Duration(milliseconds: 20));
      expect(channel.sent, [_attach()]);
      expect(channel.closed, isFalse);
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('an attach unanswered for the join limit drops the socket', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 200),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.receive(_connectedFrame);
      await _until(() => connector.channels.length == 2);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-1']);
      await connector.channels.last.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('close while the token is asked: the request is cancelled; nothing opens or is reported', () async {
      final pending = Completer<LiveResponse>();
      final http = _Http([pending]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      pending.complete(_granted('AAAAAA.token-1'));
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('close: no events or frames afterwards, twice is harmless; another room asks its own token', () async {
      final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await connection.close();
      await connection.close();
      expect(first.closed, isTrue);
      final seen = events.length;
      first.incoming
        ..add(_ablyMessage([_comment('遅い')]))
        ..add('{"action":17}');
      await _wait(const Duration(milliseconds: 20));
      expect(events, hasLength(seen));
      expect(http.requests, hasLength(1));
      connection.heartbeat();
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: _archivedRoom));
      await connector.channels.last.receive(_connectedFrame);
      expect(connector.channels.last.sent, [_attach(_archivedRoom)]);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-2']);
      await connection.close();
    });

    test('connecting to another room closes the first socket; its late frames do nothing', () async {
      final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: _archivedRoom));
      expect(first.closed, isTrue);
      await connector.channels.last.join(_archivedRoom);
      first.incoming.add(_ablyMessage([_comment('古い部屋')]));
      await connector.channels.last.receive(_ablyMessage([_comment('新しい部屋')], room: _archivedRoom));
      expect(_messages(events).map((message) => message.message), ['新しい部屋']);
      await connection.close();
    });

    test('takes SeventeenLiveDanmakuArgs only; registers in DanmakuRegistry under 17live', () async {
      final connection = _connection(_Connector(), _Http([_granted('AAAAAA.token-1')]));
      await expectLater(
        connection.connect(const ChzzkDanmakuArgs(channelId: 'x', chatChannelId: 'y')),
        throwsArgumentError,
      );
      final registry = DanmakuRegistry({
        SiteIds.seventeenLive: () => SeventeenLiveDanmakuConnection(http: _Http([_granted('AAAAAA.token-1')])),
      });
      expect(registry.supports('17live'), isTrue);
      expect(registry.connectionFor('17live'), isA<SeventeenLiveDanmakuConnection>());
    });

    test('the proxy policy routes the handshake', () async {
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connector = _Connector();
      final connection = _connection(
        connector,
        _Http([_granted('AAAAAA.token-1')]),
        proxy: const FixedProxyPolicy(perSite: {SiteIds.seventeenLive: route}),
      );
      await connection.connect(_args);
      expect(connector.routes.single, route);
      await connection.close();
    });

    test('a local WebSocket server: the path, the query, the headers, the ATTACH and the recorded frames', () async {
      final handshakes = <Map<String, Object?>>[];
      final received = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final recorded = _received('S06-live');
      server.listen((request) async {
        handshakes.add({
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'origin': request.headers.value('origin'),
          'user-agent': request.headers.value('user-agent'),
        });
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket
          ..add(recorded.first.data)
          ..listen((frame) {
            received.add(frame as String);
            if (jsonDecode(frame) case {'action': 10}) {
              for (final frame in recorded.skip(1)) {
                socket.add(frame.data);
              }
            }
          });
      });
      final requested = <Uri>[];
      final connection = SeventeenLiveDanmakuConnection(
        http: _Http([_authAnswer('S06-live')]),
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
      await _until(() => _messages(events).length == 35);
      final token = SeventeenLiveDanmakuProtocol.grant(_authAnswer('S06-live'));
      expect(requested, [SeventeenLiveDanmakuProtocol.withToken(SeventeenLiveDanmakuProtocol.endpoints.first, token)]);
      expect(handshakes, [
        {
          'path': '/',
          'query': {'access_token': token, 'format': 'json', 'heartbeats': 'true', 'v': '3'},
          'origin': 'https://17.live',
          // dart:io adds the UA to its own (`Dart/3.13 (dart:io), …`), for
          // every platform on the default handshake.
          'user-agent': endsWith(SeventeenLiveApi.userAgent),
        },
      ]);
      expect(received, [_attach()]);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 20));
      expect(received, [_attach()], reason: 'the client sends no heartbeat');
      await connection.close();
    });
  });

  group('B-14: name colours and badges (F.5a)', () {
    test("S06-live: every comment carries its name's colour and the badges by the name", () {
      final comments = [
        for (final frame in _received('S06-live'))
          if (jsonDecode(frame.data as String) case {'action': 15, 'messages': final List<Object?> items})
            for (final item in items.cast<Map<String, Object?>>())
              if (SeventeenLiveDanmakuProtocol.payload(item['data']) case final payload? when payload['type'] == 3)
                (payload['commentMsg']! as Map<Object?, Object?>, item['id']),
      ];
      expect(comments, hasLength(26));
      for (final (comment, id) in comments) {
        final message = SeventeenLiveDanmakuProtocol.message({'type': 3, 'commentMsg': comment}, id: '$id')!;
        final hex = (comment['name']! as Map<Object?, Object?>)['textColor']! as String;
        expect(
          message.nameColor,
          hex.isEmpty ? isNull : LiveMessageColor.numberToColor(int.parse(hex.substring(3), radix: 16)),
          reason: hex,
        );
        expect(message.badges.every((badge) => badge.url.startsWith('https://')), isTrue);
      }
      // The first comment (观众4): a prefix badge, an attendance badge given
      // over http and a top-right badge; the empty places give nothing.
      final first = SeventeenLiveDanmakuProtocol.message({'type': 3, 'commentMsg': comments.first.$1})!;
      expect(first.nameColor, const LiveMessageColor(0x9e, 0x7b, 0xff));
      expect(first.badges, const [
        LiveBadge(url: 'https://cdn.17app.co/80fda54d-abdd-4141-bd15-7e3b9e09863b.png', id: '2607-vip-kumamoto_jp'),
        LiveBadge(url: 'https://cdn.17app.co/ee4041c4-2700-44ea-b931-13255d0f6ff6.png'),
        LiveBadge(url: 'https://cdn.17app.co/58953f7b-8f7c-4431-a806-c436e13a52ff.png', id: '2602-tw-race-badge'),
      ]);
      expect(
        comments.where(
          (entry) => SeventeenLiveDanmakuProtocol.message({'type': 3, 'commentMsg': entry.$1})!.badges.isNotEmpty,
        ),
        isNotEmpty,
      );
    });

    test('S05-live comments have neither; odd names and badges are left out', () {
      final messages = [
        for (final frame in _received('S05-live'))
          ...SeventeenLiveDanmakuProtocol.decode(frame.data, roomId: _archivedRoom).messages,
      ];
      expect(messages.every((message) => message.nameColor == null && message.badges.isEmpty), isTrue);
      expect(
        SeventeenLiveDanmakuProtocol.nameColor({'textColor': '#FF33CDBB'}),
        const LiveMessageColor(0x33, 0xcd, 0xbb),
      );
      expect(SeventeenLiveDanmakuProtocol.nameColor({'textColor': '9E7BFF'}), const LiveMessageColor(0x9e, 0x7b, 0xff));
      for (final odd in <Object?>[
        null,
        'x',
        {'textColor': ''},
        {'textColor': 'blue'},
        {'textColor': 3},
      ]) {
        expect(SeventeenLiveDanmakuProtocol.nameColor(odd), isNull, reason: '$odd');
      }
      final badges = SeventeenLiveDanmakuProtocol.badges({
        'prefixBadges': [
          {'URL': 'https://cdn.17app.co/a.png', 'styleID': 'a'},
          {'URL': 'https://evil.example/b.png', 'styleID': 'b'},
          'not a badge',
        ],
        'prefixBadge': {'URL': 'https://cdn.17app.co/a.png', 'styleID': 'a'},
        'middleBadge': {'URL': '', 'styleID': 'm'},
        'roleBadge': {'URL': 'https://assets-17app.akamaized.net/r.png', 'styleID': ''},
        'topRightBadge': {'URL': 7},
      });
      expect(badges, const [
        LiveBadge(url: 'https://cdn.17app.co/a.png', id: 'a'),
        LiveBadge(url: 'https://assets-17app.akamaized.net/r.png'),
      ]);
    });
  });

  group('B-14: paid barrages', () {
    test('S10-events: a paid barrage (barrageStyle, 79 points) is its chat line and a super chat', () {
      final line = _events10().firstWhere((line) => line.room == '26541295');
      final frame = SeventeenLiveDanmakuProtocol.decode(line.text, roomId: line.room);
      final entry = frame.entries.single;
      expect(entry.id, 'vE0tLXZYxKNU:0');
      final [chat, paid] = entry.messages;
      const text = 'マリス殿のリスナーの皆様もお疲れ様にござる(*´ω｀*) おめでとうにござる！ 良かったら、一緒に乾杯しませんか？にござる(*´ω｀*)';
      expect((chat.type, chat.message, chat.userName, chat.messageId), (LiveMessageType.chat, text, '观众1', entry.id));
      expect(paid.type, LiveMessageType.superChat);
      expect((paid.userName, paid.userId, paid.message, paid.messageId), ('观众1', _user(1), text, entry.id));
      expect(paid.sentAt, DateTime.fromMillisecondsSinceEpoch(1790782366575));
      final data = paid.data! as LiveSuperChatMessage;
      expect(data.messageId, 'vE0tLXZYxKNU:0');
      expect(data.userName, '观众1');
      expect(data.face, 'https://cdn.17app.co/THUMBNAIL_00000001-0000-4000-8000-000000000001.jpg');
      expect(data.message, text);
      expect((data.price, data.priceText), (79, '79 coins'));
      // D07.2: the unit of the platform table (superChatUnits).
      expect(data.unit, LiveGiftUnit.point);
      expect(superChatUnits[SiteIds.seventeenLive], data.unit);
      expect(data.startTime, DateTime.fromMillisecondsSinceEpoch(1790782366575));
      expect(data.endTime, DateTime.fromMillisecondsSinceEpoch(1790782366575 + 20000));
      expect((data.backgroundColor, data.backgroundBottomColor), ('#F518CC', '#F518CC'));
    });

    test('S10-events: free barrages (inventory 14 and 12, army 5, assistant 4, all 0 points) stay chat only', () {
      // Every recorded comment that flies (barrageStyle), with its entry.
      final barrages = [
        for (final line in _events10())
          if (_payloadOf(line.text) case {'type': 3, 'commentMsg': {'barrageStyle': true}} && final payload)
            (payload, SeventeenLiveDanmakuProtocol.decode(line.text, roomId: line.room).entries.single),
      ];
      expect(barrages, hasLength(5));
      final free = barrages.skip(1).map((barrage) => barrage.$2).toList();
      expect({for (final entry in free) entry.messages.single.type}, {LiveMessageType.chat});
      expect(
        [for (final entry in free) entry.messages.single.message],
        ['こんばんワン🐶', 'ライオンにしてもらった🤩', '戰隊成員們來支持 观众4 了，目前成就值戰隊加成為 1000！', '凌凌晚上好🌇'],
      );
      for (final (payload, entry) in barrages) {
        final comment = payload['commentMsg']! as Map<String, Object?>;
        final paid = ((comment['barrage']! as Map<String, Object?>)['point']! as int) > 0;
        expect(SeventeenLiveDanmakuProtocol.superChat(payload, id: 'x') != null, paid);
        expect(entry.messages.length, paid ? 2 : 1);
      }
    });

    test('the super chat field by field: what makes one, text, time, face, colour; bad data', () {
      final now = DateTime.utc(2026, 9, 30, 12);
      Map<String, Object?> paid({Map<String, Object?> more = const {}, Map<String, Object?> user = const {}}) =>
          _comment(
            '本文',
            more: {
              'barrageStyle': true,
              'barrage': {'type': 1, 'point': 79},
              'backgroundColor': '#B3F518CC',
              'displayUser': {'userID': _user(1), 'displayName': '观众1', 'picture': 'ab-cd.jpg', ...user},
              ...more,
            },
          );
      LiveMessage? read(Map<String, Object?> payload) =>
          SeventeenLiveDanmakuProtocol.superChat(payload, id: 'f:0', now: now);
      LiveSuperChatMessage data(Map<String, Object?> payload) => read(payload)!.data! as LiveSuperChatMessage;
      expect(read(paid()), isNotNull);
      // What makes one: barrageStyle true and a point above zero, shown.
      for (final more in <Map<String, Object?>>[
        {'barrageStyle': false},
        {'barrageStyle': 'true'},
        {'barrageStyle': null},
        {
          'barrage': {'type': 1, 'point': 0},
        },
        {
          'barrage': {'type': 1, 'point': -5},
        },
        {
          'barrage': {'type': 1, 'point': '79'},
        },
        {
          'barrage': {'type': 1, 'point': 7.9},
        },
        {
          'barrage': {'type': 1},
        },
        {'barrage': 'x'},
        {'isDirty': true},
        {'isDirtyUser': true},
        {'content': '', 'comment': <String, Object?>{}},
      ]) {
        expect(read(paid(more: more)), isNull, reason: '$more');
      }
      expect(read(const {'type': 38, 'liveinfo': <String, Object?>{}}), isNull);
      expect(read({...paid(), 'type': 13}), isNull);
      // The text is comment.text with line breaks as spaces; content without it.
      expect(
        data(
          paid(
            more: {
              'content': '一\n二',
              'comment': {'text': '\n一\n二\n'},
            },
          ),
        ).message,
        '一 二',
      );
      expect(
        read(
          paid(
            more: {
              'content': '内容',
              'comment': {'text': '  '},
            },
          ),
        )!.message,
        '内容',
      );
      // The time: sendTime, else now; 20 s.
      expect(data(paid()).startTime, DateTime.fromMillisecondsSinceEpoch(_t + 1));
      final untimed = data(paid(more: {'sendTime': null}));
      expect((untimed.startTime, untimed.endTime), (now, now.add(const Duration(seconds: 20))));
      expect(read(paid(more: {'sendTime': null}))!.sentAt, isNull);
      // The face as the website builds it; a URL of its own is kept when it is
      // the platform's.
      expect(data(paid()).face, 'https://cdn.17app.co/THUMBNAIL_ab-cd.jpg');
      expect(data(paid(user: {'picture': 'http://cdn.17app.co/a.jpg'})).face, 'https://cdn.17app.co/a.jpg');
      expect(data(paid(user: {'picture': 'https://evil.example/a.jpg'})).face, isEmpty);
      expect(data(paid(user: {'picture': '../x.jpg'})).face, isEmpty);
      expect(data(paid(user: {'picture': ''})).face, isEmpty);
      expect(data(paid(user: {'picture': 5})).face, isEmpty);
      // The colour is the comment's own background, #RRGGBB.
      final colours = <Object?, String>{
        '#B3F518CC': '#F518CC',
        'ff69b4': '#FF69B4',
        ' #FFff69b4 ': '#FF69B4',
        '#FFF': '',
        'red': '',
        '': '',
        0xF518CC: '',
        null: '',
      };
      for (final MapEntry(key: value, value: colour) in colours.entries) {
        expect(SeventeenLiveDanmakuProtocol.backgroundColor(value), colour, reason: '$value');
        final fill = data(paid(more: {'backgroundColor': value}));
        expect((fill.backgroundColor, fill.backgroundBottomColor), (colour, colour), reason: '$value');
      }
      // The price text is the website's, the price the point.
      final big = data(
        paid(
          more: {
            'barrage': {'type': 2, 'point': 12000},
          },
        ),
      );
      expect((big.price, big.priceText), (12000, '12000 coins'));
      // The chat line comes first and stays as it was (M5.29).
      final entry = SeventeenLiveDanmakuProtocol.entry(paid(), id: 'f:0', now: now);
      expect([for (final message in entry.messages) message.type], [LiveMessageType.chat, LiveMessageType.superChat]);
      expect(
        [for (final message in entry.messages) message.messageId],
        ['f:0', 'f:0'],
        reason: 'one Ably message: the super chat equals itself by id, the chat line passes the gate by id',
      );
    });
  });

  group('B-14: stream end and mute', () {
    test('S10-events: the stream end (5) is an ended entry, whatever it holds', () {
      final ends = [
        for (final line in _events10())
          for (final entry in SeventeenLiveDanmakuProtocol.decode(line.text, roomId: line.room).entries)
            if (entry.ended) (line.room, entry.id),
      ];
      expect(ends, [('29648148', 'zdKdlmh20KsD:0'), ('14786082', '6q2XGMQ8l51z:0')]);
      for (final payload in <Map<String, Object?>>[
        const {'type': 5},
        const {'type': 5, 'endStreamMsg': 'x'},
        const {
          'type': 5,
          'endStreamMsg': {'closeBy': 'KillBySkyeye', 'reason': 'x'},
        },
      ]) {
        final entry = SeventeenLiveDanmakuProtocol.entry(payload, id: 'e:0');
        expect((entry.ended, entry.messages.length, entry.muted), (true, 0, null), reason: '$payload');
      }
      for (final type in <Object?>['5', 5.5, 6, null]) {
        expect(SeventeenLiveDanmakuProtocol.entry({'type': type}).ended, isFalse, reason: '$type');
      }
      // A JSON 5.0 is the website's 5 as well (a JavaScript number).
      expect(SeventeenLiveDanmakuProtocol.entry(const {'type': 5.0}).ended, isTrue);
    });

    test('the live figures carry liveinfo.mute when it is a boolean; the notice fills the model', () {
      Map<String, Object?> live(Object? mute) => {
        'type': 38,
        'liveinfo': {'mute': mute, 'liveViewerCount': 10},
      };
      expect(SeventeenLiveDanmakuProtocol.entry(live(true)).muted, isTrue);
      expect(SeventeenLiveDanmakuProtocol.entry(live(false)).muted, isFalse);
      for (final mute in <Object?>['true', 1, null]) {
        expect(SeventeenLiveDanmakuProtocol.entry(live(mute)).muted, isNull, reason: '$mute');
      }
      expect(SeventeenLiveDanmakuProtocol.entry(const {'type': 38, 'liveinfo': 'x'}).muted, isNull);
      expect(SeventeenLiveDanmakuProtocol.entry(live(true)).messages.single.type, LiveMessageType.online);
      final on = SeventeenLiveDanmakuProtocol.muteNotice(muted: true, id: 'm:0');
      expect(on.type, LiveMessageType.notice);
      expect(on.data, LiveNoticeKind.system);
      expect(on.message, SeventeenLiveDanmakuProtocol.mutedNotice);
      // What the stream does while muted (measured): a still picture, no sound.
      expect(SeventeenLiveDanmakuProtocol.mutedNotice, '主播暂停了直播（画面静止、没有声音）');
      expect(SeventeenLiveDanmakuProtocol.unmutedNotice, '主播恢复了直播');
      expect(
        (on.userName, on.userId, on.messageId, on.color, on.sentAt),
        ('', '', 'm:0', LiveMessageColor.white, null),
      );
      final off = SeventeenLiveDanmakuProtocol.muteNotice(muted: false);
      expect(
        (off.message, off.data, off.messageId),
        (SeventeenLiveDanmakuProtocol.unmutedNotice, LiveNoticeKind.system, ''),
      );
      expect(on.message, isNot(off.message));
    });

    test('the stream end ends the run with connectionFailed: what came before it is shown, nothing after', () async {
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await channel.receive(
        _ablyMessage([
          _comment('前'),
          const {'type': 5, 'endStreamMsg': <String, Object?>{}},
          _comment('後', n: 2),
        ]),
      );
      expect(events, [
        const DanmakuReady(),
        isA<DanmakuReceived>().having((event) => event.message.message, 'text', '前'),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended'),
      ]);
      expect(SeventeenLiveDanmakuConnection.broadcastEnded, 'Broadcast ended');
      expect(channel.closed, isTrue);
      await channel.receive(_ablyMessage([_comment('遅い')], id: 'later'));
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(3));
      expect(connector.channels, hasLength(1), reason: 'no reconnect');
      expect(connection.status, DanmakuStatus.closed);
    });

    test("S10-events: the recorded stream end ends its room's run", () async {
      final line = _events10().firstWhere((line) => line.room == '29648148');
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(SeventeenLiveDanmakuArgs(roomId: line.room));
      await connector.channels.single.join(line.room);
      await connector.channels.single.receive(line.text);
      expect(events.last, const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended'));
    });

    test('mute: a notice when it turns true, and when it turns false again; once per change; per run', () async {
      Map<String, Object?> live(Object? mute) => {
        'type': 38,
        'liveinfo': {'mute': mute, 'liveViewerCount': 10},
      };
      final http = _Http([_granted('AAAAAA.token-1')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      var n = 0;
      Future<void> send(Object? mute) => channel.receive(_ablyMessage([live(mute)], id: 'live${n++}'));
      List<String> notices() => [
        for (final message in _messages(events))
          if (message.type == LiveMessageType.notice) '${message.messageId} ${message.message}',
      ];
      await send(false);
      await send(null);
      expect(notices(), isEmpty, reason: 'false at first is the usual state');
      await send(true);
      await send(true);
      await send('true');
      await send(false);
      await send(false);
      await send(true);
      expect(notices(), [
        'live2:0 ${SeventeenLiveDanmakuProtocol.mutedNotice}',
        'live5:0 ${SeventeenLiveDanmakuProtocol.unmutedNotice}',
        'live7:0 ${SeventeenLiveDanmakuProtocol.mutedNotice}',
      ]);
      // Each live figure is still the viewers now, before its notice.
      expect(_messages(events).where((message) => message.type == LiveMessageType.online), hasLength(8));
      expect(_messages(events)[2].type, LiveMessageType.online);
      expect(_messages(events)[3].type, LiveMessageType.notice);
      // The same message again (a resume): nothing.
      await channel.receive(_ablyMessage([live(false)], id: 'live5'));
      expect(notices(), hasLength(3));
      // Another run starts afresh.
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: _archivedRoom));
      await connector.channels.last.join(_archivedRoom);
      await connector.channels.last.receive(_ablyMessage([live(true)], room: _archivedRoom, id: 'other'));
      expect(notices().last, 'other:0 ${SeventeenLiveDanmakuProtocol.mutedNotice}');
      await connection.close();
    });

    test('S10-events: the recorded mute on and off (liveinfo type 0), viewers writing between', () async {
      const room = '29802206';
      final lines = [
        for (final line in _events10())
          if (line.room == room) line.text,
      ];
      expect(lines, hasLength(4));
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: room));
      await connector.channels.single.join(room);
      for (final line in lines) {
        await connector.channels.single.receive(line);
      }
      expect(
        [
          for (final message in _messages(events))
            switch (message.type) {
              LiveMessageType.online => 'online ${(message.data! as LiveAudienceUpdate).value}',
              LiveMessageType.notice => 'notice ${message.message}',
              _ => '${message.type.name} ${message.message}',
            },
        ],
        [
          // The mute messages are live figures of type 0 with every figure 0;
          // the website shows those zeros as well. B-25: they are not
          // reported (were 'online 0' before each notice); the last count
          // stays.
          'notice ${SeventeenLiveDanmakuProtocol.mutedNotice}',
          'chat みんなコメントしなければ行く説',
          'chat また帰ってきたらコメント追うのに忙しくなってそう笑',
          'notice ${SeventeenLiveDanmakuProtocol.unmutedNotice}',
        ],
      );
      await connection.close();
    });

    test('a paid barrage through the connection: its chat line, then its super chat', () async {
      final line = _events10().firstWhere((line) => line.room == '26541295');
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(SeventeenLiveDanmakuArgs(roomId: line.room));
      await connector.channels.single.join(line.room);
      await connector.channels.single.receive(line.text);
      expect(
        [for (final message in _messages(events)) message.type],
        [LiveMessageType.chat, LiveMessageType.superChat],
      );
      await connection.close();
    });

    test('a super chat without its own time starts at the connection clock', () async {
      final clock = DateTime.utc(2026, 9, 30, 15, 32, 46);
      final connector = _Connector();
      final connection = SeventeenLiveDanmakuConnection(
        http: _Http([_granted('AAAAAA.token-1')]),
        connector: connector.call,
        policy: _quiet,
        now: () => clock,
      );
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive(
        _ablyMessage([
          _comment(
            '時間なし',
            more: {
              'sendTime': null,
              'barrageStyle': true,
              'barrage': {'type': 0, 'point': 10},
            },
          ),
        ]),
      );
      final paid = _messages(events).last.data! as LiveSuperChatMessage;
      expect((paid.startTime, paid.endTime), (clock, clock.add(SeventeenLiveDanmakuProtocol.superChatDuration)));
      await connection.close();
    });
  });

  group('B-14: resume', () {
    test('the resume query, the resuming ATTACH and the frames that carry a serial', () {
      final endpoint = SeventeenLiveDanmakuProtocol.endpoints.first;
      expect(
        '${SeventeenLiveDanmakuProtocol.withToken(endpoint, 'app.tok', resume: 'KEY!abc-12')}',
        'wss://17media.realtime.ably.net/?access_token=app.tok&resume=KEY%21abc-12&format=json&heartbeats=true&v=3',
      );
      expect(
        '${SeventeenLiveDanmakuProtocol.withToken(endpoint, 'app.tok')}',
        'wss://17media.realtime.ably.net/?access_token=app.tok&format=json&heartbeats=true&v=3',
      );
      expect(SeventeenLiveDanmakuProtocol.attach('1'), '{"action":10,"channel":"1"}');
      expect(SeventeenLiveDanmakuProtocol.attach('1', resume: true), '{"action":10,"channel":"1","flags":32}');
      expect(
        SeventeenLiveDanmakuProtocol.attach('1', channelSerial: 's', resume: true),
        '{"action":10,"channel":"1","channelSerial":"s","flags":32}',
      );
      expect(
        SeventeenLiveDanmakuProtocol.attach('1', channelSerial: 's'),
        '{"action":10,"channel":"1","channelSerial":"s"}',
      );
      expect((SeventeenLiveDanmakuProtocol.attachResumeFlag, SeventeenLiveDanmakuProtocol.resumedFlag), (32, 4));
      expect(SeventeenLiveDanmakuProtocol.defaultConnectionStateTtl, const Duration(seconds: 120));
      expect(SeventeenLiveDanmakuProtocol.superChatDuration, const Duration(seconds: 20));
      SeventeenLiveDanmakuFrame read(Object data) => SeventeenLiveDanmakuProtocol.decode(data, roomId: _room);
      expect(read(_attachedFrame(_room)).channelSerial, _joinedSerial);
      expect(read(_ablyMessage([_comment('x')])).channelSerial, isNull, reason: 'the helper sends none');
      expect(read('{"action":15,"channel":"$_room","channelSerial":"m1","messages":[]}').channelSerial, 'm1');
      expect(read('{"action":14,"channel":"$_room","channelSerial":"p1","presence":[]}').channelSerial, 'p1');
      expect(read('{"action":16,"channel":"$_room","channelSerial":"s1"}').channelSerial, isNull);
      expect(read('{"action":15,"channel":"1","channelSerial":"o1","messages":[]}').channelSerial, isNull);
      for (final serial in <Object?>['', 5, null]) {
        expect(
          read(jsonEncode({'action': 11, 'channel': _room, 'channelSerial': serial})).channelSerial,
          isNull,
          reason: '$serial',
        );
      }
      for (final (flags, resumed) in <(Object?, bool)>[
        (786438, true),
        (4, true),
        (786432, false),
        (786434, false),
        ('786438', false),
        (null, false),
      ]) {
        expect(read(jsonEncode({'action': 11, 'channel': _room, 'flags': flags})).resumed, resumed, reason: '$flags');
      }
    });

    test('CONNECTED: the connection id, key and times; missing or bad fields', () {
      final connected = SeventeenLiveDanmakuProtocol.decode(_connectedFrame, roomId: _room);
      expect(connected.connection, const SeventeenLiveConnectionDetails(id: 'pa6jde0UNT', key: _connectedKey));
      expect(connected.error, isNull);
      String frame(Map<String, Object?> details, {Object? id = 'id1'}) =>
          jsonEncode({'action': 4, 'connectionId': ?id, 'connectionDetails': details});
      SeventeenLiveConnectionDetails? read(String text) =>
          SeventeenLiveDanmakuProtocol.decode(text, roomId: _room).connection;
      expect(
        read(frame({'connectionKey': 'k', 'connectionStateTtl': 60000, 'maxIdleInterval': 5000})),
        const SeventeenLiveConnectionDetails(
          id: 'id1',
          key: 'k',
          stateTtl: Duration(seconds: 60),
          maxIdleInterval: Duration(seconds: 5),
        ),
      );
      for (final bad in <Object?>[0, -1, '60000', 86400001, null]) {
        final details = read(frame({'connectionKey': 'k', 'connectionStateTtl': bad, 'maxIdleInterval': bad}))!;
        expect(
          (details.stateTtl, details.maxIdleInterval),
          (const Duration(seconds: 120), const Duration(seconds: 15)),
          reason: '$bad',
        );
      }
      expect(read(frame({'connectionKey': 'k', 'connectionStateTtl': 86400000}))!.stateTtl, const Duration(days: 1));
      expect(read(frame({'connectionKey': 'k'}, id: null)), isNull);
      expect(read(frame({'connectionKey': 'k'}, id: '')), isNull);
      expect(read(frame({'connectionKey': 'k'}, id: 7)), isNull);
      expect(read(frame({'connectionKey': ''})), isNull);
      expect(read(frame({})), isNull);
      expect(read('{"action":4,"connectionId":"x","connectionDetails":"k"}'), isNull);
      expect(SeventeenLiveDanmakuProtocol.decode('{"action":4}', roomId: _room).signal, SeventeenLiveSignal.connected);
    });

    test('S09-resume-bad-key: a key that names no connection gets a new one and 80018', () {
      final lines = _lines('S09-resume-bad-key');
      final frames = [
        for (final line in lines)
          if (line['dir'] == 'in' && line['url'] == null)
            SeventeenLiveDanmakuProtocol.decode(line['text'], roomId: '29790476'),
      ];
      final connected = frames.first;
      expect(connected.signal, SeventeenLiveSignal.connected);
      expect(connected.connection!.id, 'LvPs1M0e80');
      expect(
        connected.error,
        const SeventeenLiveAblyError(
          code: 80018,
          statusCode: 400,
          message: 'invalid connection key: 4abAAAAAAAAAAA!AAAAAAAAAAAAAAAAAAAAAAAAAAA-000000',
        ),
      );
      expect(connected.error!.isTokenError, isFalse);
      expect((frames[1].signal, frames[1].resumed), (SeventeenLiveSignal.attached, false));
    });

    test(
      'S08-resume: every later socket resumes; the missed messages come once; 150 s of silence starts afresh',
      () async {
        const name = 'S08-resume';
        const room = '29790476';
        final lines = _lines(name);
        final start = DateTime.parse(_meta(name)['capturedAt']! as String);
        final handshakes = [
          for (final handshake in (_meta(name)['handshakes']! as List<Object?>).cast<Map<String, Object?>>())
            handshake['url']! as String,
        ];
        var clock = start;
        final connector = _Connector();
        final connection = SeventeenLiveDanmakuConnection(
          http: _Http([
            LiveResponse(
              status: 200,
              url: SeventeenLiveDanmakuProtocol.authUrl,
              bytes: utf8.encode(lines.first['text']! as String),
            ),
          ]),
          connector: connector.call,
          policy: _quiet,
          now: () => clock,
        );
        final events = _record(connection);
        await connection.connect(const SeventeenLiveDanmakuArgs(roomId: room));
        List<Map<String, Object?>> of(int socket, String dir) => [
          for (final line in lines)
            if (line['socket'] == socket && line['dir'] == dir) line,
        ];
        final keys = <String>[];
        for (var socket = 1; socket <= 5; socket++) {
          await _until(() => connector.channels.length == socket);
          final channel = connector.channels.last;
          for (final line in of(socket, 'in')) {
            clock = start.add(Duration(milliseconds: line['t']! as int));
            await channel.receive(line['text']!);
            if (jsonDecode(line['text']! as String) case {
              'action': 4,
              'connectionDetails': {'connectionKey': final String key},
            }) {
              keys.add(key);
            }
          }
          final recorded = [for (final line in of(socket, 'out')) line['text']];
          switch (socket) {
            case 1 || 2 || 3 || 4:
              // The ATTACH is the recorder's, byte for byte: from the last
              // serial with ATTACH_RESUME after the first.
              expect(channel.sent, recorded, reason: 'socket $socket');
            case 5:
              // 150 s after the last frame (more than 120 s + 15 s): ably-js
              // forgets the connection and the channel's serial; the recorder
              // did not, and the server answered 90003 with its backlog.
              expect(channel.sent, ['{"action":10,"channel":"$room","flags":32}']);
          }
          if (socket < 5) {
            // The next socket opens at the recorded time.
            final next = lines.firstWhere((line) => line['socket'] == socket + 1);
            clock = start.add(Duration(milliseconds: next['t']! as int));
            await channel.incoming.close();
          }
        }
        final resumes = [for (final endpoint in connector.endpoints) endpoint.queryParameters['resume']];
        expect(resumes, [null, keys[0], keys[1], keys[2], null]);
        // The recorder's first two handshakes, byte for byte; the third
        // resumed a key with its end changed and the fourth none (probes).
        expect('${connector.endpoints[0]}', handshakes[0]);
        expect('${connector.endpoints[1].replace(host: '17media.realtime.ably.net')}', handshakes[1]);
        expect(Uri.parse(handshakes[2]).queryParameters['resume'], isNot(keys[1]));
        expect(Uri.parse(handshakes[3]).queryParameters['resume'], isNull);
        expect(Uri.parse(handshakes[4]).queryParameters['resume'], keys[3]);
        // The same connection went on (the recorder's C and B), then a new one.
        expect({for (final key in keys) key.split('!').last.substring(0, 10)}, {'X-E5s1H2ZI', '3iJ42NoCkm'});
        final messages = _messages(events);
        final ids = [
          for (final message in messages)
            if (message.messageId.isNotEmpty) message.messageId,
        ];
        expect(ids.toSet(), hasLength(ids.length));
        expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(8));
        expect(messages.where((message) => message.type == LiveMessageType.online), hasLength(6));
        expect(events.whereType<DanmakuReady>(), hasLength(5));
        expect(events.whereType<DanmakuReconnecting>(), hasLength(4));
        expect(events.whereType<DanmakuClosed>(), isEmpty);
        // The channel went on at sockets 2 to 4 (RESUMED, the missed
        // messages first); at 5 the server could not (90003) and sent its
        // backlog instead.
        final attached = [
          for (final line in lines)
            if (line['dir'] == 'in' && line['url'] == null)
              if (SeventeenLiveDanmakuProtocol.decode(line['text'], roomId: room) case final frame
                  when frame.signal == SeventeenLiveSignal.attached)
                (frame.resumed, frame.error?.code),
        ];
        expect(attached, [(false, null), (true, null), (true, null), (true, null), (false, 90003)]);
        await connection.close();
      },
    );

    test('a message sent again (after a resume, or twice) is reported once; one without an id each time', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await first.receive(_ablyMessage([_comment('一'), _comment('二', n: 2)], id: 'a'));
      await first.receive(_ablyMessage([_comment('一'), _comment('二', n: 2)], id: 'a'));
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      await second.join();
      // The backlog repeats a message already shown, then a new one.
      await second.receive(
        jsonEncode({
          'action': 15,
          'channel': _room,
          'messages': [
            {'id': 'a:1', 'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(_comment('二', n: 2)))))},
            {'id': 'b:0', 'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(_comment('三', n: 3)))))},
          ],
        }),
      );
      // Neither the message nor the frame has an id: nothing to compare.
      for (var n = 0; n < 2; n++) {
        await second.receive(
          jsonEncode({
            'action': 15,
            'channel': _room,
            'messages': [
              {'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(_comment('四', n: 4)))))},
            ],
          }),
        );
      }
      expect(_messages(events).map((message) => '${message.messageId}=${message.message}'), [
        'a:0=一',
        'a:1=二',
        'b:0=三',
        '=四',
        '=四',
      ]);
      await connection.close();
    });

    test('a resume that fails (S09: a new connection, 80018) attaches from the serial all the same', () async {
      final lines = _lines('S09-resume-bad-key');
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: '29790476'));
      final first = connector.channels.single;
      await first.receive(_connectedFrame);
      await first.receive(_attachedFrame('29790476'));
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.endpoints.last.queryParameters['resume'], _connectedKey);
      final second = connector.channels.last;
      for (final line in lines.where((line) => line['dir'] == 'in' && line['url'] == null)) {
        await second.receive(line['text']!);
      }
      expect(second.sent, [_resumeAttach(_joinedSerial, '29790476')]);
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      // The next socket resumes the new connection.
      await second.incoming.close();
      await _until(() => connector.channels.length == 3);
      expect(connector.endpoints.last.queryParameters['resume'], startsWith('4abPf7l3YM04ZY!LvPs1M0e80'));
      await connection.close();
    });

    test(
      'silence: at 135 s after the last frame the key is resumed, 1 ms later it and the serial are forgotten',
      () async {
        final start = DateTime.utc(2026, 9, 30, 15);
        var clock = start;
        final connector = _Connector();
        final connection = SeventeenLiveDanmakuConnection(
          http: _Http([_granted('AAAAAA.token-1')]),
          connector: connector.call,
          policy: _quiet,
          now: () => clock,
        );
        await connection.connect(_args);
        await connector.channels.single.join();
        clock = start.add(const Duration(seconds: 135));
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2);
        expect(connector.endpoints.last.queryParameters['resume'], _connectedKey);
        await connector.channels.last.receive(_connectedFrame);
        expect(connector.channels.last.sent, [_resumeAttach(_joinedSerial)]);
        clock = clock.add(const Duration(seconds: 135, milliseconds: 1));
        await connector.channels.last.incoming.close();
        await _until(() => connector.channels.length == 3);
        expect(connector.endpoints.last.queryParameters.containsKey('resume'), isFalse);
        await connector.channels.last.receive(_connectedFrame);
        expect(connector.channels.last.sent, [_resumeAttach(null)]);
        await connection.close();
      },
    );

    test("silence: the limit is the CONNECTED's own connectionStateTtl + maxIdleInterval", () async {
      final start = DateTime.utc(2026, 9, 30, 15);
      var clock = start;
      final connector = _Connector();
      final connection = SeventeenLiveDanmakuConnection(
        http: _Http([_granted('AAAAAA.token-1')]),
        connector: connector.call,
        policy: _quiet,
        now: () => clock,
      );
      String connected(String key) => jsonEncode({
        'action': 4,
        'connectionId': 'short',
        'connectionDetails': {'connectionKey': key, 'connectionStateTtl': 60000, 'maxIdleInterval': 5000},
      });
      await connection.connect(_args);
      await connector.channels.single.receive(connected('short!1'));
      await connector.channels.single.receive(_attachedFrame(_room));
      clock = start.add(const Duration(seconds: 65));
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.endpoints.last.queryParameters['resume'], 'short!1');
      await connector.channels.last.receive(connected('short!2'));
      clock = clock.add(const Duration(seconds: 65, milliseconds: 1));
      await connector.channels.last.incoming.close();
      await _until(() => connector.channels.length == 3);
      expect(connector.endpoints.last.queryParameters['resume'], isNull);
      await connection.close();
    });

    test('a token error keeps the resume: a new token, the same key', () async {
      final http = _Http([_granted('AAAAAA.token-1'), _granted('AAAAAA.token-2')]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive(_error(6, 40142, 'Token expired'));
      await _until(() => connector.channels.length == 2);
      expect(connector.tokens, ['AAAAAA.token-1', 'AAAAAA.token-2']);
      expect(connector.endpoints.last.queryParameters['resume'], _connectedKey);
      await connector.channels.last.receive(_connectedFrame);
      expect(connector.channels.last.sent, [_resumeAttach(_joinedSerial)]);
      await connection.close();
    });

    test('an ATTACH unanswered in time forgets the serial; a socket that never said CONNECTED keeps it', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        _Http([_granted('AAAAAA.token-1')]),
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 1000),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.incoming.close();
      // No CONNECTED within the limit: the serial is kept.
      await _until(() => connector.channels.length == 2);
      await _until(() => connector.channels.length == 3);
      await connector.channels.last.receive(_connectedFrame);
      expect(connector.channels.last.sent, [_resumeAttach(_joinedSerial)]);
      // That ATTACH unanswered within the limit: the serial is forgotten.
      await _until(() => connector.channels.length == 4);
      expect(connector.endpoints.last.queryParameters['resume'], _connectedKey);
      await connector.channels.last.receive(_connectedFrame);
      expect(connector.channels.last.sent, [_resumeAttach(null)]);
      await connection.close();
    });

    test('a failed resuming handshake: neither the token nor the key in the detail', () async {
      const key = 'AbC!de/f+g-1';
      final connector = _Connector(
        fail: (endpoint) => endpoint.queryParameters.containsKey('resume')
            ? WebSocketException("Connection to '${endpoint.replace(scheme: 'https')}' was not upgraded ($key)")
            : null,
      );
      final connection = _connection(connector, _Http([_granted('AAAAAA.token/1+')]));
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.receive(
        jsonEncode({
          'action': 4,
          'connectionId': 'id',
          'connectionDetails': {'connectionKey': key},
        }),
      );
      await connector.channels.single.incoming.close();
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      final detail = events.whereType<DanmakuClosed>().single.detail;
      expect(detail, contains('resume=<key>'));
      expect(detail, contains('access_token=<token>'));
      expect(detail, endsWith('(<key>)'));
      for (final secret in [key, Uri.encodeQueryComponent(key), 'token/1', 'token%2F1']) {
        expect(detail, isNot(contains(secret)), reason: secret);
      }
    });

    test('a local WebSocket server: the dropped socket comes back with resume and the resuming ATTACH', () async {
      final queries = <String>[];
      final received = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        queries.add(request.uri.query);
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        final number = sockets.length;
        socket
          ..add(_connectedFrame)
          ..listen((frame) {
            received.add(frame as String);
            socket
              ..add(
                jsonEncode({
                  'action': 11,
                  'channel': _room,
                  'channelSerial': 'serial-$number',
                  'flags': number == 1 ? 786432 : 786438,
                }),
              )
              ..add(_ablyMessage([_comment('第$number')], id: 'm$number'));
            if (number == 1) unawaited(socket.close(1011));
          });
      });
      final connection = SeventeenLiveDanmakuConnection(
        http: _Http([_granted('AAAAAA.token-1')]),
        policy: _quiet,
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
      await connection.connect(_args);
      await _until(() => _messages(events).length == 2);
      expect(queries, [
        'access_token=AAAAAA.token-1&format=json&heartbeats=true&v=3',
        'access_token=AAAAAA.token-1&resume=KMHu-BpmDaCyjV%21aAkFypXTcZHBDW_PeCuyrh-sUc2qJ&format=json&heartbeats=true&v=3',
      ]);
      expect(received, [_attach(), _resumeAttach('serial-1')]);
      expect(_messages(events).map((message) => message.message), ['第1', '第2']);
      await connection.close();
    });
  });

  group('B-25: the viewers while the stream is paused', () {
    Map<String, Object?> live(Object? mute, int viewers) => {
      'type': 38,
      'liveinfo': {'mute': ?mute, 'liveViewerCount': viewers},
    };
    String shown(LiveMessage message) => switch (message.data) {
      LiveAudienceUpdate(:final value) => 'online $value',
      _ =>
        message.message == SeventeenLiveDanmakuProtocol.mutedNotice
            ? 'paused'
            : message.message == SeventeenLiveDanmakuProtocol.unmutedNotice
            ? 'resumed'
            : message.message,
    };

    test('while paused, and in the figures that end the pause, a count of 0 is not reported; others are', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      var n = 0;
      Future<void> send(Map<String, Object?> payload) => channel.receive(_ablyMessage([payload], id: 'live${n++}'));
      await send(live(false, 100));
      await send(live(true, 0));
      // Without mute, while paused.
      await send(live(null, 0));
      // Not 0: a count.
      await send(live(true, 50));
      await send(_comment('まだかな'));
      // The pause ends with figures of 0 as well.
      await send(live(false, 0));
      // Not paused: a 0 is a 0.
      await send(live(false, 0));
      await send(live(null, 120));
      expect(_messages(events).map(shown), [
        'online 100',
        'paused',
        'online 50',
        'まだかな',
        'resumed',
        'online 0',
        'online 120',
      ]);
      // Another run that starts paused: nothing to keep, nothing reported.
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: _archivedRoom));
      await connector.channels.last.join(_archivedRoom);
      final before = _messages(events).length;
      await connector.channels.last.receive(_ablyMessage([live(true, 0)], room: _archivedRoom, id: 'other'));
      expect(_messages(events).skip(before).map(shown), ['paused']);
      await connection.close();
    });

    test('S10-events: the recorded pause of 29802206 reports no 0; the next count after it is reported', () async {
      const room = '29802206';
      final connector = _Connector();
      final connection = _connection(connector, _Http([_granted('AAAAAA.token-1')]));
      final events = _record(connection);
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: room));
      await connector.channels.single.join(room);
      await connector.channels.single.receive(_ablyMessage([live(false, 612)], room: room, id: 'before'));
      for (final line in _events10()) {
        if (line.room == room) await connector.channels.single.receive(line.text);
      }
      await connector.channels.single.receive(_ablyMessage([live(false, 598)], room: room, id: 'after'));
      expect(_messages(events).map(shown), [
        'online 612',
        'paused',
        'みんなコメントしなければ行く説',
        'また帰ってきたらコメント追うのに忙しくなってそう笑',
        'resumed',
        'online 598',
      ]);
      // Both recorded figures are 0 (liveinfo type 0), the second not paused.
      final figures = [
        for (final line in _events10())
          if (line.room == room)
            for (final entry in SeventeenLiveDanmakuProtocol.decode(line.text, roomId: room).entries)
              if (entry.muted != null) (entry.muted, (entry.messages.single.data! as LiveAudienceUpdate).value),
      ];
      expect(figures, [(true, 0), (false, 0)]);
      await connection.close();
    });
  });

  group('B-26: the backlog after a resume is replayed', () {
    /// A `MESSAGE` whose messages have their own times (null: none), the
    /// frame [frameTime] (null: none).
    String timed(
      List<(Map<String, Object?>, int?)> items, {
      int? frameTime,
      String id = 'frame',
      String room = _room,
    }) => jsonEncode({
      'action': 15,
      'id': id,
      'channel': room,
      'timestamp': ?frameTime,
      'messages': [
        for (final (index, (payload, time)) in items.indexed)
          {'id': '$id:$index', 'timestamp': ?time, 'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))))},
      ],
    });

    String attached(int flags) =>
        jsonEncode({'action': 11, 'channel': _room, 'channelSerial': _joinedSerial, 'flags': flags});

    test('ATTACHED: the HAS_BACKLOG flag, apart from RESUMED', () {
      expect(SeventeenLiveDanmakuProtocol.hasBacklogFlag, 2);
      for (final (flags, backlog, resumed) in <(Object?, bool, bool)>[
        (786438, true, true),
        (786434, true, false),
        (786436, false, true),
        (786432, false, false),
        (2, true, false),
        ('786438', false, false),
        (null, false, false),
      ]) {
        final frame = SeventeenLiveDanmakuProtocol.decode(
          jsonEncode({'action': 11, 'channel': _room, 'flags': flags}),
          roomId: _room,
        );
        expect((frame.backlog, frame.resumed), (backlog, resumed), reason: '$flags');
      }
      // The recordings: the first attach has none; every resume (S08 2 to 4)
      // and the one that could not resume (S08 5, 90003) have one.
      final flags = [
        for (final line in _lines('S08-resume'))
          if (line['dir'] == 'in' && line['url'] == null)
            if (SeventeenLiveDanmakuProtocol.decode(line['text'], roomId: '29790476') case final frame
                when frame.signal == SeventeenLiveSignal.attached)
              frame.backlog,
      ];
      expect(flags, [false, true, true, true, true]);
    });

    test('decode: what Ably published before the attach is replayed, up to the first published at it or later', () {
      final attach = DateTime.fromMillisecondsSinceEpoch(_t);
      final frame = SeventeenLiveDanmakuProtocol.decode(
        timed([
          (_comment('前'), _t - 5000),
          (
            _comment(
              '付き',
              more: {
                'barrageStyle': true,
                'barrage': {'type': 1, 'point': 79},
              },
            ),
            _t - 3000,
          ),
          (
            const {
              'type': 38,
              'liveinfo': {'mute': true, 'liveViewerCount': 5},
            },
            _t - 1,
          ),
          // No time of its own, the frame has none: it cannot tell.
          (_comment('不明'), null),
          (_comment('今'), _t),
          (_comment('順不同'), _t - 10),
        ]),
        roomId: _room,
        backlogBefore: attach,
      );
      expect(
        [for (final entry in frame.entries) (entry.id, entry.publishedAt?.millisecondsSinceEpoch, entry.replayed)],
        [
          ('frame:0', _t - 5000, true),
          ('frame:1', _t - 3000, true),
          ('frame:2', _t - 1, true),
          ('frame:3', null, false),
          ('frame:4', _t, false),
          ('frame:5', _t - 10, false),
        ],
      );
      expect(
        [for (final message in frame.messages) (message.type, message.replayed)],
        [
          (LiveMessageType.chat, true),
          (LiveMessageType.chat, true),
          (LiveMessageType.superChat, true),
          (LiveMessageType.online, true),
          (LiveMessageType.chat, false),
          (LiveMessageType.chat, false),
          (LiveMessageType.chat, false),
        ],
      );
      // The frame's time stands for a message without its own.
      final framed = SeventeenLiveDanmakuProtocol.decode(
        timed([(_comment('a'), null), (_comment('b'), _t + 1)], frameTime: _t - 1),
        roomId: _room,
        backlogBefore: attach,
      );
      expect([for (final entry in framed.entries) entry.replayed], [true, false]);
      // Without a backlog nothing is replayed; a time that is not one is none.
      final plain = SeventeenLiveDanmakuProtocol.decode(timed([(_comment('a'), _t - 5000)]), roomId: _room);
      expect(plain.entries.single.replayed, isFalse);
      for (final bad in <Object?>['1790636400123', 0, -5, 8640000000000001, 1.5]) {
        final entry = SeventeenLiveDanmakuProtocol.decode(
          jsonEncode({
            'action': 15,
            'channel': _room,
            'messages': [
              {'id': 'x', 'timestamp': bad, 'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(_comment('x')))))},
            ],
          }),
          roomId: _room,
          backlogBefore: attach,
        ).entries.single;
        expect((entry.publishedAt, entry.replayed), (null, false), reason: '$bad');
      }
      // The builders mark what they are told.
      expect(SeventeenLiveDanmakuProtocol.muteNotice(muted: true, replayed: true).replayed, isTrue);
      expect(SeventeenLiveDanmakuProtocol.muteNotice(muted: true).replayed, isFalse);
    });

    test('S08-resume: the backlog after each resume is replayed, what came live is not; the gate shows more', () async {
      const name = 'S08-resume';
      const room = '29790476';
      final lines = _lines(name);
      final start = DateTime.parse(_meta(name)['capturedAt']! as String);
      var clock = start;
      final connector = _Connector();
      final connection = SeventeenLiveDanmakuConnection(
        http: _Http([
          LiveResponse(
            status: 200,
            url: SeventeenLiveDanmakuProtocol.authUrl,
            bytes: utf8.encode(lines.first['text']! as String),
          ),
        ]),
        connector: connector.call,
        policy: _quiet,
        now: () => clock,
      );
      final received = <(DateTime, LiveMessage)>[];
      connection.events.listen((event) {
        if (event case DanmakuReceived(:final message)) received.add((clock, message));
      });
      await connection.connect(const SeventeenLiveDanmakuArgs(roomId: room));
      for (var socket = 1; socket <= 5; socket++) {
        await _until(() => connector.channels.length == socket);
        for (final line in lines.where((line) => line['socket'] == socket && line['dir'] == 'in')) {
          clock = start.add(Duration(milliseconds: line['t']! as int));
          await connector.channels.last.receive(line['text']!);
        }
        if (socket < 5) {
          clock = start.add(
            Duration(milliseconds: lines.firstWhere((line) => line['socket'] == socket + 1)['t']! as int),
          );
          await connector.channels.last.incoming.close();
        }
      }
      await connection.close();
      // Live figures have no id of their own: their count stands for them.
      String brief(LiveMessage message) => switch (message.data) {
        LiveAudienceUpdate(:final value) => 'online $value',
        _ => '${message.type.name} ${message.messageId}',
      };
      expect(
        [
          for (final (_, message) in received)
            if (message.replayed) brief(message),
        ],
        [
          // Socket 2 (RESUMED): the comment of the 5 missed messages.
          'chat +9dXlGTJdRSM:0',
          // Socket 4 (RESUMED): the live figures of the 2 missed.
          'online 912',
          // Socket 5 (90003): the last two minutes.
          'chat qBmo/PznWibX:0',
          'chat MvCAun3OuB5m:0',
          'online 873',
          'online 881',
          'chat WY2mw3r3/CyG:0',
          'chat p/aDIrzaPU3F:0',
          'online 911',
        ],
      );
      expect(
        [
          for (final (_, message) in received)
            if (!message.replayed) brief(message),
        ],
        ['online 1016', 'chat XfeouXxQPVVs:0', 'chat yvoP/nj3Zynh:0', 'online 982', 'chat SZjM1vusrGLb:0'],
      );
      // The duplicate gate, as the app runs it when each came: every comment
      // shows. Without the flag three of socket 5's backlog, 66 to 92 s old,
      // would not (3.x's 45 s).
      final gate = DanmakuMessageGate();
      final plain = DanmakuMessageGate();
      final shown = <String>[];
      final shownBefore = <String>[];
      for (final (at, message) in received) {
        if (message.type != LiveMessageType.chat) continue;
        if (gate.accepts(message, now: at)) shown.add(message.messageId);
        final unflagged = LiveMessage(
          type: message.type,
          userName: message.userName,
          userId: message.userId,
          message: message.message,
          color: message.color,
          messageId: message.messageId,
          sentAt: message.sentAt,
        );
        if (plain.accepts(unflagged, now: at)) shownBefore.add(message.messageId);
      }
      expect(shown, hasLength(8));
      expect(shown.toSet().difference(shownBefore.toSet()), {'qBmo/PznWibX:0', 'MvCAun3OuB5m:0', 'WY2mw3r3/CyG:0'});
    });

    test(
      'a backlog ends at the first message published at the attach; a socket or an attach without one has none',
      () async {
        final attachAt = DateTime.fromMillisecondsSinceEpoch(_t + 60000);
        var clock = attachAt;
        final connector = _Connector();
        final connection = SeventeenLiveDanmakuConnection(
          http: _Http([_granted('AAAAAA.token-1')]),
          connector: connector.call,
          policy: _quiet,
          now: () => clock,
        );
        final events = _record(connection);
        await connection.connect(_args);
        final first = connector.channels.single;
        await first.join();
        // The first attach has no backlog flag: an old message is not replayed.
        await first.receive(timed([(_comment('一'), _t)], id: 'a'));
        await first.incoming.close();
        await _until(() => connector.channels.length == 2);
        final second = connector.channels.last;
        await second.receive(_connectedFrame);
        await second.receive(attached(786438));
        const at = _t + 60000;
        await second.receive(timed([(_comment('二'), at - 3000)], id: 'b'));
        await second.receive(
          timed([(_comment('三'), at - 1000), (_comment('四'), at + 5), (_comment('五'), at - 500)], id: 'c'),
        );
        await second.receive(timed([(_comment('六'), at - 2000)], id: 'd'));
        // A server-sent DETACHED and an attach without the flag: none.
        await second.receive('{"action":13,"channel":"$_room"}');
        clock = clock.add(const Duration(seconds: 5));
        await second.receive(attached(786436));
        await second.receive(timed([(_comment('七'), at - 4000)], id: 'e'));
        // An attach with the flag, then the socket drops before the backlog
        // ends: the next socket's attach without one has none.
        await second.receive('{"action":13,"channel":"$_room"}');
        await second.receive(attached(786438));
        await second.receive(timed([(_comment('八'), at - 100)], id: 'f'));
        await second.incoming.close();
        await _until(() => connector.channels.length == 3);
        final third = connector.channels.last;
        await third.receive(_connectedFrame);
        await third.receive(attached(786436));
        await third.receive(timed([(_comment('九'), at - 100)], id: 'g'));
        expect(
          [for (final message in _messages(events)) '${message.message}${message.replayed ? ' replayed' : ''}'],
          ['一', '二 replayed', '三 replayed', '四', '五', '六', '七', '八 replayed', '九'],
        );
        await connection.close();
      },
    );

    test(
      'a replayed paid barrage and mute notice are marked as well; a message seen before is still not shown',
      () async {
        final clock = DateTime.fromMillisecondsSinceEpoch(_t + 60000);
        final connector = _Connector();
        final connection = SeventeenLiveDanmakuConnection(
          http: _Http([_granted('AAAAAA.token-1')]),
          connector: connector.call,
          policy: _quiet,
          now: () => clock,
        );
        final events = _record(connection);
        await connection.connect(_args);
        final first = connector.channels.single;
        await first.join();
        await first.receive(timed([(_comment('既に'), _t)], id: 'seen'));
        await first.incoming.close();
        await _until(() => connector.channels.length == 2);
        final second = connector.channels.last;
        await second.receive(_connectedFrame);
        await second.receive(attached(786438));
        // The backlog repeats the message shown before (its id), then new ones.
        await second.receive(timed([(_comment('既に'), _t)], id: 'seen'));
        await second.receive(
          timed([
            (
              _comment(
                '付き',
                more: {
                  'barrageStyle': true,
                  'barrage': {'type': 1, 'point': 79},
                },
              ),
              _t + 1000,
            ),
            (
              const {
                'type': 38,
                'liveinfo': {'mute': true, 'liveViewerCount': 7},
              },
              _t + 2000,
            ),
          ], id: 'new'),
        );
        expect(
          [for (final message in _messages(events)) (message.type, message.message, message.replayed)],
          [
            (LiveMessageType.chat, '既に', false),
            (LiveMessageType.chat, '付き', true),
            (LiveMessageType.superChat, '付き', true),
            (LiveMessageType.online, '', true),
            (LiveMessageType.notice, SeventeenLiveDanmakuProtocol.mutedNotice, true),
          ],
        );
        await connection.close();
      },
    );
  });
}
