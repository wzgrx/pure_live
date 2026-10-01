import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A platform's name as 3.x showed it (`site_<id>`), else the adapter's.
String platformName(String id, SiteRegistry sites) {
  if (id == SiteIds.all) return i18n('site_all');
  return i18nOr('site_$id', sites.maybeOf(id)?.name ?? id);
}

/// [value] shortened as 3.x did (`readableCount`): 万 from 10000 in
/// Chinese, K from 1000 otherwise; anything not a whole number unchanged.
String readableCount(String value) {
  final count = int.tryParse(value.trim());
  if (count == null) return value;
  if (currentStrings?.language == AppLanguage.en) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}${i18n('count_k')}';
  } else if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}${i18n('count_wan')}';
  }
  return value;
}

/// How long [room] has been live, as a short text, or null when unknown or
/// not live (UPGRADES "开播时间": shown on the follow cards).
String? liveFor(LiveRoom room, DateTime now) {
  final started = room.startedAt;
  if (started == null || !room.isLiveNow) return null;
  final minutes = now.toUtc().difference(started).inMinutes;
  if (minutes < 0) return null;
  if (minutes < 60) return i18n('favorite_live_minutes', args: {'m': '${minutes < 1 ? 1 : minutes}'});
  return i18n('favorite_live_hours', args: {'h': '${minutes ~/ 60}', 'm': '${minutes % 60}'});
}

/// The mark of a room that cannot simply be played, or of a state the
/// card has no badge for (retired platform, carousel, banned), or null.
String? restrictionLabel(LiveRoom room) {
  if (SiteIds.isRetired(room.platform)) return i18n('favorite_mark_retired');
  switch (room.effectiveLiveStatus) {
    case LiveStatus.carousel:
      return i18n('favorite_mark_carousel');
    case LiveStatus.banned:
      return i18n('favorite_mark_banned');
    case LiveStatus.live || LiveStatus.replay:
      final kind = room.effectiveRestriction;
      return kind == LiveRestriction.none ? null : i18n('favorite_mark_${kind.name}');
    case LiveStatus.offline || LiveStatus.unknown:
      return null;
  }
}

/// The card of [room] (3.x built it inside `RoomCard`).
RoomCardData cardDataOf(
  LiveRoom room, {
  required SiteRegistry sites,
  required bool preferRealOnline,
  required Set<String> realOnlinePlatforms,
  required DateTime now,
}) {
  final enabled = realOnlinePlatforms.contains(room.platform);
  final kind = room.audienceType(preferRealOnline: preferRealOnline, platformEnabled: enabled);
  final value = room.audienceValue(preferRealOnline: preferRealOnline, platformEnabled: enabled);
  final name = room.displayNick(platformName(room.platform, sites));
  final duration = liveFor(room, now);
  return RoomCardData(
    platformId: room.platform,
    title: room.title,
    anchorName: duration == null ? name : '$name · $duration',
    avatarUrl: normalizeImageUrl(room.avatar),
    coverUrl: normalizeImageUrl(room.cover),
    isLive: room.isLiveNow,
    isReplay: room.isRecord,
    audience: RoomAudience(
      kind: switch (kind) {
        AudienceMetricType.popularity => RoomAudienceKind.popularity,
        AudienceMetricType.onlineViewers => RoomAudienceKind.onlineViewers,
        AudienceMetricType.totalViewers => RoomAudienceKind.totalViewers,
        AudienceMetricType.followers => RoomAudienceKind.followers,
        AudienceMetricType.unknown => RoomAudienceKind.unknown,
      },
      value: value.isEmpty ? '' : readableCount(value),
    ),
    restrictionLabel: restrictionLabel(room),
  );
}

/// The card appearance of this kind of device (3.x
/// `RoomCardSettingsController.resolve`: phones use the mobile settings,
/// everything else the desktop ones).
RoomCardAppearance watchCardAppearance(WidgetRef ref) {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final preset = watchSetting(ref, mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset);
  final config = watchSetting(ref, mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig);
  final fallback = RoomCardAppearance.fromPreset(
    RoomCardPreset.values.firstWhere((value) => value.storageKey == preset, orElse: () => RoomCardPreset.standard),
  );
  return config.isEmpty ? fallback : RoomCardAppearance.fromJson(config.cast<String, dynamic>(), fallback: fallback);
}

/// The font sizes of the settings (for the grid's card height).
LiveFontSizes watchFontSizes(WidgetRef ref) => LiveFontSizes(
  bodySmall: watchSetting(ref, Settings.fontSizeBodySmall),
  bodyMedium: watchSetting(ref, Settings.fontSizeBodyMedium),
  bodyLarge: watchSetting(ref, Settings.fontSizeBodyLarge),
  titleMedium: watchSetting(ref, Settings.fontSizeTitleMedium),
  titleLarge: watchSetting(ref, Settings.fontSizeTitleLarge),
);
