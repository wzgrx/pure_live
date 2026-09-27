import 'package:fake_async/fake_async.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _room = 'douyu:1';
final _start = DateTime.utc(2026, 9, 27, 12);

DanmakuChat _chat(
  String text, {
  String? id,
  int session = 1,
  String room = _room,
  bool local = false,
  String name = 'n',
}) => DanmakuChat(room: room, session: session, receivedAt: 0, id: id, userName: name, text: text, isLocal: local);

void main() {
  (DanmakuPipeline, List<DanmakuBatch>, FakeClock) setUp(
    FakeAsync async, {
    DanmakuFilterSettings settings = const DanmakuFilterSettings(),
    DanmakuScreenBudget budget = const DanmakuScreenBudget(1000),
  }) {
    final batches = <DanmakuBatch>[];
    final clock = FakeClock(async, _start);
    final pipeline = DanmakuPipeline(
      room: _room,
      session: 1,
      onBatch: batches.add,
      settings: settings,
      budget: budget,
      clock: clock,
    );
    return (pipeline, batches, clock);
  }

  test('CONN-2: the first message after a quiet spell goes out after 16 ms; then at most every 64 ms', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      pipeline.add(_chat('a', id: 'a'));
      async.elapse(const Duration(milliseconds: 15));
      expect(batches, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(batches.single.list.map((chat) => chat.text), ['a']);
      // The next batch waits for 64 ms after the previous one (16 + 64).
      pipeline.add(_chat('b', id: 'b'));
      async.elapse(const Duration(milliseconds: 63));
      expect(batches, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(batches, hasLength(2));
      expect(batches.last.list.single.text, 'b');
    });
  });

  test('CONN-2: at most 200 list lines per batch, oldest dropped and counted', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      for (var i = 0; i < 250; i++) {
        pipeline.add(_chat('m$i', id: '$i'));
      }
      async.elapse(const Duration(milliseconds: 64));
      final batch = batches.single;
      expect(batch.list, hasLength(200));
      expect(batch.list.first.text, 'm50');
      expect(batch.dropped, 50);
    });
  });

  test('SMP-1: screen candidates follow the budget, the list keeps everything', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async, budget: const DanmakuScreenBudget(30));
      for (var second = 0; second < 5; second++) {
        for (var i = 0; i < 200; i++) {
          pipeline.add(_chat('s$second-$i', id: '$second-$i'));
          async.elapse(const Duration(milliseconds: 5));
        }
      }
      async.elapse(const Duration(milliseconds: 100));
      final listed = batches.fold<int>(0, (sum, batch) => sum + batch.list.length);
      final screened = batches.fold<int>(0, (sum, batch) => sum + batch.screen.length);
      expect(listed, 1000);
      // 5 s at 30 per second, plus at most a quarter second of carried budget.
      expect(screened, inInclusiveRange(145, 160));
    });
  });

  test('local messages skip filters and sampling', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(
        async,
        settings: const DanmakuFilterSettings(blockedWords: ['x']),
        budget: DanmakuScreenBudget.none,
      );
      pipeline.add(_chat('x', local: true));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.single.list.single.text, 'x');
      expect(batches.single.screen.single.text, 'x');
    });
  });

  test('FLT-6/FLT-2: new settings apply at once and purge pending matches', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      pipeline
        ..add(_chat('keep', id: '1'))
        ..add(_chat('drop me', id: '2', name: 'Spammer'))
        ..settings = const DanmakuFilterSettings(blockedUsers: ['spammer'])
        ..add(_chat('later', id: '3', name: 'SPAMMER'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.single.list.map((chat) => chat.text), ['keep']);
    });
  });

  test('FLT-5: bots only hidden when the user turns the filter on', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      DanmakuChat bot(String id) =>
          DanmakuChat(room: _room, session: 1, receivedAt: 0, id: id, userName: 'n', text: 't$id', suspectedBot: true);
      pipeline
        ..add(bot('1'))
        ..settings = const DanmakuFilterSettings(hideSuspectedBots: true)
        ..add(bot('2'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.single.list.map((chat) => chat.id), ['1']);
    });
  });

  test('merge repeats and similarity are off by default (REG-DANMAKU-007) and work when on', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      pipeline
        ..add(_chat('666', id: '1'))
        ..add(_chat('666', id: '2'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.last.list, hasLength(2));
      pipeline
        ..settings = const DanmakuFilterSettings(mergeRepeats: true, similarity: true)
        ..add(_chat('主播好厉害啊', id: '3'))
        ..add(_chat('主播好厉害啊 ', id: '4'))
        ..add(_chat('主播好厉害', id: '5'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.last.list.map((chat) => chat.id), ['3']);
    });
  });

  test('online keeps the latest per kind; super chats are deduplicated; system passes', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      DanmakuOnline online(AudienceKind kind, int value) =>
          DanmakuOnline(room: _room, session: 1, receivedAt: 0, audience: kind, value: value);
      DanmakuSuperChat sc(String id) => DanmakuSuperChat(
        room: _room,
        session: 1,
        receivedAt: 0,
        id: id,
        userName: 'u',
        text: 't',
        price: 30,
        startAt: _start,
        endAt: _start,
      );
      pipeline
        ..add(online(AudienceKind.popularity, 1))
        ..add(online(AudienceKind.popularity, 2))
        ..add(online(AudienceKind.cumulative, 9))
        ..add(sc('a'))
        ..add(sc('a'))
        ..add(sc('b'))
        ..add(const DanmakuSystem(room: _room, session: 1, receivedAt: 0, status: DanmakuStatus.connected));
      async.elapse(const Duration(milliseconds: 64));
      final batch = batches.single;
      expect(batch.online, {AudienceKind.popularity: 2, AudienceKind.cumulative: 9});
      expect(batch.superChats.map((chat) => chat.id), ['a', 'b']);
      expect(batch.system.single.status, DanmakuStatus.connected);
      expect(batch.list, isEmpty);
    });
  });

  test("CONN-4: another session's or room's events never enter the batch", () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      pipeline
        ..add(_chat('late', session: 0))
        ..add(_chat('other room', room: 'douyu:2'))
        ..add(_chat('mine', id: 'm'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.single.list.map((chat) => chat.text), ['mine']);
      expect(batches.single.room, _room);
      expect(batches.single.session, 1);
    });
  });

  test('clear forgets the gate; close flushes and stops', () {
    fakeAsync((async) {
      final (pipeline, batches, _) = setUp(async);
      pipeline.add(_chat('a', id: 'x'));
      async.elapse(const Duration(milliseconds: 64));
      pipeline
        ..add(_chat('a', id: 'x'))
        ..clear()
        ..add(_chat('a', id: 'x'))
        ..close()
        ..add(_chat('after', id: 'y'));
      async.elapse(const Duration(milliseconds: 64));
      expect(batches.map((batch) => batch.list.length), [1, 1]);
    });
  });
}
