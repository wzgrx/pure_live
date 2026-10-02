import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kugoulive/danmaku';

/// One line of a sample's `frames.jsonl`: the scheduler's answer (`url`,
/// `text`) or a socket frame.
typedef _Line = ({int line, bool incoming, String? url, String? text, Uint8List? bytes});

final class _Sample {
  new(this.name)
    : lines = [
        for (final (index, text) in File('$_root/$name/frames.jsonl').readAsLinesSync().indexed)
          if (jsonDecode(text) case final Map<String, Object?> frame)
            (
              line: index + 1,
              incoming: frame['dir'] == 'in',
              url: frame['url'] as String?,
              text: frame['text'] as String?,
              bytes: frame['b64'] == null ? null : base64.decode(frame['b64']! as String),
            ),
      ],
      meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>,
      expected =
          (jsonDecode(File('$_root/$name/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
              as Map<String, Object?>;

  final String name;
  final List<_Line> lines;
  final Map<String, Object?> meta;

  /// The website's reading (web_expected.py).
  final Map<String, Object?> expected;

  /// When the sample was recorded: "now" of everything timed here.
  DateTime get recordedAt => DateTime.parse(meta['capturedAt']! as String);

  String get room => (meta['danmakuKeys']! as Map)['roomId'] as String;

  _Line get dispatch => lines.firstWhere((line) => line.url != null);

  List<_Line> get socket => [
    for (final line in lines)
      if (line.bytes != null) line,
  ];

  List<Map<String, Object?>> get expectedFrames => (expected['frames']! as List).cast<Map<String, Object?>>();

  Map<String, Object?> expectedAt(int line) => expectedFrames.singleWhere((frame) => frame['line'] == line);
}

final _Sample _s07 = _Sample('S07-live');
final _Sample _s08 = _Sample('S08-refused');
final _Sample _s09 = _Sample('S09-pk-chat');
final _Sample _s10 = _Sample('S10-chat-colours');
final _Sample _s11 = _Sample('S11-mystery-colour');

const String _room = '51049168';
final DateTime _now = _s07.recordedAt;

/// The recorded (scrubbed) scheduler answer of S07 and its grant.
LiveResponse get _recordedGrant => _answer(_s07.dispatch.text!);

LiveResponse _answer(String body, {int status = 200}) => LiveResponse(
  status: status,
  bytes: utf8.encode(body),
  url: KugouLiveDanmakuProtocol.dispatchUrl(_room, now: _now),
);

/// A scheduler answer with [token] and [hosts].
LiveResponse _granted(
  String token, {
  List<String> hosts = const ['chatwss146107.kugou.com/acksocket', 'chatwss140058.kugou.com/acksocket'],
  Object? age = 300000,
}) => _answer(
  jsonEncode({
    'code': 0,
    'data': {
      'addrs': [
        for (final host in hosts) {'host': host, 'timeout': 10000},
      ],
      'age': ?age,
      'backsoctoken': 'b' * 43,
      'protocol': 'wss://',
      'protocoltype': 1,
      'pv': 20240801,
      'socketype': 1,
      'soctoken': token,
    },
    'msg': 'success',
    'time': 1790771486371,
  }),
);

LiveResponse _refusedAnswer({int code = 1100014, String msg = 'sign verify fail'}) =>
    _answer(jsonEncode({'code': code, 'data': <String, Object?>{}, 'msg': msg, 'time': 1790769995191}));

/// Answers the scheduler from a script: a response, an error to throw, or a
/// completer to wait for; the last entry repeats.
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
          (_) => throw const TransportFailure(SiteIds.kugouLive, TransportReason.cancelled),
        ),
      ]),
      _ => throw step as Exception,
    };
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}

  /// The rooms asked for, in order.
  List<String> get rooms => [for (final request in requests) request.url.queryParameters['rid']!];
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

  /// The server accepts the login: type 4, then type 1 with [session].
  Future<void> join({String session = 'a1b2c3'}) async {
    await receive(_status(type: 4, status: 1));
    await receive(_status(type: 1, status: 1, session: session));
  }

  /// The logins sent: (command, token, session).
  List<(int, String, String)> get logins => [
    for (final frame in sent)
      if (frame is List<int> && frame.length > 18 && frame[3] == 1) _login(frame as Uint8List),
  ];
}

(int, String, String) _login(Uint8List frame) {
  final request = ProtoMessage.decode(ProtoMessage.decode(Uint8List.sublistView(frame, 18)).bytes(7)!);
  return (request.integer(1)!, request.string(15)!, request.string(23)!);
}

/// Hands out fake sockets and records every handshake; the first [failures]
/// handshakes throw.
final class _Connector {
  new({this.failures = 0});

  final int failures;
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
    if (endpoints.length <= failures) throw const SocketException('refused');
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

// Server frames ----------------------------------------------------------------

/// A server frame: the 26-byte header of the recordings (variable part 20:
/// command, length, 8 and a time), then [envelope].
Uint8List _server(int command, List<int> envelope) {
  final header = ByteData(26)
    ..setUint8(0, 100)
    ..setInt16(1, 3)
    ..setUint8(3, 1)
    ..setInt16(4, 20)
    ..setInt32(6, command)
    ..setInt32(10, envelope.length)
    ..setInt32(14, 8)
    ..setInt64(18, 1790771500000);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...envelope]);
}

/// `SocketProtocol.Message`.
Uint8List _envelope(List<int> content, {int? codec, int? compression, String? msgId}) {
  final writer = ProtoWriter();
  if (msgId != null) writer.string(4, msgId);
  if (compression != null) writer.integer(5, compression);
  if (codec != null) writer.integer(6, codec);
  writer.bytes(7, content);
  return writer.toBytes();
}

Uint8List _status({required int type, int? status, int? errorNo, String? session, String? message}) {
  final writer = ProtoWriter()
    ..integer(1, 901)
    ..integer(2, type);
  if (status != null) writer.integer(4, status);
  if (errorNo != null) writer.integer(5, errorNo);
  if (message != null) writer.string(6, message);
  if (session != null) writer.string(7, session);
  return _server(901, _envelope(writer.toBytes(), codec: 1));
}

/// A chat (501) as the server writes it (synthetic values).
Uint8List _chat({
  int command = 501,
  String text = '主播好',
  String name = '观众001',
  int senderId = 5847998728,
  int kugouId = 5847998728,
  int envelopeReceiver = 0,
  int chatReceiver = 0,
  String receiverName = '',
  int room = 51049168,
  int time = 1790771498,
  int seq = 1790771498671,
  int level = 11,
  int levelV2 = 11,
  int contentCodec = 1,
  List<int>? ext,
  List<int>? sinfo,
  String? msgId,
  (int, int)? source,
}) {
  final chat = ProtoWriter()
    ..string(1, text)
    ..integer(2, senderId)
    ..integer(3, kugouId)
    ..string(4, name);
  if (level != 0) chat.integer(5, level);
  if (chatReceiver != 0) {
    chat
      ..integer(6, chatReceiver)
      ..integer(7, chatReceiver)
      ..string(8, receiverName);
  }
  chat
    ..string(11, '')
    ..integer(12, 20210601)
    ..integer(13, seq)
    ..string(19, 'f63a33dd0baeb365')
    ..string(23, 'f63a33dd0baeb365')
    ..string(24, 'http://p3.fx.kgimg.com/v2/fxuserlogo/6423d37cd61533b9c9c78f60a5d776ff.jpg_45x45.jpg');
  if (levelV2 != 0) chat.integer(25, levelV2);
  final message = ProtoWriter()
    ..integer(1, command)
    ..bytes(2, chat.toBytes())
    ..integer(3, room);
  if (envelopeReceiver != 0) message.integer(4, envelopeReceiver);
  message
    ..integer(6, senderId)
    ..integer(7, kugouId)
    ..integer(8, 1010)
    ..integer(11, time)
    ..bytes(14, ext ?? _ext())
    ..bytes(15, sinfo ?? (ProtoWriter()..integer(1, 1)).toBytes())
    ..integer(16, contentCodec);
  if (source case (final room, final tags)) {
    message.bytes(
      18,
      (ProtoWriter()
            ..integer(1, room)
            ..integer(2, tags))
          .toBytes(),
    );
  }
  return _server(command, _envelope(message.toBytes(), codec: 1, msgId: msgId));
}

/// `Ext.Extension` with `intimacyVo` (39).
Uint8List _ext({int level = 6, String nameplate = '姜姜芽', int type = 1, int lightUp = 1, bool intimacy = true}) {
  final writer = ProtoWriter()..bytes(3, (ProtoWriter()..integer(1, 25)).toBytes());
  if (intimacy) {
    writer.bytes(
      39,
      (ProtoWriter()
            ..integer(1, level)
            ..string(2, nameplate)
            ..integer(3, type)
            ..integer(5, lightUp))
          .toBytes(),
    );
  }
  return writer.toBytes();
}

