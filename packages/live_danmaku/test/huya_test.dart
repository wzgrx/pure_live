import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/huya/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded session (S11-live): WebSocket frames in order, with their
/// direction and index in frames.jsonl. The recorder also kept one HTTP
/// response of the message board (it has a url); it is not a frame.
final List<({int index, String dir, Uint8List bytes})> _frames = [
  for (final (index, line) in File('$_root/S11-live/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 'b64': final String b64} && final Map<String, Object?> frame
        when !frame.containsKey('url'))
      (index: index, dir: dir, bytes: base64Decode(b64)),
];

Iterable<Uint8List> get _incoming => [
  for (final frame in _frames)
    if (frame.dir == 'in') frame.bytes,
];

/// 3.x's output for S11-live (fixtures/huya/danmaku/legacy_expected.dart).
final Map<String, Object?> _recorded =
    (_json('S11-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

final int _uid = _recorded['uid']! as int;

/// 3.x's messages for S11-live, with the frame each came from.
List<Map<String, Object?>> get _legacyMessages => [
  for (final message in _recorded['messages']! as List<Object?>) Map.of(message! as Map<String, Object?>),
];

/// The `lMsgId` (tag 5) of a single push (command 7); null for other frames.
int? _pushId(List<int> frame) {
  final outer = TarsStruct.decode(frame);
  if (outer.integer(0) != HuyaDanmakuProtocol.pushCommand) return null;
  return TarsStruct.decode(outer.bytes(1) ?? const []).integer(5);
}

final Map<int, Uint8List> _frameAt = {for (final frame in _frames) frame.index: frame.bytes};

/// M5.F B-4: 3.x's messages with the upgrade applied, a single push's
/// message carrying its `lMsgId` as `huya:{id}` (3.x left it without one).
List<Map<String, Object?>> get _recordedMessages => [
  for (final message in _legacyMessages)
    if (_pushId(_frameAt[message['frame']]!) case final id? when id > 0)
      {...message, 'messageId': 'huya:$id'}
    else
      message,
];

List<Map<String, Object?>> get _recordedWithoutFrames => [
  for (final message in _recordedMessages) message..remove('frame'),
];

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) {
  final data = message.data;
  return {
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
    'data': data is LiveAudienceUpdate ? {'kind': data.kind.name, 'value': data.value} : data,
  };
}

/// One case of S16-synthetic/cases.json as the server frames it, written
/// with `live_core`'s [TarsWriter] (legacy_expected.dart writes the same
/// frame with 3.x's TarsOutputStream).
Uint8List _serverFrame(Map<String, Object?> spec) {
  if (spec['base64'] case final String raw) return base64Decode(raw);
  final command = spec['command']! as int;
  var payload = Uint8List(0);
  if (command == 7) {
    payload =
        (TarsWriter()
              ..writeInt(0, 5)
              ..writeInt(1, spec['uri']! as int)
              ..writeBytes(2, _body(spec))
              ..writeInt(3, 2))
            .toBytes();
  } else if (command == 22) {
    payload =
        (TarsWriter()
              ..writeString(0, spec['group']! as String)
              ..writeList<Object?>(
                1,
                spec['items']! as List<Object?>,
                (writer, item) => writer.writeStruct(0, (writer) {
                  final entry = item! as Map<String, Object?>;
                  writer
                    ..writeInt(0, entry['uri']! as int)
                    ..writeBytes(1, _body(entry))
                    ..writeInt(2, entry['id'] as int? ?? 0);
                }),
              ))
            .toBytes();
  }
  final frame =
      (TarsWriter()
            ..writeInt(0, command)
            ..writeBytes(1, payload))
          .toBytes();
  return Uint8List.sublistView(frame, 0, frame.length - (spec['cut'] as int? ?? 0));
}

/// The body of one push in cases.json: a chat, a count, raw Base64, or
/// nothing.
Uint8List _body(Map<String, Object?> spec) {
  if (spec['body'] case final String raw) return base64Decode(raw);
  if (spec['count'] case final int count) return (TarsWriter()..writeInt(0, count)).toBytes();
  final chat = spec['chat'] as Map<String, Object?>?;
  if (chat == null) return Uint8List(0);
  final writer = TarsWriter();
  if (chat.containsKey('uid') || chat.containsKey('nick')) {
    writer.writeStruct(
      0,
      (sender) => sender
        ..writeInt(0, chat['uid'] as int? ?? 0)
        ..writeInt(1, 0)
        ..writeString(2, chat['nick'] as String? ?? '')
        ..writeInt(3, 0),
    );
  }
  writer
    ..writeInt(1, chat['tid'] as int? ?? 0)
    ..writeInt(2, chat['tid'] as int? ?? 0);
  if (chat['content'] case final String content) writer.writeString(3, content);
  if (chat['color'] case final int color) {
    writer.writeStruct(
      6,
      (format) => format
        ..writeInt(0, color)
        ..writeInt(1, 4)
        ..writeInt(2, 0)
        ..writeInt(3, 1),
    );
  }
  final body = writer.toBytes();
  return Uint8List.sublistView(body, 0, body.length - (spec['cutBody'] as int? ?? 0));
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
  new({this.fail = false});

  final bool fail;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<Iterable<String>?> protocols = [];
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
    if (fail) throw const SocketException('refused');
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

List<LiveSuperChatMessage> _superChats(List<DanmakuEvent> events) => [
  for (final message in _messages(events))
    if (message.data case final LiveSuperChatMessage data) data,
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

/// Runs [body] with the board's retry waits (and, with [timeouts], its 3 s
/// fetch timeout) recorded into [waits] and cut to a millisecond; other
/// timers run as they are.
Future<void> _fastBoard(List<Duration> waits, Future<void> Function() body, {bool timeouts = false}) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      final retry = HuyaDanmakuProtocol.superChatRetryDelays.contains(duration) && duration > Duration.zero;
      final timeout = timeouts && duration == HuyaDanmakuProtocol.superChatTimeout;
      if (!retry && !timeout) return parent.createTimer(zone, duration, callback);
      waits.add(duration);
      return parent.createTimer(zone, const Duration(milliseconds: 1), callback);
    },
  ),
);

final Uint8List _register = HuyaDanmakuProtocol.register(_uid);
final Uint8List _heartbeat = HuyaDanmakuProtocol.heartbeat();

/// A headline notice in a batch, as the server sends it.
final Uint8List _notice = _serverFrame({
  'command': 22,
  'group': 'live:$_uid',
  'items': [
    {'uri': HuyaDanmakuProtocol.superChatUri, 'id': 1},
  ],
});

/// A chat as a single push.
Uint8List _chat(String text) => _serverFrame({
  'command': 7,
  'uri': HuyaDanmakuProtocol.chatUri,
  'chat': {'uid': 7, 'nick': 'A', 'content': text},
});

HuyaDanmakuArgs _args({Future<List<LiveSuperChatMessage>> Function()? superChats, int uid = 0}) => HuyaDanmakuArgs(
  uid: uid == 0 ? _uid : uid,
  topSid: uid == 0 ? _uid : uid,
  subSid: uid == 0 ? _uid : uid,
  superChats: superChats,
);

/// A board entry (3.x's test helper).
LiveSuperChatMessage _entry(String message, {String messageId = '', Duration startOffset = Duration.zero}) {
  final start = DateTime.utc(2026, 9, 1, 12).add(startOffset);
  return LiveSuperChatMessage(
    messageId: messageId,
    backgroundBottomColor: '#246488',
    backgroundColor: '#ffffff',
    endTime: start.add(const Duration(minutes: 1)),
    face: '',
    message: message,
    price: 100,
    startTime: start,
    userName: 'tester',
  );
}

/// The retry waits after a notice: 0.6, 1.8 and 4 s.
const List<Duration> _retryWaits = [Duration(milliseconds: 600), Duration(milliseconds: 1800), Duration(seconds: 4)];

/// The M5.F recording (S17-reconnect): the chats of two connections to one
/// room, A and B, A closing and opening again as A2; `t` is milliseconds
/// since the recorder started, and open and close markers have no bytes.
final List<({String conn, String dir, int t, Uint8List? bytes})> _s17 = [
  for (final line in File('$_root/S17-reconnect/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line)
        case {'conn': final String conn, 'dir': final String dir, 't': final int t} && final Map<String, Object?> frame)
      (conn: conn, dir: dir, t: t, bytes: frame['b64'] is String ? base64Decode(frame['b64']! as String) : null),
];

/// When the S17 recorder started: "now" for its frames.
final DateTime _s17Start = DateTime.parse(
  (_json('S17-reconnect/meta.json')! as Map<String, Object?>)['capturedAt']! as String,
);

/// S17's chats of connection [conn], decoded, with their time.
List<({int t, LiveMessage message})> _s17Chats(String conn) => [
  for (final frame in _s17)
    if (frame.conn == conn && frame.bytes != null)
      for (final message in HuyaDanmakuProtocol.decode(frame.bytes!).messages) (t: frame.t, message: message),
];

/// The `sMessageId` (tag 20) of the chat in a single push.
String? _chatMessageId(Uint8List frame) {
  final push = TarsStruct.decode(TarsStruct.decode(frame).bytes(1)!);
  return TarsStruct.decode(push.bytes(2)!).string(20);
}

/// A single push (command 7) of [uri] whose tag 5 (`lMsgId`) is [lMsgId]:
/// an int, a string (the wrong type) or null (left out).
Uint8List _single(int uri, Uint8List body, {Object? lMsgId}) {
  final push = TarsWriter()
    ..writeInt(0, 5)
    ..writeInt(1, uri)
    ..writeBytes(2, body)
    ..writeInt(3, 2)
    ..writeString(4, 'chat:$_uid');
  switch (lMsgId) {
    case final int id:
      push.writeInt(5, id);
    case final String id:
      push.writeString(5, id);
  }
  push.writeInt(6, 0);
  return (TarsWriter()
        ..writeInt(0, HuyaDanmakuProtocol.pushCommand)
        ..writeBytes(1, push.toBytes()))
      .toBytes();
}

/// A chat as a single push with an `lMsgId`.
Uint8List _chatWithId(String text, int lMsgId, {int uid = 7, String nick = 'A'}) => _single(
  HuyaDanmakuProtocol.chatUri,
  _body({
    'chat': {'uid': uid, 'nick': nick, 'content': text},
  }),
  lMsgId: lMsgId,
);

/// The incoming frames of a fixture directory's frames.jsonl.
List<Uint8List> _fixtureFrames(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 'b64': final String b64}) base64Decode(b64),
];

