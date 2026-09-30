// Writes fixtures/fc2live/danmaku/S06-live/expected.json: what the archived
// v4 FC2 Live comment decoder read from the recording
// (docs/modules/M5.22-fc2live.md, "与归档 v4 的对照"). 3.x had no FC2
// comments, and pure_live_TV has none either (`EmptyDanmaku`), so the
// archived v4 is the only earlier implementation; it recorded this sample
// itself.
//
// Below the harness, `Fc2LiveProtocol.colors`, `command`, `decode` and their
// helpers are copied verbatim from archive/v4 (6ba709135)
// packages/live_danmaku/lib/src/sites/fc2live.dart (`headers`, which needs
// v4's grant type, is left out). Only what they import from elsewhere is
// stubbed here: v4's `DanmakuEvent` types (DanmakuChat, DanmakuOnline,
// AudienceKind) with the fields the decoder sets, `DanmakuColors` and
// `DecodeContext`.
//
// The harness writes v4's heartbeat commands 1 to 4 (the recording sent four)
// and reads every received socket frame with `decode`, one counts map for the
// whole recording as v4's connector kept it, writing the events (projected)
// per frame.
//
// Run from the repository root:
//
//   dart run fixtures/fc2live/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _sample = 'fixtures/fc2live/danmaku/S06-live';
const _generator =
    'archived v4 Fc2LiveProtocol.command and Fc2LiveProtocol.decode (archive/v4 6ba709135) over every received '
    'socket frame of the recording, one counts map throughout (fixtures/fc2live/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final room = meta['room'] as String;
  final counts = <String, int>{};
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    // The grant's two HTTP answers carry a URL; the socket's frames do not.
    if (line['dir'] != 'in' || line['url'] != null) continue;
    final context = DecodeContext(room: room, session: 1, receivedAt: line['t'] as int);
    final frame = Fc2LiveProtocol.decode(line['text'] as String, context: context, counts: counts);
    frames.add({
      'line': index + 1,
      'joined': frame.joined,
      'rejected': frame.rejected,
      'events': [for (final event in frame.events) _project(event)],
    });
  }
  final expected = {
    'generator': _generator,
    'value': {
      'heartbeats': [for (var id = 1; id <= 4; id++) utf8.decode(Fc2LiveProtocol.command('heartbeat', id))],
      'frames': frames,
    },
  };
  File('$_sample/expected.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(expected)}\n');
  stdout.writeln('wrote $_sample/expected.json: ${frames.length} frames');
}

Map<String, Object?> _project(DanmakuEvent event) => switch (event) {
  DanmakuChat() => {
    'type': 'chat',
    'id': event.id,
    'userId': event.userId,
    'userName': event.userName,
    'text': event.text,
    'sentAt': event.sentAt?.millisecondsSinceEpoch,
    'color': event.color,
  },
  DanmakuOnline() => {'type': 'online', 'audience': event.audience.name, 'value': event.value},
};

// Stubs of what the v4 code imports ------------------------------------------

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

abstract final class DanmakuColors {
  static const white = 0xFFFFFF;

  static int fromNumber(int value) => value & 0xFFFFFF;

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

enum AudienceKind { popularity, online, cumulative }

sealed class DanmakuEvent {
  const DanmakuEvent({required this.room, required this.session, required this.receivedAt, this.id, this.sentAt});
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
  final DateTime? sentAt;
}

final class DanmakuChat extends DanmakuEvent {
  const DanmakuChat({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    super.id,
    super.sentAt,
    this.userId = '',
    this.color = DanmakuColors.white,
  });
  final String userId;
  final String userName;
  final String text;
  final int color;
}

final class DanmakuOnline extends DanmakuEvent {
  const DanmakuOnline({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.audience,
    required this.value,
    super.id,
    super.sentAt,
  });
  final AudienceKind audience;
  final int value;
}

// Copied from archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/fc2live.dart
// (`headers`, which the harness does not use, is left out).

/// What one FC2 control message held besides events.
typedef Fc2LiveFrame = ({List<DanmakuEvent> events, bool joined, bool rejected});

/// FC2 Live's chat over the control socket (spec/sites/fc2live.md §7),
/// without I/O.
abstract final class Fc2LiveProtocol {
  /// Heartbeat period (§7.2).
  static const heartbeatInterval = Duration(seconds: 30);

