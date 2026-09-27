import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/numbers.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// What one Douyin frame held besides events.
typedef DouyinFrame = ({List<DanmakuEvent> events, Uint8List? ack});

/// Douyin's chat protocol (spec/sites/douyin.md §7), without I/O.
abstract final class DouyinProtocol {
  /// Edge hosts in the order to try (§7, REG-DOUYIN-002).
  static const hosts = ['webcast100-ws-web-lq.douyin.com', 'webcast100-ws-web-hl.douyin.com'];

  /// Push path.
  static const path = '/webcast/im/push/v2/';

  /// SDK values of the query and the signature (§7).
  static const versionCode = '180800';

  /// Webcast SDK version.
  static const sdkVersion = '1.0.15';

  /// Heartbeat period (§7).
  static const heartbeatInterval = Duration(seconds: 10);

  /// Silence that means a half-open connection (§7: 45 s, not the default).
  static const silenceTimeout = Duration(seconds: 45);

  static const _alphabet = 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe';

  /// §7 the signature plaintext for [roomId] and visitor [userUniqueId].
  static String signaturePlaintext(String roomId, String userUniqueId) => [
    'live_id=1',
    'aid=6383',
    'version_code=$versionCode',
    'webcast_sdk_version=$sdkVersion',
    'room_id=$roomId',
    'sub_room_id=',
    'sub_channel_id=',
    'did_rule=3',
    'user_unique_id=$userUniqueId',
    'device_platform=web',
    'device_type=',
    'ac=',
    'identity=audience',
  ].join(',');

  /// §7 the X-Bogus style signature of [roomId] for [userUniqueId];
  /// [r1] and [r2] (0–254) are the random bytes, injectable for tests.
  static String signature(String roomId, String userUniqueId, {required int r1, required int r2}) {
    final stub = md5.convert(utf8.encode(signaturePlaintext(roomId, userUniqueId))).toString();
    final stubBytes = [for (var i = 0; i < 32; i += 2) int.parse(stub.substring(i, i + 2), radix: 16)];
    final digest = md5.convert(stubBytes).bytes;
    final payload = [1 & 0x3f, 0, 1, 0x0e, 0x45, 0x3f, digest[14], digest[15], r2, 0];
    for (var i = 0; i < 9; i++) {
      payload[9] ^= payload[i];
    }
    _rc4(r2, payload);
    return _encode([0x40 | (r1 & 0x1f), r2, ...payload]);
  }

