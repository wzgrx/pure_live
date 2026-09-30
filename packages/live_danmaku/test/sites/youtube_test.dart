// YouTube danmaku (docs/modules/M5.19-youtube.md): the chat parser and the
// polling connection against the archived v4's output for the recorded
// answers and sessions (S06-live, S07-live-paid, S08-ended) and the synthetic
// answers and sessions (S09-synthetic), written by
// fixtures/youtube/danmaku/v4_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/youtube/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded exchanges of a sample, in order.
List<Map<String, Object?>> _frames(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

bool _isNext(Map<String, Object?> frame) => (frame['url']! as String).contains('/v1/next');

int _status(Map<String, Object?> frame) => frame['status'] as int? ?? 200;

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

/// The action [index] of a `get_live_chat` answer.
Object? _action(String text, int index) =>
    ((((jsonDecode(text) as Map<String, Object?>)['continuationContents']!
                as Map<String, Object?>)['liveChatContinuation']!
            as Map<String, Object?>)['actions']!
        as List<Object?>)[index];

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
    'type': 'chat',
    'id': (v4['id'] as String?)?.replaceFirst('youtube:', '') ?? '',
    'sentAtMicros': micros != null && micros > 0 ? micros : null,
    'userId': renderer['authorExternalChannelId'] is String ? v4['userId'] : '',
    'userName': authorName is Map && authorName['simpleText'] is String ? v4['userName'] : _joinedRuns(authorName),
    'text': newText,
    'color': '#ffffff',
    'extras': const ['', '', '', false],
  };
}

/// A message of the new code in the same shape.
Map<String, Object?> _project(LiveMessage message) {
  if (message.data case LiveAudienceUpdate(:final kind, :final value)) {
    expect(message.type, LiveMessageType.online);
    return {'event': 'viewers', 'kind': kind.name, 'value': value};
  }
  return {
    'event': 'chat',
    'type': message.type.name,
    'id': message.messageId,
    'sentAtMicros': message.sentAt?.microsecondsSinceEpoch,
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'color': '${message.color}',
    'extras': [message.userLevel, message.fansLevel, message.fansName, message.isLocal],
  };
}

/// v4's parse of one answer, in the new model; `throws` when it threw.
Object? _v4Parsed(Map<String, Object?> v4, String text) {
  if (v4['throws'] case final String type) return {'throws': type};
  return {
    'messages': [for (final event in _list(v4['events'])) _fromV4(event, _action(text, event['action']! as int))],
    'continuation': v4['continuation'],
    'timeoutMs': v4['delayMs'],
  };
}

/// The new parse of one answer (decoded as `postJson` decodes it).
Object? _parsed(String text) {
  try {
    final poll = YouTubeDanmakuProtocol.chat(jsonDecode(text));
    return {
      'messages': [for (final message in poll.messages) _project(message)],
      'continuation': poll.continuation,
      'timeoutMs': poll.timeout?.inMilliseconds,
    };
  } on Object catch (error) {
    return {'throws': error.runtimeType.toString()};
  }
}

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

/// Answers each request with the next step ({"answer"}, {"raw"}: 200;
/// {"status"}; {"error"}: no response). Once the steps run out a request
/// waits for its cancellation.
final class _ScriptedHttp implements LiveHttp {
  new(this.steps);

  final List<Map<String, Object?>> steps;
  final List<LiveRequest> requests = [];
  final Completer<void> exhausted = Completer();
  void Function(LiveRequest request)? onRequest;
  var _next = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    onRequest?.call(request);
    if (_next >= steps.length) {
      if (!exhausted.isCompleted) exhausted.complete();
      await request.cancel?.whenCancelled;
      throw TransportFailure(request.site, TransportReason.cancelled);
    }
    final step = steps[_next++];
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
  return {
    'request': request.url.path.endsWith('/next') ? 'next' : 'live_chat/get_live_chat',
    if (body.containsKey('videoId')) 'videoId': body['videoId'],
    if (body.containsKey('continuation')) 'continuation': body['continuation'],
  };
}

/// One session of the new code over [steps]: requests, waits (each timer
/// fired at once), events. It ends when the steps run out, the connection
/// closes or `connect` throws. [details] gets the details of the closing
/// and reconnecting events, [statuses] the status after each event.
Future<List<Map<String, Object?>>> _session(
  String videoId,
  List<Map<String, Object?>> steps, {
  List<String>? details,
  List<DanmakuStatus>? statuses,
  List<LiveRequest>? requests,
}) async {
  final trace = <Map<String, Object?>>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final http = _ScriptedHttp(steps)..onRequest = (request) => trace.add(_requestEntry(request));
  unawaited(http.exhausted.future.then((_) => finish()));
  final connection = YouTubeDanmakuConnection(http: http);
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
        trace.add({'wait': duration.inMilliseconds});
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
  await connection.close();
  await connecting;
  statuses?.add(connection.status);
  await subscription.cancel();
  requests?.addAll(http.requests);
  return trace;
}

