// Writes expected.json for fixtures/youtube/danmaku (docs/modules/M5.19-youtube.md).
//
// 3.x had no YouTube chat, so the reference is the archived v4 (archive/v4, 6ba709135):
// `YouTubeChatProtocol` and `YouTubeChatConnector` in packages/live_danmaku/lib/src/sites/youtube.dart. Both are copied
// below as they were. Only what they stand on is cut down: the event classes and `DecodeContext` to their fields,
// `ConnectorBase` to a recorder (every `pause` is written down and returns at once; `status`, `joined` and `terminal`
// are written down), and the transport to a script that answers each request with the next step, writing down the
// request. A parse that throws is written as {"throws": <type>}. When a session's script runs out, the connector is
// stopped (the run goes stale), as a `close` would.
//
// Output: the v4 settings; for every recorded frame the parse (`initialContinuation` for `next`, `parse` for
// `get_live_chat`); the recorded sessions S06-live followed by S08-ended's end of chat, S07-live-paid, and S08's
// replay and no-chat starts; every synthetic answer, `next` and session of S09-synthetic.
//
// Run from the repository root: dart run fixtures/youtube/danmaku/v4_expected.dart
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/youtube/danmaku';

const _generator =
    'fixtures/youtube/danmaku/v4_expected.dart: the archived v4 (archive/v4 6ba709135) YouTubeChatProtocol '
    '(headers, endpoint, nextBody, chatBody, initialContinuation, parse) and YouTubeChatConnector (its settings and '
    'its run loop over scripted answers), copied as they were; the event classes, DecodeContext, ConnectorBase and '
    'the transport cut down to recorders';

// ---- stand-ins for what v4's protocol and connector use ----

abstract final class YouTubeParse {
  static const Map<String, Object?> webContext = {
    'client': {'clientName': 'WEB', 'clientVersion': '2.20260925.01.00', 'hl': 'en', 'gl': 'US'},
  };
}

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt});
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
    'sentAtMicros': sentAt?.microsecondsSinceEpoch,
    'userId': userId,
    'userName': userName,
    'text': text,
  };
}

enum DanmakuStatus { connecting, connected, reconnecting, closed }

final class RoomDetail {
  RoomDetail(this.danmakuKeys);
  final Map<String, String> danmakuKeys;
}

final class _Stopped implements Exception {
  const _Stopped();
}

/// v4's `ConnectorBase`, cut down to a recorder.
abstract base class ConnectorBase {
  ConnectorBase({required this.detail, required this.transport});

  final RoomDetail detail;
  final _Script transport;
  final List<Map<String, Object?>> trace = [];
  var _stale = false;

  bool isStale(int generation) => _stale;

  void Function() onStop(void Function() hook) => () {};

  DecodeContext context() => const DecodeContext(room: 'youtube:room', session: 0, receivedAt: 0);

  void emit(int generation, DanmakuEvent event) {
    if (!isStale(generation)) trace.add({'event': event.toJson(), ...transport.position});
  }

  void status(int generation, DanmakuStatus status, [List<String> args = const []]) {
    if (!isStale(generation)) trace.add({'status': status.name, if (args.isNotEmpty) 'args': args});
  }

  void joined(int generation) {
    if (!isStale(generation)) trace.add({'joined': true});
  }

  void terminal(int generation, String reason, [String? detail]) {
    if (isStale(generation)) return;
    trace.add({'terminal': reason, 'detail': ?detail});
  }

  Future<bool> pause(int generation, Duration delay) async {
    if (isStale(generation)) return false;
    trace.add({'wait': delay.inMilliseconds});
    return !isStale(generation);
  }

  Future<void> run(int generation);

  /// Runs the loop to its end (terminal, or the script ran out).
  Future<List<Map<String, Object?>>> session() async {
    try {
      await run(1);
    } on Object catch (error) {
      terminal(1, 'failed', '$error');
    }
    return trace;
  }
}

/// Answers each request with the next step; writes down the request. When the
/// steps run out the run is stopped.
final class _Script {
  _Script(this.steps, this.owner);

  final List<Map<String, Object?>> steps;
  final ConnectorBase Function() owner;
  var _next = 0;
  Map<String, Object?> position = const {};

