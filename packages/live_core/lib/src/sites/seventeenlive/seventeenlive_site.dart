import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/seventeenlive/seventeenlive_api.dart';
import 'package:live_net/live_net.dart';

const _site = '17live';

/// The 17LIVE (イチナナ) adapter (3.x's `SeventeenLiveSite`; parsing in
/// [SeventeenLiveApi]).
///
/// A room is the broadcaster's `liveStreamID`, kept as asked for (3.x's
/// identity). Anonymous, like 3.x: no cookie, no account; every request
/// carries 3.x's headers and follows no redirect. Requests are 3.x's:
/// - the catalog is one category of three regions, Japan, Taiwan and Hong
///   Kong, without a request (33-1; 3.x had none);
/// - the directory is the website's recommendation sections of a region
///   (Japan for the recommendations, as 3.x), one request a page by cursor
///   ([getDirectoryPageAtCursor]); by page number ([getDirectoryPage],
///   recommendations, area rooms) it replays from page 1;
/// - search is one `lives/<id>` for a room id or link, else one
///   `liveStreams/search` (current broadcasts only, one page);
/// - follow refreshes, the live state, room entry, recordings and recovery
///   are one `lives/<id>` each: the answer carries the pull URLs.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class SeventeenLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteCursorDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [preferH264] reads "优先 H.264" (on by default,
  /// 33-2 as 22-3) each time the qualities are listed: on, the H.264
  /// transcode comes first and is the default; off, 原画 does
  /// ([SeventeenLiveApi.playQualities]).
  new(this.http, {bool Function()? preferH264}) : _preferH264 = preferH264 ?? _on;

  /// Transport.
  final LiveHttp http;

  final bool Function() _preferH264;

  static bool _on() => true;

  @override
  String get id => _site;

  @override
  String get name => SeventeenLiveApi.displayName;

  /// 3.x's lasting note on what the directory and search cover.
  @override
  String get directoryNoticeKey => 'seventeen_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with [headers], redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, Map<String, String> headers, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: headers, followRedirects: false, cancel: cancel),
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

  static Uri _api(String path, [Map<String, String>? query]) => Uri.https(SeventeenLiveApi.apiHost, path, query);

  // Catalog -------------------------------------------------------------------

  /// The one category of three regions ([SeventeenLiveApi.category], 33-1)
  /// on page 1, none after; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 ? [SeventeenLiveApi.category] : const [];

  // Directory -----------------------------------------------------------------

  /// The sections page after [cursor] (null on page 1) of [category]'s
  /// region (Japan for null, the recommendations): one request (see
  /// [SeventeenLiveApi.sectionsQuery] and [SeventeenLiveApi.sectionsPage]).
  /// [page] is the caller's sequence: page 1 takes no cursor and later pages
  /// need one. Anything else, a cursor 3.x would not send, or an area that
  /// is not one of the regions ([SeventeenLiveApi.regionOf]) is a caller
  /// error (`ArgumentError`), refused before any request as in 3.x.
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
    final region = SeventeenLiveApi.regionOf(category);
    SeventeenLiveApi.checkCursor(cursor);
    final response = await _get(
      _api('/api/v1/sections', SeventeenLiveApi.sectionsQuery(cursor, regionCode: region)),
      SeventeenLiveApi.catalogHeaders,
      cancel: cancel,
    );
    final result = SeventeenLiveApi.sectionsPage(response.text, cursor: cursor, status: response.status);
    return LiveDirectoryPage(rooms: result.rooms, page: page, hasMore: result.hasMore, nextCursor: result.nextCursor);
  }

  /// Page [page] (1–20) of [category]'s region (Japan for null), replayed
  /// from page 1 by cursor (3.x: [page] requests); a directory that ends
  /// first gives an empty last page.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > SeventeenLiveApi.maxDirectoryPage) {
      throw RangeError.range(page, 1, SeventeenLiveApi.maxDirectoryPage, 'page');
    }
    SeventeenLiveApi.regionOf(category);
    String? cursor;
    for (var current = 1; ; current++) {
      final result = await getDirectoryPageAtCursor(page: current, cursor: cursor, category: category, cancel: cancel);
      if (current == page) return result;
      if (!result.hasMore) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
      cursor = result.nextCursor;
    }
  }

  /// The first [pageSize] rooms of directory page [page]
  /// ([getDirectoryPage]); [pageSize] is not sent, and one below 1 is a
  /// caller error (3.x refused it before any request).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    return List.unmodifiable((await getDirectoryPage(page: page)).rooms.take(pageSize));
  }

  /// As [getRecommendRooms], for [category]'s region (33-1).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    return List.unmodifiable((await getDirectoryPage(page: page, category: category)).rooms.take(pageSize));
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search, one page only:
  /// - a page other than 1 or a [pageSize] below 1 finds nothing;
  /// - a room link (see [roomIdFromUrl]; `www.17.live` too, 33-6) or a room
  ///   id finds that room, live or not (one `lives/<id>`; nothing when there
  ///   is no such room);
  /// - another web address (`<scheme>://…`, [SeventeenLiveApi.isUrl]) or a
  ///   blank keyword finds nothing;
  /// - anything else is one `liveStreams/search` of the keyword cut to 100
  ///   characters ([SeventeenLiveApi.searchKeyword]): current broadcasts,
  ///   the first [pageSize]. Unlike 3.x, a keyword with a colon (`Re:Zero`)
  ///   or over 100 characters is searched (33-5).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page != 1 || pageSize < 1) return const [];
    final text = keyword.trim();
    final roomId = roomIdFromUrl(text) ?? SeventeenLiveApi.normalizeRoomId(text);
    if (roomId != null) {
      try {
        return [await _refresh(roomId, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    final query = SeventeenLiveApi.searchKeyword(text);
    if (query.isEmpty || SeventeenLiveApi.isUrl(text)) return const [];
    final response = await _get(
      _api('/api/v1/liveStreams/search', {'query': query}),
      SeventeenLiveApi.catalogHeaders,
      cancel: cancel,
    );
    return List.unmodifiable(SeventeenLiveApi.searchRooms(response.text, status: response.status).take(pageSize));
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a room id; anything else is `NotFound` without a request
  /// (3.x refused it as an identity error).
  static String _checkedId(String roomId) =>
      SeventeenLiveApi.normalizeRoomId(roomId) ?? (throw NotFound(_site, 'not a room id: $roomId'));

  Future<LiveResponse> _lives(String roomId, {CancelToken? cancel}) =>
      _get(_api('/api/v1/lives/$roomId'), SeventeenLiveApi.requestHeaders(roomId), cancel: cancel);

  /// The refresh room of [roomId]: one `lives/<id>`, without streams.
  Future<LiveRoom> _refresh(String roomId, {CancelToken? cancel}) async {
    final id = _checkedId(roomId);
    final response = await _lives(id, cancel: cancel);
    return SeventeenLiveApi.refreshRoom(response.text, roomId: id, status: response.status);
  }

  /// Room entry: one `lives/<id>`, whose pull URLs become the qualities
  /// ([SeventeenLiveRoomData]), with the danmaku channel. A room that cannot
  /// be played (offline, locked, no pull URL, a state 3.x did not know) is
  /// entered; its stream says why.
  Future<LiveRoom> _entered(String roomId) async {
    final id = _checkedId(roomId);
    final response = await _lives(id);
    return SeventeenLiveApi.enteredRoom(response.text, roomId: id, status: response.status);
  }

  /// The room with its qualities (see [_entered]).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId);

  /// Follow-card refresh: one `lives/<id>`, as in 3.x; no streams.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _refresh(roomId);

  /// Room entry's answer (the qualities included), as 3.x's recorder asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  /// Whether the refresh detail says live; a failed request is an error,
  /// never "offline", and so is a state 3.x did not know (`ApiChanged`).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId);
    if (room.isLiveStatusPending) throw ApiChanged(_site, 'lives/$roomId: unknown state');
    return room.isLiveNow;
  }

  // Streams -------------------------------------------------------------------

  /// The qualities (see [SeventeenLiveApi.qualities]) from the data room
  /// entry brought, in the order "优先 H.264" asks for
  /// ([SeventeenLiveApi.playQualities], read now): no request. A room
  /// without it (a list card, a refreshed follow) is entered first; one the
  /// platform called offline has no stream (`StreamUnavailable`, without a
  /// request). A room that cannot be played says why (a locked live names
  /// its lock).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      SeventeenLiveApi.playQualities(await _stream(detail, fresh: false), preferH264: _preferH264());

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] (3.x's `standard` id is 原画): one per CDN in
  /// the answer's order, https, with the media headers.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => SeventeenLiveApi.resolution(await _stream(detail, fresh: false), quality);

  /// Room entry again (3.x: the answer names the CDN that serves now). A
  /// room entry already found unplayable is reported without a request, as
  /// 3.x did; a quality the broadcast no longer offers is
  /// `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => SeventeenLiveApi.resolution(await _stream(detail, fresh: true), quality);

  Future<SeventeenLiveRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a 17LIVE room');
    if (detail.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
    }
    if (detail.data case final SeventeenLiveRoomData data
        when data.roomId == detail.roomId && data.userId == detail.userId) {
      if (data.qualities.isEmpty || !fresh) return data;
    }
    return (await _entered(detail.roomId)).data! as SeventeenLiveRoomData;
  }

  // Links ---------------------------------------------------------------------

  /// A live or profile page (see [SeventeenLiveApi.roomIdFromUrl]), without
  /// a request. 17LIVE has no short links.
  @override
  String? roomIdFromUrl(String url) => SeventeenLiveApi.roomIdFromUrl(url);
}
