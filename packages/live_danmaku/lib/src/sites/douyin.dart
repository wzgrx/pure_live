import 'dart:async';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// What one received Douyin frame asks for ([DouyinDanmakuProtocol.decode]):
/// the acknowledgement to send first, then the messages to report.
/// `envelopes` counts the messages the frame carried, of any method (a
/// heartbeat answer carries none). `errors` are the parts that could not be
/// read: an unreadable frame has no ack and no messages; an unreadable
/// message only loses itself.
typedef DouyinDanmakuFrame = ({
  Uint8List? ack,
  List<LiveMessage> messages,
  int envelopes,
  List<FormatException> errors,
});

/// Douyin's danmaku protocol (the codec of 3.x `DouyinDanmaku`,
/// docs/T06/T06a/T06a.5/record.md), without I/O.
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

  /// How often a connection with `DouyinDanmakuArgs.refresh` looks whether
  /// any message came (M5.F B-5; heartbeat answers do not count).
  static const Duration quietTick = Duration(minutes: 1);

  /// Quiet ticks in a row before each check of the room's broadcast: the
  /// first after 2 minutes without any message, then after 4 and 8 more,
  /// then every 16 while the room stays quiet. A message starts over.
  static const List<int> quietChecks = [2, 4, 8, 16];

  /// Longest wait for one check of the room's broadcast.
  static const Duration refreshTimeout = Duration(seconds: 10);

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
      return (ack: null, messages: const [], envelopes: 0, errors: [error]);
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
      envelopes: envelopes.length,
      errors: errors,
    );
  }

  /// `ChatMessage{common 1, user 2, content 3, eventTime 15}`,
  /// `Common{msgId 2, roomId 3, createTime 4}`, `User{id 1, nickName 3}`:
  /// another broadcast's chat is dropped (a room id of 0 or none is kept);
  /// the id is `common.msgId`, else the envelope's `msgId`. The time is
  /// `createTime`, else `eventTime` (M5.F B-5: the recorded chats carry
  /// only that); above 10^11 is milliseconds, otherwise seconds, and 0
  /// means none. Ids are unsigned (3.x printed uint64 signed).
  static LiveMessage? _chat(Uint8List payload, int envelopeId, String roomId) {
    final chat = ProtoMessage.decode(payload);
    final common = chat.message(1);
    final user = chat.message(2);
    final chatRoomId = common == null ? '' : ProtoMessage.unsigned(common.integer(3) ?? 0);
    if (chatRoomId.isNotEmpty && chatRoomId != '0' && chatRoomId != roomId) return null;
    final commonId = common == null ? '' : ProtoMessage.unsigned(common.integer(2) ?? 0);
    final messageId = commonId.isNotEmpty && commonId != '0' ? commonId : (envelopeId == 0 ? '' : '$envelopeId');
    final createTime = common?.integer(4) ?? 0;
    final eventTime = chat.integer(15) ?? 0;
    DateTime? sentAt;
    if (createTime > 0) {
      final milliseconds = _milliseconds(createTime);
      // 3.x's DateTime threw here, and the chat was lost.
      if (milliseconds > _maxEpochMilliseconds) throw FormatException('Douyin chat time out of range: $createTime');
      sentAt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } else if (eventTime > 0 && _milliseconds(eventTime) <= _maxEpochMilliseconds) {
      // B-5; a fallback out of range leaves the chat without a time.
      sentAt = DateTime.fromMillisecondsSinceEpoch(_milliseconds(eventTime));
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

  /// A platform time: above 10^11 milliseconds, otherwise seconds.
  static int _milliseconds(int time) => time > 100000000000 ? time : time * 1000;

  /// `RoomUserSeqMessage`: the concurrent audience is `total` (3), the exact
  /// number the display text rounds (M5.F B-5; recorded in rooms of 2 to
  /// 305 503 viewers); without it, `onlineUserForAnchor` (10, `30.6万`) when
  /// it has a digit, as 3.x read it. `totalUser` (7) is cumulative.
  static LiveMessage? _online(Uint8List payload) {
    final message = ProtoMessage.decode(payload);
    final total = message.integer(3) ?? 0;
    final int value;
    if (total > 0) {
      value = total;
    } else {
      final text = message.string(10) ?? '';
      if (!text.contains(RegExp('[0-9]'))) return null;
      value = parseAudienceNumber(text);
    }
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: value),
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
/// - With `DouyinDanmakuArgs.refresh` (M5.F B-5), the room's broadcast is
///   checked after [DouyinDanmakuProtocol.quietChecks] minutes without any
///   message, and when the reconnects run out: a streamer who went live
///   again has a new room_id, and the socket moves there without a notice.
///   The same broadcast (or no answer) changes nothing: a quiet socket
///   stays, an exhausted one ends as before.
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
  _Broadcast? _broadcast;

  @override
  @protected
  Future<DanmakuSocketTarget> target(DouyinDanmakuArgs args, DanmakuRun run) async {
    final broadcast = _broadcast = _Broadcast(run, args);
    if (args.refresh != null) unawaited(_watch(broadcast));
    return _target(args);
  }

  /// The endpoints of [args]'s broadcast, signed now.
  DanmakuSocketTarget _target(DouyinDanmakuArgs args) {
    final signature = _signer.danmakuSignature(roomId: args.roomId, userUniqueId: args.userId);
    return DanmakuSocketTarget(
      endpoints: DouyinDanmakuProtocol.endpoints(args, signature: signature, now: _now()),
      headers: args.headers,
    );
  }

  _Broadcast? _of(DanmakuSocketSession session) {
    final broadcast = _broadcast;
    return broadcast != null && identical(broadcast.run, session.run) ? broadcast : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    _of(session)?.session = session;
    // 3.x: ready as soon as the socket opens, then a heartbeat as the join.
    session
      ..ready()
      ..send(DouyinDanmakuProtocol.heartbeat());
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    // Douyin only sends binary frames.
    final broadcast = _of(session);
    if (data is! List<int> || broadcast == null) return;
    final frame = DouyinDanmakuProtocol.decode(data, roomId: broadcast.args.roomId);
    if (frame.envelopes > 0) broadcast.heard = true;
    if (frame.ack case final ack?) session.send(ack);
    frame.messages.forEach(session.message);
  }

  /// B-5: before giving up, one check of the room's broadcast; a new one is
  /// joined with fresh reconnects, anything else ends the run as before.
  @override
  @protected
  bool onReconnectsExhausted(DanmakuSocketSession session, String lastFailure) {
    final broadcast = _of(session);
    if (broadcast == null || broadcast.args.refresh == null) return false;
    broadcast.session = session;
    unawaited(() async {
      if (!await _follow(broadcast, session)) {
        session.run.closed(DanmakuCloseReason.reconnectsExhausted, detail: lastFailure);
      }
    }());
    return true;
  }

  /// B-5: counts the quiet ticks of [broadcast] and checks its room after
  /// [DouyinDanmakuProtocol.quietChecks] of them in a row; ends with the run.
  Future<void> _watch(_Broadcast broadcast) async {
    var quiet = 0;
    var round = 0;
    while (await broadcast.run.delay(DouyinDanmakuProtocol.quietTick)) {
      if (broadcast.heard) {
        broadcast.heard = false;
        quiet = 0;
        round = 0;
        continue;
      }
      if (++quiet < DouyinDanmakuProtocol.quietChecks[round]) continue;
      quiet = 0;
      round = min(round + 1, DouyinDanmakuProtocol.quietChecks.length - 1);
      final session = broadcast.session;
      if (session != null && await _follow(broadcast, session)) round = 0;
    }
  }

  /// Asks for the room's broadcast now and moves the socket to it when its
  /// room_id changed. True when the broadcast moved meanwhile, through this
  /// call or another one.
  Future<bool> _follow(_Broadcast broadcast, DanmakuSocketSession session) async {
    final moves = broadcast.moves;
    final next = await broadcast.check();
    if (!session.isActive) return false;
    if (broadcast.moves != moves) return true;
    if (next == null || next.roomId.isEmpty || next.roomId == broadcast.args.roomId) return false;
    broadcast
      ..args = next
      ..moves += 1
      ..heard = false;
    await session.reopen(_target(next));
    return true;
  }

  @override
  @protected
  Future<void> stop() async {
    _broadcast = null;
    await super.stop();
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => DouyinDanmakuProtocol.heartbeat();
}

/// One run's broadcast (M5.F B-5): the arguments in use, whether a message
/// came since the last quiet tick, and the check of the room in flight.
final class _Broadcast {
  new(this.run, this.args);

  final DanmakuRun run;
  DouyinDanmakuArgs args;
  DanmakuSocketSession? session;
  bool heard = false;
  int moves = 0;
  Future<DouyinDanmakuArgs?>? _checking;

  /// The room's broadcast now, or null (not live, failed, or slower than
  /// [DouyinDanmakuProtocol.refreshTimeout]); one request at a time.
  Future<DouyinDanmakuArgs?> check() {
    final refresh = args.refresh;
    if (refresh == null) return Future.value();
    final pending = _checking;
    if (pending != null) return pending;
    final checking = _checking = _ask(refresh);
    unawaited(
      checking.whenComplete(() {
        if (identical(_checking, checking)) _checking = null;
      }),
    );
    return checking;
  }

  static Future<DouyinDanmakuArgs?> _ask(Future<DouyinDanmakuArgs?> Function() refresh) async {
    try {
      return await refresh().timeout(DouyinDanmakuProtocol.refreshTimeout);
    } on Object {
      return null;
    }
  }
}
