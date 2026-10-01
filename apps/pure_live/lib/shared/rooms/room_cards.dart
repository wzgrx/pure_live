import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// LiveRoom → live_ui's RoomCardData, the card settings, and which rooms the
// discovery pages hide: one copy for every card page (follows, popular,
// areas, search, history; M12.2).

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

/// Whether [platform] has a stored cookie (the login part of [cannotPlayHere]).
bool signedInOn(CookieVault cookies, String platform) => cookies.cookieFor(platform)?.trim().isNotEmpty ?? false;

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

  /// What a card shows for [room] (3.x built it inside `RoomCard`): the
  /// platform's name for a missing streamer (UPGRADES 28-2), image addresses
  /// made absolute, the room's mark. With [now], a live room's time on air
  /// follows the streamer (UPGRADES "开播时间"; the card has no field for it).
  RoomCardData cardOf(LiveRoom room, {DateTime? now}) {
    final name = room.displayNick(platformName(room.platform));
    final duration = now == null ? null : liveDuration(room, now);
    final title = room.title.trim();
    return RoomCardData(
      platformId: room.platform,
      title: title.isEmpty ? i18n('untitled_room') : title,
      anchorName: duration == null ? name : '$name · $duration',
      avatarUrl: normalizeImageUrl(room.avatar),
      coverUrl: normalizeImageUrl(room.cover),
      isLive: room.isLiveNow,
      isReplay: room.isRecord,
      audience: audienceOf(room),
      restrictionLabel: roomMark(room),
    );
  }
}

/// The audience policy of the settings, rebuilt when they change.
AudiencePolicy watchAudiencePolicy(WidgetRef ref) => AudiencePolicy(
  preferRealOnline: watchSetting(ref, Settings.preferRealOnlineCounts),
  realOnlinePlatforms: {for (final id in watchSetting(ref, Settings.realOnlinePlatforms)) id.trim().toLowerCase()},
);

/// Whether this device takes the phone forms (3.x `PlatformUtils.isMobile`).
bool get isPhoneDevice => Platform.isAndroid || Platform.isIOS;

/// The card appearance of this device (3.x `RoomCardSettingsController.resolve`:
/// the phone settings on phones, the desktop ones elsewhere; an empty stored
/// config uses the preset, an unreadable one too).
RoomCardAppearance cardAppearanceOf(SettingsStore settings, {bool? phone}) {
  final mobile = phone ?? isPhoneDevice;
  return _appearance(
    settings.get(mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset),
    settings.get(mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig),
  );
}

/// [cardAppearanceOf], rebuilt when the card settings change.
RoomCardAppearance watchCardAppearance(WidgetRef ref, {bool? phone}) {
  final mobile = phone ?? isPhoneDevice;
  return _appearance(
    watchSetting(ref, mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset),
    watchSetting(ref, mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig),
  );
}

RoomCardAppearance _appearance(String preset, Map<String, Object?> config) {
  final base = RoomCardAppearance.fromPreset(
    RoomCardPreset.values.firstWhere((value) => value.storageKey == preset, orElse: () => RoomCardPreset.standard),
  );
  if (config.isEmpty) return base;
  try {
    return RoomCardAppearance.fromJson(Map<String, dynamic>.of(config), fallback: base);
  } on Object {
    return base;
  }
}

/// The font sizes of the settings (the grid's card heights follow them).
LiveFontSizes watchFontSizes(WidgetRef ref) => LiveFontSizes(
  bodySmall: watchSetting(ref, Settings.fontSizeBodySmall),
  bodyMedium: watchSetting(ref, Settings.fontSizeBodyMedium),
  bodyLarge: watchSetting(ref, Settings.fontSizeBodyLarge),
  titleMedium: watchSetting(ref, Settings.fontSizeTitleMedium),
  titleLarge: watchSetting(ref, Settings.fontSizeTitleLarge),
);
