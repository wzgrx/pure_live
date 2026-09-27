import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _context = DecodeContext(
  room: 'steambroadcast:76561199485215572',
  session: 1,
  receivedAt: 1,
  now: DateTime.utc(2026, 9, 27),
);
final _start = DateTime.utc(2026, 9, 27);

LiveResponse _json(Object body, Uri url, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(jsonEncode(body)), url: url);

void main() {
  group('protocol (§7)', () {
    test('URLs and headers', () {
      expect(
        SteamBroadcastProtocol.broadcastUrl('76561199485215572').toString(),
        'https://steamcommunity.com/broadcast/getbroadcastmpd/?broadcastid=0&steamid=76561199485215572&viewertoken=0&sessionid',
      );
      expect(SteamBroadcastProtocol.chatInfoUrl('1', '2').queryParameters['broadcastid'], '2');
      expect(
        SteamBroadcastProtocol.messagesUrl('https://c.test/chat/9/messages/{0}?chat_origin=x', 42).toString(),
        'https://c.test/chat/9/messages/42?chat_origin=x',
      );
      expect(SteamBroadcastProtocol.headers('1')['Referer'], 'https://steamcommunity.com/broadcast/watch/1');
    });

    test('broadcast id only when ready; the chat template must hold {0}', () {
      expect(SteamBroadcastProtocol.broadcastId('{"success":"ready","broadcastid":"77"}'), '77');
      expect(SteamBroadcastProtocol.broadcastId('{"success":"unavailable","broadcastid":0}'), isNull);
      expect(() => SteamBroadcastProtocol.chatTemplate('{"success":1,"view_url_template":"x"}'), throwsFormatException);
    });

    test('a window: chat lines, ids by window time and position, empty text dropped', () {
      final poll = SteamBroadcastProtocol.parse(
        jsonEncode({
          'messages': [
            {'steamid': '1', 'persona_name': 'A', 'msg': ' hi '},
            {'steamid': '2', 'persona_name': '', 'msg': 'ːsteamhappyː'},
            {'steamid': '3', 'persona_name': 'C', 'msg': ' '},
          ],
          'next_request': 1500,
        }),
        time: 1000,
        context: _context,
      );
      final chats = poll.events.cast<DanmakuChat>();
      expect(chats.map((c) => c.text), ['hi', 'ːsteamhappyː']);
      expect(chats.map((c) => c.id), ['steambroadcast:1000:0', 'steambroadcast:1000:1']);
      expect(chats.last.userName, 'Steam');
      expect(poll.next, 1500);
      expect(poll.initialDelay, isNull);
      expect(() => SteamBroadcastProtocol.parse('{"messages":[]}', time: 0, context: _context), throwsFormatException);
    });
  });

  group('recorded session (fixtures/steambroadcast/danmaku/S07-live)', () {
    final fixture = DanmakuFixture.load('steambroadcast', 'S07-live');
    final frames = fixture.incoming.toList();

    test('manifest → chat info → window 0 with history and initial_delay', () {
      final broadcast = SteamBroadcastProtocol.broadcastId(frames[0].text!);
      expect(broadcast, isNotNull);
      expect(frames[1].url!.queryParameters['broadcastid'], broadcast);
      final template = SteamBroadcastProtocol.chatTemplate(frames[1].text!);
      expect(frames[2].url, SteamBroadcastProtocol.messagesUrl(template, 0));
      final history = SteamBroadcastProtocol.parse(frames[2].text!, time: 0, context: fixture.context(frames[2]));
      expect(history.events, hasLength(50));
      expect(history.initialDelay, isNotNull);
      expect(frames[3].url, SteamBroadcastProtocol.messagesUrl(template, history.next));
    });

    test('each later window is the previous next_request, read along the log clock', () {
      final windows = frames.skip(2).where((f) => f.text!.trimLeft().startsWith('{')).toList();
      var expected = SteamBroadcastProtocol.parse(windows.first.text!, time: 0, context: _context).next;
      for (final frame in windows.skip(1)) {
        final time = int.parse(frame.url!.pathSegments.last);
        expect(time, expected);
        expected = SteamBroadcastProtocol.parse(frame.text!, time: time, context: _context).next;
      }
      final start = int.parse(windows[1].url!.pathSegments.last);
      final end = int.parse(windows.last.url!.pathSegments.last);
      final elapsed = windows.last.millis - windows[1].millis;
      expect((end - start - elapsed).abs(), lessThan(2000), reason: 'window time follows wall time');
    });
  });

  group('connector', () {
    test('history is skipped, new windows are emitted, the web clock paces requests', () {
      fakeAsync((async) {
        final times = <int>[];
        final http = FakeHttp((request) async {
          final url = request.url;
          if (url.path.endsWith('getbroadcastmpd/')) return _json({'success': 'ready', 'broadcastid': '7'}, url);
          if (url.path.endsWith('getchatinfo/')) {
            return _json({'success': 1, 'view_url_template': 'https://c.test/chat/1/messages/{0}?o=1'}, url);
          }
          final time = int.parse(url.pathSegments.last);
          times.add(time);
          if (time == 0) {
            return _json({
              'messages': [
                {'steamid': '1', 'persona_name': 'old', 'msg': 'history'},
              ],
              'next_request': 10000,
              'initial_delay': 300,
            }, url);
          }
          return _json({
            'messages': [
              {'steamid': '2', 'persona_name': 'new', 'msg': 'at $time'},
            ],
            'next_request': time + 500,
          }, url);
        });
        final connector = SteamBroadcastConnector(
          detail: RoomDetail(
            card: RoomCard(ref: RoomRef('steambroadcast', '1'), title: '', anchorName: '', state: LiveState.live),
            link: Uri.parse('https://example.test'),
            danmakuKeys: const {'steamid': '76561199485215572'},
          ),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        var joined = false;
        unawaited(connector.connect().then((value) => joined = value));
        async.elapse(const Duration(milliseconds: 250));
        expect(joined, isTrue);
        expect(times, [0]);
        async.elapse(const Duration(milliseconds: 100));
        expect(times, [0, 10000], reason: 'window 10000 is due after initial_delay');
        async.elapse(const Duration(milliseconds: 1000));
        expect(times, [0, 10000, 10500, 11000]);
        final chats = events.whereType<DanmakuChat>().map((c) => c.text).toList();
        expect(chats, ['at 10000', 'at 10500', 'at 11000']);
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('not broadcasting ends at once', () {
      fakeAsync((async) {
        final http = FakeHttp((request) async => _json({'success': 'unavailable'}, request.url));
        final connector = SteamBroadcastConnector(
          detail: RoomDetail(
            card: RoomCard(ref: RoomRef('steambroadcast', '1'), title: '', anchorName: '', state: LiveState.live),
            link: Uri.parse('https://example.test'),
            danmakuKeys: const {'steamid': '76561199485215572'},
          ),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args, ['offline']);
      });
    });
  });
}