  Future<_Response> send({required String endpoint, required List<int> body}) async {
    final connector = owner();
    final request = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    connector.trace.add({
      'request': endpoint,
      if (request.containsKey('videoId')) 'videoId': request['videoId'],
      if (request.containsKey('continuation')) 'continuation': request['continuation'],
    });
    if (_next >= steps.length) {
      connector._stale = true;
      throw const _Stopped();
    }
    position = {'step': _next};
    final step = steps[_next++];
    if (step['error'] case final String reason) throw TransportError(reason);
    if (step['status'] case final int status) return _Response(status, '');
    if (step['raw'] case final String raw) return _Response(200, raw);
    return _Response(200, jsonEncode(step['answer']));
  }
}

final class _Response {
  const _Response(this.status, this.text);
  final int status;
  final String text;
  bool get isSuccess => status >= 200 && status < 300;
}

final class TransportError implements Exception {
  const TransportError(this.reason);
  final String reason;
  @override
  String toString() => 'TransportFailure(youtube, $reason)';
}

// ---- v4's packages/live_danmaku/lib/src/sites/youtube.dart, as it was ----

/// One parsed `get_live_chat` answer.
final class YouTubeChatPoll {
  /// Creates a poll result.
  const YouTubeChatPoll({required this.events, this.continuation, this.delay});

  /// Chat lines in order.
  final List<DanmakuEvent> events;

  /// The next continuation; null when the chat ended.
  final String? continuation;

  /// How long the server asks to wait (`timeoutMs`).
  final Duration? delay;
}

/// YouTube live chat (spec/sites/youtube.md §7), without I/O: the watch
/// page's `next` answer names the chat's first continuation, and
/// `live_chat/get_live_chat` is polled with the continuation of the
/// previous answer.
abstract final class YouTubeChatProtocol {
  /// Request headers (as for the adapter's InnerTube calls).
  static const headers = {
    'content-type': 'application/json',
    'origin': 'https://www.youtube.com',
    'cookie': 'SOCS=CAI',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  };

  /// An InnerTube endpoint.
  static Uri endpoint(String name) => Uri.parse('https://www.youtube.com/youtubei/v1/$name?prettyPrint=false');

  /// The `next` request body for [videoId].
  static List<int> nextBody(String videoId) =>
      utf8.encode(jsonEncode({'context': YouTubeParse.webContext, 'videoId': videoId}));

  /// The `get_live_chat` request body.
  static List<int> chatBody(String continuation) =>
      utf8.encode(jsonEncode({'context': YouTubeParse.webContext, 'continuation': continuation}));