/// A gift (601) whose envelope asks for an acknowledgement when [ack] is 1
/// (the content is a bare `ContentMessage`; the gift itself is not read).
Uint8List _gift({
  int ack = 1,
  int repeat = 0,
  String offset = '14215147132598579',
  String msgId = '2216677664281887088',
}) {
  final content =
      (ProtoWriter()
            ..integer(1, 601)
            ..integer(3, 51049168)
            ..integer(11, 1790771500)
            ..integer(16, 1))
          .toBytes();
  final envelope = ProtoWriter()..string(1, offset);
  if (ack != 0) envelope.integer(2, ack);
  if (repeat != 0) envelope.integer(3, repeat);
  envelope
    ..string(4, msgId)
    ..integer(6, 1)
    ..bytes(7, content);
  return _server(601, envelope.toBytes());
}

/// A JSON message (`codec` 0), gzipped when asked.
Uint8List _json(int command, Map<String, Object?> message, {bool gzipped = false, int? compression}) {
  final text = utf8.encode(jsonEncode(message));
  return _server(
    command,
    _envelope(gzipped ? gzip.encode(text) : text, compression: compression ?? (gzipped ? 1 : null)),
  );
}

Uint8List _audience({Object? count = 100, Object? visited = 2594, Object? room = 51049168, Object? action}) =>
    _json(301005, {
      'cmd': 301005,
      'content': {
        'data': {'robot': 0, 'count': ?count, 'visited': ?visited, 'vertical': 60, 'hot': 1389, 'login': 98},
        'actionId': action ?? 'roomAuNumber',
      },
      'receiverid': 0,
      'roomid': ?room,
      'senderid': 0,
      'time': 1790771500036,
    });

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

/// No heartbeat, watchdog or join timer and a short backoff: only what the
/// test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

const KugouLiveDanmakuArgs _args = KugouLiveDanmakuArgs(roomId: _room);

KugouLiveDanmakuConnection _connection(
  _Connector connector,
  _Http http, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
  DateTime Function()? now,
  List<Duration> retryDelays = const [Duration(milliseconds: 5), Duration(milliseconds: 5)],
}) => KugouLiveDanmakuConnection(
  http: http,
  connector: connector.call,
  policy: policy,
  proxy: proxy,
  retryDelays: retryDelays,
  now: now ?? () => _now,
  random: Random(7),
);

/// What the connection logs in with for the seeded `Random(7)`
/// of [_connection]): the page's session, then its device.
(String, String) _ids() {
  final random = Random(7);
  return (KugouLiveDanmakuProtocol.uuid(random), KugouLiveDanmakuProtocol.uuid(random));
}

/// A chat as the page shows it (web_expected.py) against [message].
void _expectChat(LiveMessage message, Map<String, Object?> page, {required String reason}) {
  final badge = page['fanBadge'] as Map<String, Object?>?;
  final seq = page['seq']! as int;
  final msgId = page['msgId']! as String;
  expect(message.type, LiveMessageType.chat, reason: reason);
  expect(message.userName, page['userName'], reason: reason);
  expect(message.message, page['text'], reason: reason);
  expect(message.userId, '${page['operationUserId']}', reason: reason);
  expect(message.userLevel, page['richLevel'] == 0 ? '' : '${page['richLevel']}', reason: reason);
  expect(message.fansName, badge?['clubName'] ?? '', reason: reason);
  expect(message.fansLevel, badge == null ? '' : '${badge['level']}', reason: reason);
  expect(
    message.messageId,
    msgId.isNotEmpty
        ? msgId
        : seq > 0
        ? '${page['senderid']}:$seq'
        : '',
    reason: reason,
  );
  expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch((page['time']! as int) * 1000), reason: reason);
  // B-15: the page's text colour (dealWithChatContentColor); white where
  // the page leaves its default (3.x-style white before B-15).
  expect(message.color, _pageColor(page['contentColor'] as String?), reason: reason);
}

/// The `#rrggbb` the page writes, as a colour; null (the page's default
/// class) is white.
LiveMessageColor _pageColor(String? css) =>
    css == null ? LiveMessageColor.white : LiveMessageColor.numberToColor(int.parse(css.substring(1), radix: 16));

