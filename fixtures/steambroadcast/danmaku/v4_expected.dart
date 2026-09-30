// Writes fixtures/steambroadcast/danmaku/S07-live/expected.json: what the
// archived v4 Steam broadcast chat protocol read from the recording
// (docs/modules/M5.23-steambroadcast.md, "与归档 v4 的对照"). 3.x had no
// Steam chat, and pure_live_TV has none either (`EmptyDanmaku`), so the
// archived v4 is the only earlier implementation; it recorded this sample
// itself.
//
// Below the harness, `SteamChatPoll` and `SteamBroadcastProtocol` (without
// `headers`, which the harness does not use) are copied verbatim from
// archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/steambroadcast.dart.
// Only what they import from elsewhere is stubbed here: v4's `DanmakuEvent`
// and `DanmakuChat` with the fields the protocol sets, and `DecodeContext`.
//
// The harness reads the recorded `getbroadcastmpd` answer with
// `broadcastId`, the `getchatinfo` answer with `chatTemplate`, and every
// chat log answer with `parse` (at the window time of its URL), and writes
// v4's request URLs, the broadcast id, the template and, per answer, the
// window, the next window, `initial_delay` and the chat lines (projected).
//
// Run from the repository root:
//
//   dart run fixtures/steambroadcast/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

const _sample = 'fixtures/steambroadcast/danmaku/S07-live';
const _generator =
    'archived v4 SteamBroadcastProtocol.broadcastId, chatTemplate, messagesUrl and parse (archive/v4 6ba709135) over '
    'the recorded getbroadcastmpd, getchatinfo and chat log answers (fixtures/steambroadcast/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final steamId = (meta['danmakuKeys'] as Map<String, dynamic>)['steamid'] as String;
  final context = DecodeContext(room: meta['room'] as String, session: 1, receivedAt: 0);
  String? broadcast;
  String? template;
  final windows = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in') continue;
    final url = Uri.parse(line['url'] as String);
    final text = line['text'] as String;
    if (url.path.endsWith('/getbroadcastmpd/')) {
      broadcast = SteamBroadcastProtocol.broadcastId(text);
      continue;
    }
    if (url.path.endsWith('/getchatinfo/')) {
      template = SteamBroadcastProtocol.chatTemplate(text);
      continue;
    }
    final time = int.parse(url.pathSegments.last);
    final poll = SteamBroadcastProtocol.parse(text, time: time, context: context);
    windows.add({
      'line': index + 1,
      'time': time,
      'url': SteamBroadcastProtocol.messagesUrl(template!, time).toString(),
      'next': poll.next,
      'initialDelay': poll.initialDelay?.inMilliseconds,
      'events': [for (final event in poll.events) _project(event)],
    });
  }
  final expected = {
    'generator': _generator,
    'value': {
      'broadcastUrl': SteamBroadcastProtocol.broadcastUrl(steamId).toString(),
      'broadcastId': broadcast,
      'chatInfoUrl': SteamBroadcastProtocol.chatInfoUrl(steamId, broadcast!).toString(),
      'template': template,
      'windows': windows,
    },
  };
  File('$_sample/expected.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(expected)}\n');
  stdout.writeln('wrote $_sample/expected.json: ${windows.length} windows');
}

Map<String, Object?> _project(DanmakuEvent event) => switch (event) {
  DanmakuChat() => {
    'type': 'chat',
    'id': event.id,
    'userId': event.userId,
    'userName': event.userName,
    'text': event.text,
  },
};

// Stubs of what the v4 code imports ------------------------------------------

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

sealed class DanmakuEvent {
  const DanmakuEvent({required this.room, required this.session, required this.receivedAt, this.id});
  final String room;
  final int session;
  final int receivedAt;
  final String? id;
}

final class DanmakuChat extends DanmakuEvent {
  const DanmakuChat({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    super.id,
    this.userId = '',
  });
  final String userId;
  final String userName;
  final String text;
}

// Copied from archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/steambroadcast.dart
// (`headers` and the connector, which the harness does not use, are left out).

/// One parsed chat poll.
@immutable
final class SteamChatPoll {
  /// Creates a poll result.
  const new({required this.next, required this.events, this.initialDelay});

  /// Chat-log time (ms) of the next window (`next_request`).
  final int next;

  /// Only on a first poll: how long to wait before requesting [next].
  final Duration? initialDelay;

  /// Chat lines in order.
  final List<DanmakuEvent> events;
}

/// Steam broadcast chat (spec/sites/steambroadcast.md §7), without I/O:
/// `getbroadcastmpd` gives the broadcast id, `getchatinfo` a URL template,
/// and the template is read window by window along the chat log's clock.
abstract final class SteamBroadcastProtocol {
  /// The broadcast manifest request, which names the current broadcast.
  static Uri broadcastUrl(String steamId) => Uri.https('steamcommunity.com', '/broadcast/getbroadcastmpd/', {
    'broadcastid': '0',
    'steamid': steamId,
    'viewertoken': '0',
    'sessionid': '',
  });

  /// The chat info request for [broadcastId].
  static Uri chatInfoUrl(String steamId, String broadcastId) => Uri.https(
    'steamcommunity.com',
    '/broadcast/getchatinfo/',
    {'steamid': steamId, 'broadcastid': broadcastId, 'viewertoken': '0', 'sessionid': ''},
  );

  static Map<String, dynamic> _object(String body, String what) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw FormatException('$what: not an object');
    return decoded;
  }

  /// `getbroadcastmpd` → the broadcast id, or null when not broadcasting.
  static String? broadcastId(String body) {
    final json = _object(body, 'getbroadcastmpd');
    if (json['success'] != 'ready') return null;
    final id = json['broadcastid']?.toString() ?? '';
    return RegExp(r'^[1-9]\d*$').hasMatch(id) ? id : null;
  }

  /// `getchatinfo` → the message URL template (`…/messages/{0}?…`).
  static String chatTemplate(String body) {
    final json = _object(body, 'getchatinfo');
    final template = json['view_url_template'];
    if (json['success'] != 1 || template is! String || !template.contains('{0}')) {
      throw FormatException('getchatinfo: success ${json['success']}');
    }
    return template;
  }

  /// The URL of the chat window at [time]; 0 asks for the latest history.
  static Uri messagesUrl(String template, int time) => Uri.parse(template.replaceFirst('{0}', '$time'));

  /// One window; ids combine the window time and the position in it.
  static SteamChatPoll parse(String body, {required int time, required DecodeContext context}) {
    final json = _object(body, 'messages');
    final next = json['next_request'];
    if (next is! int || next <= 0) throw FormatException('messages: next_request $next');
    final delay = json['initial_delay'];
    final events = <DanmakuEvent>[];
    final messages = json['messages'];
    if (messages is List) {
      for (final (index, message) in messages.indexed) {
        if (message is! Map) continue;
        final text = message['msg']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final name = message['persona_name']?.toString().trim() ?? '';
        events.add(
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: 'steambroadcast:$time:$index',
            userId: message['steamid']?.toString() ?? '',
            userName: name.isEmpty ? 'Steam' : name,
            text: text,
          ),
        );
      }
    }
    return SteamChatPoll(
      next: next,
      events: events,
      initialDelay: delay is int && delay >= 0 ? Duration(milliseconds: delay) : null,
    );
  }
}
