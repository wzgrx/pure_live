import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// A platform adapter seen through its capabilities (ADR 0010, rule 7). The
/// first five platforms and the IPTV source implement all of them.
final class PlatformSite {
  const new(this._site);

  final Object _site;

  /// The adapter itself, for packages that look capabilities up by type.
  Object get raw => _site;

  LiveSite get info => _site as LiveSite;
  CatalogSource get catalog => _site as CatalogSource;
  SearchSource get search => _site as SearchSource;
  RoomSource get rooms => _site as RoomSource;
  StreamSource get streams => _site as StreamSource;
  LinkResolver get links => _site as LinkResolver;
}

/// Platform ids in display order (constitution: first five platforms, then
/// the later batches of ADR 0003), then the IPTV source (spec/modules/iptv.md §5).
const platformOrder = [
  'bilibili',
  'douyu',
  'huya',
  'douyin',
  'kuaishou',
  // Batch 2 (ADR 0003): all kept.
  'cc',
  'yy',
  'soop',
  'acfun',
  'twitch',
  // Batch 3 (ADR 0003): all kept.
  'chzzk',
  'missevan',
  'kilakila',
  'inke',
  'picarto',
  'twitcasting',
  'showroom',
  'pandalive',
  '17live',
  'iptv',
];

/// Short display names for tabs and badges, in the interface language
/// (F-APP-06; lib/i18n/*/sites.i18n.json). Every id of [platformOrder] has
/// one.
Map<String, String> get platformNames => t.sites.names;

/// Names of 3.x platforms this build has no adapter for, so their follows and
/// history still read well (spec/product.md F-FAV-08).
Map<String, String> get _otherPlatformNames => t.sites.otherNames;

/// The display name of any platform id, supported or not.
String platformName(String id) => platformNames[id] ?? _otherPlatformNames[id] ?? id;

/// A room on a platform this build has no adapter for: retired, or not ported
/// to v4 yet (spec/product.md F-FAV-08). Typed, so a page shows a notice
/// instead of failing on a missing adapter.
final class PlatformUnsupported implements Exception {
  /// Creates the error for [platform].
  const new(this.platform);

  /// The platform id.
  final String platform;

  @override
  String toString() => 'PlatformUnsupported($platform)';
}

/// Adapter lookup that fails with a type instead of a null check.
extension SiteLookup on Map<String, PlatformSite> {
  /// The adapter of [platform]; throws [PlatformUnsupported] when this build
  /// has none (F-FAV-08).
  PlatformSite of(String platform) => this[platform] ?? (throw PlatformUnsupported(platform));
}

/// Whether [platform] has accounts to sign in to (F-ACC-01): the platforms
/// whose adapters read the user's cookie. IPTV has none; CC and AcFun are
/// anonymous in v4 (spec/sites/cc.md §8, acfun.md §8), and so are the later
/// batches' adapters.
bool platformHasAccount(String platform) =>
    const {'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'yy', 'soop', 'twitch'}.contains(platform);

/// The user's platform cookies. In memory until live_store's encrypted vault
/// is wired in.
final cookieVaultProvider = Provider<CookieVault>((ref) {
  final vault = MemoryCookieVault();
  ref.onDispose(vault.dispose);
  return vault;
});

/// Shared HTTP transport for every adapter.
final liveHttpProvider = Provider<LiveHttp>((ref) {
  final http = IoLiveHttp(proxy: ref.watch(proxyPolicyProvider));
  ref.onDispose(http.close);
  return http;
});

/// Adapters by platform id.
final sitesProvider = Provider<Map<String, PlatformSite>>((ref) {
  final http = ref.watch(liveHttpProvider);
  final cookies = ref.watch(cookieVaultProvider);
  return {
    'bilibili': PlatformSite(BilibiliSite(http, cookies: cookies)),
    'douyu': PlatformSite(DouyuSite(http, cookies: cookies)),
    'huya': PlatformSite(HuyaSite(http, cookies: cookies)),
    'douyin': PlatformSite(DouyinSite(http, cookies: cookies)),
    'kuaishou': PlatformSite(KuaishouSite(http, cookies: cookies)),
    'cc': PlatformSite(CcSite(http)),
    'yy': PlatformSite(YySite(http, cookies: cookies)),
    'soop': PlatformSite(SoopSite(http, cookies: cookies)),
    'acfun': PlatformSite(AcfunSite(http)),
    'twitch': PlatformSite(TwitchSite(http, cookies: cookies)),
    'chzzk': PlatformSite(ChzzkSite(http)),
    'missevan': PlatformSite(MissevanSite(http)),
    'kilakila': PlatformSite(KilakilaSite(http)),
    'inke': PlatformSite(InkeSite(http)),
    'picarto': PlatformSite(PicartoSite(http)),
    'twitcasting': PlatformSite(TwitcastingSite(http)),
    'showroom': PlatformSite(ShowroomSite(http)),
    'pandalive': PlatformSite(PandaliveSite(http)),
    '17live': PlatformSite(SeventeenliveSite(http)),
    'iptv': PlatformSite(ref.watch(iptvSiteProvider)),
  };
});

/// Resolves a pasted link or share text to a room by asking every adapter;
/// null when none recognises it.
final linkResolverProvider = Provider<Future<RoomRef?> Function(String input)>((ref) {
  final sites = ref.watch(sitesProvider);
  return (input) async {
    for (final id in platformOrder) {
      final ref = await sites[id]!.links.resolve(input);
      if (ref != null) return ref;
    }
    return null;
  };
});

/// Platforms to show, in the user's order: the stored list filtered to the
/// platforms this build has adapters for (settings may name retired ones).
final enabledPlatformsProvider = Provider<List<String>>((ref) {
  final chosen = ref.watch(catalogPlatformsSetting).where(platformOrder.contains).toList();
  return chosen.isEmpty ? platformOrder : chosen;
});