/// The streamer uid of each S20-end frame, in order.
final List<int> _s20Uids = [
  for (final line in File('$_root/S20-end/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'conn': final String room})
      if ((_json('S20-end/meta.json')! as Map<String, Object?>)['rooms'] case final Map<String, Object?> rooms)
        if (rooms[room] case {'uid': final String uid}) int.parse(uid),
];

/// A board panel (`GameEventMessageBoardPanel`) with [entries], as a
/// headline notice carries it: tag 0 a header, tag 1 the entries (0 user: 1
/// nick, 2 avatar; 1 content; 2 iCost; 4 iTotalSec; 5 iCountDown; 9
/// lMessageId), tag 2 0.
Uint8List _panel(List<({int id, String nick, String text, int cost, int total, int countdown})> entries) =>
    (TarsWriter()
          ..writeStruct(0, (header) => header.writeInt(2, 0))
          ..writeList(
            1,
            entries,
            (writer, entry) => writer.writeStruct(
              0,
              (fields) => fields
                ..writeStruct(
                  0,
                  (user) => user
                    ..writeString(1, entry.nick)
                    ..writeString(2, ''),
                )
                ..writeString(1, entry.text)
                ..writeInt(2, entry.cost)
                ..writeInt(4, entry.total)
                ..writeInt(5, entry.countdown)
                ..writeInt(9, entry.id),
            ),
          )
          ..writeInt(2, 0))
        .toBytes();

/// [message] without its id: what 3.x reported for a single push.
LiveMessage _withoutId(LiveMessage message) => LiveMessage(
  type: message.type,
  userName: message.userName,
  userId: message.userId,
  message: message.message,
  color: message.color,
);

void main() {
  group('protocol', () {
    test("client frames are byte for byte 3.x's and the recorded ones", () {
      final register = base64Decode(_recorded['registerFrame']! as String);
      final heartbeat = base64Decode(_recorded['heartbeatFrame']! as String);
      expect(_register, register);
      expect(_heartbeat, heartbeat);
      expect(
        [
          for (final frame in _frames)
            if (frame.dir == 'out') frame.bytes,
        ],
        [register, heartbeat],
        reason: 'the recording registered and sent one heartbeat',
      );
      final outer = TarsStruct.decode(_register);
      expect(outer.integer(0), HuyaDanmakuProtocol.registerCommand);
      final payload = TarsStruct.decode(outer.bytes(1)!);
      expect(payload.list(0), ['live:$_uid', 'chat:$_uid']);
      expect(payload.string(1), '');
      expect(HuyaDanmakuProtocol.groups(_uid), ['live:$_uid', 'chat:$_uid']);
      final beat = TarsStruct.decode(_heartbeat);
      expect(beat.integer(0), HuyaDanmakuProtocol.heartbeatCommand);
      expect(beat.bytes(1), isEmpty);
    });

    test('colour: 0 or less is white, the rest as LiveMessageColor.numberToColor', () {
      expect(HuyaDanmakuProtocol.color(-1), LiveMessageColor.white);
      expect(HuyaDanmakuProtocol.color(0), LiveMessageColor.white);
      expect(HuyaDanmakuProtocol.color(-16711936), LiveMessageColor.white);
      expect(HuyaDanmakuProtocol.color(0xFF706E).toString(), '#ff706e');
      expect(HuyaDanmakuProtocol.color(0x0000FF).toString(), '#0000ff');
    });

    test('a board entry becomes the super chat message 3.x reported', () {
      final entry = _entry('hi', messageId: 'huya:1');
      final message = HuyaDanmakuProtocol.superChatMessage(entry);
      expect(message.type, LiveMessageType.superChat);
      expect(message.userName, 'SUPER_CHAT_MESSAGE');
      expect(message.message, 'SUPER_CHAT_MESSAGE');
      expect(message.color, LiveMessageColor.white);
      expect(message.data, same(entry));
    });

    test("board entries keep their event identity (3.x's test)", () {
      final first = _entry('same', messageId: 'huya:101');
      final refreshed = _entry('same', messageId: 'huya:101', startOffset: const Duration(milliseconds: 850));
      final later = _entry('same', messageId: 'huya:102', startOffset: const Duration(minutes: 5));
      expect(first, refreshed);
      expect(first.hashCode, refreshed.hashCode);
      expect(first, isNot(later));
    });
  });

  group('recorded frames (S11-live) against 3.x', () {
    test('every incoming frame decodes to what 3.x decoded', () {
      var notices = 0;
      final decoded = <Map<String, Object?>>[];
      for (final frame in _frames) {
        if (frame.dir != 'in') continue;
        final result = HuyaDanmakuProtocol.decode(frame.bytes);
        notices += result.superChatNotices;
        decoded.addAll([
          for (final message in result.messages) {'frame': frame.index, ..._project(message)},
        ]);
      }
      expect(decoded, hasLength(112));
      expect(decoded, _recordedMessages);
      expect(notices, _recorded['superChatNotices']);
      expect(decoded.where((message) => message['type'] == 'chat'), hasLength(110));
      expect(
        _legacyMessages.where((message) => message['type'] == 'chat').every((message) => message['messageId'] == ''),
        isTrue,
        reason: 'every recorded chat came as a single push (command 7), which had no id in 3.x',
      );
      // B-4: each now carries the push's lMsgId, unique in the recording.
      final ids = [
        for (final message in decoded)
          if (message['type'] == 'chat') message['messageId']! as String,
      ];
      expect(ids.every((id) => RegExp(r'^huya:[1-9][0-9]{18}$').hasMatch(id)), isTrue);
      expect(ids.toSet(), hasLength(110));
      expect(ids.first, 'huya:2048912839150912514');
    });
  });

  group('synthetic frames (S16-synthetic) against 3.x', () {
    final cases = (_json('S16-synthetic/cases.json')! as Map<String, Object?>)['cases']! as List<Object?>;
    final expected = {
      for (final result in (_json('S16-synthetic/expected.json')! as Map<String, Object?>)['value']! as List<Object?>)
        if (result case {
          'name': final String name,
          'frame': final String frame,
          'messages': final List<Object?> messages,
          'superChatNotices': final int notices,
        })
          name: (
            frame: base64Decode(frame),
            messages: [for (final message in messages) message! as Map<String, Object?>],
            notices: notices,
          ),
    };

    Map<String, Object?> chat(
      String text,
      String id, {
      String user = '',
      String userId = '0',
      String color = '#ffffff',
    }) => {
      'type': 'chat',
      'userName': user,
      'userId': userId,
      'message': text,
      'color': color,
      'messageId': id,
      'sentAt': null,
      'userLevel': '',
      'fansLevel': '',
      'fansName': '',
      'isLocal': false,
      'data': null,
    };

    /// The intentional differences (docs/D-弹幕/D01-平台弹幕协议/D01.4-虎牙弹幕/record.md), applied to
    /// 3.x's output of the case they concern.
    final differences = <String, List<Map<String, Object?>> Function(List<Map<String, Object?>>)>{
      // M2: 3.x parsed the colour's hexadecimal text and understood only 4,
      // 6 or 8 digits.
      "colours 3.x's hexadecimal parse turned white": (legacy) {
        expect(legacy.map((message) => message['color']), everyElement('#ffffff'));
        const colours = ['#0000ff', '#0a0a0a', '#ff0000', '#000064'];
        return [
          for (final (index, message) in legacy.indexed) {...message, 'color': colours[index]},
        ];
      },
      // 3.x lost the rest of the batch with the malformed item.
      'a malformed chat body in a batch': (legacy) {
        expect(legacy.map((message) => message['message']), ['第一条']);
        return [
          legacy.single,
          {...legacy.single, 'message': '第三条', 'messageId': 'huya:93'},
        ];
      },
      // 3.x's strict UTF-8 decoding threw and lost the batch; the shared
      // Tars codec (M4.3) replaces bad bytes with U+FFFD.
      'text that is not UTF-8': (legacy) {
        expect(legacy, isEmpty);
        return [chat('�', 'huya:101'), chat('之后', 'huya:102', user: '观众L', userId: '1001012')];
      },
      // M4.3 problem 19: 3.x read Tars int8 as unsigned.
      'sender uid -1 is a signed byte': (legacy) {
        expect(legacy.single['userId'], '255');
        return [
          {...legacy.single, 'userId': '-1'},
        ];
      },
    };

    test('every case has 3.x output, and TarsWriter builds the frame 3.x built', () {
      expect(expected.keys, [for (final testCase in cases) (testCase! as Map<String, Object?>)['name']]);
      expect(differences.keys.every(expected.containsKey), isTrue);
      for (final item in cases) {
        final testCase = item! as Map<String, Object?>;
        expect(
          _serverFrame(testCase['frame']! as Map<String, Object?>),
          expected[testCase['name']]!.frame,
          reason: testCase['name']! as String,
        );
      }
    });

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final name = testCase['name']! as String;
      test(name, () {
        final legacy = expected[name]!;
        final decoded = HuyaDanmakuProtocol.decode(legacy.frame);
        expect(decoded.messages.map(_project).toList(), differences[name]?.call(legacy.messages) ?? legacy.messages);
        expect(decoded.superChatNotices, legacy.notices);
      });
    }
  });

  group('M4.D: gifts (uri 6501)', () {
    test('S18: every recorded gift push is a gift with its name, count, combo, sender and id', () {
      final gifts = [
        for (final line in File('$_root/S18-gift/frames.jsonl').readAsLinesSync())
          ...HuyaDanmakuProtocol.decode(base64Decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String))
              .messages,
      ];
      expect(gifts, hasLength(27));
      expect(gifts.every((message) => message.type == LiveMessageType.gift), isTrue);
      expect(gifts.map((message) => message.messageId).toSet(), hasLength(27));
      expect(gifts.every((message) => RegExp(r'^huya:[1-9][0-9]+$').hasMatch(message.messageId)), isTrue);
      final first = gifts.first;
      expect((first.userName, first.userId, first.message), ('观众1', '9540329646482', '粉丝通行证 ×1'));
      expect(first.data, const HuyaGift(id: '22225', name: '粉丝通行证', count: 1, combo: 1, payTotal: 10));
      // E05.5: the shared gift; `lPayTotal`'s unit is not documented.
      expect(
        (first.gift?.comboTotal, first.gift?.totalValue, first.gift?.unit, first.gift?.tier),
        (1, 10, LiveGiftUnit.other, LiveGiftTier.normal),
      );
      // One viewer's 虎粮 combo: a packet per hit, counting up.
      final combo = [
        for (final message in gifts.skip(1).take(5)) (message.userName, (message.data! as HuyaGift).combo),
      ];
      expect(combo, [for (var hit = 1; hit <= 5; hit++) ('观众2', hit)]);
      expect((gifts[1].data! as HuyaGift).payTotal, 0, reason: '虎粮 is free');
      expect(gifts[1].gift?.totalValue, isNull);
    });

    test('a gift without a name, or a body that is not Tars, gives no message; the frame goes on', () {
      Uint8List push(Uint8List body) {
        final payload =
            (TarsWriter()
                  ..writeInt(1, HuyaDanmakuProtocol.giftUri)
                  ..writeBytes(2, body)
                  ..writeInt(5, 7))
                .toBytes();
        return (TarsWriter()
              ..writeInt(0, HuyaDanmakuProtocol.pushCommand)
              ..writeBytes(1, payload))
            .toBytes();
      }

      final unnamed =
          (TarsWriter()
                ..writeInt(0, 4)
                ..writeInt(2, 0))
              .toBytes();
      expect(HuyaDanmakuProtocol.decode(push(unnamed)).messages, isEmpty);
      expect(HuyaDanmakuProtocol.decode(push(Uint8List.fromList([0]))).messages, isEmpty);
      final named = (TarsWriter()..writeString(20, ' 虎粮 ')).toBytes();
      final gift = HuyaDanmakuProtocol.decode(push(named)).messages.single;
      expect((gift.message, gift.userId, gift.messageId), ('虎粮 ×1', '0', 'huya:7'));
      expect(gift.data, const HuyaGift(id: '', name: '虎粮', count: 1, combo: 1, payTotal: 0));
    });
  });

  group('M4.D2: headline boards (C-9) and the stream end (C-10)', () {
    final now = DateTime.utc(2026, 10, 1, 0, 20);

    test('C-9: a notice carrying a board gives its entries; an empty board nothing; no panel asks a fetch', () {
      // S19: the recorded notice, an empty board.
      final empty = HuyaDanmakuProtocol.decode(_fixtureFrames('S19-headline').single, now: now);
      expect(empty.messages, isEmpty);
      expect(empty.superChatNotices, 0, reason: 'the body is the board: nothing to fetch');
      final board = HuyaDanmakuProtocol.decode(
        _single(
          HuyaDanmakuProtocol.superChatUri,
          _panel([(id: 31, nick: '观众A', text: '加油', cost: 30, total: 60, countdown: 45)]),
          lMsgId: 9,
        ),
        now: now,
      );
      expect(board.superChatNotices, 0);
      final message = board.messages.single;
      expect((message.type, message.userName), (LiveMessageType.superChat, 'SUPER_CHAT_MESSAGE'));
      final entry = message.data! as LiveSuperChatMessage;
      expect((entry.messageId, entry.userName, entry.message, entry.price), ('huya:31', '观众A', '加油', 30));
      expect(entry.endTime, now.add(const Duration(seconds: 45)));
      expect(entry.startTime, now.subtract(const Duration(seconds: 15)));
      // Not a panel: the board is fetched as before.
      for (final body in [
        Uint8List(0),
        Uint8List.fromList([0]),
        (TarsWriter()..writeInt(0, 1)).toBytes(),
      ]) {
        final decoded = HuyaDanmakuProtocol.decode(_single(HuyaDanmakuProtocol.superChatUri, body), now: now);
        expect((decoded.messages.length, decoded.superChatNotices), (0, 1));
      }
    });

    test('C-9: the connection reports a carried entry once and fetches nothing', () async {
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call, now: () => now);
      final events = _record(connection);
      await connection.connect(
        _args(
          superChats: () async {
            fetches++;
            return const [];
          },
        ),
      );
      final notice = _single(
        HuyaDanmakuProtocol.superChatUri,
        _panel([(id: 31, nick: '观众A', text: '加油', cost: 30, total: 60, countdown: 45)]),
      );
      connector.channels.single.incoming
        ..add(notice)
        ..add(notice)
        ..add(_chat('after'));
      await _until(() => _messages(events).length == 2);
      expect(_messages(events).map((message) => message.type), [LiveMessageType.superChat, LiveMessageType.chat]);
      expect(_superChats(events).single.messageId, 'huya:31');
      expect(fetches, 0);
      await connection.close();
    });

    test('C-10: S20, the recorded stream ends, end the run (Broadcast ended); not for another streamer', () async {
      final frames = _fixtureFrames('S20-end');
      expect(_s20Uids, hasLength(3));
      expect([for (final frame in frames) ...HuyaDanmakuProtocol.decode(frame).ended], _s20Uids);
      expect(frames.map((frame) => HuyaDanmakuProtocol.decode(frame).messages), everyElement(isEmpty));
      final frame = frames.first;
      final uid = _s20Uids.first;
      // Another streamer's notice changes nothing.
      final other = _Connector();
      final kept = HuyaDanmakuConnection(connector: other.call);
      final keptEvents = _record(kept);
      await kept.connect(_args());
      other.channels.single.incoming
        ..add(frame)
        ..add(_chat('still here'));
      await _until(() => _messages(keptEvents).isNotEmpty);
      expect(keptEvents.whereType<DanmakuClosed>(), isEmpty);
      await kept.close();
      // This streamer's: the run ends after the frames before it, without a
      // reconnect.
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args(uid: uid));
      connector.channels.single.incoming
        ..add(_chat('last'))
        ..add(frame);
      await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      expect(events.last, const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended'));
      expect(_messages(events).single.message, 'last');
      await _wait(const Duration(milliseconds: 20));
      expect(connector.channels, hasLength(1));
      expect(connector.channels.single.closed, isTrue);
    });
  });

  group('M5.F B-4: message ids of single pushes', () {
    test('S17: a chat has the same id on every connection; none repeats; no replay after the reconnect', () {
      final a = _s17Chats('A');
      final b = _s17Chats('B');
      final a2 = _s17Chats('A2');
      expect((a.length, b.length, a2.length), (124, 189, 61));
      for (final chats in [a, b, a2]) {
        final ids = [for (final chat in chats) chat.message.messageId];
        expect(ids.every((id) => id.startsWith('huya:') && id.length > 'huya:'.length), isTrue);
        expect(ids.toSet(), hasLength(ids.length), reason: 'no id repeats on one connection');
      }
      final onB = {for (final chat in b) chat.message.messageId: chat};
      for (final chat in [...a, ...a2]) {
        final same = onB[chat.message.messageId];
        expect(same, isNotNull, reason: 'B saw every chat A and A2 saw');
        expect(
          (same!.message.userId, same.message.userName, same.message.message),
          (chat.message.userId, chat.message.userName, chat.message.message),
        );
      }
      final reopenedAt = _s17.firstWhere((frame) => frame.conn == 'A2' && frame.dir == 'open').t;
      expect(reopenedAt, 55514);
      expect(
        a2.where((chat) => onB[chat.message.messageId]!.t < reopenedAt),
        isEmpty,
        reason: 'registering again replays nothing',
      );
      // The chat's own sMessageId (tag 20) is just as stable; lMsgId is the
      // one the web client deduplicates by, and batch items carry it too.
      final chatIds = <String, String?>{
        for (final frame in _s17)
          if (frame.conn == 'B' && frame.bytes != null) '${_pushId(frame.bytes!)}': _chatMessageId(frame.bytes!),
      };
      for (final frame in _s17) {
        if (frame.conn == 'B' || frame.bytes == null) continue;
        expect(_chatMessageId(frame.bytes!), chatIds['${_pushId(frame.bytes!)}']);
      }
    });

    test('the gate lets one copy of a chat through, whichever connection brought it', () {
      final gate = DanmakuMessageGate();
      final arrivals = [
        for (final conn in ['A', 'B', 'A2']) ..._s17Chats(conn),
      ]..sort((x, y) => x.t.compareTo(y.t));
      final passed = [
        for (final chat in arrivals)
          if (gate.accepts(chat.message, now: _s17Start.add(Duration(milliseconds: chat.t)))) chat.message.messageId,
      ];
      expect(passed, hasLength(189));
      expect(passed.toSet(), {for (final chat in _s17Chats('B')) chat.message.messageId});
      // B's chats again later (a replay): all dropped within the id window.
      final late = _s17Start.add(const Duration(minutes: 5));
      expect(_s17Chats('B').where((chat) => gate.accepts(chat.message, now: late)), isEmpty);
    });

    test("a viewer repeating a line within 2.5 s is shown every time; 3.x's text rule hid the repeats", () {
      final chats = _s17Chats('B');
      List<int> shown(Iterable<({int t, LiveMessage message})> chats, LiveMessage Function(LiveMessage) form) {
        final gate = DanmakuMessageGate();
        return [
          for (final chat in chats)
            if (gate.accepts(form(chat.message), now: _s17Start.add(Duration(milliseconds: chat.t)))) chat.t,
        ];
      }

      expect(shown(chats, (message) => message), hasLength(189));
      expect(shown(chats, _withoutId).length, lessThan(189));
      // One viewer sent this line three times within 2.5 s (another one sent
      // it later).
      final line = chats.where((chat) => chat.message.message == '不小心购买此产品998').toList();
      expect(line.map((chat) => chat.t), [14256, 15567, 16703, 20976]);
      final repeated = line.where((chat) => chat.message.userId == line.first.message.userId).toList();
      expect(repeated.map((chat) => chat.t), [14256, 15567, 16703]);
      expect(shown(repeated, (message) => message), [14256, 15567, 16703]);
      expect(shown(repeated, _withoutId), [14256], reason: 'without ids: once per 2.5 s from the first one');
    });

    test('tag 5 gives the id; zero, negative, missing or not an integer gives none', () {
      final body = _body({
        'chat': {'uid': 7, 'nick': 'A', 'content': 'x'},
      });
      String id(Object? lMsgId) =>
          HuyaDanmakuProtocol.decode(_single(HuyaDanmakuProtocol.chatUri, body, lMsgId: lMsgId))
              .messages
              .single
              .messageId;
      expect(id(int.parse('2048912839150912514')), 'huya:2048912839150912514');
      expect(id(77), 'huya:77');
      expect(id(0), '');
      expect(id(-1), '');
      expect(id(null), '');
      expect(id('77'), '');
      // A single push of popularity carries it too, as batch items did.
      final popularity = HuyaDanmakuProtocol.decode(
        _single(HuyaDanmakuProtocol.popularityUri, (TarsWriter()..writeInt(0, 5413644)).toBytes(), lMsgId: 78),
      ).messages.single;
      expect(popularity.messageId, 'huya:78');
      expect((popularity.data! as LiveAudienceUpdate).value, 5413644);
      // Batch items keep their tag 2.
      final batch = _serverFrame({
        'command': 22,
        'group': 'live:$_uid',
        'items': [
          {
            'uri': HuyaDanmakuProtocol.chatUri,
            'id': 93,
            'chat': {'uid': 7, 'nick': 'A', 'content': 'x'},
          },
        ],
      });
      expect(HuyaDanmakuProtocol.decode(batch).messages.single.messageId, 'huya:93');
      // A body that is not Tars is still skipped, id or not.
      expect(
        HuyaDanmakuProtocol.decode(_single(HuyaDanmakuProtocol.chatUri, Uint8List.fromList([0x0F]), lMsgId: 79))
            .messages,
        isEmpty,
      );
      expect(
        HuyaDanmakuProtocol.decode(_single(HuyaDanmakuProtocol.superChatUri, Uint8List(0), lMsgId: 80))
            .superChatNotices,
        1,
      );
    });

    test('after a reconnect, a chat delivered again keeps its id, and the gate drops the copy', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args());
        connector.channels.single.incoming
          ..add(_chatWithId('before the drop', 41))
          ..add(_chatWithId('same line', 42));
        await _until(() => _messages(events).length == 2);
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
        connector.channels.last.incoming
          ..add(_chatWithId('same line', 42))
          ..add(_chatWithId('same line', 43));
        await _until(() => _messages(events).length == 4);
      });
      final messages = _messages(events);
      expect(messages.map((message) => message.messageId), ['huya:41', 'huya:42', 'huya:42', 'huya:43']);
      final gate = DanmakuMessageGate();
      final now = DateTime.utc(2026, 9, 30, 15, 8);
      expect(
        [
          for (final message in messages)
            if (gate.accepts(message, now: now)) message.messageId,
        ],
        ['huya:41', 'huya:42', 'huya:43'],
        reason: 'the copy is dropped; the same line under a new id is shown',
      );
      await connection.close();
    });
  });

  group('connection', () {
    test('opens the one endpoint without headers, is ready at once, registers and sends a heartbeat', () async {
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args());
      expect(connector.endpoints, [Uri.parse('wss://wsapi.huya.com')]);
      expect(connector.headers.single, isEmpty);
      expect(connector.protocols.single, isNull);
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      expect(connector.channels.single.sent, [_register, _heartbeat]);
      await connection.close();
    });

    test("3.x's timing: 60 s heartbeat, 180 s silence limit, no join timer, 8 reconnects", () {
      final connection = HuyaDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 60));
      expect(connection.site, SiteIds.huya);
      final policy = connection.policy;
      expect(policy.heartbeatInterval, const Duration(seconds: 60));
      expect(policy.inactivityTimeout, isNull, reason: 'LiveSocket derives max(3 × 60 s, 90 s) = 180 s');
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
    });

    test('sends the heartbeat on its 60 s timer and on demand', () async {
      final periods = <Duration>[];
      final connector = _Connector();
      await runZoned(
        () async {
          final connection = HuyaDanmakuConnection(connector: connector.call)..heartbeat();
          await connection.connect(_args());
          final sent = connector.channels.single.sent;
          await _until(() => sent.length >= 4);
          expect(sent.take(4), [_register, _heartbeat, _heartbeat, _heartbeat]);
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
      expect(periods, [const Duration(seconds: 60)]);
    });

    test('replaying the recording reports what 3.x decoded, in order', () async {
      // B-4: with the single pushes' ids (_recordedMessages).
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args());
      _incoming.forEach(connector.channels.single.incoming.add);
      await _until(() => _messages(events).length == 112);
      expect(_messages(events).map(_project), _recordedWithoutFrames);
      await connection.close();
    });

    test("a headline notice fetches the board in the background; decoding goes on (3.x's test)", () async {
      final waits = <Duration>[];
      final first = Completer<List<LiveSuperChatMessage>>();
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard(waits, () async {
        await connection.connect(
          _args(
            superChats: () {
              fetches++;
              return fetches == 1 ? first.future : Future.value([_entry('delayed')]);
            },
          ),
        );
        final channel = connector.channels.single;
        channel.incoming
          ..add(_notice)
          ..add(_chat('meanwhile'));
        await _until(() => _messages(events).isNotEmpty);
        expect(fetches, 1, reason: 'the first fetch starts at once');
        expect(_messages(events).single.message, 'meanwhile', reason: 'decoding does not wait for the board');
        first.complete(const []);
        await _until(() => fetches == 4);
        await _wait(const Duration(milliseconds: 20));
      });
      expect(waits, _retryWaits);
      expect(_superChats(events).map((entry) => entry.message), ['delayed']);
      final message = _messages(events).last;
      expect(message.userName, 'SUPER_CHAT_MESSAGE');
      expect(message.type, LiveMessageType.superChat);
      await connection.close();
    });

    test('an entry is reported once; with a baseline, a new entry ends the retries', () async {
      final waits = <Duration>[];
      final boards = [
        for (var i = 0; i < 4; i++) [_entry('A', messageId: 'huya:1')],
        [_entry('A', messageId: 'huya:1')],
        [_entry('A', messageId: 'huya:1'), _entry('B', messageId: 'huya:2')],
      ];
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard(waits, () async {
        await connection.connect(_args(superChats: () async => boards[fetches++]));
        connector.channels.single.incoming.add(_notice);
        await _until(() => fetches == 4);
        await _wait(const Duration(milliseconds: 20));
        expect(_superChats(events).map((entry) => entry.message), ['A'], reason: 'no baseline: every attempt runs');
        connector.channels.single.incoming.add(_notice);
        await _until(() => _superChats(events).length == 2);
        await _wait(const Duration(milliseconds: 20));
      });
      expect(fetches, 6, reason: 'the second fetch after the notice brought B');
      expect(waits, [..._retryWaits, _retryWaits.first]);
      expect(_superChats(events).map((entry) => entry.messageId), ['huya:1', 'huya:2']);
      await connection.close();
    });

    test("paid messages with the same text but different ids are both reported (3.x's test)", () async {
      final waits = <Duration>[];
      var fetches = 0;
      final first = _entry('same visible content', messageId: 'huya:101');
      final second = _entry('same visible content', messageId: 'huya:102');
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard(waits, () async {
        await connection.connect(_args(superChats: () async => ++fetches == 1 ? [first] : [first, second]));
        connector.channels.single.incoming.add(_notice);
        await _until(() => _superChats(events).length == 2);
        await _wait(const Duration(milliseconds: 20));
      });
      expect(fetches, 2);
      expect(_superChats(events).map((entry) => entry.messageId), ['huya:101', 'huya:102']);
      await connection.close();
    });

    test('notices during a fetch sequence queue one more sequence, not one each', () async {
      final waits = <Duration>[];
      final first = Completer<List<LiveSuperChatMessage>>();
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      await _fastBoard(waits, () async {
        await connection.connect(
          _args(superChats: () => ++fetches == 1 ? first.future : Future.value(const <LiveSuperChatMessage>[])),
        );
        final twoNotices = _serverFrame({
          'command': 22,
          'group': 'live:$_uid',
          'items': [
            {'uri': HuyaDanmakuProtocol.superChatUri, 'id': 1},
            {'uri': HuyaDanmakuProtocol.superChatUri, 'id': 2},
          ],
        });
        connector.channels.single.incoming
          ..add(twoNotices)
          ..add(_notice);
        await _until(() => fetches == 1);
        await _wait(const Duration(milliseconds: 20));
        expect(fetches, 1);
        first.complete(const []);
        await _until(() => fetches == 8);
        await _wait(const Duration(milliseconds: 30));
      });
      expect(fetches, 8, reason: 'two sequences of four attempts');
      await connection.close();
    });

    test('a failed or slow fetch waits for the next attempt', () async {
      final waits = <Duration>[];
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard(timeouts: true, waits, () async {
        await connection.connect(
          _args(
            superChats: () {
              fetches++;
              if (fetches == 1) return Future.error(const NetworkFailure(SiteIds.huya, 'offline'));
              if (fetches == 2) return Completer<List<LiveSuperChatMessage>>().future;
              return Future.value([_entry('late', messageId: 'huya:9')]);
            },
          ),
        );
        connector.channels.single.incoming.add(_notice);
        await _until(() => fetches == 4);
        await _wait(const Duration(milliseconds: 20));
      });
      // Every fetch starts a 3 s timeout; only the second one (which never
      // answers) runs out, and the sequence goes on.
      expect(waits.where((wait) => wait != HuyaDanmakuProtocol.superChatTimeout), _retryWaits);
      expect(waits.where((wait) => wait == HuyaDanmakuProtocol.superChatTimeout), hasLength(4));
      expect(_superChats(events).map((entry) => entry.message), ['late']);
      expect(connection.isConnected, isTrue, reason: 'board failures never touch the socket');
      await connection.close();
    });

    test('no top channel: a notice fetches nothing', () async {
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args());
      connector.channels.single.incoming
        ..add(_notice)
        ..add(_chat('after'));
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).single.message, 'after');
      await connection.close();
    });

    test("another room's pending board result is dropped and does not hold up the next room (3.x's test)", () async {
      final stale = Completer<List<LiveSuperChatMessage>>();
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard([], () async {
        await connection.connect(
          _args(
            uid: 1,
            superChats: () {
              fetches++;
              return stale.future;
            },
          ),
        );
        connector.channels.first.incoming.add(_notice);
        await _until(() => fetches == 1);
        await connection.connect(
          _args(
            uid: 4,
            superChats: () async {
              fetches++;
              return [_entry('next-room', messageId: 'huya:2')];
            },
          ),
        );
        connector.channels.last.incoming.add(_notice);
        await _until(() => _superChats(events).isNotEmpty);
        stale.complete([_entry('stale-room', messageId: 'huya:1')]);
        await _wait(const Duration(milliseconds: 30));
      });
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [HuyaDanmakuProtocol.register(4), _heartbeat]);
      expect(_superChats(events).map((entry) => entry.message), ['next-room']);
      await connection.close();
    });

    test('close drops a pending board result and stops the retries', () async {
      final pending = Completer<List<LiveSuperChatMessage>>();
      var fetches = 0;
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBoard([], () async {
        await connection.connect(
          _args(
            superChats: () {
              fetches++;
              return pending.future;
            },
          ),
        );
        connector.channels.single.incoming.add(_notice);
        await _until(() => fetches == 1);
        await connection.close();
        pending.complete([_entry('too late', messageId: 'huya:1')]);
        await _wait(const Duration(milliseconds: 30));
      });
      expect(fetches, 1);
      expect(events, [const DanmakuReady()]);
    });

    test('a dropped socket reconnects after 2 s, registers again and is ready again', () async {
      final delays = <Duration>[];
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args());
        await connector.channels.single.incoming.close();
        await _until(() => connector.channels.length == 2 && connection.isConnected);
      });
      expect(delays.first, const Duration(seconds: 2), reason: 'one endpoint: 1 s × (1 round + 1)');
      expect(connector.endpoints, [HuyaDanmakuProtocol.endpoint, HuyaDanmakuProtocol.endpoint]);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.last.sent, [_register, _heartbeat]);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    test('reconnects wait 2, 3, 4, 5, 6, 6, 6, 6 s, then give up', () async {
      final delays = <Duration>[];
      final connector = _Connector(fail: true);
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await _fastBackoff(delays, () async {
        await connection.connect(_args());
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
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.close();
      await connection.connect(_args());
      final channel = connector.channels.single;
      await connection.close();
      await connection.close();
      channel.incoming
        ..add(_incoming.first)
        ..add(_chat('after close'));
      connection.heartbeat();
      await _wait(const Duration(milliseconds: 30));
      expect(channel.closed, isTrue);
      expect(channel.sent, [_register, _heartbeat]);
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('text frames are ignored', () async {
      final connector = _Connector();
      final connection = HuyaDanmakuConnection(connector: connector.call);
      final events = _record(connection);
      await connection.connect(_args());
      connector.channels.single.incoming
        ..add('text frame')
        ..add(_chat('binary frame'));
      await _until(() => _messages(events).isNotEmpty);
      expect(_messages(events).map((message) => message.message), ['binary frame']);
      await connection.close();
    });

    test('takes HuyaDanmakuArgs only', () async {
      final connection = HuyaDanmakuConnection(connector: _Connector().call);
      await expectLater(connection.connect(_args().toString()), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under huya', () {
      final registry = DanmakuRegistry({SiteIds.huya: HuyaDanmakuConnection.new});
      expect(registry.platforms, [SiteIds.huya]);
      expect(registry.connectionFor(' Huya '), isA<HuyaDanmakuConnection>());
      expect(registry.connectionFor('douyu'), isA<EmptyDanmakuConnection>());
    });

    test('a local WebSocket server: the recorded session end to end', () async {
      // B-4: with the single pushes' ids (_recordedMessages).
      final received = <List<int>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          received.add(frame as List<int>);
          if (received.length == 2) _incoming.forEach(socket.add);
        });
      });
      addTearDown(() => server.close(force: true));
      final requested = <Uri>[];
      final connection = HuyaDanmakuConnection(
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
      await connection.connect(_args());
      await _until(() => _messages(events).length == 112);
      expect(requested, [HuyaDanmakuProtocol.endpoint]);
      expect(received, [_register, _heartbeat]);
      expect(_messages(events).map(_project), _recordedWithoutFrames);
      connection.heartbeat();
      await _until(() => received.length == 3);
      expect(received.last, _heartbeat);
      await connection.close();
    });
  });
}
