// LOOK chat (M5.28): the protocol against the recording S05-live and the
// website's own code (expected.json, written by
// fixtures/looklive/danmaku/web_expected.js), synthetic frames for the
// edges, and the connection over fake sockets and a real local server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/looklive/danmaku/S05-live';

/// The recording: the chat server and socket.io answers, then the socket's
/// text frames, with their line numbers and directions.
final List<({int line, bool incoming, String? url, String text})> _recording = [
  for (final (index, line) in File('$_root/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 'text': final String text} && final Map<String, Object?> frame)
      (line: index + 1, incoming: dir == 'in', url: frame['url'] as String?, text: text),
];

final Map<String, Object?> _meta = jsonDecode(File('$_root/meta.json').readAsStringSync()) as Map<String, Object?>;

/// The website code's view of every incoming frame (web_expected.js).
final Map<String, Object?> _web =
    (jsonDecode(File('$_root/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

/// When the recording was made: the clock of every handshake here.
final DateTime _recordedAt = DateTime.parse(_meta['capturedAt']! as String);

const String _room = '447365581';
const String _chatroom = '9902460973';
const LookLiveDanmakuArgs _args = LookLiveDanmakuArgs(roomId: _room, chatroomId: _chatroom);

/// The recorded (scrubbed) guest: the login frame's account, device and
/// session.
final LookLiveGuest _recordedGuest = () {
  final login = jsonDecode(_recording.firstWhere((frame) => !frame.incoming).text.substring(4)) as Map;
  final v = ((login['Q'] as List)[1] as Map)['v'] as Map;
  return LookLiveGuest(account: v['2'] as String, deviceId: v['3'] as String, session: v['26'] as String);
}();

/// A [Random] giving [values] in turn from `nextInt`.
final class _Sequence implements Random {
  new(this.values);

  final List<int> values;
  int _index = 0;

  @override
  int nextInt(int max) => values[_index++ % values.length];

  @override
  bool nextBool() => throw UnsupportedError('nextBool');

  @override
  double nextDouble() => throw UnsupportedError('nextDouble');
}

/// Gives the recorded guest (`nimanon_0…01`, `0…02`, `0…03`).
Random _recordedRandom() => _Sequence([
  for (final last in [1, 2, 3]) ...[0, 0, 0, 0, 0, 0, 0, last],
]);

/// No heartbeat, watchdog or join timer and a short backoff: only what the
/// test does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

/// The chat server answer of [addresses] (the recorded ones by default).
String _addressAnswer([List<String>? addresses]) => addresses == null
    ? _recording.first.text
    : jsonEncode({
        'code': 200,
        'msg': null,
        'message': null,
        'data': {'address': addresses},
        'success': true,
      });

const String _notLive = '{"code":404,"msg":"无资源","message":"无资源","data":null,"success":false}';

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

/// Answers the chat server request and the socket.io handshakes: each
/// script entry is a body, a `(status, body)` record, an error to throw or
/// a completer to wait for; the last entry repeats. Session ids count up
/// (`sid1`, `sid2`, …) unless the handshake script says otherwise.
final class _Http implements LiveHttp {
  new({List<Object>? addresses, List<Object>? sessions})
    : addresses = addresses ?? [_addressAnswer()],
      sessions = sessions ?? const [];

  final List<Object> addresses;
  final List<Object> sessions;
  final List<LiveRequest> requests = [];
  int _addressCalls = 0;
  int _sessionCalls = 0;

  List<LiveRequest> get addressRequests => [
    for (final request in requests)
      if (request.url.path == LookLiveApi.chatAddressPath) request,
  ];

  List<LiveRequest> get handshakes => [
    for (final request in requests)
      if (request.url.path == '/socket.io/1/') request,
  ];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final Object step;
    if (request.url.path == LookLiveApi.chatAddressPath) {
      step = addresses[_addressCalls.clamp(0, addresses.length - 1)];
      _addressCalls++;
    } else {
      _sessionCalls++;
      step = sessions.isEmpty
          ? 'sid$_sessionCalls:90:30:websocket,xhr-polling'
          : sessions[(_sessionCalls - 1).clamp(0, sessions.length - 1)];
    }
    return switch (step) {
      final String body => _response(request, body),
      (final int status, final String body) => _response(request, body, status: status),
      final Completer<String> pending => _response(
        request,
        await Future.any([
          pending.future,
          request.cancel!.whenCancelled.then<String>(
            (_) => throw const TransportFailure(SiteIds.lookLive, TransportReason.cancelled),
          ),
        ]),
      ),
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

  /// The server opens the session and accepts the login.
  Future<void> join() async {
    await receive('1::');
    await receive(_loginAnswer());
  }

  /// The logins sent, as their JSON.
  List<Map<String, Object?>> get logins => [
    for (final frame in sent)
      if (frame is String && frame.startsWith('3:::{"SID":13,"CID":2'))
        jsonDecode(frame.substring(4)) as Map<String, Object?>,
  ];

  int get heartbeats => sent.where((frame) => frame == LookLiveDanmakuProtocol.heartbeat).length;
}

/// Hands out fake sockets and records every handshake.
final class _Connector {
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
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

/// The login's answer (13-2) with [code], in the recorded shape.
String _loginAnswer({int code = 200}) =>
    '3:::${jsonEncode({
      'key': 0,
      'ser': 1,
      'code': code,
      'sid': 13,
      'cid': 2,
      'r': code == 200 ? [
              {'1': _chatroom, '3': 'online_liveChatRoom_110013407_564597113', '100': '564597113', '101': '26'},
              {'2': 'nimanon_00000000000000000000000000000001', '3': '4', '5': '匿名用户'},
              <String, Object?>{},
            ] : <Object?>[],
    })}';

/// A chatroom message in a notification (4-10), as the server sends them.
String _notify(Object? message, {int sid = 13, int cid = 7, int code = 200}) =>
    '3:::${jsonEncode({
      'key': 0,
      'ser': 0,
      'code': code,
      'sid': 4,
      'cid': 10,
      'r': [
        0,
        {
          'body': [message],
          'headerPacket': {'key': 0, 'sid': sid, 'cid': cid},
        },
      ],
    })}';

/// A text message in the recorded shape (synthetic values).
Map<String, Object?> _text({
  Object? text = '大家好',
  Object? type = '0',
  Object? custom,
  Object? from = '1000000002',
  Object? time = '1790770791719',
  Object? id = '8878bc5ff6cc45dead8734cd26b0f3b8',
}) => {
  '1': ?id,
  '2': ?type,
  '3': ?text,
  '4': custom ?? jsonEncode(_custom()),
  '6': '1790770468408',
  '7': '',
  '8': '',
  '20': ?time,
  '21': ?from,
  '22': _chatroom,
  '23': '1',
};

/// A `custom` of a text message: LOOK's `iplay` wrapper with [user].
Map<String, Object?> _custom({Object? bizName = 'iplay', Object? user, Map<String, Object?>? content}) => {
  'sourceType': 2,
  'bizName': ?bizName,
  'type': 0,
  'liveId': 134608594,
  'content': content ?? {'text': '大家好', 'user': user ?? _user()},
  'roomId': 447365581,
};

Map<String, Object?> _user({
  Object? nickname = '观众2',
  Object? userId = 1000000002,
  Object? liveLevel = 21,
  Object? fanClubLevel = 11,
  Object? fanClubName = '偏爱离',
}) => {
  'liveRoomNo': 900000002,
  'nobleInfo': {'nobleLevel': 30},
  'fanClubLevel': ?fanClubLevel,
  'gender': 1,
  'avatarUrl': 'http://p1.music.126.net/SyntheticAvatar0000002==/109951170000000002.jpg',
  'liveLevel': ?liveLevel,
  'userId': ?userId,
  'fanClubName': ?fanClubName,
  'fanClubAnchorId': 564597113,
  'nickname': ?nickname,
};

/// LOOK's emoji message (a custom from the server, type 2601), shaped as
/// the Live chunk reads it.
Map<String, Object?> _emoji({Object? name = '比心', Object? from = 'musiclive_server', Object? user}) => {
  '1': 'e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0',
  '2': '100',
  '3': '',
  '4': jsonEncode({
    'id': 0,
    'type': 2601,
    'content': {
      'emoji': jsonEncode({'name': ?name, 'previewUrl': 'https://p5.music.126.net/obj/emoji.png'}),
      'user': user ?? _user(),
    },
  }),
  '20': '1790770800000',
  '21': ?from,
  '22': _chatroom,
  '23': '32',
};

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

LookLiveDanmakuConnection _connection(
  _Connector connector,
  _Http http, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration addressRetryDelay = const Duration(milliseconds: 5),
}) => LookLiveDanmakuConnection(
  http: http,
  connector: connector.call,
  policy: policy,
  proxy: proxy,
  now: () => _recordedAt,
  random: _recordedRandom(),
  addressRetryDelay: addressRetryDelay,
);

