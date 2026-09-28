// Writes expected.json for fixtures/missevan/danmaku (docs/modules/M5.12-missevan.md).
//
// 3.x had no Missevan danmaku (`EmptyDanmaku`), and pure_live_TV has none
// either, so the reference is the archived v4 (archive/v4, 6ba709135):
// `MissevanProtocol` of packages/live_danmaku/lib/src/sites/missevan.dart,
// copied below as it was, and what `MissevanConnector` sent (its session
// request headers, handshake headers, join and heartbeat). Only what it
// imports is stubbed here:
//
// - v4's event model (DanmakuChat, DanmakuGift, DanmakuOnline, AudienceKind)
//   and connector types (DecodeContext, FrameResult), cut down to the fields
//   the decoder sets;
// - `package:brotli` (0.6.0, which no longer resolves on Dart 3.13): its
//   `brotli.decode` is live_net's `brotliDecode` here, the RFC 7932 decoder
//   M1.1 checked against the reference decoder (google/brotli), these
//   recordings included. Both decode a valid stream to the same bytes.
//
// It writes, for the recordings S06-live and S07-brotli, the connector's
// requests and frames and, for every received frame, whether v4 read text
// from it, whether it joined or was refused, and its events; for
// S08-synthetic the same per frame of every case.
//
// Run from the repository root: dart run fixtures/missevan/danmaku/v4_expected.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_net/live_net.dart' show brotliDecode;

const _root = 'fixtures/missevan/danmaku';

const _generator =
    'fixtures/missevan/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) MissevanProtocol '
    '(session, headers, join, heartbeat, endpoint, text, decode) over the recorded guest session and every '
    'incoming frame (copied as it was; the event classes cut down to their fields, package:brotli replaced by '
    "live_net's brotliDecode)";

// ---- stand-ins for what v4's missevan.dart imports ----

/// `package:brotli`'s codec, answered by live_net's decoder.
const brotli = _Brotli();

final class _Brotli {
  const _Brotli();

  List<int> decode(List<int> data) => brotliDecode(data);
}

enum AudienceKind { popularity, online, cumulative }

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

sealed class DanmakuEvent {
  Map<String, Object?> toJson();
}

final class DanmakuChat extends DanmakuEvent {
  DanmakuChat({
    required this.room,
    required this.session,
    required this.receivedAt,
    required this.userName,
    required this.text,
    this.id,
    this.sentAt,
    this.userId = '',
    this.userLevel,
    this.medalLevel,
    this.medalName,
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String text;
  final int? userLevel;
  final int? medalLevel;
  final String? medalName;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'chat',
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'text': text,
    'userLevel': userLevel,
    'medalLevel': medalLevel,
    'medalName': medalName,
  };
}

final class DanmakuGift extends DanmakuEvent {
  DanmakuGift({
    required this.room,
    required this.session,
    required this.receivedAt,
    required this.userName,
    required this.giftName,
    this.sentAt,
    this.userId = '',
    this.giftId = '',
    this.count = 1,
    this.icon,
  });
  final String room;
  final int session;
  final int receivedAt;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String giftId;
  final String giftName;
  final int count;
  final Uri? icon;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'gift',
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'giftId': giftId,
    'giftName': giftName,
    'count': count,
    'icon': icon?.toString(),
  };
}

final class DanmakuOnline extends DanmakuEvent {
  DanmakuOnline({
    required this.room,
    required this.session,
    required this.receivedAt,
    required this.audience,
    required this.value,
  });
  final String room;
  final int session;
  final int receivedAt;
  final AudienceKind audience;
  final int value;

  @override
  Map<String, Object?> toJson() => {'kind': 'online', 'audience': audience.name, 'value': value};
}

final class FrameResult {
  const FrameResult({this.events = const [], this.joined = false, this.rejected = false});
  static const empty = FrameResult();
  final List<DanmakuEvent> events;
  final bool joined;
  final bool rejected;
}

// ---- archive/v4 packages/live_danmaku/lib/src/sites/missevan.dart (MissevanProtocol) ----

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

// ---- harness ----

const _context = DecodeContext(room: 'missevan:0', session: 1, receivedAt: 0);

Object _frameData(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

Map<String, Object?> _decode(Object data, String roomId) {
  final result = MissevanProtocol.decode(data, roomId: roomId, context: _context);
  return {
    if (data is List<int>) 'text': MissevanProtocol.text(data) != null,
    'joined': result.joined,
    'rejected': result.rejected,
    'events': [for (final event in result.events) event.toJson()],
  };
}

/// What `MissevanConnector` sent for [roomId]: its guest session request,
/// the handshake of [session], the join with [uuid] and the heartbeat.
Map<String, Object?> _connector(String roomId, {required String session, required String uuid}) => {
  'sessionUrl': MissevanProtocol.sessionUrl.toString(),
  'sessionHeaders': const {'user-agent': _userAgent, 'referer': 'https://fm.missevan.com/'},
  'endpoint': MissevanProtocol.endpoint(roomId).toString(),
  'handshakeHeaders': MissevanProtocol.headers(session),
  'join': utf8.decode(MissevanProtocol.join(roomId, uuid)),
  'heartbeat': utf8.decode(MissevanProtocol.heartbeat()),
  'heartbeatSeconds': MissevanProtocol.heartbeatInterval.inSeconds,
};

Map<String, Object?> _recorded(String name, {String? setCookieSample}) {
  final meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>;
  final roomId = (meta['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;
  final lines = [
    for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, Object?>,
  ];
  final join = lines.firstWhere((frame) => frame['dir'] == 'out');
  final uuid = (jsonDecode(utf8.decode(_bytes(join))) as Map<String, Object?>)['uuid']! as String;
  String? session;
  if (setCookieSample != null) {
    final sample = jsonDecode(File(setCookieSample).readAsStringSync()) as Map<String, Object?>;
    final headers = (sample['response']! as Map<String, Object?>)['headers']! as Map<String, Object?>;
    session = MissevanProtocol.session((headers['set-cookie']! as List<Object?>).cast<String>());
  }
  return {
    'roomId': roomId,
    'uuid': uuid,
    'guestSession': session,
    'connector': _connector(roomId, session: session ?? '<session>', uuid: uuid),
    'frames': [
      for (final (index, frame) in lines.indexed)
        if (frame['dir'] == 'in' && frame['url'] == null) {'frame': index, ..._decode(_frameData(frame), roomId)},
    ],
  };
}

List<int> _bytes(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => utf8.encode(text),
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

Map<String, Object?> _synthetic() {
  final cases = jsonDecode(File('$_root/S08-synthetic/cases.json').readAsStringSync()) as Map<String, Object?>;
  final roomId = cases['roomId']! as String;
  return {
    'cases': {
      for (final entry in cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames})
          name: [for (final frame in frames.cast<Map<String, Object?>>()) _decode(_frameData(frame), roomId)],
    },
  };
}

void _write(String name, Map<String, Object?> value) {
  final file = File('$_root/$name/expected.json');
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n');
  stdout.writeln('wrote ${file.path}');
}

void main() {
  _write('S06-live', _recorded('S06-live', setCookieSample: 'fixtures/missevan/S05-user-info/meta.json'));
  _write('S07-brotli', _recorded('S07-brotli'));
  _write('S08-synthetic', _synthetic());
}
