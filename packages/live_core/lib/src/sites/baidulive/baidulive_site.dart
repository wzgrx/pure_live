import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/baidulive/baidulive_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'baidulive';

/// The Baidu Live (百度直播) adapter (3.x's `BaiduLiveSite`; parsing in
/// [BaiduLiveApi]).
///
/// A room is one broadcast, its id the room id as asked for (3.x's
/// identity). Anonymous, like 3.x: no cookie, no account; every request
/// carries [BaiduLiveApi.apiHeaders] and follows no redirect. Requests are
/// 3.x's:
/// - the catalog is the feed's channel list (3.x's fixed list until the
///   first feed page brings the platform's), without a request;
/// - a directory page is one signed feed POST; pages follow one feed
///   session for the recommendations and one per channel (30-6), a page
///   repeats no room of the session, and the page a session served last is
///   replayed without a request;
/// - search is one room command for a room id or link, on page 1;
/// - room entry, follow refreshes, recordings, the live state and recovery
///   are one room command each.
///
/// The adapter remembers the cards and rooms it saw (3.x's `_known`), to
/// fill what a later answer for the same room leaves out.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room. A
/// paid, forbidden or banned broadcast keeps its state and is marked
/// (30-5); an ended one plays its recording when there is one (30-4).
final class BaiduLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. Like 3.x, the feed names this client
  /// `pc-<clock>purelivedev` and every room command a new
  /// `pc-<clock>baidulive`; `deviceId` replaces both (tests), [now] the
  /// clock. [preferH264] reads "优先 H.264" (on by default, the setting
  /// shared with 8-8, 14-5, 22-3 and 33-2) at each call: on, a room's
  /// H.264 qualities come before the others, so the default is H.264 and
  /// H.265 is only picked by hand; off, the best tier comes first (30-2,
  /// see [BaiduLiveApi.ordered]).
  new(this.http, {DateTime Function()? now, this._deviceId, bool Function()? preferH264})
    : _now = now ?? DateTime.now,
      _preferH264 = preferH264 ?? _on;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  final String? _deviceId;
  final bool Function() _preferH264;

  static bool _on() => true;

  /// The feed's device id, made once per adapter (3.x).
  late final String _feedDevice = _deviceId ?? 'pc-${_now().microsecondsSinceEpoch.toRadixString(36)}purelivedev';

  /// Rooms remembered, by room id, oldest first.
  final LinkedHashMap<String, BaiduLiveRoom> _known = LinkedHashMap();

  /// The feed session of the recommendations ([_recommendations]) and of
  /// each channel, by its id (30-6: the recommendations and the "推荐"
  /// channel no longer share one).
  final Map<String, _Sequence> _sequences = {};

  /// The session key of the recommendations (no channel id is empty).
  static const String _recommendations = '';

  /// The platform's channels, once a first feed page brought them.
  List<BaiduLiveCategory>? _channels;

  /// Rooms remembered at most (3.x kept every one).
  static const int knownLimit = 512;

  @override
  String get id => _site;

  @override
  String get name => BaiduLiveApi.siteName;

  /// 3.x's lasting note on what the directory and search cover.
  @override
  String get directoryNoticeKey => BaiduLiveApi.directoryNoticeKey;

  // Requests ------------------------------------------------------------------

  /// [request] with redirects not followed (as 3.x). A cancellation before
  /// the request or while it runs is a cancelled `TransportFailure`, also
  /// when the answer (or a transport failure) arrived meanwhile; other
  /// transport failures are `NetworkFailure`.
  Future<LiveResponse> _send(LiveRequest request, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(request);
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

  /// One signed feed page of [channel] (3.x's `directory`), with
  /// [BaiduLiveApi.feedHeaders]. The body is encoded as 3.x's Dio sent it
  /// (`Uri(queryParameters:).query`): empty fields bare (`sid&`).
  Future<BaiduLivePage> _feed(
    BaiduLiveCategory channel, {
    required int page,
    required String sessionId,
    required int refreshIndex,
    CancelToken? cancel,
  }) async {
    final form = BaiduLiveApi.feedForm(
      channel: channel,
      first: page == 1,
      deviceId: _feedDevice,
      now: _now(),
      sessionId: sessionId,
      refreshIndex: refreshIndex,
    );
    final response = await _send(
      LiveRequest(
        site: _site,
        url: BaiduLiveApi.feedUrl,
        method: 'POST',
        headers: BaiduLiveApi.feedHeaders,
        body: utf8.encode(Uri(queryParameters: form).query),
        followRedirects: false,
        cancel: cancel,
      ),
      cancel: cancel,
    );
    return BaiduLiveApi.page(response.text, status: response.status);
  }

  /// Room [roomId] from one room command, filled from what was seen of it
  /// before and remembered (3.x's `_detail`).
  Future<BaiduLiveRoom> _room(String roomId, {CancelToken? cancel}) async {
    final query = BaiduLiveApi.roomQuery(
      roomId,
      deviceId: _deviceId ?? 'pc-${_now().microsecondsSinceEpoch.toRadixString(36)}baidulive',
      now: _now(),
    );
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https(BaiduLiveApi.roomHost, BaiduLiveApi.roomPath, query),
        headers: BaiduLiveApi.apiHeaders,
        followRedirects: false,
        cancel: cancel,
      ),
      cancel: cancel,
    );
    var room = BaiduLiveApi.room(response.text, expectedRoomId: roomId, status: response.status);
    if (_known[roomId] case final known?) room = room.enrich(known);
    _remember(room);
    return room;
  }

  void _remember(BaiduLiveRoom room) {
    _known
      ..remove(room.roomId)
      ..[room.roomId] = room;
    while (_known.length > knownLimit) {
      _known.remove(_known.keys.first);
    }
  }

  /// [roomId] as a room id or room link (3.x accepted both); anything else
  /// is `NotFound` without a request (3.x refused it as an identity error).
  static String _checkedId(String roomId) =>
      BaiduLiveApi.parseRoomId(roomId) ?? (throw NotFound(_site, 'not a room id: $roomId'));

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog on page 1 (see [BaiduLiveApi.categories]): the channels
  /// of the last first feed page, else 3.x's fixed list. No request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? BaiduLiveApi.categories(_channels ?? BaiduLiveApi.fallbackCategories) : const [];

  /// The channel of [area]: null is the first (the recommendations); an
  /// area of another platform or type, or a channel not in the catalog, is
  /// a caller error (3.x refused it before any request).
  BaiduLiveCategory _channel(LiveArea? area) {
    final channels = _channels ?? BaiduLiveApi.fallbackCategories;
    if (area == null) return channels.first;
    if (area.platform != _site || area.areaType != 'official') {
      throw ArgumentError.value(area, 'category', 'not a Baidu Live channel');
    }
    final id = area.areaId.trim();
    return channels.where((channel) => channel.id == id).firstOrNull ??
        (throw ArgumentError.value(area, 'category', 'not in the Baidu Live catalog'));
  }

  /// Page [page] of [category]'s feed (3.x): page 1 starts a new feed
  /// session, and each later page must be the next of that session (any
  /// other page is empty, without a request). A page keeps the rooms the
  /// session has not shown yet and has more while it was full, brought a
  /// new room and moved the session on. The first page's channel list
  /// replaces the catalog. A page below 1 is empty.
  ///
  /// 30-6: the recommendations (no [category]) have a session of their own,
  /// apart from the "推荐" channel's; asking again for the page a session
  /// served last replays it without a request (3.x answered it empty and
  /// ended the list).
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final channel = _channel(category);
    final key = category == null ? _recommendations : channel.id;
    if (page == 1) _sequences[key] = _Sequence();
    final sequence = _sequences[key];
    if (sequence != null && page == sequence.lastPage) {
      if (sequence.last case final last?) return last;
    }
    if (sequence == null || page != sequence.nextPage) {
      return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    }
    if (page > BaiduLiveApi.maxPage) throw RangeError.range(page, 1, BaiduLiveApi.maxPage, 'page');
    final previous = sequence.refreshIndex;
    final result = await _feed(
      channel,
      page: page,
      sessionId: sequence.sessionId,
      refreshIndex: page == 1 ? 1 : previous + 1,
      cancel: cancel,
    );
    if (result.categories.isNotEmpty) _channels = result.categories;
    final fresh = [
      for (final room in result.rooms)
        if (sequence.seen.add(room.roomId)) room,
    ];
    final hasMore = result.hasMore && fresh.isNotEmpty && (page == 1 || result.refreshIndex > previous);
    fresh.forEach(_remember);
    final served = LiveDirectoryPage(
      rooms: [for (final room in fresh) BaiduLiveApi.liveRoom(room)],
      page: page,
      hasMore: hasMore,
    );
    sequence
      ..sessionId = result.sessionId
      ..refreshIndex = result.refreshIndex
      ..nextPage = hasMore ? page + 1 : page
      ..lastPage = page
      ..last = served;
    return served;
  }

  /// The first [pageSize] rooms of page [page] of the recommendations (the
  /// first channel, in a session of their own, 30-6).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page)).rooms.take(pageSize).toList(growable: false);
  }

  /// The first [pageSize] rooms of page [page] of [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page, category: category)).rooms.take(pageSize).toList(growable: false);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search: a room id or room link finds that room, live or not, on
  /// page 1 (one room command; nothing when there is no such room). Baidu
  /// has no public keyword search, so anything else finds nothing, without
  /// a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final roomId = BaiduLiveApi.parseRoomId(keyword.trim());
    if (roomId == null || page != 1 || pageSize < 1) return const [];
    try {
      return [BaiduLiveApi.liveRoom(await _room(roomId, cancel: cancel))];
    } on NotFound {
      return const [];
    }
  }

  // Rooms ---------------------------------------------------------------------

  /// The room with its playback data and, while live, its chat arguments
  /// (`BaiduLiveDanmakuArgs`, M5.26), from the same room command (see
  /// [BaiduLiveApi.liveRoom]).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      BaiduLiveApi.liveRoom(await _room(_checkedId(roomId)), withData: true);

  /// Follow-card and room refresh: the same room command, without the
  /// playback data but with the chat arguments of the same answer, so a
  /// danmaku connection that ended when its signature expired reconnects
  /// with fresh lists (E05.4).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async =>
      BaiduLiveApi.liveRoom(await _room(_checkedId(roomId)), withChat: true);

  /// Room entry's answer, as 3.x's recorder asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => getRoomDetail(roomId: roomId);

  /// Whether the room command says live: a live broadcast is live whether
  /// or not it is paid or blocked (30-5; playback says why it cannot be
  /// played); preview, offline and ended are not; a state 3.x did not know
  /// is `ApiChanged`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _room(_checkedId(roomId));
    return switch (room.state) {
      BaiduLiveState.unknown => throw ApiChanged(_site, 'searchbox 371: unknown state of ${room.roomId}'),
      final state => state == BaiduLiveState.live,
    };
  }

  // Streams -------------------------------------------------------------------

  /// The qualities (see [BaiduLiveApi.qualities]: 原画 and the heights of a
  /// live broadcast, the recording of an ended one; H.264 first while
  /// "优先 H.264" is on) from the data room entry brought: no request. A
  /// room without it (a list card, a refreshed follow) is fetched first;
  /// one the platform called offline has no stream (`StreamUnavailable`,
  /// without a request). A room that cannot be played says why.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      BaiduLiveApi.qualities(await _stream(detail, fresh: false), preferH264: _preferH264());

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] (a 3.x quality id too, see
  /// [BaiduLiveApi.qualityIdFromLegacy]), with the media headers.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => BaiduLiveApi.resolution(await _stream(detail, fresh: false), quality);

  /// A new room command (3.x): the same quality id must still be offered;
  /// the old lines are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => BaiduLiveApi.resolution(await _stream(detail, fresh: true), quality);

  Future<BaiduLiveRoom> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a Baidu Live room');
    final roomId = _checkedId(detail.roomId);
    if (!fresh) {
      if (detail.data case final BaiduLiveRoom room when room.roomId == roomId) return room;
      if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '$roomId is ${detail.effectiveLiveStatus.name}');
      }
    }
    return await _room(roomId);
  }

  // Links ---------------------------------------------------------------------

  /// A room page, PC player or share page (see
  /// [BaiduLiveApi.roomIdFromUrl]), without a request. Baidu Live has no
  /// short links.
  @override
  String? roomIdFromUrl(String url) => BaiduLiveApi.roomIdFromUrl(url);
}

/// One feed session (3.x's `_BaiduDirectorySequence`), with the page it
/// served last (30-6).
final class _Sequence {
  String sessionId = '';
  int refreshIndex = 0;
  int nextPage = 1;
  int lastPage = 0;
  LiveDirectoryPage? last;
  final Set<String> seen = {};
}
