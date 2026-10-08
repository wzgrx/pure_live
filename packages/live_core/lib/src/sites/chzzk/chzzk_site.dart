import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/chzzk/chzzk_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'chzzk';

/// The qualities read for a room's playback data, until their lines are due
/// for renewal (held weakly: they go with the room).
final Expando<List<LivePlayQuality>> _fetched = Expando('chzzk qualities');

/// The CHZZK (치지직) adapter (3.x's `ChzzkSite`; parsing in [ChzzkApi]).
///
/// A room is a channel, its id the 32-hex `channelId`, as 3.x stored it.
/// Anonymous, like 3.x: no cookie, no account; every request carries
/// [ChzzkApi.headers] and follows no redirect. Requests:
/// - the catalog is the platform's areas (20-1), up to four
///   `categories/live` pages one after another;
/// - a directory page is one request by cursor ([getDirectoryPageAtCursor]):
///   `/service/v1/lives` for recommendations and 3.x's popular area, an
///   area's `/service/v2/categories/<type>/<id>/lives` otherwise; by page
///   number ([getDirectoryPage], recommendations and areas) it replays from
///   page 1, within 20 seconds;
/// - search is `/service/v1/search/channels`, one request a page;
/// - follow refreshes, the live state, room entry and recordings read the
///   channel and its `v3.1 live-detail` (two requests; 20-9: 3.x also read
///   both masters on entry);
/// - the qualities read the live's HLS masters (two requests, together),
///   which also serve its URLs; recovery reads all four again.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class ChzzkSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveSiteCursorDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveQualityDiscovery,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [now] (when masters were issued, and whether
  /// their lines are due) and `directoryDeadline` (3.x's 20 seconds for a
  /// page-number replay) are injectable for tests.
  new(this.http, {DateTime Function()? now, this._directoryDeadline = const Duration(seconds: 20)})
    : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  final Duration _directoryDeadline;

  @override
  String get id => _site;

  @override
  String get name => ChzzkApi.categoryName;

  /// The lasting note on what the directory covers (3.x's key; its text is
  /// [ChzzkApi.directoryScope], 20-6).
  @override
  String get directoryNoticeKey => 'chzzk_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: ChzzkApi.headers, followRedirects: false, cancel: cancel),
      );
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  static Uri _api(String path, [Map<String, String>? query]) => Uri.https(ChzzkApi.apiHost, path, query);

  // Catalog and directory -----------------------------------------------------

  /// The platform's areas by `categoryType` (20-1, see
  /// [ChzzkApi.categories]) on page 1; later pages are empty without a
  /// request. Up to [ChzzkApi.maxCategoryPages] `categories/live` pages,
  /// each after the previous one's `next`; the first failing fails the
  /// catalog, a later one ends it with the areas read so far.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final pages = <List<LiveArea>>[];
    Map<String, String>? next = const {};
    for (var index = 0; index < ChzzkApi.maxCategoryPages && next != null; index++) {
      final ChzzkCategoryPage result;
      try {
        final response = await _get(_api('/service/v1/categories/live', ChzzkApi.categoriesQuery(next)));
        result = ChzzkApi.categoryPage(response.text, status: response.status);
      } on SiteError {
        if (index == 0) rethrow;
        break;
      }
      pages.add(result.areas);
      next = result.next;
    }
    return ChzzkApi.categories(pages);
  }

  /// The page after [cursor] (null on page 1) of [category]'s lives: one
  /// request (see [ChzzkApi.livesUrl] and [ChzzkApi.lives]). Null or 3.x's
  /// popular area is the site-wide list. [page] is the caller's sequence:
  /// page 1 takes no cursor and later pages need one. Anything else, or a
  /// cursor this adapter did not make, is a caller error (`ArgumentError`),
  /// refused before any request as in 3.x.
  @override
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if ((page == 1) != (cursor == null)) {
      throw ArgumentError.value(cursor, 'cursor', page == 1 ? 'page 1 takes no cursor' : 'page $page needs a cursor');
    }
    final response = await _get(ChzzkApi.livesUrl(category, cursor), cancel: cancel);
    final result = ChzzkApi.lives(response.text, cursor: cursor, status: response.status);
    return LiveDirectoryPage(rooms: result.rooms, page: page, hasMore: result.hasMore, nextCursor: result.nextCursor);
  }

  /// Page [page] (1–20) of [category]'s lives (null: the site-wide list),
  /// replayed from page 1 by cursor (3.x: [page] requests); a list that ends
  /// first gives an empty last page. A channel already on an earlier page of
  /// the replay is left out (viewer counts move rows between requests). The
  /// replay has [ChzzkSite.new]'s deadline (20 seconds), after which its
  /// requests are cancelled and it is a `NetworkFailure`.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > ChzzkApi.maxDirectoryPage) {
      throw RangeError.range(page, 1, ChzzkApi.maxDirectoryPage, 'page');
    }
    ChzzkApi.checkArea(category);
    final owned = CancelToken();
    if (cancel != null) {
      if (cancel.isCancelled) owned.cancel();
      unawaited(cancel.whenCancelled.then((_) => owned.cancel()));
    }
    Future<LiveDirectoryPage> replay() async {
      String? cursor;
      final shown = <String>{};
      for (var current = 1; ; current++) {
        final result = await getDirectoryPageAtCursor(page: current, cursor: cursor, category: category, cancel: owned);
        if (current == page) {
          return LiveDirectoryPage(
            rooms: result.rooms.where((room) => !shown.contains(room.roomId)),
            page: page,
            hasMore: result.hasMore,
            nextCursor: result.nextCursor,
          );
        }
        if (!result.hasMore) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
        shown.addAll(result.rooms.map((room) => room.roomId));
        cursor = result.nextCursor;
      }
    }

    try {
      return await replay().timeout(
        _directoryDeadline,
        onTimeout: () => throw NetworkFailure(_site, 'directory page $page: over $_directoryDeadline'),
      );
    } finally {
      owned.cancel();
    }
  }

  /// Page [page] of the site-wide popular lives ([getDirectoryPage]);
  /// [pageSize] is not sent (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page)).rooms;

  /// As [getRecommendRooms], for [category] (an area of the catalog, or
  /// 3.x's popular area).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page, category: category)).rooms;

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Channels matching [keyword], live and offline (see
  /// [ChzzkApi.searchRooms]), [ChzzkApi.searchPageSize] a page from offset
  /// `(page - 1) * 20` whatever [pageSize] says (20-5; 3.x's search page
  /// asked 20 too). The keyword is cut to 100 characters
  /// ([ChzzkApi.searchKeyword]; 20-5, 3.x refused a longer one). A page
  /// below 1 or a blank keyword finds nothing, without a request (3.x); an
  /// offset over 1000000 is a caller error (`RangeError`, no request), as
  /// 3.x refused it.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1) return const [];
    final text = ChzzkApi.searchKeyword(keyword);
    if (text.isEmpty) return const [];
    final offset = (page - 1) * ChzzkApi.searchPageSize;
    if (offset > ChzzkApi.maxSearchOffset) throw RangeError.range(offset, 0, ChzzkApi.maxSearchOffset, 'offset');
    final response = await _get(
      _api('/service/v1/search/channels', {'keyword': text, 'offset': '$offset', 'size': '${ChzzkApi.searchPageSize}'}),
      cancel: cancel,
    );
    return ChzzkApi.searchRooms(response.text, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel and its latest live (two requests); an id that is not a
  /// channel id (32 lower-case hex digits, as 3.x checked) is `NotFound`
  /// without a request.
  Future<({ChzzkChannel owner, ChzzkLive? live})> _read(String roomId, {CancelToken? cancel}) async {
    final id = roomId.trim();
    if (!ChzzkApi.isChannelId(id)) throw NotFound(_site, 'not a channel id: $id');
    final channel = await _get(_api('/service/v1/channels/$id'), cancel: cancel);
    final owner = ChzzkApi.channel(channel.text, channelId: id, status: channel.status);
    final live = await _get(_api('/service/v3.1/channels/$id/live-detail'), cancel: cancel);
    return (owner: owner, live: ChzzkApi.liveDetail(live.text, owner: owner, status: live.status));
  }

  /// Room entry: the channel and its live (two requests), with the live's
  /// masters or why it cannot play ([ChzzkRoomData]); the masters are read
  /// with the qualities (20-9: entry is quicker, and a failing master no
  /// longer hides the room). [strict] (recordings) throws unreadable
  /// playback data at once.
  Future<LiveRoom> _entered(String roomId, {bool withDanmaku = false, bool strict = false, CancelToken? cancel}) async {
    final (:owner, :live) = await _read(roomId, cancel: cancel);
    if (strict) {
      if (live?.mediaError case final error?) throw error;
    }
    final room = ChzzkApi.room(owner, live);
    final chat = live != null && live.isLive ? live.chatChannelId : null;
    return room.copyWith(
      data: ChzzkApi.roomData(owner.id, live),
      danmakuData: withDanmaku && chat != null ? ChzzkDanmakuArgs(channelId: owner.id, chatChannelId: chat) : null,
    );
  }

  /// The room with its playback data and the live's chat.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId, withDanmaku: true);

  /// Follow-card refresh: the channel and its live, two requests as in 3.x.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async {
    final (:owner, :live) = await _read(roomId);
    return ChzzkApi.room(owner, live);
  }

  /// Room entry's answer, the masters to read included, as 3.x's recorder
  /// asked; unreadable playback data is `ApiChanged` here already. The
  /// live's chat comes along (multi-view connects it; E05.4).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) =>
      _entered(roomId, withDanmaku: true, strict: true);

  /// Whether the refresh detail says live (the live, not the channel:
  /// 20-7); a failed request is an error, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) =>
      discoverPlayQualitiesRaw(detail: detail);

  /// 3.x's qualities (see [ChzzkApi.qualities]) of the masters room entry
  /// kept: both read together (20-9; 3.x read them on entry), each quality
  /// holding its lines. A master that fails only loses its lines; when both
  /// fail, the first failure is thrown. The answer serves [getPlayUrls] and
  /// [resolvePlayUrlsRaw] of the same room until a line is due for renewal.
  /// A room without playback data (a list card, a refreshed follow) is
  /// entered first; one the platform called offline has no stream
  /// (`StreamUnavailable`, without a request). A live that cannot be played
  /// says why without a request (see [ChzzkApi.unavailable]). [cancel]
  /// reaches the requests.
  @override
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel}) =>
      _qualities(detail, fresh: false, cancel: cancel);

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality]: `HLS` then `LLHLS`, with the media headers and
  /// their leases; from the qualities just read, else as they are read.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => ChzzkApi.resolution(await _qualities(detail, fresh: false), quality);

  /// Room entry and the masters again (3.x's four requests): the masters
  /// carry tokens. A quality the live no longer offers is
  /// `StreamUnavailable`; the old lines are never reused, and the new ones
  /// serve the room's later requests.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => ChzzkApi.resolution(await _qualities(detail, fresh: true), quality);

  /// The qualities of [detail]: those read for its playback data while no
  /// line is due; else its masters, while their tokens hold; else (and
  /// always when [fresh]) room entry and its masters.
  Future<List<LivePlayQuality>> _qualities(LiveRoom detail, {required bool fresh, CancelToken? cancel}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a CHZZK room');
    _checkCancelled(cancel);
    final held = switch (detail.data) {
      final ChzzkRoomData data when data.channelId == detail.roomId => data,
      _ => null,
    };
    if (!fresh) {
      if (held != null) {
        final now = _now();
        if (_fetched[held] case final qualities? when ChzzkApi.linesFresh(qualities, now)) return qualities;
        if (ChzzkApi.mastersFresh(held.media, now)) return await _fetchQualities(held, cancel);
      } else if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
      }
    }
    final entered = (await _entered(detail.roomId, cancel: cancel)).data! as ChzzkRoomData;
    final qualities = await _fetchQualities(entered, cancel);
    if (held != null) _fetched[held] = qualities;
    return qualities;
  }

  /// The qualities of [data]'s masters, read together; kept with [data].
  Future<List<LivePlayQuality>> _fetchQualities(ChzzkRoomData data, CancelToken? cancel) async {
    if (data.media.isEmpty) throw data.unavailable ?? const StreamUnavailable(_site, 'no playback');
    final issuedAt = _now();
    final answers = await Future.wait([for (final media in data.media) _master(media, cancel)]);
    final bodies = [
      for (final answer in answers)
        if (answer.body case final body?) (media: answer.media, body: body),
    ];
    if (bodies.isEmpty) throw answers.first.error!;
    final qualities = ChzzkApi.qualities(bodies, issuedAt: issuedAt);
    _fetched[data] = qualities;
    return qualities;
  }

  /// One master's text, or why it failed (a cancellation is thrown).
  Future<({ChzzkMedia media, String? body, SiteError? error})> _master(ChzzkMedia media, CancelToken? cancel) async {
    try {
      final response = await _get(media.url, cancel: cancel);
      final body = ChzzkApi.master(response.text, what: '${media.id} master', status: response.status);
      return (media: media, body: body, error: null);
    } on SiteError catch (error) {
      return (media: media, body: null, error: error);
    }
  }

  // Links ---------------------------------------------------------------------

  /// A live page `https://chzzk.naver.com/live/<id>` or a channel page
  /// `https://chzzk.naver.com/<id>` (20-4; see [ChzzkApi.roomIdFromUrl]),
  /// without a request. CHZZK has no short links.
  @override
  String? roomIdFromUrl(String url) => ChzzkApi.roomIdFromUrl(url);
}
