import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_master.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'youtube';

/// What a YouTube link names (3.x's `YouTubeLinkKind`).
enum YouTubeLinkKind {
  /// One video (a broadcast), named by its 11-character id.
  video,

  /// A channel, whose `/live` page names its current broadcast.
  channel,
}

/// A YouTube link or search reference (3.x's `YouTubeLink`): a video, or a
/// channel path (`@handle`, `channel/UC…`, `c/<name>`, `user/<name>`).
@immutable
final class YouTubeLink {
  /// Creates the link.
  const new({required this.kind, required this.id});

  /// What the link names.
  final YouTubeLinkKind kind;

  /// The video id, or the channel path.
  final String id;

  /// The page to request: the watch page of a video, the `/live` page of a
  /// channel.
  String get url => switch (kind) {
    YouTubeLinkKind.video => videoUrl(id),
    YouTubeLinkKind.channel => '${YouTubeApi.origin}/$id/live',
  };

  /// The channel id a `channel/UC…` path names, when it has the shape of
  /// one (`UC` and 22 characters); null for handles, custom names and
  /// videos, which need a request.
  String? get channelId {
    if (kind != YouTubeLinkKind.channel || !id.startsWith('channel/')) return null;
    final value = id.substring('channel/'.length);
    return YouTubeApi.isChannelId(value) ? value : null;
  }

  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _channelId = RegExp(r'^UC[A-Za-z0-9_-]{20,30}$');
  static final RegExp _plainWord = RegExp(r'^[a-z]+$');
  static final RegExp _handle = RegExp(r'^[A-Za-z0-9_.-]+$');
  static final RegExp _legacyName = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');

  /// An official YouTube link (http or https; `youtu.be`, `youtube.com`,
  /// `youtube-nocookie.com` and their subdomains; no user info, no fragment),
  /// as 3.x read it:
  /// - videos: `youtu.be/<id>`, `watch?v=<id>`, `live/<id>`, `embed/<id>`,
  ///   `v/<id>`;
  /// - channels: `embed/live_stream?channel=UC…`, `@handle`, `channel/UC…`,
  ///   `c/<name>`, `user/<name>`, each also with `/live`.
  ///
  /// Anything else (shorts, search pages, other channel tabs) is null.
  static YouTubeLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_officialHost(uri.host.toLowerCase())) {
      return null;
    }
    final List<String> segments;
    final Map<String, String> query;
    try {
      segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
      query = uri.queryParameters;
    } on FormatException {
      return null;
    }
    if (segments.any((value) => value == '.' || value == '..')) return null;
    if (uri.host.toLowerCase() == 'youtu.be') {
      return segments.length == 1 ? _video(segments.single) : null;
    }
    if (segments.length == 1 && segments.single == 'watch') return _video(query['v'] ?? '');
    if (segments.length == 2 && segments.first.toLowerCase() == 'embed' && segments[1].toLowerCase() == 'live_stream') {
      final channel = query['channel'] ?? '';
      return _channelId.hasMatch(channel) ? YouTubeLink(kind: YouTubeLinkKind.channel, id: 'channel/$channel') : null;
    }
    if (segments.length == 2 && const {'live', 'embed', 'v'}.contains(segments.first.toLowerCase())) {
      return _video(segments[1]);
    }
    final path = _channelPath(segments);
    return path == null ? null : YouTubeLink(kind: YouTubeLinkKind.channel, id: path);
  }

  /// What a search keyword names exactly (23-2): a link, else a handle
  /// written with its `@` (3 to 30 characters), else a bare channel id
  /// (`UC` and 22 characters), else a bare video id; null for a keyword to
  /// search for. 3.x also read a bare 3–30 character name as a handle (so
  /// `lofi` was the channel `@lofi`); now it is a keyword, and so is an
  /// 11-letter lower-case word (`programming`), which cannot be told from a
  /// video id by its shape and practically never is one.
  static YouTubeLink? parseOrReference(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final text = raw.trim();
    if (text.startsWith('@')) {
      final handle = normalizeHandle(text);
      return handle == null ? null : YouTubeLink(kind: YouTubeLinkKind.channel, id: '@$handle');
    }
    if (YouTubeApi.isChannelId(text)) return YouTubeLink(kind: YouTubeLinkKind.channel, id: 'channel/$text');
    final video = normalizeVideoId(text);
    if (video == null || _plainWord.hasMatch(video)) return null;
    return YouTubeLink(kind: YouTubeLinkKind.video, id: video);
  }

  /// [raw] trimmed when it is an 11-character video id, else null.
  static String? normalizeVideoId(String raw) {
    final value = raw.trim();
    return _videoId.hasMatch(value) ? value : null;
  }

  /// [raw] trimmed and without its `@` when it is a handle (3 to 30 of
  /// `A-Z a-z 0-9 _ . -`), else null.
  static String? normalizeHandle(String raw) {
    final trimmed = raw.trim();
    final value = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    if (value.length < 3 || value.length > 30) return null;
    return _handle.hasMatch(value) ? value : null;
  }

  /// The watch page of [rawVideoId]; throws [FormatException] for anything
  /// that is not a video id (3.x).
  static String videoUrl(String rawVideoId) {
    final id = normalizeVideoId(rawVideoId);
    if (id == null) throw const FormatException('Invalid YouTube video ID');
    return '${YouTubeApi.origin}/watch?v=$id';
  }

  static YouTubeLink? _video(String raw) {
    final id = normalizeVideoId(raw);
    return id == null ? null : YouTubeLink(kind: YouTubeLinkKind.video, id: id);
  }

  static String? _channelPath(List<String> segments) {
    if (segments.isEmpty || segments.length > 3) return null;
    final values = [...segments];
    if (values.last.toLowerCase() == 'live') values.removeLast();
    if (values.length == 1 && values.single.startsWith('@')) {
      final handle = normalizeHandle(values.single);
      return handle == null ? null : '@$handle';
    }
    if (values.length != 2) return null;
    final prefix = values.first.toLowerCase();
    final id = values[1];
    if (prefix == 'channel' && _channelId.hasMatch(id)) return 'channel/$id';
    if ((prefix == 'c' || prefix == 'user') && _legacyName.hasMatch(id)) return '$prefix/$id';
    return null;
  }

  static bool _officialHost(String host) =>
      host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
}

/// One playable source of a live room (3.x's `YouTubeStream`): an HLS
/// variant, the HLS master itself ("HLS 自动"), a progressive format or the
/// DASH manifest.
@immutable
final class YouTubeStream {
  /// Creates the stream.
  new({
    required this.id,
    required this.label,
    required this.protocol,
    required List<Uri> urls,
    this.codec = '',
    this.height,
    this.frameRate,
    this.bitrate,
  }) : urls = List.unmodifiable(urls);

  /// 3.x's quality id: `hls:<height>:<fps above 30, else 0>:<codec>`,
  /// `hls:auto`, `http:<itag>` or `dash:auto`.
  final String id;

  /// `1080p`, `720p60`, a progressive format's `qualityLabel`, `HLS Auto`
  /// or `DASH Auto`.
  final String label;

  /// `hls`, `http` or `dash`.
  final String protocol;