  /// RC4 with the one-byte key [key], in place.
  static void _rc4(int key, List<int> data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key) & 0xff;
      final swap = s[i];
      s[i] = s[j];
      s[j] = swap;
    }
    var i = 0;
    j = 0;
    for (var k = 0; k < data.length; k++) {
      i = (i + 1) & 0xff;
      j = (j + s[i]) & 0xff;
      final swap = s[i];
      s[i] = s[j];
      s[j] = swap;
      data[k] ^= s[(s[i] + s[j]) & 0xff];
    }
  }

  /// Base64 over the signature alphabet; [bytes] is a multiple of 3 long.
  static String _encode(List<int> bytes) {
    final out = StringBuffer();
    for (var i = 0; i + 2 < bytes.length; i += 3) {
      final n = bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2];
      out
        ..write(_alphabet[n >> 18 & 0x3f])
        ..write(_alphabet[n >> 12 & 0x3f])
        ..write(_alphabet[n >> 6 & 0x3f])
        ..write(_alphabet[n & 0x3f]);
    }
    return out.toString();
  }

  /// §7 the endpoints: every host with the same query, the signature
  /// percent-encoded as a query value (REG-DOUYIN-002).
  static List<Uri> endpoints({
    required String roomId,
    required String userUniqueId,
    required String signature,
    required String userAgent,
    required DateTime now,
  }) {
    final query = {
      'app_name': 'douyin_web',
      'version_code': versionCode,
      'webcast_sdk_version': sdkVersion,
      'update_version_code': sdkVersion,
      'compress': 'gzip',
      'cursor': 'h-1_t-${now.millisecondsSinceEpoch}_r-1_d-1_u-1',
      'host': 'https://live.douyin.com',
      'aid': '6383',
      'live_id': '1',
      'did_rule': '3',
      'debug': 'false',
      'maxCacheMessageNumber': '20',
      'endpoint': 'live_pc',
      'support_wrds': '1',
      'im_path': '/webcast/im/fetch/',
      'user_unique_id': userUniqueId,
      'device_platform': 'web',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Mozilla',
      'browser_version': userAgent.startsWith('Mozilla/') ? userAgent.substring('Mozilla/'.length) : userAgent,
      'browser_online': 'true',
      'tz_name': 'Asia/Shanghai',
      'identity': 'audience',
      'room_id': roomId,
      'need_persist_msg_count': '15',
      'heartbeatDuration': '0',
      'signature': signature,
    };
    return [for (final host in hosts) Uri(scheme: 'wss', host: host, path: path, queryParameters: query)];
  }

  /// §7 handshake headers; the cookie only when there is one.
  static Map<String, String> headers({required String webRid, required String userAgent, String? cookie}) => {
    'User-Agent': userAgent,
    'Origin': 'https://live.douyin.com',
    'Referer': 'https://live.douyin.com/$webRid',
    if (cookie != null && cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
  };

  /// §7 the heartbeat frame: `PushFrame{payloadType: "hb"}`.
  static Uint8List heartbeat() => (ProtoWriter()..string(7, 'hb')).toBytes();

  /// §7 the acknowledgement of frame [logId]: `PushFrame{payloadType:
  /// "ack", logId, payload: internalExt}`.
  static Uint8List ack(int logId, String internalExt) =>
      (ProtoWriter()
            ..integer(2, logId)
            ..string(7, 'ack')
            ..bytes(8, utf8.encode(internalExt)))
          .toBytes();

  /// The `Response` inside a `PushFrame`, gunzipped when the encoding says
  /// gzip or the payload starts with `1f 8b`; null for other frames.
  static ProtoMessage? response(ProtoMessage frame) {
    final payload = frame.bytes(8);
    if (payload == null) return null;
    final gzipped =
        (frame.string(6)?.toLowerCase() == 'gzip') || (payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b);
    return ProtoMessage.decode(gzipped ? gzip.decode(payload) : payload);
  }

  /// §7 decodes one frame for broadcast [roomId]; the ack to send when the
  /// response asks for one.
  static DouyinFrame decode(List<int> data, {required String roomId, required DecodeContext context}) {
    final frame = ProtoMessage.decode(data);
    final response = DouyinProtocol.response(frame);
    if (response == null) return (events: const [], ack: null);
    final ack = response.flag(9) ? DouyinProtocol.ack(frame.integer(2) ?? 0, response.string(5) ?? '') : null;
    final events = <DanmakuEvent>[];
    for (final message in response.messages(1)) {
      try {
        final payload = message.bytes(2);
        if (payload == null) continue;
        final event = switch (message.string(1)) {
          'WebcastChatMessage' => _chat(payload, message.integer(3), roomId, context),
          'WebcastRoomUserSeqMessage' => _online(payload, context),
          'WebcastGiftMessage' => _gift(payload, roomId, context),
          _ => null,
        };
        if (event != null) events.add(event);
      } on FormatException {
        // One malformed message must not drop the rest of the frame.
      }
    }
    return (events: events, ack: ack);
  }

  /// `ChatMessage{common 1, user 2, content 3, eventTime 15}`;
  /// `Common{msgId 2, roomId 3, createTime 4}`; `User{id 1, nickName 3}`.
  static DanmakuChat? _chat(Uint8List payload, int? envelopeId, String roomId, DecodeContext context) {
    final chat = ProtoMessage.decode(payload);
    final common = chat.message(1);
    if (!_sameRoom(common, roomId)) return null;
    final text = chat.string(3) ?? '';
    if (text.isEmpty) return null;
    final user = chat.message(2);
    final commonId = common?.integer(2) ?? 0;
    final id = commonId != 0 ? commonId : (envelopeId ?? 0);
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id == 0 ? null : 'douyin:${_unsigned(id)}',
      // Recorded frames leave Common.createTime empty and carry the time
      // in ChatMessage.eventTime (15, seconds).
      sentAt: _time(common?.integer(4)) ?? _time(chat.integer(15)),
      userId: user == null ? '' : _unsigned(user.integer(1) ?? 0),
      userName: user?.string(3) ?? '',
      text: text,
    );
  }

  /// `RoomUserSeqMessage`: the concurrent audience is `total` (3), an exact
  /// integer, else the display text `onlineUserForAnchor` (10, `30.6万`);
  /// `totalUser` (7) is cumulative and never used as online
  /// (REG-DOUYIN-008: exact figures before bucketed text).
  static DanmakuOnline? _online(Uint8List payload, DecodeContext context) {
    final seq = ProtoMessage.decode(payload);
    final total = seq.integer(3) ?? 0;
    final value = total > 0 ? total : audienceNumber(seq.string(10) ?? '');
    if (value == null) return null;
    return DanmakuOnline(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      audience: AudienceKind.online,
      value: value,
    );
  }

  /// `GiftMessage{common 1, giftId 2, repeatCount 5, comboCount 6, user 7,
  /// repeatEnd 9, gift 15}`, `GiftStruct{name 16, diamondCount 12}`: only
  /// the closing message of a combo (`repeatEnd == 1`) or a single gift, so
  /// a combo is one line; 1 diamond is 0.1 yuan.
  static DanmakuGift? _gift(Uint8List payload, String roomId, DecodeContext context) {
    final gift = ProtoMessage.decode(payload);
    final common = gift.message(1);
    if (!_sameRoom(common, roomId)) return null;
    final struct = gift.message(15);
    final combo = struct?.flag(10) ?? false;
    if (combo && gift.integer(9) != 1) return null;
    final name = struct?.string(16) ?? '';
    if (name.isEmpty) return null;
    final count = max(1, max(gift.integer(6) ?? 0, gift.integer(5) ?? 0));
    final diamonds = struct?.integer(12) ?? 0;
    final user = gift.message(7);
    final commonId = common?.integer(2) ?? 0;
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: commonId == 0 ? null : 'douyin:gift:${_unsigned(commonId)}',
      sentAt: _time(common?.integer(4)),
      userId: user == null ? '' : _unsigned(user.integer(1) ?? 0),
      userName: user?.string(3) ?? '',
      giftId: '${gift.integer(2) ?? ''}',
      giftName: name,
      count: count,
      yuan: diamonds <= 0 ? null : diamonds * count / 10,
    );
  }

  /// CONN-5: a message naming another broadcast is dropped; 0 means none.
  static bool _sameRoom(ProtoMessage? common, String roomId) {
    final id = common?.integer(3) ?? 0;
    return id == 0 || roomId.isEmpty || _unsigned(id) == roomId;
  }

  static String _unsigned(int value) => value >= 0 ? '$value' : (BigInt.from(value) + (BigInt.one << 64)).toString();

  static DateTime? _time(int? raw) {
    if (raw == null || raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw > 100000000000 ? raw : raw * 1000);
  }
}

