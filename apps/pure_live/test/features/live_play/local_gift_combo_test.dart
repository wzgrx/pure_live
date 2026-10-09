// Local gift combos, counts and the banner queue
// (docs/D-弹幕/D08-本地互动/D08.4-本地礼物连击和数量): the combo window on a fake
// clock, one chat line and one history entry per combo, the counts of the
// long press and the coins, the queue's order, limit and in-place growth,
// the banner clear of the bars in the landscape fullscreen, reduced motion
// and 2x system text.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/gift_count_pulse.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_gift_effect.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

const LocalPlace _here = (platform: SiteIds.bilibili, roomId: '6', roomName: '主播');

final List<LocalGift> _bili = LocalCatalog.giftsFor(SiteIds.bilibili);
final LocalGift _snack = _bili[0];
final LocalGift _tv = _bili[1];
final LocalGift _voyage = _bili[2];

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

/// The time the test sets.
final class _Clock {
  DateTime time = DateTime(2026, 10, 9, 20);

  DateTime now() => time;

  void advance(Duration by) => time = time.add(by);
}

/// One-shot timers the test fires by hand.
final class _Timers {
  final List<(Duration, _OneShot)> started = [];

  Timer start(Duration duration, void Function() done) {
    final timer = _OneShot(done);
    started.add((duration, timer));
    return timer;
  }

  /// Fires the newest timer still running.
  void fire() => started.lastWhere((entry) => entry.$2.isActive).$2.fire();
}

final class _OneShot implements Timer {
  new(this._done);

  final void Function() _done;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _done();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

LiveMessage _message(String name, {int count = 1}) => LiveMessage(
  type: LiveMessageType.gift,
  userName: 'Pure Live',
  message: 'Pure Live 送出 $name ×$count',
  color: LiveMessageColor.white,
  data: {..._profile, 'giftId': name, 'giftName': name, 'count': count},
  isLocal: true,
);

/// A profile's message data, as [LocalProfile.toData] writes it.
const Map<String, Object?> _profile = {'local': true, 'title': '听众', 'name': 'Pure Live', 'accent': 0xFF00A1D6};

/// A room with a fake clock for the combos and plenty of coins.
Future<(LocalRoom, LocalRoomSession, _Clock)> _room(
  WidgetTester tester, {
  double width = 400,
  double height = 900,
  Map<Setting<Object>, Object> settings = const {},
  Widget Function(Widget child)? wrap,
}) async {
  final clock = _Clock();
  final room = await pumpLocalRoom(
    tester,
    width: width,
    height: height,
    settings: {Settings.localInteractionCoins: 100000, ...settings},
    wrap: wrap,
    interaction: (store) => LocalInteraction(store.settings, events: store.localEvents, now: clock.now),
  );
  final session = LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;
  return (room, session, clock);
}

/// [after] passes on the clock and the timers, then [count] of [gift] go.
Future<bool> _give(
  WidgetTester tester,
  LocalRoomSession session,
  _Clock clock,
  LocalGift gift, {
  int count = 1,
  Duration after = Duration.zero,
}) async {
  if (after > Duration.zero) {
    clock.advance(after);
    await tester.pump(after);
  }
  final sent = session.sendGift(gift, count: count);
  await tester.pump();
  await tester.pump();
  return sent;
}

/// The local gift lines of the room's chat list.
List<String> _giftLines(LocalRoomSession session) => [
  for (final line in session.room.chat.lines)
    if (line.kind == ChatLineKind.gift && (line.message?.isLocal ?? false)) line.text,
];

String? _bannerTitle(WidgetTester tester) {
  final title = _key('local-gift-banner-title');
  return title.evaluate().isEmpty ? null : tester.widget<Text>(title).data;
}

String? _bannerCount(WidgetTester tester) {
  final count = _key('local-gift-banner-count');
  return count.evaluate().isEmpty ? null : tester.widget<Text>(count).data;
}

/// The jump of the count [key] (not a page transition's scale above it).
Finder _pulseOf(String key) => find.descendant(
  of: find.ancestor(of: _key(key), matching: find.byType(GiftCountPulse)),
  matching: find.byType(ScaleTransition),
);

/// Lets the animations run (the room's builder turns them off).
Widget _moving(Widget child) => Builder(
  builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: false), child: child),
);

