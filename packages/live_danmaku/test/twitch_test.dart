import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/twitch/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded session (S07-live): text frames in order, with their
/// direction.
final List<({String dir, String text})> _frames = _recording('S07-live');

/// The frames of a recorded session, in order, with their direction.
List<({String dir, String text})> _recording(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': final String dir, 'text': final String text}) (dir: dir, text: text),
];

/// 3.x's output for S07-live (fixtures/twitch/danmaku/legacy_expected.dart).
final Map<String, Object?> _recorded =
    (_json('S07-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

final String _channel = _recorded['channel']! as String;

List<Map<String, Object?>> get _recordedMessages => [
  for (final message in _recorded['messages']! as List<Object?>) Map.of(message! as Map<String, Object?>),
];

/// 3.x's join lines for a stored cookie (keys of `cookies`).
List<String> _legacyJoin(String cookie) =>
    ((_recorded['joinLines']! as Map<String, Object?>)[cookie]! as List<Object?>).cast<String>();

/// The number the generator's Random gave 3.x: justinfan39976, the recorded
/// nick.
const int _recordedDraw = 38976;

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'data': message.data,
};

/// A chat line as the projection shows it, for the differences.
Map<String, Object?> _chat(
  String name,
  String text,
  String id, {
  int? sentAt,
  String color = '#ffffff',
  String userId = '',
}) => {
  'type': 'chat',
  'userName': name,
  'userId': userId,
  'message': text,
  'color': color,
  'messageId': id,
  'sentAt': sentAt,
  'userLevel': '',
  'fansLevel': '',
  'fansName': '',
  'isLocal': false,
  'data': null,
};

/// A notice as the projection shows it (B-7).
Map<String, Object?> _notice(String name, String text, LiveNoticeKind kind, {String userId = '', int? sentAt}) => {
  ..._chat(name, text, '', sentAt: sentAt),
  'type': 'notice',
  'userId': userId,
  'data': kind,
};

/// A retraction as the projection shows it (B-7).
Map<String, Object?> _retraction(LiveRetraction target, {int? sentAt}) => {
  ..._chat('', '', '', sentAt: sentAt),
  'type': 'retraction',
  'data': target,
};

/// One frame of S08-synthetic/cases.json as the server sends it (the same
/// framing as legacy_expected.dart's `serverFrame`).
Object _serverFrame(Object? frame) => switch (frame) {
  final String text => text,
  {'lines': final List<Object?> lines} => lines.map((line) => '$line\r\n').join(),
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

/// A [Random] whose draws are [values], in turn (the last one repeats);
/// records the bounds it was asked for.
final class _Draws implements Random {
  new(this.values);

  final List<int> values;
  final List<int> bounds = [];
  var _next = 0;

  @override
  int nextInt(int max) {
    bounds.add(max);
    return values[min(_next++, values.length - 1)];
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
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
  new({this.fail = false, this.hold, this.failAt = const {}});

  final bool fail;

  /// Handshakes to refuse, counted from 1.
  final Set<int> failAt;

  /// Keeps every handshake after the first pending until it completes.
  final Completer<void>? hold;
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
    if (fail || failAt.contains(endpoints.length)) throw const SocketException('refused');
    if (endpoints.length > 1) await hold?.future;
    final channel = _FakeChannel();
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

/// Runs [body] with every timer of a second or more (backoff) recorded into
/// [delays] and fired at once.
Future<void> _fastBackoff(List<Duration> delays, Future<void> Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration < const Duration(seconds: 1)) return parent.createTimer(zone, duration, callback);
      delays.add(duration);
      return parent.createTimer(zone, Duration.zero, callback);
    },
  ),
);

/// Runs [body] with every timer of a second or more held back, so nothing
/// that waits for a backoff can happen.
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

const TwitchChatLogin _login = (login: 'viewer_01', token: '0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o');
final TwitchDanmakuArgs _args = TwitchDanmakuArgs(channel: _channel);
final TwitchDanmakuArgs _loginArgs = TwitchDanmakuArgs(channel: _channel, chat: _login);

/// A chat line of the channel as Twitch frames it.
String _line(String id, String text) =>
    '@color=#FF0000;display-name=A;id=$id;tmi-sent-ts=1790534993943;user-id=1 '
    ':a!a@a.tmi.twitch.tv PRIVMSG #$_channel :$text\r\n';

const String _refused = ':tmi.twitch.tv NOTICE * :Login authentication failed\r\n';

/// The expired-cookie notice (B-7), field by field.
final Matcher _isCookieNotice = isA<LiveMessage>()
    .having((message) => message.type, 'type', LiveMessageType.notice)
    .having((message) => message.data, 'data', LiveNoticeKind.system)
    .having((message) => message.message, 'message', 'Twitch 的 Cookie 已失效，弹幕已改为匿名接收，请重新填写 Twitch Cookie')
    .having((message) => message.userName, 'userName', '')
    .having((message) => message.userId, 'userId', '')
    .having((message) => message.messageId, 'messageId', '')
    .having((message) => message.sentAt, 'sentAt', isNull);

/// The clock of the B-7 connection tests; only differences matter.
final DateTime _clock = DateTime.utc(2026, 9, 30, 15);

/// A tag value escaped as Twitch writes it.
String _escapeTag(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\:')
    .replaceAll(' ', r'\s')
    .replaceAll('\r', r'\r')
    .replaceAll('\n', r'\n');

/// A B-7 command line of the channel as Twitch frames it (tags escaped,
/// CR LF at the end); [words] is the trailing parameter.
String _command(String command, Map<String, String> tags, {String? words}) =>
    '${tags.isEmpty ? '' : '@${[for (final MapEntry(:key, :value) in tags.entries) '$key=${_escapeTag(value)}'].join(';')} '}'
    ':tmi.twitch.tv $command #$_channel${words == null ? '' : ' :$words'}\r\n';

/// The tags of a viewer's USERNOTICE, shaped like the recorded ones
/// (S09-live); the names and ids are made up.
Map<String, String> _viewerNotice(String msgId, String systemMsg, {String id = 'n-1'}) => {
  'badge-info': 'subscriber/3',
  'badges': 'subscriber/3',
  'color': '#1E90FF',
  'display-name': 'Viewer_A',
  'emotes': '',
  'flags': '',
  'id': id,
  'login': 'viewer_a',
  'mod': '0',
  'msg-id': msgId,
  'room-id': '100',
  'subscriber': '1',
  'system-msg': systemMsg,
  'tmi-sent-ts': '1790781300000',
  'user-id': '1001',
  'user-type': '',
};

/// The projections of what [frame] decodes to.
List<Map<String, Object?>> _decoded(String frame) =>
    TwitchDanmakuProtocol.decode(frame).messages.map(_project).toList();

const String _reconnect = ':tmi.twitch.tv RECONNECT\r\n';

void main() {
  group('protocol', () {
    test("join lines are 3.x's for every stored cookie, read through M4.8's chatLogin", () {
      final cookies = (_recorded['cookies']! as Map<String, Object?>).cast<String, String>();
      // M4.8's TwitchApi.cookieValue takes the first of repeated names and
      // compares names without case; 3.x's _parseCookie kept the last one and
      // matched names exactly (docs/D-弹幕/D01-平台弹幕协议/D01.9-Twitch弹幕/record.md, "与 v3 的对照").
      final differences = <String, List<String> Function(List<String>)>{
        'a repeated name (3.x: the last one)': (legacy) {
          expect(legacy.first, 'PASS oauth:second');
          return ['PASS oauth:first', ...legacy.skip(1)];
        },
        'upper-case names (3.x: exact names only)': (legacy) {
          expect(legacy.first, TwitchDanmakuProtocol.anonymousPassword);
          return _legacyJoin('login');
        },
      };
      expect(differences.keys.every(cookies.containsKey), isTrue);
      for (final MapEntry(key: name, value: cookie) in cookies.entries) {
        final lines = TwitchDanmakuProtocol.join(
          _channel,
          random: _Draws([_recordedDraw]),
          chat: TwitchApi.chatLogin(cookie),
        );
        final legacy = _legacyJoin(name);
        expect(lines, differences[name]?.call(legacy) ?? legacy, reason: name);
      }
    });

    test("the recording's PASS, NICK and JOIN are 3.x's; its CAP REQ and order were the recording tool's", () {
      final sent = [
        for (final frame in _frames)
          if (frame.dir == 'out') frame.text,
      ];
      final legacy = _legacyJoin('none');
      expect(sent, ['CAP REQ :twitch.tv/tags twitch.tv/commands', legacy[0], legacy[1], legacy[3]]);
      expect(legacy[2], TwitchDanmakuProtocol.capabilities);
      expect(TwitchDanmakuProtocol.join(_channel, random: _Draws([_recordedDraw])), legacy);
    });

    test('the channel is trimmed and lower-cased; anonymous nicks are justinfan1000 to justinfan99999', () {
      final random = _Draws([_recordedDraw, 0, 98999]);
      expect(TwitchDanmakuProtocol.join(' ZarBex ', random: random), _recorded['joinLinesMixedCase']);
      expect(TwitchDanmakuProtocol.anonymousNick(random), 'justinfan1000');
      expect(TwitchDanmakuProtocol.anonymousNick(random), 'justinfan99999');
      expect(random.bounds, [99000, 99000, 99000]);
      expect(TwitchDanmakuProtocol.join('x', random: random, chat: (login: ' Me ', token: ' t ')).take(2), [
        'PASS oauth:t',
        'NICK me',
      ]);
      expect(random.bounds, hasLength(3), reason: 'a login draws no nick');
    });

    test("the heartbeat is 3.x's", () {
      expect(TwitchDanmakuProtocol.heartbeat, _recorded['heartbeat']);
      expect(TwitchDanmakuProtocol.endpoint, Uri.parse('wss://irc-ws.chat.twitch.tv'));
    });

    test('a refused login is a NOTICE to *', () {
      expect(TwitchDanmakuProtocol.isLoginRejection(':tmi.twitch.tv NOTICE * :Login authentication failed'), isTrue);
      expect(TwitchDanmakuProtocol.isLoginRejection(':tmi.twitch.tv NOTICE * :Improperly formatted auth'), isTrue);
      expect(TwitchDanmakuProtocol.isLoginRejection('@msg-id=x :tmi.twitch.tv NOTICE * :anything'), isTrue);
      expect(TwitchDanmakuProtocol.isLoginRejection('NOTICE * :no prefix'), isTrue);
      expect(TwitchDanmakuProtocol.isLoginRejection('@msg-id=slow_on :tmi.twitch.tv NOTICE #room :slow mode'), isFalse);
      expect(TwitchDanmakuProtocol.isLoginRejection(':a!a@a.tmi.twitch.tv PRIVMSG #room :NOTICE * :fake'), isFalse);
      expect(TwitchDanmakuProtocol.isLoginRejection(':tmi.twitch.tv NOTICE'), isFalse);
      expect(TwitchDanmakuProtocol.isLoginRejection('@a=b'), isFalse);
      expect(TwitchDanmakuProtocol.isLoginRejection(''), isFalse);
      expect(TwitchDanmakuProtocol.decode(_refused).loginRejected, isTrue);
      expect(TwitchDanmakuProtocol.decode(_line('x', 'hi')).loginRejected, isFalse);
    });
  });

  group('recorded frames (S07-live) against 3.x', () {
    test('the 22 incoming frames give the same 18 chat lines, in the same frames, and nothing to send', () {
      final decoded = <Map<String, Object?>>[];
      for (var index = 0; index < _frames.length; index++) {
        if (_frames[index].dir != 'in') continue;
        final frame = TwitchDanmakuProtocol.decode(_frames[index].text);
        expect(frame.replies, isEmpty);
        expect(frame.loginRejected, isFalse);
        decoded.addAll([
          for (final message in frame.messages) {'frame': index, ..._project(message)},
        ]);
      }
      expect(_frames.where((frame) => frame.dir == 'in'), hasLength(22));
      expect(decoded, hasLength(18));
      expect(decoded, _recordedMessages);
      expect(_recorded['sent'], isEmpty);
    });
  });

  group('synthetic frames (S08-synthetic) against 3.x', () {
    final cases = (_json('S08-synthetic/cases.json')! as Map<String, Object?>)['cases']! as List<Object?>;
    final expected = {
      for (final result in (_json('S08-synthetic/expected.json')! as Map<String, Object?>)['value']! as List<Object?>)
        if (result case {
          'name': final String name,
          'messages': final List<Object?> messages,
          'sent': final List<Object?> sent,
        })
          name: (
            messages: [for (final message in messages) message! as Map<String, Object?>],
            sent: sent.cast<String>(),
          ),
    };

    /// The intentional differences (docs/D-弹幕/D01-平台弹幕协议/D01.9-Twitch弹幕/record.md), applied to
    /// 3.x's output of the case they concern.
    final differences =
        <
          String,
          ({List<Map<String, Object?>> messages, List<String> sent}) Function(
            ({List<Map<String, Object?>> messages, List<String> sent}),
          )
        >{
          // M2's numberToColor reads every value; 3.x's only 4, 6 or 8 hex
          // digits and made the rest white.
          'colours with 1-3, 5 or 7 hex digits were white in 3.x': (legacy) {
            expect(legacy.messages.map((message) => message['color']).toSet(), {'#ffffff'});
            const colors = ['#0000ff', '#000080', '#0a0a0a', '#000000'];
            return (
              messages: [
                for (var index = 0; index < legacy.messages.length; index++)
                  {...legacy.messages[index], 'color': colors[index]},
              ],
              sent: legacy.sent,
            );
          },
          // 3.x lost every line of the frame; only the bad line is lost now.
          "a time beyond DateTime's range loses the whole frame in 3.x": (legacy) {
            expect(legacy.messages, isEmpty);
            return (
              messages: [
                _chat('A', 'before', 'g1', sentAt: 1790534993943),
                _chat('C', 'after', 'g3', sentAt: 1790534993944),
              ],
              sent: legacy.sent,
            );
          },
          // 3.x showed the CTCP wrapper of /me lines.
          '/me lines (CTCP ACTION)': (legacy) {
            expect(legacy.messages.first['message'], '\u0001ACTION waves\u0001');
            const texts = ['waves', 'without the closing byte', ''];
            return (
              messages: [
                for (var index = 0; index < legacy.messages.length; index++)
                  {...legacy.messages[index], if (index < texts.length) 'message': texts[index]},
              ],
              sent: legacy.sent,
            );
          },
          // 3.x answered with the whole frame, the chat line included.
          'PING first in a frame with chat: 3.x sends the whole frame back': (legacy) {
            expect(legacy.sent.single, startsWith('PONG :tmi.twitch.tv\r\n@display-name=A'));
            return (messages: legacy.messages, sent: ['PONG :tmi.twitch.tv']);
          },
          // 3.x only looked at the start of the frame.
          'PING after another line: 3.x does not answer it': (legacy) {
            expect(legacy.sent, isEmpty);
            return (messages: legacy.messages, sent: ['PONG :tmi.twitch.tv']);
          },
          // B-7: 3.x read none of USERNOTICE, CLEARCHAT and CLEARMSG.
          'other commands carry no chat': (legacy) {
            expect(legacy.messages, isEmpty);
            return (
              messages: [
                _notice('Sub', 'Sub subscribed', LiveNoticeKind.subscription),
                _chat('Sub', 'great stream', 'k1'),
                _retraction(const LiveRetraction.user('2'), sentAt: 1790618719773),
                _retraction(const LiveRetraction.message('k2'), sentAt: 1),
              ],
              sent: legacy.sent,
            );
          },
          // B-7: the words of a USERNOTICE are read whole; 3.x cut them after
          // the quoted ` PRIVMSG ... :` (M5.8 issue 8).
          "a line of another command whose text holds ' PRIVMSG ' is chat to 3.x": (legacy) {
            expect(legacy.messages.single['message'], 'hello');
            return (
              messages: [
                {...legacy.messages.single, 'message': 'quoting PRIVMSG #room :hello'},
              ],
              sent: legacy.sent,
            );
          },
        };
    const refusals = {'a refused login: NOTICE * and no chat'};
    // B-7: the server's request for a new socket.
    const reconnects = {'other commands carry no chat'};

    test('every case has 3.x output', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
      expect(differences.keys.every(expected.containsKey), isTrue);
      expect(refusals.every(expected.containsKey), isTrue);
      expect(reconnects.every(expected.containsKey), isTrue);
    });

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        final messages = <Map<String, Object?>>[];
        final sent = <String>[];
        final rejected = <bool>[];
        final reconnect = <bool>[];
        for (final frame in testCase['frames']! as List<Object?>) {
          final data = _serverFrame(frame);
          final decoded = TwitchDanmakuProtocol.decode(
            data is String ? data : utf8.decode(data as List<int>, allowMalformed: true),
          );
          messages.addAll(decoded.messages.map(_project));
          sent.addAll(decoded.replies);
          rejected.add(decoded.loginRejected);
          reconnect.add(decoded.reconnect);
        }
        final legacy = expected[name]!;
        final want = differences[name]?.call(legacy) ?? legacy;
        expect(messages, want.messages);
        expect(sent, want.sent);
        expect(rejected.every((value) => value == refusals.contains(name)), isTrue);
        expect(reconnect.every((value) => value == reconnects.contains(name)), isTrue);
      });
    }
  });

  group('connection', () {
    test('opens the endpoint without headers, sends the join lines, then is ready', () async {
      final connector = _Connector();
      final random = _Draws([_recordedDraw]);
      final connection = TwitchDanmakuConnection(connector: connector.call, random: random);
      final events = _record(connection);
      final sentWhenReady = <int>[];
      connection.events.listen((event) {
        if (event is DanmakuReady) sentWhenReady.add(connector.channels.last.sent.length);
      });
      await connection.connect(_args);
      expect(connector.endpoints, [TwitchDanmakuProtocol.endpoint]);
      expect(connector.headers.single, isEmpty);
      expect(connector.protocols.single, isNull);
      expect(connector.routes.single, isA<DirectRoute>());
      expect(connector.channels.single.sent, _legacyJoin('none'));
      expect(events, [const DanmakuReady()]);
      expect(sentWhenReady, [4], reason: '3.x: joinRoom, then onReady');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test("the chat login of the arguments is 3.x's PASS and NICK", () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      await connection.connect(_loginArgs);
      expect(connector.channels.single.sent, _legacyJoin('login'));
      await connection.close();
    });

    test('the proxy policy routes the handshake', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(
        connector: connector.call,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.twitch: HttpProxyRoute('127.0.0.1', 7890)}),
      );
      await connection.connect(_args);
      expect(connector.routes.single, isA<HttpProxyRoute>());
      await connection.close();
    });

    test("3.x's timing: 40 s heartbeat, 120 s silence limit, no join timer, 8 reconnects", () {
      final connection = TwitchDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 40));
      expect(connection.site, SiteIds.twitch);
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 40));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 40 s, 90 s) = 120 s');
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends PING :tmi.twitch.tv on its 40 s timer and on demand, as text', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = TwitchDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 6);
          expect(sent.skip(4).take(2), [TwitchDanmakuProtocol.heartbeat, TwitchDanmakuProtocol.heartbeat]);
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
      expect(periods, [const Duration(seconds: 40)]);
    });

    test("answers the server's PING with PONG, one line per PING", () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      channel.incoming
        ..add('PING :tmi.twitch.tv\r\n')
        ..add('PING :tmi.twitch.tv\r\n${_line('p1', 'after the ping')}')
        ..add('${_line('p2', 'before the ping')}PING :tmi.twitch.tv\r\n');
      await _until(() => _messages(events).length == 2);
      expect(channel.sent.skip(4), ['PONG :tmi.twitch.tv', 'PONG :tmi.twitch.tv', 'PONG :tmi.twitch.tv']);
      expect(_messages(events).map((message) => message.message), ['after the ping', 'before the ping']);
      await connection.close();
    });

    test('replaying the recording reports what 3.x decoded, in order; binary frames are read as UTF-8', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      var binary = false;
      for (final frame in _frames) {
        if (frame.dir != 'in') continue;
        // Every other frame as binary: both kinds decode alike.
        channel.incoming.add((binary = !binary) ? utf8.encode(frame.text) : frame.text);
      }
      await _until(() => _messages(events).length == 18);
      expect(_messages(events).map(_project), [for (final message in _recordedMessages) message..remove('frame')]);
      expect(channel.sent, hasLength(4), reason: 'only the join lines');
      await connection.close();
    });

    test('a refused login reopens at once as an anonymous nick, without a reconnect notice', () async {
      final connector = _Connector();
      final random = _Draws([_recordedDraw]);
      final connection = TwitchDanmakuConnection(connector: connector.call, random: random);
      final events = _record(connection);
      await _withoutBackoff(() async {
        await connection.connect(_loginArgs);
        final first = connector.channels.single;
        expect(first.sent, _legacyJoin('login'));
        first.incoming.add(
          '$_refused:tmi.twitch.tv CAP * ACK :twitch.tv/tags twitch.tv/commands twitch.tv/membership\r\n',
        );
        await _until(() => connector.channels.length == 2 && connection.isConnected);
        expect(first.closed, isTrue);
        final second = connector.channels.last;
        expect(second.sent, _legacyJoin('none'));
        // The anonymous nick is never refused; a stray NOTICE * changes nothing.
        second.incoming
          ..add(_refused)
          ..add(_line('r1', 'chat as justinfan'));
        await _until(() => _messages(events).length == 2);
      });
      expect(connector.channels, hasLength(2));
      expect(connector.endpoints, [TwitchDanmakuProtocol.endpoint, TwitchDanmakuProtocol.endpoint]);
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      // B-7: the user is told once, before the anonymous socket joins, that
      // the cookie expired (3.x and M5.8 said nothing).
      expect(events[1], isA<DanmakuReceived>().having((event) => event.message, 'message', _isCookieNotice));
      expect(_messages(events).last.message, 'chat as justinfan');
      await connection.close();
    });

    test('a refused login is forgotten at the next connect; anonymous nicks ignore NOTICE *', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      await connection.connect(_loginArgs);
      connector.channels.single.incoming.add(_refused);
      await _until(() => connector.channels.length == 2 && connection.isConnected);
      await connection.connect(_loginArgs);
      expect(connector.channels, hasLength(3));
      expect(connector.channels.last.sent, _legacyJoin('login'));
      await connection.connect(_args);
      connector.channels.last.incoming.add(_refused);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(4));
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test('close while the anonymous socket opens after a refused login: nothing is reported', () async {
      final hold = Completer<void>();
      final connector = _Connector(hold: hold);
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_loginArgs);
      connector.channels.single.incoming.add(_refused);
      await _until(() => connector.endpoints.length == 2);
      expect(connector.channels.single.closed, isTrue);
      expect(connection.isConnected, isFalse);
      await connection.close();
      hold.complete();
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(2));
      expect(connector.channels.last.closed, isTrue, reason: 'the late handshake is closed');
      expect(connector.channels.last.sent, isEmpty);
      // B-7: the cookie notice came with the refusal, before close.
      expect(events, hasLength(2));
      expect(events.first, const DanmakuReady());
      expect(events.last, isA<DanmakuReceived>().having((event) => event.message, 'message', _isCookieNotice));
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a dropped socket reconnects after 2 s with a new nick, joins again and is ready again', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final random = _Draws([_recordedDraw, 1]);
      final connection = TwitchDanmakuConnection(connector: connector.call, random: random);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(delays.first, const Duration(seconds: 2), reason: 'one endpoint: 1 s × (1 round + 1)');
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [
        TwitchDanmakuProtocol.anonymousPassword,
        'NICK justinfan1001',
        TwitchDanmakuProtocol.capabilities,
        'JOIN #$_channel',
      ]);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('the chat login stays across ordinary reconnects', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      await _fastBackoff(delays, () async {
        await connection.connect(_loginArgs);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(connector.channels.last.sent, _legacyJoin('login'));
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(fail: true);
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
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
            .having((event) => event.detail, 'detail', contains('refused')),
      );
      expect(events, hasLength(2));
      expect(connection.status, DanmakuStatus.closed);
    });

    test('close: no event, heartbeat or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming
        ..add(_line('z1', 'too late'))
        ..add('PING :tmi.twitch.tv\r\n');
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, hasLength(4));
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('connecting to another room closes the first socket and joins the new room', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(const TwitchDanmakuArgs(channel: 'first'));
      await connection.connect(const TwitchDanmakuArgs(channel: 'second'));
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent.last, 'JOIN #second');
      connector.channels.first.incoming.add(_line('y1', 'from the first room'));
      connector.channels.last.incoming.add(_line('y2', 'from the second room'));
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).map((message) => message.message), ['from the second room']);
      await connection.close();
    });

    test('takes TwitchDanmakuArgs only', () async {
      final connection = TwitchDanmakuConnection(connector: _Connector().call);
      await expectLater(connection.connect(_channel), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under twitch', () {
      final registry = DanmakuRegistry({SiteIds.twitch: TwitchDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.twitch]);
      expect(registry.connectionFor(' Twitch '), isA<TwitchDanmakuConnection>());
      expect(registry.connectionFor('soop'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the recorded session end to end, as text frames', () async {
      final received = <Object?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          received.add(frame);
          if (received.length == 4) {
            for (final recorded in _frames) {
              if (recorded.dir == 'in') socket.add(recorded.text);
            }
            socket.add('PING :tmi.twitch.tv\r\n');
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = TwitchDanmakuConnection(
        random: _Draws([_recordedDraw]),
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          requested.add(endpoint);
          return connectIoSocket(
            Uri.parse('ws://127.0.0.1:${server.port}/'),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).length == 18 && received.length == 5);
      expect(requested, [TwitchDanmakuProtocol.endpoint]);
      expect(received.take(4), _legacyJoin('none'));
      expect(received[4], 'PONG :tmi.twitch.tv');
      expect(_messages(events).map(_project), [for (final message in _recordedMessages) message..remove('frame')]);
      connection.heartbeat();
      await _until(() => received.length == 6);
      expect(received.last, TwitchDanmakuProtocol.heartbeat);
      await connection.close();
    });
  });

  group('B-7 commands (synthetic)', () {
    const time = 1790781494256;

    test('CLEARMSG takes back the message target-msg-id; the retraction has no id of its own', () {
      final frame = TwitchDanmakuProtocol.decode(
        _command('CLEARMSG', {
          'login': 'viewer_b',
          'room-id': '',
          'target-msg-id': 'aa9c3bc4-0000-4000-8000-000000000001',
          'tmi-sent-ts': '$time',
        }, words: 'the deleted words'),
      );
      expect(frame.messages.map(_project), [
        _retraction(const LiveRetraction.message('aa9c3bc4-0000-4000-8000-000000000001'), sentAt: time),
      ]);
      expect(frame.messages.single.sentAt, DateTime.fromMillisecondsSinceEpoch(time));
      expect(frame.reconnect, isFalse);
      expect(frame.replies, isEmpty);
    });

    test('CLEARCHAT: a timeout or a ban takes back the messages of target-user-id; without a user, all', () {
      final frame = [
        _command('CLEARCHAT', {
          'ban-duration': '600',
          'room-id': '100',
          'target-user-id': '2002',
          'tmi-sent-ts': '$time',
        }, words: 'viewer_c'),
        _command('CLEARCHAT', {
          'room-id': '100',
          'target-user-id': '2003',
          'tmi-sent-ts': '${time + 1}',
        }, words: 'viewer_d'),
        _command('CLEARCHAT', {'room-id': '100', 'tmi-sent-ts': '${time + 2}'}),
      ].join();
      expect(_decoded(frame), [
        _retraction(const LiveRetraction.user('2002'), sentAt: time),
        _retraction(const LiveRetraction.user('2003'), sentAt: time + 1),
        _retraction(const LiveRetraction.all(), sentAt: time + 2),
      ]);
    });

    test('bad CLEARMSG and CLEARCHAT lines take nothing back, and never the whole chat', () {
      final frame = [
        // No target, an empty one, a blank one.
        _command('CLEARMSG', {'login': 'viewer_b', 'tmi-sent-ts': '$time'}, words: 'x'),
        _command('CLEARMSG', {'target-msg-id': '', 'tmi-sent-ts': '$time'}, words: 'x'),
        _command('CLEARMSG', {'target-msg-id': ' ', 'tmi-sent-ts': '$time'}, words: 'x'),
        // A user named without an id cannot be matched: not a clear.
        _command('CLEARCHAT', {'ban-duration': '60', 'tmi-sent-ts': '$time'}, words: 'viewer_c'),
        _command('CLEARCHAT', {'target-user-id': '', 'tmi-sent-ts': '$time'}, words: 'viewer_c'),
        _command('CLEARCHAT', {'tmi-sent-ts': '$time'}, words: ''),
        // A time beyond DateTime's range loses only its own line.
        _command('CLEARMSG', {'target-msg-id': 'lost', 'tmi-sent-ts': '99999999999999999'}, words: 'x'),
        // The id decides; an unreadable time is no time.
        _command('CLEARCHAT', {'target-user-id': '2004', 'tmi-sent-ts': 'soon'}),
        // Without tags (no tags capability) a bare CLEARCHAT is still a clear.
        ':tmi.twitch.tv CLEARCHAT #$_channel\r\n',
      ].join();
      expect(_decoded(frame), [
        _retraction(const LiveRetraction.user('2004')),
        _retraction(const LiveRetraction.all()),
      ]);
    });

    test("subscriptions: the system-msg as a subscription notice, the words as the viewer's chat", () {
      final resub = _command('USERNOTICE', {
        ..._viewerNotice('resub', "Viewer_A subscribed at Tier 1. They've subscribed for 33 months!", id: 'n-2'),
        'msg-param-cumulative-months': '33',
        'msg-param-sub-plan': '1000',
      }, words: 'worth it :)');
      expect(_decoded(resub), [
        _notice(
          'Viewer_A',
          "Viewer_A subscribed at Tier 1. They've subscribed for 33 months!",
          LiveNoticeKind.subscription,
          userId: '1001',
          sentAt: 1790781300000,
        ),
        _chat('Viewer_A', 'worth it :)', 'n-2', sentAt: 1790781300000, color: '#1e90ff', userId: '1001'),
      ]);
      for (final msgId in TwitchDanmakuProtocol.subscriptionNotices) {
        expect(_decoded(_command('USERNOTICE', _viewerNotice(msgId, 'Viewer_A did "$msgId".'))), [
          _notice(
            'Viewer_A',
            'Viewer_A did "$msgId".',
            LiveNoticeKind.subscription,
            userId: '1001',
            sentAt: 1790781300000,
          ),
        ], reason: msgId);
      }
      expect(TwitchDanmakuProtocol.subscriptionNotices, hasLength(12));
    });

    test('D07.2: a subgift inside a community gift is its share; one of its own and the gift itself are '
        'subscriptions', () {
      LiveMessage notice(String msgId, {String community = ''}) => TwitchDanmakuProtocol.decode(
        _command('USERNOTICE', {
          ..._viewerNotice(msgId, 'Viewer_A did "$msgId".'),
          if (community.isNotEmpty) 'msg-param-community-gift-id': community,
        }),
      ).messages.single;
      expect(TwitchDanmakuProtocol.communityShares, {'subgift', 'anonsubgift'});
      for (final msgId in TwitchDanmakuProtocol.communityShares) {
        expect(notice(msgId, community: '3918641243089153208').data, LiveNoticeKind.giftedSubscription, reason: msgId);
        expect(notice(msgId).data, LiveNoticeKind.subscription, reason: '$msgId of its own');
      }
      // The community gift announces itself with the same id: a subscription.
      expect(notice('submysterygift', community: '3918641243089153208').data, LiveNoticeKind.subscription);
    });

    test("a raid is a raid notice in the platform's words", () {
      final raid = _command('USERNOTICE', {
        ..._viewerNotice('raid', '1234 raiders from Raider_B have joined!'),
        'display-name': 'Raider_B',
        'login': 'raider_b',
        'msg-param-displayName': 'Raider_B',
        'msg-param-login': 'raider_b',
        'msg-param-viewerCount': '1234',
        'user-id': '3001',
      });
      expect(_decoded(raid), [
        _notice(
          'Raider_B',
          '1234 raiders from Raider_B have joined!',
          LiveNoticeKind.raid,
          userId: '3001',
          sentAt: 1790781300000,
        ),
      ]);
    });

    test('an announcement is a system notice of its words; other msg-ids show their system-msg as system', () {
      final frame = [
        _command('USERNOTICE', {
          ..._viewerNotice('announcement', ''),
          'msg-param-color': 'PRIMARY',
        }, words: 'Do not spoil results'),
        // Nothing to say.
        _command('USERNOTICE', _viewerNotice('announcement', ''), words: '  '),
        _command(
          'USERNOTICE',
          _viewerNotice(
            'viewermilestone',
            'Viewer_A watched 85 consecutive streams and sparked a watch streak!',
            id: 'n-3',
          ),
          words: 'W',
        ),
        _command('USERNOTICE', _viewerNotice('unraid', 'The raid has been canceled.')),
        // An unknown kind without a system-msg shows only the words.
        _command('USERNOTICE', _viewerNotice('somethingnew', '  ', id: 'n-4'), words: 'hello'),
        _command('USERNOTICE', _viewerNotice('somethingnew', '')),
        // No tags at all.
        ':tmi.twitch.tv USERNOTICE #$_channel :bare words\r\n',
      ].join();
      expect(_decoded(frame), [
        _notice('Viewer_A', 'Do not spoil results', LiveNoticeKind.system, userId: '1001', sentAt: 1790781300000),
        _notice(
          'Viewer_A',
          'Viewer_A watched 85 consecutive streams and sparked a watch streak!',
          LiveNoticeKind.system,
          userId: '1001',
          sentAt: 1790781300000,
        ),
        _chat('Viewer_A', 'W', 'n-3', sentAt: 1790781300000, color: '#1e90ff', userId: '1001'),
        _notice(
          'Viewer_A',
          'The raid has been canceled.',
          LiveNoticeKind.system,
          userId: '1001',
          sentAt: 1790781300000,
        ),
        _chat('Viewer_A', 'hello', 'n-4', sentAt: 1790781300000, color: '#1e90ff', userId: '1001'),
        _chat('Twitch', 'bare words', ''),
      ]);
    });

    test('a sharedchatnotice counts as its source-msg-id', () {
      Map<String, String> shared(String source, String systemMsg) => {
        ..._viewerNotice('sharedchatnotice', systemMsg),
        'source-msg-id': source,
        'source-room-id': '200',
      };
      final frame = [
        _command('USERNOTICE', shared('sub', 'Viewer_A subscribed at Tier 1.')),
        _command('USERNOTICE', shared('raid', '5 raiders from Viewer_A have joined!')),
        _command('USERNOTICE', shared('announcement', ''), words: 'Shared rules'),
        _command('USERNOTICE', shared('viewermilestone', 'Viewer_A watched 5 consecutive streams!')),
        _command('USERNOTICE', {..._viewerNotice('sharedchatnotice', 'No source.')}),
      ].join();
      expect(_decoded(frame).map((message) => (message['data'], message['message'])), [
        (LiveNoticeKind.subscription, 'Viewer_A subscribed at Tier 1.'),
        (LiveNoticeKind.raid, '5 raiders from Viewer_A have joined!'),
        (LiveNoticeKind.system, 'Shared rules'),
        (LiveNoticeKind.system, 'Viewer_A watched 5 consecutive streams!'),
        (LiveNoticeKind.system, 'No source.'),
      ]);
    });

    test('names fall back to the login, then to nothing for a notice and to Twitch for chat', () {
      final frame = [
        _command('USERNOTICE', {..._viewerNotice('sub', 'x subscribed.'), 'display-name': ' '}, words: 'a'),
        _command('USERNOTICE', {
          ..._viewerNotice('sub', 'y subscribed.'),
          'display-name': '',
          'login': '',
          'user-id': '',
          'color': '',
        }, words: 'b'),
      ].join();
      expect(_decoded(frame).map((message) => (message['type'], message['userName'], message['color'])), [
        ('notice', 'viewer_a', '#ffffff'),
        ('chat', 'viewer_a', '#1e90ff'),
        ('notice', '', '#ffffff'),
        ('chat', 'Twitch', '#ffffff'),
      ]);
    });

    test('the tags of these commands are unescaped in one pass (IRCv3); the words are read whole', () {
      final frame =
          '@display-name=A\\sB;id=n-5;msg-id=resub;system-msg=back\\\\slash\\:\\sdone\\ :tmi.twitch.tv USERNOTICE #$_channel '
          ':quoting PRIVMSG #$_channel :hello :) \r\n';
      expect(_decoded(frame).map((message) => message['message']), [
        r'back\slash; done',
        'quoting PRIVMSG #$_channel :hello :)',
      ]);
      expect(_decoded(frame).map((message) => message['userName']).toSet(), {'A B'});
      // 3.x's chat reading is unchanged (issue 6): `\\s` still becomes `\ `.
      expect(TwitchDanmakuProtocol.unescapeTag(r'back\\slash'), r'back\ lash');
      expect(TwitchIrcLine.unescape(r'back\\slash'), r'back\slash');
      expect(TwitchIrcLine.unescape(r'a\qb\'), 'aqb');
      expect(TwitchIrcLine.unescape(r'\r\n\s\:'), '\r\n ;');
      expect(TwitchIrcLine.unescape('plain'), 'plain');
    });

    test('RECONNECT asks for a new socket; the word in chat or a notice does not', () {
      expect(TwitchDanmakuProtocol.decode(_reconnect).reconnect, isTrue);
      expect(TwitchDanmakuProtocol.decode('RECONNECT').reconnect, isTrue);
      expect(TwitchDanmakuProtocol.decode('@a=b :tmi.twitch.tv RECONNECT\r\n').reconnect, isTrue);
      expect(TwitchDanmakuProtocol.decode(_line('c1', 'RECONNECT')).reconnect, isFalse);
      expect(TwitchDanmakuProtocol.decode(':tmi.twitch.tv NOTICE #room :RECONNECT\r\n').reconnect, isFalse);
      expect(TwitchDanmakuProtocol.decode(':tmi.twitch.tv RECONNECTING\r\n').reconnect, isFalse);
      final frame = TwitchDanmakuProtocol.decode('${_line('c2', 'before')}$_reconnect${_line('c3', 'after')}');
      expect(frame.reconnect, isTrue);
      expect(frame.messages.map((message) => message.message), ['before', 'after']);
      expect(frame.loginRejected, isFalse);
    });

    test('TwitchIrcLine splits tags, prefix, command, parameters and the trailing one', () {
      final line = TwitchIrcLine.parse(r'@a=1;b;c=x\sy :tmi.twitch.tv CLEARCHAT #room  extra :the  words :)')!;
      expect(line.tags, {'a': '1', 'b': '', 'c': 'x y'});
      expect(line.prefix, 'tmi.twitch.tv');
      expect(line.command, 'CLEARCHAT');
      expect(line.params, ['#room', 'extra']);
      expect(line.trailing, 'the  words :)');
      final bare = TwitchIrcLine.parse('RECONNECT')!;
      expect([bare.command, bare.prefix, bare.trailing], ['RECONNECT', null, null]);
      expect(bare.tags, isEmpty);
      expect(bare.params, isEmpty);
      expect(TwitchIrcLine.parse('PING :tmi.twitch.tv')?.trailing, 'tmi.twitch.tv');
      expect(TwitchIrcLine.parse(':tmi.twitch.tv CLEARCHAT #room :')?.trailing, '');
      for (final bad in ['', '@a=b', ':prefix', '@a=b :prefix', '@a=b  ']) {
        expect(TwitchIrcLine.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('B-7 recorded frames (S09-live, S10-live)', () {
    /// What the incoming frames of [recording] decode to, in order, and the
    /// replies they ask for.
    ({List<LiveMessage> messages, List<String> replies, bool flagged}) decodeAll(
      List<({String dir, String text})> recording,
    ) {
      final messages = <LiveMessage>[];
      final replies = <String>[];
      var flagged = false;
      for (final frame in recording) {
        if (frame.dir != 'in') continue;
        final decoded = TwitchDanmakuProtocol.decode(frame.text);
        messages.addAll(decoded.messages);
        replies.addAll(decoded.replies);
        flagged = flagged || decoded.reconnect || decoded.loginRejected;
      }
      return (messages: messages, replies: replies, flagged: flagged);
    }

    (Object?, String, String, String) summary(LiveMessage message) =>
        (message.data, message.userName, message.userId, message.message);

    test(
      'S09 (ironmouse): subscriptions, gifts, raids and streaks as notices; deletions and a timeout as retractions',
      () {
        final decoded = decodeAll(_recording('S09-live'));
        final messages = decoded.messages;
        expect(decoded.replies, List.filled(3, 'PONG :tmi.twitch.tv'), reason: "the server's own PINGs");
        expect(decoded.flagged, isFalse);
        expect(messages.map((message) => message.type.name), [
          ...List.filled(6, 'chat'),
          ...List.filled(3, 'notice'),
          ...['chat', 'retraction', 'chat', 'retraction', 'notice', 'notice', 'chat', 'retraction', 'chat', 'notice'],
          ...['chat', 'retraction', ...List.filled(8, 'notice')],
        ]);
        expect(
          [
            for (final message in messages)
              if (message.type == LiveMessageType.notice) summary(message),
          ],
          [
            (LiveNoticeKind.subscription, 'pfxqwzmw', '5696248051', 'pfxqwzmw subscribed at Tier 1.'),
            // D07.2: one share of the community gift announced next.
            (
              LiveNoticeKind.giftedSubscription,
              'fyiimgxdzsmybw',
              '984515358',
              'fyiimgxdzsmybw gifted a Tier 1 sub to yjjgig81!',
            ),
            (
              LiveNoticeKind.subscription,
              'fyiimgxdzsmybw',
              '984515358',
              "fyiimgxdzsmybw is gifting 1 Tier 1 Subs to ironmouse's community! They've gifted a total of 1 in the channel!",
            ),
            (LiveNoticeKind.subscription, 'fyiimgxdzsmybw', '984515358', 'fyiimgxdzsmybw subscribed at Tier 1.'),
            (
              LiveNoticeKind.system,
              'kxviv6s',
              '850519886',
              'kxviv6s watched 7 consecutive streams and sparked a watch streak!',
            ),
            (
              LiveNoticeKind.subscription,
              'ecytbehdinkakdwlwa',
              '3670226551',
              'ecytbehdinkakdwlwa subscribed at Tier 1.',
            ),
            (LiveNoticeKind.raid, 'Phpfsq_Kroad', '305470178', '49 raiders from Phpfsq_Kroad have joined!'),
            (
              LiveNoticeKind.system,
              'tciwbkicjkm',
              '103210441',
              'tciwbkicjkm watched 15 consecutive streams and sparked a watch streak!',
            ),
            (LiveNoticeKind.subscription, 'Icwozuqrb', '69564122', 'Icwozuqrb subscribed with Prime.'),
            (LiveNoticeKind.subscription, 'vvsarhqdnh606', '266437711', 'vvsarhqdnh606 subscribed with Prime.'),
            // Twitch's placeholder for an anonymous gifter; its system-msg ends
            // with a space.
            (
              LiveNoticeKind.giftedSubscription,
              'AnAnonymousGifter',
              '274598607',
              'An anonymous user gifted a Tier 1 sub to SiiYctRkf!',
            ),
            (
              LiveNoticeKind.subscription,
              'AnAnonymousGifter',
              '274598607',
              "AnAnonymousGifter is gifting 1 Tier 1 Subs to ironmouse's community!",
            ),
            (LiveNoticeKind.raid, 'wqqexg_', '160967610', '21 raiders from wqqexg_ have joined!'),
            (
              LiveNoticeKind.system,
              'pgswnwd12',
              '23053162',
              'pgswnwd12 watched 165 consecutive streams and sparked a watch streak!',
            ),
          ],
        );
        final notices = messages.where((message) => message.type == LiveMessageType.notice);
        expect(
          notices.every((message) => message.messageId.isEmpty && message.color == LiveMessageColor.white),
          isTrue,
        );
        expect(notices.first.sentAt, DateTime.fromMillisecondsSinceEpoch(1790781250631));
        expect(
          [
            for (final message in messages)
              if (message.type == LiveMessageType.retraction) (message.data, message.sentAt?.millisecondsSinceEpoch),
          ],
          [
            (const LiveRetraction.message('aa9c3bc4-7cd1-4167-84eb-132189b4f54a'), 1790781494256),
            (const LiveRetraction.user('4668257914'), 1790781513792),
            (const LiveRetraction.message('57b50d12-d8d6-43b9-94bb-a6a75f205d2c'), 1790781548740),
            (const LiveRetraction.message('a37b3ac9-1e26-4d65-95d8-d119d806a371'), 1790782007348),
          ],
        );
        // Every chat carries the ids a retraction names; each retraction names
        // chat shown before it.
        final chat = messages.where((message) => message.type == LiveMessageType.chat).toList();
        expect(chat, hasLength(11));
        expect(chat.every((message) => message.messageId.isNotEmpty && message.userId.isNotEmpty), isTrue);
        for (final (index, message) in messages.indexed) {
          if (message.data case final LiveRetraction target) {
            final before = messages.take(index).where((earlier) => earlier.type == LiveMessageType.chat);
            expect(
              before.where((earlier) => earlier.messageId == target.messageId || earlier.userId == target.userId),
              hasLength(1),
              reason: '$target',
            );
            expect(message.messageId, isEmpty, reason: 'no id of its own');
          }
        }
        // The timeout lasted 10 s: the viewer's next line comes after it.
        final timeout = messages.indexWhere((message) => message.data == const LiveRetraction.user('4668257914'));
        expect(
          messages.skip(timeout).where((message) => message.userId == '4668257914').map((message) => message.message),
          ['ironmouseLETSGOHYPE'],
        );
      },
    );

    test("S10 (caedrel): resubs and watch streaks with the viewer's words; a moderator's announcement", () {
      final decoded = decodeAll(_recording('S10-live'));
      expect(decoded.replies, List.filled(4, 'PONG :tmi.twitch.tv'));
      expect(decoded.flagged, isFalse);
      final events = decoded.messages.skip(3).toList();
      expect(decoded.messages.take(3).every((message) => message.type == LiveMessageType.chat), isTrue);
      expect(
        [
          for (final message in events)
            (message.type.name, message.data, message.userName, message.userId, message.message),
        ],
        [
          (
            'notice',
            LiveNoticeKind.system,
            'V7_BP',
            '808764097',
            'V7_BP watched 85 consecutive streams and sparked a watch streak!',
          ),
          ('chat', null, 'V7_BP', '808764097', 'W'),
          (
            'notice',
            LiveNoticeKind.system,
            'ttvt316',
            '42952915',
            'ttvt316 watched 95 consecutive streams and sparked a watch streak!',
          ),
          (
            'chat',
            null,
            'ttvt316',
            '42952915',
            'im a rat xddConga im a rat xddConga im a rat xddConga im a rat xddConga',
          ),
          (
            'notice',
            LiveNoticeKind.subscription,
            'agr_dsfhcyd',
            '63788658',
            "agr_dsfhcyd subscribed at Tier 1. They've subscribed for 33 months!",
          ),
          ('chat', null, 'agr_dsfhcyd', '63788658', 'worth'),
          (
            'notice',
            LiveNoticeKind.system,
            'layfsauqat_kggegr',
            '335157773',
            'layfsauqat_kggegr watched 15 consecutive streams and sparked a watch streak!',
          ),
          ('chat', null, 'layfsauqat_kggegr', '335157773', 'shdd'),
          (
            'notice',
            LiveNoticeKind.subscription,
            'Vimzjlsa',
            '306402510',
            "Vimzjlsa subscribed with Prime. They've subscribed for 26 months!",
          ),
          ('chat', null, 'Vimzjlsa', '306402510', 'xddO'),
          (
            'notice',
            LiveNoticeKind.system,
            'aupdooo_',
            '3644366353',
            'aupdooo_ watched 40 consecutive streams and sparked a watch streak!',
          ),
          ('chat', null, 'aupdooo_', '3644366353', '40x rat'),
          (
            'notice',
            LiveNoticeKind.subscription,
            'hshks',
            '744595235',
            "hshks subscribed at Tier 1. They've subscribed for 33 months!",
          ),
          (
            'notice',
            LiveNoticeKind.system,
            'Jryscg_Fdq',
            '877360506',
            'For the rats that have not seen pinned; The third ep of "Will the West Win" is out, link in pinned',
          ),
          (
            'notice',
            LiveNoticeKind.subscription,
            'Zygyvnj',
            '117661460',
            "Zygyvnj subscribed with Prime. They've subscribed for 29 months!",
          ),
          ('chat', null, 'Zygyvnj', '117661460', 'Is this what peaks look like?'),
          (
            'notice',
            LiveNoticeKind.subscription,
            'OogOwjp',
            '334630448',
            "OogOwjp subscribed at Tier 1. They've subscribed for 26 months!",
          ),
          (
            'chat',
            null,
            'OogOwjp',
            '334630448',
            'hey @caedrel can you learn to play Deadlock just so you can play the Rat King',
          ),
          (
            'notice',
            LiveNoticeKind.subscription,
            'kqiofoekkod655',
            '635570510',
            "kqiofoekkod655 subscribed with Prime. They've subscribed for 36 months, currently on a 16 month streak!",
          ),
          (
            'notice',
            LiveNoticeKind.subscription,
            'ynfwaamlfwplxlb',
            '332120587',
            'ynfwaamlfwplxlb subscribed at Tier 1.',
          ),
          (
            'notice',
            LiveNoticeKind.subscription,
            'fljmubyg',
            '431002129',
            "fljmubyg subscribed with Prime. They've subscribed for 10 months!",
          ),
          (
            'notice',
            LiveNoticeKind.system,
            'yotcuckql',
            '147496924',
            'yotcuckql watched 60 consecutive streams and sparked a watch streak!',
          ),
          ('chat', null, 'yotcuckql', '147496924', 'Aware'),
          (
            'notice',
            LiveNoticeKind.subscription,
            'jguftmnrip3',
            '667743933',
            "jguftmnrip3 is gifting 1 Tier 1 Subs to Caedrel's community! They've gifted a total of 2 in the channel!",
          ),
          (
            'notice',
            LiveNoticeKind.giftedSubscription,
            'jguftmnrip3',
            '667743933',
            'jguftmnrip3 gifted a Tier 1 sub to sdo_skt!',
          ),
        ],
      );
      // The words are the viewer's chat: the line's id, colour and time.
      final words = events[5];
      expect(
        _project(words),
        _chat(
          'agr_dsfhcyd',
          'worth',
          'b4196989-341b-4d62-88ff-594fa88b5e06',
          sentAt: 1790781404228,
          color: '#008000',
          userId: '63788658',
        ),
      );
      expect(events[4].sentAt, words.sentAt);
    });

    test('S09 through the connection: the same messages in order, a PONG for each server PING', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call, now: () => _clock);
      final events = _record(connection);
      await connection.connect(const TwitchDanmakuArgs(channel: 'ironmouse'));
      final channel = connector.channels.single;
      final recording = _recording('S09-live');
      for (final frame in recording) {
        if (frame.dir == 'in') channel.incoming.add(frame.text);
      }
      final expected = decodeAll(recording).messages;
      await _until(() => _messages(events).length == expected.length);
      expect(_messages(events).map(_project), expected.map(_project));
      expect(channel.sent.skip(4), List.filled(3, 'PONG :tmi.twitch.tv'));
      expect(connector.channels, hasLength(1));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await connection.close();
    });
  });

  group('B-7 connection', () {
    test('RECONNECT switches the socket at once with the same login: no reconnect notice, no second ready', () async {
      final hold = Completer<void>();
      final connector = _Connector(hold: hold);
      final connection = TwitchDanmakuConnection(connector: connector.call, now: () => _clock);
      final events = _record(connection);
      await _withoutBackoff(() async {
        await connection.connect(_loginArgs);
        final first = connector.channels.single;
        first.incoming.add('${_line('s1', 'before')}$_reconnect${_line('s2', 'same frame, after')}');
        await _until(() => connector.endpoints.length == 2);
        expect(first.closed, isTrue, reason: 'the old socket is closed first (the framework reopens)');
        expect(connection.status, DanmakuStatus.connected, reason: 'the room stays joined during the switch');
        first.incoming.add(_line('s3', 'late, from the old socket'));
        hold.complete();
        await _until(() => connector.channels.length == 2 && connector.channels.last.sent.length == 4);
        connector.channels.last.incoming.add(_line('s4', 'from the new socket'));
        await _until(() => _messages(events).length == 3);
      });
      expect(connector.channels.last.sent, _legacyJoin('login'));
      expect(connector.endpoints, [TwitchDanmakuProtocol.endpoint, TwitchDanmakuProtocol.endpoint]);
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(_messages(events).map((message) => message.message), [
        'before',
        'same frame, after',
        'from the new socket',
      ]);
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test('an anonymous switch draws a new nick, as every join does', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(
        connector: connector.call,
        random: _Draws([_recordedDraw, 7]),
        now: () => _clock,
      );
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming.add(_reconnect);
      await _until(() => connector.channels.length == 2 && connector.channels.last.sent.length == 4);
      expect(connector.channels.first.sent, _legacyJoin('none'));
      expect(connector.channels.last.sent[1], 'NICK justinfan1007');
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test(
      'a RECONNECT within 10 s of the last switch reconnects the ordinary way; at 10 s it switches quietly',
      () async {
        final delays = <Duration>[];
        var now = _clock;
        final connector = _Connector();
        final connection = TwitchDanmakuConnection(connector: connector.call, now: () => now);
        final events = _record(connection);
        await _fastBackoff(delays, () async {
          await connection.connect(_args);
          connector.channels.last.incoming.add(_reconnect);
          await _until(() => connector.channels.length == 2 && connector.channels.last.sent.length == 4);
          now = _clock.add(const Duration(milliseconds: 9999));
          connector.channels.last.incoming.add(_reconnect);
          await _until(() => connector.channels.length == 3 && connection.isConnected);
          // The ordinary reconnect is no switch: the interval still counts from the first.
          now = _clock.add(TwitchDanmakuConnection.switchInterval);
          connector.channels.last.incoming.add(_reconnect);
          await _until(() => connector.channels.length == 4 && connector.channels.last.sent.length == 4);
        });
        expect(TwitchDanmakuConnection.switchInterval, const Duration(seconds: 10));
        expect(connector.channels.take(3).every((channel) => channel.closed), isTrue);
        expect(events, [
          const DanmakuReady(),
          const DanmakuReconnecting(DanmakuInterruption.disconnected),
          const DanmakuReady(),
        ]);
        await connection.close();
      },
    );

    test('a switch whose new socket fails is reported like any failure: one notice, then ready', () async {
      final delays = <Duration>[];
      final connector = _Connector(failAt: {2});
      final connection = TwitchDanmakuConnection(connector: connector.call, now: () => _clock);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args);
        connector.channels.single.incoming.add(_reconnect);
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(connector.endpoints, hasLength(3));
      expect(delays, contains(const Duration(seconds: 2)), reason: 'the ordinary backoff after the failure');
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('close during a switch: nothing is reported, the late handshake is closed', () async {
      final hold = Completer<void>();
      final connector = _Connector(hold: hold);
      final connection = TwitchDanmakuConnection(connector: connector.call, now: () => _clock);
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming.add(_reconnect);
      await _until(() => connector.endpoints.length == 2);
      await connection.close();
      hold.complete();
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(2));
      expect(connector.channels.last.closed, isTrue);
      expect(connector.channels.last.sent, isEmpty);
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test(
      'a refusal and a RECONNECT in one frame reopen once, as an anonymous nick; later switches stay anonymous',
      () async {
        final connector = _Connector();
        final connection = TwitchDanmakuConnection(connector: connector.call, now: () => _clock);
        final events = _record(connection);
        await _withoutBackoff(() async {
          await connection.connect(_loginArgs);
          connector.channels.single.incoming.add('$_refused$_reconnect');
          await _until(() => connector.channels.length == 2 && connection.isConnected);
          await _wait(const Duration(milliseconds: 30));
          expect(connector.endpoints, hasLength(2), reason: 'one reopen');
          connector.channels.last.incoming.add(_reconnect);
          await _until(() => connector.channels.length == 3 && connector.channels.last.sent.length == 4);
        });
        expect(connector.channels[1].sent.first, TwitchDanmakuProtocol.anonymousPassword);
        expect(connector.channels[2].sent.first, TwitchDanmakuProtocol.anonymousPassword);
        expect(events, hasLength(3));
        expect(events[0], const DanmakuReady());
        expect(events[1], isA<DanmakuReceived>().having((event) => event.message, 'message', _isCookieNotice));
        expect(events[2], const DanmakuReady(), reason: 'the refusal reopens as a new join; the switch does not');
        await connection.close();
      },
    );

    test('the expired cookie is told once per connect', () async {
      final connector = _Connector();
      final connection = TwitchDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      List<LiveMessage> notices() => [
        for (final message in _messages(events))
          if (message.type == LiveMessageType.notice) message,
      ];
      await connection.connect(_loginArgs);
      connector.channels.single.incoming.add(_refused);
      await _until(() => connector.channels.length == 2 && connection.isConnected);
      // The anonymous nick is never refused; a stray refusal is not told again.
      connector.channels.last.incoming.add(_refused);
      await _wait(const Duration(milliseconds: 30));
      expect(notices(), hasLength(1));
      await connection.connect(_loginArgs);
      connector.channels.last.incoming.add(_refused);
      await _until(() => connector.channels.length == 4 && connection.isConnected);
      expect(notices(), [
        same(TwitchDanmakuProtocol.cookieExpiredNotice),
        same(TwitchDanmakuProtocol.cookieExpiredNotice),
      ]);
      expect(notices().first, _isCookieNotice);
      await connection.close();
    });

    test('a local WebSocket server: RECONNECT moves the session to a second socket', () async {
      final sockets = <WebSocket>[];
      final received = <List<Object?>>[];
      final firstClosed = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        final index = sockets.length;
        sockets.add(socket);
        final frames = <Object?>[];
        received.add(frames);
        socket.listen(
          (frame) {
            frames.add(frame);
            if (frames.length != 4) return;
            socket.add(index == 0 ? '${_line('w1', 'first socket')}$_reconnect' : _line('w2', 'second socket'));
          },
          onDone: () {
            if (index == 0 && !firstClosed.isCompleted) firstClosed.complete();
          },
        );
      });
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      final connection = TwitchDanmakuConnection(
        random: _Draws([_recordedDraw, 1]),
        now: () => _clock,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) =>
            connectIoSocket(
              Uri.parse('ws://127.0.0.1:${server.port}/'),
              headers: headers,
              protocols: protocols,
              route: route,
              connectTimeout: connectTimeout,
            ),
      );
      addTearDown(connection.close);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).length == 2);
      await firstClosed.future.timeout(const Duration(seconds: 5));
      expect(received, [
        _legacyJoin('none'),
        [..._legacyJoin('none').take(1), 'NICK justinfan1001', ..._legacyJoin('none').skip(2)],
      ]);
      expect(_messages(events).map((message) => message.message), ['first socket', 'second socket']);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      await connection.close();
    });
  });
}
