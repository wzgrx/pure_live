import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/sites.dart';

/// Orders of the search results (spec/product.md F-SRC-01). "粉丝" waits for
/// a follower count in the card model.
enum SearchSort {
  /// Each platform's own relevance, merged by rank.
  smart,

  /// Platform order, then audience.
  platform,

  /// Audience, then platform order.
  audience,
}

/// Menu labels of [SearchSort].
const Map<SearchSort, String> searchSortLabels = {
  SearchSort.smart: '智能',
  SearchSort.platform: '按平台',
  SearchSort.audience: '按人数',
};

int _audience(RoomCard card) => card.audience.online ?? card.audience.popularity ?? card.audience.cumulative ?? 0;

/// [cards] in [sort] order (3.x search_ranking.dart): live rooms always come
/// first; smart keeps each platform's relevance and takes the platforms in
/// turn (their first results, then their second …); ties fall back to the
/// title and the room key, so the order is stable. [platforms] is the user's
/// platform order.
List<RoomCard> sortSearch(List<RoomCard> cards, SearchSort sort, {required List<String> platforms}) {
  final rank = <String, int>{};
  final seen = <String, int>{};
  for (final card in cards) {
    final platform = card.ref.platform;
    final position = seen.update(platform, (value) => value + 1, ifAbsent: () => 0);
    rank[card.ref.key] = position;
  }
  int platformRank(RoomCard card) {
    final index = platforms.indexOf(card.ref.platform);
    return index < 0 ? platforms.length : index;
  }

  int compare(RoomCard a, RoomCard b) {
    final live = (b.state == LiveState.live ? 1 : 0) - (a.state == LiveState.live ? 1 : 0);
    if (live != 0) return live;
    final byPlatform = platformRank(a).compareTo(platformRank(b));
    final byAudience = _audience(b).compareTo(_audience(a));
    final byRelevance = rank[a.ref.key]!.compareTo(rank[b.ref.key]!);
    for (final order in switch (sort) {
      SearchSort.smart => [byRelevance, byPlatform],
      SearchSort.platform => [byPlatform, byAudience],
      SearchSort.audience => [byAudience, byPlatform],
    }) {
      if (order != 0) return order;
    }
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return title != 0 ? title : a.ref.key.compareTo(b.ref.key);
  }

  return [...cards]..sort(compare);
}

/// The combined results of every platform for one keyword.
@immutable
final class CombinedSearchState {
  const new({
    required this.items,
    this.cursors = const {},
    this.failed = const {},
    this.loadingMore = false,
    this.moreError,
  });

  /// Rooms without duplicates, each platform's in its own order.
  final List<RoomCard> items;

  /// Next-page cursors of the platforms that have more.
  final Map<String, PageCursor> cursors;

  /// Platforms whose first page failed (left out, the rest still shows).
  final Set<String> failed;

  /// A next round of pages is loading.
  final bool loadingMore;

  /// Every request of the last round failed.
  final Object? moreError;

  /// Whether any platform has another page.
  bool get hasMore => cursors.isNotEmpty;

  /// Rooms found per platform, for the filter rail.
  Map<String, int> get counts {
    final counts = <String, int>{};
    for (final card in items) {
      counts.update(card.ref.platform, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

/// "综合" search (F-SRC-01): the first page of every enabled platform, then
/// on [loadMore] the next page of each platform that still has one. A failing
/// platform is left out instead of failing the whole list; a platform whose
/// pages keep repeating rooms stops after two such pages (3.x
/// search_controller.dart `_canLoadAnotherPage`).
class CombinedSearchNotifier extends AsyncNotifier<CombinedSearchState> {
  new(this.keyword);

  /// The keyword.
  final String keyword;

  static const _maxStagnant = 2;
  final Map<String, int> _stagnant = {};

  Future<(String, Page<RoomCard>?, Object?)> _page(String platform, PageCursor? cursor) async {
    try {
      final page = await ref.read(sitesProvider).of(platform).search.search(keyword, cursor: cursor);
      return (platform, page, null);
    } on Object catch (error) {
      return (platform, null, error);
    }
  }

  @override
  Future<CombinedSearchState> build() async {
    ref.watch(sitesProvider);
    final platforms = ref.watch(searchablePlatformsProvider);
    _stagnant.clear();
    final pages = await Future.wait([for (final id in platforms) _page(id, null)]);
    final items = <RoomCard>[];
    final keys = <String>{};
    final cursors = <String, PageCursor>{};
    final failed = <String>{};
    for (final (platform, page, _) in pages) {
      if (page == null) {
        failed.add(platform);
        continue;
      }
      items.addAll(page.items.where((card) => keys.add(card.ref.key)));
      if (page.next case final next? when page.items.isNotEmpty) cursors[platform] = next;
    }
    return CombinedSearchState(items: items, cursors: cursors, failed: failed);
  }

  /// Loads the next page of every platform that has one; ignored while a
  /// round loads or when no platform has more.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(
      CombinedSearchState(items: current.items, cursors: current.cursors, failed: current.failed, loadingMore: true),
    );
    final pages = await Future.wait([
      for (final MapEntry(key: platform, value: cursor) in current.cursors.entries) _page(platform, cursor),
    ]);
    if (!ref.mounted) return;
    final keys = {for (final card in current.items) card.ref.key};
    final items = [...current.items];
    final cursors = <String, PageCursor>{};
    Object? error;
    var answered = 0;
    for (final (platform, page, failure) in pages) {
      if (page == null) {
        // Keep the cursor: the retry asks this page again.
        cursors[platform] = current.cursors[platform]!;
        error = failure;
        continue;
      }
      answered++;
      final before = items.length;
      items.addAll(page.items.where((card) => keys.add(card.ref.key)));
      final added = items.length - before;
      final stagnant = added == 0 ? (_stagnant[platform] ?? 0) + 1 : 0;
      _stagnant[platform] = stagnant;
      if (page.next case final next? when page.items.isNotEmpty && stagnant < _maxStagnant) cursors[platform] = next;
    }
    state = AsyncData(
      CombinedSearchState(
        items: items,
        cursors: cursors,
        failed: current.failed,
        moreError: answered == 0 ? error : null,
      ),
    );
  }
}

/// Combined results by keyword.
final AsyncNotifierProviderFamily<CombinedSearchNotifier, CombinedSearchState, String> combinedSearchProvider =
    AsyncNotifierProvider.autoDispose.family<CombinedSearchNotifier, CombinedSearchState, String>(
      CombinedSearchNotifier.new,
    );
