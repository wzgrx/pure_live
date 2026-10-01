import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';

/// The popular page's catalogues, one feed per platform, kept while the app
/// runs (3.x kept a GetX controller per platform), so switching tabs or
/// home menus does not fetch again.
final class PopularCatalog {
  /// Creates the catalogues over [services]; `probe` reads the network
  /// before each refresh (offline check, mobile-data notice).
  new(this.services, {this._probe = readNetworkKind}) {
    _settings = services.store.settings.changes.listen(_settingChanged);
  }

  /// The services.
  final AppServices services;

  final NetworkProbe _probe;
  final Map<String, RoomFeed> _feeds = {};
  late final StreamSubscription<Setting<Object>> _settings;
  Timer? _rankTimer;

  /// The platform shown last (kept across home menu switches).
  String? currentPlatform;

  /// The desktop page size picked on the page (3.x kept it per session).
  int? pageSize;

  /// Called when the current platform should refresh after a ranking change.
  void Function()? onRankingChanged;

  SettingsStore get _store => services.store.settings;

  /// The audience settings now.
  AudiencePolicy get policy => AudiencePolicy.of(_store);

  /// Whether rooms that cannot play are shown.
  bool get showUnplayable => _store.get(Settings.showUnplayableInDiscover);

  /// Whether [room] is shown.
  bool visible(LiveRoom room) =>
      showUnplayable || !cannotPlayHere(room, signedIn: signedInOn(services.cookies, room.platform));

  /// The feed of [platform].
  RoomFeed feedOf(String platform) => _feeds[platform] ??= RoomFeed(
    platform: platform,
    source: popularSourceFor(services.sites.of(platform)),
    // IPTV keeps the playlist's order (3.x).
    rank: (id, rooms) => id == SiteIds.iptv ? rooms : policy.rank(rooms),
    visible: visible,
    precheck: () => MobileDataNotice.precheck(_probe),
  );

  void _settingChanged(Setting<Object> setting) {
    final key = setting.key;
    if (key == Settings.showUnplayableInDiscover.key) {
      for (final feed in _feeds.values) {
        feed.visibilityChanged();
      }
    } else if (key == Settings.preferRealOnlineCounts.key || key == Settings.realOnlinePlatforms.key) {
      // 3.x refreshed the current platform 160 ms after the change; the
      // others refresh when they are shown again.
      for (final feed in _feeds.values) {
        feed
          ..markStale()
          ..visibilityChanged();
      }
      _rankTimer?.cancel();
      _rankTimer = Timer(const Duration(milliseconds: 160), () => onRankingChanged?.call());
    }
  }

  /// Releases the feeds.
  void dispose() {
    _rankTimer?.cancel();
    unawaited(_settings.cancel());
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    _feeds.clear();
  }
}

/// The catalogues (kept for the app's life, like 3.x's controllers).
final Provider<PopularCatalog> popularCatalogProvider = Provider((ref) {
  final catalog = PopularCatalog(ref.watch(appServicesProvider), probe: ref.watch(networkProbeProvider));
  ref.onDispose(catalog.dispose);
  return catalog;
});
