import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/acfun/danmaku';

final Uint8List _security = Uint8List.fromList(List.generate(16, (i) => i * 7 + 3));
final Uint8List _sessionKey = Uint8List.fromList(List.generate(16, (i) => 200 - i));
final Uint8List _security2 = Uint8List.fromList(List.generate(16, (i) => 100 + i));

/// A fake socket that records what the connection sends.
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

  /// Delivers [frame] and lets the connection handle it.
  Future<void> receive(Object frame) async {
    incoming.add(frame is String ? frame : Uint8List.fromList(frame as List<int>));
    await Future<void>.delayed(Duration.zero);
  }
}

/// Hands out fake sockets and records every handshake.
final class _Connector {
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
    final channel = _Channel(this);
    channels.add(channel);
    return channel;
  }
}

/// No heartbeat and no join timer: only what the test sends happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

AcfunDanmakuArgs _args({
  String userId = '1700000000000001',
  String token = 'visitor-token',
  String? security,
  bool noSecurity = false,
  List<String> tickets = const ['ticket-a', 'ticket-b'],
  String liveId = 'LIVE1',
  Future<AcfunDanmakuArgs> Function()? refresh,
  Future<AcfunGiftCatalog> Function()? gifts,
}) => AcfunDanmakuArgs(
  authorId: '41254970',
  liveId: liveId,
  visitor: AcfunVisitor(
    userId: userId,
    deviceId: 'web_abcdefghijklmnop',
    token: token,
    security: noSecurity ? null : security ?? base64.encode(_security),
  ),
  tickets: tickets,
  enterRoomAttach: 'attach-1',
  refresh: refresh,
  gifts: gifts,
);

/// The arguments a refresh gives: a new visitor keyed by [_security2].
AcfunDanmakuArgs _refreshed({String liveId = 'LIVE2', Future<AcfunDanmakuArgs> Function()? refresh}) => _args(
  userId: '1700000000000002',
  token: 'visitor-token-2',
  security: base64.encode(_security2),
  tickets: const ['ticket-c'],
  liveId: liveId,
  refresh: refresh,
);

/// A server frame: [command] with [data], sealed with [key] (mode 2 unless
/// [mode] says otherwise).
Uint8List _down(
  String command,
  List<int> data, {
  List<int>? key,
  int mode = 2,
  int seq = 9,
  int error = 0,
  String message = '',
}) {
  final writer = ProtoWriter()
    ..string(1, command)
    ..integer(2, seq)
    ..integer(3, error)
    ..bytes(4, data);
  if (message.isNotEmpty) writer.string(5, message);
  final plain = writer.toBytes();
  final header =
      (ProtoWriter()
            ..integer(1, 13)
            ..integer(7, plain.length)
            ..integer(8, mode)
            ..integer(10, seq))
          .toBytes();
  final payload = mode == 0 ? plain : AcfunDanmakuProtocol.seal(plain, key ?? _sessionKey, List.filled(16, 7));
  return AcfunDanmakuProtocol.frame(header, payload);
}

/// The register answer: [key] as the session key, instance 77.
Uint8List _registerAnswer({List<int>? security, List<int>? key, int error = 0}) => _down(
  AcfunDanmakuProtocol.registerCommand,
  (ProtoWriter()
        ..bytes(2, key ?? _sessionKey)
        ..integer(3, 77))
      .toBytes(),
  key: security ?? _security,
  mode: 1,
  seq: 1,
  error: error,
);

/// A room-command answer of [type] with [code].
Uint8List _roomAck(String type, {int code = 0, List<int> payload = const [], List<int>? key}) => _down(
  AcfunDanmakuProtocol.roomCommand,
  (ProtoWriter()
        ..string(1, type)
        ..integer(2, code)
        ..bytes(4, payload))
      .toBytes(),
  key: key,
);

Uint8List _enterAck({int code = 0, List<int>? key}) => _roomAck(
  AcfunDanmakuProtocol.enterRoomAck,
  code: code,
  payload: (ProtoWriter()..integer(1, 10000)).toBytes(),
  key: key,
);

/// `ZtLiveScMessage` of [type] with [body], gzipped when [zipped].
Uint8List _scMessage(String type, List<int> body, {bool zipped = false}) =>
    (ProtoWriter()
          ..string(1, type)
          ..integer(2, zipped ? 2 : 1)
          ..bytes(3, zipped ? gzip.encode(body) : body)
          ..string(4, 'LIVE1'))
        .toBytes();

Uint8List _push(String type, List<int> body, {int seq = 846000001, bool zipped = false, List<int>? key}) => _down(
  AcfunDanmakuProtocol.messageCommand,
  _scMessage(type, body, zipped: zipped),
  seq: seq,
  key: key,
);

Uint8List _signals(List<(String, List<List<int>>)> items) {
  final out = ProtoWriter();
  for (final (type, payloads) in items) {
    final item = ProtoWriter()..string(1, type);
    for (final payload in payloads) {
      item.bytes(2, payload);
    }
    out.bytes(1, item.toBytes());
  }
  return out.toBytes();
}

Uint8List _user(int id, String name) =>
    (ProtoWriter()
          ..integer(1, id)
          ..string(2, name))
        .toBytes();

Uint8List _comment(String text, {int time = 1790000000000, List<int>? user}) =>
    (ProtoWriter()
          ..string(1, text)
          ..integer(2, time)
          ..bytes(3, user ?? _user(123456, '观众1')))
        .toBytes();

Uint8List _chat(String text, {int seq = 846000001, List<int>? key}) => _push(
  'ZtLiveScActionSignal',
  _signals([
    ('CommonActionSignalComment', [_comment(text)]),
  ]),
  seq: seq,
  key: key,
);

Uint8List _displayInfo(String watching) =>
    (ProtoWriter()..bytes(
          1,
          (ProtoWriter()
                ..string(1, 'CommonStateSignalDisplayInfo')
                ..bytes(2, (ProtoWriter()..string(1, watching)).toBytes()))
              .toBytes(),
        ))
        .toBytes();

/// The recorded gift table (S07-live line 3, the `gift/list` answer).
AcfunGiftCatalog _recordedGifts() => AcfunApi.giftList(
  (jsonDecode(File('$_root/S07-live/frames.jsonl').readAsLinesSync()[2]) as Map<String, dynamic>)['text'] as String,
);

/// A `CommonActionSignalGift`, synthesized after the public protocol (the
/// field numbers of the public client libraries; no gift signal was
/// recorded, D07.6): sender, time, gift id, batch, combo, value, combo id.
Uint8List _giftSignal(
  int giftId, {
  int? count = 1,
  int? combo = 1,
  int value = 0,
  String? comboId = 'combo-1',
  List<int>? user,
  int time = 1790000000000,
}) {
  final out = ProtoWriter()
    ..bytes(1, user ?? _user(123456, '观众1'))
    ..integer(2, time)
    ..integer(3, giftId);
  if (count != null) out.integer(4, count);
  if (combo != null) out.integer(5, combo);
  out.integer(6, value);
  if (comboId != null) out.string(7, comboId);
  return out.toBytes();
}

