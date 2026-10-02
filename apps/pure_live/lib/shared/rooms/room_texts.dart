import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/i18n/i18n.dart';

// The words every room page shows the same way: platform names, audience
// counts, room marks, load and playback failures (M12.2: one copy instead
// of one per page).

/// The platform's display name (3.x's `site_<id>` strings), else [fallback],
/// else the id.
String platformName(String platform, {String? fallback}) =>
    i18nOr('site_${platform.trim().toLowerCase()}', fallback ?? platform);

/// A count for people: `5.6万` in Chinese, `5.6K` in English (3.x
/// `readableCount`, which only read plain integers; counts the platforms
/// already wrote with units are shortened the same way). Text without a
/// number stays as it is.
String readableAudience(String value) {
  final count = parseAudienceNumber(value);
  if (count <= 0) return value.trim();
  final english = currentStrings?.language == AppLanguage.en;
  if (!english && count >= 100000000) return '${_short(count / 100000000)}亿';
  if (!english && count >= 10000) return '${_short(count / 10000)}${i18n('count_wan')}';
  if (english && count >= 1000000) return '${_short(count / 1000000)}M';
  if (english && count >= 1000) return '${_short(count / 1000)}${i18n('count_k')}';
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

/// A broadcast's length, written the same on cards and in the room: under an
/// hour `12 分钟` (at least 1), under a day `5 小时 3 分`, then `2 天 3 小时`
/// (the card said `51 小时 49 分` where the room said `2 天`).
String elapsedText(Duration elapsed) {
  final minutes = elapsed.inMinutes < 1 ? 1 : elapsed.inMinutes;
  if (minutes < 60) return i18n('duration_minutes', args: {'m': '$minutes'});
  if (minutes < Duration.minutesPerDay) {
    return i18n('duration_hours', args: {'h': '${minutes ~/ 60}', 'm': '${minutes % 60}'});
  }
  return i18n(
    'duration_days',
    args: {'d': '${minutes ~/ Duration.minutesPerDay}', 'h': '${minutes % Duration.minutesPerDay ~/ 60}'},
  );
}

/// How long the broadcast has been on: `已开播 1 小时 20 分` ([elapsedText]),
/// `刚刚开播` under a minute.
String startedAgo(DateTime startedAt, DateTime now) {
  final elapsed = now.difference(startedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return i18n('live_play_started_just_now');
  return i18n('live_play_started', args: {'duration': elapsedText(elapsed)});
}

/// How long [room] has been live, short for a card (`已播 12 分钟`,
/// [elapsedText]; `刚刚开播` under a minute), or null when it is not live or
/// the start is unknown (UPGRADES "开播时间").
String? liveDuration(LiveRoom room, DateTime now) {
  final started = room.startedAt;
  if (started == null || !room.isLiveNow) return null;
  final elapsed = now.difference(started);
  if (elapsed.isNegative) return null;
  if (elapsed.inMinutes < 1) return i18n('live_play_started_just_now');
  return i18n('room_live', args: {'duration': elapsedText(elapsed)});
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

/// The short mark of a restriction (a card's badge); null for none.
String? restrictionLabel(LiveRestriction restriction) =>
    restriction == LiveRestriction.none ? null : i18n('room_mark_${_restrictionKey(restriction)}');

/// Why a restricted room may not play (docs/specs/UPGRADES.md "统一原则").
String restrictionReason(LiveRestriction restriction) =>
    restriction == LiveRestriction.none ? '' : i18n('room_mark_${_restrictionKey(restriction)}_hint');

/// The mark a room card shows (UPGRADES "卡片标出受限类型", 1-1): a retired
/// platform, a carousel or a ban (states the card has no badge for), else
/// the restriction; null for none.
String? roomMark(LiveRoom room) {
  if (SiteIds.isRetired(room.platform)) return i18n('room_mark_retired');
  return switch (room.effectiveLiveStatus) {
    LiveStatus.carousel => i18n('room_mark_carousel'),
    LiveStatus.banned => i18n('room_mark_banned'),
    _ => restrictionLabel(room.effectiveRestriction),
  };
}

/// Words for a failed list request (follows, popular, areas, search): what
/// went wrong in terms the user can act on, never the adapter's detail.
String describeLoadError(Object? error) => switch (error) {
  Offline() => i18n('network_disconnected_msg'),
  NeedsLogin() => i18n('load_error_login'),
  RateLimited() => i18n('load_error_rate_limited'),
  RiskControl(cookieSuspect: true) => i18n('load_error_cookie'),
  RiskControl() => i18n('load_error_risk'),
  RegionBlocked() => i18n('load_error_region'),
  ApiChanged() => i18n('load_error_changed'),
  NetworkFailure() || TransportFailure() || HttpStatusFailure() => i18n('load_error_network'),
  _ => i18n('load_error_unknown'),
};

/// Whether [error] asks the user to sign in (3.x showed the login page).
bool isLoginError(Object? error) => error is NeedsLogin || error is RiskControl;

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

/// A short name of [room] for dialogs: title, streamer, room id, or
/// "untitled" (3.x `_historyRoomLabel`).
String roomLabel(LiveRoom room) {
  for (final candidate in [room.title, room.nick, room.roomId]) {
    final value = candidate.trim();
    if (value.isNotEmpty) return value;
  }
  return i18n('untitled_room');
}
