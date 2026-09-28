// Writes fixtures/pandalive/danmaku/S07-live/expected.json: what the archived
// v4 PandaTV chat code sent and read in the recording
// (docs/modules/M5.21-pandalive.md, "与归档 v4 的对照"). 3.x had no PandaTV
// chat, and pure_live_TV has none either (`EmptyDanmaku`), so the archived
// v4 is the only earlier implementation; it recorded this sample itself.
//
// Below the harness, `PandaliveProtocol` is copied verbatim from archive/v4
// (6ba709135) packages/live_danmaku/lib/src/sites/pandalive.dart. Only what
// it imports from elsewhere is stubbed here: v4's `TextFrame`, its event
// types (DanmakuChat, DanmakuGift) with the fields the decoder sets,
// `DecodeContext` and `FrameResult`.
//
// The harness writes the socket address, handshake headers, ping period and
// `live/play` form of the recorded broadcaster (meta.json's `danmakuKeys`),
// the session v4 read from the recorded `live/play` answer, the frames it
// sends with that session (connect, subscribe, the pings from id 3), and, per
// received socket frame, the events (projected) and the join and rejection
// flags.
//
// Run from the repository root:
//
//   dart run fixtures/pandalive/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

const _sample = 'fixtures/pandalive/danmaku/S07-live';
const _generator =
    'archived v4 PandaliveProtocol (archive/v4 6ba709135: endpoint, headers, heartbeatInterval, playForm, session, '
    "connect, subscribe, ping, decode) over the recording's danmakuKeys, its live/play answer and every received "
    'socket frame (fixtures/pandalive/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync()) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final room = meta['room'] as String;
  final keys = (meta['danmakuKeys'] as Map).cast<String, String>();
  ({String channel, String token})? session;
  final frames = <Map<String, Object?>>[];
  var pings = 0;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in') {
      if ((line['text'] as String).contains('"method":7')) pings++;
      continue;
    }
    final text = line['text'] as String;
    if (line['url'] != null) {
      session = PandaliveProtocol.session(text);
      continue;
    }
    final context = DecodeContext(
      room: room,
      session: 1,
      receivedAt: line['t'] as int,
      now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final result = PandaliveProtocol.decode(text, channel: session!.channel, context: context);
    frames.add({
      'line': index + 1,
      'joined': result.joined,
      'rejected': result.rejected,
      'events': [for (final event in result.events) _project(event)],
    });
  }
  final expected = {
    'generator': _generator,
    'value': {
      'endpoint': PandaliveProtocol.endpoint.toString(),
      'headers': PandaliveProtocol.headers,
      'heartbeatSeconds': PandaliveProtocol.heartbeatInterval.inSeconds,
      'play': PandaliveProtocol.play.toString(),
      'playForm': PandaliveProtocol.playForm(keys['userId']!),
      'session': {'channel': session!.channel, 'token': session.token},
      'connect': PandaliveProtocol.connect(session.token).text,
      'subscribe': PandaliveProtocol.subscribe(session.channel).text,
      'pings': [for (var id = 3; id < 3 + pings; id++) PandaliveProtocol.ping(id).text],
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
    this.count = 1,
  });
  final String userId;
  final String userName;
  final String giftId;
  final String giftName;
  final int count;
}

// Copied from archive/v4 (6ba709135) packages/live_danmaku/lib/src/sites/pandalive.dart
// (the connector below it, which the harness does not use, is left out).

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// PandaTV's chat (spec/sites/pandalive.md §7): a Centrifugo server
/// (JSON protocol, commands and replies with ids) with the guest token of
/// `live/play`. Without I/O.
abstract final class PandaliveProtocol {
  /// §7.1 the socket.
  static final Uri endpoint = Uri.parse('wss://chat-ws.neolive.kr/connection/websocket');

  /// §7.1 the token source.
  static final Uri play = Uri.parse('https://api.pandalive.co.kr/v1/live/play');

  /// §7.2 client ping period (centrifuge-js default).
  static const heartbeatInterval = Duration(seconds: 25);

  /// Handshake headers.
  static const Map<String, String> headers = {'origin': 'https://www.pandalive.co.kr', 'user-agent': _userAgent};

  /// §7.1 the `live/play` form for broadcaster [userId].
  static Map<String, String> playForm(String userId) => {
    'action': 'watch',
    'userId': userId,
    'password': '',
    'shareLinkType': '',
  };

