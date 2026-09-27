import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/core/store.dart';

/// A platform adapter seen through its capabilities (ADR 0010, rule 7). The
/// first five platforms implement all of them.
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

/// Platform ids in display order (constitution: first five platforms).
const platformOrder = ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'];

/// Short display names for tabs and badges.
const platformNames = {'bilibili': '哔哩哔哩', 'douyu': '斗鱼', 'huya': '虎牙', 'douyin': '抖音', 'kuaishou': '快手'};

/// The user's platform cookies. In memory until live_store's encrypted vault
/// is wired in.
final cookieVaultProvider = Provider<CookieVault>((ref) {
  final vault = MemoryCookieVault();
  ref.onDispose(vault.dispose);
  return vault;
});

/// Shared HTTP transport for every adapter.
final liveHttpProvider = Provider<LiveHttp>((ref) {
  final http = IoLiveHttp();
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
