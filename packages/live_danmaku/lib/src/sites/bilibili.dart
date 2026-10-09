import 'dart:async';
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/binary.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/sender.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart' show brotliDecode;
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from
/// `SEND_GIFT`, `SEND_GIFT_V2` (what guests get, D07.4), `COMBO_SEND` or
/// `GUARD_BUY` (M4.D2, appendix C-2), as a [LiveGift] (E05.5): [goldCoins]
/// is its value in gold seeds ([LiveGiftUnit.goldSeed]), [comboId] its combo
/// key; a silver gift is [free], its value [silverCoins] in
/// [LiveGiftUnit.silverSeed]; a guard is a [LiveGiftKind.membership] of
/// [count] months at [unitPrice] each, of [guardLevel].
@immutable
final class BilibiliGift extends LiveGift {
  /// Creates the gift.
  ///
  /// [id] is `giftId` (`SEND_GIFT`) or `gift_id`, empty when missing or 0;
  /// [name] `giftName` or `gift_name` (`小心心`, `舰长`); [count] how many
  /// this message gave, at least 1: `num`, a combo's `total_num`, the months
  /// of a `GUARD_BUY`; [comboTotal] a `COMBO_SEND`'s `total_num`, the combo
  /// so far (D07.1); [unitPrice] the price of one in the gift's seeds;
  /// [free] a silver gift; [iconUrl] its picture (`gift_info.img_basic` or
  /// the gift table's, D07.4); [receiverName] `receive_user_info.uname`.
  const new({
    required super.id,
    required super.name,
    required super.count,
    this.goldCoins = 0,
    this.silverCoins = 0,
    this.comboId = '',
    this.guardLevel = 0,
    super.kind,
    super.comboTotal,
    super.unitPrice,
    super.free,
    super.iconUrl,
    super.receiverName,
  }) : super(
         comboKey: comboId,
         totalValue: free ? (silverCoins > 0 ? silverCoins : null) : (goldCoins > 0 ? goldCoins : null),
         unit: free ? LiveGiftUnit.silverSeed : LiveGiftUnit.goldSeed,
       );

  /// What it cost in gold coins (1000 = 1 yuan): `total_coin` of a gold
  /// `SEND_GIFT`, a combo's `combo_total_coin`, `price × num` of a
  /// `GUARD_BUY`. 0 for a free (silver) gift or when missing.
  final int goldCoins;

  /// What a silver (free) gift cost in silver seeds; 0 for a gold one or
  /// when missing.
  final int silverCoins;

  /// `batch_combo_id`, shared by every message of one combo; empty when
  /// missing. Every message of a combo is reported; the app counts them on
  /// one line (D07.1).
  final String comboId;

  /// The guard a `GUARD_BUY` bought (`guard_level`: 1 总督, 2 提督, 3 舰长);
  /// 0 for a gift.
  final int guardLevel;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is BilibiliGift &&
      other.goldCoins == goldCoins &&
      other.silverCoins == silverCoins &&
      other.comboId == comboId &&
      other.guardLevel == guardLevel;

  @override
  int get hashCode => Object.hash(super.hashCode, goldCoins, silverCoins, comboId, guardLevel);

  @override
  String toString() => 'BilibiliGift($name ×$count, ${free ? '$silverCoins silver' : '$goldCoins gold'})';
}

/// Bilibili's danmaku connection (3.x `BiliBiliDanmaku`,
/// docs/D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕/record.md) over the shared WebSocket runtime.
///
/// - Connects to the credentials' endpoints (the general gateway first) with
///   their headers; a start without a token first refreshes the credentials
///   up to three times, 500 ms and 1000 ms apart, and ends with
///   [DanmakuCloseReason.credentialsUnavailable] when there is still none.
/// - Sends the auth packet at every open and counts as joined when the reply
///   says `code 0`: it then sends a heartbeat at once and reports
///   [DanmakuReady]. Without a reply within 8 s it reconnects.
/// - A rejected auth refreshes the credentials (at most three times per
///   [connect]) and reopens with them; when no new credentials come, the
///   connection ends with [DanmakuCloseReason.credentialsUnavailable].
/// - Heartbeats every 30 s; notices that ask for it are acknowledged.
/// - Every gift of a combo is reported (D07.1: the app counts them on one
///   line; it used to report only the first, so the count stayed at the
///   first send's).
/// - Asks for the gift table ([BilibiliDanmakuArgs.giftCatalog]) once per
///   [connect], without waiting for it, and fills in from it what a gift's
///   packet leaves out (D07.4).
final class BilibiliDanmakuConnection extends DanmakuSocketConnection<BilibiliDanmakuArgs> {
  /// Creates the connection. [proxy] routes the socket; `connector` replaces
  /// `dart:io`'s handshake. [policy], `credentialRetryDelay` (the step
  /// between the start's credential attempts) and [random] (the auth
  /// packet's `queue_uuid`) are 3.x's values unless a test shortens them.
  new({
    super.proxy,
    super.connector,
    super.policy = defaultPolicy,
    this._credentialRetryDelay = const Duration(milliseconds: 500),
    Random? random,
  }) : _random = random ?? Random.secure(),
       super(site: SiteIds.bilibili);