  /// `h264`, `h265`, `vp9`, `av1`, or empty when unknown.
  final String codec;

  /// Video height.
  final int? height;

  /// Frames per second.
  final double? frameRate;

  /// Bandwidth in bit/s.
  final int? bitrate;

  /// The source's URLs (one line each).
  final List<Uri> urls;
}

/// What room entry learned for playback (3.x kept its `YouTubeRoom` in
/// `data`): the live broadcast of a channel room and its sources in 3.x's
/// order, or why they could not be read (the room opens anyway; the
/// qualities report it).
@immutable
final class YouTubeRoomData {
  /// Creates the data.
  new({required this.channelId, required this.videoId, List<YouTubeStream> streams = const [], this.streamError})
    : streams = List.unmodifiable(streams);

  /// The channel (the room) the data belongs to.
  final String channelId;

  /// The broadcast on air when the room was entered.
  final String videoId;

  /// The sources, best first; empty when the player answer had none.
  final List<YouTubeStream> streams;

  /// Why the sources could not be read at room entry (a restricted
  /// broadcast, 23-5, or an unreadable answer), if they could not.
  final SiteError? streamError;

  /// Whether the data belongs to the room [roomId] (the channel, or the
  /// broadcast a 3.x id names).
  bool belongsTo(String roomId) => roomId == channelId || roomId == videoId;
}

/// What the chat connection (M5, 23-3) needs of a live channel room: the
/// room, and the broadcast on air, whose chat `next` and
/// `live_chat/get_live_chat` read. A channel that starts another broadcast
/// needs a new room detail.
@immutable
final class YouTubeDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId, required this.videoId});

  /// The channel id.
  final String roomId;

  /// The broadcast on air.
  final String videoId;

  @override
  bool operator ==(Object other) => other is YouTubeDanmakuArgs && other.roomId == roomId && other.videoId == videoId;

  @override
  int get hashCode => Object.hash(roomId, videoId);

  @override
  String toString() => 'YouTubeDanmakuArgs($roomId, $videoId)';
}

/// A channel as its page names it (`metadata.channelMetadataRenderer`).
@immutable
final class YouTubeChannel {
  /// Creates the channel.
  const new({required this.channelId, required this.name, this.avatar = '', this.description = ''});

  /// `UC…`.
  final String channelId;

  /// The channel's name.
  final String name;

  /// The channel's avatar, or empty.
  final String avatar;

  /// The channel's description, or empty.
  final String description;
}

/// The live cards of a browse or search answer (23-2), one per channel, and
/// the continuation of a search page.
@immutable
final class YouTubeListing {
  /// Creates the listing.
  new({required List<LiveRoom> rooms, required List<String> videoIds, this.next, this.liveRows = 0})
    : rooms = List.unmodifiable(rooms),
      videoIds = List.unmodifiable(videoIds);

  /// The cards: the room is the channel, the card shows its broadcast.
  final List<LiveRoom> rooms;

  /// The broadcast of each card, in the same order.
  final List<String> videoIds;

  /// The token of the next search page; null at the end.
  final String? next;

  /// Live rows in the answer, before the malformed ones and the channels
  /// seen before were dropped.
  final int liveRows;
}

/// A watch or channel page reduced to what 3.x read from it.
@immutable
final class YouTubeWatchPage {
  const new _({required this.player, required this.data, required this.apiKey, this.canonical});

  /// A page without anything (the recovery reads the player answer alone).
  static const YouTubeWatchPage empty = YouTubeWatchPage._(player: {}, data: {}, apiKey: YouTubeApi.fallbackApiKey);

  /// `ytInitialPlayerResponse` (the web client's player answer), or empty.
  final Map<String, dynamic> player;

  /// `ytInitialData`, or empty.
  final Map<String, dynamic> data;

  /// `INNERTUBE_API_KEY`, else 3.x's built-in key.
  final String apiKey;

  /// The `<link rel="canonical">` target, if any.
  final String? canonical;

  /// This page when it is the watch page of [videoId] (its player answer
  /// names it); otherwise only its key, so that another video's details,
  /// viewers and avatar are never read as [videoId]'s.
  YouTubeWatchPage forVideo(String videoId) => jsonString(_object(player['videoDetails'])['videoId']) == videoId
      ? this
      : YouTubeWatchPage._(player: const {}, data: const {}, apiKey: apiKey);
}

/// A video as 3.x read it from its watch page and the ANDROID player answer,
/// as the broadcast of its channel's room (23-1).
@immutable
final class YouTubeVideo {
  const new _({
    required this.room,
    required this.videoId,
    required this.channelId,
    required this.streamingData,
    required this.playability,
    required this.reason,
    this.streamError,
  });

  /// The channel's room showing this video (id, state, names, thumbnail,
  /// viewers), without playback data.
  final LiveRoom room;

  /// The video.
  final String videoId;

  /// Its channel: the room id.
  final String channelId;

  /// The player answer's `streamingData` (read for playback only).
  final Map<String, dynamic> streamingData;

  /// `playabilityStatus.status` (`OK`, `LIVE_STREAM_OFFLINE`, …).
  final String playability;

  /// `playabilityStatus.reason`, for diagnostics.
  final String reason;

  /// Why a live broadcast gives this client no stream (23-5): its
  /// restriction as a `SiteError`; null when it may be played.
  final SiteError? streamError;
}

/// Pure parsing of YouTube's watch pages, player answers and HLS masters
/// (3.x's `YouTubeApi`). Each function takes what a request returned and
/// gives 3.x's models or throws a `SiteError`.
abstract final class YouTubeApi {
  /// The site.
  static const String origin = 'https://www.youtube.com';

  /// Desktop Chrome 140, the UA of every 3.x YouTube request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// The public InnerTube key 3.x used when a page had none.
  static const String fallbackApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// The room notice (`youtube_chat_notice`). 3.x's text began with
  /// "YouTube Live 远端聊天尚待接入；"; live chat is shown since M5.19.
  static const String chatNotice = '仅在直播页给出同时观看人数时显示在线人数，不把累计播放量当作在线人数。';

  /// 3.x's room notice, kept for the parity tests and the 3.x migration.
  static const String legacyChatNotice = 'YouTube Live 远端聊天尚待接入；仅在直播页返回专用并发观看字段时显示当前在线，不把累计播放量当作在线人数。';

  /// The "Live" destination channel, whose page is the recommendations
  /// (23-2).
  static const String liveDestination = 'UC4R8DWoMoI7CAwX8_LjQHig';

  /// The search filter "Live" (23-2).
  static const String liveFilter = 'EgJAAQ%3D%3D';

  /// The web client's InnerTube context of `navigation/resolve_url`,
  /// `browse`, `search` and `updated_metadata` (and of the chat, M5).
  static const Map<String, Object?> webContext = {
    'client': {'clientName': 'WEB', 'clientVersion': '2.20260925.01.00', 'hl': 'en', 'gl': 'US'},
  };

  static final RegExp _channelIdPattern = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

  /// Whether [id] is a channel id (`UC` and 22 characters): the room id
  /// (23-1).
  static bool isChannelId(String id) => _channelIdPattern.hasMatch(id);

