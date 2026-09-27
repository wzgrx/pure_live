import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/sites.dart';

/// Which list of rooms to show.
@immutable
sealed class RoomListQuery {
  const new(this.platform);

  /// Platform id.
  final String platform;
}

/// The platform's recommended rooms.
final class RecommendedQuery extends RoomListQuery {
  const new(super.platform);

  @override
  bool operator ==(Object other) => other is RecommendedQuery && other.platform == platform;

  @override
  int get hashCode => Object.hash('recommended', platform);
}

/// Rooms in one area.
final class AreaQuery extends RoomListQuery {
  const new(super.platform, this.area);

  /// The area.
  final Area area;

  @override
  bool operator ==(Object other) =>
      other is AreaQuery &&
      other.platform == platform &&
      other.area.id == area.id &&
      other.area.categoryId == area.categoryId;

  @override
  int get hashCode => Object.hash('area', platform, area.id, area.categoryId);
}

/// Keyword search results on one platform.
final class SearchQuery extends RoomListQuery {
  const new(super.platform, this.keyword);

  /// Search keyword.
  final String keyword;

  @override
  bool operator ==(Object other) => other is SearchQuery && other.platform == platform && other.keyword == keyword;

  @override
  int get hashCode => Object.hash('search', platform, keyword);
}

/// Loaded pages of a list.
@immutable
final class RoomListState {
  const new({required this.items, required this.next, this.loadingMore = false, this.moreError});

  /// Rooms so far, without duplicates.
  final List<RoomCard> items;

  /// Cursor of the next page; null on the last page (the adapter decides).
  final PageCursor? next;

  /// A next page is being fetched.
  final bool loadingMore;

  /// The last next-page request failed.
  final Object? moreError;

  /// Whether another page exists.
  bool get hasMore => next != null;

  RoomListState copyWith({List<RoomCard>? items, PageCursor? next, bool? loadingMore, Object? moreError}) =>
      RoomListState(
        items: items ?? this.items,
        next: next,
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: moreError,
      );
}

/// Pages through a [RoomListQuery]; the first page is the provider's value,
/// later pages come from [loadMore].
class RoomListNotifier extends AsyncNotifier<RoomListState> {
  new(this.query);

  /// The list.
  final RoomListQuery query;

  Future<Page<RoomCard>> _fetch(PageCursor? cursor) {
    final site = ref.read(sitesProvider)[query.platform]!;
    return switch (query) {
      RecommendedQuery() => site.catalog.recommended(cursor: cursor),
      AreaQuery(:final area) => site.catalog.areaRooms(area, cursor: cursor),
      SearchQuery(:final keyword) => site.search.search(keyword, cursor: cursor),
    };
  }

  @override
  Future<RoomListState> build() async {
    final page = await _fetch(null);
    return RoomListState(items: _unique(const [], page.items), next: page.next);
  }

  /// Fetches the next page; ignored while one is loading or at the end.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(next: current.next, loadingMore: true));
    try {
      final page = await _fetch(current.next);
      if (!ref.mounted) return;
      state = AsyncData(RoomListState(items: _unique(current.items, page.items), next: page.next));
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(next: current.next, moreError: error));
    }
  }

  /// Platforms repeat rooms across pages (huya search, recommend); keep the first.
  static List<RoomCard> _unique(List<RoomCard> existing, List<RoomCard> incoming) {
    final seen = {for (final card in existing) card.ref.key};
    return [...existing, ...incoming.where((card) => seen.add(card.ref.key))];
  }
}

/// Paged room lists by query.
final AsyncNotifierProviderFamily<RoomListNotifier, RoomListState, RoomListQuery> roomListProvider =
    AsyncNotifierProvider.autoDispose.family<RoomListNotifier, RoomListState, RoomListQuery>(RoomListNotifier.new);

/// Categories with areas per platform.
final FutureProviderFamily<List<Category>, String> categoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, platform) {
      ref.keepAlive();
      return ref.watch(sitesProvider)[platform]!.catalog.categories();
    });
