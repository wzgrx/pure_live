// The local interaction's platform packs follow the platforms
// (docs/D-弹幕/D08-本地互动/D08.6-平台体验资源包的图标和资源): a pack for every
// platform, the real logo wherever a badge shows, one colour table, each
// platform's coin and gifts, 3.x's gift ids kept.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/effects/local_gift_vehicle.dart';
import 'package:pure_live/features/live_play/local_interaction/local_chat_line.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_pack_badge.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

/// 3.x's gifts (`local_interaction_controller.dart:214-716`): their ids are
/// in the history (D08.1 `gift_id`) and must keep naming the same gift.
const Map<String, int> _legacyGifts = {
  'heart': 10,
  'flower': 50,
  'rocket': 500,
  'castle': 2000,
  'bili_snack': 10,
  'bili_tv': 100,
  'bili_voyage': 1980,
  'douyu_ball': 10,
  'douyu_rocket': 500,
  'douyu_super_rocket': 2000,
  'huya_stick': 10,
  'huya_sword': 300,
  'huya_one': 1000,
  'douyin_heart': 10,
  'douyin_badge': 200,
  'douyin_carnival': 3000,
  'ks_beer': 10,
  'ks_arrow': 500,
  'ks_guard': 1500,
  'cc_flower': 10,
  'cc_car': 500,
  'cc_guard': 1800,
  'twitch_cheer': 10,
  'twitch_sub': 500,
  'twitch_hype_train': 2000,
  'soop_star_balloon': 10,
  'soop_sticker': 300,
  'soop_signature_balloon': 2000,
};

/// Every gift of the catalog.
List<LocalGift> get _allGifts => [
  ...LocalCatalog.genericGifts,
  for (final platform in LocalCatalog.platformsWithGifts) ...LocalCatalog.giftsFor(platform),
];

/// The code points of a TrueType font's cmap (formats 4 and 12).
Set<int> _codePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(record, record + 4)) == 'cmap') cmap = data.getUint32(record + 8);
  }
  expect(cmap, isNot(-1), reason: 'a cmap table');
  final points = <int>{};
  final subtables = data.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final at = cmap + data.getUint32(cmap + 4 + i * 8 + 4);
    switch (data.getUint16(at)) {
      case 12:
        final groups = data.getUint32(at + 12);
        for (var g = 0; g < groups; g++) {
          final group = at + 16 + g * 12;
          for (var c = data.getUint32(group); c <= data.getUint32(group + 4); c++) {
            points.add(c);
          }
        }
      case 4:
        final segments = data.getUint16(at + 6) ~/ 2;
        for (var s = 0; s < segments; s++) {
          final end = data.getUint16(at + 14 + s * 2);
          final start = data.getUint16(at + 16 + segments * 2 + s * 2);
          if (start == 0xFFFF) continue;
          for (var c = start; c <= end; c++) {
            points.add(c);
          }
        }
    }
  }
  return points;
}

