import 'dart:isolate';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/showroom/showroom_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'showroom';

/// Where the API answers.
const _host = 'www.showroom-live.com';

/// The SHOWROOM adapter (3.x's `ShowroomSite`; parsing in [ShowroomApi]).
///
/// Anonymous, like 3.x: no cookie and no account. Every request carries
/// 3.x's headers, does not follow redirects and goes as `showroom`, so the
/// app routes the platform through its proxy setting. The requests are
/// 3.x's:
/// - the catalog, the directory, the recommendations and the search are all
///   the `live/onlives` snapshot of every live room, paged locally. Page 1
///   of the directory and of the search (the pull to refresh) always asks
///   anew; every other call reuses a snapshot younger than
///   [snapshotLifetime], so the pages after the first come from the same
///   snapshot as the first (19-1; see [getDirectoryPage]);
/// - a room is `room/profile` and `live/live_info` (asked together), after
///   `room/status` when it is named by its key; room entry and recordings
///   also ask `live/streaming_url` for a live room, and hand the comment
///   arguments ([ShowroomDanmakuArgs]) over in `danmakuData`;
/// - recovery asks `live/streaming_url` alone.
///
/// Rooms are identified by their numeric room id, which is what 3.x's
/// details returned whatever the room was asked for by. Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class ShowroomSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (the snapshot's age) is injectable for
  /// tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// How long a snapshot is reused after it arrived (3.x's 30 s).
  static const Duration snapshotLifetime = Duration(seconds: 30);

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  Future<ShowroomSnapshot>? _snapshot;
  DateTime? _snapshotAt;

  @override
  String get id => _site;

  @override
  String get name => 'SHOWROOM';

  /// 3.x's text key for the directory's scope note (one snapshot of the
  /// live rooms, paged locally).
  @override
  String get directoryNoticeKey => 'showroom_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [path] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(String path, {Map<String, String>? query, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: Uri.https(_host, path, query),
          headers: ShowroomApi.headers,
          followRedirects: false,
          cancel: cancel,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(cancel);
    return response;
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  // Snapshot ------------------------------------------------------------------

  Future<ShowroomSnapshot> _fetchSnapshot({CancelToken? cancel}) async {
    final response = await _get('/api/live/onlives', cancel: cancel);
    return ShowroomApi.snapshot(response.text, status: response.status);
  }

  /// The `onlives` snapshot.
  ///
  /// [fresh] (page 1 of the directory or the search: the pull to refresh)
  /// always asks anew. Otherwise the last snapshot is reused while it is
  /// younger than [snapshotLifetime] after it arrived, whoever fetched it
  /// (19-1: 3.x fetched anew for every call with a cancel token, so each
  /// page of the directory and the search came from another snapshot). A
  /// call without [cancel] also shares a fetch under way (3.x fetched again
  /// for every caller that came before the first answer); one with [cancel]
  /// only reuses a snapshot that has arrived, and fetches its own with the
  /// token otherwise, so cancelling it never fails another caller. The
  /// latest successful fetch becomes the shared snapshot; a failed one is
  /// forgotten.
  Future<ShowroomSnapshot> _snapshotFor({CancelToken? cancel, bool fresh = false}) async {
    if (!fresh) {
      final cached = _snapshot;
      final at = _snapshotAt;
      if (cached != null && (at == null ? cancel == null : _young(at))) {
        final snapshot = await cached;
        _checkCancelled(cancel);
        return snapshot;
      }
    }
    if (cancel == null) return await _share();
    final snapshot = await _fetchSnapshot(cancel: cancel);
    _snapshot = Future.value(snapshot);
    _snapshotAt = _now();
    return snapshot;
  }

  bool _young(DateTime at) {
    final age = _now().difference(at);
    return age >= Duration.zero && age < snapshotLifetime;
  }

  /// A new fetch, shared with every caller without a cancel token until it
  /// arrives, and then for [snapshotLifetime]; a failed one is forgotten.
  Future<ShowroomSnapshot> _share() {
    late final Future<ShowroomSnapshot> fetch;
    fetch = _fetchSnapshot().then(
      (snapshot) {
        if (identical(_snapshot, fetch)) _snapshotAt = _now();
        return snapshot;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_snapshot, fetch)) {
          _snapshot = null;
          _snapshotAt = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _snapshot = fetch;
    _snapshotAt = null;
    return fetch;
  }

  /// The genre id of [category]; another platform's area, one that is not a
  /// genre or an id that is not a genre number is a caller error
  /// (`ArgumentError`), without a request.
  static int _genreId(LiveArea category) {
    final genre = int.tryParse(category.areaId);
    if (category.platform != _site || category.areaType != ShowroomApi.areaType || genre == null || genre < 0) {
      throw ArgumentError.value(category, 'category', 'not a SHOWROOM genre');
    }
    return genre;
  }

  /// The lives of [genre]; a genre the snapshot no longer has is `NotFound`.
  static List<ShowroomLive> _genre(ShowroomSnapshot snapshot, int genre) =>
      snapshot.genre(genre) ?? (throw NotFound(_site, 'genre $genre is not in the snapshot'));

  // Catalog and directory -----------------------------------------------------

  /// The one category SHOWROOM with the snapshot's genres as areas; other
  /// pages (and a page size below 1) are empty, without a request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1 || pageSize <= 0) return const [];
    return ShowroomApi.categories(await _snapshotFor());
  }

  /// Page [page] (30 rooms) of [category], or of the recommendations when
  /// it is null (3.x). Page 1 (the pull to refresh) asks for a new snapshot;
  /// later pages come from the last one while it is younger than
  /// [snapshotLifetime], so they neither repeat nor skip rooms of page 1
  /// (19-1). A page below 1 or an area that is not a SHOWROOM genre is a
  /// caller error, without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    final genre = category == null ? null : _genreId(category);
    _checkCancelled(cancel);
    final snapshot = await _snapshotFor(cancel: cancel, fresh: page == 1);
    return ShowroomApi.directoryPage(genre == null ? snapshot.popular : _genre(snapshot, genre), page: page);
  }

  /// Slice [page] of [pageSize] of the Popularity genre (3.x's `_page`: a
  /// page or size below 1, or a size over 100, gives nothing, now without a
  /// request), from the shared snapshot (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (!ShowroomApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final snapshot = await _snapshotFor();
    return [
      for (final live in ShowroomApi.slice(snapshot.popular, page: page, pageSize: pageSize)) ShowroomApi.card(live),
    ];
  }

  /// As [getRecommendRooms], for the genre [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final genre = _genreId(category);
    if (!ShowroomApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final snapshot = await _snapshotFor();
    return [
      for (final live in ShowroomApi.slice(_genre(snapshot, genre), page: page, pageSize: pageSize))
        ShowroomApi.card(live),
    ];
  }

  // Search --------------------------------------------------------------------

  /// As [searchRoomsCancellable], every page from the shared snapshot (3.x
  /// shared it with every call without a cancel token).
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      _search(keyword, page: page, pageSize: pageSize, fresh: false);

  /// The snapshot's lives matching [keyword] (see [ShowroomApi.search]),
  /// page [page] of [pageSize]. SHOWROOM has no search API: only live rooms
  /// are found, and a link is a keyword like any other (3.x). Page 1 asks
  /// for a new snapshot; later pages come from the last one while it is
  /// younger than [snapshotLifetime] (19-1, as [getDirectoryPage]). A blank
  /// keyword or a page 3.x served nothing for gives nothing, without a
  /// request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) => _search(keyword, page: page, pageSize: pageSize, cancel: cancel, fresh: page == 1);

  Future<List<LiveRoom>> _search(
    String keyword, {
    required int page,
    required int pageSize,
    required bool fresh,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty || !ShowroomApi.validSlice(page: page, pageSize: pageSize)) return const [];
    _checkCancelled(cancel);
    final snapshot = await _snapshotFor(cancel: cancel, fresh: fresh);
    return [
      for (final live in ShowroomApi.slice(ShowroomApi.search(snapshot, query), page: page, pageSize: pageSize))
        ShowroomApi.card(live),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// The room id [reference] names: a number itself, a room key through
  /// `room/status` (REG-SHOWROOM-003), anything else `NotFound` without a
  /// request (3.x's `resolveRoomId`).
  Future<int> _roomNumber(String reference) async {
    final text = reference.trim();
    final number = ShowroomApi.roomNumber(text);
    if (number != null) return number;
    if (!ShowroomApi.keyPattern.hasMatch(text)) throw NotFound(_site, 'not a room id or key: "$text"');
    final response = await _get('/api/room/status', query: {'room_url_key': text});
    return ShowroomApi.roomIdOfStatus(response.text, status: response.status);
  }

  /// The room [reference] names: `room/profile` and `live/live_info` asked
  /// together (3.x). On [entry] a live room also asks `live/streaming_url`
  /// and keeps its rows in [ShowroomRoomData]; when that request fails the
  /// room still opens (3.x failed the whole room) and the qualities ask
  /// again. Its comment arguments go in `danmakuData` (19-3), without a
  /// request; a refreshed room has neither.
  Future<LiveRoom> _detail(String reference, {required bool entry}) async {
    final roomId = await _roomNumber(reference);
    final query = {'room_id': '$roomId'};
    final [profile, info] = await Future.wait([
      _get('/api/room/profile', query: query),
      _get('/api/live/live_info', query: query),
    ]);
    final room = ShowroomApi.profile(profile.text, roomId: roomId, status: profile.status);
    final state = ShowroomApi.liveInfo(info.text, roomId: roomId, status: info.status);
    final detail = ShowroomApi.room(room, state);
    if (!entry || !state.live) return detail;
    List<Object?>? streams;
    try {
      streams = await _streamRows(roomId);
    } on SiteError {
      streams = null;
    }
    return detail.copyWith(
      data: ShowroomRoomData(roomId: '$roomId', streams: streams),
      danmakuData: state.danmaku?.withGifts(() => giftCatalog(roomId)),
    );
  }

  // Gifts (D07.7) ---------------------------------------------------------------

  /// How long a room's gift table is reused.
  static const Duration giftListLifetime = Duration(minutes: 30);

  /// How long a failed gift table is not asked for again.
  static const Duration giftRetryAfter = Duration(minutes: 5);

  /// Rooms whose gift tables are kept; the least recent goes first.
  static const int giftListRooms = 16;

  final Map<int, ({Future<ShowroomGiftCatalog> gifts, DateTime at, bool failed})> _giftLists = {};

  /// Room [roomId]'s gift table (`live/gift_list`, D07.7), as D07.6 keeps
  /// AcFun's: fetched once for concurrent callers and reused for
  /// [giftListLifetime]; one that fails counts as empty and is asked for
  /// again after [giftRetryAfter]; parsed off the calling isolate. Never
  /// throws: without a table gifts keep their ids and pictures.
  Future<ShowroomGiftCatalog> giftCatalog(int roomId) {
    final cached = _giftLists.remove(roomId);
    if (cached != null) {
      final age = _now().difference(cached.at);
      if (age >= Duration.zero && age < (cached.failed ? giftRetryAfter : giftListLifetime)) {
        _giftLists[roomId] = cached;
        return cached.gifts;
      }
    }
    final at = _now();
    late final Future<ShowroomGiftCatalog> gifts;
    gifts = () async {
      try {
        final response = await _get('/api/live/gift_list', query: {'room_id': '$roomId'});
        return await _parseGiftList((text: response.text, status: response.status));
      } on Object {
        if (identical(_giftLists[roomId]?.gifts, gifts)) {
          _giftLists[roomId] = (gifts: Future.value(ShowroomGiftCatalog.empty), at: _now(), failed: true);
        }
        return ShowroomGiftCatalog.empty;
      }
    }();
    _giftLists[roomId] = (gifts: gifts, at: at, failed: false);
    while (_giftLists.length > giftListRooms) {
      _giftLists.remove(_giftLists.keys.first);
    }
    return gifts;
  }

  /// [ShowroomApi.giftList] of [answer] in a new isolate; static, so the
  /// closure it sends holds nothing else.
  static Future<ShowroomGiftCatalog> _parseGiftList(({String text, int status}) answer) =>
      Isolate.run(() => ShowroomApi.giftList(answer.text, status: answer.status));

  /// The room with its streams: 3.x's requests (three for a live room, two
  /// for an offline one, one more for a key).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, entry: true);

  /// Follow-card refresh: `room/profile` and `live/live_info` only (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, entry: false);

  /// The same requests as room entry (3.x): the recorder's qualities need no
  /// further request.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, entry: true);

  /// Whether `live/live_info` says live: one request (3.x read the whole
  /// refresh detail, two); a failed request is an error, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final number = await _roomNumber(roomId);
    final response = await _get('/api/live/live_info', query: {'room_id': '$number'});
    return ShowroomApi.liveInfo(response.text, roomId: number, status: response.status).live;
  }

  // Streams -------------------------------------------------------------------

  Future<List<Object?>> _streamRows(int roomId) async {
    final response = await _get('/api/live/streaming_url', query: {'room_id': '$roomId', 'abr_available': '1'});
    return ShowroomApi.streamRows(response.text, status: response.status);
  }

  static void _checkPlatform(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a SHOWROOM room');
  }

  /// 3.x's qualities (see [ShowroomApi.qualities]) from the rows room entry
  /// kept; a room without them (a list card, a refreshed room, or entry's
  /// request failed) asks `live/streaming_url`. A room the platform called
  /// offline has none (`StreamUnavailable`, 3.x gave an empty list), without
  /// a request.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    _checkPlatform(detail);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is offline');
    if (detail.data case ShowroomRoomData(:final roomId, :final streams?) when roomId == detail.roomId) {
      return ShowroomApi.qualities(streams);
    }
    return ShowroomApi.qualities(await _streamRows(await _roomNumber(detail.roomId)));
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] among the room's qualities (by its id, as 3.x),
  /// with 3.x's media headers; a quality the room does not offer is
  /// `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => ShowroomApi.resolution(_offered(await getPlayQualities(detail: detail), quality));

  /// Recovery asks `live/streaming_url` again (one request; 3.x read the
  /// whole room again, three): a room that went live again has new stream
  /// names. The quality asked for is kept, never silently changed: one the
  /// new answer lacks, or an offline room, is `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    _checkPlatform(detail);
    final rows = await _streamRows(await _roomNumber(detail.roomId));
    return ShowroomApi.resolution(_offered(ShowroomApi.qualities(rows), quality));
  }

  static LivePlayQuality _offered(List<LivePlayQuality> qualities, LivePlayQuality quality) =>
      qualities.where((offered) => '${offered.selectionId}' == '${quality.selectionId}').firstOrNull ??
      (throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered'));

  // Links ---------------------------------------------------------------------

  /// The room of a SHOWROOM link, without a request (3.x's
  /// `ShowroomLink.parse`): the id of `room/profile?room_id=`, or the key of
  /// `/r/{key}` and `/{key}`, which room entry looks up. A key made of digits
  /// only would be read as a room id, so it is resolved instead
  /// ([needsResolving]); 3.x opened the wrong room id.
  @override
  String? roomIdFromUrl(String url) {
    final link = ShowroomApi.link(Uri.tryParse(url.trim()));
    if (link == null) return null;
    final key = link.key;
    if (key == null) return link.roomId;
    return ShowroomApi.roomNumber(key) == null ? key : null;
  }

  /// A room link whose key is made of digits only (`/r/7779344804`).
  @override
  bool needsResolving(String url) {
    final key = ShowroomApi.link(Uri.tryParse(url.trim()))?.key;
    return key != null && ShowroomApi.roomNumber(key) != null;
  }

  /// The room id of the key through `room/status` (one request); null when
  /// the key is unknown or the request fails.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final key = ShowroomApi.link(Uri.tryParse(url.trim()))?.key;
    if (key == null) return null;
    final response = await session.get(
      Uri.https(_host, '/api/room/status', {'room_url_key': key}),
      readBody: true,
      headers: ShowroomApi.headers,
    );
    if (response == null) return null;
    try {
      return LinkRoom('${ShowroomApi.roomIdOfStatus(response.text, status: response.status)}');
    } on SiteError {
      return null;
    }
  }
}
