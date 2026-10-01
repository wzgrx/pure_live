import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

// Local adapters from the room model to live_ui's card input. Other pages
// need the same mapping; it can move to a shared place when one exists.

/// The audience figure in short form (3.x `readableCount`): `1.2万` in
/// Chinese from ten thousand, `1.2K` in English from a thousand; anything
/// that is not a plain number stays as the platform wrote it.
String readableAudience(String value) {
  final count = int.tryParse(value.trim());
  if (count == null) return value;
  if (currentStrings?.language == AppLanguage.en) {
    return count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}${i18n('count_k')}' : value;
  }
  return count >= 10000 ? '${(count / 10000).toStringAsFixed(1)}${i18n('count_wan')}' : value;
}

/// A protocol-relative image address made absolute (3.x
/// `normalizeNetworkImageUrl`, the part the cards need).
String normalizeImageUrl(String url) {
  final text = url.trim();
  return text.startsWith('//') ? 'https:$text' : text;
}

/// The words of [restriction] on a card, or null for none.
String? restrictionLabel(LiveRestriction restriction) => switch (restriction) {
  LiveRestriction.none => null,
  LiveRestriction.needsLogin => i18n('search_restriction_needs_login'),
  LiveRestriction.paid => i18n('search_restriction_paid'),
  LiveRestriction.subscribersOnly => i18n('search_restriction_subscribers_only'),
  LiveRestriction.private => i18n('search_restriction_private'),
  LiveRestriction.appOnly => i18n('search_restriction_app_only'),
  LiveRestriction.regionBlocked => i18n('search_restriction_region_blocked'),
  LiveRestriction.password => i18n('search_restriction_password'),
  LiveRestriction.adult => i18n('search_restriction_adult'),
  LiveRestriction.unplayable => i18n('search_restriction_unplayable'),
};

RoomAudienceKind _kind(AudienceMetricType type) => switch (type) {
  AudienceMetricType.popularity => RoomAudienceKind.popularity,
  AudienceMetricType.onlineViewers => RoomAudienceKind.onlineViewers,
  AudienceMetricType.totalViewers => RoomAudienceKind.totalViewers,
  AudienceMetricType.followers => RoomAudienceKind.followers,
  AudienceMetricType.unknown => RoomAudienceKind.unknown,
};

/// The card input of [room]; [platformName] stands in for a missing name.
RoomCardData roomCardData(
  LiveRoom room, {
  required String platformName,
  required bool preferRealOnline,
  required bool Function(String platform) realOnlineEnabled,
}) {
  final enabled = realOnlineEnabled(room.platform);
  final value = room.audienceValue(preferRealOnline: preferRealOnline, platformEnabled: enabled);
  return RoomCardData(
    platformId: room.platform,
    title: room.title.trim(),
    anchorName: room.displayNick(platformName),
    avatarUrl: normalizeImageUrl(room.avatar),
    coverUrl: normalizeImageUrl(room.cover),
    isLive: room.isLiveNow,
    isReplay: room.isRecord,
    audience: RoomAudience(
      kind: _kind(room.audienceType(preferRealOnline: preferRealOnline, platformEnabled: enabled)),
      value: value.isEmpty ? '' : readableAudience(value),
    ),
    restrictionLabel: room.isRestricted ? restrictionLabel(room.effectiveRestriction) : null,
  );
}

/// The card settings of this screen kind (3.x
/// `RoomCardSettingsController.resolve`): phones use the mobile ones.
RoomCardAppearance roomCardAppearance(SettingsStore settings, {TargetPlatform? platform}) {
  final mobile = switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
    _ => false,
  };
  final presetKey = settings.get(mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset);
  final preset = RoomCardPreset.values.firstWhere(
    (value) => value.storageKey == presetKey,
    orElse: () => RoomCardPreset.standard,
  );
  final fallback = RoomCardAppearance.fromPreset(preset);
  final config = settings.get(mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig);
  if (config.isEmpty) return fallback;
  return RoomCardAppearance.fromJson(Map<String, dynamic>.of(config), fallback: fallback);
}
