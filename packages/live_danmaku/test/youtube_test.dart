import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _start = DateTime.utc(2026, 9, 28);

void main() {
  final fixture = DanmakuFixture.load('youtube', 'S06-live');
  final next = fixture.incoming.firstWhere((f) => f.url!.path.endsWith('/next'));
  final polls = [
    for (final f in fixture.incoming)
      if (f.url!.path.endsWith('/get_live_chat')) f,
  ];

  group('protocol (§7)', () {
    test('the next answer names the first continuation', () {
      expect(YouTubeChatProtocol.initialContinuation(utf8.decode(next.bytes)), isNotEmpty);
      expect(YouTubeChatProtocol.initialContinuation('{"contents":{}}'), isNull);
    });

    test('a chat answer: text lines with ids, authors and times; the next continuation and wait', () {
      final first = YouTubeChatProtocol.parse(utf8.decode(polls.first.bytes), context: fixture.context(polls.first));
      final chats = first.events.whereType<DanmakuChat>().toList();
      expect(chats, isNotEmpty);
      expect(chats.every((c) => c.id!.startsWith('youtube:') && c.userName.startsWith('@')), isTrue);
      expect(chats.every((c) => c.sentAt != null && c.text.isNotEmpty), isTrue);
      expect(first.continuation, isNotEmpty);
      expect(first.delay, const Duration(seconds: 10));
    });

    test('paid messages become chat lines with the amount; emoji runs use their shortcut', () {
      final body = jsonEncode({
        'continuationContents': {
          'liveChatContinuation': {
            'actions': [
              {
                'addChatItemAction': {
                  'item': {
                    'liveChatPaidMessageRenderer': {
                      'id': 'p1',
                      'timestampUsec': '1790541124385000',
                      'authorName': {'simpleText': '@fan'},
                      'purchaseAmountText': {'simpleText': r'$5.00'},
                      'message': {
                        'runs': [
                          {'text': 'gg '},
                          {
                            'emoji': {
                              'emojiId': 'x',
                              'shortcuts': [':fire:'],
                            },
                          },
                        ],
                      },
                    },
                  },
                },
              },
            ],
          },
        },
      });
      final poll = YouTubeChatProtocol.parse(body, context: fixture.context(polls.first));
      final chat = poll.events.single as DanmakuChat;
      expect(chat.text, r'$5.00 gg :fire:');
      expect(chat.id, 'youtube:p1');
      expect(poll.continuation, isNull, reason: 'no continuation: the chat ended');
    });
  });

  group('connector over the recording (fixtures/youtube/danmaku/S06-live)', () {
    test('history is not emitted; later answers are; the wait is capped', () {
      fakeAsync((async) {
        var index = 0;
        final http = FakeHttp((request) async {
          final frame = request.url.path.endsWith('/next') ? next : polls[index++ % polls.length];
          return LiveResponse(status: 200, bytes: frame.bytes, url: request.url);
        });
        final connector = YouTubeChatConnector(
          detail: fixture.detail,
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        var joined = false;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isTrue);
        expect(events.whereType<DanmakuChat>(), isEmpty, reason: 'the first answer is history');
        for (var i = 1; i < polls.length; i++) {
          async.elapse(YouTubeChatConnector.maximumDelay);
        }
        final expected = [
          for (final poll in polls.skip(1))
            ...YouTubeChatProtocol.parse(utf8.decode(poll.bytes), context: fixture.context(poll)).events,
        ];
        expect(events.whereType<DanmakuChat>().length, expected.length);
        expect(http.requests.first.site, 'youtube');
        unawaited(connector.close());
        async.flushMicrotasks();
      });
    });

    test('a room without a live video ends at once', () {
      fakeAsync((async) {
        final connector = YouTubeChatConnector(
          detail: RoomDetail(
            card: RoomCard(
              ref: RoomRef('youtube', 'UCSF_aFGIIIoWY30GVV19TKA'),
              title: '',
              anchorName: '',
              state: LiveState.offline,
            ),
            link: Uri.parse('https://example.test'),
            danmakuKeys: const {'channelId': 'UCSF_aFGIIIoWY30GVV19TKA'},
          ),
          transport: FakeTransport(),
          clock: FakeClock(async, _start),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'offline');
      });
    });
  });
}
