// FC2 Live comments (M5.22): the protocol against the recording
// fixtures/fc2live/danmaku/S06-live, frame by frame with the archived v4's
// decoder (danmaku/v4_expected.dart wrote expected.json), synthetic frames
// and NG lists, and the connection over fake grant answers and sockets and a
// real local server. Nothing here compares a recorded time with the clock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/fc2live';
const _sample = '$_root/danmaku/S06-live';

/// The recorded channel.
const _channel = '29745829';
const _args = Fc2LiveDanmakuArgs(_channel);

typedef _Line = ({int line, String dir, String? url, String text});

/// Every line of the recording: the grant's two answers (with their URL),
/// then the socket's frames both ways (the client's were binary).
final List<_Line> _recording = [
  for (final (index, raw) in File('$_sample/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(raw) case final Map<String, Object?> frame)
      (
        line: index + 1,
        dir: frame['dir']! as String,
        url: frame['url'] as String?,
        text: frame['text'] as String? ?? utf8.decode(base64.decode(frame['b64']! as String)),
      ),
];

String _answer(String path) => _recording.singleWhere((line) => line.url?.endsWith(path) ?? false).text;

/// The recorded member and grant answers.
final String _member = _answer('/memberApi.php');
final String _grant = _answer('/getControlServer.php');

/// The socket's frames in order.
final List<_Line> _socket = [
  for (final line in _recording)
    if (line.url == null) line,
];

/// The archived v4's output for S06-live (danmaku/v4_expected.dart).
final Map<String, Object?> _v4 =
    (jsonDecode(File('$_sample/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

final Map<String, Object?> _meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, Object?>;

String _body(String sample) => File('$_root/$sample/body.json').readAsStringSync();

/// The recorded grant's socket (the URL without its token).
final String _recordedSocket = (jsonDecode(_grant) as Map<String, Object?>)['url']! as String;
final String _recordedOrz = (jsonDecode(_grant) as Map<String, Object?>)['orz_raw']! as String;

/// Grant answer number [n] for [channel]: the recorded one first, then
/// synthetic tokens and cookies.
String _grantAnswer(String channel, int n) {
  final grant = jsonDecode(_grant) as Map<String, Object?>;
  grant['url'] = _recordedSocket.replaceFirst('/channels/$_channel', '/channels/$channel');
  if (n > 1) {
    grant['control_token'] = 'tok$n';
    grant['orz_raw'] = 'orz$n';
  }
  return jsonEncode(grant);
}

/// Answers the grant requests: `memberApi.php` from [members] by channel
/// (the recorded channel, and any other channel as the recorded one with
/// its number), `getControlServer.php` with [_grantAnswer] numbered by call.
/// [steps] replace answers by request number (from 1): a response, an
/// exception, or a completer to wait for (cancellable).
final class _Http implements LiveHttp {
  new({this.members = const {}, this.steps = const {}});

  final Map<String, String> members;
  final Map<int, Object> steps;
  final List<LiveRequest> requests = [];
  int _grants = 0;

  List<String> get paths => [for (final request in requests) request.url.path];

  Map<String, String> form(int index) => Uri.splitQueryString(utf8.decode(requests[index].body!));

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    LiveResponse ok(String body, {int status = 200}) =>
        LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
    switch (steps[requests.length]) {
      case final LiveResponse response:
        return response;
      case final Completer<LiveResponse> pending:
        return await Future.any([
          pending.future,
          request.cancel!.whenCancelled.then(
            (_) => throw const TransportFailure(SiteIds.fc2Live, TransportReason.cancelled),
          ),
        ]);
      case final Exception error:
        throw error;
    }
    final form = Uri.splitQueryString(utf8.decode(request.body!));
    return switch (request.url.path) {
      '/api/memberApi.php' => ok(members[form['streamid']] ?? _member.replaceAll(_channel, form['streamid']!)),
      '/api/getControlServer.php' => ok(_grantAnswer(form['channel_id']!, ++_grants)),
      _ => throw StateError('unexpected ${request.url}'),
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

  /// The server's opening: `initial_connect`, `connect_complete`.
  Future<void> join() async {
    await receive(_message('initial_connect', {'publish': true}));
    await receive(_message('connect_complete'));
  }
}

/// Hands out fake sockets and records every handshake; the first [failures]
/// handshakes throw [error] (given the address).
final class _Connector {
  new({this.failures = 0, this.error});

  final int failures;
  final Exception Function(Uri endpoint)? error;
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
    if (endpoints.length <= failures) throw error?.call(endpoint) ?? const SocketException('refused');
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

/// No heartbeat, no watchdog and a short backoff: only what the test does
/// happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

Fc2LiveDanmakuConnection _connection(
  _Http http,
  _Connector connector, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) => Fc2LiveDanmakuConnection(http: http, connector: connector.call, policy: policy, proxy: proxy);

String _message(String name, [Map<String, Object?> arguments = const {}]) =>
    jsonEncode({'name': name, 'arguments': arguments});

/// A comment as the server sends it (the recording's fields).
Map<String, Object?> _comment({
  Object? comment = 'hello',
  Object? userName = '[anonymous]',
  Object? encrypted = '95qd731y54bl90no1t9605t972',
  Object? orz = '7p35js4795y2sjt0c99802o1rm2mmx528r066o64',
  Object? hash = '8o957c2t57w91w9jzg9e5qs3149rhqf5',
  Object? timestamp = 1790539323311,
  Object? color = 'black',
  Object? anonymous = 1,
  Object? history,
  Object? owner,
}) => {
  'user_name': ?userName,
  'timestamp': ?timestamp,
  'encrypted_user_id': ?encrypted,
  'orz_token': ?orz,
  'hash': ?hash,
  'comment': ?comment,
  'color': ?color,
  'size': 'middle',
  'lang': 'ja',
  'anonymous': ?anonymous,
  'history': ?history,
  'owner': ?owner,
};

String _comments(List<Map<String, Object?>> comments) => _message('comment', {'comments': comments});

/// [digits] (at least 60 each) encoded as the site encodes an FC2 user id
/// with [offset] (`decryptUserId` read backwards).
String _typeA(List<int> digits, int offset) =>
    String.fromCharCodes([0x61, 0x30 + offset, for (final (index, n) in digits.indexed) n + offset - 3 * (index + 2)]);

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuReceived) event.message,
];

List<String> _texts(List<DanmakuEvent> events) => [
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

/// A message as the projections below compare it.
Map<String, Object?> _project(LiveMessage message) => switch (message.type) {
  LiveMessageType.online => {
    'type': 'online',
    'kind': (message.data! as LiveAudienceUpdate).kind.name,
    'value': (message.data! as LiveAudienceUpdate).value,
  },
  _ => {
    'type': message.type.name,
    'id': message.messageId,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'color': '${message.color}',
  },
};

/// A v4 event as [_project] shows the new code's, with the intended
/// differences applied: no message id (v4: `fc2live:<hash>`, a sender's
/// hash), the page's user key of v4's raw `encrypted_user_id`, the colour
/// as text, v4's `online`/`cumulative` as the model's kinds.
Map<String, Object?> _fromV4(Map<String, Object?> event) => switch (event['type']) {
  'online' => {
    'type': 'online',
    'kind': event['audience'] == 'online' ? 'onlineViewers' : 'totalViewers',
    'value': event['value'],
  },
  _ => {
    'type': 'chat',
    'id': '',
    'userId': Fc2LiveDanmakuProtocol.userId(event['userId']),
    'userName': event['userName'],
    'text': event['text'],
    'sentAt': event['sentAt'],
    'color': LiveMessageColor.numberToColor(event['color']! as int).toString(),
  },
};

void main() {
  group('protocol', () {
    test("the page's heartbeat command, timing and the nominal address", () {
      expect(Fc2LiveDanmakuProtocol.heartbeat(1), '{"name":"heartbeat","arguments":{},"id":1}');
      expect(Fc2LiveDanmakuProtocol.heartbeatInterval, const Duration(seconds: 30));
      expect(Fc2LiveDanmakuProtocol.joinTimeout, const Duration(seconds: 8));
      final endpoint = Fc2LiveDanmakuProtocol.endpoint(_channel);
      expect(endpoint, Uri.parse('https://live.fc2.com/api/getControlServer.php?channel_id=29745829'));
      expect(Fc2LiveDanmakuProtocol.channelOf(endpoint), _channel);
      for (final other in [
        Uri.parse(_recordedSocket),
        Uri.parse('https://live.fc2.com/api/getControlServer.php'),
        Uri.parse('https://live.fc2.com/api/getControlServer.php?channel_id=0123'),
        Uri.parse('https://live.fc2.com/api/getControlServer.php?channel_id=abc'),
        Uri.parse('https://live.fc2.com/api/getControlServer.php?channel_id=1&x=2'),
        Uri.parse('https://live.fc2.com/api/memberApi.php?channel_id=1'),
        Uri.parse('https://example.com/api/getControlServer.php?channel_id=1'),
        Uri.parse('http://live.fc2.com/api/getControlServer.php?channel_id=1'),
      ]) {
        expect(Fc2LiveDanmakuProtocol.channelOf(other), isNull, reason: '$other');
      }
    });

    test('redact leaves out the control token and the session cookie, nothing else', () {
      const failure =
          "WebSocketException: Connection to 'https://node.live.fc2.com:0/control/channels/1?control_token=a.b_c-d#' "
          'was not upgraded to websocket, HTTP status code: 403; cookie l_ortkn=z4ip; other=1';
      final redacted = Fc2LiveDanmakuProtocol.redact(failure);
      expect(redacted, contains('/control/channels/1?control_token=…#'));
      expect(redacted, contains('l_ortkn=…; other=1'));
      expect(redacted, isNot(contains('a.b_c-d')));
      expect(redacted, isNot(contains('z4ip')));
      expect(redacted, endsWith('other=1'));
      expect(Fc2LiveDanmakuProtocol.redact('no control_token=here'), 'no control_token=here');
    });

    test('frames: text or UTF-8 bytes of a named JSON object, at most 2 MiB', () {
      final message = Fc2LiveDanmakuProtocol.decode('{"name":"_response_","id":2,"arguments":{"status":0}}')!;
      expect((message.name, message.id), ('_response_', 2));
      expect(message.arguments, {'status': 0});
      expect(Fc2LiveDanmakuProtocol.decode(utf8.encode(_message('comment', {'x': 1})))!.arguments, {'x': 1});
      expect(Fc2LiveDanmakuProtocol.decode('{"name":"connect_complete"}')!.arguments, isEmpty);
      expect(Fc2LiveDanmakuProtocol.decode('{"name":"x","arguments":[1]}')!.arguments, isEmpty);
      final malformed = [...utf8.encode('{"name":"x","arguments":{"t":"'), 0xFF, ...utf8.encode('"}}')];
      expect(Fc2LiveDanmakuProtocol.decode(malformed)!.arguments, {'t': '�'}, reason: 'malformed UTF-8 replaced');
      for (final data in <Object?>[
        '',
        'not json',
        '[{"name":"x"}]',
        '"x"',
        '{"arguments":{}}',
        '{"name":7}',
        42,
        null,
        ' ' * (Fc2LiveControl.messageLimit + 1),
        List<int>.filled(Fc2LiveControl.messageLimit + 1, 0x20),
      ]) {
        expect(Fc2LiveDanmakuProtocol.decode(data), isNull, reason: '${'$data'.length > 40 ? 'a large frame' : data}');
      }
      final padded = '{"name":"x"}${' ' * (Fc2LiveControl.messageLimit - 12)}';
      expect(Fc2LiveDanmakuProtocol.decode(padded)!.name, 'x', reason: 'exactly 2 MiB');
    });

    test('a comment: text, name, user key, time and colour; no message id', () {
      final message = Fc2LiveDanmakuProtocol.comment(_comment(comment: '  あ  ', color: 'red'))!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'あ');
      expect(message.userName, '[anonymous]');
      expect(message.userId, 'id_95qd731y54bl90no1t9605t972');
      expect(message.messageId, isEmpty, reason: 'hash names the sender');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790539323311));
      expect(message.color, const LiveMessageColor(0xE6, 0x3D, 0x37));
      expect(message.userLevel, isEmpty);
      expect(message.isLocal, isFalse);
      final named = Fc2LiveDanmakuProtocol.comment(_comment(userName: ' Name ', anonymous: 0))!;
      expect(named.userName, 'Name');
    });

    test('comments that are not chat: history, system comments, blank or missing text', () {
      LiveMessage? of(Map<String, Object?> comment) => Fc2LiveDanmakuProtocol.comment(comment);
      for (final history in <Object>[1, 1.0, true, '1']) {
        expect(of(_comment(history: history)), isNull, reason: 'history $history');
      }
      for (final history in <Object>[0, false, '0', 2]) {
        expect(of(_comment(history: history)), isNotNull, reason: 'history $history');
      }
      for (final text in <Object?>[
        null,
        '',
        '  ',
        42,
        const ['x'],
        '<b></b>',
      ]) {
        expect(of(_comment(comment: text)), isNull, reason: '$text');
      }
      final tip = {
        ..._comment(comment: null),
        'system_comment': {'type': 'tip', 'tip_amount': 100},
      };
      expect(of(tip), isNull, reason: 'a tip has no text of its own');
      expect(Fc2LiveDanmakuProtocol.comment('text'), isNull);
      expect(Fc2LiveDanmakuProtocol.comment(null), isNull);
    });

    test('text and names as the page shows them: tags removed, references decoded, trimmed', () {
      String text(String raw) => Fc2LiveDanmakuProtocol.comment(_comment(comment: raw))!.message;
      expect(text('a &lt;3 b &amp; c'), 'a <3 b & c');
      expect(text('<span class="x">hi</span><br>there'), 'hithere');
      expect(text('&lt;b&gt;literal&lt;/b&gt;'), '<b>literal</b>');
      expect(text('x < y > z'), 'x < y > z', reason: 'not tags');
      expect(text('&#x1F600;&quot;'), '😀"');
      String name(Object? raw, {Object? anonymous = 0}) =>
          Fc2LiveDanmakuProtocol.comment(_comment(userName: raw, anonymous: anonymous))!.userName;
      expect(name('A&amp;B'), 'A&B');
      expect(name('<i>Hidden</i>'), 'Hidden');
      expect(name('Real', anonymous: 1), '[anonymous]', reason: 'the page hides the name of an anonymous comment');
      expect(name('Real', anonymous: true), '[anonymous]');
      expect(name(' '), '[anonymous]');
      expect(name(null), '[anonymous]');
      expect(name(7), '[anonymous]');
      expect(Fc2LiveDanmakuProtocol.escapedText('a&b<3>&amp;<i>x</i> '), 'a&amp;b&lt;3>&amp;x ');
    });

    test("user keys: an FC2 user's id decoded whatever its offset; other ids as they are", () {
      const digits = [101, 102, 103, 104, 105, 106, 107, 108];
      final keys = {for (var offset = 0; offset <= 9; offset++) Fc2LiveDanmakuProtocol.userId(_typeA(digits, offset))};
      expect(keys, {'id-101-102-103-104-105-106-107-108'}, reason: 'one key for ten encodings');
      expect(Fc2LiveDanmakuProtocol.userId('a3'), 'id', reason: 'the page decodes nothing to "id"');
      expect(Fc2LiveDanmakuProtocol.userId('95qd731y54bl90no1t9605t972'), 'id_95qd731y54bl90no1t9605t972');
      expect(Fc2LiveDanmakuProtocol.userId('r6C>??[YTC'), 'id_r6C>??[YTC', reason: 'scrubbed: no longer type A');
      expect(Fc2LiveDanmakuProtocol.userId('a3abcdefghijk'), 'id_a3abcdefghijk', reason: 'longer than 12');
      expect(Fc2LiveDanmakuProtocol.userId('ab123'), 'id_ab123', reason: 'no offset digit');
      expect(Fc2LiveDanmakuProtocol.userId('A3xyz'), 'id_A3xyz');
      expect(Fc2LiveDanmakuProtocol.userId('a'), 'id_a');
      for (final missing in <Object?>['', null, 42]) {
        expect(Fc2LiveDanmakuProtocol.userId(missing), '', reason: '$missing');
      }
    });

    test("colours: the page's chat list by name; black, unknown and missing are white", () {
      expect(
        {for (final name in Fc2LiveDanmakuProtocol.colors.keys) name: '${Fc2LiveDanmakuProtocol.color(name)}'},
        {
          'red': '#e63d37',
          'pink': '#e13396',
          'orange': '#dc7611',
          'yellow': '#e1ac00',
          'green': '#33bd4a',
          'cyan': '#1b94c7',
          'blue': '#4472f3',
          'purple': '#b84ac5',
        },
      );
      expect(Fc2LiveDanmakuProtocol.color(' Blue '), const LiveMessageColor(0x44, 0x72, 0xF3));
      for (final name in <Object?>['black', 'white', '#ff0000', 'magenta', '', null, 3]) {
        expect(Fc2LiveDanmakuProtocol.color(name), LiveMessageColor.white, reason: '$name');
      }
    });

    test('comment times: positive milliseconds within DateTime', () {
      DateTime? at(Object? time) => Fc2LiveDanmakuProtocol.comment(_comment(timestamp: time))!.sentAt;
      for (final time in <Object?>[0, -1, 8640000000000001, 1.7e12, '1790539323311', null]) {
        expect(at(time), isNull, reason: '$time');
      }
      expect(at(1), DateTime.fromMillisecondsSinceEpoch(1));
      expect(at(8640000000000000), DateTime.fromMillisecondsSinceEpoch(8640000000000000));
    });

    test('the audience: partial updates keep the other fields; only changed sums are reported', () {
      final audience = Fc2LiveAudience();
      List<String> update(Map<String, Object?> arguments) => [
        for (final message in audience.update(arguments))
          '${(message.data! as LiveAudienceUpdate).kind.name}=${(message.data! as LiveAudienceUpdate).value}',
      ];
      expect((audience.online, audience.total), (null, null));
      expect(update({}), isEmpty);
      expect(update({'pc_user_count': 84}), ['onlineViewers=84'], reason: 'mobile unknown: counts 0');
      expect(update({'mobile_user_count': 27, 'pc_total_count': 816, 'mobile_total_count': 404}), [
        'onlineViewers=111',
        'totalViewers=1220',
      ]);
      expect(update({'pc_user_count': 85, 'pc_total_count': 817}), ['onlineViewers=112', 'totalViewers=1221']);
      expect(update({'mobile_user_count': 26}), ['onlineViewers=111']);
      expect(update({'pc_user_count': 84, 'mobile_user_count': 27}), isEmpty, reason: 'the same sum');
      expect(update({'pc_user_count': -1, 'mobile_user_count': '9', 'pc_total_count': 1.5}), isEmpty);
      expect((audience.online, audience.total), (111, 1221));
      final message = audience.update({'pc_total_count': 900}).single;
      expect((message.type, message.userName, message.message), (LiveMessageType.online, '', ''));
    });

    test('NG lists: keywords of the channel always, of FC2 with admin_ng; lower case, escaped text', () {
      final ng = Fc2LiveNgList()
        ..apply({
          'admin_ng': 0,
          'shared_ng_level': 0,
          'ng_comments': [
            {'type': 'channel_keyword', 'ng_keyword': 'SPAM', 'ng_comment_id': 11, 'mode': 'add'},
            {'type': 'admin_keyword', 'ng_keyword': 'badword', 'ng_comment_id': 12},
            {'type': 'channel_keyword', 'ng_keyword': '&amp;', 'ng_comment_id': 13},
            {'type': 'channel_keyword', 'ng_keyword': '', 'ng_comment_id': 14},
            {'type': 'unknown_keyword', 'ng_keyword': 'hello'},
            'not an entry',
          ],
        });
      expect(ng.length, 4);
      bool hides(Map<String, Object?> comment) => ng.hides(comment);
      expect(hides(_comment(comment: 'buy SpAm now')), isTrue);
      expect(hides(_comment(comment: 'a badword')), isFalse, reason: "FC2's lists are off");
      expect(hides(_comment(comment: 'x &amp; y')), isTrue, reason: 'compared as the page escapes the text');
      expect(hides(_comment(comment: 'x & y')), isTrue);
      expect(hides(_comment()), isFalse);
      ng.apply({'admin_ng': 1});
      expect(ng.usesAdminLists, isTrue);
      expect(hides(_comment(comment: 'a BADWORD')), isTrue);
      expect(
        hides(_comment(comment: 'x', userName: 'spammer', anonymous: 0)),
        isTrue,
        reason: 'names too',
      );
      expect(
        hides(_comment(comment: 'x', userName: 'spammer')),
        isFalse,
        reason: 'not anonymous ones',
      );
      expect(hides(_comment(comment: 'spam', owner: 1)), isFalse, reason: "the streamer's own comment");
      ng.apply({'admin_ng': '', 'shared_ng_level': 'x'});
      expect((ng.usesAdminLists, ng.sharedLevel), (false, 0));
    });

    test('NG lists: senders by decoded id or orz_token, the shared lists by level; removals', () {
      const digits = [101, 102, 103, 104, 105, 106];
      final ng = Fc2LiveNgList()
        ..apply({
          'admin_ng': 1,
          'shared_ng_level': 1,
          'ng_comments': [
            {'type': 'channel_user', 'ng_encrypted_user_id': _typeA(digits, 3), 'ng_comment_id': 21},
            {'type': 'share_high', 'ng_orz_token': 'orzhigh', 'ng_encrypted_user_id': 'rawhigh', 'ng_comment_id': 22},
            {'type': 'share_low', 'ng_orz_token': 'orzlow'},
            {'type': 'admin_user', 'ng_orz_token': 'orzadmin', 'ng_comment_id': '23'},
            {'type': 'share_hyper', 'ng_orz_token': ''},
          ],
        });
      bool hides({Object? encrypted, Object? orz, Object? owner}) =>
          ng.hides(_comment(encrypted: encrypted, orz: orz, owner: owner));
      expect(
        hides(encrypted: _typeA(digits, 7), orz: 'any'),
        isTrue,
        reason: 'the same FC2 user, another offset',
      );
      expect(
        hides(encrypted: _typeA(digits, 7), orz: 'any', owner: 1),
        isFalse,
        reason: 'the streamer',
      );
      expect(
        hides(encrypted: 'rawlow', orz: 'orzlow'),
        isTrue,
        reason: 'level 1: share_low',
      );
      expect(
        hides(encrypted: 'rawhigh', orz: 'orzhigh'),
        isFalse,
        reason: 'level 1: not share_high',
      );
      expect(hides(encrypted: 'raw', orz: 'orzadmin'), isTrue);
      expect(
        hides(encrypted: _typeA([101, 102], 1), orz: 'orzadmin'),
        isFalse,
        reason: 'FC2 users go by id, not orz',
      );
      expect(
        hides(encrypted: 'raw', orz: ''),
        isFalse,
        reason: 'an empty orz_token matches nothing',
      );
      expect(hides(encrypted: 'raw'), isFalse, reason: 'no orz_token');
      ng.apply({'shared_ng_level': 2});
      expect(
        hides(encrypted: 'rawhigh', orz: 'orzhigh'),
        isTrue,
        reason: 'level 2: share_high',
      );
      ng.apply({
        'ng_comments': [
          {'type': 'share_high', 'ng_comment_id': 22, 'mode': 'remove'},
          {'type': 'share_low', 'ng_orz_token': 'orzlow', 'mode': 'remove'},
          {'type': 'admin_user', 'ng_orz_token': 'orzadmin', 'ng_comment_id': 23, 'mode': 'remove'},
          {'type': 'channel_user', 'ng_comment_id': 99, 'mode': 'remove'},
        ],
      });
      expect(
        hides(encrypted: 'rawhigh', orz: 'orzhigh'),
        isFalse,
        reason: 'removed by id',
      );
      expect(
        hides(encrypted: 'rawlow', orz: 'orzlow'),
        isFalse,
        reason: 'removed by value',
      );
      expect(
        hides(encrypted: 'raw', orz: 'orzadmin'),
        isFalse,
        reason: 'ids match as text',
      );
      expect(hides(encrypted: _typeA(digits, 0), orz: 'x'), isTrue);
      expect(ng.length, 2);
    });

    test('NG lists: entries without an id or with id 0 are kept apart; comments pass through comments()', () {
      final ng = Fc2LiveNgList()
        ..apply({
          'ng_comments': [
            {'type': 'channel_keyword', 'ng_keyword': 'one', 'ng_comment_id': 0},
            {'type': 'channel_keyword', 'ng_keyword': 'one', 'ng_comment_id': 0},
            {'type': 'channel_keyword', 'ng_keyword': 'two', 'ng_comment_id': ''},
          ],
        });
      expect(ng.length, 3);
      final messages = Fc2LiveDanmakuProtocol.comments({
        'comments': [
          _comment(comment: 'number one'),
          _comment(comment: 'kept'),
          _comment(comment: 'two'),
          'not a comment',
        ],
      }, ng: ng);
      expect([for (final message in messages) message.message], ['kept']);
      expect(Fc2LiveDanmakuProtocol.comments({'comments': 'x'}), isEmpty);
      expect(Fc2LiveDanmakuProtocol.comments({}), isEmpty);
    });
  });

  group('recording (S06-live)', () {
    test('the recorded grant answers give the recorded socket; the handshake carries the grant cookie', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      await connection.connect(_args);
      final handshake = (_meta['handshakes']! as List).single as Map<String, Object?>;
      expect(connector.endpoints.single.toString(), handshake['url']);
      expect(connector.headers.single, {
        'origin': 'https://live.fc2.com',
        'user-agent': Fc2LiveApi.userAgent,
        'cookie': 'l_ortkn=$_recordedOrz',
      });
      expect((handshake['headers']! as Map)['Origin'], 'https://live.fc2.com');
      expect(http.paths, ['/api/memberApi.php', '/api/getControlServer.php']);
      expect(http.form(0), {'channel': '1', 'profile': '1', 'user': '1', 'streamid': _channel});
      expect(http.form(1), {
        'channel_id': _channel,
        'mode': 'play',
        'orz': '',
        'channel_version': 'Jv87uLm2IFhPOVy0ZgnvB',
        'client_version': '2.1.0\n [1]',
        'client_type': 'pc',
        'client_app': 'browser_hls',
        'ipv6': '',
      });
      expect(http.requests.map((request) => request.site), everyElement(SiteIds.fc2Live));
      await connection.close();
    });

    test('every received frame decodes as the archived v4 did, but for the intended differences', () {
      final frames = (_v4['frames']! as List).cast<Map<String, Object?>>();
      final received = [
        for (final line in _socket)
          if (line.dir == 'in') line,
      ];
      expect(received, hasLength(frames.length));
      final audience = Fc2LiveAudience();
      var chats = 0;
      var figures = 0;
      for (final (index, line) in received.indexed) {
        final expected = frames[index];
        expect(line.line, expected['line']);
        final message = Fc2LiveDanmakuProtocol.decode(line.text)!;
        final events = switch (message.name) {
          'comment' => Fc2LiveDanmakuProtocol.comments(message.arguments),
          'user_count' => audience.update(message.arguments),
          _ => const <LiveMessage>[],
        };
        expect(
          [for (final event in events) _project(event)],
          [for (final event in (expected['events']! as List).cast<Map<String, Object?>>()) _fromV4(event)],
          reason: 'line ${line.line}',
        );
        expect(message.name == 'connect_complete', expected['joined'], reason: 'line ${line.line}');
        expect(message.name == 'control_disconnection', expected['rejected'], reason: 'line ${line.line}');
        chats += events.where((event) => event.type == LiveMessageType.chat).length;
        figures += events.where((event) => event.type == LiveMessageType.online).length;
      }
      expect((chats, figures), (20, 27));
      final history = Fc2LiveDanmakuProtocol.decode(received.firstWhere((line) => line.line == 10).text)!;
      expect(history.arguments['comments'], hasLength(30), reason: 'the 30 comments replayed on joining');
    });

    test('hash names the sender, not the comment: it repeats across comments (no message id)', () {
      final hashes = <String, int>{};
      for (final line in _socket) {
        final message = Fc2LiveDanmakuProtocol.decode(line.text);
        if (message?.name != 'comment') continue;
        for (final comment in (message!.arguments['comments']! as List).cast<Map<String, Object?>>()) {
          if (comment['history'] == 1) continue;
          hashes.update(comment['hash']! as String, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      expect(hashes.values.reduce((a, b) => a + b), 20);
      expect(hashes.values.where((count) => count > 1), isNotEmpty);
      expect(hashes['8o957c2t57w91w9jzg9e5qs3149rhqf5'], 7);
    });

    test('the connection replays the recording: two requests, one socket, ready at connect_complete', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      expect(connection.isConnected, isFalse, reason: 'joined at connect_complete, not at the open');
      final channel = connector.channels.single;
      for (final line in _socket) {
        if (line.dir == 'in') {
          await channel.receive(line.text);
        } else {
          connection.heartbeat();
        }
      }
      final sent = [
        for (final line in _socket)
          if (line.dir == 'out') line.text,
      ];
      expect(sent, _v4['heartbeats']);
      expect(channel.sent, sent, reason: "the recorded heartbeats, as text frames (v4's were binary)");
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      final expected = [
        for (final frame in (_v4['frames']! as List).cast<Map<String, Object?>>())
          for (final event in (frame['events']! as List).cast<Map<String, Object?>>()) _fromV4(event),
      ];
      expect([for (final message in _messages(events)) _project(message)], expected);
      expect(http.requests, hasLength(2));
      await connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = Fc2LiveDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 30));
      expect(policy.joinTimeout, const Duration(seconds: 8));
      expect(policy.inactivityTimeout, isNull, reason: 'the default: 90 s');
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = Fc2LiveDanmakuConnection(http: _Http());
      expect(connection.heartbeatInterval, const Duration(seconds: 30));
      expect(connection.status, DanmakuStatus.idle);
      final registry = DanmakuRegistry({SiteIds.fc2Live: () => Fc2LiveDanmakuConnection(http: _Http())});
      expect(registry.supports('FC2Live'), isTrue);
      expect(registry.connectionFor('fc2live'), isA<Fc2LiveDanmakuConnection>());
    });

    test("handshake: the grant's socket and headers through the platform route; chat once joined", () async {
      final http = _Http();
      final connector = _Connector();
      final asked = <(String, Uri)>[];
      final connection = _connection(http, connector, proxy: _Proxy(asked));
      final events = _record(connection);
      await connection.connect(_args);
      expect(connector.routes.single, const HttpProxyRoute('127.0.0.1', 7897));
      expect(asked.last, (SiteIds.fc2Live, Uri.parse(_recordedSocket)), reason: "the grant's socket decides");
      expect(events, isEmpty);
      final channel = connector.channels.single;
      await channel.join();
      expect(events, [const DanmakuReady()]);
      await channel.receive(_message('connect_complete'));
      expect(events, [const DanmakuReady()], reason: 'once per socket');
      await channel.receive(_comments([_comment(comment: 'old', history: 1), _comment(comment: 'new')]));
      await channel.receive(_message('user_count', {'pc_user_count': 3, 'mobile_user_count': 1}));
      for (final other in ['connect_data', 'video_information', 'point_information', 'initial_connect', 'x']) {
        await channel.receive(
          _message(other, {
            'comments': [_comment()],
          }),
        );
      }
      await channel.receive('garbage');
      await channel.receive(_message('_response_', {'status': 0}));
      expect(_texts(events), ['new']);
      expect([for (final message in _messages(events)) _project(message)].last, {
        'type': 'online',
        'kind': 'onlineViewers',
        'value': 4,
      });
      expect(channel.sent, isEmpty, reason: 'nothing but heartbeats is sent');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test("the channel's NG list hides comments as the page does", () async {
      final connector = _Connector();
      final connection = _connection(_Http(), connector);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      await channel.join();
      await channel.receive(
        _message('ng_comment', {
          'admin_ng': 1,
          'shared_ng_level': 2,
          'ng_comments': [
            {'type': 'channel_keyword', 'ng_keyword': 'spam', 'ng_comment_id': 1},
            {'type': 'share_high', 'ng_orz_token': 'orzbad', 'ng_comment_id': 2},
          ],
        }),
      );
      await channel.receive(
        _comments([
          _comment(comment: 'SPAM!'),
          _comment(comment: 'from a listed sender', orz: 'orzbad', encrypted: 'rawbad'),
          _comment(comment: 'fine'),
        ]),
      );
      expect(_texts(events), ['fine']);
      await connection.close();
    });

    test('heartbeats: every interval from the open and on demand, ids counting up across sockets', () async {
      final connector = _Connector();
      final connection = _connection(
        _Http(),
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          inactivityTimeout: Duration(seconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await _until(() => first.sent.length >= 3);
      connection.heartbeat();
      final sent = [...first.sent];
      expect(sent, [for (var id = 1; id <= sent.length; id++) Fc2LiveDanmakuProtocol.heartbeat(id)]);
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      await second.join();
      await _until(() => second.sent.isNotEmpty);
      expect(
        second.sent.first,
        startsWith('{"name":"heartbeat","arguments":{},"id":'),
        reason: 'the ids go on from the first socket',
      );
      final id = (jsonDecode(second.sent.first as String) as Map<String, Object?>)['id']! as int;
      expect(id, greaterThan(sent.length));
      await connection.close();
    });

    test('a channel that cannot be joined ends at once, after the member request alone', () async {
      for (final (members, channel, detail) in [
        (
          {'10608314': _body('S02-member-offline')},
          '10608314',
          'StreamUnavailable(fc2live: channel 10608314 is not on air)',
        ),
        ({'3024638': _body('S02-member-restricted')}, '3024638', 'NeedsLogin'),
        ({'99999999': _body('S02-member-missing')}, '99999999', 'NotFound'),
      ]) {
        final http = _Http(members: members);
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await connection.connect(Fc2LiveDanmakuArgs(channel));
        expect(events, [isA<DanmakuClosed>()], reason: channel);
        final closed = events.single as DanmakuClosed;
        expect(closed.reason, DanmakuCloseReason.connectionFailed, reason: channel);
        expect(closed.detail, contains(detail));
        expect(http.paths, ['/api/memberApi.php'], reason: channel);
        expect(connector.endpoints, isEmpty);
        expect(connection.status, DanmakuStatus.closed);
      }
    });

    test('grant answers that cannot be read or refuse the stream end at once too', () async {
      LiveResponse answer(String body, {int status = 200}) => LiveResponse(
        status: status,
        bytes: utf8.encode(body),
        url: Uri.parse('https://live.fc2.com/api/getControlServer.php'),
      );
      for (final (step, kind) in [
        (answer('{"status":1}'), 'StreamUnavailable'),
        (answer('{"status":0,"url":"wss://example.com/control/channels/29745829"}'), 'ApiChanged'),
        (answer('<html>'), 'ApiChanged'),
        (answer('', status: 403), 'RiskControl'),
      ]) {
        final http = _Http(steps: {2: step});
        final connector = _Connector();
        final connection = _connection(http, connector);
        final events = _record(connection);
        await connection.connect(_args);
        expect(events.single, isA<DanmakuClosed>().having((e) => e.detail, 'detail', startsWith(kind)));
        expect((events.single as DanmakuClosed).reason, DanmakuCloseReason.connectionFailed);
        expect(connector.endpoints, isEmpty);
      }
    });

    test('arguments that are not a channel end at once without a request; other types throw', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(const Fc2LiveDanmakuArgs('0123'));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Not an FC2 channel')]);
      expect(http.requests, isEmpty);
      await expectLater(connection.connect('not fc2 args'), throwsArgumentError);
    });

    test('a network failure of the first grant is a failed handshake: reported, retried, joined', () async {
      final http = _Http(steps: {1: const TransportFailure(SiteIds.fc2Live, TransportReason.connect, 'refused')});
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await _until(() => connector.channels.isNotEmpty);
      await connector.channels.single.join();
      expect(events.last, const DanmakuReady());
      expect(http.paths, ['/api/memberApi.php', '/api/memberApi.php', '/api/getControlServer.php']);
      await connection.close();
    });

    test('a dropped socket reconnects on a fresh grant and is ready again', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive(_message('user_count', {'pc_user_count': 5, 'mobile_user_count': 0}));
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(http.requests, hasLength(4), reason: 'memberApi and getControlServer again');
      expect(connector.endpoints.last.queryParameters['control_token'], 'tok2');
      expect(connector.headers.last['cookie'], 'l_ortkn=orz2');
      await connector.channels.last.join();
      await connector.channels.last.receive(_message('user_count', {'pc_user_count': 5, 'mobile_user_count': 0}));
      await connector.channels.last.receive(_comments([_comment(comment: 'after')]));
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      expect(events.whereType<DanmakuReconnecting>().single.reason, DanmakuInterruption.disconnected);
      expect(_texts(events), ['after']);
      expect(
        _messages(events).where((message) => message.type == LiveMessageType.online),
        hasLength(1),
        reason: 'the audience is kept across sockets: an unchanged sum is not reported again',
      );
      await connection.close();
    });

    test('control_disconnection reconnects on a fresh grant, with a notice', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive(_message('control_disconnection', {'code': 4500}));
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      await connector.channels.last.join();
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      expect(connector.endpoints.last.queryParameters['control_token'], 'tok2');
      await connection.close();
    });

    test('move_server replaces the socket at once and quietly, on a fresh grant', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive(
        _message('move_server', {'url': 'wss://other.live.fc2.com/control/channels/29745829'}),
      );
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      expect(connection.isConnected, isFalse);
      expect(connector.endpoints.last.host, Uri.parse(_recordedSocket).host, reason: "the grant's node");
      await connector.channels.last.join();
      expect(events, [const DanmakuReady(), const DanmakuReady()]);
      await connector.channels.first.receive(_comments([_comment(comment: 'old socket')]));
      await connector.channels.last.receive(_comments([_comment(comment: 'new socket')]));
      expect(_texts(events), ['new socket']);
      await connection.close();
    });

    test('server-ordered reconnects end the connection unless a heartbeat is answered in between', () async {
      Future<(List<DanmakuEvent>, _Connector)> run({required bool answer}) async {
        final connector = _Connector();
        final connection = _connection(
          _Http(),
          connector,
          policy: const DanmakuSocketPolicy(
            heartbeatInterval: Duration.zero,
            reconnectBaseDelay: Duration(milliseconds: 5),
            maxReconnects: 2,
          ),
        );
        final events = _record(connection);
        await connection.connect(_args);
        for (var socket = 1; socket <= 3; socket++) {
          await _until(() => connector.channels.length == socket);
          final channel = connector.channels.last;
          await channel.join();
          if (answer) await channel.receive(_message('_response_', {'status': 0}));
          await channel.receive(_message('control_disconnection', {'code': 4500}));
        }
        await _wait(const Duration(milliseconds: 40));
        await connection.close();
        return (events, connector);
      }

      final (ended, endedConnector) = await run(answer: false);
      expect(
        ended.last,
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'control_disconnection 4500'),
      );
      expect(endedConnector.channels, hasLength(3));
      final (kept, keptConnector) = await run(answer: true);
      expect(kept.whereType<DanmakuClosed>(), isEmpty);
      expect(keptConnector.channels, hasLength(4), reason: 'still reconnecting');
    });

    test('a socket that never says connect_complete is replaced; in a row, the connection ends', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(
        http,
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 5),
          maxReconnects: 1,
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.receive(_message('initial_connect'));
      await _until(() => connector.channels.length == 2);
      expect(connector.channels.first.closed, isTrue);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      await connector.channels.last.receive(_message('initial_connect'));
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'no connect_complete in time'),
      );
      expect(http.requests, hasLength(4));
    });

    test('failed handshakes in a row end the connection; the detail names no token or cookie', () async {
      final http = _Http();
      final connector = _Connector(
        failures: 100,
        error: (endpoint) => WebSocketException(
          "Connection to '${endpoint.replace(scheme: 'https', port: 0)}#' was not upgraded to websocket, "
          'HTTP status code: 403',
        ),
      );
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
      expect(closed.detail, contains('HTTP status code: 403'));
      expect(closed.detail, contains('control_token=…'));
      expect(closed.detail, isNot(contains('tok3')));
      expect(connector.endpoints.map((endpoint) => endpoint.queryParameters['control_token']), hasLength(3));
      expect(connector.endpoints.toSet(), hasLength(3), reason: 'a fresh grant for every handshake');
      expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
    });

    test('closing during the first grant cancels it: no socket and no event', () async {
      final pending = Completer<LiveResponse>();
      final http = _Http(steps: {1: pending});
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await _wait(const Duration(milliseconds: 20));
      expect(connector.endpoints, isEmpty);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('after close nothing is reported; another connect replaces the channel', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(http, connector);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.join();
      await connection.connect(const Fc2LiveDanmakuArgs('10200498'));
      expect(connector.channels.first.closed, isTrue);
      expect(http.form(2)['streamid'], '10200498');
      expect(connector.endpoints.last.path, '/control/channels/10200498');
      await connector.channels.first.receive(_comments([_comment(comment: 'old room')]));
      await connector.channels.last.join();
      await connector.channels.last.receive(_comments([_comment(comment: 'new room')]));
      expect(_texts(events), ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(_comments([_comment(comment: 'late')]));
      await connector.channels.last.receive(_message('control_disconnection', {'code': 4500}));
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(http.requests, hasLength(4));
    });

    test('a real local server: the form POSTs, the handshake headers, chat, the audience and a heartbeat', () async {
      final posts = <String>[];
      final handshake = <String, String?>{};
      final received = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.method == 'POST') {
          final form = Uri.splitQueryString(await utf8.decodeStream(request));
          posts.add('${request.uri.path} ${form['streamid'] ?? form['channel_id']} ${request.headers.value('origin')}');
          request.response
            ..headers.contentType = ContentType.json
            ..write(request.uri.path == '/api/memberApi.php' ? _member : _grantAnswer(_channel, 2));
          await request.response.close();
          return;
        }
        handshake['path'] = '${request.uri.path}?${request.uri.query}';
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        handshake['cookie'] = request.headers.value('cookie');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          received.add('$frame');
          socket.add('{"name":"_response_","id":1,"arguments":{"status":0}}');
        });
        socket
          ..add(_message('initial_connect', {'publish': true}))
          ..add(_message('connect_complete'))
          ..add(_message('user_count', {'pc_user_count': 84, 'mobile_user_count': 27}))
          ..add(_comments([_comment(comment: 'history', history: 1), _comment(comment: 'ノルウェー')]));
      });
      final http = _Local(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = Fc2LiveDanmakuConnection(
        http: http,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.host, Uri.parse(_recordedSocket).host);
          return Fc2LiveControl.connect(
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
      await _until(() => _texts(events).isNotEmpty);
      connection.heartbeat();
      await _until(() => received.isNotEmpty);
      expect(posts, [
        '/api/memberApi.php 29745829 https://live.fc2.com',
        '/api/getControlServer.php 29745829 https://live.fc2.com',
      ]);
      expect(handshake['path'], '/control/channels/29745829?control_token=tok2');
      expect(handshake['origin'], 'https://live.fc2.com');
      expect(handshake['user-agent'], endsWith(Fc2LiveApi.userAgent));
      expect(handshake['cookie'], 'l_ortkn=orz2');
      expect(received, ['{"name":"heartbeat","arguments":{},"id":1}']);
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['ノルウェー']);
      expect(
        [
          for (final message in _messages(events))
            if (message.type == LiveMessageType.online) _project(message),
        ],
        [
          {'type': 'online', 'kind': 'onlineViewers', 'value': 111},
        ],
      );
      await connection.close();
    });
  });
}

/// Routes every platform through one proxy, recording what was asked.
final class _Proxy implements ProxyPolicy {
  new(this.asked);

  final List<(String, Uri)> asked;

  @override
  ProxyRoute routeFor(String site, Uri url) {
    asked.add((site, url));
    return const HttpProxyRoute('127.0.0.1', 7897);
  }
}

/// Sends the grant requests to a local server.
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
      followRedirects: request.followRedirects,
    ),
  );

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
