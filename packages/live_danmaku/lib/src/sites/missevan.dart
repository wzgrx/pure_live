import 'dart:convert';
import 'dart:math';

import 'package:brotli/brotli.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// Missevan's chat protocol (spec/sites/missevan.md §7), without I/O.
abstract final class MissevanProtocol {
  /// Heartbeat period (§7.4).
  static const heartbeatInterval = Duration(seconds: 30);

  /// The heartbeat text, sent and echoed (§7.4).
  static const heart = '❤️';

  /// §7.1 the guest session request.
  static final Uri sessionUrl = Uri.parse('https://fm.missevan.com/api/user/info');

  /// §7.2 the chat server of [roomId] when the detail names none.
  static Uri endpoint(String roomId) => Uri.parse('wss://im.missevan.com/ws?room_id=$roomId');

  /// §7.1 the `FM_SESS` value of Set-Cookie headers or a cookie string;
  /// null when absent.
  static String? session(Iterable<String> cookies) {
    for (final cookie in cookies) {
      final match = RegExp(r'(?:^|[;,]\s*)FM_SESS=([^;,\s]+)').firstMatch(cookie);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// §7.2 handshake headers for session [session].
  static Map<String, String> headers(String session) => {
    'cookie': 'FM_SESS=$session',
    'origin': 'https://fm.missevan.com',
    'user-agent': _userAgent,
  };

  /// §7.2 the join message.
  static List<int> join(String roomId, String uuid) => utf8.encode(
    jsonEncode({'action': 'join', 'uuid': uuid, 'type': 'room', 'room_id': int.tryParse(roomId) ?? roomId}),
  );

  /// §7.4 the heartbeat frame.
  static List<int> heartbeat() => utf8.encode(heart);

  /// A random version 4 UUID for the join.
  static String uuid(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// §7.3 the JSON text of a received message: text frames as they are,
  /// binary frames with flag 1 Brotli-decoded and checked against the
  /// declared UTF-8 length; null for anything else.
  static String? text(Object? data) {
    if (data is String) return data;
    if (data is! List<int> || data.length <= 4 || data[0] != 1) return null;
    final size = data[1] | data[2] << 8 | data[3] << 16;
    final List<int> plain;
    try {
      plain = brotli.decode(data.sublist(4));
    } on Object {
      return null;
    }
    if (plain.length != size) return null;
    return utf8.decode(plain, allowMalformed: true);
  }

  /// §7.5 decodes one received message for room [roomId].
  static FrameResult decode(Object? data, {required String roomId, required DecodeContext context}) {
    final json = text(data);
    if (json == null || json == heart) return FrameResult.empty;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return FrameResult.empty;
    }
    final items = decoded is List ? decoded : [decoded];
    var joined = false;
    var rejected = false;
    final events = <DanmakuEvent>[];
    for (final item in items) {
      if (item is! Map) continue;
      try {
        final type = item['type'];
        final event = item['event'];
        if (type == 'room' && event == 'join') {
          if (item['code'] == 0) {
            joined = true;
          } else {
            rejected = true;
          }
          continue;
        }
        if ('${item['room_id'] ?? roomId}' != roomId) continue;
        switch ((type, event)) {
          case ('message', 'new' || 'danmaku'):
            if (_chat(item, context) case final chat?) events.add(chat);
          case ('gift', 'send'):
            if (_gift(item, context) case final gift?) events.add(gift);
          case ('room', 'statistics'):
            events.addAll(_statistics(item, context));
          default:
            break;
        }
      } on Object {
        // One malformed item must not drop the rest of the frame.
      }
    }
    return FrameResult(events: events, joined: joined, rejected: rejected);
  }

  static DanmakuChat? _chat(Map<dynamic, dynamic> item, DecodeContext context) {
    final text = '${item['message'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final user = item['user'];
    final titles = user is Map && user['titles'] is List ? user['titles'] as List : const <Object?>[];
    Map<dynamic, dynamic>? title(String type) =>
        titles.whereType<Map<dynamic, dynamic>>().where((entry) => entry['type'] == type).firstOrNull;
    final id = '${item['msg_id'] ?? ''}';
    final time = item['time'] ?? item['create_time'];
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id.isEmpty ? null : 'missevan:$id',
      sentAt: time is int && time > 0 ? DateTime.fromMillisecondsSinceEpoch(time) : null,
      userId: user is Map ? '${user['user_id'] ?? ''}' : '',
      userName: user is Map ? '${user['username'] ?? ''}' : '',
      text: text,
      userLevel: _int(title('level')?['level']),
      medalLevel: _int(title('medal')?['level']),
      medalName: title('medal')?['name'] as String?,
    );
  }

  static DanmakuGift? _gift(Map<dynamic, dynamic> item, DecodeContext context) {
    final gift = item['gift'];
    final user = item['user'];
    if (gift is! Map || '${gift['name'] ?? ''}'.isEmpty) return null;
    final time = item['time'];
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      sentAt: time is int && time > 0 ? DateTime.fromMillisecondsSinceEpoch(time) : null,
      userId: user is Map ? '${user['user_id'] ?? ''}' : '',
      userName: user is Map ? '${user['username'] ?? ''}' : '',
      giftId: '${gift['gift_id'] ?? ''}',
      giftName: '${gift['name']}',
      count: _int(gift['num']) ?? 1,
      icon: gift['icon_url'] is String ? Uri.tryParse(gift['icon_url'] as String) : null,
    );
  }

