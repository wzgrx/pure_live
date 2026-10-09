// F02 c1: 设置 → 弹幕 is the live room's danmaku settings (the same
// component, DanmakuSettingsContent), with "更多" for what only the settings
// hold, and a route of its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/danmaku_page.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/pip_danmaku_settings.dart';

import '../../support.dart';
import 'settings_harness.dart';

Finder _page() => find.byKey(const ValueKey('settings-page-danmaku'));

Finder _switch(String key) => find.byKey(ValueKey('danmaku-switch-$key'));

void main() {
  setUpAll(loadStrings);

  testWidgets("the overview row opens the room's danmaku settings, the same component", (tester) async {
    await pumpSettings(tester, height: 6000);
    await tapSettings(tester, settingsSection(SettingsSection.danmaku));
    expect(_page(), findsOneWidget);
    expect(find.widgetWithText(AppBar, '弹幕'), findsOneWidget);
    expect(find.descendant(of: _page(), matching: find.byType(DanmakuSettingsContent)), findsOneWidget);
    // As in the room's tab: "改动立即生效" right of the first group's title.
    expect(find.byKey(const ValueKey('panel-group-note')), findsOneWidget);
    expect(find.text('改动立即生效'), findsOneWidget);
    // The room's groups in its order, its chat list and mini window groups
    // too (A08.6 c2), then "更多".
    expectInOrder(tester, [
      for (final title in ['观看模板', '显示范围', '样式', '重复弹幕', '画面弹幕交互', '流畅度', '弹幕列表', '小窗弹幕', '更多']) find.text(title),
    ]);
    expect(find.byKey(const ValueKey('danmaku-paused-behavior')), findsOneWidget);
    // The catalogue's rows are not drawn on the page (they are for search).
    expect(settingsRow('danmaku_speed'), findsNothing);
    // Back returns to the overview.
    await tester.tap(find.byType(BackButton));
    await settleSettings(tester);
    expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
  });

  testWidgets("a change on the page is the room's setting", (tester) async {
    final h = await pumpSettings(tester, height: 4000, arguments: 'danmaku');
    expect(h.settings.get(Settings.enableDanmakuStroke), isTrue);
    await tapSettings(tester, _switch('stroke'));
    expect(h.settings.get(Settings.enableDanmakuStroke), isFalse);
  });

  testWidgets('"更多": show, on the video (inverted), YouTube, the font and the block list', (tester) async {
    final h = await pumpSettings(tester, height: 4000, arguments: 'danmaku');
    expect(find.byKey(const ValueKey('danmaku-settings-more')), findsOneWidget);

    await tapSettings(tester, _switch('show'));
    expect(h.settings.get(Settings.enableDanmakuDisplay), isFalse);

    // "在画面上显示飞行弹幕" is on while `hideDanmaku` is off.
    expect(tester.widget<Switch>(_switch('onVideo')).value, isTrue);
    await tapSettings(tester, _switch('onVideo'));
    expect(h.settings.get(Settings.hideDanmaku), isTrue);
    expect(tester.widget<Switch>(_switch('onVideo')).value, isFalse);

    await tapSettings(tester, _switch('youtubeAllChat'));
    expect(h.settings.get(Settings.youtubeShowAllChat), isTrue);

    expect(find.byKey(const ValueKey('danmaku-value-font')), findsOneWidget);
    expect(find.text('系统默认'), findsOneWidget);

    await tapSettings(tester, find.byKey(const ValueKey('danmaku-link-block')));
    expect(h.opened, [RoutePath.kSettingsDanmuShield]);
  });

  testWidgets('A08.6: "弹幕列表样式" and "小窗显示弹幕" are on the page, the same groups as the room\'s', (tester) async {
    final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
    expect(find.byType(ChatListSettings), findsOneWidget);
    expect(find.byType(PipDanmakuSettings), findsOneWidget);
    expect(find.text('弹幕列表样式'), findsOneWidget);
    expect(find.text('小窗显示弹幕'), findsOneWidget);

    // The list's look and the gift switch are settings of every room.
    await tapSettings(
      tester,
      find.descendant(of: find.byKey(const ValueKey('danmaku-list-style')), matching: find.text('卡片')),
    );
    expect(h.settings.get(Settings.danmakuListStyle), 'card');
    // A08.10: "显示用户名", on by default.
    expect(tester.widget<Switch>(_switch('names')).value, isTrue);
    await tapSettings(tester, _switch('names'));
    expect(h.settings.get(Settings.showChatNames), isFalse);
    expect(tester.widget<Switch>(_switch('gifts')).value, isTrue);
    await tapSettings(tester, _switch('gifts'));
    expect(h.settings.get(Settings.showChatGifts), isFalse);
    expect(tester.widget<Switch>(_switch('gifts')).value, isFalse);

    // Mini window danmaku: the rest folds away while it is off (3.x).
    expect(find.byKey(const ValueKey('danmaku-setting-pipFontSize')), findsOneWidget);
    await tapSettings(tester, _switch('pip'));
    expect(h.settings.get(Settings.enablePipDanmaku), isFalse);
    expect(find.byKey(const ValueKey('danmaku-setting-pipFontSize')), findsNothing);
  });

  testWidgets('A08.6: portrait 393×852 scrolls down to the two groups before "更多"', (tester) async {
    await pumpSettings(tester, width: 393, height: 852, arguments: 'danmaku');
    final list = find.descendant(of: find.byType(DanmakuSettingsContent), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('danmaku-settings-more')), 300, scrollable: list);
    await settleSettings(tester);
    expect(find.byType(PipDanmakuSettings), findsOneWidget);
    expect(
      topOf(tester, find.byType(PipDanmakuSettings)),
      lessThan(topOf(tester, find.byKey(const ValueKey('danmaku-settings-more')))),
    );
    expect(tester.getSize(find.byType(PipDanmakuSettings)).width, lessThanOrEqualTo(393));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: the page opens in the right pane', (tester) async {
    await pumpSettings(tester, width: 1280, height: 800);
    await tapSettings(tester, settingsSection(SettingsSection.danmaku));
    expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    expect(_page(), findsOneWidget);
    expect(tester.getTopLeft(_page()).dx, greaterThan(360));
    expect(tester.getSize(find.byType(DanmakuSettingsContent)).width, lessThanOrEqualTo(720));
  });

  testWidgets('search finds its settings under "弹幕"; the filters under the block list', (tester) async {
    await pumpSettings(tester);
    await searchSettingsFor(tester, '弹幕 速度');
    expect(settingsRow('danmaku_speed'), findsOneWidget);
    expect(find.text('弹幕 › 样式'), findsOneWidget);

    await searchSettingsFor(tester, '暂停');
    expect(settingsRow('danmaku_paused'), findsOneWidget);

    // A08.6: the chat list's settings are found under "弹幕 › 弹幕列表".
    await searchSettingsFor(tester, '礼物');
    expect(settingsRow('danmaku_show_gifts'), findsOneWidget);
    expect(find.text('弹幕 › 弹幕列表'), findsOneWidget);
    await searchSettingsFor(tester, '列表样式');
    expect(settingsRow('danmaku_list_style'), findsOneWidget);
    // A08.10: "显示用户名" next to them.
    await searchSettingsFor(tester, '用户名');
    expect(settingsRow('danmaku_show_names'), findsOneWidget);
    expect(find.text('弹幕 › 弹幕列表'), findsOneWidget);

    // The similarity and Douyu filters live on the block page (U.12d).
    await searchSettingsFor(tester, '相似');
    expect(settingsRow('video_block_list'), findsOneWidget);
  });

  testWidgets('A08.9 (D-038): the tap switch says a tap opens the actions while the controls show', (tester) async {
    await pumpSettings(tester);
    await searchSettingsFor(tester, '点击 弹幕');
    expect(settingsRow('danmaku_tap'), findsOneWidget);
    expect(
      find.descendant(of: settingsRow('danmaku_tap'), matching: find.text(withoutOrphan('控制条显示时点按画面上的弹幕打开操作面板'))),
      findsOneWidget,
    );
  });

  testWidgets('D05.2 (V01.4): "同屏最大弹幕条数" is on the page and found under "弹幕 › 流畅度"', (tester) async {
    final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
    expect(find.byKey(const ValueKey('danmaku-setting-maxVisible')), findsOneWidget);
    expect(find.text('48 条'), findsOneWidget);
    tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-maxVisible'))).onChanged!(30);
    await settleSettings(tester);
    expect(h.settings.get(Settings.danmakuMaxVisibleCount), 30);

    await pumpSettings(tester);
    await searchSettingsFor(tester, '同屏');
    expect(settingsRow('danmaku_max_visible'), findsOneWidget);
    expect(find.text('弹幕 › 流畅度'), findsOneWidget);
  });

  testWidgets('D03.4 (V01.3): "按住飞行弹幕让它停住" is on the page and found under "弹幕 › 画面弹幕交互"', (tester) async {
    final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
    expect(tester.widget<Switch>(_switch('holdOnPress')).value, isTrue, reason: 'on by default (D-039)');
    await tapSettings(tester, _switch('holdOnPress'));
    expect(h.settings.get(Settings.holdDanmakuOnPress), isFalse);

    await pumpSettings(tester);
    await searchSettingsFor(tester, '按住');
    expect(settingsRow('danmaku_hold_on_press'), findsOneWidget);
    expect(find.text('弹幕 › 画面弹幕交互'), findsOneWidget);
  });

  test('its route opens the page', () {
    final page = pageRoutes[RoutePath.kDanmakuSettings]!(const RouteArgs(RoutePath.kDanmakuSettings));
    expect(page, isA<DanmakuSettingsPage>());
  });

  group('A08.12: the gift switches', () {
    Finder row(String key) => find.byKey(ValueKey('danmaku-setting-$key'));

    testWidgets('"只显示值钱的礼物" and "礼物价值换算成元" under "在聊天列表显示礼物", greyed while it is off; all off', (tester) async {
      final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
      final list = find.byType(ChatListSettings);
      for (final key in ['gifts', 'valuableGifts', 'giftYuan']) {
        expect(
          find.descendant(of: list, matching: row(key)),
          findsOneWidget,
          reason: key,
        );
      }
      expectInOrder(tester, [row('gifts'), row('valuableGifts'), row('giftYuan')]);
      expect(find.text('只显示值钱的礼物'), findsOneWidget);
      expect(find.text('礼物价值换算成元'), findsOneWidget);
      for (final key in ['valuableGifts', 'giftYuan', 'showGifts']) {
        expect(tester.widget<Switch>(_switch(key)).value, isFalse, reason: '$key: off by default (D-040)');
      }
      await tapSettings(tester, _switch('valuableGifts'));
      expect(h.settings.get(Settings.chatGiftsAboveTier), isTrue);
      await tapSettings(tester, _switch('giftYuan'));
      expect(h.settings.get(Settings.giftValueInYuan), isTrue);

      // The gifts off: the two grey out (D4), keeping their values.
      await tapSettings(tester, _switch('gifts'));
      for (final key in ['valuableGifts', 'giftYuan']) {
        final control = tester.widget<Switch>(_switch(key));
        expect(control.value, isTrue, reason: key);
        expect(control.onChanged, isNull, reason: key);
      }
      await tapSettings(tester, _switch('valuableGifts'));
      expect(h.settings.get(Settings.chatGiftsAboveTier), isTrue, reason: 'a grey row does nothing');
    });

    testWidgets('"飞行弹幕显示礼物" is in "显示范围", after "暂停时的弹幕"; the same content the room and multi-view show', (
      tester,
    ) async {
      final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
      final content = find.byType(DanmakuSettingsContent);
      expect(find.descendant(of: content, matching: row('showGifts')), findsOneWidget);
      expect(find.descendant(of: find.byType(ChatListSettings), matching: row('showGifts')), findsNothing);
      expectInOrder(tester, [
        find.text('显示范围'),
        find.byKey(const ValueKey('danmaku-paused-behavior')),
        row('showGifts'),
        find.text('样式'),
      ]);
      expect(find.text('飞行弹幕显示礼物'), findsOneWidget);
      await tapSettings(tester, _switch('showGifts'));
      expect(h.settings.get(Settings.danmakuShowGifts), isTrue);
    });

    testWidgets('large text (2x) in a 360 wide page: the rows wrap, nothing overflows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSettings(tester, width: 360, height: 9000, arguments: 'danmaku');
      for (final key in ['valuableGifts', 'giftYuan', 'showGifts']) {
        expect(row(key), findsOneWidget, reason: key);
        expect(tester.getRect(row(key)).right, lessThanOrEqualTo(360), reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('D07.2: "上舰和开会员进醒目留言" after the gift rows, on by default, not greyed by the gift switch; '
        'search finds it', (tester) async {
      final h = await pumpSettings(tester, height: 6000, arguments: 'danmaku');
      final list = find.byType(ChatListSettings);
      expect(find.descendant(of: list, matching: row('membershipCards')), findsOneWidget);
      expectInOrder(tester, [row('gifts'), row('valuableGifts'), row('giftYuan'), row('membershipCards')]);
      expect(find.text('上舰和开会员进醒目留言'), findsOneWidget);
      expect(tester.widget<Switch>(_switch('membershipCards')).value, isTrue, reason: 'on by default (D-040)');
      await tapSettings(tester, _switch('gifts'));
      expect(tester.widget<Switch>(_switch('membershipCards')).onChanged, isNotNull, reason: 'its own switch');
      await tapSettings(tester, _switch('membershipCards'));
      expect(h.settings.get(Settings.superChatIncludesMembership), isFalse);

      await pumpSettings(tester);
      for (final words in ['上舰', '醒目留言 会员']) {
        await searchSettingsFor(tester, words);
        expect(settingsRow('danmaku_membership_cards'), findsOneWidget, reason: words);
      }
      expect(find.text('弹幕 › 弹幕列表'), findsWidgets);
    });

    testWidgets('search finds the three: two under "弹幕 › 弹幕列表", one under "弹幕 › 显示范围"', (tester) async {
      await pumpSettings(tester);
      await searchSettingsFor(tester, '值钱');
      expect(settingsRow('danmaku_valuable_gifts'), findsOneWidget);
      expect(find.text('弹幕 › 弹幕列表'), findsOneWidget);
      await searchSettingsFor(tester, '换算成元');
      expect(settingsRow('danmaku_gift_yuan'), findsOneWidget);
      await searchSettingsFor(tester, '飞行 礼物');
      expect(settingsRow('danmaku_fly_gifts'), findsOneWidget);
      expect(find.text('弹幕 › 显示范围'), findsOneWidget);
    });
  });
}
