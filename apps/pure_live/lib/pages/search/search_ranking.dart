import 'package:live_core/live_core.dart';

/// How results are ordered (3.x `LiveSearchSortMode`).
enum SearchSortMode {
  /// Audience, then followers, then platform order.
  smart,

  /// Platform order, then audience, then followers.
  platform,

  /// Audience, then platform order, then followers.
  audience,

  /// Followers, then audience, then platform order.
  followers,
}

/// Filtering and ordering of search results (3.x `LiveSearchRanking`).
abstract final class SearchRanking {
  /// [rooms] without offline ones unless [includeOffline], ordered by
  /// [mode]. Live rooms come first, then playable replays (3.x put replays
  /// with offline rooms), then the rest; "offline" means not playable now,
  /// so hiding offline rooms keeps replays.
  static List<LiveRoom> apply({
    required Iterable<LiveRoom> rooms,
    required SearchSortMode mode,
    required bool includeOffline,
    required List<String> platformOrder,
    required int Function(LiveRoom left, LiveRoom right) audienceCompare,
  }) {
    final ranks = {for (var i = 0; i < platformOrder.length; i++) platformOrder[i].trim().toLowerCase(): i};
    return [
      for (final room in rooms)
        if (includeOffline || room.isPlayableNow) room,
    ]..sort((a, b) => compare(a, b, mode: mode, platformRanks: ranks, audienceCompare: audienceCompare));
  }

  /// The order of [a] and [b] under [mode].
  static int compare(
    LiveRoom a,
    LiveRoom b, {
    required SearchSortMode mode,
    required Map<String, int> platformRanks,
    required int Function(LiveRoom left, LiveRoom right) audienceCompare,
  }) {
    final state = _stateRank(b).compareTo(_stateRank(a));
    if (state != 0) return state;
    int platform() => (platformRanks[a.platform] ?? platformRanks.length).compareTo(
      platformRanks[b.platform] ?? platformRanks.length,
    );
    int audience() => audienceCompare(a, b);
    int followers() => followerCount(b).compareTo(followerCount(a));
    final order = switch (mode) {
      SearchSortMode.smart => [audience, followers, platform],
      SearchSortMode.platform => [platform, audience, followers],
      SearchSortMode.audience => [audience, platform, followers],
      SearchSortMode.followers => [followers, audience, platform],
    };
    for (final comparison in order) {
      final result = comparison();
      if (result != 0) return result;
    }
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (title != 0) return title;
    return a.identityKey.compareTo(b.identityKey);
  }

  static int _stateRank(LiveRoom room) => room.isLiveNow ? 2 : (room.isPlayableNow ? 1 : 0);

  /// The follower count of [room]: its own field, else the audience when
  /// that counts followers (3.x).
  static int followerCount(LiveRoom room) {
    final explicit = parseAudienceNumber(room.followers);
    if (explicit > 0) return explicit;
    if (room.effectiveAudienceMetricType == AudienceMetricType.followers) return parseAudienceNumber(room.watching);
    return 0;
  }
}
