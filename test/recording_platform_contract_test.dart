import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';

void main() {
  test('every built-in platform exposes strict playback-complete recording metadata', () {
    expect(
      Sites.supportedSiteIds,
      unorderedEquals(const [
        Sites.bilibiliSite,
        Sites.douyuSite,
        Sites.huyaSite,
        Sites.douyinSite,
        Sites.kuaishouSite,
        Sites.ccSite,
        Sites.twitchSite,
        Sites.soopSite,
        Sites.yySite,
        Sites.acfunSite,
        Sites.iptvSite,
      ]),
    );
    for (final siteId in Sites.supportedSiteIds) {
      expect(Sites.of(siteId).liveSite, isA<LiveSiteRecordRoomResolver>(), reason: siteId);
    }
  });

  test('per-CDN signing platforms expose the lazy recording line cursor', () {
    for (final siteId in const <String>[Sites.douyuSite, Sites.huyaSite]) {
      expect(Sites.of(siteId).liveSite, isA<LivePlayUrlCursorResolver>(), reason: siteId);
    }
  });
}
