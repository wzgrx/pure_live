import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

// A page-local LiveRoom → RoomCardData adapter. Every card page (follows,
// popular, search, areas, history) needs one; until a shared one exists in
// the app (see docs/modules/M13.6-history.md, "留给后续") the history page
// keeps its own, following 3.x's `RoomCard`.

/// Whether the card settings for phones apply on [platform] (3.x
/// `PlatformUtils.isMobile` chose the mobile card configuration).
bool isMobileCardPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
  TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
};

/// The card appearance stored as [preset] (`compact`, `normal`, `rich`,
/// `custom`) and [config] (empty: the preset's own; 3.x
/// `RoomCardSettingsController.resolve`).
RoomCardAppearance historyCardAppearance({required String preset, required Map<String, Object?> config}) {
  final base = RoomCardAppearance.fromPreset(
    RoomCardPreset.values.firstWhere((value) => value.storageKey == preset, orElse: () => RoomCardPreset.standard),
  );
  return config.isEmpty ? base : RoomCardAppearance.fromJson(config.cast<String, dynamic>(), fallback: base);
}

/// An image address the card can load: quotes and blanks removed, `//host`
/// and bare hosts made https, anything else empty (3.x
/// `normalizeNetworkImageUrl`).
String historyImageUrl(String? source) {
  var value = source?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null') return '';
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) return value;
  if (!value.contains(' ') && RegExp(r'^[\w.-]+\.[a-zA-Z]{2,}([/:?#]|$)').hasMatch(value)) return 'https://$value';
  return '';
}

/// [value] shortened like 3.x's `readableCount`: `1.2万` in Chinese from
/// 10 000, `1.2k` in English from 1 000; text that is not a whole number
/// stays as it is.
String readableAudience(String value, {required bool chinese}) {
  final count = int.tryParse(value.trim());
  if (count == null) return value;
  if (chinese && count >= 10000) return '${(count / 10000).toStringAsFixed(1)}${i18n('count_wan')}';
  if (!chinese && count >= 1000) return '${(count / 1000).toStringAsFixed(1)}${i18n('count_k')}';
  return value;
}

/// The platform's display name (3.x `site_<id>` strings), or its id.
String historyPlatformName(String platform) => i18nOr('site_${platform.trim().toLowerCase()}', platform);

/// The words of a restriction mark on the card; null for none
/// (docs/UPGRADES.md "卡片标出受限类型").
String? historyRestrictionLabel(LiveRestriction restriction) => switch (restriction) {
  LiveRestriction.none => null,
  LiveRestriction.needsLogin => i18n('history_restriction_needs_login'),
  LiveRestriction.paid => i18n('history_restriction_paid'),
  LiveRestriction.subscribersOnly => i18n('history_restriction_subscribers_only'),
  LiveRestriction.private => i18n('history_restriction_private'),
  LiveRestriction.appOnly => i18n('history_restriction_app_only'),
  LiveRestriction.regionBlocked => i18n('history_restriction_region_blocked'),
  LiveRestriction.password => i18n('history_restriction_password'),
  LiveRestriction.adult => i18n('history_restriction_adult'),
  LiveRestriction.unplayable => i18n('history_restriction_unplayable'),
};

/// A short name of [room] for dialogs: title, streamer, room id, or
/// "untitled" (3.x `_historyRoomLabel`).
String historyRoomLabel(LiveRoom room) {
  for (final candidate in [room.title, room.nick, room.roomId]) {
    final value = candidate.trim();
    if (value.isNotEmpty) return value;
  }
  return i18n('untitled_room');
}

/// What the card of [room] shows. [preferRealOnline] and
/// [realOnlinePlatforms] are the audience settings (3.x
/// `preferRealOnlineCounts`, `isRealOnlineEnabledFor`).
RoomCardData historyCardData(
  LiveRoom room, {
  required bool preferRealOnline,
  required List<String> realOnlinePlatforms,
  bool chinese = true,
}) {
  final platformEnabled = realOnlinePlatforms.contains(room.platform.trim().toLowerCase());
  final value = room.audienceValue(preferRealOnline: preferRealOnline, platformEnabled: platformEnabled);
  final kind = switch (room.audienceType(preferRealOnline: preferRealOnline, platformEnabled: platformEnabled)) {
    AudienceMetricType.popularity => RoomAudienceKind.popularity,
    AudienceMetricType.onlineViewers => RoomAudienceKind.onlineViewers,
    AudienceMetricType.totalViewers => RoomAudienceKind.totalViewers,
    AudienceMetricType.followers => RoomAudienceKind.followers,
    AudienceMetricType.unknown => RoomAudienceKind.unknown,
  };
  final title = room.title.trim();
  return RoomCardData(
    platformId: room.platform,
    title: title.isEmpty ? i18n('untitled_room') : title,
    // A platform that gave no streamer name shows its own name (UPGRADES 28-2).
    anchorName: room.displayNick(historyPlatformName(room.platform)),
    avatarUrl: historyImageUrl(room.avatar),
    coverUrl: historyImageUrl(room.cover),
    isLive: room.isLiveNow,
    isReplay: room.isRecord,
    audience: RoomAudience(
      kind: kind,
      value: value.isEmpty ? '' : readableAudience(value, chinese: chinese),
    ),
    restrictionLabel: historyRestrictionLabel(room.effectiveRestriction),
  );
}
