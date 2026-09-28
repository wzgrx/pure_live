// Writes expected.json for fixtures/chzzk/danmaku (docs/modules/M5.16-chzzk.md).
//
// 3.x had no CHZZK danmaku (`EmptyDanmaku`), and pure_live_TV has none
// either, so the reference is the archived v4 (archive/v4, 6ba709135):
// `ChzzkProtocol` of packages/live_danmaku/lib/src/sites/chzzk.dart, copied
// below as it was, and what `ChzzkConnector` sent (its token request, the
// server it picked, the handshake headers, the join and the ping). Only what
// it imports is stubbed here: v4's event model (DanmakuChat, DanmakuGift,
// DanmakuOnline, AudienceKind) and connector types (DecodeContext,
// FrameResult), cut down to the fields the decoder sets.
//
// It writes, for the recordings S09-live and S10-live, the connector's
// requests and frames and, for every received chat frame, whether v4 joined
// or was refused, its replies and its events; for S11-recent the same per
// answer (each of another chat channel); for S12-synthetic the same per frame
// of every case.
//
// Run from the repository root: dart run fixtures/chzzk/danmaku/v4_expected.dart
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/chzzk/danmaku';

const _generator =
    'fixtures/chzzk/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) ChzzkProtocol (tokenUrl, '
    'accessToken, endpoint, headers, join, recent, ping, pong, decode) over every received frame (copied as it '
    'was; the event classes cut down to their fields)';

// ---- stand-ins for what v4's chzzk.dart imports ----

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
    this.sentAt,
    this.userId = '',
    this.count = 1,
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String giftName;
  final int count;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'gift',
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
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

// ---- v4's packages/live_danmaku/lib/src/sites/chzzk.dart, ChzzkProtocol as it was ----

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// CHZZK's chat protocol (spec/sites/chzzk.md §7), without I/O. Messages
/// are JSON; the client sends them as UTF-8 in binary frames, which the
/// server accepts, and receives text frames.
abstract final class ChzzkProtocol {
  /// Heartbeat period (§7.3).
  static const heartbeatInterval = Duration(seconds: 20);

  /// Recent chat lines asked for after joining (§7.2).
  static const recentCount = 50;

  /// Handshake headers (§7.2).
  static const Map<String, String> headers = {'origin': 'https://chzzk.naver.com', 'user-agent': _userAgent};

  /// §7.2 the chat server of [chatChannelId]: `kr-ss<n>` with `n` the sum of
  /// its character codes modulo 9, plus 1.
  static Uri endpoint(String chatChannelId) {
    final server = chatChannelId.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 9 + 1;
    return Uri.parse('wss://kr-ss$server.chat.naver.com/chat');
  }

  /// §7.1 the access token request.
  static Uri tokenUrl(String chatChannelId) => Uri.https('comm-api.game.naver.com', '/nng_main/v1/chats/access-token', {
    'channelId': chatChannelId,
    'chatType': 'STREAMING',
  });

  /// §7.1 the access token of a token response; null when absent.
  static String? accessToken(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['code'] != 200) return null;
      final content = root['content'];
      final token = content is Map ? content['accessToken'] : null;
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  static List<int> _frame(Map<String, Object?> message) => utf8.encode(jsonEncode(message));

  /// §7.2 the join message (anonymous, read only).
  static List<int> join(String chatChannelId, String token) => _frame({
    'ver': '3',
    'cmd': 100,
    'svcid': 'game',
    'cid': chatChannelId,
    'bdy': {'uid': null, 'devType': 2001, 'accTkn': token, 'auth': 'READ'},
    'tid': 1,
  });

  /// §7.2 the recent chat request after joining with session [sid].
  static List<int> recent(String chatChannelId, String sid) => _frame({
    'ver': '3',
    'cmd': 5101,
    'svcid': 'game',
    'cid': chatChannelId,
    'sid': sid,
    'bdy': {'recentMessageCount': recentCount},
    'tid': 2,
  });

  /// §7.3 the client ping.
  static List<int> ping() => _frame({'ver': '3', 'cmd': 0});

  /// §7.3 the answer to a server ping.
  static List<int> pong() => _frame({'ver': '3', 'cmd': 10000});

  /// §7.2–§7.4 decodes one received message of [chatChannelId]'s chat.
  static FrameResult decode(Object? data, {required String chatChannelId, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return FrameResult.empty;
    }
    if (decoded is! Map) return FrameResult.empty;
    final cmd = decoded['cmd'];
    switch (cmd) {
      case 0:
        return FrameResult(replies: [pong()]);
      case 10100:
        final body = decoded['bdy'];
        final sid = body is Map ? body['sid'] : null;
        if (decoded['retCode'] != 0 || sid is! String) return const FrameResult(rejected: true);
        return FrameResult(joined: true, replies: [recent(chatChannelId, sid)]);
      case 93101 || 93102:
        final items = decoded['bdy'];
        if (items is! List) return FrameResult.empty;
        return FrameResult(events: _messages(items, context, recent: false));
      case 15101:
        final body = decoded['bdy'];
        final items = body is Map ? body['messageList'] : null;
        if (items is! List) return FrameResult.empty;
        return FrameResult(events: _messages(items, context, recent: true));
      default:
        return FrameResult.empty;
    }
  }

