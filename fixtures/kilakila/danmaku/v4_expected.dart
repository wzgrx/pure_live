// Writes expected.json for fixtures/kilakila/danmaku (docs/modules/M5.13-kilakila.md).
//
// 3.x had no KilaKila danmaku, so the reference is the archived v4 (archive/v4,
// 6ba709135): `KilakilaProtocol` in packages/live_danmaku/lib/src/sites/kilakila.dart
// and the socket settings of its `KilakilaConnector` (with the defaults of
// runtime/socket_connector.dart it does not override). The protocol is copied
// below as it was; only the event classes, `FrameResult`, `DecodeContext` and
// `TextFrame` are cut down to their fields, and a decode that throws is written
// as {"throws": <type>} (v4's socket loop dropped such a frame).
//
// Run from the repository root: dart run fixtures/kilakila/danmaku/v4_expected.dart
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/kilakila/danmaku';

const _generator =
    'fixtures/kilakila/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) KilakilaProtocol.endpoint, '
    '.headers, .join, .ping and .decode over every incoming frame (copied as they were; the event classes cut down to '
    'their fields), with the socket settings of KilakilaConnector';

// ---- stand-ins for the v4 model: only the fields decode sets ----

final class TextFrame {
  TextFrame(this.text);
  final String text;
}

final class DecodeContext {
  DecodeContext({
    required this.room,
    required this.session,
    required this.receivedAt,
  });
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

  @override
  Map<String, Object?> toJson() => {
    'kind': 'chat',
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'text': text,
    'userLevel': userLevel,
  };
}

final class DanmakuGift extends DanmakuEvent {
  DanmakuGift({
    required this.room,
    required this.session,
    required this.receivedAt,
    required this.userName,
    required this.giftName,
    this.id,
    this.sentAt,
    this.userId = '',
    this.giftId = '',
    this.count = 1,
    this.icon,
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
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
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'giftId': giftId,
    'giftName': giftName,
    'count': count,
    'icon': icon?.toString(),
  };
}

final class FrameResult {
  const FrameResult({
    this.events = const [],
    this.joined = false,
    this.rejected = false,
  });
  static const empty = FrameResult();
  final List<DanmakuEvent> events;
  final bool joined;
  final bool rejected;

  Map<String, Object?> toJson() => {
    'joined': joined,
    'rejected': rejected,
    'events': [for (final event in events) event.toJson()],
  };
}

// ---- archive/v4 packages/live_danmaku/lib/src/sites/kilakila.dart ----

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// KilaKila's guest chat (spec/sites/kilakila.md §7): Socket.IO 2 over
/// Engine.IO 3 on a WebSocket, namespace `/live_chat_room_guest`. Without
/// I/O.
abstract final class KilakilaProtocol {
  /// Engine.IO ping period (the server announces `pingInterval: 25000`).
  static const heartbeatInterval = Duration(seconds: 25);

  /// The Socket.IO namespace.
  static const namespace = '/live_chat_room_guest';

  /// Handshake headers.
  static const Map<String, String> headers = {
    'origin': 'https://live.kilakila.cn',
    'user-agent': _userAgent,
  };

  static String _query(String roomId) =>
      'roomId=$roomId&appId=111&clientType=1';

  /// §7.1 the socket of broadcast [roomId].
  static Uri endpoint(String roomId) => Uri.parse(
    'wss://wim.hongrenshuo.com.cn/socket.io/?${_query(roomId)}&EIO=3&transport=websocket',
  );

  /// §7.1 the namespace connect packet (a text frame).
  static TextFrame join(String roomId) =>
      TextFrame('40$namespace?${_query(roomId)},');

  /// §7.2 the Engine.IO ping (a text frame).
  static TextFrame ping() => TextFrame('2');

  /// §7.1–§7.3 decodes one received message.
  static FrameResult decode(
    Object? data, {
    required String roomId,
    required DecodeContext context,
  }) {
    if (data is! String) return FrameResult.empty;
    if (data == '40$namespace' || data.startsWith('40$namespace,'))
      return const FrameResult(joined: true);
    const prefix = '42$namespace,';
    if (!data.startsWith(prefix)) return FrameResult.empty;
    final Object? packet;
    try {
      packet = jsonDecode(data.substring(prefix.length));
    } on FormatException {
      return FrameResult.empty;
    }
    if (packet is! List || packet.length < 2 || packet[1] is! String)
      return FrameResult.empty;
    final payload = _object(packet[1]);
    if (payload == null) return FrameResult.empty;
    switch (packet[0]) {
      case 'connect_error':
        // The join answer arrives under this event name; code 0 is success.
        final code = payload['code'];
        return code == 0
            ? const FrameResult(joined: true)
            : const FrameResult(rejected: true);
      case 'text_message':
        final body = payload['body'];
        final response = body is Map ? body['response'] : null;
        if (response is! Map) return FrameResult.empty;
        if ('${response['room_id'] ?? roomId}' != roomId)
          return FrameResult.empty;
        final content = _object(response['content']);
        if (content == null) return FrameResult.empty;
        final created = response['created_at'];
        final sentAt = created is int && created > 0
            ? DateTime.fromMillisecondsSinceEpoch(created)
            : null;
        final id = response['mid'] == null
            ? null
            : 'kilakila:${response['mid']}';
        return FrameResult(
          events: [?_message(content, context, id: id, sentAt: sentAt)],
        );
      default:
        return FrameResult.empty;
    }
  }

