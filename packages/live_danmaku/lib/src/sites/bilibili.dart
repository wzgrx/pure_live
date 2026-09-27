import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

/// What one Bilibili frame held besides events.
typedef BilibiliFrame = ({List<DanmakuEvent> events, List<Uint8List> acks, bool? authorized, bool masked, int skipped});

/// Bilibili's chat protocol (spec/sites/bilibili.md §7), without I/O.
///
/// The auth packet asks for `protover` 2 (zlib) instead of 3 (brotli): the
/// server honours it, and `dart:io` inflates zlib without a brotli package
/// (docs/adr/draft-danmaku.md). Brotli packets (protover 3) are skipped.
abstract final class BilibiliProtocol {
  /// Header length (§7.3).
  static const headerLength = 16;

  /// Heartbeat period (§7.6).
  static const heartbeatInterval = Duration(seconds: 30);

  /// Operations (§7.3).
  static const opHeartbeat = 2;

  /// Heartbeat reply with the popularity figure.
  static const opHeartbeatReply = 3;

  /// Notification.
  static const opNotice = 5;

  /// Authentication.
  static const opAuth = 7;

  /// Authentication reply.
  static const opAuthReply = 8;

  /// Acknowledgement.
  static const opAck = 24;

  /// §7.3 hard limits (REG-BILIBILI-009).
  static const int maxMessageBytes = 8 << 20;

  /// Largest inflated size of one message.
  static const int maxInflatedBytes = 16 << 20;

  /// Most packets in one message.
  static const maxPackets = 4096;

  /// Deepest compression nesting.
  static const maxNesting = 2;

  /// §7.3 one client packet (protover 0, seq 1).
  static Uint8List packet(int op, List<int> body) {
    final bytes = Uint8List(headerLength + body.length);
    ByteData.sublistView(bytes)
      ..setUint32(0, bytes.length)
      ..setUint16(4, headerLength)
      ..setUint16(6, 0)
      ..setUint32(8, op)
      ..setUint32(12, 1);
    bytes.setRange(headerLength, bytes.length, body);
    return bytes;
  }

  /// §7.2 the auth packet body; [queueUuid] is 8 lower-case hex digits.
  static Map<String, Object> authBody(BilibiliDanmakuInfo info, {required String queueUuid}) => {
    'uid': info.uid,
    'roomid': info.roomId,
    'protover': 2,
    'buvid': info.buvid,
    'support_ack': true,
    'queue_uuid': queueUuid,
    'scene': 'room',
    'platform': 'web',
    'type': 2,
    'key': info.token,
  };

  /// §7.2 the auth packet.
  static Uint8List auth(BilibiliDanmakuInfo info, {required String queueUuid}) =>
      packet(opAuth, utf8.encode(jsonEncode(authBody(info, queueUuid: queueUuid))));

  /// A new `queue_uuid`.
  static String queueUuid(Random random) => [for (var i = 0; i < 8; i++) random.nextInt(16).toRadixString(16)].join();

  /// §7.6 the heartbeat packet.
  static Uint8List heartbeat() => packet(opHeartbeat, const []);

  /// Decodes one WebSocket message: events, acknowledgements to send
  /// (§7.5), the auth verdict when an op 8 arrived, whether a viewer name
  /// was masked, and how many packets were skipped. A malformed message
  /// keeps what was decoded before the fault (§7.3).
  static BilibiliFrame decode(List<int> message, {required DecodeContext context}) {
    final state = _State(context);
    try {
      if (message.length > maxMessageBytes) throw const FormatException('message too large');
      _packets(message is Uint8List ? message : Uint8List.fromList(message), 0, state);
    } on FormatException {
      state.skipped++;
    }
    return (
      events: state.events,
      acks: state.acks,
      authorized: state.authorized,
      masked: state.masked,
      skipped: state.skipped,
    );
  }