  /// Whether [id] is an 11-character video id: one broadcast, as 3.x stored
  /// it; still accepted as a room id and turned into its channel.
  static bool isVideoId(String id) => YouTubeLink._videoId.hasMatch(id);

  /// The page of [channelId] that shows its current broadcast (or the
  /// channel when it has none): the link of a channel room that is not
  /// live, and what room entry reads.
  static String liveUrl(String channelId) => '$origin/channel/$channelId/live';

  /// The link of a room: the watch page of its live broadcast, else the
  /// channel's `/live` page.
  static String roomLink(String channelId, {String? liveVideoId}) =>
      liveVideoId == null ? liveUrl(channelId) : YouTubeLink.videoUrl(liveVideoId);

  /// How long before `expire` a media URL is renewed (3.x's
  /// `getPlayUrlRefreshAt`).
  static const Duration leaseLead = Duration(minutes: 10);

  /// The label 3.x showed for the HLS master (`youtube_quality_hls_auto`).
  static const String hlsAutoLabel = 'HLS 自动';

  /// The label 3.x showed for the DASH manifest (`youtube_quality_dash_auto`).
  static const String dashAutoLabel = 'DASH 自动';

  // Requests ------------------------------------------------------------------

  /// Headers of a page request: 3.x's UA, English, the consent cookie
  /// `SOCS=CAI` (no consent page in the EU) and the video's watch page (or
  /// the site root) as Referer.
  static Map<String, String> pageHeaders(String videoId) => {
    'user-agent': userAgent,
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'cookie': 'SOCS=CAI',
    'referer': videoId.isEmpty ? '$origin/' : YouTubeLink.videoUrl(videoId),
  };

  /// Headers of the player request (the JSON content type is added by the
  /// request).
  static Map<String, String> playerHeaders(String videoId) => {
    ...pageHeaders(videoId),
    'accept': 'application/json',
    'origin': origin,
  };

  /// Media headers (3.x's `PlaybackHeaderResolver` for YouTube): UA, the
  /// watch page as Referer (the site root without a video), and Origin.
  static Map<String, String> mediaHeaders(String videoId) => {
    'origin': origin,
    'referer': videoId.isEmpty ? '$origin/' : YouTubeLink.videoUrl(videoId),
    'user-agent': userAgent,
  };

  /// Headers of the web client's InnerTube requests (the JSON content type
  /// is added by the request): the page headers with the site root as
  /// Referer, JSON and Origin.
  static Map<String, String> get apiHeaders => playerHeaders('');

  /// The web client's InnerTube endpoint [endpoint]
  /// (`navigation/resolve_url`, `browse`, `search`, `updated_metadata`).
  static Uri apiUrl(String endpoint) => Uri.parse('$origin/youtubei/v1/$endpoint?prettyPrint=false');

  /// `navigation/resolve_url` for [url]: a channel path names its channel
  /// id, a channel's `/live` path its current (or next) broadcast.
  static Map<String, Object?> resolveBody(String url) => {'context': webContext, 'url': url};

  /// `browse` of the "Live" destination (23-2).
  static Map<String, Object?> browseBody() => {'context': webContext, 'browseId': liveDestination};

  /// The first page of a live search for [query] (23-2).
  static Map<String, Object?> searchBody(String query) => {'context': webContext, 'query': query, 'params': liveFilter};

  /// A later page of a search: the previous page's continuation [token].
  static Map<String, Object?> continuationBody(String token) => {'context': webContext, 'continuation': token};

  /// `updated_metadata` of [videoId]: the live viewer count the watch page
  /// shows (23-6).
  static Map<String, Object?> metadataBody(String videoId) => {'context': webContext, 'videoId': videoId};

  /// The RSS feed of [channelId]: its name when it is not live.
  static Uri feedUrl(String channelId) =>
      Uri.parse('$origin/feeds/videos.xml').replace(queryParameters: {'channel_id': channelId});

  /// The player endpoint with [apiKey].
  static Uri playerUrl(String apiKey) =>
      Uri.parse('$origin/youtubei/v1/player').replace(queryParameters: {'key': apiKey});

