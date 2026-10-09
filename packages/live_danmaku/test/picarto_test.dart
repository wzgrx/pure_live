// Picarto danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.11-Picarto弹幕/record.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S07-live, S09-keepalive, S10-token-refused) and the synthetic frames
// (S11-synthetic), written by fixtures/picarto/danmaku/v4_expected.dart;
// the chip tips, notices and retractions of M5.F (appendix B-8) against the
// recorded deletion (S13-removed), tip (S14-tip) and system line (S15-system)
// and synthetic frames (S12-b8-synthetic).
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

/// The synthetic chip tips, notices and retractions of B-8.
final Map<String, Object?> _b8Cases = _json('S12-b8-synthetic/cases.json')! as Map<String, Object?>;

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
///
/// B-8: v4 had no super chats, notices or retractions; they are projected
/// with every field, after checking the fields their kind leaves fixed.
Map<String, Object?> _asV4(LiveMessage message) {
  switch (message.type) {
    case LiveMessageType.online:
      final data = message.data! as LiveAudienceUpdate;
      expect(data.kind, LiveAudienceMetricKind.onlineViewers);
      return {'kind': 'online', 'audience': 'online', 'value': data.value};
    case LiveMessageType.superChat:
      final data = message.data! as LiveSuperChatMessage;
      expect([message.userName, message.message], ['SUPER_CHAT_MESSAGE', 'SUPER_CHAT_MESSAGE']);
      expect(message.color, LiveMessageColor.white);
      expect(data.messageId, message.messageId);
      expect(data.endTime.difference(data.startTime), PicartoDanmakuProtocol.tipDuration);
      expect(data.priceText, '${data.price} Kudos');
      // D07.2: only the text says Kudos (superChatUnits).
      expect(data.unit, superChatUnits[SiteIds.picarto]);
      expect([data.backgroundColor, data.backgroundBottomColor], ['', ''], reason: 'the frame names no colours');
      return {
        'kind': 'superChat',
        'id': message.messageId,
        'userId': message.userId,
        'sentAt': message.sentAt?.millisecondsSinceEpoch,
        'userName': data.userName,
        'face': data.face,
        'text': data.message,
        'price': data.price,
        'start': data.startTime.millisecondsSinceEpoch,
      };
    case LiveMessageType.notice:
      expect([message.userName, message.userId, message.messageId], ['', '', '']);
      expect(message.color, LiveMessageColor.white);
      expect(message.sentAt, isNull);
      return {'kind': 'notice', 'notice': (message.data! as LiveNoticeKind).name, 'text': message.message};
    case LiveMessageType.retraction:
      expect([message.userName, message.userId, message.message, message.messageId], ['', '', '', '']);
      return {'kind': 'retraction', 'target': '${message.data! as LiveRetraction}'};
    case LiveMessageType.chat || LiveMessageType.gift:
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
}

/// When the synthetic frames are received: the "now" that dates a tip
/// without a time (B-8).
final DateTime _receivedAt = DateTime.parse(_b8Cases['receivedAt']! as String);

List<Map<String, Object?>> _decodedAsV4(Object frame, {int? channelId}) => [
  for (final message in PicartoDanmakuProtocol.decode(
    _text(frame),
    channelId: channelId ?? _channelId,
    channelName: _args.channelName,
    now: _receivedAt,
  ).messages)
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
/// (docs/D-弹幕/D01-平台弹幕协议/D01.11-Picarto弹幕/record.md, "与归档 v4 的差异"): v4's output → the new
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
  // Difference 7: lines of another type (`w`) are not chat. B-8: a `system`
  // line is a system notice, as the site shows it.
  'lines of another type in a chat frame, and lines that are not objects': (v4) => [
    [
      for (final chat in (v4.single! as List<Object?>).cast<Map<String, Object?>>())
        if (chat['text'] == 'system line')
          _notice('system', 'system line')
        else if (chat['text'] != 'whisper line')
          chat,
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
  // B-8: system, raid and subscription frames are notices; joins, leaves,
  // the user list and whispers still show nothing.
  'joins, leaves and other notices show nothing': (v4) {
    expect(v4, List.filled(8, isEmpty));
    return [
      for (var frame = 0; frame < 4; frame++) const <Object?>[],
      [_notice('system', 'Stream is live')],
      [_notice('raid', 'raid!')],
      [_notice('subscription', 'Gifter 订阅了 Receiver，3 个月')],
      const <Object?>[],
    ];
  },
  // B-8: a chip tip is a super chat (the case keeps the name it had while
  // tips were not shown).
  "a chip tip is not shown (no sample of it; its fields come from the site's client)": (v4) {
    expect(v4, [isEmpty]);
    return [
      [_tip('aaaaaaaa-0000-11f1-8000-000000000070', face: '', text: 'for you')],
    ];
  },
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

/// The time of the synthetic lines.
const int _sent = 1790531380528;

/// The avatar of the synthetic lines, under the site's image host.
const String _face = 'https://images.picarto.tv/abcdefghi/1/23/4567890/abcdefg/0123456789abcdefghij.png';

/// A synthetic chip tip (B-8) as the projection shows it; it starts at its
/// time, or when it was received when it has none.
Map<String, Object?> _tip(
  String id, {
  String userId = '7300007',
  String userName = 'Tipper',
  String face = _face,
  String text = 'thanks',
  int price = 100,
  int? sentAt = _sent,
}) => {
  'kind': 'superChat',
  'id': id,
  'userId': userId,
  'sentAt': sentAt,
  'userName': userName,
  'face': face,
  'text': text,
  'price': price,
  'start': sentAt ?? _receivedAt.millisecondsSinceEpoch,
};

/// A notice (B-8) as the projection shows it.
Map<String, Object?> _notice(String kind, String text) => {'kind': 'notice', 'notice': kind, 'text': text};

/// A retraction (B-8) as the projection shows it.
Map<String, Object?> _retraction(String target) => {'kind': 'retraction', 'target': target};

String _b8Id(int number) => 'bbbbbbbb-0000-11f1-8000-${'$number'.padLeft(12, '0')}';

/// What every case of S12-b8-synthetic shows, frame by frame (B-8).
final Map<String, List<List<Map<String, Object?>>>> _b8Expected = {
  'tip: a ct line with every field the site reads': [
    [_tip(_b8Id(1), text: 'kudo100 thanks for the stream')],
  ],
  'tip: a chat line with v set, without time, text or avatar; a line without a type': [
    [
      _tip(_b8Id(2), userId: '7300008', userName: 'TipperTwo', face: '', text: '', price: 5, sentAt: null),
      _tip(_b8Id(3), userId: '7300009', userName: 'TipperThree', face: '', text: 'no type', price: 1, sentAt: null),
    ],
  ],
  'tip: to another channel of the multistream, it says whom it went to': [
    [
      _tip(_b8Id(4), text: '打赏给 OtherChannel：go go', price: 50),
      _tip(_b8Id(5), text: '打赏给 OtherChannel', price: 50),
      _tip(_b8Id(6), text: 'same room', price: 50),
      _tip(_b8Id(7), text: 'no receiver', price: 50),
    ],
  ],
  'tip: the avatar is a path under images.picarto.tv, or a full URL as it is': [
    [
      _tip(_b8Id(8), face: 'https://images.picarto.tv/ptvimages/1/23/4567890/avatars/abcdefghij.png'),
      _tip(_b8Id(9), face: 'https://images.picarto.tv/ptvimages/1/23/4567890/avatars/abcdefghij.png'),
      _tip(_b8Id(10), face: ''),
      _tip(_b8Id(11), face: ''),
      _tip(_b8Id(12), face: ''),
    ],
  ],
  'tip: a ct line without v is still a tip; a chat line with chips but without v is chat': [
    [_tip(_b8Id(13), text: 'no flag', price: 10), _tip(_b8Id(14), text: 'false flag', price: 10)],
    [_chat('chips but no flag', _b8Id(15))],
  ],
  'tip: bad chips cost only that line': [
    [_tip(_b8Id(22), text: 'valid', price: 2)],
  ],
  'tip: text that is not text, and the id from _id': [
    [_tip('5f0000000000000000000002', text: ''), _tip('', text: '')],
  ],
  'rm: takes back one message by its id (the shape recorded on 2026-09-30)': [
    [_retraction('LiveRetraction.message(aaaaaaaa-0000-11f1-8000-000000000001)')],
    [_retraction('LiveRetraction.message(aaaaaaaa-0000-11f1-8000-000000000002)')],
  ],
  'cm: takes back every message of a user, the id as text or a number': [
    [_retraction('LiveRetraction.user(7300001)')],
    [_retraction('LiveRetraction.user(7300002)')],
  ],
  'rm and cm without a usable target show nothing': List.filled(13, const []),
  "system: the server's text; a link becomes its text, an icon is left out, lines are joined": [
    [_notice('system', 'Welcome to the chat!')],
    [_notice('system', 'Read the rules: picarto.tv/rules')],
    [_notice('system', 'Slow mode is on. Wait 5 seconds between messages.')],
    [_notice('system', 'first'), _notice('system', 'second')],
  ],
  'system: placeholders as the site fills them': [
    [_notice('system', 'see {link} and {icon}')],
    [_notice('system', 'go  now')],
    // The site gives the k-th placeholder the link 2k + 1, else the first.
    [_notice('system', 'second or first')],
    [_notice('system', '!')],
  ],
  'system: a frame for moderators (c is b) is not shown; the other lines of a system frame': [
    const [],
    [_chat('chat in a system frame', _b8Id(23)), _notice('system', 'a notice')],
  ],
  'system: a system line in a chat frame is a notice (the site reads each line by its type)': [
    [_chat('before', _b8Id(24)), _notice('system', 'Stream is live'), _chat('after', _b8Id(25))],
  ],
  'system: bad lines cost only themselves; a frame without a list shows nothing': [
    [_notice('system', 'valid')],
    const [],
    const [],
  ],
  "raid: the server's sentence, else who raided whom": [
    [_notice('raid', 'Raider is raiding with 12 viewers!')],
    [_notice('raid', 'Raider 突袭了 allatir')],
    [_notice('raid', 'Raider 突袭了 allatir')],
  ],
  'raid: nothing to say': List.filled(4, const []),
  'ns: subscriptions and gifts, worded as the site words them': [
    [_notice('subscription', 'Subscriber 订阅了 allatir，3 个月')],
    [_notice('subscription', 'Subscriber 订阅了 allatir，1 个月')],
    [_notice('subscription', 'Subscriber 开通了 allatir 的 2 级订阅')],
    [_notice('subscription', 'Gifter 赠送给 Lucky 1 个月订阅')],
    [_notice('subscription', 'Gifter 向 Picarto 社区赠送了 3 份 allatir 的订阅')],
    [_notice('subscription', 'Lucky 收到匿名赠送的 6 个月 allatir 订阅')],
    [_notice('subscription', '有人匿名向 Picarto 社区赠送了 2 份 allatir 的订阅')],
    [_notice('subscription', 'Gifter 赠送给 Lucky 2 个月订阅')],
  ],
  'ns: a name the sentence needs is missing': List.filled(7, const []),
  'a page of history (paginated or p) is skipped for every kind': [
    for (var frame = 0; frame < 6; frame++) const [],
    [_retraction('LiveRetraction.message(aaaaaaaa-0000-11f1-8000-000000000007)')],
  ],
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

  group('B-8 (M5.F): chip tips, notices, retractions', () {
    final cases = [
      for (final entry in _b8Cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames})
          (name: name, frames: frames.cast<String>()),
    ];

    test('S12-b8-synthetic is read on this room, and every case has an expectation', () {
      expect(_b8Cases['channelId'], _args.channelId);
      expect(_b8Cases['channelName'], _args.channelName);
      expect(cases.map((entry) => entry.name), _b8Expected.keys);
    });

    for (final (:name, :frames) in cases) {
      test(name, () {
        expect([for (final frame in frames) _decodedAsV4(frame)], _b8Expected[name]);
        for (final frame in frames) {
          expect(PicartoDanmakuProtocol.decode(frame, channelId: _channelId).tokenRefused, isFalse);
        }
      });
    }

    test('a chip tip is a super chat, field by field', () {
      final frame = cases.first.frames.single;
      final message = PicartoDanmakuProtocol.decode(
        frame,
        channelId: _channelId,
        channelName: 'allatir',
        now: _receivedAt,
      ).messages.single;
      expect(message.type, LiveMessageType.superChat);
      expect(message.userName, 'SUPER_CHAT_MESSAGE');
      expect(message.message, 'SUPER_CHAT_MESSAGE');
      expect(message.color, LiveMessageColor.white);
      expect(message.userId, '7300007');
      expect(message.messageId, 'bbbbbbbb-0000-11f1-8000-000000000001');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(_sent));
      final data = message.data! as LiveSuperChatMessage;
      expect(data.messageId, 'bbbbbbbb-0000-11f1-8000-000000000001');
      expect(data.userName, 'Tipper');
      expect(data.face, _face);
      expect(data.message, 'kudo100 thanks for the stream');
      expect(data.price, 100);
      expect(data.priceText, '100 Kudos');
      expect(data.startTime, DateTime.fromMillisecondsSinceEpoch(_sent));
      expect(data.endTime, DateTime.fromMillisecondsSinceEpoch(_sent).add(const Duration(seconds: 60)));
      expect(data.backgroundColor, '');
      expect(data.backgroundBottomColor, '');
      // Without a time it starts when received (the injected clock).
      final undated = PicartoDanmakuProtocol.decode(
        cases[1].frames.single,
        channelId: _channelId,
        now: _receivedAt,
      ).messages.first;
      expect(undated.sentAt, isNull);
      expect((undated.data! as LiveSuperChatMessage).startTime, _receivedAt);
      expect((undated.data! as LiveSuperChatMessage).endTime, _receivedAt.add(PicartoDanmakuProtocol.tipDuration));
    });

    test('retractions and notices, field by field', () {
      final removal = PicartoDanmakuProtocol.decode(
        '{"t":"rm","m":{"id":"aaaaaaaa-0000-11f1-8000-000000000001","m":"Chat Message Removed by allatir"}}',
        channelId: _channelId,
      ).messages.single;
      expect(removal.type, LiveMessageType.retraction);
      expect(removal.data, const LiveRetraction.message('aaaaaaaa-0000-11f1-8000-000000000001'));
      expect((removal.data! as LiveRetraction).isAll, isFalse);
      expect(removal.messageId, '', reason: "the target's id would collide with it in the duplicate gate");
      expect([removal.userName, removal.userId, removal.message], ['', '', '']);
      final clearance = PicartoDanmakuProtocol.decode('{"t":"cm","m":{"u":7300002}}', channelId: _channelId);
      expect(clearance.messages.single.type, LiveMessageType.retraction);
      expect(clearance.messages.single.data, const LiveRetraction.user('7300002'));
      for (final (frame, kind, text) in [
        ('{"t":"system","m":[{"t":"system","m":"Welcome!"}]}', LiveNoticeKind.system, 'Welcome!'),
        ('{"t":"raid","m":{"rn":"allatir","n":"Raider","m":"Raider raids!"}}', LiveNoticeKind.raid, 'Raider raids!'),
        ('{"t":"ns","m":{"sn":"S","n":"allatir","md":2}}', LiveNoticeKind.subscription, 'S 订阅了 allatir，2 个月'),
      ]) {
        final notice = PicartoDanmakuProtocol.decode(frame, channelId: _channelId).messages.single;
        expect(notice.type, LiveMessageType.notice);
        expect(notice.data, kind);
        expect(notice.message, text);
        expect([notice.userName, notice.userId, notice.messageId], ['', '', '']);
        expect(notice.color, LiveMessageColor.white);
        expect(notice.sentAt, isNull);
      }
    });

    test("S13-removed: the streamer's deleted line is taken back by its id, and cm would take the user's", () {
      final meta = _meta('S13-removed');
      final keys = meta['danmakuKeys']! as Map<String, Object?>;
      final channelId = int.parse(keys['channelId']! as String);
      final frames = _frames('S13-removed');
      expect(frames.map((frame) => frame.dir), ['in', 'in']);
      final chat = PicartoDanmakuProtocol.decode(frames[0].text, channelId: channelId).messages.single;
      expect(chat.type, LiveMessageType.chat);
      expect(chat.userName, keys['channelName']);
      expect(chat.messageId, '573b53e0-bce3-11f1-8b7e-a3860776556d');
      expect(chat.sentAt, DateTime.fromMillisecondsSinceEpoch(1790782003230));
      expect(chat.color, const LiveMessageColor(0xBE, 0xFF, 0x00));
      final removal = PicartoDanmakuProtocol.decode(frames[1].text, channelId: channelId).messages.single;
      expect(removal.type, LiveMessageType.retraction);
      expect(removal.data, LiveRetraction.message(chat.messageId));
      expect(removal.messageId, isEmpty);
      // The line's user id is what a cm names (the site compares `u`).
      final line = jsonDecode(frames[0].text);
      if (line case {'m': [{'u': final String user}]}) {
        final clearance = PicartoDanmakuProtocol.decode(
          jsonEncode({
            't': 'cm',
            'm': {'u': user},
          }),
          channelId: channelId,
        ).messages.single;
        expect(clearance.data, LiveRetraction.user(chat.userId));
      } else {
        fail('no user id in $line');
      }
      // The deletion came about 4 s later; the gate lets both through.
      final gate = DanmakuMessageGate();
      final now = chat.sentAt!.add(const Duration(seconds: 4));
      expect(gate.accepts(chat, now: now), isTrue);
      expect(gate.accepts(removal, now: now), isTrue);
    });

    test('S14-tip: a recorded tip (a chat line with v, x and the chipmote) is a super chat, field by field', () {
      final meta = _meta('S14-tip');
      final keys = meta['danmakuKeys']! as Map<String, Object?>;
      final channelName = keys['channelName']! as String;
      final frame = _frames('S14-tip').single;
      final decoded = PicartoDanmakuProtocol.decode(
        frame.text,
        channelId: int.parse(keys['channelId']! as String),
        channelName: channelName,
        now: DateTime.parse(meta['capturedAt']! as String),
      );
      expect(decoded.tokenRefused, isFalse);
      final message = decoded.messages.single;
      expect(message.type, LiveMessageType.superChat);
      expect([message.userName, message.message], ['SUPER_CHAT_MESSAGE', 'SUPER_CHAT_MESSAGE']);
      expect(message.color, LiveMessageColor.white);
      expect(message.userId, '76348');
      expect(message.messageId, '90e821d0-bce9-11f1-a839-8d3d4e5dbfb3');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790784676973));
      final data = message.data! as LiveSuperChatMessage;
      expect(data.messageId, message.messageId);
      expect(data.userName, 'Tip0bdKTWr');
      expect(
        data.face,
        'https://images.picarto.tv/ptvimages/7/76/76348/avatars/D63WLBb0cF3flNIwe7yRuY1eY47z5cp7aGrC3GYI.png',
      );
      expect(data.message, 'kudo100 Sparky is shrinking? Smaller than you think', reason: 'to this channel: no prefix');
      expect(data.price, 100);
      expect(data.priceText, '100 Kudos');
      expect(data.startTime, DateTime.fromMillisecondsSinceEpoch(1790784676973));
      expect(data.endTime, data.startTime.add(const Duration(seconds: 60)));
      expect([data.backgroundColor, data.backgroundBottomColor], ['', '']);
      // Before B-8 the line was plain chat (M5.10, v4): the chip count was lost.
      final line = (jsonDecode(frame.text)! as Map<String, Object?>)['m']! as List<Object?>;
      expect(PicartoDanmakuProtocol.chat(line.single)!.message, data.message);
      // In another channel of a multistream it names the channel it went to.
      final elsewhere = PicartoDanmakuProtocol.decode(frame.text, channelId: 1, channelName: 'OtherChannel');
      expect(
        (elsewhere.messages.single.data! as LiveSuperChatMessage).message,
        '打赏给 $channelName：kudo100 Sparky is shrinking? Smaller than you think',
      );
    });

    test('S15-system: a recorded system line (an icon, no links, a line break) is one system notice', () {
      final keys = _meta('S15-system')['danmakuKeys']! as Map<String, Object?>;
      final frame = _frames('S15-system').single;
      final decoded = PicartoDanmakuProtocol.decode(
        frame.text,
        channelId: int.parse(keys['channelId']! as String),
        channelName: keys['channelName']! as String,
      );
      expect(decoded.tokenRefused, isFalse);
      final notice = decoded.messages.single;
      expect(notice.type, LiveMessageType.notice);
      expect(notice.data, LiveNoticeKind.system);
      expect(notice.message, 'Multistream Chat has been merged: ItsDraconix,allatir,LOITER,belosha');
      expect([notice.userName, notice.userId, notice.messageId], ['', '', '']);
      expect(notice.color, LiveMessageColor.white);
      expect(notice.sentAt, isNull);
      // Before B-8 (M5.10, v4) a system frame showed nothing.
      expect(frame.text, startsWith('{"t":"system","m":[{"t":"system","m":"{icon} Multistream'));
    });

    test('the connection reports tips, notices and retractions in order; an undated tip gets its clock', () async {
      final connector = _Connector();
      final connection = PicartoDanmakuConnection(
        http: _TokenHttp([_answer(_tokenA)]),
        connector: connector.call,
        now: () => _receivedAt,
      );
      final events = _record(connection);
      await connection.connect(_args);
      final frames = [
        cases[0].frames.single,
        cases[1].frames.single,
        '{"t":"c","m":[{"t":"c","u":"7300001","n":"ViewerOne","m":"hello","id":"aaaaaaaa-0000-11f1-8000-000000000001"}]}',
        '{"t":"rm","m":{"id":"aaaaaaaa-0000-11f1-8000-000000000001","m":"Chat Message Removed by allatir"}}',
        '{"t":"cm","m":{"u":"7300001"}}',
        '{"t":"system","m":[{"t":"system","m":"Welcome!"}]}',
        '{"t":"raid","m":{"rn":"allatir","n":"Raider","m":"Raider raids!"}}',
        '{"t":"ns","m":{"sn":"S","n":"allatir","md":2}}',
      ];
      var binary = false;
      for (final frame in frames) {
        connector.channels.single.incoming.add((binary = !binary) ? utf8.encode(frame) : frame);
      }
      await _until(() => _messages(events).length == 9);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map(_asV4), [
        _tip(_b8Id(1), text: 'kudo100 thanks for the stream'),
        ..._b8Expected[cases[1].name]!.single,
        {
          'kind': 'chat',
          'id': 'picarto:aaaaaaaa-0000-11f1-8000-000000000001',
          'sentAt': null,
          'userId': '7300001',
          'userName': 'ViewerOne',
          'text': 'hello',
          'color': '#ffffff',
        },
        _retraction('LiveRetraction.message(aaaaaaaa-0000-11f1-8000-000000000001)'),
        _retraction('LiveRetraction.user(7300001)'),
        _notice('system', 'Welcome!'),
        _notice('raid', 'Raider raids!'),
        _notice('subscription', 'S 订阅了 allatir，2 个月'),
      ]);
      expect(connector.channels.single.sent, isEmpty);
      await connection.close();
    });

    test("a tip to another channel is named by the arguments' channel", () async {
      final connector = _Connector();
      final connection = _connection(_TokenHttp([_answer(_tokenA)]), connector);
      final events = _record(connection);
      await connection.connect(const PicartoDanmakuArgs(channelName: 'OtherChannel', channelId: 122866));
      connector.channels.single.incoming.add(cases[2].frames.single);
      await _until(() => _messages(events).length == 4);
      expect(
        [for (final message in _messages(events)) (message.data! as LiveSuperChatMessage).message],
        ['go go', '', '打赏给 ALLATIR：same room', 'no receiver'],
      );
      await connection.close();
    });
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
