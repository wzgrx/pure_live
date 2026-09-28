import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// What one received Douyin frame asks for ([DouyinDanmakuProtocol.decode]):
/// the acknowledgement to send first, then the messages to report. `errors`
/// are the parts that could not be read: an unreadable frame has no ack and
/// no messages; an unreadable message only loses itself.
typedef DouyinDanmakuFrame = ({Uint8List? ack, List<LiveMessage> messages, List<FormatException> errors});

/// Douyin's danmaku protocol (the codec of 3.x `DouyinDanmaku`,
/// docs/modules/M5.4-douyin.md), without I/O.
///
/// Both directions are protobuf `PushFrame`s (`seqId 1, logId 2, service 3,
/// method 4, headersList 5, payloadEncoding 6, payloadType 7, payload 8`). A
/// server frame's payload, gunzipped when its encoding says `gzip` or it
/// starts with `1f 8b`, is a `Response` (`messagesList 1, internalExt 5,
/// needAck 9, …`) whose `Message`s (`method 1, payload 2, msgId 3`) carry
/// `WebcastChatMessage` and `WebcastRoomUserSeqMessage` among many others.
abstract final class DouyinDanmakuProtocol {
  /// The two web IM edges, tried in this order (REG-DOUYIN-002).
  static const List<String> hosts = ['webcast100-ws-web-lq.douyin.com', 'webcast100-ws-web-hl.douyin.com'];

  /// Path of the push socket.
  static const String path = '/webcast/im/push/v2/';

  /// Heartbeat period (3.x `heartbeatTime`, 10 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// Silence after which the socket is replaced (3.x's `inactivityTimeout`).
  static const Duration inactivityTimeout = Duration(seconds: 45);

  static const int _maxEpochMilliseconds = 8640000000000000;

  /// The endpoints of [args]'s broadcast: every host with the same query
  /// (3.x `start` and `buildServerUrls`). The cursor carries [now]; the
  /// [signature] (`DouyinSigner.danmakuSignature`) is a query value, so its
  /// `+` and `/` are percent-encoded.
  static List<Uri> endpoints(DouyinDanmakuArgs args, {required String signature, required DateTime now}) {
    final query = {
      'app_name': 'douyin_web',
      'version_code': DouyinApi.versionCode,
      'webcast_sdk_version': DouyinApi.sdkVersion,
      'update_version_code': DouyinApi.sdkVersion,
      'compress': 'gzip',
      'cursor': 'h-1_t-${now.millisecondsSinceEpoch}_r-1_d-1_u-1',
      'host': 'https://live.douyin.com',
      'aid': DouyinApi.aid,
      'live_id': '1',
      'did_rule': '3',
      'debug': 'false',
      'maxCacheMessageNumber': '20',
      'endpoint': 'live_pc',
      'support_wrds': '1',
      'im_path': '/webcast/im/fetch/',
      'user_unique_id': args.userId,
      'device_platform': 'web',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Mozilla',
      'browser_version': DouyinApi.userAgent.substring('Mozilla/'.length),
      'browser_online': 'true',
      'tz_name': 'Asia/Shanghai',
      'identity': 'audience',
      'room_id': args.roomId,
      'need_persist_msg_count': '15',
      'heartbeatDuration': '0',
      'signature': signature,
    };
    return [for (final host in hosts) Uri(scheme: 'wss', host: host, path: path, queryParameters: query)];
  }

  /// The heartbeat frame, also sent once the socket opens (3.x `heartbeat`
  /// and `joinRoom`): `PushFrame{payloadType: "hb"}`.
  static Uint8List heartbeat() => (ProtoWriter()..string(7, 'hb')).toBytes();

  /// The acknowledgement of the frame [logId] (3.x `sendAck`):
  /// `PushFrame{logId, payloadType: "ack", payload: internalExt}`, every
  /// field written even when empty, as 3.x's generated class did.
  static Uint8List ack(int logId, String internalExt) =>
      (ProtoWriter()
            ..integer(2, logId)
            ..string(7, 'ack')
            ..string(8, internalExt))
          .toBytes();

  /// Decodes one server [frame] for broadcast [roomId] (3.x `decodeMessage`).
  ///
  /// The frame, its payload and its `Response` are read as 3.x's generated
  /// classes read them: when any part of them is unreadable (headers and
  /// message envelopes included), the frame yields nothing, not even the
  /// acknowledgement. Otherwise the acknowledgement comes when `needAck` asks
  /// for it, and each chat or audience message is decoded on its own.
  static DouyinDanmakuFrame decode(List<int> frame, {required String roomId}) {
    final ProtoMessage push;
    final ProtoMessage response;
    final List<ProtoMessage> envelopes;
    try {
      // The headers are read (and must be readable), then ignored.
      push = ProtoMessage.decode(frame)..messages(5);
      final payload = push.bytes(8) ?? Uint8List(0);
      final gzipped =
          (push.string(6) ?? '').toLowerCase() == 'gzip' ||
          (payload.length >= 2 && payload[0] == 0x1F && payload[1] == 0x8B);
      response = ProtoMessage.decode(gzipped ? gzip.decode(payload) : payload);
      envelopes = response.messages(1);
      response.messages(7);
    } on FormatException catch (error) {
      return (ack: null, messages: const [], errors: [error]);
    }
    final messages = <LiveMessage>[];
    final errors = <FormatException>[];
    for (final envelope in envelopes) {
      try {
        final payload = envelope.bytes(2) ?? Uint8List(0);
        final message = switch (envelope.string(1)) {
          'WebcastChatMessage' => _chat(payload, envelope.integer(3) ?? 0, roomId),
          'WebcastRoomUserSeqMessage' => _online(payload),
          _ => null,
        };
        if (message != null) messages.add(message);
      } on FormatException catch (error) {
        // 3.x lost the rest of the frame after one unreadable message.
        errors.add(error);
      }
    }
    return (
      ack: response.flag(9) ? ack(push.integer(2) ?? 0, response.string(5) ?? '') : null,
      messages: messages,
      errors: errors,
    );
  }

