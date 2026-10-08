import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/bigo/danmaku';

typedef _Line = ({int line, bool incoming, String? url, String text});

/// One recording: its lines (the `getWebSocketLink` request and answer, then
/// the socket's text frames), `meta.json` and the website's reading
/// (`expected.json`, written by web_expected.py).
final class _Sample {
  new(this.name)
    : lines = [
        for (final (index, line) in File('$_root/$name/frames.jsonl').readAsLinesSync().indexed)
          if (jsonDecode(line) case {'dir': final String dir} && final Map<String, Object?> frame)
            (
              line: index + 1,
              incoming: dir == 'in',
              url: frame['url'] as String?,
              text: (frame['text'] ?? frame['form'])! as String,
            ),
      ],
      meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>,
      expected = jsonDecode(File('$_root/$name/expected.json').readAsStringSync()) as Map<String, Object?>;

  final String name;
  final List<_Line> lines;
  final Map<String, Object?> meta;
  final Map<String, Object?> expected;

  Map<String, Object?> get value => expected['value']! as Map<String, Object?>;

  BigoDanmakuArgs get args {
    final keys = meta['danmakuKeys']! as Map<String, Object?>;
    return BigoDanmakuArgs(
      siteId: keys['siteId']! as String,
      ownerId: keys['ownerId']! as int,
      roomId: keys['roomId']! as String,
    );
  }

  /// The recorded `getWebSocketLink` answer.
  _Line get link => lines.firstWhere((line) => line.incoming && line.url != null);

  /// The socket's frames.
  Iterable<_Line> get socket => lines.where((line) => line.url == null);

  /// The website's reading of each received frame, by line.
  Map<int, Map<String, Object?>> get reading => {
    for (final frame in (value['frames']! as List).cast<Map<String, Object?>>()) frame['line']! as int: frame,
  };
}

final _Sample _live = _Sample('S05-live');
final _Sample _idle = _Sample('S06-idle');
final _Sample _unsigned = _Sample('S07-unsigned');

/// When S05 was recorded: "now" of every connection here.
final DateTime _recordedAt = DateTime.parse(_live.meta['capturedAt']! as String);

final BigoDanmakuArgs _args = _live.args;
const String _room = '6309489689319799326';

/// No heartbeat, watchdog or join timer, a short backoff: only what the test
/// does happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

LiveResponse _answer(String text, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(text), url: BigoDanmakuProtocol.linkUrl);

/// A `getWebSocketLink` answer for visitor [userId].
LiveResponse _visitor({String userId = '1000000002', Object? token = 'VisitorToken0000+/=', int code = 0}) => _answer(
  jsonEncode({
    'code': code,
    'data': {
      'pro_time': null,
      'uidToken': token,
      'userId': userId,
      'userName': '0',
      'seqId': '100000002',
      'deviceId': 'web_fedcba9876543210fedcba9876543210_Visitr_1790771602072',
      'wssLinkd': <Object>[],
      'realUser': null,
    },
    'msg': 'success',
    'flag': null,
  }),
);

/// Answers `getWebSocketLink` from a script: each entry is a response, an
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
          (_) => throw const TransportFailure(SiteIds.bigo, TransportReason.cancelled),
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

  /// Delivers [frame] and lets the connection handle it (and a zero login
  /// delay run out).
  Future<void> receive(Object frame) async {
    incoming.add(frame);
    await _settle();
  }

  /// The uris of the frames sent.
  List<int> get uris => [for (final frame in sent) int.parse((frame as String).substring(0, frame.indexOf('{')))];

  /// The server's side of a join: challenge, login accepted, room entered.
  Future<void> join({String sid = '2112191006'}) async {
    await receive(_challenge);
    await receive(_loginReply());
    await receive(_enterReply(sid: sid));
  }
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

const String _challenge = '256\t{"challenge":"c3ludGhldGljLWNoYWxsIQ=="}';

String _loginReply({String res = '200'}) =>
    '512535\t${jsonEncode({'uid': '1000000002', 'res': res, 'clientIp': '3362010054', 'timestamp': '1790771605', 'version': '1788748374'})}';

String _enterReply({String code = '200', String sid = '2112191006', String room = _room}) =>
    '1560\t${jsonEncode({'seqId': '4065210599', 'resCode': code, 'roomId': room, 'sid': sid, 'bownerInRoom': sid == '0' ? '0' : '1', 'micUid': '0'})}';

String _content(Map<String, Object?> content) => base64.encode(utf8.encode(jsonEncode(content)));

/// A `10|24` broadcast of a comment (synthetic values in the recorded
/// shape).
String _text({
  Object? tag = '1',
  Object? content,
  String? rawContent,
  Object? uid = '900000011',
  Object? fromUid = '900000011',
  Object? seqId = '4062331098',
  Object? grade = '6',
  String room = _room,
}) =>
    '2584\t${jsonEncode({
      'from_uid': fromUid,
      'seqId': seqId,
      'room_id': room,
      'oriUri': '2060425',
      'payload': {
        'seqId': '4062331097',
        'uid': uid,
        'grade': grade,
        'contribution': '0',
        'timestamp': '0',
        'tag': tag,
        'content': rawContent ?? _content((content ?? {'n': '观众1', 'm': 'selamat malam', 'a': '0', 'b': '0'}) as Map<String, Object?>),
        'others': [
          {'key': 'silenced', 'value': '0'},
        ],
        'owner': '1515772556',
      },
    })}';

String _nums(Object? count, {String gid = _room}) =>
    '10264\t${jsonEncode({'gid': gid, 'addUser': <Object>[], 'transId': '1790771627000', 'flag': '2', 'totalUserCount': count, 'roomCloseType': '0', 'punish_type': '0'})}';

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

