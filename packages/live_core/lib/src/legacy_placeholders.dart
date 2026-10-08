import 'package:live_core/src/sites.dart';

/// The stand-in names 3.x (`v3.2.11`) wrote as a room's nick and title when
/// the platform did not give one, by platform id. 4.x adapters no longer
/// write them (UPGRADES X-2, 28-2), but rooms 3.x stored keep them; the
/// migration (J06.2) uses this table to clear them. Data only: nothing here
/// changes a stored room.
///
/// - JD Live: `lib/core/site/jdlive/jd_live_api.dart:231-232`, `:261-262`
///   (replaced on merge at `:52-53`);
/// - Kugou Live: `lib/core/site/kugoulive/kugou_live_api.dart:396-397`,
///   `:505-506` (`:92-93`);
/// - Baidu Live: `lib/core/site/baidulive/baidu_live_api.dart:390`
///   (`:89-90`).
const Map<String, Set<String>> legacyPlaceholderNames = {
  SiteIds.jdLive: {'JD Live'},
  SiteIds.kugouLive: {'Kugou Live'},
  SiteIds.baiduLive: {'Baidu Live'},
};
