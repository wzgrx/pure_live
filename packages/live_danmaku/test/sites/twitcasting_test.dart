import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/twitcasting';

/// The recorded session (danmaku/S08-live): the `eventpubsuburl.php` answer,
/// then the socket's text frames, with their line numbers.
final List<({int line, String? url, String text})> _recording = [
  for (final (index, line) in File('$_root/danmaku/S08-live/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': 'in', 'text': final String text} && final Map<String, Object?> frame)
      (line: index + 1, url: frame['url'] as String?, text: text),
];

/// The archived v4's output for S08-live (danmaku/v4_expected.dart).
final Map<String, Object?> _v4 =
    (jsonDecode(File('$_root/danmaku/S08-live/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

/// The recorded broadcast.
const int _movie = 841529001;

final Uri _signed = Uri.parse(
  'wss://202-218-171-231.twitcasting.tv/event.pubsub/v1/streams/841529001/events'
  '?token=YYOtMPO0QZSt%3A%3A%3A9518659223%3A8wv2s1l90536tga8&n=1355jeu93o52m397',
);

/// A socket URL answer as the site gives it (slashes escaped).
LiveResponse _answer(String url, {int status = 200}) => LiveResponse(
  status: status,
  bytes: utf8.encode(jsonEncode({'url': url}).replaceAll('/', r'\/')),
  url: TwitcastingDanmakuProtocol.pubsubUrl,
);

LiveResponse _body(String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: TwitcastingDanmakuProtocol.pubsubUrl);

/// Socket URL number [n] of a broadcast, signed with a synthetic token.
String _url(int n, {int movie = _movie}) =>
    'wss://node$n.twitcasting.tv/event.pubsub/v1/streams/$movie/events?token=tok$n%3A%3A%3A1790000000%3Asig$n&n=r$n';

/// [url] as the connection opens it: with the player's `gift=1` (D07.7).
Uri _gifts(String url) => Uri.parse('$url&gift=1');

const _args = TwitcastingDanmakuArgs(channel: 'c:abzou_sub', movieId: _movie);

/// No watchdog and a short backoff: only what the test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

/// Answers `eventpubsuburl.php` from a script: each entry is a response, an
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
          (_) => throw const TransportFailure(SiteIds.twitcasting, TransportReason.cancelled),
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
}

/// Hands out fake sockets and records every handshake; [failures] makes the
/// first handshakes throw it.
final class _Connector {
  new({this.failures = 0, this.error});

  final int failures;
  final Exception? error;
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
    if (endpoints.length <= failures) throw error ?? const SocketException('refused');
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

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

/// A message as the v4 projection shows it (v4 prefixed the id).
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'id': 'twitcasting:${message.messageId}',
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
};

/// A comment event.
Map<String, Object?> _comment({
  Object? id = 101,
  Object? message = 'hello',
  Object? createdAt = 1790532456000,
  Object? author = const {'id': 'c:tw1', 'name': 'Name', 'screenName': 'c:tw1', 'grade': 0},
}) => {'type': 'comment', 'id': ?id, 'message': ?message, 'createdAt': ?createdAt, 'author': ?author, 'numComments': 7};

void main() {
  group('protocol', () {
    test('the socket URL request: a form POST of movie_id with the adapter headers, as twitcasting', () {
      final cancel = CancelToken();
      final request = TwitcastingDanmakuProtocol.request(_movie, timeout: const Duration(seconds: 3), cancel: cancel);
      expect(request.site, SiteIds.twitcasting);
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://twitcasting.tv/eventpubsuburl.php'));
      expect(utf8.decode(request.body!), 'movie_id=841529001');
      expect(request.headers, {
        ...TwitcastingApi.headers,
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      });
      expect(request.timeout, const Duration(seconds: 3));
      expect(request.cancel, same(cancel));
      expect(TwitcastingDanmakuProtocol.socketHeaders, {
        'origin': 'https://twitcasting.tv',
        'user-agent': 'Mozilla/5.0',
      });
    });

    test('the recorded request and answer (S07-pubsub): the request matches, the answer gives its URL', () async {
      final http = ReplayHttp.fixtures(_root, ['S07-pubsub']);
      final response = await http.send(TwitcastingDanmakuProtocol.request(841525457));
      final url = TwitcastingDanmakuProtocol.socketUrl(response);
      expect(url.toString(), (jsonDecode(File('$_root/S07-pubsub/body.json').readAsStringSync()) as Map)['url']);
      expect(url.scheme, 'wss');
      expect(url.path, '/event.pubsub/v1/streams/841525457/events');
      expect(url.queryParameters.keys, ['token', 'n']);
    });

    test('socket URL answers that are not usable throw FormatException', () {
      Matcher fails(String text) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(text)));
      expect(() => TwitcastingDanmakuProtocol.socketUrl(_answer(_url(1), status: 400)), fails('HTTP 400'));
      expect(() => TwitcastingDanmakuProtocol.socketUrl(_body('', status: 500)), fails('HTTP 500'));
      expect(() => TwitcastingDanmakuProtocol.socketUrl(_body('<html>')), fails('no JSON'));
      for (final body in [
        '[]',
        '{}',
        '{"url":null}',
        '{"url":42}',
        '{"url":""}',
        jsonEncode({'url': _url(1).replaceFirst('wss:', 'ws:')}),
        jsonEncode({'url': _url(1).replaceFirst('wss:', 'https:')}),
        jsonEncode({'url': 'wss://eviltwitcasting.tv/event.pubsub/v1/streams/1/events'}),
        jsonEncode({'url': 'wss://twitcasting.tv.example.com/event.pubsub/v1/streams/1/events'}),
      ]) {
        expect(() => TwitcastingDanmakuProtocol.socketUrl(_body(body)), fails('no socket URL'), reason: body);
      }
      expect(TwitcastingDanmakuProtocol.socketUrl(_body('{"url":" ${_url(1)} "}')), Uri.parse(_url(1)));
      expect(
        TwitcastingDanmakuProtocol.socketUrl(_body('{"url":"wss://twitcasting.tv/x"}')),
        Uri.parse('wss://twitcasting.tv/x'),
      );
    });

    test('the nominal endpoint carries the broadcast; other addresses have none', () {
      final endpoint = TwitcastingDanmakuProtocol.endpoint(_movie);
      expect(endpoint, Uri.parse('https://twitcasting.tv/eventpubsuburl.php?movie_id=841529001'));
      expect(TwitcastingDanmakuProtocol.movieOf(endpoint), _movie);
      for (final other in [
        _signed,
        Uri.parse('https://twitcasting.tv/eventpubsuburl.php'),
        Uri.parse('https://twitcasting.tv/eventpubsuburl.php?movie_id=0'),
        Uri.parse('https://twitcasting.tv/eventpubsuburl.php?movie_id=-5'),
        Uri.parse('https://twitcasting.tv/eventpubsuburl.php?movie_id=abc'),
        Uri.parse('https://twitcasting.tv/other.php?movie_id=1'),
        Uri.parse('https://example.com/eventpubsuburl.php?movie_id=1'),
        Uri.parse('http://twitcasting.tv/eventpubsuburl.php?movie_id=1'),
      ]) {
        expect(TwitcastingDanmakuProtocol.movieOf(other), isNull, reason: '$other');
      }
    });

    test('redact leaves out the signature of a socket URL, nothing else', () {
      // dart:io's words for a refused upgrade, with the recorded (synthetic) signature.
      final failure =
          "WebSocketException: Connection to '${_signed.replace(scheme: 'https', port: 0)}#' was not upgraded to "
          'websocket, HTTP status code: 400';
      expect(failure, contains('YYOtMPO0QZSt'));
      final redacted = TwitcastingDanmakuProtocol.redact(failure);
      expect(redacted, isNot(contains('YYOtMPO0QZSt')));
      expect(redacted, isNot(contains('1355jeu93o52m397')));
      expect(redacted, contains('/streams/841529001/events?token=…&n=…#'));
      expect(redacted, endsWith('HTTP status code: 400'));
      expect(TwitcastingDanmakuProtocol.redact('connection=ok token=x'), 'connection=ok token=x');
      expect(TwitcastingDanmakuProtocol.redact('a?n=1&x=2&token=3'), 'a?n=…&x=2&token=…');
    });

    test('a comment: text, names, ids and time', () {
      final message = TwitcastingDanmakuProtocol.comment(_comment(message: '  え？ '))!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'え？');
      expect(message.userName, 'Name');
      expect(message.userId, 'c:tw1');
      expect(message.messageId, '101');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790532456000));
      expect(message.color, LiveMessageColor.white);
      expect(message.userLevel, isEmpty);
      expect(message.isLocal, isFalse);
    });

    test('comment boundaries: blank text, missing author, name fallback, ids and times', () {
      LiveMessage? of(Map<String, Object?> event) => TwitcastingDanmakuProtocol.comment(event);
      for (final text in [
        '',
        '   ',
        null,
        42,
        const ['x'],
      ]) {
        expect(of(_comment(message: text)), isNull, reason: '$text');
      }
      final anonymous = of(_comment(author: null))!;
      expect((anonymous.userName, anonymous.userId), ('', ''));
      expect(of(_comment(author: 'someone'))!.userName, '');
      expect(of(_comment(author: const {'name': ' ', 'screenName': ' c:tw9 '}))!.userName, 'c:tw9');
      expect(of(_comment(author: const {'name': 7, 'screenName': 'sn'}))!.userName, 'sn');
      expect(of(_comment(author: const {'id': 123}))!.userId, '123');
      expect(of(_comment(author: const {'id': 1.5}))!.userId, '');
      expect(of(_comment(id: ' a.b.c '))!.messageId, 'a.b.c');
      expect(of(_comment(id: null))!.messageId, '');
      expect(of(_comment(id: 1.5))!.messageId, '');
      expect(of(_comment(id: 85985946355))!.messageId, '85985946355');
      for (final time in [0, -1, 8640000000000001, 1.5e12, '1790532456000', null]) {
        expect(of(_comment(createdAt: time))!.sentAt, isNull, reason: '$time');
      }
      expect(of(_comment(createdAt: 1))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1));
      expect(of(_comment(createdAt: 8640000000000000))!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
    });

    test('frames: keep-alive, other events, bad JSON, bytes, a lone event', () {
      List<String> texts(Object? data) => [for (final m in TwitcastingDanmakuProtocol.decode(data)) m.message];
      expect(texts('[]'), isEmpty);
      expect(texts(''), isEmpty);
      expect(texts('[{"type":"comment"'), isEmpty);
      expect(texts('null'), isEmpty);
      expect(texts('"comment"'), isEmpty);
      expect(texts(42), isEmpty);
      expect(texts(null), isEmpty);
      final others = [
        {
          'id': 'd4e6d032.6ababdfca45100.54326497',
          'type': 'gift',
          'message': 'thanks',
          'isPaidGift': true,
          'item': {'name': 'Tea', 'image': 'https://twitcasting.tv/img/item_frame.png'},
          'sender': {'id': 's', 'name': 'S'},
          'createdAt': 1790623228000,
        },
        {'type': 'update_comment', 'id': 1, 'message': 'edited'},
        {'type': 'pin_message', 'message': 'pinned'},
        {'type': 'poll_status_update', 'poll': <String, Object?>{}},
        {'type': 'raid', 'message': 'raid'},
        {'type': 'Comment', 'message': 'wrong case'},
        {'message': 'no type'},
        'text',
        7,
        null,
        [_comment(message: 'nested')],
      ];
      // D07.7: the gift is reported (its `message` is the player's caption,
      // not the sender's words).
      expect(
        texts(jsonEncode([...others, _comment(message: 'one'), _comment(message: ''), _comment(message: 'two')])),
        ['Tea ×1', 'one', 'two'],
      );
      expect(texts(utf8.encode(jsonEncode([_comment(message: '弾き語り')]))), ['弾き語り']);
      expect(texts([0xFF, ...utf8.encode('[]')]), isEmpty);
      expect(texts(jsonEncode(_comment(message: 'lone'))), ['lone']);
    });
  });

  group('recording (S08-live)', () {
    test('the recorded eventpubsuburl.php answer gives the socket URL the archived v4 read', () {
      final answer = _recording.first;
      expect(answer.url, 'https://twitcasting.tv/eventpubsuburl.php');
      final url = TwitcastingDanmakuProtocol.socketUrl(_body(answer.text));
      expect(url.toString(), _v4['socket']);
      expect(url, _signed);
      final meta = jsonDecode(File('$_root/danmaku/S08-live/meta.json').readAsStringSync()) as Map<String, Object?>;
      expect(((meta['handshakes']! as List).single as Map)['url'], _v4['socket']);
    });

    test('every received frame decodes as the archived v4 did (ids without its prefix)', () {
      final frames = (_v4['frames']! as List).cast<Map<String, Object?>>();
      final socketFrames = _recording.skip(1).toList();
      expect(socketFrames, hasLength(frames.length));
      var chats = 0;
      var keepAlives = 0;
      for (final (index, frame) in socketFrames.indexed) {
        final expected = frames[index];
        expect(frame.line, expected['line']);
        final messages = TwitcastingDanmakuProtocol.decode(frame.text);
        expect([for (final message in messages) _project(message)], expected['events'], reason: 'line ${frame.line}');
        chats += messages.length;
        if (frame.text == '[]') keepAlives++;
      }
      expect((chats, keepAlives), (12, 2));
    });

    test('the connection replays the recording: one POST, one socket, ready, 12 chats in order', () async {
      final http = _Http([_body(_recording.first.text)]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      expect(connector.endpoints, [TwitcastingDanmakuProtocol.withGifts(_signed)]);
      for (final frame in _recording.skip(1)) {
        await connector.channels.single.receive(frame.text);
      }
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      final expected = [
        for (final frame in (_v4['frames']! as List).cast<Map<String, Object?>>())
          ...(frame['events']! as List).cast<Map<String, Object?>>(),
      ];
      expect([for (final message in _messages(events)) _project(message)], expected);
      expect(connector.channels.single.sent, isEmpty);
      expect(http.requests, hasLength(1));
      await connection.close();
    });
  });

  group('gifts (D07.7, S09-gifts)', () {
    final lines = [
      for (final line in File('../../fixtures/twitcasting/danmaku/S09-gifts/frames.jsonl').readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['text']! as String,
    ];

    test('S09: every recorded gift event as the player draws it; its words as chat; notices are not gifts', () {
      final messages = [for (final line in lines) ...TwitcastingDanmakuProtocol.decode(line)];
      expect(
        [for (final m in messages) (m.type, m.userName, m.message)],
        [
          (LiveMessageType.gift, '視聴者1', 'おもいで日記10 ×1'),
          (LiveMessageType.gift, '視聴者2', 'お茶 ×1'),
          (LiveMessageType.gift, '視聴者3', 'おもいで日記10 ×1'),
          (LiveMessageType.gift, '視聴者4', 'おもいで日記10 ×1'),
          (LiveMessageType.gift, '視聴者5', '応援スター ×1'),
          (LiveMessageType.gift, '視聴者6', 'お茶ｘ10 ×1'),
          (LiveMessageType.gift, '視聴者7', 'おもいで日記10 ×1'),
          (LiveMessageType.chat, '視聴者7', 'これ何'),
          for (final words in ['むねきゅんとキスちたい', 'むねきゅんとキスちたい', 'むねきゅんに頭ポンポンされたい']) ...[
            (LiveMessageType.gift, '視聴者8', 'お茶 ×1'),
            (LiveMessageType.chat, '視聴者8', words),
          ],
          (LiveMessageType.gift, '視聴者9', 'おもいで日記爆100 ×1'),
          (LiveMessageType.chat, '視聴者9', '大沼湖何も見れなかったからありがとうね🚗💨'),
          (LiveMessageType.gift, '視聴者10', 'コンティニューコイン ×1'),
        ],
        reason: "the two score notices of the broadcasters' own accounts are left out",
      );
      final first = messages.first;
      expect(
        (first.userId, first.messageId, first.sentAt),
        ('c:viewer1', '79a5ebd5.6ac89120724bd7.85525283', DateTime.fromMillisecondsSinceEpoch(1791529248000)),
      );
      expect(
        first.data,
        TwitcastingGift(
          name: 'おもいで日記10',
          iconUrl: Uri.parse('https://s01.twitcasting.tv/img/cp/calendar2026/calendar2026_item10.png'),
        ),
      );
      final paid = messages.firstWhere((m) => m.message == 'おもいで日記爆100 ×1');
      expect((paid.data! as TwitcastingGift).paid, isTrue);
      expect(messages[messages.indexOf(paid) + 1].messageId, '${paid.messageId}:words');
      final gifts = [
        for (final m in messages)
          if (m.data case final LiveGift gift) gift,
      ];
      expect(gifts.map((g) => (g.unit, g.totalValue, g.free)), everyElement((LiveGiftUnit.other, null, false)));
      expect(gifts.map((g) => g.kind), everyElement(LiveGiftKind.gift));
    });

    test('gift boundaries: no name, no sender info, a bad picture, a missing sender', () {
      List<LiveMessage> read(Map<String, Object?> event) => TwitcastingDanmakuProtocol.gift(event);
      const item = {'name': 'お茶', 'image': 'https://s01.twitcasting.tv/img/item_tea.png', 'showsSenderInfo': true};
      expect(
        read({
          'type': 'gift',
          'item': {...item, 'name': ''},
        }),
        isEmpty,
      );
      expect(
        read({
          'type': 'gift',
          'item': {...item, 'showsSenderInfo': false},
        }),
        isEmpty,
      );
      expect(read({'type': 'comment', 'item': item}), isEmpty);
      final bare = read({
        'type': 'gift',
        'item': {...item, 'image': 'http://x/a.png'},
        'plainMessage': '  ',
        'createdAt': -1,
      }).single;
      expect((bare.userName, bare.userId, bare.messageId, bare.sentAt), ('', '', '', null));
      expect((bare.data! as LiveGift).iconUrl, isNull, reason: 'https only');
      final screenName = read({
        'type': 'gift',
        'id': 'g',
        'item': item,
        'sender': {'id': 'c:x', 'screenName': 'X'},
        'plainMessage': 'hi',
      });
      expect([for (final m in screenName) (m.userName, m.messageId)], [('X', 'g'), ('X', 'g:words')]);
    });

    test('the connection reports the recorded gifts and their words', () async {
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(
        http: _Http([_answer(_url(1))]),
        connector: connector.call,
        policy: _quiet,
      );
      final events = _record(connection);
      await connection.connect(_args);
      for (final line in lines) {
        await connector.channels.single.receive(line);
      }
      final messages = _messages(events);
      expect(messages.where((m) => m.type == LiveMessageType.gift), hasLength(12));
      expect(messages.where((m) => m.type == LiveMessageType.chat), hasLength(5));
      await connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = TwitcastingDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 10));
      expect(policy.inactivityTimeout, const Duration(seconds: 30));
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = TwitcastingDanmakuConnection(http: _Http([_answer(_url(1))]));
      expect(connection.heartbeatInterval, const Duration(seconds: 10));
      expect(connection.status, DanmakuStatus.idle);
      final registry = DanmakuRegistry({
        SiteIds.twitcasting: () => TwitcastingDanmakuConnection(http: _Http([_answer(_url(1))])),
      });
      expect(registry.supports('TwitCasting'), isTrue);
      expect(registry.connectionFor('twitcasting'), isA<TwitcastingDanmakuConnection>());
    });

    test('handshake: the POST for the broadcast, then its signed URL with the headers; open is ready', () async {
      final http = _Http([_answer(_url(1))]);
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = TwitcastingDanmakuConnection(
        http: http,
        connector: connector.call,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.twitcasting: route}),
        policy: _quiet,
      );
      final events = _record(connection);
      await connection.connect(_args);
      expect(http.requests.single.url, TwitcastingDanmakuProtocol.pubsubUrl);
      expect(utf8.decode(http.requests.single.body!), 'movie_id=841529001');
      expect(http.requests.single.timeout, const Duration(seconds: 10));
      expect(connector.endpoints, [_gifts(_url(1))]);
      expect(connector.headers.single, TwitcastingDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      await connector.channels.single.receive(jsonEncode([_comment(message: 'hi')]));
      expect(_messages(events).single.message, 'hi');
      await connection.close();
    });

    test('nothing is ever sent: not at the heartbeat ticks, not for a manual heartbeat', () async {
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(
        http: _Http([_answer(_url(1))]),
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 5),
          inactivityTimeout: Duration(seconds: 30),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _wait(const Duration(milliseconds: 60));
      connection.heartbeat();
      expect(connector.channels.single.sent, isEmpty);
      expect(connector.endpoints, hasLength(1));
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('a dropped socket reconnects with a newly signed URL and is ready again', () async {
      final http = _Http([_answer(_url(1)), _answer(_url(2))]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(connector.endpoints, [_gifts(_url(1)), _gifts(_url(2))]);
      expect(http.requests, hasLength(2));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connector.channels.last.receive(jsonEncode([_comment(message: 'after')]));
      expect(_messages(events).single.message, 'after');
      await connection.close();
    });

    test('a failed POST is a failed handshake: reported once, retried, then joined', () async {
      final http = _Http([
        const TransportFailure(SiteIds.twitcasting, TransportReason.connect, 'refused'),
        _body('', status: 503),
        _body('{"url":"https://twitcasting.tv/"}'),
        _answer(_url(4)),
      ]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await _until(() => connection.isConnected);
      expect(http.requests, hasLength(4));
      expect(connector.endpoints, [_gifts(_url(4))]);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('a failed socket handshake asks for a new URL too', () async {
      final http = _Http([_answer(_url(1)), _answer(_url(2))]);
      final connector = _Connector(failures: 1);
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connection.isConnected);
      expect(connector.endpoints, [_gifts(_url(1)), _gifts(_url(2))]);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('failures in a row end the connection; the detail names no signature', () async {
      final http = _Http([_answer(_url(1))]);
      final connector = _Connector(
        failures: 100,
        error: WebSocketException(
          "Connection to '${_url(1).replaceFirst('wss:', 'https:')}#' was not upgraded to websocket, "
          'HTTP status code: 400',
        ),
      );
      final connection = TwitcastingDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 2,
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      final closed = events.whereType<DanmakuClosed>().single;
      expect(closed.reason, DanmakuCloseReason.reconnectsExhausted);
      expect(closed.detail, contains('HTTP status code: 400'));
      expect(closed.detail, contains('token=…&n=…'));
      expect(closed.detail, isNot(contains('tok1')));
      expect(closed.detail, isNot(contains('sig1')));
      expect(http.requests, hasLength(3));
      expect(connection.status, DanmakuStatus.closed);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
    });

    test('unusable answers in a row end the connection too', () async {
      final http = _Http([_body('{}')]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 1,
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(events.last, isA<DanmakuClosed>().having((e) => e.detail, 'detail', contains('no socket URL')));
      expect(connector.endpoints, isEmpty);
      expect(http.requests, hasLength(2));
    });

    test('a silent socket is replaced; keep-alives keep it', () async {
      final http = _Http([_answer(_url(1)), _answer(_url(2))]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          // Wide enough that a loaded machine never misses a keep-alive.
          inactivityTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      // Keep-alives every 25 ms for 600 ms: the socket stays.
      for (var i = 0; i < 24; i++) {
        await connector.channels.single.receive('[]');
        await _wait(const Duration(milliseconds: 25));
      }
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      // Then silence: replaced with a newly signed URL.
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.endpoints.last, _gifts(_url(2)));
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(events[1], const DanmakuReconnecting(DanmakuInterruption.disconnected));
      await connection.close();
    });

    test('arguments without a broadcast end at once, without a request', () async {
      final http = _Http([_answer(_url(1))]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const TwitcastingDanmakuArgs(channel: 'c:x', movieId: 0));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast')]);
      expect(http.requests, isEmpty);
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect('not twitcasting args'), throwsArgumentError);
    });

    test('closing during the POST cancels it: no socket and no event', () async {
      final pending = Completer<LiveResponse>();
      final http = _Http([pending]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      pending.complete(_answer(_url(1)));
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('after close nothing is reported; another connect replaces the broadcast', () async {
      final http = _Http([_answer(_url(1)), _answer(_url(2, movie: 900))]);
      final connector = _Connector();
      final connection = TwitcastingDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      await connection.connect(const TwitcastingDanmakuArgs(channel: 'c:y', movieId: 900));
      expect(connector.channels.first.closed, isTrue);
      expect(http.requests.first.cancel!.isCancelled, isTrue);
      expect(utf8.decode(http.requests.last.body!), 'movie_id=900');
      expect(connector.endpoints.last, _gifts(_url(2, movie: 900)));
      await connector.channels.first.receive(jsonEncode([_comment(message: 'old room')]));
      await connector.channels.last.receive(jsonEncode([_comment(message: 'new room')]));
      expect([for (final m in _messages(events)) m.message], ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(jsonEncode([_comment(message: 'late')]));
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(http.requests, hasLength(2));
    });

    test('a real local server: the form POST, the handshake headers, keep-alive and chat', () async {
      final posts = <String>[];
      final handshake = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.uri.path == '/eventpubsuburl.php') {
          posts.add(
            '${request.method} ${request.headers.contentType?.mimeType} '
            '${await utf8.decodeStream(request)} ${request.headers.value('referer')}',
          );
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'url': _url(posts.length)}));
          await request.response.close();
          return;
        }
        handshake['path'] = '${request.uri.path}?${request.uri.query}';
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket
          ..add('[]')
          ..add(jsonEncode([_comment(message: '弾き語り')]));
      });
      final http = _Local(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = TwitcastingDanmakuConnection(
        http: http,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.host, 'node1.twitcasting.tv');
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
      expect(posts, ['POST application/x-www-form-urlencoded movie_id=841529001 https://twitcasting.tv/']);
      final signed = _gifts(_url(1));
      expect(handshake['path'], '${signed.path}?${signed.query}');
      expect(handshake['origin'], 'https://twitcasting.tv');
      // dart:io's handshake keeps its own user agent in front of the one given.
      expect(handshake['user-agent'], endsWith('Mozilla/5.0'));
      expect(events.first, const DanmakuReady());
      expect(_messages(events).single.message, '弾き語り');
      await connection.close();
    });
  });
}

/// Sends the `eventpubsuburl.php` requests to a local server.
final class _Local implements LiveHttp {
  new(this._inner, this._port);

  final LiveHttp _inner;
  final int _port;

  @override
  Future<LiveResponse> send(LiveRequest request) => _inner.send(
    LiveRequest(
      site: request.site,
      url: request.url.replace(scheme: 'http', host: '127.0.0.1', port: _port),
      method: request.method,
      headers: request.headers,
      body: request.body,
      timeout: request.timeout,
      cancel: request.cancel,
    ),
  );

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