  /// `ChatMessage{common 1, user 2, content 3}`, `Common{msgId 2, roomId 3,
  /// createTime 4}`, `User{id 1, nickName 3}`: another broadcast's chat is
  /// dropped (a room id of 0 or none is kept); the id is `common.msgId`, else
  /// the envelope's `msgId`; `createTime` above 10^11 is milliseconds,
  /// otherwise seconds, and 0 means none. Ids are unsigned (3.x printed
  /// uint64 signed).
  static LiveMessage? _chat(Uint8List payload, int envelopeId, String roomId) {
    final chat = ProtoMessage.decode(payload);
    final common = chat.message(1);
    final user = chat.message(2);
    final chatRoomId = common == null ? '' : ProtoMessage.unsigned(common.integer(3) ?? 0);
    if (chatRoomId.isNotEmpty && chatRoomId != '0' && chatRoomId != roomId) return null;
    final commonId = common == null ? '' : ProtoMessage.unsigned(common.integer(2) ?? 0);
    final messageId = commonId.isNotEmpty && commonId != '0' ? commonId : (envelopeId == 0 ? '' : '$envelopeId');
    final createTime = common?.integer(4) ?? 0;
    DateTime? sentAt;
    if (createTime > 0) {
      final milliseconds = createTime > 100000000000 ? createTime : createTime * 1000;
      // 3.x's DateTime threw here, and the chat was lost.
      if (milliseconds > _maxEpochMilliseconds) throw FormatException('Douyin chat time out of range: $createTime');
      sentAt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: user?.string(3) ?? '',
      userId: ProtoMessage.unsigned(user?.integer(1) ?? 0),
      message: chat.string(3) ?? '',
      color: LiveMessageColor.white,
      messageId: messageId.isEmpty ? '' : 'douyin:$messageId',
      sentAt: sentAt,
    );
  }

  /// `RoomUserSeqMessage`: the concurrent audience is the display text
  /// `onlineUserForAnchor` (10, `30.6万`), when it has a digit. `totalUser`
  /// (7) is cumulative and `total` (3) is not read, as in 3.x.
  static LiveMessage? _online(Uint8List payload) {
    final text = ProtoMessage.decode(payload).string(10) ?? '';
    if (!text.contains(RegExp('[0-9]'))) return null;
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: parseAudienceNumber(text)),
    );
  }
}

/// Douyin's danmaku connection (3.x `DouyinDanmaku`) over the shared
/// WebSocket runtime.
///
/// - Connects to both web IM edges ([DouyinDanmakuProtocol.hosts]) in turn,
///   with the X-Bogus signature of the broadcast (computed here, before the
///   first attempt, and kept for the reconnects, as in 3.x) and the room's
///   handshake headers (UA, the cookie when there is one, Origin, Referer).
/// - An open socket counts as joined; a `hb` frame follows at once and every
///   10 s; a socket silent for 45 s is replaced.
/// - Frames that ask for it are acknowledged before their messages are
///   reported; chat of another broadcast is dropped.
///
/// The app registers it as `SiteIds.douyin: () => DouyinDanmakuConnection(
/// proxy: …)`; the room's `DouyinDanmakuArgs` bring the rest.
final class DouyinDanmakuConnection extends DanmakuSocketConnection<DouyinDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake; `random` (the signature's random bytes)
  /// and `now` (the cursor time) are only for tests.
  new({super.proxy, super.connector, Random? random, DateTime Function()? now})
    : _signer = DouyinSigner(userAgent: DouyinApi.userAgent, random: random),
      _now = now ?? DateTime.now,
      super(site: SiteIds.douyin, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 10 s heartbeat and
  /// its own 45 s silence limit. No join timer: 3.x counted an open socket as
  /// joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: DouyinDanmakuProtocol.heartbeatInterval,
    inactivityTimeout: DouyinDanmakuProtocol.inactivityTimeout,
  );

  final DouyinSigner _signer;
  final DateTime Function() _now;
  String _roomId = '';

  @override
  @protected
  Future<DanmakuSocketTarget> target(DouyinDanmakuArgs args, DanmakuRun run) async {
    _roomId = args.roomId;
    final signature = _signer.danmakuSignature(roomId: args.roomId, userUniqueId: args.userId);
    return DanmakuSocketTarget(
      endpoints: DouyinDanmakuProtocol.endpoints(args, signature: signature, now: _now()),
      headers: args.headers,
    );
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    // 3.x: ready as soon as the socket opens, then a heartbeat as the join.
    session
      ..ready()
      ..send(DouyinDanmakuProtocol.heartbeat());
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    // Douyin only sends binary frames.
    if (data is! List<int>) return;
    final frame = DouyinDanmakuProtocol.decode(data, roomId: _roomId);
    if (frame.ack case final ack?) session.send(ack);
    frame.messages.forEach(session.message);
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => DouyinDanmakuProtocol.heartbeat();
}
