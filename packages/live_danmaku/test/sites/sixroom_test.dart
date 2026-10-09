import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/sixroom/danmaku/S07-live';

/// The recording (S07-live): the `getChat.php` answer, then the socket's
/// text frames, with their line numbers and directions.
final List<({int line, bool incoming, String? url, String text})> _recording = [
  for (final (index, line) in File('$_root/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 'text': final String text} && final Map<String, Object?> frame)
      (line: index + 1, incoming: dir == 'in', url: frame['url'] as String?, text: text),
];

final Map<String, Object?> _meta = jsonDecode(File('$_root/meta.json').readAsStringSync()) as Map<String, Object?>;

/// What the room page's scripts make of the recording (page_expected.py).
final Map<String, Object?> _page =
    (jsonDecode(File('$_root/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

/// The recorded room and broadcaster.
const _args = SixRoomDanmakuArgs(roomId: '80518', userId: '57401078');

/// The recorded (scrubbed) guest id.
const int _recordedGuest = 1855555555;

/// No heartbeat, watchdog or join timer and a short backoff: only what the
/// test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

const String _loginSuccess = '47\r\nenc=no\r\ncommand=result\r\ncontent=login.success\r\n';
const String _loginFailed = '46\r\nenc=no\r\ncommand=result\r\ncontent=login.failed\r\n';
const String _sendSuccess = '46\r\nenc=no\r\ncommand=result\r\ncontent=send.success\r\n';

/// A `receivemessage` frame of [root] as the server writes it: raw DEFLATE at
/// `ZLibEncoder`'s default level 6 in the site's Base64 ([deflated]) or plain
/// Base64, after its length line.
String _frame(Object? root, {bool deflated = true}) {
  final json = utf8.encode(root is String ? root : jsonEncode(root));
  final content = deflated
      ? base64
            .encode(ZLibEncoder(raw: true).convert(json))
            .replaceAll('+', '(')
            .replaceAll('/', ')')
            .replaceAll('=', '@')
      : base64.encode(json);
  final rest = 'enc=${deflated ? 'yes' : 'no'}\r\ncommand=receivemessage\r\ncontent=$content\r\n';
  return '${utf8.encode(rest).length}\r\n$rest';
}

/// A `001` frame carrying [content].
String _message(Map<String, Object?> content, {bool deflated = true}) =>
    _frame({'flag': '001', 'content': content}, deflated: deflated);

/// A public chat message as the server sends one alone.
Map<String, Object?> _chat({
  Object? from = '观众1',
  Object? content = 'hello',
  Object? fid = '10000001',
  Object? tm = 1790771511,
  Object? supremeMystery = 0,
  Object? picEmoji = const {'pic': '', 'ios_height': 0, 'pc_height': 0, 'ad_height': 0},
  String typeId = '101',
  Map<String, Object?> extra = const {'limitLevel': '-1', 'newLimitLevel': '-1', 'starLimitLevel': '-1'},
}) => {
  'typeID': int.parse(typeId),
  'tm': ?tm,
  'fid': ?fid,
  'frid': '200001',
  'from': ?from,
  'to': '',
  'toid': '',
  'torid': '',
  'content': ?content,
  'supremeMystery': ?supremeMystery,
  'picEmoji': ?picEmoji,
  'danmaku': 1,
  ...extra,
};

/// A getChat.php answer listing [servers].
LiveResponse _servers(List<Object?> servers, {int status = 200}) =>
    _body(jsonEncode({'a': <Object?>[], 'b': <Object?>[], 'websock': servers}), status: status);

LiveResponse _body(String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: SixRoomDanmakuProtocol.serversUrl);

/// The four servers of a room on [port], answer [round].
List<String> _four({int port = 5390, int round = 1}) => [
  for (final host in ['snbjh2', 'snbjg1', 'snbjh1', 'snbjg2']) 'r$round$host.6rooms.com:$port',
];

/// Answers `getChat.php` from a script: each entry is a response, an error to
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
          (_) => throw const TransportFailure(SiteIds.sixRoom, TransportReason.cancelled),
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
/// first handshakes throw.
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

/// A [Random] whose `nextInt` answers [value] (clamped to the bound).
final class _Fixed implements Random {
  new(this.value);

  final int value;
  int calls = 0;

  @override
  int nextInt(int max) {
    calls++;
    return value.clamp(0, max - 1);
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
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

List<String> _texts(List<DanmakuEvent> events) => [for (final message in _messages(events)) message.message];

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

/// A chat line as page_expected.py projects it.
Map<String, Object?> _project(LiveMessage message) => {
  'userName': message.userName,
  'userId': message.userId,
  'text': message.message,
  'tm': message.sentAt == null ? null : message.sentAt!.millisecondsSinceEpoch ~/ 1000,
};

/// A frame's result as page_expected.py projects it.
Map<String, Object?> _projectFrame(int line, SixRoomDanmakuFrame frame) => {
  'line': line,
  if (frame.joined) 'joined': true,
  if (frame.loginFailed) 'loginFailed': true,
  if (frame.refusal case final refusal?) 'refusal': refusal.split(':').first.replaceFirst('flag ', ''),
  if (frame.messages.isNotEmpty) 'chats': [for (final message in frame.messages) _project(message)],
};

SixRoomDanmakuConnection _connection(
  _Http http,
  _Connector connector, {
  DanmakuSocketPolicy policy = _quiet,
  Random? random,
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) => SixRoomDanmakuConnection(
  http: http,
  connector: connector.call,
  policy: policy,
  random: random ?? _Fixed(55555555),
  proxy: proxy,
);

void main() {
  group('protocol', () {
    test('addresses, headers, frames and timing', () {
      expect(SixRoomDanmakuProtocol.serversUrl, Uri.parse('https://v.6.cn/room/getChat.php'));
      expect(SixRoomDanmakuProtocol.heartbeatInterval, const Duration(seconds: 16));
      expect(SixRoomDanmakuProtocol.joinTimeout, const Duration(seconds: 6));
      expect(SixRoomDanmakuProtocol.maxRefusals, 3);
      expect(SixRoomDanmakuProtocol.socketHeaders, {'origin': 'https://v.6.cn', 'user-agent': SixRoomApi.userAgent});
      expect(SixRoomDanmakuProtocol.heartbeat, 'command=sendmessage\r\ncontent=y8vPLwAA\r\n');
      // The heartbeat's content is `noop`, deflated in the site's Base64.
      final noop = SixRoomDanmakuProtocol.payload('y8vPLwAA', deflated: true);
      expect(noop, 'noop');
      expect(
        SixRoomDanmakuProtocol.login(1812345678, '57401078'),
        'command=login\r\nuid=1812345678\r\nencpass=\r\nroomid=57401078\r\n',
      );
      expect(SixRoomDanmakuProtocol.guestId(_Fixed(0)), 1800000000);
      expect(SixRoomDanmakuProtocol.guestId(_Fixed(1 << 40)), 1899999999);
      final random = Random(7);
      for (var i = 0; i < 1000; i++) {
        expect(SixRoomDanmakuProtocol.guestId(random), inInclusiveRange(1800000000, 1899999999));
      }
      expect(SixRoomDanmakuProtocol.stoppingFlags, {
        '101',
        '102',
        '103',
        '104',
        '109',
        '110',
        '111',
        '112',
        '113',
        '114',
        '204',
        '305',
        '306',
      });
    });

    test('the server list request: a GET from the room page, as sixroom, no redirects', () {
      final cancel = CancelToken();
      final request = SixRoomDanmakuProtocol.serverRequest(_args, timeout: const Duration(seconds: 3), cancel: cancel);
      expect(request.site, SiteIds.sixRoom);
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://v.6.cn/room/getChat.php?rid=57401078'));
      expect(request.headers, {
        'user-agent': SixRoomApi.userAgent,
        'accept': 'application/json, text/javascript, */*; q=0.01',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
        'referer': 'https://v.6.cn/80518',
        'x-requested-with': 'XMLHttpRequest',
      });
      expect(request.body, isNull);
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 3));
      expect(request.cancel, same(cancel));
    });

    test('server list answers: hosts on 6rooms.com in order, each once; anything else throws', () {
      expect(SixRoomDanmakuProtocol.servers(_servers(_four())), [
        for (final server in _four()) Uri.parse('wss://$server'),
      ]);
      expect(
        SixRoomDanmakuProtocol.servers(
          _servers([
            ' SNBJH2.6rooms.com:5390 ',
            'snbjh2.6rooms.com:5390',
            '6rooms.com:1',
            'evil6rooms.com:5390',
            '6rooms.com.example.com:5390',
            'snbjh1.6rooms.com:0',
            'snbjh1.6rooms.com:65536',
            'snbjh1.6rooms.com:99999',
            'wss://snbjh1.6rooms.com:5390',
            'snbjh1.6rooms.com:5390:1',
            'snbjh1.6rooms.com',
            '-a.6rooms.com:5390',
            'a b.6rooms.com:5390',
            'x.6rooms.com:65535',
            5390,
            null,
            const ['snbjg1.6rooms.com:5390'],
          ]),
        ),
        [
          Uri.parse('wss://snbjh2.6rooms.com:5390'),
          Uri.parse('wss://6rooms.com:1'),
          Uri.parse('wss://x.6rooms.com:65535'),
        ],
      );
      Matcher fails(String text) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(text)));
      expect(() => SixRoomDanmakuProtocol.servers(_servers(_four(), status: 503)), fails('HTTP 503'));
      expect(() => SixRoomDanmakuProtocol.servers(_body('<html>')), fails('no JSON'));
      for (final body in [
        '[]',
        '{}',
        '{"websock":[]}',
        '{"websock":"snbjh2.6rooms.com:5390"}',
        '{"websock":["example.com:5390"]}',
        'null',
      ]) {
        expect(() => SixRoomDanmakuProtocol.servers(_body(body)), fails('no chat server'), reason: body);
      }
    });

    test('arguments: a room number and a user id, trimmed', () {
      final checked = SixRoomDanmakuProtocol.checked(
        const SixRoomDanmakuArgs(roomId: ' 80518 ', userId: ' 57401078 '),
      )!;
      expect((checked.roomId, checked.userId), ('80518', '57401078'));
      for (final args in const [
        SixRoomDanmakuArgs(roomId: '', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: '0', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: '8', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: '080518', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: 'https://v.6.cn/80518', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: '1234567890123', userId: '57401078'),
        SixRoomDanmakuArgs(roomId: '80518', userId: ''),
        SixRoomDanmakuArgs(roomId: '80518', userId: '0'),
        SixRoomDanmakuArgs(roomId: '80518', userId: 'abc'),
        SixRoomDanmakuArgs(roomId: '80518', userId: '57401078\r\ncommand=x'),
        SixRoomDanmakuArgs(roomId: '80518', userId: '12345678901234'),
      ]) {
        expect(SixRoomDanmakuProtocol.checked(args), isNull, reason: '$args');
      }
    });

    test('frame fields: the length line skipped, split at the first =, the last value kept', () {
      expect(SixRoomDanmakuProtocol.fields(_loginSuccess), {
        'enc': 'no',
        'command': 'result',
        'content': 'login.success',
      });
      expect(SixRoomDanmakuProtocol.fields('x\r\n=y\r\na=b=c\r\na=d\r\nk=\r\n\r\n'), {'a': 'd', 'k': ''});
      expect(SixRoomDanmakuProtocol.fields('a=b=c'), {'a': 'b=c'});
      expect(SixRoomDanmakuProtocol.fields(''), isEmpty);
    });

    test('payloads: the site alphabet deflated, plain Base64 with or without padding, broken ones throw', () {
      final deflated = SixRoomDanmakuProtocol.fields(_message({'typeID': 416, 'content': 1}))['content']!;
      expect(jsonDecode(SixRoomDanmakuProtocol.payload(deflated, deflated: true)), {
        'flag': '001',
        'content': {'typeID': 416, 'content': 1},
      });
      final plain = base64.encode(utf8.encode('{"flag":"001"}'));
      expect(plain, endsWith('='));
      expect(SixRoomDanmakuProtocol.payload(plain, deflated: false), '{"flag":"001"}');
      expect(SixRoomDanmakuProtocol.payload(plain.replaceAll('=', ''), deflated: false), '{"flag":"001"}');
      expect(SixRoomDanmakuProtocol.payload(plain.replaceAll('=', '@'), deflated: false), '{"flag":"001"}');
      expect(() => SixRoomDanmakuProtocol.payload('*not base64*', deflated: false), throwsFormatException);
      expect(() => SixRoomDanmakuProtocol.payload('AQIDBAU@', deflated: true), throwsFormatException);
      // A message that inflates past the limit is refused before it is all in memory.
      final bomb = base64
          .encode(ZLibEncoder(raw: true).convert(List<int>.filled(SixRoomDanmakuProtocol.maxInflatedBytes + 1, 32)))
          .replaceAll('+', '(')
          .replaceAll('/', ')')
          .replaceAll('=', '@');
      expect(
        () => SixRoomDanmakuProtocol.payload(bomb, deflated: true),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('exceeds'))),
      );
      expect(SixRoomDanmakuProtocol.payload(base64.encode([0xE5, 0x85]), deflated: false), '�');
    });

    test('frames: login results, other results, error flags, broken frames', () {
      expect(SixRoomDanmakuProtocol.decode(_loginSuccess).joined, isTrue);
      expect(SixRoomDanmakuProtocol.decode(utf8.encode(_loginSuccess)).joined, isTrue);
      expect(SixRoomDanmakuProtocol.decode(_loginFailed).loginFailed, isTrue);
      expect(SixRoomDanmakuProtocol.decode('enc=no\r\ncommand=result\r\ncontent= login.success \r\n').joined, isTrue);
      for (final frame in <Object?>[
        _sendSuccess,
        '47\r\nenc=no\r\ncommand=result\r\ncontent=login.successful\r\n',
        'command=result\r\n',
        'command=login\r\ncontent=login.success\r\n',
        'content=login.success\r\n',
        _frame({'flag': '205', 'content': 'bbbbb'}),
        _frame({'flag': '201', 'content': '发言过快！'}),
        _frame({'flag': '213', 'content': ''}),
        _frame({'flag': 1, 'content': 'x'}),
        _frame({'content': _chat()}),
        _frame('not json'),
        _frame('[1,2]'),
        _frame('"text"'),
        'enc=yes\r\ncommand=receivemessage\r\ncontent=!!!\r\n',
        'enc=yes\r\ncommand=receivemessage\r\ncontent=AQIDBAU@\r\n',
        'enc=no\r\ncommand=receivemessage\r\n',
        '',
        null,
        42,
        [0xFF, 0xFE],
      ]) {
        final decoded = SixRoomDanmakuProtocol.decode(frame);
        expect(
          (decoded.joined, decoded.loginFailed, decoded.refusal, decoded.messages.length),
          (false, false, null, 0),
          reason: '$frame',
        );
      }
      expect(SixRoomDanmakuProtocol.decode(_frame({'flag': '102', 'content': '本房间人数已满'})).refusal, 'flag 102: 本房间人数已满');
      expect(SixRoomDanmakuProtocol.decode(_frame({'flag': '204'})).refusal, 'flag 204');
      expect(SixRoomDanmakuProtocol.decode(_frame({'flag': 111, 'content': 7})).refusal, 'flag 111: 7');
      for (final flag in SixRoomDanmakuProtocol.stoppingFlags) {
        expect(SixRoomDanmakuProtocol.decode(_frame({'flag': flag, 'content': ''})).refusal, 'flag $flag');
      }
      // A chat frame sent plainly, and as bytes.
      final plain = _message(_chat(content: 'plain'), deflated: false);
      expect(SixRoomDanmakuProtocol.decode(plain).messages.single.message, 'plain');
      expect(SixRoomDanmakuProtocol.decode(utf8.encode(plain)).messages.single.message, 'plain');
    });

    test('a public chat line: name, id, text, time; no message id; the addressee is not shown', () {
      final message = SixRoomDanmakuProtocol.chat({..._chat(content: '  厨师能吃泡面/狂笑  '), 'to': '观众2', 'toid': 10000002})!;
      expect(message.type, LiveMessageType.chat);
      expect(message.userName, '观众1');
      expect(message.userId, '10000001');
      expect(message.message, '厨师能吃泡面/狂笑');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771511000));
      expect(message.messageId, isEmpty);
      expect(message.color, LiveMessageColor.white);
      expect(message.userLevel, isEmpty);
      expect(message.isLocal, isFalse);
    });

    test('public chat boundaries: names, mystery senders, pictures, references, ids and times', () {
      LiveMessage? of(Map<String, Object?> message) => SixRoomDanmakuProtocol.chat(message);
      for (final from in [null, '', '   ']) {
        expect(of(_chat(from: from)), isNull, reason: '$from');
      }
      expect(of(_chat(from: 7))!.userName, '7');
      expect(of(_chat(from: ' 名字 '))!.userName, '名字');
      final mystery = of(_chat(from: '', supremeMystery: 1))!;
      expect((mystery.userName, mystery.message), ('', 'hello'));
      expect(of(_chat(from: '神秘人', supremeMystery: '1'))!.userName, '神秘人');
      expect(of(_chat(from: '', supremeMystery: 2)), isNull);
      // A picture message: the page shows the image, whatever the text.
      final picture = {'pic': 'https://vi0.6rooms.com/x.png', 'ios_height': 1};
      expect(of(_chat(picEmoji: picture, content: 'ignored'))!.message, '[AI表情]');
      expect(of(_chat(picEmoji: picture, content: null))!.message, '[AI表情]');
      expect(of(_chat(picEmoji: const {'pic': ' '}, content: 'text'))!.message, 'text');
      expect(of(_chat(picEmoji: 'pic', content: 'text'))!.message, 'text');
      // The page reads &amp; as & and then lets the browser decode references.
      expect(
        of(_chat(content: '&lt;3 &amp;lt;3 &quot;q&quot; &#39;s&#39; &#x1F600; a&amp;b &unknown;'))!.message,
        '<3 <3 "q" \'s\' 😀 a&b &unknown;',
      );
      expect(of(_chat(content: 123))!.message, '123');
      for (final content in [
        null,
        '',
        '   ',
        1.5,
        const ['x'],
        const {'x': 1},
        true,
      ]) {
        expect(of(_chat(content: content)), isNull, reason: '$content');
      }
      expect(of(_chat(fid: 10000001))!.userId, '10000001');
      expect(of(_chat(fid: null))!.userId, '');
      expect(of(_chat(fid: 1.5))!.userId, '');
      for (final tm in [0, -1, 8640000000001, 'abc', null, 1.5]) {
        expect(of(_chat(tm: tm))!.sentAt, isNull, reason: '$tm');
      }
      expect(of(_chat(tm: '1790771511'))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771511000));
      expect(of(_chat(tm: 8640000000000))!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
    });

    test('messages: 101 alone, 110 and 1413 lists, 108 fly-screen (a super chat, D07.2), other types, nesting and '
        'guest filters', () {
      List<String> texts(Object? message) => [for (final m in SixRoomDanmakuProtocol.messages(message)) m.message];
      expect(texts(_chat(content: 'one')), ['one']);
      expect(texts({..._chat(content: 'one'), 'typeID': '101'}), ['one']);
      // 110: every entry is public chat, whatever its own type.
      expect(
        texts({
          'typeID': 110,
          'content': [
            _chat(content: 'a'),
            {..._chat(content: 'b'), 'typeID': 123},
            'x',
            _chat(from: '', content: 'hidden'),
            _chat(content: 'c'),
          ],
        }),
        ['a', 'b', 'c'],
      );
      // 1413: every entry by its own type.
      expect(
        texts({
          'typeID': 1413,
          'content': [
            {
              'typeID': 123,
              'tm': 1790771511,
              'content': {'msg': '来了'},
            },
            _chat(content: 'a'),
            {'typeID': 201, 'from': '观众2', 'content': 'gift'},
            null,
            {
              'typeID': 1413,
              'content': [_chat(content: 'nested')],
            },
            _chat(content: 'b'),
          ],
        }),
        ['a', 'nested', 'b'],
      );
      Map<String, Object?> nest(int depth) => depth == 0
          ? _chat(content: 'deep')
          : {
              'typeID': 1413,
              'content': [nest(depth - 1)],
            };
      expect(texts(nest(SixRoomDanmakuProtocol.maxDepth)), ['deep']);
      expect(texts(nest(SixRoomDanmakuProtocol.maxDepth + 1)), isEmpty);
      // 108: the fly-screen message.
      final fly = SixRoomDanmakuProtocol.messages({
        'typeID': 108,
        'from': '观众3',
        'fid': '10000003',
        'content': '主播生日快乐 &amp; 天天开心',
        'fpic': 'https://vi0.6rooms.com/x.jpg',
        'ftype': 0,
        'tm': 1790771600,
      }).single;
      expect((fly.userName, fly.userId, fly.message), ('观众3', '10000003', '主播生日快乐 & 天天开心'));
      expect(fly.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771600000));
      // D07.2: a super chat of 1000 six coins (the room page's price), a
      // minute from its time; no avatar or colours (the page has its own).
      expect(fly.type, LiveMessageType.superChat);
      final paid = fly.data! as LiveSuperChatMessage;
      expect(
        (paid.userName, paid.message, paid.price, paid.unit, paid.priceText, paid.face),
        ('观众3', '主播生日快乐 & 天天开心', 1000, LiveGiftUnit.sixCoin, '', ''),
      );
      expect(SixRoomDanmakuProtocol.flyScreenPrice, 1000);
      expect(paid.startTime, DateTime.fromMillisecondsSinceEpoch(1790771600000));
      expect(paid.endTime.difference(paid.startTime), const Duration(minutes: 1));
      expect((paid.backgroundColor, paid.backgroundBottomColor), ('', ''));
      // Without a time it starts when it came; in a batch it is read too.
      final now = DateTime(2026, 10, 9, 20);
      final untimed = SixRoomDanmakuProtocol.fly({'typeID': 108, 'from': '观众4', 'content': '晚上好'}, now: now)!;
      expect((untimed.data! as LiveSuperChatMessage).startTime, now);
      expect(
        SixRoomDanmakuProtocol.messages({
          'typeID': 1413,
          'content': [
            {'typeID': 108, 'from': '观众5', 'content': '飞'},
          ],
        }).single.type,
        LiveMessageType.superChat,
      );
      expect(texts({'typeID': 108, 'content': '无名'}), ['无名']);
      expect(texts({'typeID': 108, 'from': '观众3', 'content': ' '}), isEmpty);
      for (final type in [102, 107, 111, 123, 153, 201, 413, 1570, 4185, 865, 5100, '', null]) {
        expect(texts({..._chat(content: 'x'), 'typeID': type}), isEmpty, reason: '$type');
      }
      for (final other in [null, 'text', 1, const <Object?>[]]) {
        expect(texts(other), isEmpty);
      }
      expect(texts({'typeID': 1413, 'content': 'x'}), isEmpty);
      expect(texts({'typeID': 110}), isEmpty);
      // The client mask: shown when unset or with the PC bit.
      for (final (cli, shown) in [
        (null, true),
        (0, true),
        ('', true),
        (false, true),
        (1, true),
        (3, true),
        ('1', true),
        (true, true),
        (2, false),
        (4, false),
        ('0', false),
        ('2', false),
        ('pc', false),
        (const <Object?>[], false),
      ]) {
        expect(texts({..._chat(), 'cli': cli}), shown ? ['hello'] : isEmpty, reason: '$cli');
      }
      // Levels a guest does not have.
      for (final (key, level, shown) in [
        ('newLimitLevel', '-1', true),
        ('newLimitLevel', -1, true),
        ('newLimitLevel', '0', false),
        ('newLimitLevel', 5, false),
        ('newLimitLevel', null, false),
        ('newLimitLevel', 'x', false),
        ('starLimitLevel', '-1', true),
        ('starLimitLevel', null, true),
        ('starLimitLevel', 'x', true),
        ('starLimitLevel', '3', false),
        ('starLimitLevel', 0, false),
      ]) {
        expect(texts({..._chat(extra: const {}), key: level}), shown ? ['hello'] : isEmpty, reason: '$key $level');
      }
      expect(texts(_chat(extra: const {})), ['hello']);
      // A list the guest may not see hides all of it.
      expect(
        texts({
          'typeID': 1413,
          'newLimitLevel': '3',
          'content': [_chat()],
        }),
        isEmpty,
      );
    });
  });

  group('recording (S07-live)', () {
    test('servers, handshake, login and heartbeat are what the page sends, and what was recorded', () async {
      final answer = _recording.first;
      expect(answer.url, 'https://v.6.cn/room/getChat.php?rid=57401078');
      final servers = SixRoomDanmakuProtocol.servers(_body(answer.text));
      expect([for (final server in servers) '$server'], _page['servers']);
      final request = SixRoomDanmakuProtocol.serverRequest(_args);
      final recorded = ((_meta['requests']! as List).single as Map).cast<String, Object?>();
      expect(request.url.toString(), recorded['url']);
      expect(request.headers, recorded['headers']);
      final handshake = ((_meta['handshakes']! as List).single as Map).cast<String, Object?>();
      expect(handshake['url'], '${servers.first}');
      expect(handshake['headers'], SixRoomDanmakuProtocol.socketHeaders);
      expect(SixRoomDanmakuProtocol.login(_recordedGuest, _args.userId), _page['login']);
      expect(SixRoomDanmakuProtocol.heartbeat, _page['heartbeat']);
      expect(SixRoomDanmakuProtocol.heartbeatInterval.inSeconds, _page['heartbeatSeconds']);
      expect(SixRoomDanmakuProtocol.joinTimeout.inSeconds, _page['loginTimeoutSeconds']);
      final sent = [
        for (final frame in _recording)
          if (!frame.incoming) frame.text,
      ];
      expect(sent.first, _page['login']);
      expect(sent.skip(1), everyElement(SixRoomDanmakuProtocol.heartbeat));
      expect(sent, hasLength(13));
    });

    test('every received frame decodes as the room page shows it to a guest', () {
      final frames = (_page['frames']! as List).cast<Map<String, Object?>>();
      final received = [
        for (final frame in _recording.skip(1))
          if (frame.incoming) frame,
      ];
      expect(received, hasLength(frames.length));
      var chats = 0;
      for (final (index, frame) in received.indexed) {
        final decoded = SixRoomDanmakuProtocol.decode(frame.text);
        expect(_projectFrame(frame.line, decoded), frames[index], reason: 'line ${frame.line}');
        chats += decoded.messages.length;
      }
      expect(chats, 12);
    });

    test('the connection replays the recording: one request, one socket, login, ready, 12 chats in order', () async {
      final http = _Http([_body(_recording.first.text)]);
      final connector = _Connector();
      final connection = _connection(http, connector, random: _Fixed(_recordedGuest - 1800000000));
      final events = _record(connection);
      await connection.connect(_args);
      expect(connector.endpoints, [Uri.parse('wss://snbjh2.6rooms.com:5390')]);
      for (final frame in _recording.skip(1)) {
        if (frame.incoming) await connector.channels.single.receive(frame.text);
      }
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      final expected = [
        for (final frame in (_page['frames']! as List).cast<Map<String, Object?>>())
          ...((frame['chats'] as List?) ?? const []).cast<Map<String, Object?>>(),
      ];
      expect([for (final message in _messages(events)) _project(message)], expected);
      // The login at open, the heartbeat at login.success; no timer ran.
      expect(connector.channels.single.sent, [_page['login'], SixRoomDanmakuProtocol.heartbeat]);
      expect(http.requests, hasLength(1));
      await connection.close();
    });
  });

  group('gifts (D07.7, S08-gifts)', () {
    final lines = [
      for (final line in File('../../fixtures/sixroom/danmaku/S08-gifts/frames.jsonl').readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['text']! as String,
    ];

    test('S08: every recorded gift (201) as the chat list writes it', () {
      final frames = [for (final line in lines) SixRoomDanmakuProtocol.decode(line)];
      expect(frames.map((frame) => frame.messages.length), everyElement(1));
      final messages = [for (final frame in frames) frame.messages.single];
      expect(messages.map((m) => m.type), everyElement(LiveMessageType.gift));
      final data = [for (final m in messages) m.data! as LiveGift];
      expect(
        [
          for (final (i, g) in data.indexed)
            (messages[i].userName, g.id, g.name, g.count, g.totalValue, g.unitPrice, g.comboKey, g.comboTotal),
        ],
        [
          ('观众1', '22774', '御风铃', 1, 1000, 1000, '110001013:1791528256567', 1),
          ('观众2', '1736', '无限火力', 1, null, null, '', null),
          ('观众3', '22353', '心动电池', 1, 100, 100, '10003039:1791528881947', 1),
          ('观众3', '22353', '心动电池', 1, 100, 100, '10003039:1791528881947', 2),
          ('观众3', '22353', '心动电池', 1, 100, 100, '10003039:1791528881947', 3),
          ('观众3', '2430', '蓝宝石钻戒', 1, 100, 100, '10003039:1791528894225', 1),
          ('观众3', '2430', '蓝宝石钻戒', 1, 100, 100, '10003039:1791528894225', 2),
          ('观众4', '1419', '喜欢你', 1, null, null, '', null),
          ('神秘人', '22353', '心动电池', 3, 300, 100, '1900000047:1791528172753', 3),
        ],
      );
      expect(data.map((g) => g.unit), everyElement(LiveGiftUnit.sixCoin));
      expect(data.map((g) => g.free), everyElement(isFalse));
      expect(data.map((g) => g.iconUrl), everyElement(isNull), reason: "the table is the page's 8 MB script");
      expect(data.take(7).map((g) => g.receiverName), everyElement('︶薀昕下午播ぃ'));
      final first = messages.first;
      expect(
        (first.userId, first.message, first.messageId, first.sentAt),
        ('110001013', '御风铃 ×1', '', DateTime.fromMillisecondsSinceEpoch(1791528256000)),
      );
      expect(messages[1].messageId, 'D60DFF829C755C8797AE394508F70FDA');
      expect(messages[8].userId, '1900000047');
    });

    test("what is not a gift: a prize without a sender, no item, a fly-screen's purchase; stock gifts; pictures", () {
      Map<String, Object?> gift({Object? fid = '5', Map<String, Object?> content = const {}}) => {
        'typeID': 201,
        'tm': 1791528256,
        'fid': fid,
        'from': '观众',
        'to': '主播',
        'content': {'item': 7, 'num': 2, 'giftCoin': 10, 'itemName': '花&amp;草', ...content},
      };
      List<LiveMessage> read(Map<String, Object?> message) => SixRoomDanmakuProtocol.messages(message);
      expect(read(gift(fid: '')), isEmpty, reason: 'a game prize, written "<to> 参与 <from> 获得…"');
      expect(read(gift(fid: 0)), isEmpty);
      expect(read(gift(content: {'item': ''})), isEmpty);
      expect(read(gift(content: {'item': 106})), isEmpty, reason: '飞屏: its words are the 108 super chat');
      expect(read(gift(content: {'item': '1516'})), isEmpty, reason: '跟风飞屏: its words are the 324 super chat');
      expect(read({...gift(), 'newLimitLevel': 3}), isEmpty, reason: 'hidden from guests');
      expect(
        read(gift()).single.data,
        const LiveGift(
          id: '7',
          name: '花&草',
          count: 2,
          unitPrice: 5,
          totalValue: 10,
          unit: LiveGiftUnit.sixCoin,
          receiverName: '主播',
        ),
      );
      expect((read(gift(content: {'giftCoin': 3})).single.data! as LiveGift).unitPrice, isNull, reason: '3 over 2');
      final combo = read(gift(content: {'isContinue': '1', 'keep': <String, Object?>{}, 'groupnum': 4})).single;
      expect(
        ((combo.data! as LiveGift).comboKey, (combo.data! as LiveGift).comboTotal),
        ('', null),
        reason: 'no tmp_id',
      );
      final picture = read(gift(content: {'aiGiftPic': 'http://vi0.6rooms.com/a.png'})).single.data! as LiveGift;
      expect(picture.iconUrl, Uri.parse('https://vi0.6rooms.com/a.png'));
      // Inside a 1413 list, as most of the recorded ones came.
      expect(
        read({
          'typeID': 1413,
          'content': [gift(), gift(fid: '')],
        }),
        hasLength(1),
      );
    });

    test('324: a follow fly-screen (跟风飞屏) is a super chat of 2000 six coins; followers say nothing', () {
      // Synthetic, as the page's GiftFlyFollow.parse reads it: no 324 came in
      // 15 minutes of five rooms.
      final now = DateTime(2026, 10, 9, 15);
      final follow = SixRoomDanmakuProtocol.followFly({
        'typeID': 324,
        'tm': 1791528300,
        'content': {
          'type': 1,
          'id': 88,
          'uid': 10000007,
          'alias': '观众7',
          'avatar': 'https://vi0.6rooms.com/x.jpg',
          'msg': '主播 &amp; 大家晚上好',
          'countDownTm': 30,
          'isFollow': 0,
        },
      }, now: now)!;
      expect(
        (follow.type, follow.userName, follow.userId, follow.message, follow.messageId),
        (LiveMessageType.superChat, '观众7', '10000007', '主播 & 大家晚上好', 'follow-fly:88'),
      );
      final paid = follow.data! as LiveSuperChatMessage;
      expect((paid.price, paid.unit, paid.messageId), (2000, LiveGiftUnit.sixCoin, 'follow-fly:88'));
      expect(paid.startTime, DateTime.fromMillisecondsSinceEpoch(1791528300000));
      expect(paid.endTime.difference(paid.startTime), SixRoomDanmakuProtocol.flyScreenDuration);
      expect(SixRoomDanmakuProtocol.followFlyScreenPrice, 2000);
      final untimed = SixRoomDanmakuProtocol.followFly({
        'typeID': 324,
        'content': {'type': '1', 'alias': 'a', 'msg': 'hi'},
      }, now: now)!;
      expect(((untimed.data! as LiveSuperChatMessage).startTime, untimed.messageId), (now, ''));
      expect(
        SixRoomDanmakuProtocol.followFly({
          'typeID': 324,
          'content': {'type': 2, 'alias': '观众8', 'uid': 9},
        }),
        isNull,
        reason: 'a viewer who followed: the page only counts them',
      );
      expect(
        SixRoomDanmakuProtocol.followFly({
          'typeID': 324,
          'content': {'type': 1, 'alias': '观众8', 'msg': ' '},
        }),
        isNull,
      );
      expect(
        SixRoomDanmakuProtocol.messages({
          'typeID': '324',
          'content': {'type': 1, 'alias': 'a', 'msg': 'hi'},
        }).single.type,
        LiveMessageType.superChat,
      );
    });

    test('the connection reports the recorded gifts in order', () async {
      final http = _Http([_body(_recording.first.text)]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.receive(_loginSuccess);
      for (final line in lines) {
        await channel.receive(line);
      }
      expect(
        [for (final m in _messages(events)) m.message],
        ['御风铃 ×1', '无限火力 ×1', '心动电池 ×1', '心动电池 ×1', '心动电池 ×1', '蓝宝石钻戒 ×1', '蓝宝石钻戒 ×1', '喜欢你 ×1', '心动电池 ×3'],
      );
      await connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = SixRoomDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 16));
      expect(policy.joinTimeout, const Duration(seconds: 6));
      expect(policy.inactivityTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = SixRoomDanmakuConnection(http: _Http([_servers(_four())]));
      expect(connection.heartbeatInterval, const Duration(seconds: 16));
      expect(connection.status, DanmakuStatus.idle);
      final registry = DanmakuRegistry({
        SiteIds.sixRoom: () => SixRoomDanmakuConnection(http: _Http([_servers(_four())])),
      });
      expect(registry.supports('SixRoom'), isTrue);
      expect(registry.connectionFor('sixroom'), isA<SixRoomDanmakuConnection>());
    });

    test('handshake: the server list, its first server with the headers, the login; login.success is ready', () async {
      final http = _Http([_servers(_four())]);
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final random = _Fixed(12345678);
      final connection = _connection(
        http,
        connector,
        random: random,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.sixRoom: route}),
      );
      final events = _record(connection);
      await connection.connect(_args);
      expect(http.requests.single.url, Uri.parse('https://v.6.cn/room/getChat.php?rid=57401078'));
      expect(http.requests.single.timeout, const Duration(seconds: 10));
      expect(connector.endpoints, [Uri.parse('wss://r1snbjh2.6rooms.com:5390')]);
      expect(connector.headers.single, SixRoomDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      final channel = connector.channels.single;
      expect(channel.sent, ['command=login\r\nuid=1812345678\r\nencpass=\r\nroomid=57401078\r\n']);
      expect(events, isEmpty);
      expect(connection.isConnected, isFalse);
      await channel.receive(_loginSuccess);
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      expect(channel.sent.last, SixRoomDanmakuProtocol.heartbeat);
      await channel.receive(_sendSuccess);
      await channel.receive(_frame({'flag': '205', 'content': 'bbbbb'}));
      await channel.receive(_message(_chat(content: 'hi')));
      await channel.receive(_message({'typeID': 416, 'content': 1790771511}, deflated: false));
      expect(_texts(events), ['hi']);
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      expect(random.calls, 1);
      await connection.close();
    });

    test('heartbeats: the noop every period and on demand', () async {
      final connector = _Connector();
      final connection = _connection(
        _Http([_servers(_four())]),
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 10),
          inactivityTimeout: Duration(seconds: 30),
        ),
      );
      await connection.connect(_args);
      final channel = connector.channels.single;
      await _until(() => channel.sent.length >= 4);
      expect(channel.sent.skip(1), everyElement(SixRoomDanmakuProtocol.heartbeat));
      await connection.close();
      final quiet = _Connector();
      final manual = _connection(_Http([_servers(_four())]), quiet);
      await manual.connect(_args);
      manual.heartbeat();
      expect(quiet.channels.single.sent.last, SixRoomDanmakuProtocol.heartbeat);
      await manual.close();
    });

    test(
      'a dropped socket moves to the next server with the same guest; the list is asked again when used up',
      () async {
        final http = _Http([_servers(_four()), _servers(_four(round: 2))]);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await connection.connect(_args);
        await connector.channels.last.receive(_loginSuccess);
        for (var socket = 2; socket <= 5; socket++) {
          await connector.channels.last.incoming.close();
          await _until(() => connector.channels.length == socket);
          await connector.channels.last.receive(_loginSuccess);
        }
        expect(connector.endpoints, [
          for (final server in [..._four(), _four(round: 2).first]) Uri.parse('wss://$server'),
        ]);
        expect(http.requests, hasLength(2));
        for (final channel in connector.channels) {
          expect(channel.sent.first, SixRoomDanmakuProtocol.login(1855555555, '57401078'));
        }
        expect(events.whereType<DanmakuReady>(), hasLength(5));
        expect(events[1], const DanmakuReconnecting(DanmakuInterruption.disconnected));
        await connector.channels.last.receive(_message(_chat(content: 'after')));
        expect(_texts(events), ['after']);
        await connection.close();
      },
    );

    test('a login that does not come within the limit reconnects to the next server', () async {
      final http = _Http([_servers(_four())]);
      final connector = _Connector();
      final connection = _connection(
        http,
        connector,
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
      expect(connector.endpoints.last, Uri.parse('wss://${_four()[1]}'));
      await connector.channels.last.receive(_loginSuccess);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      // Joined: the limit no longer applies.
      await _wait(const Duration(milliseconds: 1300));
      expect(connector.channels, hasLength(2));
      expect(http.requests, hasLength(1));
      await connection.close();
    });

    test(
      'a refused login reconnects; the fourth in a row ends the connection, a success starts the count again',
      () async {
        final http = _Http([_servers(_four())]);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await connection.connect(_args);
        for (var socket = 1; socket <= 3; socket++) {
          await connector.channels.last.receive(_loginFailed);
          await _until(() => connector.channels.length == socket + 1);
        }
        await connector.channels.last.receive(_loginSuccess);
        expect(events.whereType<DanmakuReady>(), hasLength(1));
        for (var socket = 4; socket <= 6; socket++) {
          await connector.channels.last.receive(_loginFailed);
          await _until(() => connector.channels.length == socket + 1);
        }
        await connector.channels.last.receive(_loginFailed);
        expect(
          events.last,
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: login.failed'),
        );
        expect(connection.status, DanmakuStatus.closed);
        await _wait(const Duration(milliseconds: 30));
        expect(connector.channels, hasLength(7));
        expect(connector.channels.last.closed, isTrue);
      },
    );

    test('a flag on which the page stops ends the connection at once', () async {
      final connector = _Connector();
      final connection = _connection(_Http([_servers(_four())]), connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.receive(_loginSuccess);
      await connector.channels.single.receive(_frame({'flag': '204', 'content': '房间已经被关闭！'}));
      expect(events, [
        const DanmakuReady(),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: flag 204: 房间已经被关闭！'),
      ]);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(1));
      expect(connector.channels.single.closed, isTrue);
    });

    test('a failed server list is a failed handshake: reported once, retried, then joined', () async {
      final http = _Http([
        const TransportFailure(SiteIds.sixRoom, TransportReason.connect, 'refused'),
        _servers(_four(), status: 503),
        _body('[]'),
        _servers(_four(round: 4)),
      ]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await _until(() => connector.channels.isNotEmpty);
      await connector.channels.single.receive(_loginSuccess);
      expect(http.requests, hasLength(4));
      expect(connector.endpoints, [Uri.parse('wss://${_four(round: 4).first}')]);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('failures in a row end the connection with the last one', () async {
      final http = _Http([_body('[]')]);
      final connector = _Connector();
      final connection = _connection(
        http,
        connector,
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
      expect(closed.detail, contains('no chat server'));
      expect(http.requests, hasLength(3));
      expect(connector.endpoints, isEmpty);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
    });

    test('a failed socket handshake moves to the next server without asking again', () async {
      final http = _Http([_servers(_four())]);
      final connector = _Connector(failures: 1);
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connector.channels.isNotEmpty);
      await connector.channels.single.receive(_loginSuccess);
      expect(connector.endpoints, [Uri.parse('wss://${_four()[0]}'), Uri.parse('wss://${_four()[1]}')]);
      expect(http.requests, hasLength(1));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('arguments without a room end at once, without a request', () async {
      final http = _Http([_servers(_four())]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(const SixRoomDanmakuArgs(roomId: '80518', userId: 'x'));
      expect(events, [
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable room or broadcaster'),
      ]);
      expect(http.requests, isEmpty);
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect('not six rooms args'), throwsArgumentError);
    });

    test('closing during the server list request cancels it: no socket and no event', () async {
      final pending = Completer<LiveResponse>();
      final http = _Http([pending]);
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      pending.complete(_servers(_four()));
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('after close nothing is reported; another connect replaces the room with a new guest', () async {
      final http = _Http([_servers(_four()), _servers(_four(port: 5190, round: 2))]);
      final connector = _Connector();
      final random = Random(3);
      final connection = _connection(http, connector, random: random);
      final events = _record(connection);
      await connection.connect(_args);
      await connection.connect(const SixRoomDanmakuArgs(roomId: '9818', userId: '119223546'));
      expect(connector.channels.first.closed, isTrue);
      expect(http.requests.first.cancel!.isCancelled, isTrue);
      expect(http.requests.last.url.queryParameters['rid'], '119223546');
      expect(http.requests.last.headers['referer'], 'https://v.6.cn/9818');
      expect(connector.endpoints.last, Uri.parse('wss://r2snbjh2.6rooms.com:5190'));
      final first = SixRoomDanmakuProtocol.fields(connector.channels.first.sent.single as String);
      final second = SixRoomDanmakuProtocol.fields(connector.channels.last.sent.single as String);
      expect(second['roomid'], '119223546');
      expect(int.parse(second['uid']!), inInclusiveRange(1800000000, 1899999999));
      expect(second['uid'], isNot(first['uid']));
      await connector.channels.first.receive(_message(_chat(content: 'old room')));
      await connector.channels.last.receive(_loginSuccess);
      await connector.channels.last.receive(_message(_chat(content: 'new room')));
      expect(_texts(events), ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(_message(_chat(content: 'late')));
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(connector.channels, hasLength(2));
    });

    test('a real local server: the server list request, the handshake headers, login, heartbeat and chat', () async {
      final requests = <String>[];
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
        if (request.uri.path == '/room/getChat.php') {
          requests.add(
            '${request.method} ${request.uri.query} ${request.headers.value('referer')} '
            '${request.headers.value('x-requested-with')}',
          );
          request.response
            ..headers.contentType = ContentType.html
            ..write(jsonEncode({'a': <Object?>[], 'b': <Object?>[], 'websock': _four()}));
          await request.response.close();
          return;
        }
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          received.add(frame);
          if (frame is String && frame.startsWith('command=login')) {
            socket
              ..add(_loginSuccess)
              ..add(_message(_chat(content: '现场')))
              ..add(
                _message({
                  'typeID': 1413,
                  'content': [_chat(content: '列表里')],
                }),
              );
          } else if (frame == SixRoomDanmakuProtocol.heartbeat) {
            socket
              ..add(_sendSuccess)
              ..add(_frame({'flag': '205', 'content': 'bbbbb'}));
          }
        });
      });
      final http = _Local(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = SixRoomDanmakuConnection(
        http: http,
        random: _Fixed(1),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, Uri.parse('wss://r1snbjh2.6rooms.com:5390'));
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
      expect(requests, ['GET rid=57401078 https://v.6.cn/80518 XMLHttpRequest']);
      expect(handshake['origin'], 'https://v.6.cn');
      expect(handshake['user-agent'], endsWith(SixRoomApi.userAgent));
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['现场', '列表里']);
      await _until(() => received.length == 2);
      expect(received, [
        'command=login\r\nuid=1800000001\r\nencpass=\r\nroomid=57401078\r\n',
        SixRoomDanmakuProtocol.heartbeat,
      ]);
      await connection.close();
    });
  });
}

/// Sends the `getChat.php` requests to a local server.
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