void main() {
  group('protocol', () {
    test('constants: the scheduler, the page ids, the timing and the handshake headers', () {
      expect(KugouLiveDanmakuProtocol.dispatchPath, '/socket_scheduler/pc/binary/v2/address.jsonp');
      expect(KugouLiveDanmakuProtocol.signSalt, r'$_fan_xing_$');
      expect(KugouLiveDanmakuProtocol.pageVersion, '7.0.0');
      expect(KugouLiveDanmakuProtocol.socketVersion, 20240801);
      expect((KugouLiveDanmakuProtocol.clientId, KugouLiveDanmakuProtocol.roomType), (100, 102));
      expect((KugouLiveDanmakuProtocol.appId, KugouLiveDanmakuProtocol.platformId), (1010, 7));
      expect(KugouLiveDanmakuProtocol.heartbeatInterval, const Duration(seconds: 10));
      expect(KugouLiveDanmakuProtocol.joinTimeout, const Duration(seconds: 10));
      expect(KugouLiveDanmakuProtocol.defaultAge, const Duration(minutes: 5));
      expect(KugouLiveDanmakuProtocol.maxRefusals, 3);
      expect(KugouLiveDanmakuProtocol.tokenRejected, 622);
      expect(KugouLiveDanmakuProtocol.socketHeaders, {
        'origin': 'https://fanxing.kugou.com',
        'user-agent': KugouLiveApi.userAgent,
      });
      expect(KugouLiveDanmakuProtocol.heartbeat(), [100, 0, 1, 0]);
      expect(KugouLiveDanmakuProtocol.heartbeat(), base64.decode(_s07.expected['heartbeat']! as String));
      expect(KugouLiveDanmakuProtocol.checkedRoom(' 51049168 '), _room);
      for (final bad in ['', '12', '012345', '123456789012', 'abc', '5104 9168']) {
        expect(KugouLiveDanmakuProtocol.checkedRoom(bad), isNull, reason: bad);
      }
      final uuid = KugouLiveDanmakuProtocol.uuid(Random(1));
      expect(uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(KugouLiveDanmakuProtocol.uuid(Random(1)), uuid);
    });

    test('the scheduler address: the recorded ones, signed as the server accepted them', () {
      for (final sample in [_s07, _s08]) {
        final recorded = Uri.parse(sample.dispatch.url!);
        final now = DateTime.fromMillisecondsSinceEpoch(int.parse(recorded.queryParameters['clienttime']!));
        expect(KugouLiveDanmakuProtocol.dispatchUrl(sample.room, now: now), recorded, reason: sample.name);
        expect('${KugouLiveDanmakuProtocol.dispatchUrl(sample.room, now: now)}', sample.dispatch.url);
        final sign = (sample.expected['dispatch']! as Map)['sign'] as Map;
        expect(sign['sign'], sign['recorded'], reason: 'web_expected.py agrees with the server');
        expect(recorded.queryParameters['sign'], sign['sign']);
      }
      // The keys sort by code unit ('_' before letters), values as written:
      // md5("_z=&a=1&b=2$_fan_xing_$")[8:24] and md5("a=1&b=2$_fan_xing_$")[8:24].
      expect(KugouLiveDanmakuProtocol.sign({'b': '2', 'a': '1', '_z': ''}), 'd4bc22d3a5c4deee');
      expect(KugouLiveDanmakuProtocol.sign({'b': '2', 'a': '1'}), '237c3482fd8bbe3e');
    });

    test("the scheduler request is the room page's", () {
      final cancel = CancelToken();
      final request = KugouLiveDanmakuProtocol.dispatchRequest(
        _room,
        now: _now,
        timeout: const Duration(seconds: 7),
        cancel: cancel,
      );
      expect(request.site, 'kugoulive');
      expect(request.method, 'GET');
      expect(request.url, KugouLiveDanmakuProtocol.dispatchUrl(_room, now: _now));
      expect(request.url.host, KugouLiveApi.apiHost);
      expect(request.headers, {
        'user-agent': KugouLiveApi.userAgent,
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://fanxing.kugou.com',
        'referer': 'https://fanxing.kugou.com/51049168',
      });
      expect(request.headers, {
        for (final MapEntry(:key, :value) in ((_s07.meta['request']! as Map)['headers'] as Map).entries)
          key as String: value,
      });
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 7));
      expect(request.cancel, same(cancel));
    });

    test('grants: the recorded answers; refusals; answers that cannot be read', () {
      final grant = KugouLiveDanmakuProtocol.grant(_recordedGrant);
      final web = _s07.expected['dispatch']! as Map;
      expect(grant.endpoints.map((uri) => '$uri'), web['hosts']);
      expect(grant.endpoints, [
        Uri.parse('wss://chatwss146107.kugou.com/acksocket'),
        Uri.parse('wss://chatwss140058.kugou.com/acksocket'),
        Uri.parse('wss://chatwss140045.kugou.com/acksocket'),
      ]);
      expect(grant.token, web['soctoken']);
      expect(grant.age, Duration(milliseconds: web['age']! as int));
      expect(KugouLiveDanmakuProtocol.grant(_answer(_s08.dispatch.text!)).endpoints, hasLength(3));

      // What the server answered to a signature it did not accept (2026-09-30).
      expect(
        () => KugouLiveDanmakuProtocol.grant(_refusedAnswer()),
        throwsA(
          isA<KugouLiveDispatchRefusal>()
              .having((e) => e.code, 'code', 1100014)
              .having((e) => '$e', 'text', 'dispatch: code 1100014 sign verify fail'),
        ),
      );
      expect(
        () => KugouLiveDanmakuProtocol.grant(_answer('{"data":{}}')),
        throwsA(isA<KugouLiveDispatchRefusal>().having((e) => '$e', 'text', 'dispatch: code -1')),
      );
      expect(() => KugouLiveDanmakuProtocol.grant(_answer('{}', status: 403)), throwsA(isA<RiskControl>()));
      expect(() => KugouLiveDanmakuProtocol.grant(_answer('{}', status: 502)), throwsA(isA<NetworkFailure>()));
      for (final body in [
        '<html>',
        '[1]',
        '{"code":0}',
        '{"code":0,"data":[]}',
        '{"code":0,"data":{"soctoken":"t"}}',
        '{"code":0,"data":{"addrs":[],"soctoken":"t"}}',
        '{"code":0,"data":{"addrs":[{"host":"a.kugou.com/acksocket"}]}}',
        '{"code":0,"data":{"addrs":[{"host":"a.kugou.com/acksocket"}],"soctoken":"a b"}}',
        '{"code":0,"data":{"addrs":[{"host":"a.kugou.com/acksocket"}],"soctoken":"令牌"}}',
        '{"code":0,"data":{"addrs":[{"host":"a.kugou.com/acksocket"}],"soctoken":"${'t' * 1025}"}}',
        '{"code":0,"data":{"addrs":[{"host":""},{"nohost":1},"x",{"host":7}],"soctoken":"t"}}',
        '{"code":0,"data":{"protocol":"https://","addrs":[{"host":"a.kugou.com"}],"soctoken":"t"}}',
      ]) {
        expect(() => KugouLiveDanmakuProtocol.grant(_answer(body)), throwsA(isA<ApiChanged>()), reason: body);
      }

      // No protocol: ws:// (the page's default); repeated hosts once; the
      // age falls back to five minutes.
      final plain = KugouLiveDanmakuProtocol.grant(
        _answer(
          '{"code":"0","data":{"addrs":[{"host":"a.kugou.com/acksocket"},{"host":"a.kugou.com/acksocket"},'
          '{"host":"b.kugou.com:8080/x"}],"soctoken":"${'t' * 1024}","age":"x"}}',
        ),
      );
      expect(plain.endpoints, [Uri.parse('ws://a.kugou.com/acksocket'), Uri.parse('ws://b.kugou.com:8080/x')]);
      expect(plain.token, hasLength(1024));
      expect(plain.age, const Duration(minutes: 5));
      for (final age in [0, -1, null]) {
        expect(KugouLiveDanmakuProtocol.grant(_granted('t', age: age)).age, const Duration(minutes: 5));
      }
      expect(KugouLiveDanmakuProtocol.grant(_granted('t', age: 60000)).age, const Duration(minutes: 1));
    });

    test("the login: the recorded frames byte for byte, and the page's own encoding of them", () {
      for (final sample in [_s07, _s08]) {
        final recorded = sample.socket.firstWhere((line) => !line.incoming).bytes!;
        final page = (sample.expected['login']! as Map)['object'] as Map;
        final login = KugouLiveDanmakuProtocol.login(
          roomId: sample.room,
          token: page['soctoken'] as String,
          sid: page['sid'] as String,
          deviceNo: page['deviceNo'] as String,
        );
        expect(login, recorded, reason: sample.name);
        expect(login, base64.decode((sample.expected['login']! as Map)['b64'] as String), reason: sample.name);
      }
      // The header: 100, version 3, type 1, 12, the command, the length, zeros.
      final again = KugouLiveDanmakuProtocol.login(
        roomId: _room,
        token: 'token',
        sid: 'sid',
        deviceNo: 'device',
        sessionId: 'session',
        again: true,
      );
      expect(again.sublist(0, 18), [100, 0, 3, 1, 0, 12, 0, 0, 8, 153, 0, 0, 0, again.length - 18, 0, 0, 0, 0]);
      final request = ProtoMessage.decode(ProtoMessage.decode(again.sublist(18)).bytes(7)!);
      expect(
        [for (final field in request.fields) field.number],
        [1, 2, 3, 4, 6, 7, 10, 12, 13, 14, 15, 18, 23, 29, 38],
      );
      expect(request.integer(1), 2201);
      expect(request.string(23), 'session');
      expect(_login(again), (2201, 'token', 'session'));
      // Header, then Message{content: [1, 2]}.
      const header = [100, 0, 3, 1, 0, 12, 0, 0, 1, 245, 0, 0, 0, 4, 0, 0, 0, 0];
      expect(KugouLiveDanmakuProtocol.frame(501, [1, 2]), [...header, 58, 2, 1, 2]);
    });

    test('S07: every received frame is read as the website reads it', () {
      var chats = 0;
      var audience = 0;
      var status = 0;
      var heartbeats = 0;
      for (final line in _s07.socket.where((line) => line.incoming)) {
        final page = _s07.expectedAt(line.line);
        final frame = KugouLiveDanmakuProtocol.decode(line.bytes, roomId: _room);
        final reason = 'line ${line.line}';
        if (page['heartbeat'] != null) {
          heartbeats++;
          expect(page['heartbeat'], '64000300');
          expect(frame.heartbeat, isTrue, reason: reason);
          expect(frame.messages, isEmpty);
          continue;
        }
        expect(frame.heartbeat, isFalse, reason: reason);
        if (page['status'] case final Map<String, Object?> expected) {
          status++;
          final accepted = page['sessionSet'] == true;
          expect(frame.joined, accepted, reason: reason);
          expect(frame.sessionId, accepted ? expected['socsid'] : null, reason: reason);
          expect(frame.refusal, isNull, reason: reason);
        } else if (page['chat'] case final Map<String, Object?> chat) {
          chats++;
          expect(chat['shown'], isTrue);
          _expectChat(frame.messages.single, chat, reason: reason);
        } else if (page['audience'] case final Map<String, Object?> numbers) {
          audience++;
          expect(frame.messages.map((m) => m.type), [LiveMessageType.online, LiveMessageType.online]);
          final updates = [for (final message in frame.messages) message.data! as LiveAudienceUpdate];
          expect(
            [for (final update in updates) (update.kind, update.value)],
            [
              (LiveAudienceMetricKind.onlineViewers, numbers['count']),
              (LiveAudienceMetricKind.totalViewers, numbers['visited']),
            ],
            reason: reason,
          );
        } else {
          expect(frame.messages, isEmpty, reason: '$reason: command ${page['cmd']}');
          expect(frame.joined, isFalse);
        }
      }
      expect((chats, audience, status, heartbeats), (37, 5, 2, 29));
    });

    test('S07 in detail: the welcome account, a viewer, a chat to the broadcaster in public', () {
      final messages = [
        for (final line in _s07.socket.where((line) => line.incoming))
          ...KugouLiveDanmakuProtocol.decode(
            line.bytes,
            roomId: _room,
          ).messages.where((message) => message.type == LiveMessageType.chat),
      ];
      final first = messages.first;
      expect(
        (first.userName, first.userId, first.message, first.userLevel, first.fansName),
        ('观众001', '5847998728', '第1天来了，欢迎~，『观众002』来了，欢迎您哦！[/抱抱]', '', ''),
      );
      expect(first.messageId, '5847998728:1790771498671');
      expect(first.sentAt!.toUtc(), DateTime.utc(2026, 9, 30, 12, 31, 38));
      final viewer = messages[1];
      expect(
        (viewer.userName, viewer.message, viewer.userLevel, viewer.messageId),
        ('观众03', '跳个舞看看', '1', '7331759460:3321129'),
      );
      // To the broadcaster in public: shown as its text (the page adds “对 … 说”).
      final guest = messages.firstWhere((message) => message.message.startsWith('发现一名神秘嘉宾'));
      expect(guest.userName, '观众001');
      // Envelope and chat ids differ for this viewer: the envelope's is used.
      final other = messages.firstWhere((message) => message.message == '我吗？');
      expect((other.userId, other.userLevel), ('446974472', '23'));
    });

    test("S08: a refused token (622) after type 4; S09: the PK partner room's chat is marked as theirs (B-16)", () {
      final frames = [
        for (final line in _s08.socket.where((line) => line.incoming))
          KugouLiveDanmakuProtocol.decode(line.bytes, roomId: _s08.room),
      ];
      expect(frames.first.joined, isFalse);
      expect(frames.first.refusal, isNull);
      final refusal = frames.last.refusal!;
      expect((refusal.errorNo, refusal.message, refusal.tokenRejected), (622, '', true));
      expect('$refusal', '901 errorno 622');
      expect(_s08.expectedFrames.last['askSchedulerAgain'], isTrue);
      expect(const KugouLiveChatRefusal(630, 'kicked').toString(), '901 errorno 630 kicked');
      expect(const KugouLiveChatRefusal(630).tokenRejected, isFalse);

      final pk = _s09.socket.single;
      final page = _s09.expectedAt(pk.line)['chat']! as Map<String, Object?>;
      expect(page['shown'], isTrue, reason: 'the page shows it, marked as the other side');
      expect(page['otherRoom'], isTrue);
      expect(page['source'], {'roomid': 5138284, 'tags': 3});
      expect(page['roomid'], 1073619);
      // B-16 (M5.25 did not report it): chat like the room's own, marked
      // with the partner room.
      final partner = KugouLiveDanmakuProtocol.decode(pk.bytes, roomId: '1073619').messages.single;
      expect(
        (partner.type, partner.userName, partner.message, partner.userId, partner.userLevel),
        (LiveMessageType.chat, page['userName'], page['text'], '${page['operationUserId']}', '${page['richLevel']}'),
      );
      expect((partner.sourceRoomId, partner.isFromOtherRoom), ('5138284', true));
      expect(partner.color, KugouLiveDanmakuProtocol.highlightColor, reason: "the page's ${page['contentColor']}");
      expect(partner.sentAt, DateTime.fromMillisecondsSinceEpoch((page['time']! as int) * 1000));
      expect(KugouLiveDanmakuProtocol.decode(pk.bytes, roomId: '5138284').messages, isEmpty, reason: 'not this room');
    });

    test('status frames: join with or without a session, refusals, other types', () {
      final joined = KugouLiveDanmakuProtocol.decode(_status(type: 1, status: 1, session: 's1'), roomId: _room);
      expect((joined.joined, joined.sessionId, joined.refusal), (true, 's1', null));
      final bare = KugouLiveDanmakuProtocol.decode(_status(type: 1, status: 1), roomId: _room);
      expect((bare.joined, bare.sessionId), (true, null));
      for (final type in [0, 2, 4]) {
        final other = KugouLiveDanmakuProtocol.decode(
          _status(type: type, status: 1, session: 's'),
          roomId: _room,
        );
        expect((other.joined, other.refusal), (false, null), reason: '$type');
      }
      final refused = KugouLiveDanmakuProtocol.decode(
        _status(type: 1, status: 0, errorNo: 630, message: '{"reason":"x"}'),
        roomId: _room,
      );
      expect((refused.joined, refused.refusal!.errorNo, refused.refusal!.message), (false, 630, '{"reason":"x"}'));
      expect(KugouLiveDanmakuProtocol.decode(_status(type: 1), roomId: _room).refusal!.errorNo, 0);
      // A status in JSON (envelope codec 0) reads the same.
      final json = KugouLiveDanmakuProtocol.decode(
        _json(901, {'cmd': 901, 'type': 1, 'status': 1, 'socsid': 'j1'}),
        roomId: _room,
      );
      expect((json.joined, json.sessionId), (true, 'j1'));
    });

    test('chat: what the public chat shows, and what it does not', () {
      LiveMessage? read(Uint8List frame, {String room = _room}) {
        final messages = KugouLiveDanmakuProtocol.decode(frame, roomId: room).messages;
        return messages.isEmpty ? null : messages.single;
      }

      final plain = read(_chat())!;
      expect(
        (plain.userName, plain.userId, plain.message, plain.userLevel, plain.fansName, plain.fansLevel),
        ('观众001', '5847998728', '主播好', '11', '姜姜芽', '6'),
      );
      expect(plain.messageId, '5847998728:1790771498671');
      expect(plain.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771498000));

      // Not in the public chat.
      expect(read(_chat(envelopeReceiver: 2454242816)), isNull, reason: 'private');
      expect(read(_chat(senderId: -5)), isNull, reason: 'sender below 0');
      expect(read(_chat(room: 1073619)), isNull, reason: 'another room');
      expect(read(_chat(text: '')), isNull);
      expect(read(_chat(text: ' \u2028 ')), isNull);
      expect(read(_chat(contentCodec: 0)), isNull, reason: 'the page cannot read it either');
      // The PK partner room (B-16): only with the partner's room and
      // `source.tags & 1`, as the page.
      expect(read(_chat(command: 400305)), isNull, reason: 'no source');
      expect(read(_chat(command: 400305, source: (5138284, 2))), isNull, reason: 'tags without bit 1');
      expect(read(_chat(command: 400305, source: (0, 1))), isNull, reason: 'no partner room');
      expect(read(_chat(command: 400305, source: (51049168, 1))), isNull, reason: 'this room is no partner');
      final partner = read(_chat(command: 400305, source: (5138284, 1)))!;
      expect((partner.message, partner.sourceRoomId), ('主播好', '5138284'));
      expect(plain.sourceRoomId, isEmpty, reason: "the room's own chat");
      expect(read(_chat(source: (5138284, 1)))!.sourceRoomId, isEmpty, reason: 'a source on 501 is not read');
      expect(read(_chat(), room: '1073619'), isNull);
      expect(read(_chat(room: 0))?.message, '主播好', reason: 'no room: kept');

      // A chat to someone in public is its text.
      expect(read(_chat(chatReceiver: 2454242816, receiverName: '姜拾七er'))?.message, '主播好');
      // The page's separators and direction marks go; spaces stay (the page
      // removes every space, see docs/D-弹幕/D01-平台弹幕协议/D01.26-酷狗直播弹幕/record.md).
      final marks = read(
        _chat(text: ' a\u2027b\u2028c\u2029d\u202Ae\u202Bf\u202Cg\u202Dh\u202Ei j ', name: '\u202E观众 1'),
      )!;
      expect((marks.message, marks.userName), ('abcdefghi j', '观众 1'));
      // Levels: V2 first, then the old one, 0 is none.
      expect(read(_chat(level: 20, levelV2: 0))!.userLevel, '20');
      expect(read(_chat(level: 0, levelV2: 0))!.userLevel, '');
      // Fan badges as the page lights them.
      for (final (ext, badge) in [
        (_ext(level: 0), null),
        (_ext(type: 0), null),
        (_ext(type: 5), null),
        (_ext(type: 4, level: 22), ('姜姜芽', '22')),
        (_ext(lightUp: 0), null),
        (_ext(nameplate: ''), null),
        (_ext(intimacy: false), null),
        (Uint8List(0), null),
      ]) {
        final message = read(_chat(ext: ext))!;
        expect((message.fansName, message.fansLevel), badge ?? ('', ''), reason: '$badge');
      }
      // A mystery guest: the alias id, never the sender's.
      final alias =
          (ProtoWriter()
                ..integer(1, 1)
                ..integer(5, 1)
                ..string(6, '神秘嘉宾')
                ..string(8, '800001'))
              .toBytes();
      expect(read(_chat(sinfo: alias))!.userId, '800001');
      expect(read(_chat(sinfo: (ProtoWriter()..integer(5, 1)).toBytes()))!.userId, '');
      expect(read(_chat(sinfo: (ProtoWriter()..integer(5, 2)).toBytes()))!.userId, '5847998728');
      // Ids: the envelope's msgId first; no sequence or sender, none.
      expect(read(_chat(msgId: 'm-1'))!.messageId, 'm-1');
      expect(read(_chat(seq: 0))!.messageId, '');
      expect(read(_chat(senderId: 0, kugouId: 0))!.messageId, '');
      expect(read(_chat(senderId: 0, kugouId: 0))!.userId, '');
      // Times: seconds, milliseconds above 10^11, nothing at 0 or beyond DateTime.
      expect(read(_chat(time: 1790771498123))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771498123));
      expect(read(_chat(time: 0))!.sentAt, isNull);
      expect(read(_chat(time: 8640000000000001))!.sentAt, isNull);
      expect(read(_chat(time: 8640000000000000))!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
    });

    test('chat in JSON (envelope codec 0): the same rules, the URL-encoded ext', () {
      Map<String, Object?> json({Object? receiver = 0, Object? privateType, Object? ext, Object? sinfo}) => {
        'cmd': 501,
        'roomid': '51049168',
        'receiverid': receiver,
        'senderid': '5847998728',
        'time': 1790771498,
        'ext': ?ext,
        'sinfo': ?sinfo,
        'content': {
          'chatmsg': '你好',
          'sendername': '观众001',
          'senderid': 5847998728,
          'senderrichlevel': 3,
          'seq': 7,
          'privateType': ?privateType,
        },
      };
      LiveMessage? read(Map<String, Object?> message) {
        final messages = KugouLiveDanmakuProtocol.decode(_json(501, message), roomId: _room).messages;
        return messages.isEmpty ? null : messages.single;
      }

      final badge = Uri.encodeComponent(
        jsonEncode({
          'intimacyVo': {'level': 3, 'nameplate': '豆粉', 'type': 2, 'lightUp': 1},
        }),
      );
      final message = read(json(ext: badge))!;
      expect(
        (message.message, message.userId, message.userLevel, message.fansName, message.fansLevel, message.messageId),
        ('你好', '5847998728', '3', '豆粉', '3', '5847998728:7'),
      );
      expect(read(json(ext: '%E0%A4%A')), isNotNull, reason: 'a bad escape only loses the badge');
      expect(read(json(ext: '%E0%A4%A'))!.fansName, '');
      expect(read(json(ext: '%FF'))!.fansName, '');
      expect(read(json(ext: 'not json'))!.fansName, '');
      expect(read(json(ext: 42))!.fansName, '');
      expect(read(json(privateType: 1)), isNull);
      expect(read(json(receiver: '7')), isNull);
      expect(read(json(sinfo: {'ck': 1, 'ckid': 'alias'}))!.userId, 'alias');
      expect(read({...json(), 'content': 'text'}), isNull);
    });

    group('B-15: the text colour of the page', () {
      const orange = KugouLiveDanmakuProtocol.highlightColor;
      const gold = KugouLiveDanmakuProtocol.mysteryColor;
      const white = LiveMessageColor.white;

      test('the colours: #ff9900 and #CC9900', () {
        expect('$orange', '#ff9900');
        expect('$gold', '#cc9900');
      });

      test('recorded chats (S10, S11) against the page: level 8 and above, guards, little guards, a mystery guest', () {
        final colours = <LiveMessageColor>[];
        for (final sample in [_s10, _s11]) {
          for (final line in sample.socket) {
            final message = KugouLiveDanmakuProtocol.decode(line.bytes, roomId: sample.room).messages.single;
            final page = sample.expectedAt(line.line)['chat']! as Map<String, Object?>;
            expect(page['shown'], isTrue);
            _expectChat(message, page, reason: '${sample.name} line ${line.line}');
            colours.add(message.color);
          }
        }
        expect(colours, [
          orange, // S10: fan club 33 and a little guard
          orange, // fan club 8, the lowest highlighted
          orange, // a guard (userGuard.g "1") without a fan club
          orange, // a guard at fan club 30
          white, // the plate owner: empty guard entries, no fan club
          white, // fan club 3
          gold, // S11: a mystery guest at fan club 22
          white, // fan club 7, just below
        ]);
      });

      test('the recorded frames hold what the colour is read from', () {
        List<int?> levels(_Sample sample) => [
          for (final line in sample.socket)
            ((sample.expectedAt(line.line)['chat']! as Map)['fanBadge'] as Map?)?['level'] as int?,
        ];
        // Fan clubs lit (lightUp 1, type 1 to 4) show as badges; the level
        // counts whether lit or not.
        expect(levels(_s10), [33, 8, null, 30, null, 3]);
        expect(levels(_s11), [22, 7]);
        expect(
          _s07.expectedFrames.where((frame) => frame['chat'] != null).map((frame) => frame['chat']),
          everyElement(containsPair('contentColor', null)),
        );
      });

      test('synthetic chats: the thresholds and JavaScript truthiness of the page', () {
        LiveMessageColor colour({List<int>? ext, List<int>? sinfo}) => KugouLiveDanmakuProtocol.decode(
          _chat(ext: ext, sinfo: sinfo),
          roomId: _room,
        ).messages.single.color;
        List<int> ext({int? level, List<int>? userGuard, List<int>? littleGuard}) {
          final writer = ProtoWriter();
          if (userGuard != null) writer.bytes(8, userGuard);
          if (littleGuard != null) writer.bytes(9, littleGuard);
          if (level != null) writer.bytes(39, (ProtoWriter()..integer(1, level)).toBytes());
          return writer.toBytes();
        }

        List<int> guard(String g) => (ProtoWriter()..string(1, g)).toBytes();
        List<int> little(int l) => (ProtoWriter()..integer(1, l)).toBytes();
        final mystery =
            (ProtoWriter()
                  ..integer(5, 1)
                  ..string(8, 'alias'))
                .toBytes();

        for (final (label, value, expected) in [
          ('level 7', ext(level: 7), white),
          ('level 8', ext(level: 8), orange),
          ('level 0', ext(level: 0), white),
          ('level -9', ext(level: -9), white),
          ('no fan club', ext(), white),
          ('an empty ext', <int>[], white),
          ('an empty guard entry', ext(userGuard: const []), white),
          ('guard g ""', ext(userGuard: guard('')), white),
          ('guard g "0" (a non-empty string)', ext(userGuard: guard('0')), orange),
          ('guard g "6"', ext(userGuard: guard('6')), orange),
          ('little guard l 0', ext(littleGuard: little(0)), white),
          ('little guard l 1', ext(littleGuard: little(1)), orange),
          ('little guard l -1', ext(littleGuard: little(-1)), orange),
          ('little guard entry, g only', ext(littleGuard: (ProtoWriter()..integer(2, 1)).toBytes()), white),
          ('level 3 with a guard', ext(level: 3, userGuard: guard('1')), orange),
        ]) {
          expect(colour(ext: value), expected, reason: label);
        }
        // A mystery guest is gold over everything, also without an ext.
        expect(
          colour(
            ext: ext(level: 30, userGuard: guard('6')),
            sinfo: mystery,
          ),
          gold,
        );
        expect(colour(ext: ext(level: 2), sinfo: mystery), gold);
        expect(colour(ext: const [], sinfo: mystery), gold);
        expect(
          colour(ext: ext(level: 9), sinfo: (ProtoWriter()..integer(5, 2)).toBytes()),
          orange,
          reason: 'ck 2',
        );
        expect(
          colour(ext: ext(level: 9), sinfo: (ProtoWriter()..integer(1, 1)).toBytes()),
          orange,
          reason: 'no ck',
        );
      });

      test('chat in JSON: the URL-encoded ext read as JSON, JavaScript comparisons; no ext, no colour', () {
        LiveMessageColor? colour({Object? ext, Object? sinfo}) {
          final message = {
            'cmd': 501,
            'roomid': 51049168,
            'receiverid': 0,
            'senderid': 5847998728,
            'time': 1790771498,
            'ext': ?ext,
            'sinfo': ?sinfo,
            'content': {'chatmsg': '你好', 'sendername': '观众001', 'senderid': 5847998728, 'seq': 7},
          };
          final messages = KugouLiveDanmakuProtocol.decode(_json(501, message), roomId: _room).messages;
          return messages.isEmpty ? null : messages.single.color;
        }

        String encoded(Map<String, Object?> ext) => Uri.encodeComponent(jsonEncode(ext));
        for (final (label, ext, expected) in [
          (
            'level 8',
            encoded({
              'intimacyVo': {'level': 8},
            }),
            orange,
          ),
          (
            'level "8" (text compares as a number)',
            encoded({
              'intimacyVo': {'level': '8'},
            }),
            orange,
          ),
          (
            'level 7.5',
            encoded({
              'intimacyVo': {'level': 7.5},
            }),
            orange,
          ),
          (
            'level "7"',
            encoded({
              'intimacyVo': {'level': '7'},
            }),
            white,
          ),
          (
            'level "abc"',
            encoded({
              'intimacyVo': {'level': 'abc'},
            }),
            white,
          ),
          (
            'level true',
            encoded({
              'intimacyVo': {'level': true},
            }),
            white,
          ),
          (
            'little guard l "0" (a non-empty string)',
            encoded({
              'littleGuard': {'l': '0'},
            }),
            orange,
          ),
          (
            'little guard l 0',
            encoded({
              'littleGuard': {'l': 0},
            }),
            white,
          ),
          (
            'little guard l false',
            encoded({
              'littleGuard': {'l': false},
            }),
            white,
          ),
          (
            'guard g 0',
            encoded({
              'userGuard': {'g': 0},
            }),
            white,
          ),
          (
            'guard g {}',
            encoded({
              'userGuard': {'g': <String, Object?>{}},
            }),
            orange,
          ),
          (
            'guard g null',
            encoded({
              'userGuard': {'g': null},
            }),
            white,
          ),
          ('guard not an object', encoded({'userGuard': 'yes'}), white),
          ('not an object', encoded({'intimacyVo': 9}), white),
          ('a bad escape', '%E0%A4%A', white),
          ('not JSON', 'not json', white),
          ('JSON null', 'null', white),
          ('an empty string', '', white),
        ]) {
          expect(colour(ext: ext), expected, reason: label);
        }
        // The page colours mystery guests only through the ext it parsed.
        expect(colour(ext: encoded({}), sinfo: {'ck': 1, 'ckid': 'alias'}), gold);
        expect(colour(sinfo: {'ck': 1, 'ckid': 'alias'}), white, reason: 'no ext');
        expect(
          colour(ext: '%E0%A4%A', sinfo: {'ck': 1}),
          white,
          reason: 'an ext the page cannot read',
        );
        expect(
          colour(
            ext: encoded({
              'intimacyVo': {'level': 9},
            }),
            sinfo: {'ck': 0},
          ),
          orange,
        );
      });

      test("the PK partner room's chat (400305) is coloured as the page colours it (B-16)", () {
        final pk = _s09.socket.single;
        final page = _s09.expectedAt(pk.line)['chat']! as Map<String, Object?>;
        expect(page['contentColor'], '#ff9900', reason: 'the page colours it (fan club 10)');
        expect(
          KugouLiveDanmakuProtocol.decode(pk.bytes, roomId: '1073619').messages.single.color,
          KugouLiveDanmakuProtocol.highlightColor,
        );
      });
    });

    test('the audience: viewers now and of the broadcast; nothing else', () {
      List<(LiveAudienceMetricKind, int)> read(Uint8List frame) => [
        for (final message in KugouLiveDanmakuProtocol.decode(frame, roomId: _room).messages)
          ((message.data! as LiveAudienceUpdate).kind, (message.data! as LiveAudienceUpdate).value),
      ];

      expect(read(_audience()), [
        (LiveAudienceMetricKind.onlineViewers, 100),
        (LiveAudienceMetricKind.totalViewers, 2594),
      ]);
      expect(read(_audience(count: '87', visited: null)), [(LiveAudienceMetricKind.onlineViewers, 87)]);
      expect(read(_audience(count: null, visited: 0)), [(LiveAudienceMetricKind.totalViewers, 0)]);
      expect(read(_audience(count: -1, visited: 'x')), isEmpty);
      expect(read(_audience(room: null)), hasLength(2));
      expect(read(_audience(room: 1073619)), isEmpty);
      expect(read(_audience(action: 'roomHot')), isEmpty);
      expect(read(_json(301005, {'cmd': 301005, 'content': 'x'})), isEmpty);
      expect(
        read(
          _json(301005, {
            'cmd': 301005,
            'content': {'actionId': 'roomAuNumber', 'data': 7},
          }),
        ),
        isEmpty,
      );
      final online = KugouLiveDanmakuProtocol.decode(_audience(), roomId: _room).messages.first;
      expect((online.type, online.userName, online.message), (LiveMessageType.online, '', ''));
    });

    test('frames that give nothing: text, short or broken headers, bad protobuf, JSON or compression', () {
      KugouLiveDanmakuFrame read(Object? data) => KugouLiveDanmakuProtocol.decode(data, roomId: _room);
      final chat = _chat();
      for (final (name, data) in <(String, Object?)>[
        ('text', 'H'),
        ('null', null),
        ('empty', <int>[]),
        ('3 bytes', [100, 0, 3]),
        ('9 bytes', chat.sublist(0, 9)),
        ('variable part below 4', Uint8List.fromList([...chat.sublist(0, 4), 0, 3, ...chat.sublist(6)])),
        ('negative variable part', Uint8List.fromList([...chat.sublist(0, 4), 0xFF, 0xF0, ...chat.sublist(6)])),
        ('variable part past the end', Uint8List.fromList([...chat.sublist(0, 4), 0x7F, 0x00, ...chat.sublist(6)])),
        ('truncated protobuf', chat.sublist(0, chat.length - 3)),
        ('unknown command', _server(300361, _envelope(utf8.encode('{"cmd":300361}')))),
        ('not JSON', _server(301005, _envelope(utf8.encode('{"cmd":')))),
        ('JSON not an object', _server(301005, _envelope(utf8.encode('[1]')))),
        ('bad UTF-8', _server(301005, _envelope([0xFF, 0xFE]))),
        ('bad gzip', _server(301005, _envelope([1, 2, 3], compression: 1))),
        ('bad snappy', _server(301005, _envelope([5, 0, 1], compression: 2))),
      ]) {
        final frame = read(data);
        expect(frame.messages, isEmpty, reason: name);
        expect((frame.joined, frame.refusal, frame.heartbeat), (false, null, false), reason: name);
      }
      expect(read([100, 0, 3, 0]).heartbeat, isTrue);
      expect(read(Uint8List.fromList([100, 0, 3, 0, 9, 9])).heartbeat, isTrue);
      // An unknown compression is read as it is (the page does the same).
      expect(
        read(_json(301005, jsonDecode(utf8.decode(_audienceJson())) as Map<String, Object?>, compression: 9)).messages,
        hasLength(2),
      );
      // Gzip and snappy.
      expect(
        read(_json(301005, jsonDecode(utf8.decode(_audienceJson())) as Map<String, Object?>, gzipped: true)).messages,
        hasLength(2),
      );
      expect(read(_server(301005, _envelope(_snappyLiteral(_audienceJson()), compression: 2))).messages, hasLength(2));
      // A gzipped message above the limit is dropped.
      final huge = gzip.encode(Uint8List(KugouLiveDanmakuProtocol.maxContentBytes + 1));
      expect(read(_server(301005, _envelope(huge, compression: 1))).messages, isEmpty);
      // The recorded gzipped system message (cmd 100) reads, and says nothing.
      final gzipped = _s07.socket.firstWhere((line) => _s07.expectedAt(line.line)['cmd'] == 100);
      expect(read(gzipped.bytes).messages, isEmpty);
    });

    test('gifts: never reported; acknowledged (211) when the envelope asks, as the page does', () {
      final frame = KugouLiveDanmakuProtocol.decode(_gift(), roomId: _room);
      expect(frame.messages, isEmpty);
      final ack = frame.ack!;
      expect(
        ack,
        KugouLiveDanmakuProtocol.ack(roomId: _room, offset: '14215147132598579', msgId: '2216677664281887088'),
      );
      expect(ack.sublist(0, 14), [100, 0, 3, 1, 0, 12, 0, 0, 0, 211, 0, 0, 0, ack.length - 18]);
      final request = ProtoMessage.decode(ProtoMessage.decode(ack.sublist(18)).bytes(7)!);
      expect(
        [
          for (final field in request.fields)
            (field.number, field.value is List<int> ? utf8.decode(field.value as List<int>) : field.value),
        ],
        [(1, 211), (2, 51049168), (3, 0), (4, '14215147132598579'), (5, '2216677664281887088'), (6, 0)],
      );
      final repeated = KugouLiveDanmakuProtocol.decode(
        _gift(repeat: 2, msgId: 'm', offset: ''),
        roomId: _room,
      ).ack!;
      expect(repeated, KugouLiveDanmakuProtocol.ack(roomId: _room, offset: '', msgId: 'm', repeat: 2));
      expect(KugouLiveDanmakuProtocol.decode(_gift(ack: 0), roomId: _room).ack, isNull);
      expect(KugouLiveDanmakuProtocol.decode(_gift(ack: 2), roomId: _room).ack, isNull);
      expect(
        KugouLiveDanmakuProtocol.decode(_chat(msgId: 'x'), roomId: _room).ack,
        isNull,
        reason: 'only gifts',
      );
      final broken = _gift();
      expect(KugouLiveDanmakuProtocol.decode(broken.sublist(0, broken.length - 2), roomId: _room).ack, isNull);
      // A gift in JSON asks the same way (the envelope's ack).
      final json = _server(
        601,
        (ProtoWriter()
              ..string(1, '7')
              ..integer(2, 1)
              ..string(4, 'j')
              ..bytes(7, utf8.encode('{"cmd":601,"content":{}}')))
            .toBytes(),
      );
      expect(
        KugouLiveDanmakuProtocol.decode(json, roomId: _room).ack,
        KugouLiveDanmakuProtocol.ack(roomId: _room, offset: '7', msgId: 'j'),
      );
    });

    test('snappy: literals and copies as snappyjs reads them; anything malformed throws', () {
      Uint8List snappy(List<int> bytes) => KugouLiveDanmakuProtocol.snappy(Uint8List.fromList(bytes));
      // "abcabcabcab": a literal of 3, then a copy of 8 from offset 3 (tag kind 1).
      expect(utf8.decode(snappy([11, 0x08, 0x61, 0x62, 0x63, 0x11, 0x03])), 'abcabcabcab');
      // Overlapping run: "a" then copy 9 at offset 1 (tag kind 2: length 9 → (8 << 2) | 2).
      expect(utf8.decode(snappy([10, 0x00, 0x61, 0x22, 0x01, 0x00])), 'aaaaaaaaaa');
      // Tag kind 3 (4-byte offset).
      expect(utf8.decode(snappy([6, 0x08, 0x78, 0x79, 0x7A, 0x0B, 0x03, 0, 0, 0])), 'xyzxyz');
      // A literal of 61 bytes and more: the length follows the tag.
      final long = List<int>.generate(300, (i) => 0x41 + i % 26);
      expect(snappy([0xAC, 0x02, 0xF4, 0x2B, 0x01, ...long]), long);
      expect(snappy([0]), isEmpty);
      for (final (name, bytes) in [
        ('no length', <int>[]),
        ('length too long', [0x80, 0x80, 0x80, 0x80, 0x80, 0x01]),
        ('too large', [0x81, 0x80, 0x80, 0x02]),
        ('literal past the input', [3, 0x08, 0x61]),
        ('literal past the length', [1, 0x04, 0x61, 0x62]),
        ('copy before the start', [4, 0x00, 0x61, 0x05, 0x02]),
        ('copy offset 0', [5, 0x00, 0x61, 0x01, 0x00]),
        ('copy past the length', [3, 0x00, 0x61, 0x05, 0x01]),
        ('truncated offset', [5, 0x00, 0x61, 0x02]),
        ('short output', [5, 0x00, 0x61]),
      ]) {
        expect(() => snappy(bytes), throwsFormatException, reason: name);
      }
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = KugouLiveDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 10));
      expect(policy.joinTimeout, const Duration(seconds: 10));
      expect(policy.inactivityTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(KugouLiveDanmakuConnection.dispatchRetryDelays, const [
        Duration(milliseconds: 1500),
        Duration(milliseconds: 4500),
      ]);
      final connection = KugouLiveDanmakuConnection(http: _Http([_recordedGrant]));
      expect(connection.heartbeatInterval, const Duration(seconds: 10));
      expect(connection.site, SiteIds.kugouLive);
      expect(connection.status, DanmakuStatus.idle);
      final registry = DanmakuRegistry({
        SiteIds.kugouLive: () => KugouLiveDanmakuConnection(http: _Http([_recordedGrant])),
      });
      expect(registry.supports('KugouLive'), isTrue);
      expect(registry.connectionFor('kugoulive'), isA<KugouLiveDanmakuConnection>());
    });

    test('start: the scheduler, the first host, the login; ready on the accepted login; chat and audience', () async {
      final connector = _Connector();
      final http = _Http([_recordedGrant]);
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        connector,
        http,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.kugouLive: route}),
      );
      final events = _record(connection);
      await connection.connect(_args);
      final request = http.requests.single;
      final expected = KugouLiveDanmakuProtocol.dispatchRequest(_room, now: _now);
      expect(request.url, expected.url);
      expect(request.headers, expected.headers);
      expect(request.followRedirects, isFalse);
      expect(request.timeout, KugouLiveDanmakuConnection.defaultPolicy.connectTimeout);
      expect(connector.endpoints, [Uri.parse('wss://chatwss146107.kugou.com/acksocket')]);
      expect(connector.headers.single, KugouLiveDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      final channel = connector.channels.single;
      final (sid, device) = _ids();
      expect(channel.sent, [
        KugouLiveDanmakuProtocol.login(
          roomId: _room,
          token: KugouLiveDanmakuProtocol.grant(_recordedGrant).token,
          sid: sid,
          deviceNo: device,
        ),
      ]);
      await channel.receive(_status(type: 4, status: 1));
      expect(events, isEmpty);
      expect(connection.isConnected, isFalse);
      await channel.receive(_status(type: 1, status: 1, session: 's1'));
      expect(events, [const DanmakuReady()]);
      await channel.receive(_chat());
      await channel.receive(_audience());
      await channel.receive(Uint8List.fromList([100, 0, 3, 0]));
      await channel.receive(_gift());
      expect(
        channel.sent.last,
        KugouLiveDanmakuProtocol.ack(roomId: _room, offset: '14215147132598579', msgId: '2216677664281887088'),
      );
      expect(
        [for (final m in _messages(events)) m.type],
        [LiveMessageType.chat, LiveMessageType.online, LiveMessageType.online],
      );
      connection.heartbeat();
      expect(channel.sent.last, [100, 0, 1, 0]);
      await connection.close();
    });

    test('the connection replays S07: its login, ready once, the 37 chats and 10 audience numbers in order', () async {
      final connector = _Connector();
      final page = (_s07.expected['login']! as Map)['object'] as Map;
      final connection = KugouLiveDanmakuConnection(
        http: _Http([_recordedGrant]),
        connector: connector.call,
        policy: _quiet,
        now: () => _now,
        random: _Replay([page['sid'] as String, page['deviceNo'] as String]),
      );
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      final outgoing = [for (final line in _s07.socket.where((line) => !line.incoming)) line.bytes!];
      expect(channel.sent.single, outgoing.first, reason: 'the recorded login');
      for (final line in _s07.socket) {
        if (line.incoming) {
          await channel.receive(line.bytes!);
        } else if (line.bytes![3] == 0) {
          connection.heartbeat();
        }
      }
      expect(channel.sent, outgoing, reason: 'the login, then the heartbeats');
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.first, const DanmakuReady());
      final messages = _messages(events);
      expect(messages.where((m) => m.type == LiveMessageType.chat), hasLength(37));
      expect(messages.where((m) => m.type == LiveMessageType.online), hasLength(10));
      final decoded = [
        for (final line in _s07.socket.where((line) => line.incoming))
          ...KugouLiveDanmakuProtocol.decode(line.bytes, roomId: _room).messages,
      ];
      expect(
        [
          for (final m in messages)
            (
              m.type,
              m.message,
              m.messageId,
              m.data is LiveAudienceUpdate ? (m.data! as LiveAudienceUpdate).value : null,
            ),
        ],
        [
          for (final m in decoded)
            (
              m.type,
              m.message,
              m.messageId,
              m.data is LiveAudienceUpdate ? (m.data! as LiveAudienceUpdate).value : null,
            ),
        ],
      );
      await connection.close();
    });

    test('a dropped socket logs in again (2201, the last session) with the same token; ready again', () async {
      final connector = _Connector();
      final http = _Http([_granted('first')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.join(session: 'sess-1');
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      expect(second.logins, [(2201, 'first', 'sess-1')]);
      expect(http.requests, hasLength(1));
      await second.join(session: 'sess-2');
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await second.incoming.close();
      await _until(() => connector.channels.length == 3);
      expect(connector.channels.last.logins, [(2201, 'first', 'sess-2')]);
      expect(connector.channels.first.logins, [(201, 'first', '')]);
      await connection.close();
    });

    test('a token older than its age is replaced before the next socket', () async {
      var now = _now;
      final connector = _Connector();
      final http = _Http([_granted('first', age: 60000), _granted('second')]);
      final connection = _connection(connector, http, now: () => now);
      await connection.connect(_args);
      await connector.channels.first.join();
      now = now.add(const Duration(seconds: 59));
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.last.logins.single.$2, 'first');
      await connector.channels.last.join();
      now = now.add(const Duration(seconds: 1));
      await connector.channels.last.incoming.close();
      await _until(() => connector.channels.length == 3);
      expect(connector.channels.last.logins.single.$2, 'second');
      expect(http.requests, hasLength(2));
      expect(
        http.requests.last.url.queryParameters['clienttime'],
        '${now.millisecondsSinceEpoch}',
        reason: 'signed at the time asked',
      );
      // A clock that went back is not trusted either.
      now = _now.subtract(const Duration(hours: 1));
      await connector.channels.last.join();
      await connector.channels.last.incoming.close();
      await _until(() => connector.channels.length == 4);
      expect(http.requests, hasLength(3));
      await connection.close();
    });

    test('a refused token (622) asks the scheduler again; the fourth refusal in a row ends the connection', () async {
      final connector = _Connector();
      final http = _Http([for (var n = 1; n <= 8; n++) _granted('token$n')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      // The recorded refusal, three times; then a join: the count starts over.
      final refused = _s08.socket.where((line) => line.incoming).map((line) => line.bytes!).toList();
      for (var n = 1; n <= 3; n++) {
        for (final frame in refused) {
          await connector.channels.last.receive(frame);
        }
        await _until(() => connector.channels.length == n + 1);
      }
      expect([for (final c in connector.channels) c.logins.single.$2], ['token1', 'token2', 'token3', 'token4']);
      await connector.channels.last.join();
      expect(connection.isConnected, isTrue);
      // Other refusals keep the token.
      for (var n = 5; n <= 7; n++) {
        await connector.channels.last.receive(_status(type: 1, status: 0, errorNo: 630));
        await _until(() => connector.channels.length == n);
      }
      expect(
        [for (final c in connector.channels.skip(4)) c.logins.single],
        [(2201, 'token4', 'a1b2c3'), (2201, 'token4', 'a1b2c3'), (2201, 'token4', 'a1b2c3')],
      );
      await connector.channels.last.receive(_status(type: 1, status: 0, errorNo: 630, message: 'no'));
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty && connector.channels.last.closed);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: 901 errorno 630 no'),
      );
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(http.requests, hasLength(4));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
    });

    test('a socket that closes before it joins, or does not join in time, asks the scheduler again', () async {
      final connector = _Connector();
      final http = _Http([_granted('first'), _granted('second'), _granted('third')]);
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 5),
          joinTimeout: Duration(seconds: 1),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      // The server closes at once (as it does with a token it does not know).
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.last.logins.single.$2, 'second');
      // No answer in time.
      await _until(() => connector.channels.length == 3);
      expect(connector.channels.last.logins.single, (201, 'third', ''));
      await connector.channels.last.join();
      expect(events.last, const DanmakuReady());
      expect(http.requests, hasLength(3));
      await connection.close();
    });

    test('a failed handshake keeps the token; a failing scheduler fails the handshake, then works', () async {
      final connector = _Connector(failures: 1);
      final http = _Http([_granted('first')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connector.channels.isNotEmpty);
      expect(connector.endpoints, [
        Uri.parse('wss://chatwss146107.kugou.com/acksocket'),
        Uri.parse('wss://chatwss140058.kugou.com/acksocket'),
      ]);
      expect(http.requests, hasLength(1));
      expect(connector.channels.single.logins.single.$2, 'first');
      await connector.channels.single.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();

      final later = _Connector();
      final flaky = _Http([
        _granted('first'),
        const TransportFailure(SiteIds.kugouLive, TransportReason.timeout),
        _answer('<html>', status: 502),
        _granted('fourth'),
      ]);
      final reconnecting = _connection(later, flaky);
      await reconnecting.connect(_args);
      await later.channels.single.incoming.close();
      await _until(() => later.channels.length == 2);
      expect(flaky.requests, hasLength(4));
      expect(later.channels.last.logins.single.$2, 'fourth');
      expect(later.endpoints, hasLength(2), reason: 'the two handshakes that failed on the scheduler never connected');
      await reconnecting.close();
    });

    test('the scheduler at the start: three tries, then connectionFailed; a refusal ends at once', () async {
      final connector = _Connector();
      final http = _Http([
        const TransportFailure(SiteIds.kugouLive, TransportReason.timeout),
        _answer('{}', status: 500),
        _granted('third'),
      ]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      expect(http.requests, hasLength(3));
      expect(connector.channels.single.logins.single.$2, 'third');
      await connection.close();

      final failing = _Http([const TransportFailure(SiteIds.kugouLive, TransportReason.connect)]);
      final down = _connection(_Connector(), failing);
      final ended = _record(down);
      await down.connect(_args);
      expect(failing.requests, hasLength(3));
      expect(
        ended.single,
        isA<DanmakuClosed>()
            .having((e) => e.reason, 'reason', DanmakuCloseReason.connectionFailed)
            .having((e) => e.detail, 'detail', startsWith('dispatch: ')),
      );
      expect(down.status, DanmakuStatus.closed);

      final refused = _Http([_refusedAnswer(code: 1100007, msg: 'danger')]);
      final blocked = _connection(_Connector(), refused);
      final seen = _record(blocked);
      await blocked.connect(_args);
      expect(refused.requests, hasLength(1));
      expect(seen, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'dispatch: code 1100007 danger')]);
      expect(events, isEmpty);
    });

    test("the page's waits between the scheduler tries of a start", () async {
      final http = _Http([const TransportFailure(SiteIds.kugouLive, TransportReason.timeout), _granted('t')]);
      final connection = _connection(_Connector(), http, retryDelays: const [Duration(milliseconds: 120)]);
      final watch = Stopwatch()..start();
      await connection.connect(_args);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(110));
      expect(http.requests, hasLength(2));
      await connection.close();
    });

    test('the scheduler refusing at a reconnect ends the connection', () async {
      final connector = _Connector();
      final http = _Http([_granted('first'), _refusedAnswer()]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.incoming.close();
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'dispatch: code 1100014 sign verify fail'),
      );
      expect(connector.channels, hasLength(1));
      expect(connection.status, DanmakuStatus.closed);
    });

    test('hosts: the next one on failure; a host the scheduler no longer lists gives way to its first', () async {
      final connector = _Connector();
      final http = _Http([
        _granted('first', hosts: ['a.kugou.com/acksocket', 'b.kugou.com/acksocket']),
        _granted('second', hosts: ['c.kugou.com/acksocket']),
      ]);
      final connection = _connection(connector, http);
      await connection.connect(_args);
      expect(connector.endpoints.single, Uri.parse('wss://a.kugou.com/acksocket'));
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.endpoints.last, Uri.parse('wss://c.kugou.com/acksocket'));
      expect(connector.channels.last.logins.single.$2, 'second');
      await connection.close();
    });

    test("unusable arguments end at once; the wrong type is the caller's error", () async {
      final connector = _Connector();
      final http = _Http([_granted('t')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const KugouLiveDanmakuArgs(roomId: 'fanxing'));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Not a Kugou Live room')]);
      expect(http.requests, isEmpty);
      expect(connector.endpoints, isEmpty);
      expect(() => connection.connect('51049168'), throwsArgumentError);
    });

    test(
      'after close nothing is reported; a pending scheduler request is cancelled; connect replaces the room',
      () async {
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
        expect(events, isEmpty);
        expect(connector.endpoints, isEmpty);

        final second = _Http([_granted('first'), _granted('other')]);
        final replaced = _connection(connector, second);
        final seen = _record(replaced);
        await replaced.connect(_args);
        final first = connector.channels.single;
        await first.join();
        await replaced.connect(const KugouLiveDanmakuArgs(roomId: '1073619'));
        expect(first.closed, isTrue);
        expect(second.rooms, [_room, '1073619']);
        await first.receive(_chat());
        expect(connector.channels.last.logins.single, (201, 'other', ''));
        final login = ProtoMessage.decode(
          ProtoMessage.decode(Uint8List.sublistView(connector.channels.last.sent.single as Uint8List, 18)).bytes(7)!,
        );
        expect(login.integer(2), 1073619);
        await replaced.close();
        await connector.channels.last.receive(_status(type: 1, status: 1));
        await connector.channels.last.receive(_chat(room: 1073619));
        expect(seen, [const DanmakuReady()]);
      },
    );

    test('a real local server: the handshake headers, the login, the status frames, chat and heartbeat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final handshake = <String, String>{};
      final received = <List<int>>[];
      final status = _s07.socket.where((line) => line.incoming && _s07.expectedAt(line.line)['status'] != null);
      final chats = _s07.socket.where((line) => line.incoming && _s07.expectedAt(line.line)['chat'] != null);
      server.listen((request) async {
        handshake['path'] = request.uri.path;
        handshake['origin'] = request.headers.value('origin') ?? '';
        handshake['user-agent'] = request.headers.value('user-agent') ?? '';
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          final bytes = frame as List<int>;
          received.add(bytes);
          if (bytes[3] == 0) {
            socket.add([100, 0, 3, 0]);
          } else {
            for (final line in [...status, chats.first]) {
              socket.add(line.bytes);
            }
          }
        });
      });
      final connection = KugouLiveDanmakuConnection(
        http: _Http([_recordedGrant]),
        now: () => _now,
        random: Random(7),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, Uri.parse('wss://chatwss146107.kugou.com/acksocket'));
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
      await _until(() => _messages(events).isNotEmpty);
      connection.heartbeat();
      await _until(() => received.length == 2);
      expect(handshake['path'], '/acksocket');
      expect(handshake['origin'], 'https://fanxing.kugou.com');
      expect(handshake['user-agent'], endsWith(KugouLiveApi.userAgent));
      final (sid, device) = _ids();
      expect(received, [
        KugouLiveDanmakuProtocol.login(
          roomId: _room,
          token: KugouLiveDanmakuProtocol.grant(_recordedGrant).token,
          sid: sid,
          deviceNo: device,
        ),
        [100, 0, 1, 0],
      ]);
      expect(events.first, const DanmakuReady());
      expect(_messages(events).single.message, '第1天来了，欢迎~，『观众002』来了，欢迎您哦！[/抱抱]');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });
  });
}