  static Object? _decode(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw FormatException('$what: not JSON');
    }
  }

  static Iterable<Object?> _find(Object? node, String key) sync* {
    if (node is Map) {
      if (node.containsKey(key)) yield node[key];
      for (final value in node.values) {
        yield* _find(value, key);
      }
    } else if (node is List) {
      for (final value in node) {
        yield* _find(value, key);
      }
    }
  }

  static String? _continuation(Object? continuations) {
    if (continuations is! List || continuations.isEmpty) return null;
    final first = continuations.first;
    if (first is! Map) return null;
    for (final data in first.values) {
      if (data is Map && data['continuation'] is String) return data['continuation'] as String;
    }
    return null;
  }

  /// The chat's first continuation from a `next` answer, or null when the
  /// video has no live chat (not live, or chat turned off).
  static String? initialContinuation(String body) {
    for (final chat in _find(_decode(body, 'next'), 'liveChatRenderer')) {
      if (chat is Map) return _continuation(chat['continuations']);
    }
    return null;
  }

  static String _text(Object? message) {
    final runs = message is Map ? message['runs'] : null;
    if (runs is! List) return '';
    final out = StringBuffer();
    for (final run in runs.whereType<Map<Object?, Object?>>()) {
      final text = run['text'];
      if (text is String) {
        out.write(text);
        continue;
      }
      final emoji = run['emoji'];
      if (emoji is Map) {
        final shortcuts = emoji['shortcuts'];
        out.write(shortcuts is List && shortcuts.isNotEmpty ? '${shortcuts.first}' : '${emoji['emojiId'] ?? ''}');
      }
    }
    return out.toString().trim();
  }

  static String _simple(Object? node) =>
      node is Map && node['simpleText'] is String ? node['simpleText'] as String : '';

  /// Parses one `get_live_chat` answer: text messages, and paid messages
  /// as chat lines prefixed with their amount (§7).
  static YouTubeChatPoll parse(String body, {required DecodeContext context}) {
    final root = _decode(body, 'get_live_chat');
    final chat = root is Map && root['continuationContents'] is Map
        ? (root['continuationContents'] as Map)['liveChatContinuation']
        : null;
    if (chat is! Map) return const YouTubeChatPoll(events: []);
    final events = <DanmakuEvent>[];
    final actions = chat['actions'];
    for (final action in actions is List ? actions : const <Object?>[]) {
      final add = action is Map ? action['addChatItemAction'] : null;
      final item = add is Map ? add['item'] : null;
      if (item is! Map) continue;
      final Map<Object?, Object?> renderer;
      var text = '';
      if (item['liveChatTextMessageRenderer'] case final Map<Object?, Object?> message) {
        renderer = message;
        text = _text(message['message']);
      } else if (item['liveChatPaidMessageRenderer'] case final Map<Object?, Object?> paid) {
        renderer = paid;
        text = '${_simple(paid['purchaseAmountText'])} ${_text(paid['message'])}'.trim();
      } else {
        continue;
      }
      if (text.isEmpty) continue;
      final id = renderer['id'];
      final micros = int.tryParse('${renderer['timestampUsec'] ?? ''}');
      events.add(
        DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id is String && id.isNotEmpty ? 'youtube:$id' : null,
          sentAt: micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
          userId: '${renderer['authorExternalChannelId'] ?? ''}',
          userName: _simple(renderer['authorName']),
          text: text,
        ),
      );
    }
    final continuations = chat['continuations'];
    Duration? delay;
    if (continuations is List && continuations.isNotEmpty && continuations.first is Map) {
      for (final data in (continuations.first as Map).values) {
        final ms = data is Map ? data['timeoutMs'] : null;
        if (ms is int && ms >= 0) delay = Duration(milliseconds: ms);
      }
    }
    return YouTubeChatPoll(events: events, continuation: _continuation(continuations), delay: delay);
  }
}

/// YouTube live chat by polling: the first answer is the recent history
/// (not emitted); later answers are emitted. The wait follows the server's
/// `timeoutMs`, capped at [maximumDelay] (the web client is pushed new
/// messages; polling sooner keeps the delay close to it). After
/// [maxFailures] consecutive failures it gives up; an answer without a
/// continuation means the chat ended.
final class YouTubeChatConnector extends ConnectorBase {
  /// Creates the connector; [detail]'s `danmakuKeys['videoId']` is the broadcast.
  YouTubeChatConnector({required super.detail, required super.transport});

  /// Consecutive failures before the terminal state.
  static const maxFailures = 8;

  /// Longest wait between two polls.
  static const maximumDelay = Duration(seconds: 5);

  /// Shortest wait between two polls.
  static const minimumDelay = Duration(seconds: 1);

  /// Wait after a failed request.
  static const retryDelay = Duration(seconds: 2);

  @override
  Future<void> run(int generation) async {
    final video = detail.danmakuKeys['videoId'] ?? '';
    if (video.isEmpty) {
      terminal(generation, 'offline', 'no live video');
      return;
    }
    status(generation, DanmakuStatus.connecting);
    String? continuation;
    try {
      continuation = YouTubeChatProtocol.initialContinuation(await _post('next', YouTubeChatProtocol.nextBody(video)));
    } on Object catch (error) {
      if (!isStale(generation)) terminal(generation, 'failed', '$error');
      return;
    }
    if (continuation == null) {
      terminal(generation, 'offline', 'no live chat');
      return;
    }
    var failures = 0;
    var joinedOnce = false;
    var delay = Duration.zero;
    while (await pause(generation, delay)) {
      try {
        final poll = YouTubeChatProtocol.parse(
          await _post('live_chat/get_live_chat', YouTubeChatProtocol.chatBody(continuation!)),
          context: context(),
        );
        if (isStale(generation)) return;
        if (failures > 0 && joinedOnce) status(generation, DanmakuStatus.connected);
        failures = 0;
        if (!joinedOnce) {
          // The first answer is the recent history.
          joinedOnce = true;
          status(generation, DanmakuStatus.connected);
          joined(generation);
        } else {
          for (final event in poll.events) {
            emit(generation, event);
          }
        }
        final next = poll.continuation;
        if (next == null) {
          terminal(generation, 'offline', 'chat ended');
          return;
        }
        continuation = next;
        final wait = poll.delay ?? maximumDelay;
        delay = wait > maximumDelay ? maximumDelay : (wait < minimumDelay ? minimumDelay : wait);
      } on Object catch (error) {
        if (isStale(generation)) return;
        failures++;
        if (!joinedOnce && failures > 2) {
          terminal(generation, 'failed', '$error');
          return;
        }
        if (failures == 1) status(generation, DanmakuStatus.reconnecting);
        if (failures >= maxFailures) {
          terminal(generation, 'maxRetries');
          return;
        }
        delay = retryDelay;
      }
    }
  }

