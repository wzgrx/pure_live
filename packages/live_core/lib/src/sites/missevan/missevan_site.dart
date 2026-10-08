import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/missevan/missevan_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'missevan';

/// The Missevan (猫耳 FM) adapter (3.x's `MissevanSite`; parsing in
/// [MissevanApi]).
///
/// Anonymous, like 3.x: no cookie and no account. Every call is one request
/// to `fm.missevan.com/api/v2/`, as in 3.x:
/// - the catalog is `meta/data`, grouped by namespace (13-3);
/// - recommendations and areas are native pages of `chatroom/open/list`
///   ([getDirectoryPage]); an area is asked for by its namespace;
/// - search is `chatroom/search` (a long keyword cut to 100 characters,
///   13-4), or the room itself for a room number or link;
/// - room entry, follow refreshes and recordings read `live/{id}`, which
///   also holds the pull URLs, so playing asks nothing more; recovery reads
///   it again for freshly signed URLs. Room entry also hands over the
///   danmaku arguments ([MissevanDanmakuArgs], 13-2); the connection is the
///   danmaku module's (M5, `DanmakuRegistry` in `live_danmaku`).
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class MissevanSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveSiteDirectoryPager,
        LiveCancellableSearch,
        LiveSearchPaginationPolicy,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => '猫耳 FM';

  // Requests ------------------------------------------------------------------

  /// A GET of `api/v2/[path]` with 3.x's headers, redirects not followed (as
  /// 3.x). A cancellation before the request or while it runs is a
  /// cancelled `TransportFailure`, also when the answer (or a transport
  /// failure) arrived meanwhile; other transport failures are
  /// `NetworkFailure`.
  Future<LiveResponse> _get(String path, {Map<String, String> query = const {}, CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(
          site: _site,
          url: Uri.https('fm.missevan.com', '/api/v2/$path', query.isEmpty ? null : query),
          headers: MissevanApi.headers,
          followRedirects: false,
          cancel: cancel,
        ),
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

  // Catalog and directory -----------------------------------------------------

  /// The site's tabs as areas, grouped by namespace (see
  /// [MissevanApi.categories]); later pages are empty, without a request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _get('meta/data');
    return MissevanApi.categories(response.text, status: response.status);
  }

  /// Native page [page] of [category]'s rooms, or of the recommendations
  /// when it is null: every live room of the answer, and whether the site
  /// has another page. A page out of 1–10000 or an area that is not
  /// Missevan's is a caller error (`ArgumentError`), without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > 10000) throw RangeError.range(page, 1, 10000, 'page');
    final filter = category == null ? const <String, String>{} : MissevanApi.areaQuery(category);
    final response = await _get('chatroom/open/list', query: {'p': '$page', ...filter}, cancel: cancel);
    return MissevanApi.directoryPage(response.text, page: page, status: response.status);
  }

  /// The rooms of native page [page]; [pageSize] only has to be 1–100 (the
  /// site's pages are fixed), as in 3.x.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    _checkPageSize(pageSize);
    return (await getDirectoryPage(page: page)).rooms;
  }

  /// As [getRecommendRooms], for [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkPageSize(pageSize);
    return (await getDirectoryPage(page: page, category: category)).rooms;
  }

  static void _checkPageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) throw RangeError.range(pageSize, 1, 100, 'pageSize');
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Rooms for [keyword], live or not (3.x's rules):
  /// - nothing, without a request, for a blank keyword or [pageSize] below 1;
  /// - a room number or `fm.missevan.com/live/{id}` link finds that room on
  ///   page 1 only, or nothing when it does not exist;
  /// - another link (a URL with a scheme and host) finds nothing;
  /// - anything else is a `chatroom/search` keyword, [pageSize] a page. A
  ///   keyword over 100 characters is cut to its first 100
  ///   ([MissevanApi.searchKeyword], 13-4; 3.x refused it). A keyword with
  ///   control characters, a page out of 1–10000 or a [pageSize] over 100
  ///   is refused (`ArgumentError`, no request), as 3.x refused them.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (pageSize < 1) return const [];
    final input = keyword.trim();
    if (input.isEmpty) return const [];
    final roomId = _exactRoom(input);
    if (roomId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(roomId, media: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (_isLink(input)) return const [];
    final text = MissevanApi.searchKeyword(input);
    if (text == null) throw ArgumentError.value(keyword, 'keyword', 'not a Missevan keyword');
    if (page < 1 || page > 10000) throw RangeError.range(page, 1, 10000, 'page');
    if (pageSize > 100) throw RangeError.range(pageSize, 1, 100, 'pageSize');
    final response = await _get(
      'chatroom/search',
      query: {'s': text, 'p': '$page', 'page_size': '$pageSize'},
      cancel: cancel,
    );
    return MissevanApi.searchRooms(response.text, page: page, pageSize: pageSize, status: response.status);
  }

  /// A room number or room link is one exact answer, never pages; so is a
  /// link that is not a room.
  @override
  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _exactRoom(input) == null && !_isLink(input);
  }

  /// The room [input] names exactly: a room number, or a room link.
  static String? _exactRoom(String input) =>
      MissevanApi.idPattern.hasMatch(input) ? input : MissevanApi.roomIdFromUri(Uri.tryParse(input));

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// took any text with a scheme for one, so keywords such as `Re:Zero`
  /// found nothing.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// `live/{id}` as the room [roomId] (see [MissevanApi.detail]); an id
  /// that is not a room number is `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {bool media = true, bool withDanmaku = false, CancelToken? cancel}) async {
    final id = roomId.trim();
    if (!MissevanApi.idPattern.hasMatch(id)) throw NotFound(_site, 'not a room id: $id');
    final response = await _get('live/$id', cancel: cancel);
    return MissevanApi.detail(
      response.text,
      roomId: id,
      media: media,
      withDanmaku: withDanmaku,
      status: response.status,
    );
  }

  /// The room, with its pull URLs when live and the danmaku arguments
  /// ([MissevanDanmakuArgs], live or not; 13-2).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, withDanmaku: true);

  /// The same single request as room entry (3.x): the card gets state,
  /// title, heat, followers and, when live, the start time and no
  /// restriction; `mergeFrom` keeps the rest.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The room with the pull URLs the recorder starts from, and the danmaku
  /// arguments of the same answer (multi-view connects them; E05.4).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, withDanmaku: true);

  /// Whether the detail says live; a failed request is an error, never
  /// "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The one quality 原画 with its FLV and HLS lines (see
  /// [MissevanApi.qualities], 13-1), from the pull URLs the room detail
  /// brought: no request. A room the platform called offline is
  /// `StreamUnavailable` (3.x returned no qualities); a room without pull
  /// URLs (a list card, a pending state) reads its detail first.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (detail.data case final MissevanRoomData data when detail.isLiveNow) return _offered(detail, data);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is not live');
    final fresh = await _detail(detail.roomId);
    if (fresh.data case final MissevanRoomData data) return _offered(fresh, data);
    throw StreamUnavailable(_site, '${detail.roomId} is not live');
  }

  static List<LivePlayQuality> _offered(LiveRoom room, MissevanRoomData data) {
    final qualities = MissevanApi.qualities(data);
    if (qualities.isEmpty) throw StreamUnavailable(_site, '${room.roomId} has no pull URL');
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] among the room's qualities (by its id; 3.x's
  /// `hls` and `flv` name the one quality now, [MissevanApi.qualityIdFromLegacy]),
  /// with the media headers and their leases. A quality the room does not
  /// offer is `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final offered = await getPlayQualities(detail: detail);
    final wanted = MissevanApi.qualityIdFromLegacy('${quality.selectionId}');
    final same = offered.where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (same == null) throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    return MissevanApi.resolution(same);
  }

  /// The room read again: the pull URLs are signed and expire, and a room
  /// that went offline meanwhile is `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => await resolvePlayUrlsRaw(detail: await _detail(detail.roomId), quality: quality);

  /// A minute before [url]'s `expires` (3.x); null for a URL without one.
  @override
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) => MissevanApi.lease(url)?.refreshAt;

  /// [url]'s `expires`; null for a URL without one.
  @override
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => MissevanApi.lease(url)?.expiresAt;

  // Links ---------------------------------------------------------------------

  /// A room of `fm.missevan.com/live/{id}` (see [MissevanApi.roomIdFromUri]).
  /// The site has no short links.
  @override
  String? roomIdFromUrl(String url) => MissevanApi.roomIdFromUri(Uri.tryParse(url.trim()));
}
