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
/// `EmptyDanmaku`; the chat is M5's, with [SteamBroadcastDanmakuArgs]).
/// Every request carries 3.x's headers, does not follow redirects and goes
/// as `steambroadcast`, so the app routes the platform through its proxy
/// setting. The requests:
/// - the catalog is one area, the trending broadcasts; its pages, the
///   recommendations and the keyword search are `allcontenthome` (10 a
///   page, HTML; 3.x);
/// - a room's name and avatar are its mini profile (27-2; the watch page,
///   3.x's source of the name, when the profile fails);
/// - a refresh reads `getbroadcastinfo` (state, title, game, cover,
///   viewers; `getbroadcastmpd`, 3.x's, when it fails): two requests, as in
///   3.x;
/// - room entry and recording read `getbroadcastmpd` (state, restriction,
///   viewers, master), then for a broadcast that is not offline
///   `getbroadcastinfo` (title, game, cover; 27-2) and the HLS master,
///   checked against the account (its variants are the qualities, 27-7);
/// - recovery reads `getbroadcastmpd` and the master only;
/// - each list or room call has one 25 s deadline (3.x's `_scope`).
///
/// Like 3.x, the site remembers the broadcasters it listed and fills a room
/// answer's missing name, title, game, cover, avatar and (while live)
/// viewers from them.
///
/// Rooms are identified by the broadcaster's 64-bit Steam id; watch and
/// profile links are accepted as room ids, custom addresses resolve with
/// one request (27-4). Failures are `SiteError`s; nothing is disguised as an
/// offline room, and a media problem never fails the room itself: it is
/// reported when the stream is asked for.
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
  /// filters the requested page, ids and links look the account up).
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

  /// 3.x's search (Steam has no anonymous broadcast search): a Steam id, a
  /// watch link or a profile link (27-4) is the account's room (the
  /// refresh's two requests, first page only); a custom address
  /// `steamcommunity.com/id/<name>` is resolved first (one more request,
  /// 27-4); an account without a page is no result. Any other keyword
  /// filters directory page [page] by id, name, title and game (case
  /// ignored), the first [pageSize]. A blank keyword, a page below 1 or a
  /// page size outside 1–100 gives nothing without a request.
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
    final vanity = SteamBroadcastApi.vanityOf(raw);
    if (steamId != null || vanity != null) {
      if (page != 1) return const [];
      try {
        return await _scoped(cancel, (token) async {
          final id = steamId ?? await _resolveVanity(vanity!, token);
          if (id == null) return const <LiveRoom>[];
          return [_finish(await _read(id, media: false, cancel: token))];
        });
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

  /// The Steam id at the custom address [vanity] (its profile XML), or null
  /// when there is no such profile.
  Future<String?> _resolveVanity(String vanity, CancelToken cancel) async {
    final answer = await _get(SteamBroadcastApi.vanityUrl(vanity), SteamBroadcastApi.xmlHeaders, cancel: cancel);
    return SteamBroadcastApi.steamIdOfProfileXml(answer.text, status: answer.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a Steam id (a bare id, a watch link or, since 27-4, a
  /// profile link); anything else is `NotFound` without a request.
  static String _steamId(String roomId) {
    final steamId = SteamBroadcastApi.steamIdOf(roomId);
    if (steamId == null) throw NotFound(_site, 'room id "${roomId.trim()}" is not a Steam id');
    return steamId;
  }

  /// The broadcaster's name and avatar: the mini profile (27-2), or when it
  /// fails the watch page's name (3.x's source; its failures are the
  /// room's, a page without a broadcast config is `NotFound`).
  Future<SteamBroadcastProfile> _profile(String steamId, CancelToken cancel) async {
    try {
      final answer = await _get(
        SteamBroadcastApi.profileUrl(steamId),
        SteamBroadcastApi.roomHeaders(steamId, json: true),
        cancel: cancel,
      );
      return SteamBroadcastApi.profile(answer.text, steamId: steamId, status: answer.status);
    } on SiteError {
      final watch = await _get(
        SteamBroadcastApi.watchUrl(steamId),
        SteamBroadcastApi.roomHeaders(steamId),
        cancel: cancel,
      );
      return (name: SteamBroadcastApi.broadcaster(watch.text, steamId: steamId, status: watch.status), avatar: '');
    }
  }

  /// `getbroadcastmpd` of [steamId] with [profile]'s name and avatar.
  Future<SteamBroadcast> _mpd(String steamId, SteamBroadcastProfile profile, CancelToken cancel) async {
    final answer = await _get(
      SteamBroadcastApi.mpdUrl(steamId),
      SteamBroadcastApi.roomHeaders(steamId, json: true),
      cancel: cancel,
    );
    return SteamBroadcastApi.broadcast(answer.text, steamId: steamId, profile: profile, status: answer.status);
  }

  /// `getbroadcastinfo` of [steamId] with [profile]'s name and avatar.
  Future<SteamBroadcast> _info(String steamId, SteamBroadcastProfile profile, CancelToken cancel) async {
    final answer = await _get(
      SteamBroadcastApi.infoUrl(steamId),
      SteamBroadcastApi.roomHeaders(steamId, json: true),
      cancel: cancel,
    );
    return SteamBroadcastApi.info(answer.text, steamId: steamId, profile: profile, status: answer.status);
  }

  /// [broadcast] with its HLS master loaded and checked against the account
  /// (3.x), and its variants read (27-7). Whatever goes wrong with the
  /// master becomes the broadcast's media error (3.x failed the room).
  Future<SteamBroadcast> _withMaster(SteamBroadcast broadcast, CancelToken cancel) async {
    final master = broadcast.master;
    if (master == null || broadcast.mediaError != null) return broadcast;
    final steamId = broadcast.steamId;
    try {
      final playlist = await _get(master, SteamBroadcastApi.mediaHeaders(steamId), cancel: cancel);
      final codec = SteamBroadcastApi.checkMaster(
        playlist.text,
        master: master,
        steamId: steamId,
        status: playlist.status,
      );
      return broadcast.withMaster(
        codec: codec,
        variants: SteamBroadcastApi.variants(playlist.text, master: master),
      );
    } on SiteError catch (error) {
      return broadcast.withMaster(mediaError: error);
    }
  }

  /// The room's answers. The name and avatar come from [_profile].
  /// Without [media] (a refresh): `getbroadcastinfo`, or 3.x's
  /// `getbroadcastmpd` when it fails (27-2). With [media] (entry,
  /// recording): `getbroadcastmpd` (the state and restriction), then unless
  /// it is offline or the account may not broadcast `getbroadcastinfo`
  /// (title, game, cover; its failure is ignored) and the checked master.
  Future<SteamBroadcast> _read(String steamId, {required bool media, required CancelToken cancel}) async {
    final profile = await _profile(steamId, cancel);
    if (!media) {
      try {
        return await _info(steamId, profile, cancel);
      } on SiteError {
        return await _mpd(steamId, profile, cancel);
      }
    }
    var broadcast = await _mpd(steamId, profile, cancel);
    if (broadcast.state != SteamBroadcastState.offline && broadcast.state != SteamBroadcastState.accountRestricted) {
      try {
        broadcast = broadcast.withInfo(await _info(steamId, profile, cancel));
      } on SiteError {
        // The title, game and cover stay those of getbroadcastmpd and the
        // remembered card (3.x's).
      }
    }
    return await _withMaster(broadcast, cancel);
  }

  /// [broadcast] filled from the last one remembered of the broadcaster,
  /// then remembered itself, as a room.
  LiveRoom _finish(SteamBroadcast broadcast, {bool danmaku = false}) {
    final known = _known[broadcast.steamId];
    final filled = known == null ? broadcast : broadcast.enrich(known);
    _remember(filled);
    return SteamBroadcastApi.room(
      filled,
      data: SteamBroadcastApi.roomData(filled),
      danmaku: danmaku ? SteamBroadcastDanmakuArgs(filled.steamId, broadcastId: filled.broadcastId) : null,
    );
  }

  /// The room of [roomId] (3.x's `_detail`) within one [deadline].
  Future<LiveRoom> _detail(String roomId, {required bool media, bool danmaku = false}) async {
    final steamId = _steamId(roomId);
    final broadcast = await _scoped(null, (token) => _read(steamId, media: media, cancel: token));
    return _finish(broadcast, danmaku: danmaku);
  }

  /// The room: its profile, `getbroadcastmpd`, and unless offline
  /// `getbroadcastinfo` and the checked HLS master (four requests for a
  /// live room, 3.x three; two for an offline one), with the danmaku
  /// arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, media: true, danmaku: true);

  /// The profile and `getbroadcastinfo` (27-2; two requests, as 3.x's
  /// watch page and `getbroadcastmpd`): no master, so the refreshed room
  /// cannot be played until it is entered, and no restriction (the answer
  /// does not say).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, media: false);

  /// The room with its checked master and danmaku arguments, like
  /// [getRoomDetail] (3.x; multi-view connects the danmaku, E05.4).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, media: true, danmaku: true);

  /// Whether the broadcast is live (the refresh's two requests, 3.x's
  /// count). Offline, a restricted account and a replay are not; an unknown
  /// state is `StreamUnavailable`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId);
    return switch (room.effectiveLiveStatus) {
      LiveStatus.live => true,
      LiveStatus.offline || LiveStatus.banned || LiveStatus.replay => false,
      _ => throw StreamUnavailable(_site, '${room.roomId}: broadcast state unknown'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The room data of [detail] when it can be played (3.x's `_snapshot`, no
  /// request): a Steam room, not offline, with the data of its own room
  /// answer saying live (or a replay) with a checked master. Otherwise the
  /// reason (the data's first, see
  /// [SteamBroadcastRoomData.streamError]; a card has no data); another
  /// platform's room is a caller error.
  SteamBroadcastRoomData _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Steam broadcast');
    final steamId = _steamId(detail.roomId);
    final data = detail.data;
    final own = data is SteamBroadcastRoomData && data.steamId == steamId ? data : null;
    if (own?.streamError case final error?) throw error;
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$steamId is offline');
    if (own == null) throw StreamUnavailable(_site, '$steamId has no room answer; enter the room first');
    return own;
  }

  /// The quality of [data] with the id of [quality], or null.
  static LivePlayQuality? _offered(SteamBroadcastRoomData data, LivePlayQuality quality) {
    final wanted = '${quality.selectionId}';
    return data.qualities.where((option) => '${option.selectionId}' == wanted).firstOrNull;
  }

  /// The resolution of [offered] in [data]: the checked master as the one
  /// line, the variant's codec when it names one. A variant's quality names
  /// the variant as the line's selector, so the player plays the master
  /// restricted to it (G01.4; before, every quality played the whole
  /// master and the player chose); the adaptive quality has none.
  static LivePlayUrlResolution _resolution(SteamBroadcastRoomData data, LivePlayQuality offered) {
    final variant = offered.data;
    final line = SteamBroadcastApi.line(
      data.master!,
      codec: variant is SteamBroadcastVariant ? variant.codec ?? data.codec : data.codec,
    );
    return LivePlayUrlResolution.lines(
      [line],
      appliedQualityData: '${offered.selectionId}',
      sourceVariantSelectors: {if (variant is SteamBroadcastVariant) line.url: variant},
    );
  }

  /// 3.x's adaptive quality, 自适应 HLS, then one per variant of the
  /// checked master when it has several (27-7), when the room can be played
  /// (no request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => _playable(detail).qualities;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The checked master of the room as its one line (no request, 3.x),
  /// applied as [quality] (a variant's selector is the quality's data,
  /// [SteamBroadcastVariant]). A room that cannot be played says why (see
  /// [getPlayQualities]); a quality the room does not offer is a caller
  /// error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = _playable(detail);
    final offered = _offered(data, quality);
    if (offered == null) throw ArgumentError.value(quality, 'quality', 'not a quality of this Steam broadcast');
    return _resolution(data, offered);
  }

  /// A fresh master (3.x: the room asked again, REG-LEASE-005): only
  /// `getbroadcastmpd` and the master (two requests; 3.x three), never the
  /// one [detail] holds. A variant the fresh master no longer has plays the
  /// adaptive quality, and says so. A quality that is neither is a caller
  /// error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final steamId = _playable(detail).steamId;
    final wanted = '${quality.selectionId}';
    if (wanted != SteamBroadcastApi.qualityId && !SteamBroadcastApi.isVariantId(wanted)) {
      throw ArgumentError.value(quality, 'quality', 'not a Steam broadcast quality');
    }
    final broadcast = await _scoped(
      null,
      (token) async => await _withMaster(await _mpd(steamId, (name: '', avatar: ''), token), token),
    );
    final data = SteamBroadcastApi.roomData(broadcast);
    if (data.streamError case final error?) throw error;
    return _resolution(data, _offered(data, quality) ?? SteamBroadcastApi.quality);
  }

  // Links ---------------------------------------------------------------------

  /// A watch link or, since 27-4, a profile link of `steamcommunity.com`
  /// (see [SteamBroadcastApi.steamIdOf]).
  @override
  String? roomIdFromUrl(String url) => SteamBroadcastApi.steamIdOf(url);

  /// A custom address `steamcommunity.com/id/<name>` (27-4).
  @override
  bool needsResolving(String url) => SteamBroadcastApi.vanityOf(url) != null;

  /// The Steam id of a custom address: one request for its profile XML;
  /// null when there is no such profile or the answer cannot be read.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final vanity = SteamBroadcastApi.vanityOf(url);
    if (vanity == null) return null;
    final response = await session.get(
      SteamBroadcastApi.vanityUrl(vanity),
      readBody: true,
      headers: SteamBroadcastApi.xmlHeaders,
    );
    if (response == null) return null;
    try {
      final steamId = SteamBroadcastApi.steamIdOfProfileXml(response.text, status: response.status);
      return steamId == null ? null : LinkRoom(steamId);
    } on SiteError {
      return null;
    }
  }
}
