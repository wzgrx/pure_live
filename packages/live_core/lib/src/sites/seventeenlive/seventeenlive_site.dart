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
/// - there is no catalog (3.x's LiveSite defaults: no category, no area
///   rooms);
/// - the directory is the website's Japanese recommendation sections, one
///   request a page by cursor ([getDirectoryPageAtCursor]); by page number
///   ([getDirectoryPage], recommendations) it replays from page 1;
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
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

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

  // Directory -----------------------------------------------------------------

  /// The sections page after [cursor] (null on page 1): one request (see
  /// [SeventeenLiveApi.sectionsQuery] and [SeventeenLiveApi.sectionsPage]).
  /// [page] is the caller's sequence: page 1 takes no cursor and later pages
  /// need one. There is no category (3.x had none), so [category] must be
  /// null. Anything else, or a cursor 3.x would not send, is a caller error
  /// (`ArgumentError`), refused before any request as in 3.x.
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
    _checkCategory(category);
    SeventeenLiveApi.checkCursor(cursor);
    final response = await _get(
      _api('/api/v1/sections', SeventeenLiveApi.sectionsQuery(cursor)),
      SeventeenLiveApi.catalogHeaders,
      cancel: cancel,
    );
    final result = SeventeenLiveApi.sectionsPage(response.text, cursor: cursor, status: response.status);
    return LiveDirectoryPage(rooms: result.rooms, page: page, hasMore: result.hasMore, nextCursor: result.nextCursor);
  }

  static void _checkCategory(LiveArea? category) {
    if (category != null) throw ArgumentError.value(category, 'category', '17LIVE has no categories');
  }

  /// Page [page] (1–20) of the directory, replayed from page 1 by cursor
  /// (3.x: [page] requests); a directory that ends first gives an empty last
  /// page.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > SeventeenLiveApi.maxDirectoryPage) {
      throw RangeError.range(page, 1, SeventeenLiveApi.maxDirectoryPage, 'page');
    }
    _checkCategory(category);
    String? cursor;
    for (var current = 1; ; current++) {
      final result = await getDirectoryPageAtCursor(page: current, cursor: cursor, cancel: cancel);
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

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search, one page only:
  /// - a page other than 1 or a [pageSize] below 1 finds nothing;
  /// - a room link (see [roomIdFromUrl]) or a room id finds that room, live
  ///   or not (one `lives/<id>`; nothing when there is no such room);
  /// - another URL (anything with a scheme), a blank keyword or one over
  ///   100 characters finds nothing;
  /// - anything else is one `liveStreams/search`: current broadcasts, the
  ///   first [pageSize].
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
    if (text.isEmpty || text.length > SeventeenLiveApi.maxKeywordLength || (Uri.tryParse(text)?.hasScheme ?? false)) {
      return const [];
    }
    final response = await _get(
      _api('/api/v1/liveStreams/search', {'query': text}),
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
  /// ([SeventeenLiveRoomData]). A room that cannot be played (offline, no
  /// pull URL, a state 3.x did not know) is entered; its stream says why.
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

  /// 3.x's qualities (see [SeventeenLiveApi.qualities]) from the data room
  /// entry brought: no request. A room without it (a list card, a refreshed
  /// follow) is entered first; one the platform called offline has no
  /// stream (`StreamUnavailable`, without a request). A room that cannot be
  /// played says why.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      SeventeenLiveApi.playQualities(await _stream(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality]: one per CDN in the answer's order, with the
  /// media headers.
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
