import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// One answer of a platform: its rooms and whether more may follow.
@immutable
final class RoomChunk {
  /// Creates the chunk.
  const new(this.rooms, {required this.hasMore});

  /// The rooms, in the platform's order.
  final List<LiveRoom> rooms;

  /// Whether asking again can give more rooms.
  final bool hasMore;
}

/// How one platform's recommendations are fetched, one chunk after the other
/// (3.x chose one of five page controllers per platform in
/// `PopularController.initControllers`).
abstract interface class RoomSource {
  /// The next chunk.
  Future<RoomChunk> next(CancelToken cancel);

  /// The same source from its first chunk (a refresh).
  RoomSource restart();
}

/// A platform with native directory pages (3.x `LiveDirectoryController`):
/// the page numbers or cursors of the platform, its own end-of-list answer.
final class DirectorySource implements RoomSource {
  /// Creates the source over [pager].
  new(this.pager);

  /// The platform's directory.
  final LiveSiteDirectoryPager pager;

  var _page = 1;
  String? _cursor;

  @override
  Future<RoomChunk> next(CancelToken cancel) async {
    final page = switch (pager) {
      final LiveSiteCursorDirectoryPager cursorPager => await cursorPager.getDirectoryPageAtCursor(
        page: _page,
        cursor: _cursor,
        cancel: cancel,
      ),
      _ => await pager.getDirectoryPage(page: _page, cancel: cancel),
    };
    _page++;
    _cursor = page.nextCursor;
    return RoomChunk(page.rooms, hasMore: page.hasMore);
  }

  @override
  RoomSource restart() => DirectorySource(pager);
}

/// Fixed-size server windows (3.x `PopularServerFixedController`): each
/// request asks for [size] rooms; a shorter answer is the last one.
final class WindowSource implements RoomSource {
  /// Creates the source over [site] with [size] rooms per request.
  new(this.site, this.size);

  /// The platform.
  final LiveSite site;

  /// Rooms per request.
  final int size;

  var _page = 1;

  @override
  Future<RoomChunk> next(CancelToken cancel) async {
    final rooms = await site.getRecommendRooms(page: _page++, pageSize: size);
    return RoomChunk(rooms, hasMore: rooms.length >= size);
  }

  @override
  RoomSource restart() => WindowSource(site, size);
}

/// Numbered pages of a constant size (3.x `PopularServerRemoteController`,
/// which asked each request for only the rooms still missing and so moved
/// the platform's page boundaries; the size is constant here). The list
/// ends at an empty page (and at pages that bring nothing new, see
/// [RoomFeed]).
final class PagedSource implements RoomSource {
  /// Creates the source over [site].
  new(this.site, {this.size = 30});

  /// The platform.
  final LiveSite site;

  /// Rooms per request.
  final int size;

  var _page = 1;

  @override
  Future<RoomChunk> next(CancelToken cancel) async {
    final rooms = await site.getRecommendRooms(page: _page++, pageSize: size);
    return RoomChunk(rooms, hasMore: rooms.isNotEmpty);
  }

  @override
  RoomSource restart() => PagedSource(site, size: size);
}

/// One answer holds everything (3.x `PopularServerAllController` for
/// Kuaishou, `PopularLocalReactiveController` for IPTV).
final class SingleSource implements RoomSource {
  /// Creates the source over [site].
  new(this.site);

  /// The platform.
  final LiveSite site;

  @override
  Future<RoomChunk> next(CancelToken cancel) async =>
      RoomChunk(await site.getRecommendRooms(pageSize: 1000), hasMore: false);

  @override
  RoomSource restart() => SingleSource(site);
}

/// The server window sizes 3.x tuned per platform (`PopularController`).
const Map<String, int> popularWindowSizes = {
  SiteIds.douyu: 40,
  SiteIds.huya: 120,
  SiteIds.soop: 60,
  // One top window filtered before slicing: remote pages skip cards.
  SiteIds.twitcasting: 60,
  // The first large page needs no browser integrity; later cursors can.
  SiteIds.twitch: 100,
  // Heat ordered: a larger window lets real-online mode rank properly.
  SiteIds.cc: 100,
  SiteIds.douyin: 20,
};

