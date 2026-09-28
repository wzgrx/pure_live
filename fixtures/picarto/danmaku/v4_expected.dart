// Writes expected.json for fixtures/picarto/danmaku (docs/modules/M5.10-picarto.md).
//
// 3.x had no Picarto danmaku, so the reference is the archived v4 (archive/v4,
// 6ba709135): `PicartoProtocol` and the request of `PicartoConnector.plan` in
// packages/live_danmaku/lib/src/sites/picarto.dart, with `DanmakuColors` from
// packages/live_danmaku/lib/src/model.dart. They are copied below as they
// were; only the event classes are cut down to their fields, and a decode
// that throws is written as {"throws": <type>}.
//
// Run from the repository root: dart run fixtures/picarto/danmaku/v4_expected.dart
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/picarto/danmaku';

const _generator =
    'fixtures/picarto/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) PicartoProtocol.token over '
    'the token answer, PicartoProtocol.endpoint, and PicartoProtocol.decode over every incoming frame (copied as '
    'they were; the event classes cut down to their fields)';

// ---- archive/v4 packages/live_danmaku/lib/src/model.dart (excerpt) ----

enum AudienceKind { online }

abstract final class DanmakuColors {
  /// The default chat colour.
  static const white = 0xFFFFFF;

  /// The RGB part of a platform colour number: 4 and 6 hex digits are RGB,
  /// 8 digits are ARGB and the alpha is ignored (§1).
  static int fromNumber(int value) => value & 0xFFFFFF;

  /// Parses `#RRGGBB`, `RRGGBB`, `0xAARRGGBB` and the 4-digit form; null when
  /// [text] is not hex.
  static int? parse(String? text) {
    if (text == null) return null;
    var hex = text.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    } else if (hex.toLowerCase().startsWith('0x')) {
      hex = hex.substring(2);
    }
    if (hex.isEmpty || hex.length > 8 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    return fromNumber(int.parse(hex, radix: 16));
  }
}

// ---- stand-ins for the v4 event model: only the fields decode sets ----