  static void _packets(Uint8List data, int depth, _State state) {
    if (depth > maxNesting) throw const FormatException('nesting too deep');
    final view = ByteData.sublistView(data);
    var offset = 0;
    var count = 0;
    while (offset < data.length) {
      if (++count > maxPackets) throw const FormatException('too many packets');
      if (offset + headerLength > data.length) throw const FormatException('truncated header');
      final length = view.getUint32(offset);
      final header = view.getUint16(offset + 4);
      final version = view.getUint16(offset + 6);
      final op = view.getUint32(offset + 8);
      if (header < headerLength || length < header || offset + length > data.length) {
        throw const FormatException('bad packet length');
      }
      final body = Uint8List.sublistView(data, offset + header, offset + length);
      _packet(version, op, body, depth, state);
      offset += length;
    }
  }

  static void _packet(int version, int op, Uint8List body, int depth, _State state) {
    switch (op) {
      case opHeartbeatReply:
        if (body.length >= 4) state.online(AudienceKind.popularity, ByteData.sublistView(body).getUint32(0));
      case opAuthReply:
        final text = utf8.decode(body, allowMalformed: true).trim();
        final reply = text.isEmpty ? null : jsonDecode(text);
        state.authorized = reply == null || (reply is Map && _int(reply['code']) == 0);
      case opNotice:
        switch (version) {
          case 2:
            _packets(inflate(body), depth + 1, state);
          case 3:
            state.skipped++;
          default:
            final text = utf8.decode(body, allowMalformed: true).trim();
            if (text.isEmpty) return;
            try {
              final notice = jsonDecode(text);
              if (notice is Map<String, dynamic>) _notice(notice, state);
            } on FormatException {
              state.skipped++;
            }
        }
    }
  }

  /// Inflates a zlib body within [maxInflatedBytes].
  static Uint8List inflate(List<int> body) {
    final sink = _BoundedSink(maxInflatedBytes);
    ZLibDecoder().startChunkedConversion(sink)
      ..add(body)
      ..close();
    return sink.bytes.takeBytes();
  }

  static void _notice(Map<String, dynamic> notice, _State state) {
    final ack = acknowledgement(notice);
    if (ack != null) state.acks.add(ack);
    final cmd = notice['cmd']?.toString() ?? '';
    final context = state.context;
    DanmakuEvent? event;
    if (cmd.contains('DANMU_MSG')) {
      event = _chat(notice, state);
    } else if (cmd == 'WATCHED_CHANGE') {
      final value = _int(_map(notice['data'])?['num']);
      if (value != null && value >= 0) state.online(AudienceKind.cumulative, value);
    } else if (cmd == 'SUPER_CHAT_MESSAGE') {
      event = superChat(_map(notice['data']), context);
    } else if (cmd == 'SEND_GIFT') {
      event = _gift(_map(notice['data']), context);
    }
    if (event != null) state.events.add(event);
  }

  /// §7.5 the op 24 packet for a notice that asks for one, or null.
  static Uint8List? acknowledgement(Map<String, dynamic> notice) {
    if (notice['p_is_ack'] != true || !notice.containsKey('p_msg_type')) return null;
    final id = notice['msg_id']?.toString().trim() ?? '';
    final cmd = notice['cmd']?.toString().trim() ?? '';
    final type = _int(notice['p_msg_type']);
    if (id.isEmpty || cmd.isEmpty || type == null) return null;
    return packet(opAck, utf8.encode(jsonEncode({'msg_id': id, 'cmd': cmd, 'p_msg_type': type})));
  }

