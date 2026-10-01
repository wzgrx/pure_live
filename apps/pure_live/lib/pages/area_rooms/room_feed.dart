import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

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

/// Restrictions that cannot be played by a viewer here, so discovery pages
/// hide them unless the user shows them (docs/UPGRADES.md, "受限……": hidden
/// by default, setting `showUnplayableInDiscover`). Login and age checks
/// stay visible: a signed-in viewer may play them.
const Set<LiveRestriction> hiddenInDiscovery = {
  LiveRestriction.unplayable,
  LiveRestriction.paid,
  LiveRestriction.password,
  LiveRestriction.private,
  LiveRestriction.subscribersOnly,
  LiveRestriction.appOnly,
  LiveRestriction.regionBlocked,
};

/// The rooms of one area, page after page (3.x's area room controllers).
///
/// - Refresh starts again from page 1 (which also renews the snapshot of
///   platforms that share one between pages, 19-1, 24-5, 26-1) and only
///   replaces the shown rooms when it succeeds.
/// - More pages load at the end of the list; a failure keeps the rooms and
///   can be retried.
/// - Rooms are kept once per identity; a page with nothing new ends the list.
final class AreaRoomFeed extends ChangeNotifier {
  /// The rooms `load` gives for [area]; `showUnplayable` says whether rooms
  /// that cannot be played are listed.
  new({required this._load, required this.area, this._showUnplayable = false, this.maxRooms = 5000});

  final RoomPageLoader _load;

  /// The area.
  final LiveArea area;

  /// The most rooms kept (3.x kept up to 20000 of native directories).
  final int maxRooms;

  List<LiveRoom> _all = const [];
  final Set<String> _seen = {};
  int _nextPage = 1;
  String? _cursor;
  bool _hasMore = true;
  bool _loaded = false;
  bool _showUnplayable;
  Object? _error;
  bool _refreshFailed = false;
  bool _refreshing = false;
  bool _loadingMore = false;
  int _generation = 0;
  CancelToken? _cancel;
  bool _disposed = false;

  /// The rooms to show.
  List<LiveRoom> get rooms => _showUnplayable
      ? _all
      : [
          for (final room in _all)
            if (!_hidden(room)) room,
        ];

  /// How many loaded rooms are hidden as unplayable.
  int get hiddenCount => _showUnplayable ? 0 : _all.where(_hidden).length;

  /// Whether unplayable rooms are listed.
  bool get showUnplayable => _showUnplayable;

  set showUnplayable(bool value) {
    if (value == _showUnplayable) return;
    _showUnplayable = value;
    _notify();
  }

  /// Whether page 1 has answered once.
  bool get hasLoaded => _loaded;

  /// Whether another page may exist.
  bool get hasMore => _hasMore;

  /// The last failure (null after a success).
  Object? get error => _error;

  /// Whether [error] is a failed refresh (the rooms shown are the old ones)
  /// rather than a failed next page.
  bool get refreshFailed => _refreshFailed;

  /// Whether page 1 is loading again.
  bool get isRefreshing => _refreshing;

  /// Whether a further page is loading.
  bool get isLoadingMore => _loadingMore;

  /// Whether anything is loading.
  bool get isLoading => _refreshing || _loadingMore;

  bool _hidden(LiveRoom room) => hiddenInDiscovery.contains(room.effectiveRestriction);

  /// Loads page 1 again; the rooms shown stay until it answers.
  Future<void> refresh() async {
    final generation = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    _refreshing = true;
    _loadingMore = false;
    _notify();
    try {
      final batch = await _load(1, null, cancel);
      if (_stale(generation)) return;
      _all = const [];
      _seen.clear();
      _accept(batch, page: 1);
      _error = null;
      _refreshFailed = false;
    } on Object catch (error) {
      if (_stale(generation)) return;
      _error = error;
      _refreshFailed = true;
    } finally {
      if (!_stale(generation)) {
        _loaded = true;
        _refreshing = false;
        _notify();
      }
    }
  }

  /// Loads the next page unless one is loading or the list has ended.
  Future<void> loadMore() async {
    if (!_loaded || !_hasMore || isLoading || _disposed) return;
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    _loadingMore = true;
    _error = null;
    _refreshFailed = false;
    _notify();
    try {
      final batch = await _load(_nextPage, _cursor, cancel);
      if (_stale(generation)) return;
      _accept(batch, page: _nextPage);
    } on Object catch (error) {
      if (_stale(generation)) return;
      _error = error;
    } finally {
      if (!_stale(generation)) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  /// Retries what failed: page 1 after a failed refresh or with nothing
  /// shown, else the next page.
  Future<void> retry() => _all.isEmpty || _refreshFailed ? refresh() : loadMore();

  void _accept(RoomBatch batch, {required int page}) {
    final areaName = area.areaName.trim();
    final fresh = <LiveRoom>[];
    for (final room in batch.rooms) {
      if (_seen.add(room.identityKey)) fresh.add(areaName.isEmpty ? room : room.copyWith(area: areaName));
    }
    _all = List.unmodifiable([..._all, ...fresh]);
    _nextPage = page + 1;
    _cursor = batch.nextCursor;
    _hasMore = batch.hasMore && fresh.isNotEmpty && _all.length < maxRooms;
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