String _decrypt(String data, String key) =>
    utf8.decode(Aes128Cbc.decrypt(base64Decode(data), key: utf8.encode(key), iv: utf8.encode('0102030405060708')));

/// The plain payload of a `weapi` form.
String _payload(LiveRequest request) {
  final form = Uri.splitQueryString(utf8.decode(request.body!));
  return _decrypt(_decrypt(form['params']!, '0123456789abcdef'), '0CoJUm6Qyw8W8jud');
}

/// Records one request and fails it.
final class _Capturing implements LiveHttp {
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw const TransportFailure(SiteIds.lookLive, TransportReason.connect);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

/// A chat line as the website code shows it (web_expected.js), in this
/// implementation's terms: the sender's id is `userId` (else `from`), the
/// name and text trimmed, levels and the fan club as text when positive.
Map<String, Object?> _fromWeb(Map<String, Object?> line) {
  String level(Object? value) => value is int && value > 0 ? '$value' : '';
  return {
    'id': line['idClient'],
    'userId': '${line['userId'] ?? line['from']}',
    'userName': (line['nick'] as String? ?? '').trim(),
    'text': line['kind'] == 'emoji' ? '[${line['text']}]' : (line['text']! as String).trim(),
    'userLevel': level(line['liveLevel']),
    'fansLevel': level(line['fanClubLevel']),
    'fansName': (line['fanClubName'] as String? ?? '').trim(),
    'sentAt': line['time'],
  };
}

Map<String, Object?> _project(LiveMessage message) => {
  'id': message.messageId,
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
};

void main() {
  group('protocol', () {
    test('the app key, timing, headers and fixed frames', () {
      expect(LookLiveDanmakuProtocol.appKey, '3a6a3e48f6854dfa4e4464f3bdaec3b4');
      expect(
        (LookLiveDanmakuProtocol.sdkVersion, LookLiveDanmakuProtocol.protocolVersion),
        ('47', 1),
        reason: 'the web SDK 5.0.1',
      );
      expect(LookLiveDanmakuProtocol.heartbeatInterval, const Duration(seconds: 30));
      expect(
        LookLiveDanmakuProtocol.heartbeatInterval * LookLiveDanmakuProtocol.ticksPerHeartbeat,
        const Duration(minutes: 3),
        reason: "the SDK's heartbeatInterval 18e4",
      );
      expect(LookLiveDanmakuProtocol.joinTimeout, const Duration(seconds: 10));
      expect(
        (LookLiveDanmakuProtocol.addressAttempts, LookLiveDanmakuProtocol.addressRetryDelay),
        (2, const Duration(seconds: 2)),
      );
      expect(LookLiveDanmakuProtocol.socketHeaders, {'origin': 'https://look.163.com', 'user-agent': 'Mozilla/5.0'});
      expect(LookLiveDanmakuProtocol.heartbeat, '3:::{"SID":1,"CID":2,"SER":0}');
      expect(LookLiveDanmakuProtocol.socketHeartbeat, '2::');
      expect(LookLiveDanmakuProtocol.retriedRefusals, {408, 415, 500, 503});
      expect(LookLiveDanmakuProtocol.kickReasons[LookLiveDanmakuProtocol.silentKick], 'silentlyKick');
    });

    test("the chat server request is the adapter's weapi POST, with the website's payload", () async {
      final request = LookLiveDanmakuProtocol.addressRequest(_room);
      expect('${request.method} ${request.url}', 'POST https://api.look.163.com/weapi/livestream/chat/address');
      expect(_payload(request), '{"liveRoomNo":"447365581","os":0}');
      final recorded = (_meta['requests']! as List).first as Map<String, Object?>;
      expect(jsonDecode(_payload(request)), recorded['payload']);
      expect(request.headers, recorded['headers']);
      // What LookLiveSite sends for its own requests.
      final capturing = _Capturing();
      await expectLater(LookLiveSite(capturing).getRoomDetail(roomId: _room), throwsA(isA<NetworkFailure>()));
      final site = capturing.requests.single;
      expect(
        (request.site, request.method, request.headers, request.followRedirects, request.timeout),
        (site.site, site.method, site.headers, site.followRedirects, site.timeout),
      );
      expect(utf8.decode(request.body!), LookLiveApi.formBody(LookLiveApi.chatAddressPayload(_room)));
      final cancel = CancelToken();
      expect(LookLiveDanmakuProtocol.addressRequest(_room, cancel: cancel).cancel, same(cancel));
    });

    test('endpoints, the socket.io handshake and the socket of a session (the recording)', () {
      final addresses = LookLiveApi.chatAddresses(_recording.first.text);
      final endpoints = LookLiveDanmakuProtocol.endpoints(addresses);
      expect(endpoints.map((endpoint) => '$endpoint'), [
        'wss://chatwl01.yunxinfw.com:443/socket.io/1/websocket/',
        'wss://chatwl01-bgp.yunxinfw.com:443/socket.io/1/websocket/',
        'wss://chatwl02-bgp.yunxinfw.com:443/socket.io/1/websocket/',
        'wss://chatwl02.yunxinfw.com:443/socket.io/1/websocket/',
      ]);
      final recorded = (_meta['requests']! as List)[1] as Map<String, Object?>;
      final t = int.parse(Uri.parse(recorded['url']! as String).queryParameters['t']!);
      final handshake = LookLiveDanmakuProtocol.handshakeRequest(
        endpoints.first,
        roomId: _room,
        now: DateTime.fromMillisecondsSinceEpoch(t),
      );
      // Uri drops https's default port; the website wrote it.
      expect(handshake.url, Uri.parse(recorded['url']! as String));
      expect(handshake.url, Uri.parse(_recording[1].url!));
      expect((handshake.site, handshake.method, handshake.followRedirects), (SiteIds.lookLive, 'GET', false));
      expect(handshake.headers, {
        'origin': 'https://look.163.com',
        'referer': 'https://look.163.com/live?id=447365581',
        'user-agent': 'Mozilla/5.0',
      });
      final plain = LookLiveDanmakuProtocol.handshakeRequest(
        Uri.parse('ws://127.0.0.1:9000/socket.io/1/websocket/'),
        roomId: _room,
        now: _recordedAt,
      );
      expect('${plain.url}', 'http://127.0.0.1:9000/socket.io/1/?t=${_recordedAt.millisecondsSinceEpoch}');
      final session = LookLiveDanmakuProtocol.sessionOf(_response(handshake, _recording[1].text));
      expect(session, '00000000-0000-4000-8000-000000000001');
      final socket = LookLiveDanmakuProtocol.socketUrl(endpoints.first, session);
      expect(socket, Uri.parse(((_meta['handshakes']! as List).single as Map)['url'] as String));
      for (final (status, body) in [
        (500, 'sid:90:30:websocket'),
        (403, 'handshake unauthorized'),
        (200, ''),
        (200, 'sid:90:30'),
        (200, 'sid:90:30:xhr-polling'),
        (200, 'a/b:90:30:websocket'),
        (200, ':90:30:websocket'),
        (200, '<html>'),
      ]) {
        expect(
          () => LookLiveDanmakuProtocol.sessionOf(_response(handshake, body, status: status)),
          throwsFormatException,
          reason: '$status $body',
        );
      }
      expect(LookLiveDanmakuProtocol.sessionOf(_response(handshake, ' s-1_A:25:60:websocket \n')), 's-1_A');
    });

    test('arguments: a room number and a chatroom id the login can carry as a number', () {
      expect(LookLiveDanmakuProtocol.checked(_args), _args);
      expect(
        LookLiveDanmakuProtocol.checked(
          const LookLiveDanmakuArgs(roomId: ' 447365581 ', chatroomId: ' 9902460973 ', anonymousMode: true),
        ),
        const LookLiveDanmakuArgs(roomId: _room, chatroomId: _chatroom, anonymousMode: true),
      );
      expect(
        LookLiveDanmakuProtocol.checked(const LookLiveDanmakuArgs(roomId: _room, chatroomId: '9007199254740991')),
        isNotNull,
      );
      for (final (roomId, chatroomId) in [
        ('', _chatroom),
        ('1', _chatroom),
        ('0447365581', _chatroom),
        ('room', _chatroom),
        (_room, ''),
        (_room, '0'),
        (_room, '09902460973'),
        (_room, '9007199254740992'),
        (_room, '12345678901234567'),
        (_room, '99-1'),
      ]) {
        expect(
          LookLiveDanmakuProtocol.checked(LookLiveDanmakuArgs(roomId: roomId, chatroomId: chatroomId)),
          isNull,
          reason: '$roomId $chatroomId',
        );
      }
    });

    test("the login is the SDK's assembly (web_expected.js) and the recording; again after a reconnect", () {
      final login = _web['login']! as Map<String, Object?>;
      final recorded = _recording[(login['line']! as int) - 1];
      expect(recorded.incoming, isFalse);
      final ours = LookLiveDanmakuProtocol.login(chatroomId: _chatroom, guest: _recordedGuest, serial: 1);
      expect(ours, recorded.text);
      expect(ours, login['assembled']);
      final again = jsonDecode(
        LookLiveDanmakuProtocol.login(
          chatroomId: _chatroom,
          guest: _recordedGuest,
          serial: 2,
          again: true,
        ).substring(4),
      ) as Map<String, Object?>;
      final q = again['Q']! as List;
      expect(again['SER'], 2);
      expect((((q[1] as Map)['v'] as Map)['8'], ((q[2] as Map)['v'] as Map)['8']), (1, 0));
      expect(((q[1] as Map)['v'] as Map)['5'], 9902460973, reason: 'the chatroom as a number, as the website sends it');
    });

    test('the guest: nimanon_ and 32 hex digits, a device and a session of 32 hex digits', () {
      final guest = LookLiveGuest.random(Random(7));
      expect(guest.account, matches(RegExp(r'^nimanon_[0-9a-f]{32}$')));
      expect(guest.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(guest.session, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect({guest.account.substring(8), guest.deviceId, guest.session}, hasLength(3));
      final recorded = LookLiveGuest.random(_recordedRandom());
      expect(
        (recorded.account, recorded.deviceId, recorded.session),
        (_recordedGuest.account, _recordedGuest.deviceId, _recordedGuest.session),
      );
    });

    test('socket.io packets: connect, heartbeat, disconnect, error, noop, acks, other endpoints, framed, bytes', () {
      expect(LookLiveDanmakuProtocol.decode('1::').opened, isTrue);
      expect(LookLiveDanmakuProtocol.decode('2::').replies, ['2::']);
      expect(LookLiveDanmakuProtocol.decode('0::').dropped, isTrue);
      expect(LookLiveDanmakuProtocol.decode('7:::1+0').dropped, isTrue);
      expect(LookLiveDanmakuProtocol.decode('7:::2').dropped, isTrue);
      for (final quiet in ['8::', '5:::{"name":"x"}', '4:::{}', '6:::1', '', 'nonsense', '3:::', '3:::not json']) {
        final frame = LookLiveDanmakuProtocol.decode(quiet);
        expect(
          (frame.opened, frame.dropped, frame.joined, frame.replies.length, frame.messages.length),
          (false, false, false, 0, 0),
          reason: quiet,
        );
      }
      // A message asking for an ack (an id without "+") is acked.
      expect(LookLiveDanmakuProtocol.decode('3:7::{"sid":1,"cid":2,"code":200,"r":[]}').replies, ['6:::7']);
      expect(LookLiveDanmakuProtocol.decode('3:7+::{"sid":1,"cid":2,"code":200,"r":[]}').replies, isEmpty);
      // Packets of another endpoint (namespace) are not the chat's.
      expect(LookLiveDanmakuProtocol.decode('1::/other').opened, isFalse);
      expect(LookLiveDanmakuProtocol.decode(_notify(_text()).replaceFirst('3:::', '3::/other:')).messages, isEmpty);
      // socket.io 0.9's framing: \ufffd<length>\ufffd<packet>…, in UTF-16 units.
      final chat = _notify(_text(text: '表情😀'));
      final framed = LookLiveDanmakuProtocol.decode('\ufffd3\ufffd1::\ufffd${chat.length}\ufffd$chat\ufffd3\ufffd2::');
      expect((framed.opened, framed.messages.single.message), (true, '表情😀'));
      expect(framed.replies, ['2::']);
      expect(LookLiveDanmakuProtocol.decode('\ufffd99\ufffd1::').opened, isFalse, reason: 'a length past the end');
      expect(LookLiveDanmakuProtocol.decode('\ufffdx\ufffd1::').opened, isFalse);
      expect(LookLiveDanmakuProtocol.decode(utf8.encode(_notify(_text()))).messages.single.message, '大家好');
      expect(LookLiveDanmakuProtocol.decode([0xff, 0xfe]).messages, isEmpty);
      expect(LookLiveDanmakuProtocol.decode(null).messages, isEmpty);
      expect(LookLiveDanmakuProtocol.decode(42).opened, isFalse);
    });

    test('answers: the login and its refusal, kicks, messages direct or in a notification; unreadable ones', () {
      expect(LookLiveDanmakuProtocol.decode(_loginAnswer()).joined, isTrue);
      final refused = LookLiveDanmakuProtocol.decode(_loginAnswer(code: 404));
      expect((refused.joined, refused.refusal), (false, 404));
      expect(LookLiveDanmakuProtocol.decode('3:::{"sid":13,"cid":2,"r":[]}').refusal, 0, reason: 'no code');
      expect(LookLiveDanmakuProtocol.decode('3:::{"sid":"13","cid":"2","code":"200","r":[]}').joined, isTrue);
      expect(LookLiveDanmakuProtocol.decode('3:::{"sid":13,"cid":3,"code":200,"r":[1,""]}').kicked, 1);
      expect(
        LookLiveDanmakuProtocol.decode(
          '3:::{"sid":4,"cid":10,"code":200,"r":[0,{"body":[5,""],"headerPacket":{"sid":13,"cid":3}}]}',
        ).kicked,
        5,
        reason: 'a kick in a notification',
      );
      expect(LookLiveDanmakuProtocol.decode('3:::{"sid":13,"cid":3,"code":200,"r":[]}').kicked, 0);
      // 13-7 directly, and wrapped (4-10 as recorded, and 4-11).
      final direct =
          '3:::${jsonEncode({
            'sid': 13,
            'cid': 7,
            'code': 200,
            'r': [_text()],
          })}';
      expect(LookLiveDanmakuProtocol.decode(direct).messages.single.message, '大家好');
      expect(LookLiveDanmakuProtocol.decode(_notify(_text())).messages.single.message, '大家好');
      expect(
        LookLiveDanmakuProtocol.decode(_notify(_text()).replaceFirst('"cid":10', '"cid":11')).messages,
        hasLength(1),
      );
      expect(LookLiveDanmakuProtocol.decode(_notify(_text(), code: 500)).messages, isEmpty);
      expect(LookLiveDanmakuProtocol.decode(_notify(_text(), cid: 6)).messages, isEmpty, reason: 'not 13-7');
      for (final bad in [
        '3:::[]',
        '3:::{"cid":7}',
        '3:::{"sid":4,"cid":10,"code":200,"r":[0]}',
        '3:::{"sid":4,"cid":10,"code":200,"r":[0,{"body":[]}]}',
        '3:::{"sid":4,"cid":10,"code":200,"r":[0,{"headerPacket":{"sid":13,"cid":7},"body":{}}]}',
        '3:::{"sid":4,"cid":10,"code":200,"r":[0,{"headerPacket":{"sid":13},"body":[]}]}',
        '3:::{"sid":4,"cid":10,"code":200,"r":"x"}',
        '3:::{"sid":13,"cid":7,"code":200,"r":{}}',
        '3:::{"sid":1,"cid":2,"code":200,"r":[]}',
      ]) {
        final frame = LookLiveDanmakuProtocol.decode(bad);
        expect((frame.messages.length, frame.joined, frame.kicked, frame.refusal), (0, false, null, null), reason: bad);
      }
    });

    test('a chat line: text, sender, levels, fan club, message id and time', () {
      final message = LookLiveDanmakuProtocol.chat(_text())!;
      expect(message.type, LiveMessageType.chat);
      expect(message.color, LiveMessageColor.white);
      expect(_project(message), {
        'id': '8878bc5ff6cc45dead8734cd26b0f3b8',
        'userId': '1000000002',
        'userName': '观众2',
        'text': '大家好',
        'userLevel': '21',
        'fansLevel': '11',
        'fansName': '偏爱离',
        'sentAt': 1790770791719,
      });
      expect(message.sentAt!.isUtc, isFalse);
    });

    test('chat boundaries: types, text, the iplay wrapper, risk levels, senders, levels and times', () {
      LiveMessage? chat(Map<String, Object?> message, {bool anonymousMode = false}) =>
          LookLiveDanmakuProtocol.chat(message, anonymousMode: anonymousMode);
      String custom(Map<String, Object?> value) => jsonEncode(value);
      // Not chat.
      for (final (reason, message) in [
        ('no text', _text(text: null)),
        ('empty text', _text(text: '')),
        ('blank text', _text(text: '  ')),
        ('text not a string', _text(text: true)),
        ('no custom', {..._text()}..remove('4')),
        ('custom not JSON', _text(custom: '{bad')),
        ('custom not an object', _text(custom: '[1]')),
        ('custom empty', _text(custom: '')),
        ('custom not text', _text(custom: 7)),
        ('another bizName', _text(custom: custom(_custom(bizName: 'other')))),
        ('no bizName', _text(custom: custom(_custom(bizName: null)))),
        ('no content', _text(custom: custom({'bizName': 'iplay'}))),
        ('content not an object', _text(custom: custom({'bizName': 'iplay', 'content': 'x'}))),
        ('no user', _text(custom: custom(_custom(content: {'text': '大家好'})))),
        ('user not an object', _text(custom: custom(_custom(content: {'user': 'x'})))),
        (
          'a risk level the guest lacks',
          _text(
            custom: custom(
              _custom(
                content: {
                  'user': _user(),
                  'commonCtrl': {'riskLevelKey': 'level2'},
                },
              ),
            ),
          ),
        ),
        (
          'a numeric risk level',
          _text(
            custom: custom(
              _custom(
                content: {
                  'user': _user(),
                  'commonCtrl': {'riskLevelKey': 3},
                },
              ),
            ),
          ),
        ),
        ('another message type', _text(type: '1')),
        ('a notification', _text(type: '5')),
        ('no type', _text(type: null)),
        (
          'a custom message that is not an emoji',
          {
            ..._emoji(),
            '4': jsonEncode({
              'id': 0,
              'type': 114,
              'content': {'user': _user()},
            }),
          },
        ),
        ('an emoji not from the server', _emoji(from: '1000000002')),
        ('an emoji without a name', _emoji(name: '')),
        (
          'an emoji without a sender',
          {
            ..._emoji(),
            '4': jsonEncode({
              'type': 2601,
              'content': {'emoji': '{"name":"比心"}'},
            }),
          },
        ),
        (
          'an emoji that is not JSON',
          {
            ..._emoji(),
            '4': jsonEncode({
              'type': 2601,
              'content': {'emoji': '比心', 'user': _user()},
            }),
          },
        ),
      ]) {
        expect(chat(message), isNull, reason: reason);
      }
      expect(LookLiveDanmakuProtocol.chat('x'), isNull);
      expect(LookLiveDanmakuProtocol.chat(null), isNull);
      // A risk level that is empty, null, false or 0 is shown (the website's `!(o && !i[o])`).
      for (final key in [null, '', false, 0]) {
        final message = _text(
          custom: custom(
            _custom(
              content: {
                'user': _user(),
                'commonCtrl': {'riskLevelKey': key},
              },
            ),
          ),
        );
        expect(chat(message)?.message, '大家好', reason: '$key');
      }
      // Text: trimmed; a number as text; type as a number.
      expect(chat(_text(text: '  你好 \n'))!.message, '你好');
      expect(chat(_text(text: 7))!.message, '7', reason: 'the page shows a number too');
      expect(chat(_text(type: 0))!.message, '大家好');
      // Sender: nickname, else nickName; ids as numbers or text, else `from`.
      LiveMessage sent(Map<String, Object?> user, {Object? from = '1000000002'}) => chat(
        _text(
          from: from,
          custom: custom(_custom(user: user)),
        ),
      )!;
      expect(sent(_user(nickname: null)..['nickName'] = '别名').userName, '别名');
      expect(sent(_user(nickname: '')..['nickName'] = '别名').userName, '别名');
      expect(sent(_user(nickname: ' 名字 ')).userName, '名字');
      expect(sent(_user(nickname: null)).userName, '');
      expect(sent(_user(userId: '123')).userId, '123');
      expect(sent(_user(userId: null)).userId, '1000000002');
      expect(sent(_user(userId: null), from: null).userId, '');
      // Levels: positive whole numbers (or their text), else ''.
      for (final (value, expected) in [(0, ''), (-1, ''), ('12', '12'), (1.5, ''), (null, ''), (true, '')]) {
        final message = chat(
          _text(
            custom: custom(
              _custom(
                user: _user(liveLevel: value, fanClubLevel: value, fanClubName: null),
              ),
            ),
          ),
        )!;
        expect((message.userLevel, message.fansLevel, message.fansName), (expected, expected, ''), reason: '$value');
      }
      // The fan club of fanClubInfo when the user's own is missing.
      final info = chat(
        _text(
          custom: custom(
            _custom(
              user: _user(fanClubLevel: null, fanClubName: null)
                ..['fanClubInfo'] = {'fanClubLevel': 3, 'fanClubName': '粉团'},
            ),
          ),
        ),
      )!;
      expect((info.fansLevel, info.fansName), ('3', '粉团'));
      // Ids and times.
      expect(chat(_text(id: null))!.messageId, '');
      for (final (value, expected) in [
        ('1790770791719', 1790770791719),
        (1790770791719, 1790770791719),
        ('0', null),
        ('-5', null),
        ('x', null),
        (null, null),
        ('8640000000000000', 8640000000000000),
        ('8640000000000001', null),
      ]) {
        expect(chat(_text(time: value))!.sentAt?.millisecondsSinceEpoch, expected, reason: '$value');
      }
    });

    test('emoji messages (2601) are chat in brackets; short-keyed customs (sp 1) are expanded as parseIM does', () {
      final emoji = LookLiveDanmakuProtocol.chat(_emoji())!;
      expect(
        (emoji.message, emoji.userName, emoji.userId, emoji.messageId),
        ('[比心]', '观众2', '1000000002', 'e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0'),
      );
      expect(LookLiveDanmakuProtocol.chat({..._emoji(), '2': 100})!.message, '[比心]');
      // encodeIM's short keys: c content, u user, n nickname, i userId, l
      // liveLevel, fcl/fcn the fan club; unknown keys keep their names.
      final short = {
        'sp': 1,
        'bizName': 'iplay',
        'sourceType': 2,
        'c': {
          'ir': false,
          'u': {'n': '短名', 'i': 42, 'l': 7, 'fcl': 2, 'fcn': '团', 'a': 'x/1.jpg', 'extra': 1},
          'commonCtrl': {'riskLevelKey': null},
        },
      };
      final expanded = LookLiveDanmakuProtocol.chat(_text(custom: jsonEncode(short)))!;
      expect(
        (expanded.userName, expanded.userId, expanded.userLevel, expanded.fansLevel, expanded.fansName),
        ('短名', '42', '7', '2', '团'),
      );
      // Without sp 1 the short keys are not names.
      expect(LookLiveDanmakuProtocol.chat(_text(custom: jsonEncode({...short, 'sp': 0}))), isNull);
      expect(
        LookLiveDanmakuProtocol.chat(
          _text(
            custom: jsonEncode({
              ...short,
              'c': [short['c']],
            }),
          ),
        ),
        isNull,
        reason: 'content not an object',
      );
    });

    test("anonymous rooms show a name's first character and *** (the room page)", () {
      String? name(Object? nickname) => LookLiveDanmakuProtocol.chat(
        _text(
          custom: jsonEncode(_custom(user: _user(nickname: nickname))),
        ),
        anonymousMode: true,
      )?.userName;
      expect(name('观众2'), '观***');
      expect(name('😀笑脸'), '😀***', reason: 'a whole code point, not half a surrogate pair');
      expect(name('a'), 'a***');
      expect(name(''), '');
      expect(name(null), '');
      expect(LookLiveDanmakuProtocol.chat(_emoji(), anonymousMode: true)!.userName, '观***');
      expect(LookLiveDanmakuProtocol.decode(_notify(_text()), anonymousMode: true).messages.single.userName, '观***');
    });
  });

