import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/looklive/looklive_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'looklive';

/// How many rooms are kept to complete later answers (3.x kept every room
/// it saw).
const _knownLimit = 2000;

/// The LOOK Live (NetEase) adapter (3.x's `LookLiveSite` and `LookLiveApi`;
/// parsing in [LookLiveApi]).
///
/// Anonymous, like 3.x: no cookie and no account (3.x's LOOK Live also had
/// no chat, `EmptyDanmaku`; since M5.28 room entry and recording hand the
/// chat's [LookLiveDanmakuArgs] from the room answer to `live_danmaku`,
/// without a request of their own). Every request is a form POST of
/// NetEase's `weapi` envelope with 3.x's headers, does not follow redirects, goes as
/// `looklive` (so the app routes the platform through its proxy setting)
/// and has 3.x's 20 s deadline. The requests are 3.x's:
/// - the video and voice recommendation lists, 20 rooms a page, paged
///   natively. The directory without an area, the recommendations and the
///   search ask both lists for the same page and merge them (video first);
///   an area asks its own list. The merged pages remember which list has
///   ended and no longer ask it (upgrade 32-1; page 1 starts over);
/// - a room is `room/get/v3` (one request at every depth); recovery asks it
///   again. The streams are read at room entry and recording only.
///
/// Rooms seen in the lists complete later answers of the same broadcast
/// (heat and viewers, which the room answer lacks, while it is live), as in
/// 3.x. Rooms are identified by the room number asked for. Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class LookLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [deadline] bounds each request (3.x: 20 s).
  new(this.http, {this.deadline = const Duration(seconds: 20)});

  /// Transport.
  final LiveHttp http;

  /// Longest request.
  final Duration deadline;

  /// The last card or answer of each room, oldest first.
  final Map<String, LookLiveRoom> _known = {};

  /// The page at which each list answered "no more" in the merged pages
  /// (32-1); cleared by the next merged page 1.
  final Map<LookLiveKind, int> _ended = {};

  @override
  String get id => _site;

  @override
  String get name => LookLiveApi.siteName;

  /// 3.x's text key for the directory's scope note (native pages of both
  /// lists; the search filters the first page, room numbers and links look
  /// the room up).
  @override
  String get directoryNoticeKey => 'looklive_directory_scope';

  // Requests ------------------------------------------------------------------

  /// POSTs [payload] to [path] in the `weapi` envelope within [deadline]
  /// (3.x's `_post`). The caller's cancellation, before the request or
  /// while it runs, is a cancelled `TransportFailure`, also when the answer
  /// arrived meanwhile; the deadline and other transport failures are
  /// `NetworkFailure`.
  Future<LiveResponse> _post(String path, Object? payload, CancelToken? cancel) async {
    _checkCancelled(cancel);
    final token = CancelToken();
    var expired = false;
    final timer = Timer(deadline, () {
      expired = true;
      token.cancel();
    });
    if (cancel != null) unawaited(cancel.whenCancelled.then((_) => token.cancel()));
    final request = LiveRequest(
      site: _site,
      url: Uri.parse('${LookLiveApi.apiOrigin}$path'),
      method: 'POST',
      headers: LookLiveApi.requestHeaders,
      body: utf8.encode(LookLiveApi.formBody(payload)),
      followRedirects: false,
      timeout: deadline,
      cancel: token,
    );
    try {
      final response = await Future.any<LiveResponse>([
        http.send(request),
        token.whenCancelled.then<LiveResponse>((_) => throw const TransportFailure(_site, TransportReason.cancelled)),
      ]);
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      _checkCancelled(cancel);
      if (expired) throw NetworkFailure(_site, 'no answer within ${deadline.inSeconds} s: $path');
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    } finally {
      timer.cancel();
    }
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  /// [rooms] completed from what was seen of each before, and remembered
  /// (3.x's `_remember`), dropping the oldest past [_knownLimit].
  List<LookLiveRoom> _remember(Iterable<LookLiveRoom> rooms) => [for (final room in rooms) _keep(room)];

  LookLiveRoom _keep(LookLiveRoom room) {
    final known = _known.remove(room.roomId);
    final kept = known == null ? room : room.enrich(known);
    _known[room.roomId] = kept;
    if (_known.length > _knownLimit) _known.remove(_known.keys.first);
    return kept;
  }

  // Lists ---------------------------------------------------------------------

  /// Page [page] of the list of [kind] (3.x's `directory`). A page past
  /// [LookLiveApi.maxPage] is a caller error.
  Future<LookLivePage> _list(LookLiveKind kind, int page, CancelToken? cancel) async {
    if (page > LookLiveApi.maxPage) throw RangeError.range(page, 1, LookLiveApi.maxPage, 'page');
    final response = await _post(LookLiveApi.listPath(kind), LookLiveApi.listPayload(page), cancel);
    return LookLiveApi.directory(response.text, kind: kind, status: response.status);
  }

  /// Page [page] of [kind]'s list, or of both merged when null (3.x's
  /// `_directory`): the requests at once, video rooms first, each room
  /// once; another page when either list has one. A page below 1 is empty
  /// without a request.
  ///
  /// Merged, a list that answered "no more" on an earlier page is not asked
  /// again (upgrade 32-1: 3.x asked both lists on every page, and the video
  /// list, a few rooms long, answered `itemList: null` each time). Page 1
  /// always asks both and starts the record over, so pulling to refresh
  /// sees a list that has grown again.
  Future<LookLivePage> _page(int page, LookLiveKind? kind, CancelToken? cancel) async {
    _checkCancelled(cancel);
    if (page < 1) return LookLivePage.empty;
    if (kind != null) return await _list(kind, page, cancel);
    final asked = [
      for (final list in LookLiveKind.values)
        if (_ended[list] case final end when end == null || page <= end) list,
    ];
    final results = await Future.wait([for (final list in asked) _list(list, page, cancel)]);
    if (page == 1) _ended.clear();
    for (final (index, list) in asked.indexed) {
      if (!results[index].hasMore) {
        _ended[list] = page;
      } else if (_ended[list] case final end? when end <= page) {
        _ended.remove(list);
      }
    }
    final rooms = <String, LookLiveRoom>{};
    for (final result in results) {
      for (final room in result.rooms) {
        rooms.putIfAbsent(room.roomId, () => room);
      }
    }
    return LookLivePage(rooms: rooms.values, hasMore: results.any((result) => result.hasMore));
  }

  /// 3.x's one category `LOOK 直播` with the video and voice areas (the
  /// first [pageSize]), on page 1 only; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? LookLiveApi.categories(pageSize: pageSize) : const [];

  /// Page [page] of [category]'s list, or of both lists merged for the
  /// recommendations (3.x). Another area is a caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    final kind = LookLiveApi.kindOf(category);
    final result = await _page(page, kind, cancel);
    return LiveDirectoryPage(
      rooms: [for (final room in _remember(result.rooms)) LookLiveApi.liveRoom(room)],
      page: page,
      hasMore: result.hasMore,
    );
  }

  /// Page [page] of both lists merged, cut to [pageSize]. A page or size
  /// below 1 gives nothing without a request (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page)).rooms.take(pageSize).toList();
  }

  /// Page [page] of [category]'s list, cut to [pageSize]. A page or size
  /// below 1 gives nothing without a request; another area is a caller
  /// error (3.x).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page, category: category)).rooms.take(pageSize).toList();
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search (page 1 only): a room number or room link finds that room
  /// (a room the site does not know is no result); another keyword filters
  /// the first page of both lists by number, name and title, case ignored,
  /// up to [pageSize]. A blank keyword, another page, a page size below 1
  /// or over 100, or a link of another site gives nothing without a
  /// request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final raw = keyword.trim();
    if (raw.isEmpty || page != 1 || pageSize < 1 || pageSize > LookLiveApi.maxSearchSize) return const [];
    final roomId = LookLiveApi.roomIdOf(raw);
    if (roomId != null) {
      try {
        return [await _detail(roomId, withMedia: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (_isLink(raw)) return const [];
    final query = raw.toLowerCase();
    final rooms = _remember((await _page(1, null, cancel)).rooms);
    return [
      for (final room in rooms.where((room) => LookLiveApi.matches(room, query)).take(pageSize))
        LookLiveApi.liveRoom(room),
    ];
  }

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// filtered the lists with it, which never matched.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a room number (a room link is read too, as in 3.x);
  /// anything else is `NotFound` without a request.
  static String _roomId(String roomId) =>
      LookLiveApi.roomIdOf(roomId) ?? (throw NotFound(_site, 'room id "${roomId.trim()}" is not a room number'));

  /// The room answer of [roomId], with its streams when [withMedia] and
  /// live, completed from the last card or answer of the room, which it then
  /// replaces (3.x's `_detail`).
  Future<LookLiveRoom> _answer(String roomId, {required bool withMedia, CancelToken? cancel}) async {
    final number = _roomId(roomId);
    final response = await _post(LookLiveApi.roomPath, LookLiveApi.roomPayload(number), cancel);
    return _keep(LookLiveApi.room(response.text, roomId: number, withMedia: withMedia, status: response.status));
  }

  /// The room of [roomId]; with its data (and streams) when [withMedia].
  Future<LiveRoom> _detail(String roomId, {required bool withMedia, CancelToken? cancel}) async => LookLiveApi.liveRoom(
    await _answer(roomId, withMedia: withMedia, cancel: cancel),
    withData: withMedia,
  );

  /// The room with its streams (one request, 3.x); the room carries its
  /// [LookLiveRoom].
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, withMedia: true);

  /// The room without streams or data (one request, 3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, withMedia: false);

  /// As [getRoomDetail] (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, withMedia: true);

  /// Whether the room answer says live (one request, 3.x): live rooms that
  /// cannot be played here (app-only, ticketed) are live too. A banned room
  /// is not live (32-2; 3.x failed on -10); an unknown state is
  /// `ApiChanged`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _answer(roomId, withMedia: false);
    return switch (room.state) {
      LookLiveState.live => true,
      LookLiveState.offline || LookLiveState.banned => false,
      LookLiveState.unknown => throw ApiChanged(_site, '${room.roomId}: unknown liveStatus'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The room data of [detail] when it can be played (3.x's snapshot check,
  /// no request): a LOOK room, not offline, with the data of a room entry
  /// or recording detail (a card or refresh has none), live with streams.
  /// Otherwise `StreamUnavailable` with the reason (see
  /// [LookLiveRoom.streamError]); another platform's room is a caller
  /// error.
  LookLiveRoom _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a LOOK Live room');
    final roomId = _roomId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$roomId is ${detail.effectiveLiveStatus.name}');
    final data = detail.data;
    if (data is! LookLiveRoom || data.roomId != roomId) {
      throw StreamUnavailable(_site, '$roomId has no room answer; open the room first');
    }
    final error = data.streamError;
    if (error != null) throw error;
    return data;
  }

  /// 3.x's qualities, one per stream (HLS, then FLV), when the room can be
  /// played (no request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      LookLiveApi.qualities(_playable(detail));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] from the room's streams, no request (3.x): the
  /// applied quality is the one asked for. A room that cannot be played
  /// says why (see [getPlayQualities]); another quality is a caller error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final id = '${quality.selectionId}';
    return LivePlayUrlResolution.lines([LookLiveApi.line(_playable(detail), id)], appliedQualityData: id);
  }

  /// A fresh room answer for [quality] (one request, 3.x): [detail] must
  /// have been playable, and the room still is. Another quality is a caller
  /// error, before any request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final id = '${quality.selectionId}';
    final roomId = _playable(detail).roomId;
    if (id != LookLiveApi.hlsId && id != LookLiveApi.flvId) {
      throw ArgumentError.value(quality, 'quality', 'not a LOOK Live quality');
    }
    final fresh = await _detail(roomId, withMedia: true);
    return LivePlayUrlResolution.lines([LookLiveApi.line(_playable(fresh), id)], appliedQualityData: id);
  }

  // Links ---------------------------------------------------------------------

  /// A room link of `look.163.com` (3.x's `LookLiveLink.parseRoomId`, see
  /// [LookLiveApi.roomIdFromUrl]).
  @override
  String? roomIdFromUrl(String url) => LookLiveApi.roomIdFromUrl(url);
}
