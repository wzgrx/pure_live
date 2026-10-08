// The local interaction (docs/A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md): the composers, the
// panel, the gift banner, the style page, the chat lines, the settings page
// and the logic over 3.x's `localInteraction.*` settings.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

/// The visible keys of [keys], top to bottom.
List<String> _column(WidgetTester tester, List<String> keys) => [
  for (final key in keys)
    if (_key(key).evaluate().isNotEmpty) key,
]..sort((a, b) => tester.getTopLeft(_key(a)).dy.compareTo(tester.getTopLeft(_key(b)).dy));

RoomPanelController _panels(WidgetTester tester) =>
    RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

LocalRoomSession _session(WidgetTester tester) => LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(_key('live-play-menu'));
  await tester.pumpAndSettle();
  await tester.tap(_key('room-menu-localInteraction'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text, {String field = 'local-composer-bar'}) async {
  await tester.enterText(_in(field, find.byType(EditableText)), text);
  await tester.tap(_in(field, _key('local-composer-send')));
  await tester.pump();
}

void main() {
  group('logic (3.x local_interaction_controller.dart)', () {
    test('the catalog: templates, colours, fonts, places, titles, 34 packs and the gifts', () {
      expect(
        [for (final p in LocalCatalog.presets) p.id],
        ['clean', 'highlight', 'neon', 'minimal', 'caption', 'cyber'],
      );
      final clean = LocalCatalog.defaultPreset;
      expect(
        (clean.color, clean.fontSize, clean.speed, clean.fontWeight, clean.showStroke, clean.strokeWidth),
        (0xFFFFFFFF, 19.0, 130.0, 600, true, 1.5),
      );
      expect(LocalCatalog.presetById('caption')!.placement, 'bottom');
      expect(LocalCatalog.presetById('caption')!.fixedDurationMs, 5200);
      expect(LocalCatalog.danmakuColors, hasLength(12));
      expect(LocalCatalog.effectColors, hasLength(7));
      expect(LocalCatalog.fontFamilyIds, ['system', 'rounded', 'serif', 'mono']);
      expect(LocalCatalog.placementIds, ['scroll', 'top', 'bottom']);
      expect(LocalCatalog.titles, ['listener', 'night_owl', 'supporter', 'guardian']);
      expect(LocalCatalog.packs, hasLength(34));
      expect(LocalCatalog.packFor('BILIBILI').badge, '📺');
      expect(LocalCatalog.packFor('kick'), LocalCatalog.genericPack);
      for (final platform in ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop']) {
        final gifts = LocalCatalog.giftsFor(platform);
        expect(gifts, hasLength(3), reason: platform);
        expect(gifts.where((gift) => gift.big), hasLength(1), reason: platform);
      }
      expect([for (final g in LocalCatalog.giftsFor('yy')) g.price], [10, 50, 500, 2000]);
      expect(LocalCatalog.levelFor(0), 1);
      expect(LocalCatalog.levelFor(1499), 3);
      expect(LocalCatalog.normalizeName('  ${'字' * 25}  '), '字' * 20);
      expect(LocalCatalog.normalizeName('   '), '');
      // A08.13 P16: "粗体" there and back keeps the template's weight (3.x
      // wrote 800 and 500: "清爽" 600 came back as 500).
      for (final preset in LocalCatalog.presets) {
        final weight = preset.fontWeight;
        final bold = weight >= 700;
        final toggled = bold ? LocalCatalog.regularWeight(weight) : LocalCatalog.boldWeight(weight);
        expect(toggled >= 700, !bold, reason: preset.id);
        final back = bold ? LocalCatalog.boldWeight(toggled) : LocalCatalog.regularWeight(toggled);
        expect(back, weight, reason: preset.id);
      }
      expect(
        [
          for (final w in [400, 500, 600]) LocalCatalog.boldWeight(w),
        ],
        [700, 700, 800],
      );
      expect(
        [
          for (final w in [700, 800, 900]) LocalCatalog.regularWeight(w),
        ],
        [500, 600, 600],
      );
      expect(LocalCatalog.danmakuLimit, 40);
    });

    test("3.x's keys and defaults; gifts, coins, history and the style", () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await loadStrings();
      final local = LocalInteraction(store.settings);
      addTearDown(local.dispose);
      expect(
        (local.enabled, local.userName, local.title, local.coins, local.level),
        (true, 'Pure Live', 'listener', 1000, 1),
      );
      expect(
        (local.showAsDanmaku, local.showPlatformBadge, local.showLevelBadge, local.enableGiftEffects),
        (true, true, true, true),
      );
      expect(local.preset, 'clean');

      final chat = local.createChat(' 主播晚上好 ', platform: 'bilibili');
      expect(chat.isLocal, isTrue);
      expect(chat.message, '主播晚上好');
      expect(chat.userName, '📺 舰队等级 · 听众 · Pure Live', reason: "3.x's sender label (copy)");
      expect(LocalProfile.of(chat)!.badgeLabel, '📺 舰队等级 Lv.1');
      expect(chat.style!.fontSize, 19);

      final voyage = LocalCatalog.giftsFor('bilibili').last;
      expect(local.sendGift(voyage, platform: 'bilibili'), isNull, reason: '1980 > 1000');
      final snack = local.sendGift(LocalCatalog.giftsFor('bilibili').first, platform: 'bilibili')!;
      expect(snack.message, 'Pure Live 送出 辣条 ×1', reason: 'c10: the name once');
      expect((local.coins, local.experience), (990, 10));
      local.recharge(500);
      expect(local.history, ['增加本地体验币 +500', '🌶️ 📺 舰队等级 · 听众 · Pure Live 送出 辣条 ×1']);
      expect(local.statusLine(LocalCatalog.packFor('bilibili')), '用户等级 Lv.1 · 1490 电池');
      for (var i = 0; i < 40; i++) {
        local.recharge(1);
      }
      expect(local.history, hasLength(30));

      local.setStyle(Settings.localDanmakuFontSize, 99);
      expect((local.fontSize, local.preset, local.presetLabel), (32.0, 'custom', '自定义'));
      local.resetStyle();
      expect((local.fontSize, local.preset), (19.0, 'clean'));
      local
        ..updateName('  ')
        ..updateName('阿明');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Written under 3.x's keys.
      expect(store.settings.get(Settings.localInteractionUserName), '阿明');
      expect(store.settings.get(Settings.localInteractionCoins), 1530);
      expect(store.settings.get(Settings.localDanmakuPreset), 'clean');
      // A08.13 P4: a clear hands back what it took; the undo puts it under
      // what came since, still 30 at most.
      final cleared = local.clearHistory();
      expect(cleared, hasLength(30));
      expect(local.history, isEmpty);
      local
        ..recharge(7)
        ..restoreHistory(cleared);
      expect(local.history, hasLength(30));
      expect(local.history.first, '增加本地体验币 +7');
      expect(local.history[1], cleared.first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.settings.get(Settings.localInteractionHistory), local.history);
    });
  });

  group('portrait room', () {
    testWidgets('U.2k-a: the composer under the chat list: star, field, send; a message shows at once', (tester) async {
      final room = await pumpLocalRoom(tester);
      final bar = _key('local-composer-bar');
      expect(bar, findsOneWidget);
      expect(tester.getBottomLeft(bar).dy, 900, reason: 'the last row of the room');
      final star = _in('local-composer-bar', _key('local-composer-style'));
      final field = _in('local-composer-bar', find.byType(EditableText));
      final send = _in('local-composer-bar', _key('local-composer-send'));
      expect(tester.getCenter(star).dx, lessThan(tester.getCenter(field).dx));
      expect(tester.getCenter(field).dx, lessThan(tester.getCenter(send).dx));
      expect(_in('local-composer-bar', find.byIcon(AppIcons.localStyle)), findsOneWidget);
      expect(_in('local-composer-bar', find.byIcon(AppIcons.localSend)), findsOneWidget);
      expect(_in('local-composer-bar', find.text('发送本地弹幕，只有你看得到')), findsOneWidget);
      expect(tester.getSize(_key('local-composer-field')).height, 48);

      await _send(tester, '   ');
      expect(_key('live-play-local-line'), findsNothing, reason: 'an empty one is not sent');
      await _send(tester, '主播晚上好');
      // K1 (A): at once, no "2 秒后" toast.
      final line = _key('live-play-local-line');
      expect(line, findsOneWidget);
      expect(_in('live-play-local-line', find.text('本地')), findsOneWidget);
      expect(_in('live-play-local-line', find.text('📺 舰队等级 Lv.1')), findsOneWidget);
      expect(find.textContaining('听众 · Pure Live：', findRichText: true), findsWidgets);
      expect(room.toasts, isEmpty);
      final flying = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
      expect(flying.flyingCount, 1, reason: 'it flies over the picture');
      await closeLocalRoom(tester, room);
    });

    testWidgets('K1: with the danmaku over the picture off, the first message says it only joined the list', (
      tester,
    ) async {
      final room = await pumpLocalRoom(tester, settings: {Settings.hideDanmaku: true});
      await _send(tester, '一');
      await _send(tester, '二');
      expect(room.toasts, ['画面弹幕已关闭，只加到了弹幕列表']);
      expect(_key('live-play-local-line'), findsNWidgets(2));
      await closeLocalRoom(tester, room);
    });

    testWidgets('#28: with the local interaction off there is no composer, no menu entry, no panel', (tester) async {
      final room = await pumpLocalRoom(tester, settings: {Settings.localInteractionEnabled: false});
      expect(_key('local-composer-bar'), findsNothing);
      await tester.tap(_key('live-play-menu'));
      await tester.pumpAndSettle();
      expect(_key('room-menu-localInteraction'), findsNothing);
      expect(find.byType(PopupMenuDivider), findsOneWidget, reason: 'two groups, no third');
      await closeLocalRoom(tester, room);
    });

    testWidgets('appendix A 6: a long press on a local danmaku: copy only, no blocking (A08.13 P17)', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final room = await pumpLocalRoom(tester);
      await _send(tester, '主播晚上好');
      await tester.longPress(_key('live-play-local-line'));
      await tester.pumpAndSettle();
      expect(_key('live-play-copy-message'), findsOneWidget);
      // A08.13 P17: local messages skip the filters, so a blocked word would
      // never stop the next one; the panel does not offer it.
      expect(_key('live-play-block-keyword'), findsNothing);
      expect(_key('live-play-block-user'), findsNothing);
      await tester.tap(_key('live-play-copy-message'));
      await tester.pumpAndSettle();
      expect(copied, '📺 舰队等级 · 听众 · Pure Live: 主播晚上好');
      await closeLocalRoom(tester, room);
    });

    testWidgets('U.2k-d: the menu opens the panel under the picture; its order; the header', (tester) async {
      final room = await pumpLocalRoom(tester);
      await tester.tap(_key('live-play-menu'));
      await tester.pumpAndSettle();
      expect(_in('room-menu-localInteraction', find.text('本地互动体验')), findsOneWidget);
      expect(_in('room-menu-localInteraction', find.byIcon(AppIcons.localInteraction)), findsOneWidget);
      expect(
        tester.getTopLeft(_key('room-menu-localInteraction')).dy,
        greaterThan(tester.getTopLeft(find.byType(PopupMenuDivider).last).dy),
      );
      await tester.tap(_key('room-menu-localInteraction'));
      await tester.pumpAndSettle();
      final panel = _key('local-interaction-panel');
      expect(panel, findsOneWidget);
      // c2: under the picture, the picture stays visible.
      final video = tester.getRect(_key('live-play-video-box'));
      expect(tester.getTopLeft(panel).dy, greaterThanOrEqualTo(video.bottom - 1));
      expect(_in('local-interaction-panel', find.text('本地互动体验')), findsOneWidget);
      expect(_in('local-panel-settings', find.text('设置')), findsOneWidget);
      expect(
        tester.getCenter(_key('local-panel-settings')).dx,
        lessThan(tester.getCenter(_key('room-panel-close')).dx),
      );
      // c3: who you are, compose, gifts, coins first; then the profile.
      expect(
        _column(tester, [
          'local-identity-card',
          'local-panel-composer',
          'local-gift-bili_snack',
          'local-recharge-500',
          'local-name-input',
        ]),
        [
          'local-identity-card',
          'local-panel-composer',
          'local-gift-bili_snack',
          'local-recharge-500',
          'local-name-input',
        ],
      );
      expect(_in('local-identity-card', find.text('听众 · Pure Live')), findsOneWidget);
      expect(_in('local-identity-card', find.text('哔哩哔哩 · 用户等级 Lv.1 · 1000 电池')), findsOneWidget);
      // c11: the gift the coins do not cover is faded; prices with the coin.
      expect(tester.widget<Opacity>(_key('local-gift-bili_voyage')).opacity, 0.45);
      expect(tester.widget<Opacity>(_key('local-gift-bili_snack')).opacity, 1);
      expect(_in('local-gift-bili_snack', find.byIcon(AppIcons.localCoins)), findsOneWidget);
      await tester.drag(_key('local-panel-list'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(
        _column(tester, ['local-panel-overlay', 'local-panel-giftEffects', 'local-panel-style', 'local-history']),
        ['local-panel-overlay', 'local-panel-giftEffects', 'local-panel-style', 'local-history'],
      );
      expect(find.text('本地弹幕在画面上飞过'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.key == const ValueKey('local-panel-style-value') && w.data == '清爽',
        ),
        findsOneWidget,
      );
      expect(_in('local-history', find.text('还没有互动记录')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(_key('local-history-clear')).onPressed, isNull);
      // Back closes the panel before anything else.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      await closeLocalRoom(tester, room);
    });

    testWidgets('#8: a gift costs coins, joins the list and shows its banner on the picture for 3 s', (tester) async {
      final room = await pumpLocalRoom(tester);
      await _openPanel(tester);
      await tester.tap(_key('local-gift-bili_voyage'));
      await tester.pump();
      expect(room.toasts, ['体验币余额不足']);
      expect(_key('local-gift-banner'), findsNothing);
      await tester.tap(_key('local-gift-bili_snack'));
      await tester.pump();
      await tester.pump();
      final banner = _key('local-gift-banner');
      expect(banner, findsOneWidget);
      // c9: in the middle of the picture, not of the page.
      final video = tester.getRect(_key('live-play-video-box'));
      expect((tester.getCenter(banner) - video.center).distance, lessThan(1));
      expect(_in('local-gift-banner', find.text('Pure Live 送出 辣条 ×1')), findsOneWidget);
      expect(_in('local-gift-banner', find.text('📺 舰队等级 Lv.1 · 听众')), findsOneWidget);
      expect(_in('local-identity-card', find.text('哔哩哔哩 · 用户等级 Lv.1 · 990 电池')), findsOneWidget);
      expect(room.settings.get(Settings.localInteractionCoins), anyOf(990, 1000), reason: 'written behind');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(banner, findsNothing);
      // The gift line: "送出 🌶 辣条 ×1", the name once (c10).
      _panels(tester).close();
      await tester.pumpAndSettle();
      expect(find.textContaining('送出', findRichText: true), findsWidgets);
      expect(_session(tester).giftEffect.value, isNull);
      await closeLocalRoom(tester, room);
    });

    testWidgets('#13: with the gift effects off there is no banner', (tester) async {
      final room = await pumpLocalRoom(tester, settings: {Settings.localInteractionEnableGiftEffects: false});
      await _openPanel(tester);
      await tester.tap(_key('local-gift-bili_snack'));
      await tester.pump();
      expect(_key('local-gift-banner'), findsNothing);
      await closeLocalRoom(tester, room);
    });
  });

  group('local danmaku style (c4, c5)', () {
    testWidgets('from the panel: the next page with back; the preview stays on top; the order; grey, not gone', (
      tester,
    ) async {
      final room = await pumpLocalRoom(tester);
      await _openPanel(tester);
      await tester.drag(_key('local-panel-list'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.tap(_key('local-panel-style'));
      await tester.pumpAndSettle();
      expect(_key('local-style-panel'), findsOneWidget);
      expect(_key('local-style-back'), findsOneWidget);
      expect(_in('local-style-reset', find.text('恢复默认')), findsOneWidget);
      expect(_in('local-style-preset-clean', find.text('清爽（默认）')), findsOneWidget);
      expect(
        _column(tester, [
          'local-style-preview',
          'local-style-presets',
          'local-style-placements',
          'local-style-fonts',
          'local-style-colors',
        ]),
        [
          'local-style-preview',
          'local-style-presets',
          'local-style-placements',
          'local-style-fonts',
          'local-style-colors',
        ],
      );
      final previewTop = tester.getTopLeft(_key('local-style-preview')).dy;
      await tester.drag(_key('local-style-controls'), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_key('local-style-preview')).dy, previewTop, reason: 'the preview does not scroll away');
      // Default: the outline on, the shadow off, scrolling.
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: _key('local-style-group-stroke'), matching: find.byType(Opacity)).first,
            )
            .opacity,
        1,
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: _key('local-style-group-shadow'), matching: find.byType(Opacity)).first,
            )
            .opacity,
        0.38,
      );
      expect(find.textContaining('打开“阴影 / 微光”后可调', findRichText: true), findsOneWidget);
      expect(tester.widget<Slider>(_key('local-style-slider-shadowBlur')).onChanged, isNull);
      expect(_key('local-style-fixed-condition'), findsOneWidget);
      expect(tester.widget<Slider>(_key('local-style-slider-fixedDuration')).onChanged, isNull);
      await tester.ensureVisible(_key('local-style-shadow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('local-style-shadow'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(_key('local-style-slider-shadowBlur')).onChanged, isNotNull);
      final local = _session(tester).interaction;
      expect(local.preset, 'custom');
      await tester.tap(_key('local-style-reset'));
      await tester.pumpAndSettle();
      expect((local.preset, local.showShadow), ('clean', false));
      await tester.tap(_key('local-style-back'));
      await tester.pumpAndSettle();
      expect(_key('local-interaction-panel'), findsOneWidget);
      await closeLocalRoom(tester, room);
    });

    testWidgets("#1: the composer's star opens the style by itself (no back)", (tester) async {
      final room = await pumpLocalRoom(tester);
      await tester.tap(_in('local-composer-bar', _key('local-composer-style')));
      await tester.pumpAndSettle();
      expect(_key('local-style-panel'), findsOneWidget);
      expect(_key('local-style-back'), findsNothing);
      await tester.tap(_key('room-panel-close'));
      await tester.pumpAndSettle();
      expect(_key('local-style-panel'), findsNothing);
      await closeLocalRoom(tester, room);
    });
  });

  group('wide and fullscreen', () {
    testWidgets('wide: the composer at the foot of the chat column; the panel on the right, 360 wide', (tester) async {
      final room = await pumpLocalRoom(tester, width: 1280, height: 800);
      final bar = tester.getRect(_key('local-composer-bar'));
      expect(bar.bottom, 800);
      expect(bar.left, greaterThan(800), reason: 'in the chat column');
      await _openPanel(tester);
      final panel = tester.getRect(_key('local-interaction-panel'));
      // The full height under the app bar, over the chat column.
      expect((panel.width, panel.right, panel.top, panel.bottom), (roomSidePanelWidth, 1280.0, kToolbarHeight, 800.0));
      await closeLocalRoom(tester, room);
    });

    testWidgets(
      'U.2k-b: the composer on the picture: 420 at most, the star collapses it below 180; focus holds the controls',
      (tester) async {
        final session = ValueNotifier<LocalRoomSession?>(null);
        final holds = <bool>[];
        Widget bar(double width, String key) => ValueListenableBuilder(
          valueListenable: session,
          builder: (context, value, _) => value == null
              ? const SizedBox.shrink()
              : SizedBox(
                  key: ValueKey(key),
                  width: width,
                  height: 52,
                  child: LocalDanmakuComposer(place: LocalComposerPlace.video, session: value, onHold: holds.add),
                ),
        );
        final room = await pumpLocalRoom(
          tester,
          width: 1000,
          wrap: (page) => Stack(
            children: [
              page,
              Positioned(left: 0, bottom: 0, child: Column(children: [bar(600, 'wide-bar'), bar(150, 'narrow-bar')])),
            ],
          ),
        );
        session.value = _session(tester);
        await tester.pump();
        expect(tester.getSize(_in('wide-bar', _key('local-composer-video'))).width, localComposerVideoMaxWidth);
        expect(_in('narrow-bar', _key('local-composer-star')), findsOneWidget);
        expect(_in('narrow-bar', find.byType(EditableText)), findsNothing);
        // A08.13 P8: the folded composer shows "write", the star stays the style's.
        expect(_in('narrow-bar', find.byIcon(AppIcons.localCompose)), findsOneWidget);
        expect(_in('narrow-bar', find.byIcon(AppIcons.localStyle)), findsNothing);
        expect(_in('wide-bar', find.byIcon(AppIcons.localCompose)), findsNothing);
        // The field: star, words, send; the star is the local danmaku colour.
        final star = tester.widget<Icon>(_in('wide-bar', find.byIcon(AppIcons.localStyle)));
        expect(star.color, Color(LocalCatalog.defaultPreset.color));
        await tester.tap(_in('wide-bar', find.byType(EditableText)));
        await tester.pump();
        expect(holds, [true]);
        await _send(tester, '今晚唱哪首', field: 'wide-bar');
        expect(_key('live-play-local-line'), findsOneWidget);
        // #27: the star opens a row above the bar with the keyboard; sending closes it.
        await tester.tap(_in('narrow-bar', _key('local-composer-star')));
        await tester.pumpAndSettle();
        final row = _key('local-composer-row');
        expect(row, findsOneWidget);
        expect(tester.getRect(row).bottom, lessThan(tester.getRect(_key('narrow-bar')).top + 52));
        await _send(tester, '第二条', field: 'local-composer-row');
        await tester.pumpAndSettle();
        expect(row, findsNothing);
        expect(_key('live-play-local-line'), findsNWidgets(2));
        await closeLocalRoom(tester, room);
      },
    );
  });

  group('settings page (U.2k-g)', () {
    Future<AppServices> pumpSettings(WidgetTester tester, {Map<Setting<Object>, Object> settings = const {}}) async {
      tester.view
        ..physicalSize = const Size(400, 3000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        if (settings.isNotEmpty) await services.store.settings.setAll(settings);
        return services;
      }))!;
      await tester.runAsync(loadStrings);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
            home: const LocalInteractionSettingsPage(),
          ),
        ),
      );
      await settleLocal(tester);
      return services;
    }

    testWidgets('c15: grouped by use; the entry line under the switch; history and clearing', (tester) async {
      final services = await pumpSettings(
        tester,
        settings: {
          Settings.localInteractionHistory: ['增加本地体验币 +500'],
        },
      );
      expect(find.text('本地用户与互动'), findsOneWidget);
      final groups = ['本地互动', '本地用户资料', '画面上', '平台体验资源包', '本地体验币与记录'];
      final tops = [for (final title in groups) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort());
      expect(
        tester.getTopLeft(_key('local-settings-entry-desc')).dy,
        lessThan(tester.getTopLeft(find.text('本地用户资料')).dy),
      );
      expect(_in('local-settings-status', find.text('本地等级 Lv.1 · 1000 本地体验币')), findsOneWidget);
      expect(
        _column(tester, [
          'local-settings-overlay',
          'local-settings-badge',
          'local-settings-level',
          'local-settings-giftEffects',
          'local-settings-style',
        ]),
        [
          'local-settings-overlay',
          'local-settings-badge',
          'local-settings-level',
          'local-settings-giftEffects',
          'local-settings-style',
        ],
      );
      expect(find.byType(ChoiceChip).evaluate().length, greaterThanOrEqualTo(34 + 4));
      await tester.tap(_key('local-pack-douyu'));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.key == const ValueKey('local-pack-status') && w.data == '用户等级 Lv.1 · 1000 鱼翅',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('local-history-count') && w.data == '1 条'),
        findsOneWidget,
      );
      await tester.tap(_key('local-history-clear'));
      await tester.pump();
      expect(_in('local-history', find.text('还没有互动记录')), findsOneWidget);
      // A08.13 P4: the same undo on the settings page.
      expect(_in('local-history-undo', find.text('已清空 1 条本地互动记录')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_in('local-history-undo', find.text('撤销')));
      await tester.pump();
      expect(_in('local-history', find.text('增加本地体验币 +500')), findsOneWidget);
      await tester.tap(_key('local-history-clear'));
      await tester.pump();
      await tester.tap(_key('local-recharge-2000'));
      await tester.pump();
      expect(_in('local-settings-status', find.text('本地等级 Lv.1 · 3000 本地体验币')), findsOneWidget);
      // #14: the same style panel as the room's.
      await tester.tap(_key('local-settings-style'));
      await tester.pumpAndSettle();
      expect(_key('local-style-panel'), findsOneWidget);
      await tester.tap(_key('room-panel-close'));
      await tester.pumpAndSettle();
      // #28: switched off, only the first group stays.
      await tester.tap(_key('local-settings-enabled'));
      await tester.pump();
      expect(find.text('本地用户资料'), findsNothing);
      expect(_key('local-settings-entry-desc'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(services.store.settings.get(Settings.localInteractionEnabled), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.close);
    });
  });

  group('A08.13 small fixes', () {
    String? copied;
    void watchClipboard(WidgetTester tester) {
      copied = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    testWidgets('P4: clearing the history in the panel says how many and undoes for 4 s', (tester) async {
      final room = await pumpLocalRoom(tester);
      await _openPanel(tester);
      await tester.tap(_key('local-recharge-500'));
      await tester.pump();
      await tester.tap(_key('local-gift-bili_snack'));
      await tester.pump();
      final local = _session(tester).interaction;
      final before = local.history;
      expect(before, hasLength(2));
      await tester.drag(_key('local-panel-list'), const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.tap(_key('local-history-clear'));
      await tester.pump();
      expect(local.history, isEmpty);
      expect(_in('local-history', find.text('还没有互动记录')), findsOneWidget);
      final toast = _key('local-history-undo');
      expect(_in('local-history-undo', find.text('已清空 2 条本地互动记录')), findsOneWidget);
      expect(tester.widget<SnackBar>(toast).duration, AppToast.actionDuration);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_in('local-history-undo', find.text('撤销')));
      await tester.pumpAndSettle();
      expect(local.history, before);
      expect(_in('local-history', find.text('增加本地体验币 +500')), findsOneWidget);
      expect(toast, findsNothing);
      await closeLocalRoom(tester, room);
    });

    testWidgets('P9: at most 40 characters; the count shows from 30 and turns red at 40', (tester) async {
      final room = await pumpLocalRoom(tester);
      final input = _in('local-composer-bar', find.byType(EditableText));
      final count = _in('local-composer-bar', _key('local-composer-count'));
      await tester.enterText(input, '字' * 29);
      await tester.pump();
      expect(count, findsNothing, reason: 'room for the words');
      await tester.enterText(input, '字' * 30);
      await tester.pump();
      expect(tester.widget<Text>(count).data, '30 / 40');
      // A paste of 60 keeps the first 40; an emoji is one character.
      await tester.enterText(input, '${'😀' * 10}${'字' * 50}');
      await tester.pump();
      expect(tester.widget<EditableText>(input).controller.text.characters.length, 40);
      final full = tester.widget<Text>(count);
      expect(full.data, '40 / 40');
      expect(full.style?.color, Theme.of(tester.element(count)).colorScheme.error);
      // The count sits inside the field, after the words.
      final field = tester.getRect(_key('local-composer-field'));
      expect(field.contains(tester.getCenter(count)), isTrue);
      expect(tester.getCenter(count).dx, greaterThan(tester.getCenter(input).dx));
      await tester.tap(_in('local-composer-bar', _key('local-composer-send')));
      await tester.pump();
      expect(find.textContaining('${'😀' * 10}${'字' * 30}', findRichText: true), findsWidgets);
      expect(count, findsNothing, reason: 'the field is empty again');
      await closeLocalRoom(tester, room);
    });

    testWidgets('P12: a local gift line has the long press and the double tap: copy, the name once', (tester) async {
      watchClipboard(tester);
      final room = await pumpLocalRoom(tester);
      await _openPanel(tester);
      await tester.tap(_key('local-gift-bili_snack'));
      await tester.pump();
      _panels(tester).close();
      await tester.pumpAndSettle();
      final line = _key('live-play-local-line');
      expect(line, findsOneWidget);
      await tester.longPress(line);
      await tester.pumpAndSettle();
      expect(_key('live-play-message-panel'), findsOneWidget);
      expect(_in('live-play-message-card', find.text('Pure Live 送出 辣条 ×1', findRichText: true)), findsOneWidget);
      expect(_key('live-play-copy-message'), findsOneWidget);
      expect(_key('live-play-block-keyword'), findsNothing);
      expect(_key('live-play-block-user'), findsNothing);
      await tester.tap(_key('live-play-copy-message'));
      await tester.pumpAndSettle();
      expect(copied, 'Pure Live 送出 辣条 ×1');
      copied = null;
      await tester.tap(line);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(line);
      await tester.pumpAndSettle();
      expect(copied, 'Pure Live 送出 辣条 ×1');
      await closeLocalRoom(tester, room);
    });

    testWidgets('P16: "粗体" on and off gives back the template\'s weight', (tester) async {
      final room = await pumpLocalRoom(tester);
      await tester.tap(_in('local-composer-bar', _key('local-composer-style')));
      await tester.pumpAndSettle();
      final local = _session(tester).interaction;
      expect(local.fontWeight, 600, reason: '"清爽"');
      final bold = _key('local-style-bold');
      await tester.drag(_key('local-style-controls'), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(bold);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(bold).selected, isFalse);
      await tester.tap(bold);
      await tester.pumpAndSettle();
      expect((local.fontWeight, tester.widget<ChoiceChip>(bold).selected), (800, true));
      await tester.tap(bold);
      await tester.pumpAndSettle();
      expect((local.fontWeight, tester.widget<ChoiceChip>(bold).selected), (600, false));
      await closeLocalRoom(tester, room);
    });
  });

  testWidgets('the flying layer: a local danmaku held at the top stays its time, then goes', (tester) async {
    final messages = StreamController<LiveMessage>.broadcast(sync: true);
    addTearDown(messages.close);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 300,
          child: DanmakuOverlay(
            messages: messages.stream,
            retractions: const Stream.empty(),
            look: const DanmakuLook(),
          ),
        ),
      ),
    );
    messages.add(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'Pure Live',
        message: '置顶',
        color: LiveMessageColor.white,
        isLocal: true,
        style: LiveMessageStyle(
          fontSize: 20,
          baseSpeed: 130,
          fontWeight: 700,
          showStroke: true,
          strokeWidth: 2,
          placement: LiveMessagePlacement.top,
          fixedDurationMs: 2000,
        ),
      ),
    );
    final state = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
    await tester.pump(const Duration(seconds: 1));
    expect(state.flyingCount, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(state.flyingCount, 0);
  });
}