  /// §7.4 `DANMU_MSG`.
  static DanmakuChat? _chat(Map<String, dynamic> notice, _State state) {
    final info = notice['info'];
    if (info is! List || info.length < 3) return null;
    final meta = info[0] is List ? info[0] as List : const <Object?>[];
    final user = info[2] is List ? info[2] as List : const <Object?>[];
    final text = info[1]?.toString() ?? '';
    if (text.isEmpty) return null;
    final (name, masked) = userName(notice, meta, user.length > 1 ? user[1]?.toString() ?? '' : '');
    if (masked) state.masked = true;
    final nonce = meta.length > 5 ? meta[5]?.toString() ?? '' : '';
    final medal = info.length > 3 && info[3] is List ? info[3] as List : const <Object?>[];
    final level = info.length > 4 && info[4] is List && (info[4] as List).isNotEmpty
        ? _int((info[4] as List)[0])
        : null;
    final color = meta.length > 3 ? _int(meta[3]) ?? 0 : 0;
    final context = state.context;
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: nonce.isEmpty ? null : 'bilibili:$nonce',
      sentAt: _time(meta.length > 4 ? meta[4] : null),
      userId: user.isEmpty ? '' : user[0]?.toString() ?? '',
      userName: name,
      text: text,
      color: color == 0 ? DanmakuColors.white : DanmakuColors.fromNumber(color),
      userLevel: level,
      medalLevel: medal.length > 1 ? _int(medal[0]) : null,
      medalName: medal.length > 1 ? _text(medal[1]) : null,
    );
  }

  /// §7.4 the display name: the first unmasked of `info[0][15]` (maybe a
  /// JSON string) `user.base.name` or `origin_info.name`, top-level `uinfo`,
  /// `data.uinfo`, then [legacy] (`info[2][1]`); the first candidate when
  /// all are masked. The flag says whether the result is masked.
  static (String, bool) userName(Map<String, dynamic> notice, List<Object?> meta, String legacy) {
    var rich = meta.length > 15 ? meta[15] : null;
    if (rich is String && rich.trimLeft().startsWith('{')) {
      try {
        rich = jsonDecode(rich);
      } on FormatException {
        rich = null;
      }
    }
    String read(Object? root) {
      if (root is! Map) return '';
      final user = root['user'] is Map ? root['user'] as Map : root;
      final base = user['base'];
      if (base is! Map) return '';
      final name = base['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
      final origin = base['origin_info'];
      return origin is Map ? origin['name']?.toString().trim() ?? '' : '';
    }

    final candidates = [
      for (final root in [rich, notice['uinfo'], _map(notice['data'])?['uinfo']])
        if (read(root) case final name when name.isNotEmpty) name,
      if (legacy.trim().isNotEmpty) legacy.trim(),
    ];
    for (final candidate in candidates) {
      if (!isMasked(candidate)) return (candidate, false);
    }
    return candidates.isEmpty ? ('', false) : (candidates.first, true);
  }

  /// Whether the platform masked [name] (`**` or `＊＊`).
  static bool isMasked(String name) => RegExp(r'\*{2,}|＊{2,}').hasMatch(name);

  /// §7.4 / §7.7 a `SUPER_CHAT_MESSAGE` data object (also the items of the
  /// `getMessageList` snapshot).
  static DanmakuSuperChat? superChat(Map<String, dynamic>? data, DecodeContext context) {
    if (data == null) return null;
    final start = _int(data['start_time']);
    final end = _int(data['end_time']);
    final price = _int(data['price']);
    final text = data['message']?.toString() ?? '';
    if (start == null || end == null || price == null || text.isEmpty) return null;
    final user = _map(data['user_info']);
    final face = user?['face']?.toString() ?? '';
    final id = data['id']?.toString() ?? '';
    return DanmakuSuperChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id.isEmpty || id == '0' ? null : 'bilibili:sc:$id',
      userName: user?['uname']?.toString() ?? '',
      avatar: face.isEmpty ? null : Uri.tryParse('$face@200w.jpg'),
      text: text,
      price: price,
      startAt: DateTime.fromMillisecondsSinceEpoch(start * 1000),
      endAt: DateTime.fromMillisecondsSinceEpoch(end * 1000),
      backgroundColor: DanmakuColors.parse(data['background_color']?.toString()),
      bottomColor: DanmakuColors.parse(data['background_bottom_color']?.toString()),
    );
  }

  /// `SEND_GIFT`: gold-coin gifts carry their value (1000 coins = 1 yuan).
  static DanmakuGift? _gift(Map<String, dynamic>? data, DecodeContext context) {
    if (data == null) return null;
    final name = data['giftName']?.toString() ?? '';
    if (name.isEmpty) return null;
    final count = _int(data['num']) ?? 1;
    final gold = data['coin_type'] == 'gold' ? _int(data['total_coin']) : null;
    final id = data['tid']?.toString() ?? '';
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id.isEmpty ? null : 'bilibili:gift:$id',
      sentAt: _time(data['timestamp']),
      userId: data['uid']?.toString() ?? '',
      userName: data['uname']?.toString() ?? '',
      giftId: data['giftId']?.toString() ?? '',
      giftName: name,
      count: count,
      yuan: gold == null ? null : gold / 1000,
    );
  }

  static DateTime? _time(Object? raw) {
    final value = _int(raw);
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value > 100000000000 ? value : value * 1000);
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;
}