  /// Comment colours by name (§7.3); `black` is the page's default and
  /// draws as the overlay default.
  static const Map<String, int> colors = {
    'black': DanmakuColors.white,
    'white': DanmakuColors.white,
    'red': 0xFF0000,
    'pink': 0xFF8080,
    'orange': 0xFFA500,
    'yellow': 0xFFFF00,
    'green': 0x00FF00,
    'cyan': 0x00FFFF,
    'blue': 0x0000FF,
    'purple': 0xC000FF,
  };

  /// A control command as a binary frame (the server reads the JSON text of
  /// binary frames too, §7.2).
  static List<int> command(String name, int id) =>
      utf8.encode(jsonEncode({'name': name, 'arguments': <String, Object?>{}, 'id': id}));

  static int? _count(Object? value) => value is int && value >= 0 ? value : null;

  /// §7.3 decodes one message. Comments replayed on join (`history: 1`)
  /// are dropped; `user_count` updates are partial, so [counts] carries the
  /// last PC and mobile figures between messages.
  static Fc2LiveFrame decode(String text, {required DecodeContext context, required Map<String, int> counts}) {
    final message = jsonDecode(text);
    if (message is! Map) return (events: const [], joined: false, rejected: false);
    final arguments = message['arguments'];
    switch (message['name']) {
      case 'connect_complete':
        return (events: const [], joined: true, rejected: false);
      case 'control_disconnection':
        // 4500: a stale control token; a fresh grant is needed (§7.1).
        return (events: const [], joined: false, rejected: true);
      case 'comment' when arguments is Map && arguments['comments'] is List:
        final events = <DanmakuEvent>[
          for (final comment in (arguments['comments'] as List).whereType<Map<Object?, Object?>>())
            if (_chat(comment, context) case final DanmakuChat chat) chat,
        ];
        return (events: events, joined: false, rejected: false);
      case 'user_count' when arguments is Map:
        final before = {...counts};
        for (final key in const ['pc_user_count', 'mobile_user_count', 'pc_total_count', 'mobile_total_count']) {
          if (_count(arguments[key]) case final int value) counts[key] = value;
        }
        final events = <DanmakuEvent>[];
        final online = _sumOf(counts, 'pc_user_count', 'mobile_user_count');
        final total = _sumOf(counts, 'pc_total_count', 'mobile_total_count');
        if (online != null && online != _sumOf(before, 'pc_user_count', 'mobile_user_count')) {
          events.add(_online(AudienceKind.online, online, context));
        }
        if (total != null && total != _sumOf(before, 'pc_total_count', 'mobile_total_count')) {
          events.add(_online(AudienceKind.cumulative, total, context));
        }
        return (events: events, joined: false, rejected: false);
    }
    return (events: const [], joined: false, rejected: false);
  }

  static int? _sumOf(Map<String, int> counts, String a, String b) =>
      counts[a] == null && counts[b] == null ? null : (counts[a] ?? 0) + (counts[b] ?? 0);

  static DanmakuOnline _online(AudienceKind kind, int value, DecodeContext context) => DanmakuOnline(
    room: context.room,
    session: context.session,
    receivedAt: context.receivedAt,
    audience: kind,
    value: value,
  );

  static DanmakuChat? _chat(Map<Object?, Object?> comment, DecodeContext context) {
    if (comment['history'] == 1) return null;
    final text = '${comment['comment'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final hash = comment['hash'];
    final timestamp = comment['timestamp'];
    final color = '${comment['color'] ?? ''}'.toLowerCase();
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: hash is String && hash.isNotEmpty ? 'fc2live:$hash' : null,
      sentAt: timestamp is int ? DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true) : null,
      userId: '${comment['encrypted_user_id'] ?? ''}',
      userName: '${comment['user_name'] ?? ''}'.trim(),
      text: text,
      color: colors[color] ?? DanmakuColors.parse(color) ?? DanmakuColors.white,
    );
  }
}