void main() {
  group('the queue (c4)', () {
    test('one banner at a time, in order, five at most; a combo grows where it is', () {
      final timers = _Timers();
      final queue = LocalGiftQueue(timer: timers.start);
      addTearDown(queue.dispose);
      var heard = 0;
      queue.addListener(() => heard++);
      final a = queue.add(_message('甲'))!;
      expect((queue.value?.serial, queue.waiting.length, heard), (a.serial, 0, 1));
      expect(timers.started.single.$1, const Duration(seconds: 3));
      final b = queue.add(_message('乙'))!;
      final c = queue.add(_message('丙'))!;
      queue
        ..add(_message('丁'))
        ..add(_message('戊'));
      expect(queue.length, LocalCatalog.giftBannerLimit);
      expect(queue.add(_message('己')), isNull, reason: 'the sixth only joins the list');
      expect([for (final show in queue.waiting) show.gift!.name], ['乙', '丙', '丁', '戊']);

      // A waiting combo grows in its place; the one on the picture starts its
      // time again.
      final grown = queue.grow(c, _message('丙', count: 3))!;
      expect((grown.serial, grown.revision, grown.count), (c.serial, 1, 3));
      expect([for (final show in queue.waiting) show.count], [1, 3, 1, 1]);
      final before = timers.started.length;
      final again = queue.grow(a, _message('甲', count: 2))!;
      expect((queue.value, timers.started.length, timers.started[before - 1].$2.isActive), (again, before + 1, false));

      timers.fire();
      expect(queue.value?.serial, b.serial);
      timers.fire();
      expect((queue.value?.serial, queue.value?.count), (c.serial, 3));
      expect(queue.grow(a, _message('甲', count: 3)), isNull, reason: 'gone');
      for (var i = 0; i < 3; i++) {
        timers.fire();
      }
      expect((queue.value, queue.length), (null, 0));
      expect(queue.add(_message('庚')), isNotNull, reason: 'room again');
    });

    test("D08.5's hook: a banner's own time", () {
      final timers = _Timers();
      final queue = LocalGiftQueue(
        timer: timers.start,
        durationOf: (show) => show.gift!.name == '大' ? const Duration(seconds: 5) : const Duration(seconds: 3),
      );
      addTearDown(queue.dispose);
      queue
        ..add(_message('大'))
        ..add(_message('小'));
      timers.fire();
      expect([for (final (time, _) in timers.started) time.inSeconds], [5, 3]);
      queue.clear();
      expect((queue.value, queue.waiting.length), (null, 0));
    });
  });

  group('the interaction: counts, coins, one entry a combo (c1, c3)', () {
    test('a count takes price × count; too few coins take nothing; a combo is one entry and one line', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await loadStrings();
      final local = LocalInteraction(store.settings, events: store.localEvents);
      addTearDown(local.dispose);
      await local.start();
      expect(LocalCatalog.giftCounts, [1, 10, 66, 520]);
      expect(local.coins, 1000);
      expect(
        local.sendGift(_snack, platform: SiteIds.bilibili, place: _here, count: 520),
        isNull,
        reason: '5200',
      );
      expect((local.coins, local.experience, local.events.length), (1000, 0, 0));
      expect(local.sendGift(_snack, platform: SiteIds.bilibili, count: 0), isNull);

      final combo = LocalGiftCombo(_snack);
      final first = local.sendGift(_snack, platform: SiteIds.bilibili, place: _here, combo: combo)!;
      expect((first.message, LocalGiftData.of(first)!.count), ('Pure Live 送出 辣条 ×1', 1));
      final second = local.sendGift(_snack, platform: SiteIds.bilibili, place: _here, count: 10, combo: combo)!;
      expect((second.message, LocalGiftData.of(second)!.count), ('Pure Live 送出 辣条 ×11', 11));
      expect((combo.count, combo.coins), (11, 110));
      expect((local.coins, local.experience), (890, 110), reason: 'each send takes its own coins');
      final gifts = [
        for (final event in local.events)
          if (event.kind == LocalEventKind.gift) event,
      ];
      expect([for (final event in gifts) (event.count, event.coins)], [(11, 110)]);
      expect(local.describe(gifts.single), '🌶️ 送出 辣条 ×11');
      expect(local.history, ['🌶️ 📺 舰队等级 · 听众 · Pure Live 送出 辣条 ×11'], reason: "3.x's line, one");

      // Stored as one row; a later combo is a new one.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stored = await store.localEvents.all();
      expect([for (final event in stored) (event.kind, event.count, event.coins)], [(LocalEventKind.gift, 11, 110)]);
      local.sendGift(_snack, platform: SiteIds.bilibili, place: _here, combo: LocalGiftCombo(_snack));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect([for (final event in await store.localEvents.all()) event.count], [1, 11]);
      expect(local.history, hasLength(2));

      // Cleared during a combo: the next send starts a new entry.
      final run = LocalGiftCombo(_tv);
      local
        ..sendGift(_tv, platform: SiteIds.bilibili, place: _here, combo: run)
        ..clearHistory()
        ..sendGift(_tv, platform: SiteIds.bilibili, place: _here, combo: run);
      expect([for (final event in local.events) event.count], [1]);
      expect(run.count, 2, reason: 'the line and the banner still count on');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect([for (final event in await store.localEvents.all()) event.count], [1]);
    });
  });

  group('in the room', () {
    testWidgets('c1: within 3 s one banner ×2, one line, coins taken twice; at 4 s a new one', (tester) async {
      final (room, session, clock) = await _room(tester);
      final coins = session.interaction.coins;
      await _give(tester, session, clock, _snack);
      expect((_bannerTitle(tester), _bannerCount(tester)), ('Pure Live 送出 辣条', '×1'));
      final serial = session.giftEffect.value!.serial;
      await _give(tester, session, clock, _snack, after: const Duration(seconds: 2));
      expect(_bannerCount(tester), '×2');
      expect((session.giftEffect.value!.serial, session.giftEffect.value!.revision), (serial, 1));
      expect(_giftLines(session), ['Pure Live 送出 辣条 ×2']);
      expect(session.room.chat.replacements, 1);
      expect(session.interaction.coins, coins - 20);
      expect(_in('live-play-local-line', _key('live-play-local-gift-count')), findsOneWidget);
      expect(tester.widget<Text>(_key('live-play-local-gift-count')).data, '×2');
      expect(_pulseOf('live-play-local-gift-count'), findsNothing, reason: 'less motion');
      expect(_pulseOf('local-gift-banner-count'), findsNothing, reason: 'less motion');
      // The time started again at the second send: up until 5 s.
      await tester.pump(const Duration(milliseconds: 2900));
      expect(_bannerCount(tester), '×2');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(_key('local-gift-banner'), findsNothing);
      // 4 s after the last send: a new combo, a new banner and line.
      clock.advance(const Duration(seconds: 4));
      await _give(tester, session, clock, _snack);
      expect(_bannerCount(tester), '×1');
      expect(session.giftEffect.value!.serial, isNot(serial));
      expect(_giftLines(session), ['Pure Live 送出 辣条 ×2', 'Pure Live 送出 辣条 ×1']);
      final gifts = [
        for (final event in session.interaction.events)
          if (event.kind == LocalEventKind.gift) event.count,
      ];
      expect(gifts, [1, 2], reason: 'one entry a combo, newest first');
      // A different gift breaks the combo: the snack after the TV is new.
      await _give(tester, session, clock, _tv, after: const Duration(milliseconds: 500));
      await _give(tester, session, clock, _snack, after: const Duration(milliseconds: 500));
      expect(_giftLines(session).sublist(2), ['Pure Live 送出 小电视 ×1', 'Pure Live 送出 辣条 ×1']);
      await closeLocalRoom(tester, room);
    });

    testWidgets('c4: three gifts in a row show one after another; the sixth only joins the list', (tester) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _snack);
      await _give(tester, session, clock, _tv);
      await _give(tester, session, clock, _voyage);
      expect(_bannerTitle(tester), 'Pure Live 送出 辣条', reason: 'the first stays, not replaced');
      expect(find.byKey(const ValueKey('local-gift-banner')), findsOneWidget, reason: 'never two at once');
      // A combo of a waiting one grows in its place.
      await _give(tester, session, clock, _voyage, after: const Duration(seconds: 1));
      expect([for (final show in session.giftEffect.waiting) show.count], [1, 2]);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(_bannerTitle(tester), 'Pure Live 送出 小电视');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect((_bannerTitle(tester), _bannerCount(tester)), ('Pure Live 送出 大航海', '×2'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(_key('local-gift-banner'), findsNothing);

      final six = [...LocalCatalog.genericGifts, _snack, _tv];
      for (final gift in six) {
        await _give(tester, session, clock, gift);
      }
      expect(session.giftEffect.length, LocalCatalog.giftBannerLimit);
      expect(_giftLines(session), hasLength(3 + 6), reason: 'every gift is in the list');
      expect(session.giftEffect.waiting.last.gift!.name, '辣条', reason: 'the sixth has no banner');
      await closeLocalRoom(tester, room);
    });

    testWidgets("c2: with motion the banner's ×N jumps to 1.8 and back, the line's to 1.2", (tester) async {
      final (room, session, clock) = await _room(tester, wrap: _moving);
      await _give(tester, session, clock, _snack);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_pulseOf('local-gift-banner-count'), findsNothing, reason: 'nothing jumps before the count changes');
      await _give(tester, session, clock, _snack, after: const Duration(milliseconds: 500));
      final banner = _pulseOf('local-gift-banner-count');
      expect(banner, findsOneWidget);
      expect(tester.widget<ScaleTransition>(banner).scale.value, closeTo(1.8, 0.2));
      await tester.pump(const Duration(milliseconds: 100));
      final line = _pulseOf('live-play-local-gift-count');
      expect(line, findsOneWidget, reason: "the merged line's ×N, as the platforms' lines");
      expect(tester.widget<ScaleTransition>(line).scale.value, closeTo(1.2, 0.05));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<ScaleTransition>(_pulseOf('local-gift-banner-count')).scale.value, 1);
      expect(tester.widget<ScaleTransition>(_pulseOf('live-play-local-gift-count')).scale.value, 1);
      await tester.pump(const Duration(seconds: 3));
      await closeLocalRoom(tester, room);
    });

    testWidgets('c3: the long press menu: four counts with their cost, greyed beyond the coins; ×10 at once', (
      tester,
    ) async {
      final (room, session, clock) = await _room(tester, settings: {Settings.localInteractionCoins: 1000});
      RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.open(RoomPanelKind.localInteraction);
      await tester.pumpAndSettle();
      final coins = session.interaction.coins;
      expect(coins, inInclusiveRange(1000, 1100), reason: "the day's check-in may add 100");
      await tester.ensureVisible(_key('local-gift-bili_tv'));
      await tester.pumpAndSettle();
      await tester.longPress(_key('local-gift-bili_tv'));
      await tester.pumpAndSettle();
      expect(_key('app-menu-title'), findsOneWidget);
      expect(tester.widget<Text>(_key('app-menu-title')).data, '小电视 · 选择数量');
      final enabled = {
        for (final count in LocalCatalog.giftCounts)
          count: tester.widget<PopupMenuItem<int>>(_key('local-gift-count-$count')).enabled,
      };
      expect(enabled, {1: true, 10: true, 66: false, 520: false});
      expect(find.text('共 6600 电池'), findsOneWidget);
      final grey = tester.widget<Text>(find.text('×66'));
      expect(grey.style!.color!.a, closeTo(0.38, 0.01), reason: 'greyed');
      // A greyed count takes no tap.
      await tester.tap(_key('local-gift-count-66'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(session.interaction.coins, coins);
      if (_key('local-gift-count-10').evaluate().isEmpty) {
        await tester.longPress(_key('local-gift-bili_tv'));
        await tester.pumpAndSettle();
      }
      await tester.tap(_key('local-gift-count-10'));
      // Not pumpAndSettle: the banner's 3 s would pass.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.interaction.coins, coins - 1000);
      expect(session.giftEffect.value!.count, 10);
      expect(_giftLines(session), ['Pure Live 送出 小电视 ×10']);
      final entry = session.interaction.events.firstWhere((event) => event.kind == LocalEventKind.gift);
      expect((entry.count, entry.coins), (10, 1000));
      // Too few for ten more: the usual words, nothing taken.
      expect(await _give(tester, session, clock, _tv, count: 10), isFalse);
      expect(room.toasts.last, '体验币余额不足');
      expect(session.interaction.coins, coins - 1000);
      await tester.pump(const Duration(seconds: 3));
      await closeLocalRoom(tester, room);
    });

    testWidgets('"再发一次" sends as many as the entry says', (tester) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _snack, count: 66);
      RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.open(RoomPanelKind.localInteraction);
      await tester.pumpAndSettle();
      await tester.drag(_key('local-panel-list'), const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.tap(_key('local-history-filter-gift'));
      await tester.pumpAndSettle();
      expect(_in('local-history-row-0', find.textContaining('送出 辣条 ×66')), findsOneWidget);
      final coins = session.interaction.coins;
      clock.advance(const Duration(seconds: 10));
      await tester.ensureVisible(_key('local-history-again-0'));
      await tester.pumpAndSettle();
      await tester.tap(_key('local-history-again-0'));
      await tester.pumpAndSettle();
      expect(session.interaction.coins, coins - 660);
      expect(_in('local-history-row-0', find.textContaining('送出 辣条 ×66')), findsOneWidget);
      expect(_in('local-history-row-1', find.textContaining('送出 辣条 ×66')), findsOneWidget);
      await closeLocalRoom(tester, room);
    });

    testWidgets('landscape fullscreen: the banner keeps clear of the bars, centred', (tester) async {
      final (room, session, clock) = await _room(tester, width: 852, height: 393);
      await tester.tap(_key('live-play-fullscreen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final layer = tester.widget<LocalGiftLayer>(find.byType(LocalGiftLayer));
      expect(layer.fullscreen, isTrue);
      expect(layer.clearance.top, greaterThanOrEqualTo(controlBarHeight));
      expect(layer.clearance.bottom, greaterThanOrEqualTo(controlBarHeight));
      final overlay = tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay));
      expect((layer.clearance.top, layer.clearance.bottom), (overlay.giftClearance.top, overlay.giftClearance.bottom));
      await _give(tester, session, clock, _voyage);
      final screen = tester.getRect(find.byType(LocalGiftLayer));
      final banner = tester.getRect(_key('local-gift-banner'));
      expect(banner.top, greaterThanOrEqualTo(screen.top + layer.clearance.top));
      expect(banner.bottom, lessThanOrEqualTo(screen.bottom - layer.clearance.bottom));
      expect(banner.center.dx, closeTo(screen.center.dx, 1));
      await tester.pump(const Duration(seconds: 3));
      await closeLocalRoom(tester, room);
    });

    for (final (name, size) in [('portrait inline', const Size(400, 900)), ('landscape', const Size(852, 393))]) {
      testWidgets('2x system text, $name: the banner shrinks to fit between the bars', (tester) async {
        final (room, session, clock) = await _room(
          tester,
          width: size.width,
          height: size.height,
          wrap: (page) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: page,
            ),
          ),
        );
        if (size.width > size.height) {
          await tester.tap(_key('live-play-fullscreen'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
        await _give(tester, session, clock, _voyage);
        await _give(tester, session, clock, _voyage, count: 10);
        expect(_bannerCount(tester), '×11');
        final layer = tester.widget<LocalGiftLayer>(find.byType(LocalGiftLayer));
        final free = layer.clearance.deflateRect(tester.getRect(find.byType(LocalGiftLayer)));
        final banner = tester.getRect(_key('local-gift-banner'));
        expect(banner.top, greaterThanOrEqualTo(free.top - 0.5), reason: '$banner in $free');
        expect(banner.bottom, lessThanOrEqualTo(free.bottom + 0.5), reason: '$banner in $free');
        expect(banner.width, lessThanOrEqualTo(free.width + 0.5));
        expect(tester.takeException(), isNull, reason: 'no overflow');
        await tester.pump(const Duration(seconds: 3));
        await closeLocalRoom(tester, room);
      });
    }
  });
}
