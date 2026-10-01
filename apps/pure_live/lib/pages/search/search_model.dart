import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/pages/search/search_capability.dart';
import 'package:pure_live/pages/search/search_ranking.dart';

/// What the search looks for.
enum SearchMode {
  /// Rooms (`LiveSite.searchRooms`; 3.x's only mode).
  rooms,

  /// Streamers (`LiveSite.searchAnchors`; new in v4).
  anchors,
}

/// A streamer found on [platform].
@immutable
final class AnchorResult {
  /// Creates the result.
  const new(this.platform, this.item);

  /// Platform id.
  final String platform;

  /// What the platform answered.
  final LiveAnchorItem item;

  /// Whether the streamer is live.
  bool get isLive => item.liveStatus;

  /// The streamer's room, to open.
  LiveRoom toRoom() => LiveRoom(
    platform: platform,
    roomId: item.roomId,
    nick: item.userName,
    avatar: item.avatar,
    liveStatus: item.liveStatus ? LiveStatus.live : LiveStatus.offline,
  );

  /// Identity within the results.
  String get key => LiveRoom.identityKeyFor(platform: platform, roomId: item.roomId);
}

/// How long one platform may take for one page (3.x `liveSearchRequestTimeout`).
const Duration searchRequestTimeout = Duration(seconds: 12);

/// Pages in a row without new results before a platform stops paging
/// (3.x `maxConsecutiveStagnantSearchPages`).
const int maxStagnantSearchPages = 2;

/// Platforms searched at the same time (3.x `maxConcurrentNativeSearchSites`).
const int maxConcurrentSearchSites = 12;