  /// 3.x's player request: the ANDROID client, which answers anonymous
  /// requests with an HLS manifest (the web client needs browser proofs).
  static Map<String, Object?> playerBody(String videoId) => {
    'videoId': videoId,
    'contentCheckOk': true,
    'racyCheckOk': true,
    'context': {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '21.08.266',
        'platform': 'DESKTOP',
        'clientScreen': 'EMBED',
        'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
        'browserName': 'Chrome',
      },
      'user': {'lockedSafetyMode': false},
      'request': {'useSsl': true},
    },
  };

  /// 3.x's status rules for every request: 200 with a body is the answer;
  /// 400 and an empty body are `ApiChanged`, 401/403 `RiskControl`, 404
  /// `NotFound`, 429 `RateLimited`, 5xx and anything else (a redirect not
  /// followed, another 2xx) `NetworkFailure`.
  static void checkStatus(int status, String body, String what) {
    switch (status) {
      case 200:
        if (body.isEmpty) throw ApiChanged(_site, '$what: empty body');
        return;
      case 400:
        throw ApiChanged(_site, '$what: HTTP 400');
      case 401 || 403:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw NotFound(_site, '$what: HTTP 404');
      case 429:
        throw RateLimited(_site, detail: '$what: HTTP 429');
    }
    throw NetworkFailure(_site, '$what: HTTP $status');
  }

  // Pages ---------------------------------------------------------------------

  /// A watch or channel page: `ytInitialPlayerResponse`, `ytInitialData`,
  /// `INNERTUBE_API_KEY` and the canonical link, found as 3.x found them
  /// (the first object after each marker that is valid JSON). A page
  /// without them is not an error: the player answer alone can decide.
  static YouTubeWatchPage watchPage(String html, {int status = 200}) {
    checkStatus(status, html, 'watch page');
    return YouTubeWatchPage._(
      player: _embedded(html, 'ytInitialPlayerResponse'),
      data: _embedded(html, 'ytInitialData'),
      apiKey: RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ?? fallbackApiKey,
      canonical: _canonical.firstMatch(html)?.group(1),
    );
  }

  static final RegExp _canonical = RegExp(
    '''<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// The broadcast a channel's `/live` page names (3.x's
  /// `resolveReference`): the final URL when it is a video, else the
  /// canonical link, else the page's player when it is live, else the first
  /// video in `ytInitialData` that looks live; null when there is none (the
  /// channel is not live).
  static String? liveVideoOfPage(String html, {Uri? finalUrl, int status = 200}) =>
      channelLive(html, finalUrl: finalUrl, status: status).videoId;

  /// A channel's `/live` page: the page itself (the watch page of the
  /// broadcast it names, or the channel page) and the broadcast, found as
  /// [liveVideoOfPage] finds it.
  static ({YouTubeWatchPage page, String? videoId}) channelLive(String html, {Uri? finalUrl, int status = 200}) {
    checkStatus(status, html, 'channel page');
    final page = watchPage(html);
    final redirected = finalUrl == null ? null : YouTubeLink.parse(finalUrl.toString());
    if (redirected?.kind == YouTubeLinkKind.video) return (page: page, videoId: redirected!.id);
    final canonical = page.canonical == null ? null : YouTubeLink.parse(page.canonical!);
    if (canonical?.kind == YouTubeLinkKind.video) return (page: page, videoId: canonical!.id);
    final details = _object(page.player['videoDetails']);
    final id = YouTubeLink.normalizeVideoId(jsonString(details['videoId']) ?? '');
    if (id != null && details['isLive'] == true) return (page: page, videoId: id);
    return (page: page, videoId: _findLiveVideo(page.data));
  }

  /// The channel a channel page names (`metadata.channelMetadataRenderer`:
  /// `externalId`, `title`, `avatar`, `description`); null when the page
  /// names none (a watch page, or YouTube's "This channel does not exist.").
  static YouTubeChannel? channel(YouTubeWatchPage page) {
    final metadata = _object(_object(page.data['metadata'])['channelMetadataRenderer']);
    final id = jsonString(metadata['externalId']) ?? '';
    final name = jsonString(metadata['title']);
    if (!isChannelId(id) || name == null) return null;
    return YouTubeChannel(
      channelId: id,
      name: name,
      avatar: _thumbnail(metadata['avatar'], avatar: true),
      description: jsonString(metadata['description']) ?? '',
    );
  }

  /// The room of a channel that is not live, from its page: the name,
  /// avatar and description (23-1: "未开播时显示频道名"), no title.
  static LiveRoom offlineRoom(YouTubeChannel channel) => LiveRoom(
    roomId: channel.channelId,
    platform: _site,
    userId: channel.channelId,
    nick: channel.name,
    avatar: channel.avatar,
    introduction: channel.description,
    link: liveUrl(channel.channelId),
    liveStatus: LiveStatus.offline,
    notice: chatNotice,
    httpHeaders: mediaHeaders(''),
  );

  /// The room of a channel that `navigation/resolve_url` called not live,
  /// with its [name] when it was asked for (a search card); a follow keeps
  /// the name it stored.
  static LiveRoom offlineCard(String channelId, {String name = ''}) => LiveRoom(
    roomId: channelId,
    platform: _site,
    userId: channelId,
    nick: name,
    link: liveUrl(channelId),
    liveStatus: LiveStatus.offline,
  );

  // InnerTube (web client) -----------------------------------------------------

  static Map<String, dynamic> _json(String body, int status, String what) {
    checkStatus(status, body, what);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  }

  /// `navigation/resolve_url`: a watch endpoint names a video (a channel's
  /// `/live` path: its broadcast on air or next), a browse endpoint a
  /// channel. A path YouTube does not know is 404 (`NotFound`); one naming
  /// neither is `NotFound` too. An unknown `channel/UC…` is answered as a
  /// channel all the same (checked 2026-09-29), so only the channel page or
  /// the feed tells it apart.
  static ({String? videoId, String? channelId}) resolved(String body, {int status = 200}) {
    final endpoint = _object(_json(body, status, 'resolve_url')['endpoint']);
    final video = YouTubeLink.normalizeVideoId(jsonString(_object(endpoint['watchEndpoint'])['videoId']) ?? '');
    final channel = jsonString(_object(endpoint['browseEndpoint'])['browseId']) ?? '';
    if (video == null && !isChannelId(channel)) throw const NotFound(_site, 'resolve_url: names no channel or video');
    return (videoId: video, channelId: video == null ? channel : null);
  }

  /// The channel's name in its RSS feed (the feed's own `<title>`, before
  /// the first entry); 404 is `NotFound` (no such channel).
  static String feedName(String xml, {int status = 200}) {
    checkStatus(status, xml, 'feed');
    final end = xml.indexOf('<entry');
    final head = end < 0 ? xml : xml.substring(0, end);
    final title = RegExp('<title>([^<]*)</title>').firstMatch(head)?.group(1);
    final name = title == null ? null : jsonString(decodeHtmlEntities(title));
    if (name == null) throw ApiChanged(_site, 'feed: no title (${_snippet(xml)})');
    return name;
  }

  /// The live viewer count of an `updated_metadata` answer (its
  /// `videoViewCountRenderer`, "1,331 watching now"), or null (23-6).
  static int? viewers(String body, {int status = 200}) => _currentViewers(_json(body, status, 'updated_metadata'));

  /// The live cards of a `browse` ([search] false) or `search` answer
  /// (23-2), each a channel's room showing one broadcast:
  /// - a row is live with the live badge, the live time overlay or an
  ///   "N watching" count (ended and upcoming rows are left out);
  /// - the room is the owner's channel id, the link the broadcast's watch
  ///   page, the avatar the channel's (23-4), the audience the "watching"
  ///   count; a members-only badge marks it [LiveRestriction.subscribersOnly]
  ///   (anything else is unknown on a card);
  /// - a live row without a video id, channel id, title or name is skipped
  ///   (every live row malformed is `ApiChanged`); a channel's later rows
  ///   are left out, so a channel has one card (the first, the site's
  ///   order);
  /// - a search answer's last continuation is the next page, unless it had
  ///   no live row. A `browse` answer without any video row is `ApiChanged`.
  static YouTubeListing listing(String body, {required bool search, int status = 200}) {
    final what = search ? 'search' : 'browse';
    final root = _json(body, status, what);
    final rows = _findAll(root, 'videoRenderer');
    if (!search && rows.isEmpty) throw const ApiChanged(_site, 'browse: no video rows');
    final rooms = <LiveRoom>[];
    final videos = <String>[];
    final seen = <String>{};
    var live = 0;
    var malformed = 0;
    for (final row in rows) {
      final renderer = _object(row);
      if (!_rowLive(renderer)) continue;
      live++;
      final card = _card(renderer);
      if (card == null) {
        malformed++;
      } else if (seen.add(card.room.roomId)) {
        rooms.add(card.room);
        videos.add(card.videoId);
      }
    }
    if (live > 0 && malformed == live) throw ApiChanged(_site, '$what: all $live live rows malformed');
    String? next;
    if (search && live > 0) {
      final items = _findAll(root, 'continuationItemRenderer');
      if (items.isNotEmpty) {
        final command = _object(_object(_object(items.last)['continuationEndpoint'])['continuationCommand']);
        next = jsonString(command['token']);
      }
    }
    return YouTubeListing(rooms: rooms, videoIds: videos, next: next, liveRows: live);
  }

  static bool _rowLive(Map<String, dynamic> renderer) {
    if (renderer.containsKey('upcomingEventData')) return false;
    final badges = renderer['badges'];
    if (badges is List) {
      for (final badge in badges) {
        if (_object(_object(badge)['metadataBadgeRenderer'])['style'] == 'BADGE_STYLE_TYPE_LIVE_NOW') return true;
      }
    }
    final overlays = renderer['thumbnailOverlays'];
    if (overlays is List) {
      for (final overlay in overlays) {
        if (_object(_object(overlay)['thumbnailOverlayTimeStatusRenderer'])['style'] == 'LIVE') return true;
      }
    }
    return _watching(renderer['viewCountText']) != null;
  }

  static final RegExp _watchingCount = RegExp(r'^(\d[\d,.]*)\s*watching', caseSensitive: false);

  /// `10,366 watching` → 10366.
  static int? _watching(Object? value) {
    final match = _watchingCount.firstMatch(_text(value));
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    return digits == null || digits.isEmpty ? null : int.tryParse(digits);
  }

  static ({LiveRoom room, String videoId})? _card(Map<String, dynamic> renderer) {
    final videoId = YouTubeLink.normalizeVideoId(jsonString(renderer['videoId']) ?? '');
    final owner = renderer['ownerText'] ?? renderer['longBylineText'] ?? renderer['shortBylineText'];
    final avatar = _object(_object(renderer['channelThumbnailSupportedRenderers'])['channelThumbnailWithLinkRenderer']);
    final channelId =
        _browseId(owner) ??
        _browseId({
          'runs': [avatar],
        }) ??
        '';
    final title = _text(renderer['title']);
    final nick = _text(owner);
    if (videoId == null || !isChannelId(channelId) || title.isEmpty || nick.isEmpty) return null;
    final viewers = _watching(renderer['viewCountText']);
    final badges = renderer['badges'];
    final members =
        badges is List &&
        badges.any(
          (badge) => _object(_object(badge)['metadataBadgeRenderer'])['style'] == 'BADGE_STYLE_TYPE_MEMBERS_ONLY',
        );
    return (
      room: LiveRoom(
        roomId: channelId,
        platform: _site,
        userId: channelId,
        nick: nick,
        title: title,
        avatar: _thumbnail(avatar['thumbnail'], avatar: true),
        cover: _thumbnail(renderer['thumbnail']),
        link: YouTubeLink.videoUrl(videoId),
        liveStatus: LiveStatus.live,
        restriction: members ? LiveRestriction.subscribersOnly : null,
        watching: viewers?.toString() ?? '',
        onlineViewers: viewers?.toString() ?? '',
        audienceMetricType: AudienceMetricType.onlineViewers,
        httpHeaders: mediaHeaders(videoId),
      ),
      videoId: videoId,
    );
  }

  /// The channel a `{runs: [...]}` owner text links to.
  static String? _browseId(Object? value) {
    final runs = _object(value)['runs'];
    if (runs is! List) return null;
    for (final run in runs) {
      final endpoint = _object(_object(_object(run)['navigationEndpoint'])['browseEndpoint']);
      final id = jsonString(endpoint['browseId']);
      if (id != null && isChannelId(id)) return id;
    }
    return null;
  }

  /// Every value under [key] anywhere in [root], in document order (at most
  /// [_walkBudget] nodes visited).
  static List<Object?> _findAll(Object? root, String key) {
    final found = <Object?>[];
    var visited = 0;
    void walk(Object? value) {
      if (++visited > _walkBudget) throw ApiChanged(_site, 'answer too large looking for $key');
      if (value is List) {
        value.forEach(walk);
      } else if (value is Map) {
        for (final MapEntry(key: name, value: item) in value.entries) {
          if (name == key) found.add(item);
          walk(item);
        }
      }
    }

    walk(root);
    return found;
  }

  static String? _findLiveVideo(Object? root) {
    var visited = 0;
    String? walk(Object? value) {
      if (++visited > _walkBudget) throw const ApiChanged(_site, 'channel page: ytInitialData too large');
      if (value is List) {
        for (final item in value) {
          if (walk(item) case final match?) return match;
        }
      } else if (value is Map) {
        final id = YouTubeLink.normalizeVideoId(jsonString(value['videoId']) ?? '');
        if (id != null && _looksLive(value)) return id;
        for (final item in value.values) {
          if (walk(item) case final match?) return match;
        }
      }
      return null;
    }

    return walk(root);
  }

  static const int _walkBudget = 250000;

  /// 3.x's test for a live video renderer: a live flag, the live badge, the
  /// live time overlay, or a `LIVE` label anywhere inside it.
  static bool _looksLive(Map<dynamic, dynamic> map) {
    if (map['isLive'] == true || map['isLiveNow'] == true) return true;
    final encoded = jsonEncode(map).toLowerCase();
    return encoded.contains('badge_style_type_live_now') ||
        encoded.contains('thumbnail_overlay_time_status_style_live') ||
        encoded.contains('"label":"live"');
  }

  // Player --------------------------------------------------------------------

  /// The player answer as a JSON object.
  static Map<String, dynamic> player(String body, {int status = 200}) {
    checkStatus(status, body, 'player');
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw ApiChanged(_site, 'player: not a JSON object (${_snippet(body)})');
  }

  /// The channel's room showing [videoId], from the video's [page] (see
  /// [YouTubeWatchPage.forVideo]) and the ANDROID [player] answer, merged
  /// as 3.x merged them (the player answer's fields win).
  ///
  /// The answer must name [videoId]: one naming no video is `NotFound`
  /// (`ERROR`, a missing video), `NeedsLogin` (sign-in, age or content
  /// checks), `StreamUnavailable` (`UNPLAYABLE`) or `ApiChanged`; one naming
  /// another video, or no channel, is `ApiChanged`.
  ///
  /// The room is the video's channel (23-1): its id is the channel id, the
  /// link the watch page while live and the channel's `/live` page
  /// otherwise. States:
  /// - `isLive` (or `liveBroadcastDetails.isLiveNow`), not
  ///   `LIVE_STREAM_OFFLINE`: live, also when the client may not play it
  ///   (23-5; 3.x showed a restricted broadcast as banned and an unplayable
  ///   one as offline). The restriction is [restrictionOf] (none for `OK`),
  ///   and [YouTubeVideo.streamError] says why there is no stream;
  /// - private, sign-in, age or content checks on a video that is no
  ///   broadcast: banned, with its restriction (3.x);
  /// - anything else with a status (ended, upcoming, an ordinary video):
  ///   offline, the channel is not on air (3.x: `NotFound` for an ordinary
  ///   video, which was no room);
  /// - no status at all: unknown.
  ///
  /// Title and author are required (`ApiChanged`). Concurrent viewers come
  /// from the page's live `videoViewCountRenderer` and the start from its
  /// microformat, only while live; the avatar is the channel's from the
  /// page (23-4), empty without one (the player answer has none).
  static YouTubeVideo video({
    required YouTubeWatchPage page,
    required Map<String, dynamic> player,
    required String videoId,
  }) {
    final details = <String, dynamic>{..._object(page.player['videoDetails']), ..._object(player['videoDetails'])};
    final apiStatus = _object(player['playabilityStatus']);
    final status = jsonString(apiStatus['status']) != null ? apiStatus : _object(page.player['playabilityStatus']);
    final code = (jsonString(status['status']) ?? '').toUpperCase();
    final reason = jsonString(status['reason']) ?? '';
    final actual = YouTubeLink.normalizeVideoId(jsonString(details['videoId']) ?? '');
    if (actual == null) {
      final detail = 'player: no video for $videoId ($code $reason)'.trim();
      throw switch (code) {
        'ERROR' => NotFound(_site, detail),
        'LOGIN_REQUIRED' || 'AGE_CHECK_REQUIRED' || 'CONTENT_CHECK_REQUIRED' => NeedsLogin(_site, detail),
        'UNPLAYABLE' => StreamUnavailable(_site, detail),
        _ => ApiChanged(_site, detail),
      };
    }
    if (actual != videoId) throw ApiChanged(_site, 'player: asked for $videoId, answered $actual');
    final micro = <String, dynamic>{
      ..._object(_object(page.player['microformat'])['playerMicroformatRenderer']),
      ..._object(_object(player['microformat'])['playerMicroformatRenderer']),
    };
    final channelId = jsonString(details['channelId']) ?? jsonString(micro['externalChannelId']) ?? '';
    if (!isChannelId(channelId)) throw ApiChanged(_site, 'player: $videoId names no channel');
    final broadcast = _object(micro['liveBroadcastDetails']);
    final live = (details['isLive'] == true || broadcast['isLiveNow'] == true) && code != 'LIVE_STREAM_OFFLINE';
    final liveContent =
        live || details['isLiveContent'] == true || details['isUpcoming'] == true || broadcast.isNotEmpty;
    final lowerReason = reason.toLowerCase();
    final private = details['isPrivate'] == true;
    final restricted =
        private ||
        const {'LOGIN_REQUIRED', 'AGE_CHECK_REQUIRED', 'CONTENT_CHECK_REQUIRED'}.contains(code) ||
        lowerReason.contains('sign in') ||
        lowerReason.contains('private');
    final state = switch (code) {
      _ when live => LiveStatus.live,
      _ when restricted && !liveContent => LiveStatus.banned,
      '' when !liveContent => LiveStatus.unknown,
      _ => LiveStatus.offline,
    };
    final restriction = state == LiveStatus.live || state == LiveStatus.banned
        ? restrictionOf(code: code, reason: reason, private: private)
        : null;
    final title = _required(details['title'], 'title');
    final author = _required(details['author'], 'author');
    final thumbnail = _thumbnail(details['thumbnail'] ?? micro['thumbnail']);
    final viewers = live ? _currentViewers(page.data) : null;
    final category = jsonString(micro['category']);
    final room = LiveRoom(
      roomId: channelId,
      platform: _site,
      userId: channelId,
      nick: author,
      title: title,
      avatar: _ownerAvatar(page.data),
      cover: thumbnail,
      area: category,
      introduction: jsonString(details['shortDescription']) ?? '',
      link: roomLink(channelId, liveVideoId: live ? videoId : null),
      liveStatus: state,
      startedAt: live ? _time(broadcast['startTimestamp']) : null,
      restriction: restriction,
      watching: viewers?.toString() ?? '',
      onlineViewers: viewers?.toString() ?? '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: chatNotice,
      danmakuData: live ? YouTubeDanmakuArgs(roomId: channelId, videoId: videoId) : null,
      httpHeaders: mediaHeaders(videoId),
    );
    return YouTubeVideo._(
      room: room,
      videoId: videoId,
      channelId: channelId,
      streamingData: _object(player['streamingData']),
      playability: code,
      reason: reason,
      streamError: live && restriction != LiveRestriction.none
          ? restrictionError(room, restriction ?? LiveRestriction.unplayable, reason: reason)
          : null,
    );
  }

  /// What keeps a broadcast from this client, from the player answer's
  /// status [code] and [reason] (23-5): `OK` is none; then private,
  /// members only ([LiveRestriction.subscribersOnly]), an age check
  /// ([LiveRestriction.adult]), a country or region
  /// ([LiveRestriction.regionBlocked]), a payment or purchase
  /// ([LiveRestriction.paid]), any other sign-in or content check
  /// ([LiveRestriction.needsLogin]); anything else (`UNPLAYABLE`, `ERROR`)
  /// is [LiveRestriction.unplayable]. The reasons are English (the requests
  /// send `Accept-Language: en-US`); one not recognised falls back on the
  /// status code.
  static LiveRestriction restrictionOf({required String code, required String reason, bool private = false}) {
    final lower = reason.toLowerCase();
    if (private || lower.contains('private')) return LiveRestriction.private;
    if (code == 'OK') return LiveRestriction.none;
    if (lower.contains('member')) return LiveRestriction.subscribersOnly;
    if (code == 'AGE_CHECK_REQUIRED' || _age.hasMatch(lower)) return LiveRestriction.adult;
    if (_region.hasMatch(lower)) return LiveRestriction.regionBlocked;
    if (_payment.hasMatch(lower)) return LiveRestriction.paid;
    if (code == 'LOGIN_REQUIRED' || code == 'CONTENT_CHECK_REQUIRED' || lower.contains('sign in')) {
      return LiveRestriction.needsLogin;
    }
    return LiveRestriction.unplayable;
  }

  static final RegExp _age = RegExp(r'\bage\b|age-restricted|inappropriate for some users');
  static final RegExp _region = RegExp(r'\bcountry\b|\bregion\b|\blocation\b');
  static final RegExp _payment = RegExp(r'\bpayment\b|\bpurchase\b|\bpaid\b');

  /// The error playback reports for [room]'s [restriction] (M2.1's table):
  /// `RegionBlocked` for a region, `NeedsLogin` for sign-in and age checks,
  /// `StreamUnavailable` naming the kind (and YouTube's [reason]) for the
  /// rest.
  static SiteError restrictionError(LiveRoom room, LiveRestriction restriction, {String reason = ''}) {
    final why = reason.isEmpty ? '' : ': $reason';
    final detail = '${room.roomId} is ${restriction.name}$why';
    return switch (restriction) {
      LiveRestriction.regionBlocked => RegionBlocked(_site, detail),
      LiveRestriction.needsLogin || LiveRestriction.adult => NeedsLogin(_site, detail),
      _ => StreamUnavailable(_site, detail),
    };
  }

  /// The channel id [player] (an ANDROID player answer for [videoId])
  /// names, whether or not the video is a broadcast: the new room id of a
  /// video id 3.x stored (23-1, M9). A missing video is `NotFound`, one
  /// only signed-in viewers see `NeedsLogin`, as in [video].
  static String channelOf(Map<String, dynamic> player, String videoId) {
    final details = _object(player['videoDetails']);
    final status = _object(player['playabilityStatus']);
    final code = (jsonString(status['status']) ?? '').toUpperCase();
    final actual = YouTubeLink.normalizeVideoId(jsonString(details['videoId']) ?? '');
    if (actual == null) {
      final detail = 'player: no video for $videoId ($code)';
      throw switch (code) {
        'ERROR' => NotFound(_site, detail),
        'LOGIN_REQUIRED' || 'AGE_CHECK_REQUIRED' || 'CONTENT_CHECK_REQUIRED' => NeedsLogin(_site, detail),
        'UNPLAYABLE' => StreamUnavailable(_site, detail),
        _ => ApiChanged(_site, detail),
      };
    }
    if (actual != videoId) throw ApiChanged(_site, 'player: asked for $videoId, answered $actual');
    final channel = jsonString(details['channelId']) ?? '';
    if (!isChannelId(channel)) throw ApiChanged(_site, 'player: $videoId names no channel');
    return channel;
  }

  static String _required(Object? value, String name) {
    final text = jsonString(value);
    if (text == null || text.length > 8192) throw ApiChanged(_site, 'player: videoDetails.$name missing');
    return text;
  }

  /// An ISO 8601 time with an offset (`2026-09-23T16:47:51+00:00`) in UTC;
  /// null for anything else or before 2005.
  static DateTime? _time(Object? value) {
    final text = jsonString(value);
    if (text == null || !RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(text)) return null;
    final time = DateTime.tryParse(text)?.toUtc();
    return time == null || time.year < 2005 || time.year > 2286 ? null : time;
  }

  /// The channel avatar of a watch page (`videoOwnerRenderer.thumbnail`,
  /// 23-4); empty without one.
  static String _ownerAvatar(Map<String, dynamic> data) {
    final owners = data.isEmpty ? const <Object?>[] : _findAll(data, 'videoOwnerRenderer');
    return owners.isEmpty ? '' : _thumbnail(_object(owners.first)['thumbnail'], avatar: true);
  }

  /// The last https thumbnail on `ytimg.com` or `ggpht.com` (3.x), or also
  /// on `googleusercontent.com` for an [avatar] (channel pages serve them
  /// there); empty when there is none or the list has more than 64
  /// entries.
  static String _thumbnail(Object? value, {bool avatar = false}) {
    final items = _object(value)['thumbnails'];
    if (items is! List || items.length > 64) return '';
    for (final item in items.reversed) {
      final uri = Uri.tryParse(jsonString(_object(item)['url']) ?? '');
      final host = uri?.host.toLowerCase() ?? '';
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment &&
          (_imageHost(host) ||
              (avatar && (host == 'googleusercontent.com' || host.endsWith('.googleusercontent.com'))))) {
        return uri.toString();
      }
    }
    return '';
  }

  /// The first live `videoViewCountRenderer` (`1,256 watching now`), its
  /// digits.
  static int? _currentViewers(Object? root) {
    var visited = 0;
    int? walk(Object? value) {
      if (++visited > _walkBudget) return null;
      if (value is List) {
        for (final item in value) {
          if (walk(item) case final match?) return match;
        }
      } else if (value is Map) {
        final renderer = _object(value['videoViewCountRenderer']);
        if (renderer.isNotEmpty && renderer['isLive'] == true) {
          final digits = _runsText(renderer['viewCount']).replaceAll(RegExp('[^0-9]'), '');
          final number = int.tryParse(digits);
          if (number != null && number >= 0) return number;
        }
        for (final item in value.values) {
          if (walk(item) case final match?) return match;
        }
      }
      return null;
    }

    return walk(root);
  }

  /// The text of a `{simpleText}` or `{runs: [...]}` object, the runs joined
  /// as written (a run may start with its space), trimmed.
  static String _text(Object? value) {
    final map = _object(value);
    final simple = map['simpleText'];
    if (simple is String) return simple.trim();
    final runs = map['runs'];
    if (runs is! List) return '';
    return [
      for (final run in runs)
        if (_object(run)['text'] case final String text) text,
    ].join().trim();
  }

  static String _runsText(Object? value) {
    final map = _object(value);
    final simple = jsonString(map['simpleText']);
    if (simple != null) return simple;
    final runs = map['runs'];
    if (runs is! List) return '';
    return [for (final run in runs) jsonString(_object(run)['text']) ?? ''].join();
  }

  // Streams -------------------------------------------------------------------

  /// The sources of a live [video]'s player answer before the HLS master is
  /// read: the master, the progressive formats (at most 64; one without a
  /// plain `url`, `itag` or `qualityLabel` is skipped) and the DASH
  /// manifest. A URL that is not https on a YouTube media host is
  /// `ApiChanged` (3.x failed the room).
  static ({Uri? hls, List<YouTubeStream> formats, Uri? dash}) sources(YouTubeVideo video) {
    final streaming = video.streamingData;
    final hls = jsonString(streaming['hlsManifestUrl']);
    final formats = <YouTubeStream>[];
    final raw = streaming['formats'];
    if (raw is List && raw.length <= 64) {
      final seen = <String>{};
      for (final item in raw) {
        final format = _object(item);
        final url = jsonString(format['url']);
        final itag = jsonInt(format['itag']);
        final label = jsonString(format['qualityLabel']);
        if (url == null || itag == null || label == null || !seen.add('http:$itag')) continue;
        formats.add(
          YouTubeStream(
            id: 'http:$itag',
            label: label,
            protocol: 'http',
            codec: _codec(jsonString(format['mimeType']) ?? ''),
            height: jsonInt(format['height']),
            frameRate: _double(format['fps']),
            bitrate: jsonInt(format['bitrate']),
            urls: [_mediaUri(url)],
          ),
        );
      }
    }
    final dash = jsonString(streaming['dashManifestUrl']);
    return (hls: hls == null ? null : _mediaUri(hls), formats: formats, dash: dash == null ? null : _mediaUri(dash));
  }

  /// The variants of the HLS master [text] read from [source] (3.x's
  /// `_hlsVariants`, read by the shared [HlsStreamInf.read] with strict
  /// attributes): one stream per `#EXT-X-STREAM-INF`, labelled by height
  /// (and frame rate above 30). Throws [FormatException] for anything 3.x
  /// did not accept (then only the master itself is offered): a missing
  /// `#EXTM3U`, more than 64 variants, malformed attributes, two variants of
  /// one quality id, a variant URL off YouTube's media hosts, no variant.
  static List<YouTubeStream> hlsVariants(Uri source, String text) {
    if (text.length > _maxMaster || utf8.encode(text).length > _maxMaster) {
      throw const FormatException('YouTube HLS master exceeds byte budget');
    }
    final entries = HlsStreamInf.read(text);
    if (entries.length > 64) throw const FormatException('Invalid YouTube HLS variant count');
    final result = <YouTubeStream>[];
    final seen = <String>{};
    for (final entry in entries) {
      final line = entry.uri;
      if (line == null) throw const FormatException('Incomplete YouTube HLS master');
      final pending = entry.attributes(strict: true);
      final resolution = RegExp(r'^[1-9][0-9]{0,4}x([1-9][0-9]{0,4})$').firstMatch(pending['RESOLUTION'] ?? '');
      final height = int.tryParse(resolution?.group(1) ?? '');
      final frameRate = double.tryParse(pending['FRAME-RATE'] ?? '');
      final codec = _codec(pending['CODECS'] ?? '');
      final frames = frameRate != null && frameRate > 30 ? frameRate.round().toString() : '0';
      final id = 'hls:${height ?? 0}:$frames:${codec.isEmpty ? 'auto' : codec}';
      final Uri uri;
      try {
        uri = _mediaUri(source.resolve(line).toString());
      } on ApiChanged {
        throw const FormatException('YouTube HLS variant off the media hosts');
      }
      if (!seen.add(id)) throw const FormatException('Ambiguous YouTube HLS quality identity');
      result.add(
        YouTubeStream(
          id: id,
          label: height == null ? 'HLS Auto' : '${height}p${frames == '0' ? '' : frames}',
          protocol: 'hls',
          codec: codec,
          height: height,
          frameRate: frameRate,
          bitrate: int.tryParse(pending['BANDWIDTH'] ?? ''),
          urls: [uri],
        ),
      );
    }
    if (result.isEmpty) throw const FormatException('Incomplete YouTube HLS master');
    return result;
  }

  static const int _maxMaster = 4 * 1024 * 1024;

  /// The HLS master offered as one source when its variants cannot be read.
  static YouTubeStream hlsAuto(Uri master) =>
      YouTubeStream(id: 'hls:auto', label: 'HLS Auto', protocol: 'hls', urls: [master]);

  /// 3.x's source list: the HLS variants (or [hlsAuto]), the progressive
  /// [formats], the DASH manifest; ordered by [qualitySort], best first,
  /// then by id.
  static List<YouTubeStream> streams({
    List<YouTubeStream> hls = const [],
    List<YouTubeStream> formats = const [],
    Uri? dash,
  }) {
    final seen = <String>{};
    return [
      for (final stream in [
        ...hls,
        ...formats,
        if (dash != null) YouTubeStream(id: 'dash:auto', label: 'DASH Auto', protocol: 'dash', urls: [dash]),
      ])
        if (seen.add(stream.id)) stream,
    ]..sort((left, right) {
      final rank = qualitySort(right).compareTo(qualitySort(left));
      return rank != 0 ? rank : left.id.compareTo(right.id);
    });
  }

  /// 3.x's order: height × 1000 + frame rate + 30 (HLS), 20 (progressive)
  /// or 10 (DASH); the automatic sources have no height.
  static int qualitySort(YouTubeStream stream) {
    final fps = (stream.frameRate ?? 0).round().clamp(0, 999);
    final protocol = switch (stream.protocol) {
      'hls' => 30,
      'http' => 20,
      'dash' => 10,
      _ => 0,
    };
    return (stream.height ?? 0) * 1000 + fps + protocol;
  }

  /// 3.x's qualities: `1080p · H264 · HLS`, `HLS 自动 · HLS`,
  /// `DASH 自动 · DASH`, `360p · H264 · HTTP`; the id is the stream id.
  static List<LivePlayQuality> qualities(List<YouTubeStream> streams) => [
    for (final stream in streams)
      LivePlayQuality(quality: _qualityLabel(stream), id: stream.id, sort: qualitySort(stream)),
  ];

  static String _qualityLabel(YouTubeStream stream) {
    final label = switch (stream.id) {
      'hls:auto' => hlsAutoLabel,
      'dash:auto' => dashAutoLabel,
      _ => stream.label,
    };
    final codec = stream.codec.isEmpty ? '' : ' · ${stream.codec.toUpperCase()}';
    return '$label$codec · ${stream.protocol.toUpperCase()}';
  }

  /// The lines of [stream] for [videoId]: 3.x's media headers, the format
  /// (HLS, a progressive file, or unknown for DASH), the codec, the host as
  /// line id and the lease from `expire`. The applied quality is the
  /// stream's id (3.x).
  static LivePlayUrlResolution resolution(YouTubeStream stream, {required String videoId}) {
    final headers = mediaHeaders(videoId);
    return LivePlayUrlResolution.lines([
      for (final url in stream.urls)
        LivePlayLine(
          url.toString(),
          headers: headers,
          format: switch (stream.protocol) {
            'hls' => StreamFormat.hls,
            'http' => StreamFormat.other,
            _ => null,
          },
          codec: switch (stream.codec) {
            'h264' => 'avc',
            'h265' => 'hevc',
            '' => null,
            final other => other,
          },
          lineId: url.host,
          lease: lease(url),
        ),
    ], appliedQualityData: stream.id);
  }

  /// When [url] stops opening connections: its `expire` query parameter or
  /// `/expire/<seconds>/` path segment (3.x's `getPlayUrlInvalidAt`).
  static DateTime? invalidAt(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final query = int.tryParse(RegExp(r'(?:^|&)expire=(\d+)(?:&|$)').firstMatch(uri.query)?.group(1) ?? '');
    if (query != null && query > 0) return DateTime.fromMillisecondsSinceEpoch(query * 1000, isUtc: true);
    final List<String> segments;
    try {
      segments = uri.pathSegments;
    } on FormatException {
      return null;
    }
    final index = segments.indexOf('expire');
    if (index >= 0 && index + 1 < segments.length) {
      final path = int.tryParse(segments[index + 1]);
      if (path != null && path > 0) return DateTime.fromMillisecondsSinceEpoch(path * 1000, isUtc: true);
    }
    return null;
  }

  /// The lease of [url]: renew [leaseLead] before [invalidAt]. Expiry does
  /// not cut an open connection; the next playlist refresh fails.
  static PlayLease? lease(Uri url) {
    final expiresAt = invalidAt(url.toString());
    return expiresAt == null ? null : PlayLease(refreshAt: expiresAt.subtract(leaseLead), expiresAt: expiresAt);
  }

  // Helpers -------------------------------------------------------------------

  static String _codec(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('av01')) return 'av1';
    if (lower.contains('vp09') || lower.contains('vp9')) return 'vp9';
    if (lower.contains('hev1') || lower.contains('hvc1')) return 'h265';
    if (lower.contains('avc1') || lower.contains('h264')) return 'h264';
    return '';
  }

  static double? _double(Object? value) {
    final result = value is num ? value.toDouble() : double.tryParse(jsonString(value) ?? '');
    return result != null && result.isFinite && result >= 0 ? result : null;
  }

  static final RegExp _unsafeUrl = RegExp(r'[\s\x00-\x1f]');

  /// An https media URL on `googlevideo.com`, `youtube.com` or
  /// `youtube-nocookie.com` (or their subdomains), without user info or
  /// fragment; else `ApiChanged`.
  static Uri _mediaUri(String raw) {
    final uri = raw.isEmpty || raw.length > 65536 || raw.contains(_unsafeUrl) ? null : Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment || !_mediaHost(host)) {
      throw ApiChanged(_site, 'media URL off the YouTube hosts: ${_snippet(raw)}');
    }
    return uri;
  }

  static bool _mediaHost(String host) =>
      host == 'googlevideo.com' ||
      host.endsWith('.googlevideo.com') ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');

  static bool _imageHost(String host) =>
      host == 'ytimg.com' || host.endsWith('.ytimg.com') || host == 'ggpht.com' || host.endsWith('.ggpht.com');

  /// The first JSON object after [marker] (3.x's `_embeddedObject`): braces
  /// counted outside strings; an object that does not decode is skipped for
  /// the next marker. Empty when there is none.
  static Map<String, dynamic> _embedded(String text, String marker) {
    var offset = text.indexOf(marker);
    while (offset >= 0) {
      final start = text.indexOf('{', offset + marker.length);
      if (start < 0) break;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var index = start; index < text.length; index++) {
        final code = text.codeUnitAt(index);
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (code == 0x5c) {
            escaped = true;
          } else if (code == 0x22) {
            quoted = false;
          }
          continue;
        }
        if (code == 0x22) {
          quoted = true;
        } else if (code == 0x7b) {
          depth++;
        } else if (code == 0x7d && --depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, index + 1));
            if (decoded is Map<String, dynamic>) return decoded;
          } on FormatException {
            // Not this one; try the next marker.
          }
          break;
        }
      }
      offset = text.indexOf(marker, offset + marker.length);
    }
    return const {};
  }
}

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : (value is Map ? value.cast<String, dynamic>() : const {});

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
