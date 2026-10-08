// YouTube danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.20-YouTube弹幕/record.md): the chat parser and the
// polling connection against the archived v4's output for the recorded
// answers and sessions (S06-live, S07-live-paid, S08-ended) and the synthetic
// answers and sessions (S09-synthetic), written by
// fixtures/youtube/danmaku/v4_expected.dart; and the M5.F follow-ups (B-13:
// super chats, notices, retractions, the viewer count of updated_metadata,
// the "Live chat" view) against the recordings S10-live-all-chat and
// S11-metadata-ended and synthetic answers; B-22 (the Super Chats still
// pinned on joining, S10) and B-23 (gifts, S12-gifts).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/youtube/danmaku';

/// When S10-live-all-chat was recorded: the "now" of Super Chats without a
/// platform time.
final DateTime _recordedAt = DateTime.utc(2026, 9, 30, 15, 13);

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded exchanges of a sample, in order.
List<Map<String, Object?>> _frames(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

bool _isNext(Map<String, Object?> frame) => (frame['url']! as String).contains('/v1/next');

bool _isMetadata(Map<String, Object?> frame) => (frame['url']! as String).contains('/v1/updated_metadata');

int _status(Map<String, Object?> frame) => frame['status'] as int? ?? 200;

Object? _answer(Map<String, Object?> frame) => jsonDecode(frame['text']! as String);

/// The continuation a recorded frame was asked for with.
String _asked(Map<String, Object?> frame) => (frame['request']! as Map<String, Object?>)['continuation']! as String;

/// The archived v4's output for a sample.
Map<String, Object?> _v4(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) => (value! as List<Object?>).cast<Map<String, Object?>>();

final Map<String, Object?> _cases = _json('S09-synthetic/cases.json')! as Map<String, Object?>;

final Map<String, Object?> _v4Synthetic = _v4('S09-synthetic');

Map<String, Map<String, Object?>> _named(String key) => {
  for (final entry in _list(_cases[key])) entry['name']! as String: entry,
};

/// A step of a script as the text its answer has (sessions and cases).
String _stepText(Map<String, Object?> step) =>
    step['raw'] as String? ?? (step.containsKey('answer') ? jsonEncode(step['answer']) : jsonEncode(step['body']));

/// A recorded frame as a script step (as v4_expected.dart makes it).
Map<String, Object?> _step(Map<String, Object?> frame) =>
    _status(frame) == 200 ? {'raw': frame['text']} : {'status': _status(frame)};

/// The item of an action: `addChatItemAction.item`'s renderer.
({Map<String, Object?> renderer, bool paid}) _item(Object? action) {
  final item =
      ((action! as Map<String, Object?>)['addChatItemAction']! as Map<String, Object?>)['item']!
          as Map<String, Object?>;
  final paid = item['liveChatPaidMessageRenderer'];
  return paid is Map<String, Object?>
      ? (renderer: paid, paid: true)
      : (renderer: item['liveChatTextMessageRenderer']! as Map<String, Object?>, paid: false);
}

/// The actions of a `get_live_chat` answer.
List<Object?> _actions(Object? answer) =>
    (((answer! as Map<String, Object?>)['continuationContents']! as Map<String, Object?>)['liveChatContinuation']!
            as Map<String, Object?>)['actions']!
        as List<Object?>;

/// The action [index] of a `get_live_chat` answer.
Object? _action(String text, int index) => _actions(jsonDecode(text))[index];

String _joinedRuns(Object? node) => node is Map && node['runs'] is List
    ? [
        for (final run in node['runs'] as List)
          if (run is Map && run['text'] is String) run['text'] as String,
      ].join()
    : '';

/// A chat line of v4 turned into the new model by the documented
/// differences 1–4, from the item it came from:
///
/// 1. no `youtube:` prefix on the message id;
/// 2. a standard emoji is its character (`emojiId`), a custom one its
///    shortcut; v4 wrote the first shortcut of both. The texts are rebuilt
///    run by run under both rules, and v4's must come out as v4 wrote it;
/// 3. a time that is not positive is no time;
/// 4. the user id only when it is text; a name or amount written as runs is
///    read.
///
/// B-13: a paid message is a super chat now, not a chat line; it keeps the
/// line's shape here ([_project]), so v4's paid lines still compare.
Map<String, Object?> _fromV4(Map<String, Object?> v4, Object? action) {
  final (:renderer, :paid) = _item(action);
  final runs = (renderer['message'] as Map<String, Object?>?)?['runs'];
  final v4Tokens = <String>[];
  final newTokens = <String>[];
  for (final run in runs is List ? runs : const <Object?>[]) {
    if (run is! Map) continue;
    if (run['text'] case final String text) {
      v4Tokens.add(text);
      newTokens.add(text);
    } else if (run['emoji'] case final Map<String, Object?> emoji) {
      final shortcuts = emoji['shortcuts'];
      final shortcut = shortcuts is List && shortcuts.isNotEmpty ? shortcuts.first : null;
      final id = emoji['emojiId'];
      v4Tokens.add(shortcut != null ? '$shortcut' : '${id ?? ''}');
      final textShortcut = shortcut is String ? shortcut : '';
      newTokens.add(
        emoji['isCustomEmoji'] == true ? textShortcut : (id is String && id.isNotEmpty ? id : textShortcut),
      );
    }
  }
  var v4Text = v4Tokens.join().trim();
  var newText = newTokens.join().trim();
  if (paid) {
    final amount = renderer['purchaseAmountText'] as Map<String, Object?>?;
    final simple = amount?['simpleText'];
    v4Text = '${simple is String ? simple : ''} $v4Text'.trim();
    newText = '${simple is String ? simple : _joinedRuns(amount)} $newText'.trim();
  }
  expect(v4['text'], v4Text, reason: "the test rebuilds v4's text from the item's runs");
  final authorName = renderer['authorName'];
  final micros = v4['sentAtMicros'] as int?;
  return {
    'event': 'chat',
    'type': paid ? 'superChat' : 'chat',
    'id': (v4['id'] as String?)?.replaceFirst('youtube:', '') ?? '',
    'sentAtMicros': micros != null && micros > 0 ? micros : null,
    'userId': renderer['authorExternalChannelId'] is String ? v4['userId'] : '',
    'userName': authorName is Map && authorName['simpleText'] is String ? v4['userName'] : _joinedRuns(authorName),
    'text': newText,
    'color': '#ffffff',
    'extras': const ['', '', '', false],
  };
}

/// A message of the new code in the same shape. A super chat is a line of
/// type `superChat` whose text is its amount and its message (B-13);
/// retractions and notices, which v4 did not have, have their own shapes.
Map<String, Object?> _project(LiveMessage message) {
  switch (message.data) {
    case LiveAudienceUpdate(:final kind, :final value):
      expect(message.type, LiveMessageType.online);
      return {'event': 'viewers', 'kind': kind.name, 'value': value};
    case LiveRetraction(:final messageId, :final userId):
      expect(message.type, LiveMessageType.retraction);
      expect(
        [message.messageId, message.userId, message.userName, message.message, message.sentAt],
        ['', '', '', '', null],
      );
      return {'event': 'retraction', 'messageId': ?messageId, 'userId': ?userId};
    case final LiveNoticeKind kind:
      expect(message.type, LiveMessageType.notice);
      return {
        'event': 'notice',
        'kind': kind.name,
        'id': message.messageId,
        'sentAtMicros': message.sentAt?.microsecondsSinceEpoch,
        'userId': message.userId,
        'userName': message.userName,
        'text': message.message,
      };
    case LiveSuperChatMessage(:final priceText, message: final text):
      expect(message.type, LiveMessageType.superChat);
      return {..._line(message), 'text': '$priceText $text'.trim()};
    default:
      return _line(message);
  }
}

Map<String, Object?> _line(LiveMessage message) => {
  'event': 'chat',
  'type': message.type.name,
  'id': message.messageId,
  'sentAtMicros': message.sentAt?.microsecondsSinceEpoch,
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
  'color': '${message.color}',
  'extras': [message.userLevel, message.fansLevel, message.fansName, message.isLocal],
  // B-22: a Super Chat still pinned on joining.
  if (message.replayed) 'replayed': true,
};

/// Every field of a super chat and of its message.
Map<String, Object?> _superChat(LiveMessage message) {
  final data = message.data! as LiveSuperChatMessage;
  expect(message.type, LiveMessageType.superChat);
  expect(
    [message.userName, message.message, message.messageId, message.color],
    [data.userName, data.message, data.messageId, LiveMessageColor.white],
  );
  expect(message.sentAt == null || message.sentAt == data.startTime, isTrue);
  return {
    'id': data.messageId,
    'userName': data.userName,
    'userId': message.userId,
    'face': data.face,
    'message': data.message,
    'price': data.price,
    'priceText': data.priceText,
    'startMicros': data.startTime.microsecondsSinceEpoch,
    'seconds': data.endTime.difference(data.startTime).inSeconds,
    'colors': [data.backgroundColor, data.backgroundBottomColor],
  };
}

bool _isB13Only(Map<String, Object?> entry) => entry['event'] == 'retraction' || entry['event'] == 'notice';

/// v4's parse of one answer, in the new model; `throws` when it threw.
Object? _v4Parsed(Map<String, Object?> v4, String text) {
  if (v4['throws'] case final String type) return {'throws': type};
  return {
    'messages': [for (final event in _list(v4['events'])) _fromV4(event, _action(text, event['action']! as int))],
    'continuation': v4['continuation'],
    'timeoutMs': v4['delayMs'],
  };
}

/// The new parse of one answer (decoded as `postJson` decodes it), without
/// the retractions and notices v4 did not have (B-13; checked on their own).
Object? _parsed(String text) {
  try {
    final poll = YouTubeDanmakuProtocol.chat(jsonDecode(text), now: _recordedAt);
    return {
      'messages': [
        for (final message in poll.messages)
          if (_project(message) case final entry when !_isB13Only(entry)) entry,
      ],
      'continuation': poll.continuation,
      'timeoutMs': poll.timeout?.inMilliseconds,
    };
  } on Object catch (error) {
    return {'throws': error.runtimeType.toString()};
  }
}

/// The messages of one answer, projected.
List<Map<String, Object?>> _messages(Object? answer, {DateTime? now}) => [
  for (final message in YouTubeDanmakuProtocol.chat(answer, now: now ?? _recordedAt).messages) _project(message),
];

/// A v4 session trace in the shape of the new one (difference 11): waits of
/// zero (v4 paused without a timer) and `connecting` left out; `connected`
/// is [DanmakuReady]; the terminal states are the M5.0 reasons.
List<Map<String, Object?>> _v4Session(List<Map<String, Object?>> trace, List<Map<String, Object?>> steps) => [
  for (final entry in trace)
    if (entry['request'] != null)
      entry
    else if (entry['wait'] case final int ms when ms > 0)
      {'wait': ms}
    else if (entry['status'] == 'connected')
      {'event': 'ready'}
    else if (entry['status'] == 'reconnecting')
      {'event': 'reconnecting'}
    else if (entry['terminal'] case final String reason)
      {'event': 'closed', 'reason': reason == 'maxRetries' ? 'reconnectsExhausted' : 'connectionFailed'}
    else if (entry['event'] case final Map<String, Object?> event)
      _fromV4(event, _action(_stepText(steps[entry['step']! as int]), entry['action']! as int)),
];

/// Answers each chat request with the next step ({"answer"}, {"raw"}: 200;
/// {"status"}; {"error"}: no response), and each `updated_metadata` request
/// with the next of [metadata]. Once either runs out a request waits for its
/// cancellation.
final class _ScriptedHttp implements LiveHttp {
  new(this.steps, {this.metadata = const []});

  final List<Map<String, Object?>> steps;
  final List<Map<String, Object?>> metadata;

  /// The chat requests (`next`, `get_live_chat`).
  final List<LiveRequest> requests = [];

  /// The `updated_metadata` requests.
  final List<LiveRequest> metadataRequests = [];

  /// Completes when a chat request finds no step left.
  final Completer<void> exhausted = Completer();

  /// Completes when an `updated_metadata` request finds no step left.
  final Completer<void> metadataExhausted = Completer();
  void Function(LiveRequest request)? onRequest;
  var _next = 0;
  var _nextMetadata = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final isMetadata = request.url.path.endsWith('/updated_metadata');
    (isMetadata ? metadataRequests : requests).add(request);
    onRequest?.call(request);
    final script = isMetadata ? metadata : steps;
    final index = isMetadata ? _nextMetadata++ : _next++;
    if (index >= script.length) {
      final ran = isMetadata ? metadataExhausted : exhausted;
      if (!ran.isCompleted) ran.complete();
      await request.cancel?.whenCancelled;
      throw TransportFailure(request.site, TransportReason.cancelled);
    }
    final step = script[index];
    if (step['error'] case final String reason) {
      throw TransportFailure(request.site, TransportReason.values.byName(reason), 'scripted');
    }
    final status = step['status'] as int? ?? 200;
    return LiveResponse(status: status, bytes: utf8.encode(status == 200 ? _stepText(step) : ''), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

/// Answers each request when the test says so, ignoring cancellation (a late
/// answer).
final class _ManualHttp implements LiveHttp {
  final List<({LiveRequest request, Completer<LiveResponse> answer})> pending = [];

  @override
  Future<LiveResponse> send(LiveRequest request) {
    final answer = Completer<LiveResponse>();
    pending.add((request: request, answer: answer));
    return answer.future;
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

/// The body of a request, decoded.
Map<String, Object?> _body(LiveRequest request) => jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;

Map<String, Object?> _requestEntry(LiveRequest request) {
  final body = _body(request);
  final path = request.url.path;
  return {
    'request': path.endsWith('/next')
        ? 'next'
        : path.endsWith('/updated_metadata')
        ? 'updated_metadata'
        : 'live_chat/get_live_chat',
    if (body.containsKey('videoId')) 'videoId': body['videoId'],
    if (body.containsKey('continuation')) 'continuation': body['continuation'],
  };
}

/// One session of the new code over [steps]: requests, waits (each timer
/// fired at once), events. It ends when the steps run out (the [metadata]
/// steps when there are some), the connection closes or `connect` throws.
/// [details] gets the details of the closing and reconnecting events,
/// [statuses] the status after each event.
///
/// B-13: `updated_metadata` requests and their 30 s waits are in the trace
/// only with [viewerPolls]; without [metadata] they are never answered.
Future<List<Map<String, Object?>>> _session(
  String videoId,
  List<Map<String, Object?>> steps, {
  List<String>? details,
  List<DanmakuStatus>? statuses,
  List<LiveRequest>? requests,
  List<LiveRequest>? metadataRequests,
  List<Map<String, Object?>> metadata = const [],
  bool viewerPolls = false,
  bool allChat = false,
}) async {
  final trace = <Map<String, Object?>>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final http = _ScriptedHttp(steps, metadata: metadata)
    ..onRequest = (request) {
      final entry = _requestEntry(request);
      if (viewerPolls || entry['request'] != 'updated_metadata') trace.add(entry);
    };
  unawaited((metadata.isEmpty ? http.exhausted : http.metadataExhausted).future.then((_) => finish()));
  final connection = YouTubeDanmakuConnection(http: http, allChat: allChat, now: () => _recordedAt);
  final subscription = connection.events.listen((event) {
    trace.add(switch (event) {
      DanmakuReady() => {'event': 'ready'},
      DanmakuReceived(:final message) => _project(message),
      DanmakuReconnecting() => {'event': 'reconnecting'},
      DanmakuClosed(:final reason) => {'event': 'closed', 'reason': reason.name},
    });
    if (event case DanmakuReconnecting(:final detail) || DanmakuClosed(:final detail)) details?.add(detail);
    statuses?.add(connection.status);
    if (event is DanmakuClosed) finish();
  });
  // `connect` may still be joining when the steps run out; the session ends
  // then and the close lets it return.
  late final Future<void> connecting;
  await runZoned(
    () async {
      connecting = connection
          .connect(YouTubeDanmakuArgs(roomId: 'UCsyntheticChannel000001', videoId: videoId))
          .catchError((Object error) {
            trace.add({'threw': error.runtimeType.toString()});
            finish();
          });
      await done.future;
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (viewerPolls || duration != YouTubeDanmakuProtocol.viewerInterval) {
          trace.add({'wait': duration.inMilliseconds});
        }
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
  await connection.close();
  await connecting;
  statuses?.add(connection.status);
  await subscription.cancel();
  requests?.addAll(http.requests);
  metadataRequests?.addAll(http.metadataRequests);
  return trace;
}

List<Map<String, Object?>> _withoutViewers(List<Map<String, Object?>> trace) => [
  for (final entry in trace)
    if (entry['event'] != 'viewers') entry,
];

/// A trace without the retractions and notices v4 did not have (B-13).
List<Map<String, Object?>> _withoutB13(List<Map<String, Object?>> trace) => [
  for (final entry in trace)
    if (!_isB13Only(entry)) entry,
];

/// An event as the tests compare it: a message projected, others as text.
Object _shown(DanmakuEvent event) => event is DanmakuReceived ? _project(event.message) : '$event';

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

LiveResponse _ok(LiveRequest request, Object? answer) =>
    LiveResponse(status: 200, bytes: utf8.encode(jsonEncode(answer)), url: request.url);

Map<String, Object?> _watchAnswer({String token = 'T-reload', int? viewers}) => {
  'contents': {
    'twoColumnWatchNextResults': {
      'conversationBar': {
        'liveChatRenderer': {
          'continuations': [
            {
              'reloadContinuationData': {'continuation': token},
            },
          ],
        },
      },
      if (viewers != null)
        'results': {
          'results': {
            'contents': [
              {
                'videoPrimaryInfoRenderer': {
                  'viewCount': {
                    'videoViewCountRenderer': {
                      'viewCount': {'simpleText': '$viewers watching now'},
                      'isLive': true,
                    },
                  },
                },
              },
            ],
          },
        },
    },
  },
};

Map<String, Object?> _textItem(String text, {int index = 0}) => {
  'addChatItemAction': {
    'item': {
      'liveChatTextMessageRenderer': {
        'message': {
          'runs': [
            {'text': text},
          ],
        },
        'authorName': {'simpleText': '@viewer$index'},
        'id': 'id-$text',
        'timestampUsec': '${1790633000000000 + index}',
        'authorExternalChannelId': 'UCsyntheticViewer${'$index'.padLeft(7, '0')}',
      },
    },
  },
};

/// A `get_live_chat` answer with [actions] (text lines for strings).
Map<String, Object?> _chatAnswer(
  List<Object> actions, {
  String? token = 'T-next',
  int timeoutMs = 10000,
  String kind = 'invalidationContinuationData',
}) => {
  'continuationContents': {
    'liveChatContinuation': {
      if (token != null)
        'continuations': [
          {
            kind: {if (kind != 'reloadContinuationData') 'timeoutMs': timeoutMs, 'continuation': token},
          },
        ],
      'actions': [
        for (final (index, action) in actions.indexed)
          if (action is String) _textItem(action, index: index) else action,
      ],
    },
  },
};

const Map<String, Object?> _ended = {
  'contents': {
    'messageRenderer': {
      'text': {
        'runs': [
          {'text': 'Chat is disabled for this live stream.'},
        ],
      },
    },
  },
};

/// A paid message of the synthetic answers: `id` P[n], red unless given.
Map<String, Object?> _paid(
  int n, {
  Object? amount = r'$5.00',
  String? text = 'thanks',
  Object? header = 0xFFD00000,
  Object? body = 0xFFE62117,
  Object? time = 'default',
  Object? photo,
}) => {
  'addChatItemAction': {
    'item': {
      'liveChatPaidMessageRenderer': {
        'id': 'P$n',
        'timestampUsec': ?(time == 'default' ? '${1790781200000000 + n}' : time),
        'authorName': {'simpleText': '@payer$n'},
        'authorExternalChannelId': 'UCsyntheticPayer${'$n'.padLeft(8, '0')}',
        'purchaseAmountText': ?(amount is String ? {'simpleText': amount} : amount),
        if (text != null)
          'message': {
            'runs': [
              {'text': text},
            ],
          },
        'headerBackgroundColor': ?header,
        'bodyBackgroundColor': ?body,
        'headerTextColor': 4294967295,
        'bodyTextColor': 4294967295,
        'authorPhoto': ?photo,
      },
    },
  },
};

/// A ticker item for the item [id], pinned for [seconds].
Map<String, Object?> _ticker(String id, Object? seconds, {String kind = 'liveChatTickerPaidMessageItemRenderer'}) => {
  'addLiveChatTickerItemAction': {
    'item': {
      kind: {'id': id, 'durationSec': seconds, 'fullDurationSec': seconds},
    },
    'durationSec': '$seconds',
  },
};

/// The view field (119693434.16.1) of a continuation.
int? _view(String token) =>
    ProtoMessage.decode(base64Url.decode(base64Url.normalize(token.replaceAll('%3D', '='))))
        .message(119693434)
        ?.message(16)
        ?.integer(1);

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '%3D');

/// The first value of [key] in [node], depth first.
Object? _first(Object? node, String key) {
  if (node is Map) {
    if (node.containsKey(key)) return node[key];
    for (final value in node.values) {
      if (_first(value, key) case final found?) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      if (_first(value, key) case final found?) return found;
    }
  }
  return null;
}

/// The reload continuation S06-live's chat answered with once the broadcast
/// was over (S08-ended frame 3): a real Top chat continuation.
final String _endReload = YouTubeDanmakuProtocol.chat(_answer(_frames('S08-ended')[3])).continuation!;

const YouTubeDanmakuArgs _args = YouTubeDanmakuArgs(roomId: 'UCHjbBVD4yRI7vU-S9Pwpnkw', videoId: 'e3n116VqcrE');

void main() {
  group('protocol', () {
    test("v4's endpoints, bodies and timing; the adapter's headers", () {
      final settings = _v4('S06-live')['settings']! as Map<String, Object?>;
      final endpoints = settings['endpoints']! as Map<String, Object?>;
      expect('${YouTubeDanmakuProtocol.nextEndpoint}', endpoints['next']);
      expect('${YouTubeDanmakuProtocol.chatEndpoint}', endpoints['chat']);
      expect(YouTubeDanmakuProtocol.nextBody('VIDEO_ID_11'), settings['nextBody']);
      expect(YouTubeDanmakuProtocol.chatBody('TOKEN'), settings['chatBody']);
      expect(YouTubeDanmakuProtocol.maxFailures, settings['maxFailures']);
      expect(YouTubeDanmakuProtocol.maximumDelay.inMilliseconds, settings['maximumDelayMs']);
      expect(YouTubeDanmakuProtocol.minimumDelay.inMilliseconds, settings['minimumDelayMs']);
      expect(YouTubeDanmakuProtocol.retryDelay.inMilliseconds, settings['retryDelayMs']);
      expect(YouTubeDanmakuProtocol.requestTimeout.inMilliseconds, settings['requestTimeoutMs']);
      // v4 ended the join on the third failed poll (`failures > 2`).
      expect(YouTubeDanmakuProtocol.startAttempts, 3);
      // Difference 13: the adapter's headers; v4 sent content type, origin,
      // cookie and UA only, with the same values.
      final v4Headers = settings['headers']! as Map<String, Object?>;
      expect(YouTubeDanmakuProtocol.headers, YouTubeApi.apiHeaders);
      for (final name in ['origin', 'cookie', 'user-agent']) {
        expect(YouTubeDanmakuProtocol.headers[name], v4Headers[name], reason: name);
      }
      expect(YouTubeDanmakuProtocol.headers, containsPair('accept-language', 'en-US,en;q=0.9'));
      expect(YouTubeDanmakuProtocol.headers, containsPair('referer', 'https://www.youtube.com/'));
      expect(v4Headers['content-type'], 'application/json');
    });

    test('the wait between polls: timeoutMs within 1–5 s, 5 s without one', () {
      Duration delay(int? ms) => YouTubeDanmakuProtocol.pollDelay(ms == null ? null : Duration(milliseconds: ms));
      expect(delay(null), const Duration(seconds: 5));
      expect(delay(10000), const Duration(seconds: 5));
      expect(delay(5000), const Duration(seconds: 5));
      expect(delay(3000), const Duration(seconds: 3));
      expect(delay(1000), const Duration(seconds: 1));
      expect(delay(200), const Duration(seconds: 1));
      expect(delay(0), const Duration(seconds: 1));
    });

    test('next: the continuation, replays, and the live viewers (S06, S07, S08, S10)', () {
      final s06 = YouTubeDanmakuProtocol.watch(_answer(_frames('S06-live').first));
      expect(s06.live, isTrue);
      expect(s06.viewers, isNull, reason: 'the S06 recording kept only the conversation bar');
      final s07 = YouTubeDanmakuProtocol.watch(_answer(_frames('S07-live-paid').first));
      expect([s07.live, s07.replay, s07.viewers], [true, false, 49142]);
      final s08 = _frames('S08-ended');
      final replay = YouTubeDanmakuProtocol.watch(_answer(s08[0]));
      expect([replay.live, replay.replay, replay.viewers], [false, true, null], reason: '"400,387 views" is not live');
      expect(replay.continuation, startsWith('op2w0wRy'));
      final ended = YouTubeDanmakuProtocol.watch(_answer(s08[2]));
      expect([ended.continuation, ended.live, ended.viewers], [null, false, null]);
      final s10 = YouTubeDanmakuProtocol.watch(_answer(_frames('S10-live-all-chat').first));
      expect([s10.live, s10.replay, s10.viewers], [true, false, 15163]);
      expect(() => YouTubeDanmakuProtocol.watch(<Object?>[]), throwsFormatException);
    });

    test('emoji: the character for a standard one, the shortcut for a custom one', () {
      final poll = YouTubeDanmakuProtocol.chat(
        jsonDecode(
          _stepText(
            _named('answers')['runs: text, a link, standard emoji with and without shortcuts, '
                'custom emoji with and without shortcuts']!,
          ),
        ),
      );
      expect(poll.messages.single.message, 'gg example.com 😂🇹🇷:face-purple-crying: !');
      final s06 = _frames('S06-live');
      final line = YouTubeDanmakuProtocol.chat(_answer(s06[3])).messages.last;
      expect(line.message, '👴👴👴👴👴');
    });

    test('the end of a chat: a reload without actions, then no continuationContents (S08)', () {
      final frames = _frames('S08-ended');
      final reload = YouTubeDanmakuProtocol.chat(_answer(frames[3]));
      expect([reload.messages, reload.reload, reload.timeout, reload.ended], [isEmpty, true, null, false]);
      final ended = YouTubeDanmakuProtocol.chat(_answer(frames[4]));
      expect([ended.ended, ended.notice], [true, 'Chat is disabled for this live stream.']);
      expect(() => YouTubeDanmakuProtocol.chat('text'), throwsFormatException);
    });

    test('audience message', () {
      final message = YouTubeDanmakuProtocol.audience(1250);
      expect(message.type, LiveMessageType.online);
      expect(_project(message), {'event': 'viewers', 'kind': 'onlineViewers', 'value': 1250});
    });
  });

  group('recorded answers against v4', () {
    for (final name in ['S06-live', 'S07-live-paid', 'S08-ended']) {
      test('$name: every answer parses to what v4 parsed (differences 1–4; B-13: paid lines are super chats)', () {
        final frames = _frames(name);
        final v4 = _list(_v4(name)['frames']);
        expect(v4, hasLength(frames.length));
        var lines = 0;
        for (final (index, frame) in frames.indexed) {
          final text = frame['text']! as String;
          final expected = v4[index];
          if (_status(frame) != 200) {
            expect(expected, {'frame': index, 'status': _status(frame)});
          } else if (_isNext(frame)) {
            expect(YouTubeDanmakuProtocol.watch(jsonDecode(text)).continuation, expected['initialContinuation']);
          } else {
            final ours = _parsed(text)! as Map<String, Object?>;
            expect(ours, _v4Parsed(expected, text), reason: '$name frame $index');
            lines += (ours['messages']! as List).length;
          }
        }
        expect(lines, {'S06-live': 94, 'S07-live-paid': 255, 'S08-ended': 0}[name]);
      });
    }
  });

  test("M13.16: a channel's custom emoji names its picture; standard emoji and plain lines have none", () {
    final lines = [
      for (final frame in _frames('S07-live-paid'))
        if (_status(frame) == 200 && !_isNext(frame)) ...YouTubeDanmakuProtocol.chat(_answer(frame)).messages,
    ];
    final crying = lines.firstWhere((line) => line.message.contains(':face-purple-crying:'));
    expect(crying.emotes, [
      const LiveEmote(
        code: ':face-purple-crying:',
        url: 'https://yt3.ggpht.com/g6_km98AfdHbN43gvEuNdZ2I07MmzVpArLwEvNBwwPqpZYzszqhRzU_DXALl11TchX5_xFE=w48-h48-c-k-nd',
      ),
    ], reason: 'the larger thumbnail, once although the line repeats it');
    for (final line in lines) {
      for (final emote in line.emotes) {
        expect(line.message, contains(emote.code));
        expect(emote.url, startsWith('https://'));
      }
    }
    expect(lines.where((line) => !line.message.contains(':')).every((line) => line.emotes.isEmpty), isTrue);
  });

  group('synthetic answers (S09-synthetic) against v4', () {
    final answers = _named('answers');
    final v4Answers = _v4Synthetic['answers']! as Map<String, Object?>;
    // Cases where the new code differs beyond differences 1–4 applied to
    // v4's lines: what v4 gave, then what the new code gives.
    final different = <String, void Function(Map<String, Object?> v4, Map<String, Object?> ours)>{
      // Difference 4: v4 read only `simpleText` amounts, so the line had no
      // text and was dropped.
      'fields of other types': (v4, ours) {
        final v4Texts = [for (final event in _list(v4['events'])) event['text']];
        final texts = [for (final message in _list(ours['messages'])) message['text']];
        expect(v4Texts, ['numeric id', 'author in runs', 'author is text', 'run text is a number']);
        expect(texts, [...v4Texts, r'$1.00']);
        expect(ours['messages'], [
          ...(_v4Parsed(v4, _stepText(answers['fields of other types']!))! as Map<String, Object?>)['messages']!
              as List,
          _list(ours['messages']).last,
        ]);
      },
      // Difference 3: a time past DateTime failed v4's whole answer.
      'a time past what DateTime holds': (v4, ours) {
        expect(v4, {'throws': 'ArgumentError'});
        expect(
          [for (final message in _list(ours['messages'])) (message['text'], message['sentAtMicros'])],
          [('before', 1790633046000000), ('far future', null), ('after', 1790633048000000)],
        );
      },
      // Difference 12: no continuation, so the chat is over and the wait of
      // that entry is not read (v4 kept it, though it never waited again).
      'a continuation that is not text': (v4, ours) {
        expect(v4, {'events': <Object?>[], 'continuation': null, 'delayMs': 2000});
        expect(ours, {'messages': <Object?>[], 'continuation': null, 'timeoutMs': null});
      },
      // Difference 5: an answer that is not a JSON object is a failure (tried
      // again); v4 took it for the end of the chat.
      'a JSON array': (v4, ours) {
        expect(v4, {'events': <Object?>[], 'continuation': null, 'delayMs': null});
        expect(ours, {'throws': 'FormatException'});
      },
      'a JSON string': (v4, ours) {
        expect(v4, {'events': <Object?>[], 'continuation': null, 'delayMs': null});
        expect(ours, {'throws': 'FormatException'});
      },
    };

    test('every answer has v4 output; every difference names a case', () {
      expect(v4Answers.keys, answers.keys);
      expect(answers.keys, containsAll(different.keys));
    });

    for (final MapEntry(key: name, value: entry) in answers.entries) {
      test(name, () {
        final text = _stepText(entry);
        final v4 = v4Answers[name]! as Map<String, Object?>;
        final ours = _parsed(text)! as Map<String, Object?>;
        if (different[name] case final check?) {
          check(v4, ours);
        } else {
          expect(ours, _v4Parsed(v4, text));
        }
      });
    }

    test("the continuation's kind and wait", () {
      YouTubeChatPoll poll(String name) => YouTubeDanmakuProtocol.chat(jsonDecode(_stepText(answers[name]!)));
      expect(
        [poll('a timed continuation, 3 s').timeout, poll('a timed continuation, 3 s').reload],
        [const Duration(seconds: 3), false],
      );
      expect([poll('a reload continuation').reload, poll('a reload continuation').timeout], [true, null]);
      expect(poll('two continuation kinds in one entry').continuation, 'SYNTH-first');
      expect(poll('two continuation kinds in one entry').reload, isFalse);
      expect(poll('timeoutMs as text').timeout, isNull);
      expect(poll('timeoutMs negative').timeout, isNull);
      expect(poll('timeoutMs 0').timeout, Duration.zero);
      expect(
        poll('no continuationContents, a message: the chat is over').notice,
        'Chat is disabled for this live stream.',
      );
      expect(poll('an empty object').notice, '');
    });
  });

  group('synthetic next answers (S09-synthetic) against v4', () {
    final nexts = _named('nexts');
    final v4Nexts = _v4Synthetic['nexts']! as Map<String, Object?>;

    test('every next answer has v4 output', () => expect(v4Nexts.keys, nexts.keys));

    for (final MapEntry(key: name, value: entry) in nexts.entries) {
      test(name, () {
        final v4 = v4Nexts[name]! as Map<String, Object?>;
        Object? ours;
        try {
          ours = {'initialContinuation': YouTubeDanmakuProtocol.watch(jsonDecode(_stepText(entry))).continuation};
        } on Object catch (error) {
          ours = {'throws': error.runtimeType.toString()};
        }
        if (name == 'a JSON array holding the chat') {
          // Difference 5: v4 searched any JSON; the new code wants an object.
          expect(v4, {'initialContinuation': 'SYNTH-in-array'});
          expect(ours, {'throws': 'FormatException'});
        } else {
          expect(ours, v4);
        }
      });
    }

    test('viewers and replays', () {
      YouTubeChatEntry watch(String name) => YouTubeDanmakuProtocol.watch(jsonDecode(_stepText(nexts[name]!)));
      expect(watch('live, with the viewers in runs').viewers, 1234);
      expect(watch('live, with the viewers in simpleText').viewers, 1331);
      expect(watch('live, without a view count').viewers, isNull);
      expect(watch('a view count that is not live').viewers, isNull);
      expect([watch('a chat replay').replay, watch('a chat replay').live], [true, false]);
      expect([watch('isReplay false').replay, watch('isReplay false').live], [false, true]);
      expect(watch('no live chat: a conversation bar message').live, isFalse);
    });
  });

  group('sessions against v4', () {
    test('S06-live, then the end of its chat (S08-ended): the same requests, waits and lines', () async {
      final s06 = _frames('S06-live');
      final s08 = _frames('S08-ended');
      final steps = [for (final frame in s06) _step(frame), _step(s08[3]), _step(s08[4])];
      final details = <String>[];
      final ours = await _session('xd_fJRWZuVI', steps, details: details);
      expect(_withoutB13(ours), _v4Session(_list(_v4('S06-live')['session']), steps));
      expect(ours.where((entry) => entry['event'] == 'chat'), hasLength(21));
      expect(details, ['Chat ended: Chat is disabled for this live stream.']);
      // B-13: frame 8's removeChatItemByAuthorAction (frame 1's is history).
      expect(ours.where(_isB13Only), [
        {'event': 'retraction', 'userId': 'GI8fdRKVmbxNudO8rcY3NmBM'},
      ]);
    });

    test('S07-live-paid: the same, and the viewers of next after joining (difference 8)', () async {
      final steps = [for (final frame in _frames('S07-live-paid')) _step(frame)];
      final ours = await _session('e3n116VqcrE', steps);
      expect(_withoutB13(_withoutViewers(ours)), _v4Session(_list(_v4('S07-live-paid')['session']), steps));
      final ready = ours.indexWhere((entry) => entry['event'] == 'ready');
      expect(ours[ready + 1], {'event': 'viewers', 'kind': 'onlineViewers', 'value': 49142});
      expect(ours.where((entry) => entry['event'] == 'chat'), hasLength(203));
      // B-13: the Super Chats are super chats.
      expect(
        [
          for (final entry in ours)
            if (entry['type'] == 'superChat') (entry['text']! as String).split(' ').first,
        ],
        ['TRY 550.00', 'TRY 109.99', 'TRY 1,100.00', 'TRY 22.00'],
      );
      // B-13: the three removals, after the line one of them names.
      final retractions = [
        for (final (index, entry) in ours.indexed)
          if (entry['event'] == 'retraction') (index, entry['messageId']),
      ];
      expect(
        [for (final (_, id) in retractions) id],
        [
          'ChwKGkNJU2o1c1Nra3BjREZiMGkxZ0FkeUZFYXJR',
          'ChwKGkNQems5TW1ra3BjREZRRUF5d1Fka2xRQTdR',
          'ChwKGkNKclcySjJra3BjREZUZmlQd1FkVXQ0aTRB',
        ],
      );
      final shown = ours.indexWhere((entry) => entry['id'] == 'ChwKGkNQems5TW1ra3BjREZRRUF5d1Fka2xRQTdR');
      expect(ours[shown]['type'], 'chat');
      expect(shown, lessThan(retractions[1].$1));
    });

    test('S08-ended: a broadcast with a chat replay ends at once (difference 6)', () async {
      final s08 = _frames('S08-ended');
      final steps = [_step(s08[0]), _step(s08[1]), _step(s08[1]), _step(s08[1])];
      final v4 = _v4Session(_list((_v4('S08-ended')['sessions']! as Map<String, Object?>)['replay']), steps);
      expect(v4.where((entry) => entry['request'] == 'live_chat/get_live_chat'), hasLength(3));
      expect(v4.last, {'event': 'closed', 'reason': 'connectionFailed'});
      final details = <String>[];
      final ours = await _session('xd_fJRWZuVI', steps, details: details);
      expect(ours, [
        v4.first,
        {'event': 'closed', 'reason': 'connectionFailed'},
      ]);
      expect(details, ['Chat replay only']);
    });

    test('S08-ended: a broadcast without a chat ends at once, as in v4', () async {
      final steps = [_step(_frames('S08-ended')[2])];
      final details = <String>[];
      final ours = await _session('9njefMDxzqw', steps, details: details);
      expect(ours, _v4Session(_list((_v4('S08-ended')['sessions']! as Map<String, Object?>)['noChat']), steps));
      expect(details, ['No live chat']);
    });

    final sessions = _named('sessions');
    final v4Sessions = _v4Synthetic['sessions']! as Map<String, Object?>;
    const next = {'request': 'next', 'videoId': 'Synth3tic_0'};
    Map<String, Object?> poll(String token) => {'request': 'live_chat/get_live_chat', 'continuation': token};
    const ready = {'event': 'ready'};
    const viewers = {'event': 'viewers', 'kind': 'onlineViewers', 'value': 1234};
    const failed = {'event': 'closed', 'reason': 'connectionFailed'};
    Map<String, Object?> chat(String text) => {'event': 'chat', 'text': text};
    Map<String, Object?> brief(Map<String, Object?> item) =>
        item['event'] == 'chat' ? chat(item['text']! as String) : item;
    // The sessions where the new code differs from v4: its trace, with chat
    // lines by their text only.
    final different = <String, List<Map<String, Object?>>>{
      // Difference 9: next is tried again; v4 ended at its first failure.
      'next fails once': [
        next,
        {'wait': 2000},
        next,
        poll('SYNTH-reload-0'),
        ready,
        viewers,
        {'wait': 5000},
        poll('SYNTH-1'),
        chat('after a retry'),
        failed,
      ],
      'next fails three times': [
        next,
        {'wait': 2000},
        next,
        {'wait': 2000},
        next,
        failed,
      ],
      // Difference 9: no reconnecting notice while joining.
      'the first poll fails twice, then answers': [
        next,
        poll('SYNTH-reload-0'),
        {'wait': 2000},
        poll('SYNTH-reload-0'),
        {'wait': 2000},
        poll('SYNTH-reload-0'),
        ready,
        viewers,
        {'wait': 5000},
        poll('SYNTH-1'),
        chat('shown'),
        failed,
      ],
      'the first poll fails three times': [
        next,
        poll('SYNTH-reload-0'),
        {'wait': 2000},
        poll('SYNTH-reload-0'),
        {'wait': 2000},
        poll('SYNTH-reload-0'),
        failed,
      ],
      // Difference 6: a replay has no live chat to poll.
      'a chat replay': [next, failed],
      // Difference 10: a chat over before joining is not joined.
      'the history answer has no continuation': [next, poll('SYNTH-reload-0'), failed],
      // Difference 7: the answer to a reload continuation is history.
      'a reload in the middle': [
        next,
        poll('SYNTH-reload-0'),
        ready,
        {'wait': 5000},
        poll('SYNTH-1'),
        chat('before the reload'),
        {'wait': 5000},
        poll('SYNTH-reload'),
        {'wait': 5000},
        poll('SYNTH-2'),
        chat('after the reload'),
        failed,
      ],
      // Difference 14: only a video id is asked for.
      'not a video id': [failed],
    };

    test('every session has v4 output; every difference names a session', () {
      expect(v4Sessions.keys, sessions.keys);
      expect(sessions.keys, containsAll(different.keys));
    });

    for (final MapEntry(key: name, value: entry) in sessions.entries) {
      test(name, () async {
        final steps = _list(entry['steps']);
        final videoId = entry['videoId']! as String;
        final v4 = _v4Session(_list(v4Sessions[name]), steps);
        final ours = _withoutB13(await _session(videoId, steps));
        if (different[name] case final expected?) {
          expect(v4, isNot(equals(ours)));
          expect(ours.map(brief).toList(), expected);
        } else {
          expect(_withoutViewers(ours), v4);
        }
      });
    }

    test('the close details and the statuses', () async {
      final details = <String>[];
      final statuses = <DanmakuStatus>[];
      await _session(
        'Synth3tic_0',
        _list(sessions['failures after joining, then recovery']!['steps']),
        details: details,
        statuses: statuses,
      );
      expect(details, [
        'TransportFailure(youtube, timeout: scripted)',
        'HttpStatusFailure(youtube, 503)',
        'Chat ended',
      ]);
      expect(statuses, [
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected,
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected,
        DanmakuStatus.connected,
        DanmakuStatus.closed,
        DanmakuStatus.idle,
      ]);
      final exhausted = <String>[];
      await _session('Synth3tic_0', _list(sessions['eight failures in a row']!['steps']), details: exhausted);
      expect(exhausted, ['HttpStatusFailure(youtube, 500)', 'HttpStatusFailure(youtube, 500)']);
      final start = <String>[];
      await _session('Synth3tic_0', _list(sessions['next fails three times']!['steps']), details: start);
      expect(start, ['TransportFailure(youtube, connect: scripted)']);
      final none = <String>[];
      await _session('  ', const [], details: none);
      expect(none, ['No broadcast']);
    });
  });

  group('B-13: super chats', () {
    test('S07: every Super Chat as a super chat: the amount as shown, the colours, the time by tier', () {
      final frames = _frames('S07-live-paid');
      final paid = [
        for (final frame in frames.skip(1))
          for (final message in YouTubeDanmakuProtocol.chat(_answer(frame), now: _recordedAt).messages)
            if (message.type == LiveMessageType.superChat) message,
      ];
      // The recording's ticker items were scrubbed to {}, so the time is the
      // tier's, told by the header colour.
      expect(
        [for (final message in paid) (_superChat(message)['priceText'], _superChat(message)['seconds'])],
        [
          ('₫1,000,000', 3600),
          ('TRY 55.00', 120),
          ('TRY 550.00', 1800),
          ('TRY 109.99', 120),
          ('TRY 1,100.00', 3600),
          ('TRY 22.00', 60),
        ],
      );
      final one = paid[2];
      expect(_superChat(one), {
        'id': 'ChwKGkNQbWNpY2Vra3BjREZiekdQd1FkcjlBdGln',
        'userName': '@LvrbiQzluYwuhvst',
        'userId': 'UC_b8aCJb3slYrZuLjea38Sr',
        'face': '',
        'message': startsWith('Nihat abi bu adamı 3 cümlenle'),
        'price': 0,
        'priceText': 'TRY 550.00',
        'startMicros': 1790633230349018,
        'seconds': 1800,
        'colors': ['#c2185b', '#e91e63'],
      });
      expect(one.sentAt, DateTime.fromMicrosecondsSinceEpoch(1790633230349018));
      expect(one.sentAt!.isUtc, isFalse);
      expect([one.userLevel, one.fansLevel, one.fansName, one.isLocal], ['', '', '', false]);
      expect((one.data! as LiveSuperChatMessage).endTime, one.sentAt!.add(const Duration(minutes: 30)));
    });

    test("S10: the time is the ticker item's fullDurationSec; without one (light blue) a minute", () {
      final frames = _frames('S10-live-all-chat');
      final rows = <List<Object?>>[];
      for (final frame in frames) {
        if (_isNext(frame) || _isMetadata(frame)) continue;
        final answer = _answer(frame);
        final pinned = <String, int>{
          for (final action in _actions(answer))
            if (action case {'addLiveChatTickerItemAction': {'item': final Map<String, Object?> item}})
              if (item.values.single case {'id': final String id, 'fullDurationSec': final int seconds}) id: seconds,
        };
        for (final message in YouTubeDanmakuProtocol.chat(answer, now: _recordedAt).messages) {
          if (message.type != LiveMessageType.superChat) continue;
          final fields = _superChat(message);
          expect(fields['seconds'], pinned[fields['id']] ?? 60, reason: '${fields['priceText']}');
          expect(fields['startMicros'], message.sentAt!.microsecondsSinceEpoch);
          rows.add([fields['priceText'], fields['seconds'], ...fields['colors']! as List<Object?>]);
        }
      }
      expect(rows, [
        // The first answer (history; parsed here, never reported).
        ['¥500', 120, '#00bfa5', '#1de9b6'],
        ['¥3,200', 600, '#e65100', '#f57c00'],
        ['¥1,563', 300, '#ffb300', '#ffca28'],
        [r'$20.00', 600, '#e65100', '#f57c00'],
        ['¥500', 120, '#00bfa5', '#1de9b6'],
        ['¥5,000', 1800, '#c2185b', '#e91e63'],
        ['₩50,000', 1800, '#c2185b', '#e91e63'],
        // Later answers. ¥20,000 is red too, pinned 2 h, not the tier's 1 h.
        [r'R$100.00', 3600, '#d00000', '#e62117'],
        ['¥1,563', 300, '#ffb300', '#ffca28'],
        ['¥20,000', 7200, '#d00000', '#e62117'],
        ['¥320', 60, '#00b8d4', '#00e5ff'],
      ]);
      expect(YouTubeDanmakuProtocol.tierDisplay[0xFFD00000], const Duration(hours: 1));
    });

    test('the tier table when no ticker item names the message; an unknown colour is a minute', () {
      final tiers = {
        0xFF1565C0: 60,
        0xFF00B8D4: 60,
        0xFF00BFA5: 120,
        0xFFFFB300: 300,
        0xFFE65100: 600,
        0xFFC2185B: 1800,
        0xFFD00000: 3600,
        0xFF123456: 60,
      };
      final answer = _chatAnswer([
        for (final (index, colour) in tiers.keys.indexed) _paid(index, header: colour),
        _paid(20, header: '4291821568'),
        _paid(21, header: null, body: null),
      ]);
      expect(
        [for (final message in YouTubeDanmakuProtocol.chat(answer).messages) _superChat(message)['seconds']],
        [...tiers.values, 60, 60],
      );
      expect(YouTubeDanmakuProtocol.unpinnedDisplay, const Duration(minutes: 1));
    });

    test('ticker items: only a whole positive fullDurationSec for the same id counts, before or after it', () {
      final answer = _chatAnswer([
        _ticker('P1', 7200),
        _paid(1),
        _paid(2),
        _ticker('P2', 0),
        _paid(3),
        _ticker('P3', '300'),
        _paid(4),
        _ticker('P4', -5),
        _paid(5),
        _ticker('another', 900),
        _paid(6, header: 0xFF00BFA5),
        _ticker('P6', 150, kind: 'liveChatTickerSomethingNewRenderer'),
        _ticker('', 900),
      ]);
      expect(
        [for (final message in YouTubeDanmakuProtocol.chat(answer).messages) _superChat(message)['seconds']],
        [7200, 3600, 3600, 3600, 3600, 150],
      );
    });

    test('fields: no platform time starts now; colours, avatar, amount and text of other shapes', () {
      final now = DateTime.utc(2026, 9, 30, 15, 13, 30);
      final photo = {
        'thumbnails': [
          {'url': 'https://yt4.ggpht.com/synthetic-photo=s32-c-k-c0x00ffffff-no-rj', 'width': 32, 'height': 32},
          {'url': 'https://yt4.ggpht.com/synthetic-photo=s64-c-k-c0x00ffffff-no-rj', 'width': 64, 'height': 64},
        ],
      };
      final answer = _chatAnswer([
        _paid(1, time: null, photo: photo),
        _paid(2, time: '0', header: 0x1FFFFFFFF, body: -1),
        _paid(
          3,
          amount: {
            'runs': [
              {'text': r'  $2.00 '},
            ],
          },
          text: null,
          photo: {
            'thumbnails': [
              {'url': '//yt4.ggpht.com/synthetic-photo=s64'},
            ],
          },
        ),
        _paid(
          4,
          amount: null,
          text: 'no amount',
          photo: {
            'thumbnails': [
              {'url': 'http://yt4.ggpht.com/insecure'},
            ],
          },
        ),
        _paid(5, amount: null, text: null),
        _paid(6, amount: '  ', text: '  '),
        _paid(7, amount: 5, text: 'amount not text', photo: {'thumbnails': <Object?>[]}),
      ]);
      final messages = YouTubeDanmakuProtocol.chat(answer, now: now).messages;
      expect(messages.map(_superChat).toList(), [
        {
          'id': 'P1',
          'userName': '@payer1',
          'userId': 'UCsyntheticPayer00000001',
          'face': 'https://yt4.ggpht.com/synthetic-photo=s64-c-k-c0x00ffffff-no-rj',
          'message': 'thanks',
          'price': 0,
          'priceText': r'$5.00',
          'startMicros': now.microsecondsSinceEpoch,
          'seconds': 3600,
          'colors': ['#d00000', '#e62117'],
        },
        {
          'id': 'P2',
          'userName': '@payer2',
          'userId': 'UCsyntheticPayer00000002',
          'face': '',
          'message': 'thanks',
          'price': 0,
          'priceText': r'$5.00',
          'startMicros': now.microsecondsSinceEpoch,
          'seconds': 60,
          'colors': ['', ''],
        },
        {
          'id': 'P3',
          'userName': '@payer3',
          'userId': 'UCsyntheticPayer00000003',
          'face': 'https://yt4.ggpht.com/synthetic-photo=s64',
          'message': '',
          'price': 0,
          'priceText': r'$2.00',
          'startMicros': 1790781200000003,
          'seconds': 3600,
          'colors': ['#d00000', '#e62117'],
        },
        {
          'id': 'P4',
          'userName': '@payer4',
          'userId': 'UCsyntheticPayer00000004',
          'face': '',
          'message': 'no amount',
          'price': 0,
          'priceText': '',
          'startMicros': 1790781200000004,
          'seconds': 3600,
          'colors': ['#d00000', '#e62117'],
        },
        {
          'id': 'P7',
          'userName': '@payer7',
          'userId': 'UCsyntheticPayer00000007',
          'face': '',
          'message': 'amount not text',
          'price': 0,
          'priceText': '',
          'startMicros': 1790781200000007,
          'seconds': 3600,
          'colors': ['#d00000', '#e62117'],
        },
      ]);
      expect(
        [for (final message in messages) message.sentAt?.microsecondsSinceEpoch],
        [null, null, 1790781200000003, 1790781200000004, 1790781200000007],
      );
    });

    test('S09: the synthetic Super Chats', () {
      final answers = _named('answers');
      List<Map<String, Object?>> superChats(String name) => [
        for (final message in YouTubeDanmakuProtocol.chat(jsonDecode(_stepText(answers[name]!))).messages)
          if (message.type == LiveMessageType.superChat) _superChat(message),
      ];
      expect(superChats('a Super Chat with a message').single, {
        'id': 'ChwKGkP00000000000000000001',
        'userName': '@supporter1',
        'userId': 'UCsyntheticViewer0001001',
        'face': '',
        'message': 'great show 👏',
        'price': 0,
        'priceText': 'TRY 55.00',
        'startMicros': 1790633001000000,
        'seconds': 3600,
        'colors': ['#d00000', '#e62117'],
      });
      expect(superChats('a Super Chat without a message').single['message'], '');
      expect(superChats('a Super Chat with neither amount nor message'), isEmpty);
      expect(superChats('a Super Chat with only spaces for its message').single, containsPair('message', ''));
      expect(superChats('fields of other types').single, containsPair('priceText', r'$1.00'));
    });

    test('super chats, notices and retractions pass the message filter untouched', () {
      final filter = DanmakuMessageFilter(
        settings: const DanmakuFilterSettings(blockedKeywords: ['thanks', 'welcome'], blockedUsers: ['@payer1']),
        clock: () => _recordedAt,
      );
      final messages = YouTubeDanmakuProtocol.chat(
        _chatAnswer([
          _paid(1),
          _paid(1),
          {
            'removeChatItemAction': {'targetItemId': 'P1'},
          },
          {
            'addChatItemAction': {
              'item': {
                'liveChatMembershipItemRenderer': {
                  'id': 'M1',
                  'authorName': {'simpleText': '@payer1'},
                  'headerSubtext': {'simpleText': 'Welcome to Members!'},
                },
              },
            },
          },
        ]),
        now: _recordedAt,
      ).messages;
      expect([for (final message in messages) filter.accepts(message)], [true, true, true, true]);
    });
  });

  group('B-13: notices', () {
    test('S10: a new member and milestones', () {
      final frames = _frames('S10-live-all-chat');
      final notices = [
        for (final entry in _messages(_answer(frames[7])))
          if (entry['event'] == 'notice') entry,
      ];
      expect(notices, [
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': 'ChwKGkNLdjhwWV9NbHBjREZlN1B3Z1FkejlRR2N3',
          'sentAtMicros': 1790781277439430,
          'userId': 'UC6FWujV09YvMpTZQ3T-RDz1',
          'userName': '@p5x7pg0pdlzzv',
          'text': '@p5x7pg0pdlzzv Welcome to 生贄の祭壇!',
        },
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': 'Ci8KLUNOcVJzNlhGa0pjREZUemJ2Z2dkcURjOVJnLUxveU1lc0lELTM1ODE1NjI1Ng%3D%3D',
          'sentAtMicros': 1790781282265685,
          'userId': 'UCatLkX_L5MnHcg9fjg-hygJ',
          'userName': '@3y3cwq',
          'text': '@3y3cwq Member for 65 months（生贄の祭壇）：今年もおめでとーーーーーーーー！！ まだ末長くよろしくお願いしますなぁ〜(*´ω｀*)',
        },
      ]);
      final history = [
        for (final entry in _messages(_answer(frames[1])))
          if (entry['event'] == 'notice') entry['text'],
      ];
      expect(history, [
        '@gy3w4b6nq Member for 29 months（生贄の祭壇）：ころさんおめでとう！！！🎊🎉:_koroneListener2::_koroneIiyubi:',
        '@n6cfyyy0isv Member for 15 months（生贄の祭壇）：遅れましたが、ころさん誕生日おめでとうーーー！！！！',
        '@onlmd5thpo Member for 65 months（生贄の祭壇）：こうして8年目のお誕生日を一緒にお祝いできて、僕も誇らしい気持ちでいっぱいです。',
      ]);
    });

    test('S10: Super Stickers and gifted memberships, the renderers the ticker carries', () {
      final history = _answer(_frames('S10-live-all-chat')[1]);
      final items = [
        for (final action in _actions(history))
          if (action case {'addLiveChatTickerItemAction': {'item': final Map<String, Object?> item}})
            if (item.values.single
                case {
                  'showItemEndpoint': {'showLiveChatItemEndpoint': {'renderer': final Map<String, Object?> renderer}},
                }
                when !renderer.containsKey('liveChatPaidMessageRenderer') &&
                    !renderer.containsKey('liveChatMembershipItemRenderer'))
              {
                'addChatItemAction': {'item': renderer},
              },
      ];
      expect(_messages(_chatAnswer(items)), [
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': 'ChwKGkNLV09sLURKbHBjREZhRFB3Z1FkbU5FYjJB',
          'sentAtMicros': 1790780659954090,
          'userId': 'UCXKrfBiorCZiMkmwjl2eltS',
          'userName': '@zl0hsi',
          'text':
              '@zl0hsi 送出 Super Sticker ¥3,000：Pear character dancing under a rain of confetti and taking his hat off '
              "to say 'You are amazing'",
        },
        // The ticker's copy of a gift purchase has no id or time of its own.
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': '',
          'sentAtMicros': null,
          'userId': 'UC9drtFV5h6c5JWDpIC6Xm43',
          'userName': '@oogk2uz8tmeobv',
          'text': '@oogk2uz8tmeobv Sent 50 Korone Ch. 戌神ころね gift memberships',
        },
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': 'ChwKGkNNNll5SURKbHBjREZTWEV3Z1FkX0pvcDJR',
          'sentAtMicros': 1790780457858217,
          'userId': 'UC6ohVsPewG0uRNJ9IoPJi-o',
          'userName': '@ejrtuybl',
          'text': '@ejrtuybl 送出 Super Sticker ¥5,000：Shiba dog jumping in the air with fireworks around him',
        },
        {
          'event': 'notice',
          'kind': 'subscription',
          'id': 'ChwKGkNKS0o3ZTdJbHBjREZjWGV3Z1FkeWlNS0x3',
          'sentAtMicros': 1790780435460460,
          'userId': 'UCqTl-CDxSXu7SAIrp5YZKT-',
          'userName': '@4bvmu',
          'text': '@4bvmu 送出 Super Sticker ¥5,000：Shiba dog jumping in the air with fireworks around him',
        },
      ]);
    });

    test('synthetic: a received gift, a gift purchase, and items without text', () {
      Map<String, Object?> item(String kind, Map<String, Object?> renderer) => {
        'addChatItemAction': {
          'item': {kind: renderer},
        },
      };
      Map<String, Object?> runs(List<String> texts) => {
        'runs': [
          for (final text in texts) {'text': text, 'bold': true},
        ],
      };
      final answer = _chatAnswer([
        item('liveChatSponsorshipsGiftRedemptionAnnouncementRenderer', {
          'id': 'G1',
          'timestampUsec': '1790781300000000',
          'authorExternalChannelId': 'UCsyntheticReceiver00001',
          'authorName': {'simpleText': '@receiver'},
          'message': runs(['received a gift membership by ', '@gifter']),
        }),
        item('liveChatSponsorshipsGiftPurchaseAnnouncementRenderer', {
          'id': 'G2',
          'timestampUsec': '1790781301000000',
          'authorExternalChannelId': 'UCsyntheticGifter0000001',
          'header': {
            'liveChatSponsorshipsHeaderRenderer': {
              'authorName': {'simpleText': '@gifter'},
              'primaryText': runs(['Sent ', '5', ' ', 'Synthetic Channel', ' gift memberships']),
            },
          },
        }),
        item('liveChatSponsorshipsGiftPurchaseAnnouncementRenderer', {'id': 'G3'}),
        item('liveChatSponsorshipsGiftRedemptionAnnouncementRenderer', {
          'id': 'G4',
          'authorName': {'simpleText': '@receiver'},
        }),
        item('liveChatMembershipItemRenderer', {
          'id': 'M1',
          'authorName': {'simpleText': '@member'},
          'message': runs(['a message without a header']),
        }),
        item('liveChatMembershipItemRenderer', {
          'id': 'M2',
          'authorName': {'simpleText': '@member'},
          'headerPrimaryText': runs(['Member for ', '2', ' months']),
        }),
        item('liveChatMembershipItemRenderer', {
          'id': 'M3',
          'headerSubtext': {'simpleText': 'New member'},
        }),
        item('liveChatPaidStickerRenderer', {
          'id': 'S1',
          'authorName': {'simpleText': '@sticker'},
        }),
        item('liveChatPaidStickerRenderer', {
          'id': 'S2',
          'authorName': {'simpleText': '@sticker'},
          'sticker': {
            'accessibility': {
              'accessibilityData': {'label': ' A cat waving '},
            },
          },
        }),
        item('liveChatPaidStickerRenderer', {
          'id': 'S3',
          'purchaseAmountText': {'simpleText': '€2.00'},
          'sticker': {'accessibility': 'not a map'},
        }),
        item('liveChatAutoModMessageRenderer', {'id': 'X1'}),
        item('giftMessageViewModel', {
          'id': 'X2',
          'text': {'content': 'sent Donut'},
        }),
      ]);
      expect(
        [for (final entry in _messages(answer)) (entry['id'], entry['text'])],
        [
          ('G1', '@receiver received a gift membership by @gifter'),
          ('G2', '@gifter Sent 5 Synthetic Channel gift memberships'),
          ('M2', '@member Member for 2 months'),
          ('M3', 'New member'),
          ('S1', '@sticker 送出 Super Sticker'),
          ('S2', '@sticker 送出 Super Sticker：A cat waving'),
          ('S3', '送出 Super Sticker €2.00'),
          // B-23: the gift item is read now, as a gift (was not read).
          ('X2', 'sent Donut'),
        ],
      );
      final messages = YouTubeDanmakuProtocol.chat(answer).messages;
      expect(messages.last.type, LiveMessageType.gift);
      expect(
        messages.take(messages.length - 1).every((message) => message.data == LiveNoticeKind.subscription),
        isTrue,
      );
      expect(
        [messages[0].userId, messages[0].userName, messages[0].sentAt?.microsecondsSinceEpoch],
        ['UCsyntheticReceiver00001', '@receiver', 1790781300000000],
      );
    });

    test('S09: a sticker and a membership are notices now; the gift purchase without a header is not', () {
      final answer = jsonDecode(
        _stepText(
          _named('answers')['Super Stickers, memberships, gifted memberships, engagement messages and placeholders '
              'are not read']!,
        ),
      );
      expect(
        [for (final entry in _messages(answer)) (entry['event'], entry['text'])],
        [
          ('notice', '@sticker10 送出 Super Sticker €2.00'),
          ('notice', '@member11 Welcome to Members!'),
          ('chat', 'after the others'),
        ],
      );
    });
  });

  group('B-13: retractions', () {
    test('S07: removeChatItemAction; S06: removeChatItemByAuthorAction', () {
      final s07 = _frames('S07-live-paid');
      expect(_messages(_answer(s07[4])).where(_isB13Only), [
        {'event': 'retraction', 'messageId': 'ChwKGkNJU2o1c1Nra3BjREZiMGkxZ0FkeUZFYXJR'},
      ]);
      final s06 = _frames('S06-live');
      expect(_messages(_answer(s06[8])).where(_isB13Only), [
        {'event': 'retraction', 'userId': 'GI8fdRKVmbxNudO8rcY3NmBM'},
      ]);
      final retraction = YouTubeDanmakuProtocol.chat(_answer(s06[8])).messages.last;
      expect(retraction.type, LiveMessageType.retraction);
      expect(retraction.data, const LiveRetraction.user('GI8fdRKVmbxNudO8rcY3NmBM'));
      expect(retraction.color, LiveMessageColor.white);
    });

    test('the four removal actions, in order; ids missing, empty or not text; other actions', () {
      final answer = _chatAnswer([
        'before',
        {
          'removeChatItemAction': {'targetItemId': 'A'},
        },
        {
          'markChatItemAsDeletedAction': {
            'targetItemId': 'B',
            'deletedStateMessage': {
              'runs': [
                {'text': '[message deleted]'},
              ],
            },
          },
        },
        {
          'removeChatItemByAuthorAction': {'externalChannelId': 'UCsyntheticAuthor0000001'},
        },
        {
          'markChatItemsByAuthorAsDeletedAction': {
            'externalChannelId': 'UCsyntheticAuthor0000002',
            'deletedStateMessage': {'simpleText': '[message retracted]'},
          },
        },
        {'removeChatItemAction': <String, Object?>{}},
        {
          'removeChatItemAction': {'targetItemId': ''},
        },
        {
          'markChatItemAsDeletedAction': {'targetItemId': 7},
        },
        {
          'removeChatItemByAuthorAction': {'externalChannelId': null},
        },
        {'markChatItemsByAuthorAsDeletedAction': 'not a map'},
        {
          'replaceChatItemAction': {
            'targetItemId': 'C',
            'replacementItem': (_textItem('replacement')['addChatItemAction']! as Map)['item'],
          },
        },
        {'clearChatWindowAction': <String, Object?>{}},
        {
          'clickTrackingParams': 'CAEQ',
          'removeChatItemAction': {'targetItemId': 'D'},
        },
        'after',
      ]);
      expect(
        [for (final entry in _messages(answer)) entry['text'] ?? entry],
        [
          'before',
          {'event': 'retraction', 'messageId': 'A'},
          {'event': 'retraction', 'messageId': 'B'},
          {'event': 'retraction', 'userId': 'UCsyntheticAuthor0000001'},
          {'event': 'retraction', 'userId': 'UCsyntheticAuthor0000002'},
          {'event': 'retraction', 'messageId': 'D'},
          'after',
        ],
      );
    });

    test('S09: removals are retractions now; the replacement and other actions are still not read', () {
      final answer = jsonDecode(
        _stepText(_named('answers')['removals, a replacement and other actions are not read']!),
      );
      expect(
        [for (final entry in _messages(answer)) entry['text'] ?? entry],
        [
          {'event': 'retraction', 'messageId': 'ChwKGkN00000000000000000001'},
          {'event': 'retraction', 'userId': 'UCsyntheticViewer0000016'},
          {'event': 'retraction', 'messageId': 'ChwKGkN00000000000000000002'},
          'still read',
        ],
      );
    });

    test('the duplicate gate: a retraction has no id of its own, so it never collides with its line', () {
      final poll = YouTubeDanmakuProtocol.chat(
        _chatAnswer([
          'first',
          {
            'removeChatItemAction': {'targetItemId': 'id-first'},
          },
          {
            'removeChatItemAction': {'targetItemId': 'id-second'},
          },
          {
            'removeChatItemAction': {'targetItemId': 'id-first'},
          },
        ]),
      );
      final gate = DanmakuMessageGate();
      final now = DateTime.fromMicrosecondsSinceEpoch(1790633000000000).add(const Duration(seconds: 1));
      expect([for (final message in poll.messages) gate.accepts(message, now: now)], [true, true, true, false]);
    });
  });

  group('B-13: the viewer count (updated_metadata)', () {
    test('S10 and S11: the count and the continuation of each answer; an ended broadcast has no count', () {
      final s10 = [
        for (final frame in _frames('S10-live-all-chat'))
          if (_isMetadata(frame)) frame,
      ];
      final first = YouTubeDanmakuProtocol.metadata(_answer(s10[0]));
      final second = YouTubeDanmakuProtocol.metadata(_answer(s10[1]));
      expect(s10[0]['request'], {'videoId': 'lNPh7CdwkWk'});
      expect([first.viewers, second.viewers], [15987, 16217]);
      expect(_asked(s10[1]), first.continuation);
      expect(second.continuation, startsWith('-of5rQMZ'));
      final s11 = _frames('S11-metadata-ended');
      final ended = YouTubeDanmakuProtocol.metadata(_answer(s11[0]));
      expect([ended.viewers, _asked(s11[1])], [null, ended.continuation]);
      expect(YouTubeDanmakuProtocol.metadata(_answer(s11[1])).viewers, isNull);
      expect(YouTubeDanmakuProtocol.metadata(<String, Object?>{}), (viewers: null, continuation: null));
      expect(
        YouTubeDanmakuProtocol.metadata({
          'continuation': {
            'timedContinuationData': {'continuation': 7},
          },
        }).continuation,
        isNull,
      );
      expect(() => YouTubeDanmakuProtocol.metadata('text'), throwsFormatException);
      expect(YouTubeDanmakuProtocol.metadataBody('lNPh7CdwkWk'), {
        'context': YouTubeApi.webContext,
        'videoId': 'lNPh7CdwkWk',
      });
      expect(YouTubeDanmakuProtocol.metadataContinuationBody('C'), {
        'context': YouTubeApi.webContext,
        'continuation': 'C',
      });
      expect(
        '${YouTubeDanmakuProtocol.metadataEndpoint}',
        'https://www.youtube.com/youtubei/v1/updated_metadata?prettyPrint=false',
      );
      expect(YouTubeDanmakuProtocol.viewerInterval, const Duration(seconds: 30));
    });

    test('every 30 s once joined: by video id, then with the continuation; each count reported (S10)', () async {
      final frames = _frames('S10-live-all-chat');
      final metadata = [
        for (final frame in frames)
          if (_isMetadata(frame)) _step(frame),
      ];
      final metadataRequests = <LiveRequest>[];
      final ours = await _session(
        'lNPh7CdwkWk',
        [_step(frames[0]), _step(frames[1])],
        metadata: metadata,
        viewerPolls: true,
        allChat: true,
        metadataRequests: metadataRequests,
      );
      Map<String, Object?> count(int value) => {'event': 'viewers', 'kind': 'onlineViewers', 'value': value};
      final continuation = YouTubeDanmakuProtocol.chat(_answer(frames[1])).continuation;
      expect(ours, [
        {'request': 'next', 'videoId': 'lNPh7CdwkWk'},
        {'request': 'live_chat/get_live_chat', 'continuation': _asked(frames[1])},
        {'event': 'ready'},
        count(15163),
        // B-22: the Super Chats the first answer's ticker still pins.
        for (final message in YouTubeDanmakuProtocol.chat(_answer(frames[1]), now: _recordedAt).pinned)
          _project(message),
        {'wait': 5000},
        {'wait': 30000},
        {'request': 'live_chat/get_live_chat', 'continuation': continuation},
        {'request': 'updated_metadata', 'videoId': 'lNPh7CdwkWk'},
        count(15987),
        {'wait': 30000},
        {'request': 'updated_metadata', 'continuation': _asked(frames[5])},
        count(16217),
        {'wait': 30000},
        {
          'request': 'updated_metadata',
          'continuation': YouTubeDanmakuProtocol.metadata(_answer(frames[5])).continuation,
        },
      ]);
      for (final request in metadataRequests) {
        expect([request.method, request.site, request.timeout], ['POST', 'youtube', const Duration(seconds: 15)]);
        expect(request.headers, {...YouTubeApi.apiHeaders, 'content-type': 'application/json; charset=utf-8'});
        expect(_body(request)['context'], YouTubeApi.webContext);
      }
      // The session closed while the last one waited: it was cancelled.
      expect(metadataRequests.last.cancel!.isCancelled, isTrue);
    });

    test('a failure or an answer without a count reports nothing and leaves the chat alone', () async {
      final ended = _frames('S11-metadata-ended');
      final s10 = _frames('S10-live-all-chat');
      final statuses = <DanmakuStatus>[];
      final metadataRequests = <LiveRequest>[];
      final ours = await _session(
        'lNPh7CdwkWk',
        [
          {'answer': _watchAnswer()},
          {'answer': _chatAnswer(const [])},
        ],
        metadata: [
          {'status': 500},
          {'raw': '<html>not json</html>'},
          {'error': 'timeout'},
          _step(ended[0]),
          _step(s10[2]),
        ],
        viewerPolls: true,
        statuses: statuses,
        metadataRequests: metadataRequests,
      );
      expect(
        [for (final request in metadataRequests) _body(request)..remove('context')],
        [
          {'videoId': 'lNPh7CdwkWk'},
          {'videoId': 'lNPh7CdwkWk'},
          {'videoId': 'lNPh7CdwkWk'},
          {'videoId': 'lNPh7CdwkWk'},
          {'continuation': _asked(ended[1])},
          {'continuation': YouTubeDanmakuProtocol.metadata(_answer(s10[2])).continuation},
        ],
      );
      expect(
        [
          for (final entry in ours)
            if (entry['event'] != null) entry,
        ],
        [
          {'event': 'ready'},
          {'event': 'viewers', 'kind': 'onlineViewers', 'value': 15987},
        ],
      );
      expect(statuses, [DanmakuStatus.connected, DanmakuStatus.connected, DanmakuStatus.idle]);
    });

    test('no viewer request before the chat is joined, nor after it ended', () async {
      final metadataRequests = <LiveRequest>[];
      await _session('Synth3tic_0', [
        {'answer': _watchAnswer()},
        {'status': 500},
        {'status': 500},
        {'status': 500},
      ], metadataRequests: metadataRequests);
      expect(metadataRequests, isEmpty);
      final ended = <LiveRequest>[];
      final trace = await _session(
        'Synth3tic_0',
        [
          {'answer': _watchAnswer()},
          {'answer': _chatAnswer(const [])},
          {
            'answer': _chatAnswer(['last'], token: null),
          },
        ],
        viewerPolls: true,
        metadataRequests: ended,
      );
      // The chat ends before the first viewer wait is over.
      expect(trace.last, {'event': 'closed', 'reason': 'connectionFailed'});
      expect(trace, contains(equals({'wait': 30000})));
      expect(ended, isEmpty);
    });
  });

  group('B-13: the "Live chat" view', () {
    final s06Next = YouTubeDanmakuProtocol.watch(_answer(_frames('S06-live').first)).continuation!;
    final s10 = _frames('S10-live-all-chat');
    final s10Next = YouTubeDanmakuProtocol.watch(_answer(s10.first)).continuation!;

    test("the view field: rewriting Top chat's selector gives the page's own Live chat selector", () {
      for (final frame in [_frames('S06-live').first, s10.first]) {
        final selector = <String, String>{
          for (final item in (_first(_answer(frame), 'subMenuItems')! as List).cast<Map<String, Object?>>())
            item['title']! as String: _first(item['continuation'], 'continuation')! as String,
        };
        expect(selector.keys, ['Top chat', 'Live chat']);
        expect([_view(selector['Top chat']!), _view(selector['Live chat']!)], [4, 1]);
        expect(YouTubeDanmakuProtocol.allChatContinuation(selector['Top chat']!), selector['Live chat']);
        expect(YouTubeDanmakuProtocol.allChatContinuation(selector['Live chat']!), selector['Live chat']);
      }
    });

    test("S10: next's continuation rewritten is the one the server accepted; its answers keep the view", () {
      expect(_view(s10Next), 4);
      final live = YouTubeDanmakuProtocol.allChatContinuation(s10Next);
      expect(live, _asked(s10[1]));
      expect(_view(live!), 1);
      for (final frame in s10.skip(1)) {
        if (_isMetadata(frame)) continue;
        expect(_view(YouTubeDanmakuProtocol.chat(_answer(frame)).continuation!), 1);
      }
      // The Top chat recordings keep 4.
      for (final frame in _frames('S06-live').skip(1)) {
        expect(_view(YouTubeDanmakuProtocol.chat(_answer(frame)).continuation!), 4);
      }
    });

    test('the rewrite changes one byte: that varint, from 4 to 1', () {
      for (final token in [s06Next, s10Next, _asked(_frames('S08-ended')[3]), _endReload]) {
        final before = base64Url.decode(base64Url.normalize(token.replaceAll('%3D', '=')));
        final rewritten = YouTubeDanmakuProtocol.allChatContinuation(token)!;
        final after = base64Url.decode(base64Url.normalize(rewritten.replaceAll('%3D', '=')));
        expect(after, hasLength(before.length));
        final changed = [
          for (var i = 0; i < before.length; i++)
            if (before[i] != after[i]) (i, before[i], after[i]),
        ];
        expect(changed, hasLength(1));
        expect([changed.single.$2, changed.single.$3, before[changed.single.$1 - 1]], [4, 1, 0x08]);
        expect(rewritten.endsWith('%3D') == token.endsWith('%3D'), isTrue);
      }
    });

    test('what cannot be rewritten gives null', () {
      List<int> view(void Function(ProtoWriter writer) fields) => (ProtoWriter()..also(fields)).toBytes();
      List<int> chat(List<int> view, {List<int> extra = const []}) => [
        ...(ProtoWriter()
              ..bytes(3, utf8.encode('header'))
              ..integer(6, 1)
              ..bytes(16, view))
            .toBytes(),
        ...extra,
      ];
      String wrap(List<int> chat, {int field = 119693434}) => _encode((ProtoWriter()..bytes(field, chat)).toBytes());
      final top = view(
        (writer) => writer
          ..integer(1, 4)
          ..integer(3, 2),
      );
      final live = view(
        (writer) => writer
          ..integer(1, 1)
          ..integer(3, 2),
      );
      // Built the same way, the rewrite is exact.
      expect(YouTubeDanmakuProtocol.allChatContinuation(wrap(chat(top))), wrap(chat(live)));
      expect(YouTubeDanmakuProtocol.allChatContinuation(wrap(chat(live))), wrap(chat(live)));
      // A fixed32 field (tag 7, wire type 5): not copied.
      const fixed32 = [0x3D, 1, 2, 3, 4];
      final cases = {
        'another view': wrap(chat(view((writer) => writer.integer(1, 2)))),
        'no view': wrap(chat(view((writer) => writer.integer(3, 2)))),
        'no field 16': wrap((ProtoWriter()..integer(6, 1)).toBytes()),
        'field 16 twice': wrap(chat(top, extra: (ProtoWriter()..bytes(16, top)).toBytes())),
        'the view twice': wrap(
          chat(
            view(
              (writer) => writer
                ..integer(1, 4)
                ..integer(1, 4),
            ),
          ),
        ),
        'the view not a varint': wrap(chat(view((writer) => writer.bytes(1, [4])))),
        'field 16 not a message': wrap([...(ProtoWriter()..integer(16, 4)).toBytes()]),
        'a fixed32 field beside field 16': wrap(chat(top, extra: fixed32)),
        'a fixed32 field in field 16': wrap(chat([...top, ...fixed32])),
        'the wrapper twice': _encode([
          ...(ProtoWriter()..bytes(119693434, chat(top))).toBytes(),
          ...(ProtoWriter()..bytes(119693434, chat(top))).toBytes(),
        ]),
        "a replay's continuation (S08)": _asked(_frames('S08-ended')[1]),
        'a scrubbed continuation (S07)': YouTubeDanmakuProtocol.watch(_answer(_frames('S07-live-paid').first))
            .continuation!,
        'truncated': s06Next.substring(0, s06Next.length - 12),
        'empty': '',
        'not base64': 'not a continuation!',
        'another percent escape': s06Next.replaceFirst('%3D', '%2F'),
      };
      for (final MapEntry(key: name, value: token) in cases.entries) {
        expect(YouTubeDanmakuProtocol.allChatContinuation(token), isNull, reason: name);
      }
    });

    test('S10 with the setting on: the first poll in the Live chat view, then the continuations answered', () async {
      final requests = <LiveRequest>[];
      final ours = await _session(
        'lNPh7CdwkWk',
        [
          for (final frame in s10)
            if (!_isMetadata(frame)) _step(frame),
        ],
        allChat: true,
        requests: requests,
      );
      // The same requests as recorded.
      expect(
        [for (final request in requests.skip(1)) _body(request)['continuation']],
        [
          for (final frame in s10.skip(1))
            if (!_isMetadata(frame)) _asked(frame),
          YouTubeDanmakuProtocol.chat(_answer(s10.last)).continuation,
        ],
      );
      int count(String event, [String? type]) =>
          ours.where((entry) => entry['event'] == event && (type == null || entry['type'] == type)).length;
      expect([count('ready'), count('viewers'), count('reconnecting'), count('closed')], [1, 1, 0, 0]);
      // The first answer (history) is not reported, but for the 50 Super
      // Chats its ticker still pins (B-22; was 4 super chats).
      expect(
        [count('chat', 'chat'), count('chat', 'superChat'), count('notice'), count('retraction')],
        [303 + 80 + 84 + 166, 4 + 50, 2, 0],
      );
    });

    test('off by default: the continuation of next as it came', () async {
      final requests = <LiveRequest>[];
      final http = _ScriptedHttp([_step(s10[0]), _step(s10[1])]);
      final connection = YouTubeDanmakuConnection(http: http);
      await connection.connect(const YouTubeDanmakuArgs(roomId: 'UChAnqc_AY5_I3Px5dig3X1Q', videoId: 'lNPh7CdwkWk'));
      await connection.close();
      requests.addAll(http.requests);
      expect(_body(requests[1])['continuation'], s10Next);
    });

    test('allChatOf is read at every start (C01.6)', () async {
      var allChat = false;
      final http = _ScriptedHttp([_step(s10[0]), _step(s10[1]), _step(s10[0]), _step(s10[1])]);
      final connection = YouTubeDanmakuConnection(http: http, allChatOf: () => allChat);
      const args = YouTubeDanmakuArgs(roomId: 'UChAnqc_AY5_I3Px5dig3X1Q', videoId: 'lNPh7CdwkWk');
      await connection.connect(args);
      await connection.close();
      allChat = true;
      await connection.connect(args);
      await connection.close();
      final requests = http.requests;
      expect(requests, hasLength(4));
      expect(_body(requests[1])['continuation'], s10Next);
      expect(_body(requests[3])['continuation'], YouTubeDanmakuProtocol.allChatContinuation(s10Next));
    });

    final top = s06Next;
    final live = YouTubeDanmakuProtocol.allChatContinuation(s06Next)!;
    Map<String, Object?> poll(String token) => {'request': 'live_chat/get_live_chat', 'continuation': token};
    const next = {'request': 'next', 'videoId': 'xd_fJRWZuVI'};
    const ready = {'event': 'ready'};
    const failed = {'event': 'closed', 'reason': 'connectionFailed'};
    List<Object?> brief(List<Map<String, Object?>> trace) => [
      for (final entry in trace)
        if (entry['event'] == 'chat') entry['text'] else entry,
    ];

    test('refused (400): asked again at once as it came, not a failure; Top chat from then on', () async {
      final statuses = <DanmakuStatus>[];
      final ours = await _session(
        'xd_fJRWZuVI',
        [
          {'answer': _watchAnswer(token: top)},
          {'status': 400},
          {
            'answer': _chatAnswer(['history'], token: 'T-1'),
          },
          {
            'answer': _chatAnswer(['shown'], token: top, kind: 'reloadContinuationData'),
          },
          {
            'answer': _chatAnswer(['history again'], token: 'T-2'),
          },
          {
            'answer': _chatAnswer(['after'], token: null),
          },
        ],
        allChat: true,
        statuses: statuses,
      );
      expect(brief(ours), [
        next,
        poll(live),
        poll(top),
        ready,
        {'wait': 5000},
        poll('T-1'),
        'shown',
        {'wait': 5000},
        poll(top),
        {'wait': 5000},
        poll('T-2'),
        'after',
        failed,
      ]);
      expect(statuses.contains(DanmakuStatus.reconnecting), isFalse);
    });

    test('an answer without a chat in the Live chat view: asked again as it came', () async {
      final ours = await _session('xd_fJRWZuVI', [
        {'answer': _watchAnswer(token: top)},
        {'answer': _ended},
        {
          'answer': _chatAnswer(['history'], token: 'T-1'),
        },
        {
          'answer': _chatAnswer(['after'], token: null),
        },
      ], allChat: true);
      expect(brief(ours), [
        next,
        poll(live),
        poll(top),
        ready,
        {'wait': 5000},
        poll('T-1'),
        'after',
        failed,
      ]);
      // Both views ended: the chat is over.
      final details = <String>[];
      final over = await _session(
        'xd_fJRWZuVI',
        [
          {'answer': _watchAnswer(token: top)},
          {'answer': _ended},
          {'answer': _ended},
        ],
        allChat: true,
        details: details,
      );
      expect(brief(over), [next, poll(live), poll(top), failed]);
      expect(details, ['Chat ended: Chat is disabled for this live stream.']);
    });

    test('a 5xx or a broken answer is a failure (2 s, still the Live chat view); a refusal is not', () async {
      final ours = await _session('xd_fJRWZuVI', [
        {'answer': _watchAnswer(token: top)},
        {'status': 503},
        {'raw': '<html>not json</html>'},
        {'status': 400},
        {
          'answer': _chatAnswer(['history'], token: 'T-1'),
        },
        {
          'answer': _chatAnswer(['after'], token: null),
        },
      ], allChat: true);
      expect(brief(ours), [
        next,
        poll(live),
        {'wait': 2000},
        poll(live),
        {'wait': 2000},
        poll(live),
        poll(top),
        ready,
        {'wait': 5000},
        poll('T-1'),
        'after',
        failed,
      ]);
      final details = <String>[];
      final exhausted = await _session(
        'xd_fJRWZuVI',
        [
          {'answer': _watchAnswer(token: top)},
          {'status': 503},
          {'status': 503},
          {'status': 503},
        ],
        allChat: true,
        details: details,
      );
      expect(brief(exhausted), [
        next,
        poll(live),
        {'wait': 2000},
        poll(live),
        {'wait': 2000},
        poll(live),
        failed,
      ]);
      expect(details, ['HttpStatusFailure(youtube, 503)']);
    });

    test('a continuation that cannot be rewritten is asked for as it came, once', () async {
      final ours = await _session('xd_fJRWZuVI', [
        {'answer': _watchAnswer(token: 'SYNTH-reload-0')},
        {
          'answer': _chatAnswer(['history'], token: 'T-1'),
        },
        {
          'answer': _chatAnswer(['after'], token: null),
        },
      ], allChat: true);
      expect(brief(ours), [
        next,
        poll('SYNTH-reload-0'),
        ready,
        {'wait': 5000},
        poll('T-1'),
        'after',
        failed,
      ]);
    });

    test('a reload continuation later is asked for in the Live chat view too; its answer is history', () async {
      final reload = _endReload;
      expect(_view(reload), 4, reason: 'S06-live ended with a Top chat reload continuation');
      final ours = await _session('xd_fJRWZuVI', [
        {'answer': _watchAnswer(token: top)},
        {
          'answer': _chatAnswer(['history'], token: 'T-1'),
        },
        {
          'answer': _chatAnswer(['before'], token: reload, kind: 'reloadContinuationData'),
        },
        {
          'answer': _chatAnswer(['recent, again'], token: 'T-2'),
        },
        {
          'answer': _chatAnswer(['after'], token: null),
        },
      ], allChat: true);
      expect(brief(ours), [
        next,
        poll(live),
        ready,
        {'wait': 5000},
        poll('T-1'),
        'before',
        {'wait': 5000},
        poll(YouTubeDanmakuProtocol.allChatContinuation(reload)!),
        {'wait': 5000},
        poll('T-2'),
        'after',
        failed,
      ]);
    });

    test('closed while the Live chat view is asked for: a late refusal asks nothing more', () async {
      final http = _ManualHttp();
      final connection = YouTubeDanmakuConnection(http: http, allChat: true);
      final events = _record(connection);
      final connecting = connection.connect(
        const YouTubeDanmakuArgs(roomId: 'UCSF_aFGIIIoWY30GVV19TKA', videoId: 'xd_fJRWZuVI'),
      );
      await _until(() => http.pending.length == 1);
      http.pending[0].answer.complete(_ok(http.pending[0].request, _watchAnswer(token: top)));
      await _until(() => http.pending.length == 2);
      expect(_body(http.pending[1].request)['continuation'], live);
      await connection.close();
      http.pending[1].answer.complete(LiveResponse(status: 400, bytes: const [], url: http.pending[1].request.url));
      await connecting;
      await _wait(const Duration(milliseconds: 20));
      expect(http.pending, hasLength(2));
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a local HTTP server: the Live chat view refused on the wire (400), then Top chat (S10)', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
        bodies.add(body);
        final response = request.response..headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        switch (bodies.length) {
          case 1:
            response.write(s10[0]['text']);
          case 2:
            response
              ..statusCode = 400
              ..write(
                jsonEncode({
                  'error': {
                    'code': 400,
                    'message': 'Request contains an invalid argument.',
                    'status': 'INVALID_ARGUMENT',
                  },
                }),
              );
          case 3:
            response.write(s10[1]['text']);
          case 4:
            response.write(s10[3]['text']);
          default:
            // Never answers; the connection is closed meanwhile.
            return;
        }
        await response.close();
      });
      final http = _Rerouted(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = YouTubeDanmakuConnection(http: http, allChat: true, now: () => _recordedAt);
      final events = _record(connection);
      await runZoned(
        () async {
          await connection.connect(
            const YouTubeDanmakuArgs(roomId: 'UChAnqc_AY5_I3Px5dig3X1Q', videoId: 'lNPh7CdwkWk'),
          );
          await _until(() => bodies.length == 5);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) => parent.createTimer(
            zone,
            duration >= const Duration(seconds: 1) && duration <= const Duration(seconds: 5) ? Duration.zero : duration,
            callback,
          ),
        ),
      );
      await connection.close();
      expect(
        [for (final body in bodies) body['videoId'] ?? body['continuation']],
        [
          'lNPh7CdwkWk',
          _asked(s10[1]),
          s10Next,
          YouTubeDanmakuProtocol.chat(_answer(s10[1])).continuation,
          YouTubeDanmakuProtocol.chat(_answer(s10[3])).continuation,
        ],
      );
      final lines = YouTubeDanmakuProtocol.chat(_answer(s10[3]), now: _recordedAt).messages;
      expect(events.map(_shown).toList(), [
        'DanmakuReady()',
        {'event': 'viewers', 'kind': 'onlineViewers', 'value': 15163},
        // B-22: the Super Chats the first answer's ticker still pins.
        for (final message in YouTubeDanmakuProtocol.chat(_answer(s10[1]), now: _recordedAt).pinned) _project(message),
        for (final line in lines) _project(line),
      ]);
      expect(lines.where((line) => line.type == LiveMessageType.superChat), hasLength(3));
    });
  });

  group('B-22: Super Chats still pinned on joining', () {
    final s10 = _frames('S10-live-all-chat');
    // When the first answer came: the start of the recording and its time.
    final received = DateTime.parse(
      (_json('S10-live-all-chat/meta.json')! as Map<String, Object?>)['capturedAt']! as String,
    ).add(Duration(milliseconds: s10[1]['t']! as int));

    test("S10: the first answer's ticker pins 50 Super Chats: replayed, oldest first, ending when the ticker does", () {
      final answer = _answer(s10[1]);
      final poll = YouTubeDanmakuProtocol.chat(answer, now: received);
      final tickers = <String, Map<String, Object?>>{
        for (final action in _actions(answer))
          if (action case {
            'addLiveChatTickerItemAction': {
              'item': {'liveChatTickerPaidMessageItemRenderer': final Map<String, Object?> item},
            },
          })
            item['id']! as String: item,
      };
      expect([tickers.length, poll.pinned.length], [50, 50]);
      expect({for (final message in poll.pinned) message.messageId}, tickers.keys.toSet());
      final lags = <int>[];
      for (final (index, message) in poll.pinned.indexed) {
        final data = message.data! as LiveSuperChatMessage;
        final ticker = tickers[message.messageId]!;
        expect([message.type, message.replayed, message.sentAt], [LiveMessageType.superChat, true, data.startTime]);
        // The page counts durationSec down from when the answer comes.
        final left = Duration(seconds: ticker['durationSec']! as int);
        expect(data.endTime, received.add(left));
        // durationSec is the time left when the server answered:
        // fullDurationSec less the time since the Super Chat was sent, a few
        // seconds less still (the answer took them).
        final full = Duration(seconds: ticker['fullDurationSec']! as int);
        lags.add((full - received.difference(data.startTime) - left).inMilliseconds);
        if (index > 0) {
          final before = poll.pinned[index - 1].data! as LiveSuperChatMessage;
          expect(before.startTime.isAfter(data.startTime), isFalse, reason: 'oldest first');
        }
      }
      expect(lags.every((lag) => lag >= 4000 && lag <= 7000), isTrue, reason: '$lags');
      String brief(LiveMessage message) =>
          '${(message.data! as LiveSuperChatMessage).priceText} ${message.userName} ${message.sentAt!.microsecondsSinceEpoch}';
      expect(brief(poll.pinned.first), '¥5,630 @bqd09s0 1790780442679248');
      expect(brief(poll.pinned.last), '¥500 @9gv95q4s 1790781209749568');
      // The dearest: NT$5,633.00, pinned for three hours, 10043 s left.
      final dearest = poll.pinned.singleWhere(
        (message) => message.messageId == 'ChwKGkNLX1Y2WUxKbHBjREZRakl3Z1FkSjlnaE1n',
      );
      expect(_superChat(dearest)..remove('seconds'), {
        'id': 'ChwKGkNLX1Y2WUxKbHBjREZRakl3Z1FkSjlnaE1n',
        'userName': '@7l4x53pi',
        'userId': 'UCcX9fFIssJoxHJaO5W_Uhqy',
        'face': '',
        'message': startsWith('ころさんお誕生日おめでとう～～～！'),
        'price': 0,
        'priceText': r'NT$5,633.00',
        'startMicros': 1790780459957613,
        'colors': ['#d00000', '#e62117'],
      });
      expect((dearest.data! as LiveSuperChatMessage).endTime, received.add(const Duration(seconds: 10043)));
    });

    test('S10: the history holds 7 of them as messages; the pinned ones are the same but for their end', () {
      final poll = YouTubeDanmakuProtocol.chat(_answer(s10[1]), now: received);
      final history = [
        for (final message in poll.messages)
          if (message.type == LiveMessageType.superChat) message,
      ];
      expect(history, hasLength(7));
      for (final message in history) {
        final pinned = poll.pinned.singleWhere((other) => other.messageId == message.messageId);
        expect(message.replayed, isFalse);
        expect(_superChat(pinned)..remove('seconds'), _superChat(message)..remove('seconds'));
        expect(_project(pinned), {..._project(message), 'replayed': true});
        expect(pinned.data, message.data, reason: 'a super chat is the same one by its id');
      }
      // The duplicate gate: every pinned one passes (the oldest was sent
      // 13 minutes before, but is still on display); the same ones again,
      // as the history or live, do not.
      final gate = DanmakuMessageGate();
      expect([for (final message in poll.pinned) gate.accepts(message, now: received)], everyElement(isTrue));
      expect([for (final message in history) gate.accepts(message, now: received)], everyElement(isFalse));
      // The Top chat recording kept no ticker items (scrubbed to {}).
      expect(YouTubeDanmakuProtocol.chat(_answer(_frames('S07-live-paid')[1])).pinned, isEmpty);
    });

    test('which ticker items count: time left a whole number above zero, a paid message inside; one per id', () {
      final received = DateTime.utc(2026, 9, 30, 15, 13, 30);
      Map<String, Object?> renderer(
        int n, {
        Object? time = 'default',
        String? id,
        Object? amount = r'$5.00',
        String? text = 'thanks',
      }) {
        final item =
            (_paid(n, time: time, amount: amount, text: text)['addChatItemAction']! as Map<String, Object?>)['item']!
                as Map<String, Object?>;
        final paid = {...item['liveChatPaidMessageRenderer']! as Map<String, Object?>};
        if (id != null) paid['id'] = id;
        return {'liveChatPaidMessageRenderer': paid};
      }

      Map<String, Object?> ticker(
        String id,
        Object? left, {
        Map<String, Object?>? inside,
        String kind = 'liveChatTickerPaidMessageItemRenderer',
        bool endpoint = true,
      }) => {
        'addLiveChatTickerItemAction': {
          'item': {
            kind: {
              'id': id,
              'durationSec': ?left,
              'fullDurationSec': 3600,
              if (endpoint)
                'showItemEndpoint': {
                  'showLiveChatItemEndpoint': {'renderer': inside},
                },
            },
          },
          'durationSec': '$left',
        },
      };

      final poll = YouTubeDanmakuProtocol.chat(
        _chatAnswer([
          ticker('P1', 600, inside: renderer(1)),
          ticker('P2', 0, inside: renderer(2)),
          ticker('P3', -5, inside: renderer(3)),
          ticker('P4', '300', inside: renderer(4)),
          ticker('P5', null, inside: renderer(5)),
          ticker('P6', 60, endpoint: false),
          ticker('P7', 60, inside: renderer(7), kind: 'liveChatTickerPaidStickerItemRenderer'),
          ticker(
            'M8',
            60,
            inside: {
              'liveChatMembershipItemRenderer': {
                'id': 'M8',
                'headerSubtext': {'simpleText': 'Welcome!'},
              },
            },
          ),
          ticker('P9', 60, inside: renderer(9, amount: null, text: null)),
          ticker('P1', 500, inside: renderer(1)),
          ticker(
            'E1',
            30,
            inside: renderer(10, id: '', time: '1790781150000000'),
          ),
          ticker(
            'E2',
            40,
            inside: renderer(11, id: '', time: '1790781150000000'),
          ),
          ticker('P12', 120, inside: renderer(12, time: null)),
          ticker('P13', 60, inside: renderer(13, time: '1790781100000000')),
          ticker('P14', 60, inside: {'liveChatPaidMessageRenderer': 'not a map'}),
        ]),
        now: received,
      );
      expect(poll.messages, isEmpty, reason: 'ticker items are not messages');
      expect(
        [
          for (final message in poll.pinned)
            (
              message.messageId,
              message.userName,
              message.sentAt?.microsecondsSinceEpoch,
              (message.data! as LiveSuperChatMessage).endTime.difference(received).inSeconds,
              message.replayed,
            ),
        ],
        [
          ('P13', '@payer13', 1790781100000000, 60, true),
          // No id: nothing to tell them apart by; the same time keeps their order.
          ('', '@payer10', 1790781150000000, 30, true),
          ('', '@payer11', 1790781150000000, 40, true),
          // P1 once, with the first item's time left.
          ('P1', '@payer1', 1790781200000001, 600, true),
          // No time of its own: it starts when the answer came.
          ('P12', '@payer12', null, 120, true),
        ],
      );
      expect((poll.pinned.last.data! as LiveSuperChatMessage).startTime, received);
      // The ticker's time left is not the message's display time: a Super
      // Chat of the same answer is shown for fullDurationSec as before.
      final live = YouTubeDanmakuProtocol.chat(
        _chatAnswer([_paid(1), ticker('P1', 600, inside: renderer(1))]),
        now: received,
      ).messages.single;
      expect([live.replayed, _superChat(live)['seconds']], [false, 3600]);
    });

    test('the connection reports them once joined, after the viewers; later answers and reloads do not', () async {
      Map<String, Object?> pin(int n, int left) => {
        'addLiveChatTickerItemAction': {
          'item': {
            'liveChatTickerPaidMessageItemRenderer': {
              'id': 'P$n',
              'durationSec': left,
              'fullDurationSec': left,
              'showItemEndpoint': {
                'showLiveChatItemEndpoint': {
                  'renderer': (_paid(n)['addChatItemAction']! as Map<String, Object?>)['item'],
                },
              },
            },
          },
        },
      };
      final trace = await _session('Synth3tic_0', [
        {'answer': _watchAnswer(viewers: 1234)},
        // The history: its lines and Super Chats are not reported; the two it
        // pins are, oldest first.
        {
          'answer': _chatAnswer(['history', _paid(2), pin(2, 60), pin(1, 600)], token: 'T-1'),
        },
        // A new Super Chat and its ticker item: the Super Chat once, live.
        {
          'answer': _chatAnswer([_paid(3), pin(3, 120), 'live'], token: 'T-2', kind: 'reloadContinuationData'),
        },
        // History again after a reload: nothing, the pinned one neither.
        {
          'answer': _chatAnswer(['again', pin(4, 60)], token: 'T-3'),
        },
        {
          'answer': _chatAnswer(['last'], token: null),
        },
      ]);
      expect(
        [
          for (final entry in trace)
            if (entry['event'] == 'chat')
              '${entry['type']} ${entry['id']}${entry['replayed'] == true ? ' replayed' : ''}'
            else if (entry['event'] case final String event)
              event
            else if (entry['request'] case final String request)
              '$request ${entry['continuation'] ?? entry['videoId']}'
            else
              'wait ${entry['wait']}',
        ],
        [
          'next Synth3tic_0',
          'live_chat/get_live_chat T-reload',
          'ready',
          'viewers',
          'superChat P1 replayed',
          'superChat P2 replayed',
          'wait 5000',
          'live_chat/get_live_chat T-1',
          'superChat P3',
          'chat id-live',
          'wait 5000',
          'live_chat/get_live_chat T-2',
          'wait 5000',
          'live_chat/get_live_chat T-3',
          'chat id-last',
          'closed',
        ],
      );
    });

    test('S10 through the connection: the 50 pinned Super Chats pass the message filter and the gate', () async {
      final events = <LiveMessage>[];
      final http = _ScriptedHttp([_step(s10[0]), _step(s10[1])]);
      final connection = YouTubeDanmakuConnection(http: http, now: () => received);
      connection.events.listen((event) {
        if (event case DanmakuReceived(:final message)) events.add(message);
      });
      await connection.connect(const YouTubeDanmakuArgs(roomId: 'UChAnqc_AY5_I3Px5dig3X1Q', videoId: 'lNPh7CdwkWk'));
      await connection.close();
      expect(events.first.type, LiveMessageType.online);
      final pinned = events.skip(1).toList();
      expect(pinned, hasLength(50));
      expect(pinned.every((message) => message.type == LiveMessageType.superChat && message.replayed), isTrue);
      final filter = DanmakuMessageFilter(clock: () => received);
      expect(pinned.every(filter.accepts), isTrue);
      final gate = DanmakuMessageGate();
      expect(pinned.every((message) => gate.accepts(message, now: received)), isTrue);
    });
  });

  group('B-23: gifts', () {
    final s12 = _frames('S12-gifts').single;

    test('S12: the three gifts of the recording, field by field', () {
      final poll = YouTubeDanmakuProtocol.chat(_answer(s12), now: _recordedAt);
      expect(poll.messages, hasLength(3));
      expect(poll.pinned, isEmpty);
      expect(
        [
          for (final message in poll.messages)
            [
              message.type,
              message.userName,
              message.userId,
              message.message,
              message.messageId,
              message.sentAt,
              message.color,
              message.replayed,
              message.data,
            ],
        ],
        [
          for (final (id, name, gift, file) in [
            ('ChwKGkNKR0sydXUtbHBjREZYb1UxZ0FkUHRBUlJ3', '@b2tm11fb1ixskbc', 'Donut', 'donut'),
            ('ChwKGkNNaW1oS1NfbHBjREZaYVN3Z0VkRkhzRXpn', '@rmkwwr2ljd', 'Ramen', 'ramen_jp'),
            ('ChwKGkNMR29sNHZEbHBjREZiNHoxZ0FkYTJvOFZB', '@sddw613ul0fh', 'Heart', 'heart'),
          ])
            [
              LiveMessageType.gift,
              name,
              '',
              'sent $gift',
              id,
              null,
              LiveMessageColor.white,
              false,
              YouTubeGift(
                name: gift,
                text: 'sent $gift',
                image: Uri.parse('https://www.gstatic.com/youtube/img/pdg/gift/assets/$file.png=w640-h640'),
              ),
            ],
        ],
      );
      final gift = poll.messages.first.data! as YouTubeGift;
      expect('$gift', 'YouTubeGift(sent Donut)');
      expect(gift.hashCode, poll.messages.first.data.hashCode);
    });

    test('fields: the text, the name, the image; channel id and time when present; items without text', () {
      Map<String, Object?> gift(Map<String, Object?> fields) => {
        'addChatItemAction': {
          'item': {'giftMessageViewModel': fields},
        },
      };
      Map<String, Object?> sources(List<String> urls) => {
        'sources': [
          for (final url in urls) {'url': url, 'width': 480, 'height': 480},
        ],
      };
      final messages = YouTubeDanmakuProtocol.chat(
        _chatAnswer([
          gift({
            'id': 'G1',
            'text': {'content': '  sent Cake  '},
            'authorName': {'content': ' @giver '},
            'authorExternalChannelId': 'UCsyntheticGiver00000001',
            'timestampUsec': '1790781300000000',
            'giftImage': sources(['https://www.gstatic.com/a.png=w480', 'https://www.gstatic.com/a.png=w640']),
          }),
          gift({
            'id': 'G2',
            'text': {'content': 'a gift in another wording'},
            'giftImage': sources(['http://insecure.example/a.png']),
          }),
          gift({
            'text': {'content': 'sent '},
            'giftImage': 'not a map',
          }),
          gift({
            'id': 'G4',
            'text': {'content': 'sent Tea'},
            'authorName': 'not a map',
            'authorExternalChannelId': 7,
            'timestampUsec': '-1',
            'giftImage': sources([]),
          }),
          gift({
            'id': 'X1',
            'text': {'content': '   '},
          }),
          gift({'id': 'X2', 'text': 'sent Donut'}),
          gift({'id': 'X3'}),
          gift({
            'id': 'X4',
            'text': {'content': 7},
          }),
        ]),
      ).messages;
      expect(
        [
          for (final message in messages)
            (
              message.messageId,
              message.userName,
              message.userId,
              message.message,
              message.sentAt?.microsecondsSinceEpoch,
              message.data,
            ),
        ],
        [
          (
            'G1',
            '@giver',
            'UCsyntheticGiver00000001',
            'sent Cake',
            1790781300000000,
            YouTubeGift(name: 'Cake', text: 'sent Cake', image: Uri.parse('https://www.gstatic.com/a.png=w640')),
          ),
          (
            'G2',
            '',
            '',
            'a gift in another wording',
            null,
            const YouTubeGift(name: '', text: 'a gift in another wording'),
          ),
          ('', '', '', 'sent', null, const YouTubeGift(name: '', text: 'sent')),
          ('G4', '', '', 'sent Tea', null, const YouTubeGift(name: 'Tea', text: 'sent Tea')),
        ],
      );
      expect(messages.every((message) => message.type == LiveMessageType.gift), isTrue);
      expect(const YouTubeGift(name: 'a', text: 'b'), isNot(const YouTubeGift(name: 'a', text: 'c')));
    });

    test('through the connection: a gift in a later answer is a gift; in the first answer it is history', () async {
      final filter = DanmakuMessageFilter(clock: () => _recordedAt);
      final trace = await _session('aGHE6jSxncw', [
        {'answer': _watchAnswer()},
        _step(s12),
        {'answer': _chatAnswer(_actions(_answer(s12)).cast<Object>(), token: null)},
      ]);
      expect(
        [
          for (final entry in trace)
            if (entry['event'] == 'chat') '${entry['type']} ${entry['userName']} ${entry['text']}',
        ],
        ['gift @b2tm11fb1ixskbc sent Donut', 'gift @rmkwwr2ljd sent Ramen', 'gift @sddw613ul0fh sent Heart'],
      );
      // Gifts pass the message filter (it filters chat only); the gate
      // tells a gift sent again by its id.
      final gifts = YouTubeDanmakuProtocol.chat(_answer(s12)).messages;
      expect(gifts.every(filter.accepts), isTrue);
      final gate = DanmakuMessageGate();
      expect(
        [
          for (final gift in [...gifts, ...gifts]) gate.accepts(gift, now: _recordedAt),
        ],
        [true, true, true, false, false, false],
      );
    });
  });

  group('connection', () {
    test('no heartbeat; registers in DanmakuRegistry under youtube', () {
      final connection = YouTubeDanmakuConnection(http: _ScriptedHttp(const []))..heartbeat();
      expect(connection.heartbeatInterval, Duration.zero);
      final registry = DanmakuRegistry({
        SiteIds.youtube: () => YouTubeDanmakuConnection(http: _ScriptedHttp(const [])),
      });
      expect(registry.platforms, [SiteIds.youtube]);
      expect(registry.connectionFor(' YouTube '), isA<YouTubeDanmakuConnection>());
      expect(registry.connectionFor('twitch'), isA<EmptyDanmakuConnection>());
    });

    test('takes YouTubeDanmakuArgs only; a video id with spaces is trimmed', () async {
      final connection = YouTubeDanmakuConnection(http: _ScriptedHttp(const []));
      expect(() => connection.connect('e3n116VqcrE'), throwsArgumentError);
      final requests = <LiveRequest>[];
      await _session(' e3n116VqcrE ', [
        {'answer': _watchAnswer()},
      ], requests: requests);
      expect(_body(requests.first)['videoId'], 'e3n116VqcrE');
    });

    test("the requests: POST, the adapter's headers and JSON body, youtube's route, 15 s", () async {
      final requests = <LiveRequest>[];
      await _session('e3n116VqcrE', [
        {'answer': _watchAnswer()},
        {'answer': _chatAnswer(const [])},
      ], requests: requests);
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.site, 'youtube');
        expect(request.timeout, const Duration(seconds: 15));
        expect(request.cancel, isNotNull);
        expect(request.headers, {...YouTubeApi.apiHeaders, 'content-type': 'application/json; charset=utf-8'});
        expect(_body(request)['context'], YouTubeApi.webContext);
      }
      expect('${requests[0].url}', 'https://www.youtube.com/youtubei/v1/next?prettyPrint=false');
      expect(_body(requests[0]).keys, ['context', 'videoId']);
      expect('${requests[1].url}', 'https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?prettyPrint=false');
      expect(_body(requests[1]), {'context': YouTubeApi.webContext, 'continuation': 'T-reload'});
      expect(_body(requests[2])['continuation'], 'T-next');
    });

    test('connect completes once joined; status and events follow the chat', () async {
      final http = _ManualHttp();
      final connection = YouTubeDanmakuConnection(http: http);
      final events = _record(connection);
      var connected = false;
      unawaited(connection.connect(_args).then((_) => connected = true));
      await _until(() => http.pending.length == 1);
      expect(connection.status, DanmakuStatus.connecting);
      http.pending[0].answer.complete(_ok(http.pending[0].request, _watchAnswer(viewers: 900)));
      await _until(() => http.pending.length == 2);
      expect(connected, isFalse);
      http.pending[1].answer.complete(_ok(http.pending[1].request, _chatAnswer(['history'], timeoutMs: 1000)));
      await _until(() => connected);
      expect(connection.status, DanmakuStatus.connected);
      expect(connection.isConnected, isTrue);
      expect(events.map(_shown).toList(), [
        'DanmakuReady()',
        {'event': 'viewers', 'kind': 'onlineViewers', 'value': 900},
      ]);
      await _until(() => http.pending.length == 3);
      http.pending[2].answer.complete(_ok(http.pending[2].request, _chatAnswer(['new line'])));
      await _until(() => events.length == 3);
      expect((events.last as DanmakuReceived).message.message, 'new line');
      await connection.close();
      expect(connection.status, DanmakuStatus.idle);
    });

    test('close during the first request cancels it; connect completes; nothing follows', () async {
      final http = _ScriptedHttp(const []);
      final connection = YouTubeDanmakuConnection(http: http);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await _until(() => http.requests.length == 1);
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await _wait(const Duration(milliseconds: 20));
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('close while waiting for the next poll: no request, event or timer follows', () async {
      final http = _ScriptedHttp([
        {'answer': _watchAnswer()},
        {'answer': _chatAnswer(const [])},
        {
          'answer': _chatAnswer(['too late']),
        },
      ]);
      final connection = YouTubeDanmakuConnection(http: http);
      final events = _record(connection);
      final timers = <Timer>[];
      await runZoned(
        () => connection.connect(_args),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      await _until(() => timers.isNotEmpty);
      expect(http.requests, hasLength(2));
      await connection.close();
      await _wait(const Duration(milliseconds: 20));
      expect(timers.every((timer) => !timer.isActive), isTrue);
      expect(http.requests, hasLength(2));
      expect(http.metadataRequests, isEmpty);
      expect(events, [const DanmakuReady()]);
    });

    test("connecting to another broadcast: the first one's late answer is dropped", () async {
      final http = _ManualHttp();
      final connection = YouTubeDanmakuConnection(http: http);
      final events = _record(connection);
      unawaited(connection.connect(_args));
      await _until(() => http.pending.length == 1);
      final second = connection.connect(
        const YouTubeDanmakuArgs(roomId: 'UCsyntheticChannel000001', videoId: 'Synth3tic_0'),
      );
      await _until(() => http.pending.length == 2);
      expect(_body(http.pending[1].request)['videoId'], 'Synth3tic_0');
      expect(http.pending[0].request.cancel!.isCancelled, isTrue);
      http.pending[0].answer.complete(_ok(http.pending[0].request, _watchAnswer(token: 'first-room')));
      await _wait(const Duration(milliseconds: 20));
      expect(http.pending, hasLength(2), reason: "the first broadcast's answer asks nothing more");
      http.pending[1].answer.complete(_ok(http.pending[1].request, _watchAnswer(token: 'second-room')));
      await _until(() => http.pending.length == 3);
      expect(_body(http.pending[2].request)['continuation'], 'second-room');
      http.pending[2].answer.complete(_ok(http.pending[2].request, _chatAnswer(const [])));
      await second;
      expect(events, [const DanmakuReady()]);
      await connection.close();
    });

    test('a local HTTP server: the requests on the wire, the recorded answers (S07), a 503 on the way', () async {
      final frames = _frames('S07-live-paid');
      final bodies = <Map<String, Object?>>[];
      final seen = <HttpHeaders>[];
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        // Read the body before counting the request: the test closes the
        // connection once it sees the fifth, and a body still in flight
        // then would be cut off.
        final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
        seen.add(request.headers);
        paths.add('${request.method} ${request.uri}');
        bodies.add(body);
        final response = request.response..headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        switch (paths.length) {
          case 1:
            response.write(frames[0]['text']);
          case 2:
            response.write(frames[1]['text']);
          case 3:
            response.statusCode = 503;
          case 4:
            response.write(frames[2]['text']);
          default:
            // Never answers; the connection is closed meanwhile.
            return;
        }
        await response.close();
      });
      final http = _Rerouted(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = YouTubeDanmakuConnection(http: http);
      final events = _record(connection);
      await runZoned(
        () async {
          await connection.connect(_args);
          await _until(() => paths.length == 5);
        },
        zoneSpecification: ZoneSpecification(
          // Only the waits between polls (1–5 s) fire at once, not the
          // client's timeouts.
          createTimer: (self, parent, zone, duration, callback) => parent.createTimer(
            zone,
            duration >= const Duration(seconds: 1) && duration <= const Duration(seconds: 5) ? Duration.zero : duration,
            callback,
          ),
        ),
      );
      await connection.close();
      expect(paths, [
        'POST /youtubei/v1/next?prettyPrint=false',
        for (var i = 0; i < 4; i++) 'POST /youtubei/v1/live_chat/get_live_chat?prettyPrint=false',
      ]);
      expect(bodies[0], {'context': YouTubeApi.webContext, 'videoId': 'e3n116VqcrE'});
      expect(
        [for (final body in bodies.skip(1)) body['continuation']],
        [
          (frames[1]['request']! as Map)['continuation'],
          (frames[2]['request']! as Map)['continuation'],
          (frames[2]['request']! as Map)['continuation'],
          (frames[3]['request']! as Map)['continuation'],
        ],
      );
      for (final headers in seen) {
        expect(headers.value('user-agent'), YouTubeApi.userAgent);
        expect(headers.value('cookie'), 'SOCS=CAI');
        expect(headers.value('origin'), 'https://www.youtube.com');
        expect(headers.value('accept-language'), 'en-US,en;q=0.9');
        expect(headers.contentType?.mimeType, 'application/json');
      }
      final lines = YouTubeDanmakuProtocol.chat(_answer(frames[2])).messages;
      expect(events.map(_shown).toList(), [
        'DanmakuReady()',
        {'event': 'viewers', 'kind': 'onlineViewers', 'value': 49142},
        'DanmakuReconnecting(disconnected: HttpStatusFailure(youtube, 503))',
        'DanmakuReady()',
        for (final line in lines) _project(line),
      ]);
    });
  });
}

extension on ProtoWriter {
  /// Runs [fields] on this writer.
  void also(void Function(ProtoWriter writer) fields) => fields(this);
}

/// Sends the requests to a local server, path and query kept.
final class _Rerouted implements LiveHttp {
  new(this._inner, this._port);

  final LiveHttp _inner;
  final int _port;

  @override
  Future<LiveResponse> send(LiveRequest request) => _inner.send(
    LiveRequest(
      site: request.site,
      url: Uri.parse('http://127.0.0.1:$_port${request.url.path}?${request.url.query}'),
      method: request.method,
      headers: request.headers,
      body: request.body,
      timeout: request.timeout,
      cancel: request.cancel,
    ),
  );

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