  static DanmakuEvent? _message(
    Map<dynamic, dynamic> content,
    DecodeContext context, {
    String? id,
    DateTime? sentAt,
  }) {
    final user = '${content['u'] ?? ''}';
    final name = content['n'] is String ? content['n'] as String : '';
    switch (content['t']) {
      case 200:
        final text = '${content['c'] ?? ''}'.trim();
        if (text.isEmpty) return null;
        return DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: user,
          userName: name,
          text: text,
          userLevel: _int(content['l']),
        );
      case 220:
        final gift = content['c'];
        if (gift is! Map || '${gift['name'] ?? ''}'.isEmpty) return null;
        return DanmakuGift(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: user,
          userName: name,
          giftId: '${gift['id'] ?? ''}',
          giftName: '${gift['name']}',
          count: _int(gift['doubleCount']) ?? 1,
          icon: gift['pic'] is String
              ? Uri.tryParse(gift['pic'] as String)
              : null,
        );
      default:
        return null;
    }
  }

  static Map<dynamic, dynamic>? _object(Object? value) {
    if (value is Map) return value;
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
}

// ---- the socket settings of v4's KilakilaConnector ----

Map<String, Object?> _connector(String roomId) => {
  'endpoints': [KilakilaProtocol.endpoint(roomId).toString()],
  'headers': KilakilaProtocol.headers,
  'openFrames': [KilakilaProtocol.join(roomId).text],
  // KilakilaConnector overrides these three.
  'joinedOnOpen': false,
  'heartbeatSeconds': KilakilaProtocol.heartbeatInterval.inSeconds,
  'heartbeatOnJoin': false,
  'heartbeat': KilakilaProtocol.ping().text,
  // SocketConnector's defaults: authTimeout, silenceTimeout
  // (max(3 × heartbeat, 90 s)), maxRejections, the handshake limit.
  'authTimeoutSeconds': 8,
  'silenceTimeoutSeconds': 90,
  'maxRejections': 3,
  'connectTimeoutSeconds': 10,
  // plan() without a room id: DanmakuStartFailure('credentials', 'no current broadcast').
  'withoutRoom': {'terminal': 'credentials', 'detail': 'no current broadcast'},
};

// ---- driver ----

Object _decode(Object? data, String roomId) {
  final context = DecodeContext(
    room: 'kilakila:$roomId',
    session: 1,
    receivedAt: 0,
  );
  try {
    return KilakilaProtocol.decode(
      data,
      roomId: roomId,
      context: context,
    ).toJson();
  } on Object catch (error) {
    return {
      'throws': error is TypeError ? 'TypeError' : error.runtimeType.toString(),
    };
  }
}

Map<String, Object?> _recorded(String name) {
  final meta = jsonDecode(
    File('$_root/$name/meta.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final roomId =
      (meta['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;
  final frames = <Object?>[];
  var index = 0;
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) {
    final frame = jsonDecode(line) as Map<String, Object?>;
    final at = index++;
    if (frame['dir'] != 'in') continue;
    frames.add({
      'frame': at,
      ...(_decode(frame['text'], roomId) as Map<String, Object?>),
    });
  }
  return {'roomId': roomId, 'connector': _connector(roomId), 'frames': frames};
}

Map<String, Object?> _synthetic() {
  final cases = jsonDecode(
    File('$_root/S09-synthetic/cases.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final roomId = cases['roomId']! as String;
  return {
    'roomId': roomId,
    'cases': {
      for (final entry in cases['cases']! as List<Object?>)
        if (entry case {
          'name': final String name,
          'frames': final List<Object?> frames,
        })
          name: [
            for (final frame in frames)
              _decode(switch (frame) {
                final String text => text,
                {'b64': final String b64} => base64Decode(b64),
                _ => throw FormatException('frame $frame'),
              }, roomId),
          ],
    },
  };
}

void _write(String name, Map<String, Object?> value) {
  final file = File('$_root/$name/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n',
  );
  stdout.writeln('wrote ${file.path}');
}

void main() {
  for (final name in const ['S07-live', 'S08-live-full']) {
    _write(name, _recorded(name));
  }
  _write('S09-synthetic', _synthetic());
}
