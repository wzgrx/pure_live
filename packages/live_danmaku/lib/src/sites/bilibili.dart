import 'dart:async';
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/binary.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// Bilibili's danmaku connection (3.x `BiliBiliDanmaku`,
/// docs/modules/M5.1-bilibili.md) over the shared WebSocket runtime.
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
    _credentials = _Credentials(run, current);
    return _target(current);
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
    for (final item in BilibiliDanmakuProtocol.decode(data).items) {
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
}

/// Something one received Bilibili message held, in order
/// ([BilibiliDanmakuProtocol.decode]).
@immutable
sealed class BilibiliDanmakuItem {
  const new();
}

/// A message to report: chat, super chat or an audience figure.
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

  /// Protocol version the auth packet asks for: 2 (zlib). 3.x asked for 3
  /// (brotli); `dart:io` has no brotli decoder.
  static const int protocolVersion = 2;

  /// Largest WebSocket message and packet.
  static const int maxMessageBytes = 8 * 1024 * 1024;

  /// Largest inflated packet stream.
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
  /// corrupt or oversized zlib, an auth reply that is not JSON. A notice that
  /// is not JSON, or not a message this decoder knows, is skipped on its
  /// own. Brotli packets are skipped: the auth packet asks for zlib.
  static ({List<BilibiliDanmakuItem> items, FormatException? error}) decode(List<int> message) {
    final items = <BilibiliDanmakuItem>[];
    try {
      if (message.length > maxMessageBytes) {
        throw FormatException('Bilibili danmaku message is too large: ${message.length} bytes');
      }
      _stream(message is Uint8List ? message : Uint8List.fromList(message), 0, items);
    } on FormatException catch (error) {
      return (items: items, error: error);
    }
    return (items: items, error: null);
  }

  static void _stream(Uint8List data, int depth, List<BilibiliDanmakuItem> items) {
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
      _packet(version, operation, Uint8List.sublistView(data, offset + header, offset + length), depth, items);
      offset += length;
    }
    if (offset != data.length) {
      throw FormatException('Incomplete Bilibili danmaku frame: parsed=$offset, total=${data.length}');
    }
  }

  static void _packet(int version, int operation, Uint8List body, int depth, List<BilibiliDanmakuItem> items) {
    switch (operation) {
      case opHeartbeatReply:
        if (body.length < 4) return;
        final value = ByteData.sublistView(body).getUint32(0);
        items.add(BilibiliDanmakuMessage(_audience(LiveAudienceMetricKind.popularity, value)));
      case opNotice:
        switch (version) {
          case 2:
            _stream(_inflate(body), depth + 1, items);
          case 3:
            // Brotli: never asked for.
            return;
          default:
            final text = utf8.decode(body, allowMalformed: true).trim();
            if (text.isNotEmpty) _notice(text, items);
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

  static void _notice(String text, List<BilibiliDanmakuItem> items) {
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
    final message = cmd.contains('DANMU_MSG')
        ? _chat(notice)
        : switch (cmd) {
            'WATCHED_CHANGE' => _watched(notice),
            'SUPER_CHAT_MESSAGE' => _superChat(notice),
            _ => null,
          };
    if (message != null) items.add(BilibiliDanmakuMessage(message));
  }

  /// `DANMU_MSG`: text `info[1]`, colour `info[0][3]` (0 is white), time
  /// `info[0][4]` (milliseconds above 1e11, else seconds), id
  /// `bilibili:` + `info[0][5]`, user id `info[2][0]`, name from
  /// [_userName]. A chat without its user list is not shown.
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
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _userName(notice, meta, user[1]?.toString() ?? ''),
      userId: user[0]?.toString() ?? '',
      message: '${info[1]}',
      color: color == 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
      messageId: nonce.isEmpty ? '' : 'bilibili:$nonce',
      sentAt: sentAt,
    );
  }

  static const int _maxEpochMilliseconds = 8640000000000000;

  /// The display name: the first unmasked of the rich user in `info[0][15]`
  /// (maybe JSON text), the notice's `uinfo`, `data.uinfo` and [legacy]
  /// (`info[2][1]`); the first rich one when all are masked, else [legacy].
  static String _userName(Map<String, dynamic> notice, List<Object?> meta, String legacy) {
    var rich = meta.length > 15 ? meta[15] : null;
    if (rich is String && rich.trimLeft().startsWith('{')) {
      try {
        rich = jsonDecode(rich);
      } on FormatException {
        rich = null;
      }
    }
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

  /// `SUPER_CHAT_MESSAGE`: `data` read like an item of the snapshot
  /// `BilibiliApi.superChats` (M4.1) reads, so both give the same
  /// [LiveSuperChatMessage.messageId] (`data.id`) and the room page merges
  /// them.
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
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: 'SUPER_CHAT_MESSAGE',
      message: 'SUPER_CHAT_MESSAGE',
      color: LiveMessageColor.white,
      data: LiveSuperChatMessage(
        messageId: jsonString(data['id']) ?? '',
        userName: jsonString(userInfo?['uname']) ?? '',
        face: face.isEmpty ? '' : '$face@200w.jpg',
        message: jsonString(data['message']) ?? '',
        price: jsonInt(data['price']) ?? 0,
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
