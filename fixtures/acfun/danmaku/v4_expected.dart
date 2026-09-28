// Writes fixtures/acfun/danmaku/S07-live/expected.json: what the archived v4
// AcFun chat decoder read from every received frame of the recording
// (docs/modules/M5.9-acfun.md, "与归档 v4 的对照"). 3.x had no AcFun danmaku,
// and pure_live_TV has none either (`EmptyDanmaku`), so the archived v4 is
// the only earlier implementation; it recorded this sample itself.
//
// Below the harness, the code is copied verbatim from archive/v4 (6ba709135):
//
// - packages/live_danmaku/lib/src/sites/acfun.dart, from AcfunChatSession to
//   the end of AcfunLink (the connector, which needs v4's socket runtime, is
//   left out);
// - packages/live_danmaku/lib/src/codec/protobuf.dart and codec/aes.dart
//   without their imports.
//
// Only what they import from elsewhere is stubbed here: v4's `DanmakuEvent`
// types (DanmakuChat, DanmakuGift, DanmakuOnline) with the fields the decoder
// sets, `AudienceKind`, `DecodeContext`, `@immutable`, and `jsonInt`,
// `jsonString`, `jsonUrl`, `parseChineseCount` copied from v4's
// packages/live_core/lib/src/text.dart.
//
// The harness builds v4's `AcfunChatSession` from the recorded HTTP start
// (visitor/login, startPlay, gift/list, as v4's connector did; the device id
// is the `did` of the recorded startPlay URL) and one `AcfunLink`, then reads
// every received link frame in order: the packet (command, sequence id,
// error code), the answer of a room command (type, code, the enter-room
// heartbeat) and the events of a push (projected), with its ticket and
// broadcast flags.
//
// Run from the repository root:
//
//   dart run fixtures/acfun/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sample = 'fixtures/acfun/danmaku/S07-live';
const _generator =
    'archived v4 AcfunLink.read, AcfunProtocol.ack/heartbeatOf/push (archive/v4 6ba709135) over every received link '
    'frame, one link for the recorded session (fixtures/acfun/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
  ];
  Map<String, dynamic> http(String path) => lines.firstWhere(
    (line) => line['url'] != null && Uri.parse(line['url'] as String).path.endsWith(path),
  );
  final visitor = AcfunProtocol.visitor(http('/visitor/login')['text'] as String);
  final startPlay = http('/startPlay');
  final play = AcfunProtocol.startPlay(startPlay['text'] as String)!;
  final gifts = AcfunProtocol.gifts(http('/gift/list')['text'] as String);
  final session = AcfunChatSession(
    userId: visitor.userId,
    token: visitor.token,
    security: visitor.security,
    deviceId: Uri.parse(startPlay['url'] as String).queryParameters['did']!,
    liveId: play.liveId,
    tickets: play.tickets,
    attach: play.attach,
  );
  final link = AcfunLink(session);
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in' || line['b64'] == null) continue;
    final packet = link.read(base64.decode(line['b64'] as String));
    final frame = <String, Object?>{
      'line': index + 1,
      'command': packet.command,
      'seqId': packet.seqId,
      'errorCode': packet.errorCode,
    };
    if (packet.command == AcfunProtocol.register) frame['registered'] = link.registered;
    if (packet.command == AcfunProtocol.roomCommand) {
      final ack = AcfunProtocol.ack(packet.payload);
      frame['ack'] = {
        'type': ack.type,
        'code': ack.code,
        if (ack.type == 'ZtLiveCsEnterRoomAck') 'heartbeatMs': AcfunProtocol.heartbeatOf(ack.payload)?.inMilliseconds,
      };
    }
    if (packet.command == AcfunProtocol.message) {
      final context = DecodeContext(
        room: 'acfun:${visitor.userId}',
        session: 1,
        receivedAt: line['t'] as int,
        now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      final push = AcfunProtocol.push(packet.payload, context, gifts: gifts);
      frame['events'] = [for (final event in push.events) _project(event)];
      frame['ticketInvalid'] = push.ticketInvalid;
      frame['liveClosed'] = push.liveClosed;
    }
    frames.add(frame);
  }
  final expected = {
    'generator': _generator,
    'value': {
      'session': {
        'userId': '${session.userId}',
        'deviceId': session.deviceId,
        'liveId': session.liveId,
        'tickets': session.tickets,
        'attach': session.attach,
        'gifts': gifts.length,
      },
      'frames': frames,
    },
  };
  File('$_sample/expected.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(expected)}\n');
  stdout.writeln('wrote $_sample/expected.json: ${frames.length} frames');
}

Map<String, Object?> _project(DanmakuEvent event) => switch (event) {
  DanmakuChat() => {
    'type': 'chat',
    'userId': event.userId,
    'userName': event.userName,
    'text': event.text,
    'sentAt': event.sentAt?.millisecondsSinceEpoch,
  },
  DanmakuGift() => {
    'type': 'gift',
    'userId': event.userId,
    'userName': event.userName,
    'giftId': event.giftId,
    'giftName': event.giftName,
    'count': event.count,
    'sentAt': event.sentAt?.millisecondsSinceEpoch,
  },
  DanmakuOnline() => {'type': 'online', 'audience': event.audience.name, 'value': event.value},
};

// Stubs of what the v4 code imports ------------------------------------------

const immutable = _Immutable();

