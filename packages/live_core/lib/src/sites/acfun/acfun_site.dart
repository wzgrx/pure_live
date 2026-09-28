import 'dart:async';
import 'dart:math';

import 'package:live_core/src/json.dart';
import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/acfun/acfun_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'acfun';

/// How long a visitor session is reused (3.x).
const _visitorLifetime = Duration(minutes: 5);

/// The budget of one search page, every server page it reads included
/// (3.x's timeout).
const _defaultSearchTimeout = Duration(seconds: 8);

/// Server pages one search page may read before the answer counts as
/// broken (3.x).
const _maxSearchRequests = 4;

/// Listings (a page size and filter), cursors per listing and searches
/// kept (3.x's bounds).
const _maxListings = 12;
const _maxCursors = 64;
const _maxSearches = 8;

/// Author ids in links (3.x's `WebSearchRoomParser` rule).
final RegExp _authorPattern = RegExp(r'^[1-9][0-9]{0,19}$');

const _deviceAlphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// What one `startPlay` gave, with the visitor session it was asked with.
typedef _Play = ({AcfunRoomData data, List<String> tickets, String enterRoomAttach, AcfunVisitor visitor});

/// The AcFun adapter (3.x's `AcfunSite`, `AcfunApi`, `AcfunDirectory` and
/// `AcfunSearchClient`; parsing in [AcfunApi]).
///
/// Everything is anonymous. Lists, details and search need no session;
/// streams come from `startPlay`, asked with a visitor session that is kept
/// in memory for five minutes and shared by concurrent callers. The
/// directory and the author search are cursor-paged by the site and served
/// here by page number, as 3.x did. Failures are `SiteError`s; nothing is
/// disguised as an offline room.
final class AcfunSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver, LivePlayRecoveryResolver {
  /// Creates the adapter; [now], [random] (the visitor's device id) and
  /// `searchTimeout` (8 seconds, 3.x's) are injectable for tests.
  new(this.http, {DateTime Function()? now, Random? random, this._searchTimeout = _defaultSearchTimeout})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  final Random _random;
  final Duration _searchTimeout;

  ({AcfunVisitor visitor, DateTime expiresAt})? _visitor;
  Future<AcfunVisitor>? _login;
  final Map<String, _Listing> _listings = {};
  final Map<(String, int), _Search> _searches = {};

  @override
  String get id => _site;