final class _State {
  new(this.context);

  final DecodeContext context;
  final List<DanmakuEvent> events = [];
  final List<Uint8List> acks = [];
  bool? authorized;
  bool masked = false;
  int skipped = 0;

  void online(AudienceKind audience, int value) => events.add(
    DanmakuOnline(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      audience: audience,
      value: value,
    ),
  );
}

final class _BoundedSink implements Sink<List<int>> {
  new(this.limit);

  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) throw const FormatException('inflated message too large');
    bytes.add(chunk);
  }

  @override
  void close() {}
}

/// Bilibili's chat connection: token from the adapter, auth within 8 s,
/// 30 s heartbeat, acknowledgements, a super chat snapshot once joined.
final class BilibiliConnector extends SocketConnector {
  /// Creates the connector.
  new({
    required super.detail,
    required super.transport,
    required this.credentials,
    super.session,
    super.clock,
    super.policy,
    Random? random,
    Future<void> Function(Duration)? sleep,
  }) : _random = random ?? Random.secure(),
       _sleep = sleep ?? Future<void>.delayed;

  /// Source of tokens.
  final DanmakuCredentials? credentials;

  final Random _random;
  final Future<void> Function(Duration) _sleep;
  BilibiliDanmakuInfo? _info;
  var _maskedReported = false;
  var _snapshotTaken = false;

  static const _gateway = 'wss://broadcastlv.chat.bilibili.com/sub';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final source = credentials;
    if (source == null) throw const DanmakuStartFailure('credentials', 'no bilibili credentials');
    // §7.2: three attempts, 500 ms and 1000 ms apart.
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await _sleep(Duration(milliseconds: 500 * attempt));
      try {
        final info = await source.bilibili(detail);
        if (info.token.isNotEmpty) {
          _info = info;
          return SocketPlan(
            endpoints: info.servers.isEmpty ? [Uri.parse(_gateway)] : info.servers,
            headers: info.headers,
          );
        }
      } on Object catch (error) {
        last = error;
      }
    }
    throw DanmakuStartFailure('credentials', last?.toString());
  }

  @override
  List<List<int>> openFrames() {
    final info = _info;
    return info == null ? const [] : [BilibiliProtocol.auth(info, queueUuid: BilibiliProtocol.queueUuid(_random))];
  }

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => BilibiliProtocol.heartbeatInterval;

  @override
  List<int> heartbeat() => BilibiliProtocol.heartbeat();

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    if (data is! List<int>) return FrameResult.empty;
    final frame = BilibiliProtocol.decode(data, context: context);
    final events = frame.events;
    if (frame.masked && !_maskedReported) {
      _maskedReported = true;
      events.add(
        DanmakuSystem(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          status: DanmakuStatus.bilibiliGuestMasked,
        ),
      );
    }
    return FrameResult(
      events: events,
      replies: frame.acks,
      joined: frame.authorized ?? false,
      rejected: frame.authorized == false,
    );
  }

  @override
  void onJoined(int generation) {
    if (_snapshotTaken) return;
    _snapshotTaken = true;
    unawaited(_snapshot(generation));
  }

  /// §7.7 the super chats pinned before joining.
  Future<void> _snapshot(int generation) async {
    try {
      final info = _info;
      final response = await transport.http.send(
        LiveRequest(
          site: 'bilibili',
          url: Uri.https('api.live.bilibili.com', '/av/v1/SuperChat/getMessageList', {
            'room_id': '${info?.roomId ?? room.roomId}',
          }),
          headers: {'user-agent': info?.headers['user-agent'] ?? BilibiliParse.userAgent},
          timeout: const Duration(seconds: 8),
        ),
      );
      if (!response.isSuccess) return;
      final body = jsonDecode(response.text);
      final data = body is Map ? body['data'] : null;
      final list = data is Map ? data['list'] : null;
      if (list is! List) return;
      final context = this.context();
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final event = BilibiliProtocol.superChat(item, context);
        if (event != null) emit(generation, event);
      }
    } on Object {
      // The snapshot is best effort; live super chats still arrive.
    }
  }
}
