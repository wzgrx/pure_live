import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/youtube/youtube_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'youtube';

/// 3.x's limit for every YouTube request (receive timeout and body
/// deadline).
const _timeout = Duration(seconds: 25);

/// The YouTube Live adapter (3.x's `YouTubeSite`; parsing in [YouTubeApi]).
///
/// A room is one broadcast, identified by its 11-character video id (what
/// 3.x stored for follows); channel links name their current broadcast. The
/// requests are 3.x's, anonymous, with 3.x's headers and the consent cookie
/// `SOCS=CAI`, as `youtube` so the app routes them through the platform's
/// proxy:
/// - a room is its watch page (`INNERTUBE_API_KEY`, the web player answer,
///   the live viewer count) and the ANDROID `player` answer; room entry and
///   recordings of a live room also read the HLS master (three requests,
///   refreshes two);
/// - search looks up exactly one reference (a video id, a link or a handle),
///   a channel through its `/live` page; there is no catalog, directory or
///   recommendation list (3.x);
/// - recovery asks the `player` answer and the HLS master again (3.x read
///   the watch page as well).
///
/// No login, no cookie, no danmaku (3.x's YouTube had `EmptyDanmaku`).
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class YouTubeSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  /// The InnerTube key of the last watch page (the recovery has no page).
  String _apiKey = YouTubeApi.fallbackApiKey;

  @override
  String get id => _site;

  @override
  String get name => 'YouTube Live';

  /// 3.x's text key for the directory's scope note (exact references only,
  /// no public catalog).
  @override
  String get directoryNoticeKey => 'youtube_directory_scope';

  // Requests ------------------------------------------------------------------

  /// [request] as `youtube`. A cancellation before it or while it runs is a
  /// cancelled `TransportFailure`, also when the answer (or a transport
  /// failure) arrived meanwhile; other transport failures are
  /// `NetworkFailure`.
  Future<LiveResponse> _send(LiveRequest request) async {
    _checkCancelled(request.cancel);
    final LiveResponse response;
    try {
      response = await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(request.cancel);
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(request.cancel);
    return response;
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  Future<LiveResponse> _get(Uri url, Map<String, String> headers, {CancelToken? cancel}) =>
      _send(LiveRequest(site: _site, url: url, headers: headers, timeout: _timeout, cancel: cancel));

  /// The watch page of [videoId]; its key is kept for the recovery.
  Future<YouTubeWatchPage> _page(String videoId, {CancelToken? cancel}) async {
    final response = await _get(
      Uri.parse(YouTubeLink.videoUrl(videoId)),
      YouTubeApi.pageHeaders(videoId),
      cancel: cancel,
    );
    final page = YouTubeApi.watchPage(response.text, status: response.status);
    _apiKey = page.apiKey;
    return page;
  }

  /// The ANDROID `player` answer for [videoId] (3.x's body, with [apiKey]).
  Future<Map<String, dynamic>> _player(String videoId, String apiKey, {CancelToken? cancel}) async {
    final response = await _send(
      LiveRequest.json(
        site: _site,
        url: YouTubeApi.playerUrl(apiKey),
        json: YouTubeApi.playerBody(videoId),
        headers: YouTubeApi.playerHeaders(videoId),
        timeout: _timeout,
        cancel: cancel,
      ),
    );
    return YouTubeApi.player(response.text, status: response.status);
  }

  /// Watch page, then player answer (3.x's order: the key comes from the
  /// page).
  Future<YouTubeVideo> _video(String videoId, {CancelToken? cancel}) async {
    final page = await _page(videoId, cancel: cancel);
    return YouTubeApi.video(
      page: page,
      player: await _player(videoId, page.apiKey, cancel: cancel),
      videoId: videoId,
    );
  }

  /// The sources of a live [video]. The HLS master is read (with the media
  /// headers) when [readMaster]; when it cannot be read, or its variants
  /// are not what 3.x accepted, the master itself is the one HLS source
  /// ("HLS 自动"), as in 3.x.
  Future<List<YouTubeStream>> _streams(YouTubeVideo video, {bool readMaster = true}) async {
    final sources = YouTubeApi.sources(video);
    final hls = <YouTubeStream>[];
    final master = sources.hls;
    if (master != null) {
      if (readMaster) {
        try {
          final response = await _get(master, YouTubeApi.mediaHeaders(video.room.roomId));
          YouTubeApi.checkStatus(response.status, response.text, 'HLS master');
          hls.addAll(YouTubeApi.hlsVariants(master, response.text));
        } on SiteError {
          // The master stays playable as the automatic source.
        } on FormatException {
          // Variants 3.x did not accept: the master itself.
        }
      }
      if (hls.isEmpty) hls.add(YouTubeApi.hlsAuto(master));
    }
    return YouTubeApi.streams(hls: hls, formats: sources.formats, dash: sources.dash);
  }

  /// The video id a room id names; anything else is `NotFound` without a
  /// request (3.x: `identity`).
  static String _videoId(String roomId) =>
      YouTubeLink.normalizeVideoId(roomId) ?? (throw NotFound(_site, 'not a video id: "$roomId"'));

  // Catalog, directory and search ---------------------------------------------

  /// 3.x's directory: one empty page (YouTube has no public catalog here),
  /// without a request. A page below 1 or an area is a caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (category != null) throw ArgumentError.value(category, 'category', 'YouTube has no areas');
    return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
  }

  /// No recommendations (3.x), without a request.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async => const [];

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// The one room [keyword] names (3.x): a video id or video link directly,
  /// a handle (`@name` or a bare 3–30 character name) or channel link
  /// through the channel's `/live` page. One page only; a keyword that
  /// names nothing, a channel that is not live, a missing video or one that
  /// is not a broadcast gives nothing. The card is the refresh detail
  /// (watch page and player answer, no streams).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page != 1 || pageSize < 1) return const [];
    final reference = YouTubeLink.parseOrReference(keyword);
    if (reference == null) return const [];
    try {
      final videoId = reference.kind == YouTubeLinkKind.video
          ? reference.id
          : await _channelLive(reference, cancel: cancel);
      if (videoId == null) return const [];
      return [(await _video(videoId, cancel: cancel)).room];
    } on NotFound {
      return const [];
    }
  }

  /// The broadcast a channel's `/live` page names, or null (3.x's
  /// `resolveReference`; redirects followed as 3.x did).
  Future<String?> _channelLive(YouTubeLink channel, {CancelToken? cancel}) async {
    final response = await _get(Uri.parse(channel.url), YouTubeApi.pageHeaders(''), cancel: cancel);
    return YouTubeApi.liveVideoOfPage(response.text, finalUrl: response.url, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// The room [roomId]: watch page and player answer. On [entry] a live
  /// room also reads its sources (the HLS master) into [YouTubeRoomData];
  /// when they cannot be read the room still opens (3.x failed the room)
  /// and the qualities report why.
  Future<LiveRoom> _detail(String roomId, {required bool entry}) async {
    final videoId = _videoId(roomId);
    final video = await _video(videoId);
    if (!entry || !video.room.isLiveNow) return video.room;
    YouTubeRoomData data;
    try {
      data = YouTubeRoomData(videoId: videoId, streams: await _streams(video));
    } on SiteError catch (error) {
      data = YouTubeRoomData(videoId: videoId, streamError: error);
    }
    return video.room.copyWith(data: data);
  }

  /// The room with its sources: three requests for a live room, two
  /// otherwise (3.x).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, entry: true);

  /// Follow-card refresh: watch page and player answer only (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, entry: false);

  /// The same requests as room entry (3.x): the recorder's qualities need
  /// no further request.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, entry: true);

  /// Whether the refresh detail says live (two requests, 3.x); a room
  /// without any playability status is `ApiChanged`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _detail(roomId, entry: false);
    if (room.isLiveStatusPending) throw ApiChanged(_site, '$roomId: no playability status');
    return room.isLiveNow;
  }

  // Streams -------------------------------------------------------------------

  static void _checkPlatform(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a YouTube room');
  }

  /// A room the platform said cannot play: offline (ended, upcoming, not
  /// playable) is `StreamUnavailable`, banned (private, sign-in, age or
  /// content checks) `NeedsLogin`, a room without status `ApiChanged`.
  static void _checkPlayable(LiveRoom room) {
    switch (room.effectiveLiveStatus) {
      case LiveStatus.offline:
        throw StreamUnavailable(_site, '${room.roomId} is offline');
      case LiveStatus.banned:
        throw NeedsLogin(_site, '${room.roomId} is restricted');
      case LiveStatus.unknown:
        throw ApiChanged(_site, '${room.roomId}: no playability status');
      case LiveStatus.live || LiveStatus.replay:
        return;
    }
  }

  /// The sources of [detail]: those room entry kept; a room without them
  /// (a list card, a refreshed or stored room) makes room entry's requests
  /// (3.x could not play it). A room the platform called offline or banned
  /// has none, without a request (3.x gave an empty list).
  Future<List<YouTubeStream>> _roomStreams(LiveRoom detail) async {
    _checkPlatform(detail);
    final videoId = _videoId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) _checkPlayable(detail);
    var data = detail.data;
    if (data is! YouTubeRoomData || data.videoId != videoId) {
      final room = await _detail(videoId, entry: true);
      _checkPlayable(room);
      data = room.data;
    }
    if (data is! YouTubeRoomData) throw StreamUnavailable(_site, '$videoId has no sources');
    final error = data.streamError;
    if (error != null) throw error;
    if (data.streams.isEmpty) throw StreamUnavailable(_site, '$videoId: the player answer has no sources');
    return data.streams;
  }

  /// 3.x's qualities (see [YouTubeApi.qualities]).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      YouTubeApi.qualities(await _roomStreams(detail));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] (by its id, as 3.x) with 3.x's media headers
  /// and the lease of each URL; a quality the room does not offer is
  /// `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => YouTubeApi.resolution(_offered(await _roomStreams(detail), quality), videoId: detail.roomId);

  /// Fresh URLs: the `player` answer (with the key of the last watch page)
  /// and, for an HLS variant, the HLS master (3.x read the watch page too).
  /// The quality asked for is kept, never silently changed: one the new
  /// answer lacks, or a room that is no longer live, is an error.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    _checkPlatform(detail);
    final videoId = _videoId(detail.roomId);
    final video = YouTubeApi.video(
      page: YouTubeWatchPage.empty,
      player: await _player(videoId, _apiKey),
      videoId: videoId,
    );
    _checkPlayable(video.room);
    final id = '${quality.selectionId}';
    final streams = await _streams(video, readMaster: id.startsWith('hls:') && id != 'hls:auto');
    return YouTubeApi.resolution(_offered(streams, quality), videoId: videoId);
  }

  static YouTubeStream _offered(List<YouTubeStream> streams, LivePlayQuality quality) =>
      streams.where((stream) => stream.id == '${quality.selectionId}').firstOrNull ??
      (throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered'));

  /// `expire` of [url] (3.x); the lines carry the same lease.
  @override
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => YouTubeApi.invalidAt(url);

  /// Ten minutes before [getPlayUrlInvalidAt] (3.x).
  @override
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) =>
      YouTubeApi.invalidAt(url)?.subtract(YouTubeApi.leaseLead);

  // Links ---------------------------------------------------------------------

  /// The video of a YouTube video link (3.x's `YouTubeLink.parseDurableVideoId`),
  /// without a request.
  @override
  String? roomIdFromUrl(String url) {
    final link = YouTubeLink.parse(url);
    return link?.kind == YouTubeLinkKind.video ? link!.id : null;
  }

  /// A channel link (`@handle`, `channel/UC…`, `c/…`, `user/…`,
  /// `embed/live_stream?channel=`): its current broadcast needs a request.
  @override
  bool needsResolving(String url) => YouTubeLink.parse(url)?.kind == YouTubeLinkKind.channel;

  /// The broadcast the channel's `/live` page names (one request; a
  /// redirect is parsed again); null when the channel is not live or the
  /// page cannot be read.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final link = YouTubeLink.parse(url);
    if (link == null || link.kind != YouTubeLinkKind.channel) return null;
    final page = Uri.parse(link.url);
    final response = await session.get(page, readBody: true, headers: YouTubeApi.pageHeaders(''));
    if (response == null) return null;
    final target = ShortLinkSession.redirectTarget(page, response);
    if (target != null) return LinkRedirect(target);
    try {
      final videoId = YouTubeApi.liveVideoOfPage(response.text, finalUrl: response.url, status: response.status);
      return videoId == null ? null : LinkRoom(videoId);
    } on SiteError {
      return null;
    }
  }
}
