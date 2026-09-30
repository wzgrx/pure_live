// Writes expected.json for fixtures/17live/danmaku (docs/modules/M5.29-17live.md).
//
// 3.x had no 17LIVE danmaku (`EmptyDanmaku`), and pure_live_TV has none
// either, so the reference is the archived v4 (archive/v4, 6ba709135):
// `SeventeenliveProtocol` of packages/live_danmaku/lib/src/sites/seventeenlive.dart,
// copied below as it was (lines 10-165), and what `SeventeenliveConnector` sent
// (its token request, the socket of the recorded token, the handshake headers,
// the ATTACH). Only what it imports is stubbed here: v4's event model
// (DanmakuChat, DanmakuGift, DanmakuOnline, AudienceKind) and connector types
// (TextFrame, DecodeContext, FrameResult), cut down to the fields the decoder
// sets.
//
// It writes, for the recordings S05-live and S06-live, the connector's requests
// and frames and, for every received socket frame, whether v4 joined or
// rejected and its events; for S07-synthetic the same per frame of every case
// (or the error v4 threw).
//
// Run from the repository root: dart run fixtures/17live/danmaku/v4_expected.dart
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/17live/danmaku';

const _generator =
    'fixtures/17live/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) SeventeenliveProtocol (auth, '
    'heartbeatInterval, headers, token, endpoint, attach, payload, decode) over every received socket frame (copied '
    'as it was; the event classes cut down to their fields)';

// ---- stand-ins for what v4's seventeenlive.dart imports ----

final class TextFrame extends UnmodifiableListView<int> {
  TextFrame(this.text) : super(utf8.encode(text));
  final String text;
}

enum AudienceKind { popularity, online, cumulative }

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt, required this.now});
  final String room;
  final int session;
  final int receivedAt;
  final DateTime now;
}

final class FrameResult {
  const FrameResult({this.events = const [], this.replies = const [], this.joined = false, this.rejected = false});
  static const empty = FrameResult();
  final List<DanmakuEvent> events;
  final List<List<int>> replies;
  final bool joined;
  final bool rejected;
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
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String text;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'chat',
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'text': text,
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
    this.userId = '',
    this.giftId = '',
    this.count = 1,
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final String userId;
  final String userName;
  final String giftId;
  final String giftName;
  final int count;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'gift',
    'id': id,
    'userId': userId,
    'userName': userName,
    'giftId': giftId,
    'giftName': giftName,
    'count': count,
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

// ---- v4's packages/live_danmaku/lib/src/sites/seventeenlive.dart, lines 10-165, as it was ----

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// 17LIVE's chat (spec/sites/17live.md §7): an anonymous Ably token from
/// `messenger/auth`, then Ably's JSON realtime protocol on the room's
/// channel; message payloads are gzip + base64 JSON. Without I/O.
abstract final class SeventeenliveProtocol {
  /// §7.1 the token source.
  static final Uri auth = Uri.parse('https://api-dsa.17app.co/api/v1/messenger/auth');

  /// §7.2 the server's heartbeat period (`maxIdleInterval`); the client
  /// sends none.
  static const heartbeatInterval = Duration(seconds: 15);

  /// Request and handshake headers.
  static const Map<String, String> headers = {'origin': 'https://17.live', 'user-agent': _userAgent};

  /// §7.1 the Ably token of an auth answer; null unless the provider is
  /// Ably (1).
  static String? token(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['provider'] != 1) return null;
      final token = root['token'];
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.1 the realtime socket for [token].
  static Uri endpoint(String token) => Uri(
    scheme: 'wss',
    host: '17media.realtime.ably.net',
    path: '/',
    queryParameters: {'access_token': token, 'format': 'json', 'heartbeats': 'true', 'v': '3'},
  );

  /// §7.1 the ATTACH message for room [roomId].
  static TextFrame attach(String roomId) => TextFrame(jsonEncode({'action': 10, 'channel': roomId}));

