import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/settings/platforms_page.dart';

void main() {
  test('F-DSC-03: rows follow the stored order, hidden platforms after them', () {
    final rows = platformRows(['huya', 'kick', 'douyu']);
    expect(rows.take(2).toList(), [('huya', true), ('douyu', true)]);
    expect(rows.where((row) => !row.$2).map((row) => row.$1), [
      for (final id in platformOrder)
        if (id != 'huya' && id != 'douyu') id,
    ]);
  });

  test('F-DSC-03: saving keeps the order and the slots of retired platforms', () {
    final rows = [('douyu', true), ('huya', false), ('bilibili', true)];
    expect(storedPlatforms(rows, ['huya', 'kick', 'douyu']), ['douyu', 'bilibili', 'kick']);
  });

  test('F-DSC-03: platforms a new version adds join the list once; hidden ones stay hidden', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    await store.settings.set(Settings.catalogPlatforms, ['douyu']);
    await appendNewPlatforms(store);
    expect(store.settings.get(Settings.catalogPlatforms), ['douyu'], reason: 'the first run only records');

    await store.meta.set('catalog.knownPlatforms', 'douyu,huya');
    await appendNewPlatforms(store);
    expect(store.settings.get(Settings.catalogPlatforms), [
      'douyu',
      for (final id in platformOrder)
        if (id != 'douyu' && id != 'huya') id,
    ]);
    // Hiding one afterwards sticks: it is known now.
    await store.settings.set(Settings.catalogPlatforms, ['douyu']);
    await appendNewPlatforms(store);
    expect(store.settings.get(Settings.catalogPlatforms), ['douyu']);
  });

  test('every platform in the order has a name, the stored default lists them all', () {
    expect(platformNames.keys.toSet(), platformOrder.toSet());
    expect(Settings.catalogPlatforms.defaultValue, platformOrder);
    expect(platformName('bigo'), 'Bigo Live', reason: 'not registered yet (ADR 0031), follows still read well');
  });

  test('discover lists catalog platforms only, search native-search ones only', () {
    final http = ReplayHttp(const []);
    final container = ProviderContainer(
      overrides: [
        sitesProvider.overrideWithValue({
          'tiktok': PlatformSite(TikTokSite(http)),
          'jdlive': PlatformSite(JdLiveSite(http)),
          'youtube': PlatformSite(YouTubeSite(http)),
        }),
        enabledPlatformsProvider.overrideWithValue(['tiktok', 'jdlive', 'youtube']),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(browsablePlatformsProvider), ['jdlive', 'youtube'], reason: 'TikTok is link-only');
    expect(container.read(searchablePlatformsProvider), ['youtube'], reason: 'JD has no search');
  });
}