  /// §7.4 chat and donation items; the live (93101/93102) and recent
  /// (15101) forms differ only in field names. The last member count of a
  /// live frame becomes one online figure.
  static List<DanmakuEvent> _messages(List<dynamic> items, DecodeContext context, {required bool recent}) {
    final events = <DanmakuEvent>[];
    int? members;
    for (final item in items) {
      if (item is! Map) continue;
      try {
        members = _int(item[recent ? 'memberCount' : 'mbrCnt']) ?? members;
        events.addAll(_message(item, context, recent: recent));
      } on Object {
        // One malformed item must not drop the rest of the frame.
      }
    }
    if (!recent && members != null && members >= 0) {
      events.add(
        DanmakuOnline(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          audience: AudienceKind.online,
          value: members,
        ),
      );
    }
    return events;
  }

  static List<DanmakuEvent> _message(Map<dynamic, dynamic> item, DecodeContext context, {required bool recent}) {
    final status = item[recent ? 'messageStatusType' : 'msgStatusType'];
    if (status != null && status != 'NORMAL') return const [];
    final type = _int(item[recent ? 'messageTypeCode' : 'msgTypeCode']);
    final text = '${item[recent ? 'content' : 'msg'] ?? ''}'.trim();
    final userId = '${item[recent ? 'userId' : 'uid'] ?? ''}';
    final time = _int(item[recent ? 'messageTime' : 'msgTime']);
    final profile = _object(item['profile']);
    final extras = _object(item['extras']);
    final anonymous = extras?['isAnonymous'] == true;
    final name = anonymous ? '匿名' : '${profile?['nickname'] ?? ''}';
    final sentAt = time == null || time <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(time);
    final id = userId.isEmpty || time == null ? null : 'chzzk:$userId:$time';
    final events = <DanmakuEvent>[];
    final amount = _int(extras?['payAmount']);
    if (type == 10 || amount != null) {
      if (amount != null && amount > 0) {
        events.add(
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '$id:gift',
            sentAt: sentAt,
            userId: anonymous ? '' : userId,
            userName: name,
            giftName: '치즈',
            count: amount,
          ),
        );
      }
    } else if (type != null && type != 1) {
      // Images, stickers and system lines carry no chat text.
      return const [];
    }
    if (text.isNotEmpty) {
      events.add(
        DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: anonymous ? '' : userId,
          userName: name,
          text: text,
        ),
      );
    }
    return events;
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

// ---- harness ----

final _context = DecodeContext(room: 'chzzk:0', session: 1, receivedAt: 0, now: DateTime.utc(2026, 9, 29));

Object _frameData(Map<String, Object?> frame) => switch (frame) {
  {'text': final String text} => text,
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

Map<String, Object?> _decode(Object data, String chatChannelId) {
  final result = ChzzkProtocol.decode(data, chatChannelId: chatChannelId, context: _context);
  return {
    'joined': result.joined,
    'rejected': result.rejected,
    'replies': [for (final reply in result.replies) jsonDecode(utf8.decode(reply))],
    'events': [for (final event in result.events) event.toJson()],
  };
}

/// What `ChzzkConnector` sent for [chatChannelId] with [token]: its token
/// request (with the handshake headers, as v4 sent it), the one server, the
/// handshake headers, the join and the ping.
Map<String, Object?> _connector(String chatChannelId, String token) => {
  'tokenUrl': ChzzkProtocol.tokenUrl(chatChannelId).toString(),
  'tokenHeaders': ChzzkProtocol.headers,
  'endpoint': ChzzkProtocol.endpoint(chatChannelId).toString(),
  'handshakeHeaders': ChzzkProtocol.headers,
  'join': utf8.decode(ChzzkProtocol.join(chatChannelId, token)),
  'ping': utf8.decode(ChzzkProtocol.ping()),
  'heartbeatSeconds': ChzzkProtocol.heartbeatInterval.inSeconds,
};

List<Map<String, Object?>> _lines(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, Object?>,
];

Map<String, Object?> _recorded(String name) {
  final meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>;
  final chat = (meta['danmakuKeys']! as Map<String, Object?>)['chatChannelId']! as String;
  final lines = _lines(name);
  final tokenFrame = lines.firstWhere((frame) => '${frame['url']}'.contains('/chats/access-token'));
  final token = ChzzkProtocol.accessToken(tokenFrame['text']! as String);
  return {
    'chatChannelId': chat,
    'accessToken': token,
    'connector': _connector(chat, token!),
    'frames': [
      for (final (index, frame) in lines.indexed)
        if (frame['dir'] == 'in' && frame['url'] == null) {'frame': index, ..._decode(_frameData(frame), chat)},
    ],
  };
}

Map<String, Object?> _recent(String name) {
  final meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>;
  final keys = (meta['danmakuKeys']! as List<Object?>).cast<Map<String, Object?>>();
  final lines = _lines(name);
  return {
    'frames': [
      for (final (index, frame) in lines.indexed)
        {
          'frame': index,
          'chatChannelId': keys[index]['chatChannelId'],
          ..._decode(_frameData(frame), keys[index]['chatChannelId']! as String),
        },
    ],
  };
}

Map<String, Object?> _synthetic() {
  final cases = jsonDecode(File('$_root/S12-synthetic/cases.json').readAsStringSync()) as Map<String, Object?>;
  final chat = cases['chatChannelId']! as String;
  return {
    'connector': _connector(chat, '<token>'),
    'cases': {
      for (final entry in cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames})
          name: [for (final frame in frames.cast<Map<String, Object?>>()) _decode(_frameData(frame), chat)],
    },
  };
}

void _write(String name, Map<String, Object?> value) {
  final file = File('$_root/$name/expected.json');
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n');
  stdout.writeln('wrote ${file.path}');
}

void main() {
  _write('S09-live', _recorded('S09-live'));
  _write('S10-live', _recorded('S10-live'));
  _write('S11-recent', _recent('S11-recent'));
  _write('S12-synthetic', _synthetic());
}