  /// 3.x's timing: a 30 s heartbeat (so 90 s of silence replaces the socket)
  /// and 8 s for the auth reply.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: Duration(seconds: 30),
    joinTimeout: Duration(seconds: 8),
  );

  /// Credential refreshes after rejected auths, per [connect].
  static const int maxCredentialRefreshes = 3;

  /// Credential attempts when a start has no token.
  static const int startCredentialAttempts = 3;

  final Duration _credentialRetryDelay;
  final Random _random;
  _Credentials? _credentials;

  /// Whether Bilibili masked [name] (`**` or `＊＊`, guests see names like
  /// `观***`): the room page tells the user once per session that logging in
  /// shows full names (3.x `bilibili_guest_name_masked`).
  static bool isMaskedName(String name) => BilibiliDanmakuProtocol.isMaskedName(name);

  @override
  @protected
  Future<DanmakuSocketTarget> target(BilibiliDanmakuArgs args, DanmakuRun run) async {
    var current = args;
    if (current.token.isEmpty) {
      for (var attempt = 0; attempt < startCredentialAttempts && run.isActive; attempt++) {
        try {
          final refreshed = await current.refresh?.call();
          if (refreshed != null && refreshed.token.isNotEmpty) {
            current = refreshed;
            break;
          }
        } on Object {
          // 3.x logged the failure and tried again.
        }
        if (attempt < startCredentialAttempts - 1 && !await run.delay(_credentialRetryDelay * (attempt + 1))) break;
      }
      if (!run.isActive || current.token.isEmpty) {
        throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: 'No token');
      }
    }
    final credentials = _credentials = _Credentials(run, current);
    unawaited(_loadGifts(credentials));
    return _target(current);
  }

  /// The gift table (D07.4) for [credentials]' run, asked for once as it
  /// starts; until it comes, and when it fails, gifts go without what only
  /// the table has (the guard pictures, a picture or price the packet
  /// leaves out).
  Future<void> _loadGifts(_Credentials credentials) async {
    final load = credentials.args.giftCatalog;
    if (load == null) return;
    try {
      final gifts = await load();
      if (credentials.run.isActive) credentials.gifts = gifts;
    } on Object {
      // Soft: the gifts are still reported.
    }
  }

  static DanmakuSocketTarget _target(BilibiliDanmakuArgs args) => DanmakuSocketTarget(
    endpoints: args.servers.isEmpty ? [Uri.parse(BilibiliApi.danmakuGateway)] : args.servers,
    headers: args.headers,
  );

  _Credentials? _of(DanmakuSocketSession session) {
    final credentials = _credentials;
    return credentials != null && identical(credentials.run, session.run) ? credentials : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final credentials = _of(session);
    if (credentials == null) return;
    session.send(BilibiliDanmakuProtocol.auth(credentials.args, queueUuid: BilibiliDanmakuProtocol.queueUuid(_random)));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    if (data is! List<int>) return;
    final gifts = _of(session)?.gifts ?? BilibiliGiftCatalog.empty;
    for (final item in BilibiliDanmakuProtocol.decode(data, gifts: gifts).items) {
      if (!session.isActive) return;
      switch (item) {
        case BilibiliDanmakuMessage(:final message):
          session.message(message);
        case BilibiliDanmakuAck(:final packet):
          session.send(packet);
        case BilibiliDanmakuAuthReply(:final code):
          _authReply(session, code);
      }
    }
  }

  void _authReply(DanmakuSocketSession session, int code) {
    if (code == 0) {
      if (session.isConnected) return;
      session
        ..heartbeat()
        ..ready();
      return;
    }
    session
      ..cancelJoinTimeout()
      ..markDisconnected();
    unawaited(_refreshCredentials(session, code));
  }

  /// 3.x `_refreshCredentialsAndReconnect`, which did nothing more when no
  /// new token came or the refreshes ran out: the rejected socket then went
  /// on reconnecting with the rejected token.
  Future<void> _refreshCredentials(DanmakuSocketSession session, int code) async {
    final credentials = _of(session);
    if (credentials == null || credentials.refreshing) return;
    if (credentials.refreshes >= maxCredentialRefreshes) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: 'Auth rejected (code $code)');
      return;
    }
    credentials
      ..refreshing = true
      ..refreshes += 1;
    try {
      BilibiliDanmakuArgs? refreshed;
      try {
        refreshed = await credentials.args.refresh?.call();
      } on Object {
        // Reported as unavailable below.
      }
      if (!session.isActive) return;
      if (refreshed == null || refreshed.token.isEmpty) {
        session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: 'Auth rejected (code $code)');
        return;
      }
      credentials.args = refreshed;
      await session.reopen(_target(refreshed));
    } finally {
      credentials.refreshing = false;
    }
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => BilibiliDanmakuProtocol.heartbeat();

  @override
  @protected
  Future<void> stop() async {
    _credentials = null;
    await super.stop();
  }
}

/// The credentials of one run: the ones in use and the refresh budget.
final class _Credentials {
  new(this.run, this.args);

  final DanmakuRun run;
  BilibiliDanmakuArgs args;
  int refreshes = 0;
  bool refreshing = false;

  /// The gift table, once [BilibiliDanmakuArgs.giftCatalog] gave it.
  BilibiliGiftCatalog gifts = BilibiliGiftCatalog.empty;
}

/// Something one received Bilibili message held, in order
/// ([BilibiliDanmakuProtocol.decode]).
@immutable
sealed class BilibiliDanmakuItem {
  const new();
}

/// A message to report: chat, super chat, gift, audience figure, retraction
/// or notice.
final class BilibiliDanmakuMessage extends BilibiliDanmakuItem {
  /// Creates the item.
  const new(this.message);

  /// The message.
  final LiveMessage message;
}

/// An acknowledgement to send back (op 24): the notice before it asked for
/// one.
final class BilibiliDanmakuAck extends BilibiliDanmakuItem {
  /// Creates the item.
  const new(this.packet);

