import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/sites/douyin/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/douyin/danmaku';

Map<String, dynamic> _value(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

List<Map<String, dynamic>> _lines(String sample) => [
  for (final line in File('$_root/$sample/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
];

Uint8List _bytes(Map<String, dynamic> line) => base64.decode(line['b64'] as String);

/// 3.x's output for the recorded session (S13-live).
final Map<String, dynamic> _live = _value('S13-live');
final List<Map<String, dynamic>> _liveLines = _lines('S13-live');
final Map<String, dynamic> _meta =
    jsonDecode(File('$_root/S13-live/meta.json').readAsStringSync()) as Map<String, dynamic>;

DouyinDanmakuArgs _argsOf(Map<String, dynamic> json, {String? cookie}) => DouyinDanmakuArgs(
  webRid: json['webRid'] as String,
  roomId: json['roomId'] as String,
  userId: json['userId'] as String,
  cookie: cookie ?? json['cookie'] as String,
);

final DouyinDanmakuArgs _args = _argsOf(_live['args'] as Map<String, dynamic>);
final Uint8List _heartbeat = DouyinDanmakuProtocol.heartbeat();

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'data': switch (message.data) {
    null => null,
    final LiveAudienceUpdate update => {'kind': update.kind.name, 'value': update.value},
    final other => '$other',
  },
};

/// The effects of one decoded frame, in the generator's form: the
/// acknowledgement sent first, then the messages.
List<Map<String, Object?>> _effects(DouyinDanmakuFrame frame) => [
  if (frame.ack case final ack?) {'send': base64.encode(ack)},
  for (final message in frame.messages) {'message': _project(message)},
];

/// 3.x's effects of one frame without its log line (the new decoder reports
/// errors instead of logging them).
List<Map<String, Object?>> _legacy(Map<String, dynamic> frame) => [
  for (final effect in frame['effects'] as List<dynamic>)
    if (!(effect as Map<String, dynamic>).containsKey('error')) Map<String, Object?>.of(effect),
];

bool _legacyFailed(Map<String, dynamic> frame) =>
    (frame['effects'] as List<dynamic>).any((effect) => (effect as Map<String, dynamic>).containsKey('error'));

Map<String, Object?> _chat(
  String text, {
  String userName = '观众1',
  String userId = '579432622234547',
  String messageId = 'douyin:7690224691106976802',
}) => {
  'message': {
    'type': 'chat',
    'userName': userName,
    'userId': userId,
    'message': text,
    'color': '#ffffff',
    'userLevel': '',
    'fansLevel': '',
    'fansName': '',
    'isLocal': false,
    'messageId': messageId,
    'sentAt': null,
    'data': null,
  },
};

final class _Channel implements SocketChannel {
  new(this._connector);

  final _Connector _connector;
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Uint8List> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    final bytes = Uint8List.fromList(data as List<int>);
    sent.add(bytes);
    _connector.onSend?.call(bytes);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// Hands out fake sockets and records every handshake.
final class _Connector {
  new({this.fail = false});

  final bool fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<_Channel> channels = [];
  void Function(Uint8List bytes)? onSend;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    if (fail) throw const SocketException('refused');
    final channel = _Channel(this);
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

Map<String, String> _lowerCase(Map<String, dynamic> headers) => {
  for (final MapEntry(:key, :value) in headers.entries) key.toLowerCase(): value as String,
};

/// The recorded frames sent by the client after each received one (the
/// acknowledgements), and every received frame.
final List<Uint8List> _recordedAcks = [
  for (final line in _liveLines)
    if (line['dir'] == 'out' && !_equals(_bytes(line), _heartbeat)) _bytes(line),
];

bool _equals(List<int> a, List<int> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

final List<Uint8List> _received = [
  for (final line in _liveLines)
    if (line['dir'] == 'in') _bytes(line),
];

/// Every effect 3.x had over the whole recording, in order.
List<Map<String, Object?>> get _liveEffects => [
  for (final frame in _live['frames'] as List<dynamic>) ..._legacy(frame as Map<String, dynamic>),
];

void main() {
  group('protobuf reader', () {
    test('varints: up to ten bytes, wrapping to 64 bits; longer or truncated ones fail', () {
      final writer = ProtoWriter()..integer(1, -1);
      final bytes = writer.toBytes();
      expect(bytes, [0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]);
      final message = ProtoMessage.decode(bytes);
      expect(message.integer(1), -1);
      expect(ProtoMessage.unsigned(message.integer(1)!), '18446744073709551615');
      expect(ProtoMessage.unsigned(int.parse('7690183442860198697')), '7690183442860198697');
      expect(ProtoMessage.unsigned(0), '0');
      expect(() => ProtoMessage.decode([0x08, for (var i = 0; i < 10; i++) 0xFF, 0x01]), throwsFormatException);
      expect(() => ProtoMessage.decode(const [0x08, 0x80]), throwsFormatException);
    });

    test('field 0, bad lengths, wire types 6 and 7 and a lone group end fail', () {
      expect(() => ProtoMessage.decode(const [0x00]), throwsFormatException);
      expect(() => ProtoMessage.decode(const [0x0A, 0x05, 0x61]), throwsFormatException);
      // A length of −1 as a signed 32-bit value.
      expect(() => ProtoMessage.decode(const [0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]), throwsFormatException);
      expect(() => ProtoMessage.decode(const [0x0E]), throwsFormatException);
      expect(() => ProtoMessage.decode(const [0x0F]), throwsFormatException);
      expect(() => ProtoMessage.decode(const [0x0C]), throwsFormatException);
      expect(ProtoMessage.decode(const []).fields, isEmpty);
    });

    test('groups are skipped to their end; fixed fields are read', () {
      final message = ProtoMessage.decode(const [
        0x2B, 0x08, 0x01, 0x13, 0x10, 0x02, 0x14, 0x2C, // group 5 { 1: 1, group 2 { 2: 2 } }
        0x1A, 0x01, 0x61, // 3: "a"
        0x25, 0x01, 0x00, 0x00, 0x00, // 4: fixed32 1
        0x31, 0x02, 0, 0, 0, 0, 0, 0, 0, // 6: fixed64 2
      ]);
      expect(message.string(3), 'a');
      expect(message.fields.map((field) => field.number), [5, 3, 4, 6]);
      expect(message.fields[2].value, 1);
      expect(message.fields[3].value, 2);
      expect(
        () => ProtoMessage.decode(const [0x2B, 0x08, 0x01, 0x34]),
        throwsFormatException,
        reason: 'end of group 6',
      );
      expect(() => ProtoMessage.decode(const [0x2B, 0x08, 0x01]), throwsFormatException, reason: 'no end');
    });

    test("3.x's runtime: last value wins, other wire types are ignored, messages merge, bools read 32 bits", () {
      final bytes = [
        ...(ProtoWriter()
              ..string(3, 'a')
              ..integer(3, 5)
              ..string(3, 'b')
              ..integer(3, 6)
              ..bytes(1, (ProtoWriter()..integer(2, 7)).toBytes())
              ..integer(1, 9)
              ..bytes(1, (ProtoWriter()..integer(3, 8)).toBytes())
              ..integer(9, 1 << 32)
              ..integer(10, (1 << 32) | 1))
            .toBytes(),
      ];
      final message = ProtoMessage.decode(bytes);
      expect(message.string(3), 'b');
      expect(message.integer(3), 6);
      expect(message.message(1)?.integer(2), 7);
      expect(message.message(1)?.integer(3), 8);
      expect(message.messages(1), hasLength(2));
      expect(message.message(4), isNull);
      expect(message.string(4), isNull);
      expect(message.flag(9), isFalse);
      expect(message.flag(10), isTrue);
      expect(message.flag(11), isFalse);
      expect(
        ProtoMessage.decode(const [0x0A, 0x02, 0xE4, 0xB8]).string(1),
        '\u{FFFD}',
        reason: 'malformed UTF-8 is replaced',
      );
    });
  });

  group('client frames and handshake', () {
    test("the heartbeat, also sent to join, is 3.x's and the recorded one", () {
      expect(base64.encode(_heartbeat), _live['heartbeat']);
      expect(base64.encode(_heartbeat), _live['join']);
      expect(_bytes(_liveLines.first), _heartbeat, reason: 'the recording starts with the join heartbeat');
    });

    test("the endpoints are 3.x's, and the recorded handshake's", () {
      final endpoints = DouyinDanmakuProtocol.endpoints(
        _args,
        signature: _live['signature'] as String,
        now: DateTime.fromMillisecondsSinceEpoch(_live['cursorTime'] as int),
      );
      expect(endpoints.map((endpoint) => '$endpoint'), _live['endpoints']);
      final recorded = ((_meta['handshakes'] as List<dynamic>).single as Map<String, dynamic>)['url'] as String;
      expect('${endpoints.first}', recorded);
      expect(endpoints.map((endpoint) => endpoint.host), DouyinDanmakuProtocol.hosts);
      // REG-DOUYIN-002: the signature is a query value, `+` and `/` encoded.
      final signed = DouyinDanmakuProtocol.endpoints(_args, signature: 'A+B/C=', now: DateTime(2026));
      for (final endpoint in signed) {
        expect(endpoint.queryParameters['signature'], 'A+B/C=');
        expect('$endpoint', contains('signature=A%2BB%2FC%3D'));
        expect(endpoint.queryParameters['room_id'], _args.roomId);
        expect(endpoint.queryParameters['user_unique_id'], _args.userId);
        expect(endpoint.queryParameters['webcast_sdk_version'], '1.0.15');
      }
    });

    test("the handshake headers are 3.x's: UA, the cookie when there is one, Origin, Referer", () {
      expect(_args.headers, _lowerCase(_live['headers'] as Map<String, dynamic>));
      final withCookie = _argsOf(_live['args'] as Map<String, dynamic>, cookie: 'ttwid=1%7Csynthetic');
      expect(withCookie.headers, _lowerCase(_live['headersWithCookie'] as Map<String, dynamic>));
      final blank = _argsOf(_live['args'] as Map<String, dynamic>, cookie: '  ');
      expect(blank.headers, _lowerCase(_live['headersWithBlankCookie'] as Map<String, dynamic>));
    });

    test('an acknowledgement writes every field, even empty ones, as 3.x did', () {
      expect(base64.encode(DouyinDanmakuProtocol.ack(0, '')), 'EAA6A2Fja0IA');
      final ack = ProtoMessage.decode(DouyinDanmakuProtocol.ack(-1, 'ext'));
      expect(ProtoMessage.unsigned(ack.integer(2)!), '18446744073709551615');
      expect(ack.string(7), 'ack');
      expect(ack.string(8), 'ext');
    });
  });

  group('recorded frames (S13-live) against 3.x', () {
    test('every received frame: the same acknowledgement and messages as 3.x', () {
      final frames = _live['frames'] as List<dynamic>;
      expect(frames, hasLength(_received.length));
      var index = 0;
      for (final item in frames) {
        final frame = item as Map<String, dynamic>;
        final line = _liveLines[(frame['line'] as int) - 1];
        expect(line['dir'], 'in');
        final decoded = DouyinDanmakuProtocol.decode(_bytes(line), roomId: _args.roomId);
        expect(_effects(decoded), _legacy(frame), reason: 'line ${frame['line']}');
        expect(_legacyFailed(frame), isFalse);
        expect(decoded.errors, isEmpty);
        index++;
      }
      expect(index, 81);
      final effects = _liveEffects;
      expect(effects.where((effect) => effect.containsKey('send')), hasLength(78));
      final messages = [for (final effect in effects) ?effect['message'] as Map<String, Object?>?];
      expect(messages.where((message) => message['type'] == 'chat'), hasLength(215));
      expect(messages.where((message) => message['type'] == 'online'), hasLength(16));
      expect(messages.map((message) => message['sentAt']).toSet(), {null}, reason: 'no chat carries createTime');
    });

    test('the acknowledgements are the ones recorded', () {
      final acks = [for (final frame in _received) ?DouyinDanmakuProtocol.decode(frame, roomId: _args.roomId).ack];
      expect(acks, _recordedAcks);
      expect(acks, hasLength(78));
    });

    test("another broadcast's room_id drops every chat, not the audience or the acknowledgements", () {
      final decoded = [for (final frame in _received) DouyinDanmakuProtocol.decode(frame, roomId: '1')];
      expect(decoded.expand((frame) => frame.messages).map((message) => message.type).toSet(), {
        LiveMessageType.online,
      });
      expect(decoded.where((frame) => frame.ack != null), hasLength(78));
    });
  });

  group('synthetic frames (S13-vectors) against 3.x', () {
    final lines = _lines('S13-vectors');
    final vectors = [
      for (final vector in _value('S13-vectors')['vectors'] as List<dynamic>) vector as Map<String, dynamic>,
    ];
    const send =
        'EO3ZjNWSt92CRDoDYWNrQlxpbnRlcm5hbF9zcmM6cHVzaHNlcnZlcnxmaXJzdF9yZXFfbXM6MTc5MDUxOTk3MTAyNXx3c3NfbXNnX3R5'
        'cGU6cnx3cmRzX3Y6NzY5MDIyNDcxMzk4NDkwNjUzNw==';

    /// The intentional differences (docs/modules/M5.4-douyin.md), applied to
    /// 3.x's effects of the vector's only frame.
    final differences = <String, List<Map<String, Object?>> Function(List<Map<String, Object?>>)>{
      // 3.x lost the rest of the frame after an unreadable message.
      'malformed-chat-before-good-chat': (legacy) {
        expect(legacy, [
          {'send': send},
        ]);
        return [
          ...legacy,
          _chat('after the bad one'),
          {
            'message': {
              ..._chat('')['message']! as Map<String, Object?>,
              'type': 'online',
              'userName': '',
              'userId': '',
              'messageId': '',
              'data': {'kind': 'onlineViewers', 'value': 306000},
            },
          },
        ];
      },
      'malformed-online-before-good-chat': (legacy) {
        expect(legacy, [
          {'send': send},
        ]);
        return [...legacy, _chat('after the bad one')];
      },
      // 3.x's DateTime threw on a time out of range, losing the rest too.
      'create-time-out-of-range': (legacy) {
        expect(legacy, [
          {'send': send},
        ]);
        return [...legacy, _chat('after it')];
      },
      // 3.x printed uint64 ids signed: this broadcast's room id did not match.
      'uint64-ids-above-2^63': (legacy) {
        expect(legacy, [
          {'send': send},
        ]);
        return [
          ...legacy,
          _chat(
            'room id past 2^63',
            userName: 'max',
            userId: '18446744073709551615',
            messageId: 'douyin:9300000000000000002',
          ),
        ];
      },
    };

    test('every vector has 3.x output; every difference is still needed', () {
      expect(vectors, hasLength(25));
      final names = {for (final vector in vectors) vector['vector']};
      expect(differences.keys.every(names.contains), isTrue);
      expect(lines.map((line) => line['vector']).toSet(), names);
    });

    for (final vector in vectors) {
      final name = vector['vector'] as String;
      test(name, () {
        final args = _argsOf(vector['args'] as Map<String, dynamic>);
        final frames = vector['frames'] as List<dynamic>;
        for (final item in frames) {
          final frame = item as Map<String, dynamic>;
          final line = lines[(frame['line'] as int) - 1];
          expect(line['vector'], name);
          final decoded = DouyinDanmakuProtocol.decode(_bytes(line), roomId: args.roomId);
          final legacy = _legacy(frame);
          final difference = differences[name];
          if (difference == null) {
            expect(_effects(decoded), legacy, reason: 'line ${frame['line']}');
            expect(decoded.errors.isNotEmpty, _legacyFailed(frame), reason: 'errors of line ${frame['line']}');
          } else {
            expect(frames, hasLength(1));
            expect(_effects(decoded), difference(legacy));
            expect(_effects(decoded), isNot(legacy));
          }
        }
      });
    }
  });

  group('connection', () {
    DouyinDanmakuConnection connection(_Connector connector) => DouyinDanmakuConnection(
      connector: connector.call,
      random: Random(7),
      now: () => DateTime.fromMillisecondsSinceEpoch(1790519970273),
    );

    test('opens the first edge, signed, with the room headers; ready at once, then a heartbeat', () async {
      final connector = _Connector();
      final douyin = connection(connector);
      final events = _record(douyin);
      await douyin.connect(_args);
      final signature = DouyinSigner(
        userAgent: DouyinApi.userAgent,
        random: Random(7),
      ).danmakuSignature(roomId: _args.roomId, userUniqueId: _args.userId);
      expect(connector.endpoints, [
        DouyinDanmakuProtocol.endpoints(
          _args,
          signature: signature,
          now: DateTime.fromMillisecondsSinceEpoch(1790519970273),
        ).first,
      ]);
      expect(connector.endpoints.single.queryParameters['cursor'], 'h-1_t-1790519970273_r-1_d-1_u-1');
      expect(connector.headers.single, _args.headers);
      expect(events, [const DanmakuReady()]);
      expect(douyin.isConnected, isTrue);
      expect(connector.channels.single.sent, [_heartbeat]);
      await douyin.close();
    });

    test("3.x's timing: 10 s heartbeat, 45 s silence limit, no join timer, 8 reconnects", () {
      final douyin = DouyinDanmakuConnection();
      expect(douyin.heartbeatInterval, const Duration(seconds: 10));
      expect(douyin.site, SiteIds.douyin);
      final policy = douyin.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 10));
      expect(policy.inactivityTimeout, const Duration(seconds: 45));
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends the heartbeat on its 10 s timer and on demand; nothing after close', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final douyin = connection(connector)..heartbeat();
          await douyin.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 3);
          expect(sent.take(3), [_heartbeat, _heartbeat, _heartbeat]);
          await douyin.close();
          final count = sent.length;
          douyin.heartbeat();
          await _wait(const Duration(milliseconds: 20));
          expect(sent, hasLength(count));
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            periods.add(period);
            return parent.createPeriodicTimer(zone, const Duration(milliseconds: 5), callback);
          },
        ),
      );
      expect(periods, [const Duration(seconds: 10)]);
    });

    test("replaying the recording sends and reports what 3.x did, in 3.x's order", () async {
      final connector = _Connector();
      final douyin = connection(connector);
      final timeline = <Map<String, Object?>>[];
      douyin.events.listen((event) {
        if (event is DanmakuReceived) timeline.add({'message': _project(event.message)});
      });
      await douyin.connect(_args);
      connector.onSend = (bytes) => timeline.add({'send': base64.encode(bytes)});
      final channel = connector.channels.single;
      _received.forEach(channel.incoming.add);
      final expected = _liveEffects;
      await _until(() => timeline.length == expected.length);
      expect(timeline, expected);
      expect(channel.sent.skip(1), _recordedAcks, reason: 'the join heartbeat, then the recorded acknowledgements');
      await douyin.close();
    });

    test("another broadcast's chat is dropped; text frames are ignored", () async {
      final connector = _Connector();
      final douyin = connection(connector);
      final events = _record(douyin);
      await douyin.connect(DouyinDanmakuArgs(webRid: '1', roomId: '1', userId: _args.userId, cookie: ''));
      final channel = connector.channels.single
        ..incoming.add('text frame')
        ..incoming.add(_received[1]);
      await _until(() => channel.sent.length == 2);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events), isEmpty, reason: 'every recorded chat names room 7690183442860198697');
      await douyin.close();
    });

    test('a cookie goes into the handshake', () async {
      final connector = _Connector();
      final douyin = connection(connector);
      await douyin.connect(_argsOf(_live['args'] as Map<String, dynamic>, cookie: 'ttwid=1%7Csynthetic'));
      expect(connector.headers.single, _lowerCase(_live['headersWithCookie'] as Map<String, dynamic>));
      await douyin.close();
    });

    test('a dropped socket moves to the other edge after 1 s with the same URL, joins and is ready again', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final douyin = connection(connector);
      final events = _record(douyin);
      await _fastBackoff(delays, () async {
        await douyin.connect(_args);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && douyin.isConnected);
      });
      expect(delays.first, const Duration(seconds: 1), reason: 'two edges: the next one at once, 1 s × 1');
      expect(connector.endpoints.map((endpoint) => endpoint.host), DouyinDanmakuProtocol.hosts);
      expect(connector.endpoints.last.query, connector.endpoints.first.query, reason: '3.x kept signature and cursor');
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [_heartbeat]);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await douyin.close();
    });

    test('reconnects alternate the edges, waiting 1, 2, 2, 3, 3, 4, 4, 5 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(fail: true);
      final douyin = connection(connector);
      final events = _record(douyin);
      await _fastBackoff(delays, () async {
        await douyin.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays, [
        for (final seconds in [1, 2, 2, 3, 3, 4, 4, 5]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints.map((endpoint) => endpoint.host), [
        for (var i = 0; i < 9; i++) DouyinDanmakuProtocol.hosts[i % 2],
      ]);
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(
        events.last,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('refused')),
      );
      expect(events, hasLength(2));
      expect(douyin.status, DanmakuStatus.closed);
    });

    test('close: no event, acknowledgement or heartbeat afterwards; closing twice is harmless', () async {
      final connector = _Connector();
      final douyin = connection(connector);
      final events = _record(douyin);
      await douyin.close();
      await douyin.connect(_args);
      final channel = connector.channels.single;
      await douyin.close();
      await douyin.close();
      channel.incoming.add(_received[1]);
      douyin.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, [_heartbeat]);
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(douyin.status, DanmakuStatus.idle);
    });

    test('connecting to another broadcast closes the first socket and filters by the new room_id', () async {
      final connector = _Connector();
      final douyin = connection(connector);
      final events = _record(douyin);
      await douyin.connect(DouyinDanmakuArgs(webRid: '1', roomId: '1', userId: _args.userId, cookie: ''));
      await douyin.connect(_args);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.endpoints.last.queryParameters['room_id'], _args.roomId);
      connector.channels.first.incoming.add(_received[1]);
      connector.channels.last.incoming.add(_received[1]);
      await _until(() => _messages(events).isNotEmpty);
      await _wait(const Duration(milliseconds: 10));
      expect(_messages(events).map((message) => message.message), ['木森大气', '1', '左上角有苹果18手机']);
      await douyin.close();
    });

    test('takes DouyinDanmakuArgs only', () async {
      final douyin = connection(_Connector());
      await expectLater(douyin.connect(_args.roomId), throwsArgumentError);
      expect(douyin.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under douyin', () {
      final registry = DanmakuRegistry({SiteIds.douyin: DouyinDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.douyin]);
      expect(registry.connectionFor(' Douyin '), isA<DouyinDanmakuConnection>());
      expect(registry.connectionFor('douyu'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the handshake and the recorded session end to end', () async {
      final received = <Uint8List>[];
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          received.add(Uint8List.fromList(frame as List<int>));
          if (received.length == 1) _received.forEach(socket.add);
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final douyin = DouyinDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          requested.add(endpoint);
          return connectIoSocket(
            endpoint.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(douyin);
      final args = _argsOf(_live['args'] as Map<String, dynamic>, cookie: 'ttwid=1%7Csynthetic');
      await douyin.connect(args);
      final expected = _liveEffects;
      final messages = [for (final effect in expected) ?effect['message']];
      await _until(() => _messages(events).length == messages.length && received.length == 79);
      final request = requests.single;
      expect(request.uri.path, DouyinDanmakuProtocol.path);
      expect(request.uri.queryParameters, requested.single.queryParameters);
      // dart:io adds the UA after its own default, as it did under 3.x's
      // IOWebSocketChannel (docs/modules/M5.4-douyin.md, 框架层的发现).
      expect(
        request.headers.value('user-agent'),
        allOf(startsWith('Dart/'), endsWith(' (dart:io), ${DouyinApi.userAgent}')),
      );
      expect(request.headers.value('origin'), 'https://live.douyin.com');
      expect(request.headers.value('referer'), 'https://live.douyin.com/${args.webRid}');
      expect(request.headers.value('cookie'), 'ttwid=1%7Csynthetic');
      expect(received, [_heartbeat, ..._recordedAcks]);
      expect(_messages(events).map(_project), messages);
      douyin.heartbeat();
      await _until(() => received.length == 80);
      expect(received.last, _heartbeat);
      await douyin.close();
    });
  });
}
