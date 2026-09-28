// Writes fixtures/twitcasting/danmaku/S08-live/expected.json: what the
// archived v4 TwitCasting comment decoder read from the recording
// (docs/modules/M5.11-twitcasting.md, "与归档 v4 的对照"). 3.x had no
// TwitCasting comments, and pure_live_TV has none either (`EmptyDanmaku`),
// so the archived v4 is the only earlier implementation; it recorded this
// sample itself.
//
// Below the harness, `TwitcastingProtocol.socket` and
// `TwitcastingProtocol.decode` are copied verbatim from archive/v4
// (6ba709135) packages/live_danmaku/lib/src/sites/twitcasting.dart. Only what
// they import from elsewhere is stubbed here: v4's `DanmakuEvent` types
// (DanmakuChat, DanmakuGift) with the fields the decoder sets, and
// `DecodeContext`.
//
// The harness reads the recorded `eventpubsuburl.php` answer with `socket`
// and every received socket frame with `decode`, and writes the socket URL
// and, per frame, the events (projected).
//
// Run from the repository root:
//
//   dart run fixtures/twitcasting/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _sample = 'fixtures/twitcasting/danmaku/S08-live';
const _generator =
    'archived v4 TwitcastingProtocol.socket and TwitcastingProtocol.decode (archive/v4 6ba709135) over the recorded '
    'eventpubsuburl.php answer and every received socket frame (fixtures/twitcasting/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final room = meta['room'] as String;
  String? socket;
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in') continue;
    final text = line['text'] as String;
    if (line['url'] != null) {
      socket = TwitcastingProtocol.socket(text)?.toString();
      continue;
    }
    final context = DecodeContext(
      room: room,
      session: 1,
      receivedAt: line['t'] as int,
      now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    frames.add({
      'line': index + 1,
      'events': [for (final event in TwitcastingProtocol.decode(text, context: context)) _project(event)],
    });
  }
  final expected = {
    'generator': _generator,
    'value': {'socket': socket, 'frames': frames},
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
  },
  DanmakuGift() => {
    'type': 'gift',
    'id': event.id,
    'userId': event.userId,
    'userName': event.userName,
    'giftId': event.giftId,
    'giftName': event.giftName,
    'sentAt': event.sentAt?.millisecondsSinceEpoch,
  },
};

// Stubs of what the v4 code imports ------------------------------------------

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt, required this.now});
  final String room;
  final int session;
  final int receivedAt;
  final DateTime now;
}

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
  });
  final String userId;
  final String userName;
  final String text;
}

final class DanmakuGift extends DanmakuEvent {
  const DanmakuGift({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.giftName,
    super.id,
    super.sentAt,
    this.userId = '',
    this.giftId = '',
  });
  final String userId;
  final String userName;
  final String giftId;
  final String giftName;
}

// Copied from archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/twitcasting.dart
// (the class's other members, which the harness does not use, are left out).

abstract final class TwitcastingProtocol {
  /// §7.1 the socket URL of a `eventpubsuburl.php` answer, or null.
  static Uri? socket(String body) {
    try {
      final root = jsonDecode(body);
      final url = root is Map ? Uri.tryParse('${root['url'] ?? ''}') : null;
      return url != null && url.scheme == 'wss' && url.host.endsWith('twitcasting.tv') ? url : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.2 decodes one pushed array.
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
    final items = root is List ? root : [root];
    final events = <DanmakuEvent>[];
    for (final item in items) {
      if (item is! Map) continue;
      final author = item['author'] is Map ? item['author'] as Map : const <Object?, Object?>{};
      final created = item['createdAt'];
      final sentAt = created is int && created > 0 ? DateTime.fromMillisecondsSinceEpoch(created) : null;
      switch (item['type']) {
        case 'comment':
          final message = '${item['message'] ?? ''}'.trim();
          if (message.isEmpty) continue;
          events.add(
            DanmakuChat(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              id: item['id'] == null ? null : 'twitcasting:${item['id']}',
              sentAt: sentAt,
              userId: '${author['id'] ?? ''}',
              userName: '${author['name'] ?? ''}',
              text: message,
            ),
          );
        case 'gift':
          final item0 = item['item'] is Map ? item['item'] as Map : const <Object?, Object?>{};
          final sender = item['sender'] is Map ? item['sender'] as Map : author;
          final name = '${item0['name'] ?? ''}';
          if (name.isEmpty) continue;
          events.add(
            DanmakuGift(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              id: item['id'] == null ? null : 'twitcasting:${item['id']}',
              sentAt: sentAt,
              userId: '${sender['id'] ?? ''}',
              userName: '${sender['name'] ?? ''}',
              giftId: '${item0['id'] ?? ''}',
              giftName: name,
            ),
          );
      }
    }
    return events;
  }
}