  /// The packet to send.
  final Uint8List packet;
}

/// The auth reply (op 8): `code` 0 accepts, anything else rejects (a reply
/// without a code, or not an object, is −1).
final class BilibiliDanmakuAuthReply extends BilibiliDanmakuItem {
  /// Creates the item.
  const new(this.code);

  /// The reply's code.
  final int code;
}

/// Bilibili's danmaku wire format (3.x `BiliBiliDanmaku`'s encoding and
/// decoding), without I/O.
///
/// Every packet has a 16-byte big-endian header: total length (4), header
/// length (2), protocol version (2: 0 JSON, 1 int32, 2 zlib, 3 brotli),
/// operation (4) and sequence (4, 1 when sent). One WebSocket message can
/// hold several packets; a compressed packet holds another packet stream.
abstract final class BilibiliDanmakuProtocol {
  /// Header length.
  static const int headerLength = 16;

  /// Heartbeat (sent, empty body).
  static const int opHeartbeat = 2;

  /// Heartbeat reply with the popularity figure (4 bytes).
  static const int opHeartbeatReply = 3;

  /// Notice: JSON, or a compressed packet stream.
  static const int opNotice = 5;

  /// Auth (sent).
  static const int opAuth = 7;

  /// Auth reply.
  static const int opAuthReply = 8;

  /// Acknowledgement (sent).
  static const int opAck = 24;

  /// Protocol version the auth packet asks for: 3 (brotli), as 3.x and the
  /// web player do. M5.1 asked for 2 (zlib) while there was no brotli
  /// decoder; zlib packets are still decoded.
  static const int protocolVersion = 3;

  /// Largest WebSocket message and packet.
  static const int maxMessageBytes = 8 * 1024 * 1024;

  /// Largest inflated packet stream (zlib or brotli).
  static const int maxInflatedBytes = 16 * 1024 * 1024;

  /// Most packets in one stream.
  static const int maxPackets = 4096;

  /// Deepest nesting of compressed streams.
  static const int maxNesting = 2;

  static final RegExp _masked = RegExp(r'\*{2,}|＊{2,}');

  /// Whether Bilibili masked [name] (`**` or `＊＊`).
  static bool isMaskedName(String name) => _masked.hasMatch(name);

  /// One client packet: [body] as UTF-8 after the header (version 0,
  /// sequence 1), written like 3.x's `encodeData`.
  static Uint8List packet(int operation, String body) {
    final data = utf8.encode(body);
    final writer = BinaryWriter()
      ..writeInt(data.length + headerLength, 4)
      ..writeInt(headerLength, 2)
      ..writeInt(0, 2)
      ..writeInt(operation, 4)
      ..writeInt(1, 4)
      ..writeBytes(data);
    return Uint8List.fromList(writer.buffer);
  }

  /// The heartbeat packet.
  static Uint8List heartbeat() => packet(opHeartbeat, '');

  /// The auth packet's body, in 3.x's key order.
  static Map<String, Object> authPayload(BilibiliDanmakuArgs args, {required String queueUuid}) => {
    'uid': args.uid,
    'roomid': args.roomId,
    'protover': protocolVersion,
    'buvid': args.buvid,
    'support_ack': true,
    'queue_uuid': queueUuid,
    'scene': 'room',
    'platform': 'web',
    'type': 2,
    'key': args.token,
  };

  /// The auth packet.
  static Uint8List auth(BilibiliDanmakuArgs args, {required String queueUuid}) =>
      packet(opAuth, jsonEncode(authPayload(args, queueUuid: queueUuid)));

  /// A new `queue_uuid`: eight lower-case hexadecimal digits.
  static String queueUuid(Random random) => [for (var i = 0; i < 8; i++) random.nextInt(16).toRadixString(16)].join();

  /// The acknowledgement a [notice] asks for (`p_is_ack` true with a
  /// `msg_id`, a `cmd` and an integer `p_msg_type`), or null.
  static Uint8List? acknowledgement(Map<String, dynamic> notice) {
    if (notice['p_is_ack'] != true || !notice.containsKey('p_msg_type')) return null;
    final id = notice['msg_id']?.toString().trim() ?? '';
    final cmd = notice['cmd']?.toString().trim() ?? '';
    final type = int.tryParse(notice['p_msg_type']?.toString() ?? '');
    if (id.isEmpty || cmd.isEmpty || type == null) return null;
    return packet(opAck, jsonEncode({'msg_id': id, 'cmd': cmd, 'p_msg_type': type}));
  }

  /// Decodes one WebSocket message into its items, in order.
  ///
  /// A malformed message keeps the items decoded before the fault, which is
  /// returned as `error`: a message over [maxMessageBytes], a bad or
  /// truncated header, trailing bytes, too many packets, too deep nesting,
  /// corrupt or oversized zlib or brotli, an auth reply that is not JSON. A
  /// notice that is not JSON, or not a message this decoder knows, is skipped
  /// on its own.
  ///
  /// [gifts] fills in the gifts' pictures and prices their packets leave
  /// out (D07.4).
  static ({List<BilibiliDanmakuItem> items, FormatException? error}) decode(
    List<int> message, {
    BilibiliGiftCatalog gifts = BilibiliGiftCatalog.empty,
  }) {
    final items = <BilibiliDanmakuItem>[];
    try {
      if (message.length > maxMessageBytes) {
        throw FormatException('Bilibili danmaku message is too large: ${message.length} bytes');
      }
      _stream(message is Uint8List ? message : Uint8List.fromList(message), 0, items, gifts);
    } on FormatException catch (error) {
      return (items: items, error: error);
    }
    return (items: items, error: null);
  }