/// An `AcfunActionSignalThrowBanana` (synthesized: visitor, count, time).
Uint8List _bananaSignal(int count, {List<int>? user}) =>
    (ProtoWriter()
          ..bytes(1, user ?? _user(654321, '观众2'))
          ..integer(2, count)
          ..integer(3, 1790000000500))
        .toBytes();

Uint8List _giftPush(List<Uint8List> gifts, {List<Uint8List> bananas = const []}) => _scMessage(
  'ZtLiveScActionSignal',
  _signals([('CommonActionSignalGift', gifts), if (bananas.isNotEmpty) ('AcfunActionSignalThrowBanana', bananas)]),
);

/// A client frame opened with [key]: its header and upstream payload.
({ProtoMessage header, ProtoMessage up}) _up(List<int> frame, List<int> key) {
  final (:header, :payload) = AcfunDanmakuProtocol.unframe(frame);
  return (header: header, up: ProtoMessage.decode(AcfunDanmakuProtocol.open(payload, key)));
}

/// The command of a client frame: the register opens with [security], the
/// rest with [session].
String _command(List<int> frame, {List<int>? security, List<int>? session}) {
  final (:header, payload: _) = AcfunDanmakuProtocol.unframe(frame);
  final key = header.integer(8) == 1 ? security ?? _security : session ?? _sessionKey;
  return _up(frame, key).up.string(1)!;
}

/// The room command's type and ticket of a `CsCmd` client frame.
(String, String) _roomCommand(List<int> frame, {List<int>? key}) {
  final command = _up(frame, key ?? _sessionKey).up.message(4)!;
  return (command.string(1)!, command.string(3)!);
}

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

Iterable<String> _texts(List<DanmakuEvent> events) => events
    .whereType<DanmakuReceived>()
    .where((event) => event.message.type == LiveMessageType.chat)
    .map((event) => event.message.message);

/// Waits until [condition] holds, at most two seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A connection joined through [connector]: register answered, room entered.
Future<(AcfunDanmakuConnection, List<DanmakuEvent>)> _joined(
  _Connector connector, {
  AcfunDanmakuArgs? args,
  DanmakuSocketPolicy policy = _quiet,
  DateTime Function()? now,
}) async {
  final connection = AcfunDanmakuConnection(connector: connector.call, policy: policy, now: now, random: Random(1));
  final events = _record(connection);
  await connection.connect(args ?? _args());
  final channel = connector.channels.last;
  await channel.receive(_registerAnswer());
  await channel.receive(_enterAck());
  expect(events.last, const DanmakuReady());
  return (connection, events);
}

/// The projection fixtures/acfun/danmaku/v4_expected.dart writes of v4's
/// events, for this implementation's messages.
Map<String, Object?> _project(LiveMessage message) => switch (message.data) {
  LiveAudienceUpdate(:final kind, :final value) => {
    'type': 'online',
    'audience': kind == LiveAudienceMetricKind.onlineViewers ? 'online' : kind.name,
    'value': value,
  },
  _ => {
    'type': message.type.name,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
  },
};

