import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/tiktok/tiktok_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'tiktok';

/// The TikTok LIVE adapter (3.x's `TikTokSite`; parsing in [TikTokApi],
/// links in [TikTokLink]).
///
/// Link-only, as in 3.x: TikTok has no anonymous directory or search, so the
/// directory is empty (with a lasting explanation) and search looks up the
/// one user a username, `@username` or link names. A room is a user: its id
/// is the lower-case username (3.x's identity), never the numeric LIVE room
/// id, which changes with every broadcast. Anonymous, like 3.x: no cookie,
/// no account, no danmaku (3.x's `EmptyDanmaku`). Requests are 3.x's, with
/// its headers and without following redirects:
/// - follow refreshes and search read the user's LIVE
///   (`api-live/user/room`), without its streams;
/// - room entry and recordings read the same answer with its streams;
///   playback uses them, recovery reads the answer again;
/// - a `share/live` link asks `webcast/room/info` for its owner first.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class TikTokSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (when an answer arrived, the start of its
  /// URLs' lifetime) is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => TikTokApi.siteName;

  /// 3.x's lasting note on what the directory covers (exact accounts and
  /// links; the public directory needs a web session).
  @override
  String get directoryNoticeKey => 'tiktok_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers (the Referer is [username]'s room),
  /// redirects not followed (as 3.x). A cancellation before the request or
  /// while it runs is a cancelled `TransportFailure`, also when the answer
  /// (or a transport failure) arrived meanwhile; other transport failures
  /// are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {String? username, CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: TikTokApi.requestHeaders(username: username),
          followRedirects: false,
          cancel: cancel,
        ),
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

  /// The username a room id names (3.x trimmed and lower-cased it); anything
  /// else is `NotFound` without a request.
  static String _username(String roomId) =>
      TikTokLink.normalizeUsername(roomId) ?? (throw NotFound(_site, 'not a TikTok username: $roomId'));

  /// The user's LIVE as the room [roomId] (see [TikTokApi.room]).
  Future<LiveRoom> _room(String roomId, {required bool includeMedia, CancelToken? cancel}) async {
    final username = _username(roomId);
    final response = await _get(TikTokApi.userRoomUrl(username), username: username, cancel: cancel);
    return TikTokApi.room(
      response.text,
      username: username,
      includeMedia: includeMedia,
      issuedAt: _now(),
      status: response.status,
    );
  }

  /// The username owning LIVE room [liveRoomId] (`room/info`).
  Future<String> _owner(String liveRoomId, {CancelToken? cancel}) async {
    final response = await _get(TikTokApi.roomInfoUrl(liveRoomId), cancel: cancel);
    return TikTokApi.owner(response.text, liveRoomId: liveRoomId, status: response.status);
  }

  // Directory -----------------------------------------------------------------

  /// Always empty: no public directory is reachable anonymously (3.x shows
  /// [directoryNoticeKey] instead). Only recommendation pages exist; a page
  /// below 1 or a category is a caller error, as 3.x refused them. Nothing
  /// is requested.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (category != null) throw ArgumentError.value(category, 'category', 'TikTok has no categories');
    return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
  }

  /// Empty, as the directory (3.x also answered bad pages with nothing).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async => const [];

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// The one user [keyword] names (3.x's exact lookup, see
  /// [TikTokLink.lookup]), on page 1 only: a username with or without `@`
  /// or a user link reads the user's LIVE (one request); a `share/live`
  /// link asks for its owner first (two). Other keywords, a short link,
  /// later pages and a page size below 1 give nothing without a request. A
  /// user or LIVE room the site does not know gives nothing; every other
  /// failure is thrown, as in 3.x. The card is a follow refresh's (no
  /// streams).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    if (page != 1 || pageSize < 1) return const [];
    final link = TikTokLink.lookup(keyword);
    if (link == null) return const [];
    try {
      final username = switch (link.kind) {
        TikTokLinkKind.username => link.id,
        TikTokLinkKind.liveRoom => await _owner(link.id, cancel: cancel),
      };
      return [await _room(username, includeMedia: false, cancel: cancel)];
    } on NotFound {
      return const [];
    }
  }

  // Rooms ---------------------------------------------------------------------

  /// Room entry: one request, with the streams in its [TikTokRoomData]. A
  /// live room without a stream is still returned; playing it is
  /// `StreamUnavailable`.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _room(roomId, includeMedia: true);

  /// Follow refresh: the same one request without reading the streams
  /// (3.x); `mergeFrom` keeps the rest.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _room(roomId, includeMedia: false);

  /// The room a recording starts from, as room entry; a live room without a
  /// stream is `StreamUnavailable` here already (3.x). Offline and banned
  /// rooms are returned as they are.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) async {
    final room = await _room(roomId, includeMedia: true);
    final data = room.data! as TikTokRoomData;
    if (data.state == TikTokState.live && data.streams.isEmpty) throw TikTokApi.unplayable(data)!;
    return room;
  }

  /// Whether the user is live (the refresh request). A state 3.x did not
  /// know is no answer (3.x threw): `StreamUnavailable`. A restricted LIVE
  /// is not live (3.x).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _room(roomId, includeMedia: false);
    if (room.isLiveStatusPending) throw StreamUnavailable(_site, '@${room.roomId}: state not known');
    return room.isLiveNow;
  }

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities of the streams [detail] carries; a room without them
  /// (a list card, a follow) is entered first (one request). A room known to
  /// be offline or banned is refused without a request, and so is a LIVE
  /// that cannot be played (see [TikTokApi.unplayable]; 3.x listed nothing).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      TikTokApi.qualities(await _playable(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] in the streams [detail] carries (no request when
  /// it has them, as 3.x).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => TikTokApi.resolution(await _playable(detail, fresh: false), quality);

  /// Recovery reads the user's LIVE again, as 3.x did; the quality must still
  /// be offered (no silent switch).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => TikTokApi.resolution(await _playable(detail, fresh: true), quality);

  /// The streams of [detail]'s LIVE, playable: what [detail] already says
  /// first (an offline room is `StreamUnavailable`, a banned one `NeedsLogin`,
  /// its own data's reason), without a request; then its own data, or when
  /// it has none (or [fresh]) the answer now.
  Future<TikTokRoomData> _playable(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a TikTok room');
    final username = _username(detail.roomId);
    switch (detail.effectiveLiveStatus) {
      case LiveStatus.offline:
        throw StreamUnavailable(_site, '@$username is offline');
      case LiveStatus.banned:
        throw NeedsLogin(_site, '@$username is restricted');
      case LiveStatus.live || LiveStatus.replay || LiveStatus.unknown:
        break;
    }
    final known = detail.data;
    if (known is TikTokRoomData && known.username == username) {
      if (TikTokApi.unplayable(known) case final error?) throw error;
      if (!fresh) return known;
    }
    final data = (await _room(username, includeMedia: true)).data! as TikTokRoomData;
    if (TikTokApi.unplayable(data) case final error?) throw error;
    return data;
  }

  // Links ---------------------------------------------------------------------

  /// A user link (`tiktok.com/@<user>`, `/@<user>/live`), without a request
  /// (see [TikTokLink.parse]).
  @override
  String? roomIdFromUrl(String url) {
    final link = TikTokLink.parse(url);
    return link?.kind == TikTokLinkKind.username ? link!.id : null;
  }

  /// A `share/live/<LIVE room id>` link, whose owner needs a request, and
  /// the share short links ([TikTokLink.shortLink]).
  @override
  bool needsResolving(String url) =>
      TikTokLink.parse(url)?.kind == TikTokLinkKind.liveRoom || TikTokLink.shortLink(url) != null;

  /// A short link: one redirect, not followed, its target parsed again by
  /// any platform (3.x). A `share/live` link: its owner from one
  /// `room/info` through [session]; null when that fails (3.x's import
  /// reported the failure the same way).
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    if (TikTokLink.shortLink(url) case final short?) {
      final response = await session.get(short, headers: const {'user-agent': TikTokApi.userAgent});
      final target = ShortLinkSession.redirectTarget(short, response);
      return target == null ? null : LinkRedirect(target);
    }
    final link = TikTokLink.parse(url);
    if (link == null || link.kind != TikTokLinkKind.liveRoom) return null;
    final response = await session.get(
      TikTokApi.roomInfoUrl(link.id),
      readBody: true,
      headers: TikTokApi.requestHeaders(),
    );
    if (response == null) return null;
    try {
      return LinkRoom(TikTokApi.owner(response.text, liveRoomId: link.id, status: response.status));
    } on SiteError {
      return null;
    }
  }
}
