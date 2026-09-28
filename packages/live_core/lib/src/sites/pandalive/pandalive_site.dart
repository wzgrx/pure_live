import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/pandalive/pandalive_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'pandalive';

/// The PandaTV (팬더티비) adapter (3.x's `PandaLiveSite`; parsing in
/// [PandaLiveApi]).
///
/// A room is a broadcaster, its id the login id as asked for (3.x's
/// identity). Anonymous, like 3.x: no cookie, no account; every request
/// carries [PandaLiveApi.headers] with the page it stands for as Referer and
/// follows no redirect. Requests are 3.x's:
/// - the catalog is one fixed area, the public directory, without a
///   request; a directory page is one `live/index` POST (30 by popularity);
/// - search is one `member/bj` for a room link or, on page 1, a keyword
///   that is a broadcaster id; else the BJ search (`live/bj_list`) and then
///   the LIVE search (`live/index` by viewers), one after the other, each
///   with half the page;
/// - follow refreshes and the live state are one `member/bj`;
/// - room entry, recordings and recovery add `live/play` and the IVS master
///   (read once, its variants handed out) while the broadcaster is live.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class PandaLiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (when `live/play` issued the variants) is
  /// injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => PandaLiveApi.categoryName;

  /// 3.x's lasting note on what the directory and search cover.
  @override
  String get directoryNoticeKey => 'pandalive_directory_scope';

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

  /// A form POST of [form] to the API at [path] (3.x's `_post`): the
  /// content type without a charset, as Dio sent it.
  Future<LiveResponse> _post(String path, Map<String, String> form, {required String referer, CancelToken? cancel}) {
    final url = Uri.https(PandaLiveApi.apiHost, path);
    return _send(
      LiveRequest(
        site: _site,
        url: url,
        method: 'POST',
        headers: {...PandaLiveApi.headers(referer), 'content-type': 'application/x-www-form-urlencoded'},
        body: LiveRequest.form(site: _site, url: url, fields: form).body,
        followRedirects: false,
        cancel: cancel,
      ),
      cancel: cancel,
    );
  }

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog (see [PandaLiveApi.categories]) on page 1; later pages are
  /// empty. No request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 ? PandaLiveApi.categories() : const [];

  /// Page [page] (1–1000) of the public directory: one `live/index` POST of
  /// 30 by popularity (see [PandaLiveApi.livePage]). [category] is null or
  /// the public area; anything else, or a page out of range, is a caller
  /// error refused before any request, as in 3.x.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    PandaLiveApi.checkArea(category);
    PandaLiveApi.checkPage(page);
    final response = await _post(
      '/v1/live/index',
      PandaLiveApi.directoryForm(page),
      referer: '${PandaLiveApi.origin}/live',
      cancel: cancel,
    );
    return PandaLiveApi.livePage(response.text, page: page, status: response.status);
  }

  /// Page [page] of the public directory; [pageSize] is not sent (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page)).rooms;

  /// As [getRecommendRooms], for the public area.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page, category: category)).rooms;

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search, in its order:
  /// - a page below 1 or a [pageSize] below 1 finds nothing;
  /// - a room link (see [roomIdFromUrl]) finds that broadcaster, live or
  ///   not, on page 1 (one `member/bj`; nothing when there is no such
  ///   broadcaster);
  /// - another URL, or a keyword shorter than 2 or longer than 100
  ///   characters, finds nothing;
  /// - on page 1, a keyword that is a broadcaster id finds that broadcaster
  ///   alone when it exists; when it does not (HTTP 400 `NotFound`, which
  ///   3.x mistook for a broken answer and failed the search:
  ///   REG-PANDALIVE-001) the search goes on;
  /// - the BJ search, then the LIVE search, one after the other (the
  ///   gateway was seen to stall one of two parallel POSTs), each with its
  ///   own offset: `ceil(pageSize / 2)` live rows (none for a page of one)
  ///   and the rest broadcasters, at most 50 each. Live cards come first, a
  ///   broadcaster once. One source failing leaves the other's rows; both
  ///   failing, or no row and a failure, is the failure.
  ///
  /// A page over 1000 or a keyword with a control character is a caller
  /// error (3.x refused both sources before any request).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1) return const [];
    final query = keyword.trim();
    final linked = roomIdFromUrl(query);
    if (linked != null) {
      if (page > 1) return const [];
      try {
        return [await _refresh(linked, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (Uri.tryParse(query)?.hasScheme ?? false) return const [];
    if (query.length < PandaLiveApi.minKeywordLength || query.length > PandaLiveApi.maxKeywordLength) {
      return const [];
    }
    final exact = PandaLiveApi.normalizeUserId(query);
    if (page == 1 && exact != null) {
      try {
        return [await _refresh(exact, cancel: cancel)];
      } on NotFound {
        // Not a broadcaster id after all: search it.
      }
    }
    PandaLiveApi.checkPage(page);
    PandaLiveApi.checkKeyword(query);
    final liveSize = pageSize > 1 ? (pageSize + 1) ~/ 2 : 0;
    final broadcasterSize = (pageSize - liveSize).clamp(1, PandaLiveApi.maxSourceSize);
    LiveDirectoryPage? broadcasters;
    LiveDirectoryPage? live;
    SiteError? broadcasterError;
    SiteError? liveError;
    try {
      final response = await _post(
        '/v1/live/bj_list',
        PandaLiveApi.broadcasterSearchForm(query, page: page, size: broadcasterSize),
        referer: PandaLiveApi.searchReferer('bj', query),
        cancel: cancel,
      );
      broadcasters = PandaLiveApi.broadcasterPage(
        response.text,
        page: page,
        size: broadcasterSize,
        status: response.status,
      );
    } on SiteError catch (error) {
      broadcasterError = error;
    }
    _checkCancelled(cancel);
    if (liveSize > 0) {
      final size = liveSize.clamp(1, PandaLiveApi.maxSourceSize);
      try {
        final response = await _post(
          '/v1/live/index',
          PandaLiveApi.liveSearchForm(query, page: page, size: size),
          referer: PandaLiveApi.searchReferer('live', query),
          cancel: cancel,
        );
        live = PandaLiveApi.livePage(response.text, page: page, size: size, status: response.status);
      } on SiteError catch (error) {
        liveError = error;
      }
    }
    _checkCancelled(cancel);
    final failure = liveError ?? broadcasterError;
    if (live == null && broadcasters == null) throw failure!;
    final seen = <String>{};
    final rooms = [
      for (final room in [...?live?.rooms, ...?broadcasters?.rooms])
        if (seen.add(room.roomId.toLowerCase())) room,
    ];
    if (rooms.isEmpty && failure != null) throw failure;
    return List.unmodifiable(rooms);
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a broadcaster id; anything else is `NotFound` without a
  /// request (3.x refused it as an identity error).
  static String _checkedId(String roomId) =>
      PandaLiveApi.normalizeUserId(roomId) ?? (throw NotFound(_site, 'not a broadcaster id: $roomId'));

  Future<PandaLiveMember> _member(String userId, {CancelToken? cancel}) async {
    final response = await _post(
      '/v1/member/bj',
      PandaLiveApi.memberForm(userId),
      referer: PandaLiveApi.roomUrl(userId),
      cancel: cancel,
    );
    return PandaLiveApi.member(response.text, userId: userId, status: response.status);
  }

  /// The follow-refresh room of [userId]: one `member/bj`.
  Future<LiveRoom> _refresh(String userId, {CancelToken? cancel}) async =>
      PandaLiveApi.refreshRoom(await _member(userId, cancel: cancel));

  /// Room entry (3.x's `room` with media): `member/bj`; while the
  /// broadcaster is listed as live, `live/play` and, for a playable
  /// broadcast, its IVS master, read once (its token is single use:
  /// REG-PANDALIVE-002) and turned into qualities whose lines are the
  /// variant playlists ([PandaLiveRoomData]). A broadcast that cannot be
  /// played (ended, adult, password, no HLS, no video, master gone) is
  /// entered; its stream says why. A master that is refused or unreadable
  /// fails the entry, as in 3.x.
  Future<LiveRoom> _entered(String roomId) async {
    final userId = _checkedId(roomId);
    final member = await _member(userId);
    if (member.media == null) {
      return PandaLiveApi.profileRoom(member).copyWith(
        data: PandaLiveRoomData(
          userId: userId,
          userIndex: member.index,
          unavailable: const StreamUnavailable(_site, 'member/bj: not live'),
        ),
      );
    }
    final referer = PandaLiveApi.roomUrl(userId);
    final answer = await _post('/v1/live/play', PandaLiveApi.playForm(userId), referer: referer);
    final play = PandaLiveApi.play(answer.text, member: member, status: answer.status);
    final (:room, :unavailable) = PandaLiveApi.playRoom(member, play);
    PandaLiveRoomData data({List<LivePlayQuality> qualities = const [], SiteError? unavailable}) => PandaLiveRoomData(
      userId: userId,
      userIndex: member.index,
      qualities: qualities,
      unavailable: unavailable,
      chatChannel: play.isLive ? play.chatChannel : null,
      chatToken: play.isLive ? play.chatToken : null,
    );
    if (unavailable != null) return room.copyWith(data: data(unavailable: unavailable));
    final master = play.master!;
    final issuedAt = _now();
    final response = await _send(
      LiveRequest(site: _site, url: master, headers: PandaLiveApi.headers(referer), followRedirects: false),
    );
    try {
      final qualities = PandaLiveApi.qualities(
        PandaLiveApi.master(response.text, status: response.status),
        master: master,
        userId: userId,
        issuedAt: issuedAt,
      );
      return room.copyWith(data: data(qualities: qualities));
    } on StreamUnavailable catch (error) {
      return room.copyWith(data: data(unavailable: error));
    }
  }

  /// The room with its qualities (see [_entered]).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId);

  /// Follow-card refresh: one `member/bj`, as in 3.x; no `live/play`.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async =>
      PandaLiveApi.refreshRoom(await _member(_checkedId(roomId)));

  /// Room entry's answer (the qualities included), as 3.x's recorder asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  /// Whether the refresh detail says live; a failed request is an error,
  /// never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities (see [PandaLiveApi.qualities]) from the data room
  /// entry brought: no request. A room without it (a list card, a refreshed
  /// follow) is entered first; one the platform called offline has no
  /// stream (`StreamUnavailable`, without a request). A room that cannot be
  /// played says why.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      PandaLiveApi.playQualities(await _stream(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The variant playlist of [quality], with the media headers and its
  /// lease.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => PandaLiveApi.resolution(await _stream(detail, fresh: false), quality);

  /// Room entry again (3.x): a new `live/play` and master. A quality the
  /// broadcast no longer offers is `StreamUnavailable`; the old lines are
  /// never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => PandaLiveApi.resolution(await _stream(detail, fresh: true), quality);

  Future<PandaLiveRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a PandaTV room');
    if (!fresh) {
      if (detail.data case final PandaLiveRoomData data when data.userId.toLowerCase() == detail.roomId.toLowerCase()) {
        return data;
      }
      if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
      }
    }
    return (await _entered(detail.roomId)).data! as PandaLiveRoomData;
  }

  // Links ---------------------------------------------------------------------

  /// A live or channel page (see [PandaLiveApi.roomIdFromUrl]), without a
  /// request. PandaTV has no short links.
  @override
  String? roomIdFromUrl(String url) => PandaLiveApi.roomIdFromUrl(url);
}