Future<void> _settle() async {
  await _wait(Duration.zero);
  await _wait(Duration.zero);
}

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

BigoDanmakuConnection _connection(
  _Connector connector,
  _Http http, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration loginDelay = Duration.zero,
  DateTime Function()? now,
}) => BigoDanmakuConnection(
  http: http,
  connector: connector.call,
  policy: policy,
  proxy: proxy,
  loginDelay: loginDelay,
  now: now ?? () => _recordedAt,
  random: Random(1),
);

/// A message as expected.json writes it.
Map<String, Object?> _project(LiveMessage message) => switch (message.type) {
  LiveMessageType.online => {'type': 'online', 'value': (message.data! as LiveAudienceUpdate).value},
  _ => {
    'type': 'chat',
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'level': message.userLevel,
    'id': message.messageId,
  },
};

/// The time a recorded client frame was made at: the answer's `timeStamp`,
/// the entry's and the audience request's `seqId`, the ping's `seqid`.
DateTime? _timeOf(String frame) {
  final body = jsonDecode(frame.substring(frame.indexOf('{'))) as Map<String, Object?>;
  final head = frame.substring(0, frame.indexOf('{'));
  final millis = switch (head) {
    '79108' => int.parse(body['timeStamp']! as String) * 1000,
    '1304' || '10776' => int.parse(body['seqId']! as String),
    '791' => int.parse(body['seqid']! as String),
    _ => null,
  };
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

/// Replays [sample] through a connection: the recorded visitor, every
/// received frame, a heartbeat where the recording pinged, the clock at each
/// client frame's recorded time.
Future<({List<DanmakuEvent> events, _Connector connector, _Http http, BigoDanmakuConnection connection})> _replay(
  _Sample sample, {
  List<Object>? moreAnswers,
}) async {
  var clock = _recordedAt;
  final connector = _Connector();
  final http = _Http([_answer(sample.link.text), ...?moreAnswers]);
  final connection = _connection(connector, http, now: () => clock);
  final events = _record(connection);
  await connection.connect(sample.args);
  final channel = connector.channels.first;
  final frames = sample.socket.toList();
  for (final (index, frame) in frames.indexed) {
    if (frame.incoming) {
      final next = frames.skip(index + 1).takeWhile((f) => !f.incoming).map((f) => _timeOf(f.text));
      clock = next.firstWhere((time) => time != null, orElse: () => clock) ?? clock;
      await channel.receive(frame.text);
    } else if (frame.text.startsWith('791{')) {
      clock = _timeOf(frame.text)!;
      connection.heartbeat();
    }
  }
  return (events: events, connector: connector, http: http, connection: connection);
}

void main() {
  group('protocol', () {
    test('the socket, headers, timing and uris', () {
      expect(BigoDanmakuProtocol.endpoint, Uri.parse('wss://wss.bigolive.tv/live/official/web'));
      expect(BigoDanmakuProtocol.socketHeaders, {
        'origin': BigoApi.headers['origin'],
        'user-agent': BigoApi.headers['user-agent'],
      });
      expect(BigoDanmakuProtocol.heartbeatInterval, const Duration(seconds: 10));
      expect(BigoDanmakuProtocol.joinTimeout, const Duration(seconds: 10));
      expect(BigoDanmakuProtocol.loginDelay, const Duration(seconds: 1));
      expect(BigoDanmakuProtocol.maxRefusals, 3);
      const uri = BigoDanmakuProtocol.uri;
      expect(
        [
          BigoDanmakuProtocol.loginUri,
          BigoDanmakuProtocol.loginReplyUri,
          BigoDanmakuProtocol.enterUri,
          BigoDanmakuProtocol.enterReplyUri,
          BigoDanmakuProtocol.usersUri,
          BigoDanmakuProtocol.usersReplyUri,
          BigoDanmakuProtocol.textUri,
          BigoDanmakuProtocol.audienceUri,
          BigoDanmakuProtocol.pingUri,
        ],
        [
          uri(2001, 23),
          uri(2002, 23),
          uri(5, 24),
          uri(6, 24),
          uri(42, 24),
          uri(43, 24),
          uri(10, 24),
          uri(40, 24),
          uri(3, 23),
        ],
      );
      expect((BigoDanmakuProtocol.challengeUri, BigoDanmakuProtocol.answerUri), (256, 79108));
      expect(BigoDanmakuProtocol.chatTags, {1, 2});
      final handshake = (_live.meta['handshakes']! as List).single as Map<String, Object?>;
      expect(handshake['url'], '${BigoDanmakuProtocol.endpoint}');
      // Recorded with 3.x's bare `Mozilla/5.0`; the user agent is now the
      // adapter's browser one (E03.19).
      expect(BigoDanmakuProtocol.socketHeaders, {
        ...(handshake['headers']! as Map).cast<String, Object?>(),
        'user-agent': BigoApi.userAgent,
      });
    });

    test('the visitor request is the recorded one; device ids have the page shape', () {
      final cancel = CancelToken();
      const device = 'web_0123456789abcdef0123456789abcdef_Sample_1790771602072';
      final request = BigoDanmakuProtocol.linkRequest(device, timeout: const Duration(seconds: 7), cancel: cancel);
      final link = _live.meta['link']! as Map<String, Object?>;
      expect(request.site, SiteIds.bigo);
      expect(request.method, link['method']);
      expect('${request.url}', link['url']);
      // Recorded with 3.x's headers; the adapter's are now a full browser
      // fingerprint (E03.19), the content type stays.
      final recorded = (link['headers']! as Map).cast<String, Object?>();
      expect(request.headers, {...BigoApi.headers, 'content-type': recorded['content-type']});
      expect(recorded.keys.toSet().difference(request.headers.keys.toSet()), isEmpty);
      expect(request.followRedirects, link['followRedirects']);
      expect(utf8.decode(request.body!), _live.lines.first.text);
      expect(request.timeout, const Duration(seconds: 7));
      expect(request.cancel, same(cancel));

      final pattern = RegExp(r'^web_[0-9a-f]{32}_[A-Za-z0-9]{6}_1790771602060$');
      final ids = {
        for (var seed = 0; seed < 20; seed++)
          BigoDanmakuProtocol.deviceId(Random(seed), DateTime.fromMillisecondsSinceEpoch(1790771602060)),
      };
      expect(ids, hasLength(20));
      expect(ids.every(pattern.hasMatch), isTrue, reason: '$ids');
    });

    test('visitors: the recorded answer; ###VER2 dropped; unusable answers are FormatExceptions', () {
      final recorded = BigoDanmakuProtocol.visitor(_answer(_live.link.text), deviceId: 'mine');
      final data = (jsonDecode(_live.link.text) as Map<String, Object?>)['data']! as Map<String, Object?>;
      expect(recorded.userId, data['userId']);
      expect(recorded.token, data['uidToken']);
      expect(recorded.userName, '0');
      expect(recorded.deviceId, data['deviceId']);
      expect('$recorded', 'BigoChatVisitor(${data['userId']})', reason: 'no token in the text');

      final marked = BigoDanmakuProtocol.visitor(_visitor(token: 'abc###VER2'), deviceId: 'mine');
      expect(marked.token, 'abc');
      final bare = BigoDanmakuProtocol.visitor(
        _answer(
          jsonEncode({
            'code': 0,
            'data': {'userId': '12', 'uidToken': 'tok', 'userName': '', 'deviceId': ''},
          }),
        ),
        deviceId: 'mine',
      );
      expect((bare.userName, bare.deviceId), ('0', 'mine'));

      for (final (label, response) in [
        ('403', LiveResponse(status: 403, bytes: _visitor().bytes, url: BigoDanmakuProtocol.linkUrl)),
        ('not JSON', _answer('<html>')),
        ('array', _answer('[]')),
        ('code', _visitor(code: 500006)),
        ('code as text', _answer('{"code":"0","data":{"userId":"1","uidToken":"t"}}')),
        ('no data', _answer('{"code":0,"data":null}')),
        ('no user', _visitor(userId: '')),
        ('user not digits', _visitor(userId: '12a')),
        ('user too long', _visitor(userId: '1' * 21)),
        ('no token', _visitor(token: null)),
        ('empty token', _visitor(token: '')),
        ('token with a space', _visitor(token: 'a b')),
        ('non-ASCII token', _visitor(token: 'tök')),
        ('token too long', _visitor(token: 'a' * 4097)),
        ('token only the marker', _visitor(token: '###VER2')),
        ('numeric token', _visitor(token: 12345)),
      ]) {
        expect(
          () => BigoDanmakuProtocol.visitor(response, deviceId: 'mine'),
          throwsA(isA<FormatException>()),
          reason: label,
        );
      }
    });

    test('arguments: a Bigo id, an owner and a room id; trimmed', () {
      expect(BigoDanmakuProtocol.checked(_args), isA<BigoDanmakuArgs>());
      final trimmed = BigoDanmakuProtocol.checked(
        const BigoDanmakuArgs(siteId: ' tikaa12 ', ownerId: 1515772556, roomId: ' 6309489689319799326 '),
      )!;
      expect((trimmed.siteId, trimmed.roomId), ('tikaa12', _room));
      expect(
        BigoDanmakuProtocol.checked(const BigoDanmakuArgs(siteId: 'a', ownerId: 9007199254740991, roomId: '1')),
        isNotNull,
      );
      for (final args in const [
        BigoDanmakuArgs(siteId: '', ownerId: 1, roomId: '1'),
        BigoDanmakuArgs(siteId: 'bad id', ownerId: 1, roomId: '1'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 0, roomId: '1'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: -1, roomId: '1'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 9007199254740992, roomId: '1'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1, roomId: ''),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1, roomId: '0'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1, roomId: '0123'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1, roomId: '12a'),
        BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1, roomId: '123456789012345678901'),
      ]) {
        expect(BigoDanmakuProtocol.checked(args), isNull, reason: '$args');
      }
    });

    test('client frames: the answer, login, entry, audience request and ping', () {
      const visitor = BigoChatVisitor(userId: '1000000002', token: 'Tok+/=', deviceId: 'web_x');
      final now = DateTime.fromMillisecondsSinceEpoch(1790771605735, isUtc: true);
      final answer = BigoDanmakuProtocol.answer('c3ludGhldGljLWNoYWxsIQ==', now);
      final sign = md5.convert(utf8.encode('60#4#5#1790771605#1#1#1#1#YWxsIQ==')).toString();
      expect(
        answer,
        '79108{"appId":"60","osType":"4","clientVersion":"5","timeStamp":"1790771605","nonce":"1",'
        '"reservedForSecurity":"1","appSign":"1","redundancy":"1","sign":"$sign"}',
      );
      // A challenge shorter than 8 characters is used whole (slice(-8)).
      expect(
        (jsonDecode(BigoDanmakuProtocol.answer('abc', now).substring(5)) as Map<String, Object?>)['sign'],
        md5.convert(utf8.encode('60#4#5#1790771605#1#1#1#1#abc')).toString(),
      );
      expect(
        BigoDanmakuProtocol.login(visitor),
        '512279{"uid":"1000000002","cookie":"Tok+/=","secret":"0","userName":"0","deviceId":"web_x","userFlag":"0",'
        '"status":"0","password":"0","sdkVersion":"0","displayType":"0","pbVersion":"0","lang":"cn",'
        '"loginLevel":"0","clientVersionCode":"0","clientType":"7","clientOsVer":"0","netConf":{"clientIp":"0",'
        '"proxySwitch":"0","proxyTimestamp":"0","mcc":"0","mnc":"0","countryCode":"CN"}}',
      );
      expect(
        BigoDanmakuProtocol.enter(_room, visitor, now),
        '1304{"secretKey":"0","seqId":"1790771605735","roomId":"$_room","reserver":"1","clientVersion":"0",'
        '"clientType":"7","version":"15","deviceid":"web_x","other":[]}',
      );
      expect(
        BigoDanmakuProtocol.users(_args, now),
        '10776{"uid":"1515772556","seqId":"1790771605735","roomid":"$_room","contribution":"0",'
        '"enterTimestamp":"0","number":"0","ident":"0","userGrade":"0","version":"0","lastUserBeanGrade":"0",'
        '"lastUserId":"0","others":[]}',
      );
      expect(
        BigoDanmakuProtocol.ping(now),
        '791{"status":"0","seqid":"1790771605735","flag":"0","roomId":"0","ownerStatus":"0","micUid":"0"}',
      );
    });

    test('control frames: challenge, login, entry, idle room and refusals', () {
      BigoDanmakuFrame read(Object? frame) => BigoDanmakuProtocol.decode(frame, roomId: _room);
      expect(read(_challenge).challenge, 'c3ludGhldGljLWNoYWxsIQ==');
      expect(read(utf8.encode(_challenge)).challenge, 'c3ludGhldGljLWNoYWxsIQ==', reason: 'bytes are UTF-8');
      for (final frame in ['256\t{"challenge":""}', '256\t{"challenge":1}', '256\t{}', '257\t{"challenge":"x"}']) {
        expect(read(frame).challenge, isNull, reason: frame);
      }
      expect(read(_loginReply()).loggedIn, isTrue);
      expect(
        (read(_loginReply(res: '403')).loggedIn, read(_loginReply(res: '403')).refusal),
        (false, 'login: res 403'),
      );
      expect(read('512535\t{"res":200}').refusal, 'login: res 200', reason: 'the page compares with "200"');
      expect(read('512535\t{}').refusal, 'login: res ');
      final entered = read(_enterReply());
      expect((entered.entered, entered.idle, entered.refusal), (true, false, null));
      for (final sid in ['0', '']) {
        final idle = read(_enterReply(sid: sid));
        expect((idle.entered, idle.idle), (false, true), reason: sid);
      }
      expect(read('1560\t{"resCode":"200"}').idle, isTrue, reason: 'no sid');
      expect(read('1560\t{"resCode":"200","sid":2112191006}').entered, isTrue);
      expect(read(_enterReply(code: '500')).refusal, 'enter: resCode 500');
      expect(read('1560\t{"resCode":200,"sid":"1"}').refusal, 'enter: resCode 200');
      final unsigned = read('0\u0000        {"errUri":"512279","info":"unsigned"}');
      expect(unsigned.refusal, 'unsigned: 512279');
      expect(read('791\t{"info":"unsigned"}').refusal, 'unsigned: ');
      expect(read('791\t{"errUri":512279}').refusal, 'unsigned: 512279');
      for (final frame in [
        '791\t{"errUri":""}',
        '791\t{"errUri":0}',
        '791\t{"errUri":false}',
        '791\t{"errUri":null}',
        '791\t{"status":"0","seqid":"4065509877"}',
        '3608\t{"roomStatus":"1"}',
        'close',
        '',
        '2584\t[1]',
        '2584\t{not json',
        '{}',
        '   {"challenge":"x"}',
      ]) {
        final result = read(frame);
        expect(
          (result.challenge, result.loggedIn, result.entered, result.idle, result.refusal, result.messages.isEmpty),
          (null, false, false, false, null, true),
          reason: frame,
        );
      }
      expect(read(null).messages, isEmpty);
      expect(read(42).messages, isEmpty);
    });

    test('a comment: text, name, user id, level and message id', () {
      final message = BigoDanmakuProtocol.decode(_text(), roomId: _room).messages.single;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'selamat malam');
      expect(message.userName, '观众1');
      expect(message.userId, '900000011');
      expect(message.userLevel, '6');
      expect(message.messageId, '900000011:4062331098');
      expect(message.sentAt, isNull);
      expect(message.color, LiveMessageColor.white);
      expect(message.data, isNull);
      expect(message.isLocal, isFalse);
    });

    test('comment boundaries: tags, rooms, content, text, names, ids and levels', () {
      LiveMessage? chat(String frame) => BigoDanmakuProtocol.decode(frame, roomId: _room).messages.singleOrNull;
      // Tags: 1 and 2 (the page's comments), as text or number; others not.
      expect(chat(_text(tag: '2'))?.message, 'selamat malam');
      expect(chat(_text(tag: 1))?.message, 'selamat malam');
      for (final tag in ['3', '6', '8', '10', '11', '34', '37', '134', '0', '', 'x', null, 1.0]) {
        expect(chat(_text(tag: tag)), isNull, reason: '$tag');
      }
      expect(chat(_text(room: '6309489689319799327')), isNull, reason: 'another room');
      expect(BigoDanmakuProtocol.decode(_text(), roomId: '1').messages, isEmpty);
      // Content: Base64 of UTF-8 JSON; padding may be missing; a trailing
      // newline in the JSON is fine.
      expect(chat(_text(rawContent: base64.encode(utf8.encode('{"n":"a","m":"b"}\n'))))?.message, 'b');
      expect(chat(_text(rawContent: _content({'m': 'ab'}).replaceAll('=', '')))?.message, 'ab');
      for (final raw in [
        '',
        '!!!!',
        base64.encode([0xff, 0xfe]),
        base64.encode(utf8.encode('[1]')),
        'bm90IGpzb24=',
      ]) {
        expect(chat(_text(rawContent: raw)), isNull, reason: raw);
      }
      // Text: trimmed; a number is written out; empty or other types dropped.
      expect(chat(_text(content: {'n': 'a', 'm': '  hi  '}))?.message, 'hi');
      expect(chat(_text(content: {'n': 'a', 'm': 12}))?.message, '12');
      for (final text in ['', '   ', null, true, 1.5, <String>[], <String, String>{}]) {
        expect(chat(_text(content: {'n': 'a', 'm': text})), isNull, reason: '$text');
      }
      expect(chat(_text(content: {'n': 'a'})), isNull);
      // Names: trimmed; missing or not text is empty.
      expect(chat(_text(content: {'n': ' 观众2 ', 'm': 'x'}))?.userName, '观众2');
      expect(chat(_text(content: {'m': 'x'}))?.userName, '');
      expect(chat(_text(content: {'n': 7, 'm': 'x'}))?.userName, '7');
      expect(chat(_text(content: {'n': false, 'm': 'x'}))?.userName, '');
      // User ids: payload.uid, else from_uid; not digits is none, and then no
      // message id.
      expect(chat(_text(uid: 900000012))?.userId, '900000012');
      expect(chat(_text(uid: null, fromUid: '900000013'))?.userId, '900000013');
      expect(chat(_text(uid: 'abc', fromUid: '900000013'))?.userId, '900000013');
      final anonymous = chat(_text(uid: null, fromUid: null))!;
      expect((anonymous.userId, anonymous.messageId), ('', ''));
      // Message ids: the user and the frame's seqId (digits).
      expect(chat(_text(seqId: 4062331099))?.messageId, '900000011:4062331099');
      expect(chat(_text(seqId: null))?.messageId, '');
      expect(chat(_text(seqId: 'x1'))?.messageId, '');
      // Levels: digits.
      expect(chat(_text(grade: 25))?.userLevel, '25');
      expect(chat(_text(grade: '0'))?.userLevel, '0');
      for (final grade in [null, '', '-1', 'x', 2.5]) {
        expect(chat(_text(grade: grade))?.userLevel, '', reason: '$grade');
      }
      // A payload that is not an object.
      expect(chat('2584\t{"room_id":"$_room","seqId":"1","payload":"x"}'), isNull);
    });

    test('audience: NUMS and the user-list answer of this room, whole numbers only', () {
      int? count(String frame) => switch (BigoDanmakuProtocol.decode(frame, roomId: _room).messages.singleOrNull) {
        final LiveMessage message => (message.data! as LiveAudienceUpdate).value,
        null => null,
      };
      final message = BigoDanmakuProtocol.decode(_nums('467'), roomId: _room).messages.single;
      expect(message.type, LiveMessageType.online);
      expect((message.data! as LiveAudienceUpdate).kind, LiveAudienceMetricKind.onlineViewers);
      expect((message.userName, message.message, message.color), ('', '', LiveMessageColor.white));
      expect(count(_nums('467')), 467);
      expect(count(_nums(468)), 468);
      expect(count(_nums('0')), 0);
      for (final value in ['-1', '', 'x', '1.5', null, 1.5, '1e3', '123456789012345678901']) {
        expect(count(_nums(value)), isNull, reason: '$value');
      }
      expect(count(_nums('467', gid: '1')), isNull);
      expect(count('11032\t{"uid":"1","seqId":"1","room_id":"$_room","users":[],"total":"481"}'), 481);
      expect(count('11032\t{"uid":"0","seqId":"0","room_id":"0","isEnd":"0","opRes":"0","total":"0"}'), isNull);
      expect(count('11032\t{"room_id":"$_room","totalUserCount":"481"}'), isNull);
      expect(count('10264\t{"gid":"$_room","total":"481"}'), isNull);
    });
  });

  group('recordings', () {
    test("the client frames are the website's, from the recorded inputs", () {
      for (final sample in [_live, _idle, _unsigned]) {
        final visitor = BigoDanmakuProtocol.visitor(_answer(sample.link.text), deviceId: 'unused');
        final challenge = sample.socket
            .map((line) => BigoDanmakuProtocol.decode(line.text, roomId: sample.args.roomId).challenge)
            .nonNulls
            .single;
        final expected = {
          for (final frame in (sample.value['client']! as List).cast<Map<String, Object?>>())
            frame['line']! as int: frame['text']! as String,
        };
        final recorded = {
          for (final line in sample.socket)
            if (!line.incoming) line.line: line.text,
        };
        expect(recorded, expected, reason: '${sample.name}: the recorder sent what the website sends');
        for (final MapEntry(key: line, value: frame) in expected.entries) {
          final time = _timeOf(frame);
          final ours = switch (frame.substring(0, frame.indexOf('{'))) {
            '79108' => BigoDanmakuProtocol.answer(challenge, time!),
            '512279' => BigoDanmakuProtocol.login(visitor),
            '1304' => BigoDanmakuProtocol.enter(sample.args.roomId, visitor, time!),
            '10776' => BigoDanmakuProtocol.users(sample.args, time!),
            _ => BigoDanmakuProtocol.ping(time!),
          };
          expect(ours, frame, reason: '${sample.name}:$line');
        }
      }
    });

    test('every received frame reads as the website reads it', () {
      var chats = 0;
      var audience = 0;
      for (final sample in [_live, _idle, _unsigned]) {
        final reading = sample.reading;
        for (final line in sample.socket.where((line) => line.incoming)) {
          final expected = reading[line.line]!;
          final frame = BigoDanmakuProtocol.decode(line.text, roomId: sample.args.roomId);
          final reason = '${sample.name}:${line.line}';
          expect([for (final message in frame.messages) _project(message)], expected['events'], reason: reason);
          final page = expected['page'] as Map<String, Object?>?;
          expect(frame.challenge != null, page?['answer'] == true, reason: reason);
          expect(frame.loggedIn, page?['login'] == '200', reason: reason);
          expect(frame.entered || frame.idle, page?['enterRoom'] == '200', reason: reason);
          expect(frame.idle, page?['sid'] == '0', reason: reason);
          expect(frame.refusal != null, page?['loginFail'] == true, reason: reason);
          chats += frame.messages.where((m) => m.type == LiveMessageType.chat).length;
          audience += frame.messages.where((m) => m.type == LiveMessageType.online).length;
          if (page case {'chat': {'type': final int tag}} when tag != 1 && tag != 2) {
            expect(frame.messages, isEmpty, reason: '$reason: tag $tag is not a comment');
          }
        }
      }
      expect((chats, audience), (6, 4));
    });

    test('the caller address the login answer echoes is the scrubbed documentation address', () {
      // The site writes it as a little-endian uint32 in decimal; the recorded
      // one was the recorder's exit address, which fixture privacy (dotted
      // and Base64 forms only) cannot see.
      String dotted(int value) => [for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xff].join('.');
      var answers = 0;
      for (final sample in [_live, _idle]) {
        for (final line in sample.socket.where((line) => line.incoming && line.text.startsWith('512535'))) {
          final body = jsonDecode(line.text.substring(line.text.indexOf('{'))) as Map<String, Object?>;
          expect(body['clientIp'], '3362010054', reason: '${sample.name}:${line.line}');
          expect(dotted(int.parse(body['clientIp']! as String)), '198.51.100.200');
          answers += 1;
        }
      }
      for (final sample in [_live, _idle, _unsigned]) {
        for (final line in sample.lines) {
          for (final match in RegExp('"clientIp":"([^"]*)"').allMatches(line.text)) {
            expect(match[1], anyOf('0', '3362010054'), reason: '${sample.name}:${line.line}');
          }
        }
      }
      expect(answers, 2);
    });

    test('S05-live replays: one visitor, the recorded frames, ready once, 6 comments and 4 counts', () async {
      final replay = await _replay(_live);
      final channel = replay.connector.channels.single;
      expect(replay.connector.endpoints, [BigoDanmakuProtocol.endpoint]);
      expect(replay.connector.headers.single, BigoDanmakuProtocol.socketHeaders);
      expect(replay.http.requests, hasLength(1));
      expect(
        utf8.decode(replay.http.requests.single.body!),
        matches(RegExp('^deviceId=web_[0-9a-f]{32}_[A-Za-z0-9]{6}_${_recordedAt.millisecondsSinceEpoch}\$')),
      );
      expect(channel.sent, [
        for (final line in _live.socket)
          if (!line.incoming) line.text,
      ]);
      expect(replay.events.first, const DanmakuReady());
      expect(replay.events.whereType<DanmakuReady>(), hasLength(1));
      expect(replay.events.whereType<DanmakuReconnecting>(), isEmpty);
      final expected = [
        for (final frame in (_live.value['frames']! as List).cast<Map<String, Object?>>())
          ...(frame['events']! as List).cast<Map<String, Object?>>(),
      ];
      expect([for (final message in _messages(replay.events)) _project(message)], expected);
      expect(replay.connection.isConnected, isTrue);
      await replay.connection.close();
    });

    test('S06-idle replays: the room has no broadcast, so the connection ends after the entry', () async {
      final replay = await _replay(_idle);
      expect(replay.events, [
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast in room 6812312308570332324'),
      ]);
      expect(replay.connector.channels.single.uris, [79108, 512279, 1304]);
      expect(replay.connector.channels.single.closed, isTrue);
      expect(replay.connection.status, DanmakuStatus.closed);
    });

    test('S07-unsigned replays: a refused login asks for a new visitor and reconnects', () async {
      final replay = await _replay(_unsigned, moreAnswers: [_visitor()]);
      await _until(() => replay.connector.channels.length == 2);
      expect(replay.http.requests, hasLength(2));
      expect(replay.connector.channels.first.closed, isTrue);
      expect(replay.events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      final second = replay.connector.channels.last;
      await second.join();
      expect(second.uris, [79108, 512279, 1304, 10776]);
      expect((jsonDecode(second.sent[1].toString().substring(6)) as Map)['uid'], '1000000002');
      expect(replay.events.last, const DanmakuReady());
      await replay.connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = BigoDanmakuConnection.defaultPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 10));
      expect(policy.joinTimeout, const Duration(seconds: 10));
      expect(policy.inactivityTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = BigoDanmakuConnection(http: _Http([_visitor()]));
      expect(connection.heartbeatInterval, const Duration(seconds: 10));
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.site, SiteIds.bigo);
      final registry = DanmakuRegistry({
        SiteIds.bigo: () => BigoDanmakuConnection(http: _Http([_visitor()])),
      });
      expect(registry.supports('BIGO'), isTrue);
      expect(registry.connectionFor('bigo'), isA<BigoDanmakuConnection>());
    });

    test('handshake: a visitor first, then the socket; answer, login a second later, entry, ready', () async {
      final connector = _Connector();
      final http = _Http([_visitor()]);
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = _connection(
        connector,
        http,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.bigo: route}),
        // Long enough that the checks before the login always come first.
        loginDelay: const Duration(seconds: 1),
      );
      final events = _record(connection);
      await connection.connect(_args);
      expect(http.requests, hasLength(1));
      expect(http.requests.single.url, BigoDanmakuProtocol.linkUrl);
      expect(http.requests.single.cancel, isNotNull);
      expect(connector.endpoints, [BigoDanmakuProtocol.endpoint]);
      expect(connector.headers.single, BigoDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      final channel = connector.channels.single;
      expect(channel.sent, isEmpty, reason: 'the server speaks first');
      connection.heartbeat();
      expect(channel.sent, isEmpty, reason: 'no ping before the login');
      await channel.receive(_challenge);
      expect(channel.uris, [79108]);
      await _wait(const Duration(milliseconds: 30));
      expect(channel.uris, [79108], reason: 'the login waits');
      await channel.receive(_loginReply());
      expect(channel.uris, [79108], reason: 'no entry before the login was sent');
      await _until(() => channel.sent.length == 2);
      expect(channel.sent[1], BigoDanmakuProtocol.login(BigoDanmakuProtocol.visitor(_visitor(), deviceId: '')));
      await channel.receive(_challenge);
      expect(channel.uris, [79108, 512279], reason: 'one answer per socket');
      await channel.receive(_loginReply());
      expect(channel.uris, [79108, 512279, 1304]);
      expect(events, isEmpty);
      expect(connection.isConnected, isFalse);
      await channel.receive(_enterReply());
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      expect(channel.sent.last, BigoDanmakuProtocol.users(_args, _recordedAt));
      await channel.receive(_loginReply());
      await channel.receive(_enterReply());
      expect(channel.uris, [79108, 512279, 1304, 10776], reason: 'once per socket');
      await channel.receive(_text(content: {'n': '观众1', 'm': 'halo'}));
      await channel.receive(_text(content: {'n': '观众1', 'm': 'other room'}, room: '1'));
      await channel.receive(_text(tag: '37', content: {'level': 12, 'n': '观众2'}));
      await channel.receive(_nums('467'));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(
        [for (final m in _messages(events)) _project(m)],
        [
          {
            'type': 'chat',
            'userId': '900000011',
            'userName': '观众1',
            'text': 'halo',
            'level': '6',
            'id': '900000011:4062331098',
          },
          {'type': 'online', 'value': 467},
        ],
      );
      connection.heartbeat();
      expect(channel.sent.last, BigoDanmakuProtocol.ping(_recordedAt));
      await connection.close();
    });

    test('pings every heartbeat once logged in', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        _Http([_visitor()]),
        policy: const DanmakuSocketPolicy(heartbeatInterval: Duration(milliseconds: 20)),
      );
      await connection.connect(_args);
      final channel = connector.channels.single;
      await _wait(const Duration(milliseconds: 70));
      expect(channel.sent, isEmpty, reason: 'nothing before the login');
      await channel.join();
      await _until(() => channel.uris.where((uri) => uri == 791).length >= 2);
      await connection.close();
      final sent = channel.sent.length;
      await _wait(const Duration(milliseconds: 60));
      expect(channel.sent, hasLength(sent), reason: 'no ping after close');
    });

    test('a dropped socket reconnects with the same visitor and joins again', () async {
      final connector = _Connector();
      final http = _Http([_visitor(), _visitor(userId: '1000000003')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.join();
      await connector.channels.first.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(http.requests, hasLength(1), reason: 'the page reconnects with its wsConfig');
      final second = connector.channels.last;
      await second.join();
      expect(second.sent[1], connector.channels.first.sent[1], reason: 'the same login');
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('refused logins and entries: a new visitor each time; the fourth in a row ends it', () async {
      final connector = _Connector();
      final http = _Http([for (var n = 1; n <= 8; n++) _visitor(userId: '100000000$n')]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      // Three refusals, then a join: the count starts over.
      var sockets = 1;
      for (final refusal in [
        _loginReply(res: '403'),
        _enterReply(code: '500'),
        '0\u0000 {"errUri":"512279","info":"unsigned"}',
      ]) {
        final channel = connector.channels.last;
        await channel.receive(_challenge);
        if (refusal.startsWith('1560')) await channel.receive(_loginReply());
        await channel.receive(refusal);
        sockets += 1;
        await _until(() => connector.channels.length == sockets);
      }
      await connector.channels.last.join();
      expect(connection.isConnected, isTrue);
      // Four in a row: the joined socket's own login refused, then three new
      // sockets' logins.
      for (var n = 0; n < 4; n++) {
        final channel = connector.channels.last;
        await channel.receive(_challenge);
        await channel.receive(_loginReply(res: '500'));
        if (n == 3) break;
        sockets += 1;
        await _until(() => connector.channels.length == sockets);
      }
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty && connector.channels.last.closed);
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: login: res 500'),
      );
      expect(connector.channels, hasLength(7));
      expect(http.requests, hasLength(7));
      final logins = [
        for (final channel in connector.channels)
          (jsonDecode(channel.sent[1].toString().substring(6)) as Map<String, Object?>)['uid'],
      ];
      expect(logins, [for (var n = 1; n <= 7; n++) '100000000$n']);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
    });

    test('an unanswered join times out: a new visitor and a new socket', () async {
      final connector = _Connector();
      final http = _Http([_visitor(), _visitor(userId: '1000000003')]);
      final connection = _connection(
        connector,
        http,
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
      // A token the server does not accept: the login is never answered.
      await connector.channels.first.receive(_challenge);
      await _until(() => connector.channels.length == 2);
      expect(http.requests, hasLength(2));
      await connector.channels.last.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await _wait(const Duration(milliseconds: 1300));
      expect(connector.channels, hasLength(2), reason: 'joined: no timeout');
      await connection.close();
    });

    test('a room without a broadcast ends the connection', () async {
      final connector = _Connector();
      final connection = _connection(connector, _Http([_visitor()]));
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.single.join(sid: '0');
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast in room $_room')]);
      expect(connector.channels.single.closed, isTrue);
      expect(connector.channels.single.uris, [79108, 512279, 1304]);
    });

    test('a failing visitor request is a failed handshake: retried, then the reconnects run out', () async {
      final connector = _Connector();
      final http = _Http([
        const TransportFailure(SiteIds.bigo, TransportReason.timeout),
        _answer('<html>', status: 502),
        _visitor(code: 500006),
        _visitor(),
      ]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connector.channels.isNotEmpty);
      expect(http.requests, hasLength(4));
      expect(connector.endpoints, hasLength(1), reason: 'no socket without a visitor');
      await connector.channels.single.join();
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();

      final failing = _Http([const TransportFailure(SiteIds.bigo, TransportReason.connect)]);
      final exhausted = BigoDanmakuConnection(
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
      await exhausted.connect(_args);
      await _until(() => ended.whereType<DanmakuClosed>().isNotEmpty);
      expect(
        ended.last,
        isA<DanmakuClosed>().having((e) => e.reason, 'reason', DanmakuCloseReason.reconnectsExhausted),
      );
      expect(ended.whereType<DanmakuReconnecting>(), hasLength(1));
      expect(failing.requests, hasLength(3));
    });

    test('a failed socket handshake keeps the visitor for the next one', () async {
      final connector = _Connector(failures: 1);
      final http = _Http([_visitor(), _visitor(userId: '1000000003')]);
      final connection = _connection(connector, http);
      await connection.connect(_args);
      await _until(() => connector.channels.isNotEmpty);
      expect(connector.endpoints, hasLength(2));
      expect(http.requests, hasLength(1));
      await connection.close();
    });

    test('unusable arguments end at once, without a request or a handshake', () async {
      final connector = _Connector();
      final http = _Http([_visitor()]);
      final connection = _connection(connector, http);
      final events = _record(connection);
      await connection.connect(const BigoDanmakuArgs(siteId: 'tikaa12', ownerId: 1515772556, roomId: '0'));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable room')]);
      expect(http.requests, isEmpty);
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect('tikaa12'), throwsArgumentError);
    });

    test(
      'after close nothing is reported; a pending visitor request is cancelled; connect replaces the room',
      () async {
        final connector = _Connector();
        final pending = Completer<LiveResponse>();
        final http = _Http([pending]);
        final connection = _connection(connector, http);
        final events = _record(connection);
        final connecting = connection.connect(_args);
        await _until(() => http.requests.isNotEmpty);
        await connection.close();
        expect(http.requests.single.cancel!.isCancelled, isTrue);
        await connecting;
        expect(connector.endpoints, isEmpty);
        expect(events, isEmpty);

        final live = _Http([_visitor(), _visitor(userId: '1000000003')]);
        final other = _Connector();
        final second = _connection(other, live, loginDelay: const Duration(milliseconds: 30));
        final seen = _record(second);
        await second.connect(_args);
        final first = other.channels.single;
        await first.receive(_challenge);
        await second.connect(
          const BigoDanmakuArgs(siteId: 'qashia305', ownerId: 409742853, roomId: '6812312308570332324'),
        );
        expect(first.closed, isTrue);
        await _wait(const Duration(milliseconds: 60));
        expect(first.uris, [79108], reason: 'the old login timer is gone');
        final next = other.channels.last;
        await next.receive(_challenge);
        await _until(() => next.sent.length == 2);
        await next.receive(_loginReply());
        await next.receive(_enterReply());
        expect(next.sent[2], contains('"roomId":"6812312308570332324"'));
        await first.receive(_text());
        await second.close();
        await next.receive(_text());
        await next.receive(_nums('1'));
        expect(seen, [const DanmakuReady()]);
        expect(live.requests, hasLength(2), reason: 'a new visitor for the new room');
      },
    );

    test('a real local server: the handshake headers, the join, a ping and chat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final handshake = <String, String?>{};
      final received = <int>[];
      server.listen((request) async {
        handshake['path'] = request.uri.path;
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket
          ..add(_challenge)
          ..listen((frame) {
            final text = frame as String;
            final uri = int.parse(text.substring(0, text.indexOf('{')));
            received.add(uri);
            switch (uri) {
              case 512279:
                socket.add(_loginReply());
              case 1304:
                socket.add(_enterReply());
              case 10776:
                socket
                  ..add('11032\t{"uid":"1","seqId":"1","room_id":"$_room","users":[],"total":"481"}')
                  ..add(_text(content: {'n': '观众1', 'm': 'dari server'}));
              case 791:
                socket.add('791\t{"status":"0","seqid":"4065509877"}');
            }
          });
      });
      final connection = BigoDanmakuConnection(
        http: _Http([_visitor()]),
        now: () => _recordedAt,
        loginDelay: const Duration(milliseconds: 10),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, BigoDanmakuProtocol.endpoint);
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
      connection.heartbeat();
      await _until(() => received.length == 5);
      expect(handshake['path'], '/live/official/web');
      expect(handshake['origin'], 'https://www.bigo.tv');
      expect(handshake['user-agent'], endsWith(BigoApi.userAgent), reason: 'the browser user agent (E03.19)');
      expect(received, [79108, 512279, 1304, 10776, 791]);
      expect(events.first, const DanmakuReady());
      expect([for (final m in _messages(events)) _project(m)['text'] ?? _project(m)['value']], [481, 'dari server']);
      expect(connection.isConnected, isTrue);
      await connection.close();
    });
  });
}