void main() {
  group('the catalog', () {
    test('every platform has its pack, in SiteIds order, in the colour of its logo', () {
      expect([for (final pack in LocalCatalog.packs) pack.id], SiteIds.supported);
      for (final id in SiteIds.supported) {
        final pack = LocalCatalog.packFor(id);
        expect(pack.id, id);
        expect(pack.nameKey, 'site_$id');
        expect(pack.accent, PlatformLogos.colorOf(id), reason: '$id: one colour table (PlatformLogos.colors)');
        expect(LocalPackBadge.hasLogo(id), isTrue, reason: '$id: shows its logo');
        expect(pack.badge, isNotEmpty, reason: '$id: the words where no picture fits');
      }
      expect(LocalCatalog.packFor(SiteIds.kick).currencyKey, 'local_currency_kicks');
      expect(LocalCatalog.packFor('huajiao'), LocalCatalog.genericPack);
      expect(LocalPackBadge.hasLogo(LocalCatalog.genericPack.id), isFalse);
    });

    test("3.x's eight keep their words, gift ids and prices; every id resolves; no id twice", () {
      for (final MapEntry(key: id, value: price) in _legacyGifts.entries) {
        final gift = LocalCatalog.giftById(id);
        expect(gift, isNotNull, reason: id);
        expect((gift!.price, gift.nameKey), (price, 'local_gift_$id'), reason: id);
      }
      for (final (platform, own, badge) in [
        (SiteIds.bilibili, 'bili', 'bilibili'),
        (SiteIds.douyu, 'douyu', 'douyu'),
        (SiteIds.huya, 'huya', 'huya'),
        (SiteIds.douyin, 'douyin', 'douyin'),
        (SiteIds.kuaishou, 'kuaishou', 'kuaishou'),
        (SiteIds.cc, 'cc', 'cc'),
        (SiteIds.twitch, 'twitch', 'twitch'),
        (SiteIds.soop, 'soop', 'soop'),
      ]) {
        final pack = LocalCatalog.packFor(platform);
        expect((pack.currencyKey, pack.levelKey), ('local_currency_$own', 'local_level_$own'), reason: platform);
        expect(LocalCatalog.badgeKeyFor(platform), 'local_badge_$badge', reason: platform);
      }
      expect(LocalCatalog.packFor(SiteIds.bilibili).badge, '📺', reason: "3.x's history line and sender name");
      final ids = [for (final gift in _allGifts) gift.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'an id names one gift');
      for (final gift in _allGifts) {
        expect(identical(LocalCatalog.giftById(gift.id), gift), isTrue, reason: gift.id);
        expect(gift.nameKey, 'local_gift_${gift.id}');
      }
      expect(LocalCatalog.giftById('gone'), isNull);
    });

    test('the platforms with own gifts: one small, one medium, one big; every big one has its own vehicle', () {
      expect(LocalCatalog.platformsWithGifts.length, greaterThanOrEqualTo(26));
      for (final platform in LocalCatalog.platformsWithGifts) {
        final gifts = LocalCatalog.giftsFor(platform);
        expect(
          [for (final gift in gifts) LocalGiftTier.ofGift(gift)],
          [LocalGiftTier.small, LocalGiftTier.medium, LocalGiftTier.big],
          reason: platform,
        );
        expect(gifts.last.big, isTrue, reason: '$platform: the big banner');
        expect(
          LocalCatalog.packFor(platform).currencyKey == LocalCatalog.genericPack.currencyKey,
          platform == SiteIds.youtube || platform == SiteIds.baiduLive,
          reason: '$platform: its own coin where it has one',
        );
      }
      for (final gift in _allGifts) {
        if (LocalGiftTier.ofGift(gift) == LocalGiftTier.big) {
          expect(LocalGiftVehicle.named.containsKey(gift.id), isTrue, reason: '${gift.id}: a vehicle chosen for it');
        }
      }
      expect(LocalGiftVehicle.of('six_fly_screen'), LocalGiftVehicle.airplane, reason: 'a fly-screen flies');
      expect(LocalGiftVehicle.of('baidu_rocket'), LocalGiftVehicle.rocket);
      expect(LocalGiftVehicle.of('look_star'), LocalGiftVehicle.meteor);
      // The research's own figures: a Six Rooms fly-screen is 1000 six
      // coins (V03.5 §2), Kick's Kicks and CHZZK's cheese are the coins.
      expect(LocalCatalog.giftById('six_fly_screen')!.price, 1000);
      expect(LocalCatalog.packFor(SiteIds.sixRoom).currencyKey, 'local_currency_six_coin');
      expect(LocalCatalog.packFor(SiteIds.chzzk).currencyKey, 'local_currency_cheese');
      // The ones without a gift system of their own keep the generic four.
      for (final platform in [SiteIds.steamBroadcast, SiteIds.jdLive, SiteIds.iptv]) {
        expect(LocalCatalog.giftsFor(platform), LocalCatalog.genericGifts, reason: platform);
      }
    });

    test('every gift and badge emoji is in the bundled emoji font', () {
      final points = _codePoints(File('assets/fonts/emoji/NotoColorEmoji-Subset.ttf').readAsBytesSync());
      final texts = [
        for (final gift in _allGifts) gift.emoji,
        for (final pack in [LocalCatalog.genericPack, ...LocalCatalog.packs])
          if (pack.badge.runes.any((rune) => rune > 0x2000)) pack.badge,
      ];
      for (final text in texts) {
        for (final rune in text.runes) {
          if (rune == 0xFE0F) continue; // localEmojiText drops it
          expect(points.contains(rune), isTrue, reason: '$text U+${rune.toRadixString(16)}');
        }
      }
    });
  });

  group('the badge', () {
    testWidgets('the logo of each platform; the words of the generic pack', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Wrap(
            children: [
              for (final pack in [LocalCatalog.genericPack, ...LocalCatalog.packs])
                LocalPackBadge(pack.id, fallback: pack.badge, size: 20),
            ],
          ),
        ),
      );
      for (final pack in LocalCatalog.packs) {
        expect(_key('local-pack-logo-${pack.id}'), findsOneWidget, reason: pack.id);
      }
      expect(find.byType(PlatformLogo), findsNWidgets(LocalCatalog.packs.length));
      expect(find.text('✨'), findsOneWidget, reason: 'the generic pack');
    });

    testWidgets('a chat line from before D08.6 (no platform) keeps its emoji badge; a new one has the logo', (
      tester,
    ) async {
      await tester.runAsync(loadStrings);
      const old = LiveMessage(
        type: LiveMessageType.chat,
        userName: '📺 舰队等级 · 听众 · Pure Live',
        message: '晚上好',
        color: LiveMessageColor.white,
        isLocal: true,
        data: {
          'local': true,
          'title': '听众',
          'name': 'Pure Live',
          'accent': 0xFF00AEEC,
          'badge': '📺',
          'badgeName': '舰队等级',
          'level': 1,
        },
      );
      final now = LiveMessage(
        type: LiveMessageType.chat,
        userName: '🎮 订阅徽章 · 听众 · Pure Live',
        message: '晚上好',
        color: LiveMessageColor.white,
        isLocal: true,
        data: {
          ...const LocalProfile(
            title: '听众',
            name: 'Pure Live',
            accent: 0xFF00E1B4,
            badge: '🎮',
            badgeName: '订阅徽章',
            level: 2,
            platform: SiteIds.chzzk,
          ).toData(),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().light,
          home: Scaffold(
            body: Column(
              children: [
                const KeyedSubtree(
                  key: ValueKey('old'),
                  child: LocalChatLine(message: old),
                ),
                KeyedSubtree(
                  key: const ValueKey('now'),
                  child: LocalChatLine(message: now),
                ),
              ],
            ),
          ),
        ),
      );
      expect(_in('old', find.text('📺 舰队等级 Lv.1')), findsOneWidget);
      expect(_in('old', find.byType(PlatformLogo)), findsNothing);
      expect(_in('now', find.text('订阅徽章 Lv.2')), findsOneWidget);
      expect(_in('now', _key('local-pack-logo-chzzk')), findsOneWidget);
      expect(LocalProfile.of(now)!.platform, SiteIds.chzzk);
      expect(LocalProfile.of(old)!.platform, isNull);
    });
  });

  group('the settings page', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets("×$scale: a logo on every chip but the chosen one; Kick's preview: logo, coin, gifts", (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view
          ..physicalSize = const Size(400, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = (await tester.runAsync(testServices))!;
        await tester.runAsync(loadStrings);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appServicesProvider.overrideWithValue(services)],
            child: MaterialApp(theme: const LiveTheme().light, home: const LocalInteractionSettingsPage()),
          ),
        );
        await settleLocal(tester);
        await tester.scrollUntilVisible(
          _key('local-settings-packs'),
          300,
          scrollable: find.descendant(of: _key('local-settings-list'), matching: find.byType(Scrollable)).first,
        );
        await tester.pumpAndSettle();
        expect(
          _in('local-settings-packs', find.byType(PlatformLogo)),
          findsNWidgets(LocalCatalog.packs.length - 1),
          reason: 'Bilibili, chosen, has the tick',
        );
        expect(_in('local-settings-packs', _key('local-pack-logo-kick')), findsOneWidget);
        expect(_in('local-pack-preview', _key('local-pack-logo-bilibili')), findsOneWidget);
        expect(_in('local-pack-preview', find.text('📺 哔哩哔哩')), findsNothing, reason: 'the logo, not the emoji');

        await tester.ensureVisible(_key('local-pack-kick'));
        await tester.pumpAndSettle();
        await tester.tap(_key('local-pack-kick'));
        await tester.pumpAndSettle();
        expect(services.store.settings.get(Settings.localInteractionPreviewPlatform), SiteIds.kick);
        await tester.ensureVisible(_key('local-pack-preview'));
        await tester.pumpAndSettle();
        expect(_in('local-pack-preview', _key('local-pack-logo-kick')), findsOneWidget);
        expect(_in('local-pack-preview', find.text('Kick')), findsOneWidget);
        expect(_in('local-pack-preview', find.text('订阅等级 Lv.1 · 1000 Kicks')), findsOneWidget);
        for (final name in ['💚 Kicks · 10', '⭐ 订阅 · 500', '🎁 送订阅 · 2000']) {
          expect(_in('local-pack-preview', find.text(name)), findsOneWidget, reason: name);
        }
        final preview = tester.getRect(_key('local-pack-preview'));
        expect(preview.right, lessThanOrEqualTo(400), reason: 'inside the screen');
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(services.close);
      });
    }
  });

  group('the room', () {
    for (final (name, width, height) in [('portrait', 400.0, 900.0), ('landscape', 900.0, 400.0)]) {
      testWidgets("$name, a Kick room: the card has the logo and Kicks, the grid Kick's gifts; a gift shows the logo", (
        tester,
      ) async {
        final room = await pumpLocalRoom(tester, platform: SiteIds.kick, width: width, height: height);
        final overlay = tester.element(find.byType(DanmakuOverlay));
        expect(LocalRoomScope.maybeOf(overlay)!.platform, SiteIds.kick);
        RoomPanelScope.maybeOf(overlay)!.open(RoomPanelKind.localInteraction);
        await tester.pumpAndSettle();
        expect(_in('local-identity-card', _key('local-pack-logo-kick')), findsOneWidget);
        expect(
          _in('local-identity-card', find.text('Kick · 订阅等级 Lv.1 · 1100 Kicks')),
          findsOneWidget,
          reason: "1000 and the check-in's 100 (D08.3)",
        );
        final card = tester.getRect(_key('local-identity-card'));
        final panel = tester.getRect(_key('local-interaction-panel'));
        expect(card.left >= panel.left && card.right <= panel.right, isTrue);
        await tester.scrollUntilVisible(
          _key('local-gift-kick_gift_subs'),
          200,
          scrollable: find.descendant(of: _key('local-panel-list'), matching: find.byType(Scrollable)).first,
        );
        await tester.pumpAndSettle();
        for (final id in ['kick_kicks', 'kick_sub', 'kick_gift_subs']) {
          expect(_key('local-gift-$id'), findsOneWidget, reason: id);
        }
        expect(_key('local-gift-heart'), findsNothing, reason: 'not the generic gifts');

        await tester.tap(_key('local-gift-kick_sub'));
        await tester.pump();
        expect(_in('local-gift-banner', _key('local-pack-logo-kick')), findsOneWidget);
        expect(_in('local-gift-banner', find.text('订阅徽章 Lv.1 · 听众')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(LocalGiftTier.medium.duration);
        await tester.pump();
        await closeLocalRoom(tester, room);
      });
    }

    testWidgets("the history: 3.x's and D08.1's gift ids still read, with their platform's logo", (tester) async {
      final now = DateTime.now();
      final room = await pumpLocalRoom(
        tester,
        prepare: (store) => store.localEvents.addAll([
          LocalEvent(
            at: now.subtract(const Duration(minutes: 9)),
            kind: LocalEventKind.gift,
            platform: SiteIds.bilibili,
            roomId: '6',
            roomName: '主播',
            giftId: 'bili_voyage',
            count: 1,
            coins: 1980,
          ),
          LocalEvent(
            at: now.subtract(const Duration(minutes: 8)),
            kind: LocalEventKind.gift,
            platform: SiteIds.yy,
            roomId: '8',
            roomName: '别的主播',
            giftId: 'castle',
            count: 2,
            coins: 4000,
          ),
          LocalEvent(
            at: now.subtract(const Duration(minutes: 7)),
            kind: LocalEventKind.gift,
            platform: SiteIds.douyu,
            roomId: '9',
            roomName: '斗鱼主播',
            giftId: 'douyu_super_rocket',
            count: 1,
            coins: 2000,
          ),
        ]),
      );
      final overlay = tester.element(find.byType(DanmakuOverlay));
      RoomPanelScope.maybeOf(overlay)!.open(RoomPanelKind.localInteraction);
      await tester.pumpAndSettle();
      await tester.drag(_key('local-panel-list'), const Offset(0, -1500));
      await tester.pumpAndSettle();
      final rows = [for (var i = 0; i < 3; i++) 'local-history-row-$i'];
      expect(_in(rows[0], find.text('🛰 送出 超级火箭 ×1')), findsOneWidget);
      expect(_in(rows[0], _key('local-pack-logo-douyu')), findsOneWidget);
      expect(_in(rows[1], find.text('🏰 送出 城堡 ×2')), findsOneWidget);
      expect(_in(rows[1], _key('local-pack-logo-yy')), findsOneWidget);
      expect(_in(rows[2], find.text('⚓ 送出 大航海 ×1')), findsOneWidget);
      expect(_in(rows[2], _key('local-pack-logo-bilibili')), findsOneWidget);
      expect(_key('local-history-again-0'), findsOneWidget, reason: 'an old id still sends again');
      await closeLocalRoom(tester, room);
    });
  });
}
