import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/room/playback.dart';

import 'danmaku/fake_danmaku.dart';
import 'fakes.dart';
import 'multiview_fakes.dart';

/// Invariants of spec/modules/multiview.md §11 with fake engines.
void main() {
  late LiveStore store;
  late FakeSite site;
  late List<FakeEngine> engines;
  late FakeDanmakuSource chats;
  late MemoryRoomVolumes volumes;
  late ProviderContainer container;

  ProviderContainer makeContainer([List<Override> extra = const []]) =>
      ProviderContainer(
          overrides: [
            storeProvider.overrideWithValue(store),
            sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
            engineFactoryProvider.overrideWithValue(() {
              final engine = FakeEngine();
              engines.add(engine);
              return engine;
            }),
            danmakuSourceProvider.overrideWithValue(chats),
            roomVolumesProvider.overrideWithValue(volumes),
            ...extra,
          ],
        )
        // Keep the auto-dispose controller alive for the test.
        ..listen(multiviewProvider, (_, _) {});

  setUp(() async {
    store = await LiveStore.inMemory();
    site = FakeSite('douyu', offline: {'off'});
    engines = [];
    chats = FakeDanmakuSource();
    volumes = MemoryRoomVolumes();
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  MultiviewController controller() => container.read(multiviewProvider.notifier);
  MultiviewState state() => container.read(multiviewProvider);
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));
  PlaybackSession session(int index) => state().cells[index].session!;

  test('only the focus cell makes sound; mute-all silences it too (INV-MULTI-01, AUD-3)', () async {
    volumes.stored[RoomRef('douyu', '2')] = 0.8;
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(1, RoomRef('douyu', '2'));
    await settle();
    expect(state().audioFocus, 1, reason: 'a newly playing cell takes the focus (AUD-2)');
    expect(engines.map((e) => e.volume), [0, 0.8], reason: 'the focus plays at its room volume (CEL-9)');

    controller().setFocus(0);
    await settle();
    expect(engines.map((e) => e.volume), [state().cells[0].volume, 0]);

    controller().toggleMuteAll();
    await settle();
    expect(engines.every((e) => e.volume == 0), isTrue);
    controller().setFocus(1);
    await settle();
    expect(state().audioFocus, 1, reason: 'focus still moves while muted');
    expect(engines.every((e) => e.volume == 0), isTrue);
  });

  test('a known offline room creates no decoder and asks for no streams (INV-MULTI-05)', () async {
    await controller().assign(0, RoomRef('douyu', 'off'));
    expect(state().cells[0].status, CellStatus.offline);
    expect(engines, isEmpty);
    expect(site.streamRequests, isEmpty);
  });

  test('a late result never lands in a reassigned cell (INV-MULTI-03)', () async {
    final first = controller().assign(0, RoomRef('douyu', 'slow'));
    final second = controller().assign(0, RoomRef('douyu', 'fast'));
    await Future.wait([first, second]);
    await settle();
    expect(state().cells[0].room, RoomRef('douyu', 'fast'));
    expect(state().cells[0].status, CellStatus.playing);
    final live = engines.where((e) => !e.disposed).length;
    expect(live, 1, reason: 'the superseded session was released');
  });

  test('closing the focus cell moves the focus to the first playing cell and empties at once (CEL-7)', () async {
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(2, RoomRef('douyu', '3'));
    await settle();
    expect(state().audioFocus, 2);
    controller().close(2);
    expect(state().cells[2].status, CellStatus.empty);
    expect(state().audioFocus, 0);
    await settle();
    expect(engines[1].disposed, isTrue);
  });

  test('shrinking the layout keeps the playing cells and releases the tail (LYT-3)', () async {
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(3, RoomRef('douyu', '4'));
    await settle();
    final kept = state().cells[0].session;
    controller().setLayout(MultiviewLayout.two);
    await settle();
    expect(state().cells, hasLength(2));
    expect(state().cells[0].session, same(kept), reason: 'no rebuild of the playing cell');
    expect(engines[1].disposed, isTrue);
  });

  test('the pick target moves to the next free cell after an assignment (CEL-4)', () async {
    controller().setLayout(MultiviewLayout.four);
    unawaited(controller().assign(0, RoomRef('douyu', '1')));
    expect(state().target, 1);
    await settle();
  });

  test('1+N: a room for a small cell starts muted and leaves the sound with the big cell (AUD-2)', () async {
    controller().setLayout(MultiviewLayout.onePlusN);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(2, RoomRef('douyu', '3'));
    await settle();
    expect(state().big, 0);
    expect(state().audioFocus, 0);
    expect(engines[1].volume, 0);
    controller().setFocus(2);
    await settle();
    expect(state().big, 2, reason: 'a promotion moves the big cell and the sound');
    expect(engines[1].volume, state().cells[2].volume);
    expect(engines[0].volume, 0);
  });

  group('volume (CEL-9)', () {
    test('a cell starts at its room volume, else the default; changes are heard and stored', () async {
      volumes.stored[RoomRef('douyu', '1')] = 0.3;
      controller().setLayout(MultiviewLayout.two);
      await controller().assign(0, RoomRef('douyu', '1'));
      await controller().assign(1, RoomRef('douyu', '2'));
      await settle();
      expect(state().cells[0].volume, 0.3);
      // Tests run as a touch platform: the phone default.
      expect(state().cells[1].volume, store.settings.get(Settings.defaultMobileVolume));

      controller().setVolume(1, 0.7, persist: false);
      await settle();
      expect(engines[1].volume, 0.7, reason: 'the focus hears it while dragging');
      expect(volumes.stored.containsKey(RoomRef('douyu', '2')), isFalse);
      controller().setVolume(1, 0.6);
      await settle();
      expect(volumes.stored[RoomRef('douyu', '2')], 0.6, reason: 'stored when the drag ends');

      controller().setVolume(0, 0.9);
      await settle();
      expect(engines[0].volume, 0, reason: 'a cell without the focus stays silent');
      expect(state().cells[0].volume, 0.9);

      controller()
        ..toggleMuteAll()
        ..setVolume(1, 0.4);
      await settle();
      expect(engines[1].volume, 0, reason: 'mute-all keeps the value silent (AUD-3)');
      controller().toggleMuteAll();
      await settle();
      expect(engines[1].volume, 0.4);
    });
  });

  group('pause (CEL-6)', () {
    test('pausing keeps the cell playing in status and records the intent; resuming plays', () async {
      await controller().assign(0, RoomRef('douyu', '1'));
      await settle();
      controller().setPaused(0, paused: true);
      await settle();
      expect(state().cells[0].status, CellStatus.playing);
      expect(state().cells[0].paused, isTrue);
      expect(session(0).state.phase, PlaybackPhase.paused);
      expect(engines[0].commands.last, 'pause');

      controller().togglePauseSelected();
      await settle();
      expect(state().cells[0].paused, isFalse);
      expect(session(0).state.wantsPlay, isTrue);
      expect(engines[0].commands.last, 'play');
    });

    test('a pause during the open still holds when the open finishes', () async {
      final assigning = controller().assign(0, RoomRef('douyu', '1'));
      while (state().cells[0].status != CellStatus.playing) {
        await Future<void>.delayed(Duration.zero);
      }
      controller().setPaused(0, paused: true);
      await assigning;
      await settle();
      expect(state().cells[0].paused, isTrue);
      expect(session(0).state.wantsPlay, isFalse);
      expect(session(0).state.phase, PlaybackPhase.paused);
    });

    test('refresh assigns the same room with a new session (REC-MV-5)', () async {
      await controller().assign(0, RoomRef('douyu', '1'));
      await settle();
      final old = session(0);
      await controller().refresh(0);
      await settle();
      expect(state().cells[0].room, RoomRef('douyu', '1'));
      expect(session(0), isNot(same(old)));
      expect(engines.first.disposed, isTrue);
    });
  });

  group('danmaku (DM-1, DM-2, DM-4)', () {
    test('off by default; on connects only the selected cell, and follows the focus', () async {
      controller().setLayout(MultiviewLayout.two);
      await controller().assign(0, RoomRef('douyu', '1'));
      await controller().assign(1, RoomRef('douyu', '2'));
      await settle();
      expect(chats.feeds, isEmpty, reason: 'the page switch is off by default (DM-1)');

      controller().setDanmaku(enabled: true);
      await settle();
      expect(chats.feeds.map((f) => f.room.ref.roomId), ['2'], reason: 'the focus cell only');

      controller().setFocus(0);
      await settle();
      expect(chats.feeds.first.closed, isTrue, reason: 'at most one connection');
      expect(chats.feeds.map((f) => f.room.ref.roomId), ['2', '1']);
      expect(controller().danmaku?.room.ref, RoomRef('douyu', '1'));

      controller().close(0);
      await settle();
      expect(chats.feeds.last.closed, isFalse, reason: 'the focus moved to the other playing cell');
      expect(chats.feeds.last.room.ref.roomId, '2');

      controller().toggleDanmaku();
      await settle();
      expect(chats.feeds.every((f) => f.closed), isTrue);
      expect(controller().danmaku, isNull);
    });

    test('the same room keeps its connection when its cell is refreshed', () async {
      await controller().assign(0, RoomRef('douyu', '1'));
      controller().setDanmaku(enabled: true);
      await settle();
      await controller().refresh(0);
      await settle();
      expect(chats.feeds, hasLength(1));
      expect(chats.feeds.single.closed, isFalse);
    });

    test('the global "显示弹幕" switch off means no connection (F-DM-01)', () async {
      container.read(danmakuPrefsProvider.notifier).setEnabled(enabled: false);
      await controller().assign(0, RoomRef('douyu', '1'));
      controller().setDanmaku(enabled: true);
      await settle();
      expect(chats.feeds, isEmpty);
      container.read(danmakuPrefsProvider.notifier).setEnabled(enabled: true);
      await settle();
      expect(chats.feeds, hasLength(1));
    });

    test('the block list is the single-room one, upper case included (DM-4, REG-MULTI-005)', () async {
      await store.blockRules.add(BlockKind.keyword, 'ABC');
      await controller().assign(0, RoomRef('douyu', '1'));
      controller().setDanmaku(enabled: true);
      await settle();
      expect(chats.feeds.single.current.blockedWords, ['ABC']);
      final chat = controller().danmaku!;
      chats.feeds.single.emit(batchOf([chatLine('u', 'xabcx'), chatLine('v', 'hello')]));
      await settle();
      expect(chat.chat.lines.where(chat.isBlocked), hasLength(1));
    });
  });

  group('suspension (RS-3)', () {
    Future<void> fillTwo() async {
      controller().setLayout(MultiviewLayout.two);
      await controller().assign(0, RoomRef('douyu', '1'));
      await controller().assign(1, RoomRef('douyu', '2'));
      await settle();
    }

    test('covered by a page: only the sound focus plays on, and uncovered all resume', () async {
      await fillTwo();
      controller().setCovered(covered: true);
      expect(session(0).state.phase, PlaybackPhase.suspended);
      expect(session(1).state.phase, isNot(PlaybackPhase.suspended));
      expect(session(0).state.wantsPlay, isTrue, reason: 'the intent never changes (INV-MULTI-12)');
      controller().setCovered(covered: false);
      await settle();
      expect(session(0).state.phase, isNot(PlaybackPhase.suspended));
    });

    test('a user pause while suspended stays paused after the cover goes (INV-MULTI-12)', () async {
      await fillTwo();
      controller()
        ..setCovered(covered: true)
        ..setPaused(0, paused: true)
        ..setCovered(covered: false);
      await settle();
      expect(session(0).state.phase, PlaybackPhase.paused);
    });

    test('in the background every cell waits 1.5 s, then suspends; back, all resume', () async {
      await fillTwo();
      controller().setAppHidden(hidden: true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(session(1).state.phase, isNot(PlaybackPhase.suspended), reason: 'short hidden phases change nothing');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(session(0).state.phase, PlaybackPhase.suspended);
      expect(session(1).state.phase, PlaybackPhase.suspended);
      expect(session(1).state.wantsPlay, isTrue);
      controller().setAppHidden(hidden: false);
      expect(session(0).state.phase, isNot(PlaybackPhase.suspended));
      expect(session(1).state.phase, isNot(PlaybackPhase.suspended));
    });

    test('background play keeps only the focus, as sound without video', () async {
      await store.settings.set(Settings.backgroundPlay, true);
      await fillTwo();
      controller().setAppHidden(hidden: true);
      await Future<void>.delayed(multiviewHideDelay + const Duration(milliseconds: 100));
      expect(session(0).state.phase, PlaybackPhase.suspended);
      expect(session(1).state.phase, isNot(PlaybackPhase.suspended));
      expect(engines[1].audioOnly, isTrue);
      controller().setAppHidden(hidden: false);
      await settle();
      expect(session(0).state.phase, isNot(PlaybackPhase.suspended));
      expect(engines[1].audioOnly, isFalse, reason: 'the video comes back in the foreground');
    });

    test('1+N: small cells out of view suspend; a promotion forgets the old report (REG-MULTI-009)', () async {
      controller().setLayout(MultiviewLayout.onePlusN);
      controller()
        ..addCell()
        ..addCell();
      expect(state().cells, hasLength(6));
      for (var i = 0; i < 6; i++) {
        await controller().assign(i, RoomRef('douyu', '${i + 1}'));
      }
      await settle();
      expect(state().big, 0);
      controller().setVisibleSmallCells([1, 2, 3]);
      expect(session(4).state.phase, PlaybackPhase.suspended);
      expect(session(5).state.phase, PlaybackPhase.suspended);
      expect(session(1).state.phase, isNot(PlaybackPhase.suspended));

      controller().setVisibleSmallCells([3, 4, 5]);
      await settle();
      expect(session(1).state.phase, PlaybackPhase.suspended);
      expect(session(5).state.phase, isNot(PlaybackPhase.suspended));

      controller().setFocus(1);
      await settle();
      expect(state().big, 1);
      expect(
        [for (var i = 0; i < 6; i++) session(i).state.phase],
        everyElement(isNot(PlaybackPhase.suspended)),
        reason: 'nothing is held on the old report until the column reports again',
      );
    });
  });

  test('entering pauses the room page player (ENT-2, INV-MULTI-02)', () async {
    final room = PlaybackSession(engine: FakeEngine.new);
    addTearDown(room.dispose);
    final scoped = makeContainer([playbackSessionProvider.overrideWith((ref) => room)])
      // The room page below keeps its session alive.
      ..listen(playbackSessionProvider, (_, _) {});
    addTearDown(scoped.dispose);
    final detail = await site.detail(RoomRef('douyu', '9'));
    await room.open(PlaybackRequest.room(site, detail));
    expect(room.state.wantsPlay, isTrue);
    await scoped.read(multiviewProvider.notifier).start(layout: MultiviewLayout.two);
    await settle();
    expect(room.state.wantsPlay, isFalse);
    expect(room.state.phase, PlaybackPhase.paused);
  });
}