final class _Immutable {
  const _Immutable();
}

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt, required this.now});
  final String room;
  final int session;
  final int receivedAt;
  final DateTime now;
}

enum AudienceKind { popularity, online, cumulative }

sealed class DanmakuEvent {
  const DanmakuEvent({required this.room, required this.session, required this.receivedAt, this.sentAt});
  final String room;
  final int session;
  final int receivedAt;
  final DateTime? sentAt;
}

final class DanmakuChat extends DanmakuEvent {
  const DanmakuChat({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    super.sentAt,
    this.userId = '',
  });
  final String userName;
  final String text;
  final String userId;
}

final class DanmakuGift extends DanmakuEvent {
  const DanmakuGift({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.giftName,
    super.sentAt,
    this.userId = '',
    this.giftId = '',
    this.count = 1,
    this.icon,
  });
  final String userName;
  final String giftName;
  final String userId;
  final String giftId;
  final int count;
  final Uri? icon;
}

final class DanmakuOnline extends DanmakuEvent {
  const DanmakuOnline({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.audience,
    required this.value,
  });
  final AudienceKind audience;
  final int value;
}

// v4: packages/live_core/lib/src/text.dart (jsonInt, jsonString, jsonUrl, parseChineseCount)

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value == value.truncateToDouble() ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? jsonString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Uri? jsonUrl(Object? value) {
  final text = jsonString(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? uri : null;
}

int? parseChineseCount(Object? value) {
  if (value is int) return value;
  final text = jsonString(value)?.replaceAll(',', '');
  if (text == null) return null;
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(万|亿)?\+?$').firstMatch(text);
  if (match == null) return null;
  final number = double.parse(match.group(1)!);
  final scale = switch (match.group(2)) {
    '万' => 10000,
    '亿' => 100000000,
    _ => 1,
  };
  return (number * scale).round();
}

// v4: packages/live_danmaku/lib/src/sites/acfun.dart (AcfunChatSession ... AcfunLink) ---------------

/// The anonymous chat session AcFun's HTTP start hands out
/// (spec/sites/acfun.md §7.1).
@immutable
final class AcfunChatSession {
  /// Creates a session.
  const new({
    required this.userId,
    required this.token,
    required this.security,
    required this.deviceId,
    required this.liveId,
    required this.tickets,
    required this.attach,
  });

  /// The visitor's user id (`userId` of `visitor/login`).
  final int userId;

  /// The service token (`acfun.api.visitor_st`).
  final String token;

  /// `acSecurity`, base64-decoded: the AES key of the register exchange.
  final Uint8List security;

  /// The `_did` the visitor logged in with.
  final String deviceId;

  /// The broadcast (`startPlay` `liveId`).
  final String liveId;

  /// `availableTickets`: room tickets, tried in order.
  final List<String> tickets;

  /// `enterRoomAttach`, echoed in the enter-room command.
  final String attach;
}

/// A gift of the room's gift list (§7.5).
@immutable
final class AcfunGift {
  /// Creates a gift.
  const new({required this.name, this.icon});

  /// Display name.
  final String name;

  /// Picture.
  final Uri? icon;
}

/// One packet received on the link, decrypted.
@immutable
final class AcfunPacket {
  /// Creates a packet.
  const new({required this.command, required this.seqId, required this.payload, this.errorCode = 0, this.error = ''});

  /// `DownstreamPayload.command`, like `Basic.Register`.
  final String command;

  /// The header's sequence id (push acknowledgements echo it).
  final int seqId;

  /// `payloadData`.
  final Uint8List payload;

  /// `errorCode`; zero is success.
  final int errorCode;

  /// `errorMsg`.
  final String error;
}

/// What one push message carried.
typedef AcfunPush = ({List<DanmakuEvent> events, bool ticketInvalid, bool liveClosed});

/// AcFun's chat link (spec/sites/acfun.md §7), without I/O: the HTTP start,
/// the framing and the push decoding. The per-socket codec state lives in
/// [AcfunLink].
abstract final class AcfunProtocol {
  /// The link server (§7.2).
  static final Uri endpoint = Uri.parse('wss://link.xiatou.com/');

  /// Browser user agent for the HTTP start and the handshake.
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Handshake headers.
  static const Map<String, String> headers = {'User-Agent': userAgent, 'Origin': 'https://live.acfun.cn'};

  /// Link application id.
  static const appId = 13;

  /// Product name.
  static const kpn = 'ACFUN_APP';

  /// Product flavour.
  static const kpf = 'PC_WEB';

  /// Business line.
  static const subBiz = 'mainApp';

  /// Live SDK version the web client reports.
  static const sdkVersion = 'kwai-acfun-live-link';

  /// Frame magic, big-endian.
  static const magic = 0xABCD;

  /// Register command.
  static const register = 'Basic.Register';

  /// Keep-alive command.
  static const keepAlive = 'Basic.KeepAlive';

  /// Room command (enter room, heartbeat).
  static const roomCommand = 'Global.ZtLiveInteractive.CsCmd';

  /// Room messages.
  static const message = 'Push.ZtLiveInteractive.Message';

  /// Keep-alive period (`heartBeatInterval: 5e4`).
  static const keepAliveInterval = Duration(seconds: 50);

  /// Room heartbeat until the enter-room answer names one (§7.3).
  static const defaultHeartbeat = Duration(seconds: 10);

  /// `visitor/login`, a form POST with `sid=acfun.api.visitor`.
  static final Uri visitorUrl = Uri.https('id.app.acfun.cn', '/rest/app/visitor/login');

  /// `startPlay`, a form POST with `authorId` and `pullStreamType`.
  static Uri startPlayUrl({required int userId, required String deviceId, required String token}) =>
      _zt('/rest/zt/live/web/startPlay', userId: userId, deviceId: deviceId, token: token);

  /// `gift/list`, a form POST with `visitorId` and `liveId`.
  static Uri giftListUrl({required int userId, required String deviceId, required String token}) =>
      _zt('/rest/zt/live/web/gift/list', userId: userId, deviceId: deviceId, token: token);

  static Uri _zt(String path, {required int userId, required String deviceId, required String token}) => Uri.https(
    'api.kuaishouzt.com',
    path,
    {'subBiz': subBiz, 'kpn': kpn, 'kpf': kpf, 'userId': '$userId', 'did': deviceId, 'acfun.api.visitor_st': token},
  );

  /// A web device id: `web_` and 16 letters or digits.
  static String deviceId(Random random) {
    const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return 'web_${List.generate(16, (_) => letters[random.nextInt(letters.length)]).join()}';
  }

  /// `visitor/login`; throws [FormatException] unless `result == 0` with a
  /// complete session.
  static ({int userId, String token, Uint8List security}) visitor(String body) {
    final root = jsonDecode(body);
    if (root is! Map || jsonInt(root['result']) != 0) throw const FormatException('AcFun visitor/login refused');
    final userId = jsonInt(root['userId']);
    final token = jsonString(root['acfun.api.visitor_st']);
    final security = jsonString(root['acSecurity']);
    if (userId == null || token == null || security == null) {
      throw const FormatException('AcFun visitor/login: incomplete session');
    }
    return (userId: userId, token: token, security: base64.decode(security));
  }

  /// `startPlay`: the room tickets; null when the room is not live (result
  /// 129004); throws [FormatException] for any other refusal.
  static ({String liveId, List<String> tickets, String attach})? startPlay(String body) {
    final root = jsonDecode(body);
    if (root is! Map) throw const FormatException('AcFun startPlay: not an object');
    final result = jsonInt(root['result']);
    if (result == 129004) return null;
    final data = root['data'];
    if (result != 1 || data is! Map) throw FormatException('AcFun startPlay result $result');
    final liveId = jsonString(data['liveId']);
    final tickets = [
      for (final ticket in data['availableTickets'] is List ? data['availableTickets'] as List : const [])
        ?jsonString(ticket),
    ];
    if (liveId == null || tickets.isEmpty) throw const FormatException('AcFun startPlay: no liveId or tickets');
    return (liveId: liveId, tickets: tickets, attach: jsonString(data['enterRoomAttach']) ?? '');
  }

  /// `gift/list`: names and pictures by gift id; empty when the answer is
  /// not a list.
  static Map<int, AcfunGift> gifts(String body) {
    final root = jsonDecode(body);
    final data = root is Map ? root['data'] : null;
    final list = data is Map ? data['giftList'] : null;
    return {
      for (final item in list is List ? list : const [])
        if (item is Map)
          if ((jsonInt(item['giftId']), jsonString(item['giftName'])) case (final int id, final String name))
            id: AcfunGift(name: name, icon: _picture(item['webpPicList']) ?? _picture(item['pngPicList'])),
    };
  }

  static Uri? _picture(Object? list) =>
      list is List && list.isNotEmpty && list.first is Map ? jsonUrl((list.first as Map)['url']) : null;

  /// Wraps an encoded header and payload: magic, version 1, the two lengths
  /// (big-endian), then the bytes (§7.2).
  static Uint8List frame(List<int> header, List<int> payload) {
    final out = Uint8List(12 + header.length + payload.length);
    ByteData.sublistView(out)
      ..setUint16(0, magic)
      ..setUint16(2, 1)
      ..setUint32(4, header.length)
      ..setUint32(8, payload.length);
    out
      ..setAll(12, header)
      ..setAll(12 + header.length, payload);
    return out;
  }

  /// Splits [bytes] into header and (still encrypted) payload; throws
  /// [FormatException] when the lengths do not add up.
  static ({ProtoMessage header, Uint8List payload}) unframe(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (data.length < 12) throw const FormatException('AcFun frame shorter than its prefix');
    final view = ByteData.sublistView(data);
    if (view.getUint16(0) != magic) throw const FormatException('AcFun frame without magic');
    final headerLength = view.getUint32(4);
    final payloadLength = view.getUint32(8);
    if (12 + headerLength + payloadLength != data.length) throw const FormatException('AcFun frame size mismatch');
    return (
      header: ProtoMessage.decode(Uint8List.sublistView(data, 12, 12 + headerLength)),
      payload: Uint8List.sublistView(data, 12 + headerLength),
    );
  }

  /// Encrypts [plain] under [key]: a random IV, then the CBC ciphertext.
  static Uint8List seal(List<int> plain, List<int> key, Random random) {
    final iv = Uint8List.fromList(List.generate(AesCbc.blockSize, (_) => random.nextInt(256)));
    return Uint8List.fromList([...iv, ...AesCbc(key).encrypt(plain, iv)]);
  }

  /// Decrypts a [seal]ed payload.
  static Uint8List open(List<int> sealed, List<int> key) {
    if (sealed.length < 2 * AesCbc.blockSize) throw const FormatException('AcFun payload shorter than two blocks');
    return AesCbc(key).decrypt(sealed.sublist(AesCbc.blockSize), sealed.sublist(0, AesCbc.blockSize));
  }

  /// `ZtLiveCsCmdAck`: the answered command, its error code and payload.
  static ({String type, int code, Uint8List payload}) ack(List<int> payload) {
    final message = ProtoMessage.decode(payload);
    return (type: message.string(1) ?? '', code: message.integer(2) ?? 0, payload: message.bytes(4) ?? Uint8List(0));
  }

  /// `ZtLiveCsEnterRoomAck.heartbeatIntervalMs`; null when absent or zero.
  static Duration? heartbeatOf(List<int> payload) {
    final millis = ProtoMessage.decode(payload).integer(1) ?? 0;
    return millis > 0 ? Duration(milliseconds: millis) : null;
  }

  /// §7.4 one `Push.ZtLiveInteractive.Message`: comments, gifts, the
  /// audience figure; room notices as flags.
  static AcfunPush push(List<int> payload, DecodeContext context, {Map<int, AcfunGift> gifts = const {}}) {
    final message = ProtoMessage.decode(payload);
    var body = message.bytes(3) ?? Uint8List(0);
    if (message.integer(2) == 2) body = Uint8List.fromList(gzip.decode(body));
    final events = <DanmakuEvent>[];
    switch (message.string(1)) {
      case 'ZtLiveScActionSignal':
        for (final item in ProtoMessage.decode(body).messages(1)) {
          final type = item.string(1);
          for (final field in item.fields) {
            if (field.number != 2 || field.value is! Uint8List) continue;
            final event = _action(type, field.value as Uint8List, context, gifts);
            if (event != null) events.add(event);
          }
        }
      case 'ZtLiveScStateSignal':
        for (final item in ProtoMessage.decode(body).messages(1)) {
          if (item.string(1) != 'CommonStateSignalDisplayInfo') continue;
          final watching = parseChineseCount(ProtoMessage.decode(item.bytes(2) ?? const []).string(1));
          if (watching == null) continue;
          events.add(
            DanmakuOnline(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              audience: AudienceKind.online,
              value: watching,
            ),
          );
        }
      case 'ZtLiveScTicketInvalid':
        return (events: events, ticketInvalid: true, liveClosed: false);
      case 'ZtLiveScStatusChanged':
        return (events: events, ticketInvalid: false, liveClosed: ProtoMessage.decode(body).integer(1) == 1);
    }
    return (events: events, ticketInvalid: false, liveClosed: false);
  }

  static DanmakuEvent? _action(String? type, Uint8List payload, DecodeContext context, Map<int, AcfunGift> gifts) {
    final signal = ProtoMessage.decode(payload);
    switch (type) {
      case 'CommonActionSignalComment':
        final text = signal.string(1) ?? '';
        final user = signal.message(3);
        if (text.isEmpty || user == null) return null;
        return DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          sentAt: _time(signal.integer(2)),
          userId: _id(user.integer(1)),
          userName: user.string(2) ?? '',
          text: text,
        );
      case 'CommonActionSignalGift':
        final user = signal.message(1);
        final id = signal.integer(3);
        final gift = gifts[id];
        if (user == null || id == null || gift == null) return null;
        final batch = signal.integer(4) ?? 1;
        return DanmakuGift(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          sentAt: _time(signal.integer(2)),
          userId: _id(user.integer(1)),
          userName: user.string(2) ?? '',
          giftId: '$id',
          giftName: gift.name,
          count: batch > 0 ? batch : 1,
          icon: gift.icon,
        );
      case 'AcfunActionSignalThrowBanana':
        final user = signal.message(1);
        if (user == null) return null;
        final count = signal.integer(2) ?? 1;
        return DanmakuGift(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          sentAt: _time(signal.integer(3)),
          userId: _id(user.integer(1)),
          userName: user.string(2) ?? '',
          giftId: '1',
          giftName: gifts[1]?.name ?? '香蕉',
          count: count > 0 ? count : 1,
          icon: gifts[1]?.icon,
        );
    }
    return null;
  }

  static String _id(int? id) => id == null || id <= 0 ? '' : '$id';

  static DateTime? _time(int? millis) =>
      millis == null || millis <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

/// The encrypted link of one socket (§7.2, §7.3): sequence numbers, the
/// register key and the session key the register answer brings.
final class AcfunLink {
  /// Starts a link for [session]; [random] draws the IVs.
  new(this.session, {Random? random}) : _random = random ?? Random.secure();

  /// The HTTP session.
  final AcfunChatSession session;

  final Random _random;
  var _seq = 1;
  var _instanceId = 0;
  Uint8List? _sessionKey;

  /// Whether the register answer arrived.
  bool get registered => _sessionKey != null;

  /// Register (`Basic.Register`), sealed with `acSecurity` and carrying the
  /// service token in the header.
  List<int> register() {
    final request = ProtoWriter()
      ..bytes(
        1,
        (ProtoWriter()
              ..string(1, 'link-sdk')
              ..string(4, '1.2.1'))
            .toBytes(),
      )
      ..bytes(
        2,
        (ProtoWriter()
              ..integer(1, 6)
              ..string(3, 'h5')
              ..string(5, session.deviceId))
            .toBytes(),
      )
      ..integer(4, 1)
      ..integer(5, 1)
      ..integer(8, 0)
      ..bytes(
        11,
        (ProtoWriter()
              ..string(1, AcfunProtocol.kpn)
              ..string(2, AcfunProtocol.kpf)
              ..integer(4, session.userId)
              ..string(5, session.deviceId))
            .toBytes(),
      );
    return _send(AcfunProtocol.register, request.toBytes(), serviceToken: true);
  }

  /// `Basic.KeepAlive`: present and in the foreground.
  List<int> keepAlive() => _send(
    AcfunProtocol.keepAlive,
    (ProtoWriter()
          ..integer(1, 1)
          ..integer(2, 1))
        .toBytes(),
  );

  /// Enter the room with ticket [ticket] (an index into the session's
  /// tickets); [reconnects] counts earlier attempts.
  List<int> enterRoom({int ticket = 0, int reconnects = 0}) {
    final enter = ProtoWriter()
      ..integer(1, 0)
      ..integer(2, reconnects)
      ..string(4, session.attach)
      ..string(5, AcfunProtocol.sdkVersion);
    return _command('ZtLiveCsEnterRoom', enter.toBytes(), ticket);
  }

  /// The room heartbeat number [sequence], stamped [now].
  List<int> heartbeat({required int sequence, required DateTime now, int ticket = 0}) => _command(
    'ZtLiveCsHeartbeat',
    (ProtoWriter()
          ..integer(1, now.millisecondsSinceEpoch)
          ..integer(2, sequence))
        .toBytes(),
    ticket,
  );

  /// The acknowledgement every push gets: the push's command and sequence
  /// id, no payload.
  List<int> pushAck(AcfunPacket push) => _send(push.command, null, headerSeq: push.seqId, advance: false);

  List<int> _command(String type, List<int> payload, int ticket) {
    final tickets = session.tickets;
    final command = ProtoWriter()
      ..string(1, type)
      ..bytes(2, payload)
      ..string(3, tickets.isEmpty ? '' : tickets[ticket % tickets.length])
      ..string(4, session.liveId);
    return _send(AcfunProtocol.roomCommand, command.toBytes());
  }

  List<int> _send(String command, List<int>? data, {bool serviceToken = false, int? headerSeq, bool advance = true}) {
    final upstream = ProtoWriter()
      ..string(1, command)
      ..integer(2, _seq)
      ..integer(3, 1);
    if (data != null) upstream.bytes(4, data);
    upstream.string(9, AcfunProtocol.subBiz);
    final plain = upstream.toBytes();
    final key = serviceToken ? session.security : _sessionKey;
    if (key == null) throw StateError('AcFun link: $command before the register answer');
    final header = ProtoWriter()
      ..integer(1, AcfunProtocol.appId)
      ..integer(2, session.userId)
      ..integer(3, _instanceId)
      ..integer(7, plain.length)
      ..integer(8, serviceToken ? 1 : 2);
    if (serviceToken) {
      header.bytes(
        9,
        (ProtoWriter()
              ..integer(1, 1)
              ..bytes(2, [for (final unit in session.token.codeUnits) unit & 0xFF]))
            .toBytes(),
      );
    }
    header
      ..integer(10, headerSeq ?? _seq)
      ..string(12, AcfunProtocol.kpn);
    if (advance) _seq++;
    return AcfunProtocol.frame(header.toBytes(), AcfunProtocol.seal(plain, key, _random));
  }

  /// Decodes one received frame; the register answer's session key is kept
  /// for everything after it. Throws [FormatException] on a frame that does
  /// not decode (a wrong key included).
  AcfunPacket read(List<int> frame) {
    final (:header, :payload) = AcfunProtocol.unframe(frame);
    final plain = switch (header.integer(8) ?? 0) {
      0 => payload,
      1 => AcfunProtocol.open(payload, session.security),
      2 => AcfunProtocol.open(payload, _sessionKey ?? (throw const FormatException('AcFun: no session key yet'))),
      final mode => throw FormatException('AcFun: encryption mode $mode'),
    };
    final down = ProtoMessage.decode(plain);
    final packet = AcfunPacket(
      command: down.string(1) ?? '',
      seqId: header.integer(10) ?? 0,
      payload: down.bytes(4) ?? Uint8List(0),
      errorCode: down.integer(3) ?? 0,
      error: down.string(5) ?? '',
    );
    if (packet.command == AcfunProtocol.register && packet.errorCode == 0) {
      final answer = ProtoMessage.decode(packet.payload);
      final key = answer.bytes(2);
      if (key != null && key.isNotEmpty) _sessionKey = Uint8List.fromList(key);
      _instanceId = answer.integer(3) ?? 0;
    }
    return packet;
  }
}

// v4: packages/live_danmaku/lib/src/codec/protobuf.dart ----------------------------------------------

/// One protobuf field as it appeared on the wire.
@immutable
final class ProtoField {
  /// Creates a field.
  const new(this.number, this.wireType, this.value);

  /// Field number.
  final int number;

  /// Wire type: 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32.
  final int wireType;

  /// `int` for varint and fixed types, [Uint8List] for length-delimited.
  final Object value;
}

/// A protobuf message decoded without a schema: the fields in wire order
/// (docs/adr/0019-danmaku-layer.md: a hand-written reader of the few fields the
/// connectors need instead of generated classes).
@immutable
final class ProtoMessage {
  /// Wraps [fields].
  const new(this.fields);

  /// Decodes [bytes]; throws [FormatException] on truncated or group fields.
  factory decode(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final fields = <ProtoField>[];
    var offset = 0;
    int varint() {
      var result = 0;
      for (var shift = 0; shift < 64; shift += 7) {
        if (offset >= data.length) throw const FormatException('Truncated varint');
        final byte = data[offset++];
        result |= (byte & 0x7F) << shift;
        if (byte < 0x80) return result;
      }
      throw const FormatException('Varint longer than 10 bytes');
    }

    int fixed(int size) {
      if (offset + size > data.length) throw const FormatException('Truncated fixed field');
      final view = ByteData.sublistView(data, offset, offset + size);
      offset += size;
      return size == 8 ? view.getInt64(0, Endian.little) : view.getUint32(0, Endian.little);
    }

    while (offset < data.length) {
      final key = varint();
      final number = key >>> 3;
      final wireType = key & 7;
      if (number == 0) throw const FormatException('Field number 0');
      switch (wireType) {
        case 0:
          fields.add(ProtoField(number, 0, varint()));
        case 1:
          fields.add(ProtoField(number, 1, fixed(8)));
        case 2:
          final length = varint();
          if (length < 0 || offset + length > data.length) throw const FormatException('Truncated bytes field');
          fields.add(ProtoField(number, 2, Uint8List.sublistView(data, offset, offset + length)));
          offset += length;
        case 5:
          fields.add(ProtoField(number, 5, fixed(4)));
        default:
          throw FormatException('Unsupported wire type $wireType');
      }
    }
    return ProtoMessage(fields);
  }

  /// Fields in wire order.
  final List<ProtoField> fields;

  ProtoField? _last(int number) {
    for (var i = fields.length - 1; i >= 0; i--) {
      if (fields[i].number == number) return fields[i];
    }
    return null;
  }

  /// The last varint or fixed value of [number]; null when absent.
  int? integer(int number) => switch (_last(number)?.value) {
    final int value => value,
    _ => null,
  };

  /// Whether [number] is a true bool.
  bool flag(int number) => (integer(number) ?? 0) != 0;

  /// The last length-delimited value of [number].
  Uint8List? bytes(int number) => switch (_last(number)?.value) {
    final Uint8List value => value,
    _ => null,
  };

  /// The last value of [number] as UTF-8 text; malformed bytes become U+FFFD.
  String? string(int number) {
    final value = bytes(number);
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }

  /// The last value of [number] as a nested message.
  ProtoMessage? message(int number) {
    final value = bytes(number);
    return value == null ? null : ProtoMessage.decode(value);
  }

  /// Every value of a repeated [number], as nested messages.
  Iterable<ProtoMessage> messages(int number) sync* {
    for (final field in fields) {
      if (field.number == number && field.value is Uint8List) yield ProtoMessage.decode(field.value as Uint8List);
    }
  }
}

/// Writes protobuf fields in call order.
final class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void _varint(int value) {
    var rest = value;
    while (true) {
      final byte = rest & 0x7F;
      rest >>>= 7;
      if (rest == 0) {
        _out.addByte(byte);
        return;
      }
      _out.addByte(byte | 0x80);
    }
  }

  /// A varint field (int, uint, bool, enum).
  void integer(int number, int value) {
    _varint(number << 3);
    _varint(value);
  }

  /// A length-delimited field.
  void bytes(int number, List<int> value) {
    _varint(number << 3 | 2);
    _varint(value.length);
    _out.add(value);
  }

  /// A UTF-8 string field.
  void string(int number, String value) => bytes(number, utf8.encode(value));

  /// Copies [field] as it was read.
  void field(ProtoField field) {
    switch (field.value) {
      case final Uint8List value:
        bytes(field.number, value);
      case final int value when field.wireType == 0:
        integer(field.number, value);
      case final int value:
        _varint(field.number << 3 | field.wireType);
        final size = field.wireType == 1 ? 8 : 4;
        final data = ByteData(size);
        if (size == 8) {
          data.setInt64(0, value, Endian.little);
        } else {
          data.setUint32(0, value, Endian.little);
        }
        _out.add(data.buffer.asUint8List());
    }
  }

  /// The encoded message.
  Uint8List toBytes() => _out.toBytes();
}