final class DecodeContext {
  DecodeContext({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

sealed class DanmakuEvent {
  Map<String, Object?> toJson();
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

final class DanmakuChat extends DanmakuEvent {
  DanmakuChat({
    required this.room,
    required this.session,
    required this.receivedAt,
    required this.id,
    required this.sentAt,
    required this.userId,
    required this.userName,
    required this.text,
    required this.color,
  });
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String text;
  final int color;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'chat',
    'id': id,
    'sentAt': sentAt?.millisecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'text': text,
    'color': '#${color.toRadixString(16).padLeft(6, '0')}',
  };
}

// ---- archive/v4 packages/live_danmaku/lib/src/sites/picarto.dart ----

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// Picarto's chat (spec/sites/picarto.md §7): an anonymous JWT from the
/// GraphQL API, then a JSON WebSocket the server keeps alive. Without I/O.
abstract final class PicartoProtocol {
  /// The GraphQL endpoint.
  static final Uri graphql = Uri.parse('https://ptvintern.picarto.tv/ptvapi');

  /// Silence watchdog base: the server sends `stream` updates every
  /// 25–60 s (S07-live), so 3 × 60 s without anything is a dead connection.
  static const watchInterval = Duration(seconds: 60);

  /// Request headers.
  static const Map<String, String> headers = {'origin': 'https://picarto.tv', 'user-agent': _userAgent};

  /// §7.1 the token request body for [channel].
  static List<int> tokenQuery(String channel) => utf8.encode(
    jsonEncode({
      'query': r'query ($name: String) { generateJwtToken(channel_name: $name) { key } }',
      'variables': {'name': channel},
    }),
  );

  /// §7.1 the JWT of a token response, or null.
  static String? token(String body) {
    try {
      final root = jsonDecode(body);
      final data = root is Map ? root['data'] : null;
      final generated = data is Map ? data['generateJwtToken'] : null;
      final key = generated is Map ? generated['key'] : null;
      return key is String && key.split('.').length == 3 ? key : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.1 the chat socket for [token].
  static Uri endpoint(String token) => Uri.parse('wss://chat.picarto.tv/chat/token=$token');

  /// §7.2 decodes one received message.
  static List<DanmakuEvent> decode(Object? data, {required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const [];
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    if (root is! Map) return const [];
    if (root['type'] == 'stream') {
      final messages = root['messages'];
      final viewers = messages is Map ? messages['viewers'] : null;
      return [
        if (viewers is int && viewers >= 0)
          DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
      ];
    }
    if (root['t'] != 'c' || root['m'] is! List) return const [];
    return [
      for (final item in root['m'] as List)
        if (item is Map && item['m'] is String && (item['m'] as String).trim().isNotEmpty)
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: item['id'] is String ? 'picarto:${item['id']}' : null,
            sentAt: item['d'] is int ? DateTime.fromMillisecondsSinceEpoch(item['d'] as int) : null,
            userId: '${item['u'] ?? ''}',
            userName: '${item['n'] ?? ''}',
            text: (item['m'] as String).trim(),
            color: DanmakuColors.parse(item['k'] as String?) ?? DanmakuColors.white,
          ),
    ];
  }
}

// ---- the request of v4's PicartoConnector.plan and its socket settings ----

Map<String, Object?> _connector(String channel) => {
  'tokenRequest': {
    'method': 'POST',
    'url': PicartoProtocol.graphql.toString(),
    'headers': const {...PicartoProtocol.headers, 'content-type': 'application/json', 'referer': 'https://picarto.tv/'},
    'body': jsonDecode(utf8.decode(PicartoProtocol.tokenQuery(channel))),
  },
  'handshakeHeaders': PicartoProtocol.headers,
  'openFrames': <Object?>[],
  'heartbeat': null,
  'watchIntervalSeconds': PicartoProtocol.watchInterval.inSeconds,
};

// ---- driver ----

final _context = DecodeContext(room: 'picarto:allatir', session: 1, receivedAt: 0);

Object _decode(Object? data) {
  try {
    return [for (final event in PicartoProtocol.decode(data, context: _context)) event.toJson()];
  } on Object catch (error) {
    return {'throws': error is TypeError ? 'TypeError' : error.runtimeType.toString()};
  }
}

Map<String, Object?> _recorded(String name) {
  final meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, Object?>;
  final channel = (meta['danmakuKeys']! as Map<String, Object?>)['channelName']! as String;
  String? token;
  final frames = <Object?>[];
  var index = 0;
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync()) {
    final frame = jsonDecode(line) as Map<String, Object?>;
    final at = index++;
    if (frame['dir'] != 'in') continue;
    final text = frame['text']! as String;
    if (frame['url'] != null) {
      token = PicartoProtocol.token(text);
      continue;
    }
    frames.add({'frame': at, 'events': _decode(text)});
  }
  return {
    'channel': channel,
    'token': token,
    'endpoint': token == null ? null : PicartoProtocol.endpoint(token).toString(),
    'connector': _connector(channel),
    'frames': frames,
  };
}

Map<String, Object?> _synthetic() {
  final cases = jsonDecode(File('$_root/S11-synthetic/cases.json').readAsStringSync()) as Map<String, Object?>;
  return {
    'cases': {
      for (final entry in cases['cases']! as List<Object?>)
        if (entry case {'name': final String name, 'frames': final List<Object?> frames})
          name: [
            for (final frame in frames)
              _decode(switch (frame) {
                final String text => text,
                {'b64': final String b64} => base64Decode(b64),
                _ => throw FormatException('frame $frame'),
              }),
          ],
    },
  };
}

void _write(String name, Map<String, Object?> value) {
  final file = File('$_root/$name/expected.json');
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n');
  stdout.writeln('wrote ${file.path}');
}

void main() {
  for (final name in const ['S07-live', 'S09-keepalive', 'S10-token-refused']) {
    _write(name, _recorded(name));
  }
  _write('S11-synthetic', _synthetic());
}
