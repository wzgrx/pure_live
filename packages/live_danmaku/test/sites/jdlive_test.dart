// JD Live chat (M5.24): the guest liveauth request and its answer, the
// socket frames against what the website's own code makes of two recordings
// (fixtures/jdlive/danmaku, expected.json by web_expected.mjs), synthetic
// frames for the edges, and the connection over fake and local sockets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/jdlive/danmaku';

/// One line of a recording.
typedef _Line = ({int line, Map<String, Object?> record});

List<_Line> _lines(String sample) => [
  for (final (index, line) in File('$_root/$sample/frames.jsonl').readAsLinesSync().indexed)
    (line: index + 1, record: jsonDecode(line) as Map<String, Object?>),
];

Map<String, Object?> _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync()) as Map<String, Object?>;

/// The website's reading of a recording (web_expected.mjs).
Map<String, Object?> _web(String sample) => _json('$sample/expected.json')['value']! as Map<String, Object?>;

/// The recorded liveauth request, answer and socket frames of [sample].
({Map<String, Object?> request, String answer, List<({int line, String text})> frames}) _recording(String sample) {
  final lines = _lines(sample);
  final request = lines.firstWhere((line) => line.record['dir'] == 'out').record;
  final answer = lines.firstWhere((line) => line.record['dir'] == 'in' && line.record['url'] != null);
  return (
    request: request,
    answer: answer.record['text']! as String,
    frames: [
      for (final line in lines)
        if (line.record case {'dir': 'in', 'text': final String text} when line.record['url'] == null)
          (line: line.line, text: text),
    ],
  );
}

/// The broadcast of S06-live (chat) and S07-ended (the broadcast ends).
const _live = '48399381';
const _ended = '48431089';

/// The clock of the synthetic requests.
final DateTime _now = DateTime.utc(2026, 9, 30, 12);

LiveResponse _body(String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: JdLiveDanmakuProtocol.authUrl);

/// A liveauth answer with socket [n]'s token (guest token shape).
LiveResponse _answer(int n, {String liveUrl = 'wss://live-ws4.jd.com', String? mask}) => _body(
  jsonEncode({
    'code': 0,
    'msg': '鉴权成功',
    'data': {
      'liveUrl': liveUrl,
      'quicUrl': false,
      'secretPin': 'c2VjcmV0UGluJG4=',
      'token': _token(n),
      'msgMaskKey': ?mask,
    },
  }),
);

String _token(int n) => base64Url.encode(utf8.encode('jd.mall_游客_1000000000${n}_1790770000000123456'));

Uri _socket(int n, {String liveUrl = 'wss://live-ws4.jd.com'}) => Uri.parse('$liveUrl?token=${_token(n)}');

/// A statistics frame.
String _stats({Object? current = '3', Object? total = '1745', Object? group = _live}) => jsonEncode({
  'datetime': 1790637935368,
  'from': {'app': 'jd.live', 'pinmd5': '0f1e2d3c4b5a69788796a5b4c3d2e1f0', 'secretPin': 'U3RhdGlzdGljcyEhIQ=='},
  'id': '1c0ffee0ddba11ad5eed0000cafe0001',
  'body': {
    'message_num': '9',
    'pv': '1023',
    'groupid': ?group,
    'thumbs_up_num': '33',
    'total_viwer': ?total,
    'max_viewer': '3',
    'current_viewer': ?current,
    'cart_num': '0',
  },
  'type': 'get_statistics_result',
  'msgSource': 0,
});

/// A `chat_group_message` event of kind [type].
Map<String, Object?> _event(
  String type, {
  Object? content = 'hello',
  Object? nickName = 'jd_viewer',
  Object? group = _live,
  Object? from = const {'app': 'jd.live', 'pinmd5': 'a1b2c3d4e5f60718293a4b5c6d7e8f90', 'secretPin': 'x'},
  Object? id = 'f3a1c2d4-0b5e-4c6f-9a7b-8c9d0e1f2a3b',
  Object? datetime = 1790637935368,
}) => {
  'datetime': ?datetime,
  'from': ?from,
  'id': ?id,
  'body': {'nickName': ?nickName, 'groupid': ?group, 'type': type, 'content': ?content, 'plus': '0'},
  'type': 'chat_group_message',
  'msgSource': 0,
};

String _chat({Object? content = 'hello', Object? nickName = 'jd_viewer', Object? group = _live}) =>
    jsonEncode(_event('viewer_send_message', content: content, nickName: nickName, group: group));

JdLiveDanmakuFrame _decode(Object? data, {String liveId = _live, String? mask}) =>
    JdLiveDanmakuProtocol.decode(data, liveId: liveId, maskKey: mask);

List<String> _texts(Object? data, {String liveId = _live, String? mask}) => [
  for (final message in _decode(data, liveId: liveId, mask: mask).messages) message.message,
];

/// XORs [text]'s UTF-8 with [key] as the server would mask a binary frame.
List<int> _masked(String text, String key) {
  final bytes = utf8.encode(text);
  return [for (var i = 0; i < bytes.length; i++) bytes[i] ^ key.codeUnitAt(i % key.length)];
}

