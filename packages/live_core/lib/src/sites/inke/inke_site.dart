import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/inke/inke_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'inke';

/// The Inke (映客) adapter (3.x's `InkeSite`; parsing in [InkeApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no danmaku (3.x's Inke
/// had `EmptyDanmaku`). The requests are 3.x's, with 3.x's headers:
/// - the catalog and channel pages are `web/Live_channel_pc`, the
///   recommendations `web/Live_top_pc` (one page each, sliced for callers
///   that page);
/// - a nickname search filters those two showcases; a uid or room link
///   finds that room;
/// - room entry, follow refreshes and recordings read `web/live_share_pc`
///   (one request);
/// - streams: the app's `api/live/now_publish` (one request, a freshly
///   signed URL each time). 3.x looked for the broadcast in the website
///   showcases instead and could not play anything outside them
///   (REG-INKE-001); that lookup stays as the fallback.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class InkeSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LiveCancellableSearch,
        LiveSearchPaginationPolicy {
  /// Creates the adapter; [now] (when a pull URL was received, for its
  /// lease) is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '映客';

  /// 3.x's text key for the directory's scope note (showcases, not a full
  /// list).
  @override
  String get directoryNoticeKey => 'inke_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: InkeApi.headers, followRedirects: false, cancel: cancel),
      );
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
  }

  static Uri _web(String path, [Map<String, String>? query]) =>
      Uri.parse('${InkeApi.webApi}/$path').replace(queryParameters: query);

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  // Catalog and directory -----------------------------------------------------

  /// The one category 映客 with the website's channels as areas (see
  /// [InkeApi.categories]); later pages are empty, without a request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _get(_web('Live_channel_pc'));
    return InkeApi.categories(response.text, status: response.status);
  }

  /// The showcase of [category], or the top list when it is null: one page
  /// (3.x). Page 2 and later are empty, without a request. A page below 1
  /// or an area that is not an Inke channel is a caller error, without a
  /// request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (category != null &&
        (category.platform.trim().toLowerCase() != _site || category.areaType != InkeApi.areaType)) {
      throw ArgumentError.value(category, 'category', 'not an Inke channel');
    }
    _checkCancelled(cancel);
    if (page > 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    if (category == null) {
      final response = await _get(_web('Live_top_pc'), cancel: cancel);
      return InkeApi.topPage(response.text, status: response.status);
    }
    final response = await _get(_web('Live_channel_pc'), cancel: cancel);
    return InkeApi.channelPage(response.text, tabKey: category.areaId, status: response.status);
  }

  /// Slice [page] of [pageSize] of the top list (3.x's `_slice`: the one
  /// page is requested for every slice).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => _slice(page, pageSize);

  /// As [getRecommendRooms], for [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _slice(page, pageSize, category: category);

  Future<List<LiveRoom>> _slice(int page, int pageSize, {LiveArea? category}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    final rooms = (await getDirectoryPage(category: category)).rooms;
    // Checked before multiplying, so huge pages never overflow (3.x).
    if (page - 1 > rooms.length ~/ pageSize) return const [];
    final start = (page - 1) * pageSize;
    if (start >= rooms.length) return const [];
    return rooms.sublist(start, (start + pageSize).clamp(start, rooms.length));
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Rooms for [keyword] (3.x's rules):
  /// - a page or [pageSize] below 1 is a caller error, without a request;
  /// - a uid or Inke room link finds that room on page 1 only (an offline
  ///   one named `UID <uid>`: the answer has no profile), or nothing when
  ///   the site answers 404;
  /// - another link (a URL with a scheme and host) or a blank keyword finds
  ///   nothing, without a request;
  /// - anything else filters the nicknames of the top list and the channels
  ///   (see [InkeApi.searchShowcases]). A page over 10000, a [pageSize] over
  ///   60 or a keyword over 100 characters is refused without a request, as
  ///   3.x refused them.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    final input = keyword.trim();
    final uid = _exactRoom(input);
    if (uid != null) {
      if (page != 1) return const [];
      try {
        final room = await _detail(uid, cancel: cancel);
        return [if (room.isExplicitlyOfflineNow) room.copyWith(title: 'UID $uid', nick: 'UID $uid') else room];
      } on NotFound {
        return const [];
      }
    }
    if (_isLink(input)) return const [];
    if (page > 10000) throw RangeError.range(page, 1, 10000, 'page');
    if (pageSize > 60) throw RangeError.range(pageSize, 1, 60, 'pageSize');
    if (input.toLowerCase().length > 100) throw ArgumentError.value(keyword, 'keyword', 'over 100 characters');
    if (input.isEmpty) return const [];
    final top = await _get(_web('Live_top_pc'), cancel: cancel);
    final showcase = InkeApi.topPage(top.text, status: top.status).rooms;
    final channels = await _get(_web('Live_channel_pc'), cancel: cancel);
    return InkeApi.searchShowcases(
      input,
      [...showcase, ...InkeApi.channelRooms(channels.text, status: channels.status)],
      page: page,
      pageSize: pageSize,
    );
  }

  /// A uid or room link is one exact answer, never pages; so is a link that
  /// is not a room.
  @override
  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _exactRoom(input) == null && !_isLink(input);
  }

  /// The room [input] names exactly: a uid, or a room link.
  static String? _exactRoom(String input) =>
      InkeApi.idPattern.hasMatch(input) ? input : InkeApi.roomIdFromUri(Uri.tryParse(input));

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// took any text with a scheme for one, so keywords such as `Re:Zero`
  /// found nothing.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// `live_share_pc` as the room [roomId] (see [InkeApi.detail]); an id that
  /// is not a uid is `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {CancelToken? cancel}) async {
    final uid = roomId.trim();
    if (!InkeApi.idPattern.hasMatch(uid)) throw NotFound(_site, 'not a uid: $uid');
    final response = await _get(_web('live_share_pc', {'uid': uid}), cancel: cancel);
    return InkeApi.detail(response.text, uid: uid, status: response.status);
  }

  /// The room: one request. 3.x also looked for the pull URL here and failed
  /// the whole room when the showcases did not hold it; the stream is now
  /// resolved when played ([resolvePlayUrlsRaw]).
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

  /// Whether the detail says live; a failed request is an error, never
  /// "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's one quality, FLV ([InkeApi.flv]), without a request. A room the
  /// platform called offline is `StreamUnavailable` (3.x returned no
  /// qualities); whether a live or pending room plays is settled when its
  /// lines are resolved.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is not live');
    return const [InkeApi.flv];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The Wangsu FLV line of the room's current broadcast, freshly signed,
  /// with the media headers and its lease (see [_pullUrls]). A room the
  /// platform called offline, or a quality other than [InkeApi.flv], is
  /// `StreamUnavailable` without a request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is not live');
    return await _resolve(detail, quality);
  }

  /// A freshly signed line, as [resolvePlayUrlsRaw], whatever the room's
  /// last known state (3.x read the room again).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality);

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality) async {
    if ('${quality.selectionId}' != '${InkeApi.flv.selectionId}') {
      throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    }
    final uid = detail.roomId.trim();
    if (!InkeApi.idPattern.hasMatch(uid)) throw NotFound(_site, 'not a uid: $uid');
    final data = detail.data;
    final urls = await _pullUrls(uid, knownLiveId: data is InkeRoomData ? data.liveId : null);
    return InkeApi.resolution(urls, issuedAt: _now());
  }

  /// The pull URLs of [uid]'s current broadcast:
  /// 1. `now_publish`: its Wangsu URL. When the app says the anchor is not
  ///    live, that is `StreamUnavailable` and nothing else is asked.
  /// 2. When the app answered no Wangsu URL, or failed, 3.x's lookup: the
  ///    showcases in [InkeApi.showcasePaths] order, for the broadcast the
  ///    app named or else [knownLiveId] (the room entry's), until one holds
  ///    it. The app's failure is reported when none does; without either
  ///    broadcast id it is reported at once.
  Future<List<String>> _pullUrls(String uid, {String? knownLiveId}) async {
    String? liveId;
    SiteError? appFailure;
    try {
      final response = await _get(Uri.parse('${InkeApi.appApi}/now_publish').replace(queryParameters: {'id': uid}));
      final broadcast = InkeApi.broadcast(response.text, uid: uid, status: response.status);
      if (broadcast == null) throw StreamUnavailable(_site, '$uid is not live');
      if (broadcast.pullUrl case final url?) return [url];
      liveId = broadcast.liveId;
    } on StreamUnavailable {
      rethrow;
    } on SiteError catch (error) {
      appFailure = error;
      liveId = knownLiveId;
    }
    if (liveId == null) throw appFailure ?? StreamUnavailable(_site, '$uid: no pull URL');
    for (final path in InkeApi.showcasePaths) {
      final response = await _get(_web(path));
      final urls = InkeApi.showcaseUrls(response.text, path: path, uid: uid, liveId: liveId, status: response.status);
      if (urls.isNotEmpty) return urls;
    }
    throw appFailure ?? StreamUnavailable(_site, '$uid: no pull URL for broadcast $liveId');
  }

  // Links ---------------------------------------------------------------------

  /// The uid of an Inke room or app share link (see
  /// [InkeApi.roomIdFromUri]). The site has no short links.
  @override
  String? roomIdFromUrl(String url) => InkeApi.roomIdFromUri(Uri.tryParse(url.trim()));
}
