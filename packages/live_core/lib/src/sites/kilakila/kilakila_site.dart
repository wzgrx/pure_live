import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kilakila/kilakila_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'kilakila';

/// The KilaKila (克拉克拉) adapter (3.x's `KilakilaSite`; parsing in
/// [KilakilaApi]).
///
/// A room is an anchor: its id is the anchor's uid, never the id of one
/// broadcast (REG-KILAKILA-001), so 3.x's follows keep matching. Anonymous,
/// like 3.x: no cookie, no account; every request carries
/// [KilakilaApi.headers] and follows no redirect. Requests are 3.x's:
/// - the catalog is two fixed timelines, without a request;
/// - recommendations and the timelines are `pcLive/timeline` pages
///   ([getDirectoryPage], ten a page);
/// - search is the website's user search page (one request, the anchors'
///   state unknown), or one profile request for a uid or anchor link;
/// - follow refreshes read the anchor's profile (`Tg/personalH5`) only;
/// - room entry and recordings read the profile, then the current
///   broadcast's `getRoomInfo`, which also holds the pull URLs; recovery
///   reads both again.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class KilakilaSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSearchPaginationPolicy,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (the pull URLs' issue time) is injectable
  /// for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => KilakilaApi.categoryName;

  /// 3.x's lasting note on what the directory covers (the two official
  /// timelines, not the whole site).
  @override
  String get directoryNoticeKey => 'kilakila_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: KilakilaApi.headers, followRedirects: false, cancel: cancel),
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

  static Uri _profileUrl(String uid) => Uri.https(KilakilaApi.ownerHost, '/Tg/personalH5', {'uid': uid});

  static Uri _roomInfoUrl(String broadcastId) =>
      Uri.https('live.kilakila.cn', '/LiveRoom/getRoomInfo', {'roomId': broadcastId});

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog (see [KilakilaApi.categories]) on page 1; later pages
  /// are empty. No request: the platform has no area API.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 ? KilakilaApi.categories() : const [];

  /// Native page [page] of [category]'s timeline, or of the hot timeline
  /// (the recommendations) when it is null; ten rows a page, as 3.x's
  /// directory pager asked. The page's end is the platform's `isLastPage`,
  /// not the number of rooms.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      _timeline(page: page, pageSize: KilakilaApi.pageSize, category: category, cancel: cancel);

  /// The hot timeline's page [page] of [pageSize] rows (sent, 1–100).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _timeline(page: page, pageSize: pageSize)).rooms;

  /// As [getRecommendRooms], for [category]'s timeline.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await _timeline(page: page, pageSize: pageSize, category: category)).rooms;

  /// A page out of 1–100000, a [pageSize] out of 1–100 or an area that is
  /// not a KilaKila timeline is a caller error (`ArgumentError`), refused
  /// before any request as in 3.x.
  Future<LiveDirectoryPage> _timeline({
    required int page,
    required int pageSize,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 || page > 100000) throw RangeError.range(page, 1, 100000, 'page');
    if (pageSize < 1 || pageSize > 100) throw RangeError.range(pageSize, 1, 100, 'pageSize');
    final type = KilakilaApi.timelineType(category);
    final response = await _get(
      Uri.https('live.kilakila.cn', '/pcLive/timeline', {
        'tag': '0',
        'type': '$type',
        'genderType': '0',
        'pageNo': '$page',
        'pageSize': '$pageSize',
      }),
      cancel: cancel,
    );
    return KilakilaApi.timelinePage(response.text, page: page, pageSize: pageSize, type: type, status: response.status);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Anchors for [keyword] (3.x's rules):
  /// - a page or [pageSize] below 1 is a caller error (`ArgumentError`);
  /// - a blank keyword finds nothing, without a request;
  /// - a uid or an anchor link finds that anchor on page 1 only (one
  ///   profile request): its current broadcast's room, else the anchor with
  ///   an unknown state; an unknown anchor finds nothing;
  /// - a broadcast link, another link (`scheme://host`) or a number with a
  ///   leading zero finds nothing, without a request;
  /// - anything else is a keyword of the website's user search, one page a
  ///   request; the anchors' state is unknown there, and no anchor is
  ///   looked up one by one. A keyword over 100 characters, a page over
  ///   10000 or a [pageSize] over 100 is refused (`ArgumentError`, no
  ///   request), as 3.x refused them; [pageSize] is not sent (the site's
  ///   pages are fixed).
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
    final link = _searchLink(input);
    if (link == null) {
      if (!supportsSearchPaginationFor(input)) return const [];
      if (!KilakilaApi.isSearchable(input)) throw ArgumentError.value(keyword, 'keyword', 'not a KilaKila keyword');
      if (page > 10000) throw RangeError.range(page, 1, 10000, 'page');
      if (pageSize > 100) throw RangeError.range(pageSize, 1, 100, 'pageSize');
      final response = await _get(KilakilaApi.searchUrl(input, page), cancel: cancel);
      return KilakilaApi.searchPage(response.text, status: response.status);
    }
    if (link.kind != KilakilaLinkKind.owner || page > 1) return const [];
    try {
      final profile = await _profile(link.id, cancel: cancel);
      final current = profile.current;
      return [if (current != null) KilakilaApi.room(current) else KilakilaApi.profileRoom(profile)];
    } on NotFound {
      return const [];
    }
  }

  /// A keyword is paged; a uid, a link or a number is one exact answer.
  @override
  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _searchLink(input) == null && !RegExp(r'^[0-9]+$').hasMatch(input) && !_isLink(input);
  }

  /// The anchor or broadcast [input] names exactly: a uid, or a link.
  static KilakilaLink? _searchLink(String input) =>
      KilakilaApi.isId(input) ? KilakilaLink(KilakilaLinkKind.owner, input) : KilakilaLink.parse(input);

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// took any text with a scheme for one, so keywords such as `Re:Zero`
  /// found nothing.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// The profile of the anchor [uid]; an id that is not a uid is `NotFound`
  /// without a request.
  Future<KilakilaProfile> _profile(String uid, {CancelToken? cancel}) async {
    final id = uid.trim();
    if (!KilakilaApi.isId(id)) throw NotFound(_site, 'not a uid: $id');
    final response = await _get(_profileUrl(id), cancel: cancel);
    return KilakilaApi.profile(response.text, uid: id, status: response.status);
  }

  /// Room entry (3.x's `_detail` with playback): the profile, then the
  /// current broadcast's `getRoomInfo` (which must be this anchor's) with
  /// the pull URLs in [KilakilaRoomData]. An anchor without a current
  /// broadcast is its profile with an unknown state (one request). A
  /// broadcast that ended between the two requests (`getRoomInfo` says
  /// unknown or a historical replay) cannot be played: `StreamUnavailable`,
  /// as 3.x failed here too. A paid or not live broadcast is still entered;
  /// its stream says why it cannot play.
  Future<LiveRoom> _entered(String uid, {bool withDanmaku = false}) async {
    final profile = await _profile(uid);
    final current = profile.current;
    if (current == null) {
      return KilakilaApi.profileDetail(profile).copyWith(data: KilakilaRoomData(issuedAt: _now()));
    }
    final KilakilaBroadcast broadcast;
    try {
      final response = await _get(_roomInfoUrl(current.broadcastId));
      broadcast = KilakilaApi.roomInfo(
        response.text,
        broadcastId: current.broadcastId,
        uid: profile.uid,
        status: response.status,
      );
    } on NotFound catch (error) {
      throw StreamUnavailable(_site, 'the current broadcast is gone (${error.detail})');
    }
    return KilakilaApi.withProfile(KilakilaApi.room(broadcast), profile).copyWith(
      data: KilakilaRoomData(issuedAt: _now(), broadcast: broadcast),
      danmakuData: withDanmaku ? KilakilaDanmakuArgs(roomId: broadcast.broadcastId) : null,
    );
  }

  /// The room with its stream data and the danmaku room.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId, withDanmaku: true);

  /// Follow-card refresh: the profile only, one request as in 3.x; the
  /// current broadcast's card gives state, title and cover. No stream data.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async =>
      KilakilaApi.profileDetail(await _profile(roomId));

  /// Room entry's answer (the stream data included), as 3.x's recorder
  /// asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  /// Whether the refresh detail says live; a failed request is an error,
  /// never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities, FLV and HLS (see [KilakilaApi.qualities]), from the
  /// stream data room entry brought: no request. A room without it (a list
  /// card, a refreshed follow) is entered first; one the platform called
  /// offline has no stream (`StreamUnavailable`, without a request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      KilakilaApi.qualities(await _stream(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] with the media headers and its lease.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => KilakilaApi.resolution(await _stream(detail, fresh: false), quality);

  /// Room entry again: the anchor may be on a new broadcast, and the pull
  /// URLs are signed. A quality the new broadcast lacks, or no broadcast, is
  /// `StreamUnavailable`; the old URLs are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => KilakilaApi.resolution(await _stream(detail, fresh: true), quality);

  Future<KilakilaRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (!fresh) {
      if (detail.data case final KilakilaRoomData data) return data;
      if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
      }
    }
    return (await _entered(detail.roomId)).data! as KilakilaRoomData;
  }

  // Links ---------------------------------------------------------------------

  /// An anchor page (`live.kilakila.cn/zhubo/<uid>`,
  /// `live.hongrenshuo.com.cn/index/roomuser/uid/<uid>`, or its encrypted
  /// form), without a request (see [KilakilaLink.parse]).
  @override
  String? roomIdFromUrl(String url) {
    final link = KilakilaLink.parse(url);
    return link?.kind == KilakilaLinkKind.owner ? link!.id : null;
  }

  /// A broadcast page (`/room/<id>`, `/PcLive/index/detail?id=`, or the
  /// encrypted share links the website hands out): its anchor needs a
  /// request.
  @override
  bool needsResolving(String url) => KilakilaLink.parse(url)?.kind == KilakilaLinkKind.broadcast;

  /// The anchor of a broadcast link: one `getRoomInfo` through [session]
  /// (3.x also asked for the anchor's profile, only to check it); null when
  /// it fails or does not name its anchor (an unknown broadcast, a
  /// historical replay).
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final link = KilakilaLink.parse(url);
    if (link == null || link.kind != KilakilaLinkKind.broadcast) return null;
    final response = await session.get(_roomInfoUrl(link.id), readBody: true, headers: KilakilaApi.headers);
    if (response == null) return null;
    try {
      return LinkRoom(KilakilaApi.roomInfo(response.text, broadcastId: link.id, status: response.status).uid);
    } on SiteError {
      return null;
    }
  }
}
