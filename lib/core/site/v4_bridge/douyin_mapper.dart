import 'package:live_core/live_core.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

/// The legacy Douyin card for a v4 card (docs/adr/0012-legacy-bridge.md).
///
/// Legacy cards led with the cumulative audience when there was one, else
/// the online count, and named the online count when there was neither
/// (douyin_site.dart:207-231, 300-321). Feed cards also linked to their room
/// and showed the UI copy “热门推荐” when the feed gave no area (spec §2
/// 推荐: v4 reports no area and leaves the copy to the interface).
LiveRoom douyinLegacyRoom(RoomCard card, V4List list) {
  final room = V4Bridge.liveRoomFromCard(card, cumulativeFirst: true);
  if (card.audience.online == null && card.audience.cumulative == null) {
    room
      ..watching = ''
      ..audienceMetricType = AudienceMetricType.onlineViewers;
  }
  if (list == V4List.recommend) {
    room
      ..area = card.area ?? '热门推荐'
      ..link = 'https://live.douyin.com/${card.ref.roomId}';
  }
  return room;
}
