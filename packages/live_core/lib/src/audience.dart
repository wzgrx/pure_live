import 'package:meta/meta.dart';

/// What a room's audience number means. Stored by name in room JSON.
enum AudienceMetricType {
  /// Platform popularity or heat; not a head count.
  popularity,

  /// Concurrent viewers.
  onlineViewers,

  /// Cumulative viewers of the current session.
  totalViewers,

  /// Followers of the streamer.
  followers,

  /// Not known.
  unknown,
}

/// Where a platform exposes its concurrent-viewer count.
enum AudienceOnlineAvailability {
  /// Nowhere.
  unsupported,

  /// Only in the room (detail or realtime messages).
  roomRealtime,

  /// Already in room lists.
  roomList,
}

/// Which audience metrics a platform has (3.x's per-platform table; the
/// comments record why each value is what it is).
@immutable
final class AudiencePlatformCapability {
  /// Creates a capability.
  const new({required this.hasPopularity, required this.hasTotalViewers, required this.onlineAvailability});

  /// A platform without known metrics.
  static const AudiencePlatformCapability unknown = AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  );

  /// Whether the platform has a popularity or heat value.
  final bool hasPopularity;

  /// Whether the platform has a cumulative viewer value.
  final bool hasTotalViewers;

  /// Where the concurrent-viewer count is available.
  final AudienceOnlineAvailability onlineAvailability;

  /// Whether the platform has a concurrent-viewer count at all.
  bool get supportsConcurrentOnline => onlineAvailability != AudienceOnlineAvailability.unsupported;

  /// Whether room lists already carry the concurrent-viewer count.
  bool get onlineAvailableInRoomLists => onlineAvailability == AudienceOnlineAvailability.roomList;

  /// The capability of [platform] (case-insensitive), or [unknown].
  static AudiencePlatformCapability of(String? platform) =>
      audienceCapabilities[platform?.trim().toLowerCase()] ?? unknown;
}

