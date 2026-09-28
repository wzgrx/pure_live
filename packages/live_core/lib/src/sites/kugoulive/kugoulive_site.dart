import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kugoulive/kugoulive_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'kugoulive';

/// The Kugou Live (酷狗直播, 繁星) adapter (3.x's `KugouLiveSite`; parsing
/// in [KugouLiveApi]).
///
/// A room is its number (3 to 11 digits), as asked for; a room link names
/// its number. Anonymous, like 3.x: no cookie, no account; every request
/// carries [KugouLiveApi.apiHeaders] and follows no redirect. Requests are
/// 3.x's:
/// - the catalog is the home page's area links, read once and kept; a
///   directory page is one room list (`index/list` for 推荐, `list_v4` for an
///   area);
/// - search is one `getEnterRoomInfo` for a room number or link (page 1),
///   else one `type_all.jsonp` of 200 streamers per page, paged here;
/// - follow refreshes and the live state are one `getEnterRoomInfo`;
/// - room entry, recordings and recovery add `streamaddr` while the room is
///   live.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class KugouLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter; [now] (the search callback's and the stream
  /// request's clock values, the default time of the lease queries) is
  /// injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  /// The home page's areas, read once for the adapter's lifetime (3.x); a
  /// failed read is asked again next time.
  Future<List<LiveArea>>? _areas;

  @override
  String get id => _site;

  @override
  String get name => KugouLiveApi.siteName;

  /// 3.x's lasting note on what the directory and search cover.
  @override
  String get directoryNoticeKey => 'kugoulive_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: KugouLiveApi.apiHeaders, followRedirects: false, cancel: cancel),
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

  /// 3.x's catalog on page 1 (see [KugouLiveApi.catalog]): the home page's
  /// areas, the first [pageSize] of them; later pages and a [pageSize] below
  /// 1 are empty without a request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    return KugouLiveApi.catalog(await _catalog(), pageSize);
  }

  Future<List<LiveArea>> _catalog() => _areas ??= () async {
    try {
      final response = await _get(Uri.parse('${KugouLiveApi.webOrigin}/'));
      return KugouLiveApi.areas(response.text, status: response.status);
    } on Object {
      _areas = null;
      rethrow;
    }
  }();

  /// Page [page] of [category] (推荐 when null): one room list request
  /// (see [KugouLiveApi.directoryUrl]). A page below 1 is empty without a
  /// request (3.x); another platform's area, another area type or an id
  /// that is not 1–8 digits is an `ArgumentError`, a page over
  /// [KugouLiveApi.maxPage] a `RangeError`, both before any request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final areaId = KugouLiveApi.areaId(category);
    if (page > KugouLiveApi.maxPage) throw RangeError.range(page, 1, KugouLiveApi.maxPage, 'page');
    final response = await _get(KugouLiveApi.directoryUrl(page, areaId), cancel: cancel);
    return KugouLiveApi.directoryPage(response.text, page: page, status: response.status);
  }

  /// Page [page] of 推荐, at most [pageSize] rooms of it (3.x); a page or
  /// size below 1 is empty without a request.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page)).rooms.take(pageSize).toList();
  }

  /// As [getRecommendRooms], for [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page, category: category)).rooms.take(pageSize).toList();
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search, in its order:
  /// - a blank keyword, a page below 1 or a [pageSize] outside 1–100 finds
  ///   nothing;
  /// - a room number or room link finds that room on page 1 (one
  ///   `getEnterRoomInfo`, the refresh detail; nothing when there is no such
  ///   room, where 3.x showed a room named "Kugou Live") and nothing on later
  ///   pages;
  /// - a keyword over 100 characters is an `ArgumentError` (3.x refused it
  ///   before the request);
  /// - else one `type_all.jsonp` answering 200 streamers, live or not, of
  ///   which page [page] of [pageSize] is returned.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty || page < 1 || pageSize < 1 || pageSize > KugouLiveApi.maxSearchPageSize) return const [];
    final roomId = KugouLiveApi.parseRoomId(text);
    if (roomId != null) {
      if (page != 1) return const [];
      try {
        return [(await _info(roomId, cancel: cancel)).room];
      } on NotFound {
        return const [];
      }
    }
    if (text.length > KugouLiveApi.maxKeywordLength) {
      throw ArgumentError.value(keyword, 'keyword', 'longer than ${KugouLiveApi.maxKeywordLength} characters');
    }
    final callback = 'pureLive${_now().microsecondsSinceEpoch}';
    final response = await _get(KugouLiveApi.searchUrl(text, callback), cancel: cancel);
    final rooms = KugouLiveApi.searchRooms(response.text, callback: callback, status: response.status);
    return rooms.skip((page - 1) * pageSize).take(pageSize).toList();
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a room number (a room link names one, as in 3.x); anything
  /// else is `NotFound` without a request (3.x: `identity`).
  static String _checkedId(String roomId) =>
      KugouLiveApi.parseRoomId(roomId) ?? (throw NotFound(_site, 'not a Kugou Live room: "$roomId"'));

  Future<({LiveRoom room, KugouLiveState state})> _info(String roomId, {CancelToken? cancel}) async {
    final response = await _get(KugouLiveApi.roomInfoUrl(roomId), cancel: cancel);
    return KugouLiveApi.roomInfo(response.text, roomId: roomId, status: response.status);
  }

  /// Room entry (3.x's `room` with media): `getEnterRoomInfo`, then, while
  /// the room is live, `streamaddr`, whose variants go into
  /// [KugouLiveRoomData]. A room that cannot be played (offline, restricted,
  /// no live session, no stream in the answer) is entered; its stream says
  /// why (3.x failed the entry when the answer had no stream). A stream
  /// answer that fails otherwise fails the entry, as in 3.x.
  Future<LiveRoom> _entered(String roomId) async {
    final id = _checkedId(roomId);
    final (:room, :state) = await _info(id);
    final refused = KugouLiveApi.playbackError(state, id);
    if (refused != null) {
      return room.copyWith(
        data: KugouLiveRoomData(roomId: id, unavailable: refused),
      );
    }
    final response = await _get(KugouLiveApi.streamUrl(id, millis: _now().millisecondsSinceEpoch));
    try {
      final variants = KugouLiveApi.variants(response.text, roomId: id, status: response.status);
      return room.copyWith(
        data: KugouLiveRoomData(roomId: id, variants: variants),
      );
    } on StreamUnavailable catch (error) {
      return room.copyWith(
        data: KugouLiveRoomData(roomId: id, unavailable: error),
      );
    }
  }

  /// The room with its variants (see [_entered]): two requests for a live
  /// room, one otherwise.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId);

  /// Follow-card refresh: one `getEnterRoomInfo`, as in 3.x.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async => (await _info(_checkedId(roomId))).room;

  /// Room entry's answer (the variants included), as 3.x's recorder asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  /// Whether the refresh detail says live (one request). A room shown as
  /// unknown has no answer, never "offline": restricted is `NeedsLogin`,
  /// without a live session `ApiChanged` (3.x: `access` for both).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final id = _checkedId(roomId);
    return switch ((await _info(id)).state) {
      KugouLiveState.live => true,
      KugouLiveState.offline => false,
      KugouLiveState.restricted => throw NeedsLogin(_site, 'room $id is restricted (limitType)'),
      KugouLiveState.unknown => throw ApiChanged(_site, 'room $id: neither offline nor a live session'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities (see [KugouLiveApi.qualities]) from the variants room
  /// entry kept: no request. A room without them (a list card, a refreshed
  /// follow) is entered first; one the platform called offline has no
  /// stream (`StreamUnavailable`, without a request). A room that cannot be
  /// played says why.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      KugouLiveApi.qualities(await _variants(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] (by its id, as 3.x) with the media headers and
  /// the lease of each URL; a quality the room does not offer is
  /// `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => KugouLiveApi.resolution(_offered(await _variants(detail, fresh: false), quality));

  /// Room entry again (3.x: two requests). A quality the room no longer
  /// offers, or a room that is no longer live, is an error; the old lines
  /// are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => KugouLiveApi.resolution(_offered(await _variants(detail, fresh: true), quality));

  Future<List<KugouLiveVariant>> _variants(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a Kugou Live room');
    final roomId = _checkedId(detail.roomId);
    if (!fresh && detail.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '$roomId is ${detail.effectiveLiveStatus.name}');
    }
    final kept = detail.data;
    final data = !fresh && kept is KugouLiveRoomData && kept.roomId == roomId
        ? kept
        : (await _entered(roomId)).data! as KugouLiveRoomData;
    if (data.unavailable case final error?) throw error;
    return data.variants;
  }

  static KugouLiveVariant _offered(List<KugouLiveVariant> variants, LivePlayQuality quality) =>
      variants.where((variant) => variant.id == '${quality.selectionId}').firstOrNull ??
      (throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered'));

  /// `txTime` of [url] (3.x); the lines carry the same lease.
  @override
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => KugouLiveApi.invalidAt(url);

  /// Five minutes before [getPlayUrlInvalidAt], or [now] (default: the
  /// clock) once that has passed (3.x).
  @override
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) => KugouLiveApi.refreshAt(url, now: now ?? _now());

  // Links ---------------------------------------------------------------------

  /// A room link (see [KugouLiveApi.roomIdFromUrl]), without a request.
  /// Kugou Live has no short links.
  @override
  String? roomIdFromUrl(String url) => KugouLiveApi.roomIdFromUrl(url);
}