// v4: packages/live_danmaku/lib/src/codec/aes.dart ---------------------------------------------------

/// AES (FIPS-197) in CBC mode with PKCS#7 padding (NIST SP 800-38A), for
/// AcFun's chat link (spec/sites/acfun.md §7). It is the only cipher a chat
/// protocol needs, so it lives here instead of adding a dependency.
///
/// Not constant-time: it protects nothing on this device, it only speaks
/// the platform's wire format.
final class AesCbc {
  /// Expands [key] (16, 24 or 32 bytes); throws [ArgumentError] otherwise.
  factory(List<int> key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'AES keys are 16, 24 or 32 bytes');
    }
    _Tables.ready();
    final words = key.length ~/ 4;
    final rounds = words + 6;
    final total = 4 * (rounds + 1);
    final encrypt = Uint32List(total);
    for (var i = 0; i < words; i++) {
      encrypt[i] = key[4 * i] << 24 | key[4 * i + 1] << 16 | key[4 * i + 2] << 8 | key[4 * i + 3];
    }
    var rcon = 1;
    for (var i = words; i < total; i++) {
      var t = encrypt[i - 1];
      if (i % words == 0) {
        t = _subWord(t << 8 & 0xFFFFFFFF | t >>> 24) ^ rcon << 24;
        rcon = _xtime(rcon);
      } else if (words > 6 && i % words == 4) {
        t = _subWord(t);
      }
      encrypt[i] = encrypt[i - words] ^ t;
    }
    // The equivalent inverse cipher: round keys in reverse order, the inner
    // ones through InvMixColumns.
    final decrypt = Uint32List(total);
    for (var round = 0; round <= rounds; round++) {
      for (var column = 0; column < 4; column++) {
        final word = encrypt[4 * (rounds - round) + column];
        decrypt[4 * round + column] = round == 0 || round == rounds
            ? word
            : _Tables.dec0[_Tables.sbox[word >>> 24]] ^
                  _Tables.dec1[_Tables.sbox[word >>> 16 & 0xFF]] ^
                  _Tables.dec2[_Tables.sbox[word >>> 8 & 0xFF]] ^
                  _Tables.dec3[_Tables.sbox[word & 0xFF]];
      }
    }
    return AesCbc._(rounds, encrypt, decrypt);
  }

  new _(this._rounds, this._encryptKeys, this._decryptKeys);

  /// Block size in bytes.
  static const blockSize = 16;

  final int _rounds;
  final Uint32List _encryptKeys;
  final Uint32List _decryptKeys;

  /// Pads [plain] (PKCS#7) and encrypts it under [iv]; the result holds the
  /// ciphertext only.
  Uint8List encrypt(List<int> plain, List<int> iv) {
    _checkIv(iv);
    final pad = blockSize - plain.length % blockSize;
    final out = Uint8List(plain.length + pad)
      ..setAll(0, plain)
      ..fillRange(plain.length, plain.length + pad, pad);
    final state = Uint32List(4);
    _load(iv, 0, state);
    final block = Uint32List(4);
    for (var offset = 0; offset < out.length; offset += blockSize) {
      _load(out, offset, block);
      for (var i = 0; i < 4; i++) {
        state[i] ^= block[i];
      }
      _encryptBlock(state);
      _store(state, out, offset);
    }
    return out;
  }

  /// Decrypts [cipher] under [iv] and removes the padding; throws
  /// [FormatException] on a partial block or bad padding (a wrong key).
  Uint8List decrypt(List<int> cipher, List<int> iv) {
    _checkIv(iv);
    if (cipher.isEmpty || cipher.length % blockSize != 0) {
      throw FormatException('AES-CBC: ${cipher.length} bytes is not whole blocks');
    }
    final out = Uint8List(cipher.length);
    final previous = Uint32List(4);
    _load(iv, 0, previous);
    final block = Uint32List(4);
    final next = Uint32List(4);
    for (var offset = 0; offset < cipher.length; offset += blockSize) {
      _load(cipher, offset, block);
      next.setAll(0, block);
      _decryptBlock(block);
      for (var i = 0; i < 4; i++) {
        block[i] ^= previous[i];
      }
      _store(block, out, offset);
      previous.setAll(0, next);
    }
    final pad = out.last;
    if (pad < 1 || pad > blockSize) throw const FormatException('AES-CBC: bad padding');
    for (var i = out.length - pad; i < out.length; i++) {
      if (out[i] != pad) throw const FormatException('AES-CBC: bad padding');
    }
    return Uint8List.sublistView(out, 0, out.length - pad);
  }

  void _encryptBlock(Uint32List s) {
    final k = _encryptKeys;
    var s0 = s[0] ^ k[0];
    var s1 = s[1] ^ k[1];
    var s2 = s[2] ^ k[2];
    var s3 = s[3] ^ k[3];
    final e0 = _Tables.enc0;
    final e1 = _Tables.enc1;
    final e2 = _Tables.enc2;
    final e3 = _Tables.enc3;
    for (var round = 1; round < _rounds; round++) {
      final r = 4 * round;
      final t0 = e0[s0 >>> 24] ^ e1[s1 >>> 16 & 0xFF] ^ e2[s2 >>> 8 & 0xFF] ^ e3[s3 & 0xFF] ^ k[r];
      final t1 = e0[s1 >>> 24] ^ e1[s2 >>> 16 & 0xFF] ^ e2[s3 >>> 8 & 0xFF] ^ e3[s0 & 0xFF] ^ k[r + 1];
      final t2 = e0[s2 >>> 24] ^ e1[s3 >>> 16 & 0xFF] ^ e2[s0 >>> 8 & 0xFF] ^ e3[s1 & 0xFF] ^ k[r + 2];
      final t3 = e0[s3 >>> 24] ^ e1[s0 >>> 16 & 0xFF] ^ e2[s1 >>> 8 & 0xFF] ^ e3[s2 & 0xFF] ^ k[r + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final r = 4 * _rounds;
    final box = _Tables.sbox;
    s[0] = _last(box, s0, s1, s2, s3) ^ k[r];
    s[1] = _last(box, s1, s2, s3, s0) ^ k[r + 1];
    s[2] = _last(box, s2, s3, s0, s1) ^ k[r + 2];
    s[3] = _last(box, s3, s0, s1, s2) ^ k[r + 3];
  }

  void _decryptBlock(Uint32List s) {
    final k = _decryptKeys;
    var s0 = s[0] ^ k[0];
    var s1 = s[1] ^ k[1];
    var s2 = s[2] ^ k[2];
    var s3 = s[3] ^ k[3];
    final d0 = _Tables.dec0;
    final d1 = _Tables.dec1;
    final d2 = _Tables.dec2;
    final d3 = _Tables.dec3;
    for (var round = 1; round < _rounds; round++) {
      final r = 4 * round;
      final t0 = d0[s0 >>> 24] ^ d1[s3 >>> 16 & 0xFF] ^ d2[s2 >>> 8 & 0xFF] ^ d3[s1 & 0xFF] ^ k[r];
      final t1 = d0[s1 >>> 24] ^ d1[s0 >>> 16 & 0xFF] ^ d2[s3 >>> 8 & 0xFF] ^ d3[s2 & 0xFF] ^ k[r + 1];
      final t2 = d0[s2 >>> 24] ^ d1[s1 >>> 16 & 0xFF] ^ d2[s0 >>> 8 & 0xFF] ^ d3[s3 & 0xFF] ^ k[r + 2];
      final t3 = d0[s3 >>> 24] ^ d1[s2 >>> 16 & 0xFF] ^ d2[s1 >>> 8 & 0xFF] ^ d3[s0 & 0xFF] ^ k[r + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final r = 4 * _rounds;
    final box = _Tables.inverse;
    s[0] = _last(box, s0, s3, s2, s1) ^ k[r];
    s[1] = _last(box, s1, s0, s3, s2) ^ k[r + 1];
    s[2] = _last(box, s2, s1, s0, s3) ^ k[r + 2];
    s[3] = _last(box, s3, s2, s1, s0) ^ k[r + 3];
  }

  static int _last(Uint8List box, int a, int b, int c, int d) =>
      box[a >>> 24] << 24 | box[b >>> 16 & 0xFF] << 16 | box[c >>> 8 & 0xFF] << 8 | box[d & 0xFF];

  static void _checkIv(List<int> iv) {
    if (iv.length != blockSize) throw ArgumentError.value(iv.length, 'iv', 'the IV is one 16-byte block');
  }

  static void _load(List<int> bytes, int offset, Uint32List into) {
    for (var i = 0; i < 4; i++) {
      final at = offset + 4 * i;
      into[i] = bytes[at] << 24 | bytes[at + 1] << 16 | bytes[at + 2] << 8 | bytes[at + 3];
    }
  }

  static void _store(Uint32List words, Uint8List out, int offset) {
    for (var i = 0; i < 4; i++) {
      final word = words[i];
      final at = offset + 4 * i;
      out[at] = word >>> 24;
      out[at + 1] = word >>> 16;
      out[at + 2] = word >>> 8;
      out[at + 3] = word;
    }
  }

  static int _subWord(int word) {
    final box = _Tables.sbox;
    return box[word >>> 24] << 24 | box[word >>> 16 & 0xFF] << 16 | box[word >>> 8 & 0xFF] << 8 | box[word & 0xFF];
  }
}

/// Multiplication by x in GF(2^8).
int _xtime(int value) => (value << 1 ^ (value & 0x80 != 0 ? 0x1B : 0)) & 0xFF;

int _multiply(int a, int b) {
  var result = 0;
  var x = a;
  for (var y = b; y > 0; y >>= 1) {
    if (y & 1 != 0) result ^= x;
    x = _xtime(x);
  }
  return result;
}

/// S-boxes and round tables, built once from the field arithmetic instead
/// of pasted as literals.
abstract final class _Tables {
  static final sbox = Uint8List(256);
  static final inverse = Uint8List(256);
  static final enc0 = Uint32List(256);
  static final enc1 = Uint32List(256);
  static final enc2 = Uint32List(256);
  static final enc3 = Uint32List(256);
  static final dec0 = Uint32List(256);
  static final dec1 = Uint32List(256);
  static final dec2 = Uint32List(256);
  static final dec3 = Uint32List(256);
  static var _built = false;

  static int _rotate(int word) => word >>> 8 | (word & 0xFF) << 24;

  static int _rotateByte(int value, int by) => (value << by | value >>> (8 - by)) & 0xFF;

  static void ready() {
    if (_built) return;
    _built = true;
    // Walk the multiplicative group with generator 3: p runs over 3^k,
    // q over its inverse 3^-k, so q is the inverse of p.
    var p = 1;
    var q = 1;
    do {
      p = p ^ _xtime(p);
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xFF;
      if (q & 0x80 != 0) q ^= 0x09;
      sbox[p] = q ^ _rotateByte(q, 1) ^ _rotateByte(q, 2) ^ _rotateByte(q, 3) ^ _rotateByte(q, 4) ^ 0x63;
    } while (p != 1);
    sbox[0] = 0x63;
    for (var i = 0; i < 256; i++) {
      inverse[sbox[i]] = i;
    }
    for (var i = 0; i < 256; i++) {
      final s = sbox[i];
      final e = _multiply(s, 2) << 24 | s << 16 | s << 8 | _multiply(s, 3);
      enc0[i] = e;
      enc1[i] = _rotate(e);
      enc2[i] = _rotate(enc1[i]);
      enc3[i] = _rotate(enc2[i]);
      final v = inverse[i];
      final d = _multiply(v, 14) << 24 | _multiply(v, 9) << 16 | _multiply(v, 13) << 8 | _multiply(v, 11);
      dec0[i] = d;
      dec1[i] = _rotate(d);
      dec2[i] = _rotate(dec1[i]);
      dec3[i] = _rotate(dec2[i]);
    }
  }
}
