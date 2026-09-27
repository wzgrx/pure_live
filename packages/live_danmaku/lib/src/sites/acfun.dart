import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/aes.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

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

/// AcFun's chat connection (§7): visitor login and `startPlay` over HTTP,
/// then the encrypted link; 10 s room heartbeat, 50 s keep-alive, every push
/// acknowledged.
final class AcfunConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['author']` (or the room
  /// id) is the author.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy, Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  AcfunChatSession? _chat;
  Map<int, AcfunGift> _gifts = const {};

  /// Per-socket state: reset by every [openFrames].
  AcfunLink? _link;
  Duration _heartbeat = AcfunProtocol.defaultHeartbeat;
  var _sequence = 0;
  var _joined = false;
  DateTime? _keptAlive;

  String get _author => detail.danmakuKeys['author'] ?? room.roomId;

  Future<String> _post(Uri url, Map<String, String> fields, {Map<String, String> headers = const {}}) async {
    final response = await transport.http.send(
      LiveRequest.form(
        site: 'acfun',
        url: url,
        headers: {'user-agent': AcfunProtocol.userAgent, 'referer': 'https://live.acfun.cn/', ...headers},
        fields: fields,
        timeout: const Duration(seconds: 10),
      ),
    );
    if (!response.isSuccess) throw FormatException('AcFun ${url.path} HTTP ${response.status}');
    return response.text;
  }

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final author = _author;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(author)) throw const DanmakuStartFailure('noRoom', 'acfun author missing');
    Object? last;
    // A refused visitor session is replaced once, as the adapter does.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final deviceId = AcfunProtocol.deviceId(_random);
        final visitor = AcfunProtocol.visitor(
          await _post(
            AcfunProtocol.visitorUrl,
            const {'sid': 'acfun.api.visitor'},
            headers: {'cookie': '_did=$deviceId;'},
          ),
        );
        final query = (userId: visitor.userId, deviceId: deviceId, token: visitor.token);
        final play = AcfunProtocol.startPlay(
          await _post(AcfunProtocol.startPlayUrl(userId: query.userId, deviceId: query.deviceId, token: query.token), {
            'authorId': author,
            'pullStreamType': 'FLV',
          }),
        );
        if (play == null) throw const DanmakuStartFailure('noRoom', 'acfun room is not live');
        if (_gifts.isEmpty) {
          try {
            _gifts = AcfunProtocol.gifts(
              await _post(
                AcfunProtocol.giftListUrl(userId: query.userId, deviceId: query.deviceId, token: query.token),
                {'visitorId': '${visitor.userId}', 'liveId': play.liveId},
              ),
            );
          } on Object {
            // Gift names are optional; gifts without one are dropped.
          }
        }
        _chat = AcfunChatSession(
          userId: visitor.userId,
          token: visitor.token,
          security: visitor.security,
          deviceId: deviceId,
          liveId: play.liveId,
          tickets: play.tickets,
          attach: play.attach,
        );
        return SocketPlan(endpoints: [AcfunProtocol.endpoint], headers: AcfunProtocol.headers);
      } on DanmakuStartFailure {
        rethrow;
      } on Object catch (error) {
        last = error;
      }
    }
    throw DanmakuStartFailure('credentials', '$last');
  }

  @override
  List<List<int>> openFrames() {
    final chat = _chat;
    if (chat == null) return const [];
    final link = _link = AcfunLink(chat, random: _random);
    _heartbeat = AcfunProtocol.defaultHeartbeat;
    _sequence = 0;
    _joined = false;
    _keptAlive = null;
    return [link.register()];
  }

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get authTimeout => const Duration(seconds: 10);

  @override
  Duration get heartbeatInterval => _heartbeat;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => _link?.heartbeat(sequence: _sequence++, now: clock.now()) ?? const [];

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    final link = _link;
    if (data is! List<int> || link == null) return FrameResult.empty;
    final packet = link.read(data);
    switch (packet.command) {
      case AcfunProtocol.register:
        if (packet.errorCode != 0 || !link.registered) return const FrameResult(rejected: true);
        _keptAlive = context.now;
        return FrameResult(replies: [link.keepAlive(), link.enterRoom()]);
      case AcfunProtocol.roomCommand:
        if (packet.errorCode != 0) return const FrameResult(rejected: true);
        final ack = AcfunProtocol.ack(packet.payload);
        if (ack.code != 0) return const FrameResult(rejected: true);
        if (ack.type == 'ZtLiveCsEnterRoomAck') {
          if (_joined) return FrameResult.empty;
          _joined = true;
          _heartbeat = AcfunProtocol.heartbeatOf(ack.payload) ?? AcfunProtocol.defaultHeartbeat;
          return const FrameResult(joined: true);
        }
        // Checked at each heartbeat answer: half a heartbeat early keeps the
        // 50 s period instead of rounding it up to the next heartbeat.
        final since = _keptAlive;
        final due = AcfunProtocol.keepAliveInterval - _heartbeat ~/ 2;
        if (since != null && context.now.difference(since) >= due) {
          _keptAlive = context.now;
          return FrameResult(replies: [link.keepAlive()]);
        }
        return FrameResult.empty;
      case AcfunProtocol.message:
        final push = AcfunProtocol.push(packet.payload, context, gifts: _gifts);
        return FrameResult(
          events: push.events,
          replies: [link.pushAck(packet)],
          // A dead ticket or a closed broadcast asks for a new start, which
          // ends the connection when the room is no longer live.
          rejected: push.ticketInvalid || push.liveClosed,
        );
      default:
        if (packet.errorCode != 0) return const FrameResult(rejected: true);
        return FrameResult(replies: [if (packet.command.startsWith('Push')) link.pushAck(packet)]);
    }
  }
}
