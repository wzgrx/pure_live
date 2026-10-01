import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/popular/popular_feed.dart';

/// The platform's display name (3.x `site_<id>` texts, else the adapter's).
String platformDisplayName(String platform, {String? fallback}) =>
    i18nOr('site_$platform', fallback ?? platform.toUpperCase());

/// 3.x `readableCount`: a whole number shown as `1.2万` (Chinese) or `1.2K`
/// (English); other texts as they are.
String readableAudience(String value) {
  final count = int.tryParse(value.trim());
  if (count == null) return value;
  final english = currentStrings?.language == AppLanguage.en;
  if (!english && count >= 10000) return '${(count / 10000).toStringAsFixed(1)}${i18n('count_wan')}';
  if (english && count >= 1000) return '${(count / 1000).toStringAsFixed(1)}${i18n('count_k')}';
  return value;
}

/// The words of a card's restriction mark (UPGRADES "卡片标出受限类型"); a
/// carousel is marked too (1-1). Null for a room without one.
String? restrictionLabel(LiveRoom room) {
  if (room.effectiveLiveStatus == LiveStatus.carousel) return i18n('popular_status_carousel');
  return switch (room.effectiveRestriction) {
    LiveRestriction.none => null,
    LiveRestriction.needsLogin => i18n('popular_restriction_login'),
    LiveRestriction.paid => i18n('popular_restriction_paid'),
    LiveRestriction.subscribersOnly => i18n('popular_restriction_subscribers'),
    LiveRestriction.private => i18n('popular_restriction_private'),
    LiveRestriction.appOnly => i18n('popular_restriction_app_only'),
    LiveRestriction.regionBlocked => i18n('popular_restriction_region'),
    LiveRestriction.password => i18n('popular_restriction_password'),
    LiveRestriction.adult => i18n('popular_restriction_adult'),
    LiveRestriction.unplayable => i18n('popular_restriction_unplayable'),
  };
}

/// Whether [room] cannot be played here (UPGRADES 统一原则: discovery pages
/// hide such rooms unless the user shows them): a carousel, or a restriction
/// this client cannot pass. A login or age check counts only while the
/// platform has no cookie ([signedIn]).
bool cannotPlayHere(LiveRoom room, {required bool signedIn}) {
  if (room.effectiveLiveStatus == LiveStatus.carousel) return true;
  return switch (room.effectiveRestriction) {
    LiveRestriction.none => false,
    LiveRestriction.needsLogin || LiveRestriction.adult => !signedIn,
    _ => true,
  };
}

/// The audience settings a card and the ranking use (3.x
/// `preferRealOnlineCounts`, `realOnlinePlatforms`).
final class AudiencePolicy {
  /// Creates the policy.
  const new({required this.preferRealOnline, required this.realOnlinePlatforms});

  /// Reads the policy from [settings].
  factory of(SettingsStore settings) => AudiencePolicy(
    preferRealOnline: settings.get(Settings.preferRealOnlineCounts),
    realOnlinePlatforms: {for (final id in settings.get(Settings.realOnlinePlatforms)) id.trim().toLowerCase()},
  );

  /// Show concurrent viewers where the platform has them.
  final bool preferRealOnline;

  /// The platforms that setting applies to.
  final Set<String> realOnlinePlatforms;

  /// Whether the setting applies to [platform].
  bool enabledFor(String platform) => realOnlinePlatforms.contains(platform.trim().toLowerCase());

  /// [rooms] by audience, largest first (3.x `rankPopularRoomsByAudience`).
  List<LiveRoom> rank(List<LiveRoom> rooms) => [...rooms]
    ..sort(
      (left, right) =>
          LiveRoom.compareAudienceRanking(left, right, preferRealOnline: preferRealOnline, platformEnabled: enabledFor),
    );