  // v4's transport call, over the script: a failed status is v4's
  // FormatException('HTTP <status> <endpoint>').
  Future<String> _post(String endpoint, List<int> body) async {
    final response = await transport.send(endpoint: endpoint, body: body);
    if (!response.isSuccess) throw FormatException('HTTP ${response.status} $endpoint');
    return response.text;
  }
}

// ---- output ----

const _context = DecodeContext(room: 'youtube:room', session: 0, receivedAt: 0);

/// The index in `actions` of each item `parse` turns into an event, in order:
/// the loop of `parse` again, with its own helpers (for the tests, which map
/// v4's text to the new one from the item's runs).
List<int> _sources(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  final chat = root is Map && root['continuationContents'] is Map
      ? (root['continuationContents'] as Map)['liveChatContinuation']
      : null;
  if (chat is! Map) return const [];
  final actions = chat['actions'];
  return [
    for (final (index, action) in (actions is List ? actions : const <Object?>[]).indexed)
      if (_source(action)) index,
  ];
}

bool _source(Object? action) {
  final add = action is Map ? action['addChatItemAction'] : null;
  final item = add is Map ? add['item'] : null;
  if (item is! Map) return false;
  if (item['liveChatTextMessageRenderer'] case final Map<Object?, Object?> message) {
    return YouTubeChatProtocol._text(message['message']).isNotEmpty;
  }
  if (item['liveChatPaidMessageRenderer'] case final Map<Object?, Object?> paid) {
    return '${YouTubeChatProtocol._simple(paid['purchaseAmountText'])} ${YouTubeChatProtocol._text(paid['message'])}'
        .trim()
        .isNotEmpty;
  }
  return false;
}

Map<String, Object?> _parsed(String text) {
  try {
    final poll = YouTubeChatProtocol.parse(text, context: _context);
    final sources = _sources(text);
    return {
      'events': [
        for (final (index, event) in poll.events.indexed) {...event.toJson(), 'action': sources[index]},
      ],
      'continuation': poll.continuation,
      'delayMs': poll.delay?.inMilliseconds,
    };
  } on Object catch (error) {
    return {'throws': error.runtimeType.toString()};
  }
}

Map<String, Object?> _initial(String text) {
  try {
    return {'initialContinuation': YouTubeChatProtocol.initialContinuation(text)};
  } on Object catch (error) {
    return {'throws': error.runtimeType.toString()};
  }
}