  @override
  String get name => 'AcFun 直播';

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url) => _send(LiveRequest(site: _site, url: url, headers: AcfunApi.apiHeaders));

  /// `api/channel/list` with 3.x's query (`pcursor=` even when empty).
  static Uri _listUrl({required int count, String cursor = '', String? filters}) => LiveRequest.withQuery(
    Uri.https('live.acfun.cn', '/api/channel/list'),
    {'count': count, 'pcursor': cursor, 'filters': filters},
  );

  static String _authorId(String roomId) {
    final id = roomId.trim();
    if (!AcfunApi.isAuthorId(id)) throw NotFound(_site, 'room id "$id" is not an AcFun author id');
    return id;
  }

  // Catalog -------------------------------------------------------------------

  /// One category (id `acfun`, the display name, as in 3.x) with the areas
  /// of a one-room list answer, so no listing's cursors are touched.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page > 1) return const [];
    final response = await _get(_listUrl(count: 1));
    return [
      LiveCategory(
        id: id,
        name: name,
        children: AcfunApi.areas(response.text, typeName: name, status: response.status),
      ),
    ];
  }

  /// Live rooms of [category] (its filter type and id); [pageSize] is sent,
  /// limited to 1–60 (3.x). An area of another platform, or without numeric
  /// ids, is `NotFound`.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final type = jsonCount(category.areaType);
    final area = jsonCount(category.areaId);
    final platform = category.platform.trim().toLowerCase();
    if (type == null || area == null || (platform.isNotEmpty && platform != _site)) {
      throw NotFound(
        _site,
        'area ${category.areaType}/${category.areaId} of "${category.platform}" is not an AcFun area',
      );
    }
    return await _listingPage(page, pageSize.clamp(1, 60), AcfunApi.filterQuery(type: type, id: area));
  }

  /// Every live room by popularity; [pageSize] is sent, limited to 1–60.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      _listingPage(page, pageSize.clamp(1, 60), null);

  /// Page [page] of a listing. The site pages by opaque cursor (`pcursor`);
  /// a first-page read starts a new chain of cursors (a refresh; a first
  /// page still loading is shared). A page after the last one is empty
  /// without a request.
  Future<List<LiveRoom>> _listingPage(int page, int count, String? filters) {
    final number = page < 1 ? 1 : page;
    final key = '$count ${filters ?? ''}';
    var listing = _listings.remove(key);
    if (listing == null || (number == 1 && listing.pending[1] == null)) listing = _Listing();
    _listings[key] = listing;
    while (_listings.length > _maxListings) {
      _listings.remove(_listings.keys.first);
    }
    return _page(listing, number, count, filters);
  }

  Future<List<LiveRoom>> _page(_Listing listing, int page, int count, String? filters) {
    final pending = listing.pending[page];
    if (pending != null) return pending;
    final last = listing.lastPage;
    if (last != null && page > last) return Future.value(const []);
    final cursor = listing.cursorOf(page);
    if (cursor == null) {
      // The chain lost this page's cursor (a refresh by another list, or an
      // evicted listing). 3.x failed with "pagination expired"
      // (REG-ACFUN-004); the pages before it are read again instead.
      return _page(listing, page - 1, count, filters).then((_) => _page(listing, page, count, filters));
    }
    return listing.pending[page] = _load(listing, page, cursor, count, filters);
  }

  Future<List<LiveRoom>> _load(_Listing listing, int page, String cursor, int count, String? filters) async {
    try {
      final response = await _get(_listUrl(count: count, cursor: cursor, filters: filters));
      final result = AcfunApi.directory(response.text, status: response.status);
      final next = result.next;
      if (next == null) {
        listing.lastPage = page;
      } else {
        // A cursor this chain already used cannot lead anywhere new (3.x).
        for (var earlier = 1; earlier <= page; earlier++) {
          if (listing.cursorOf(earlier) == next) {
            throw ApiChanged(_site, 'channel/list: page $page repeats the cursor of page $earlier');
          }
        }
        if (listing.lastPage == page) listing.lastPage = null;
        listing.cursors[page + 1] = next;
        while (listing.cursors.length > _maxCursors) {
          listing.cursors.remove(listing.cursors.keys.reduce(min));
        }
      }
      return result.rooms;
    } finally {
      listing.pending.removeWhere((key, _) => key == page);
    }
  }

  // Search --------------------------------------------------------------------

  /// Authors matching [keyword], live or not (the site's author search;
  /// 30 a server page). Pages of [pageSize] (limited to 1–60) are cut from
  /// the server pages in order, so a short server page never ends the
  /// results early (REG-ACFUN-002): they end when the pages reach
  /// `data-total`. A page takes at most 8 seconds and 4 server pages; a
  /// first-page read restarts the search and cancels the previous one's
  /// requests. A blank keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final number = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, 60);
    final key = (text, size);
    var search = _searches.remove(key);
    if (number == 1 && search?.inFlightPage != 1) {
      search?.cancel?.cancel();
      search = null;
    }
    search ??= _Search.at(number, size);
    _searches[key] = search;
    while (_searches.length > _maxSearches) {
      _searches.remove(_searches.keys.first)?.cancel?.cancel();
    }
    final running = search.inFlight;
    if (running != null) {
      if (search.inFlightPage == number) return await running;
      // 3.x failed another page while one was loading ("pagination
      // expired"); this one waits for it and is served after it.
      try {
        await running;
      } on Object {
        // That page's caller sees its failure.
      }
      return await searchRooms(keyword, page: number, pageSize: size);
    }
    if (search.finished && search.remaining.isEmpty && number >= search.nextPage) return const [];
    if (number != search.nextPage) {
      // Not the page after the last one served (the search was restarted
      // or evicted): 3.x failed with "pagination expired"; the search starts
      // again at the page's position instead.
      search = _searches[key] = _Search.at(number, size);
    }
    search.inFlightPage = number;
    return await (search.inFlight = _collect(key, search));
  }

  /// [searchRooms] as streamers (3.x).
  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => [
    for (final room in await searchRooms(keyword, page: page, pageSize: pageSize))
      LiveAnchorItem(roomId: room.roomId, avatar: room.avatar, userName: room.nick, liveStatus: room.isLiveNow),
  ];

  Future<List<LiveRoom>> _collect((String, int) key, _Search search) async {
    final cancel = CancelToken();
    search.cancel = cancel;
    try {
      return await _fill(key, search, cancel).timeout(
        _searchTimeout,
        onTimeout: () => throw NetworkFailure(_site, 'search: no page within ${_searchTimeout.inMilliseconds} ms'),
      );
    } finally {
      // A timeout alone would leave the request running.
      cancel.cancel();
      search
        ..cancel = null
        ..inFlight = null
        ..inFlightPage = null;
    }
  }

  /// One page from the rows left over and the next server pages. Only a
  /// whole page is committed: a failure leaves the search where it was, so
  /// the same page can be asked for again.
  Future<List<LiveRoom>> _fill((String, int) key, _Search search, CancelToken cancel) async {
    final (keyword, size) = key;
    var remaining = search.remaining;
    var serverPage = search.nextServerPage;
    var finished = search.finished;
    var skip = search.skip;
    var requests = 0;
    final result = <LiveRoom>[];
    while (result.length < size) {
      if (cancel.isCancelled) throw const TransportFailure(_site, TransportReason.cancelled, 'search restarted');
      if (remaining.isEmpty) {
        if (finished) break;
        if (++requests > _maxSearchRequests) {
          throw const ApiChanged(_site, 'search: $_maxSearchRequests server pages without authors');
        }
        final answer = await _searchPage(keyword, serverPage, cancel);
        remaining = answer.rooms.skip(skip).toList();
        skip = 0;
        finished = serverPage * AcfunApi.searchPageSize >= answer.total;
        serverPage++;
      }
      final take = min(size - result.length, remaining.length);
      result.addAll(remaining.take(take));
      remaining = remaining.sublist(take);
    }
    if (cancel.isCancelled || !identical(_searches[key], search)) {
      throw const TransportFailure(_site, TransportReason.cancelled, 'search restarted');
    }
    search
      ..remaining = remaining
      ..nextServerPage = serverPage
      ..finished = finished
      ..skip = 0
      ..nextPage += 1;
    return result;
  }

  Future<({List<LiveRoom> rooms, int total})> _searchPage(String keyword, int page, CancelToken cancel) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('www.acfun.cn', '/search', {
          'keyword': keyword,
          'type': 'user',
          'pCursor': '$page',
          'quickViewId': 'up-list',
          'reqID': '1',
          'ajaxpipe': '1',
        }),
        headers: AcfunApi.searchHeaders,
        timeout: _searchTimeout,
        cancel: cancel,
      ),
    );
    return AcfunApi.searchPage(response.text, page: page, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  Future<LiveRoom> _info(String roomId) async {
    final id = _authorId(roomId);
    final response = await _get(Uri.https('live.acfun.cn', '/api/live/info', {'authorId': id}));
    return AcfunApi.roomDetail(response.text, authorId: id, status: response.status);
  }

  /// [room] with its broadcast when it is live (3.x asked `startPlay` on
  /// room entry and before recording); a broadcast that ended in between
  /// is `StreamUnavailable` (3.x failed the load too).
  Future<LiveRoom> _withBroadcast(LiveRoom room, {required bool danmaku}) async {
    if (!room.isLiveNow) return room;
    final play = await _startPlay(room.roomId);
    return room.copyWith(data: play.data, danmakuData: danmaku ? _danmakuArgs(room.roomId, play) : null);
  }

  /// The room with its broadcast (the stream data) and danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      await _withBroadcast(await _info(roomId), danmaku: true);

  /// Follow-card refresh: `live/info` only, never a visitor session.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _info(roomId);

  /// The room with its broadcast, as 3.x's recorder read it.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) async =>
      await _withBroadcast(await _info(roomId), danmaku: false);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _info(roomId)).isLiveNow;

  // Visitor session -------------------------------------------------------------

  /// The visitor session, reused for five minutes; concurrent callers share
  /// one login. [fresh] logs in again (a new device id).
  Future<AcfunVisitor> _session({bool fresh = false}) {
    final cached = _visitor;
    if (!fresh && cached != null && _now().isBefore(cached.expiresAt)) return Future.value(cached.visitor);
    return _login ??= () async {
      try {
        final deviceId =
            'web_${List.generate(16, (_) => _deviceAlphabet[_random.nextInt(_deviceAlphabet.length)]).join()}';
        final response = await _send(
          LiveRequest.form(
            site: _site,
            url: Uri.https('id.app.acfun.cn', '/rest/app/visitor/login'),
            headers: {...AcfunApi.apiHeaders, 'cookie': '_did=$deviceId;'},
            fields: const {'sid': 'acfun.api.visitor'},
          ),
        );
        final visitor = AcfunApi.visitor(response.text, deviceId: deviceId, status: response.status);
        _visitor = (visitor: visitor, expiresAt: _now().add(_visitorLifetime));
        return visitor;
      } finally {
        _login = null;
      }
    }();
  }

  /// `startPlay` for [authorId]. A refused session is dropped and the
  /// request made once more with a new one (REG-ACFUN-003; 3.x dropped it
  /// only for the next request, so that attempt failed). An ended
  /// broadcast is `StreamUnavailable` and keeps the session.
  Future<_Play> _startPlay(String authorId, {bool freshSession = false}) async {
    for (var attempt = 0; ; attempt++) {
      final visitor = await _session(fresh: freshSession || attempt > 0);
      final response = await _send(
        LiveRequest.form(
          site: _site,
          url: Uri.https('api.kuaishouzt.com', '/rest/zt/live/web/startPlay', {
            'subBiz': 'mainApp',
            'kpn': 'ACFUN_APP',
            'kpf': 'PC_WEB',
            'userId': visitor.userId,
            'did': visitor.deviceId,
            'acfun.api.visitor_st': visitor.token,
          }),
          headers: AcfunApi.apiHeaders,
          fields: {'authorId': authorId, 'pullStreamType': 'FLV'},
        ),
      );
      try {
        final play = AcfunApi.startPlay(response.text, issuedAt: _now(), status: response.status);
        return (data: play.data, tickets: play.tickets, enterRoomAttach: play.enterRoomAttach, visitor: visitor);
      } on RiskControl {
        if (identical(_visitor?.visitor, visitor)) _visitor = null;
        if (attempt > 0) rethrow;
      }
    }
  }

  // Streams -------------------------------------------------------------------

  /// Qualities of the broadcast [detail] carries, best first (a live room
  /// without one, like a list card, asks `startPlay` first). A room the
  /// platform said is offline is `StreamUnavailable` without a request
  /// (3.x returned no qualities).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      AcfunApi.playQualities(await _broadcast(detail));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] from the broadcast [detail] carries (its URLs
  /// are signed for 30 days).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => AcfunApi.resolution(await _broadcast(detail), qualityId: quality.selectionId);

  /// Recovery asks `startPlay` again (3.x asked for the whole room again):
  /// a new broadcast has new URLs. The quality must still be offered; it is
  /// never swapped for another one.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => AcfunApi.resolution(await _broadcast(detail, fresh: true), qualityId: quality.selectionId);

  Future<AcfunRoomData> _broadcast(LiveRoom detail, {bool fresh = false}) async {
    if (detail.data case final AcfunRoomData data when !fresh) return data;
    if (!fresh && detail.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
    }
    return (await _startPlay(_authorId(detail.roomId))).data;
  }

  // Danmaku -------------------------------------------------------------------

  AcfunDanmakuArgs _danmakuArgs(String authorId, _Play play) => AcfunDanmakuArgs(
    authorId: authorId,
    liveId: play.data.liveId,
    visitor: play.visitor,
    tickets: play.tickets,
    enterRoomAttach: play.enterRoomAttach,
    refresh: () => danmakuArgs(authorId),
  );

  /// Danmaku arguments from a new visitor session and a new `startPlay`
  /// (tickets are per session; a broadcast that ended is
  /// `StreamUnavailable`).
  Future<AcfunDanmakuArgs> danmakuArgs(String authorId) async {
    final id = _authorId(authorId);
    return _danmakuArgs(id, await _startPlay(id, freshSession: true));
  }

  // Links ---------------------------------------------------------------------

  /// A live room page: `live.acfun.cn/live/{id}` (3.x's rule: exactly those
  /// two segments), or the mobile `m.acfun.cn/live/detail/{id}`. Profile
  /// pages (`www.acfun.cn/u/{id}`) are not rooms, as in 3.x.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !ShortLinkSession.isHttpUri(uri)) return null;
    final host = uri.host.toLowerCase();
    final segments = RoomPaths.segments(uri);
    final id = switch (segments) {
      ['live', final id] when host == 'live.acfun.cn' => id,
      ['live', 'detail', final id] when host == 'm.acfun.cn' => id,
      _ => null,
    };
    if (id == null) return null;
    final trimmed = id.trim();
    return RoomPaths.isRoomIdentifier(trimmed, _authorPattern) ? trimmed : null;
  }
}

/// One listing (a page size and filter): the cursors of the pages read so
/// far, the page that said "no more", and the pages being read.
final class _Listing {
  /// Cursors of pages 2 and on (page 1's is empty).
  final Map<int, String> cursors = {};
  final Map<int, Future<List<LiveRoom>>> pending = {};
  int? lastPage;

  String? cursorOf(int page) => page <= 1 ? '' : cursors[page];
}

/// One author search (a keyword and page size): the rows of the last server
/// page not served yet, the next pages, and the page being read.
final class _Search {
  /// A search whose next page is [page] of [size]: the page's first row is
  /// found assuming full server pages (a new search starts at page 1).
  new at(int page, int size)
    : nextPage = page,
      nextServerPage = (page - 1) * size ~/ AcfunApi.searchPageSize + 1,
      skip = (page - 1) * size % AcfunApi.searchPageSize;

  List<LiveRoom> remaining = const [];
  int nextPage;
  int nextServerPage;

  /// Rows of [nextServerPage] already served before this search started.
  int skip;
  bool finished = false;
  Future<List<LiveRoom>>? inFlight;
  int? inFlightPage;
  CancelToken? cancel;
}
