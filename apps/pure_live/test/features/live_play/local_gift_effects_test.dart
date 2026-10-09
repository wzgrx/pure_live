// The three local gift effects (docs/D-弹幕/D08-本地互动/D08.5-三档礼物特效): the
// tiers by price, the level "全部 / 只要大礼物 / 关" over 3.x's switch, the
// small gift's flying line, the medium gift's banner, the big gift's vehicle
// behind its banner; each for its tier's time in the banner queue, inside
// what the layer keeps clear of (the bars, a side panel), with 2x system
// text, the still banner with less motion, a combo keeping its effect.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/effects/local_gift_flyer.dart';
import 'package:pure_live/features/live_play/local_interaction/effects/local_gift_vehicle.dart';
import 'package:pure_live/features/live_play/local_interaction/local_gift_effect.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

final List<LocalGift> _bili = LocalCatalog.giftsFor(SiteIds.bilibili);
final LocalGift _snack = _bili[0];
final LocalGift _tv = _bili[1];
final LocalGift _voyage = _bili[2];
final LocalGift _superRocket = LocalCatalog.giftsFor(SiteIds.douyu)[2];

Finder _key(String key) => find.byKey(ValueKey(key));

/// The time the test sets (the combos' window).
final class _Clock {
  DateTime time = DateTime(2026, 10, 9, 20);

  DateTime now() => time;

  void advance(Duration by) => time = time.add(by);
}

/// Lets the animations run (the room's builder turns them off).
Widget _moving(Widget child) => Builder(
  builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: false), child: child),
);

/// [_moving] with 2x system text.
Widget _movingLarge(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: false, textScaler: const TextScaler.linear(2)),
    child: child,
  ),
);

/// A room with plenty of coins and a fake clock; motion on unless [still].
Future<(LocalRoom, LocalRoomSession, _Clock)> _room(
  WidgetTester tester, {
  double width = 400,
  double height = 900,
  bool still = false,
  bool large = false,
  Map<Setting<Object>, Object> settings = const {},
}) async {
  final clock = _Clock();
  final room = await pumpLocalRoom(
    tester,
    width: width,
    height: height,
    settings: {Settings.localInteractionCoins: 1000000, ...settings},
    wrap: still ? null : (large ? _movingLarge : _moving),
    interaction: (store) => LocalInteraction(store.settings, events: store.localEvents, now: clock.now),
  );
  final session = LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;
  return (room, session, clock);
}

