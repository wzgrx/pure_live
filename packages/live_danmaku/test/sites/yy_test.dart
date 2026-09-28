import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/sites/yy/packet.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/yy/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded session (S08-live): frames in order, with their direction.
final List<({String dir, Uint8List bytes})> _frames = [
  for (final line in File('$_root/S08-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': final String dir, 'b64': final String b64}) (dir: dir, bytes: base64Decode(b64)),
];

/// 3.x's output for S08-live (fixtures/yy/danmaku/legacy_expected.dart).
final Map<String, Object?> _recorded =
    (_json('S08-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

final int _topSid = _recorded['topSid']! as int;
final String _recordedUuid = _recorded['uuid']! as String;
final YyDanmakuArgs _args = YyDanmakuArgs(topSid: _topSid, subSid: _recorded['subSid']! as int);

/// The recorded server answers: anonymous login, AP login, channel join, and
/// the two chat lines.
Uint8List get _loginAnswer => _frames[1].bytes;
Uint8List get _apAnswer => _frames[3].bytes;
Uint8List get _joinedAnswer => _frames[6].bytes;
List<Uint8List> get _chatFrames => [_frames[189].bytes, _frames[488].bytes];

/// The text of the recorded chat inside its XML wrapper.
const _recordedChat = '发起了欢乐投票，铁铁们快点击左上角图标支持吧！参与还有机会获奖励哦~';

/// 3.x's failure and warning texts and the new ones (the wording of
/// pure_live_TV, which translated them).
const _texts = {
  'YY WebSocket 尾部数据不足 10 字节': 'YY WebSocket trailer shorter than 10 bytes',
  'YY WebSocket 帧长度异常：': 'YY WebSocket frame length mismatch: ',
  'YY 弹幕协议握手数据异常：': 'YY danmaku handshake payload is malformed: ',
  'YY 弹幕消息格式异常：': 'YY danmaku message shape is unexpected: ',
  'YY 弹幕消息解析异常：': 'YY danmaku message failed to parse: ',
  'YY 匿名登录返回了未知协议：': 'YY anonymous login returned an unknown protocol: ',
  'YY 匿名登录失败：': 'YY anonymous login failed: ',
  'YY AP 登录失败：': 'YY AP login failed: ',
  'YY 加入频道路由失败：': 'YY channel routing failed: ',
  'YY 加入频道失败：': 'YY failed to join the channel: ',
  'YY 聊天消息格式异常：': 'YY chat message shape is unexpected: ',
  'YY 聊天正文长度越界': 'YY chat body length is out of range',
  '，': ', ',
};

String _translate(String legacy) =>
    _texts.entries.fold(legacy, (text, entry) => text.replaceAll(entry.key, entry.value));

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

/// One batch in the generator's form.
Map<String, Object?> _result(YyDanmakuBatch batch, YyDanmakuSession session) => {
  'outbound': [for (final packet in batch.outbound) base64Encode(packet)],
  'ready': batch.becameReady,
  'messages': [for (final message in batch.messages) _project(message)],
  'failure': batch.failure,
  'warnings': batch.warnings,
  'phase': session.phase.name,
  'heartbeat': switch (session.heartbeat()) {
    final packet? => base64Encode(packet),
    null => null,
  },
};

/// 3.x's batch with its texts in the new wording.
Map<String, Object?> _legacy(Map<String, Object?> result) => {
  ...result,
  'failure': switch (result['failure']) {
    final String failure => _translate(failure),
    _ => null,
  },
  'warnings': [for (final warning in result['warnings']! as List<Object?>) _translate(warning! as String)],
};

/// [result] with its messages' texts replaced (the XML bodies, REG-YY-009).
Map<String, Object?> _withTexts(Map<String, Object?> result, List<String> texts) {
  final messages = result['messages']! as List<Object?>;
  return {
    ...result,
    'messages': [
      for (var index = 0; index < texts.length; index++)
        {...messages[index]! as Map<String, Object?>, 'message': texts[index]},
    ],
  };
}

int _uri(Object packet) => ByteData.sublistView(Uint8List.fromList(packet as List<int>)).getUint32(4, Endian.little);

/// A join answer (`512011` carrying `2048514`) for [topSid] with [status].
Uint8List _joinAnswer(int topSid, {int? subSid, int status = 4}) {
  final payload = YyPacketWriter()
    ..writeUint32(topSid)
    ..writeUint32(5)
    ..writeUint32(subSid ?? topSid)
    ..writeUint32(topSid)
    ..writeUint32(123)
    ..writeUint8(status)
    ..writeUtf8String('');
  return (YyPacketWriter(uri: 512011)
        ..writeString('')
        ..writeUint32(2048514)
        ..writeUint16(200)
        ..writeByteArray32(payload.takeBytes())
        ..writeByteArray32(const [4, 0, 0, 0xff]))
      .takeBytes();
}

/// A chat line (`533080` carrying app 31's `3104600`) of [topSid].
Uint8List _chat(int topSid, String text, {String name = '观众'}) {
  final block = YyPacketWriter()
    ..writeUint32(0)
    ..writeUcs2String32('')
    ..writeUint32(0)
    ..writeUint32(16)
    ..writeUcs2String32(text)
    ..writeUint32(0);
  final chat = YyPacketWriter(uri: 3104600)
    ..writeUint32(5)
    ..writeUint32(topSid)
    ..writeUint32(topSid)
    ..writeByteArray(block.takeBytes())
    ..writeString('')
    ..writeString('')
    ..writeUtf8String(name)
    ..writeUint32(0);
  return (YyPacketWriter(uri: 533080)
        ..writeUint64(1)
        ..writeUint64(topSid)
        ..writeUint32(31)
        ..writeByteArray32(chat.takeBytes()))
      .takeBytes();
}

/// A fake server socket: records what the client sends and answers each
/// packet with what [answer] returns.
final class _FakeChannel implements SocketChannel {
  new({this.answer, this.closeCode, this.closeReason});

  final List<Uint8List> Function(Object packet)? answer;
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
    answer?.call(data).forEach(incoming.add);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  final int? closeCode;

  @override
  final String? closeReason;
}

/// Hands out fake channels and records every handshake.
final class _Connector {
  new({this.fail = false, _FakeChannel Function()? make}) : make = make ?? _FakeChannel.new;

  final bool fail;
  final _FakeChannel Function() make;
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
    final channel = make();
    channels.add(channel);
    return channel;
  }
}

/// The recorded server: answers the anonymous login, the AP login and the
/// join; [join] replaces the join answer (null: none).
_FakeChannel Function() _server({Uint8List? Function()? join}) =>
    () => _FakeChannel(
      answer: (packet) => switch (_uri(packet)) {
        778244 => [_loginAnswer],
        775684 => [_apAnswer],
        513035 => [if (join == null) _joinedAnswer else ?join()],
        _ => const [],
      },
    );

/// The channel a router packet (`513035`) asks to join.
({int topSid, int subSid}) _requestedChannel(Object packet) {
  final reader = YyPacketReader(Uint8List.fromList(packet as List<int>), hasHeader: true)
    ..readString()
    ..readUint32()
    ..readUint16();
  final join = YyPacketReader(reader.readByteArray32())..readUint32();
  return (topSid: join.readUint32(), subSid: join.readUint32());
}

/// A server that joins whichever channel is asked for.
_FakeChannel _echoServer() => _FakeChannel(
  answer: (packet) => switch (_uri(packet)) {
    778244 => [_loginAnswer],
    775684 => [_apAnswer],
    513035 => [
      switch (_requestedChannel(packet)) {
        (:final topSid, :final subSid) => _joinAnswer(topSid, subSid: subSid),
      },
    ],
    _ => const [],
  },
);

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

/// Runs [body] with every timer of a second or more recorded into [delays];
/// those of the [fast] durations fire at once.
Future<void> _timers(Set<Duration> fast, List<Duration> delays, Future<void> Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration >= const Duration(seconds: 1)) delays.add(duration);
      return parent.createTimer(zone, fast.contains(duration) ? Duration.zero : duration, callback);
    },
  ),
);

