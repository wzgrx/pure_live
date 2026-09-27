import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart' show BlockKind;
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';

import 'fake_danmaku.dart';

/// Lets the fake feed's async open and its stream deliveries run.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A source whose opens finish only when the test says so.
final class _GatedSource implements DanmakuSource {
  final List<Completer<void>> gates = [];
  final List<FakeDanmakuFeed> feeds = [];

  @override
  Future<DanmakuFeed> open(
    RoomDetail room, {
    required DanmakuFilterSettings settings,
    required DanmakuScreenBudget budget,
  }) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    final feed = FakeDanmakuFeed(room, settings, budget);
    feeds.add(feed);
    return feed;
  }
}

void main() {
  late FakeDanmakuSource source;
  late RecordingOnVideo overlay;

  setUp(() {
    source = FakeDanmakuSource();
    overlay = RecordingOnVideo();
  });

  RoomDanmaku create({bool enabled = true, DanmakuFilterSettings filters = const DanmakuFilterSettings()}) =>
      RoomDanmaku(source: source, room: liveRoom(), filters: filters, enabled: enabled, overlay: overlay);

  test('F-DM-01: connects only while danmaku is on and keeps the list when turned off', () async {
    final danmaku = create(enabled: false);
    addTearDown(danmaku.dispose);
    await _settle();
    expect(source.feeds, isEmpty);
    expect(danmaku.connection.value, ChatConnection.off);

    danmaku.setEnabled(enabled: true);
    await _settle();
    expect(source.feeds, hasLength(1));
    expect(danmaku.connection.value, ChatConnection.connecting);
    source.feeds.single.emit(batchOf([chatLine('a', 'hello')]));
    await _settle();
    expect(danmaku.chat.length, 1);

    danmaku.setEnabled(enabled: false);
    await _settle();
    expect(source.feeds.single.closed, isTrue);
    expect(danmaku.connection.value, ChatConnection.off);
    expect(danmaku.chat.length, 1, reason: 'disconnecting keeps what was shown');
  });

  test('a batch fills the list in arrival order, the board, the audience and the notices', () async {
    final danmaku = create();
    addTearDown(danmaku.dispose);
    await _settle();
    final first = chatLine('a', 'one');
    final gift = giftLine('b', '小心心', count: 3);
    final second = chatLine('c', 'two');
    source.feeds.single.emit(
      batchOf(
        [first, second],
        gifts: [gift],
        superChats: [superChat('sc1', 'd', '醒目', end: DateTime.now().add(const Duration(minutes: 5)))],
        online: {AudienceKind.popularity: 1200},
        system: [
          const DanmakuSystem(room: 'douyu:1', session: 1, receivedAt: 1, status: DanmakuStatus.connected),
          const DanmakuSystem(room: 'douyu:1', session: 1, receivedAt: 2, status: DanmakuStatus.replayMode),
        ],
      ),
    );
    await _settle();
    expect(danmaku.chat.lines, [first, gift, second]);
    expect(danmaku.superChats.value.single.id, 'sc1');
    expect(danmaku.audience.value, {AudienceKind.popularity: 1200});
    expect(headlineAudience(danmaku.audience.value), (AudienceKind.popularity, 1200));
    expect(danmaku.connection.value, ChatConnection.connected);
    expect(danmaku.notice.value?.status, DanmakuStatus.replayMode);

    // LST-6: the online figure wins over heat once it arrives.
    source.feeds.single.emit(batchOf(const [], online: {AudienceKind.online: 35}));
    await _settle();
    expect(headlineAudience(danmaku.audience.value), (AudienceKind.online, 35));
  });

  test('LST-1: the list keeps the newest 500 lines', () async {
    final danmaku = create();
    addTearDown(danmaku.dispose);
    await _settle();
    for (var i = 0; i < 6; i++) {
      source.feeds.single.emit(batchOf([for (var j = 0; j < 100; j++) chatLine('u', 'm${i * 100 + j}')]));
    }
    await _settle();
    expect(danmaku.chat.length, 500);
    expect((danmaku.chat[0] as DanmakuChat).text, 'm100');
    expect((danmaku.chat[499] as DanmakuChat).text, 'm599');
  });

  test('REN-7: the overlay gets chat only while playing; local lines always', () async {
    final danmaku = create();
    addTearDown(danmaku.dispose);
    await _settle();
    expect(overlay.pauses, contains(pausedForVideo));

    source.feeds.single.emit(batchOf([chatLine('a', 'while buffering'), chatLine('me', 'local', local: true)]));
    await _settle();
    expect(overlay.items.map((item) => item.text), ['local']);
    expect(overlay.items.single.isLocal, isTrue);

    danmaku.setPlaying(playing: true);
    expect(overlay.pauses, isEmpty);
    source.feeds.single.emit(batchOf([chatLine('a', 'playing')]));
    await _settle();
    expect(overlay.items.map((item) => item.text), ['local', 'playing']);
    expect(chatOfHit(null), isNull);
    expect(onVideoItem(chatLine('a', 'x')).data, isA<DanmakuChat>());
  });

  test('SMP-3: hiding danmaku on the video clears it and stops screen sampling; the list keeps going', () async {
    final danmaku = create()..setPlaying(playing: true);
    addTearDown(danmaku.dispose);
    await _settle();
    final feed = source.feeds.single;
    expect(feed.initialBudget.perSecond, greaterThan(0));

    danmaku.setOverlayVisible(visible: false);
    expect(feed.budgets.last.perSecond, 0);
    expect(overlay.clears, greaterThan(0));
    feed.emit(batchOf([chatLine('a', 'hidden')]));
    await _settle();
    expect(overlay.items, isEmpty);
    expect(danmaku.chat.length, 1);

    danmaku.setOverlayVisible(visible: true);
    expect(feed.budgets.last.perSecond, greaterThan(0));
  });

  test('FLT-2: blocking applies at once to the list and to the worker, ignoring case', () async {
    final danmaku = create();
    addTearDown(danmaku.dispose);
    await _settle();
    source.feeds.single.emit(
      batchOf([chatLine('Spammer', '加群领福利'), chatLine('viewer', '主播好'), chatLine('other', 'BUY now')]),
    );
    await _settle();
    final feed = source.feeds.single;

    danmaku.block(BlockKind.user, 'spammer');
    expect(danmaku.chat.lines.map((line) => (line as DanmakuChat).text), ['主播好', 'BUY now']);
    expect(feed.current.blockedUsers, ['spammer']);

    danmaku.block(BlockKind.keyword, 'buy');
    expect(danmaku.chat.lines.map((line) => (line as DanmakuChat).text), ['主播好']);
    expect(feed.current.blockedWords, ['buy']);

    // The store's list arriving later with the same rules changes nothing.
    final updates = feed.settings.length;
    danmaku
      ..block(BlockKind.user, ' SPAMMER ')
      ..setFilters(danmaku.filters);
    expect(feed.settings.length, updates + 1);
    expect(danmaku.chat.length, 1);
  });

  test('F-LI-01: local lines go to the list and the video even while paused, never filtered', () async {
    final danmaku = create(filters: const DanmakuFilterSettings(blockedWords: ['加油']));
    addTearDown(danmaku.dispose);
    await _settle();
    expect(danmaku.sendLocal('  主播加油  '), isTrue);
    final line = danmaku.chat.lines.single as DanmakuChat;
    expect(line.text, '主播加油');
    expect(line.isLocal, isTrue);
    expect(overlay.items.map((item) => item.text), ['主播加油'], reason: 'REN-7: local lines always show');
    expect(danmaku.sendLocal('   '), isFalse);
    expect(danmaku.sendLocal('字' * 150), isTrue);
    expect((danmaku.chat.lines.last as DanmakuChat).text.length, RoomDanmaku.localMaxLength);
  });

  test('FLT-2: a block also takes the matching lines off the video at once', () async {
    final danmaku = create()..setPlaying(playing: true);
    addTearDown(danmaku.dispose);
    await _settle();
    source.feeds.single.emit(batchOf([chatLine('Spammer', '加群领福利'), chatLine('viewer', '主播好')]));
    await _settle();
    expect(overlay.items.map((item) => item.text), ['加群领福利', '主播好']);

    danmaku.block(BlockKind.keyword, '加群');
    expect(overlay.items.map((item) => item.text), ['主播好']);
  });

  test('INV-ROOM-11: a connection that opens after a reconnect started is closed, not used', () async {
    final gated = _GatedSource();
    final danmaku = RoomDanmaku(
      source: gated,
      room: liveRoom(),
      filters: const DanmakuFilterSettings(),
      enabled: true,
      overlay: overlay,
    );
    addTearDown(danmaku.dispose);
    await _settle();
    expect(gated.gates, hasLength(1));
    unawaited(danmaku.reconnect());
    await _settle();
    expect(gated.gates, hasLength(2));

    gated.gates.first.complete();
    await _settle();
    expect(gated.feeds.first.closed, isTrue, reason: 'the stale open is closed');
    gated.gates.last.complete();
    await _settle();
    gated.feeds.last.emit(batchOf([chatLine('a', 'current')]));
    await _settle();
    expect(danmaku.chat.length, 1);
    expect(gated.feeds.last.closed, isFalse);
  });

  testWidgets('LST-5: super chats are deduplicated and leave at their end time', (tester) async {
    var now = DateTime(2026, 9, 27, 20);
    final danmaku = RoomDanmaku(
      source: source,
      room: liveRoom(),
      filters: const DanmakuFilterSettings(),
      enabled: true,
      now: () => now,
    );
    await tester.pump();
    final soon = superChat('a', 'u1', '第一条', end: now.add(const Duration(seconds: 30)));
    final later = superChat('b', 'u2', '第二条', end: now.add(const Duration(minutes: 2)));
    source.feeds.single.emit(batchOf(const [], superChats: [later, soon, soon]));
    await tester.pump();
    expect(danmaku.superChats.value.map((chat) => chat.id), ['a', 'b']);

    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    expect(danmaku.superChats.value.map((chat) => chat.id), ['b']);

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(danmaku.superChats.value, isEmpty);
    unawaited(danmaku.dispose());
    await tester.pump();
  });

  testWidgets('LST-7: the same notice shows once in 3 s', (tester) async {
    var now = DateTime(2026, 9, 27, 20);
    final danmaku = RoomDanmaku(
      source: source,
      room: liveRoom(),
      filters: const DanmakuFilterSettings(),
      enabled: true,
      now: () => now,
    );
    await tester.pump();
    var shown = 0;
    danmaku.notice.addListener(() => shown++);
    const notice = DanmakuSystem(room: 'douyu:1', session: 1, receivedAt: 1, status: DanmakuStatus.timeout);
    source.feeds.single.emit(batchOf(const [], system: [notice]));
    await tester.pump();
    danmaku.notice.value = null;
    now = now.add(const Duration(seconds: 1));
    source.feeds.single.emit(batchOf(const [], system: [notice]));
    await tester.pump();
    expect(shown, 2, reason: 'shown once, then cleared; the repeat within 3 s is dropped');
    expect(danmaku.connection.value, ChatConnection.closed);
    unawaited(danmaku.dispose());
    await tester.pump();
  });
}
