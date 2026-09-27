@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/app/routes.dart';
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
    // Riverpod retries a failed list with backoff before the error shows.
    Future<void> failed(ShotApp app) async {
      await discover(app);
      await app.frames(60, const Duration(seconds: 1));
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
  });
}