  static void _stream(Uint8List data, int depth, List<BilibiliDanmakuItem> items, BilibiliGiftCatalog gifts) {
    if (depth > maxNesting) throw const FormatException('Bilibili danmaku packet nesting is too deep');
    final view = ByteData.sublistView(data);
    var offset = 0;
    var count = 0;
    while (offset + headerLength <= data.length) {
      if (++count > maxPackets) throw const FormatException('Bilibili danmaku message contains too many packets');
      final length = view.getUint32(offset);
      final header = view.getUint16(offset + 4);
      final version = view.getUint16(offset + 6);
      final operation = view.getUint32(offset + 8);
      // A zero length must not leave the offset where it is.
      if (header < headerLength || length < header || length > maxMessageBytes || offset + length > data.length) {
        throw FormatException(
          'Invalid Bilibili danmaku frame: offset=$offset, packet=$length, header=$header, total=${data.length}',
        );
      }
      _packet(version, operation, Uint8List.sublistView(data, offset + header, offset + length), depth, items, gifts);
      offset += length;
    }
    if (offset != data.length) {
      throw FormatException('Incomplete Bilibili danmaku frame: parsed=$offset, total=${data.length}');
    }
  }

  static void _packet(
    int version,
    int operation,
    Uint8List body,
    int depth,
    List<BilibiliDanmakuItem> items,
    BilibiliGiftCatalog gifts,
  ) {
    switch (operation) {
      case opHeartbeatReply:
        if (body.length < 4) return;
        final value = ByteData.sublistView(body).getUint32(0);
        items.add(BilibiliDanmakuMessage(_audience(LiveAudienceMetricKind.popularity, value)));
      case opNotice:
        switch (version) {
          case 2:
            _stream(_inflate(body), depth + 1, items, gifts);
          case 3:
            _stream(brotliDecode(body, maxOutput: maxInflatedBytes), depth + 1, items, gifts);
          default:
            final text = utf8.decode(body, allowMalformed: true).trim();
            if (text.isNotEmpty) _notice(text, items, gifts);
        }
      case opAuthReply:
        final text = utf8.decode(body, allowMalformed: true).trim();
        final Object? reply = text.isEmpty ? const {'code': 0} : jsonDecode(text);
        final code = reply is Map ? int.tryParse(reply['code']?.toString() ?? '') : null;
        items.add(BilibiliDanmakuAuthReply(code ?? -1));
    }
  }

  static Uint8List _inflate(Uint8List body) {
    final sink = _BoundedSink(maxInflatedBytes);
    ZLibDecoder().startChunkedConversion(sink)
      ..add(body)
      ..close();
    return sink.bytes.takeBytes();
  }

  static void _notice(String text, List<BilibiliDanmakuItem> items, BilibiliGiftCatalog gifts) {
    final Object? notice;
    try {
      notice = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (notice is! Map<String, dynamic>) return;
    final ack = acknowledgement(notice);
    if (ack != null) items.add(BilibiliDanmakuAck(ack));
    final cmd = '${notice['cmd']}';
    // RECALL_DANMU_MSG contains DANMU_MSG: match it before the chat.
    final messages = switch (cmd) {
      'RECALL_DANMU_MSG' => [?_recall(notice)],
      _ when cmd.contains('DANMU_MSG') => [?_chat(notice)],
      'WATCHED_CHANGE' => [?_watched(notice)],
      'ONLINE_RANK_COUNT' => [?_onlineRank(notice)],
      'SEND_GIFT' || 'COMBO_SEND' => [?_gift(notice, gifts, combo: cmd == 'COMBO_SEND')],
      'SEND_GIFT_V2' => [?_giftV2(notice, gifts)],
      'GUARD_BUY' => [?_guard(notice, gifts)],
      'SUPER_CHAT_MESSAGE' => [?_superChat(notice)],
      'SUPER_CHAT_MESSAGE_DELETE' => _superChatDeleted(notice),
      'WARNING' => [_notify(notice, warningNotice)],
      'CUT_OFF' => [_notify(notice, cutOffNotice)],
      _ => const <LiveMessage>[],
    };
    for (final message in messages) {
      items.add(BilibiliDanmakuMessage(message));
    }
  }

  /// Start of the notice of `WARNING` (a moderator warned the room), before
  /// the platform's reason.
  static const String warningNotice = '直播间收到警告';

  /// Start of the notice of `CUT_OFF` (a moderator cut the stream off),
  /// before the platform's reason.
  static const String cutOffNotice = '直播被切断';

  /// `RECALL_DANMU_MSG` (the web player's `withdrawUserDanmaku`):
  /// `recall_type` 2 takes back every chat of `data.uinfo.uid` (else
  /// `data.target_id`), 3 the whole chat. Other types (0 nothing, 1 a single
  /// chat the web player does not handle here) and a uid of 0 (guests see
  /// every uid as 0) give nothing.
  static LiveMessage? _recall(Map<String, dynamic> notice) {
    final data = notice['data'];
    if (data is! Map) return null;
    final LiveRetraction target;
    switch (jsonInt(data['recall_type'])) {
      case 2:
        final uinfo = data['uinfo'];
        final uid = (uinfo is Map ? jsonInt(uinfo['uid']) : null) ?? jsonInt(data['target_id']);
        if (uid == null || uid <= 0) return null;
        target = LiveRetraction.user('$uid');
      case 3:
        target = const LiveRetraction.all();
      default:
        return null;
    }
    return _retraction(target);
  }

  /// `SUPER_CHAT_MESSAGE_DELETE`: the super chats of `data.ids` were taken
  /// down (refunded or removed); one retraction each, by the id
  /// [_superChat] gives them.
  static List<LiveMessage> _superChatDeleted(Map<String, dynamic> notice) {
    final data = notice['data'];
    if (data is! Map) return const [];
    return [
      for (final raw in data['ids'] is List ? data['ids'] as List : const [])
        if (jsonString(raw) case final id?) _retraction(LiveRetraction.message(id)),
    ];
  }

  /// A retraction: no id of its own, no sender.
  static LiveMessage _retraction(LiveRetraction target) => LiveMessage(
    type: LiveMessageType.retraction,
    userName: '',
    message: '',
    color: LiveMessageColor.white,
    data: target,
  );

  /// A system notice: [lead], then the platform's reason `msg` when there is
  /// one.
  static LiveMessage _notify(Map<String, dynamic> notice, String lead) {
    final reason = jsonString(notice['msg'])?.trim() ?? '';
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: '',
      message: reason.isEmpty ? lead : '$lead：$reason',
      color: LiveMessageColor.white,
      data: LiveNoticeKind.system,
    );
  }

