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
final List<({String dir, String text})> _frames = [
  for (final line in File('$_root/S07-live/frames.jsonl').readAsLinesSync())
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
Map<String, Object?> _chat(String name, String text, String id, {int? sentAt, String color = '#ffffff'}) => {
  'type': 'chat',
  'userName': name,
  'userId': '',
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
  new({this.fail = false, this.hold});

  final bool fail;

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
    if (fail) throw const SocketException('refused');
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

void main() {
  group('protocol', () {
    test("join lines are 3.x's for every stored cookie, read through M4.8's chatLogin", () {
      final cookies = (_recorded['cookies']! as Map<String, Object?>).cast<String, String>();
      // M4.8's TwitchApi.cookieValue takes the first of repeated names and
      // compares names without case; 3.x's _parseCookie kept the last one and
      // matched names exactly (docs/modules/M5.8-twitch.md, "与 v3 的对照").
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

    /// The intentional differences (docs/modules/M5.8-twitch.md), applied to
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
        };
    const refusals = {'a refused login: NOTICE * and no chat'};

    test('every case has 3.x output', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
      expect(differences.keys.every(expected.containsKey), isTrue);
      expect(refusals.every(expected.containsKey), isTrue);
    });

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        final messages = <Map<String, Object?>>[];
        final sent = <String>[];
        final rejected = <bool>[];
        for (final frame in testCase['frames']! as List<Object?>) {
          final data = _serverFrame(frame);
          final decoded = TwitchDanmakuProtocol.decode(
            data is String ? data : utf8.decode(data as List<int>, allowMalformed: true),
          );
          messages.addAll(decoded.messages.map(_project));
          sent.addAll(decoded.replies);
          rejected.add(decoded.loginRejected);
        }
        final legacy = expected[name]!;
        final want = differences[name]?.call(legacy) ?? legacy;
        expect(messages, want.messages);
        expect(sent, want.sent);
        expect(rejected.every((value) => value == refusals.contains(name)), isTrue);
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

    test('a refused login reopens at once as an anonymous nick, without a notice', () async {
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
        await _until(() => _messages(events).isNotEmpty);
      });
      expect(connector.channels, hasLength(2));
      expect(connector.endpoints, [TwitchDanmakuProtocol.endpoint, TwitchDanmakuProtocol.endpoint]);
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      expect(_messages(events).single.message, 'chat as justinfan');
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
      expect(events, [const DanmakuReady()]);
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
}