/// The source of [site]'s recommendations (3.x's choice per platform).
RoomSource popularSourceFor(LiveSite site) {
  if (site is LiveSiteDirectoryPager) return DirectorySource(site as LiveSiteDirectoryPager);
  if (site.id == SiteIds.iptv || site.id == SiteIds.kuaishou) return SingleSource(site);
  final window = popularWindowSizes[site.id];
  return window == null ? PagedSource(site) : WindowSource(site, window);
}

/// One page from a platform: its rooms, whether another page exists, and
/// the server's cursor for it.
typedef RoomBatch = ({List<LiveRoom> rooms, bool hasMore, String? nextCursor});

/// Loads page [page] (from 1) after [cursor].
typedef RoomPageLoader = Future<RoomBatch> Function(int page, String? cursor, CancelToken cancel);

/// How many rooms to ask a page-numbered platform for: SOOP and TwitCasting
/// take 60 (SOOP's maximum; TwitCasting's whole window), the rest the
/// adapters' default 30 (platforms with a fixed page size ignore it).
int areaRoomPageSize(String platform) => switch (platform) {
  SiteIds.soop || SiteIds.twitcasting => 60,
  _ => 30,
};

/// How [site] pages the rooms of [area] (3.x `AreaRoomsBinding.createController`,
/// simplified to one rule per kind of platform):
/// - platforms with native directory pages (including CC's category pager
///   and cursor platforms such as AcFun, CHZZK, 17LIVE) page natively and
///   say whether there is more;
/// - the others are asked page by page and end at a page with nothing new.
///
/// 3.x cut some platforms' pages into fixed slices, which hid rooms: Douyu
/// returns 120 a page and 3.x showed 40 (upgrade A-1), SOOP asked 30 a
/// page but sliced as if 60 (A-4), Kuaishou took page 1 only and paged it
/// locally (A-2). Every page is now shown whole.
RoomPageLoader areaRoomLoader(LiveSite site, LiveArea area) {
  final directory = switch (site) {
    final LiveSiteDirectoryPager pager => pager,
    final LiveSiteCategoryDirectoryProvider provider => provider.categoryDirectory,
    _ => null,
  };
  if (directory is LiveSiteCursorDirectoryPager) {
    return (page, cursor, cancel) async {
      final answer = await directory.getDirectoryPageAtCursor(
        page: page,
        cursor: cursor,
        category: area,
        cancel: cancel,
      );
      // A cursor that does not move would load the same page forever.
      final next = answer.nextCursor;
      final moved = next != null && next.isNotEmpty && next != cursor;
      return (rooms: answer.rooms, hasMore: answer.hasMore && moved, nextCursor: next);
    };
  }
  if (directory != null) {
    return (page, cursor, cancel) async {
      final answer = await directory.getDirectoryPage(page: page, category: area, cancel: cancel);
      return (rooms: answer.rooms, hasMore: answer.hasMore, nextCursor: answer.nextCursor);
    };
  }
  final pageSize = areaRoomPageSize(site.id);
  return (page, cursor, cancel) async {
    final rooms = await site.getCategoryRooms(area, page: page, pageSize: pageSize);
    return (rooms: rooms, hasMore: rooms.isNotEmpty, nextCursor: null);
  };
}

/// An area's rooms as a [RoomSource]: the pages [load] gives, each room
/// tagged with the area's name ([areaName]; platforms leave it out of
/// category lists).
final class AreaRoomSource implements RoomSource {
  /// Creates the source over [load].
  new(this.load, {this.areaName = ''});

  /// Loads one page.
  final RoomPageLoader load;

  /// The area's name given to its rooms; empty keeps theirs.
  final String areaName;

  var _page = 1;
  String? _cursor;

  @override
  Future<RoomChunk> next(CancelToken cancel) async {
    final batch = await load(_page, _cursor, cancel);
    _page++;
    _cursor = batch.nextCursor;
    final name = areaName.trim();
    if (name.isEmpty) return RoomChunk(batch.rooms, hasMore: batch.hasMore);
    return RoomChunk([for (final room in batch.rooms) room.copyWith(area: name)], hasMore: batch.hasMore);
  }

  @override
  RoomSource restart() => AreaRoomSource(load, areaName: areaName);
}

