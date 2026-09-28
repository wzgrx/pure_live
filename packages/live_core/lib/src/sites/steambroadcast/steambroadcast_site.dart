import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/steambroadcast/steambroadcast_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'steambroadcast';

/// How many broadcasters the site remembers to fill room answers from
/// (3.x kept every one it listed).
const _rememberLimit = 1000;

/// The Steam broadcast adapter (3.x's `SteamBroadcastSite` and
/// `SteamBroadcastApi`; parsing in [SteamBroadcastApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no chat (3.x's Steam had
/// `EmptyDanmaku`). Every request carries 3.x's headers, does not follow
/// redirects and goes as `steambroadcast`, so the app routes the platform
/// through its proxy setting. The requests are 3.x's:
/// - the catalog is one area, the trending broadcasts; its pages, the
///   recommendations and the keyword search are `allcontenthome` (10 a
///   page, HTML);
/// - a room is its watch page (the broadcaster's name) and
///   `getbroadcastmpd` (state, viewers, HLS master); on room entry and for
///   recording also the HLS master, checked against the account. A refresh
///   loads no master;
/// - each list or room call has one 25 s deadline (3.x's `_scope`).
///
/// Like 3.x, the site remembers the broadcasters it listed and fills a room
/// answer's missing name, title, game, cover, avatar and viewers from them.
///
/// Rooms are identified by the broadcaster's 64-bit Steam id. Failures are
/// `SiteError`s; nothing is disguised as an offline room, and a media
/// problem never fails the room itself: it is reported when the stream is
/// asked for.
final class SteamBroadcastSite extends LiveSite
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
  /// with all its requests (3.x: 25 s).
  new(this.http, {this.deadline = const Duration(seconds: 25)});

  /// Transport.
  final LiveHttp http;

  /// Longest list or room call.
  final Duration deadline;

  /// The last broadcast seen of each broadcaster, oldest first.
  final Map<String, SteamBroadcast> _known = {};

  @override
  String get id => _site;

  @override
  String get name => SteamBroadcastApi.siteName;

  /// 3.x's text key for the directory's scope note (ten a page; the search
  /// filters the requested page, ids and watch links look the account up).
  @override
  String get directoryNoticeKey => 'steambroadcast_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with [headers], redirects not followed. A cancellation
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

  /// Remembers [broadcast] as the latest of its broadcaster.
  void _remember(SteamBroadcast broadcast) {
    _known
      ..remove(broadcast.steamId)
      ..[broadcast.steamId] = broadcast;
    if (_known.length > _rememberLimit) _known.remove(_known.keys.first);
  }

  // Directory -----------------------------------------------------------------

  /// Page [page] of the trending broadcasts (3.x's `directory`); its cards
  /// are remembered. A page past 10000 is a caller error, without a request.
  Future<SteamBroadcastPage> _directory(int page, CancelToken? cancel) {
    if (page > SteamBroadcastApi.maxPage) throw RangeError.range(page, 1, SteamBroadcastApi.maxPage, 'page');
    return _scoped(cancel, (token) async {
      final response = await _get(
        SteamBroadcastApi.directoryUrl(page),
        SteamBroadcastApi.directoryHeaders,
        cancel: token,
      );
      final result = SteamBroadcastApi.directory(response.text, page: page, status: response.status);
      result.broadcasts.forEach(_remember);
      return result;
    });
  }

  /// Another area than the trending broadcasts is a caller error.
  static void _checkArea(LiveArea? category) {
    if (category != null && !SteamBroadcastApi.isArea(category)) {
      throw ArgumentError.value(category, 'category', 'not the trending Steam broadcasts');
    }
  }

  /// 3.x's one category `Steam Broadcasts` with its one area, on page 1 with
  /// a page size of at least 1; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? SteamBroadcastApi.categories() : const [];

  /// Page [page] (10 broadcasts) of the trending broadcasts, for the one area
  /// or the recommendations (3.x). A page below 1 is empty without a request
  /// (3.x); another area is a caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkArea(category);
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final result = await _directory(page, cancel);
    return LiveDirectoryPage(
      rooms: [for (final broadcast in result.broadcasts) SteamBroadcastApi.room(broadcast)],
      page: page,
      hasMore: result.hasMore,
    );
  }

  /// The first [pageSize] (at most 60) cards of directory page [page] (3.x);
  /// a page or size below 1 gives nothing without a request.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    final result = await _directory(page, null);
    return [
      for (final broadcast in result.broadcasts.take(pageSize.clamp(1, SteamBroadcastApi.maxRecommendSize)))
        SteamBroadcastApi.room(broadcast),
    ];
  }

  /// The one area's rooms: [getRecommendRooms].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkArea(category);
    return await getRecommendRooms(page: page, pageSize: pageSize);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search (Steam has no anonymous broadcast search): a Steam id or
  /// watch link is the account's room (two requests, first page only; an
  /// account without a watch page is no result); any other keyword filters
  /// directory page [page] by id, name, title and game (case ignored), the
  /// first [pageSize]. A blank keyword, a page below 1 or a page size
  /// outside 1–100 gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final raw = keyword.trim();
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > SteamBroadcastApi.maxSearchSize) return const [];
    final steamId = SteamBroadcastApi.steamIdOf(raw);
    if (steamId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(steamId, media: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    final result = await _directory(page, cancel);
    return [
      for (final broadcast in SteamBroadcastApi.filter(result.broadcasts, raw.toLowerCase()).take(pageSize))
        SteamBroadcastApi.room(broadcast),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a Steam id (a bare id or a watch link, 3.x); anything else
  /// is `NotFound` without a request.
  static String _steamId(String roomId) {
    final steamId = SteamBroadcastApi.steamIdOf(roomId);
    if (steamId == null) throw NotFound(_site, 'room id "${roomId.trim()}" is not a Steam id');
    return steamId;
  }

  /// [steamId]'s broadcast (3.x's `room`) within one [deadline].
  Future<SteamBroadcast> _broadcast(String steamId, {required bool media, CancelToken? cancel}) =>
      _scoped(cancel, (token) => _read(steamId, media: media, cancel: token));

  /// The watch page, `getbroadcastmpd` and, with [media] for a live one, the
  /// HLS master checked against the account. Whatever goes wrong with the
  /// master becomes the broadcast's media error (3.x failed the room).
  Future<SteamBroadcast> _read(String steamId, {required bool media, required CancelToken cancel}) async {
    final watch = await _get(
      SteamBroadcastApi.watchUrl(steamId),
      SteamBroadcastApi.roomHeaders(steamId),
      cancel: cancel,
    );
    final name = SteamBroadcastApi.broadcaster(watch.text, steamId: steamId, status: watch.status);
    final answer = await _get(
      SteamBroadcastApi.mpdUrl(steamId),
      SteamBroadcastApi.roomHeaders(steamId, json: true),
      cancel: cancel,
    );
    final broadcast = SteamBroadcastApi.broadcast(
      answer.text,
      steamId: steamId,
      broadcaster: name,
      status: answer.status,
    );
    final master = broadcast.master;
    if (!media || master == null || broadcast.mediaError != null) return broadcast;
    try {
      final playlist = await _get(master, SteamBroadcastApi.mediaHeaders(steamId), cancel: cancel);
      return broadcast.withMaster(
        codec: SteamBroadcastApi.checkMaster(playlist.text, master: master, steamId: steamId, status: playlist.status),
      );
    } on SiteError catch (error) {
      return broadcast.withMaster(mediaError: error);
    }
  }

  /// The room of [roomId] (3.x's `_detail`): its broadcast, filled from the
  /// last one remembered of the broadcaster and then remembered itself.
  Future<LiveRoom> _detail(String roomId, {required bool media, bool danmaku = false, CancelToken? cancel}) async {
    final steamId = _steamId(roomId);
    var broadcast = await _broadcast(steamId, media: media, cancel: cancel);
    final known = _known[steamId];
    if (known != null) broadcast = broadcast.enrich(known);
    _remember(broadcast);
    return SteamBroadcastApi.room(
      broadcast,
      data: SteamBroadcastApi.roomData(broadcast),
      danmaku: danmaku ? SteamBroadcastDanmakuArgs(steamId) : null,
    );
  }

  /// The room: its watch page, `getbroadcastmpd` and the checked HLS master
  /// (three requests for a live room, two otherwise; 3.x), with the danmaku
  /// arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, media: true, danmaku: true);

  /// The watch page and `getbroadcastmpd` only (3.x): no master, so the
  /// refreshed room cannot be played until it is entered.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, media: false);

  /// The room with its checked master, like [getRoomDetail] (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, media: true);

  /// Whether the broadcast is live (the refresh's two requests, 3.x). A
  /// restricted or unknown broadcast is `StreamUnavailable`, never
  /// "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId);
    return switch (room.effectiveLiveStatus) {
      LiveStatus.live => true,
      LiveStatus.offline => false,
      _ => throw StreamUnavailable(_site, '${room.roomId}: broadcast state unknown'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The room data of [detail] when it can be played (3.x's `_snapshot`, no
  /// request): a Steam room, not offline, with the data of its own room
  /// answer (a card has none) saying live with a checked master. Otherwise
  /// the reason (see [SteamBroadcastRoomData.streamError]); another
  /// platform's room is a caller error.
  SteamBroadcastRoomData _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Steam broadcast');
    final steamId = _steamId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$steamId is offline');
    final data = detail.data;
    if (data is! SteamBroadcastRoomData || data.steamId != steamId) {
      throw StreamUnavailable(_site, '$steamId has no room answer; enter the room first');
    }
    final error = data.streamError;
    if (error != null) throw error;
    return data;
  }

  static void _checkQuality(LivePlayQuality quality) {
    if ('${quality.selectionId}' != SteamBroadcastApi.qualityId) {
      throw ArgumentError.value(quality, 'quality', 'not the Steam broadcast quality');
    }
  }

  /// 3.x's one quality, 自适应 HLS, when the room can be played (no
  /// request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    _playable(detail);
    return const [SteamBroadcastApi.quality];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The checked master of the room as its one line (no request, 3.x). A
  /// room that cannot be played says why (see [getPlayQualities]); a quality
  /// other than [SteamBroadcastApi.quality] is a caller error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = _playable(detail);
    _checkQuality(quality);
    return LivePlayUrlResolution.lines([
      SteamBroadcastApi.line(data.master!, codec: data.codec),
    ], appliedQualityData: SteamBroadcastApi.qualityId);
  }

  /// A fresh master (3.x): the room is asked again with its master (three
  /// requests), never the one [detail] holds (REG-LEASE-005).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final steamId = _playable(detail).steamId;
    _checkQuality(quality);
    final data = _playable(await _detail(steamId, media: true));
    return LivePlayUrlResolution.lines([
      SteamBroadcastApi.line(data.master!, codec: data.codec),
    ], appliedQualityData: SteamBroadcastApi.qualityId);
  }

  // Links ---------------------------------------------------------------------

  /// A watch link of `steamcommunity.com` (3.x's
  /// `SteamBroadcastLink.parseSteamId`, see [SteamBroadcastApi.steamIdOf]).
  @override
  String? roomIdFromUrl(String url) => SteamBroadcastApi.steamIdOf(url);
}
