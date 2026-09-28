import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/weibo/weibo_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'weibo';

/// The Weibo Live (微博直播) adapter (3.x's `WeiboSite`; parsing in
/// [WeiboApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no danmaku (3.x's Weibo
/// had `EmptyDanmaku`). The requests are 3.x's, with 3.x's headers:
/// - the catalog is one category with one area, without a request;
/// - the recommendations (and that area) are the snapshot
///   `pc_recommend/list.json?count=10` (one page; page 2 and later are empty
///   without a request, and callers' page sizes are not applied, as in 3.x);
/// - a nickname search filters that snapshot; a broadcast id or room link
///   finds that room;
/// - room entry, follow refreshes and recordings read
///   `room/show_pc_live.json` (one request);
/// - every playback, recovery and recording reads that detail again (one
///   request) and plays its FLV; there is no signed URL to reuse.
///
/// A room is one broadcast, not the anchor (see [WeiboApi]). Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class WeiboSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => WeiboApi.siteName;

  /// 3.x's text key for the directory's scope note (an official snapshot
  /// without states or audience, not a full-site search).
  @override
  String get directoryNoticeKey => 'weibo_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: WeiboApi.headers, followRedirects: false, cancel: cancel),
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

  /// 3.x's bounds, checked before any request: a page from 1, a page size
  /// from 1 to 1000.
  static void _checkPage(int page, [int pageSize = 30]) {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pageSize < 1 || pageSize > 1000) throw RangeError.range(pageSize, 1, 1000, 'pageSize');
  }

  // Catalog and directory -----------------------------------------------------

  /// The one category 微博直播 with its one area 公开推荐, the snapshot (3.x);
  /// later pages are empty. No request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    _checkPage(page, pageSize);
    return page == 1 ? WeiboApi.categories() : const [];
  }

  /// The snapshot, for the recommendations and the one area alike: one page
  /// (3.x). Page 2 and later are empty, without a request. A page below 1
  /// or another area is a caller error, without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    _checkPage(page);
    if (category != null && !WeiboApi.isArea(category)) {
      throw ArgumentError.value(category, 'category', 'not the Weibo recommendation area');
    }
    if (page > 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final response = await _get(WeiboApi.recommendUrl, cancel: cancel);
    return WeiboApi.recommendations(response.text, status: response.status);
  }

  /// Page [page] of the snapshot, whole: 3.x checked [pageSize] but did not
  /// apply it.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    _checkPage(page, pageSize);
    return (await getDirectoryPage(page: page)).rooms;
  }

  /// As [getRecommendRooms], for the one area.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkPage(page, pageSize);
    return (await getDirectoryPage(page: page, category: category)).rooms;
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Rooms for [keyword] (3.x's rules), on page 1 only (later pages are
  /// empty without a request):
  /// - a page or [pageSize] out of bounds is a caller error, without a
  ///   request;
  /// - a broadcast id or room link ([WeiboApi.exactRoom]) finds that room,
  ///   or nothing when the site says it does not exist;
  /// - another link (a URL with a scheme and host) or a blank keyword finds
  ///   nothing, without a request;
  /// - anything else filters the snapshot's nicknames
  ///   ([WeiboApi.searchSnapshot]).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    _checkPage(page, pageSize);
    if (page > 1) return const [];
    final exact = WeiboApi.exactRoom(keyword);
    if (exact != null) {
      try {
        return [await _detail(exact, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    final input = keyword.trim();
    if (input.isEmpty || _isLink(input)) return const [];
    final snapshot = await getDirectoryPage(cancel: cancel);
    return WeiboApi.searchSnapshot(input, snapshot.rooms, pageSize: pageSize);
  }

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// filtered the snapshot's nicknames with it, which never matched.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// `show_pc_live` as the room [roomId] (see [WeiboApi.detail]), of
  /// [ownerId] when given; an id that is no broadcast id is `NotFound`
  /// without a request.
  Future<LiveRoom> _detail(String roomId, {int? ownerId, CancelToken? cancel}) async {
    final liveId = roomId.trim();
    if (!WeiboApi.isLiveId(liveId)) throw NotFound(_site, 'not a broadcast id: $liveId');
    final response = await _get(WeiboApi.detailUrl(liveId), cancel: cancel);
    return WeiboApi.detail(response.text, liveId: liveId, ownerId: ownerId, status: response.status);
  }

  /// The room: one request (3.x).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same single request (3.x): state, title and pictures; `mergeFrom`
  /// keeps the rest.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The room the recorder starts from; its lines come from
  /// [resolvePlayUrlsRaw].
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the broadcast is live: true when live, false for a replay. A
  /// state 3.x did not know is no answer (3.x threw): a restricted
  /// broadcast is `NeedsLogin`, any other `StreamUnavailable` (see
  /// [WeiboApi.unplayable]).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _detail(roomId);
    if (room.isLiveNow) return true;
    if (room.isRecord) return false;
    final data = room.data;
    throw (data is WeiboRoomData ? WeiboApi.unplayable(data) : null) ??
        StreamUnavailable(_site, '${room.roomId}: state not known');
  }

  // Streams -------------------------------------------------------------------

  /// 3.x's one quality, 原始流 ([WeiboApi.original]), without a request,
  /// when the room's detail says it plays; otherwise its reason
  /// ([WeiboApi.unplayable]; 3.x returned no qualities for a replay).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    _checkPlayable(detail);
    return const [WeiboApi.original];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of the broadcast as the site answers now: the detail is read
  /// again (one request, 3.x), must still be the same anchor's and must
  /// play. A quality other than [WeiboApi.original], or a room whose known
  /// detail does not play, is refused without a request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality);

  /// As [resolvePlayUrlsRaw] (3.x read the detail again for every attempt).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality);

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality) async {
    if ('${quality.selectionId}' != '${WeiboApi.original.selectionId}') {
      throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    }
    _checkPlayable(detail);
    final known = detail.data;
    final owner = known is WeiboRoomData ? known.ownerId : int.tryParse(detail.userId?.trim() ?? '');
    final fresh = await _detail(detail.roomId, ownerId: owner != null && owner > 0 ? owner : null);
    final data = fresh.data! as WeiboRoomData;
    if (WeiboApi.unplayable(data) case final error?) throw error;
    return WeiboApi.resolution(data.mediaUrls);
  }

  /// Throws why [room] cannot play, from what its detail already says: its
  /// [WeiboRoomData], or without one (a list card, a stored follow) a
  /// replay or offline state.
  static void _checkPlayable(LiveRoom room) {
    final data = room.data;
    if (data is WeiboRoomData) {
      if (WeiboApi.unplayable(data) case final error?) throw error;
    } else if (room.isRecord || room.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '${room.roomId} is not live');
    }
  }

  // Links ---------------------------------------------------------------------

  /// The broadcast of a Weibo room link (see [WeiboApi.liveIdFromUrl]); a
  /// bare broadcast id is no link (it is found by search). The site's share
  /// short links (`t.cn`) were not followed by 3.x either.
  @override
  String? roomIdFromUrl(String url) => WeiboApi.liveIdFromUrl(url);
}