  group('recording (S05-live)', () {
    test("the recorded requests, handshake and socket are the protocol's", () {
      final [address, handshake] = (_meta['requests']! as List).cast<Map<String, Object?>>();
      expect(address['url'], '${LookLiveApi.apiOrigin}${LookLiveApi.chatAddressPath}');
      expect(address['payload'], LookLiveApi.chatAddressPayload(_room));
      expect(address['headers'], LookLiveApi.requestHeaders);
      expect(_recording.first.url, address['url']);
      expect(handshake['url'], _recording[1].url);
      final socket = (_meta['handshakes']! as List).single as Map<String, Object?>;
      expect((socket['headers']! as Map)['origin'], LookLiveDanmakuProtocol.socketHeaders['origin']);
      expect(_meta['danmakuKeys'], {'roomId': _room, 'chatroomId': _chatroom, 'anonymousMode': false});
    });

    test('every incoming frame decodes as the website code does (expected.json)', () {
      final web = (_web['frames']! as List).cast<Map<String, Object?>>();
      final incoming = [
        for (final frame in _recording)
          if (frame.incoming && frame.url == null) frame,
      ];
      expect(web.map((frame) => frame['line']), incoming.map((frame) => frame.line));
      var chats = 0;
      for (final (index, frame) in incoming.indexed) {
        final expected = web[index];
        final decoded = LookLiveDanmakuProtocol.decode(frame.text);
        final reason = 'line ${frame.line}';
        expect(decoded.opened, (expected['packets']! as List).contains('connect'), reason: reason);
        expect(decoded.replies, expected['replies'], reason: reason);
        expect(decoded.joined, expected['joined'], reason: reason);
        expect((decoded.refusal, decoded.kicked, decoded.dropped), (null, null, false), reason: reason);
        expect(decoded.messages.map(_project), [
          for (final line in (expected['chat']! as List).cast<Map<String, Object?>>()) _fromWeb(line),
        ], reason: reason);
        chats += decoded.messages.length;
      }
      expect(chats, 47, reason: '47 chat lines: 35 of the room assistant, 12 of two viewers');
      expect(web.where((frame) => frame['joined'] == true).single['line'], 5);
    });

    test('the connection replays the recording: one handshake, the login, ready, 47 chats, the echoes', () async {
      final http = _Http(sessions: [_recording[1].text]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      expect(_payload(http.addressRequests.single), '{"liveRoomNo":"447365581","os":0}');
      expect('${http.handshakes.single.url}', startsWith('https://chatwl01.yunxinfw.com/socket.io/1/?t='));
      expect(connector.endpoints.map((endpoint) => '$endpoint'), [
        ((_meta['handshakes']! as List).single as Map)['url'],
      ]);
      final socket = connector.channels.single;
      for (final frame in _recording.skip(2)) {
        if (frame.incoming) {
          await socket.receive(frame.text);
        } else if (frame.text == LookLiveDanmakuProtocol.heartbeat) {
          connection.heartbeat();
        }
      }
      expect(socket.sent, [
        for (final frame in _recording.skip(2))
          if (!frame.incoming && frame.text != '0::') frame.text,
      ], reason: 'the login, 12 echoes and the link heartbeat; the recorder said 0:: when it left');
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events), hasLength(47));
      expect(connection.isConnected, isTrue);
      await connection.close();
    });
  });

  group('gifts (D07.7, S06-gifts)', () {
    final lines = [
      for (final line in File('../../fixtures/looklive/danmaku/S06-gifts/frames.jsonl').readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['text']! as String,
    ];

    test('S06: every recorded custom message 102 is a gift: name, count, worth in notes, picture, sender', () {
      final messages = [for (final line in lines) ...LookLiveDanmakuProtocol.decode(line).messages];
      expect(
        [for (final m in messages) (m.userName, m.message, (m.data! as LiveGift).totalValue)],
        [('观众1', '小麦穗 ×1', 1), ('观众2', '时光相册 ×1', 1), ('观众3', '时光相册 ×1', 1), ('观众4', '旋转木马 ×1', 100)],
      );
      final first = messages.first;
      expect(
        (first.type, first.userId, first.userLevel, first.fansLevel, first.fansName, first.messageId, first.sentAt),
        (
          LiveMessageType.gift,
          '7000000001',
          '38',
          '18',
          '口果汁',
          '5ec5af7d94fc432bbe36dcb7eb6d43b7',
          DateTime.fromMillisecondsSinceEpoch(1791531626046),
        ),
      );
      expect(
        first.data,
        LiveGift(
          id: '14193526',
          name: '小麦穗',
          unitPrice: 1,
          totalValue: 1,
          unit: LiveGiftUnit.note,
          iconUrl: Uri.parse('https://p1.music.126.net/rS6UvA8RznaFOobx26Uj8g==/109951173868759962.jpg'),
        ),
      );
      final masked = LookLiveDanmakuProtocol.decode(lines.last, anonymousMode: true).messages.single;
      expect(masked.userName, '观***');
    });

    test('what is not a gift: chat, other custom types, no gift id; a receiver', () {
      Map<String, Object?> message(Map<String, Object?> custom, {String type = '100'}) => {
        '1': 'id',
        '2': type,
        '4': jsonEncode(custom),
        '20': '1791531626046',
      };
      LiveMessage? read(Map<String, Object?> m) => LookLiveDanmakuProtocol.gift(m);
      const content = {
        'giftId': 7,
        'giftName': '花',
        'number': 3,
        'giftWorth': 10,
        'user': {'userId': 5, 'nickName': 'a'},
      };
      expect(read(message({'type': 102, 'content': content}, type: '0')), isNull);
      expect(read(message({'type': 114, 'content': content})), isNull);
      expect(
        read(
          message({
            'type': 102,
            'content': {...content, 'giftId': 0},
          }),
        ),
        isNull,
      );
      expect(read(message({'type': 102})), isNull);
      final gift =
          read(
                message({
                  'type': 102,
                  'content': {
                    ...content,
                    'receiver': {'nickName': '嘉宾'},
                    'giftIconUrl': 'x',
                  },
                }),
              )!.data!
              as LiveGift;
      expect(
        gift,
        const LiveGift(
          id: '7',
          name: '花',
          count: 3,
          unitPrice: 10,
          totalValue: 30,
          unit: LiveGiftUnit.note,
          receiverName: '嘉宾',
        ),
      );
    });
  });

  group('connection', () {
    test('timing and registration', () {
      final connection = LookLiveDanmakuConnection(http: _Http());
      expect(connection.heartbeatInterval, const Duration(seconds: 30));
      expect(LookLiveDanmakuConnection.defaultPolicy.joinTimeout, const Duration(seconds: 10));
      expect(LookLiveDanmakuConnection.defaultPolicy.inactivityTimeout, isNull, reason: 'the default: 3 × 30 s = 90 s');
      final registry = DanmakuRegistry({SiteIds.lookLive: () => LookLiveDanmakuConnection(http: _Http())});
      expect(registry.supports('looklive'), isTrue);
      expect(registry.connectionFor('LookLive'), isA<LookLiveDanmakuConnection>());
    });

    test('the handshake: chat servers, a socket.io session, the socket; login on 1::, ready on its answer', () async {
      final http = _Http();
      final connector = _Connector();
      const proxy = FixedProxyPolicy(perSite: {'looklive': HttpProxyRoute('127.0.0.1', 7897)});
      final connection = _connection(connector, http, proxy: proxy);
      final events = _record(connection);
      await connection.connect(_args);
      expect(http.requests.map((request) => '${request.method} ${request.url}'), [
        'POST https://api.look.163.com/weapi/livestream/chat/address',
        'GET https://chatwl01.yunxinfw.com/socket.io/1/?t=${_recordedAt.millisecondsSinceEpoch}',
      ]);
      expect(http.handshakes.single.timeout, const Duration(seconds: 10), reason: "the socket's connect timeout");
      expect(connector.endpoints.map((endpoint) => '$endpoint'), [
        'wss://chatwl01.yunxinfw.com:443/socket.io/1/websocket/sid1',
      ]);
      expect(connector.headers.single, LookLiveDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, const HttpProxyRoute('127.0.0.1', 7897));
      final socket = connector.channels.single;
      expect(socket.sent, isEmpty, reason: 'nothing before the session opens');
      expect(events, isEmpty);
      await socket.receive('1::');
      expect(socket.sent, [LookLiveDanmakuProtocol.login(chatroomId: _chatroom, guest: _recordedGuest, serial: 1)]);
      await socket.receive('1::');
      expect(socket.logins, hasLength(1), reason: 'one login per socket');
      expect(connection.isConnected, isFalse);
      await socket.receive(_loginAnswer());
      expect(events, [const DanmakuReady()]);
      await socket.receive(_notify(_text()));
      await socket.receive(
        _notify({
          ..._emoji(),
          '4': jsonEncode({'id': 0, 'type': 114, 'content': <String, Object?>{}}),
        }),
      );
      expect(_messages(events).map((message) => message.message), ['大家好']);
      await connection.close();
    });

    test('chat servers: a room that is not live ends at once; one retry after a failure; then the end', () async {
      final notLive = _Http(addresses: [_notLive]);
      final connector = _Connector();
      final connection = _connection(connector, notLive);
      final events = _record(connection);
      await connection.connect(_args);
      expect(
        events.single,
        isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.connectionFailed),
      );
      expect((events.single as DanmakuClosed).detail, startsWith('No chat: '));
      expect(notLive.requests, hasLength(1));
      expect(connector.endpoints, isEmpty);
      // One failure: asked again, then joined.
      final flaky = _Http(
        addresses: [const TransportFailure(SiteIds.lookLive, TransportReason.connect), _addressAnswer()],
      );
      final second = _Connector();
      final retried = _connection(second, flaky);
      final retriedEvents = _record(retried);
      await retried.connect(_args);
      expect(flaky.addressRequests, hasLength(2));
      await second.channels.single.join();
      expect(retriedEvents, [const DanmakuReady()]);
      await retried.close();
      // Two failures (an HTTP error, an answer without servers): the end.
      final failing = _Http(
        addresses: [
          (503, ''),
          _addressAnswer(['bad']),
        ],
      );
      final third = _Connector();
      final failed = _connection(third, failing);
      final failedEvents = _record(failed);
      await failed.connect(_args);
      expect(failing.addressRequests, hasLength(2));
      expect(third.endpoints, isEmpty);
      expect(failedEvents.single, isA<DanmakuClosed>());
      expect((failedEvents.single as DanmakuClosed).detail, startsWith('Chat servers: ApiChanged'));
    });

    test(
      'a failed socket.io session counts as a failed handshake: the next server, then the reconnects run out',
      () async {
        final http = _Http(
          addresses: [
            _addressAnswer(['a.example.com:443', 'b.example.com:443']),
          ],
          sessions: [(500, 'error'), 'sid:90:30:xhr-polling', 'ok:90:30:websocket'],
        );
        final connector = _Connector();
        final connection = _connection(connector, http);
        final events = _record(connection);
        await connection.connect(_args);
        await _until(() => connector.channels.isNotEmpty);
        expect(http.handshakes.map((request) => request.url.host), ['a.example.com', 'b.example.com', 'a.example.com']);
        expect('${connector.endpoints.single}', 'wss://a.example.com:443/socket.io/1/websocket/ok');
        expect(events.whereType<DanmakuReconnecting>(), hasLength(1));
        await connector.channels.single.join();
        expect(events.last, const DanmakuReady());
        await connection.close();
        // Sessions that never come: eight attempts, then the end.
        final never = _Http(sessions: [const TransportFailure(SiteIds.lookLive, TransportReason.connect)]);
        final none = _Connector();
        final exhausted = _connection(none, never);
        final exhaustedEvents = _record(exhausted);
        await exhausted.connect(_args);
        await _until(() => exhaustedEvents.any((event) => event is DanmakuClosed));
        expect((exhaustedEvents.last as DanmakuClosed).reason, DanmakuCloseReason.reconnectsExhausted);
        expect(never.handshakes, hasLength(9));
        expect(none.endpoints, isEmpty);
      },
    );

    test('a dropped socket: a new session and login (serial 2, again), ready again', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      await first.join();
      await first.incoming.close();
      await _until(() => connector.channels.length == 2);
      final second = connector.channels.last;
      await second.join();
      expect('${connector.endpoints.last}', endsWith('/sid2'));
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      final login = second.logins.single;
      final q = login['Q']! as List;
      expect(login['SER'], 2);
      expect((((q[1] as Map)['v'] as Map)['8'], ((q[2] as Map)['v'] as Map)['8']), (1, 0));
      expect(((q[1] as Map)['v'] as Map)['2'], _recordedGuest.account, reason: 'the same guest for the run');
      expect(http.addressRequests, hasLength(1), reason: 'the chat servers are asked once per connect');
      await connection.close();
    });

    test('0:: and 7::: from the server replace the socket', () async {
      for (final packet in ['0::', '7:::1+0']) {
        final connector = _Connector();
        final connection = _connection(connector, _Http());
        final events = _record(connection);
        await connection.connect(_args);
        await connector.channels.single.join();
        await connector.channels.single.receive(packet);
        await _until(() => connector.channels.length == 2);
        expect(connector.channels.first.closed, isTrue, reason: packet);
        await connector.channels.last.join();
        expect(events.whereType<DanmakuReady>(), hasLength(2), reason: packet);
        await connection.close();
      }
    });

    test('refused logins: codes that may pass reconnect, three in a row at most; others end at once', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http());
      final events = _record(connection);
      await connection.connect(_args);
      for (var socket = 0; socket < 3; socket++) {
        await _until(() => connector.channels.length == socket + 1);
        await connector.channels.last.receive('1::');
        await connector.channels.last.receive(_loginAnswer(code: 503));
      }
      await _until(() => connector.channels.length == 4);
      // A join in between starts the count again.
      await connector.channels.last.join();
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await connector.channels.last.receive('0::');
      for (var socket = 4; socket < 8; socket++) {
        await _until(() => connector.channels.length == socket + 1);
        await connector.channels.last.receive('1::');
        await connector.channels.last.receive(_loginAnswer(code: 415));
      }
      await _until(() => events.last is DanmakuClosed);
      expect(connector.channels, hasLength(8));
      expect(events.last, const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Login refused: 415'));
      // A chatroom that is gone ends the run at once.
      final gone = _Connector();
      final ended = _connection(gone, _Http());
      final endedEvents = _record(ended);
      await ended.connect(_args);
      await gone.channels.single.receive('1::');
      await gone.channels.single.receive(_loginAnswer(code: 13002));
      expect(endedEvents, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Login refused: 13002')]);
      await _wait(const Duration(milliseconds: 20));
      expect(gone.channels, hasLength(1));
      expect(gone.channels.single.closed, isTrue);
    });

    test('kicks: a silent one reconnects; any other ends the run', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http());
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join();
      await connector.channels.single.receive('3:::{"sid":13,"cid":3,"code":200,"r":[4,""]}');
      await _until(() => connector.channels.length == 2);
      await connector.channels.last.join();
      await connector.channels.last.receive('3:::{"sid":13,"cid":3,"code":200,"r":[1,""]}');
      expect(events.last, const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Kicked: chatroomClosed'));
      for (final (reason, name) in [(2, 'managerKick'), (5, 'blacked'), (9, '9'), (0, '0')]) {
        final other = _Connector();
        final kicked = _connection(other, _Http());
        final kickedEvents = _record(kicked);
        await kicked.connect(_args);
        await other.channels.single.join();
        await other.channels.single.receive('3:::{"sid":13,"cid":3,"code":200,"r":[$reason]}');
        expect((kickedEvents.last as DanmakuClosed).detail, 'Kicked: $name');
      }
    });

    test('an unanswered login times out and reconnects', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        _Http(),
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          // Wide enough that a loaded machine never lets the timer beat the
          // step the test takes next.
          joinTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.receive('1::');
      await _until(() => connector.channels.length == 2);
      await connector.channels.last.join();
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await _wait(const Duration(milliseconds: 1300));
      expect(connector.channels, hasLength(2), reason: 'a joined socket has no timer');
      await connection.close();
    });

    test('heartbeats: 2:: is echoed; the link heartbeat every sixth tick after the login, and on demand', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        _Http(),
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      await connection.connect(_args);
      final socket = connector.channels.single;
      await socket.receive('2::');
      expect(socket.sent, ['2::']);
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 150));
      expect(socket.heartbeats, 0, reason: 'nothing before the login');
      // Taken before the login: the sixth tick after it is at least 100 ms
      // later, however long the login takes to process.
      final joinedAt = DateTime.now();
      await socket.join();
      await _until(() => socket.heartbeats == 1);
      expect(DateTime.now().difference(joinedAt), greaterThanOrEqualTo(const Duration(milliseconds: 100)));
      connection.heartbeat();
      expect(socket.heartbeats, 2, reason: 'at once on demand');
      await connection.close();
      LookLiveDanmakuConnection(http: _Http()).heartbeat();
    });

    test('unusable arguments end at once, without a request; other argument types are rejected', () async {
      final http = _Http();
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const LookLiveDanmakuArgs(roomId: _room, chatroomId: '0'));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable room or chatroom')]);
      expect(http.requests, isEmpty);
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect(const PandaLiveDanmakuArgs(userId: 'x', channel: '1')), throwsArgumentError);
    });

    test('after close nothing is reported and pending requests are cancelled; connect replaces the room', () async {
      final pending = Completer<String>();
      final http = _Http(addresses: [pending]);
      final connector = _Connector();
      final connection = _connection(connector, http);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.isNotEmpty);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      expect(connector.endpoints, isEmpty);
      // A session request in flight.
      final session = Completer<String>();
      final slow = _Http(sessions: [session]);
      final slowConnector = _Connector();
      final slowConnection = _connection(slowConnector, slow);
      final slowConnecting = slowConnection.connect(_args);
      await _until(() => slow.handshakes.isNotEmpty);
      await slowConnection.close();
      await slowConnecting;
      expect(slow.handshakes.single.cancel!.isCancelled, isTrue);
      expect(slowConnector.endpoints, isEmpty);
      // A joined socket, then another room.
      final replaced = _Connector();
      final switching = _connection(replaced, _Http());
      final switchingEvents = _record(switching);
      await switching.connect(_args);
      await replaced.channels.single.join();
      await switching.connect(const LookLiveDanmakuArgs(roomId: '21623631', chatroomId: '462192286'));
      expect(replaced.channels.first.closed, isTrue);
      await replaced.channels.last.receive('1::');
      final login = replaced.channels.last.logins.single;
      expect((((login['Q']! as List)[1] as Map)['v'] as Map)['5'], 462192286);
      await replaced.channels.first.receive(_notify(_text()));
      expect(_messages(switchingEvents), isEmpty, reason: "the old room's socket is silent");
      await switching.close();
      final closedCount = switchingEvents.length;
      await replaced.channels.last.receive(_loginAnswer());
      await replaced.channels.last.receive(_notify(_text()));
      expect(switchingEvents, hasLength(closedCount));
      expect(events, isEmpty);
    });

    test('an anonymous room masks the names', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http());
      final events = _record(connection);
      await connection.connect(const LookLiveDanmakuArgs(roomId: _room, chatroomId: _chatroom, anonymousMode: true));
      await connector.channels.single.join();
      await connector.channels.single.receive(_notify(_text()));
      expect(_messages(events).single.userName, '观***');
      await connection.close();
    });

    test('a real local server: the socket.io handshake, the socket, the login, the echo and chat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      final real = IoLiveHttp();
      addTearDown(() async {
        real.close();
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final seen = <String, String?>{};
      final received = <Object?>[];
      server.listen((request) async {
        if (request.uri.path == '/socket.io/1/') {
          seen['handshake'] = '${request.uri}';
          seen['referer'] = request.headers.value('referer');
          request.response.write('local-sid:90:30:websocket,xhr-polling');
          await request.response.close();
          return;
        }
        seen['socket'] = request.uri.path;
        seen['origin'] = request.headers.value('origin');
        seen['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket
          ..add('1::')
          ..listen((frame) {
            received.add(frame);
            if (frame is String && frame.startsWith('3:::{"SID":13')) {
              socket
                ..add(_loginAnswer())
                ..add('\ufffd3\ufffd2::\ufffd${_notify(_text()).length}\ufffd${_notify(_text())}');
            }
          });
      });
      final http = _Delegating(real, addresses: _addressAnswer(['127.0.0.1:${server.port}']));
      final connection = LookLiveDanmakuConnection(
        http: http,
        now: () => _recordedAt,
        random: _recordedRandom(),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.scheme, 'wss');
          return connectIoSocket(
            endpoint.replace(scheme: 'ws'),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).isNotEmpty && received.length == 2);
      connection.heartbeat();
      await _until(() => received.length == 3);
      expect(seen['handshake'], '/socket.io/1/?t=${_recordedAt.millisecondsSinceEpoch}');
      expect(seen['referer'], 'https://look.163.com/live?id=447365581');
      expect(seen['socket'], '/socket.io/1/websocket/local-sid');
      expect(seen['origin'], 'https://look.163.com');
      expect(seen['user-agent'], endsWith('Mozilla/5.0'), reason: 'dart:io puts its own name first');
      expect(received, [
        LookLiveDanmakuProtocol.login(chatroomId: _chatroom, guest: _recordedGuest, serial: 1),
        '2::',
        LookLiveDanmakuProtocol.heartbeat,
      ]);
      expect(events.first, const DanmakuReady());
      expect(_messages(events).single.message, '大家好');
      await connection.close();
    });
  });
}

/// Answers the chat server request itself and sends the socket.io
/// handshakes to the real [http] over plain HTTP (the local server).
final class _Delegating implements LiveHttp {
  new(this.http, {required this.addresses});

  final LiveHttp http;
  final String addresses;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if (request.url.path == LookLiveApi.chatAddressPath) return _response(request, addresses);
    return await http.send(
      LiveRequest(
        site: request.site,
        url: request.url.replace(scheme: 'http'),
        headers: request.headers,
        followRedirects: request.followRedirects,
        timeout: request.timeout,
        cancel: request.cancel,
      ),
    );
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}