/// A list of rooms fetched chunk after chunk (M12.2: the popular page's
/// catalogue and an area's rooms share it): the rooms so far without
/// repeats, each chunk ordered by [rank] (popular: by audience, as 3.x did),
/// whether more exist, and the state of the request in flight.
///
/// The rooms shown are the ones [visible] keeps, so the phone list (load more
/// at the end) and the desktop pages show the same catalogue, and a refresh
/// builds a new list before it replaces the old one (a failed refresh keeps
/// what is on screen).
final class RoomFeed extends ChangeNotifier {
  /// Creates the feed of [platform] over [_source]; [rank] orders each chunk
  /// (unchanged when null), at most [maxRooms] are kept.
  new({
    required this.platform,
    required this._source,
    required this.visible,
    List<LiveRoom> Function(String platform, List<LiveRoom> rooms)? rank,
    this.maxRooms,
    this.precheck,
  }) : rank = rank ?? _unranked;

  static List<LiveRoom> _unranked(String platform, List<LiveRoom> rooms) => rooms;

  /// The platform id.
  final String platform;

  /// Orders one chunk (3.x `rankPopularRoomsByAudience` on the popular page).
  final List<LiveRoom> Function(String platform, List<LiveRoom> rooms) rank;

  /// The most rooms kept (3.x kept up to 20000 of an area's directory); null
  /// for no limit.
  final int? maxRooms;

  /// Whether a room is shown (the "show rooms that cannot play" setting).
  final bool Function(LiveRoom room) visible;

  /// Runs before a refresh asks the platform (3.x `checkNetworkBeforeRequest`:
  /// the offline check); its error is the refresh's error.
  final Future<void> Function()? precheck;

  /// Requests per load before it gives up (3.x).
  static const int maxRequests = 20;

  RoomSource _source;
  List<LiveRoom> _rooms = const [];
  Set<String> _keys = {};
  bool _hasMore = true;
  bool _loaded = false;
  bool _busy = false;
  bool _refreshing = false;
  bool _stale = false;
  bool _disposed = false;
  Object? _error;
  bool _errorOnRefresh = false;
  int _generation = 0;
  CancelToken? _cancel;
  Future<void>? _active;

  /// The desktop page shown (1-based).
  int page = 1;

  /// Every room fetched, hidden ones included.
  List<LiveRoom> get allRooms => _rooms;

  /// The rooms shown.
  List<LiveRoom> get rooms => [
    for (final room in _rooms)
      if (visible(room)) room,
  ];

  /// How many fetched rooms [visible] hides.
  int get hiddenCount => _rooms.length - rooms.length;

  /// Whether the platform may have more rooms.
  bool get hasMore => _hasMore;

  /// Whether an answer (or a failure) arrived at least once.
  bool get loaded => _loaded;

  /// Whether a request is running.
  bool get busy => _busy;

  /// Whether a refresh is running.
  bool get refreshing => _refreshing;

  /// The last failure, until the next request.
  Object? get error => _error;

  /// Whether [error] came from a refresh (the old rooms stay on screen).
  bool get errorOnRefresh => _errorOnRefresh;

  /// Whether the ranking settings changed since the rooms were fetched.
  bool get stale => _stale;

  /// Marks the rooms as ranked with old settings: the next [open] refreshes.
  void markStale() => _stale = true;

  /// Forgets the last failure.
  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  /// Called when the tab shows: loads the first rooms, or refreshes rooms
  /// ranked with old settings.
  Future<void> open({required int count}) {
    if (_stale && _loaded) return refresh(count: count);
    if (_loaded && (_rooms.isNotEmpty || _error != null)) return Future.value();
    return ensure(count);
  }

  /// Fetches until [count] rooms are shown or the platform has no more.
  Future<void> ensure(int count) {
    final active = _active;
    if (active != null) return active;
    if (_disposed || (!_hasMore && _loaded) || rooms.length >= count) return Future.value();
    final generation = _generation;
    late final Future<void> operation;
    operation = _fill(count, generation).whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
    return _active = operation;
  }

  /// Loads at least one more shown room unless the list has ended (the end of
  /// a phone list).
  Future<void> loadMore() => _loaded ? ensure(rooms.length + 1) : Future.value();

  /// Retries what failed: the refresh, or the next rooms.
  Future<void> retry({required int count}) =>
      _errorOnRefresh || _rooms.isEmpty ? refresh(count: count) : ensure(rooms.length + 1);

