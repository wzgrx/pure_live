import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _fixtures = '../../fixtures/pandalive';
const _root = '$_fixtures/danmaku/S07-live';

/// The recording (S07-live): its `live/play` answer, then the socket's text
/// frames, with their line numbers and directions.
final List<({int line, bool incoming, String? url, String text})> _recording = [
  for (final (index, line) in File('$_root/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 'text': final String text} && final Map<String, Object?> frame)
      (line: index + 1, incoming: dir == 'in', url: frame['url'] as String?, text: text),
];

final Map<String, Object?> _meta = jsonDecode(File('$_root/meta.json').readAsStringSync()) as Map<String, Object?>;

/// The archived v4's output for S07-live (danmaku/v4_expected.dart).
final Map<String, Object?> _v4 =
    (jsonDecode(File('$_root/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

/// When the recording was made: "now" of every token expiry read here.
final DateTime _recordedAt = DateTime.parse(_meta['capturedAt']! as String);

/// The recorded broadcaster and channel.
const String _user = 'daisy00';
const String _channel = '24133575';

/// The recorded (scrubbed) token.
final String _recordedToken = (jsonDecode(_recording.first.text) as Map<String, Object?>)['token']! as String;

/// A synthetic HS256-shaped token lapsing at [exp] (seconds).
String _jwt({required int? exp, String sub = 'guest0000001'}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'typ': 'JWT', 'alg': 'HS256'})}.${part({'sub': sub, 'exp': ?exp})}.c2lnbmF0dXJlLW5vdC1jaGVja2Vk';
}

/// A token lapsing [minutes] after the recording.
String _tokenFor(int minutes, {String sub = 'guest0000001'}) => _jwt(
  exp: _recordedAt.add(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 1000,
  sub: sub,
);

final PandaLiveDanmakuArgs _args = PandaLiveDanmakuArgs(userId: _user, channel: _channel, token: _tokenFor(30));

/// No heartbeat, watchdog or join timer and a short backoff: only what the
/// test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

/// An accepted `live/play` answer carrying [token] for [channel].
LiveResponse _granted(String token, {Object? channel = _channel, Object? isLive = true, int status = 200}) =>
    LiveResponse(
      status: status,
      bytes: utf8.encode(
        jsonEncode({
          'result': true,
          'message': '시청이 시작되었습니다.',
          'channel': ?channel,
          'token': token,
          'media': {'userId': _user, 'userIdx': 24133575, 'isLive': ?isLive},
        }),
      ),
      url: PandaLiveDanmakuProtocol.playUrl,
    );

/// A refused `live/play` answer (HTTP 400) with `errorData.code` [code].
LiveResponse _refused(String? code) => LiveResponse(
  status: 400,
  bytes: utf8.encode(
    jsonEncode({
      'result': false,
      'message': '방송이 종료되었습니다.',
      'errorData': ?(code == null ? null : {'code': code}),
    }),
  ),
  url: PandaLiveDanmakuProtocol.playUrl,
);

LiveResponse _body(String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: PandaLiveDanmakuProtocol.playUrl);

/// Answers `live/play` from a script: each entry is a response, an error to
/// throw, or a completer to wait for; the last entry repeats.
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
          (_) => throw const TransportFailure(SiteIds.pandaLive, TransportReason.cancelled),
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

  /// The server's answers to connect (a token of [ttl] seconds) and
  /// subscribe.
  Future<void> join({int ttl = 1798}) async {
    await receive(_connectReply(ttl: ttl));
    await receive(_reply(2));
  }

  /// The connect commands sent, as their tokens.
  List<String> get tokens => [
    for (final frame in sent)
      if (jsonDecode(frame as String) case {'id': 1, 'params': {'token': final String token}}) token,
  ];
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

String _reply(int id, [Map<String, Object?>? result]) => jsonEncode({'id': id, 'result': ?result});

String _connectReply({int ttl = 1798, bool expires = true}) => _reply(1, {
  'client': '00000000-0000-4000-8000-000000000000',
  'version': '3.1.1',
  'expires': expires,
  'ttl': ttl,
  'subs': {'_person:#v_00000000-0': <String, Object?>{}},
});

String _errorReply(int id, {int code = 109, String message = 'token expired'}) => jsonEncode({
  'id': id,
  'error': {'code': code, 'message': message},
});

/// A chat message in the shape the server sent on 2026-09-29 (synthetic
/// values).
Map<String, Object?> _message({
  Object? type = 'chatter',
  Object? message = '안녕하세요',
  Object? emoticon,
  Object? nk = '观众1',
  Object? id = 'viewer01',
  Object? createdAt = 1790536489,
}) => {
  'type': ?type,
  'message': ?message,
  'emoticon': emoticon,
  'translate': null,
  'filtered': false,
  'autoTranslate': false,
  'created_at': ?createdAt,
  'id': ?id,
  'nk': ?nk,
  'adv': false,
  'lang': ['ko'],
  'lcl': 'KR',
  'sex': 'M',
  'dt': 'PC',
  'pf': 'web',
  'idx': 12345678,
};

/// A publication of [message] on [channel] at [offset].
String _pub(Object? message, {String channel = _channel, Object? offset = 2095}) => jsonEncode({
  'result': {
    'channel': channel,
    'data': {'data': message, 'offset': ?offset},
  },
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

PandaLiveDanmakuConnection _connection(
  _Connector connector,
  _Http http, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) => PandaLiveDanmakuConnection(
  http: http,
  connector: connector.call,
  policy: policy,
  proxy: proxy,
  now: () => _recordedAt,
);

/// A message as the v4 projection shows it; v4's id is `pandalive:` and
/// this implementation's id.
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'id': 'pandalive:${message.messageId}',
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
};

void main() {
  group('protocol', () {
    test('the socket, headers, commands and timing', () {
      expect(PandaLiveDanmakuProtocol.endpoint, Uri.parse('wss://chat-ws.neolive.kr/connection/websocket'));
      expect(PandaLiveDanmakuProtocol.endpoint, PandaLiveApi.chatServer);
      expect(PandaLiveDanmakuProtocol.playUrl, Uri.parse('https://api.pandalive.co.kr/v1/live/play'));
      expect(PandaLiveDanmakuProtocol.socketHeaders, {
        'origin': 'https://www.pandalive.co.kr',
        'user-agent': PandaLiveApi.userAgent,
      });
      expect(PandaLiveDanmakuProtocol.connect('a.b.c'), '{"params":{"token":"a.b.c","name":"js"},"id":1}');
      expect(PandaLiveDanmakuProtocol.subscribe(_channel), '{"method":1,"params":{"channel":"24133575"},"id":2}');
      expect(PandaLiveDanmakuProtocol.ping(3), '{"method":7,"id":3}');
      expect(PandaLiveDanmakuProtocol.heartbeatInterval, const Duration(seconds: 25));
      expect(PandaLiveDanmakuProtocol.joinTimeout, const Duration(seconds: 8));
      expect(PandaLiveDanmakuProtocol.renewalLead, const Duration(minutes: 1));
      expect(PandaLiveDanmakuProtocol.maxRefusals, 3);
      expect(PandaLiveDanmakuProtocol.chatTypes, {'bj', 'chatter', 'manager', 'support'});
      expect(PandaLiveDanmakuProtocol.renewalDelay(const Duration(seconds: 1798)), const Duration(seconds: 1738));
      expect(PandaLiveDanmakuProtocol.renewalDelay(const Duration(seconds: 121)), const Duration(seconds: 61));
      expect(PandaLiveDanmakuProtocol.renewalDelay(const Duration(seconds: 120)), const Duration(seconds: 60));
      expect(PandaLiveDanmakuProtocol.renewalDelay(const Duration(seconds: 1)), const Duration(milliseconds: 500));
    });

    test('the live/play request is the one room entry sends', () async {
      final http = ReplayHttp.fixtures(
        _fixtures,
        const ['S04-member-live', 'S05-play-live', 'S06-master'],
        ignoredQuery: const {'token'},
      );
      final master = DateTime.parse(
        (jsonDecode(File('$_fixtures/S06-master/meta.json').readAsStringSync()) as Map)['capturedAt'] as String,
      );
      final room = await PandaLiveSite(http, now: () => master).getRoomDetail(roomId: _user);
      final entry = http.requests.singleWhere((request) => request.url.path == '/v1/live/play');
      final cancel = CancelToken();
      final request = PandaLiveDanmakuProtocol.playRequest(_user, timeout: const Duration(seconds: 7), cancel: cancel);
      expect(request.site, entry.site);
      expect(request.method, entry.method);
      expect(request.url, entry.url);
      expect(request.headers, entry.headers);
      expect(request.headers['content-type'], 'application/x-www-form-urlencoded');
      expect(request.headers['referer'], 'https://www.pandalive.co.kr/play/daisy00');
      expect(utf8.decode(request.body!), utf8.decode(entry.body!));
      expect(utf8.decode(request.body!), 'action=watch&userId=daisy00&password=&shareLinkType=');
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 7));
      expect(request.cancel, same(cancel));
      // Room entry's chat arguments are this broadcast's channel and token.
      final args = room.danmakuData! as PandaLiveDanmakuArgs;
      final answer = jsonDecode(File('$_fixtures/S05-play-live/body.json').readAsStringSync()) as Map;
      expect((args.userId, args.channel, args.token), (_user, _channel, answer['token']));
      expect(PandaLiveDanmakuProtocol.checked(args), isNotNull);
    });

    test('grants: the channel and token of live/play; refusals; unreadable answers', () {
      final live = File('$_fixtures/S05-play-live/body.json').readAsStringSync();
      final full = PandaLiveDanmakuProtocol.grant(_body(live));
      expect(full.channel, _channel);
      expect(full.token, (jsonDecode(live) as Map)['token']);
      final recorded = PandaLiveDanmakuProtocol.grant(_body(_recording.first.text));
      expect((recorded.channel, recorded.token), (_channel, _recordedToken));
      expect(PandaLiveDanmakuProtocol.grant(_granted('t.o.k', channel: 24133575)).channel, _channel);
      expect(PandaLiveDanmakuProtocol.grant(_granted('t.o.k', isLive: null)).token, 't.o.k');

      Matcher refusal(String code) => throwsA(isA<PandaLiveChatRefusal>().having((e) => e.code, 'code', code));
      for (final (sample, code) in [('S05-play-castend', 'castEnd'), ('S05-play-needlogin', 'needAdult')]) {
        final body = File('$_fixtures/$sample/body.json').readAsStringSync();
        expect(() => PandaLiveDanmakuProtocol.grant(_body(body, status: 400)), refusal(code), reason: sample);
      }
      expect(() => PandaLiveDanmakuProtocol.grant(_refused('needPassword')), refusal('needPassword'));
      expect(() => PandaLiveDanmakuProtocol.grant(_refused(null)), refusal(''));
      expect(() => PandaLiveDanmakuProtocol.grant(_granted('t.o.k', isLive: false)), refusal('not live'));
      expect(const PandaLiveChatRefusal('castEnd').toString(), 'live/play: castEnd');
      expect(const PandaLiveChatRefusal('').toString(), 'live/play: refused');

      expect(() => PandaLiveDanmakuProtocol.grant(_granted('t.o.k', status: 403)), throwsA(isA<RiskControl>()));
      expect(() => PandaLiveDanmakuProtocol.grant(_granted('t.o.k', status: 502)), throwsA(isA<NetworkFailure>()));
      expect(() => PandaLiveDanmakuProtocol.grant(_body('<html>')), throwsA(isA<ApiChanged>()));
      for (final response in [
        _granted(''),
        _granted('a b'),
        _granted('t\u0000k'),
        _granted('ㅋ.ㅋ.ㅋ'),
        _granted('t' * 4097),
        _granted('t.o.k', channel: null),
        _granted('t.o.k', channel: 'abc'),
        _granted('t.o.k', channel: '1' * 20),
        _body('{"result":true,"channel":"24133575","token":42}'),
      ]) {
        expect(() => PandaLiveDanmakuProtocol.grant(response), throwsFormatException, reason: response.text);
      }
      expect(PandaLiveDanmakuProtocol.grant(_granted('t' * 4096)).token, hasLength(4096));
    });

    test('token expiry: the JWT exp, else unknown', () {
      final exp = _recordedAt.millisecondsSinceEpoch ~/ 1000 + 1800;
      expect(
        PandaLiveDanmakuProtocol.tokenExpiry(_jwt(exp: exp)),
        DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      );
      expect(PandaLiveDanmakuProtocol.tokenExpiry(_jwt(exp: 1))!.millisecondsSinceEpoch, 1000);
      expect(PandaLiveDanmakuProtocol.tokenExpiry(_jwt(exp: null)), isNull);
      for (final exp in [0, -1, 8640000000001]) {
        expect(PandaLiveDanmakuProtocol.tokenExpiry(_jwt(exp: exp)), isNull, reason: '$exp');
      }
      String withPayload(String payload) => 'aGVhZGVy.${base64Url.encode(utf8.encode(payload))}.c2ln';
      for (final token in [
        _recordedToken,
        'a.b',
        'a.b.c.d',
        '',
        withPayload('{"exp":"1790538000"}'),
        withPayload('[1790538000]'),
        withPayload('not json'),
        'aGVhZGVy.!!!.c2ln',
        'aGVhZGVy.${base64Url.encode([0xFF, 0xFE])}.c2ln',
      ]) {
        expect(PandaLiveDanmakuProtocol.tokenExpiry(token), isNull, reason: token);
      }
    });

    test('arguments: a broadcaster id and a numeric channel; an unusable token is dropped', () {
      final checked = PandaLiveDanmakuProtocol.checked(
        const PandaLiveDanmakuArgs(userId: ' daisy00 ', channel: ' 24133575 ', token: ' a.b.c '),
      )!;
      expect((checked.userId, checked.channel, checked.token), (_user, _channel, 'a.b.c'));
      expect(
        PandaLiveDanmakuProtocol.checked(const PandaLiveDanmakuArgs(userId: '1506087545@ka', channel: '1'))?.userId,
        '1506087545@ka',
      );
      for (final token in [null, '', '   ', 'a b.c', 'a\u0000b', 'ㅋ']) {
        final args = PandaLiveDanmakuProtocol.checked(PandaLiveDanmakuArgs(userId: _user, channel: '1', token: token));
        expect(args?.token, isNull, reason: '$token');
        expect(args?.userId, _user);
      }
      for (final (user, channel) in [
        ('', _channel),
        ('daisy 00', _channel),
        ('../x', _channel),
        ('daisy00@k', _channel),
        (_user, ''),
        (_user, 'abc'),
        (_user, '-1'),
        (_user, '1.5'),
        (_user, '1' * 20),
      ]) {
        expect(
          PandaLiveDanmakuProtocol.checked(PandaLiveDanmakuArgs(userId: user, channel: channel, token: 'a.b.c')),
          isNull,
          reason: '$user $channel',
        );
      }
    });

    test('a chat: text, name, login id, message id and time', () {
      final message = PandaLiveDanmakuProtocol.chat({
        'data': _message(message: '  안녕하세요\n'),
        'offset': 2095,
      }, channel: _channel)!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, '안녕하세요');
      expect(message.userName, '观众1');
      expect(message.userId, 'viewer01');
      expect(message.messageId, '24133575:2095');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790536489000));
      expect(message.color, LiveMessageColor.white);
      expect((message.userLevel, message.fansLevel, message.fansName), ('', '', ''));
      expect(message.isLocal, isFalse);
      expect(message.data, isNull);
    });

    test('chat boundaries: types, text, emoticons, names, ids, offsets and times', () {
      LiveMessage? of(Map<String, Object?> message, {Object? offset = 7}) =>
          PandaLiveDanmakuProtocol.chat({'data': message, 'offset': ?offset}, channel: _channel);
      for (final type in ['bj', 'chatter', 'manager', 'support']) {
        expect(of(_message(type: type))!.message, '안녕하세요', reason: type);
      }
      for (final type in [
        'MediaUpdate',
        'Recommend',
        'SponCoin',
        'ItemCoin',
        'Info',
        'FanUp',
        'FanIn',
        'KingFanIn',
        'ManagerIn',
        'RoomEnd',
        'CastPause',
        'ModifyRoom',
        'Chatter',
        '',
        null,
        1,
      ]) {
        expect(of(_message(type: type)), isNull, reason: '$type');
      }
      for (final text in [
        '',
        '   ',
        null,
        1.5,
        true,
        const ['x'],
        const {'a': 1},
      ]) {
        expect(of(_message(message: text)), isNull, reason: '$text');
      }
      expect(of(_message(message: 7))!.message, '7');
      // An emoticon alone shows its name, as the archived v4 did.
      const block = {
        'idx': 56,
        'type': 'default',
        'style': 'block',
        'group': 'pandaemo',
        'name': 'pandaS하트다발png',
        'img': 'https://cdn.pandalive.co.kr/upload/ChatEmoticon/2025/12/23/0.png',
      };
      expect(
        of(_message(message: '', emoticon: const {'block': block, 'inline': <Object?>[]}))!.message,
        '[pandaS하트다발png]',
      );
      expect(
        of(
          _message(
            message: null,
            emoticon: const {
              'inline': <Object?>[],
              'block': {'name': '  하트 '},
            },
          ),
        )!.message,
        '[하트]',
      );
      expect(of(_message(message: 'text', emoticon: const {'block': block}))!.message, 'text');
      for (final emoticon in [
        null,
        'x',
        const <String, Object?>{},
        const {'block': null},
        const {
          'block': {'name': ''},
        },
        const {
          'block': {'name': 3.5},
        },
        const {
          'inline': ['a'],
        },
      ]) {
        expect(
          of(_message(message: '', emoticon: emoticon)),
          isNull,
          reason: '$emoticon',
        );
      }
      final bare = of(_message(nk: null, id: null))!;
      expect((bare.userName, bare.userId), ('', ''));
      expect(of(_message(nk: '  이름 '))!.userName, '이름');
      expect(of(_message(nk: const ['x']))!.userName, '');
      expect(of(_message(id: 42))!.userId, '42');
      expect(of(_message(id: 1.5))!.userId, '');
      expect(of(_message(), offset: 0)!.messageId, '24133575:0');
      for (final offset in [null, -1, 1.5, '7']) {
        expect(of(_message(), offset: offset)!.messageId, isEmpty, reason: '$offset');
      }
      for (final time in [0, -1, 8640000000001, 1.79e9, '1790536489', null]) {
        expect(of(_message(createdAt: time))!.sentAt, isNull, reason: '$time');
      }
      expect(of(_message(createdAt: 1))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(of(_message(createdAt: 8640000000000))!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
      expect(PandaLiveDanmakuProtocol.chat(_message(), channel: _channel), isNull);
      expect(PandaLiveDanmakuProtocol.chat({'data': 'text'}, channel: _channel), isNull);
      expect(PandaLiveDanmakuProtocol.chat(null, channel: _channel), isNull);
    });

    test('frames: replies join, refuse or tell the token life; publications of the channel are chat', () {
      PandaLiveDanmakuFrame of(Object? data) => PandaLiveDanmakuProtocol.decode(data, channel: _channel);
      List<String> texts(Object? data) => [for (final message in of(data).messages) message.message];

      final connected = of(_connectReply());
      expect((connected.joined, connected.refusal, connected.expiresIn), (false, null, const Duration(seconds: 1798)));
      expect(of(_connectReply(expires: false)).expiresIn, isNull);
      expect(of(_connectReply(ttl: 0)).expiresIn, isNull);
      expect(of(_reply(1)).expiresIn, isNull);
      final joined = of(_reply(2, {}));
      expect((joined.joined, joined.refusal, joined.expiresIn), (true, null, null));
      expect(joined.messages, isEmpty);
      expect(of(_reply(2)).joined, isTrue);
      expect(of(_errorReply(1)).refusal, 'connect: 109 token expired');
      expect(of(_errorReply(2, code: 103, message: 'permission denied')).refusal, 'subscribe: 103 permission denied');
      expect(of(_errorReply(2)).joined, isFalse);
      expect(of(jsonEncode({'id': 1, 'error': 'bad'})).refusal, 'connect: bad');
      for (final reply in [
        _reply(3),
        _reply(7, {}),
        _errorReply(5),
        jsonEncode({'id': '2', 'result': <String, Object?>{}}),
      ]) {
        final frame = of(reply);
        expect((frame.joined, frame.refusal, frame.expiresIn), (false, null, null), reason: reply);
        expect(frame.messages, isEmpty);
      }

      expect(texts(_pub(_message(message: 'one'))), ['one']);
      expect(texts(utf8.encode(_pub(_message(message: '둘')))), ['둘']);
      expect(texts([0xFF, ...utf8.encode(_pub(_message()))]), isEmpty);
      expect(
        texts(
          jsonEncode({
            'result': {
              'channel': 24133575,
              'data': {'data': _message(message: 'n')},
            },
          }),
        ),
        ['n'],
      );
      // Several lines in one frame, in order; blank and broken lines are skipped.
      final batch = of(
        [
          _connectReply(ttl: 60),
          _reply(2),
          '',
          'not json',
          _pub(_message(message: 'a')),
          '[1]',
          _pub(_message(message: 'b'), offset: 2096),
        ].join('\n'),
      );
      expect(batch.joined, isTrue);
      expect(batch.expiresIn, const Duration(minutes: 1));
      expect(
        [for (final m in batch.messages) (m.message, m.messageId)],
        [('a', '24133575:2095'), ('b', '24133575:2096')],
      );
      expect(of('${_errorReply(1)}\n${_errorReply(2)}').refusal, 'connect: 109 token expired');
      for (final frame in [
        '',
        'null',
        '"text"',
        '[${_pub(_message())}]',
        _pub(_message(), channel: '24133576'),
        _pub(_message(), channel: ''),
        jsonEncode({
          'result': {
            'type': 1,
            'channel': _channel,
            'data': {
              'info': {'user': 'x'},
            },
          },
        }),
        jsonEncode({
          'result': {'type': 3, 'channel': _channel},
        }),
        jsonEncode({'result': 'x'}),
        jsonEncode({
          'result': {'channel': _channel, 'data': 'x'},
        }),
        _pub({'type': 'MediaUpdate', 'created_at': 1790536599}),
        _pub({'type': 'Recommend', 'created_at': 1790536599}),
        // Hearts are gifts (D07.7, the hearts group); special hearts are not read.
        _pub({'type': 'ItemCoin', 'message': '{"coin":10,"nick":"a","id":"b"}'}),
      ]) {
        expect(texts(frame), isEmpty, reason: frame);
      }
      expect(texts(42), isEmpty);
      expect(texts(null), isEmpty);
    });
  });

  group('recording (S07-live)', () {
    test('the socket, headers, form, commands and ping period are those of the archived v4 and the recording', () {
      final keys = (_meta['danmakuKeys']! as Map).cast<String, String>();
      expect(keys, {'userId': _user, 'channel': _channel});
      final handshake = (_meta['handshakes']! as List).single as Map<String, Object?>;
      expect(PandaLiveDanmakuProtocol.endpoint.toString(), _v4['endpoint']);
      expect(handshake['url'], _v4['endpoint']);
      expect(PandaLiveDanmakuProtocol.socketHeaders, _v4['headers']);
      expect(handshake['headers'], _v4['headers']);
      expect(PandaLiveDanmakuProtocol.heartbeatInterval.inSeconds, _v4['heartbeatSeconds']);
      expect(PandaLiveDanmakuProtocol.playUrl.toString(), _v4['play']);
      expect(PandaLiveApi.playForm(_user), _v4['playForm']);
      expect(_recording.first.url, _v4['play']);
      final grant = PandaLiveDanmakuProtocol.grant(_body(_recording.first.text));
      expect({'channel': grant.channel, 'token': grant.token}, _v4['session']);
      final sent = [
        for (final frame in _recording)
          if (!frame.incoming) frame.text,
      ];
      expect(sent, [
        PandaLiveDanmakuProtocol.connect(grant.token),
        PandaLiveDanmakuProtocol.subscribe(grant.channel),
        for (var id = 3; id <= 8; id++) PandaLiveDanmakuProtocol.ping(id),
      ]);
      expect(sent, [_v4['connect'], _v4['subscribe'], ...(_v4['pings']! as List)]);
    });

    test('every received frame decodes as the archived v4 did (its id carries a site prefix)', () {
      final frames = (_v4['frames']! as List).cast<Map<String, Object?>>();
      final received = [
        for (final frame in _recording)
          if (frame.incoming && frame.url == null) frame,
      ];
      expect(received, hasLength(frames.length));
      var chats = 0;
      for (final (index, frame) in received.indexed) {
        final expected = frames[index];
        expect(frame.line, expected['line']);
        final decoded = PandaLiveDanmakuProtocol.decode(frame.text, channel: _channel);
        expect(decoded.joined, expected['joined'], reason: 'line ${frame.line}');
        expect(decoded.refusal != null, expected['rejected'], reason: 'line ${frame.line}');
        expect(
          [for (final message in decoded.messages) _project(message)],
          expected['events'],
          reason: 'line ${frame.line}',
        );
        chats += decoded.messages.length;
      }
      // The connect reply of line 4 says when the token lapses.
      expect(
        PandaLiveDanmakuProtocol.decode(received.first.text, channel: _channel).expiresIn,
        const Duration(seconds: 1798),
      );
      expect((received.length, chats), (27, 18));
    });

    test('the connection replays the recording: connect and subscribe, ready, 18 chats, pings 3 to 8', () async {
      final connector = _Connector();
      final http = _Http([_granted(_tokenFor(30))]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      final keys = (_meta['danmakuKeys']! as Map).cast<String, String>();
      await connection.connect(
        PandaLiveDanmakuArgs(userId: keys['userId']!, channel: keys['channel']!, token: _recordedToken),
      );
      expect(connector.endpoints, [Uri.parse(_v4['endpoint']! as String)]);
      expect(connector.headers.single, _v4['headers']);
      final channel = connector.channels.single;
      for (final frame in _recording.skip(1)) {
        if (frame.incoming) {
          await channel.receive(frame.text);
        } else if (frame.text.contains('"method":7')) {
          connection.heartbeat();
        }
      }
      expect(channel.sent, [
        for (final frame in _recording)
          if (!frame.incoming) frame.text,
      ]);
      // The recorded token says nothing of its expiry: it was used, no new one asked.
      expect(http.requests, isEmpty);
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      final expected = [
        for (final frame in (_v4['frames']! as List).cast<Map<String, Object?>>())
          ...(frame['events']! as List).cast<Map<String, Object?>>(),
      ];
      expect([for (final message in _messages(events)) _project(message)], expected);
      await connection.close();
    });
  });

  group('hearts (D07.7, S08-hearts)', () {
    final lines = [
      for (final line in File('$_fixtures/danmaku/S08-hearts/frames.jsonl').readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['text']! as String,
    ];
    String channelOf(String line) => ((jsonDecode(line) as Map)['result'] as Map)['channel'] as String;

    test('S08: every recorded SponCoin as hearts, the receiving member, the words as chat', () {
      final messages = [
        for (final line in lines) ...PandaLiveDanmakuProtocol.decode(line, channel: channelOf(line)).messages,
      ];
      expect(
        [for (final m in messages) (m.type, m.userName, m.data is LiveGift ? (m.data! as LiveGift).count : m.message)],
        [
          for (final coin in [1063, 1063, 1063, 1050]) (LiveMessageType.gift, '시청자1', coin),
          (LiveMessageType.gift, '시청자2', 4444),
          (LiveMessageType.gift, '시청자2', 4444),
          (LiveMessageType.gift, '시청자3', 1599),
          (LiveMessageType.gift, '시청자3', 1599),
          for (final coin in [999, 1009, 1015, 1062]) (LiveMessageType.gift, '시청자4', coin),
          (LiveMessageType.gift, '시청자5', 1001),
          (LiveMessageType.chat, '시청자5', '갓조개'),
          (LiveMessageType.gift, '시청자6', 10666),
          (LiveMessageType.chat, '시청자6', '노느라 깜빡했네 상처뿐인시그보여줘'),
          (LiveMessageType.gift, '시청자7', 2222),
        ],
      );
      final first = messages.first;
      expect(
        (first.userId, first.messageId, first.message, first.sentAt?.isUtc),
        ('viewer01', '29619030:7954', '하트 ×1063', false),
      );
      expect(
        first.data,
        const LiveGift(
          name: '하트',
          count: 1063,
          kind: LiveGiftKind.tip,
          unitPrice: 1,
          totalValue: 1063,
          unit: LiveGiftUnit.heart,
          receiverName: '진하늘',
        ),
      );
      final words = messages.firstWhere((m) => m.message == '갓조개');
      expect(words.messageId, '27472604:12527:words');
      expect((messages[messages.length - 3].data! as LiveGift).tier, LiveGiftTier.precious, reason: '10666 hearts');
    });

    test('what is not hearts: other types, broken messages, no sender or no hearts', () {
      Map<String, Object?> push(Object? message, {String type = 'SponCoin'}) => {
        'result': {
          'channel': '1',
          'data': {
            'data': {'type': type, 'message': message, 'created_at': 1791530463},
            'offset': 5,
          },
        },
      };
      List<LiveMessage> read(Map<String, Object?> push) =>
          PandaLiveDanmakuProtocol.decode(jsonEncode(push), channel: '1').messages;
      expect(read(push(jsonEncode({'nick': 'a', 'id': 'a', 'coin': 10}), type: 'ItemCoin')), isEmpty);
      expect(read(push('{broken')), isEmpty);
      expect(read(push(jsonEncode({'nick': '', 'id': 'a', 'coin': 10}))), isEmpty);
      expect(read(push(jsonEncode({'nick': 'a', 'id': 'a', 'coin': 0}))), isEmpty);
      expect(read(push(jsonEncode({'nick': 'a', 'id': 'a', 'coin': '10'}))), isEmpty);
      final plain = read(
        push(
          jsonEncode({
            'nick': 'a',
            'id': 'a',
            'coin': 10,
            'heartMessage': {'message': ' '},
          }),
        ),
      );
      expect(
        [for (final m in plain) (m.type, m.messageId, (m.data! as LiveGift).receiverName)],
        [(LiveMessageType.gift, '1:5', '')],
      );
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = PandaLiveDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 25));
      expect(policy.joinTimeout, const Duration(seconds: 8));
      expect(policy.inactivityTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = PandaLiveDanmakuConnection(http: _Http([_granted('a.b.c')]));
      expect(connection.heartbeatInterval, const Duration(seconds: 25));
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.site, SiteIds.pandaLive);
      final registry = DanmakuRegistry({
        SiteIds.pandaLive: () => PandaLiveDanmakuConnection(http: _Http([_granted('a.b.c')])),
      });
      expect(registry.supports('PandaLive'), isTrue);
      expect(registry.connectionFor('pandalive'), isA<PandaLiveDanmakuConnection>());
    });

    test('handshake: the token room entry brought, connect and subscribe; ready on the subscription reply', () async {
      final connector = _Connector();
      final http = _Http([_granted('unused')]);
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        connector,
        http,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.pandaLive: route}),
      );
      final events = _record(connection);
      await connection.connect(_args);
      expect(connector.endpoints, [PandaLiveDanmakuProtocol.endpoint]);
      expect(connector.headers.single, PandaLiveDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      final channel = connector.channels.single;
      expect(channel.sent, [
        PandaLiveDanmakuProtocol.connect(_args.token!),
        PandaLiveDanmakuProtocol.subscribe(_channel),
      ]);
      expect(http.requests, isEmpty);
      await channel.receive(_connectReply());
      expect(events, isEmpty);
      expect(connection.isConnected, isFalse);
      await channel.receive(_reply(2));
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      await channel.receive(_reply(2));
      await channel.receive(_pub(_message(message: 'hi')));
      await channel.receive(_pub(_message(message: 'other channel'), channel: '1'));
      await channel.receive(_pub({'type': 'MediaUpdate', 'created_at': 1790536599}));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect([for (final m in _messages(events)) m.message], ['hi']);
      await connection.close();
    });

    test('no token, or one lapsing within a minute: live/play first, with its channel', () async {
      for (final token in [null, _tokenFor(1), _tokenFor(-5)]) {
        final connector = _Connector();
        final fresh = _tokenFor(30, sub: 'guest0000002');
        final http = _Http([_granted(fresh, channel: '555')]);
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(PandaLiveDanmakuArgs(userId: _user, channel: _channel, token: token));
        final request = http.requests.single;
        final expected = PandaLiveDanmakuProtocol.playRequest(_user);
        expect((request.site, request.method, request.url), (expected.site, expected.method, expected.url));
        expect(request.headers, expected.headers);
        expect(request.body, expected.body);
        expect(request.followRedirects, isFalse);
        expect(request.timeout, PandaLiveDanmakuConnection.defaultPolicy.connectTimeout);
        final channel = connector.channels.single;
        expect(channel.sent, [PandaLiveDanmakuProtocol.connect(fresh), PandaLiveDanmakuProtocol.subscribe('555')]);
        await channel.join();
        await channel.receive(_pub(_message(message: 'old channel')));
        await channel.receive(_pub(_message(message: 'new channel'), channel: '555'));
        expect(events.first, const DanmakuReady());
        expect([for (final m in _messages(events)) (m.message, m.messageId)], [('new channel', '555:2095')]);
        await connection.close();
      }
      // A token lapsing later than a minute is used.
      final connector = _Connector();
      final http = _Http([_granted('unused')]);
      final connection = _connection(connector, http);
      final token = _tokenFor(2);
      await connection.connect(PandaLiveDanmakuArgs(userId: _user, channel: _channel, token: token));
      expect(http.requests, isEmpty);
      expect(connector.channels.single.tokens, [token]);
      await connection.close();
    });

    test('a dropped socket reconnects with a new token from live/play and joins again', () async {
      final connector = _Connector();
      final second = _tokenFor(30, sub: 'guest0000002');
      final http = _Http([_granted(second)]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.join();
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(http.requests, hasLength(1));
      final channel = connector.channels.last;
      expect(channel.tokens, [second]);
      expect(channel.sent.last, PandaLiveDanmakuProtocol.subscribe(_channel));
      await channel.join();
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('a failed handshake keeps its new token for the next one', () async {
      final connector = _Connector(failures: 1);
      final token = _tokenFor(30, sub: 'guest0000002');
      final http = _Http([_granted(token), _granted('never.used.token')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const PandaLiveDanmakuArgs(userId: _user, channel: _channel));
      await _until(() => connector.channels.isNotEmpty);
      expect(connector.endpoints, hasLength(2));
      expect(http.requests, hasLength(1));
      expect(connector.channels.single.tokens, [token]);
      await connector.channels.single.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('live/play refusing the broadcast ends the connection, at the start or at a reconnect', () async {
      final connector = _Connector();
      final http = _Http([_refused('castEnd')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const PandaLiveDanmakuArgs(userId: _user, channel: _channel));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'live/play: castEnd')]);
      expect(connector.endpoints, isEmpty);
      expect(connection.status, DanmakuStatus.closed);

      final later = _Connector();
      final ended = _Http([_granted('not.live.yet', isLive: false)]);
      final reconnecting = _connection(later, ended);
      final seen = _record(reconnecting);
      await reconnecting.connect(_args);
      await later.channels.single.join();
      await later.channels.single.incoming.close();
      await _until(() => seen.whereType<DanmakuClosed>().isNotEmpty);
      expect(seen, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'live/play: not live'),
      ]);
      expect(later.channels, hasLength(1));
      expect(ended.requests, hasLength(1));
      expect(reconnecting.status, DanmakuStatus.closed);
    });

    test('live/play failing counts as a failed handshake: retried, then the reconnects run out', () async {
      final connector = _Connector();
      final token = _tokenFor(30, sub: 'guest0000002');
      final http = _Http([
        const TransportFailure(SiteIds.pandaLive, TransportReason.timeout),
        _body('<html>', status: 502),
        _body('{"result":true}'),
        _granted(token),
      ]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const PandaLiveDanmakuArgs(userId: _user, channel: _channel));
      await _until(() => connector.channels.isNotEmpty);
      expect(http.requests, hasLength(4));
      expect(connector.channels.single.tokens, [token]);
      await connector.channels.single.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();

      final failing = _Http([const TransportFailure(SiteIds.pandaLive, TransportReason.connect)]);
      final exhausted = PandaLiveDanmakuConnection(
        http: failing,
        connector: _Connector().call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 2,
        ),
        now: () => _recordedAt,
      );
      final ended = _record(exhausted);
      await exhausted.connect(const PandaLiveDanmakuArgs(userId: _user, channel: _channel));
      await _until(() => ended.whereType<DanmakuClosed>().isNotEmpty);
      expect(
        ended.last,
        isA<DanmakuClosed>().having((e) => e.reason, 'reason', DanmakuCloseReason.reconnectsExhausted),
      );
      expect(ended.whereType<DanmakuReconnecting>(), hasLength(1));
      expect(failing.requests, hasLength(3));
    });

    test('a refused join reconnects with a new token; the fourth refusal in a row ends the connection', () async {
      final connector = _Connector();
      final http = _Http([for (var n = 1; n <= 6; n++) _granted(_tokenFor(30, sub: 'guest000000$n'))]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      // Three refusals, then a join: the count starts over.
      for (var n = 1; n <= 3; n++) {
        await connector.channels.last.receive(_errorReply(1));
        await _until(() => connector.channels.length == n + 1);
      }
      await connector.channels.last.join();
      expect(connection.isConnected, isTrue);
      for (var n = 5; n <= 7; n++) {
        await connector.channels.last.receive(_errorReply(2, code: 103, message: 'permission denied'));
        await _until(() => connector.channels.length == n);
      }
      await connector.channels.last.receive(_errorReply(1));
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty && connector.channels.last.closed);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: connect: 109 token expired'),
      );
      expect(connector.channels, hasLength(7));
      expect(
        [for (final c in connector.channels) c.tokens.single],
        [_args.token, for (var n = 1; n <= 6; n++) _tokenFor(30, sub: 'guest000000$n')],
      );
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
    });

    test('a lapsed token as the server answers it (109, then closed) is replaced once', () async {
      final connector = _Connector();
      final token = _tokenFor(30, sub: 'guest0000002');
      final http = _Http([_granted(token)]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      // The recorded token says nothing of its expiry, so it is tried.
      await connection.connect(PandaLiveDanmakuArgs(userId: _user, channel: _channel, token: _recordedToken));
      final first = connector.channels.single;
      await first.receive(_errorReply(1));
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(2));
      expect(http.requests, hasLength(1));
      expect(connector.channels.last.tokens, [token]);
      await connector.channels.last.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('an unanswered join times out and reconnects with a new token', () async {
      final connector = _Connector();
      final http = _Http([_granted(_tokenFor(30, sub: 'guest0000002'))]);
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.tokens, [_tokenFor(30, sub: 'guest0000002')]);
      await connector.channels.last.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('before the token lapses: a new token and socket, quietly; chat goes on', () async {
      final connector = _Connector();
      final renewed = _tokenFor(30, sub: 'guest0000002');
      final http = _Http([_granted(renewed)]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join(ttl: 1);
      await first.receive(_pub(_message(message: 'before')));
      // Renewal halfway through a 1 s token.
      await _until(() => connector.channels.length == 2);
      expect(http.requests, hasLength(1));
      expect(first.closed, isTrue);
      final second = connector.channels.last;
      expect(second.tokens, [renewed]);
      expect(second.sent.last, PandaLiveDanmakuProtocol.subscribe(_channel));
      expect(connection.isConnected, isTrue);
      await second.join();
      await second.receive(_pub(_message(message: 'after'), offset: 2096));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect([for (final m in _messages(events)) m.message], ['before', 'after']);
      // The second socket's token lasts 30 minutes: no renewal soon.
      await _wait(const Duration(milliseconds: 700));
      expect(connector.channels, hasLength(2));
      await connection.close();
    });

    test('a renewal that live/play refuses ends the connection; one that fails keeps the socket', () async {
      final connector = _Connector();
      final http = _Http([_refused('castEnd')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join(ttl: 1);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty && connector.channels.single.closed);
      expect(events, [
        const DanmakuReady(),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'live/play: castEnd'),
      ]);
      expect(connector.channels.single.closed, isTrue);

      final kept = _Connector();
      final failing = _Http([const TransportFailure(SiteIds.pandaLive, TransportReason.timeout), _granted('x.y.z')]);
      final staying = _connection(kept, failing);
      final seen = _record(staying);
      await staying.connect(_args);
      await kept.channels.single.join(ttl: 1);
      await _until(() => failing.requests.isNotEmpty);
      await _wait(const Duration(milliseconds: 50));
      expect(kept.channels, hasLength(1));
      expect(kept.channels.single.closed, isFalse);
      expect(seen, [const DanmakuReady()]);
      // The server then closes the lapsed socket: the reconnect asks again.
      await kept.channels.single.incoming.close();
      await _until(() => kept.channels.length == 2);
      expect(kept.channels.last.tokens, ['x.y.z']);
      await staying.close();
    });

    test('a socket that drops while a renewal waits for live/play is not replaced again', () async {
      final connector = _Connector();
      final pending = Completer<LiveResponse>();
      final renewed = _tokenFor(30, sub: 'guest0000002');
      final reconnected = _tokenFor(30, sub: 'guest0000003');
      final http = _Http([pending, _granted(reconnected)]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join(ttl: 1);
      await _until(() => http.requests.length == 1);
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.last.tokens, [reconnected]);
      pending.complete(_granted(renewed));
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(2));
      expect(connector.channels.last.closed, isFalse);
      await connector.channels.last.join();
      // The renewal's token was not used yet: the next handshake takes it.
      await connector.channels.last.incoming.close();
      await _until(() => connector.channels.length == 3);
      expect(connector.channels.last.tokens, [renewed]);
      expect(http.requests, hasLength(2));
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      await connection.close();
    });

    test('a renewed socket whose join goes unanswered is replaced', () async {
      final connector = _Connector();
      final http = _Http([for (var n = 2; n <= 3; n++) _granted(_tokenFor(30, sub: 'guest000000$n'))]);
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join(ttl: 1);
      await _until(() => connector.channels.length == 2);
      // No reply on the renewed socket.
      await _until(() => connector.channels.length == 3);
      expect(connector.channels[1].closed, isTrue);
      expect(connector.channels.last.tokens, [_tokenFor(30, sub: 'guest0000003')]);
      await connector.channels.last.join();
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('pings count on from the subscription on every socket; on the timer and on demand', () async {
      final connector = _Connector();
      final http = _Http([_granted(_tokenFor(30, sub: 'guest0000002'))]);
      final connection = _connection(
        connector,
        http,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          inactivityTimeout: Duration(seconds: 5),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await _until(() => first.sent.length >= 4);
      connection.heartbeat();
      final ids = [for (final frame in first.sent.skip(2)) (jsonDecode(frame as String) as Map)['id']];
      expect(ids, [for (var id = 3; id < 3 + ids.length; id++) id]);
      expect(first.sent.skip(2), everyElement(contains('"method":7')));
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      await second.join();
      connection.heartbeat();
      expect(second.sent[2], PandaLiveDanmakuProtocol.ping(3));
      await connection.close();
    });

    test('unusable arguments end at once, without a request or a handshake', () async {
      final connector = _Connector();
      final http = _Http([_granted('a.b.c')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      for (final args in const [
        PandaLiveDanmakuArgs(userId: '', channel: _channel, token: 'a.b.c'),
        PandaLiveDanmakuArgs(userId: 'bad id', channel: _channel),
        PandaLiveDanmakuArgs(userId: _user, channel: 'abc', token: 'a.b.c'),
      ]) {
        events.clear();
        await connection.connect(args);
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable broadcaster or channel'),
        ]);
      }
      expect(connector.endpoints, isEmpty);
      expect(http.requests, isEmpty);
      await expectLater(connection.connect('not pandalive args'), throwsArgumentError);
    });

    test('after close nothing is reported; a pending live/play is cancelled; connect replaces the room', () async {
      final pending = Completer<LiveResponse>();
      final waiting = _Http([pending]);
      final stalled = _connection(_Connector(), waiting);
      final quiet = _record(stalled);
      final starting = stalled.connect(const PandaLiveDanmakuArgs(userId: _user, channel: _channel));
      await _until(() => waiting.requests.isNotEmpty);
      await stalled.close();
      await starting;
      expect(waiting.requests.single.cancel!.isCancelled, isTrue);
      expect(quiet, isEmpty);

      final connector = _Connector();
      final http = _Http([_granted('x.y.z')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.join();
      final next = PandaLiveDanmakuArgs(
        userId: 'other01',
        channel: '777',
        token: _tokenFor(30, sub: 'guest0000009'),
      );
      await connection.connect(next);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [
        PandaLiveDanmakuProtocol.connect(next.token!),
        PandaLiveDanmakuProtocol.subscribe('777'),
      ]);
      await connector.channels.first.receive(_pub(_message(message: 'old socket')));
      await connector.channels.last.join();
      await connector.channels.last.receive(_pub(_message(message: 'old channel')));
      await connector.channels.last.receive(_pub(_message(message: 'new room'), channel: '777'));
      expect([for (final m in _messages(events)) m.message], ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(_pub(_message(message: 'late'), channel: '777'));
      connection.heartbeat();
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(connector.channels, hasLength(2));
      expect(http.requests, isEmpty);
    });

    test('a real local server: the handshake headers, connect, subscribe, ping and chat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final handshake = <String, String?>{};
      final received = <Object?>[];
      server.listen((request) async {
        handshake['path'] = request.uri.path;
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          received.add(frame);
          final command = jsonDecode(frame as String) as Map<String, Object?>;
          switch (command) {
            case {'id': 1}:
              socket.add(_connectReply());
            case {'id': 2}:
              socket.add(
                [
                  _reply(2, {}),
                  _pub({'type': 'MediaUpdate', 'created_at': 1790536599}),
                  _pub(_message(message: '반가워요')),
                ].join('\n'),
              );
            case {'method': 7, 'id': final int id}:
              socket.add(_reply(id));
          }
        });
      });
      final connection = PandaLiveDanmakuConnection(
        http: _Http([_granted('unused')]),
        now: () => _recordedAt,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, PandaLiveDanmakuProtocol.endpoint);
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
      await _until(() => received.length == 3);
      await _wait(const Duration(milliseconds: 20));
      expect(handshake['path'], '/connection/websocket');
      expect(handshake['origin'], 'https://www.pandalive.co.kr');
      expect(handshake['user-agent'], endsWith(PandaLiveApi.userAgent));
      expect(received, [
        PandaLiveDanmakuProtocol.connect(_args.token!),
        PandaLiveDanmakuProtocol.subscribe(_channel),
        PandaLiveDanmakuProtocol.ping(3),
      ]);
      expect(events.first, const DanmakuReady());
      expect(_messages(events).single.message, '반가워요');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });
  });
}