  /// §7.1 the chat channel and token of a `live/play` answer, or the
  /// refusal code (`castEnd`, `needAdult`, …) when there is none.
  static ({String channel, String token})? session(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['result'] != true) return null;
      final channel = '${root['channel'] ?? ''}';
      final token = root['token'];
      if (!RegExp(r'^[0-9]+$').hasMatch(channel) || token is! String || token.split('.').length != 3) return null;
      return (channel: channel, token: token);
    } on FormatException {
      return null;
    }
  }

  /// §9 why `live/play` gave no session.
  static String refusal(String body) {
    try {
      final root = jsonDecode(body);
      final error = root is Map ? root['errorData'] : null;
      return error is Map ? '${error['code']}' : 'no token';
    } on FormatException {
      return 'not JSON';
    }
  }

  /// §7.1 the connect command.
  static TextFrame connect(String token) => TextFrame(
    jsonEncode({
      'params': {'token': token, 'name': 'js'},
      'id': 1,
    }),
  );

  /// §7.1 the subscribe command for [channel].
  static TextFrame subscribe(String channel) => TextFrame(
    jsonEncode({
      'method': 1,
      'params': {'channel': channel},
      'id': 2,
    }),
  );

  /// §7.2 a ping command with id [id].
  static TextFrame ping(int id) => TextFrame(jsonEncode({'method': 7, 'id': id}));

  /// Normal chat types (§7.3).
  static const chatTypes = {'bj', 'chatter', 'manager', 'support'};

  static const _giftNames = {'heart': '하트', 'signature': '시그니처하트', 'item': '스페셜하트'};

  /// §7.3 decodes one frame (one or more newline-separated JSON replies
  /// and pushes) for [channel].
  static FrameResult decode(Object? data, {required String channel, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final events = <DanmakuEvent>[];
    var joined = false;
    var rejected = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final Object? reply;
      try {
        reply = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (reply is! Map) continue;
      final id = reply['id'];
      if (id == 1 || id == 2) {
        if (reply['error'] != null) rejected = true;
        if (id == 2 && reply['error'] == null) joined = true;
        continue;
      }
      final result = reply['result'];
      if (result is! Map || result['type'] != null || '${result['channel']}' != channel) continue;
      final publication = result['data'];
      final message = publication is Map ? publication['data'] : null;
      if (message is! Map) continue;
      final offset = publication is Map ? publication['offset'] : null;
      final event = _event(message, offset: offset is int ? '$channel:$offset' : null, context: context);
      if (event != null) events.add(event);
    }
    return FrameResult(events: events, joined: joined, rejected: rejected);
  }

  static DateTime? _time(Object? value) =>
      value is int && value > 0 ? DateTime.fromMillisecondsSinceEpoch(value * 1000) : null;

  static DanmakuEvent? _event(
    Map<dynamic, dynamic> message, {
    required String? offset,
    required DecodeContext context,
  }) {
    final type = '${message['type']}';
    if (chatTypes.contains(type)) {
      var text = '${message['message'] ?? ''}'.trim();
      if (text.isEmpty) text = _emoticon(message['emoticon']) ?? '';
      if (text.isEmpty) return null;
      return DanmakuChat(
        room: context.room,
        session: context.session,
        receivedAt: context.receivedAt,
        id: offset == null ? null : 'pandalive:$offset',
        sentAt: _time(message['created_at']),
        userId: '${message['id'] ?? ''}',
        userName: '${message['nk'] ?? message['id'] ?? ''}',
        text: text,
      );
    }
    if (type != 'SponCoin' && type != 'ItemCoin') return null;
    final raw = message['message'];
    final Object? body;
    try {
      body = raw is String ? jsonDecode(raw) : raw;
    } on FormatException {
      return null;
    }
    if (body is! Map) return null;
    final coins = body['coin'] is int ? body['coin'] as int : int.tryParse('${body['coin']}');
    if (coins == null || coins <= 0) return null;
    final gift = type == 'ItemCoin'
        ? 'item'
        : body.containsKey('heart')
        ? 'signature'
        : 'heart';
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: offset == null ? null : 'pandalive:$offset',
      sentAt: _time(message['created_at']),
      userId: '${body['id'] ?? ''}',
      userName: '${body['nick'] ?? body['id'] ?? ''}',
      giftId: gift,
      giftName: _giftNames[gift]!,
      count: coins,
    );
  }

  /// An emoticon-only message shows the emoticon's name.
  static String? _emoticon(Object? emoticon) {
    if (emoticon is! Map) return null;
    for (final value in emoticon.values) {
      if (value is Map && value['name'] is String && (value['name'] as String).isNotEmpty) return '[${value['name']}]';
    }
    return null;
  }
}
