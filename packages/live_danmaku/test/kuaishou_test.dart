// Kuaishou danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.6-快手弹幕/record.md): the feed parser and the
// polling connection against 3.x's output for the recorded answers
// (S16-live) and the synthetic answers and sessions (S17-synthetic), written
// by fixtures/kuaishou/danmaku/legacy_expected.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kuaishou/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

/// The recorded exchanges of S16-live: the request URL and the answer body.
final List<({String url, String text})> _recordedFrames = [
  for (final line in File('$_root/S16-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 'url': final String url, 'text': final String text}) (url: url, text: text),
];

/// 3.x's output for S16-live.
final Map<String, Object?> _live =
    (_json('S16-live/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

final Map<String, Object?> _cases = _json('S17-synthetic/cases.json')! as Map<String, Object?>;

/// 3.x's output for S17-synthetic.
final Map<String, Object?> _synthetic =
    (_json('S17-synthetic/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) => [
  for (final item in value! as List<Object?>) item! as Map<String, Object?>,
];

/// The body text of one answer of cases.json (as legacy_expected.dart's
/// `bodyOf`).
String _bodyOf(Map<String, Object?> answer) {
  if (answer['raw'] case final String raw) return raw;
  var text = jsonEncode(answer['payload']);
  for (var layer = 1; layer < (answer['layers'] as int? ?? 2); layer++) {
    text = jsonEncode(text);
  }
  return text;
}

/// The projection legacy_expected.dart writes for 3.x's messages.
Map<String, Object?> _project(LiveMessage message) {
  final data = message.data;
  return {
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
    'data': data is LiveAudienceUpdate ? {'kind': data.kind.name, 'value': data.value} : data,
  };
}

/// The name 3.x's error had for what the new code throws: 3.x's HTTP client
/// threw a `CoreError` for every failed request, and a refusal was a
/// `StateError`.
String _v3ErrorName(Object error) => switch (error) {
  TransportFailure() || HttpStatusFailure() => 'CoreError',
  KuaishouFeedRejected() => 'StateError',
  FormatException() => 'FormatException',
  _ => error.runtimeType.toString(),
};

/// What legacy_expected.dart writes for one answer: the body decoded once,
/// then parsed.
Map<String, Object?> _parsed(Object? decoded) {
  try {
    final batch = KuaishouDanmakuProtocol.parse(decoded);
    return {
      'cursor': batch.cursor,
      'pullDelayMs': batch.pullDelay.inMilliseconds,
      'onlineViewers': batch.onlineViewers,
      'messages': [for (final message in batch.messages) _project(message)],
    };
  } on Object catch (error) {
    return {'error': _v3ErrorName(error)};
  }
}

/// 3.x's status texts for the reasons.
const Map<DanmakuInterruption, String> _v3Reconnect = {DanmakuInterruption.disconnected: '与服务器断开连接，正在尝试重连'};
const Map<DanmakuCloseReason, String> _v3Close = {DanmakuCloseReason.reconnectsExhausted: '服务器连接失败：快手弹幕重连超过最大次数'};

/// Answers each request with the next step of a script (`error`: a
/// transport failure of that reason; `status`: that status; otherwise the
/// answer with 200). Once the steps run out a request waits for its
/// cancellation.
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
    final status = step['status'] as int?;
    return LiveResponse(
      status: status ?? 200,
      bytes: utf8.encode(status == null ? _bodyOf(step) : ''),
      url: request.url,
    );
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

LiveResponse _ok(LiveRequest request, Object payload) =>
    LiveResponse(status: 200, bytes: utf8.encode(jsonEncode(jsonEncode(payload))), url: request.url);

Map<String, Object?> _comment(String text, {int time = 1000}) => {
  'type': 'comment',
  'content': text,
  'time': time,
  'author': {'userName': 'viewer', 'userId': 7},
};

/// One session as legacy_expected.dart traces 3.x's: requests, timer waits
/// (each fired at once), events with 3.x's texts, and how `connect` ended.
/// It ends when the script runs out, the connection closes or `connect`
/// throws. [statuses] gets the status after each event; [errors] the error
/// `connect` threw.
Future<List<Map<String, Object?>>> _session(
  List<Map<String, Object?>> steps, {
  String liveStreamId = 'ls-synthetic',
  String cookie = '',
  List<DanmakuStatus>? statuses,
  List<Object>? errors,
  List<LiveRequest>? requests,
}) async {
  final trace = <Map<String, Object?>>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final http = _ScriptedHttp(steps)
    ..onRequest = (request) => trace.add({
      'request': {
        'url': '${request.url.origin}${request.url.path}',
        'query': request.url.queryParameters,
        'headers': request.headers,
      },
    });
  unawaited(http.exhausted.future.then((_) => finish()));
  final connection = KuaishouDanmakuConnection(http: http);
  final subscription = connection.events.listen((event) {
    trace.add(switch (event) {
      DanmakuReady() => {'event': 'ready'},
      DanmakuReceived(:final message) => {'event': 'message', 'message': _project(message)},
      DanmakuReconnecting(:final reason) => {'event': 'reconnect', 'text': _v3Reconnect[reason]},
      DanmakuClosed(:final reason) => {'event': 'close', 'text': _v3Close[reason]},
    });
    statuses?.add(connection.status);
    if (event is DanmakuClosed) finish();
  });
  await runZoned(
    () async {
      try {
        await connection.connect(KuaishouDanmakuArgs(liveStreamId: liveStreamId, cookie: cookie));
        trace.add({'start': 'returned'});
      } on Object catch (error) {
        errors?.add(error);
        trace.add({'start': 'threw', 'error': _v3ErrorName(error)});
        finish();
      }
      await done.future;
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        trace.add({'delay': duration.inMilliseconds});
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
  await connection.close();
  statuses?.add(connection.status);
  await subscription.cancel();
  requests?.addAll(http.requests);
  return trace;
}

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

const KuaishouDanmakuArgs _args = KuaishouDanmakuArgs(liveStreamId: 'ls-synthetic');

void main() {
  group('protocol', () {
    test("3.x's endpoints, headers and query", () {
      expect(KuaishouDanmakuProtocol.endpoints.map((endpoint) => '$endpoint'), [
        'https://livev.m.chenzhongtech.com/wap/live/feed',
        'https://m.gifshow.com/wap/live/feed',
      ]);
      expect(KuaishouDanmakuProtocol.headers(''), {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0 Mobile '
            'Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Referer': 'https://livev.m.chenzhongtech.com/',
      });
      expect(KuaishouDanmakuProtocol.headers('   '), isNot(contains('cookie')));
      expect(KuaishouDanmakuProtocol.headers(' a=b; c=d ')['cookie'], 'a=b; c=d');
      expect(KuaishouDanmakuProtocol.query('L', ''), {'liveStreamId': 'L'});
      expect(KuaishouDanmakuProtocol.query('L', 'c'), {'liveStreamId': 'L', 'cursor': 'c'});
    });

    test("3.x's timing: start retries, back-off, give-up count, no heartbeat", () {
      expect(KuaishouDanmakuProtocol.startRetryDelays, const [
        Duration(milliseconds: 600),
        Duration(milliseconds: 1400),
      ]);
      expect(
        [for (var failures = 1; failures <= 8; failures++) KuaishouDanmakuProtocol.backoff(failures).inSeconds],
        [1, 2, 4, 8, 8, 8, 8, 8],
      );
      expect(KuaishouDanmakuProtocol.maxFailures, 8);
      expect(KuaishouDanmakuProtocol.defaultPullDelay, const Duration(seconds: 3));
      final connection = KuaishouDanmakuConnection(http: _ScriptedHttp(const []));
      expect(connection.heartbeatInterval, Duration.zero);
      connection.heartbeat();
      expect(connection.status, DanmakuStatus.idle);
    });

    // 3.x test/kuaishou_danmaku_test.dart, first two cases.
    test('parses double-encoded mobile feed comments and audience count', () {
      final batch = KuaishouDanmakuProtocol.parse(
        jsonEncode(
          jsonEncode({
            'result': 1,
            'cursor': 'next-cursor',
            'pullCycleSeconds': 3,
            'currentWatchingCount': '1.2万',
            'liveStreamFeeds': [
              {
                'type': 'comment',
                'content': '测试弹幕',
                'time': 1788278277492,
                'author': {'userName': '快手用户A', 'userId': 4143159120},
              },
              {
                'type': 'gift',
                'content': '礼物',
                'author': {'userName': '礼物用户'},
              },
            ],
          }),
        ),
      );
      expect(batch.cursor, 'next-cursor');
      expect(batch.pullDelay, const Duration(seconds: 3));
      expect(batch.onlineViewers, 12000);
      expect(batch.messages, hasLength(1));
      expect(batch.messages.single.message, '测试弹幕');
      expect(batch.messages.single.userName, '快手用户A');
      expect(batch.messages.single.userId, '4143159120');
      expect(batch.messages.single.messageId, startsWith('kuaishou:'));
      expect(batch.messages.single.sentAt?.millisecondsSinceEpoch, 1788278277492);
      expect(batch.reported.map((message) => message.type), [LiveMessageType.online, LiveMessageType.chat]);
      final audience = batch.reported.first;
      expect(audience.data, isA<LiveAudienceUpdate>());
      expect((audience.data! as LiveAudienceUpdate).kind, LiveAudienceMetricKind.onlineViewers);
      expect((audience.data! as LiveAudienceUpdate).value, 12000);
    });

    test('rejects an unsuccessful answer instead of presenting a false connection', () {
      expect(
        () => KuaishouDanmakuProtocol.parse({'result': 2, 'liveStreamFeeds': <Object?>[]}),
        throwsA(isA<KuaishouFeedRejected>().having((error) => error.result, 'result', 2)),
      );
      expect(
        () => KuaishouDanmakuProtocol.parse({'result': 'x'}),
        throwsA(isA<KuaishouFeedRejected>().having((error) => error.result, 'result', isNull)),
      );
    });

    test('an answer without an audience figure reports only its comments', () {
      final batch = KuaishouDanmakuProtocol.parse({
        'result': 1,
        'liveStreamFeeds': [_comment('only')],
      });
      expect(batch.onlineViewers, isNull);
      expect(batch.reported.map((message) => message.message), ['only']);
    });
  });

  group('recorded answers (S16-live) against 3.x', () {
    test('every recorded answer parses to what 3.x parsed', () {
      final expected = _list(_live['answers']);
      expect(_recordedFrames, hasLength(expected.length));
      for (var index = 0; index < _recordedFrames.length; index++) {
        expect(_parsed(jsonDecode(_recordedFrames[index].text)), expected[index], reason: 'answer $index');
      }
      expect([for (final answer in expected) ...(answer['messages']! as List<Object?>)], hasLength(42));
    });

    test("replaying the recording: 3.x's requests, waits and messages, in order", () async {
      final requests = <LiveRequest>[];
      final trace = await _session(
        [
          for (final frame in _recordedFrames) {'raw': frame.text},
        ],
        liveStreamId: _live['liveStreamId']! as String,
        requests: requests,
      );
      expect(trace, _list(_live['session']));
      // The recording tool asked for the same URLs, in the same order.
      expect(
        [for (final request in requests.take(_recordedFrames.length)) '${request.url}'],
        [for (final frame in _recordedFrames) frame.url],
      );
    });
  });

  group('synthetic answers (S17-synthetic) against 3.x', () {
    final feeds = _list(_cases['feeds']);
    final expected = {for (final feed in _list(_synthetic['feeds'])) feed['name']! as String: feed};

    test('every feed has 3.x output', () {
      expect(expected.keys, [for (final feed in feeds) feed['name']]);
    });

    for (final feed in feeds) {
      final name = feed['name']! as String;
      test(name, () {
        final v3 = Map.of(expected[name]!)..remove('name');
        final actual = _parsed(jsonDecode(_bodyOf(feed)));
        if (feed['skipEntry'] != null) {
          // 3.x failed the whole answer on the entry DateTime cannot hold;
          // the new code skips that entry only (差异 2).
          expect(v3['error'], anyOf('RangeError', 'UnsupportedError'));
          expect(actual, v3['v3WithoutEntry']);
          return;
        }
        expect(actual, v3);
      });
    }
  });

  group('synthetic sessions (S17-synthetic) against 3.x', () {
    final sessions = _list(_cases['sessions']);
    final expected = {
      for (final session in _list(_synthetic['sessions'])) session['name']! as String: session['trace'],
    };

    test('every session has 3.x output', () {
      expect(expected.keys, [for (final session in sessions) session['name']]);
    });

    for (final session in sessions) {
      final name = session['name']! as String;
      test(name, () async {
        final trace = await _session(
          _list(session['steps']),
          liveStreamId: session['liveStreamId'] as String? ?? 'ls-synthetic',
          cookie: session['cookie'] as String? ?? '',
        );
        expect(trace, expected[name]);
      });
    }
  });

  group('connection', () {
    test('a failed start throws the last failure, typed, and leaves the connection idle', () async {
      final sessions = {for (final session in _list(_cases['sessions'])) session['name']! as String: session};
      Future<Object> failure(String name) async {
        final errors = <Object>[];
        final requests = <LiveRequest>[];
        final session = sessions[name]!;
        await _session(
          _list(session['steps']),
          liveStreamId: session['liveStreamId'] as String? ?? 'ls-synthetic',
          errors: errors,
          requests: requests,
        );
        return errors.single;
      }

      expect(
        await failure('three failed starts throw the last failure'),
        isA<HttpStatusFailure>().having((error) => error.status, 'status', 502),
      );
      expect(
        await failure('three refused starts throw the refusal'),
        isA<KuaishouFeedRejected>().having((error) => error.result, 'result', 3),
      );
      expect(
        await failure('a body that is not JSON goes to the fallback, an answer of the wrong shape does not'),
        isFormatException,
      );
      expect(await failure('a blank live stream id throws before any request'), isFormatException);

      final connection = KuaishouDanmakuConnection(
        http: _ScriptedHttp([
          for (var request = 0; request < 6; request++) {'error': 'connect'},
        ]),
      );
      final events = _record(connection);
      await runZoned(
        () => expectLater(connection.connect(_args), throwsA(isA<TransportFailure>())),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) => parent.createTimer(zone, Duration.zero, callback),
        ),
      );
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.isConnected, isFalse);
      expect(events, isEmpty);
    });

    test('status follows ready, reconnecting and joining again; the last failure is the close detail', () async {
      final statuses = <DanmakuStatus>[];
      final recovering = _list(
        _list(_cases['sessions'])
            .firstWhere((session) => session['name'] == 'a success resets the failures and joins again')['steps'],
      );
      await _session(recovering, statuses: statuses);
      expect(statuses, [
        DanmakuStatus.connected, // ready
        DanmakuStatus.connected, // audience
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected, // ready again
        DanmakuStatus.connected,
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected, // ready again
        DanmakuStatus.idle, // closed by the test
      ]);

      final closed = <DanmakuEvent>[];
      final http = _ScriptedHttp([
        {
          'payload': {'result': 1},
        },
        for (var failure = 0; failure < 18; failure++) {'error': 'connect'},
      ]);
      final connection = KuaishouDanmakuConnection(http: http);
      connection.events.where((event) => event is DanmakuClosed).listen(closed.add);
      await runZoned(
        () async {
          await connection.connect(_args);
          await _until(() => closed.isNotEmpty);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) => parent.createTimer(zone, Duration.zero, callback),
        ),
      );
      expect(
        closed.single,
        isA<DanmakuClosed>()
            .having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted)
            .having((event) => event.detail, 'detail', contains('connect')),
      );
      expect(connection.status, DanmakuStatus.closed);
      expect(http.requests, hasLength(1 + 18));
    });

    // 3.x test/kuaishou_danmaku_test.dart, last case; REG-KUAISHOU-014.
    test('close during the first request cancels it; connect completes; nothing follows', () async {
      final http = _ScriptedHttp(const []);
      final connection = KuaishouDanmakuConnection(http: http);
      final events = _record(connection);
      final connecting = connection.connect(_args);
      await http.exhausted.future;
      await connection.close();
      await connecting;
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      expect(http.requests, hasLength(1), reason: 'not retried on the fallback');
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('close while waiting for the next request: no request, event or timer follows', () async {
      final timers = <Timer>[];
      final http = _ScriptedHttp([
        {
          'payload': {
            'result': 1,
            'cursor': 'a',
            'liveStreamFeeds': [_comment('hello')],
          },
        },
      ]);
      final connection = KuaishouDanmakuConnection(http: http);
      final events = _record(connection);
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
      expect(connection.isConnected, isTrue);
      expect(timers.single.isActive, isTrue, reason: 'the 3 s wait');
      await connection.close();
      await _wait(const Duration(milliseconds: 20));
      expect(timers.single.isActive, isFalse);
      expect(http.requests, hasLength(1));
      expect(events.map((event) => event.runtimeType), [DanmakuReady, DanmakuReceived]);
      expect(connection.isConnected, isFalse);
    });

    test("connecting to another room: the first room's late answer is dropped", () async {
      final http = _ManualHttp();
      final connection = KuaishouDanmakuConnection(http: http);
      final events = _record(connection);
      final first = connection.connect(const KuaishouDanmakuArgs(liveStreamId: 'first'));
      await _until(() => http.pending.length == 1);
      final second = connection.connect(const KuaishouDanmakuArgs(liveStreamId: 'second', cookie: 'k=v'));
      await _until(() => http.pending.length == 2);
      final (request: firstRequest, answer: firstAnswer) = http.pending.first;
      final (request: secondRequest, answer: secondAnswer) = http.pending.last;
      expect(firstRequest.cancel!.isCancelled, isTrue);
      expect(firstRequest.url.queryParameters['liveStreamId'], 'first');
      expect(secondRequest.url.queryParameters, {'liveStreamId': 'second'}, reason: 'a new room starts without cursor');
      expect(secondRequest.headers['cookie'], 'k=v');
      firstAnswer.complete(
        _ok(firstRequest, {
          'result': 1,
          'cursor': 'x',
          'liveStreamFeeds': [_comment('from the first room')],
        }),
      );
      await first;
      secondAnswer.complete(
        _ok(secondRequest, {
          'result': 1,
          'cursor': 'y',
          'liveStreamFeeds': [_comment('from the second room')],
        }),
      );
      await second;
      expect(
        [
          for (final event in events)
            if (event is DanmakuReceived) event.message.message,
        ],
        ['from the second room'],
      );
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(http.pending, hasLength(2), reason: 'the next request waits for the 3 s pull cycle');
      await connection.close();
    });

    test('takes KuaishouDanmakuArgs only', () async {
      final http = _ScriptedHttp(const []);
      final connection = KuaishouDanmakuConnection(http: http);
      await expectLater(connection.connect('ls-synthetic'), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(http.requests, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('registers in DanmakuRegistry under kuaishou', () {
      final http = _ScriptedHttp(const []);
      final registry = DanmakuRegistry({SiteIds.kuaishou: () => KuaishouDanmakuConnection(http: http)});
      expect(registry.platforms, [SiteIds.kuaishou]);
      expect(registry.connectionFor(' Kuaishou '), isA<KuaishouDanmakuConnection>());
      expect(registry.connectionFor('douyu'), isA<EmptyDanmakuConnection>());
    });

    test('a local HTTP server: recorded answers, the fallback after a 503, headers on the wire', () async {
      final seen = <HttpHeaders>[];
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        seen.add(request.headers);
        paths.add('${request.uri.path}?${request.uri.query}');
        final response = request.response..headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        switch (paths.length) {
          case 1:
            response.write(_recordedFrames[0].text);
          case 2:
            response.statusCode = 503;
          case 3:
            response.write(_recordedFrames[1].text);
          default:
            // Never answers; the connection is closed meanwhile.
            return;
        }
        await response.close();
      });
      final http = _Rerouted(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = KuaishouDanmakuConnection(http: http);
      final events = _record(connection);
      final liveStreamId = _live['liveStreamId']! as String;
      await runZoned(
        () async {
          await connection.connect(KuaishouDanmakuArgs(liveStreamId: liveStreamId, cookie: ' did=web_1 '));
          await _until(() => paths.length == 4);
        },
        zoneSpecification: ZoneSpecification(
          // Only the pull cycle waits (1–10 s) fire at once, not the client's
          // timeouts.
          createTimer: (self, parent, zone, duration, callback) => parent.createTimer(
            zone,
            duration >= const Duration(seconds: 1) && duration <= const Duration(seconds: 10)
                ? Duration.zero
                : duration,
            callback,
          ),
        ),
      );
      await connection.close();
      final cursor = _parsed(jsonDecode(_recordedFrames[0].text))['cursor'];
      expect(paths, [
        '/primary/wap/live/feed?liveStreamId=$liveStreamId',
        '/primary/wap/live/feed?liveStreamId=$liveStreamId&cursor=$cursor',
        '/fallback/wap/live/feed?liveStreamId=$liveStreamId&cursor=$cursor',
        '/primary/wap/live/feed?liveStreamId=$liveStreamId&cursor=${_parsed(jsonDecode(_recordedFrames[1].text))['cursor']}',
      ]);
      for (final headers in seen) {
        expect(headers.value('user-agent'), KuaishouDanmakuProtocol.userAgent);
        expect(headers.value('accept'), 'application/json, text/plain, */*');
        expect(headers.value('referer'), 'https://livev.m.chenzhongtech.com/');
        expect(headers.value('cookie'), 'did=web_1');
      }
      final v3 = _list(_live['session']);
      final v3Events = [
        for (final entry in v3)
          if (entry['event'] != null) entry,
      ];
      // The first two answers: ready, then each answer's audience and comments.
      final firstTwo = v3Events.take(1 + 4 + 10).toList();
      expect([
        for (final event in events)
          switch (event) {
            DanmakuReady() => {'event': 'ready'},
            DanmakuReceived(:final message) => {'event': 'message', 'message': _project(message)},
            _ => {'event': '$event'},
          },
      ], firstTwo);
      expect(
        events.whereType<DanmakuReconnecting>(),
        isEmpty,
        reason: 'the fallback answered, so the request did not fail',
      );
    });
  });
}

/// Sends the feed requests to a local server: the primary endpoint under
/// `/primary`, the fallback under `/fallback`.
final class _Rerouted implements LiveHttp {
  new(this._inner, this._port);

  final LiveHttp _inner;
  final int _port;

  @override
  Future<LiveResponse> send(LiveRequest request) {
    final prefix = request.url.host == KuaishouDanmakuProtocol.endpoints.first.host ? 'primary' : 'fallback';
    return _inner.send(
      LiveRequest(
        site: request.site,
        url: Uri.parse('http://127.0.0.1:$_port/$prefix${request.url.path}?${request.url.query}'),
        headers: request.headers,
        timeout: request.timeout,
        cancel: request.cancel,
      ),
    );
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