Future<void> _fullscreen(WidgetTester tester) async {
  await tester.tap(_key('live-play-fullscreen'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// [after] passes, then [gift] goes.
Future<void> _give(
  WidgetTester tester,
  LocalRoomSession session,
  _Clock clock,
  LocalGift gift, {
  Duration? after,
}) async {
  if (after != null) {
    clock.advance(after);
    await tester.pump(after);
  }
  expect(session.sendGift(gift), isTrue);
  await tester.pump();
  await tester.pump();
}

/// The part of the layer the effects may use: inside what it keeps clear of.
Rect _area(WidgetTester tester) {
  final area = _key('local-gift-area');
  final padding = tester.widget<Padding>(area).padding.resolve(TextDirection.ltr);
  return padding.deflateRect(tester.getRect(area));
}

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// What the gift layer shows now: the line, the banner, the vehicle.
({bool line, bool banner, bool vehicle}) _shown() => (
  line: _key('local-gift-flyer').evaluate().isNotEmpty,
  banner: _key('local-gift-banner').evaluate().isNotEmpty,
  vehicle: _key('local-gift-vehicle').evaluate().isNotEmpty,
);

void main() {
  group('the tiers (c1)', () {
    test('by the price of one: below 100 small, below 1000 medium, then big; a big mark is big', () {
      expect(
        [
          for (final price in [10, 50, 99, 100, 500, 999, 1000, 1980, 5000]) LocalGiftTier.of(price: price).name,
        ],
        ['small', 'small', 'small', 'medium', 'medium', 'medium', 'big', 'big', 'big'],
      );
      expect(LocalGiftTier.of(price: 10, big: true), LocalGiftTier.big);
      expect(LocalGiftTier.of(price: 0), LocalGiftTier.medium, reason: 'unknown: the banner it had');
      expect((LocalCatalog.giftTierMedium, LocalCatalog.giftTierBig), (100, 1000));
      // Every catalogue: its cheapest small, the marked ones big; nothing
      // marked big is cheap.
      final gifts = [
        ...LocalCatalog.genericGifts,
        for (final pack in LocalCatalog.packs) ...LocalCatalog.giftsFor(pack.id),
      ];
      for (final gift in gifts) {
        final tier = LocalGiftTier.ofGift(gift);
        if (gift.big) expect(tier, LocalGiftTier.big, reason: gift.id);
        if (gift.price < 100) expect(tier, LocalGiftTier.small, reason: gift.id);
      }
      expect(
        {for (final gift in LocalCatalog.genericGifts) gift.id: LocalGiftTier.ofGift(gift).name},
        {'heart': 'small', 'flower': 'small', 'rocket': 'medium', 'castle': 'big'},
      );
      expect([for (final gift in _bili) LocalGiftTier.ofGift(gift)], LocalGiftTier.values);
    });

    test("each tier's time; a big gift's vehicle is done before its banner", () {
      expect([for (final tier in LocalGiftTier.values) tier.duration.inSeconds], [4, 3, 4]);
      expect(LocalGiftVehicle.duration, lessThan(LocalGiftTier.big.duration));
      expect(LocalGiftVehicle.duration.inMilliseconds, inInclusiveRange(2000, 3000), reason: 'c4: 2 to 3 s');
    });

    test('the vehicles: rockets fly as rockets; each big gift always the same one', () {
      expect(LocalGiftVehicle.of('douyu_super_rocket'), LocalGiftVehicle.rocket);
      expect(LocalGiftVehicle.of('bili_voyage'), LocalGiftVehicle.airplane);
      expect(LocalGiftVehicle.of('ks_guard'), LocalGiftVehicle.meteor);
      expect(LocalGiftVehicle.of('a_new_gift'), LocalGiftVehicle.of('a_new_gift'));
      final big = {
        for (final pack in LocalCatalog.packs)
          for (final gift in LocalCatalog.giftsFor(pack.id))
            if (LocalGiftTier.ofGift(gift) == LocalGiftTier.big) LocalGiftVehicle.of(gift.id),
      };
      expect(big, LocalGiftVehicle.values.toSet(), reason: 'all three are used');
    });

    test('the level: which tiers show', () {
      expect(
        {
          for (final level in LocalGiftEffectLevel.values)
            level.id: [for (final tier in LocalGiftTier.values) level.shows(tier)],
        },
        {
          'all': [true, true, true],
          'bigOnly': [false, false, true],
          'off': [false, false, false],
        },
      );
      expect(
        [
          for (final id in ['all', 'bigOnly', 'off', '', 'big']) LocalGiftEffectLevel.parse(id),
        ],
        [
          LocalGiftEffectLevel.all,
          LocalGiftEffectLevel.bigOnly,
          LocalGiftEffectLevel.off,
          LocalGiftEffectLevel.all,
          LocalGiftEffectLevel.all,
        ],
      );
    });
  });

  group("the level over 3.x's switch (c2)", () {
    Future<(LiveStore, LocalInteraction)> open([Map<Setting<Object>, Object> settings = const {}]) async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await store.settings.setAll({Settings.localInteractionCoins: 100000, ...settings});
      await loadStrings();
      final local = LocalInteraction(store.settings);
      addTearDown(local.dispose);
      return (store, local);
    }

    test('nothing stored: the switch decides (on is all, off is off)', () async {
      final (_, on) = await open();
      expect(on.giftEffectLevel, LocalGiftEffectLevel.all);
      final (_, off) = await open({Settings.localInteractionEnableGiftEffects: false});
      expect(off.giftEffectLevel, LocalGiftEffectLevel.off);
    });

    test('a choice is stored with the switch; 3.x turning the switch decides', () async {
      final (store, local) = await open();
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      local.giftEffectLevel = LocalGiftEffectLevel.bigOnly;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(local.giftEffectLevel, LocalGiftEffectLevel.bigOnly);
      expect(
        (
          store.settings.get(Settings.localInteractionGiftEffectLevel),
          store.settings.get(Settings.localInteractionEnableGiftEffects),
        ),
        ('bigOnly', true),
      );
      local.giftEffectLevel = LocalGiftEffectLevel.off;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.settings.get(Settings.localInteractionEnableGiftEffects), isFalse, reason: '3.x reads off');
      // 3.x installed over it turns the switch on: every gift again.
      await store.settings.set(Settings.localInteractionEnableGiftEffects, true);
      expect(local.giftEffectLevel, LocalGiftEffectLevel.all);
      // ... and with "只要大礼物" chosen, turning it off is off.
      local.giftEffectLevel = LocalGiftEffectLevel.bigOnly;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.settings.set(Settings.localInteractionEnableGiftEffects, false);
      expect(local.giftEffectLevel, LocalGiftEffectLevel.off);
      // The old setter still works (the switch on keeps the choice).
      local.enableGiftEffects = true;
      expect(local.giftEffectLevel, LocalGiftEffectLevel.bigOnly);
    });

    test("a gift's effect follows the level when it is sent", () async {
      final (_, local) = await open();
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      String effect(LocalGift gift) =>
          (local.sendGift(gift, platform: SiteIds.bilibili)!.data! as Map)['effect']! as String;
      expect(
        [
          for (final gift in [_snack, _tv, _voyage]) effect(gift),
        ],
        ['ticker', 'ticker', 'full'],
      );
      local.giftEffectLevel = LocalGiftEffectLevel.bigOnly;
      expect(
        [
          for (final gift in [_snack, _tv, _voyage]) effect(gift),
        ],
        ['none', 'none', 'full'],
      );
      local.giftEffectLevel = LocalGiftEffectLevel.off;
      expect(
        [
          for (final gift in [_snack, _tv, _voyage]) effect(gift),
        ],
        ['none', 'none', 'none'],
      );
      final castle = LocalCatalog.genericGifts.last;
      local.giftEffectLevel = LocalGiftEffectLevel.all;
      expect((castle.big, effect(castle)), (false, 'full'), reason: '2000 each: big without the mark');
    });
  });

  group('the vehicles drawn (c4)', () {
    test('every vehicle draws its frames without throwing, a few dozen particles at most, nothing after', () {
      for (final size in [const Size(914, 259), const Size(400, 121), const Size(411, 560)]) {
        for (final vehicle in LocalGiftVehicle.values) {
          final scene = LocalGiftVehicleScene(vehicle, seed: 0.3);
          var most = 0;
          var any = 0;
          for (var frame = 0; frame <= 2.8 * 120; frame++) {
            final recorder = ui.PictureRecorder();
            final drawn = scene.paint(Canvas(recorder), size, frame / 120);
            recorder.endRecording().dispose();
            most = drawn > most ? drawn : most;
            any += drawn;
          }
          expect(most, inInclusiveRange(1, LocalGiftVehicleScene.maxParticles), reason: '$vehicle $size');
          expect(any, greaterThan(0));
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          expect(scene.paint(canvas, size, 2.8), 0, reason: 'done');
          scene.dispose();
          expect(scene.paint(canvas, size, 1), 0, reason: 'disposed');
          recorder.endRecording().dispose();
        }
      }
    });
  });

  group('in the room', () {
    testWidgets('small: the line flies right to left near the top, inside the layer, for 4 s; no banner', (
      tester,
    ) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _snack);
      expect(_shown(), (line: true, banner: false, vehicle: false));
      expect(tester.widget<Text>(_key('local-gift-flyer-title')).data, 'Pure Live 送出 辣条');
      expect(tester.widget<Text>(_key('local-gift-flyer-count')).data, '×1');
      final area = _area(tester);
      expect(tester.getRect(_key('local-gift-flyer-lane')), area, reason: 'the lane is the layer, clipped');
      final xs = <double>[];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 600));
        final line = tester.getRect(_key('local-gift-flyer'));
        expect(line.top, closeTo(area.top + LocalGiftFlyer.top, 0.5));
        expect(line.bottom, lessThanOrEqualTo(area.bottom));
        xs.add(line.left);
      }
      expect(xs, [...xs]..sort((a, b) => b.compareTo(a)), reason: 'right to left');
      expect(xs.first, lessThan(area.right));
      // Slowest in the middle: the middle steps are shorter than the first.
      expect(xs[0] - xs[1], lessThan(area.width));
      expect(xs[2] - xs[3], lessThan(xs[0] - xs[1]));
      await tester.pump(LocalGiftTier.small.duration - const Duration(milliseconds: 3600));
      await tester.pump();
      expect(_shown(), (line: false, banner: false, vehicle: false));
      expect(session.giftEffect.value, isNull);
      await closeLocalRoom(tester, room);
    });

    testWidgets('a combo keeps the line flying where it is, its ×N jumps, its time starts again', (tester) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _snack);
      await tester.pump(const Duration(seconds: 1));
      final state = tester.state(find.byType(LocalGiftFlyer));
      final before = tester.getRect(_key('local-gift-flyer')).left;
      await _give(tester, session, clock, _snack, after: const Duration(milliseconds: 500));
      expect(tester.state(find.byType(LocalGiftFlyer)), same(state), reason: 'the same line (ValueKey(serial))');
      expect(tester.widget<Text>(_key('local-gift-flyer-count')).data, '×2');
      final now = tester.getRect(_key('local-gift-flyer')).left;
      expect(now, lessThanOrEqualTo(before), reason: 'not back to the right edge');
      expect(session.giftEffect.value!.revision, 1);
      // 4 s from the second send, not from the first.
      await tester.pump(const Duration(milliseconds: 3500));
      expect(_shown().line, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(_shown().line, isFalse);
      await closeLocalRoom(tester, room);
    });

    testWidgets('medium: the banner alone for 3 s', (tester) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _tv);
      expect(_shown(), (line: false, banner: true, vehicle: false));
      await tester.pump(const Duration(milliseconds: 2900));
      expect(_shown().banner, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(_shown().banner, isFalse);
      await closeLocalRoom(tester, room);
    });

    testWidgets('big: the vehicle behind the banner, the same through a combo; gone at 2.8 s, the banner at 4 s', (
      tester,
    ) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _voyage);
      expect(_shown(), (line: false, banner: true, vehicle: true));
      final area = _area(tester);
      expect(tester.getRect(_key('local-gift-vehicle')), area);
      // Behind the banner: painted first.
      final stack = find.ancestor(of: _key('local-gift-vehicle'), matching: find.byType(Stack)).first;
      final children = tester.widget<Stack>(stack).children;
      expect(children.first, isA<LocalGiftVehicleView>());
      await tester.pump(const Duration(seconds: 1));
      final state = tester.state(find.byType(LocalGiftVehicleView));
      await _give(tester, session, clock, _voyage, after: const Duration(milliseconds: 500));
      expect(tester.state(find.byType(LocalGiftVehicleView)), same(state), reason: 'not started again');
      expect(tester.widget<Text>(_key('local-gift-banner-count')).data, '×2');
      // The vehicle started 1.5 s ago: done 1.3 s later; the banner stays.
      await tester.pump(const Duration(milliseconds: 1400));
      expect(_shown(), (line: false, banner: true, vehicle: false));
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump();
      expect(_shown(), (line: false, banner: false, vehicle: false));
      await closeLocalRoom(tester, room);
    });

    testWidgets('mixed tiers wait their turn: the line, the banner, the vehicle; one at a time', (tester) async {
      final (room, session, clock) = await _room(tester);
      await _give(tester, session, clock, _snack);
      await _give(tester, session, clock, _tv);
      await _give(tester, session, clock, _superRocket);
      expect([for (final show in session.giftEffect.waiting) show.tier], [LocalGiftTier.medium, LocalGiftTier.big]);
      expect(_shown(), (line: true, banner: false, vehicle: false));
      await tester.pump(const Duration(milliseconds: 3900));
      expect(_shown(), (line: true, banner: false, vehicle: false));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(_shown(), (line: false, banner: true, vehicle: false));
      expect(tester.widget<Text>(_key('local-gift-banner-title')).data, 'Pure Live 送出 小电视');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(_shown(), (line: false, banner: true, vehicle: true));
      expect(tester.widget<LocalGiftVehicleView>(find.byType(LocalGiftVehicleView)).vehicle, LocalGiftVehicle.rocket);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(_shown(), (line: false, banner: false, vehicle: false));
      expect(session.giftEffect.length, 0);
      await closeLocalRoom(tester, room);
    });

    testWidgets('less motion: every tier is the still banner, for its time', (tester) async {
      final (room, session, clock) = await _room(tester, still: true);
      for (final gift in [_snack, _tv, _voyage]) {
        await _give(tester, session, clock, gift);
        expect(_shown(), (line: false, banner: true, vehicle: false), reason: gift.id);
        expect(find.byType(TweenAnimationBuilder<double>), findsNothing, reason: 'it does not grow in');
        final time = session.giftEffect.value!.tier.duration;
        await tester.pump(time);
        await tester.pump();
        expect(_shown().banner, isFalse, reason: gift.id);
      }
      await closeLocalRoom(tester, room);
    });

    testWidgets('"只要大礼物": small and medium only join the list; "关": nothing', (tester) async {
      final (room, session, clock) = await _room(
        tester,
        settings: {Settings.localInteractionGiftEffectLevel: 'bigOnly'},
      );
      await _give(tester, session, clock, _snack);
      await _give(tester, session, clock, _tv);
      expect((session.giftEffect.value, _shown()), (null, (line: false, banner: false, vehicle: false)));
      await _give(tester, session, clock, _voyage);
      expect(_shown(), (line: false, banner: true, vehicle: true));
      session.interaction.giftEffectLevel = LocalGiftEffectLevel.off;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await _give(tester, session, clock, _superRocket);
      expect(session.giftEffect.value, isNull);
      expect(
        [
          for (final line in session.room.chat.lines)
            if (line.message?.isLocal ?? false) line.text,
        ].length,
        4,
        reason: 'every gift is in the list',
      );
      await closeLocalRoom(tester, room);
    });

    testWidgets('landscape fullscreen with the side panel open: the line and the vehicle stay left of it', (
      tester,
    ) async {
      final (room, session, clock) = await _room(tester, width: 852, height: 393);
      await _fullscreen(tester);
      RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.open(RoomPanelKind.localInteraction);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final layer = tester.getRect(find.byType(LocalGiftLayer));
      await _give(tester, session, clock, _snack);
      final area = _area(tester);
      expect(area.right, lessThan(layer.right - 200), reason: 'the panel covers the right');
      final clearance = tester.widget<LocalGiftLayer>(find.byType(LocalGiftLayer)).clearance;
      expect(area.top, greaterThanOrEqualTo(layer.top + clearance.top - 0.5));
      expect(area.bottom, lessThanOrEqualTo(layer.bottom - clearance.bottom + 0.5));
      expect(tester.getRect(_key('local-gift-flyer-lane')), area);
      await tester.pump(LocalGiftTier.small.duration);
      await tester.pump();
      await _give(tester, session, clock, _voyage);
      expect(tester.getRect(_key('local-gift-vehicle')), area);
      expect(_inside(tester.getRect(_key('local-gift-banner')), area), isTrue);
      await tester.pump(LocalGiftTier.big.duration);
      await closeLocalRoom(tester, room);
    });

    for (final (name, size) in [('portrait inline', const Size(400, 900)), ('landscape', const Size(852, 393))]) {
      testWidgets('2x system text, $name: the line and the vehicle stay inside the bars', (tester) async {
        final (room, session, clock) = await _room(tester, width: size.width, height: size.height, large: true);
        if (size.width > size.height) await _fullscreen(tester);
        await _give(tester, session, clock, _snack);
        final area = _area(tester);
        await tester.pump(const Duration(seconds: 2));
        final line = tester.getRect(_key('local-gift-flyer'));
        expect(line.top, greaterThanOrEqualTo(area.top));
        expect(line.bottom, lessThanOrEqualTo(area.bottom), reason: '$line in $area');
        // The line's text grows at most 1.3 times (UI.md §8.2).
        expect(line.height, lessThan(60));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        await _give(tester, session, clock, _voyage);
        expect(tester.getRect(_key('local-gift-vehicle')), area);
        expect(_inside(tester.getRect(_key('local-gift-banner')), area), isTrue);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'no overflow');
        await tester.pump(LocalGiftTier.big.duration);
        await closeLocalRoom(tester, room);
      });
    }

    testWidgets('the panel: three choices; "只要大礼物" turns the switch on, "关" off', (tester) async {
      final (room, session, _) = await _room(tester, still: true);
      RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.open(RoomPanelKind.localInteraction);
      await tester.pumpAndSettle();
      final row = _key('local-panel-giftEffects');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.descendant(of: _key('local-panel-list'), matching: find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
      expect(find.descendant(of: row, matching: find.text('显示本地礼物特效')), findsOneWidget);
      expect(
        [
          for (final id in ['all', 'bigOnly', 'off'])
            tester.widget<ChoiceChip>(_key('local-panel-giftEffects-$id')).selected,
        ],
        [true, false, false],
      );
      expect(find.descendant(of: row, matching: find.text('只要大礼物')), findsOneWidget);
      await tester.tap(_key('local-panel-giftEffects-bigOnly'));
      await tester.pumpAndSettle();
      expect(session.interaction.giftEffectLevel, LocalGiftEffectLevel.bigOnly);
      expect(room.settings.get(Settings.localInteractionEnableGiftEffects), isTrue);
      await tester.tap(_key('local-panel-giftEffects-off'));
      await tester.pumpAndSettle();
      expect(room.settings.get(Settings.localInteractionEnableGiftEffects), isFalse);
      expect(tester.widget<ChoiceChip>(_key('local-panel-giftEffects-off')).selected, isTrue);
      await closeLocalRoom(tester, room);
    });
  });

  testWidgets('the settings page: the same three choices; the switch off from 3.x shows "关"', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() async {
      final services = await testServices();
      await services.store.settings.set(Settings.localInteractionEnableGiftEffects, false);
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
    expect(tester.widget<ChoiceChip>(_key('local-settings-giftEffects-off')).selected, isTrue);
    await tester.tap(_key('local-settings-giftEffects-all'));
    await tester.pumpAndSettle();
    expect(services.store.settings.get(Settings.localInteractionEnableGiftEffects), isTrue);
    expect(services.store.settings.get(Settings.localInteractionGiftEffectLevel), 'all');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}
