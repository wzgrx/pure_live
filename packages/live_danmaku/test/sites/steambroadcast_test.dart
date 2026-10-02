// Steam broadcast chat (docs/T06/T06a/T06a.24/record.md): the protocol
// against the archived v4's reading of the recording
// (fixtures/steambroadcast/danmaku/S07-live, expected.json written by
// danmaku/v4_expected.dart), synthetic answers for everything the recording
// lacks (chat lines after the history, failures, other states), and the
// connection over the recording and a synthetic Steam. The connection's
// waits run in a zone that fires them at once and moves a fake clock by
// them, so the chat log's clock is checked to the millisecond; one test
// reads through IoLiveHttp from a local server. The chat log's times are its
// own clock (milliseconds since the chat began), never compared with the
// wall clock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/steambroadcast/danmaku';

/// The recorded answers of S07-live: line, URL, arrival (ms after the start)
/// and body.
final List<({int line, Uri url, int t, String text})> _recording = [
  for (final (index, line) in File('$_root/S07-live/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': 'in', 'url': final String url, 't': final int t, 'text': final String text})
      (line: index + 1, url: Uri.parse(url), t: t, text: text),
];

/// The archived v4's reading of S07-live (danmaku/v4_expected.dart).
final Map<String, Object?> _v4 =
    (jsonDecode(File('$_root/S07-live/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

final List<Map<String, Object?>> _v4Windows = [
  for (final window in _v4['windows']! as List<Object?>) window! as Map<String, Object?>,
];

/// The recorded broadcaster (meta.json's `danmakuKeys`).
const _steamId = '76561199799018508';

/// A broadcaster for the synthetic answers.
const _synthetic = '76561199485215572';

String _projectChat(LiveMessage message) => '${message.userId}|${message.userName}|${message.message}';

/// What a test shows of an event.
Object _shown(DanmakuEvent event) => switch (event) {
  DanmakuReceived(message: LiveMessage(type: LiveMessageType.online, data: final LiveAudienceUpdate update)) =>
    'viewers ${update.kind.name} ${update.value}',
  DanmakuReceived(:final message) => 'chat ${_projectChat(message)}',
  _ => '$event',
};

LiveResponse _json(LiveRequest request, Object? body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(jsonEncode(body)), url: request.url);

LiveResponse _text(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

const _notFoundPage = '<html> <head> <title>404 Not Found</title> </head> <body> <h1>Not Found</h1> </body> </html>';

/// The connection's monotonic clock in a test.
final class _Clock {
  Duration now = Duration.zero;
}

/// Runs a connection on a fake clock: every timer the connection sets fires
/// at once and moves the clock by its duration, recorded in [waits].
final class _Session {
  new(LiveHttp http, {_Clock? clock}) : clock = clock ?? _Clock() {
    connection = SteamBroadcastDanmakuConnection(http: http, elapsed: () => this.clock.now);
    connection.events.listen((event) {
      events.add(event);
      statuses.add(connection.status);
    });
  }

  final _Clock clock;
  late final SteamBroadcastDanmakuConnection connection;
  final List<Duration> waits = [];
  final List<DanmakuEvent> events = [];
  final List<DanmakuStatus> statuses = [];

  List<int> get waited => [for (final wait in waits) wait.inMilliseconds];

  List<Object> get shown => events.map(_shown).toList();

  Future<void> connect(Object? args) => runZoned(
    () => connection.connect(args),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        waits.add(duration);
        clock.now += duration;
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
}

/// A synthetic Steam. `getbroadcastmpd` answers [mpd]; `getchatinfo` the
/// chat of [current] (HTTP 500 `success: 2` for any other id, as Steam
/// does); the chat log of [current] answers window 0 with one history line,
/// `next_request` [first] and [initialDelay], and window t with [lines] of t
/// and t + [step] (with [initialDelays] of t when given); another chat log
/// is 404. Each request moves the clock by [rtt] (and [slow] of its
/// window). [script] may answer instead (its log line and how many times it
/// was asked). After [windowLimit] chat log requests every request waits for
/// its cancellation and [idle] completes.
final class _Steam implements LiveHttp {
  new(this.clock, {this.rtt = Duration.zero, this.windowLimit = 6});

  final _Clock clock;
  final Duration rtt;
  final int windowLimit;
  final List<LiveRequest> requests = [];
  final List<String> log = [];
  final Completer<void> idle = Completer();
  Map<String, Object?> mpd = {'success': 'ready', 'broadcastid': '7001', 'num_viewers': 42, 'hls_url': ''};
  String current = '7001';
  int first = 5000;
  int step = 500;
  int initialDelay = 300;
  final Map<int, List<Map<String, Object?>>> lines = {};
  final Map<int, int> initialDelays = {};
  final Map<int, Duration> slow = {};
  LiveResponse? Function(LiveRequest request, String line, int count)? script;
  int _windows = 0;

  static String template(String broadcast) =>
      'https://steambroadcastchat.akamaized.net/chat/c$broadcast/messages/{0}?chat_origin=chat1.discovery.steamserver.net:8071';

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final url = request.url;
    final line = switch (url.path) {
      '/broadcast/getbroadcastmpd/' => 'mpd',
      '/broadcast/getchatinfo/' => 'info ${url.queryParameters['broadcastid']}',
      _ => 'window ${url.pathSegments[1]}:${url.pathSegments.last}',
    };
    log.add(line);
    final count = log.where((entry) => entry == line).length;
    if (line.startsWith('window') && ++_windows > windowLimit) {
      if (!idle.isCompleted) idle.complete();
      await request.cancel!.whenCancelled;
      throw const TransportFailure(SiteIds.steamBroadcast, TransportReason.cancelled);
    }
    clock.now += rtt;
    if (script?.call(request, line, count) case final answer?) return answer;
    if (line == 'mpd') return _json(request, mpd);
    if (line.startsWith('info ')) {
      final id = url.queryParameters['broadcastid'];
      return id == current
          ? _json(request, {
              'success': 1,
              'chat_id': 'c$id',
              'view_url_template': template(id!),
              'blocked': false,
              'moderators_steamid': <Object?>[],
            })
          : _json(request, {'success': 2}, status: 500);
    }
    if (url.pathSegments[1] != 'c$current') return _text(request, _notFoundPage, status: 404);
    final time = int.parse(url.pathSegments.last);
    clock.now += slow[time] ?? Duration.zero;
    if (time == 0) {
      return _json(request, {
        'messages': [
          {'steamid': '100', 'persona_name': 'old', 'msg': 'history'},
        ],
        'next_request': first,
        'initial_delay': initialDelay,
      });
    }
    return _json(request, {
      'messages': lines[time] ?? <Object?>[],
      'next_request': time + step,
      'initial_delay': ?initialDelays[time],
    });
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

/// A chat line of the chat log.
Map<String, Object?> _line(String text, {String steamId = '200', String name = 'viewer'}) => {
  'steamid': steamId,
  'instance_id': 1234,
  'persona_name': name,
  'flair': '',
  'in_game': false,
  'msg': text,
};

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

const _args = SteamBroadcastDanmakuArgs(_synthetic, broadcastId: '7001');

void main() {
  group('protocol', () {
    test("the requests: v4's and the recorded URLs, the adapter's headers, the chat log's cross-origin headers", () {
      expect(SteamBroadcastApi.mpdUrl(_steamId).toString(), _v4['broadcastUrl']);
      expect(SteamBroadcastApi.mpdUrl(_steamId), _recording[0].url);
      expect(SteamBroadcastDanmakuProtocol.chatInfoUrl(_steamId, '3718707516587165478').toString(), _v4['chatInfoUrl']);
      expect(SteamBroadcastDanmakuProtocol.chatInfoUrl(_steamId, '3718707516587165478'), _recording[1].url);
      expect(SteamBroadcastDanmakuProtocol.headers(_steamId), SteamBroadcastApi.roomHeaders(_steamId, json: true));
      expect(SteamBroadcastDanmakuProtocol.headers(_steamId)['x-requested-with'], 'XMLHttpRequest');
      expect(SteamBroadcastDanmakuProtocol.chatHeaders(_steamId), {
        'user-agent': SteamBroadcastApi.userAgent,
        'accept': 'application/json, text/javascript, */*; q=0.01',
        'accept-language': 'en-US,en;q=0.9',
        'origin': 'https://steamcommunity.com',
        'referer': 'https://steamcommunity.com/broadcast/watch/$_steamId',
      });
      final cancel = CancelToken();
      final request = SteamBroadcastDanmakuProtocol.request(_recording[2].url, const {'a': 'b'}, cancel: cancel);
      expect(request.site, 'steambroadcast');
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.timeout, const Duration(seconds: 10));
      expect(request.cancel, same(cancel));
      expect(request.headers, {'a': 'b'});
    });

    test('getchatinfo: the recorded template; refusals and shapes that are not a chat log', () {
      final chat = SteamBroadcastDanmakuProtocol.chat(_recording[1].text, broadcastId: '3718707516587165478');
      expect(chat.template, _v4['template']);
      expect(chat.window(0), _recording[2].url);
      expect(chat.window(414148761), _recording[3].url);
      expect(chat.broadcastId, '3718707516587165478');
      expect(chat, SteamBroadcastChat(broadcastId: '3718707516587165478', template: chat.template));

      Matcher refused<T extends SiteError>(String detail) =>
          throwsA(isA<T>().having((error) => '$error', 'detail', contains(detail)));
      SteamBroadcastChat read(Object? body, {int status = 200}) => SteamBroadcastDanmakuProtocol.chat(
        body is String ? body : jsonEncode(body),
        broadcastId: '1',
        status: status,
      );
      // Steam's answer for an id that is not the broadcaster's current one.
      expect(() => read({'success': 2}, status: 500), refused<NetworkFailure>('getchatinfo: HTTP 500 {"success":2}'));
      expect(() => read('<html>denied</html>', status: 403), refused<RiskControl>('HTTP 403'));
      expect(() => read('', status: 404), refused<NotFound>('HTTP 404'));
      expect(() => read('', status: 429), refused<RateLimited>('HTTP 429'));
      expect(() => read('not json'), refused<ApiChanged>('not JSON'));
      expect(() => read([1]), refused<ApiChanged>('not an object'));
      String address(String url) => jsonEncode({'success': 1, 'view_url_template': url});
      expect(() => read({'success': 2}), refused<ApiChanged>('success 2'));
      expect(() => read({'success': 1}), refused<ApiChanged>('view_url_template'));
      expect(() => read({'success': 1, 'view_url_template': 7}), refused<ApiChanged>('view_url_template'));
      for (final url in [
        'https://steambroadcastchat.akamaized.net/chat/1/messages/0',
        'http://steambroadcastchat.akamaized.net/chat/1/messages/{0}',
        'https://evil.akamaized.net/chat/1/messages/{0}',
        'https://steambroadcastchat.akamaized.net.evil.test/chat/1/messages/{0}',
        'https://evilsteamcommunity.com/chat/1/messages/{0}',
        'https://user@steambroadcastchat.akamaized.net/chat/1/messages/{0}',
        'https://steambroadcastchat.akamaized.net:8443/chat/1/messages/{0}',
        'https://steambroadcastchat.akamaized.net/chat/1/messages/{0}#x',
      ]) {
        expect(() => read(address(url)), throwsA(isA<ApiChanged>()), reason: url);
      }
      for (final url in [
        'https://steambroadcastchat.akamaized.net/chat/1/messages/{0}?chat_origin=x.steamserver.net:8071',
        'https://SteamBroadcastChat.akamaized.net:443/chat/1/messages/{0}',
        'https://steambroadcast-chat2.akamaized.net/chat/1/messages/{0}',
        'https://broadcastchat7.discovery.steamserver.net/chat/1/messages/{0}',
        'https://steamcommunity.com/broadcast/chat/1/{0}',
        'https://cache1.steamcontent.com/chat/{0}',
        'https://community.fastly.steamstatic.com/chat/{0}',
      ]) {
        expect(read(address(url)).template, url);
      }
      expect(
        read(address('https://steamcommunity.com/c/{0}/{0}')).window(5),
        Uri.parse('https://steamcommunity.com/c/5/{0}'),
      );
      expect(read({'success': '1', 'view_url_template': 'https://steamcommunity.com/c/{0}'}).template, isNotEmpty);
    });

    test('broadcast ids: digits, not 0, trimmed', () {
      expect(SteamBroadcastDanmakuProtocol.broadcastIdOf(' 3718707516587165478 '), '3718707516587165478');
      expect(SteamBroadcastDanmakuProtocol.broadcastIdOf('7'), '7');
      for (final value in [null, '', '0', '007', '-1', '1.5', 'abc', '1' * 21]) {
        expect(SteamBroadcastDanmakuProtocol.broadcastIdOf(value), isNull, reason: value);
      }
    });

    test('a window: the next window, initial_delay and the chat lines', () {
      final window = SteamBroadcastDanmakuProtocol.window(
        jsonEncode({
          'messages': [
            _line('  hello  ', steamId: '42', name: ' Name '),
            _line('ːsteamhappyː'),
            _line('   '),
            {'steamid': '3', 'persona_name': 'n', 'msg': 12},
            {'steamid': 4, 'persona_name': 5, 'msg': 'numbers'},
            {'steamid': true, 'msg': 'no name'},
            'text',
            null,
          ],
          'next_request': 1500,
        }),
        time: 1000,
      );
      expect(window.next, 1500);
      expect(window.initialDelay, isNull);
      expect(window.messages.map(_projectChat), [
        '42|Name|hello',
        '200|viewer|ːsteamhappyː',
        '4||numbers',
        '||no name',
      ]);
      for (final message in window.messages) {
        expect(message.type, LiveMessageType.chat);
        expect(message.color, LiveMessageColor.white);
        expect(message.messageId, '', reason: 'Steam gives no id');
        expect(message.sentAt, isNull, reason: 'nor a time');
        expect((message.userLevel, message.fansName, message.data), ('', '', null));
      }
      expect(() => window.messages.add(window.messages.first), throwsUnsupportedError);

      SteamBroadcastChatWindow read(Map<String, Object?> body, {int time = 1000}) =>
          SteamBroadcastDanmakuProtocol.window(jsonEncode(body), time: time);
      expect(read({'next_request': '1500', 'initial_delay': '250'}).next, 1500);
      expect(read({'next_request': 1001, 'initial_delay': 250}).initialDelay, const Duration(milliseconds: 250));
      expect(read({'next_request': 1500, 'initial_delay': '250'}).initialDelay, const Duration(milliseconds: 250));
      expect(read({'next_request': 1500, 'initial_delay': 0}).initialDelay, Duration.zero);
      for (final delay in [-1, 2.5, 'soon', null, true]) {
        expect(read({'next_request': 1500, 'initial_delay': delay}).initialDelay, isNull, reason: '$delay');
      }
      expect(read({'next_request': 1500, 'messages': 'none'}).messages, isEmpty);
      expect(read({'next_request': 7, 'messages': <Object?>[]}, time: 0).next, 7, reason: 'window 0: any next');
      for (final next in [null, 0, -5, 1000, 999, 1500.0, '15a', '', '1234567890123456', true]) {
        expect(() => read({'next_request': next}), throwsA(isA<ApiChanged>()), reason: '$next');
      }
      expect(
        () => SteamBroadcastDanmakuProtocol.window(_notFoundPage, time: 1000, status: 404),
        throwsA(
          isA<NotFound>().having((error) => '$error', 'detail', 'NotFound(steambroadcast: chat window 1000: HTTP 404)'),
        ),
      );
      expect(() => SteamBroadcastDanmakuProtocol.window('{', time: 1), throwsA(isA<ApiChanged>()));
      expect(() => SteamBroadcastDanmakuProtocol.window('[]', time: 1), throwsA(isA<ApiChanged>()));
      expect(() => SteamBroadcastDanmakuProtocol.window('', time: 1, status: 502), throwsA(isA<NetworkFailure>()));
    });

    test("the audience: getbroadcastmpd's num_viewers, concurrent viewers", () {
      final message = SteamBroadcastDanmakuProtocol.audience(2519);
      expect(message.type, LiveMessageType.online);
      expect(message.data, isA<LiveAudienceUpdate>());
      final update = message.data! as LiveAudienceUpdate;
      expect((update.kind, update.value), (LiveAudienceMetricKind.onlineViewers, 2519));
      expect(AudiencePlatformCapability.of('steambroadcast').onlineAvailability, AudienceOnlineAvailability.roomList);
    });

    test("the chat log's clock: as the web client times it, with the nudge and the bounds", () {
      final clock = SteamBroadcastChatClock();
      expect((clock.isSynced, clock.window, clock.nudge), (false, 0, Duration.zero));
      Duration ms(int value) => Duration(milliseconds: value);
      expect(clock.sync(5000, ms(300), ms(100)), ms(300));
      expect((clock.isSynced, clock.window), (true, 5000));
      // Window 5500 is due 500 ms after window 5000, which was due at 400.
      expect(clock.advance(5500, ms(450)), ms(450));
      expect(clock.window, 5500);
      // Behind (6000 was due at 1400, 6500 at 1900): at once.
      expect(clock.advance(6000, ms(1500)), Duration.zero);
      expect(clock.advance(6500, ms(1900)), Duration.zero);
      expect(clock.advance(7000, ms(1900)), ms(500));
      clock
        ..miss()
        ..miss();
      expect(clock.nudge, ms(20));
      expect(clock.advance(7500, ms(2400)), ms(520), reason: 'due at 400 + 2500 + 20');
      for (var i = 0; i < 200; i++) {
        clock.miss();
      }
      expect(clock.nudge, const Duration(seconds: 1), reason: 'bounded (the web client is not)');
      expect(clock.advance(1000000, ms(0)), const Duration(seconds: 60), reason: 'at most 60 s');
      expect(clock.sync(9000, const Duration(minutes: 5), ms(0)), const Duration(seconds: 60));
      expect(clock.sync(9000, ms(-5), ms(0)), Duration.zero);
      clock.resync();
      expect((clock.isSynced, clock.window, clock.nudge), (false, 0, const Duration(seconds: 1)));
      expect(SteamBroadcastChatClock().advance(300, ms(10)), Duration.zero, reason: 'not set: sets it now');
    });

    test('the waits after failures: 500 ms, then 1, 2, 4, 8 s from the 8th', () {
      expect(
        [for (var failures = 1; failures <= 15; failures++) SteamBroadcastDanmakuProtocol.wait(failures)],
        [
          for (var i = 0; i < 7; i++) const Duration(milliseconds: 500),
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          for (var i = 0; i < 5; i++) const Duration(seconds: 8),
        ],
      );
      expect(
        (
          SteamBroadcastDanmakuProtocol.resyncAfter,
          SteamBroadcastDanmakuProtocol.lookUpAfter,
          SteamBroadcastDanmakuProtocol.maxFailures,
        ),
        (4, 8, 15),
      );
    });
  });

  group('recording (S07-live)', () {
    test("getbroadcastmpd and getchatinfo: the broadcast, viewers and template are v4's", () {
      expect(_recording, hasLength(146));
      final broadcast = SteamBroadcastApi.broadcast(_recording[0].text, steamId: _steamId);
      expect(broadcast.broadcastId, _v4['broadcastId']);
      expect(broadcast.state, SteamBroadcastState.live);
      expect(broadcast.viewers, 2519);
      expect(_recording[1].url.queryParameters['broadcastid'], _v4['broadcastId']);
      final chat = SteamBroadcastDanmakuProtocol.chat(_recording[1].text, broadcastId: broadcast.broadcastId!);
      expect(chat.template, _v4['template']);
    });

    test('each of the 144 chat log answers reads as v4 read it; each window is the previous next_request', () {
      expect(_v4Windows, hasLength(144));
      final chat = SteamBroadcastDanmakuProtocol.chat(_recording[1].text, broadcastId: '3718707516587165478');
      int? expectedTime = 0;
      for (final expected in _v4Windows) {
        final frame = _recording[(expected['line']! as int) - 1];
        final time = expected['time']! as int;
        expect(time, expectedTime, reason: 'line ${frame.line}');
        expect(chat.window(time), frame.url);
        expect(chat.window(time).toString(), expected['url']);
        final window = SteamBroadcastDanmakuProtocol.window(frame.text, time: time);
        expect(window.next, expected['next'], reason: 'line ${frame.line}');
        expect(window.initialDelay?.inMilliseconds, expected['initialDelay'], reason: 'line ${frame.line}');
        final v4 = [for (final event in expected['events']! as List<Object?>) event! as Map<String, Object?>];
        expect(window.messages.map(_projectChat), [
          for (final event in v4) '${event['userId']}|${event['userName']}|${event['text']}',
        ], reason: 'line ${frame.line}');
        // v4's ids are the window and the position; the new messages have none.
        expect(
          [for (final event in v4) event['id']],
          [for (var index = 0; index < v4.length; index++) 'steambroadcast:$time:$index'],
        );
        expectedTime = window.next;
      }
      expect(_v4Windows.first['initialDelay'], 491);
      expect((_v4Windows.first['events']! as List).length, 50, reason: 'the history');
      expect(_v4Windows.skip(1).every((window) => (window['events']! as List).isEmpty), isTrue);
      // The log's clock follows the wall clock: 143 windows in 77.8 s.
      final firstTime = _v4Windows[1]['time']! as int;
      final lastTime = _v4Windows.last['time']! as int;
      final elapsed = _recording.last.t - _recording[3].t;
      expect((lastTime - firstTime - elapsed).abs(), lessThan(1000));
    });

    test('the connection replays the recording: the same requests, one join, the viewers, no history', () async {
      final requests = <LiveRequest>[];
      final byUrl = {for (final frame in _recording) frame.url.toString(): frame.text};
      final http = _ManualHttp();
      final session = _Session(http);
      unawaited(session.connect(const SteamBroadcastDanmakuArgs(_steamId)));
      var answered = 0;
      final done = Completer<void>();
      // Answers every recorded request at once; the one after the recording waits.
      unawaited(() async {
        while (answered < _recording.length) {
          await _until(() => http.pending.length > answered);
          final pending = http.pending[answered++];
          requests.add(pending.request);
          final body = byUrl[pending.request.url.toString()];
          pending.answer.complete(
            body == null ? _text(pending.request, _notFoundPage, status: 404) : _text(pending.request, body),
          );
        }
        await _until(() => http.pending.length > answered);
        done.complete();
      }());
      await done.future;
      final next = http.pending.last.request.url;
      await session.connection.close();
      expect([for (final request in requests) request.url], [for (final frame in _recording) frame.url]);
      expect(next, Uri.parse((_v4['template']! as String).replaceFirst('{0}', '${_v4Windows.last['next']}')));
      expect(session.shown, ['viewers onlineViewers 2519', 'DanmakuReady()']);
      final steps = [
        for (var index = 2; index < _v4Windows.length; index++)
          (_v4Windows[index]['time']! as int) - (_v4Windows[index - 1]['time']! as int),
      ];
      // No time passes while answering: after the history each wait is the
      // step of the log's clock.
      expect(session.waited, [0, 491, ...steps, 414227100 - 414226555]);
      for (final request in requests.take(2)) {
        expect(request.headers, SteamBroadcastApi.roomHeaders(_steamId, json: true));
      }
      for (final request in requests.skip(2)) {
        expect(request.headers, SteamBroadcastDanmakuProtocol.chatHeaders(_steamId));
        expect(request.followRedirects, isFalse);
      }
      expect(session.connection.status, DanmakuStatus.idle);
    });
  });

  group('connection', () {
    test('registers under the platform id; no heartbeat', () async {
      final registry = DanmakuRegistry({
        SiteIds.steamBroadcast: () => SteamBroadcastDanmakuConnection(http: _Steam(_Clock())),
      });
      expect(registry.supports('steambroadcast'), isTrue);
      final connection = registry.connectionFor('SteamBroadcast');
      expect(connection, isA<SteamBroadcastDanmakuConnection>());
      expect(connection.heartbeatInterval, Duration.zero);
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 1);
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      session.connection.heartbeat();
      expect(steam.log, ['info 7001', 'window c7001:0', 'window c7001:5000']);
      await session.connection.close();
    });

    test(
      "with the entry's broadcast id: getchatinfo, the history skipped, each window's lines on the log's clock",
      () async {
        final clock = _Clock();
        final steam = _Steam(clock, rtt: const Duration(milliseconds: 100), windowLimit: 5)
          ..lines[5500] = [_line('first'), _line('second', steamId: '201', name: 'B')]
          ..lines[6500] = [_line('ːsteamhappyː')]
          ..initialDelays[6000] = 200
          ..lines[6000] = [_line('resynced')];
        final session = _Session(steam, clock: clock);
        await session.connect(_args);
        expect(session.shown, ['DanmakuReady()'], reason: 'connect completes once window 0 answered');
        await steam.idle.future;
        expect(steam.log, [
          'info 7001',
          'window c7001:0',
          'window c7001:5000',
          'window c7001:5500',
          'window c7001:6000',
          'window c7001:6500',
          'window c7001:7000',
        ]);
        expect(session.shown, [
          'DanmakuReady()',
          'chat 200|viewer|first',
          'chat 201|B|second',
          'chat 200|viewer|resynced',
          'chat 200|viewer|ːsteamhappyː',
        ]);
        // Window 0 answers at 200 ms: 5000 is due at 500. Each answer takes
        // 100 ms, so each next window waits 400 ms. The answer for 6000 (at
        // 1600) carries initial_delay 200: 6500 is due at 1800 and the clock
        // counts from there, as the web client does.
        expect(session.waited, [0, 300, 400, 400, 200, 400]);
        expect(session.connection.isConnected, isTrue);
        final info = steam.requests.first;
        expect(info.url, SteamBroadcastDanmakuProtocol.chatInfoUrl(_synthetic, '7001'));
        expect(info.headers, SteamBroadcastApi.roomHeaders(_synthetic, json: true));
        for (final request in steam.requests) {
          expect(request.site, 'steambroadcast');
          expect(request.followRedirects, isFalse);
          expect(request.timeout, const Duration(seconds: 10));
        }
        expect(steam.requests[1].headers, SteamBroadcastDanmakuProtocol.chatHeaders(_synthetic));
        await session.connection.close();
        expect(session.connection.status, DanmakuStatus.idle);
        expect(session.events, hasLength(5), reason: 'nothing after close');
      },
    );

    test('a reader that fell behind asks at once until it caught up', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 5)..slow[5500] = const Duration(milliseconds: 1200);
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      // 5000 due at 300, 5500 at 800 (answered at 2000): 6000 (due 1300)
      // and 6500 (due 1800) at once, 7000 (due 2300) after 300 ms.
      expect(session.waited, [0, 300, 500, 0, 0, 300]);
      await session.connection.close();
    });

    test('up to three missed windows are retried after 500 ms each, silently; later waits add 10 ms each', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 8)
        ..lines[5500] = [_line('after misses')]
        ..script = (request, line, count) =>
            line == 'window c7001:5500' && count <= 3 ? _text(request, _notFoundPage, status: 404) : null;
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      expect(steam.log.skip(2).take(5), [
        'window c7001:5000',
        'window c7001:5500',
        'window c7001:5500',
        'window c7001:5500',
        'window c7001:5500',
      ]);
      expect(session.shown, ['DanmakuReady()', 'chat 200|viewer|after misses']);
      // 5500 answers at 2300 (it was due at 800): 6000 (due 1330) and 6500
      // (due 1830) at once, then 7000 at 2330: the three misses moved the
      // clock by 30 ms.
      expect(session.waited, [0, 300, 500, 500, 500, 500, 0, 0, 30]);
      expect(session.statuses, everyElement(DanmakuStatus.connected));
      await session.connection.close();
    });

    test('the 4th failure in a row reports reconnecting and reads from window 0 again, which joins again', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 8)
        ..lines[5500] = [_line('back')]
        ..script = (request, line, count) => switch (line) {
          'window c7001:5000' => _text(request, _notFoundPage, status: 404),
          // Meanwhile the log went on.
          'window c7001:0' when count == 2 => _json(request, {
            'messages': [_line('history again')],
            'next_request': 5500,
            'initial_delay': 300,
          }),
          _ => null,
        };
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      expect(steam.log, [
        'info 7001',
        'window c7001:0',
        for (var i = 0; i < 4; i++) 'window c7001:5000',
        'window c7001:0',
        'window c7001:5500',
        'window c7001:6000',
        'window c7001:6500',
      ]);
      const notFound = 'NotFound(steambroadcast: chat window 5000: HTTP 404)';
      expect(session.shown, [
        'DanmakuReady()',
        'DanmakuReconnecting(disconnected: $notFound)',
        'DanmakuReady()',
        'chat 200|viewer|back',
      ], reason: "the second window 0's history is not reported either");
      expect(session.statuses, [
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected,
        DanmakuStatus.connected,
      ]);
      expect(session.waited.take(7), [0, 300, 500, 500, 500, 500, 300]);
      await session.connection.close();
    });

    test("from the 8th failure the chat is looked up again: a new broadcast's chat is followed", () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 13)..lines[5500] = [_line('new broadcast')];
      steam.script = (request, line, count) {
        if (line.startsWith('window c7001:') && steam.log.length > 3) {
          // The broadcast ended; the broadcaster started another one.
          steam
            ..current = '7002'
            ..mpd = {'success': 'ready', 'broadcastid': '7002', 'num_viewers': 50};
          return _text(request, _notFoundPage, status: 404);
        }
        return null;
      };
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      expect(steam.log, [
        'info 7001',
        'window c7001:0',
        'window c7001:5000',
        for (var i = 0; i < 4; i++) 'window c7001:5500',
        for (var i = 0; i < 4; i++) 'window c7001:0',
        'mpd',
        'info 7002',
        'window c7002:0',
        'window c7002:5000',
        'window c7002:5500',
        'window c7002:6000',
      ]);
      expect(session.shown, [
        'DanmakuReady()',
        'DanmakuReconnecting(disconnected: NotFound(steambroadcast: chat window 5500: HTTP 404))',
        'viewers onlineViewers 50',
        'DanmakuReady()',
        'chat 200|viewer|new broadcast',
      ]);
      expect(session.waited.take(12), [0, 300, 500, 500, 500, 500, 500, 500, 500, 500, 1000, 300]);
      await session.connection.close();
    });

    test('a stale id from the room entry: getchatinfo refuses it, getbroadcastmpd names the current one', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 1);
      final session = _Session(steam, clock: clock);
      await session.connect(const SteamBroadcastDanmakuArgs(_synthetic, broadcastId: '6999'));
      expect(session.shown, ['viewers onlineViewers 42', 'DanmakuReady()']);
      await steam.idle.future;
      expect(steam.log, ['info 6999', 'mpd', 'info 7001', 'window c7001:0', 'window c7001:5000']);
      expect(steam.requests[1].url, SteamBroadcastApi.mpdUrl(_synthetic));
      expect(steam.requests[1].headers, SteamBroadcastApi.roomHeaders(_synthetic, json: true));
      expect(session.waited, [0, 500, 300]);
      await session.connection.close();
    });

    test('without a broadcast id, getbroadcastmpd first; ids that are not ids are ignored', () async {
      for (final id in [null, '', '0', 'abc']) {
        final clock = _Clock();
        final steam = _Steam(clock, windowLimit: 1);
        final session = _Session(steam, clock: clock);
        await session.connect(SteamBroadcastDanmakuArgs(' $_synthetic ', broadcastId: id));
        await steam.idle.future;
        expect(steam.log, ['mpd', 'info 7001', 'window c7001:0', 'window c7001:5000'], reason: id);
        expect(steam.requests.first.url.queryParameters['steamid'], _synthetic);
        await session.connection.close();
      }
    });

    test(
      'an offline broadcaster, a restricted account or a broadcast for subscribers only ends the connection',
      () async {
        for (final (mpd, detail) in [
          ({'success': 'unavailable'}, 'Offline'),
          ({'success': 'offline'}, 'Offline'),
          ({'success': 'user_restricted'}, 'The account may not broadcast'),
          ({'success': 'missing_subscription'}, 'Subscribers only'),
          ({'success': 'ready', 'broadcastid': '7001', 'num_viewers': 3, 'hls_url': ''}, null),
        ]) {
          final clock = _Clock();
          final steam = _Steam(clock, windowLimit: 0)..mpd = mpd;
          final session = _Session(steam, clock: clock);
          final connected = session.connect(const SteamBroadcastDanmakuArgs(_synthetic));
          if (detail == null) {
            await steam.idle.future;
            expect(steam.log, ['mpd', 'info 7001', 'window c7001:0']);
            await session.connection.close();
            await connected;
            continue;
          }
          await connected;
          expect(session.shown, ['DanmakuClosed(connectionFailed: $detail)'], reason: '$mpd');
          expect(steam.log, ['mpd'], reason: 'no getchatinfo');
          expect(session.connection.status, DanmakuStatus.closed);
        }
      },
    );

    test('failures go on: waiting for the broadcast, then no answer at all; the 16th ends the connection', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 99)
        ..mpd = {'success': 'waiting_for_start', 'retry': 5000}
        ..script = (request, line, count) => line == 'mpd' && count > 6
            ? throw const TransportFailure(SiteIds.steamBroadcast, TransportReason.timeout, 'scripted')
            : null;
      final session = _Session(steam, clock: clock);
      await session.connect(const SteamBroadcastDanmakuArgs(_synthetic));
      expect(session.shown, [
        'DanmakuReconnecting(disconnected: StreamUnavailable(steambroadcast: getbroadcastmpd: no broadcast id (unknown)))',
      ], reason: 'connect completes when the trouble is reported');
      await _until(() => session.connection.status == DanmakuStatus.closed);
      expect(steam.log, List.filled(16, 'mpd'));
      expect(session.shown.skip(1), [
        'DanmakuClosed(reconnectsExhausted: TransportFailure(steambroadcast, timeout: scripted))',
      ]);
      expect(session.waited, [0, for (var i = 0; i < 7; i++) 500, 1000, 2000, 4000, 8000, 8000, 8000, 8000, 8000]);
    });

    test('an answer resets the count; a failing getchatinfo asks getbroadcastmpd again', () async {
      final clock = _Clock();
      final steam = _Steam(clock, windowLimit: 5)
        ..script = (request, line, count) => switch (line) {
          'info 7001' when count <= 2 => _json(request, {'success': 1, 'view_url_template': 'http://x/{0}'}),
          'window c7001:5000' when count <= 3 => _text(request, _notFoundPage, status: 404),
          _ => null,
        };
      final session = _Session(steam, clock: clock);
      await session.connect(_args);
      await steam.idle.future;
      expect(steam.log, [
        'info 7001',
        'mpd',
        'info 7001',
        'mpd',
        'info 7001',
        'window c7001:0',
        for (var i = 0; i < 4; i++) 'window c7001:5000',
        'window c7001:5500',
      ]);
      expect(
        session.shown.where((event) => event is String && event.startsWith('DanmakuReconnecting')),
        isEmpty,
        reason: '5 failures, but never 4 in a row',
      );
      await session.connection.close();
    });

    test('a Steam id that is not one ends at once; other arguments are refused', () async {
      final clock = _Clock();
      final steam = _Steam(clock);
      final session = _Session(steam, clock: clock);
      for (final id in ['', '12345', 'gaben', '76561199799018508x']) {
        await session.connect(SteamBroadcastDanmakuArgs(id, broadcastId: '7001'));
        expect(session.shown.last, 'DanmakuClosed(connectionFailed: Not a Steam id)', reason: id);
      }
      expect(steam.requests, isEmpty);
      await expectLater(session.connect(const TwitcastingDanmakuArgs(channel: 'c', movieId: 1)), throwsArgumentError);
      await expectLater(session.connect(null), throwsArgumentError);
    });

    test('close cancels the pending request; nothing is reported after; a new room ignores the old answers', () async {
      final http = _ManualHttp();
      final session = _Session(http);
      final first = session.connect(_args);
      await _until(() => http.pending.length == 1);
      final stale = http.pending.single;
      expect(stale.request.cancel!.isCancelled, isFalse);
      unawaited(session.connect(const SteamBroadcastDanmakuArgs('76561198843011284', broadcastId: '8001')));
      await _until(() => http.pending.length == 2);
      expect(stale.request.cancel!.isCancelled, isTrue, reason: 'the old room is stopped');
      stale.answer.complete(_json(stale.request, {'success': 1, 'view_url_template': _Steam.template('7001')}));
      await first;
      final current = http.pending[1];
      expect(current.request.url.queryParameters['broadcastid'], '8001');
      current.answer.complete(_json(current.request, {'success': 1, 'view_url_template': _Steam.template('8001')}));
      await _until(() => http.pending.length == 3);
      expect(http.pending[2].request.url.pathSegments[1], 'c8001', reason: "the new room's chat log");
      expect(http.pending.where((pending) => pending.request.url.pathSegments.contains('c7001')), isEmpty);
      await session.connection.close();
      expect(http.pending[2].request.cancel!.isCancelled, isTrue);
      http.pending[2].answer.complete(
        _json(http.pending[2].request, {'messages': <Object?>[], 'next_request': 1, 'initial_delay': 0}),
      );
      await _wait(const Duration(milliseconds: 20));
      expect(session.events, isEmpty, reason: 'no join after close');
      expect(http.pending, hasLength(3));
      expect(session.connection.status, DanmakuStatus.idle);
    });

    test('a local server through IoLiveHttp: the headers as sent, a chat line', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <String, HttpHeaders>{};
      final pending = Completer<void>();
      server.listen((request) async {
        final path = request.uri.path;
        seen[path.startsWith('/chat/') ? 'window ${request.uri.pathSegments.last}' : path] = request.headers;
        final response = request.response..headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        switch (path) {
          case '/broadcast/getchatinfo/':
            response.write(jsonEncode({'success': 1, 'view_url_template': _Steam.template('7001')}));
          case '/chat/c7001/messages/0':
            response.write(jsonEncode({'messages': <Object?>[], 'next_request': 10, 'initial_delay': 1}));
          case '/chat/c7001/messages/10':
            response.write(
              jsonEncode({
                'messages': [_line('from the server')],
                'next_request': 20,
              }),
            );
          default:
            // Never answers; the connection is closed meanwhile.
            if (!pending.isCompleted) pending.complete();
            await pending.future;
            return;
        }
        await response.close();
      });
      final http = _Rerouted(IoLiveHttp(), server.port);
      addTearDown(http.close);
      final connection = SteamBroadcastDanmakuConnection(http: http);
      final events = <DanmakuEvent>[];
      connection.events.listen(events.add);
      await connection.connect(_args);
      await pending.future;
      await connection.close();
      expect(seen.keys, ['/broadcast/getchatinfo/', 'window 0', 'window 10', 'window 20']);
      final info = seen['/broadcast/getchatinfo/']!;
      expect(info.value('x-requested-with'), 'XMLHttpRequest');
      expect(info.value('referer'), 'https://steamcommunity.com/broadcast/watch/$_synthetic');
      expect(info.value('user-agent'), SteamBroadcastApi.userAgent);
      final window = seen['window 10']!;
      expect(window.value('origin'), 'https://steamcommunity.com');
      expect(window.value('accept'), 'application/json, text/javascript, */*; q=0.01');
      expect(window.value('x-requested-with'), isNull);
      expect(events.map(_shown), ['DanmakuReady()', 'chat 200|viewer|from the server']);
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
      headers: request.headers,
      followRedirects: request.followRedirects,
      timeout: request.timeout,
      cancel: request.cancel,
    ),
  );

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() => _inner.close();
}
