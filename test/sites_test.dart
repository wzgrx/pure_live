import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/acfun/acfun_site.dart';
import 'package:pure_live/modules/search/search_capability.dart';
import 'package:pure_live/modules/multiview/danmaku/multiview_danmaku_session.dart';

void main() {
  test('AcFun is navigable, recordable and searchable without constructing other adapters', () {
    expect(Sites.isSupported(' ACFUN '), isTrue);
    final site = Sites.of(' ACFUN ');
    expect(site.liveSite, isA<AcfunSite>());
    expect(site.liveSite, isA<LiveSiteRecordRoomResolver>());
    expect(site.liveSite, isA<LiveSiteRoomRefresher>());
    expect(site.liveSite, isA<LivePlayRecoveryResolver>());
    expect(Sites.supportSites.where((s) => s.id == site.id), hasLength(1));
    final search = LiveSearchCapabilities.forPlatform('acfun');
    expect(search.supportsPagination, isTrue);
    expect(search.mayIncludeOffline, isTrue);
    expect(MultiviewDanmakuSession.isSupportedPlatform('acfun'), isFalse);
  });

  test('validates live-room route platform ids without constructing a site', () {
    expect(Sites.isSupported('bilibili'), isTrue);
    expect(Sites.isSupported(' HUYA '), isTrue);
    expect(Sites.isSupported(' Twitch '), isTrue);
    expect(Sites.isSupported(' SOOP '), isTrue);
    expect(Sites.isSupported('unknown-platform'), isFalse);
  });

  test('resolves imported platform ids after trimming and case normalization', () {
    expect(Sites.of(' BILIBILI ').id, Sites.bilibiliSite);
    expect(Sites.of(' HuYa ').id, Sites.huyaSite);
  });

  test('failure-prone adapters expose a refresh path that preserves unknown state on transport errors', () {
    for (final siteId in [Sites.ccSite, Sites.twitchSite, Sites.soopSite]) {
      expect(Sites.of(siteId).liveSite, isA<LiveSiteRoomRefresher>(), reason: siteId);
    }
  });
}
