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

/// Search sessions kept (the oldest is dropped first).
const _searchLimit = 16;

/// Remembered broadcasts kept (the oldest is dropped first).
const _broadcastLimit = 256;

/// The pages of one keyword's search: the continuation of each page after
/// the first, and the channels already shown (one card per channel across
/// the pages).
final class _SearchSession {
  final Map<int, String> cursors = {};
  final Set<String> seen = {};
}

/// The YouTube Live adapter (3.x's `YouTubeSite`; parsing in [YouTubeApi]).
///
/// A room is a channel (23-1), identified by its channel id (`UC…`): its
/// current broadcast is found on every visit, and a channel that is not live
/// shows its name. The 11-character video id 3.x stored (one broadcast) is
/// still accepted everywhere and comes back as its channel's room;
/// [resolveRoomId] gives the new id alone, for the migration (M9). Requests
/// are anonymous, with 3.x's headers and the consent cookie `SOCS=CAI`, as
/// `youtube` so the app routes them through the platform's proxy:
/// - room entry and recording read the full page (a channel's `/live` page,
///   which is the watch page of its broadcast, or a video's watch page), the
///   ANDROID `player` answer and the HLS master: three requests while live,
///   as in 3.x; a channel that is not live is its page alone;
/// - a follow refresh reads no page (23-6): `navigation/resolve_url` names
///   the broadcast, `player` gives its state and `updated_metadata` the
///   live viewer count;
/// - recommendations are the "Live" destination page and keyword search is
///   the live search, paged along its continuations (23-2); an exact
///   reference (a link, `@handle`, channel or video id) is looked up;
/// - recovery asks the `player` answer and the HLS master again (3.x read
///   the watch page as well).
///
/// A broadcast a list card or room entry showed for a channel is
/// remembered for [broadcastLifetime], so entering the channel then opens
/// that broadcast even when the channel has several on air. No login, no
/// cookie; the chat (M5) gets [YouTubeDanmakuArgs]. Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class YouTubeSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSearchPaginationPolicy,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter. A broadcast shown for a channel is remembered for
  /// [broadcastLifetime] (zero turns it off), timed by [clock].
  new(this.http, {this.broadcastLifetime = const Duration(minutes: 30), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// How long the broadcast a card or room entry showed for a channel is
  /// the one entering the channel opens (a channel may have several live
  /// broadcasts; its `/live` page names only one).
  final Duration broadcastLifetime;

  final DateTime Function() _clock;

  /// The InnerTube key of the last watch page (the recovery and the refresh
  /// have no page).
  String _apiKey = YouTubeApi.fallbackApiKey;

  /// The broadcast last shown for each channel, and when.
  final Map<String, ({String videoId, DateTime at})> _broadcasts = {};

  /// The keyword searches, by keyword.
  final Map<String, _SearchSession> _searches = {};

  @override
  String get id => _site;

  @override
  String get name => 'YouTube Live';

  /// 3.x's text key for the directory's scope note. Its 3.x text (exact
  /// references only, a catalog and keyword paging to follow) no longer
  /// holds: the recommendations are the "Live" destination and search pages
  /// through live broadcasts (23-2). The text is M13's to rewrite.
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

  /// A web client InnerTube request.
  Future<LiveResponse> _post(String endpoint, Map<String, Object?> body, {CancelToken? cancel}) => _send(
    LiveRequest.json(
      site: _site,
      url: YouTubeApi.apiUrl(endpoint),
      json: body,
      headers: YouTubeApi.apiHeaders,
      timeout: _timeout,
      cancel: cancel,
    ),
  );

  /// The watch page of [videoId]; its key is kept for the requests without
  /// a page.
  Future<YouTubeWatchPage> _page(String videoId) async {
    final response = await _get(Uri.parse(YouTubeLink.videoUrl(videoId)), YouTubeApi.pageHeaders(videoId));
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
  Future<YouTubeVideo> _video(String videoId) async {
    final page = await _page(videoId);
    return YouTubeApi.video(page: page, player: await _player(videoId, page.apiKey), videoId: videoId);
  }

  /// The player answer alone (a refresh, a search card).
  Future<YouTubeVideo> _playerVideo(String videoId, {CancelToken? cancel}) async => YouTubeApi.video(
    page: YouTubeWatchPage.empty,
    player: await _player(videoId, _apiKey, cancel: cancel),
    videoId: videoId,
  );

  /// What `navigation/resolve_url` says [url] names.
  Future<({String? videoId, String? channelId})> _resolve(String url, {CancelToken? cancel}) async {
    final response = await _post('navigation/resolve_url', YouTubeApi.resolveBody(url), cancel: cancel);
    return YouTubeApi.resolved(response.text, status: response.status);
  }

  /// The room of [video] (live) with the viewer count of `updated_metadata` (23-6); a
  /// failed count leaves it empty rather than failing the room.
  Future<LiveRoom> _withViewers(YouTubeVideo video, {CancelToken? cancel}) async {
    final int? viewers;
    try {
      final response = await _post('updated_metadata', YouTubeApi.metadataBody(video.videoId), cancel: cancel);
      viewers = YouTubeApi.viewers(response.text, status: response.status);
    } on SiteError {
      return video.room;
    }
    if (viewers == null) return video.room;
    return video.room.copyWith(watching: '$viewers', onlineViewers: '$viewers');
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
          final response = await _get(master, YouTubeApi.mediaHeaders(video.videoId));
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

  /// A room id: a channel id, or a video id 3.x stored; anything else is
  /// `NotFound` without a request (3.x: `identity`).
  static String _roomId(String roomId) {
    final id = roomId.trim();
    if (YouTubeApi.isChannelId(id) || YouTubeApi.isVideoId(id)) return id;
    throw NotFound(_site, 'not a channel or video id: "$id"');
  }

  // Remembered broadcasts ------------------------------------------------------

  void _remember(String channelId, String videoId) {
    if (broadcastLifetime <= Duration.zero) return;
    _broadcasts
      ..remove(channelId)
      ..[channelId] = (videoId: videoId, at: _clock());
    if (_broadcasts.length > _broadcastLimit) _broadcasts.remove(_broadcasts.keys.first);
  }

  void _rememberListing(YouTubeListing listing) {
    for (final (index, room) in listing.rooms.indexed) {
      _remember(room.roomId, listing.videoIds[index]);
    }
  }

  String? _remembered(String channelId) {
    final entry = _broadcasts[channelId];
    if (entry == null) return null;
    if (_clock().difference(entry.at) < broadcastLifetime) return entry.videoId;
    _broadcasts.remove(channelId);
    return null;
  }

  // Catalog, directory and search ---------------------------------------------

  /// The "Live" destination page (23-2): one page of live broadcasts, one
  /// card per channel (the room is the channel, the card shows the
  /// broadcast). Only page 1 exists (the destination has no continuation);
  /// later pages are empty without a request. A page below 1 or an area is a
  /// caller error.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (category != null) throw ArgumentError.value(category, 'category', 'YouTube has no areas');
    if (page > 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final response = await _post('browse', YouTubeApi.browseBody(), cancel: cancel);
    final listing = YouTubeApi.listing(response.text, search: false, status: response.status);
    _rememberListing(listing);
    return LiveDirectoryPage(rooms: listing.rooms, page: 1, hasMore: false);
  }

  /// The directory's page [page] (23-2; 3.x had none), whatever [pageSize].
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page < 1 ? 1 : page)).rooms;

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Rooms for [keyword] (23-2):
  /// - an exact reference ([YouTubeLink.parseOrReference]: a link,
  ///   `@handle`, channel id) is its channel's room as one card, on page 1
  ///   only; a bare video id too, but one naming no video falls back to the
  ///   keyword search;
  /// - anything else is YouTube's live search, page by page along its
  ///   continuations (the site's page of about 20, whatever [pageSize]);
  ///   page 1 starts over, a later page needs the one before it, and a
  ///   channel shown on an earlier page is left out.
  ///
  /// A blank keyword, a page size below 1 or a page below 1 gives nothing
  /// without a request; a reference naming nothing gives nothing. Cards are
  /// refresh-depth rooms (no streams).
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final text = keyword.trim();
    if (text.isEmpty || page < 1 || pageSize < 1) return const [];
    final reference = YouTubeLink.parseOrReference(text);
    if (reference != null) {
      final exact = _isExact(text, reference);
      if (exact && page != 1) return const [];
      if (page == 1) {
        final room = await _lookup(reference, cancel: cancel);
        if (room != null) return [room];
        if (exact) return const [];
      }
    }
    return await _keywordSearch(text, page, cancel: cancel);
  }

  static bool _isExact(String text, YouTubeLink reference) =>
      reference.kind == YouTubeLinkKind.channel || YouTubeLink.parse(text) != null;

  /// Exact references have one page; keywords (and bare video ids, which
  /// may be words) are paged.
  @override
  bool supportsSearchPaginationFor(String keyword) {
    final text = keyword.trim();
    if (text.isEmpty) return false;
    final reference = YouTubeLink.parseOrReference(text);
    return reference == null || !_isExact(text, reference);
  }

  /// The room [reference] names at refresh depth (a channel not live has its
  /// feed's name), or null when it names nothing.
  Future<LiveRoom?> _lookup(YouTubeLink reference, {CancelToken? cancel}) async {
    try {
      final room = reference.kind == YouTubeLinkKind.video
          ? await _refreshRoom(reference.id, named: true, cancel: cancel)
          : await _refreshChannel(reference.id, channelId: reference.channelId, named: true, cancel: cancel);
      if (room.isLiveNow) {
        final shown = YouTubeLink.parse(room.link ?? '');
        if (shown?.kind == YouTubeLinkKind.video) _remember(room.roomId, shown!.id);
      }
      return room;
    } on NotFound {
      return null;
    }
  }

  Future<List<LiveRoom>> _keywordSearch(String text, int page, {CancelToken? cancel}) async {
    final _SearchSession session;
    final Map<String, Object?> body;
    if (page == 1) {
      session = _SearchSession();
      body = YouTubeApi.searchBody(text);
    } else {
      final known = _searches[text];
      final cursor = known?.cursors[page];
      if (known == null || cursor == null) return const [];
      session = known;
      body = YouTubeApi.continuationBody(cursor);
    }
    final response = await _post('search', body, cancel: cancel);
    final listing = YouTubeApi.listing(response.text, search: true, status: response.status);
    if (page == 1) {
      _searches
        ..remove(text)
        ..[text] = session;
      if (_searches.length > _searchLimit) _searches.remove(_searches.keys.first);
    }
    final next = listing.next;
    if (next != null) session.cursors[page + 1] = next;
    final rooms = <LiveRoom>[];
    for (final (index, room) in listing.rooms.indexed) {
      if (!session.seen.add(room.roomId)) continue;
      rooms.add(room);
      _remember(room.roomId, listing.videoIds[index]);
    }
    return rooms;
  }

  // Rooms ---------------------------------------------------------------------

  /// Room entry of [roomId]: a channel opens the broadcast remembered for
  /// it, else the one its `/live` page names; a video id opens that video
  /// while it is live, else its channel's current state. A live room reads
  /// its sources into [YouTubeRoomData]; when they cannot be read, or the
  /// broadcast is restricted (23-5), the room still opens and the qualities
  /// report why.
  Future<LiveRoom> _enter(String roomId) async {
    final id = _roomId(roomId);
    if (YouTubeApi.isVideoId(id)) return await _enterVideo(id);
    final remembered = _remembered(id);
    if (remembered != null) return await _enterVideo(remembered, channelId: id);
    return await _enterChannel(id);
  }

  /// The watch page and player answer of [videoId] (3.x's two requests);
  /// live, its sources too. Otherwise the channel may be live with another
  /// broadcast: its `/live` page is read as well (a video id 3.x stored, or
  /// a remembered broadcast that ended). A remembered broadcast of another
  /// channel than [channelId] is ignored.
  Future<LiveRoom> _enterVideo(String videoId, {String? channelId}) async {
    final YouTubeVideo video;
    try {
      video = await _video(videoId);
    } on NotFound {
      if (channelId == null) rethrow;
      return await _enterChannel(channelId);
    }
    if (channelId != null && video.channelId != channelId) return await _enterChannel(channelId);
    if (video.room.isLiveNow) return await _withStreams(video);
    return await _enterChannel(video.channelId, known: video);
  }

  /// The channel's `/live` page: the watch page of the broadcast it names
  /// (then its player answer and, live, the HLS master), or the channel page
  /// (its name, avatar and description, 23-1). A broadcast of another
  /// channel is not this channel's. A page naming neither is `NotFound`
  /// (YouTube's "This channel does not exist.").
  Future<LiveRoom> _enterChannel(String channelId, {YouTubeVideo? known}) async {
    final response = await _get(Uri.parse(YouTubeApi.liveUrl(channelId)), YouTubeApi.pageHeaders(''));
    final live = YouTubeApi.channelLive(response.text, finalUrl: response.url, status: response.status);
    _apiKey = live.page.apiKey;
    final videoId = live.videoId;
    if (videoId != null) {
      final YouTubeVideo video;
      if (videoId == known?.videoId) {
        video = known!;
      } else {
        final page = live.page.forVideo(videoId);
        video = YouTubeApi.video(page: page, player: await _player(videoId, page.apiKey), videoId: videoId);
      }
      if (video.channelId == channelId) return video.room.isLiveNow ? await _withStreams(video) : video.room;
    }
    final channel = YouTubeApi.channel(live.page);
    if (channel != null) {
      if (channel.channelId != channelId) {
        throw ApiChanged(_site, 'channel page: asked for $channelId, answered ${channel.channelId}');
      }
      return YouTubeApi.offlineRoom(channel);
    }
    if (known != null) return known.room;
    throw NotFound(_site, 'channel $channelId: no channel page');
  }

  /// [video] (live) with its sources, or the reason it has none.
  Future<LiveRoom> _withStreams(YouTubeVideo video) async {
    _remember(video.channelId, video.videoId);
    YouTubeRoomData data;
    final restricted = video.streamError;
    if (restricted != null) {
      data = YouTubeRoomData(channelId: video.channelId, videoId: video.videoId, streamError: restricted);
    } else {
      try {
        data = YouTubeRoomData(channelId: video.channelId, videoId: video.videoId, streams: await _streams(video));
      } on SiteError catch (error) {
        data = YouTubeRoomData(channelId: video.channelId, videoId: video.videoId, streamError: error);
      }
    }
    return video.room.copyWith(data: data);
  }

  /// A refresh of [roomId] without any page (23-6): a channel is
  /// [_refreshChannel]; a video id is its player answer, live with the
  /// viewer count, otherwise its channel's current state.
  Future<LiveRoom> _refreshRoom(String roomId, {bool viewers = true, bool named = false, CancelToken? cancel}) async {
    final id = _roomId(roomId);
    if (YouTubeApi.isChannelId(id)) {
      return await _refreshChannel('channel/$id', channelId: id, viewers: viewers, named: named, cancel: cancel);
    }
    final video = await _playerVideo(id, cancel: cancel);
    if (video.room.isLiveNow) return viewers ? await _withViewers(video, cancel: cancel) : video.room;
    return await _refreshChannel(
      'channel/${video.channelId}',
      channelId: video.channelId,
      known: video,
      viewers: viewers,
      named: named,
      cancel: cancel,
    );
  }

  /// The channel at [path] (`channel/UC…`, `@handle`, `c/<name>`,
  /// `user/<name>`) without any page: `navigation/resolve_url` of its
  /// `/live` path names its broadcast (on air, or the next one) or the
  /// channel; a broadcast's player answer gives the state, live the viewer
  /// count too ([viewers]). A channel that is not live has no name here
  /// (a follow keeps its own) unless [named] (its feed is read). A broadcast
  /// of another channel than [channelId] is not this channel's.
  Future<LiveRoom> _refreshChannel(
    String path, {
    String? channelId,
    YouTubeVideo? known,
    bool viewers = true,
    bool named = false,
    CancelToken? cancel,
  }) async {
    final target = await _resolve('${YouTubeApi.origin}/$path/live', cancel: cancel);
    final videoId = target.videoId;
    if (videoId != null) {
      final video = videoId == known?.videoId ? known! : await _playerVideo(videoId, cancel: cancel);
      if (channelId == null || video.channelId == channelId) {
        return video.room.isLiveNow && viewers ? await _withViewers(video, cancel: cancel) : video.room;
      }
    }
    final channel = target.channelId ?? channelId!;
    if (channelId != null && channel != channelId) {
      throw ApiChanged(_site, 'resolve_url: asked for $channelId, answered $channel');
    }
    if (known != null) return known.room;
    if (!named) return YouTubeApi.offlineCard(channel);
    final feed = await _get(YouTubeApi.feedUrl(channel), YouTubeApi.pageHeaders(''), cancel: cancel);
    return YouTubeApi.offlineCard(channel, name: YouTubeApi.feedName(feed.text, status: feed.status));
  }

  /// The room with its sources: three requests for a live room (page,
  /// player answer, HLS master), as in 3.x; a channel that is not live is its
  /// page alone. The room is the channel, whatever id was given.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _enter(roomId);

  /// Follow-card refresh without any page (23-6): a live channel is
  /// `navigation/resolve_url`, `player` and `updated_metadata` (three small
  /// requests; 3.x read the 1.4 MB watch page and `player`); one that is not
  /// live is `navigation/resolve_url` alone (with `player` when it names an
  /// upcoming broadcast). No avatar, area or start time (the page has
  /// them); the follow keeps what it stored.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _refreshRoom(roomId);

  /// The same requests as room entry (3.x): the recorder's qualities need
  /// no further request.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _enter(roomId);

  /// Whether the channel is live: the refresh without the viewer count (one
  /// or two small requests); a room without any playability status is
  /// `ApiChanged`, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await _refreshRoom(roomId, viewers: false);
    if (room.isLiveStatusPending) throw ApiChanged(_site, '$roomId: no playability status');
    return room.isLiveNow;
  }

  /// The room id a stored [roomId] now is (23-1, for the migration of 3.x's
  /// follows, M9): a channel id as it is, without a request; a video id
  /// becomes its channel's id from its `player` answer (one request),
  /// whether or not it is still a broadcast. A video that no longer exists
  /// is `NotFound`, a private one `NeedsLogin`; other failures are their
  /// `SiteError`s, and the video id is still accepted meanwhile.
  Future<String> resolveRoomId(String roomId, {CancelToken? cancel}) async {
    final id = _roomId(roomId);
    if (YouTubeApi.isChannelId(id)) return id;
    return YouTubeApi.channelOf(await _player(id, _apiKey, cancel: cancel), id);
  }

  // Streams -------------------------------------------------------------------

  static void _checkPlatform(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a YouTube room');
  }

  /// A room the platform said cannot play: offline (ended, upcoming, not
  /// live) is `StreamUnavailable`, banned `NeedsLogin` (or its
  /// restriction's error), a room without status `ApiChanged`; a live room
  /// with a restriction reports it (23-5).
  static void _checkPlayable(LiveRoom room) {
    switch (room.effectiveLiveStatus) {
      case LiveStatus.offline || LiveStatus.carousel:
        throw StreamUnavailable(_site, '${room.roomId} is ${room.effectiveLiveStatus.name}');
      case LiveStatus.banned:
        final restriction = room.restriction;
        if (restriction == null || restriction == LiveRestriction.none) {
          throw NeedsLogin(_site, '${room.roomId} is restricted');
        }
        throw YouTubeApi.restrictionError(room, restriction);
      case LiveStatus.unknown:
        throw ApiChanged(_site, '${room.roomId}: no playability status');
      case LiveStatus.live || LiveStatus.replay:
        if (room.isRestricted) throw YouTubeApi.restrictionError(room, room.effectiveRestriction);
        return;
    }
  }

  /// The broadcast and sources of [detail]: those room entry kept; a room
  /// without them (a list card, a refreshed or stored room) makes room
  /// entry's requests (3.x could not play it). A room the platform called
  /// offline or banned has none, without a request (3.x gave an empty list).
  Future<YouTubeRoomData> _roomStreams(LiveRoom detail) async {
    _checkPlatform(detail);
    final id = _roomId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) _checkPlayable(detail);
    var data = detail.data;
    if (data is! YouTubeRoomData || !data.belongsTo(id)) {
      final room = await _enter(id);
      data = room.data;
      if (data is! YouTubeRoomData) _checkPlayable(room);
    }
    if (data is! YouTubeRoomData) throw StreamUnavailable(_site, '$id has no sources');
    final error = data.streamError;
    if (error != null) throw error;
    if (data.streams.isEmpty) throw StreamUnavailable(_site, '${data.videoId}: the player answer has no sources');
    return data;
  }

  /// 3.x's qualities (see [YouTubeApi.qualities]).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      YouTubeApi.qualities((await _roomStreams(detail)).streams);

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] (by its id, as 3.x) with 3.x's media headers
  /// (the broadcast's watch page as Referer) and the lease of each URL; a
  /// quality the room does not offer is `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = await _roomStreams(detail);
    return YouTubeApi.resolution(_offered(data.streams, quality), videoId: data.videoId);
  }

  /// Fresh URLs of the broadcast room entry opened: its `player` answer
  /// (with the key of the last watch page) and, for an HLS variant, the HLS
  /// master (3.x read the watch page too). A room without a broadcast (a
  /// card, a stored room) makes room entry's requests. The quality asked for
  /// is kept, never silently changed: one the new answer lacks, or a
  /// broadcast that ended, is an error (a new room detail follows the
  /// channel to its next broadcast).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    _checkPlatform(detail);
    final id = _roomId(detail.roomId);
    final data = detail.data;
    final videoId = data is YouTubeRoomData && data.belongsTo(id)
        ? data.videoId
        : (YouTubeApi.isVideoId(id) ? id : null);
    if (videoId == null) return await resolvePlayUrlsRaw(detail: detail, quality: quality);
    final video = YouTubeApi.video(
      page: YouTubeWatchPage.empty,
      player: await _player(videoId, _apiKey),
      videoId: videoId,
    );
    if (YouTubeApi.isChannelId(id) && video.channelId != id) {
      throw ApiChanged(_site, 'player: $videoId is not a broadcast of $id');
    }
    _checkPlayable(video.room);
    final selected = '${quality.selectionId}';
    final streams = await _streams(video, readMaster: selected.startsWith('hls:') && selected != 'hls:auto');
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

  /// The room a link names without a request: a video link's video (3.x's
  /// `YouTubeLink.parseDurableVideoId`; room entry turns it into its
  /// channel and opens that broadcast), a `channel/UC…` or
  /// `embed/live_stream?channel=UC…` link's channel (23-1).
  @override
  String? roomIdFromUrl(String url) {
    final link = YouTubeLink.parse(url);
    if (link == null) return null;
    return link.kind == YouTubeLinkKind.video ? link.id : link.channelId;
  }

  /// A channel link by handle or name (`@handle`, `c/…`, `user/…`): its
  /// channel id needs a request.
  @override
  bool needsResolving(String url) {
    final link = YouTubeLink.parse(url);
    return link?.kind == YouTubeLinkKind.channel && link!.channelId == null;
  }

  /// The channel a handle or name link names: `navigation/resolve_url` of
  /// the channel path (one small request, 23-1; 3.x read the 1.3 MB `/live`
  /// page for its current broadcast); null when YouTube knows no such
  /// channel or the request fails.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final link = YouTubeLink.parse(url);
    if (link == null || link.kind != YouTubeLinkKind.channel || link.channelId != null) return null;
    final response = await session.send(
      LiveRequest.json(
        site: _site,
        url: YouTubeApi.apiUrl('navigation/resolve_url'),
        json: YouTubeApi.resolveBody('${YouTubeApi.origin}/${link.id}'),
        headers: YouTubeApi.apiHeaders,
        timeout: _timeout,
      ),
    );
    if (response == null) return null;
    try {
      final target = YouTubeApi.resolved(response.text, status: response.status);
      return LinkRoom(target.channelId ?? target.videoId!);
    } on SiteError {
      return null;
    }
  }
}