/// The backoff waits of one endpoint (1 s × (rounds + 1), at most 6 s).
final Set<Duration> _backoff = {for (var seconds = 2; seconds <= 6; seconds++) Duration(seconds: seconds)};

/// The sections of a router packet (`513035`): its fields, the join
/// payload, and the header sections with the trace id (extension 103) cut
/// out, which is the only part that differs between clients.
({List<Object> fields, String trace}) _router(List<int> packet) {
  final reader = YyPacketReader(Uint8List.fromList(packet), hasHeader: true);
  final fields = <Object>[
    reader.uri,
    reader.readString(),
    reader.readUint32(),
    reader.readUint16(),
    base64Encode(reader.readByteArray32()),
  ];
  final headers = YyPacketReader(reader.readByteArray32());
  var trace = '';
  while (headers.bytesAvailable > 0) {
    final tag = headers.readUint32();
    if (tag >> 24 != 7) {
      final length = tag & 0xffffff;
      // Section 8's length leaves out its colour word, as in the web client.
      fields.add([tag, base64Encode(headers.readBytes(min(length - 4, headers.bytesAvailable)))]);
      continue;
    }
    final count = headers.readUint32();
    for (var index = 0; index < count; index++) {
      final key = headers.readUint32();
      final value = headers.readByteArray();
      if (key == 103) {
        trace = String.fromCharCodes(value);
      } else {
        fields.add([key, base64Encode(value)]);
      }
    }
  }
  expect(reader.bytesAvailable, 0);
  return (fields: fields, trace: trace);
}