/// The search page's state and requests (3.x `SearchController`, without
/// GetX): platform choice, all-platform fan-out with bounded concurrency,
/// per-platform paging, cancellation of a replaced search, filtering and
/// ordering.
final class SearchModel extends ChangeNotifier {
  /// A model over [sites] (a snapshot of the user's platform list for the
  /// page's lifetime). [audienceCompare] orders by audience with the user's
  /// audience settings.
  new({
    required List<LiveSite> sites,
    required this.audienceCompare,
    this.timeout = searchRequestTimeout,
    this.pageSize = 20,
  }) : sites = List.unmodifiable(sites) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  }

  /// The platforms, in the user's order.
  final List<LiveSite> sites;

  /// Orders two rooms by audience.
  final int Function(LiveRoom left, LiveRoom right) audienceCompare;

  /// How long one platform may take for one page.
  final Duration timeout;

  /// Rooms asked for per page.
  final int pageSize;

  int _selected = 0;
  SearchMode _mode = SearchMode.rooms;
  bool _includeOffline = true;
  SearchSortMode _sort = SearchSortMode.smart;
  String _keyword = '';
  int _page = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;
  bool _hasMore = false;
  int _pending = 0;
  List<String> _failed = const [];
  LiveSite? _unsupported;
  List<LiveRoom> _results = const [];
  List<AnchorResult> _anchors = const [];
  final Map<String, LiveRoom> _rawRooms = {};
  final Map<String, AnchorResult> _rawAnchors = {};
  final Map<String, bool> _more = {};
  final Map<String, int> _stagnant = {};
  int _generation = 0;
  CancelToken? _cancel;
  Future<void>? _task;
  (int, SearchMode, String)? _taskKey;
  bool _disposed = false;

  /// The chosen platform: 0 is all, `i` is `sites[i - 1]`.
  int get selected => _selected;

  /// The chosen platform, or null for all.
  LiveSite? get selectedSite => _selected == 0 ? null : sites[_selected - 1];

  /// What is searched.
  SearchMode get mode => _mode;

  /// Whether offline results are shown.
  bool get includeOffline => _includeOffline;

  /// The order.
  SearchSortMode get sort => _sort;

  /// The keyword of the current results.
  String get keyword => _keyword;

  /// The first page is loading.
  bool get loading => _loading;

  /// A further page is loading.
  bool get loadingMore => _loadingMore;

  /// A search has been made (results, empty or failed).
  bool get searched => _searched;

  /// Another page can be loaded.
  bool get hasMore => _hasMore;

  /// Platforms still answering the current page.
  int get pending => _pending;

  /// Ids of the platforms whose last page failed.
  List<String> get failed => _failed;

  /// The chosen platform when it cannot search in [mode].
  LiveSite? get unsupported => _unsupported;

  /// Rooms, filtered and ordered.
  List<LiveRoom> get results => _results;

  /// Streamers, filtered and ordered.
  List<AnchorResult> get anchors => _anchors;

  /// Number of shown results in [mode].
  int get resultCount => _mode == SearchMode.rooms ? _results.length : _anchors.length;

  /// Every result is offline and offline results are hidden.
  bool get hidesAllOffline =>
      !_includeOffline &&
      resultCount == 0 &&
      (_mode == SearchMode.rooms ? _rawRooms.isNotEmpty : _rawAnchors.isNotEmpty);

  /// Whether [site] can be searched in [mode].
  static bool supports(LiveSite site, SearchMode mode) {
    final capability = SearchCapabilities.of(site.id);
    return mode == SearchMode.rooms ? capability.native : capability.anchors;
  }

  /// Whether anything chosen can be searched in [mode].
  bool get canSearch => _chosen.any((site) => supports(site, _mode));

  /// Whether the chosen platform has a web search.
  bool get canOpenWebSearch {
    final site = selectedSite;
    return site != null && SearchCapabilities.of(site.id).webSearch;
  }

  List<LiveSite> get _chosen => _selected == 0 ? sites : [sites[_selected - 1]];

  /// Chooses platform [index] (0 for all). After a search, searches
  /// [draft] there (3.x searched the text field's current words); an empty
  /// draft clears the old platform's results.
  void select(int index, {String draft = ''}) {
    final next = index.clamp(0, sites.length);
    if (_disposed || next == _selected) return;
    _invalidate();
    _selected = next;
    _rerunOrReset(draft);
  }

  /// Switches to [mode], searching [draft] like [select].
  void setMode(SearchMode mode, {String draft = ''}) {
    if (_disposed || mode == _mode) return;
    _invalidate();
    _mode = mode;
    _rerunOrReset(draft);
  }

  void _rerunOrReset(String draft) {
    if (!_searched) {
      _notify();
      return;
    }
    final word = draft.trim();
    if (word.isNotEmpty) {
      unawaited(search(word));
      return;
    }
    _reset(searched: false);
    _notify();
  }

  /// Shows or hides offline results.
  void setIncludeOffline({required bool value}) {
    if (_disposed || value == _includeOffline) return;
    _includeOffline = value;
    _apply();
    _notify();
  }

  /// Orders by [value].
  void setSort(SearchSortMode value) {
    if (_disposed || value == _sort) return;
    _sort = value;
    _apply();
    _notify();
  }

  /// Orders again (the audience settings changed).
  void reorder() {
    if (_disposed) return;
    _apply();
    _notify();
  }

  /// Searches [keyword] on the chosen platforms. A second call for the same
  /// platform, mode and words while the first is running joins it (Enter
  /// and the search button can both fire in one frame).
  Future<void> search(String keyword) {
    final word = keyword.trim();
    if (_disposed || word.isEmpty) return Future.value();
    final key = (_selected, _mode, word);
    final running = _task;
    if (running != null && _taskKey == key) return running;
    late final Future<void> task;
    task = _start(word).whenComplete(() {
      if (!identical(_task, task)) return;
      _task = null;
      _taskKey = null;
    });
    _task = task;
    _taskKey = key;
    return task;
  }

  Future<void> _start(String word) async {
    _invalidate(retireTask: false);
    final generation = _generation;
    _cancel = CancelToken();
    _keyword = word;
    _reset(searched: true);
    _loading = true;
    _notify();
    await _searchPage(word, 1, generation, append: false);
  }

  /// Loads the next page.
  Future<void> loadMore() async {
    if (_disposed || _loading || _loadingMore || !_hasMore || _keyword.isEmpty) return;
    _loadingMore = true;
    _notify();
    await _searchPage(_keyword, _page + 1, _generation, append: true);
  }

  void _reset({required bool searched}) {
    if (!searched) _keyword = '';
    _page = 0;
    _loading = false;
    _loadingMore = false;
    _pending = 0;
    _hasMore = false;
    _searched = searched;
    _failed = const [];
    _unsupported = null;
    _rawRooms.clear();
    _rawAnchors.clear();
    _more.clear();
    _stagnant.clear();
    _results = const [];
    _anchors = const [];
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _invalidate({bool retireTask = true}) {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    if (retireTask) {
      _task = null;
      _taskKey = null;
    }
  }

  Future<void> _searchPage(String word, int page, int generation, {required bool append}) async {
    final mode = _mode;
    final chosen = _chosen;
    if (!append) {
      for (final site in chosen) {
        _more[site.id] = supports(site, mode);
        _stagnant[site.id] = 0;
      }
    }
    final searchable = [
      for (final site in chosen)
        if (supports(site, mode) && (!append || (_more[site.id] ?? false))) site,
    ];
    final cancel = _cancel;
    if (searchable.isEmpty || cancel == null) {
      if (!_isCurrent(generation)) return;
      if (chosen.length == 1 && !supports(chosen.single, mode)) _unsupported = chosen.single;
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _pending = 0;
      _apply();
      _notify();
      return;
    }

    _pending = searchable.length;
    _notify();
    final failures = <String>[];
    var completed = 0;
    // Show each platform's answer as it arrives instead of waiting for the
    // slowest one.
    await for (final batch in _searchBounded(searchable, word, page, mode, cancel)) {
      // Drain retired batches too, but never write them.
      if (!_isCurrent(generation)) continue;
      final before = _rawRooms.length + _rawAnchors.length;
      for (final room in batch.rooms) {
        _rawRooms[_roomKey(room)] = room;
      }
      for (final item in batch.anchors) {
        final result = AnchorResult(batch.site.id, item);
        _rawAnchors[result.key] = result;
      }
      final added = _rawRooms.length + _rawAnchors.length - before;
      if (batch.failed) failures.add(batch.site.id);
      _more[batch.site.id] = _canLoadAnother(batch, word, mode, added);
      completed++;
      _pending = searchable.length - completed;
      _apply();
      if (resultCount > 0 || completed == searchable.length) _loading = false;
      _notify();
    }

    if (!_isCurrent(generation)) return;
    _page = page;
    _hasMore = chosen.any((site) => _more[site.id] ?? false);
    _failed = List.unmodifiable(failures);
    _loading = false;
    _loadingMore = false;
    _pending = 0;
    _notify();
  }

  Stream<_Batch> _searchBounded(
    List<LiveSite> searchable,
    String word,
    int page,
    SearchMode mode,
    CancelToken cancel,
  ) async* {
    final active = <int, Future<_Batch>>{};
    var next = 0;
    void fill() {
      while (!cancel.isCancelled && active.length < maxConcurrentSearchSites && next < searchable.length) {
        final index = next++;
        active[index] = _searchSite(searchable[index], word, page, mode, cancel);
      }
    }

    fill();
    while (active.isNotEmpty) {
      final done = await Future.any([
        for (final MapEntry(:key, :value) in active.entries) value.then((batch) => (key, batch)),
      ]);
      unawaited(active.remove(done.$1));
      yield done.$2;
      // A retired search drains started requests but opens no queued ones.
      fill();
    }
  }

  bool _canLoadAnother(_Batch batch, String word, SearchMode mode, int added) {
    final site = batch.site;
    final capability = SearchCapabilities.of(site.id);
    final refused = mode == SearchMode.rooms && site is LiveSearchPaginationPolicy && !_pagesFor(site, word);
    if (!capability.paged || refused || batch.failed || batch.isEmpty) {
      _stagnant.remove(site.id);
      return false;
    }
    if (added > 0) {
      _stagnant[site.id] = 0;
      return true;
    }
    // Search pages often overlap by one answer: allow a bounded chance to
    // reach the next new page, but stop endpoints repeating themselves.
    final stagnant = (_stagnant[site.id] ?? 0) + 1;
    _stagnant[site.id] = stagnant;
    return stagnant < maxStagnantSearchPages;
  }

  static bool _pagesFor(LiveSite site, String word) =>
      (site as LiveSearchPaginationPolicy).supportsSearchPaginationFor(word);

  Future<_Batch> _searchSite(LiveSite site, String word, int page, SearchMode mode, CancelToken cancel) async {
    // One token per request: cancelled with the search or at the deadline.
    final token = CancelToken();
    final timer = Timer(timeout, token.cancel);
    unawaited(cancel.whenCancelled.then((_) => token.cancel()));
    try {
      final query = _queryFor(site.id, word);
      final work = mode == SearchMode.rooms
          ? site
                .searchRoomsWithCancellation(query, page: page, pageSize: pageSize, cancel: token)
                .then((rooms) => _Batch(site, rooms: rooms))
          : site.searchAnchors(word, page: page, pageSize: pageSize).then((items) => _Batch(site, anchors: items));
      // Adapters without transport cancellation are no longer waited for;
      // their request itself is not stopped.
      final batch = await Future.any([
        work,
        token.whenCancelled.then<_Batch>((_) => throw TransportFailure(site.id, TransportReason.cancelled)),
      ]);
      if (token.isCancelled) throw TransportFailure(site.id, TransportReason.cancelled);
      return batch;
    } on Object catch (error) {
      if (!cancel.isCancelled) log('Search failed on ${site.id}: $error', name: 'Search');
      return _Batch(site, failed: true);
    } finally {
      timer.cancel();
    }
  }

  /// The words sent to [platform]. TwitCasting refuses a keyword over 100
  /// characters (`ArgumentError`, as 3.x), which turned a pasted share text
  /// into a "failed" platform; it gets the first 100 like the platforms
  /// that cut themselves (UPGRADES 13-4, 15-5, 20-5, 33-5).
  static String _queryFor(String platform, String word) =>
      platform == SiteIds.twitcasting && word.length > 100 ? word.substring(0, 100) : word;

  static String _roomKey(LiveRoom room) {
    if (room.roomId.isNotEmpty) return room.identityKey;
    return '${room.platform}:${room.nick.trim()}:${room.title.trim()}';
  }

  void _apply() {
    final order = [for (final site in sites) site.id];
    _results = SearchRanking.apply(
      rooms: _rawRooms.values,
      mode: _sort,
      includeOffline: _includeOffline,
      platformOrder: order,
      audienceCompare: audienceCompare,
    );
    final ranks = {for (var i = 0; i < order.length; i++) order[i]: i};
    _anchors =
        [
          for (final result in _rawAnchors.values)
            if (_includeOffline || result.isLive) result,
        ]..sort((a, b) {
          final live = (b.isLive ? 1 : 0).compareTo(a.isLive ? 1 : 0);
          if (live != 0) return live;
          return (ranks[a.platform] ?? order.length).compareTo(ranks[b.platform] ?? order.length);
        });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _invalidate();
    _disposed = true;
    super.dispose();
  }
}

final class _Batch {
  new(this.site, {this.rooms = const [], this.anchors = const [], this.failed = false});

  final LiveSite site;
  final List<LiveRoom> rooms;
  final List<LiveAnchorItem> anchors;
  final bool failed;

  bool get isEmpty => rooms.isEmpty && anchors.isEmpty;
}
