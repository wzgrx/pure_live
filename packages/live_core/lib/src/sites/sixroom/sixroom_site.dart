import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/sixroom/sixroom_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'sixroom';

/// How many rooms the site remembers to fill room answers from and to skip
/// the room page with (3.x kept every one it listed; the homepage lists
/// about 450 at the evening peak).
const _rememberLimit = 2000;

/// The 6.cn (六间房) adapter (3.x's `SixRoomSite` and `SixRoomApi`; parsing
/// in [SixRoomApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no chat (3.x's Six Rooms
/// had `EmptyDanmaku`). Every request carries 3.x's headers, does not follow
/// redirects, may take 15 s (3.x's receive timeout) and goes as `sixroom`,
/// so the app routes the platform through its proxy setting. The requests:
/// - the recommendations and 歌区, 舞区, 脱口秀, 派对 are pages of the
///   app's mobile lists (`special`, `u0`, `u1`, `u2`, `u8`; M4.U.31, 31-4:
///   3.x filtered the 1 MB homepage for every list), one request a page.
///   Rooms an earlier page of the list gave since its page 1 are left out;
/// - "全部" is still the homepage (every live room; the app has no such
///   list), 星颜 the web's subarea list (the app's `u10` answers nothing).
///   Both are read whole and paged locally: page 1 loads the list, later
///   pages reuse it for 90 s (3.x's homepage snapshot);
/// - the search is `search.php` (one page); a room number or room link
///   looks the room up instead;
/// - a room is the mobile inroom POST for its broadcaster's user id. The id
///   comes from the rooms the site listed, else from the room page (3.x
///   read it there too, with a pattern the page no longer matched);
/// - each list or room call has one 20 s deadline (3.x's `_scope`).
///
/// Like 3.x, the site remembers the rooms it listed and read, and fills a
/// room answer's missing avatar, cover, area and followers from them, and
/// the popularity and start only while the same broadcast is live (31-5).
///
/// Rooms are identified by their room number (`rid`), as in 3.x. Failures
/// are `SiteError`s; nothing is disguised as an offline room.
final class SixRoomSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [deadline] bounds one list call, or one room call
  /// with all its requests (3.x: 20 s); [clock] dates the snapshots of the
  /// lists read whole.
  new(this.http, {this.deadline = const Duration(seconds: 20), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Longest list or room call.
  final Duration deadline;

  /// Longest single request (3.x's receive timeout).
  static const Duration requestTimeout = Duration(seconds: 15);

  final DateTime Function() _clock;

  /// The last room seen of each room number, oldest first.
  final Map<String, SixRoomRoom> _known = {};

  /// The lists read whole (the homepage, web subareas) by their URL, and
  /// when they were loaded.
  final Map<Uri, ({List<SixRoomRoom> rooms, DateTime at})> _snapshots = {};

  /// The rooms of each page of each mobile list sequence (type and page
  /// size) since its page 1.
  final Map<String, Map<int, Set<String>>> _listed = {};

  @override
  String get id => _site;

  @override
  String get name => SixRoomApi.siteName;

  /// 3.x's text key for the directory's scope note (the homepage's live
  /// rooms paged locally in six areas; the search finds offline
  /// broadcasters too; room numbers and links look the room up).
  @override
  String get directoryNoticeKey => 'sixroom_directory_scope';

  // Requests ------------------------------------------------------------------

  /// [request] sent, redirects not followed. A cancellation before the
  /// request or while it runs is a cancelled `TransportFailure`, also when
  /// the answer (or a transport failure) arrived meanwhile; other transport
  /// failures are `NetworkFailure`.
  Future<LiveResponse> _send(LiveRequest request, CancelToken cancel) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(cancel);
    return response;
  }

  /// A GET with 3.x's web headers, or the mobile ones for the app's lists.
  Future<LiveResponse> _get(Uri url, {required CancelToken cancel, bool mobile = false}) => _send(
    LiveRequest(
      site: _site,
      url: url,
      headers: mobile ? SixRoomApi.listHeaders : SixRoomApi.webHeaders,
      followRedirects: false,
      timeout: requestTimeout,
      cancel: cancel,
    ),
    cancel,
  );

  /// 3.x's form POST: the fields in its order, encoded as `Uri` does.
  Future<LiveResponse> _post(Uri url, Map<String, String> fields, {required CancelToken cancel}) => _send(
    LiveRequest(
      site: _site,
      url: url,
      method: 'POST',
      headers: SixRoomApi.mobileHeaders,
      body: utf8.encode(Uri(queryParameters: fields).query),
      followRedirects: false,
      timeout: requestTimeout,
      cancel: cancel,
    ),
    cancel,
  );

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  /// [work] under its own token, cancelled by [cancel] or when [deadline]
  /// passes (3.x's `_scope`): the caller's cancellation is a cancelled
  /// `TransportFailure`, the deadline a `NetworkFailure`.
  Future<T> _scoped<T>(CancelToken? cancel, Future<T> Function(CancelToken token) work) async {
    _checkCancelled(cancel);
    final token = CancelToken();
    var expired = false;
    final timer = Timer(deadline, () {
      expired = true;
      token.cancel();
    });
    if (cancel != null) unawaited(cancel.whenCancelled.then((_) => token.cancel()));
    try {
      return await Future.any<T>([
        work(token),
        token.whenCancelled.then<T>((_) => throw const TransportFailure(_site, TransportReason.cancelled)),
      ]);
    } on TransportFailure catch (failure) {
      if (failure.reason != TransportReason.cancelled || !expired || (cancel?.isCancelled ?? false)) rethrow;
      throw NetworkFailure(_site, 'no answer within ${deadline.inSeconds} s');
    } finally {
      timer.cancel();
    }
  }

  /// [room] filled from the last one remembered of its room (3.x's
  /// `enrich`), remembered as the latest itself.
  SixRoomRoom _remember(SixRoomRoom room) {
    final known = _known.remove(room.roomId);
    final merged = known == null ? room : room.enrich(known);
    _known[room.roomId] = merged;
    if (_known.length > _rememberLimit) _known.remove(_known.keys.first);
    return merged;
  }

  // Directory -----------------------------------------------------------------

  /// The rooms of the list [url] read whole ([parse] reads its answer):
  /// loaded for [refresh], else reused while younger than 90 s (and not from
  /// the future, 3.x's homepage snapshot).
  Future<List<SixRoomRoom>> _whole(
    Uri url,
    List<SixRoomRoom> Function(String body, int status) parse, {
    required bool refresh,
    required CancelToken cancel,
  }) async {
    final cached = _snapshots[url];
    final now = _clock();
    if (!refresh &&
        cached != null &&
        !now.isBefore(cached.at) &&
        now.difference(cached.at) < SixRoomApi.directoryCacheLifetime) {
      return cached.rooms;
    }
    final response = await _get(url, cancel: cancel);
    final rooms = parse(response.text, response.status);
    _snapshots[url] = (rooms: rooms, at: _clock());
    return rooms;
  }

  /// Page [page] of [pageSize] rooms of a list read whole (the homepage for
  /// all rooms, 3.x; a web subarea for 星颜, 31-4), paged locally.
  Future<LiveDirectoryPage> _wholePage(
    int page,
    int pageSize,
    Uri url,
    List<SixRoomRoom> Function(String body, int status) parse,
    CancelToken token,
  ) async {
    final rooms = await _whole(url, parse, refresh: page == 1, cancel: token);
    final start = (page - 1) * pageSize;
    if (start >= rooms.length) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final end = (start + pageSize).clamp(0, rooms.length);
    return LiveDirectoryPage(
      rooms: [for (final room in rooms.sublist(start, end)) SixRoomApi.liveRoom(_remember(room))],
      page: page,
      hasMore: end < rooms.length,
    );
  }

  /// Page [page] of [pageSize] rooms of the mobile list [type] (31-4): one
  /// request. Rooms an earlier page of the list at this size gave since its
  /// page 1 are left out (the list moves by popularity between pages); a
  /// page asked again is not measured against itself.
  Future<LiveDirectoryPage> _listPage(int page, int pageSize, String type, CancelToken token) async {
    final response = await _get(
      SixRoomApi.listUrl(type, page: page, size: pageSize),
      cancel: token,
      mobile: true,
    );
    final result = SixRoomApi.list(response.text, type: type, page: page, size: pageSize, status: response.status);
    final key = '$type/$pageSize';
    if (page == 1) _listed.remove(key);
    final pages = _listed.putIfAbsent(key, () => {});
    final earlier = {
      for (final MapEntry(key: number, value: ids) in pages.entries)
        if (number < page) ...ids,
    };
    pages[page] = {for (final room in result.rooms) room.roomId};
    return LiveDirectoryPage(
      rooms: [
        for (final room in result.rooms)
          if (!earlier.contains(room.roomId)) SixRoomApi.liveRoom(_remember(room)),
      ],
      page: page,
      hasMore: result.hasMore,
    );
  }

  /// Page [page] of [pageSize] rooms of area [areaId], or of the
  /// recommendations when null, within one deadline; the cards are
  /// remembered. A page past 10000 is a caller error, without a request.
  Future<LiveDirectoryPage> _directoryPage(int page, int pageSize, String? areaId, CancelToken? cancel) {
    if (page > SixRoomApi.maxPage) throw RangeError.range(page, 1, SixRoomApi.maxPage, 'page');
    final type = areaId == null ? SixRoomApi.recommendType : SixRoomApi.mobileTypeOf(areaId);
    final subarea = areaId == null ? null : SixRoomApi.subareaOf(areaId);
    return _scoped(cancel, (token) {
      if (type != null) return _listPage(page, pageSize, type, token);
      if (subarea != null) {
        return _wholePage(
          page,
          pageSize,
          SixRoomApi.subareaUrl(subarea),
          (body, status) => SixRoomApi.subarea(body, status: status),
          token,
        );
      }
      return _wholePage(
        page,
        pageSize,
        SixRoomApi.homeUrl,
        (body, status) => SixRoomApi.directory(body, status: status),
        token,
      );
    });
  }

  /// The area id of [category]; another platform, type or id is a caller
  /// error.
  static String _areaId(LiveArea category) =>
      SixRoomApi.areaIdOf(category) ?? (throw ArgumentError.value(category, 'category', 'not a Six Rooms area'));

  /// 3.x's one category `六间房直播` with the first [pageSize] of its six
  /// areas, on page 1 with a page size of at least 1; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? SixRoomApi.categories(limit: pageSize) : const [];

  /// Page [page] (30 rooms) of [category], or of the recommendations (the
  /// mobile list `special`, 31-4; 3.x: all rooms). A page below 1 is empty
  /// without a request (3.x); another area is a caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    return await _directoryPage(page, SixRoomApi.pageSize, category == null ? null : _areaId(category), cancel);
  }

  /// Page [page] of [pageSize] (at most 100) rooms of the recommendations
  /// (the mobile list `special`, 31-4; 3.x: all rooms); a page or size
  /// below 1 gives nothing without a request.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await _directoryPage(page, pageSize.clamp(1, SixRoomApi.maxPageSize), null, null)).rooms;
  }

  /// Page [page] of [pageSize] (at most 100) rooms of [category]; a page or
  /// size below 1 gives nothing without a request.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await _directoryPage(page, pageSize.clamp(1, SixRoomApi.maxPageSize), _areaId(category), null)).rooms;
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search: a room number or room link is that room (page 1 only,
  /// without its stream; a room that does not exist is no result); any
  /// other keyword is the first [pageSize] cards of `search.php` (page 1
  /// only, remembered and filled from what the site knows). A blank
  /// keyword, a page below 1 or a page size outside 1–100 gives nothing
  /// without a request; so does a keyword over 80 characters (3.x failed
  /// it; 6.cn answers "too long" past 15).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final raw = keyword.trim();
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > SixRoomApi.maxPageSize) return const [];
    final roomId = SixRoomApi.roomIdOf(raw);
    if (roomId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(roomId, media: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (page != 1 || raw.length > SixRoomApi.maxKeywordLength) return const [];
    final rooms = await _scoped(cancel, (token) async {
      final response = await _get(SixRoomApi.searchUrl(raw), cancel: token);
      return SixRoomApi.search(response.text, status: response.status);
    });
    // Every result is remembered, the shown ones too (3.x).
    final remembered = [for (final room in rooms) _remember(room)];
    return [for (final room in remembered.take(pageSize)) SixRoomApi.liveRoom(room)];
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a room number (a number or room link, 3.x); anything else
  /// is `NotFound` without a request.
  static String _roomId(String roomId) =>
      SixRoomApi.roomIdOf(roomId) ?? (throw NotFound(_site, 'room id "${roomId.trim()}" is not a Six Rooms room'));

  /// Room [roomId]: the broadcaster's user id ([knownUserId], else from the
  /// room page) and the inroom answer, with the stream for [media].
  Future<SixRoomRoom> _read(
    String roomId, {
    required String? knownUserId,
    required bool media,
    required CancelToken cancel,
  }) async {
    var userId = knownUserId?.trim() ?? '';
    if (!SixRoomApi.isUserId(userId)) {
      final page = await _get(SixRoomApi.roomUrl(roomId), cancel: cancel);
      userId = SixRoomApi.userIdOf(page.text, roomId: roomId, status: page.status);
    }
    final answer = await _post(SixRoomApi.inroomUrl, SixRoomApi.inroomForm(userId), cancel: cancel);
    return SixRoomApi.room(answer.text, roomId: roomId, userId: userId, media: media, status: answer.status);
  }

  /// The room of [roomId] (3.x's `_detail`) within one [deadline]: its
  /// answer, filled from the last one remembered of the room and then
  /// remembered itself.
  Future<LiveRoom> _detail(String roomId, {required bool media, bool danmaku = false, CancelToken? cancel}) async {
    final id = _roomId(roomId);
    final room = _remember(
      await _scoped(cancel, (token) => _read(id, knownUserId: _known[id]?.userId, media: media, cancel: token)),
    );
    return SixRoomApi.liveRoom(
      room,
      data: SixRoomApi.roomData(room),
      danmaku: danmaku ? SixRoomDanmakuArgs(roomId: room.roomId, userId: room.userId) : null,
    );
  }

  /// The room with its stream (one request when the site knows the
  /// broadcaster, two otherwise; 3.x) and the danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, media: true, danmaku: true);

  /// The room without its stream (3.x), so it cannot be played until it is
  /// entered.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, media: false);

  /// The room with its stream, like [getRoomDetail] (3.x), and the danmaku
  /// arguments of the same answer (multi-view connects them; E05.4).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, media: true, danmaku: true);

  /// Whether the room is live (the refresh's requests, 3.x); a live private
  /// or black-screen room is live (M2.1; 3.x failed). A state the answer
  /// does not give is `StreamUnavailable`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId);
    return switch (room.effectiveLiveStatus) {
      LiveStatus.live => true,
      LiveStatus.offline => false,
      _ => throw StreamUnavailable(_site, '${room.roomId}: state unknown'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The room data of [detail] when it can be played (3.x's `_snapshot`, no
  /// request): a Six Rooms room, not offline, with the data of its own
  /// room answer (a card has none) saying live with a stream. Otherwise the
  /// reason (see [SixRoomRoomData.streamError]); another platform's room is
  /// a caller error.
  SixRoomRoomData _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Six Rooms room');
    final roomId = _roomId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$roomId is offline');
    final data = detail.data;
    if (data is! SixRoomRoomData || data.roomId != roomId) {
      throw StreamUnavailable(_site, '$roomId has no room answer; enter the room first');
    }
    final error = data.streamError;
    if (error != null) throw error;
    return data;
  }

  static void _checkQuality(LivePlayQuality quality) {
    if ('${quality.selectionId}' != SixRoomApi.qualityId) {
      throw ArgumentError.value(quality, 'quality', 'not the Six Rooms quality');
    }
  }

  /// 3.x's one quality, `FLV 原始线路` with the resolution and bitrate, when
  /// the room can be played (no request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => [
    SixRoomApi.quality(_playable(detail).stream!),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The room's FLV stream as its one line (no request, 3.x). A room that
  /// cannot be played says why (see [getPlayQualities]); a quality other
  /// than 3.x's `flv:source` is a caller error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = _playable(detail);
    _checkQuality(quality);
    return LivePlayUrlResolution.lines([SixRoomApi.line(data.stream!)], appliedQualityData: SixRoomApi.qualityId);
  }

  /// A fresh stream (3.x): the room is asked again with its stream, never
  /// the one [detail] holds (REG-LEASE-005).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final roomId = _playable(detail).roomId;
    _checkQuality(quality);
    final data = _playable(await _detail(roomId, media: true));
    return LivePlayUrlResolution.lines([SixRoomApi.line(data.stream!)], appliedQualityData: SixRoomApi.qualityId);
  }

  // Links ---------------------------------------------------------------------

  /// A room link of `v.6.cn` or `m.6.cn` (3.x's `SixRoomLink.parseRoomId`,
  /// see [SixRoomApi.roomIdOf]).
  @override
  String? roomIdFromUrl(String url) => SixRoomApi.roomIdOf(url);
}