void main() {
  group('protocol', () {
    test("3.x's endpoint, headers and timing", () {
      const uuid = '00000000-0000-4000-8000-000000000001';
      final endpoint = YyDanmakuProtocol.endpoint(uuid);
      expect(endpoint.toString(), 'wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=$uuid');
      expect(endpoint.queryParameters, {'appid': 'yymwebh5', 'version': '3.2.10', 'uuid': uuid});
      expect(YyDanmakuProtocol.headers.keys, ['User-Agent', 'Origin']);
      expect(YyDanmakuProtocol.headers['User-Agent'], contains('Chrome/151.0.0.0'));
      expect(YyDanmakuProtocol.headers['Origin'], 'https://www.yy.com');
      expect(YyDanmakuProtocol.heartbeatInterval, const Duration(seconds: 5));
      expect(YyDanmakuProtocol.inactivityTimeout, const Duration(seconds: 45));
      expect(YyDanmakuProtocol.handshakeTimeout, const Duration(seconds: 15));
    });

    test('random version 4 UUIDs', () {
      final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final uuids = {for (var i = 0; i < 50; i++) YyDanmakuProtocol.uuid(Random.secure())};
      expect(uuids, hasLength(50));
      expect(uuids.every(pattern.hasMatch), isTrue);
      expect(YyDanmakuProtocol.uuid(Random(7)), YyDanmakuProtocol.uuid(Random(7)));
    });

    test("packets carry 3.x's 10-byte little-endian header; reads past the end throw", () {
      final bytes = (YyPacketWriter(uri: 778244)..writeUint32(7)).takeBytes();
      expect(bytes, [14, 0, 0, 0, 0x04, 0xe0, 0x0b, 0, 200, 0, 7, 0, 0, 0]);
      final reader = YyPacketReader(bytes, hasHeader: true);
      expect([reader.packetLength, reader.uri, reader.responseCode], [14, 778244, 200]);
      expect(reader.readUint32(), 7);
      expect(reader.bytesAvailable, 0);
      expect(reader.readUint8, throwsFormatException);
      expect(reader.offset, 14, reason: 'a failed read does not move');
      expect(() => YyPacketReader(Uint8List.sublistView(bytes, 0, 12), hasHeader: true), throwsFormatException);
      expect(() => YyPacketReader(Uint8List(8), hasHeader: true), throwsFormatException);
      final strings =
          (YyPacketWriter()
                ..writeString('B8')
                ..writeUtf8String('弹幕')
                ..writeUcs2String32('弹幕😀')
                ..writeUint64(0x18A809CF3))
              .takeBytes();
      final read = YyPacketReader(strings);
      expect(
        [read.readString(), read.readUtf8String(), read.readUcs2String32(), read.readUint64()],
        ['B8', '弹幕', '弹幕😀', 0x18A809CF3],
      );
    });

    test("client packets are byte for byte 3.x's", () {
      final session = YyDanmakuSession(topSid: _topSid, subSid: _args.subSid, uuid: _recordedUuid);
      expect(base64Encode(session.beginHandshake()), _recorded['handshake']);
      expect(session.heartbeat(), isNull, reason: 'no ping before the AP login');
      final sent = [
        for (final frame in _recorded['frames']! as List<Object?>)
          ...((frame! as Map<String, Object?>)['outbound']! as List<Object?>),
      ];
      final ours = [
        for (final frame in _frames)
          if (frame.dir == 'in')
            for (final packet in session.consume(frame.bytes).outbound) base64Encode(packet),
      ];
      expect(ours, sent);
      expect(ours.map((packet) => _uri(base64Decode(packet))), [775684, 513035, 538456, 537944, 537944]);
      expect(base64Encode(session.heartbeat()!), _recorded['heartbeat']);
    });

    test("they are the recording's too, apart from the router's trace id", () {
      final session = YyDanmakuSession(topSid: _topSid, subSid: _args.subSid, uuid: _recordedUuid);
      final ours = [session.beginHandshake()];
      for (final frame in _frames) {
        if (frame.dir == 'in') ours.addAll(session.consume(frame.bytes).outbound);
      }
      final recorded = [
        for (final frame in _frames)
          if (frame.dir == 'out' && _uri(frame.bytes) != 794116) frame.bytes,
      ];
      expect(ours, hasLength(recorded.length));
      for (var index = 0; index < ours.length; index++) {
        if (_uri(ours[index]) != 513035) {
          expect(ours[index], recorded[index], reason: 'packet $index');
          continue;
        }
        final (ourRouter, recordedRouter) = (_router(ours[index]), _router(recorded[index]));
        expect(ourRouter.fields, recordedRouter.fields);
        expect(ourRouter.trace, matches(RegExp(r'^F6618651891_yymwebh5_\d{1,5}_0$')));
        expect(recordedRouter.trace, 'F6618651891_yymwebh5_0');
      }
      final pings = [
        for (final frame in _frames)
          if (frame.dir == 'out' && _uri(frame.bytes) == 794116) frame.bytes,
      ];
      expect(pings, hasLength(25));
      expect(pings, everyElement(session.heartbeat()));
    });

    test("the recording's AP login answer carries a documentation address, not the recorder's", () {
      // The answer echoes the client's public address and port after its
      // context (3.x's tests wrote 127.0.0.1:1234 there); the archive kept it.
      final reader = YyPacketReader(_apAnswer, hasHeader: true)
        ..readUint32()
        ..readUint32();
      expect(reader.readString(), '259:0');
      expect(reader.readBytes(4).join('.'), '203.0.113.7');
    });

    test('chat text: XML bodies give their txt data, other text is kept', () {
      expect(YyDanmakuProtocol.chatText('  晚上好 '), '晚上好');
      expect(YyDanmakuProtocol.chatText('/{mg 好听'), '/{mg 好听');
      expect(YyDanmakuProtocol.chatText('我 <3 你 <txt data="x"/>'), '我 <3 你 <txt data="x"/>');
      expect(
        YyDanmakuProtocol.chatText('<?xml version="1.0"?><msg><txt data="$_recordedChat" /></msg>'),
        _recordedChat,
      );
      expect(YyDanmakuProtocol.chatText(' <msg><txt data=" 两边 "/></msg> '), '两边');
      expect(YyDanmakuProtocol.chatText("<msg><txt data='前'/><face id=\"1\"/><txt  data=\"后\"/></msg>"), '前后');
      expect(YyDanmakuProtocol.chatText('<msg><txt size="3" data="属性在后"/></msg>'), '属性在后');
      expect(YyDanmakuProtocol.chatText('<msg><face id="1"/></msg>'), '');
      expect(
        YyDanmakuProtocol.chatText(
          '<msg><txt data="&amp;&lt;&gt;&quot;&apos;&#x4F60;&#X597D;&#22909;&#x1F600;"/></msg>',
        ),
        '&<>"\'你好好😀',
      );
      expect(
        YyDanmakuProtocol.chatText('<msg><txt data="&#xD800;&#x110000;&#99999999999999999999;&nbsp;&amp"/></msg>'),
        '&#xD800;&#x110000;&#99999999999999999999;&nbsp;&amp',
        reason: 'references to no character, unknown entities and unterminated ones stay',
      );
    });

    test("the failure detail is 3.x's: one line, at most 120 characters", () {
      expect(YyDanmakuProtocol.compactFailure(''), '');
      expect(YyDanmakuProtocol.compactFailure('  WebSocket closed\n  (code=1006)\t '), 'WebSocket closed (code=1006)');
      final long = 'x' * 121;
      expect(YyDanmakuProtocol.compactFailure(long), '${'x' * 117}...');
      expect(YyDanmakuProtocol.compactFailure('y' * 120), 'y' * 120);
    });
  });

  group('recorded frames (S08-live) against 3.x', () {
    test("every incoming frame's batch is 3.x's, the XML chat unwrapped", () {
      final expected = {
        for (final frame in _recorded['frames']! as List<Object?>)
          (frame! as Map<String, Object?>)['frame']! as int: Map.of(frame as Map<String, Object?>)..remove('frame'),
      };
      expect(expected.keys, [1, 3, 6, 189, 488]);
      final session = YyDanmakuSession(topSid: _topSid, subSid: _args.subSid, uuid: _recordedUuid)..beginHandshake();
      var incoming = 0;
      for (var index = 0; index < _frames.length; index++) {
        if (_frames[index].dir != 'in') continue;
        incoming++;
        final result = _result(session.consume(_frames[index].bytes), session);
        final legacy = expected[index];
        if (legacy == null) {
          expect(result['outbound'], isEmpty, reason: 'frame $index');
          expect(result['messages'], isEmpty, reason: 'frame $index');
          expect(result['ready'], isFalse, reason: 'frame $index');
          expect(result['warnings'], isEmpty, reason: 'frame $index');
          continue;
        }
        if (index == 189 || index == 488) {
          // REG-YY-009: 3.x showed the XML wrapper as the chat.
          final message = ((legacy['messages']! as List).single as Map)['message'] as String;
          expect(message, startsWith('<?xml version="1.0"?><msg><txt data="'));
          expect(result, _withTexts(_legacy(legacy), [_recordedChat]), reason: 'frame $index');
        } else {
          expect(result, _legacy(legacy), reason: 'frame $index');
        }
      }
      expect(incoming, _recorded['incomingFrames']);
      expect(session.phase.name, _recorded['phase']);
    });

    test("the recorded chat is 3.x's but for the text: white, named, no id or time", () {
      final session = YyDanmakuSession(topSid: _topSid, subSid: _args.subSid, uuid: _recordedUuid)..beginHandshake();
      [_loginAnswer, _apAnswer, _joinedAnswer].forEach(session.consume);
      final chat = session.consume(_chatFrames.first).messages.single;
      expect(_project(chat), {
        'type': 'chat',
        'userName': '观众1',
        'userId': '',
        'message': _recordedChat,
        'color': '#ffffff',
        'messageId': '',
        'sentAt': null,
        'userLevel': '',
        'fansLevel': '',
        'fansName': '',
        'isLocal': false,
        'data': null,
      });
    });

    test("another channel's session reads no chat and fails the join", () {
      final session = YyDanmakuSession(topSid: 1, subSid: 1, uuid: _recordedUuid)..beginHandshake();
      final batches = [
        for (final frame in _frames)
          if (frame.dir == 'in') session.consume(frame.bytes),
      ];
      expect(batches.expand((batch) => batch.messages), isEmpty);
      expect(batches.map((batch) => batch.failure).nonNulls, ['YY failed to join the channel: 4']);
    });
  });

  group('synthetic frames (S09-synthetic) against 3.x', () {
    final doc = _json('S09-synthetic/cases.json')! as Map<String, Object?>;
    final cases = doc['cases']! as List<Object?>;
    final expected = {
      for (final result in (_json('S09-synthetic/expected.json')! as Map<String, Object?>)['value']! as List<Object?>)
        if (result case {
          'name': final String name,
          'frames': final List<Object?> frames,
          'results': final List<Object?> results,
        })
          name: (
            frames: [for (final frame in frames) base64Decode(frame! as String)],
            results: [for (final result in results) result! as Map<String, Object?>],
          ),
    };

    /// REG-YY-009: the texts of the chat in the last frame of the XML cases
    /// (3.x showed the wrapper).
    const xmlTexts = {
      'XML body with one txt': ['发起了欢乐投票，快来支持吧！'],
      'XML body with entities and an emoticon code': ['a & b <3 "引号" 你好😀 /{tx'],
      'XML body with two txt elements around another element': ['前半后半'],
      'XML body without txt': <String>[],
    };

    test('every case has 3.x output', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
      expect(xmlTexts.keys.every(expected.containsKey), isTrue);
    });

    for (final item in cases) {
      final name = (item! as Map<String, Object?>)['name']! as String;
      test(name, () {
        final (:frames, :results) = expected[name]!;
        final session = YyDanmakuSession(
          topSid: doc['topSid']! as int,
          subSid: doc['subSid']! as int,
          uuid: doc['uuid']! as String,
        )..beginHandshake();
        for (var index = 0; index < frames.length; index++) {
          final result = _result(session.consume(frames[index]), session);
          var legacy = _legacy(results[index]);
          final texts = xmlTexts[name];
          if (texts != null && index == frames.length - 1) {
            expect(
              ((legacy['messages']! as List).single as Map)['message'],
              anyOf(contains('<txt'), contains('<face')),
            );
            legacy = _withTexts(legacy, texts);
          }
          expect(result, legacy, reason: 'frame $index');
        }
      });
    }
  });

  group('connection', () {
    test('opens its endpoint with the exact headers and starts the handshake, not joined yet', () async {
      final connector = _Connector();
      final connection = YyDanmakuConnection(connector: connector.call, random: Random(1));
      final events = _record(connection);
      await connection.connect(_args);
      expect(connection.uuid, YyDanmakuProtocol.uuid(Random(1)));
      expect(connector.endpoints, [YyDanmakuProtocol.endpoint(connection.uuid)]);
      expect(connector.headers.single, YyDanmakuProtocol.headers);
      expect(connector.protocols.single, isNull);
      expect(connector.routes.single, const DirectRoute(), reason: '3.x always went direct');
      expect(connector.channels.single.sent.map(_uri), [778244]);
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.connecting);
      await connection.close();
    });

    test("3.x's timing: 5 s heartbeat, 45 s silence limit, 15 s handshake, 8 reconnects", () {
      final connection = YyDanmakuConnection();
      expect(connection.site, SiteIds.yy);
      expect(connection.heartbeatInterval, const Duration(seconds: 5));
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 5));
      expect(policy.inactivityTimeout, const Duration(seconds: 45));
      expect(policy.joinTimeout, const Duration(seconds: 15));
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      expect(YyDanmakuConnection().uuid, isNot(connection.uuid));
    });

    test('the recorded handshake joins; chat follows, unwrapped', () async {
      final connector = _Connector(make: _server());
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connection.isConnected);
      final channel = connector.channels.single;
      expect(channel.sent.map(_uri), [778244, 775684, 513035, 538456, 537944, 537944]);
      expect(events, [const DanmakuReady()]);
      _chatFrames.forEach(channel.incoming.add);
      await _until(() => _messages(events).length == 2);
      expect(_messages(events).map((message) => message.message), [_recordedChat, _recordedChat]);
      expect(_messages(events).map((message) => message.userName), ['观众1', '观众1']);
      channel.incoming
        ..add('text frame')
        ..add(_chat(1, 'another channel'))
        ..add(_chat(_topSid, 'this channel'));
      await _until(() => _messages(events).length == 3);
      expect(_messages(events).last.message, 'this channel');
      await connection.close();
    });

    test('heartbeat: the AP ping every 5 s, none before the AP login', () async {
      final periods = <Duration>[];
      final connector = _Connector(make: _server(join: () => null));
      await runZoned(
        () async {
          final connection = YyDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args);
          final sent = connector.channels.single.sent;
          await _until(() => sent.where((packet) => _uri(packet) == 794116).length >= 2);
          final uris = sent.map(_uri).toList();
          expect(uris.where((uri) => uri != 794116), [778244, 775684, 513035, 538456]);
          expect(uris.indexOf(794116), greaterThan(uris.indexOf(775684)), reason: 'no ping before the AP login');
          final ping = sent.firstWhere((packet) => _uri(packet) == 794116);
          expect(ping, (YyPacketWriter(uri: 794116)..writeUint32(0)).takeBytes());
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
      expect(periods, [const Duration(seconds: 5)]);
    });

    test('a refused join: the refusal, a reconnect and a new anonymous login', () async {
      var attempts = 0;
      final connector = _Connector(
        make: _server(join: () => ++attempts == 1 ? _joinAnswer(_topSid, status: 10) : _joinedAnswer),
      );
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      final delays = <Duration>[];
      await _timers(_backoff, delays, () async {
        await connection.connect(_args);
        await _until(() => connection.isConnected);
      });
      expect(delays.firstWhere((delay) => delay != YyDanmakuProtocol.handshakeTimeout), const Duration(seconds: 2));
      expect(connector.channels, hasLength(2));
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent.map(_uri), [778244, 775684, 513035, 538456, 537944, 537944]);
      expect(connector.endpoints.toSet(), hasLength(1), reason: 'the same UUID for every reconnect');
      expect(events, [
        const DanmakuReconnecting(DanmakuInterruption.protocolError, detail: 'YY failed to join the channel: 10'),
        const DanmakuReconnecting(DanmakuInterruption.disconnected, detail: 'Reconnect requested'),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('refusals in a row end the connection after 8 reconnects (3.x retried forever)', () async {
      final connector = _Connector(make: _server(join: () => _joinAnswer(_topSid, status: 10)));
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _timers(_backoff, [], () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(connector.channels, hasLength(9));
      expect(connector.channels.every((channel) => channel.closed), isTrue);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(16));
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'YY failed to join the channel: 10'),
      );
      expect(connection.status, DanmakuStatus.closed);
      await _wait(const Duration(milliseconds: 20));
      expect(connector.channels, hasLength(9), reason: 'no reconnect after the end');
    });

    test('a join resets the count of refusals', () async {
      final answers = [for (var i = 0; i < 8; i++) 10, 4, for (var i = 0; i < 8; i++) 10, 4];
      var attempt = 0;
      final connector = _Connector(
        make: _server(join: () => _joinAnswer(_topSid, status: answers[attempt++])),
      );
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _timers(_backoff, [], () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuReady>().length == 1);
        await connector.channels.last.incoming.close();
        await _until(() => events.whereType<DanmakuReady>().length == 2);
      });
      expect(connector.channels, hasLength(18));
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      await connection.close();
    });

    test('no join within 15 s: a handshake timeout notice, a reconnect, and an end after 8 of them', () async {
      final delays = <Duration>[];
      final connector = _Connector(make: _server(join: () => null));
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _timers({..._backoff, const Duration(seconds: 15)}, delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays.where((delay) => delay == const Duration(seconds: 15)), hasLength(9));
      expect(connector.channels, hasLength(9));
      expect(events.take(2), [
        const DanmakuReconnecting(DanmakuInterruption.handshakeTimeout),
        const DanmakuReconnecting(DanmakuInterruption.disconnected, detail: 'Reconnect requested'),
      ]);
      expect(events.whereType<DanmakuReconnecting>(), hasLength(16));
      expect(
        events.last,
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'YY danmaku handshake timed out'),
      );
    });

    test('a joined socket that drops reconnects with the failure as detail and joins again', () async {
      final delays = <Duration>[];
      final connector = _Connector(
        make: () {
          final server = _server()();
          return _FakeChannel(answer: server.answer, closeCode: 1006, closeReason: ' going\n  away ');
        },
      );
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _timers(_backoff, delays, () async {
        await connection.connect(_args);
        await _until(() => connection.isConnected);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(
        delays.firstWhere((delay) => delay != YyDanmakuProtocol.handshakeTimeout),
        const Duration(seconds: 2),
        reason: 'one endpoint: 1 s × (1 round + 1)',
      );
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected, detail: 'WebSocket closed (code=1006): going away'),
        const DanmakuReady(),
      ]);
      expect(connector.channels.last.sent.map(_uri).take(3), [778244, 775684, 513035]);
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(fail: true);
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _timers(_backoff, delays, () async {
        await connection.connect(_args);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(delays, [
        for (final seconds in [2, 3, 4, 5, 6, 6, 6, 6]) Duration(seconds: seconds),
      ]);
      expect(connector.endpoints, hasLength(9));
      expect(events, [
        const DanmakuReconnecting(DanmakuInterruption.disconnected, detail: 'SocketException: refused'),
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'SocketException: refused'),
      ]);
    });

    test('close: no event, heartbeat or reconnect afterwards; closing twice is harmless', () async {
      final connector = _Connector(make: _server());
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args);
      await _until(() => connection.isConnected);
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming.add(_chatFrames.first);
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, hasLength(6));
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('another room: the first socket closes, the same UUID joins the new channel', () async {
      final connector = _Connector(make: _echoServer);
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => connection.isConnected);
      await connection.connect(const YyDanmakuArgs(topSid: 22490906, subSid: 22490906));
      await _until(() => connection.isConnected);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.endpoints.toSet(), hasLength(1));
      final joins = [
        for (final channel in connector.channels)
          for (final packet in channel.sent)
            if (_uri(packet) == 513035) _requestedChannel(packet),
      ];
      expect(joins, [(topSid: _topSid, subSid: _topSid), (topSid: 22490906, subSid: 22490906)]);
      connector.channels.first.incoming.add(_chat(_topSid, 'first room'));
      connector.channels.last.incoming
        ..add(_chat(_topSid, 'first room on the new socket'))
        ..add(_chat(22490906, 'second room'));
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).map((message) => message.message), ['second room']);
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      await connection.close();
    });

    test('a room that is not broadcasting joins the same way (M4.U 6-7)', () async {
      final html = File('../../fixtures/yy/S05-page-offline/body.html').readAsStringSync();
      final room = YyApi.offlineRoom(requestedId: '85520900', page: YyApi.roomPage(html));
      expect(room.liveStatus, LiveStatus.offline);
      final args = room.danmakuData! as YyDanmakuArgs;
      final connector = _Connector(make: _echoServer);
      final connection = YyDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(args);
      await _until(() => connection.isConnected);
      connector.channels.single.incoming.add(_chat(args.topSid, '主播不在也能聊'));
      await _until(() => _messages(events).isNotEmpty);
      expect(args, const YyDanmakuArgs(topSid: 85520900, subSid: 85520900));
      expect(connector.channels.single.sent.where((packet) => _uri(packet) == 513035).map(_requestedChannel), [
        (topSid: 85520900, subSid: 85520900),
      ]);
      expect(events, [const DanmakuReady(), isA<DanmakuReceived>()]);
      expect(_messages(events).single.message, '主播不在也能聊');
      await connection.close();
    });

    test('takes YyDanmakuArgs only', () async {
      final connection = YyDanmakuConnection(connector: _Connector().call);
      await expectLater(connection.connect('$_topSid'), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under yy', () {
      final registry = DanmakuRegistry({SiteIds.yy: YyDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.yy]);
      expect(registry.connectionFor(' YY '), isA<YyDanmakuConnection>());
      expect(registry.connectionFor('huya'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server through the exact handshake: the recorded session end to end', () async {
      final received = <int>[];
      final requests = <HttpHeaders>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.headers);
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          final uri = _uri(frame as List<int>);
          received.add(uri);
          switch (uri) {
            case 778244:
              socket.add(_loginAnswer);
            case 775684:
              socket.add(_apAnswer);
            case 513035:
              socket.add(_joinedAnswer);
            case 537944 when received.where((uri) => uri == 537944).length == 2:
              _chatFrames.forEach(socket.add);
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = YyDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          requested.add(endpoint);
          return connectExactWebSocket(
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
      expect(requested, [YyDanmakuProtocol.endpoint(connection.uuid)]);
      expect(requests.single.value('user-agent'), YyDanmakuProtocol.headers['User-Agent']);
      expect(requests.single.value('origin'), 'https://www.yy.com');
      expect(received, [778244, 775684, 513035, 538456, 537944, 537944]);
      expect(events.first, const DanmakuReady());
      expect(_messages(events).map((message) => message.message), [_recordedChat, _recordedChat]);
      connection.heartbeat();
      await _until(() => received.length == 7);
      expect(received.last, 794116);
      await connection.close();
    });
  });
}