List<Map<String, dynamic>> _lines() => [
  for (final line in File('$_root/S07-live/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
];

Map<String, dynamic> _expectedValue() =>
    (jsonDecode(File('$_root/S07-live/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

/// The recorded HTTP start as `AcfunDanmakuArgs` (what M4.10's room entry
/// gives): the visitor of visitor/login, the `did` of the startPlay URL, the
/// broadcast of startPlay.
AcfunDanmakuArgs _recordedArgs(List<Map<String, dynamic>> lines) {
  Map<String, dynamic> http(String path) =>
      lines.firstWhere((line) => line['url'] != null && Uri.parse(line['url'] as String).path.endsWith(path));
  final startPlay = http('/startPlay');
  final deviceId = Uri.parse(startPlay['url'] as String).queryParameters['did']!;
  final visitor = AcfunApi.visitor(http('/visitor/login')['text'] as String, deviceId: deviceId);
  // The recorded startPlay keeps only what the chat reads (its stream list
  // was dropped by the scrubber), so it is read here, not by AcfunApi.
  final play = (jsonDecode(startPlay['text'] as String) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  return AcfunDanmakuArgs(
    authorId: '41254970',
    liveId: play['liveId'] as String,
    visitor: visitor,
    tickets: (play['availableTickets'] as List<dynamic>).cast<String>(),
    enterRoomAttach: play['enterRoomAttach'] as String,
  );
}

void main() {
  group('protocol', () {
    test('frames: magic, version 1, two big-endian lengths; anything else is a FormatException', () {
      final frame = AcfunDanmakuProtocol.frame([1, 2], [3, 4, 5]);
      expect(frame, [0xAB, 0xCD, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 1, 2, 3, 4, 5]);
      final (:header, :payload) = AcfunDanmakuProtocol.unframe(AcfunDanmakuProtocol.frame([8, 1], [9]));
      expect(header.integer(1), 1);
      expect(payload, [9]);
      expect(() => AcfunDanmakuProtocol.unframe(frame.sublist(0, frame.length - 1)), throwsFormatException);
      expect(() => AcfunDanmakuProtocol.unframe([...frame, 0]), throwsFormatException);
      expect(() => AcfunDanmakuProtocol.unframe([0, 1, ...frame.sublist(2)]), throwsFormatException);
      expect(() => AcfunDanmakuProtocol.unframe(frame.sublist(0, 11)), throwsFormatException);
      final huge = Uint8List.fromList(frame);
      ByteData.sublistView(huge).setUint32(4, 0xFFFFFFFF);
      expect(() => AcfunDanmakuProtocol.unframe(huge), throwsFormatException);
    });

    test('acSecurity: a Base64 AES-128 key, else unusable', () {
      expect(AcfunDanmakuProtocol.securityKey(base64.encode(_security)), _security);
      expect(AcfunDanmakuProtocol.securityKey(null), isNull);
      expect(AcfunDanmakuProtocol.securityKey(''), isNull);
      expect(AcfunDanmakuProtocol.securityKey('not base64!'), isNull);
      expect(AcfunDanmakuProtocol.securityKey(base64.encode(List.filled(24, 1))), isNull);
    });

    test('sealing: IV then AES-128-CBC; short, misaligned or wrongly keyed payloads do not open', () {
      final sealed = AcfunDanmakuProtocol.seal(utf8.encode('hello'), _security, List.filled(16, 5));
      expect(sealed.take(16), List.filled(16, 5));
      expect(sealed, hasLength(32));
      expect(utf8.decode(AcfunDanmakuProtocol.open(sealed, _security)), 'hello');
      expect(() => AcfunDanmakuProtocol.open(sealed.sublist(0, 31), _security), throwsFormatException);
      expect(() => AcfunDanmakuProtocol.open(sealed.sublist(0, 16), _security), throwsFormatException);
      expect(() => AcfunDanmakuProtocol.open(sealed, _sessionKey), throwsFormatException);
    });

    test('register: sealed with acSecurity, the service token in the header, the web client fields', () {
      final args = _args();
      final link = AcfunDanmakuLink(args, security: _security, random: Random(2));
      final frame = link.register();
      final (:header, :up) = _up(frame, _security);
      expect(header.integer(1), 13);
      expect(header.integer(2), 1700000000000001);
      expect(header.integer(3), 0);
      expect(header.integer(8), 1, reason: 'service-token mode');
      expect(header.message(9)!.integer(1), 1);
      expect(header.message(9)!.string(2), 'visitor-token');
      expect(header.integer(10), 1);
      expect(header.string(12), 'ACFUN_APP');
      expect(
        header.integer(7),
        AcfunDanmakuProtocol.open(AcfunDanmakuProtocol.unframe(frame).payload, _security).length,
        reason: 'decodedPayloadLen is the plain length',
      );
      expect((up.string(1), up.integer(2), up.integer(3), up.string(9)), ('Basic.Register', 1, 1, 'mainApp'));
      final request = up.message(4)!;
      expect((request.message(1)!.string(1), request.message(1)!.string(4)), ('link-sdk', '1.2.1'));
      final device = request.message(2)!;
      expect((device.integer(1), device.string(3), device.string(5)), (6, 'h5', 'web_abcdefghijklmnop'));
      expect((request.integer(4), request.integer(5), request.integer(8)), (1, 1, 0));
      final common = request.message(11)!;
      expect(
        (common.string(1), common.string(2), common.integer(4), common.string(5)),
        ('ACFUN_APP', 'PC_WEB', 1700000000000001, 'web_abcdefghijklmnop'),
      );
      expect(link.registered, isFalse);
      expect(link.keepAlive, throwsStateError, reason: 'no session key before the register answer');
    });

    test('after the register answer: the session key, the instance id and counting sequence ids', () {
      final link = AcfunDanmakuLink(_args(), security: _security, random: Random(2))..register();
      final answer = link.read(_registerAnswer());
      expect((answer.command, answer.errorCode, answer.seqId, link.registered), ('Basic.Register', 0, 1, true));
      final keep = _up(link.keepAlive(), _sessionKey);
      expect((keep.header.integer(8), keep.header.integer(3), keep.header.integer(10)), (2, 77, 2));
      expect(keep.header.message(9), isNull);
      expect((keep.up.string(1), keep.up.integer(2)), ('Basic.KeepAlive', 2));
      expect((keep.up.message(4)!.integer(1), keep.up.message(4)!.integer(2)), (1, 1));

      final enter = _up(link.enterRoom(ticket: 'ticket-a', reconnects: 2), _sessionKey);
      expect(enter.up.string(1), 'Global.ZtLiveInteractive.CsCmd');
      final command = enter.up.message(4)!;
      expect((command.string(1), command.string(3), command.string(4)), ('ZtLiveCsEnterRoom', 'ticket-a', 'LIVE1'));
      final body = command.message(2)!;
      expect(
        (body.integer(1), body.integer(2), body.string(4), body.string(5)),
        (0, 2, 'attach-1', 'kwai-acfun-live-link'),
      );

      final now = DateTime.utc(2026, 9, 29);
      final first = _up(link.heartbeat(ticket: 'ticket-b', now: now), _sessionKey);
      final second = _up(link.heartbeat(ticket: 'ticket-b', now: now), _sessionKey);
      final beat = first.up.message(4)!;
      expect((beat.string(1), beat.string(3)), ('ZtLiveCsHeartbeat', 'ticket-b'));
      expect((beat.message(2)!.integer(1), beat.message(2)!.integer(2)), (now.millisecondsSinceEpoch, 0));
      expect(second.up.message(4)!.message(2)!.integer(2), 1, reason: 'the heartbeat sequence counts from 0');
      expect((first.header.integer(10), second.header.integer(10)), (4, 5));
    });

    test('a push acknowledgement echoes the push sequence id, carries no payload and does not count', () {
      final link = AcfunDanmakuLink(_args(), security: _security, random: Random(2))..read(_registerAnswer());
      final push = link.read(_chat('hi', seq: 846000123));
      expect((push.command, push.seqId), ('Push.ZtLiveInteractive.Message', 846000123));
      final ack = _up(link.pushAck(push), _sessionKey);
      expect((ack.header.integer(10), ack.up.integer(2)), (846000123, 1));
      expect(ack.up.string(1), 'Push.ZtLiveInteractive.Message');
      expect(ack.up.bytes(4), isNull);
      expect(_up(link.keepAlive(), _sessionKey).up.integer(2), 1, reason: 'the ack did not use a sequence id');
    });

    test('reading: wrong keys, early session frames, unknown modes and bad answers', () {
      final fresh = AcfunDanmakuLink(_args(), security: _security);
      expect(() => fresh.read(_chat('early')), throwsFormatException, reason: 'no session key yet');
      expect(() => fresh.read(_down('X', const [], mode: 3)), throwsFormatException);
      expect(() => fresh.read(_registerAnswer(security: _security2)), throwsFormatException);
      final plain = fresh.read(_down('Basic.Ping', const [1], mode: 0, error: 5, message: 'nope'));
      expect((plain.command, plain.errorCode, plain.error), ('Basic.Ping', 5, 'nope'));
      expect(plain.payload, [1]);

      final refused = AcfunDanmakuLink(_args(), security: _security)..read(_registerAnswer(error: 10));
      expect(refused.registered, isFalse, reason: 'a refused register keeps no key');
      final shortKey = AcfunDanmakuLink(_args(), security: _security)..read(_registerAnswer(key: List.filled(8, 1)));
      expect(shortKey.registered, isFalse, reason: 'the session key is an AES-128 key');
    });

    test('command answers and the enter-room heartbeat interval', () {
      final ack = AcfunDanmakuProtocol.ack(
        (ProtoWriter()
              ..string(1, 'ZtLiveCsEnterRoomAck')
              ..integer(2, 3)
              ..bytes(4, (ProtoWriter()..integer(1, 10000)).toBytes()))
            .toBytes(),
      );
      expect((ack.type, ack.code), ('ZtLiveCsEnterRoomAck', 3));
      expect(AcfunDanmakuProtocol.heartbeatInterval(ack.payload), const Duration(seconds: 10));
      expect(AcfunDanmakuProtocol.heartbeatInterval(const []), isNull);
      final empty = AcfunDanmakuProtocol.ack(const []);
      expect((empty.type, empty.code, empty.payload.length), ('', 0, 0));
    });

    test('pushes: comments (plain and gzipped) and the audience; everything else is not shown', () {
      final actions = AcfunDanmakuProtocol.push(
        _scMessage(
          'ZtLiveScActionSignal',
          _signals([
            ('CommonActionSignalComment', [_comment('顶不住了'), _comment('second', user: _user(0, 'guest'))]),
            ('CommonActionSignalLike', [_user(1, 'liker')]),
            ('CommonActionSignalGift', [_user(2, 'giver')]),
            ('AcfunActionSignalThrowBanana', [_user(3, 'banana')]),
          ]),
          zipped: true,
        ),
      );
      expect((actions.ticketInvalid, actions.statusChanged), (false, null));
      final chats = actions.messages;
      expect(chats, hasLength(2));
      expect(
        (chats.first.type, chats.first.userId, chats.first.userName, chats.first.message),
        (LiveMessageType.chat, '123456', '观众1', '顶不住了'),
      );
      expect(chats.first.sentAt, DateTime.fromMillisecondsSinceEpoch(1790000000000));
      expect((chats.first.color, chats.first.messageId), (LiveMessageColor.white, ''));
      expect((chats.last.userId, chats.last.userName), ('', 'guest'), reason: 'no id below 1');

      final states = AcfunDanmakuProtocol.push(
        _scMessage('ZtLiveScStateSignal', [
          ..._displayInfo('1.2万'),
          ...(ProtoWriter()..bytes(1, (ProtoWriter()..string(1, 'AcfunStateSignalDisplayInfo')).toBytes())).toBytes(),
          ..._displayInfo('76'),
          ..._displayInfo('many'),
        ]),
      );
      expect([for (final message in states.messages) (message.data! as LiveAudienceUpdate).value], [12000, 76]);
      expect(states.messages.first.type, LiveMessageType.online);
      expect((states.messages.first.data! as LiveAudienceUpdate).kind, LiveAudienceMetricKind.onlineViewers);

      final notify = AcfunDanmakuProtocol.push(_scMessage('ZtLiveScNotifySignal', _displayInfo('9')));
      expect(notify.messages, isEmpty);
    });

    group('gifts (D07.6; signals synthesized after the public protocol)', () {
      final table = _recordedGifts();

      test('a gift named, priced and pictured by the recorded table: AC coins, ten to a yuan', () {
        final message = AcfunDanmakuProtocol.push(
          _giftPush([_giftSignal(16, count: 2, combo: 3, value: 2888000)]),
          gifts: table,
        ).messages.single;
        expect(
          (message.type, message.userId, message.userName, message.message, message.color),
          (LiveMessageType.gift, '123456', '观众1', '猴岛 ×2', LiveMessageColor.white),
        );
        expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790000000000));
        expect(
          message.data,
          AcfunGift(
            id: '16',
            name: '猴岛',
            count: 2,
            comboKey: 'combo-1',
            comboTotal: 6,
            unitPrice: 2888,
            totalValue: 5776,
            unit: LiveGiftUnit.acCoin,
            iconUrl: table['16']!.iconUrl,
            value: 2888000,
          ),
        );
        expect(message.gift!.tier, LiveGiftTier.precious, reason: '577.6 yuan');
        expect('${message.data}', 'AcfunGift(猴岛 ×2)');
      });

      test('bananas: the gift with id 1 and the throw signal, free', () {
        final messages = AcfunDanmakuProtocol.push(
          _giftPush([_giftSignal(1, count: 5, comboId: null)], bananas: [_bananaSignal(3)]),
          gifts: table,
        ).messages;
        expect([for (final message in messages) message.message], ['香蕉 ×5', '香蕉 ×3']);
        for (final message in messages) {
          final gift = message.gift!;
          expect(
            (gift.id, gift.unit, gift.free, gift.unitPrice, gift.iconUrl),
            ('1', LiveGiftUnit.banana, true, 1, table['1']!.iconUrl),
          );
          expect(gift.tier, LiveGiftTier.normal);
        }
        expect((messages.first.gift!.comboKey, messages.first.gift!.comboTotal), ('', 5));
        expect((messages.last.userName, messages.last.gift!.comboTotal), ('观众2', null));
        expect(messages.last.sentAt, DateTime.fromMillisecondsSinceEpoch(1790000000500));
      });

      test('without the table: only the id (a banana keeps its name), no value', () {
        final messages = AcfunDanmakuProtocol.push(
          _giftPush([_giftSignal(17), _giftSignal(1)], bananas: [_bananaSignal(1)]),
        ).messages;
        expect(
          [for (final message in messages) (message.gift!.name, message.gift!.displayName)],
          [('', '17'), ('香蕉', '香蕉'), ('香蕉', '香蕉')],
        );
        final unknown = messages.first.gift!;
        expect(
          (unknown.unit, unknown.totalValue, unknown.free, unknown.iconUrl),
          (LiveGiftUnit.other, null, false, null),
        );
        expect(messages[1].gift!.free, isTrue);
        // A gift the table does not list: the id only.
        expect(AcfunDanmakuProtocol.push(_giftPush([_giftSignal(99999)]), gifts: table).messages.single.gift!.name, '');
      });

      test('bad signals: no sender or gift id gives nothing; missing counts are 1; the others still come', () {
        final messages = AcfunDanmakuProtocol.push(
          _giftPush([
            (ProtoWriter()..integer(3, 17)).toBytes(),
            (ProtoWriter()..bytes(1, _user(1, 'a'))).toBytes(),
            _giftSignal(0),
            _giftSignal(17, count: null, combo: null),
            _giftSignal(17, count: -2, combo: 0, comboId: '  '),
            Uint8List.fromList([0x0A, 0x09]),
            _giftSignal(35, combo: 2, user: _user(0, 'guest')),
          ]),
          gifts: table,
        ).messages;
        expect(
          [for (final message in messages) (message.gift!.count, message.gift!.comboTotal)],
          [(1, null), (1, null), (1, 2)],
        );
        expect(messages[1].gift!.comboKey, '');
        expect((messages.last.userId, messages.last.userName), ('', 'guest'));
        expect(
          AcfunDanmakuProtocol.push(_giftPush(const [], bananas: [(ProtoWriter()..integer(2, 3)).toBytes()])).messages,
          isEmpty,
          reason: 'a banana without a sender',
        );
      });

      test('the connection names gifts once the table came; before it, or when it fails, by id', () async {
        final table = Completer<AcfunGiftCatalog>();
        var asked = 0;
        final connector = _Connector();
        final (connection, events) = await _joined(
          connector,
          args: _args(
            gifts: () {
              asked++;
              return table.future;
            },
          ),
        );
        final channel = connector.channels.single;
        await channel.receive(
          _push(
            'ZtLiveScActionSignal',
            _signals([
              ('CommonActionSignalGift', [_giftSignal(17)]),
            ]),
          ),
        );
        table.complete(_recordedGifts());
        await Future<void>.delayed(Duration.zero);
        await channel.receive(
          _push(
            'ZtLiveScActionSignal',
            _signals([
              ('CommonActionSignalGift', [_giftSignal(17)]),
            ]),
          ),
        );
        final gifts = [for (final event in events.whereType<DanmakuReceived>()) ?event.message.gift];
        expect([for (final gift in gifts) (gift.displayName, gift.unitPrice)], [('17', null), ('快乐水', 1)]);
        // A reconnect keeps the table and does not ask again.
        await channel.incoming.close();
        await _until(() => connector.channels.length == 2);
        expect(asked, 1);
        await connection.close();

        final failing = _Connector();
        final (other, otherEvents) = await _joined(failing, args: _args(gifts: () => Future.error(StateError('x'))));
        await failing.channels.single.receive(
          _push(
            'ZtLiveScActionSignal',
            _signals([
              ('CommonActionSignalGift', [_giftSignal(17)]),
            ]),
          ),
        );
        expect(otherEvents.whereType<DanmakuReceived>().single.message.gift!.displayName, '17');
        await other.close();
      });
    });

    test('pushes: a dead ticket and the broadcast status are flagged', () {
      expect(AcfunDanmakuProtocol.push(_scMessage('ZtLiveScTicketInvalid', const [])).ticketInvalid, isTrue);
      for (final type in [1, 2, 3, 4]) {
        final push = AcfunDanmakuProtocol.push(
          _scMessage('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, type)).toBytes()),
        );
        expect((push.statusChanged, push.ticketInvalid), (type, false));
      }
      expect(AcfunDanmakuProtocol.push(_scMessage('ZtLiveScStatusChanged', const [])).statusChanged, 0);
      expect(AcfunDanmakuProtocol.refreshingStatuses, {1, 2, 4});
    });

    test('pushes: bad parts are skipped on their own; boundaries of text, sender and time', () {
      final push = AcfunDanmakuProtocol.push(
        _scMessage(
          'ZtLiveScActionSignal',
          _signals([
            (
              'CommonActionSignalComment',
              [
                [0x0A, 0x05, 0x61],
                _comment(''),
                (ProtoWriter()..string(1, 'no sender')).toBytes(),
                _comment('zero time', time: 0),
                _comment('far time', time: 8640000000000001),
                _comment('kept'),
              ],
            ),
          ]),
        ),
      );
      expect(push.messages.map((message) => message.message), ['zero time', 'far time', 'kept']);
      expect(push.messages.take(2).map((message) => message.sentAt), [null, null]);

      expect(AcfunDanmakuProtocol.push([0x0A, 0x05]).messages, isEmpty, reason: 'a truncated message');
      final badGzip =
          (ProtoWriter()
                ..string(1, 'ZtLiveScActionSignal')
                ..integer(2, 2)
                ..bytes(3, [1, 2, 3]))
              .toBytes();
      expect(AcfunDanmakuProtocol.push(badGzip).messages, isEmpty);
      expect(AcfunDanmakuProtocol.push(_scMessage('ZtLiveScSomethingNew', _displayInfo('5'))).messages, isEmpty);
      final truncatedList = AcfunDanmakuProtocol.push(
        _scMessage('ZtLiveScStateSignal', [..._displayInfo('7'), 0x0A, 0x09]),
      );
      expect(truncatedList.messages, isEmpty, reason: 'a signal list that does not decode');
      final badSignal = AcfunDanmakuProtocol.push(
        _scMessage('ZtLiveScStateSignal', [
          ...(ProtoWriter()..bytes(1, const [0x0A, 0x09])).toBytes(),
          ..._displayInfo('7'),
        ]),
      );
      expect(badSignal.messages.map((message) => (message.data! as LiveAudienceUpdate).value), [
        7,
      ], reason: 'a signal that does not decode is skipped on its own');
    });
  });

  group('the recording (fixtures/acfun/danmaku/S07-live)', () {
    final lines = _lines();
    final expected = _expectedValue();
    final args = _recordedArgs(lines);
    final security = AcfunDanmakuProtocol.securityKey(args.visitor.security)!;

    test('the recorded HTTP start gives the arguments v4 used', () {
      final session = expected['session'] as Map<String, dynamic>;
      expect(args.visitor.userId, session['userId']);
      expect(args.visitor.deviceId, session['deviceId']);
      expect(args.liveId, session['liveId']);
      expect(args.tickets, session['tickets']);
      expect(args.enterRoomAttach, session['attach']);
    });

    test('every received frame decodes as v4 decoded it (expected.json)', () {
      final link = AcfunDanmakuLink(args, security: security);
      final frames = (expected['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
      final byLine = {for (final frame in frames) frame['line'] as int: frame};
      var chats = 0;
      var audiences = 0;
      var compared = 0;
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line['dir'] != 'in' || line['b64'] == null) continue;
        final want = byLine[index + 1]!;
        final packet = link.read(base64.decode(line['b64'] as String));
        expect(
          (packet.command, packet.seqId, packet.errorCode),
          (want['command'], want['seqId'], want['errorCode']),
          reason: 'line ${index + 1}',
        );
        if (want['registered'] != null) expect(link.registered, want['registered']);
        if (want['ack'] case final Map<String, dynamic> ack) {
          final got = AcfunDanmakuProtocol.ack(packet.payload);
          expect((got.type, got.code), (ack['type'], ack['code']), reason: 'line ${index + 1}');
          if (ack.containsKey('heartbeatMs')) {
            expect(AcfunDanmakuProtocol.heartbeatInterval(got.payload)?.inMilliseconds, ack['heartbeatMs']);
          }
        }
        if (want['events'] case final List<dynamic> events) {
          final push = AcfunDanmakuProtocol.push(packet.payload);
          expect(push.messages.map(_project).toList(), events, reason: 'line ${index + 1}');
          expect(push.ticketInvalid, want['ticketInvalid']);
          expect(push.statusChanged == 1, want['liveClosed']);
          chats += push.messages.where((message) => message.type == LiveMessageType.chat).length;
          audiences += push.messages.where((message) => message.type == LiveMessageType.online).length;
        }
        compared++;
      }
      expect((compared, byLine.length), (390, 390));
      expect((chats, audiences), (1, 151));
    });

    test('the recorded client frames are what this link writes (headers and plain payloads)', () {
      final link = AcfunDanmakuLink(args, security: security);
      Uint8List? sessionKey;
      AcfunDanmakuPacket? lastPush;
      final counts = <String, int>{};
      for (final line in lines) {
        if (line['b64'] == null) continue;
        final bytes = base64.decode(line['b64'] as String);
        if (line['dir'] == 'in') {
          final packet = link.read(bytes);
          if (packet.command == AcfunDanmakuProtocol.registerCommand) {
            sessionKey = ProtoMessage.decode(packet.payload).bytes(2);
          }
          if (packet.command.startsWith('Push.')) lastPush = packet;
          continue;
        }
        final recorded = AcfunDanmakuProtocol.unframe(bytes);
        final key = recorded.header.integer(8) == 1 ? security : sessionKey!;
        final plain = ProtoMessage.decode(AcfunDanmakuProtocol.open(recorded.payload, key));
        final command = plain.string(1)!;
        final Uint8List ours;
        switch (command) {
          case 'Basic.Register':
            ours = link.register();
          case 'Basic.KeepAlive':
            ours = link.keepAlive();
          case 'Global.ZtLiveInteractive.CsCmd':
            final cmd = plain.message(4)!;
            ours = cmd.string(1) == 'ZtLiveCsEnterRoom'
                ? link.enterRoom(ticket: args.tickets.first)
                : link.heartbeat(
                    ticket: args.tickets.first,
                    now: DateTime.fromMillisecondsSinceEpoch(cmd.message(2)!.integer(1)!),
                  );
          default:
            expect(command, lastPush!.command);
            ours = link.pushAck(lastPush);
        }
        final mine = AcfunDanmakuProtocol.unframe(ours);
        List<Object> fields(ProtoMessage header) => [
          for (final field in header.fields)
            [field.number, if (field.value case final List<int> bytes) List.of(bytes) else field.value],
        ];
        expect(fields(mine.header), fields(recorded.header), reason: '$command header');
        expect(AcfunDanmakuProtocol.open(mine.payload, key), AcfunDanmakuProtocol.open(recorded.payload, key));
        counts[command] = (counts[command] ?? 0) + 1;
      }
      expect(counts, {
        'Basic.Register': 1,
        'Basic.KeepAlive': 6,
        'Global.ZtLiveInteractive.CsCmd': 31,
        'Push.ZtLiveInteractive.Message': 353,
      });
    });

    test('the connection replays the recording: joined once, every push acknowledged, 1 chat, 151 audiences', () async {
      final connector = _Connector();
      final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(args);
      expect(connector.endpoints, [Uri.parse('wss://link.xiatou.com/')]);
      expect(connector.headers.single, {'user-agent': AcfunApi.userAgent, 'origin': 'https://live.acfun.cn'});
      final channel = connector.channels.single;
      expect(channel.sent.map((frame) => _command(frame, security: security)), ['Basic.Register']);
      for (final line in lines) {
        if (line['dir'] == 'in' && line['b64'] != null) await channel.receive(base64.decode(line['b64'] as String));
      }
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['对面是使劲的。']);
      final audiences = [
        for (final event in events.whereType<DanmakuReceived>())
          if (event.message.data case LiveAudienceUpdate(:final value)) value,
      ];
      expect(audiences, hasLength(151));
      expect(audiences.toSet(), {70, 71, 72, 73, 74, 75, 76});
      final sessionKey = ProtoMessage.decode(
        ProtoMessage.decode(
          AcfunDanmakuProtocol.open(
            AcfunDanmakuProtocol.unframe(base64.decode(lines[4]['b64'] as String)).payload,
            security,
          ),
        ).bytes(4)!,
      ).bytes(2)!;
      final commands = [for (final frame in channel.sent) _command(frame, security: security, session: sessionKey)];
      expect(commands.take(3), ['Basic.Register', 'Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd']);
      expect(commands.skip(3), everyElement('Push.ZtLiveInteractive.Message'));
      expect(commands.skip(3), hasLength(353));
      await connection.close();
    });
  });

  group('connection', () {
    test('timing, the registry entry and the argument type', () async {
      final connection = AcfunDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 10));
      expect(connection.site, SiteIds.acfun);
      expect(AcfunDanmakuConnection.defaultPolicy.joinTimeout, const Duration(seconds: 10));
      expect(AcfunDanmakuConnection.defaultPolicy.inactivityTimeout, isNull, reason: 'max(3 × 10 s, 90 s)');
      expect(AcfunDanmakuConnection.defaultPolicy.maxReconnects, 8);
      final registry = DanmakuRegistry({SiteIds.acfun: AcfunDanmakuConnection.new});
      expect(registry.supports('acfun'), isTrue);
      expect(registry.connectionFor('AcFun'), isA<AcfunDanmakuConnection>());
      await expectLater(connection.connect('not acfun args'), throwsArgumentError);
    });

    test('handshake: register at open, keep-alive and enter room on its answer, ready on the enter answer', () async {
      final connector = _Connector();
      final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args());
      final channel = connector.channels.single;
      expect(channel.sent.map(_command), ['Basic.Register']);
      expect(connection.status, DanmakuStatus.connecting);
      await channel.receive(_registerAnswer());
      expect(channel.sent.skip(1).map(_command), ['Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd']);
      expect(_roomCommand(channel.sent.last), ('ZtLiveCsEnterRoom', 'ticket-a'));
      expect(events, isEmpty);
      await channel.receive(_chat('before the enter answer'));
      expect(_texts(events), ['before the enter answer']);
      expect(connection.isConnected, isFalse);
      await channel.receive(_enterAck());
      expect(events.last, const DanmakuReady());
      expect(connection.isConnected, isTrue);
      await channel.receive(_enterAck());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await connection.close();
    });

    test('heartbeats only after the room was entered, with a keep-alive every fifth one', () async {
      final connector = _Connector();
      final now = DateTime.utc(2026, 9, 29, 12);
      final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet, now: () => now);
      await connection.connect(_args());
      final channel = connector.channels.single;
      connection.heartbeat();
      await channel.receive(_registerAnswer());
      connection.heartbeat();
      expect(channel.sent.map(_command), ['Basic.Register', 'Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd']);
      await channel.receive(_enterAck());
      final before = channel.sent.length;
      for (var i = 0; i < 10; i++) {
        connection.heartbeat();
      }
      final beats = channel.sent.skip(before).toList();
      expect(beats.map(_command), [
        for (var i = 1; i <= 10; i++) ...[if (i % 5 == 0) 'Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd'],
      ]);
      final heartbeats = beats.where((frame) => _command(frame) != 'Basic.KeepAlive').toList();
      expect(heartbeats.map(_roomCommand), everyElement(('ZtLiveCsHeartbeat', 'ticket-a')));
      final payload = _up(heartbeats.last, _sessionKey).up.message(4)!.message(2)!;
      expect((payload.integer(1), payload.integer(2)), (now.millisecondsSinceEpoch, 9));
      await connection.close();
    });

    test('the heartbeat timer runs every interval once joined', () async {
      final connector = _Connector();
      final (connection, _) = await _joined(
        connector,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 10),
          inactivityTimeout: Duration(seconds: 5),
        ),
      );
      final channel = connector.channels.single;
      await _until(
        () => channel.sent.where((frame) => _command(frame) == 'Global.ZtLiveInteractive.CsCmd').length >= 7,
      );
      expect(
        channel.sent.where((frame) => _command(frame) == 'Basic.KeepAlive').length,
        greaterThanOrEqualTo(2),
        reason: 'the one after the register answer and the one with the fifth heartbeat',
      );
      await connection.close();
    });

    test('every push is acknowledged before its messages are reported; other pushes too', () async {
      final connector = _Connector();
      final (connection, _) = await _joined(connector);
      final order = <String>[];
      connection.events.listen((event) => order.add('event'));
      connector.onSend = (bytes) => order.add('send ${_command(bytes)}');
      final channel = connector.channels.single;
      await channel.receive(_chat('ack me', seq: 846000777));
      expect(order, ['send Push.ZtLiveInteractive.Message', 'event']);
      expect(_up(channel.sent.last, _sessionKey).header.integer(10), 846000777);
      order.clear();
      await channel.receive(_down('Push.SomethingElse', const [1, 2], seq: 55));
      expect(order, ['send Push.SomethingElse']);
      await channel.receive(_down('Basic.KeepAlive', (ProtoWriter()..integer(2, 1790000000000)).toBytes()));
      await channel.receive(_roomAck('ZtLiveCsHeartbeatAck'));
      await channel.receive(_down('Basic.Unknown', const []));
      expect(order, ['send Push.SomethingElse'], reason: 'answers are not acknowledged');
      await connection.close();
    });

    test('bad frames are dropped on their own', () async {
      final connector = _Connector();
      final (connection, events) = await _joined(connector);
      final channel = connector.channels.single;
      final sent = channel.sent.length;
      await channel.receive('text frame');
      await channel.receive([1, 2, 3]);
      await channel.receive(_chat('wrong key', key: _security2));
      final chat = _chat('truncated');
      await channel.receive(chat.sublist(0, chat.length - 1));
      await channel.receive(_roomAck('x', key: _security2));
      await channel.receive(_down(AcfunDanmakuProtocol.roomCommand, const [0x0A, 0x09]));
      await channel.receive(_chat('still here'));
      expect(_texts(events), ['still here']);
      expect(channel.sent.length, sent + 1, reason: 'only the good push was acknowledged');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test('a dropped socket reconnects, registers again and tells the reconnect count', () async {
      final connector = _Connector();
      final (connection, events) = await _joined(connector);
      await connector.channels.single.incoming.close();
      await _until(() => connector.channels.length == 2);
      expect(connection.isConnected, isFalse);
      final second = connector.channels.last;
      expect(second.sent.map(_command), ['Basic.Register']);
      await second.receive(_registerAnswer());
      final enter = _up(second.sent.last, _sessionKey).up.message(4)!;
      expect((enter.string(1), enter.message(2)!.integer(2)), ('ZtLiveCsEnterRoom', 1));
      await second.receive(_enterAck());
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connection.close();
    });

    group('tickets', () {
      test('a dead ticket enters again with the next one on the same socket', () async {
        final connector = _Connector();
        final (connection, events) = await _joined(connector);
        final channel = connector.channels.single;
        await channel.receive(_roomAck('ZtLiveCsHeartbeatAck', code: 3));
        expect(connection.isConnected, isFalse);
        expect(_roomCommand(channel.sent.last), ('ZtLiveCsEnterRoom', 'ticket-b'));
        await channel.receive(_enterAck());
        expect(events.whereType<DanmakuReady>(), hasLength(2));
        connection.heartbeat();
        expect(_roomCommand(channel.sent.last), ('ZtLiveCsHeartbeat', 'ticket-b'));
        expect(connector.channels, hasLength(1));
        await connection.close();
      });

      test('ZtLiveScTicketInvalid moves to the next ticket too', () async {
        final connector = _Connector();
        final (connection, _) = await _joined(connector);
        final channel = connector.channels.single;
        await channel.receive(_push('ZtLiveScTicketInvalid', const []));
        expect(_command(channel.sent[channel.sent.length - 2]), 'Push.ZtLiveInteractive.Message');
        expect(_roomCommand(channel.sent.last), ('ZtLiveCsEnterRoom', 'ticket-b'));
        await connection.close();
      });

      test('when every ticket failed since the last join, new arguments and a new socket, without a notice', () async {
        final connector = _Connector();
        var refreshes = 0;
        final (connection, events) = await _joined(
          connector,
          args: _args(
            refresh: () async {
              refreshes++;
              return _refreshed();
            },
          ),
        );
        final first = connector.channels.single;
        await first.receive(_enterAck(code: 2));
        expect(_roomCommand(first.sent.last), ('ZtLiveCsEnterRoom', 'ticket-b'));
        await first.receive(_enterAck(code: 4));
        await _until(() => connector.channels.length == 2);
        expect(refreshes, 1);
        expect(first.closed, isTrue);
        final second = connector.channels.last;
        final register = _up(second.sent.single, _security2);
        expect(register.header.message(9)!.string(2), 'visitor-token-2');
        await second.receive(_registerAnswer(security: _security2));
        final enter = _up(second.sent.last, _sessionKey).up.message(4)!;
        expect((enter.string(3), enter.string(4)), ('ticket-c', 'LIVE2'));
        await second.receive(_enterAck());
        expect(events, [const DanmakuReady(), const DanmakuReady()]);
        await connection.close();
      });
    });

    group('refresh', () {
      test('a refused register refreshes and reopens', () async {
        final connector = _Connector();
        final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
        await connection.connect(_args(refresh: () async => _refreshed()));
        await connector.channels.single.receive(_registerAnswer(error: 10018));
        await _until(() => connector.channels.length == 2);
        expect(_command(connector.channels.last.sent.single, security: _security2), 'Basic.Register');
        await connection.close();
      });

      test('a refused command, an ended broadcast and a new broadcast refresh; new stream URLs do not', () async {
        for (final (name, frame) in [
          ('envelope error', _down(AcfunDanmakuProtocol.roomCommand, const [], error: 1)),
          ('keep-alive error', _down(AcfunDanmakuProtocol.keepAliveCommand, const [], error: 1)),
          ('ended (1)', _roomAck('ZtLiveCsHeartbeatAck', code: 1)),
          ('new broadcast (8)', _roomAck('ZtLiveCsHeartbeatAck', code: 8)),
          ('closed', _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 1)).toBytes())),
          ('reopened', _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 2)).toBytes())),
          ('banned', _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 4)).toBytes())),
        ]) {
          final connector = _Connector();
          var refreshes = 0;
          final (connection, _) = await _joined(
            connector,
            args: _args(
              refresh: () async {
                refreshes++;
                return _refreshed();
              },
            ),
          );
          await connector.channels.single.receive(frame);
          await _until(() => connector.channels.length == 2);
          expect(refreshes, 1, reason: name);
          await connection.close();
        }
        final connector = _Connector();
        final (connection, _) = await _joined(connector, args: _args(refresh: () => fail('no refresh')));
        await connector.channels.single.receive(
          _push('ZtLiveScStatusChanged', (ProtoWriter()..integer(1, 3)).toBytes()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connector.channels, hasLength(1));
        expect(connection.isConnected, isTrue);
        await connection.close();
      });

      test('a broadcast that is gone ends as connectionFailed; nothing follows', () async {
        final connector = _Connector();
        final (connection, events) = await _joined(
          connector,
          args: _args(refresh: () async => throw const StreamUnavailable('acfun', 'startPlay: 直播已关播 (129004)')),
        );
        final channel = connector.channels.single;
        await channel.receive(_roomAck('ZtLiveCsHeartbeatAck', code: 1));
        await _until(() => events.last is DanmakuClosed);
        expect(
          events.last,
          const DanmakuClosed(
            DanmakuCloseReason.connectionFailed,
            detail: 'Command error 1; refresh failed: StreamUnavailable',
          ),
        );
        expect(connection.status, DanmakuStatus.closed);
        await _until(() => channel.closed);
        final count = events.length;
        await channel.receive(_chat('late'));
        expect(events, hasLength(count));
      });

      test('a failed refresh, or none, ends as credentialsUnavailable without leaking the error text', () async {
        for (final refresh in <Future<AcfunDanmakuArgs> Function()?>[
          () async => throw const NetworkFailure('acfun', 'GET https://x/?acfun.api.visitor_st=secret failed'),
          null,
          () async => _args(noSecurity: true),
        ]) {
          final connector = _Connector();
          final (_, events) = await _joined(connector, args: _args(refresh: refresh));
          await connector.channels.single.receive(_enterAck(code: 9));
          await _until(() => events.last is DanmakuClosed);
          final closed = events.last as DanmakuClosed;
          expect(closed.reason, DanmakuCloseReason.credentialsUnavailable);
          expect(closed.detail, isNot(contains('secret')));
        }
      });

      test('one refresh at a time; at most three without a join, a join resets the budget', () async {
        final connector = _Connector();
        final pending = <Completer<AcfunDanmakuArgs>>[];
        Future<AcfunDanmakuArgs> refresh() {
          final completer = Completer<AcfunDanmakuArgs>();
          pending.add(completer);
          return completer.future;
        }

        final (connection, events) = await _joined(connector, args: _args(refresh: refresh));
        await connector.channels.last.receive(_enterAck(code: 9));
        await connector.channels.last.receive(_enterAck(code: 9));
        expect(pending, hasLength(1), reason: 'the second refusal found the refresh running');
        for (var i = 1; i <= 3; i++) {
          pending.last.complete(_args(refresh: refresh));
          await _until(() => connector.channels.length == i + 1);
          await connector.channels.last.receive(_registerAnswer());
          if (i < 3) {
            await connector.channels.last.receive(_enterAck(code: 9));
            expect(pending, hasLength(i + 1));
          }
        }
        await connector.channels.last.receive(_enterAck());
        expect(connection.isConnected, isTrue, reason: 'joined after the third refresh');
        await connector.channels.last.receive(_enterAck(code: 9));
        expect(pending, hasLength(4), reason: 'the join reset the budget');
        pending.last.complete(_args(refresh: refresh));
        await _until(() => connector.channels.length == 5);
        for (var i = 0; i < 2; i++) {
          await connector.channels.last.receive(_registerAnswer(error: 1));
          pending.last.complete(_args(refresh: refresh));
          await _until(() => connector.channels.length == 6 + i);
        }
        await connector.channels.last.receive(_registerAnswer(error: 1));
        expect(
          events.last,
          const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable, detail: 'Register refused (1)'),
        );
        expect(pending, hasLength(6));
      });

      test('a refresh that returns after close or another connect does nothing', () async {
        final connector = _Connector();
        final completer = Completer<AcfunDanmakuArgs>();
        final (connection, events) = await _joined(connector, args: _args(refresh: () => completer.future));
        await connector.channels.single.receive(_enterAck(code: 9));
        await connection.close();
        final count = events.length;
        completer.complete(_refreshed());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connector.channels, hasLength(1));
        expect(events, hasLength(count));
      });
    });

    group('start', () {
      test('connecting sends no HTTP request: the arguments are from room entry', () async {
        final connector = _Connector();
        final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
        await connection.connect(_args(refresh: () => fail('no refresh at start')));
        expect(connector.channels, hasLength(1));
        await connection.close();
      });

      test('no acSecurity or no tickets: one refresh first', () async {
        for (final args in [
          _args(noSecurity: true, refresh: () async => _refreshed()),
          _args(tickets: const [], refresh: () async => _refreshed()),
          _args(security: 'short', refresh: () async => _refreshed()),
        ]) {
          final connector = _Connector();
          final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
          await connection.connect(args);
          expect(_command(connector.channels.single.sent.single, security: _security2), 'Basic.Register');
          await connection.close();
        }
      });

      test('still unusable, no refresh, or a broadcast that is gone: closed without a socket', () async {
        for (final (args, reason) in [
          (
            _args(noSecurity: true, refresh: () async => _args(noSecurity: true)),
            DanmakuCloseReason.credentialsUnavailable,
          ),
          (_args(noSecurity: true), DanmakuCloseReason.credentialsUnavailable),
          (
            _args(noSecurity: true, refresh: () async => throw const StreamUnavailable('acfun')),
            DanmakuCloseReason.connectionFailed,
          ),
          (
            _args(noSecurity: true, refresh: () async => throw const RiskControl('acfun')),
            DanmakuCloseReason.credentialsUnavailable,
          ),
        ]) {
          final connector = _Connector();
          final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
          final events = _record(connection);
          await connection.connect(args);
          expect(connector.channels, isEmpty);
          expect((events.single as DanmakuClosed).reason, reason);
          expect(connection.status, DanmakuStatus.closed);
        }
      });

      test('close during the start refresh: nothing opens, nothing is reported', () async {
        final connector = _Connector();
        final completer = Completer<AcfunDanmakuArgs>();
        final connection = AcfunDanmakuConnection(connector: connector.call, policy: _quiet);
        final events = _record(connection);
        final connecting = connection.connect(_args(noSecurity: true, refresh: () => completer.future));
        await Future<void>.delayed(Duration.zero);
        await connection.close();
        completer.complete(_refreshed());
        await connecting;
        expect(connector.channels, isEmpty);
        expect(events, isEmpty);
      });
    });

    test('join timeouts: the first replaces the socket, the second in a row refreshes as well', () async {
      final connector = _Connector();
      var refreshes = 0;
      final connection = AcfunDanmakuConnection(
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(milliseconds: 30),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(
        _args(
          refresh: () async {
            refreshes++;
            return _refreshed();
          },
        ),
      );
      await _until(() => connector.channels.length == 2);
      expect(refreshes, 0);
      expect(_command(connector.channels.last.sent.single), 'Basic.Register');
      await _until(() => connector.channels.length == 3);
      expect(refreshes, 1);
      final third = connector.channels.last;
      expect(_command(third.sent.single, security: _security2), 'Basic.Register');
      await third.receive(_registerAnswer(security: _security2));
      await third.receive(_enterAck());
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(connector.channels, hasLength(3), reason: 'the join stopped the timer');
      await connection.close();
    });

    test('close: no events and no frames afterwards', () async {
      final connector = _Connector();
      final (connection, events) = await _joined(connector);
      final channel = connector.channels.single;
      await connection.close();
      expect(connection.status, DanmakuStatus.idle);
      expect(channel.closed, isTrue);
      final count = events.length;
      connection.heartbeat();
      expect(events, hasLength(count));
      await connection.close();
    });

    test('a real local WebSocket server: handshake headers, register, enter, chat and heartbeats', () async {
      final seen = <String>[];
      final handshake = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        handshake['user-agent'] = request.headers.value('user-agent');
        handshake['origin'] = request.headers.value('origin');
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((frame) {
          final command = _command(frame as List<int>);
          seen.add(command);
          if (command == 'Basic.Register') socket.add(_registerAnswer());
          if (command == 'Global.ZtLiveInteractive.CsCmd' && _roomCommand(frame).$1 == 'ZtLiveCsEnterRoom') {
            socket
              ..add(_enterAck())
              ..add(_chat('弹幕'));
          }
        });
      });
      addTearDown(() => server.close(force: true));
      final local = Uri.parse('ws://127.0.0.1:${server.port}/');
      final connection = AcfunDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, AcfunDanmakuProtocol.endpoint);
          return connectIoSocket(
            local,
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
        policy: const DanmakuSocketPolicy(heartbeatInterval: Duration(milliseconds: 20)),
      );
      final events = _record(connection);
      await connection.connect(_args());
      await _until(
        () => _texts(events).isNotEmpty && seen.where((c) => c == 'Global.ZtLiveInteractive.CsCmd').length >= 3,
      );
      // dart:io's handshake keeps its own user agent in front of the one
      // given (the server accepted it live on 2026-09-29).
      expect(handshake['user-agent'], endsWith(AcfunApi.userAgent));
      expect(handshake['origin'], 'https://live.acfun.cn');
      expect(events.first, const DanmakuReady());
      expect(_texts(events), ['弹幕']);
      expect(seen.take(3), ['Basic.Register', 'Basic.KeepAlive', 'Global.ZtLiveInteractive.CsCmd']);
      await _until(() => seen.contains('Push.ZtLiveInteractive.Message'));
      await connection.close();
    });
  });
}
