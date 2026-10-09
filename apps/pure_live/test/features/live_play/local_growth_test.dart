// Local growth (docs/D-弹幕/D08-本地互动/D08.3-本地成长): the rules as numbers,
// the day's counts, the watch clock (playing, paused, in the background, with
// a fake clock and a fake tick, D-017), writes kept to one in ten minutes,
// the check-in across midnight, the daily limits, the level's progress and
// the off switch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_growth.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

const LocalPlace _here = (platform: SiteIds.bilibili, roomId: '6', roomName: '主播');

/// A tick the test fires by hand.
final class _Ticks {
  final List<_FakeTimer> timers = [];

  Timer start(Duration period, void Function(Timer timer) tick) {
    expect(period, LocalWatchTime.tick);
    final timer = _FakeTimer(tick);
    timers.add(timer);
    return timer;
  }

  /// Whether a tick runs.
  bool get running => timers.any((timer) => timer.isActive);

  /// Fires the running ticks once.
  void fire() {
    for (final timer in [...timers]) {
      if (timer.isActive) timer.callback(timer);
    }
  }
}

final class _FakeTimer implements Timer {
  new(this.callback);

  final void Function(Timer timer) callback;
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// A local interaction over a memory store with the clock [clock].
final class _Rig {
  new(this.store, this.clock) : local = LocalInteraction(store.settings, events: store.localEvents, now: clock.now);

  static Future<_Rig> create(DateTime start) async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    await loadStrings();
    final rig = _Rig(store, _Clock(start));
    addTearDown(rig.local.dispose);
    // Run first: the writes under way end before the store closes.
    addTearDown(_settle);
    await rig.local.start();
    return rig;
  }

  final LiveStore store;
  final _Clock clock;
  final LocalInteraction local;

  SettingsStore get settings => store.settings;

  /// What is stored for today, written or not (the store's own value).
  LocalGrowthDay? get stored => LocalGrowthDay.parse(settings.get(Settings.localInteractionGrowthDay));
}

final class _Clock {
  new(this.time);

  DateTime time;

  DateTime now() => time;