  /// `DANMU_MSG`: text `info[1]`, colour `info[0][3]` (0 is white), time
  /// `info[0][4]` (milliseconds above 1e11, else seconds), id
  /// `bilibili:` + `info[0][5]`, user id `info[2][0]`, name from
  /// [_userName], pictures from [emotes], fan badge from [_medal] and the
  /// avatar (a [DanmakuSender] in `data`) from [_avatar] (B06). A chat
  /// without its user list is not shown.
  static LiveMessage? _chat(Map<String, dynamic> notice) {
    final info = notice['info'];
    if (info is! List || info.length < 3) return null;
    final meta = info[0];
    final user = info[2];
    if (meta is! List || meta.length < 4 || user is! List || user.length < 2) return null;
    final color = switch (meta[3]) {
      final int value => value,
      _ => 0,
    };
    final time = meta.length > 4 ? int.tryParse(meta[4]?.toString() ?? '') : null;
    final nonce = meta.length > 5 ? meta[5]?.toString() ?? '' : '';
    DateTime? sentAt;
    if (time != null) {
      final milliseconds = time > 100000000000 ? time : time * 1000;
      // 3.x's DateTime threw and dropped the chat.
      if (milliseconds.abs() > _maxEpochMilliseconds) return null;
      sentAt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    final rich = meta.length > 15 ? _json(meta[15]) : null;
    final medal = _medal(rich, info.length > 3 ? info[3] : null);
    final avatar = _avatar(rich);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _userName(notice, rich, user[1]?.toString() ?? ''),
      userId: user[0]?.toString() ?? '',
      message: '${info[1]}',
      color: color == 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
      fansName: medal.name,
      fansLevel: medal.level,
      messageId: nonce.isEmpty ? '' : 'bilibili:$nonce',
      sentAt: sentAt,
      emotes: emotes('${info[1]}', meta),
      data: avatar.isEmpty ? null : DanmakuSender(avatar: avatar),
    );
  }

  /// The fan badge the sender wears: `user.medal{name, level}` of the rich
  /// user in `info[0][15]` ([rich], decoded), else `info[3]` ([legacy]:
  /// `[level, name, streamer, room, …]`); empty without a name. Guests see
  /// it unmasked. The level is empty when it is not a positive number.
  static ({String name, String level}) _medal(Object? rich, Object? legacy) {
    String level(Object? value) => switch (jsonInt(value)) {
      final int number when number > 0 => '$number',
      _ => '',
    };
    String text(Object? value) => value is String ? value.trim() : '';
    final user = rich is Map ? (rich['user'] is Map ? rich['user'] as Map : rich) : null;
    if (user?['medal'] case final Map<Object?, Object?> medal when text(medal['name']).isNotEmpty) {
      return (name: text(medal['name']), level: level(medal['level']));
    }
    if (legacy is List && legacy.length > 1 && text(legacy[1]).isNotEmpty) {
      return (name: text(legacy[1]), level: level(legacy[0]));
    }
    return (name: '', level: '');
  }