  /// §7.5 figures of `room`/`statistics`: `score` is heat, `online` the
  /// listeners in the room right now.
  static List<DanmakuOnline> _statistics(Map<dynamic, dynamic> item, DecodeContext context) {
    final holder = item['statistics'];
    if (holder is! Map) return const [];
    return [
      for (final (key, kind) in const [('score', AudienceKind.popularity), ('online', AudienceKind.online)])
        if (_int(holder[key]) case final value? when value >= 0)
          DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: kind,
            value: value,
          ),
    ];
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
}

/// Missevan's chat connection: a guest session per start, one server, a
/// 30 s heartbeat.
final class MissevanConnector extends SocketConnector {
  /// Creates the connector; [credentials] may supply the user's cookie.
  new({
    required super.detail,
    required super.transport,
    this.credentials,
    super.session,
    super.clock,
    super.policy,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Source of the user's cookie, if any.
  final DanmakuCredentials? credentials;

  final Random _random;

  String get _roomId => detail.danmakuKeys['roomId'] ?? room.roomId;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    String? session;
    if (!refresh) {
      final user = await credentials?.cookie('missevan');
      session = user == null ? null : MissevanProtocol.session([user]);
    }
    if (session == null) {
      final LiveResponse response;
      try {
        response = await transport.http.send(
          LiveRequest(
            site: 'missevan',
            url: MissevanProtocol.sessionUrl,
            headers: const {'user-agent': _userAgent, 'referer': 'https://fm.missevan.com/'},
          ),
        );
      } on Object catch (error) {
        throw DanmakuStartFailure('credentials', '$error');
      }
      session = MissevanProtocol.session(response.headers['set-cookie'] ?? const []);
      if (session == null) throw DanmakuStartFailure('credentials', 'no guest session (HTTP ${response.status})');
    }
    final named = detail.danmakuKeys['websocket'];
    final endpoint = named == null ? null : Uri.tryParse(named);
    return SocketPlan(
      endpoints: [if (endpoint != null && endpoint.scheme == 'wss') endpoint else MissevanProtocol.endpoint(_roomId)],
      headers: MissevanProtocol.headers(session),
    );
  }

  @override
  List<List<int>> openFrames() => [MissevanProtocol.join(_roomId, MissevanProtocol.uuid(_random))];

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => MissevanProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => MissevanProtocol.heartbeat();

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      MissevanProtocol.decode(data, roomId: _roomId, context: context);
}