/// Audience metrics per platform id.
const Map<String, AudiencePlatformCapability> audienceCapabilities = {
  // Bilibili's room `online` field and operation-3 heartbeat are popularity;
  // WATCHED_CHANGE is cumulative. Neither is a concurrent head count.
  'bilibili': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  'douyu': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  // Huya's website URI 8006 calls the field iAttendeeCount, but live captures
  // stay in the same multi-million popularity range as totalCount. Keep it as
  // heat until the public protocol exposes a distinct head count.
  'huya': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  'douyin': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  'kuaishou': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  'cc': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Twitch GraphQL exposes viewersCount as the concurrent viewer count in
  // directory, search and room metadata responses.
  'twitch': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // SOOP lists expose total_view_cnt/view_cnt as PC + mobile concurrent
  // viewers. current_view_cnt alone is PC-only and must not be displayed as
  // the total audience; player metadata may omit the count altogether.
  'soop': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // YY's public `users` value follows the platform popularity scale. No
  // separate concurrent audience field is exposed by the current web API.
  'yy': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  // Picarto viewers and total_views have separate concurrent/cumulative meanings.
  'picarto': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  'twitcasting': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // SHOWROOM's view_num is session traffic and is not documented as a
  // concurrent audience. Keep it in the cumulative column.
  'showroom': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  // CHZZK exposes concurrentUserCount and separately tells clients whether
  // the value may be shown through cvExposure.
  'chzzk': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Kick lists and channel answers carry viewer_count, the concurrent
  // viewers; a streamer may hide it (show_view_count false), then it stays
  // unknown (M4.34).
  'kick': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // The room detail keeps current liveViewerCount separate from cumulative viewerCount.
  // In the room, the chat's LIVE message (type 38) pushes liveViewerCount
  // again, the figure the website shows; the danmaku connection reports it
  // (M5.29).
  '17live': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
  // LiveMe exposes platform heat, current playnumber and cumulative
  // watchnumber as separate fields in both its directory and room response.
  'liveme': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // TikTok LIVE exposes liveRoomStats.userCount as concurrent viewers and
  // enterCount as cumulative room entries; keep those metrics separate.
  'tiktok': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
  // The watch page exposes a dedicated concurrent-view renderer while a
  // broadcast is live. Historical viewCount is deliberately not reused. The
  // live chat's `next` answer carries the same renderer; the danmaku
  // connection reports it once as it joins (M5.19).
  'youtube': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
  // The finite public directory exposes user_count for current broadcasts.
  // Room detail has no verified concurrent field and therefore keeps it unknown.
  // In the room, the chat's audience frames (NUMS `totalUserCount`, and the
  // user-list answer's `total`) are the same concurrent count; the danmaku
  // connection reports them as online viewers (M5.20).
  'bigo': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // PandaTV's `user` value is the concurrent audience in the official
  // directory and play response; `playCnt`, the broadcast's entries so far,
  // is its cumulative audience (M4.U 25-3; 3.x showed only `user`).
  'pandalive': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // FC2 exposes current `count` and cumulative `total` independently in both
  // its public directory and member metadata.
  'fc2live': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Steam community cards and getbroadcastmpd both expose the current
  // concurrent audience independently from the broadcast identity.
  'steambroadcast': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // JD labels the public-directory `pv` value as views rather than current
  // concurrency, so it remains a cumulative audience field. In the room, the
  // guest chat's get_statistics_result (about every 3.5 s while most rooms
  // are live) carries current_viewer, which rises and falls as viewers join
  // and leave, and total_viwer, the same cumulative views (M5.24).
  'jdlive': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
  // Kugou keeps directory viewerNum/getViewerNum, platform hot and
  // broadcaster fansCount as three independent metrics. In the room, the
  // chat's roomAuNumber (301005) pushes about every minute the viewers now
  // (count, the lists' viewerNum) and the broadcast's cumulative viewers
  // (visited, the website's "本场累计"); its hot is the page's own heat, not the
  // lists' hot (M5.25).
  'kugoulive': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Baidu's PC feed audience_count and room online_users are live audience
  // values. Fan counts stay in the independent follower field. The chat's
  // message list carries the same figure (payload 101's onlineusercnt),
  // which the danmaku connection reports as it changes (M5.26).
  'baidulive': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Six Rooms exposes a homepage `count` used by its ranking cards, without a
  // stable public contract proving unique concurrent viewers. Keep it as
  // platform popularity; room fans remain an independent follower metric.
  'sixroom': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.unsupported,
  ),
  // LOOK keeps recommendation popularity and onlineNumber as independent
  // values. The latter is the current audience shown on official web cards.
  'looklive': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // Missevan's lists and room detail carry the heat `score` and an `online`
  // that is always 0; the listeners in the room come only with the chat's
  // `room/statistics` (M5.12), about every two minutes.
  'missevan': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
  // Inke's app answers (the hot list, the current broadcast) carry
  // numbers.real, the "N人在看" the app shows, and online_users, a larger
  // display figure kept as heat (REG-INKE-003). The website showcases carry
  // neither; 3.x showed no Inke audience (M4.U.14).
  'inke': AudiencePlatformCapability(
    hasPopularity: true,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // AcFun onlineCount is independent of likes/followers; author search omits it.
  'acfun': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: false,
    onlineAvailability: AudienceOnlineAvailability.roomList,
  ),
  // KilaKila's anchor profile (follow refresh and room entry) has the
  // broadcast's current onlineNumber; the timelines and getRoomInfo have only
  // watchNumber, its cumulative listeners (REG-KILAKILA-003, M4.U 15-2). In
  // the room, the guest chat's room state (637) pushes the listeners now
  // about every 5 s, the number the live page shows (M5.13).
  'kilakila': AudiencePlatformCapability(
    hasPopularity: false,
    hasTotalViewers: true,
    onlineAvailability: AudienceOnlineAvailability.roomRealtime,
  ),
};

/// A sortable audience key for rooms whose platforms use different scales.
///
/// In concurrent-viewer mode an explicit concurrent value ranks ahead of a
/// pending one, and a pending supported room ahead of a heat or cumulative
/// fallback, so a multi-million popularity score never outranks a real
/// audience of a few thousand people.
@immutable
final class AudienceRankKey {
  /// Creates a key.
  const new({required this.metricPriority, required this.value});

  /// Higher ranks first: 3 explicit concurrent, 2 pending concurrent, 1 a
  /// native value, 0 nothing.
  final int metricPriority;

  /// The number within the tier.
  final int value;
}

/// The number in an audience text: `5.6万` 56000, `1.2亿`, `18.3k`, `1.5M`,
/// `2.4千`, `534，739`; 0 when there is none.
int parseAudienceNumber(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text.isEmpty) return 0;
  final normalized = text.replaceAll(',', '').replaceAll('，', '');
  final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(亿|万|千|[kwm])?').firstMatch(normalized);
  final number = double.tryParse(match?.group(1) ?? '') ?? 0;
  final multiplier = switch (match?.group(2)) {
    '亿' => 100000000,
    '万' || 'w' => 10000,
    '千' || 'k' => 1000,
    'm' => 1000000,
    _ => 1,
  };
  return (number * multiplier).round();
}

/// Whether [value] is a measured, positive audience number.
bool hasAudienceValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isNotEmpty && text != 'null' && parseAudienceNumber(text) > 0;
}

/// Whether [value] carries any digit, zero included (an explicit count).
bool hasExplicitAudienceValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isNotEmpty && text != 'null' && RegExp('[0-9]').hasMatch(text);
}
