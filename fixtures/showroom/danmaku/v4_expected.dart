// Writes fixtures/showroom/danmaku/S06-live/expected.json: what the archived
// v4 SHOWROOM comment code sent and read in the recording
// (docs/modules/M5.15-showroom.md, "与归档 v4 的对照"). 3.x had no SHOWROOM
// comments, and pure_live_TV has none either (`EmptyDanmaku`), so the
// archived v4 is the only earlier implementation; it recorded this sample
// itself.
//
// Below the harness, `ShowroomProtocol` is copied verbatim from archive/v4
// (6ba709135) packages/live_danmaku/lib/src/sites/showroom.dart. Only what it
// imports from elsewhere is stubbed here: v4's `TextFrame`, its event types
// (DanmakuChat, DanmakuGift) with the fields the decoder sets, and
// `DecodeContext`.
//
// The harness writes the socket address, handshake headers, subscription
// and ping of the recorded broadcast (meta.json's `danmakuKeys`), and every
// received frame's events (projected). v4's chat id ends in the comment
// text's `String.hashCode`, which Dart does not promise to keep across SDKs;
// the test compares only the part before it.
//
// Run from the repository root:
//
//   dart run fixtures/showroom/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

const _sample = 'fixtures/showroom/danmaku/S06-live';
const _generator =
    'archived v4 ShowroomProtocol (archive/v4 6ba709135: endpoint, headers, subscribe, ping, decode) over the '
    "recording's danmakuKeys and every received frame (fixtures/showroom/danmaku/v4_expected.dart)";

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync())
      jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(
    File('$_sample/meta.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final room = meta['room'] as String;
  final keys = (meta['danmakuKeys'] as Map).cast<String, String>();
  final key = keys['bcsvrKey']!;
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in') continue;
    final context = DecodeContext(
      room: room,
      session: 1,
      receivedAt: line['t'] as int,
    );
    frames.add({
      'line': index + 1,
      'events': [
        for (final event in ShowroomProtocol.decode(
          line['text'],
          key: key,
          context: context,
        ))
          _project(event),
      ],
    });
  }
  final expected = {
    'generator': _generator,
    'value': {
      'endpoint': ShowroomProtocol.endpoint(
        keys['bcsvrHost'] ?? ShowroomProtocol.defaultHost,
      ).toString(),
      'headers': ShowroomProtocol.headers,
      'subscribe': ShowroomProtocol.subscribe(key).text,
      'ping': ShowroomProtocol.ping().text,
      'heartbeatSeconds': ShowroomProtocol.heartbeatInterval.inSeconds,
      'frames': frames,
    },
  };
  File('$_sample/expected.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
  );
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
    'count': event.count,
    'sentAt': event.sentAt?.millisecondsSinceEpoch,
  },
};

// Stubs of what the v4 code imports ------------------------------------------

final class TextFrame extends UnmodifiableListView<int> {
  TextFrame(this.text) : super(utf8.encode(text));
  final String text;
}

final class DecodeContext {
  const DecodeContext({
    required this.room,
    required this.session,
    required this.receivedAt,
  });
  final String room;
  final int session;
  final int receivedAt;
}

sealed class DanmakuEvent {
  const DanmakuEvent({
    required this.room,
    required this.session,
    required this.receivedAt,
    this.id,
    this.sentAt,
  });
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
    this.count = 1,
  });
  final String userId;
  final String userName;
  final String giftId;
  final String giftName;
  final int count;
}

// Copied from archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/showroom.dart
// (the connector below it, which the harness does not use, is left out).

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// SHOWROOM's comment broadcast (spec/sites/showroom.md §7): tab-separated
/// text frames on the `bcsvr` host. Without I/O.
abstract final class ShowroomProtocol {
  /// Ping period (§7.2).
  static const heartbeatInterval = Duration(seconds: 60);

  /// The default broadcast host.
  static const defaultHost = 'online.showroom-live.com';

  /// Handshake headers.
  static const Map<String, String> headers = {
    'origin': 'https://www.showroom-live.com',
    'user-agent': _userAgent,
  };

  /// §7.1 the socket on [host].
  static Uri endpoint(String host) => Uri.parse('wss://$host/');

  /// §7.1 the subscription for live key [key].
  static TextFrame subscribe(String key) => TextFrame('SUB\t$key');

  /// §7.2 the ping.
  static TextFrame ping() => TextFrame('PING\tshowroom');

  /// §7.3 decodes one frame of live [key]: `MSG\t<key>\t<json>`.
  static List<DanmakuEvent> decode(
    Object? data, {
    required String key,
    required DecodeContext context,
  }) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null || !text.startsWith('MSG\t')) return const [];
    final parts = text.split('\t');
    if (parts.length < 3 || parts[1] != key) return const [];
    final Object? message;
    try {
      message = jsonDecode(parts.sublist(2).join('\t'));
    } on FormatException {
      return const [];
    }
    if (message is! Map) return const [];
    final created = message['created_at'];
    final sentAt = created is int && created > 0
        ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
        : null;
    final user = '${message['u'] ?? ''}';
    final name = '${message['ac'] ?? ''}';
    switch ('${message['t']}') {
      case '1':
        final comment = '${message['cm'] ?? ''}'.trim();
        if (comment.isEmpty) return const [];
        return [
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: created == null
                ? null
                : 'showroom:$user:$created:${comment.hashCode}',
            sentAt: sentAt,
            userId: user,
            userName: name,
            text: comment,
          ),
        ];
      case '2':
        final gift = '${message['g'] ?? ''}';
        if (gift.isEmpty) return const [];
        final count = message['n'];
        return [
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            sentAt: sentAt,
            userId: user,
            userName: name,
            giftId: gift,
            giftName: '#$gift',
            count: count is int && count > 0 ? count : 1,
          ),
        ];
      default:
        return const [];
    }
  }
}