/// The JSON of an audience message.
Uint8List _audienceJson() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'cmd': 301005,
      'content': {
        'data': {'count': 12, 'visited': 34},
        'actionId': 'roomAuNumber',
      },
      'roomid': 51049168,
    }),
  ),
);

/// [bytes] as a snappy block of literals only (60 bytes a literal).
Uint8List _snappyLiteral(List<int> bytes) {
  final out = BytesBuilder();
  var length = bytes.length;
  while (length >= 0x80) {
    out.addByte((length & 0x7F) | 0x80);
    length >>= 7;
  }
  out.addByte(length);
  for (var start = 0; start < bytes.length; start += 60) {
    final end = min(start + 60, bytes.length);
    out
      ..addByte((end - start - 1) << 2)
      ..add(bytes.sublist(start, end));
  }
  return out.toBytes();
}

/// A `Random` whose uuids are the given ones (the recorded session and
/// device).
final class _Replay implements Random {
  new(List<String> ids) : _digits = [for (final id in ids) ..._digitsOf(id)];

  final List<int> _digits;
  var _next = 0;

  static List<int> _digitsOf(String uuid) => [
    for (final (index, char) in uuid.split('').indexed)
      if (char != '-' && index != 14)
        // 'y' gets (value & 3) | 8, so the value that gives it back.
        int.parse(char, radix: 16) - (index == 19 ? 8 : 0),
  ];

  @override
  int nextInt(int max) => _digits[_next++];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