List<Map<String, Object?>> _withoutViewers(List<Map<String, Object?>> trace) => [
  for (final entry in trace)
    if (entry['event'] != 'viewers') entry,
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

Map<String, Object?> _chatAnswer(List<String> texts, {String? token = 'T-next', int timeoutMs = 10000}) => {
  'continuationContents': {
    'liveChatContinuation': {
      if (token != null)
        'continuations': [
          {
            'invalidationContinuationData': {'timeoutMs': timeoutMs, 'continuation': token},
          },
        ],
      'actions': [
        for (final (index, text) in texts.indexed)
          {
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
          },
      ],
    },
  },
};

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

    test('next: the continuation, replays, and the live viewers (S06, S07, S08)', () {
      final s06 = YouTubeDanmakuProtocol.watch(jsonDecode(_frames('S06-live').first['text']! as String));
      expect(s06.live, isTrue);
      expect(s06.viewers, isNull, reason: 'the S06 recording kept only the conversation bar');
      final s07 = YouTubeDanmakuProtocol.watch(jsonDecode(_frames('S07-live-paid').first['text']! as String));
      expect([s07.live, s07.replay, s07.viewers], [true, false, 49142]);
      final s08 = _frames('S08-ended');
      final replay = YouTubeDanmakuProtocol.watch(jsonDecode(s08[0]['text']! as String));
      expect([replay.live, replay.replay, replay.viewers], [false, true, null], reason: '"400,387 views" is not live');
      expect(replay.continuation, startsWith('op2w0wRy'));
      final ended = YouTubeDanmakuProtocol.watch(jsonDecode(s08[2]['text']! as String));
      expect([ended.continuation, ended.live, ended.viewers], [null, false, null]);
      expect(() => YouTubeDanmakuProtocol.watch(<Object?>[]), throwsFormatException);
    });

    test('a Super Chat is a chat line with its amount first; every field of a line (S07)', () {
      final frames = _frames('S07-live-paid');
      final poll = YouTubeDanmakuProtocol.chat(jsonDecode(frames[3]['text']! as String));
      final paid = poll.messages.singleWhere((message) => message.message.startsWith('TRY\u00a0550.00 '));
      expect(paid.type, LiveMessageType.chat);
      expect(paid.color, LiveMessageColor.white);
      // The amount is written with a no-break space.
      expect(paid.message, startsWith('TRY\u00a0550.00 Nihat abi bu adamı'));
      expect(paid.messageId, 'ChwKGkNQbWNpY2Vra3BjREZiekdQd1FkcjlBdGln');
      expect(paid.sentAt, DateTime.fromMicrosecondsSinceEpoch(1790633230349018));
      expect(paid.sentAt!.isUtc, isFalse);
      expect(paid.userName, '@LvrbiQzluYwuhvst');
      expect(paid.userId, hasLength(24));
      expect([paid.userLevel, paid.fansLevel, paid.fansName, paid.isLocal, paid.data], ['', '', '', false, null]);
      expect(poll.continuation, isNotNull);
      expect(poll.reload, isFalse);
      expect(poll.timeout, const Duration(seconds: 10));
      final all = [
        for (final frame in frames.skip(1))
          ...YouTubeDanmakuProtocol.chat(jsonDecode(frame['text']! as String)).messages,
      ];
      expect(all.where((message) => RegExp(r'^(TRY|₫)\s?[\d,.]+ ').hasMatch(message.message)), hasLength(6));
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
      final line = YouTubeDanmakuProtocol.chat(jsonDecode(s06[3]['text']! as String)).messages.last;
      expect(line.message, '👴👴👴👴👴');
    });

    test('the end of a chat: a reload without actions, then no continuationContents (S08)', () {
      final frames = _frames('S08-ended');
      final reload = YouTubeDanmakuProtocol.chat(jsonDecode(frames[3]['text']! as String));
      expect([reload.messages, reload.reload, reload.timeout, reload.ended], [isEmpty, true, null, false]);
      final ended = YouTubeDanmakuProtocol.chat(jsonDecode(frames[4]['text']! as String));
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
      test('$name: every answer parses to what v4 parsed (differences 1–4)', () {
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
      expect(ours, _v4Session(_list(_v4('S06-live')['session']), steps));
      expect(ours.where((entry) => entry['event'] == 'chat'), hasLength(21));
      expect(details, ['Chat ended: Chat is disabled for this live stream.']);
    });

    test('S07-live-paid: the same, and the viewers of next after joining (difference 8)', () async {
      final steps = [for (final frame in _frames('S07-live-paid')) _step(frame)];
      final ours = await _session('e3n116VqcrE', steps);
      expect(_withoutViewers(ours), _v4Session(_list(_v4('S07-live-paid')['session']), steps));
      final ready = ours.indexWhere((entry) => entry['event'] == 'ready');
      expect(ours[ready + 1], {'event': 'viewers', 'kind': 'onlineViewers', 'value': 49142});
      expect(ours.where((entry) => entry['event'] == 'chat'), hasLength(203));
      expect(ours.where((entry) => '${entry['text']}'.startsWith('TRY\u00a0')), hasLength(4));
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
        final ours = await _session(videoId, steps);
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
      final lines = YouTubeDanmakuProtocol.chat(jsonDecode(frames[2]['text']! as String)).messages;
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
