import 'dart:convert';

import 'package:live_core/src/audience.dart';
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
  /// One video (a broadcast): its 11-character id is the room id.
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

  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _channelId = RegExp(r'^UC[A-Za-z0-9_-]{20,30}$');
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

  /// A search keyword as 3.x read it: a link, else a bare video id, else a
  /// bare handle (with or without `@`, 3 to 30 characters, so `lofi` is the
  /// channel `@lofi`); null for anything else (`lofi girl`).
  static YouTubeLink? parseOrReference(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final video = normalizeVideoId(raw);
    if (video != null) return YouTubeLink(kind: YouTubeLinkKind.video, id: video);
    final handle = normalizeHandle(raw);
    return handle == null ? null : YouTubeLink(kind: YouTubeLinkKind.channel, id: '@$handle');
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
/// `data`): the live room's sources in 3.x's order, or why they could not
/// be read (the room opens anyway; the qualities report it).
@immutable
final class YouTubeRoomData {
  /// Creates the data.
  new({required this.videoId, List<YouTubeStream> streams = const [], this.streamError})
    : streams = List.unmodifiable(streams);

  /// The video (room) the data belongs to.
  final String videoId;

  /// The sources, best first; empty when the player answer had none.
  final List<YouTubeStream> streams;

  /// Why the sources could not be read at room entry, if they could not.
  final SiteError? streamError;
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
}

/// A video as 3.x read it from its watch page and the ANDROID player answer.
@immutable
final class YouTubeVideo {
  const new _({required this.room, required this.streamingData, required this.playability, required this.reason});

  /// The room (id, state, names, thumbnail, viewers), without playback data.
  final LiveRoom room;

  /// The player answer's `streamingData` (read for playback only).
  final Map<String, dynamic> streamingData;

  /// `playabilityStatus.status` (`OK`, `LIVE_STREAM_OFFLINE`, …).
  final String playability;

  /// `playabilityStatus.reason`, for diagnostics.
  final String reason;
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

  /// 3.x's room notice (`youtube_chat_notice`, zh.json).
  static const String chatNotice = 'YouTube Live 远端聊天尚待接入；仅在直播页返回专用并发观看字段时显示当前在线，不把累计播放量当作在线人数。';

  /// The area of a video without a category (3.x).
  static const String defaultArea = 'YouTube Live';

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
  /// watch page as Referer, and Origin.
  static Map<String, String> mediaHeaders(String videoId) => {
    'origin': origin,
    'referer': YouTubeLink.videoUrl(videoId),
    'user-agent': userAgent,
  };

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
  static String? liveVideoOfPage(String html, {Uri? finalUrl, int status = 200}) {
    checkStatus(status, html, 'channel page');
    final redirected = finalUrl == null ? null : YouTubeLink.parse(finalUrl.toString());
    if (redirected?.kind == YouTubeLinkKind.video) return redirected!.id;
    final page = watchPage(html);
    final canonical = page.canonical == null ? null : YouTubeLink.parse(page.canonical!);
    if (canonical?.kind == YouTubeLinkKind.video) return canonical!.id;
    final details = _object(page.player['videoDetails']);
    final id = YouTubeLink.normalizeVideoId(jsonString(details['videoId']) ?? '');
    if (id != null && details['isLive'] == true) return id;
    return _findLiveVideo(page.data);
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

  /// The room of [videoId] from its [page] and the ANDROID [player] answer,
  /// merged as 3.x merged them (the player answer's fields win).
  ///
  /// The answer must name [videoId]: one naming no video is `NotFound`
  /// (`ERROR`, a missing video), `NeedsLogin` (sign-in, age or content
  /// checks), `StreamUnavailable` (`UNPLAYABLE`) or `ApiChanged`; one naming
  /// another video is `ApiChanged`. 3.x's states:
  /// - private, sign-in, age or content checks: banned;
  /// - `isLive` (or `liveBroadcastDetails.isLiveNow`) with status `OK`: live;
  /// - other broadcasts (ended, upcoming, live but not playable) and
  ///   `LIVE_STREAM_OFFLINE`: offline;
  /// - no status at all: unknown;
  /// - anything else (an ordinary video): `NotFound`, it is no live room.
  ///
  /// Title and author are required (`ApiChanged`). Concurrent viewers come
  /// from the page's live `videoViewCountRenderer`, only while live.
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
    final broadcast = _object(micro['liveBroadcastDetails']);
    final live = details['isLive'] == true || broadcast['isLiveNow'] == true;
    final liveContent =
        live || details['isLiveContent'] == true || details['isUpcoming'] == true || broadcast.isNotEmpty;
    final lowerReason = reason.toLowerCase();
    final restricted =
        details['isPrivate'] == true ||
        const {'LOGIN_REQUIRED', 'AGE_CHECK_REQUIRED', 'CONTENT_CHECK_REQUIRED'}.contains(code) ||
        lowerReason.contains('sign in') ||
        lowerReason.contains('private');
    final state = switch (code) {
      _ when restricted => LiveStatus.banned,
      'OK' when live => LiveStatus.live,
      _ when liveContent || code == 'LIVE_STREAM_OFFLINE' => LiveStatus.offline,
      '' => LiveStatus.unknown,
      _ => throw NotFound(_site, 'player: $videoId is not a live broadcast ($code)'),
    };
    final title = _required(details['title'], 'title');
    final author = _required(details['author'], 'author');
    final thumbnail = _thumbnail(details['thumbnail'] ?? micro['thumbnail']);
    final viewers = state == LiveStatus.live ? _currentViewers(page.data) : null;
    final category = jsonString(micro['category']) ?? '';
    return YouTubeVideo._(
      room: LiveRoom(
        roomId: videoId,
        platform: _site,
        userId: jsonString(details['channelId']) ?? '',
        nick: author,
        title: title,
        avatar: thumbnail,
        cover: thumbnail,
        area: category.isEmpty ? defaultArea : category,
        introduction: jsonString(details['shortDescription']) ?? '',
        link: YouTubeLink.videoUrl(videoId),
        liveStatus: state,
        watching: viewers?.toString() ?? '',
        onlineViewers: viewers?.toString() ?? '',
        audienceMetricType: AudienceMetricType.onlineViewers,
        notice: chatNotice,
        httpHeaders: mediaHeaders(videoId),
      ),
      streamingData: _object(player['streamingData']),
      playability: code,
      reason: reason,
    );
  }

  static String _required(Object? value, String name) {
    final text = jsonString(value);
    if (text == null || text.length > 8192) throw ApiChanged(_site, 'player: videoDetails.$name missing');
    return text;
  }

  /// The last https thumbnail on `ytimg.com` or `ggpht.com` (3.x); empty
  /// when there is none or the list has more than 64 entries.
  static String _thumbnail(Object? value) {
    final items = _object(value)['thumbnails'];
    if (items is! List || items.length > 64) return '';
    for (final item in items.reversed) {
      final uri = Uri.tryParse(jsonString(_object(item)['url']) ?? '');
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment &&
          _imageHost(uri.host.toLowerCase())) {
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
  /// `_hlsVariants`): one stream per `#EXT-X-STREAM-INF`, labelled by height
  /// (and frame rate above 30). Throws [FormatException] for anything 3.x
  /// did not accept (then only the master itself is offered): a missing
  /// `#EXTM3U`, more than 64 variants, malformed attributes, two variants of
  /// one quality id, a variant URL off YouTube's media hosts, no variant.
  static List<YouTubeStream> hlsVariants(Uri source, String text) {
    if (text.length > _maxMaster || utf8.encode(text).length > _maxMaster) {
      throw const FormatException('YouTube HLS master exceeds byte budget');
    }
    final lines = const LineSplitter().convert(text).map((line) => line.trim()).where((line) => line.isNotEmpty);
    final iterator = lines.iterator;
    if (!iterator.moveNext() || iterator.current != '#EXTM3U') {
      throw const FormatException('Expected YouTube HLS master');
    }
    Map<String, String>? pending;
    final result = <YouTubeStream>[];
    final seen = <String>{};
    while (iterator.moveNext()) {
      final line = iterator.current;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null || result.length >= 64) throw const FormatException('Invalid YouTube HLS variant count');
        pending = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
        continue;
      }
      if (line.startsWith('#') || pending == null) continue;
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
      pending = null;
    }
    if (pending != null || result.isEmpty) throw const FormatException('Incomplete YouTube HLS master');
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

  static final RegExp _attribute = RegExp(r'([A-Z0-9-]+)=("[^"\r\n\x00]*"|[^,\s"]+)(?:,|$)');

  static Map<String, String> _attributes(String text) {
    final values = <String, String>{};
    var offset = 0;
    while (offset < text.length) {
      final match = _attribute.matchAsPrefix(text, offset);
      if (match == null || values.containsKey(match[1])) {
        throw const FormatException('Malformed YouTube HLS attributes');
      }
      final value = match[2]!;
      values[match[1]!] = value.startsWith('"') ? value.substring(1, value.length - 1) : value;
      offset = match.end;
    }
    return values;
  }

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