  Future<void> _fill(int count, int generation) async {
    _busy = true;
    _error = null;
    _errorOnRefresh = false;
    _notify();
    final cancel = _cancel = CancelToken();
    final result = _Collected(List.of(_rooms), {..._keys});
    try {
      _hasMore = await _collect(
        _source,
        result,
        count,
        cancel,
        onProgress: () {
          if (generation != _generation) return;
          _rooms = List.unmodifiable(result.rooms);
          _keys = result.keys;
          _loaded = true;
          _notify();
        },
      );
      if (generation != _generation) return;
      _loaded = true;
    } on Object catch (error) {
      if (generation != _generation) return;
      _error = error;
      _loaded = true;
    } finally {
      if (generation == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Fetches a new catalogue from the first chunk and replaces the rooms
  /// once at least [count] are shown (or the platform has no more). A
  /// failure keeps the rooms on screen and reports [error].
  Future<void> refresh({required int count}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _cancel?.cancel();
    _active = null;
    _busy = true;
    _refreshing = true;
    _error = null;
    _errorOnRefresh = false;
    _notify();
    final source = _source.restart();
    final cancel = _cancel = CancelToken();
    final result = _Collected([], {});
    try {
      await precheck?.call();
      if (generation != _generation) return;
      final hasMore = await _collect(source, result, count, cancel);
      if (generation != _generation) return;
      _source = source;
      _rooms = List.unmodifiable(result.rooms);
      _keys = result.keys;
      _hasMore = hasMore;
      _stale = false;
      page = 1;
    } on Object catch (error) {
      if (generation != _generation) return;
      if (_rooms.isEmpty && result.rooms.isNotEmpty) {
        // Nothing to keep: show what arrived before the failure.
        _source = source;
        _rooms = List.unmodifiable(result.rooms);
        _keys = result.keys;
        _hasMore = true;
      } else {
        _errorOnRefresh = _rooms.isNotEmpty;
      }
      _error = error;
    } finally {
      if (generation == _generation) {
        _loaded = true;
        _busy = false;
        _refreshing = false;
        _notify();
      }
    }
  }

  /// Fetches chunks from [source] into [into] until [count] rooms are
  /// visible; answers whether more may follow. Two chunks in a row without a
  /// new room end the list (3.x); an empty chunk that says more may follow
  /// (Kilakila drops repeated timeline pages) counts as one of them, and the
  /// platform's own `hasMore: false` ends it at once.
  Future<bool> _collect(
    RoomSource source,
    _Collected into,
    int count,
    CancelToken cancel, {
    VoidCallback? onProgress,
  }) async {
    var hasMore = true;
    var requests = 0;
    var unchanged = 0;
    int shown() => into.rooms.where(visible).length;
    while (hasMore && shown() < count && requests < maxRequests && unchanged < 2) {
      final chunk = await source.next(cancel);
      if (cancel.isCancelled) throw const _Superseded();
      requests++;
      final fresh = [
        for (final room in chunk.rooms)
          if (into.keys.add(room.identityKey)) room,
      ];
      into.rooms.addAll(rank(platform, fresh));
      unchanged = fresh.isEmpty ? unchanged + 1 : 0;
      hasMore = chunk.hasMore && unchanged < 2;
      if (maxRooms case final limit? when into.rooms.length >= limit) hasMore = false;
      onProgress?.call();
    }
    return hasMore;
  }

  /// Desktop: makes sure page [number] of [size] rooms can be shown.
  Future<void> goToPage(int number, {required int size}) async {
    page = math.max(1, number);
    _notify();
    await ensure(page * size);
    final last = lastPage(size);
    if (!_hasMore && page > last) {
      page = last;
      _notify();
    }
  }

  /// The last page of [size] rooms, as far as known.
  int lastPage(int size) => math.max(1, (rooms.length / size).ceil());

  /// Page [number] of [size] rooms.
  List<LiveRoom> pageRooms(int number, int size) {
    final shown = rooms;
    final start = (number - 1) * size;
    if (start >= shown.length) return const [];
    return shown.sublist(start, math.min(start + size, shown.length));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Visibility or appearance settings changed.
  void visibilityChanged() => _notify();

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    super.dispose();
  }
}

final class _Collected {
  new(this.rooms, this.keys);
  final List<LiveRoom> rooms;
  final Set<String> keys;
}

final class _Superseded implements Exception {
  const new();
}