/// Douyin's chat connection: signed URL on two edges, 10 s heartbeat, 45 s
/// silence limit, acknowledgements.
final class DouyinConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys` must hold this
  /// broadcast's `roomId`, the `webRid` and the `userUniqueId`.
  new({
    required super.detail,
    required super.transport,
    this.credentials,
    super.session,
    super.clock,
    super.policy,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Source of the session cookie.
  final DanmakuCredentials? credentials;

  final Random _random;

  String get _roomId => detail.danmakuKeys['roomId'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final roomId = _roomId;
    final visitor = detail.danmakuKeys['userUniqueId'] ?? '';
    final webRid = detail.danmakuKeys['webRid'] ?? room.roomId;
    if (roomId.isEmpty || visitor.isEmpty) throw const DanmakuStartFailure('noRoom', 'douyin room_id missing');
    String? cookie;
    try {
      cookie = await credentials?.cookie('douyin');
    } on Object {
      cookie = null;
    }
    final signature = DouyinProtocol.signature(roomId, visitor, r1: _random.nextInt(256), r2: _random.nextInt(255));
    return SocketPlan(
      endpoints: DouyinProtocol.endpoints(
        roomId: roomId,
        userUniqueId: visitor,
        signature: signature,
        userAgent: DouyinParse.userAgent,
        now: clock.now(),
      ),
      headers: DouyinProtocol.headers(webRid: webRid, userAgent: DouyinParse.userAgent, cookie: cookie),
    );
  }

  @override
  List<List<int>> openFrames() => const [];

  @override
  Duration get heartbeatInterval => DouyinProtocol.heartbeatInterval;

  @override
  Duration get silenceTimeout => DouyinProtocol.silenceTimeout;

  @override
  List<int> heartbeat() => DouyinProtocol.heartbeat();

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    if (data is! List<int>) return FrameResult.empty;
    final frame = DouyinProtocol.decode(data, roomId: _roomId, context: context);
    final ack = frame.ack;
    return FrameResult(events: frame.events, replies: [?ack]);
  }
}