  void advance(Duration by) => time = time.add(by);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// [rig] watches with [clock] ticking a minute at a time for [minutes].
void _watchMinutes(_Rig rig, LocalWatchTime clock, _Ticks ticks, int minutes) {
  for (var i = 0; i < minutes; i++) {
    rig.clock.advance(const Duration(minutes: 1));
    ticks.fire();
  }
}

LocalWatchTime _clockFor(_Rig rig, _Ticks ticks) => LocalWatchTime(
  onWatched: (from, to) => rig.local.watched(from, to, place: _here),
  onSettle: rig.local.settleWatch,
  now: rig.clock.now,
  periodic: ticks.start,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the rules (c1, V03.6 §5.4)', () {
    test("the numbers are constants of the catalog; the level formula is 3.x's", () {
      expect(LocalCatalog.watchStep, const Duration(minutes: 10));
      expect((LocalCatalog.watchExperience, LocalCatalog.watchCoins), (10, 20));
      expect(LocalCatalog.watchExperienceDailyLimit, 300);
      expect((LocalCatalog.checkInExperience, LocalCatalog.checkInCoins), (20, 100));
      expect((LocalCatalog.chatExperience, LocalCatalog.chatExperienceDailyLimit), (1, 50));
      expect(LocalCatalog.rechargeAmounts, [500, 2000, 10000], reason: 'D-001: the buttons stay');
      // D-001: experience ÷ 500 + 1, no top.
      expect(
        [
          for (final xp in [0, 499, 500, 999, 1000, 49999]) LocalCatalog.levelFor(xp),
        ],
        [1, 1, 2, 2, 3, 100],
      );
      expect(LocalCatalog.levelFor(-5), 1);
    });

    test('progress into the level; a tier name every 10 levels, the last one from Lv.90', () {
      expect(LocalCatalog.progressFor(0), (level: 1, into: 0, missing: 500));
      expect(LocalCatalog.progressFor(1380), (level: 3, into: 380, missing: 120));
      expect(LocalCatalog.progressFor(1500), (level: 4, into: 0, missing: 500));
      expect(
        [
          for (final level in [1, 9, 10, 19, 20, 89, 90, 99, 100, 500]) LocalCatalog.tierKeyFor(level),
        ],
        [
          'local_level_tier_0',
          'local_level_tier_0',
          'local_level_tier_1',
          'local_level_tier_1',
          'local_level_tier_2',
          'local_level_tier_8',
          'local_level_tier_9',
          'local_level_tier_9',
          'local_level_tier_9',
          'local_level_tier_9',
        ],
      );
    });

    test('the tier names and the progress line read from the translations', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      await rig.settings.set(Settings.localInteractionExperience, 1380);
      expect(rig.local.levelLabel, 'Lv.3 · 新人');
      expect(rig.local.nextLevelLabel, '还差 120 经验到 Lv.4');
      await rig.settings.set(Settings.localInteractionExperience, 4500);
      expect(rig.local.levelLabel, 'Lv.10 · 常客');
      expect(
        [for (final key in LocalCatalog.tierKeys) i18n(key)],
        ['新人', '常客', '熟客', '老友', '铁粉', '元老', '名人', '传奇', '殿堂', '至尊'],
      );
    });
  });

  group("the day's counts", () {
    test('stored as JSON; another day reads as nothing; bad values read as none', () {
      const day = LocalGrowthDay(
        day: '2026-10-09',
        watched: Duration(minutes: 35),
        watchExperience: 30,
        checkedIn: true,
        chatExperience: 4,
      );
      expect(LocalGrowthDay.parse(day.encode()), day);
      expect(LocalGrowthDay.read(day.encode(), '2026-10-09'), day);
      expect(LocalGrowthDay.read(day.encode(), '2026-10-10'), const LocalGrowthDay(day: '2026-10-10'));
      expect(LocalGrowthDay.read('', '2026-10-10'), const LocalGrowthDay(day: '2026-10-10'));
      expect(LocalGrowthDay.parse('{not json'), isNull);
      expect(LocalGrowthDay.parse('[1]'), isNull);
      expect(LocalGrowthDay.parse('{"watchExp": 3}'), isNull, reason: 'no day');
      expect(
        LocalGrowthDay.parse('{"day": "2026-10-09", "watchedMs": -5, "watchExp": "x", "chatExp": 2.0}'),
        const LocalGrowthDay(day: '2026-10-09', chatExperience: 2),
      );
    });

    test("the device's own day: midnight to midnight, local time", () {
      expect(LocalGrowthDay.dayOf(DateTime(2026, 10, 9, 23, 59, 59)), '2026-10-09');
      expect(LocalGrowthDay.dayOf(DateTime(2026, 10, 10)), '2026-10-10');
      expect(LocalGrowthDay.dayOf(DateTime(2026, 1, 5, 8)), '2026-01-05');
      expect(LocalGrowthDay.endOfDay(DateTime(2026, 10, 9, 23, 59)), DateTime(2026, 10, 10));
      expect(LocalGrowthDay.endOfDay(DateTime(2026, 12, 31, 1)), DateTime(2027));
      expect(LocalGrowthDay.dayOf(DateTime(2026, 10, 9, 23).toUtc()), '2026-10-09', reason: 'read in local time');
    });
  });

  group('the watch clock (c2)', () {
    test('counting starts the minute tick; stopping hands over the rest and settles; nothing ticks while stopped', () {
      var now = DateTime(2026, 10, 9, 20);
      final ticks = _Ticks();
      final pieces = <(DateTime, DateTime)>[];
      var settled = 0;
      final clock = LocalWatchTime(
        onWatched: (from, to) => pieces.add((from, to)),
        onSettle: () => settled++,
        now: () => now,
        periodic: ticks.start,
      );
      expect((clock.counting, ticks.running), (false, false));
      clock.update(counting: true);
      expect((clock.counting, ticks.running), (true, true));
      now = now.add(const Duration(minutes: 1));
      ticks.fire();
      now = now.add(const Duration(seconds: 30));
      clock
        ..update(counting: true) // already counting: nothing changes
        ..update(counting: false);
      expect(pieces, [
        (DateTime(2026, 10, 9, 20), DateTime(2026, 10, 9, 20, 1)),
        (DateTime(2026, 10, 9, 20, 1), DateTime(2026, 10, 9, 20, 1, 30)),
      ]);
      expect((settled, clock.counting, ticks.running), (1, false, false));
      // Stopped: time passing counts nothing, and stopping again settles nothing.
      now = now.add(const Duration(hours: 1));
      ticks.fire();
      clock.update(counting: false);
      expect((pieces.length, settled), (2, 1));
      clock.dispose();
      expect(settled, 1);
    });

    test('a long gap counts 5 minutes at most; a clock set back counts nothing', () {
      var now = DateTime(2026, 10, 9, 20);
      final ticks = _Ticks();
      final pieces = <Duration>[];
      final clock = LocalWatchTime(
        onWatched: (from, to) => pieces.add(to.difference(from)),
        onSettle: () {},
        now: () => now,
        periodic: ticks.start,
      )..update(counting: true);
      now = now.add(const Duration(hours: 2));
      ticks.fire();
      now = now.subtract(const Duration(minutes: 30));
      ticks.fire();
      now = now.add(const Duration(minutes: 1));
      ticks.fire();
      expect(pieces, [LocalWatchTime.longestGap, const Duration(minutes: 1)]);
      clock.dispose();
      expect(ticks.running, isFalse);
    });
  });

  group('watching (c2)', () {
    test('every 10 minutes of playing: +10 experience, +20 coins; 9 minutes give nothing yet', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      _watchMinutes(rig, clock, ticks, 9);
      expect((rig.local.experience, rig.local.coins), (0, 1000));
      expect(rig.local.today.watched, const Duration(minutes: 9));
      _watchMinutes(rig, clock, ticks, 1);
      expect((rig.local.experience, rig.local.coins), (10, 1020));
      _watchMinutes(rig, clock, ticks, 15);
      expect((rig.local.experience, rig.local.coins), (20, 1040));
      expect(
        rig.local.today,
        const LocalGrowthDay(day: '2026-10-09', watched: Duration(minutes: 25), watchExperience: 20),
      );
      clock.dispose();
      await _settle();
      expect(rig.stored, rig.local.today, reason: 'the 5 minutes left are stored when it stops');
      expect(rig.settings.get(Settings.localInteractionExperience), 20);
    });

    test('paused and on again: the minutes add up over the pause, the pause itself counts nothing', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      _watchMinutes(rig, clock, ticks, 6);
      clock.update(counting: false); // paused
      rig.clock.advance(const Duration(minutes: 30));
      ticks.fire();
      expect(rig.local.today.watched, const Duration(minutes: 6));
      clock.update(counting: true);
      _watchMinutes(rig, clock, ticks, 4);
      expect((rig.local.experience, rig.local.coins), (10, 1020));
      clock.dispose();
    });

    test('batched: an hour of watching writes 6 times (once a step), not every minute', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      final writes = <String>[];
      final subscription = rig.settings.changes.listen((setting) {
        if (setting == Settings.localInteractionGrowthDay) {
          writes.add(rig.settings.get(Settings.localInteractionGrowthDay));
        }
      });
      addTearDown(subscription.cancel);
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      for (var minute = 1; minute <= 64; minute++) {
        _watchMinutes(rig, clock, ticks, 1);
        await _settle();
      }
      expect(writes, hasLength(6));
      expect(rig.stored!.watched, const Duration(minutes: 60), reason: 'the 4 minutes since are in memory');
      expect(rig.local.today.watched, const Duration(minutes: 64));
      clock.update(counting: false);
      await _settle();
      expect(writes, hasLength(7), reason: 'stopping stores the rest');
      expect(rig.stored!.watched, const Duration(minutes: 64));
      clock.dispose();
    });

    test('at most 300 experience a day from watching (30 steps), then nothing more that day', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 8));
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      _watchMinutes(rig, clock, ticks, 6 * 60);
      expect((rig.local.experience, rig.local.coins), (300, 1600));
      expect(rig.local.today.watchExperience, 300);
      expect(rig.local.today.watched, const Duration(hours: 6));
      clock.dispose();
    });

    test('over midnight: each day keeps its own minutes; the new day starts from nothing', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 23, 50));
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      _watchMinutes(rig, clock, ticks, 7); // 23:57
      rig.clock.advance(const Duration(minutes: 5)); // 00:02, one look
      ticks.fire();
      expect((rig.local.experience, rig.local.coins), (10, 1020), reason: '23:50–24:00 is ten minutes of the 9th');
      expect(rig.local.today, const LocalGrowthDay(day: '2026-10-10', watched: Duration(minutes: 2)));
      _watchMinutes(rig, clock, ticks, 8);
      expect((rig.local.experience, rig.local.coins), (20, 1040));
      clock.dispose();
      await _settle();
      expect(rig.stored, const LocalGrowthDay(day: '2026-10-10', watched: Duration(minutes: 10), watchExperience: 10));
    });

    test('the time of a day older than the one stored is let go (the clock set back)', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      await rig.settings.set(
        Settings.localInteractionGrowthDay,
        const LocalGrowthDay(day: '2026-10-11', checkedIn: true).encode(),
      );
      rig.local
        ..watched(DateTime(2026, 10, 9, 20), DateTime(2026, 10, 9, 20, 5))
        ..settleWatch();
      await _settle();
      expect(rig.stored, const LocalGrowthDay(day: '2026-10-11', checkedIn: true));
      // Counting today goes on from nothing (not frozen until the 11th).
      expect(rig.local.checkIn(), isTrue);
      expect(rig.local.today.day, '2026-10-09');
    });
  });

  group('check-in (c3) and local danmaku (c4)', () {
    test('once a local day: +20 experience, +100 coins; again after midnight (23:59 → 00:00)', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 23, 59));
      expect(rig.local.checkIn(place: _here), isTrue);
      expect((rig.local.experience, rig.local.coins), (20, 1100));
      expect(rig.local.checkIn(place: _here), isFalse);
      rig.clock.advance(const Duration(seconds: 59));
      expect(rig.local.checkIn(place: _here), isFalse, reason: '23:59:59 is still the 9th');
      rig.clock.advance(const Duration(seconds: 1));
      expect(rig.local.checkIn(place: _here), isTrue, reason: '00:00 is the 10th');
      expect((rig.local.experience, rig.local.coins), (40, 1200));
      await _settle();
      expect(rig.stored, const LocalGrowthDay(day: '2026-10-10', checkedIn: true));
    });

    test('a local danmaku: +1 experience, no coins, at most 50 a day; the next day again', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      for (var i = 0; i < 60; i++) {
        rig.local.rewardChat(place: _here);
      }
      expect((rig.local.experience, rig.local.coins), (50, 1000));
      expect(rig.local.rewardChat(), isFalse);
      rig.clock.advance(const Duration(hours: 5));
      expect(rig.local.rewardChat(), isTrue);
      expect(rig.local.today.chatExperience, 1);
    });

    test('a restore of the same day keeps its limits (no second check-in)', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      rig.local.checkIn();
      await _settle();
      final file = await BackupService(rig.store).exportAll();
      final other = await _Rig.create(DateTime(2026, 10, 9, 21));
      await BackupService(other.store).restoreAll(file);
      expect((other.local.experience, other.local.coins), (20, 1100));
      expect(other.local.checkIn(), isFalse);
    });
  });

  group('levels (c5)', () {
    test('a level reached writes one "level" entry, however many levels one gain passes', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      await rig.settings.set(Settings.localInteractionExperience, 499);
      rig.local.rewardChat(place: _here);
      expect(rig.local.level, 2);
      final entry = rig.local.events.first;
      expect((entry.kind, entry.count, entry.roomName), (LocalEventKind.level, 2, '主播'));
      expect(rig.local.describe(entry), '升到 Lv.2');
      // A big gift passes three levels: one entry, Lv.5.
      await rig.settings.set(Settings.localInteractionCoins, 5000);
      final voyage = LocalCatalog.giftsFor(SiteIds.bilibili).firstWhere((gift) => gift.price >= 1980);
      expect(rig.local.sendGift(voyage, platform: SiteIds.bilibili, place: _here), isNotNull);
      expect(rig.local.level, LocalCatalog.levelFor(500 + voyage.price));
      expect([for (final e in rig.local.events.take(2)) e.kind], [LocalEventKind.level, LocalEventKind.gift]);
      expect(rig.local.events.first.count, rig.local.level);
      await _settle();
      expect((await rig.store.localEvents.all()).where((e) => e.kind == LocalEventKind.level), hasLength(2));
    });
  });

  group('in a room (c2, c3, c4)', () {
    /// Opens the room with the clock [clock]; checks in on entering.
    Future<(LocalRoom, LocalRoomSession)> open(WidgetTester tester, _Clock clock) async {
      final room = await pumpLocalRoom(
        tester,
        interaction: (store) => LocalInteraction(store.settings, events: store.localEvents, now: clock.now),
      );
      return (room, LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!);
    }

    /// [count] minutes pass, the player moving on every 3 seconds (so its
    /// stall watch sees it play).
    Future<void> minutes(WidgetTester tester, LocalRoom room, _Clock clock, int count) async {
      const step = Duration(seconds: 3);
      for (var i = 0; i < count * 20; i++) {
        clock.advance(step);
        room.engine.advance();
        await tester.pump(step);
      }
    }

    Future<void> lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
      states.forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump();
    }

    testWidgets('entering checks in once a day; playing counts; paused, in the background not; '
        'picture-in-picture does', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 9, 20));
      final (room, session) = await open(tester, clock);
      final local = session.interaction;
      expect((local.experience, local.coins), (20, 1100), reason: 'the first room of the day');
      final watch = LocalRoomWatch.of(local, session.room.session);
      expect(watch.counting, isTrue);

      await minutes(tester, room, clock, 10);
      expect((local.experience, local.coins), (30, 1120));

      // Paused: the time passing counts nothing.
      await tester.runAsync(session.room.session.pause);
      await tester.pump();
      expect(watch.counting, isFalse);
      await minutes(tester, room, clock, 10);
      expect(local.today.watched, const Duration(minutes: 10));
      await tester.runAsync(session.room.session.resume);
      room.engine
        ..emit(const EngineBuffering(buffering: false))
        ..emit(const EnginePlaying(playing: true));
      await tester.pump();
      expect(watch.counting, isTrue);

      // Picture-in-picture (Flutter says inactive) counts while it plays.
      await lifecycle(tester, [AppLifecycleState.inactive]);
      expect(watch.counting, isTrue);
      await minutes(tester, room, clock, 10);
      expect((local.experience, local.coins), (40, 1140));
      await lifecycle(tester, [AppLifecycleState.resumed]);
      expect(watch.counting, isTrue);

      // In the background: stops (and stores) at once; nothing counts there.
      await minutes(tester, room, clock, 3);
      await lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
      expect(watch.counting, isFalse);
      await settleLocal(tester);
      expect(
        LocalGrowthDay.parse(room.settings.get(Settings.localInteractionGrowthDay))!.watched,
        const Duration(minutes: 23),
      );
      await minutes(tester, room, clock, 20);
      expect(local.today.watched, const Duration(minutes: 23));
      expect((local.experience, local.coins), (40, 1140));

      // Back on the screen it plays again and counts again.
      await lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
      room.engine
        ..emit(const EngineBuffering(buffering: false))
        ..emit(const EnginePlaying(playing: true));
      await tester.pump();
      expect(watch.counting, isTrue);
      await minutes(tester, room, clock, 7);
      expect((local.experience, local.coins), (50, 1160));

      // Local growth off: stops; the next room the same day does not check in again.
      local.growthEnabled = false;
      await tester.pump();
      expect(watch.counting, isFalse);
      local.growthEnabled = true;
      await tester.pump();
      expect(local.checkIn(), isFalse);
      expect(room.toasts, isEmpty, reason: 'no level reached');
      await closeLocalRoom(tester, room);
    });

    testWidgets('a local danmaku: +1 experience; a level reached says so and joins the history', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 9, 20));
      final (room, session) = await open(tester, clock);
      final local = session.interaction;
      await tester.runAsync(() => room.settings.set(Settings.localInteractionExperience, 498));
      expect(session.sendChat('晚上好'), isTrue);
      expect(local.experience, 499);
      expect(room.toasts, isEmpty);
      expect(session.sendChat('再来一句'), isTrue);
      expect(local.level, 2);
      expect(room.toasts, ['本地等级升到 Lv.2']);
      expect(local.events.first.kind, LocalEventKind.level);
      expect(local.describe(local.events.first), '升到 Lv.2');
      expect(local.events.first.roomName, '主播');
      await closeLocalRoom(tester, room);
    });

    testWidgets('leaving the room stops the player, which settles the watch time; one watch per player', (
      tester,
    ) async {
      final clock = _Clock(DateTime(2026, 10, 9, 20));
      final (room, session) = await open(tester, clock);
      final player = session.room.session;
      final watch = LocalRoomWatch.of(session.interaction, player);
      expect(LocalRoomWatch.of(session.interaction, player), same(watch), reason: 'a page opened again picks it up');
      await minutes(tester, room, clock, 4);
      // What leaving does to the player (`RoomRuntime.dispose`).
      await tester.runAsync(player.stop);
      await tester.pump();
      expect(watch.counting, isFalse);
      await settleLocal(tester);
      expect(
        LocalGrowthDay.parse(room.settings.get(Settings.localInteractionGrowthDay)),
        const LocalGrowthDay(day: '2026-10-09', watched: Duration(minutes: 4), checkedIn: true),
      );
      await closeLocalRoom(tester, room);
    });
  });

  group('the identity card and the settings page (c5)', () {
    Finder key(String key) => find.byKey(ValueKey(key));
    Finder inside(String parent, Finder finder) => find.descendant(of: key(parent), matching: finder);

    for (final (name, width, height, scale) in [
      ('portrait', 400.0, 900.0, 1.0),
      ('landscape', 900.0, 400.0, 1.0),
      ('portrait at 2× text', 400.0, 900.0, 2.0),
      ('landscape at 2× text', 900.0, 400.0, 2.0),
    ]) {
      testWidgets('$name: the level, its tier and progress, today; "更多" adds coins as the buttons did', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final clock = _Clock(DateTime(2026, 10, 9, 20));
        final room = await pumpLocalRoom(
          tester,
          width: width,
          height: height,
          settings: {Settings.localInteractionExperience: 1360},
          interaction: (store) => LocalInteraction(store.settings, events: store.localEvents, now: clock.now),
        );
        final session = LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!..sendChat('晚上好');
        // What the room menu's "本地互动体验" does (a phone's landscape menu
        // scrolls).
        RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.open(RoomPanelKind.localInteraction);
        await tester.pumpAndSettle();
        // 1360 + 20 (the check-in) + 1 (the danmaku): Lv.3, 381 into it.
        expect(inside('local-identity-card', find.text('Lv.3 · 新人')), findsOneWidget);
        expect(inside('local-identity-card', find.text('还差 119 经验到 Lv.4')), findsOneWidget);
        expect(tester.widget<LinearProgressIndicator>(key('local-level-bar')).value, closeTo(381 / 500, 1e-9));
        expect(inside('local-identity-card', find.text('今天已签到 · 看直播 +0/300 · 弹幕 +1/50')), findsOneWidget);
        final card = tester.getRect(key('local-identity-card'));
        final panel = tester.getRect(key('local-interaction-panel'));
        expect(card.left >= panel.left && card.right <= panel.right, isTrue, reason: 'inside the panel');
        expect(
          tester.getRect(key('local-level-progress')).bottom,
          lessThanOrEqualTo(card.bottom),
          reason: 'the progress inside the card',
        );

        // c5: the three amounts are in "更多", in the room's coin.
        expect(key('local-recharge-2000'), findsNothing);
        await tester.tap(key('local-identity-more'));
        await tester.pumpAndSettle();
        expect(
          [
            for (final amount in [500, 2000, 10000]) find.text('+$amount 电池').evaluate().length,
          ],
          [1, 1, 1],
        );
        await tester.tap(key('local-recharge-2000'));
        await tester.pumpAndSettle();
        final local = session.interaction;
        expect((local.coins, local.experience), (3100, 1381), reason: 'coins only, as 3.x');
        expect(local.events.first.kind, LocalEventKind.recharge);
        expect(inside('local-identity-card', find.text('哔哩哔哩 · 用户等级 Lv.3 · 3100 电池')), findsOneWidget);
        await closeLocalRoom(tester, room);
      });
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('settings page ×$scale: the progress under the status; the switch, on; off hides today', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view
          ..physicalSize = const Size(400, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = (await tester.runAsync(() async {
          final services = await testServices();
          await services.store.settings.set(Settings.localInteractionExperience, 4520);
          return services;
        }))!;
        await tester.runAsync(loadStrings);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appServicesProvider.overrideWithValue(services)],
            child: MaterialApp(theme: const LiveTheme().light, home: const LocalInteractionSettingsPage()),
          ),
        );
        await settleLocal(tester);
        expect(inside('local-settings-list', find.text('Lv.10 · 常客')), findsOneWidget);
        expect(find.text('还差 480 经验到 Lv.11'), findsOneWidget);
        expect(find.text('今天还没签到 · 看直播 +0/300 · 弹幕 +0/50'), findsOneWidget, reason: 'no room yet');
        expect(
          tester.getTopLeft(key('local-level-progress')).dy,
          greaterThan(tester.getTopLeft(key('local-settings-status')).dy),
        );
        await tester.ensureVisible(key('local-settings-growth'));
        await tester.pumpAndSettle();
        expect(find.text('本地成长'), findsOneWidget);
        expect(tester.widget<Switch>(key('local-settings-switch-growth')).value, isTrue);
        await tester.tap(key('local-settings-switch-growth'));
        await tester.pump();
        expect(services.store.settings.get(Settings.localInteractionGrowthEnabled), isFalse);
        expect(key('local-growth-today'), findsNothing);
        expect(key('local-level-progress'), findsOneWidget, reason: 'the level is there either way');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(services.close);
      });
    }
  });

  group('the off switch (c1)', () {
    test(
      'on by default; off: no check-in, no watching, no danmaku experience; gifts as in 3.x; no level entries',
      () async {
        final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
        expect(rig.local.growthEnabled, isTrue);
        expect(rig.local.growing, isTrue);
        rig.local.growthEnabled = false;
        expect(rig.local.growing, isFalse);
        final ticks = _Ticks();
        final clock = _clockFor(rig, ticks)..update(counting: true);
        _watchMinutes(rig, clock, ticks, 30);
        clock.dispose();
        expect(rig.local.checkIn(), isFalse);
        expect(rig.local.rewardChat(), isFalse);
        expect((rig.local.experience, rig.local.coins), (0, 1000));
        await rig.settings.set(Settings.localInteractionExperience, 495);
        final snack = LocalCatalog.giftsFor(SiteIds.bilibili).first;
        rig.local.sendGift(snack, platform: SiteIds.bilibili, place: _here);
        expect((rig.local.experience, rig.local.coins), (495 + snack.price, 1000 - snack.price), reason: '3.x');
        expect(rig.local.level, 2);
        expect([for (final e in rig.local.events) e.kind], [LocalEventKind.gift]);
        await _settle();
        expect(rig.stored, isNull, reason: 'nothing counted');
      },
    );

    test('turning it off keeps the minutes watched so far; the local interaction off counts nothing either', () async {
      final rig = await _Rig.create(DateTime(2026, 10, 9, 20));
      final ticks = _Ticks();
      final clock = _clockFor(rig, ticks)..update(counting: true);
      _watchMinutes(rig, clock, ticks, 4);
      rig.local.growthEnabled = false;
      await _settle();
      expect(rig.stored!.watched, const Duration(minutes: 4));
      clock.dispose();
      rig.local
        ..growthEnabled = true
        ..enabled = false;
      expect((rig.local.growing, rig.local.checkIn(), rig.local.rewardChat()), (false, false, false));
    });
  });
}
