import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// The platform filter that shows every follow (3.x `Sites.allSite`).
const String allPlatforms = SiteIds.all;

/// The tag filter that shows every follow (3.x `TagManagementController.allTagKey`).
const String allTags = '';

/// The tab a follow is listed under: [LiveRoom.followGroup] (live, playable
/// replay, everything else), with a retired platform's follows always
/// offline (they can no longer be refreshed or opened).
FollowGroup groupOf(LiveRoom room) => SiteIds.isRetired(room.platform) ? FollowGroup.offline : room.followGroup;

/// The platform tabs: [allPlatforms], then every platform that has a follow.
///
/// Platforms of the user's platform list ([platformOrder], the `hotAreasList`
/// setting) come first in that order, the others after them in the app's
/// platform order and retired or unknown ones last, so a follow is never
/// reachable only through "all" (3.x listed only the platform list's
/// platforms).
List<String> platformTabs(Iterable<LiveRoom> rooms, List<String> platformOrder) {
  final present = {for (final room in rooms) room.platform};
  final ordered = <String>[allPlatforms];
  void addAll(Iterable<String> ids) {
    for (final raw in ids) {
      final id = raw.trim().toLowerCase();
      if (present.contains(id) && !ordered.contains(id)) ordered.add(id);
    }
  }

  addAll(platformOrder);
  addAll(SiteIds.supported);
  addAll(present.toList()..sort());
  return ordered;
}

/// Whether [room] belongs to [platform] ([allPlatforms] matches every room).
bool onPlatform(LiveRoom room, String platform) => platform == allPlatforms || room.platform == platform;

/// How follows are ordered inside a tab.
final class FollowOrder {
  /// Creates the order from the audience settings and the tags.
  const new({required this.preferRealOnline, required this.realOnlinePlatforms, required this.tags});

  /// The `preferRealOnlineCounts` setting.
  final bool preferRealOnline;

  /// The `realOnlinePlatforms` setting.
  final Set<String> realOnlinePlatforms;

  /// The tags, in the user's order.
  final List<StoreTag> tags;

  /// Live and replay follows: largest audience first (3.x
  /// `compareAudienceRanking`); with a tag selected, rooms whose best tag
  /// ranks higher come first (3.x `_getRoomTagScore`).
  int compare(LiveRoom left, LiveRoom right, {required Map<String, List<String>> assignments, required bool byTag}) {
    if (byTag) {
      final score = _tagRank(right, assignments).compareTo(_tagRank(left, assignments));
      if (score != 0) return score;
    }
    return LiveRoom.compareAudienceRanking(
      left,
      right,
      preferRealOnline: preferRealOnline,
      platformEnabled: realOnlinePlatforms.contains,
    );
  }

  int _tagRank(LiveRoom room, Map<String, List<String>> assignments) {
    final ids = assignments[room.identityKey] ?? const <String>[];
    var best = 0;
    for (var index = 0; index < tags.length; index++) {
      if (ids.contains(tags[index].id)) {
        final rank = tags.length - index;
        if (rank > best) best = rank;
      }
    }
    return best;
  }
}

/// The follows of one tab: [group] on [platform] with [tagId] ([allTags]
/// for any), live and replay ones sorted by [order], offline ones in the
/// user's order (3.x).
List<LiveRoom> roomsOf(
  List<LiveRoom> rooms, {
  required FollowGroup group,
  required String platform,
  required String tagId,
  required Map<String, List<String>> assignments,
  required FollowOrder order,
}) {
  final list = [
    for (final room in rooms)
      if (groupOf(room) == group &&
          onPlatform(room, platform) &&
          (tagId == allTags || (assignments[room.identityKey]?.contains(tagId) ?? false)))
        room,
  ];
  if (group != FollowGroup.offline) {
    final byTag = tagId != allTags;
    list.sort((a, b) => order.compare(a, b, assignments: assignments, byTag: byTag));
  }
  return list;
}

/// The tags worth offering in [group] on [platform]: those at least one of
/// its follows has, in the user's order (3.x `visibleTags`).
List<StoreTag> tagsOf(
  List<LiveRoom> rooms, {
  required FollowGroup group,
  required String platform,
  required List<StoreTag> tags,
  required Map<String, List<String>> assignments,
}) {
  final used = <String>{
    for (final room in rooms)
      if (groupOf(room) == group && onPlatform(room, platform)) ...?assignments[room.identityKey],
  };
  return [
    for (final tag in tags)
      if (used.contains(tag.id)) tag,
  ];
}

/// How many follows of [platform] each tab has.
Map<FollowGroup, int> groupCounts(List<LiveRoom> rooms, String platform) {
  final counts = {for (final group in FollowGroup.values) group: 0};
  for (final room in rooms) {
    if (onPlatform(room, platform)) counts.update(groupOf(room), (count) => count + 1);
  }
  return counts;
}
