import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/jdlive/jdlive_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'jdlive';

/// How many list cards are kept to complete play answers (3.x kept every
/// card it saw).
const _knownLimit = 2000;

/// How many keyword searches keep their page sequence (3.x kept all).
const _searchLimit = 32;

/// The JD Live adapter (3.x's `JdLiveSite` and `JdLiveApi`; parsing in
/// [JdLiveApi]).
///
/// Anonymous, like 3.x: no cookie and no account. The room entry of a live
/// broadcast carries the arguments of its chat ([JdLiveDanmakuArgs], M5.24;
/// 3.x's JD Live had `EmptyDanmaku`). Every request carries 3.x's headers,
/// does not follow redirects and goes as `jdlive`, so the app routes the platform
/// through its proxy setting. The requests are 3.x's:
/// - the featured list `liveListWithTabToM` (the one area, the directory,
///   the recommendations and the search filter), paged natively: page 1
///   starts a sequence at the clock's time, and each next page sends the
///   previous `currentCount` with that time, while the previous page had
///   new broadcasts (upgrade 28-1; a broadcast already listed in the
///   sequence is not listed again). The directory, the recommendations (and
///   the area) and each search keyword keep their own sequence;
/// - a room is the play answer `getImmediatePlayToM` (refresh, live status,
///   exact search: one request); room entry and recording of a live room
///   with a playlist also download and check it (two requests); recovery
///   asks both again. A replay plays its recording, not downloaded
///   beforehand. Each call has one 20 s deadline (3.x's `_scope`).
///
/// The play answer has no title, shop name, avatar, cover or views; they
/// come from the list cards seen in this session, as in 3.x, else they stay
/// empty (upgrades 28-2, 28-3), so a follow keeps what it stored. Rooms are
/// identified by the broadcast id (`liveId`) asked for. Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class JdLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [deadline] bounds a list page, or a play answer
  /// with its playlist (3.x: 20 s); [now] is the clock of the requests and
  /// list sequences, injectable for tests.
  new(this.http, {this.deadline = const Duration(seconds: 20), DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Longest list page, or play answer and playlist together.
  final Duration deadline;

  final DateTime Function() _now;

  /// The last card or play answer of each broadcast, oldest first.
  final Map<String, JdLiveRoom> _known = {};

  /// Page sequences: `directory`, `recommend` and `search:<keyword>`.
  final Map<String, _Sequence> _sequences = {};

  @override
  String get id => _site;

  @override
  String get name => JdLiveApi.siteName;

  /// 3.x's text key for the directory's scope note (native 30-card pages; the
  /// search filters the requested page, ids and room links look the room
  /// up).
  @override
  String get directoryNoticeKey => 'jdlive_directory_scope';

  // Requests ------------------------------------------------------------------

  /// GETs [url] with [headers], redirects not followed. A cancellation
  /// before the request or while it runs is a cancelled `TransportFailure`,
  /// also when the answer (or a transport failure) arrived meanwhile; other
  /// transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, Map<String, String> headers, {required CancelToken cancel}) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(site: _site, url: url, headers: headers, followRedirects: false, cancel: cancel),
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

  /// Keeps [room] as the latest of its broadcast, dropping the oldest past
  /// [_knownLimit].
  void _remember(JdLiveRoom room) {
    _known
      ..remove(room.liveId)
      ..[room.liveId] = room;
    if (_known.length > _knownLimit) _known.remove(_known.keys.first);
  }

  // Featured list -------------------------------------------------------------

  /// Page [page] of sequence [key] (3.x's `_directory`): page 1 starts the
  /// sequence; a later page needs the previous page of the same sequence
  /// to have asked for it, else it is empty without a request, as is a
  /// page below 1. A broadcast an earlier page of the sequence listed is
  /// left out, and a page without new broadcasts is the last (the unified
  /// timeline rule, with 28-1's "go on while a page has broadcasts"). The
  /// cards are remembered for the play answers.
  Future<JdLivePage> _page(String key, int page, CancelToken? cancel) async {
    _checkCancelled(cancel);
    if (page < 1) return JdLivePage.empty;
    if (page == 1) _start(key);
    final sequence = _sequences[key];
    final count = sequence?.counts[page];
    if (sequence == null || count == null) return JdLivePage.empty;
    if (page > JdLiveApi.maxPage) throw RangeError.range(page, 1, JdLiveApi.maxPage, 'page');
    final result = await _scoped(cancel, (token) async {
      final response = await _get(
        JdLiveApi.listUrl(page: page, count: count, timestamp: sequence.timestamp, now: _now()),
        JdLiveApi.apiHeaders,
        cancel: token,
      );
      return JdLiveApi.directory(response.text, page: page, after: count, status: response.status);
    });
    result.rooms.forEach(_remember);
    final fresh = [
      for (final room in result.rooms)
        if (sequence.listed.add(room.liveId)) room,
    ];
    final hasMore = result.hasMore && fresh.isNotEmpty;
    if (hasMore) {
      sequence.counts[page + 1] = result.nextCount;
    } else {
      sequence.counts.remove(page + 1);
    }
    return JdLivePage(rooms: fresh, nextCount: result.nextCount, hasMore: hasMore);
  }

  /// A new sequence for [key] at the clock's time; searches beyond
  /// [_searchLimit] drop the oldest.
  void _start(String key) {
    _sequences
      ..remove(key)
      ..[key] = _Sequence(_now().millisecondsSinceEpoch);
    final searches = [
      for (final name in _sequences.keys)
        if (name.startsWith('search:')) name,
    ];
    if (searches.length > _searchLimit) _sequences.remove(searches.first);
  }

  /// Another area than the featured list is a caller error.
  static void _checkArea(LiveArea? category) {
    if (category != null && !JdLiveApi.isArea(category)) {
      throw ArgumentError.value(category, 'category', 'not the JD Live featured list');
    }
  }

  // Catalog and directory -----------------------------------------------------

  /// 3.x's one category `JD Live` with its one area (the featured list), on
  /// page 1 with a page size of at least 1; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? JdLiveApi.categories() : const [];

  /// Page [page] of the featured list, for the one area or the
  /// recommendations (3.x): its broadcasts, and whether another page may
  /// follow (28-1). Another area is a caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkArea(category);
    final result = await _page('directory', page, cancel);
    return LiveDirectoryPage(
      rooms: [for (final room in result.rooms) JdLiveApi.room(room)],
      page: page,
      hasMore: result.hasMore,
    );
  }

  /// Page [page] of the featured list (its own sequence), cut to [pageSize]
  /// (at most 30). A page or size below 1 gives nothing without a request
  /// (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    final result = await _page('recommend', page, null);
    return [for (final room in result.rooms.take(pageSize.clamp(1, JdLiveApi.maxRecommendSize))) JdLiveApi.room(room)];
  }

  /// The one area's rooms: [getRecommendRooms]. Another area is a caller
  /// error.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkArea(category);
    return await getRecommendRooms(page: page, pageSize: pageSize);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search: a broadcast id or room link finds that room (page 1
  /// only; a broadcast the site does not know is no result); another
  /// keyword filters page [page] of the featured list (its own sequence per
  /// keyword) by id, account, shop name and title, case ignored, up to
  /// [pageSize]. A blank keyword, a page below 1, a page size below 1 or
  /// over 100, or a link of another site gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final raw = keyword.trim();
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > JdLiveApi.maxSearchSize) return const [];
    final liveId = JdLiveApi.liveIdOf(raw);
    if (liveId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(liveId, withMedia: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (_isLink(raw)) return const [];
    final query = raw.toLowerCase();
    final result = await _page('search:$query', page, cancel);
    final matches = result.rooms.where((room) => JdLiveApi.matches(room, query)).take(pageSize);
    return [for (final room in matches) JdLiveApi.room(room)];
  }

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// filtered the list with it, which never matched.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a broadcast id (a room link is read too, as in 3.x);
  /// anything else is `NotFound` without a request.
  static String _liveId(String roomId) =>
      JdLiveApi.liveIdOf(roomId) ?? (throw NotFound(_site, 'room id "${roomId.trim()}" is not a broadcast id'));

  /// The play answer of [liveId]; with [withMedia], a live broadcast's
  /// playlist is downloaded (3.x's media headers) and checked too, within
  /// the same deadline (3.x's `room`). A live broadcast with only an FLV
  /// stream (28-4) has nothing to check, an app-only one is not played (one
  /// request, as 3.x, which did not count it live); a replay's recording is
  /// not downloaded (JD records whole broadcasts: 1.4 MB and 9,500 segments
  /// for a week, 2026-09-28).
  Future<JdLiveRoom> _play(String liveId, {required bool withMedia, CancelToken? cancel}) =>
      _scoped(cancel, (token) async {
        final response = await _get(JdLiveApi.playUrl(liveId, now: _now()), JdLiveApi.apiHeaders, cancel: token);
        final room = JdLiveApi.play(response.text, liveId: liveId, status: response.status);
        final hls = room.hls;
        if (withMedia && room.state == JdLiveState.live && !room.appOnly && hls != null) {
          final playlist = await _get(hls, JdLiveApi.mediaHeaders(liveId), cancel: token);
          JdLiveApi.checkPlaylist(playlist.text, expected: hls, status: playlist.status);
        }
        return room;
      });

  /// The room of [roomId] (3.x's `_detail`): the play answer completed from
  /// the last card of the broadcast, which it then replaces; with its data
  /// (and media) when [withMedia].
  Future<LiveRoom> _detail(String roomId, {required bool withMedia, CancelToken? cancel}) async {
    final liveId = _liveId(roomId);
    var room = await _play(liveId, withMedia: withMedia, cancel: cancel);
    final known = _known[liveId];
    if (known != null) room = room.enrich(known);
    _remember(room);
    return JdLiveApi.room(room, withData: withMedia);
  }

  /// The room: the play answer and, when live, the playlist check (two
  /// requests, 3.x). The room carries its [JdLiveRoom] with the media and
  /// the blurred background.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, withMedia: true);

  /// The play answer only (one request, 3.x); no room data.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, withMedia: false);

  /// As [getRoomDetail] (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, withMedia: true);

  /// Whether the play answer says live (one request, 3.x); an app-only
  /// broadcast is live too (the unified rule for restricted broadcasts;
  /// 3.x: an error). A state that is neither live nor ended is an error,
  /// never "offline": paused is `StreamUnavailable`, an unknown status
  /// `ApiChanged`.
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final liveId = _liveId(roomId);
    final room = await _play(liveId, withMedia: false);
    final known = _known[liveId];
    _remember(known == null ? room : room.enrich(known));
    return switch (room.state) {
      JdLiveState.live => true,
      JdLiveState.preview || JdLiveState.offline || JdLiveState.replay => false,
      JdLiveState.paused => throw StreamUnavailable(_site, '$liveId is paused'),
      JdLiveState.unknown => throw ApiChanged(_site, '$liveId: unknown status'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The play answer of [detail] when it can be played (3.x's snapshot
  /// check, no request): a JD room, not offline, with the data of a room
  /// entry or recording detail (a card or refresh has none) that is live
  /// with an address or a replay with its recording. Otherwise the reason
  /// (`StreamUnavailable`: app-only, offline, no address or recording);
  /// another platform's room is a caller error.
  JdLiveRoom _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a JD Live room');
    final liveId = _liveId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$liveId is offline');
    final data = detail.data;
    if (data is! JdLiveRoom || data.liveId != liveId) {
      throw StreamUnavailable(_site, '$liveId has no play answer; open the room first');
    }
    final error = data.streamError;
    if (error != null) throw error;
    return data;
  }

  /// The qualities when the room can be played (no request): 3.x's HLS then
  /// FLV for a live room (those with an address, 28-4), `原画` for a
  /// replay's recording.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      JdLiveApi.qualities(_playable(detail));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] from the room's play answer, no request (3.x),
  /// with the media headers (28-5): the applied quality is the one asked
  /// for. A room that cannot be played says why (see [getPlayQualities]),
  /// as does a quality it lacks; another quality is a caller error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final id = '${quality.selectionId}';
    return LivePlayUrlResolution.lines([JdLiveApi.line(_playable(detail), id)], appliedQualityData: id);
  }

  /// A fresh play answer and, for a live broadcast, playlist check for
  /// [quality] (two requests, 3.x; one for a replay): [detail] must have
  /// been playable, and the broadcast still is.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final id = '${quality.selectionId}';
    final liveId = _playable(detail).liveId;
    if (id != JdLiveApi.hlsId && id != JdLiveApi.flvId && id != JdLiveApi.replayId) {
      throw ArgumentError.value(quality, 'quality', 'not a JD Live quality');
    }
    final fresh = await _detail(liveId, withMedia: true);
    return LivePlayUrlResolution.lines([JdLiveApi.line(_playable(fresh), id)], appliedQualityData: id);
  }

  // Links ---------------------------------------------------------------------

  /// A room link of `lives.jd.com` (3.x's `JdLiveLink.parseLiveId`, see
  /// [JdLiveApi.liveIdFromUrl]).
  @override
  String? roomIdFromUrl(String url) => JdLiveApi.liveIdFromUrl(url);
}

/// One page sequence (3.x's `_JdDirectorySequence`): the time of its first
/// page, the `currentCount` to send for each page it may ask for, and the
/// broadcasts it listed.
final class _Sequence {
  new(this.timestamp);

  final int timestamp;
  final Map<int, int> counts = {1: 0};
  final Set<String> listed = {};
}
