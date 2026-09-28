// Writes expected.json for the Twitch danmaku samples: 3.x's decoder runs over
// the recorded frames of S07-live and the synthetic frames of S08-synthetic
// (docs/modules/M5.8-twitch.md, "与 v3 的对照").
//
// The code in the "3.x" section is TwitchDanmaku copied from
// legacy/lib/core/danmaku/twitch_danmaku.dart (archive/v4) without `start` and
// `stop` (the socket is tested apart): heartbeat, joinRoom, _parseCookie,
// decodeMessage, parseMessages and _decodeTag, plus the frame conversion of
// start's `onMessage` as `receive`. Only CoreLog is replaced (errors go to
// stderr), `onMessage` is a list, WebScoketUtils is a stub that records what
// `sendMessage` gets, SettingsService is a stub holding the Twitch cookie,
// dart:math's Random is a stub whose nextInt returns 38976 (so the anonymous
// nick is the recorded justinfan39976), and 3.x's LiveMessage and
// LiveMessageColor (with 3.x's numberToColor) are reduced to their fields
// (from legacy/lib/common/models/live_message.dart).
//
// S07-live: every incoming frame of frames.jsonl is decoded in order, with
// what 3.x sent back. joinRoom runs for the recorded channel (meta.json
// `danmakuKeys.login`) with a set of stored cookies, and heartbeat once.
//
// S08-synthetic: the frames of every case of cases.json are decoded in order.
//
// Run from the repository root: dart run fixtures/twitch/danmaku/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/twitch/danmaku';

/// Stored cookies joinRoom runs with; the token is made up.
const _cookies = {
  'none': '',
  'login': 'auth-token=0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o; login=Viewer_01',
  'spaces around names and values': ' auth-token = 0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o ; login = VIEWER_01 ',
  'token only': 'auth-token=0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o',
  'login only': 'login=viewer_01',
  'empty token': 'auth-token=; login=viewer_01',
  'empty login': 'auth-token=0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o; login= ',
  '= inside the token': 'auth-token=abc=def; login=viewer_01',
  'other cookies around them': 'unique_id=x; auth-token=0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o; persistent=y; login=viewer_01',
  'a repeated name (3.x: the last one)': 'auth-token=first; login=viewer_01; auth-token=second',
  'upper-case names (3.x: exact names only)': 'Auth-Token=0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o; Login=viewer_01',
};

void main() {
  _recorded();
  _synthetic();
}