/// No watchdog and a short backoff: only what the test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

/// Answers liveauth from a script: each entry is a response, an error to
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
          (_) => throw const TransportFailure(SiteIds.jdLive, TransportReason.cancelled),
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
/// first handshakes throw [error].
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

List<String> _chats(List<DanmakuEvent> events) => [
  for (final message in _messages(events))
    if (message.type == LiveMessageType.chat) message.message,
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

/// The website's projection of a frame (web_expected.mjs): the chat lines
/// it adds and the viewer count it keeps.
Map<String, Object?> _project(int line, JdLiveDanmakuFrame frame) {
  final total = [
    for (final message in frame.messages)
      if (message.data case LiveAudienceUpdate(kind: LiveAudienceMetricKind.totalViewers, :final value)) value,
  ];
  return {
    'line': line,
    'chat': [
      for (final message in frame.messages)
        if (message.type == LiveMessageType.chat) {'nickName': message.userName, 'content': message.message},
    ],
    if (total.isNotEmpty) 'viewer': '${total.single}',
    if (frame.ended) 'status': 2,
  };
}

/// The page's projection without the chat kind, which the messages do not
/// carry.
Map<String, Object?> _webProjection(Map<String, Object?> frame) => {
  ...frame,
  'chat': [
    for (final chat in (frame['chat']! as List).cast<Map<String, Object?>>())
      {'nickName': chat['nickName'], 'content': chat['content']},
  ],
};

LiveAudienceUpdate _audience(LiveMessage message) => message.data! as LiveAudienceUpdate;

void main() {
  group('protocol', () {
    test("the content: the page's JSON in its key order; encrypted as the page does", () {
      final content = JdLiveDanmakuProtocol.content(_live, now: _now, nonce: '012345');
      expect(
        content,
        '{"appId":"jd.mall","secretKey":"RYm2dMPMWD9AxYFk","groupId":"48399381","clientType":"m",'
        '"timestamp":${_now.millisecondsSinceEpoch},"origin":-100,"encryptPin":true,"random":"012345"}',
      );
      final encrypted = JdLiveDanmakuProtocol.encrypt(content);
      final plain = Aes128Cbc.decrypt(
        base64.decode(encrypted),
        key: utf8.encode('RYm2dMPMWD9AxYFk'),
        iv: utf8.encode('0102030405060708'),
      );
      expect(utf8.decode(plain), content);
      expect(base64.decode(encrypted).length % 16, 0);
    });

    test('the nonce: six digits, as Math.random().toString().slice(-6)', () {
      final random = Random(7);
      final nonces = [for (var i = 0; i < 200; i++) JdLiveDanmakuProtocol.nonce(random)];
      expect(nonces.every(RegExp(r'^\d{6}$').hasMatch), isTrue);
      expect(nonces.toSet().length, greaterThan(190));
      expect(JdLiveDanmakuProtocol.nonce(Random(1)), JdLiveDanmakuProtocol.nonce(Random(1)));
    });

    test("the request: the page's form POST, the adapter's headers, no redirects, as jdlive", () {
      final cancel = CancelToken();
      final request = JdLiveDanmakuProtocol.request(
        _live,
        now: _now,
        nonce: '012345',
        timeout: const Duration(seconds: 3),
        cancel: cancel,
      );
      expect(request.site, SiteIds.jdLive);
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://api.m.jd.com/api'));
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 3));
      expect(request.cancel, same(cancel));
      expect(request.headers, {
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://lives.jd.com',
        'referer': 'https://lives.jd.com/',
        'user-agent': JdLiveApi.userAgent,
        'content-type': 'application/x-www-form-urlencoded',
      });
      final body = utf8.decode(request.body!);
      expect(body.split('&').map((pair) => pair.split('=').first), ['loginType', 'appid', 'functionId', 'body', 't']);
      final form = Uri.splitQueryString(body);
      expect(form['loginType'], '2');
      expect(form['appid'], 'h5-live');
      expect(form['functionId'], 'liveauth');
      expect(form['t'], '${_now.millisecondsSinceEpoch}');
      final json = jsonDecode(form['body']!) as Map<String, Object?>;
      expect(json.keys, ['appId', 'content']);
      expect(json['appId'], 'jd.mall');
      expect(
        json['content'],
        JdLiveDanmakuProtocol.encrypt(JdLiveDanmakuProtocol.content(_live, now: _now, nonce: '012345')),
      );
      expect(JdLiveDanmakuProtocol.socketHeaders, {
        'origin': 'https://lives.jd.com',
        'user-agent': JdLiveApi.userAgent,
      });
    });

    test('answers: the socket URL is liveUrl?token=, the mask when given', () {
      final auth = JdLiveDanmakuProtocol.auth(_answer(1));
      expect(auth.socketUrl, _socket(1));
      expect('${auth.socketUrl}', 'wss://live-ws4.jd.com?token=${_token(1)}', reason: 'the token as given');
      expect(auth.maskKey, isNull);
      expect(JdLiveDanmakuProtocol.auth(_answer(1, mask: 'k3y')).maskKey, 'k3y');
      expect(JdLiveDanmakuProtocol.auth(_answer(1, mask: '')).maskKey, isNull);
      expect(
        JdLiveDanmakuProtocol.auth(_answer(1, liveUrl: 'wss://ws.jd.com/chat')).socketUrl,
        _socket(1, liveUrl: 'wss://ws.jd.com/chat'),
      );
      expect(JdLiveDanmakuProtocol.auth(_answer(1, liveUrl: ' wss://JD.COM ')).socketUrl.host, 'jd.com');
    });

    test('answers that are not usable throw FormatException', () {
      Matcher fails(String text) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(text)));
      expect(() => JdLiveDanmakuProtocol.auth(_body('', status: 403)), fails('HTTP 403'));
      expect(() => JdLiveDanmakuProtocol.auth(_body('<html>')), fails('no JSON'));
      expect(() => JdLiveDanmakuProtocol.auth(_body('[]')), fails('no JSON object'));
      expect(
        () => JdLiveDanmakuProtocol.auth(_body('{"code":1,"msg":"鉴权失败","data":{"error":"解密失败!"}}')),
        fails('liveauth refused: 1 鉴权失败 (解密失败!)'),
      );
      expect(() => JdLiveDanmakuProtocol.auth(_body('{"code":"0","data":{}}')), fails('refused: 0'));
      expect(() => JdLiveDanmakuProtocol.auth(_body('{"code":0}')), fails('refused'));
      Map<String, Object?> data(Map<String, Object?> edits) {
        final json = jsonDecode(_answer(1).text) as Map<String, Object?>;
        final fields = json['data']! as Map<String, Object?>;
        for (final MapEntry(:key, :value) in edits.entries) {
          value == null ? fields.remove(key) : fields[key] = value;
        }
        return json;
      }

      for (final edits in <Map<String, Object?>>[
        {'liveUrl': null},
        {'liveUrl': 42},
        {'liveUrl': ''},
        {'liveUrl': 'ws://live-ws4.jd.com'},
        {'liveUrl': 'https://live-ws4.jd.com'},
        {'liveUrl': 'wss://live-ws4.jd.com.example.com'},
        {'liveUrl': 'wss://evil-jd.com'},
        {'liveUrl': 'wss://live-ws4.jd.com?x=1'},
        {'liveUrl': 'wss://live-ws4.jd.com#x'},
        {'liveUrl': 'wss://user@live-ws4.jd.com'},
        {'token': null},
        {'token': 7},
        {'token': ' '},
        {'token': 'a b'},
        {'token': 'a&b=1'},
        {'token': 'a#b'},
      ]) {
        expect(() => JdLiveDanmakuProtocol.auth(_body(jsonEncode(data(edits)))), fails('no socket'), reason: '$edits');
      }
    });

    test('the nominal endpoint carries the broadcast; other addresses have none', () {
      final endpoint = JdLiveDanmakuProtocol.endpoint(_live);
      expect(endpoint, Uri.parse('https://api.m.jd.com/api?functionId=liveauth&groupId=48399381'));
      expect(JdLiveDanmakuProtocol.liveIdOf(endpoint), _live);
      for (final other in [
        _socket(1),
        Uri.parse('https://api.m.jd.com/api'),
        Uri.parse('https://api.m.jd.com/api?functionId=liveauth'),
        Uri.parse('https://api.m.jd.com/api?functionId=liveauth&groupId=0'),
        Uri.parse('https://api.m.jd.com/api?functionId=liveauth&groupId=abc'),
        Uri.parse('https://api.m.jd.com/api?functionId=other&groupId=48399381'),
        Uri.parse('https://api.m.jd.com/other?functionId=liveauth&groupId=48399381'),
        Uri.parse('https://example.com/api?functionId=liveauth&groupId=48399381'),
        Uri.parse('http://api.m.jd.com/api?functionId=liveauth&groupId=48399381'),
      ]) {
        expect(JdLiveDanmakuProtocol.liveIdOf(other), isNull, reason: '$other');
      }
    });

    test('redact leaves out the token of a socket URL, nothing else', () {
      // dart:io's words for a used token (measured: HTTP 200, no upgrade).
      final failure =
          "WebSocketException: Connection to '${_socket(1).replace(scheme: 'https', port: 0)}#' was not upgraded to "
          'websocket, HTTP status code: 200';
      expect(failure, contains(_token(1)));
      final redacted = JdLiveDanmakuProtocol.redact(failure);
      expect(redacted, isNot(contains(_token(1))));
      expect(redacted, contains('live-ws4.jd.com:0?token=…#'));
      expect(redacted, endsWith('HTTP status code: 200'));
      expect(JdLiveDanmakuProtocol.redact('connection=ok token=x'), 'connection=ok token=x');
      expect(JdLiveDanmakuProtocol.redact('a?x=1&token=3&y=2'), 'a?x=1&token=…&y=2');
    });

    test('a viewer message: name, text, user, id and time', () {
      final message = _decode(_chat(content: ' 多重 ', nickName: ' jd_viewer ')).messages.single;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, '多重');
      expect(message.userName, 'jd_viewer');
      expect(message.userId, 'a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(message.messageId, 'f3a1c2d4-0b5e-4c6f-9a7b-8c9d0e1f2a3b');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790637935368));
      expect(message.color, LiveMessageColor.white);
      expect((message.userLevel, message.fansName, message.isLocal), ('', '', false));
    });

    test("the streamer's message: named 主播 as the page shows, without a name of its own", () {
      final message = _decode(jsonEncode(_event('anchor_send_message', content: '正在讲解Top宝贝', nickName: null)));
      expect(message.messages.single.userName, '主播');
      expect(message.messages.single.message, '正在讲解Top宝贝');
      expect(JdLiveDanmakuProtocol.anchorName, '主播');
      final named = _decode(jsonEncode(_event('anchor_send_message', nickName: 'shop'))).messages.single;
      expect(named.userName, '主播', reason: 'the page ignores any name');
    });

    test('chat boundaries: blank text, names, users, ids and times', () {
      LiveMessage? of(Map<String, Object?> event) => JdLiveDanmakuProtocol.chat(event);
      for (final text in [
        '',
        '   ',
        null,
        42,
        const ['x'],
      ]) {
        expect(of(_event('viewer_send_message', content: text)), isNull, reason: '$text');
      }
      expect(of(_event('viewer_send_message', nickName: null))!.userName, '');
      expect(of(_event('viewer_send_message', nickName: 7))!.userName, '');
      expect(of(_event('viewer_send_message', from: null))!.userId, '');
      expect(of(_event('viewer_send_message', from: 'x'))!.userId, '');
      expect(of(_event('viewer_send_message', from: const {'pinmd5': 5}))!.userId, '');
      expect(of(_event('viewer_send_message', id: null))!.messageId, '');
      expect(of(_event('viewer_send_message', id: 42))!.messageId, '');
      for (final time in [0, -1, 8640000000000001, 1.5e12, '1790637935368', null]) {
        expect(of(_event('viewer_send_message', datetime: time))!.sentAt, isNull, reason: '$time');
      }
      expect(of(_event('viewer_send_message', datetime: 1))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1));
      expect(
        of(_event('viewer_send_message', datetime: 8640000000000000))!.sentAt,
        DateTime.fromMillisecondsSinceEpoch(8640000000000000),
      );
      expect(of(const {'type': 'chat_group_message'}), isNull);
      expect(of(const {'body': 'x'}), isNull);
    });

    test('the audience: current_viewer online, total_viwer cumulative; numbers or their text, not negative', () {
      final messages = _decode(_stats()).messages;
      expect(messages.map((m) => (m.type, _audience(m).kind, _audience(m).value)), [
        (LiveMessageType.online, LiveAudienceMetricKind.onlineViewers, 3),
        (LiveMessageType.online, LiveAudienceMetricKind.totalViewers, 1745),
      ]);
      expect(messages.every((m) => m.userName.isEmpty && m.message.isEmpty), isTrue);
      List<(LiveAudienceMetricKind, int)> of(Object? current, Object? total) => [
        for (final m in _decode(_stats(current: current, total: total)).messages)
          (_audience(m).kind, _audience(m).value),
      ];
      expect(of(0, 12), [(LiveAudienceMetricKind.onlineViewers, 0), (LiveAudienceMetricKind.totalViewers, 12)]);
      expect(of(' 5 ', null), [(LiveAudienceMetricKind.onlineViewers, 5)]);
      expect(of(null, '7'), [(LiveAudienceMetricKind.totalViewers, 7)]);
      for (final bad in ['-1', -1, '1.5', 1.5, 'x', '', true]) {
        expect(of(bad, bad), isEmpty, reason: '$bad');
      }
    });

    test('frames: other events, other groups, bad JSON, bytes, the mask, the end', () {
      expect(_texts(''), isEmpty);
      expect(_texts('{"type":"chat_group_message"'), isEmpty);
      expect(_texts('null'), isEmpty);
      expect(_texts('[${_chat()}]'), isEmpty, reason: 'an array is not a frame');
      expect(_texts(42), isEmpty);
      expect(_texts(null), isEmpty);
      expect(_texts('{"type":"chat_group_message","body":"x"}'), isEmpty);
      for (final type in [
        'thumbs_up',
        'join_live_broadcast_summary',
        'anchor_public_reply',
        'live_common_reply',
        'viewer_buy_product_summary',
        'viewer_get_coupon',
        'pay_attention_to_anchor',
        'new_anchor_cart_number',
        'anchor_new_popup_product',
        'jdlive_refresh_cart',
        'suspend_live_broadcast',
        'resume_live_broadcast',
        'Viewer_send_message',
        'unknown',
      ]) {
        final frame = _decode(jsonEncode(_event(type)));
        expect((frame.messages.length, frame.ended), (0, false), reason: type);
      }
      expect(_texts(jsonEncode({..._event('viewer_send_message'), 'type': 'other'})), isEmpty);
      // The group: a number or its text; another group's events are dropped.
      expect(_texts(_chat(group: 48399381)), ['hello']);
      expect(_texts(_chat(group: ' 48399381 ')), ['hello']);
      expect(_texts(_chat(group: null)), ['hello'], reason: 'no group: this socket is one group');
      for (final other in [48399382, '48399382', 4.8399381e7, true]) {
        expect(_texts(_chat(group: other)), isEmpty, reason: '$other');
        expect(_decode(_stats(group: other)).messages, isEmpty, reason: '$other');
      }
      // Bytes: UTF-8, XORed with the answer's mask when it has one.
      expect(_texts(utf8.encode(_chat(content: '多重'))), ['多重']);
      expect(_texts(_masked(_chat(content: '多重'), 'k3y'), mask: 'k3y'), ['多重']);
      expect(_texts(_masked(_chat(content: '多重'), 'k3y')), isEmpty, reason: 'masked bytes without the mask');
      expect(_texts(_masked(_chat(content: 'é'), 'ÿé'), mask: 'ÿé'), ['é'], reason: 'the low byte of each code unit');
      expect(_texts(_chat(content: 'text'), mask: 'k3y'), ['text'], reason: 'text frames are never masked');
      expect(_texts([0xFF, ...utf8.encode(_chat())]), isEmpty, reason: 'not UTF-8');
      // The end of the broadcast.
      final end = _decode(jsonEncode(_event('stop_live_broadcast', content: null)));
      expect((end.messages.length, end.ended), (0, true));
      expect(_decode(jsonEncode(_event('stop_live_broadcast', group: 1))).ended, isFalse);
    });
  });

  group('recordings', () {
    test("S06-live's liveauth: the page's request and the answer's socket, as the page reads them", () {
      final recording = _recording('S06-live');
      final web = _web('S06-live');
      final meta = _json('S06-live/meta.json');
      final plain = recording.request['content']! as String;
      final content = jsonDecode(plain) as Map<String, Object?>;
      expect(content['groupId'], _live);
      final now = DateTime.fromMillisecondsSinceEpoch(content['timestamp']! as int);
      final nonce = content['random']! as String;
      expect(JdLiveDanmakuProtocol.content(_live, now: now, nonce: nonce), plain);
      final request = JdLiveDanmakuProtocol.request(_live, now: now, nonce: nonce);
      final form = Uri.splitQueryString(utf8.decode(request.body!));
      final recorded = Uri.splitQueryString(recording.request['text']! as String);
      expect(form, recorded, reason: 'the same form as the recorder sent');
      expect((jsonDecode(form['body']!) as Map)['content'], web['content'], reason: "the page's encryption");
      final requests = (meta['requests']! as List).cast<Map<String, Object?>>();
      expect(requests.single['url'], '${JdLiveDanmakuProtocol.authUrl}');
      final auth = JdLiveDanmakuProtocol.auth(_body(recording.answer));
      expect('${auth.socketUrl}', web['socket']);
      expect(((meta['handshakes']! as List).single as Map)['url'], web['socket']);
      expect((auth.maskKey, web['mask']), (null, null), reason: 'guest answers have no mask');
    });

    for (final (sample, liveId) in [('S06-live', _live), ('S07-ended', _ended)]) {
      test('$sample: every frame as the page reads it: its chat lines, its viewer count, the end', () {
        final web = (_web(sample)['frames']! as List).cast<Map<String, Object?>>();
        final frames = _recording(sample).frames;
        expect(frames, hasLength(web.length));
        for (final (index, frame) in frames.indexed) {
          expect(
            _project(frame.line, JdLiveDanmakuProtocol.decode(frame.text, liveId: liveId)),
            _webProjection(web[index]),
            reason: 'line ${frame.line}',
          );
        }
      });
    }

    test('S06-live by hand: the viewer, the streamer, the audience at every statistics frame', () {
      final frames = _recording('S06-live').frames;
      final decoded = [for (final frame in frames) JdLiveDanmakuProtocol.decode(frame.text, liveId: _live)];
      final chats = [
        for (final frame in decoded)
          for (final message in frame.messages)
            if (message.type == LiveMessageType.chat) message,
      ];
      expect(
        [for (final m in chats) (m.userName, m.message)],
        [('hq_290537adwg', '多重'), ('主播', '老铁，您说的“多重”是指多重优惠还是多重款式呢？')],
      );
      final viewer = chats.first;
      expect(viewer.messageId, '93d8c91d-39ee-4866-be2a-72f7ab22427a');
      expect(viewer.sentAt, DateTime.fromMillisecondsSinceEpoch(1790637935368));
      expect(viewer.userId, hasLength(32));
      final raw = jsonDecode(frames.firstWhere((f) => f.text.contains('viewer_send_message')).text) as Map;
      expect(viewer.userId, (raw['from'] as Map)['pinmd5']);
      expect(chats.last.userId, isNot(viewer.userId));
      // Statistics: two numbers each, current_viewer as the page's store
      // never reads it; it follows the viewer's join and leave.
      final online = [
        for (final frame in decoded)
          for (final message in frame.messages) ?_audienceOf(message, LiveAudienceMetricKind.onlineViewers),
      ];
      final statistics = frames.where((f) => f.text.contains('"get_statistics_result"')).length;
      expect(online, hasLength(statistics));
      expect(online.toSet(), {0, 1});
      expect(decoded.where((frame) => frame.ended), isEmpty);
    });

    test('S06-live replayed through the connection: one POST, one socket, ready once, messages in order', () async {
      final recording = _recording('S06-live');
      final http = _Http([_body(recording.answer)]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      expect(connector.endpoints, [Uri.parse(_web('S06-live')['socket']! as String)]);
      for (final frame in recording.frames) {
        await connector.channels.single.receive(frame.text);
      }
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      final expected = [
        for (final frame in recording.frames) ...JdLiveDanmakuProtocol.decode(frame.text, liveId: _live).messages,
      ];
      expect(_messages(events).map(_key), expected.map(_key));
      expect(_chats(events), ['多重', '老铁，您说的“多重”是指多重优惠还是多重款式呢？']);
      expect(connector.channels.single.sent, isEmpty);
      expect(http.requests, hasLength(1));
      await connection.close();
    });

    test(
      'S07-ended replayed: the end closes the connection; later frames and the idle close are not reported',
      () async {
        final recording = _recording('S07-ended');
        final http = _Http([_body(recording.answer)]);
        final connector = _Connector();
        final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(const JdLiveDanmakuArgs(liveId: _ended));
        final end = recording.frames.indexWhere((frame) => frame.text.contains('stop_live_broadcast'));
        expect(end, greaterThan(0));
        expect(end, lessThan(recording.frames.length - 1), reason: 'frames came after the end');
        for (final frame in recording.frames) {
          await connector.channels.single.receive(frame.text);
        }
        expect(events.last, const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended'));
        expect(connection.status, DanmakuStatus.closed);
        final expected = [
          for (final frame in recording.frames.take(end))
            ...JdLiveDanmakuProtocol.decode(frame.text, liveId: _ended).messages,
        ];
        expect(_messages(events).map(_key), expected.map(_key));
        expect(connector.channels.single.closed, isTrue);
        await connector.channels.single.incoming.close();
        await _wait(const Duration(milliseconds: 30));
        expect(events.last, isA<DanmakuClosed>());
        expect(http.requests, hasLength(1), reason: 'no reconnect after the end');
        final lines = _lines('S07-ended');
        expect(lines.last.record, containsPair('code', 1006), reason: 'the server closed 180 s after the last frame');
        expect((lines.last.record['t']! as int) - (lines[lines.length - 2].record['t']! as int), closeTo(180000, 100));
      },
    );
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = JdLiveDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 20));
      expect(policy.inactivityTimeout, const Duration(seconds: 200));
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(JdLiveDanmakuProtocol.silenceTimeout, greaterThan(JdLiveDanmakuProtocol.serverIdleTimeout));
      expect(JdLiveDanmakuProtocol.statisticsInterval, lessThan(JdLiveDanmakuProtocol.serverIdleTimeout));
      final connection = JdLiveDanmakuConnection(http: _Http([_answer(1)]));
      expect(connection.heartbeatInterval, const Duration(seconds: 20));
      expect(connection.status, DanmakuStatus.idle);
      final registry = DanmakuRegistry({
        SiteIds.jdLive: () => JdLiveDanmakuConnection(http: _Http([_answer(1)])),
      });
      expect(registry.supports('JDLive'), isTrue);
      expect(registry.connectionFor('jdlive'), isA<JdLiveDanmakuConnection>());
    });

    test(
      'handshake: liveauth for the broadcast at the clock, then its socket with the headers; open is ready',
      () async {
        final http = _Http([_answer(1)]);
        final connector = _Connector();
        const route = HttpProxyRoute('127.0.0.1', 7897);
        final connection = JdLiveDanmakuConnection(
          http: http,
          connector: connector.call,
          proxy: const FixedProxyPolicy(perSite: {SiteIds.jdLive: route}),
          policy: _quiet,
          now: () => _now,
          random: Random(3),
        );
        final events = _record(connection);
        await connection.connect(const JdLiveDanmakuArgs(liveId: ' $_live '));
        final request = http.requests.single;
        expect(request.url, JdLiveDanmakuProtocol.authUrl);
        expect(request.timeout, const Duration(seconds: 10));
        final expected = JdLiveDanmakuProtocol.request(_live, now: _now, nonce: JdLiveDanmakuProtocol.nonce(Random(3)));
        expect(request.body, expected.body, reason: 'the clock and the nonce as injected');
        expect(request.headers, expected.headers);
        expect(connector.endpoints, [_socket(1)]);
        expect(connector.headers.single, JdLiveDanmakuProtocol.socketHeaders);
        expect(connector.routes.single, route);
        expect(events, [const DanmakuReady()]);
        expect(connection.isConnected, isTrue);
        await connector.channels.single.receive(_stats());
        await connector.channels.single.receive(_chat(content: 'hi'));
        expect(_chats(events), ['hi']);
        expect(_messages(events).where((m) => m.type == LiveMessageType.online), hasLength(2));
        await connection.close();
      },
    );

    test('nothing is ever sent: not at the heartbeat ticks, not for a manual heartbeat', () async {
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(
        http: _Http([_answer(1)]),
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 5),
          inactivityTimeout: Duration(seconds: 30),
        ),
      );
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _wait(const Duration(milliseconds: 60));
      connection.heartbeat();
      expect(connector.channels.single.sent, isEmpty);
      expect(connector.endpoints, hasLength(1));
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('a dropped socket reconnects with a new token and is ready again', () async {
      final http = _Http([_answer(1), _answer(2)]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await connector.channels.first.incoming.close();
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(connector.endpoints, [_socket(1), _socket(2)]);
      expect(http.requests, hasLength(2));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connector.channels.last.receive(_chat(content: 'after'));
      expect(_chats(events), ['after']);
      await connection.close();
    });

    test('a failed or refused liveauth is a failed handshake: reported once, retried, then joined', () async {
      final http = _Http([
        const TransportFailure(SiteIds.jdLive, TransportReason.connect, 'refused'),
        _body('', status: 403),
        _body('{"code":1,"msg":"鉴权失败","data":{"error":"解密失败!"}}'),
        _answer(4),
      ]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await _until(() => connection.isConnected);
      expect(http.requests, hasLength(4));
      expect(connector.endpoints, [_socket(4)]);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('a refused socket handshake (a used token) asks for a new token', () async {
      final http = _Http([_answer(1), _answer(2)]);
      final connector = _Connector(failures: 1);
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _until(() => connection.isConnected);
      expect(connector.endpoints, [_socket(1), _socket(2)]);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('failures in a row end the connection; the detail names no token', () async {
      final http = _Http([_answer(1)]);
      final connector = _Connector(
        failures: 100,
        error: WebSocketException(
          "Connection to '${_socket(1).replace(scheme: 'https', port: 0)}#' was not upgraded to websocket, "
          'HTTP status code: 200',
        ),
      );
      final connection = JdLiveDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 2,
        ),
      );
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      final closed = events.whereType<DanmakuClosed>().single;
      expect(closed.reason, DanmakuCloseReason.reconnectsExhausted);
      expect(closed.detail, contains('HTTP status code: 200'));
      expect(closed.detail, contains('token=…'));
      expect(closed.detail, isNot(contains(_token(1))));
      expect(http.requests, hasLength(3));
      expect(connection.status, DanmakuStatus.closed);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
    });

    test('refusals in a row end the connection with the refusal', () async {
      final http = _Http([_body('{"code":1,"msg":"鉴权失败","data":{"error":"解密失败!"}}')]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 1,
        ),
      );
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(events.last, isA<DanmakuClosed>().having((e) => e.detail, 'detail', contains('解密失败')));
      expect(connector.endpoints, isEmpty);
      expect(http.requests, hasLength(2));
    });

    test('a silent socket is replaced with a new token; statistics keep it', () async {
      final http = _Http([_answer(1), _answer(2)]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(
        http: http,
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          // Wide enough that a loaded machine never misses a statistics frame.
          inactivityTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      // Statistics every 25 ms for 600 ms: the socket stays.
      for (var i = 0; i < 24; i++) {
        await connector.channels.single.receive(_stats());
        await _wait(const Duration(milliseconds: 25));
      }
      expect(connector.channels, hasLength(1));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      // Then silence: replaced, with a new token.
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.endpoints.last, _socket(2));
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
      await connection.close();
    });

    test('the end of the broadcast ends the connection; its later frames are not reported', () async {
      final http = _Http([_answer(1)]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await connector.channels.single.receive(jsonEncode(_event('stop_live_broadcast', content: null, group: 1)));
      expect(connection.status, DanmakuStatus.connected, reason: "another group's end");
      await connector.channels.single.receive(jsonEncode(_event('stop_live_broadcast', content: null)));
      await connector.channels.single.receive(_chat(content: 'late'));
      expect(events, [
        const DanmakuReady(),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended'),
      ]);
      expect(connector.channels.single.closed, isTrue);
      await _wait(const Duration(milliseconds: 30));
      expect(http.requests, hasLength(1));
    });

    test(
      'a masked answer: binary frames of that socket are unmasked with its key, the next socket with its own',
      () async {
        final http = _Http([_answer(1, mask: 'k3y'), _answer(2, mask: 'Zq')]);
        final connector = _Connector();
        final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
        await connector.channels.single.receive(_masked(_chat(content: 'one'), 'k3y'));
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
        await connector.channels.last.receive(_masked(_chat(content: 'old key'), 'k3y'));
        await connector.channels.last.receive(_masked(_chat(content: 'two'), 'Zq'));
        await connector.channels.last.receive(_chat(content: 'text'));
        expect(_chats(events), ['one', 'two', 'text']);
        await connection.close();
      },
    );

    test('arguments without a broadcast id end at once, without a request', () async {
      for (final id in ['', ' ', '0123456', 'abc', '1234', '48399381x']) {
        final http = _Http([_answer(1)]);
        final connector = _Connector();
        final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
        final events = _record(connection);
        await connection.connect(JdLiveDanmakuArgs(liveId: id));
        expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast')], reason: id);
        expect(http.requests, isEmpty);
        expect(connector.endpoints, isEmpty);
      }
      final connection = JdLiveDanmakuConnection(http: _Http([_answer(1)]));
      await expectLater(connection.connect('not JD args'), throwsArgumentError);
    });

    test('closing during liveauth cancels it: no socket and no event', () async {
      final pending = Completer<LiveResponse>();
      final http = _Http([pending]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      final connecting = connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      pending.complete(_answer(1));
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('after close nothing is reported; another connect replaces the broadcast', () async {
      final http = _Http([_answer(1), _answer(2)]);
      final connector = _Connector();
      final connection = JdLiveDanmakuConnection(http: http, connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await connection.connect(const JdLiveDanmakuArgs(liveId: _ended));
      expect(connector.channels.first.closed, isTrue);
      expect(http.requests.first.cancel!.isCancelled, isTrue);
      final body = Uri.splitQueryString(utf8.decode(http.requests.last.body!))['body']!;
      final content = (jsonDecode(body) as Map)['content']! as String;
      final plain = utf8.decode(
        Aes128Cbc.decrypt(
          base64.decode(content),
          key: utf8.encode(JdLiveDanmakuProtocol.secretKey),
          iv: utf8.encode(JdLiveDanmakuProtocol.iv),
        ),
      );
      expect((jsonDecode(plain) as Map)['groupId'], _ended);
      await connector.channels.first.receive(_chat(content: 'old room'));
      await connector.channels.last.receive(_chat(content: 'old group'));
      await connector.channels.last.receive(_chat(content: 'new room', group: _ended));
      expect(_chats(events), ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(_chat(content: 'late', group: _ended));
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(http.requests, hasLength(2));
    });

    test('a real local server: the form POST, the handshake headers, statistics and chat', () async {
      final posts = <Map<String, String>>[];
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
        if (request.uri.path == '/api') {
          posts.add({
            'method': request.method,
            'type': '${request.headers.contentType}',
            'origin': request.headers.value('origin') ?? '',
            'referer': request.headers.value('referer') ?? '',
            ...Uri.splitQueryString(await utf8.decodeStream(request)),
          });
          request.response
            ..headers.contentType = ContentType.json
            ..write(_answer(posts.length).text);
          await request.response.close();
          return;
        }
        handshake['query'] = request.uri.query;
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket
          ..add(_stats())
          ..add(_chat(content: '多重'));
      });
      final http = _Local(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = JdLiveDanmakuConnection(
        http: http,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.host, 'live-ws4.jd.com');
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
      await connection.connect(const JdLiveDanmakuArgs(liveId: _live));
      await _until(() => _chats(events).isNotEmpty);
      final post = posts.single;
      expect((post['method'], post['type']), ('POST', 'application/x-www-form-urlencoded'));
      expect((post['origin'], post['referer']), ('https://lives.jd.com', 'https://lives.jd.com/'));
      expect((post['loginType'], post['appid'], post['functionId']), ('2', 'h5-live', 'liveauth'));
      expect(handshake['query'], 'token=${_token(1)}');
      expect(handshake['origin'], 'https://lives.jd.com');
      // dart:io's handshake keeps its own user agent in front of the one given.
      expect(handshake['user-agent'], endsWith(JdLiveApi.userAgent));
      expect(events.first, const DanmakuReady());
      expect(_chats(events), ['多重']);
      expect(_messages(events).where((m) => m.type == LiveMessageType.online).map((m) => _audience(m).value), [
        3,
        1745,
      ]);
      await connection.close();
    });
  });
}

/// The comparable part of a message.
String _key(LiveMessage message) => [
  message.type.name,
  message.userName,
  message.userId,
  message.message,
  message.messageId,
  message.sentAt?.millisecondsSinceEpoch,
  if (message.data case final LiveAudienceUpdate update) '${update.kind.name}=${update.value}',
].join('|');

int? _audienceOf(LiveMessage message, LiveAudienceMetricKind kind) => switch (message.data) {
  LiveAudienceUpdate(kind: final k, :final value) when k == kind => value,
  _ => null,
};

/// Sends the liveauth requests to a local server.
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
      followRedirects: request.followRedirects,
      timeout: request.timeout,
      cancel: request.cancel,
    ),
  );

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