  /// §7.3 a message payload: base64 of gzip of JSON (or plain JSON).
  static Map<String, dynamic>? payload(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is! String || data.isEmpty) return null;
    try {
      final text = data.startsWith('H4sI') ? utf8.decode(gzip.decode(base64.decode(data))) : data;
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.3 decodes one frame of room [roomId].
  static FrameResult decode(Object? data, {required String roomId, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return FrameResult.empty;
    }
    if (root is! Map) return FrameResult.empty;
    switch (root['action']) {
      case 11 when '${root['channel']}' == roomId:
        return const FrameResult(joined: true);
      case 6 || 9 || 13 when root['error'] != null:
        return const FrameResult(rejected: true);
      case 15 when '${root['channel']}' == roomId:
        final messages = root['messages'];
        return FrameResult(
          events: [
            for (final message in messages is List ? messages : const <Object?>[])
              if (message is Map)
                ...?_event(
                  payload(message['data']),
                  id: message['id'] is String ? message['id'] as String : null,
                  context: context,
                ),
          ],
        );
      default:
        return FrameResult.empty;
    }
  }

  static DateTime? _time(Object? millis) =>
      millis is int && millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;

  static List<DanmakuEvent>? _event(
    Map<String, dynamic>? message, {
    required String? id,
    required DecodeContext context,
  }) {
    if (message == null) return null;
    switch (message['type']) {
      case 3:
        final comment = message['commentMsg'];
        if (comment is! Map) return null;
        final body = comment['comment'];
        final text = '${(body is Map ? body['text'] : null) ?? comment['content'] ?? ''}'.trim();
        if (text.isEmpty) return null;
        final user = comment['displayUser'] is Map ? comment['displayUser'] as Map : const <String, Object?>{};
        return [
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '17live:$id',
            sentAt: _time(comment['sendTime']),
            userId: '${user['userID'] ?? ''}',
            userName: '${user['displayName'] ?? user['openID'] ?? ''}',
            text: text,
          ),
        ];
      case 13:
        final gift = message['giftMsg'];
        if (gift is! Map || gift['giftID'] is! String) return null;
        final user = gift['displayUser'] is Map ? gift['displayUser'] as Map : const <String, Object?>{};
        return [
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '17live:$id',
            userId: '${user['userID'] ?? ''}',
            userName: '${user['displayName'] ?? user['openID'] ?? ''}',
            giftId: gift['giftID'] as String,
            giftName: gift['giftID'] as String,
          ),
        ];
      case 38:
        final info = message['liveinfo'];
        final viewers = info is Map ? info['liveViewerCount'] : null;
        if (viewers is! int || viewers < 0) return null;
        return [
          DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
        ];
      default:
        return null;
    }
  }
}

// ---- harness ----

final _context = DecodeContext(room: '17live:0', session: 1, receivedAt: 0, now: DateTime.utc(2026, 9, 28));

/// What `SeventeenliveConnector` sent for [roomId] with [token]: its token
/// request (headers and body), the socket, the handshake headers, the ATTACH
/// and the heartbeat period (it sends no heartbeat).
Map<String, Object?> _connector(String roomId, String token) => {
  'authUrl': SeventeenliveProtocol.auth.toString(),
  'authMethod': 'POST',
  'authHeaders': {
    ...SeventeenliveProtocol.headers,
    'accept': 'application/json',
    'content-type': 'application/json',
    'referer': 'https://17.live/',
  },
  'authBody': '{}',
  'endpoint': SeventeenliveProtocol.endpoint(token).toString(),
  'handshakeHeaders': SeventeenliveProtocol.headers,
  'attach': SeventeenliveProtocol.attach(roomId).text,
  'heartbeatSeconds': SeventeenliveProtocol.heartbeatInterval.inSeconds,
};

Map<String, Object?> _decode(Object data, String roomId) {
  final FrameResult result;
  try {
    result = SeventeenliveProtocol.decode(data, roomId: roomId, context: _context);
  } on Object catch (error) {
    return {'throws': error.runtimeType.toString()};
  }
  return {
    'joined': result.joined,
    'rejected': result.rejected,
    'events': [for (final event in result.events) event.toJson()],
  };
}

Object _frameData(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

Map<String, Object?> _recorded(String name) {
  final meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>;
  final roomId = (meta['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;
  final lines = [
    for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, Object?>,
  ];
  final auth = lines.firstWhere((frame) => frame['url'] == SeventeenliveProtocol.auth.toString());
  final token = SeventeenliveProtocol.token(auth['text']! as String);
  return {
    'roomId': roomId,
    'token': token,
    'connector': _connector(roomId, token!),
    'frames': [
      for (final (index, frame) in lines.indexed)
        if (frame['dir'] == 'in' && frame['url'] == null) {'frame': index, ..._decode(_frameData(frame), roomId)},
    ],
  };
}

Map<String, Object?> _synthetic() {
  final cases = jsonDecode(File('$_root/S07-synthetic/cases.json').readAsStringSync()) as Map<String, Object?>;
  final roomId = cases['roomId']! as String;
  return {
    'roomId': roomId,
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
  _write('S05-live', _recorded('S05-live'));
  _write('S06-live', _recorded('S06-live'));
  _write('S07-synthetic', _synthetic());
}