void _recorded() {
  final meta = jsonDecode(File('$_root/S07-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final channel = (meta['danmakuKeys'] as Map)['login'] as String;
  final frames = [
    for (final line in File('$_root/S07-live/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final danmaku = TwitchDanmaku()..webScoketUtils = WebScoketUtils();
  final messages = <Map<String, Object?>>[];
  final sent = <Object?>[];
  for (var index = 0; index < frames.length; index++) {
    final frame = frames[index];
    if (frame['dir'] != 'in') continue;
    danmaku.received.clear();
    danmaku.webScoketUtils!.sent.clear();
    danmaku.receive(frame['text'] as String);
    for (final message in danmaku.received) {
      messages.add({'frame': index, ..._project(message)});
    }
    for (final reply in danmaku.webScoketUtils!.sent) {
      sent.add({'frame': index, 'text': reply});
    }
  }

  List<Object?> join(String roomId, String cookie) {
    SettingsService.to.cookieManager.twitchCookie.v = cookie;
    final sender = TwitchDanmaku()..webScoketUtils = WebScoketUtils();
    sender.joinRoom(roomId);
    return sender.webScoketUtils!.sent;
  }

  final heartbeat = TwitchDanmaku()..webScoketUtils = WebScoketUtils();
  heartbeat.heartbeat();
  _write('$_root/S07-live/expected.json', {
    'generator':
        'fixtures/twitch/danmaku/legacy_expected.dart: 3.x TwitchDanmaku.decodeMessage over every incoming frame '
        '(with what it sent back), joinRoom (the lines it sends for the channel of meta.json danmakuKeys.login with '
        'each stored cookie; Random.secure().nextInt stubbed to 38976) and heartbeat',
    'value': {
      'channel': channel,
      'joinLines': {for (final MapEntry(:key, :value) in _cookies.entries) key: join(channel, value)},
      'cookies': _cookies,
      'joinLinesMixedCase': join(' ZarBex ', ''),
      'heartbeat': heartbeat.webScoketUtils!.sent.single,
      'messages': messages,
      'sent': sent,
    },
  });
}

void _synthetic() {
  final doc = jsonDecode(File('$_root/S08-synthetic/cases.json').readAsStringSync()) as Map<String, dynamic>;
  final results = <Map<String, Object?>>[];
  for (final item in doc['cases'] as List) {
    final testCase = item as Map<String, dynamic>;
    final danmaku = TwitchDanmaku()..webScoketUtils = WebScoketUtils();
    for (final frame in testCase['frames'] as List) {
      danmaku.receive(serverFrame(frame));
    }
    results.add({
      'name': testCase['name'],
      'messages': [for (final message in danmaku.received) _project(message)],
      'sent': danmaku.webScoketUtils!.sent,
    });
  }
  _write('$_root/S08-synthetic/expected.json', {
    'generator':
        'fixtures/twitch/danmaku/legacy_expected.dart: 3.x TwitchDanmaku.decodeMessage over the frames of each case '
        'of cases.json, in order, with what it sent back',
    'value': results,
  });
}

/// One frame of cases.json as the server sends it: a String for a text
/// frame, bytes for a binary one.
Object serverFrame(Object? frame) => switch (frame) {
  final String text => text,
  {'lines': final List lines} => lines.map((line) => '$line\r\n').join(),
  {'b64': final String b64} => base64Decode(b64),
  _ => throw FormatException('frame $frame'),
};

Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'data': message.data,
};

void _write(String path, Object value) {
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Stubs for what 3.x's TwitchDanmaku imports.

abstract final class CoreLog {
  static void error(Object? message) => stderr.writeln('CoreLog.error: $message');
}

/// Records what 3.x sends; always connected.
class WebScoketUtils {
  final List<dynamic> sent = [];

  void sendMessage(dynamic message) => sent.add(message);
}

/// dart:math's Random: `Random.secure().nextInt(99000)` gives 38976, so the
/// anonymous nick is justinfan39976 (the recorded one).
class Random {
  Random.secure();

  int nextInt(int max) => 38976;
}

/// The Twitch cookie of 3.x's settings (`cookieManager.twitchCookie.v`).
class SettingsService {
  static final SettingsService to = SettingsService();

  final _CookieManager cookieManager = _CookieManager();
}

class _CookieManager {
  final _Value twitchCookie = _Value();
}

class _Value {
  String v = '';
}

abstract interface class LiveDanmaku {}

enum LiveMessageType { chat, gift, online, superChat }

class LiveMessageColor {
  final int r, g, b;
  const LiveMessageColor(this.r, this.g, this.b);
  static LiveMessageColor get white => LiveMessageColor(255, 255, 255);
  static LiveMessageColor numberToColor(int intColor) {
    var obj = intColor.toRadixString(16);

    LiveMessageColor color = LiveMessageColor.white;
    if (obj.length == 4) {
      obj = "00$obj";
    }
    if (obj.length == 6) {
      var R = int.parse(obj.substring(0, 2), radix: 16);
      var G = int.parse(obj.substring(2, 4), radix: 16);
      var B = int.parse(obj.substring(4, 6), radix: 16);

      color = LiveMessageColor(R, G, B);
    }
    if (obj.length == 8) {
      var R = int.parse(obj.substring(2, 4), radix: 16);
      var G = int.parse(obj.substring(4, 6), radix: 16);
      var B = int.parse(obj.substring(6, 8), radix: 16);
      //var A = int.parse(obj.substring(0, 2), radix: 16);
      color = LiveMessageColor(R, G, B);
    }

    return color;
  }

  @override
  String toString() {
    return "#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}";
  }
}

class LiveMessage {
  final LiveMessageType type;
  final String userName;
  final String userId;
  final String message;
  final dynamic data;
  final LiveMessageColor color;
  final String userLevel;
  final String fansLevel;
  final String fansName;
  final bool isLocal;
  final String messageId;
  final DateTime? sentAt;

  LiveMessage({
    required this.type,
    required this.userName,
    this.userId = "",
    required this.message,
    this.data,
    required this.color,
    this.userLevel = "",
    this.fansLevel = "",
    this.fansName = "",
    this.isLocal = false,
    this.messageId = "",
    this.sentAt,
  });
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/twitch_danmaku.dart (TwitchDanmaku without
// start, stop and the connection state).

class TwitchDanmaku implements LiveDanmaku {
  WebScoketUtils? webScoketUtils;

  /// The stub's `onMessage`.
  final List<LiveMessage> received = [];

  Function(LiveMessage msg)? get onMessage => received.add;

  int heartbeatTime = 40 * 1000; //默认是40s

  var serverUrl = "wss://irc-ws.chat.twitch.tv";

  void heartbeat() {
    webScoketUtils?.sendMessage("PING :tmi.twitch.tv");
  }

  /// start's `onMessage` callback of WebScoketUtils.
  void receive(dynamic e) {
    decodeMessage(e is String ? e : utf8.decode(e as List<int>, allowMalformed: true));
  }

  void joinRoom(String roomId) {
    final cookie = SettingsService.to.cookieManager.twitchCookie.v;
    final cookieValues = _parseCookie(cookie);
    final token = cookieValues['auth-token']?.trim() ?? '';
    final login = cookieValues['login']?.trim().toLowerCase() ?? '';
    final authenticated = token.isNotEmpty && login.isNotEmpty;
    final user = authenticated ? login : "justinfan${1000 + Random.secure().nextInt(99000)}";
    webScoketUtils
      ?..sendMessage(authenticated ? "PASS oauth:$token" : "PASS SCHMOOPIIE")
      ..sendMessage("NICK $user")
      ..sendMessage("CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership")
      ..sendMessage("JOIN #${roomId.trim().toLowerCase()}");
  }

  static Map<String, String> _parseCookie(String cookie) {
    final result = <String, String>{};
    for (final part in cookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      result[part.substring(0, separator).trim()] = part.substring(separator + 1).trim();
    }
    return result;
  }

  void decodeMessage(String data) {
    try {
      if (data.startsWith("PING")) {
        // respond to PING according to https://dev.twitch.tv/docs/irc/#keepalive-messages
        webScoketUtils?.sendMessage(data.replaceFirst("PING", "PONG").trim());
      }
      for (final message in parseMessages(data)) {
        onMessage?.call(message);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  /// Parses complete Twitch IRC frames. Kept separate from socket delivery so
  /// reconnect, empty-color and escaped display-name cases stay testable.
  List<LiveMessage> parseMessages(String data) {
    final messages = <LiveMessage>[];
    for (final rawLine in data.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (!line.contains(' PRIVMSG ')) continue;

      final tags = <String, String>{};
      if (line.startsWith('@')) {
        final tagEnd = line.indexOf(' ');
        if (tagEnd > 1) {
          for (final entry in line.substring(1, tagEnd).split(';')) {
            final separator = entry.indexOf('=');
            if (separator < 0) continue;
            tags[entry.substring(0, separator)] = _decodeTag(entry.substring(separator + 1));
          }
        }
      }

      final messageStart = line.indexOf(' :', line.indexOf(' PRIVMSG '));
      if (messageStart < 0) continue;
      final content = line.substring(messageStart + 2);
      final prefixMatch = RegExp(r' :?([^! ]+)!').firstMatch(line);
      final userName = (tags['display-name']?.trim().isNotEmpty ?? false)
          ? tags['display-name']!.trim()
          : (prefixMatch?.group(1) ?? 'Twitch');
      final colorText = (tags['color'] ?? '').replaceFirst('#', '');
      final colorValue = int.tryParse(colorText, radix: 16) ?? 0xFFFFFF;
      final timestamp = int.tryParse(tags['tmi-sent-ts'] ?? '');

      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          message: content,
          userName: userName,
          userId: tags['user-id'] ?? '',
          messageId: tags['id'] ?? '',
          sentAt: timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp),
          color: LiveMessageColor.numberToColor(colorValue),
        ),
      );
    }
    return messages;
  }

  static String _decodeTag(String value) => value
      .replaceAll(r'\s', ' ')
      .replaceAll(r'\:', ';')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\\', '\\');
}