  /// The audience a card shows (`audience.dart`: concurrent viewers when the
  /// setting applies, else heat, cumulative, concurrent).
  RoomAudience audienceOf(LiveRoom room) {
    final enabled = enabledFor(room.platform);
    final value = room.audienceValue(preferRealOnline: preferRealOnline, platformEnabled: enabled);
    final type = room.audienceType(preferRealOnline: preferRealOnline, platformEnabled: enabled);
    return RoomAudience(
      kind: switch (type) {
        AudienceMetricType.popularity => RoomAudienceKind.popularity,
        AudienceMetricType.onlineViewers => RoomAudienceKind.onlineViewers,
        AudienceMetricType.totalViewers => RoomAudienceKind.totalViewers,
        AudienceMetricType.followers => RoomAudienceKind.followers,
        AudienceMetricType.unknown => RoomAudienceKind.unknown,
      },
      value: value.isEmpty ? '' : readableAudience(value),
    );
  }

  /// What a card shows for [room].
  RoomCardData cardOf(LiveRoom room) => RoomCardData(
    platformId: room.platform,
    title: room.title,
    anchorName: room.displayNick(platformDisplayName(room.platform)),
    avatarUrl: normalizeImageUrl(room.avatar),
    coverUrl: normalizeImageUrl(room.cover),
    isLive: room.isLiveNow,
    isReplay: room.isRecord,
    audience: audienceOf(room),
    restrictionLabel: restrictionLabel(room),
  );
}

/// Whether this device takes the phone forms (3.x `PlatformUtils.isMobile`).
bool get isPhoneDevice => Platform.isAndroid || Platform.isIOS;

/// The card appearance of this device (3.x `RoomCardSettingsController.resolve`:
/// the phone settings on Android, the desktop ones elsewhere; an empty
/// stored config uses the preset).
RoomCardAppearance cardAppearanceOf(SettingsStore settings, {bool? phone}) {
  final mobile = phone ?? isPhoneDevice;
  final preset = settings.get(mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset);
  final base = RoomCardAppearance.fromPreset(
    RoomCardPreset.values.firstWhere((value) => value.storageKey == preset, orElse: () => RoomCardPreset.standard),
  );
  final config = settings.get(mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig);
  return config.isEmpty ? base : RoomCardAppearance.fromJson(Map<String, dynamic>.of(config), fallback: base);
}

/// Rooms per desktop page and the choices (3.x `PageSettingsController`:
/// 0 or a missing size means 20 above 960 px, else 12).
({int size, List<int> options}) pageSizesOf(SettingsStore settings, double width) {
  final wide = width > 960;
  final raw = settings.get(Settings.pageSizeOptions);
  final parsed = {
    for (final match in RegExp(r'\d+').allMatches(raw))
      if (int.tryParse(match.group(0)!) case final value? when value >= 1 && value <= 100) value,
  }.toList()..sort();
  final options = parsed.isEmpty ? (wide ? const [20, 40, 60, 80] : const [12, 24, 36, 48]) : parsed;
  final stored = settings.get(Settings.pageDefaultSize);
  final size = stored > 0 && options.contains(stored) ? stored : (stored > 0 ? options.first : (wide ? 20 : 12));
  return (size: size, options: options.contains(size) ? options : ([...options, size]..sort()));
}

/// The popular page's catalogues, one feed per platform, kept while the app
/// runs (3.x kept a GetX controller per platform), so switching tabs or
/// home menus does not fetch again.
final class PopularCatalog {
  /// Creates the catalogues over [services].
  new(this.services) {
    _settings = services.store.settings.changes.listen(_settingChanged);
  }

  /// The services.
  final AppServices services;

  final Map<String, PopularFeed> _feeds = {};
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
      showUnplayable ||
      !cannotPlayHere(room, signedIn: services.cookies.cookieFor(room.platform)?.trim().isNotEmpty ?? false);

  /// The feed of [platform].
  PopularFeed feedOf(String platform) => _feeds[platform] ??= PopularFeed(
    platform: platform,
    source: popularSourceFor(services.sites.of(platform)),
    // IPTV keeps the playlist's order (3.x).
    rank: (id, rooms) => id == SiteIds.iptv ? rooms : policy.rank(rooms),
    visible: visible,
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
  final catalog = PopularCatalog(ref.watch(appServicesProvider));
  ref.onDispose(catalog.dispose);
  return catalog;
});
