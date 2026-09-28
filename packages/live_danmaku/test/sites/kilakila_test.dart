// KilaKila danmaku (docs/modules/M5.13-kilakila.md): the protocol and the
// connection against the archived v4's output for the recorded sessions
// (S07-live, S08-live-full) and the synthetic frames (S09-synthetic), written
// by fixtures/kilakila/danmaku/v4_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kilakila/danmaku';

const String _namespace = KilakilaDanmakuProtocol.namespace;

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

typedef _Frame = ({int index, String dir, int t, String text});

/// The frames of a recorded session, in order.
List<_Frame> _frames(String name) => [
  for (final (index, line) in File('$_root/$name/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 't': final int t, 'text': final String text})
      (index: index, dir: dir, t: t, text: text),
];

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// The archived v4's output for a session.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

String _roomOf(String name) => (_meta(name)['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;

/// v4's result per incoming frame of a recorded session, by frame index.
Map<int, Map<String, Object?>> _v4Frames(String name) => {
  for (final frame in (_v4(name)['frames']! as List<Object?>).cast<Map<String, Object?>>())
    frame['frame']! as int: frame,
};

final Map<String, Object?> _cases = _json('S09-synthetic/cases.json')! as Map<String, Object?>;

final String _syntheticRoom = _cases['roomId']! as String;

/// v4's result for every synthetic case: one per frame.
final Map<String, Object?> _v4Cases = _v4('S09-synthetic')['cases']! as Map<String, Object?>;

/// A frame of cases.json as the server sends it.
Object _serverFrame(Object? frame) => switch (frame) {
  final String text => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

/// A message in the projection v4_expected.dart writes for v4's events. v4
/// prefixed message ids with `kilakila:` (difference 1); the projection adds
/// the prefix back. v4 had no audience; the new one is written as
/// `{"kind": "online", "value": …}`.
Map<String, Object?> _eventAsV4(LiveMessage message) {
  if (message.type == LiveMessageType.online) {
    final data = message.data! as LiveAudienceUpdate;
    expect(data.kind, LiveAudienceMetricKind.onlineViewers);
    return {'kind': 'online', 'value': data.value};
  }
  expect(message.type, LiveMessageType.chat);
  expect(message.color, LiveMessageColor.white);
  expect([message.fansLevel, message.fansName], ['', '']);
  return {
    'kind': 'chat',
    'id': message.messageId.isEmpty ? null : 'kilakila:${message.messageId}',
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'userLevel': message.userLevel.isEmpty ? null : int.parse(message.userLevel),
  };
}

/// A decoded frame in v4's projection; `dropped` (v4 had no such result) is
/// false for v4.
Map<String, Object?> _asV4(KilakilaDanmakuFrame frame) => {
  'joined': frame.joined,
  'rejected': frame.refusal != null,
  'dropped': frame.dropped,
  'events': [for (final message in frame.messages) _eventAsV4(message)],
};

Map<String, Object?> _v4Result(Object? v4) => switch (v4) {
  final Map<String, Object?> thrown when thrown.containsKey('throws') => thrown,
  final Map<String, Object?> result => {
    'joined': result['joined'],
    'rejected': result['rejected'],
    'dropped': false,
    'events': result['events'],
  },
  _ => throw FormatException('v4 $v4'),
};

Map<String, Object?> _decoded(Object frame, {String? roomId}) =>
    _asV4(KilakilaDanmakuProtocol.decode(frame, roomId: roomId ?? _syntheticRoom));

/// A synthetic chat line as the v4 projection shows it.
Map<String, Object?> _chat(String text, String mid, {int? sentAt = 1790629525534}) => {
  'kind': 'chat',
  'id': 'kilakila:$mid',
  'sentAt': sentAt,
  'userId': '7300000000001',
  'userName': 'Viewer One',
  'text': text,
  'userLevel': 38,
};

const Map<String, Object?> _nothing = {'joined': false, 'rejected': false, 'dropped': false, 'events': <Object?>[]};
const Map<String, Object?> _refused = {'joined': false, 'rejected': true, 'dropped': false, 'events': <Object?>[]};
const Map<String, Object?> _dropped = {'joined': false, 'rejected': false, 'dropped': true, 'events': <Object?>[]};

Map<String, Object?> _online(int value) => {
  ..._nothing,
  'events': [
    {'kind': 'online', 'value': value},
  ],
};

List<Object?> _events(Object? v4) => (v4! as Map<String, Object?>)['events']! as List<Object?>;

/// The differences of the new decoder from v4 in the synthetic cases
/// (docs/modules/M5.13-kilakila.md, "与归档 v4 的差异"): v4's results (with
/// `dropped: false`) → the new ones, per case. Cases not listed decode as v4
/// did.
final Map<String, List<Object?> Function(List<Object?> v4)> _differences = {
  // Difference 6: a Socket.IO error packet on the namespace is a refusal.
  'a Socket.IO error packet on the namespace is a refusal': (v4) {
    expect(v4, List.filled(4, _nothing));
    return [_refused, _refused, _refused, _nothing];
  },
  // Difference 7: the server leaving the namespace or closing the transport.
  'the server leaves the namespace or closes the transport': (v4) {
    expect(v4, List.filled(4, _nothing));
    return [_dropped, _dropped, _nothing, _nothing];
  },
  // Difference 4: chat text must be text (v4 printed numbers and booleans).
  'chat text: trimmed and kept with its line breaks; blank, missing or not text is no line': (v4) {
    expect(_events(v4[4]).single, containsPair('text', '123'));
    expect(_events(v4[5]).single, containsPair('text', 'true'));
    return [v4[0], v4[1], v4[2], v4[3], _nothing, _nothing, v4[6]];
  },
  // Difference 5: user ids are numbers or text (v4 printed `{x: 1}`).
  'names and user ids: text or numbers; other types are empty': (v4) {
    expect(_events(v4[1]).single, containsPair('userId', '{x: 1}'));
    return [
      v4[0],
      {
        ..._nothing,
        'events': [
          {...(_events(v4[1]).single! as Map<String, Object?>), 'userId': ''},
        ],
      },
      v4[2],
      v4[3],
      v4[4],
    ];
  },
  // Difference 4: a time out of range loses only the time; v4 lost the
  // frame (RangeError).
  'a time out of range': (v4) {
    expect(v4, [
      {'throws': 'RangeError'},
    ]);
    return [
      {
        ..._nothing,
        'events': [_chat('far future', '1047000000000000025', sentAt: null)],
      },
    ];
  },
  // Difference 2: gifts are not reported.
  'gifts are not shown: 220 and the gift line 10004': (v4) {
    expect(_events(v4[0]).single, containsPair('kind', 'gift'));
    return [_nothing, _nothing];
  },
  // Difference 3: the room state's watchNumber is the audience.
  'the room state 637: watchNumber is the listeners now': (v4) {
    expect(v4, List.filled(2, _nothing));
    return [_online(315), _online(317)];
  },
  'room state boundaries: zero, negative, text, missing, bad escapes, bad UTF-8, plain JSON, an object': (v4) {
    expect(v4, List.filled(10, _nothing));
    return [_online(0), _nothing, _nothing, _nothing, _nothing, _nothing, _online(7), _nothing, _nothing, _nothing];
  },
};

// ---- the connection ----

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
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
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
    routes.add(route);
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

/// No heartbeat or watchdog and a short backoff: only what the test does
/// happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  joinTimeout: Duration(seconds: 8),
  reconnectBaseDelay: Duration(milliseconds: 5),
);

const String _room = '2269142054376308832';
const KilakilaDanmakuArgs _args = KilakilaDanmakuArgs(roomId: _room);

const String _joinOk =
    '42$_namespace,["connect_error","{\\"result_type\\":0,\\"code\\":0,\\"message\\":\\"join success\\"}"]';
const String _joinRefused = '42$_namespace,["connect_error","{\\"code\\":3,\\"message\\":\\"room closed\\"}"]';

KilakilaDanmakuConnection _connection(
  _Connector connector, {
  DanmakuSocketPolicy policy = _quiet,
  ProxyPolicy? proxy,
}) => KilakilaDanmakuConnection(connector: connector.call, policy: policy, proxy: proxy ?? const FixedProxyPolicy());

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

/// The server's greeting and join answer, as S07 and S08 recorded them.
void _accept(_FakeChannel channel) => channel.incoming
  ..add(
    '0{"sid":"00000000-0000-4000-8000-000000000000","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":60000}',
  )
  ..add('40')
  ..add('41')
  ..add(_joinOk)
  ..add('40$_namespace');

void main() {
  group('protocol', () {
    test("the socket, its headers, the join and the ping are v4's and the recordings'", () {
      for (final name in ['S07-live', 'S08-live-full']) {
        final roomId = _roomOf(name);
        final v4 = _v4(name)['connector']! as Map<String, Object?>;
        final handshake = (_meta(name)['handshakes']! as List<Object?>).single! as Map<String, Object?>;
        final endpoint = KilakilaDanmakuProtocol.endpoint(roomId).toString();
        expect(endpoint, (v4['endpoints']! as List<Object?>).single);
        expect(endpoint, handshake['url']);
        final join = KilakilaDanmakuProtocol.join(roomId);
        expect(join, (v4['openFrames']! as List<Object?>).single);
        final frames = _frames(name);
        expect(frames.first, (index: 0, dir: 'out', t: frames.first.t, text: join));
        expect(KilakilaDanmakuProtocol.ping, v4['heartbeat']);
        // The origin is v4's and the recordings'; the user agent is the
        // adapter's (difference 9).
        final headers = handshake['headers']! as Map<String, Object?>;
        expect(KilakilaDanmakuProtocol.handshakeHeaders['origin'], headers['origin']);
        expect((v4['headers']! as Map<String, Object?>)['origin'], headers['origin']);
        expect(headers['user-agent'], contains('Chrome/140'));
        expect(KilakilaDanmakuProtocol.handshakeHeaders['user-agent'], KilakilaApi.userAgent);
        expect(KilakilaDanmakuProtocol.handshakeHeaders.keys, ['origin', 'user-agent']);
      }
    });

    test('S08 sent only the join and the ping, every 25 s from the open, each answered by 3', () {
      final frames = _frames('S08-live-full');
      final sent = frames.where((frame) => frame.dir == 'out').toList();
      expect(sent.first.text, KilakilaDanmakuProtocol.join(_room));
      expect(sent.skip(1).map((frame) => frame.text), List.filled(5, '2'));
      final open = frames.firstWhere((frame) => frame.text.startsWith('0{')).t;
      for (final (index, ping) in sent.skip(1).indexed) {
        expect(ping.t - open, closeTo((index + 1) * 25000, 500));
        final answer = frames[ping.index + 1];
        expect((answer.dir, answer.text), ('in', '3'));
      }
      expect(KilakilaDanmakuProtocol.heartbeatInterval.inSeconds, 25);
      final greeting = jsonDecode(frames.firstWhere((frame) => frame.text.startsWith('0{')).text.substring(1));
      expect(greeting, containsPair('pingInterval', 25000));
    });

    test('a chat line fills the message model', () {
      final line = _frames('S08-live-full')[6].text;
      final frame = KilakilaDanmakuProtocol.decode(line, roomId: _room);
      final message = frame.messages.single;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, '心存善良，万物晴朗☀');
      expect(message.userName, '观众1友友友友友友友友友');
      expect(message.userId, '9808547595636');
      expect(message.userLevel, '161');
      expect(message.messageId, '1047028601860070400');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790629525534));
      expect(message.color, LiveMessageColor.white);
      expect([message.fansLevel, message.fansName, message.isLocal, message.data], ['', '', false, null]);
      expect([frame.joined, frame.refusal, frame.dropped], [false, null, false]);
    });

    test('the room state 637 gives the listeners now as onlineViewers', () {
      final frame = KilakilaDanmakuProtocol.decode(_frames('S08-live-full')[8].text, roomId: _room);
      final message = frame.messages.single;
      expect(message.type, LiveMessageType.online);
      expect([message.userName, message.message, message.messageId], ['', '', '']);
      final data = message.data! as LiveAudienceUpdate;
      expect([data.kind, data.value], [LiveAudienceMetricKind.onlineViewers, 315]);
    });

    test('refusal texts: the message, else the code; error packets: their text', () {
      String? refusal(String frame) => KilakilaDanmakuProtocol.decode(frame, roomId: _room).refusal;
      expect(refusal(_joinRefused), 'room closed');
      expect(refusal('42$_namespace,["connect_error","{\\"code\\":2,\\"message\\":\\"\\"}"]'), 'code 2');
      expect(refusal('42$_namespace,["connect_error","{}"]'), 'code null');
      expect(refusal('44$_namespace,"Not authorized"'), 'Not authorized');
      expect(refusal('44$_namespace,{"message":"Invalid namespace"}'), 'Invalid namespace');
      expect(refusal('44$_namespace,{"data":1}'), '{"data":1}');
      expect(refusal('44$_namespace,oops'), 'oops');
      expect(refusal('44$_namespace'), 'error');
      expect(refusal(_joinOk), isNull);
    });
  });

  group('recordings against v4', () {
    test('S07-live: joins where v4 joined; chats as v4 decoded them, gifts left out', () {
      final v4 = _v4Frames('S07-live');
      final roomId = _roomOf('S07-live');
      final received = _frames('S07-live').where((frame) => frame.dir == 'in').toList();
      expect(received, hasLength(v4.length));
      var chats = 0;
      var gifts = 0;
      for (final frame in received) {
        final expected = _v4Result(v4[frame.index]);
        final v4Events = expected['events']! as List<Object?>;
        gifts += v4Events.where((event) => (event! as Map<String, Object?>)['kind'] == 'gift').length;
        final kept = [
          for (final event in v4Events)
            if ((event! as Map<String, Object?>)['kind'] != 'gift') event,
        ];
        chats += kept.length;
        expect(_decoded(frame.text, roomId: roomId), {...expected, 'events': kept}, reason: 'frame ${frame.index}');
      }
      expect((chats, gifts), (5, 3));
    });

    test('S08-live-full: chats as v4 decoded them, and the listeners of every room state', () {
      final v4 = _v4Frames('S08-live-full');
      final received = _frames('S08-live-full').where((frame) => frame.dir == 'in').toList();
      expect(received, hasLength(v4.length));
      final audience = <int>[];
      var chats = 0;
      for (final frame in received) {
        final expected = _v4Result(v4[frame.index]);
        final decoded = _decoded(frame.text, roomId: _room);
        final events = decoded['events']! as List<Object?>;
        final online = [
          for (final event in events.cast<Map<String, Object?>>())
            if (event['kind'] == 'online') event['value']! as int,
        ];
        audience.addAll(online);
        final v4Events = expected['events']! as List<Object?>;
        chats += v4Events.length;
        expect(
          {
            ...decoded,
            'events': [
              for (final event in events.cast<Map<String, Object?>>())
                if (event['kind'] != 'online') event,
            ],
          },
          expected,
          reason: 'frame ${frame.index}',
        );
        if (online.isNotEmpty) expect(frame.text, contains(r'\\\"t\\\":637'));
      }
      expect(chats, 7);
      expect(audience, [
        ...List.filled(5, 315),
        316,
        316,
        312,
        312,
        312,
        312,
        314,
        ...List.filled(7, 315),
        ...List.filled(5, 316),
        ...List.filled(6, 317),
      ]);
    });
  });

  group('synthetic frames against v4 (S09-synthetic)', () {
    final cases = [
      for (final entry in _cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames}) (name: name, frames: frames),
    ];

    test('every case has v4 output, and every difference names a case', () {
      expect(cases, hasLength(24));
      expect(_v4Cases.keys, [for (final entry in cases) entry.name]);
      expect(_differences.keys.toSet().difference(_v4Cases.keys.toSet()), isEmpty);
    });

    for (final (:name, :frames) in cases) {
      test(name, () {
        final v4 = [for (final result in _v4Cases[name]! as List<Object?>) _v4Result(result)];
        expect(v4, hasLength(frames.length));
        final expected = _differences[name]?.call(v4) ?? v4;
        expect([for (final frame in frames) _decoded(_serverFrame(frame))], expected);
      });
    }
  });

  group('connection', () {
    test('timing and registration', () {
      final v4 = _v4('S07-live')['connector']! as Map<String, Object?>;
      final connection = KilakilaDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 25));
      final policy = connection.policy;
      expect(policy.heartbeatInterval.inSeconds, v4['heartbeatSeconds']);
      expect(policy.joinTimeout!.inSeconds, v4['authTimeoutSeconds']);
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 25 s, 90 s) = 90 s');
      expect(v4['silenceTimeoutSeconds'], 90);
      expect(policy.connectTimeout.inSeconds, v4['connectTimeoutSeconds']);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(KilakilaDanmakuConnection.maxRefusals, v4['maxRejections']);
      expect(connection.site, SiteIds.kilakila);
      final registry = DanmakuRegistry({SiteIds.kilakila: KilakilaDanmakuConnection.new});
      expect(registry.supports('KilaKila '), isTrue);
      expect(registry.connectionFor(SiteIds.kilakila), isA<KilakilaDanmakuConnection>());
    });

    test(
      'handshake: the broadcast socket with its headers and route; the join on open; ready once confirmed',
      () async {
        final connector = _Connector();
        const route = HttpProxyRoute('127.0.0.1', 7897);
        final connection = _connection(connector, proxy: const FixedProxyPolicy(perSite: {SiteIds.kilakila: route}));
        final events = _record(connection);
        await connection.connect(const KilakilaDanmakuArgs(roomId: ' $_room '));
        expect(connector.endpoints, [KilakilaDanmakuProtocol.endpoint(_room)]);
        expect(connector.headers.single, KilakilaDanmakuProtocol.handshakeHeaders);
        expect(connector.routes.single, route);
        final channel = connector.channels.single;
        expect(channel.sent, [KilakilaDanmakuProtocol.join(_room)]);
        expect(events, isEmpty, reason: 'not joined before the server confirms');
        expect(connection.isConnected, isFalse);
        _accept(channel);
        await _until(() => events.isNotEmpty);
        await _wait(const Duration(milliseconds: 10));
        expect(events, [const DanmakuReady()], reason: 'connect_error code 0 and 40 are one join');
        expect(connection.isConnected, isTrue);
        await connection.close();
        expect(channel.closed, isTrue);
      },
    );

    test("the namespace's 40 alone is the join too", () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      connector.channels.single.incoming.add('40$_namespace');
      await _until(() => events.isNotEmpty);
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('replaying S08-live-full reports its 7 chats and 30 audience updates in order, and nothing else', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      final expected = <Object?>[];
      for (final frame in _frames('S08-live-full')) {
        if (frame.dir != 'in') continue;
        channel.incoming.add(frame.text);
        expected.addAll(_decoded(frame.text, roomId: _room)['events']! as List<Object?>);
      }
      expect(expected, hasLength(37));
      await _until(() => _messages(events).length == expected.length);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map(_eventAsV4), expected);
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(channel.sent, [KilakilaDanmakuProtocol.join(_room)]);
      await connection.close();
    });

    test('the Engine.IO ping goes out at every tick from the open, before the join too, and on demand', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = KilakilaDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 3);
          expect(sent.take(3), [KilakilaDanmakuProtocol.join(_room), '2', '2']);
          connection.heartbeat();
          await _until(() => sent.length >= 4);
          expect(sent.skip(1), everyElement('2'));
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
      expect(periods, [const Duration(seconds: 25)]);
    });

    test('a join not confirmed in time replaces the socket, which joins again', () async {
      final connector = _Connector();
      final connection = _connection(
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 100),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => events.isNotEmpty);
      // A late confirmation on the given-up socket, before the reconnect
      // (200 ms later), joins nothing.
      final first = connector.channels.single;
      first.incoming.add('40$_namespace');
      await _wait(const Duration(milliseconds: 20));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      expect(connection.isConnected, isFalse);
      await _until(() => connector.channels.length == 2);
      expect(first.closed, isTrue);
      final second = connector.channels.last;
      expect(second.sent, [KilakilaDanmakuProtocol.join(_room)]);
      _accept(second);
      await _until(() => events.whereType<DanmakuReady>().isNotEmpty);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('a refused join reconnects with a protocolError notice; a later join clears the count', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      for (var round = 0; round < 3; round++) {
        final channels = connector.channels.length;
        connector.channels.last.incoming
          ..add('0{"sid":"x"}')
          ..add(_joinRefused)
          // A confirmation after the refusal, on the same socket, is ignored.
          ..add('40$_namespace');
        await _until(() => connector.channels.length == channels + 1);
      }
      _accept(connector.channels.last);
      await _until(() => events.whereType<DanmakuReady>().isNotEmpty);
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(
        events.where(
          (event) => event == const DanmakuReconnecting(DanmakuInterruption.protocolError, detail: 'room closed'),
        ),
        hasLength(3),
      );
      expect(connector.channels.take(3).every((channel) => channel.closed), isTrue);
      expect(connector.channels.every((channel) => channel.sent.first == KilakilaDanmakuProtocol.join(_room)), isTrue);
      // Joined again: three more refusals are tolerated.
      for (var round = 0; round < 3; round++) {
        final channels = connector.channels.length;
        connector.channels.last.incoming.add(_joinRefused);
        await _until(() => connector.channels.length == channels + 1);
      }
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      await connection.close();
    });

    test('the fourth refusal in a row ends with connectionFailed', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      for (var socket = 1; socket <= 4; socket++) {
        await _until(() => connector.channels.length == socket);
        connector.channels.last.incoming.add(_joinRefused);
      }
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(connector.channels, hasLength(4));
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: room closed'),
      );
      expect(
        events.whereType<DanmakuReconnecting>().where((event) => event.reason == DanmakuInterruption.protocolError),
        hasLength(3),
      );
      expect(connection.status, DanmakuStatus.closed);
      await _wait(const Duration(milliseconds: 30));
      expect(connector.channels, hasLength(4), reason: 'no reconnect after the end');
      expect(connector.channels.last.closed, isTrue);
    });

    test('a server leaving the namespace or closing the transport is reconnected and joined again', () async {
      for (final drop in ['41$_namespace', '1']) {
        final connector = _Connector();
        final connection = _connection(connector);
        final events = _record(connection);
        await connection.connect(_args);
        _accept(connector.channels.single);
        await _until(() => connection.isConnected);
        connector.channels.single.incoming
          ..add(drop)
          // Frames the old socket still delivers are not this room's.
          ..add(_frames('S08-live-full')[6].text);
        await _until(() => connector.channels.length == 2);
        expect(connection.isConnected, isFalse);
        _accept(connector.channels.last);
        await _until(() => events.whereType<DanmakuReady>().length == 2);
        expect(events, [
          const DanmakuReady(),
          const DanmakuReconnecting(DanmakuInterruption.disconnected),
          const DanmakuReady(),
        ], reason: drop);
        await connection.close();
      }
    });

    test('arguments without a broadcast end at once, without a handshake', () async {
      for (final roomId in ['', '  ', 'abc', '0123', '-1', '12a']) {
        final connector = _Connector();
        final connection = _connection(connector);
        final events = _record(connection);
        await connection.connect(KilakilaDanmakuArgs(roomId: roomId));
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast'),
        ], reason: roomId);
        expect(connector.endpoints, isEmpty);
      }
      await expectLater(
        KilakilaDanmakuConnection().connect(const PicartoDanmakuArgs(channelName: 'a', channelId: 1)),
        throwsArgumentError,
      );
    });

    test('after close nothing is reported; another connect replaces the broadcast', () async {
      final connector = _Connector();
      final connection = _connection(connector);
      final events = _record(connection);
      await connection.connect(_args);
      final first = connector.channels.single;
      _accept(first);
      await _until(() => connection.isConnected);
      await connection.connect(const KilakilaDanmakuArgs(roomId: '2268805595228274844'));
      expect(first.closed, isTrue);
      expect(connector.endpoints.last, KilakilaDanmakuProtocol.endpoint('2268805595228274844'));
      expect(connector.channels.last.sent, [KilakilaDanmakuProtocol.join('2268805595228274844')]);
      // The old room's frames go nowhere.
      first.incoming.add(_frames('S08-live-full')[6].text);
      _accept(connector.channels.last);
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      await connection.close();
      final count = events.length;
      connector.channels.last.incoming
        ..add(_frames('S08-live-full')[6].text)
        ..add(_frames('S08-live-full')[8].text);
      await _wait(const Duration(milliseconds: 20));
      expect(events, hasLength(count));
      expect(_messages(events), isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a real local server: the path and query, the headers, the text frames, ping and pong', () async {
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
        handshake['path'] = '${request.uri.path}?${request.uri.query}';
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((data) {
          received.add(data);
          if (data == '2') socket.add('3');
          if (data is String && data.startsWith('40$_namespace')) {
            socket
              ..add(_joinOk)
              ..add('40$_namespace');
            for (final index in [6, 8]) {
              socket.add(_frames('S08-live-full')[index].text);
            }
          }
        });
        socket
          ..add(
            '0{"sid":"00000000-0000-4000-8000-000000000000","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":60000}',
          )
          ..add('40')
          ..add('41');
      });
      final connection = KilakilaDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint.host, KilakilaDanmakuProtocol.host);
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
      await _until(() => received.length == 2);
      final endpoint = KilakilaDanmakuProtocol.endpoint(_room);
      expect(handshake['path'], '${endpoint.path}?${endpoint.query}');
      expect(handshake['origin'], KilakilaApi.origin);
      // dart:io's handshake keeps its own user agent in front of the one given.
      expect(handshake['user-agent'], endsWith(KilakilaApi.userAgent));
      expect(received, [KilakilaDanmakuProtocol.join(_room), '2'], reason: 'text frames');
      expect(events.first, const DanmakuReady());
      expect(_messages(events).map((message) => message.type), [LiveMessageType.chat, LiveMessageType.online]);
      await connection.close();
    });
  });
}
