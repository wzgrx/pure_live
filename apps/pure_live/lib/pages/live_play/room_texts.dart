import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The platform's display name (3.x's `site_<id>` strings).
String platformName(String platform) {
  final key = 'site_${platform.trim().toLowerCase()}';
  return i18nExists(key) ? i18n(key) : platform;
}

/// A count for people: `5.6万` in Chinese, `5.6K` in English (3.x
/// `readableCount`, which only read plain integers).
String readableAudience(String value) {
  final count = parseAudienceNumber(value);
  if (count <= 0) return value.trim();
  final english = currentStrings?.language == AppLanguage.en;
  if (!english && count >= 100000000) return '${_short(count / 100000000)}亿';
  if (!english && count >= 10000) return '${_short(count / 10000)}${i18n('count_wan')}';
  if (english && count >= 1000000) return '${_short(count / 1000000)}M';
  if (english && count >= 1000) return '${_short(count / 1000)}K';
  return '$count';
}

String _short(double value) => value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// One audience figure of the room, labelled by what it means.
typedef AudienceFigure = ({AudienceMetricType type, String value});

/// The room's audience figures, each with its own meaning (audience.dart):
/// concurrent viewers first, then heat, then cumulative viewers. 3.x showed
/// one number whose label depended on a setting, so Bilibili's heat and its
/// new online count (C-1) could not be told apart.
List<AudienceFigure> audienceFigures(LiveRoom room) => [
  if (room.hasRealOnlineCount) (type: AudienceMetricType.onlineViewers, value: room.effectiveOnlineViewers),
  if (hasAudienceValue(room.effectivePopularity))
    (type: AudienceMetricType.popularity, value: room.effectivePopularity),
  if (hasAudienceValue(room.effectiveTotalViewers))
    (type: AudienceMetricType.totalViewers, value: room.effectiveTotalViewers),
  if (!room.hasRealOnlineCount &&
      !hasAudienceValue(room.effectivePopularity) &&
      !hasAudienceValue(room.effectiveTotalViewers) &&
      room.supportsRealOnlineCount)
    (type: AudienceMetricType.onlineViewers, value: ''),
];

/// The label of an audience figure (3.x's keys).
String audienceLabel(AudienceMetricType type) => i18n(switch (type) {
  AudienceMetricType.onlineViewers => 'audience_online',
  AudienceMetricType.totalViewers => 'audience_total',
  AudienceMetricType.followers => 'audience_followers',
  AudienceMetricType.popularity => 'audience_popularity',
  AudienceMetricType.unknown => 'audience_count',
});

/// How long the broadcast has been on: `已开播 1 小时 20 分`.
String startedAgo(DateTime startedAt, DateTime now) {
  final elapsed = now.difference(startedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return i18n('live_play_started_just_now');
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  if (hours == 0) return i18n('live_play_started_minutes', args: {'minutes': '$minutes'});
  if (hours >= 48) return i18n('live_play_started_days', args: {'days': '${elapsed.inDays}'});
  return i18n('live_play_started_hours', args: {'hours': '$hours', 'minutes': '$minutes'});
}

/// `2026-10-01 20:05` in local time.
String formatStartTime(DateTime startedAt) {
  final local = startedAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _restrictionKey(LiveRestriction restriction) => switch (restriction) {
  LiveRestriction.none => 'none',
  LiveRestriction.needsLogin => 'needs_login',
  LiveRestriction.paid => 'paid',
  LiveRestriction.subscribersOnly => 'subscribers_only',
  LiveRestriction.private => 'private',
  LiveRestriction.appOnly => 'app_only',
  LiveRestriction.regionBlocked => 'region_blocked',
  LiveRestriction.password => 'password',
  LiveRestriction.adult => 'adult',
  LiveRestriction.unplayable => 'unplayable',
};

/// The short mark of a restriction (the card's chip).
String restrictionLabel(LiveRestriction restriction) => i18n('live_play_restriction_${_restrictionKey(restriction)}');

/// Why a restricted room may not play (docs/UPGRADES.md "统一原则").
String restrictionReason(LiveRestriction restriction) =>
    i18n('live_play_restriction_${_restrictionKey(restriction)}_hint');

/// What the user sees for a failure of the room detail, the qualities or the
/// stream: by kind, never the platform's raw text.
String failureText(Object? error) => switch (error) {
  NotFound() => i18n('live_play_error_not_found'),
  NeedsLogin() => i18n('live_play_error_needs_login'),
  RateLimited() || RiskControl() => i18n('live_play_error_rejected'),
  RegionBlocked() => i18n('live_play_error_region'),
  StreamUnavailable() => i18n('live_play_error_no_stream'),
  ApiChanged() => i18n('live_play_error_api_changed'),
  NetworkFailure() || TransportFailure() => i18n('live_play_error_network'),
  PlayerException(:final error) when error is SiteError => failureText(error),
  PlayerException(:final type) => i18nOr('error_${type.name}', i18n('error_unknown')),
  _ => i18n('get_room_info_failed_retry'),
};

/// A danmaku interruption as a chat line (3.x's texts, M5.0 table).
String interruptionText(DanmakuInterruption reason) => i18n(switch (reason) {
  DanmakuInterruption.disconnected => 'live_play_danmaku_reconnecting',
  DanmakuInterruption.handshakeTimeout => 'live_play_danmaku_handshake_timeout',
  DanmakuInterruption.protocolError => 'live_play_danmaku_protocol_error',
});

/// A final danmaku close as a chat line (3.x's texts, M5.0 table).
String closeText(DanmakuCloseReason reason) => i18n(switch (reason) {
  DanmakuCloseReason.reconnectsExhausted => 'live_play_danmaku_reconnects_exhausted',
  DanmakuCloseReason.connectionFailed => 'live_play_danmaku_connect_failed',
  DanmakuCloseReason.credentialsUnavailable => 'live_play_danmaku_credentials',
});

/// The offline text of a room that cannot play now.
String offlineText(LiveRoom room) => switch (room.effectiveLiveStatus) {
  LiveStatus.banned => i18n('live_play_banned'),
  LiveStatus.carousel => i18n('live_play_carousel'),
  LiveStatus.unknown => i18n('live_play_status_unknown'),
  _ => i18n('stream_not_live'),
};
