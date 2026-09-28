@Tags(['screenshots'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import 'shot_harness.dart';

/// 关注, 发现 and 搜索 (principles §4.1, §5.2) across the width classes.
void main() {
  screenshotSetUp();

  group('follows', () {
    Future<void> follows(ShotApp app) => app.go('/follows');

    screenshot('follows', ShotScreen.phone, follows);
    screenshot('follows', ShotScreen.phone, follows, theme: ShotTheme.dark);
    screenshot('follows', ShotScreen.phone, follows, textScale: 2);
    screenshot('follows', ShotScreen.phoneLandscape, follows);
    screenshot('follows-banner', ShotScreen.medium, follows, world: () => ShotWorld(failedPlatforms: {'huya'}));
    screenshot('follows', ShotScreen.expanded, follows, theme: ShotTheme.dark);
    screenshot('follows', ShotScreen.large, follows);
    screenshot('follows', ShotScreen.extraLarge, follows, theme: ShotTheme.dark);
    screenshot('follows-empty', ShotScreen.phone, follows, world: () => ShotWorld(follows: false));
    // principles §3.3: the banner wraps its actions under the text on a phone.
    screenshot(
      'follows-banner',
      ShotScreen.phone,
      follows,
      world: () => ShotWorld(failedPlatforms: {'huya'}),
      theme: ShotTheme.dark,
    );
    // principles §3.3: nobody live under 开播, and a failed read.
    screenshot(
      'follows-nonelive',
      ShotScreen.phone,
      (app) => app.go(followsLiveLocation),
      world: () => ShotWorld(anyoneLive: false),
    );
    screenshot(
      'follows-error',
      ShotScreen.phone,
      follows,
      world: () => ShotWorld(followsFail: true),
      theme: ShotTheme.dark,
    );

    Finder card(String name) => find.byWidgetPredicate((widget) => widget is RoomCardView && widget.anchorName == name);

    // F-FAV-09: 多选 from the card menu; then taps choose (a row too).
    screenshot('follows-select', ShotScreen.phone, (app) async {
      await follows(app);
      await app.tester.longPress(card('夜航星'));
      await app.frames();
      await app.tester.tap(find.text(t.follows.select));
      await app.frames();
      await app.tester.tap(card('北岛看海'));
      await app.tester.tap(card('橘子汽水'));
      await app.frames(3);
    });
    // Desktops: Ctrl-click starts it, Shift-click adds a range.
    screenshot('follows-select', ShotScreen.large, (app) async {
      await follows(app);
      final keys = app.tester;
      await keys.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await keys.tap(card('夜航星'), kind: PointerDeviceKind.mouse);
      await keys.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await keys.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await keys.tap(card('橘子汽水'), kind: PointerDeviceKind.mouse);
      await keys.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await app.frames(3);
    }, theme: ShotTheme.dark);
    // principles §5.2: on a landscape phone the top bar scrolls away.
    screenshot('follows-scrolled', ShotScreen.phoneLandscape, (app) async {
      await follows(app);
      await app.tester.drag(find.byType(CustomScrollView).first, const Offset(0, -240));
      await app.frames();
    });
  });

  group('discover', () {
    Future<void> discover(ShotApp app) => app.go('/discover');
    ShotWorld loading() => ShotWorld(catalog: ListMode.loading);
    ShotWorld failing() => ShotWorld(catalog: ListMode.error);

    screenshot('discover', ShotScreen.phone, discover);
    screenshot('discover', ShotScreen.phone, discover, locale: AppLocale.zhHant);
    screenshot('discover', ShotScreen.phone, discover, locale: AppLocale.en);
    screenshot('discover', ShotScreen.phone, discover, theme: ShotTheme.dark);
    screenshot('discover', ShotScreen.phoneLandscape, discover, theme: ShotTheme.dark);
    screenshot('discover', ShotScreen.medium, discover, theme: ShotTheme.dark);
    screenshot('discover', ShotScreen.expanded, discover);
    screenshot('discover', ShotScreen.large, discover, theme: ShotTheme.dark, locale: AppLocale.en);
    screenshot('discover', ShotScreen.extraLarge, discover);
    screenshot('discover-loading', ShotScreen.phone, discover, world: loading);
    screenshot('discover-loading', ShotScreen.large, discover, world: loading, theme: ShotTheme.dark);
    // The app retries a network failure twice (1 s, 2 s), then explains it:
    // the error must be on screen within 4 s (networkRetry).
    Future<void> failed(ShotApp app) async {
      await discover(app);
      await app.frames(4, const Duration(seconds: 1));
    }

    screenshot('discover-error', ShotScreen.phone, failed, world: failing);
    screenshot('discover-error', ShotScreen.expanded, failed, world: failing, theme: ShotTheme.dark);
    screenshot('discover-areas', ShotScreen.phone, (app) async {
      await discover(app);
      await app.tester.tap(find.text(t.discover.areas).first);
      await app.frames();
    });
  });

  group('search', () {
    Future<void> search(ShotApp app) => app.go(searchLocation('英雄联盟'));
    ShotWorld nothing() => ShotWorld(search: ListMode.empty);

    screenshot('search', ShotScreen.phone, search);
    screenshot('search', ShotScreen.phone, search, theme: ShotTheme.dark, locale: AppLocale.en);
    screenshot('search', ShotScreen.expanded, search);
    screenshot('search', ShotScreen.large, search, theme: ShotTheme.dark);
    screenshot('search', ShotScreen.extraLarge, search);
    screenshot('search-empty', ShotScreen.phone, search, world: nothing);
    screenshot('search-empty', ShotScreen.large, search, world: nothing, theme: ShotTheme.dark);
    // principles §4.1: a pasted room link offers 打开直播间 at the top.
    screenshot(
      'search-link',
      ShotScreen.phone,
      (app) => app.go(searchLocation('https://www.douyu.com/288016')),
      overrides: (world) => [linkResolverProvider.overrideWithValue((input) async => RoomRef('douyu', '288016'))],
    );
    screenshot('search', ShotScreen.medium, search, locale: AppLocale.zhHant);
    screenshot('search-empty', ShotScreen.phone, search, world: nothing, theme: ShotTheme.dark, locale: AppLocale.en);

    // F-SRC-06: a focused, empty box lists the recent searches.
    Future<void> history(ShotApp app) async {
      final store = app.container.read(storeProvider);
      await app.tester.runAsync(() async {
        for (final (index, keyword) in ['原神', 'LOL', '王者荣耀', '英雄联盟 大师分段', '户外 川西', 'Chill stream'].indexed) {
          await store.searchHistory.record(keyword, at: DateTime.utc(2026, 9, 27, 20, index));
        }
      });
      await app.go('/search');
      await app.tester.tap(find.byType(TextField));
      await app.tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await app.frames();
    }

    screenshot('search-history', ShotScreen.phone, history);
    screenshot('search-history', ShotScreen.large, history, theme: ShotTheme.dark, locale: AppLocale.en);
  });
}