List<Map<String, Object?>> _frames(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

bool _isNext(Map<String, Object?> frame) => (frame['url']! as String).contains('/v1/next');

/// A recorded frame as a script step: its status (200 for S06-live, which has
/// none) and its text.
Map<String, Object?> _step(Map<String, Object?> frame) {
  final status = frame['status'] as int? ?? 200;
  return status == 200 ? {'raw': frame['text']} : {'status': status};
}

/// v4's run over [steps]; each event names the step and the action it came
/// from.
Future<List<Map<String, Object?>>> _session(String videoId, List<Map<String, Object?>> steps) async {
  late final YouTubeChatConnector connector;
  final script = _Script(steps, () => connector);
  connector = YouTubeChatConnector(detail: RoomDetail({'videoId': videoId}), transport: script);
  final trace = await connector.session();
  final emitted = <int, int>{};
  return [
    for (final entry in trace)
      if (entry['step'] case final int step)
        {...entry, 'action': _sources(_stepText(steps[step]))[emitted[step] = (emitted[step] ?? -1) + 1]}
      else
        entry,
  ];
}

/// Every recorded answer parsed; a failed status is written as such (v4's
/// transport threw before parsing it).
Map<String, Object?> _recorded(String name) => {
  'frames': [
    for (final (index, frame) in _frames(name).indexed)
      {
        'frame': index,
        ...switch (frame['status'] as int? ?? 200) {
          200 => _isNext(frame) ? _initial(frame['text']! as String) : _parsed(frame['text']! as String),
          final status => {'status': status},
        },
      },
  ],
};

Map<String, Object?> _settings() => {
  'headers': YouTubeChatProtocol.headers,
  'endpoints': {
    'next': '${YouTubeChatProtocol.endpoint('next')}',
    'chat': '${YouTubeChatProtocol.endpoint('live_chat/get_live_chat')}',
  },
  'nextBody': jsonDecode(utf8.decode(YouTubeChatProtocol.nextBody('VIDEO_ID_11'))),
  'chatBody': jsonDecode(utf8.decode(YouTubeChatProtocol.chatBody('TOKEN'))),
  'maxFailures': YouTubeChatConnector.maxFailures,
  'maximumDelayMs': YouTubeChatConnector.maximumDelay.inMilliseconds,
  'minimumDelayMs': YouTubeChatConnector.minimumDelay.inMilliseconds,
  'retryDelayMs': YouTubeChatConnector.retryDelay.inMilliseconds,
  // v4's LiveRequest default, which its chat requests kept.
  'requestTimeoutMs': 15000,
};

String _stepText(Map<String, Object?> step) =>
    step['raw'] as String? ?? (step.containsKey('answer') ? jsonEncode(step['answer']) : '');

void _write(String name, Map<String, Object?> value) {
  final file = File('$_root/$name/expected.json');
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n');
  stdout.writeln('wrote ${file.path}');
}

Future<void> main() async {
  final s06 = _frames('S06-live');
  final s07 = _frames('S07-live-paid');
  final s08 = _frames('S08-ended');
  final lastS06 = jsonDecode(s06.last['text']! as String) as Map<String, Object?>;
  final lastToken =
      ((((lastS06['continuationContents']! as Map)['liveChatContinuation']! as Map)['continuations']! as List).first
              as Map)
          .values
          .whereType<Map<Object?, Object?>>()
          .first['continuation'];
  if ((s08[3]['request']! as Map)['continuation'] != lastToken) {
    throw StateError('S08-ended frame 3 does not continue S06-live');
  }

  _write('S06-live', {
    'settings': _settings(),
    ..._recorded('S06-live'),
    'session': await _session('xd_fJRWZuVI', [for (final frame in s06) _step(frame), _step(s08[3]), _step(s08[4])]),
  });
  _write('S07-live-paid', {
    ..._recorded('S07-live-paid'),
    'session': await _session('e3n116VqcrE', [for (final frame in s07) _step(frame)]),
  });
  _write('S08-ended', {
    ..._recorded('S08-ended'),
    'sessions': {
      'replay': await _session('xd_fJRWZuVI', [_step(s08[0]), _step(s08[1]), _step(s08[1]), _step(s08[1])]),
      'noChat': await _session('9njefMDxzqw', [_step(s08[2])]),
    },
  });

  final cases = jsonDecode(File('$_root/S09-synthetic/cases.json').readAsStringSync()) as Map<String, Object?>;
  _write('S09-synthetic', {
    'answers': {
      for (final entry in (cases['answers']! as List).cast<Map<String, Object?>>())
        entry['name']! as String: _parsed(_stepText(entry.containsKey('raw') ? entry : {'answer': entry['body']})),
    },
    'nexts': {
      for (final entry in (cases['nexts']! as List).cast<Map<String, Object?>>())
        entry['name']! as String: _initial(_stepText(entry.containsKey('raw') ? entry : {'answer': entry['body']})),
    },
    'sessions': {
      for (final entry in (cases['sessions']! as List).cast<Map<String, Object?>>())
        entry['name']! as String: await _session(
          entry['videoId']! as String,
          (entry['steps']! as List).cast<Map<String, Object?>>(),
        ),
    },
  });
}
