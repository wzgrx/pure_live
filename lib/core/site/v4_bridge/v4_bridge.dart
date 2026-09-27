import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/common/proxy_routing.dart';
import 'package:pure_live/core/site/v4_bridge/v4_platforms.dart';
import 'package:pure_live/model/live_category.dart';

/// The 3.3.x bridge from the legacy site interface to the v4 platform layer
/// for lists, search and links (docs/adr/0012-legacy-bridge.md).
class V4Bridge {
  V4Bridge._(this._http);

  /// A bridge over [http], for tests.
  @visibleForTesting
  factory V4Bridge.withHttp(LiveHttp http) => V4Bridge._(http);

  static V4Bridge? _instance;

  /// The app-wide bridge: dart:io transport following the app proxy setting.
  static V4Bridge get instance => _instance ??= V4Bridge._(IoLiveHttp(proxy: const _AppProxyPolicy()));

  /// Replaces the app-wide bridge in tests.
  @visibleForTesting
  static set instance(V4Bridge? bridge) => _instance = bridge;

  /// Whether [platform] runs its lists, search and links on v4.
  static bool handles(String? platform) =>
      platform != null && (platformsOverride ?? v4BridgePlatforms).contains(platform);

  /// Replaces [v4BridgePlatforms] in tests; the legacy expected-value tests
  /// set it to empty so they keep exercising the legacy parsers.
  @visibleForTesting
  static Set<String>? platformsOverride;

  final LiveHttp _http;
  final Map<String, Object> _sites = {};

  /// Cursor needed to fetch `<key>#<page>`; a stored null means that page is
  /// past the end.
  final Map<String, PageCursor?> _cursors = {};

  Object _site(String platform) => _sites.putIfAbsent(
    platform,
    () => switch (platform) {
      'douyu' => DouyuSite(_http),
      _ => throw StateError('No v4 adapter for $platform'),
    },
  );

  /// Legacy pages are numbered; v4 pages are cursors. Walk from page 1 when a
  /// cursor is not cached yet, never guess one.
  Future<Page<RoomCard>> _page(String key, int page, Future<Page<RoomCard>> Function(PageCursor?) fetch) async {
    PageCursor? cursor;
    if (page > 1) {
      final slot = '$key#$page';
      if (!_cursors.containsKey(slot)) await _page(key, page - 1, fetch);
      if (!_cursors.containsKey(slot)) return const Page.empty();
      cursor = _cursors[slot];
      if (cursor == null) return const Page.empty();
    }
    final result = await fetch(cursor);
    _cursors['$key#${page + 1}'] = result.next;
    return result;
  }

  /// Legacy `getCategores`.
  Future<List<LiveCategory>> categories(String platform) async {
    final categories = await (_site(platform) as CatalogSource).categories();
    return [
      for (final category in categories)
        LiveCategory(
          id: category.id,
          name: category.name,
          children: [
            for (final area in category.areas)
              LiveArea(
                platform: platform,
                areaType: category.id,
                typeName: category.name,
                areaId: area.id,
                areaName: area.name,
                areaPic: area.icon?.toString() ?? '',
              ),
          ],
        ),
    ];
  }

  /// Legacy `getCategoryRooms`.
  Future<List<LiveRoom>> areaRooms(String platform, LiveArea area, int page) async {
    final site = _site(platform) as CatalogSource;
    final v4Area = Area(id: area.areaId ?? '', name: area.areaName ?? '', categoryId: area.areaType ?? '');
    final result = await _page(
      '$platform|area|${area.areaId}',
      page,
      (cursor) => site.areaRooms(v4Area, cursor: cursor),
    );
    return [for (final card in result.items) liveRoomFromCard(card)];
  }

  /// Legacy `getRecommendRooms`.
  Future<List<LiveRoom>> recommended(String platform, int page) async {
    final site = _site(platform) as CatalogSource;
    final result = await _page('$platform|recommend', page, (cursor) => site.recommended(cursor: cursor));
    return [for (final card in result.items) liveRoomFromCard(card)];
  }

  /// Legacy `searchRooms`.
  Future<List<LiveRoom>> search(String platform, String keyword, int page) async {
    final site = _site(platform) as SearchSource;
    final result = await _page('$platform|search|$keyword', page, (cursor) => site.search(keyword, cursor: cursor));
    return [for (final card in result.items) liveRoomFromCard(card)];
  }

  /// A link or share text resolved by the platform's v4 resolver.
  Future<RoomRef?> resolve(String platform, String input) => (_site(platform) as LinkResolver).resolve(input);

  /// The legacy card for a v4 card.
  @visibleForTesting
  static LiveRoom liveRoomFromCard(RoomCard card) {
    final audience = card.audience;
    final (metric, value) = switch (audience) {
      Audience(online: final online?) => (AudienceMetricType.onlineViewers, online),
      Audience(popularity: final heat?) => (AudienceMetricType.popularity, heat),
      Audience(cumulative: final total?) => (AudienceMetricType.totalViewers, total),
      _ => (AudienceMetricType.unknown, null),
    };
    return LiveRoom(
      roomId: card.ref.roomId,
      title: card.title,
      nick: card.anchorName,
      avatar: card.avatar?.toString() ?? '',
      cover: card.cover?.toString() ?? '',
      area: card.area ?? '',
      watching: value?.toString() ?? '0',
      audienceMetricType: metric,
      popularity: audience.popularity?.toString() ?? '',
      onlineViewers: audience.online?.toString() ?? '',
      totalViewers: audience.cumulative?.toString() ?? '',
      platform: card.ref.platform,
      liveStatus: switch (card.state) {
        LiveState.live => LiveStatus.live,
        LiveState.offline => LiveStatus.offline,
        LiveState.replay => LiveStatus.replay,
      },
      status: card.state == LiveState.live,
      isRecord: card.state == LiveState.replay,
    );
  }
}

/// The app proxy setting, read per request like the legacy Dio client.
final class _AppProxyPolicy implements ProxyPolicy {
  const _AppProxyPolicy();

  @override
  ProxyRoute routeFor(String site, Uri url) {
    final proxy = SettingsService.to.proxy;
    final directive = buildProxyDirective(
      enabled: proxy.enableAppProxy.value,
      host: proxy.appProxyHost.value,
      port: proxy.appProxyPort.value,
    );
    if (!directive.startsWith('PROXY ')) return const DirectRoute();
    final endpoint = directive.substring(6);
    final colon = endpoint.lastIndexOf(':');
    return HttpProxyRoute(endpoint.substring(0, colon), int.parse(endpoint.substring(colon + 1)));
  }
}