  /// The sender's avatar: `user.base.face` of the rich user ([rich],
  /// decoded), else `base.origin_info.face`; https, and on `hdslb.com` asked
  /// for at 96 × 96 (the chat draws it at most 32 dp). Guests see it
  /// unmasked. Empty when there is none.
  static String _avatar(Object? rich) {
    if (rich is! Map) return '';
    final user = rich['user'] is Map ? rich['user'] as Map : rich;
    final base = user['base'];
    if (base is! Map) return '';
    var url = _picture(base['face']);
    if (url.isEmpty) {
      final origin = base['origin_info'];
      if (origin is Map) url = _picture(origin['face']);
    }
    if (url.isEmpty) return '';
    final uri = Uri.parse(url);
    final small = (uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com')) && !uri.path.contains('@');
    return small ? '$url@96w_96h.jpg' : url;
  }

  /// The pictures of a chat with text [text] and `info[0]` [meta] (M13.16):
  /// a sticker (`info[0][12]` 1, the picture `info[0][13].url`) is its whole
  /// text; otherwise the inline codes (`[dog]`) of [text] that
  /// `info[0][15].extra.emots` names (`code` → `{url}`), each once. Image
  /// addresses on `hdslb.com` are made https.
  static List<LiveEmote> emotes(String text, List<Object?> meta) {
    if (text.isEmpty) return const [];
    final sticker = meta.length > 13 ? meta[13] : null;
    if (meta.length > 12 && meta[12] == 1 && sticker is Map) {
      final url = _picture(sticker['url']);
      return url.isEmpty ? const [] : [LiveEmote(code: text, url: url)];
    }
    var rich = meta.length > 15 ? meta[15] : null;
    if (rich is String) rich = _json(rich);
    final extra = rich is Map ? _json(rich['extra']) : null;
    final emots = extra is Map ? extra['emots'] : null;
    if (emots is! Map || emots.isEmpty) return const [];
    return [
      for (final MapEntry(:key, :value) in emots.entries)
        if (key is String && key.isNotEmpty && text.contains(key) && value is Map)
          if (_picture(value['url']) case final url when url.isNotEmpty) LiveEmote(code: key, url: url),
    ];
  }

  /// [value] decoded when it is JSON text, else [value] itself; null when it
  /// is text that is not JSON.
  static Object? _json(Object? value) {
    if (value is! String) return value;
    if (!value.trimLeft().startsWith('{')) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  /// An image address: http(s) only, `hdslb.com`'s made https.
  static String _picture(Object? value) {
    final url = value is String ? value.trim() : '';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return '';
    if (uri.scheme == 'http' && (uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com'))) {
      return uri.replace(scheme: 'https').toString();
    }
    return url;
  }

  static const int _maxEpochMilliseconds = 8640000000000000;

  /// The display name: the first unmasked of the rich user in `info[0][15]`
  /// ([rich], decoded from JSON text), the notice's `uinfo`, `data.uinfo`
  /// and [legacy] (`info[2][1]`); the first rich one when all are masked,
  /// else [legacy]. A guest gets every one of them masked (B06: the server
  /// masks by connection, see docs/D-弹幕/D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/record.md); a logged-in
  /// connection gets the full name in `user.base.name`.
  static String _userName(Map<String, dynamic> notice, Object? rich, String legacy) {
    final data = notice['data'];
    final candidates = [
      for (final root in [rich, notice['uinfo'], if (data is Map) data['uinfo']])
        if (_richName(root) case final name when name.isNotEmpty) name,
    ];
    for (final candidate in [...candidates, legacy]) {
      if (candidate.isNotEmpty && !isMaskedName(candidate)) return candidate;
    }
    return candidates.isNotEmpty ? candidates.first : legacy;
  }

  /// `user.base.name` (or `base.name` at the top), else
  /// `base.origin_info.name`, trimmed.
  static String _richName(Object? root) {
    if (root is! Map) return '';
    final user = root['user'] is Map ? root['user'] as Map : root;
    final base = user['base'];
    if (base is! Map) return '';
    final name = base['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final origin = base['origin_info'];
    return origin is Map ? origin['name']?.toString().trim() ?? '' : '';
  }

  /// `WATCHED_CHANGE`: the room's cumulative viewers, `data.num` when it is a
  /// whole number of zero or more.
  static LiveMessage? _watched(Map<String, dynamic> notice) {
    final data = notice['data'];
    if (data is! Map) return null;
    final value = int.tryParse(data['num']?.toString() ?? '');
    if (value == null || value < 0) return null;
    return _audience(LiveAudienceMetricKind.totalViewers, value);
  }

  /// `ONLINE_RANK_COUNT` (about every 3 s): the room's online viewers,
  /// `data.online_count`, else `data.count` (the web page shows the text of
  /// one of them on its viewer tab; recorded equal or 1 to 3 apart). M4.D2,
  /// appendix C-1: the heartbeat reply's popularity is always 1 for guests.
  static LiveMessage? _onlineRank(Map<String, dynamic> notice) {
    final data = notice['data'];
    if (data is! Map) return null;
    final value = jsonCount(data['online_count']) ?? jsonCount(data['count']);
    return value == null ? null : _audience(LiveAudienceMetricKind.onlineViewers, value);
  }

  /// `SEND_GIFT` (logged in: `giftName`, `giftId`, `num`, `price`,
  /// `total_coin`, `coin_type`, `tid`, `timestamp`) and `COMBO_SEND` (a
  /// combo so far: `gift_name`, `gift_id`, `total_num`, `combo_total_coin`),
  /// both with `uid`, `uname`, `batch_combo_id`, `gift_info.img_basic`, the
  /// fan medal (`sender_uinfo.medal`, else `medal_info`) and the receiver
  /// (`receive_user_info.uname`): a [LiveMessageType.gift] holding a
  /// [BilibiliGift] ([_giftOf]); a `COMBO_SEND`'s count is also its
  /// [LiveGift.comboTotal]. Without a name, nothing.
  static LiveMessage? _gift(Map<String, dynamic> notice, BilibiliGiftCatalog gifts, {required bool combo}) {
    final data = notice['data'];
    if (data is! Map) return null;
    final count = jsonInt(data[combo ? 'total_num' : 'num']) ?? 0;
    final info = data['gift_info'];
    final receiver = data['receive_user_info'];
    final tid = combo ? '' : jsonString(data['tid']) ?? '';
    final sender = data['sender_uinfo'];
    var userName = jsonString(data['uname'])?.trim() ?? '';
    if (userName.isEmpty) userName = _richName(sender);
    return _giftOf(
      gifts,
      id: _giftId(data[combo ? 'gift_id' : 'giftId']),
      name: jsonString(data[combo ? 'gift_name' : 'giftName']) ?? '',
      count: count,
      coinType: jsonString(data['coin_type']) ?? '',
      price: combo ? null : jsonInt(data['price']),
      total: jsonInt(data[combo ? 'combo_total_coin' : 'total_coin']),
      comboId: jsonString(data['batch_combo_id']) ?? '',
      comboTotal: combo && count > 0 ? count : null,
      icon: BilibiliApi.giftIcon(info is Map ? info['img_basic'] : null),
      receiver: receiver is Map ? jsonString(receiver['uname'])?.trim() ?? '' : '',
      userName: userName,
      userId: jsonString(data['uid']) ?? '',
      medal: _giftMedal(sender, data['medal_info']),
      messageId: tid.isEmpty ? '' : 'bilibili:gift:$tid',
      sentAt: combo ? null : jsonInt(data['timestamp']),
    );
  }

  /// `SEND_GIFT_V2`, what a guest gets instead of `SEND_GIFT` (D07.4,
  /// fixtures/bilibili/danmaku/S13-guest-gifts): `data.pb` is the same gift
  /// as protobuf. Fields read (the table is in
  /// docs/D-弹幕/D07-礼物和付费消息/D07.4-哔哩哔哩礼物补全/record.md): 1 `uid` (none for
  /// a guest), 2 `uname` (masked for a guest, D-013), 8 `medal_info`
  /// (5 level, 6 name), 15 `sender_uinfo` (2.1 name, 3 medal: 1 name,
  /// 2 level) and 10 the gift: 1 id, 2 name, 3 num, 5 price, 7 total, 8
  /// `coin_type`, 9 `tid`, 10 time (seconds), 12 `batch_combo_id`, 29.1 the
  /// receiver's name, 35.1 the picture. A packet that is not protobuf, or a
  /// gift without a name, gives nothing.
  static LiveMessage? _giftV2(Map<String, dynamic> notice, BilibiliGiftCatalog gifts) {
    final data = notice['data'];
    final encoded = data is Map ? data['pb'] : null;
    if (encoded is! String || encoded.isEmpty) return null;
    final ProtoMessage root;
    final ProtoMessage? gift;
    try {
      root = ProtoMessage.decode(base64.decode(encoded));
      gift = root.message(10);
    } on FormatException {
      return null;
    }
    if (gift == null) return null;
    final sender = root.message(15);
    var userName = root.string(2)?.trim() ?? '';
    if (userName.isEmpty) userName = sender?.message(2)?.string(1)?.trim() ?? '';
    String level(int? value) => value != null && value > 0 ? '$value' : '';
    final medal = root.message(8);
    final rich = sender?.message(3);
    final medalName = medal?.string(6)?.trim() ?? '';
    final richName = rich?.string(1)?.trim() ?? '';
    final uid = root.integer(1) ?? 0;
    final tid = gift.string(9)?.trim() ?? '';
    return _giftOf(
      gifts,
      id: _giftId(gift.integer(1)),
      name: gift.string(2) ?? '',
      count: gift.integer(3) ?? 0,
      coinType: gift.string(8) ?? '',
      price: gift.integer(5),
      total: gift.integer(7),
      comboId: gift.string(12)?.trim() ?? '',
      icon: BilibiliApi.giftIcon(gift.message(35)?.string(1)),
      receiver: gift.message(29)?.string(1)?.trim() ?? '',
      userName: userName,
      userId: ProtoMessage.unsigned(uid),
      medal: medalName.isNotEmpty
          ? (name: medalName, level: level(medal?.integer(5)))
          : richName.isNotEmpty
          ? (name: richName, level: level(rich?.integer(2)))
          : (name: '', level: ''),
      messageId: tid.isEmpty ? '' : 'bilibili:gift:$tid',
      sentAt: gift.integer(10),
    );
  }

  /// A gift message from what [_gift] and [_giftV2] read, with the gift
  /// table [gifts] for what the packet leaves out:
  ///
  /// - the name, else the table's;
  /// - silver (`coin_type` `silver`, or the table's when the packet says
  ///   nothing) is free, its value in silver seeds;
  /// - the price of one: `total ÷ count` when the total is given, else
  ///   `price`, else the table's (for the same coin); the value: `total`,
  ///   else the price times the count;
  /// - the picture: the packet's, else the table's.
  static LiveMessage? _giftOf(
    BilibiliGiftCatalog gifts, {
    required String id,
    required String name,
    required int count,
    required String coinType,
    required int? price,
    required int? total,
    required String comboId,
    required Uri? icon,
    required String receiver,
    required String userName,
    required String userId,
    required ({String name, String level}) medal,
    required String messageId,
    required int? sentAt,
    int? comboTotal,
  }) {
    final entry = id.isEmpty ? null : gifts[id];
    final title = name.trim().isNotEmpty ? name.trim() : entry?.name ?? '';
    if (title.isEmpty) return null;
    final number = count > 0 ? count : 1;
    final silver = coinType == 'silver' || (coinType.isEmpty && (entry?.silver ?? false));
    final paid = total != null && total > 0 ? total : null;
    var unit = price != null && price > 0 ? price : null;
    if (paid != null && (unit == null || unit * number != paid)) unit = paid % number == 0 ? paid ~/ number : null;
    if (unit == null && entry != null && entry.silver == silver && entry.price > 0) unit = entry.price;
    final value = paid ?? (unit == null ? null : unit * number);
    return _giftMessage(
      userName: userName,
      userId: userId,
      medal: medal,
      messageId: messageId,
      sentAt: sentAt,
      gift: BilibiliGift(
        id: id,
        name: title,
        count: number,
        goldCoins: silver ? 0 : value ?? 0,
        silverCoins: silver ? value ?? 0 : 0,
        comboId: comboId,
        comboTotal: comboTotal,
        unitPrice: unit,
        free: silver,
        iconUrl: icon ?? entry?.icon,
        receiverName: receiver,
      ),
    );
  }

  /// The fan medal of a gift's sender: `sender_uinfo.medal{name, level}`
  /// ([rich]), else `medal_info{medal_name, medal_level}` ([legacy]); guests
  /// see it unmasked (as on a chat line, D01.32).
  static ({String name, String level}) _giftMedal(Object? rich, Object? legacy) {
    final medal = _medal(rich, null);
    if (medal.name.isNotEmpty || legacy is! Map) return medal;
    return _medal(null, [legacy['medal_level'], legacy['medal_name']]);
  }

  /// `GUARD_BUY`: `username` bought `num` months of guard `guard_level` (1
  /// 总督, 2 提督, 3 舰长; `gift_name`, else the level's name) at `price`
  /// gold coins each: a [LiveGiftKind.membership] holding the level
  /// ([BilibiliGift.guardLevel]), its picture from the gift table's
  /// `guard_resources`.
  static LiveMessage? _guard(Map<String, dynamic> notice, BilibiliGiftCatalog gifts) {
    final data = notice['data'];
    if (data is! Map) return null;
    final guard = jsonInt(data['guard_level']) ?? 0;
    final level = guard >= 1 && guard <= 3 ? guard : 0;
    var name = jsonString(data['gift_name'])?.trim() ?? '';
    if (name.isEmpty) name = BilibiliApi.guardName(level);
    if (name.isEmpty) return null;
    final count = jsonInt(data['num']) ?? 0;
    final months = count > 0 ? count : 1;
    final price = jsonInt(data['price']) ?? 0;
    return _giftMessage(
      userName: jsonString(data['username']) ?? '',
      userId: jsonString(data['uid']) ?? '',
      medal: (name: '', level: ''),
      messageId: '',
      sentAt: jsonInt(data['start_time']),
      gift: BilibiliGift(
        id: _giftId(data['gift_id']),
        name: name,
        count: months,
        goldCoins: price > 0 ? price * months : 0,
        kind: LiveGiftKind.membership,
        unitPrice: price > 0 ? price : null,
        iconUrl: gifts.guards[level]?.icon,
        guardLevel: level,
      ),
    );
  }

  static String _giftId(Object? raw) {
    final id = jsonString(raw) ?? '';
    return id == '0' ? '' : id;
  }

  static LiveMessage _giftMessage({
    required String userName,
    required String userId,
    required ({String name, String level}) medal,
    required String messageId,
    required int? sentAt,
    required BilibiliGift gift,
  }) => LiveMessage(
    type: LiveMessageType.gift,
    userName: userName,
    userId: userId,
    message: gift.plainText,
    color: LiveMessageColor.white,
    fansName: medal.name,
    fansLevel: medal.level,
    messageId: messageId,
    sentAt: sentAt != null && sentAt > 0 && sentAt < 100000000000
        ? DateTime.fromMillisecondsSinceEpoch(sentAt * 1000)
        : null,
    data: gift,
  );

  /// `SUPER_CHAT_MESSAGE`: `data` read like an item of the snapshot
  /// `BilibiliApi.superChats` (M4.1) reads, so both give the same
  /// [LiveSuperChatMessage.messageId] (`data.id`) and the room page merges
  /// them. The message carries the same id, which a later
  /// `SUPER_CHAT_MESSAGE_DELETE` takes back.
  static LiveMessage? _superChat(Map<String, dynamic> notice) {
    final data = notice['data'];
    if (data is! Map<String, dynamic>) return null;
    DateTime? time(Object? seconds) => switch (jsonInt(seconds)) {
      final int value when value > 0 => DateTime.fromMillisecondsSinceEpoch(value * 1000),
      _ => null,
    };
    final (start, end) = (time(data['start_time']), time(data['end_time']));
    if (start == null || end == null) return null;
    final user = data['user_info'];
    final userInfo = user is Map<String, dynamic> ? user : null;
    final face = normalizeImageUrl(userInfo?['face']);
    final id = jsonString(data['id']) ?? '';
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: 'SUPER_CHAT_MESSAGE',
      message: 'SUPER_CHAT_MESSAGE',
      color: LiveMessageColor.white,
      messageId: id,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: jsonString(userInfo?['uname']) ?? '',
        face: face.isEmpty ? '' : '$face@200w.jpg',
        message: jsonString(data['message']) ?? '',
        price: jsonInt(data['price']) ?? 0,
        unit: LiveGiftUnit.yuan,
        startTime: start,
        endTime: end,
        backgroundColor: jsonString(data['background_color']) ?? '',
        backgroundBottomColor: jsonString(data['background_bottom_color']) ?? '',
      ),
    );
  }

  static LiveMessage _audience(LiveAudienceMetricKind kind, int value) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    color: LiveMessageColor.white,
    data: LiveAudienceUpdate(kind: kind, value: value),
  );
}

/// Collects inflated bytes and fails once they pass [limit], so a highly
/// compressible packet is rejected before it is all in memory.
final class _BoundedSink implements Sink<List<int>> {
  new(this.limit);

  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (chunk.length > limit - bytes.length) {
      throw FormatException('Bilibili decompressed message exceeds $limit bytes');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
