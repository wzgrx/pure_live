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
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';

import '../../support.dart';
import 'settings_harness.dart';

Finder _page() => find.byKey(const ValueKey('settings-page-danmaku'));

Finder _switch(String key) => find.byKey(ValueKey('danmaku-switch-$key'));

void main() {
  setUpAll(loadStrings);

  testWidgets("the overview row opens the room's danmaku settings, the same component", (tester) async {
    await pumpSettings(tester, height: 4000);
    await tapSettings(tester, settingsSection(SettingsSection.danmaku));
    expect(_page(), findsOneWidget);
    expect(find.widgetWithText(AppBar, '弹幕'), findsOneWidget);
    expect(find.descendant(of: _page(), matching: find.byType(DanmakuSettingsContent)), findsOneWidget);
    // As in the room's tab: "改动立即生效" right of the first group's title.
    expect(find.byKey(const ValueKey('panel-group-note')), findsOneWidget);
    expect(find.text('改动立即生效'), findsOneWidget);
    // The room's groups in its order, then "更多".
    expectInOrder(tester, [
      for (final title in ['观看模板', '显示范围', '样式', '重复弹幕', '画面弹幕交互', '流畅度', '更多']) find.text(title),
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

  test('its route opens the page', () {
    final page = pageRoutes[RoutePath.kDanmakuSettings]!(const RouteArgs(RoutePath.kDanmakuSettings));
    expect(page, isA<DanmakuSettingsPage>());
  });
}
