import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'kuaishou';
const _origin = 'https://live.kuaishou.com';

/// What the danmaku connection needs to follow one broadcast (3.x's
/// `KuaishouDanmakuArgs`): the broadcast's `liveStreamId`, the key of the
/// mobile comment feed, and the cookie in effect when the room was read
/// (the user's, else the anonymous session's, else empty).
@immutable
final class KuaishouDanmakuArgs {
  /// Creates the arguments.
  const new({required this.liveStreamId, this.cookie = '', this.emotes = const {}});

  /// Id of the current broadcast (a new one every broadcast).
  final String liveStreamId;

  /// Cookie header for the feed requests; empty for none.
  final String cookie;

  /// The site's emoji table: the code a comment writes (`[笑哭]`) → its
  /// picture (https), from the room page ([KuaishouApi.emojiTable]); empty
  /// when the room was not read from its page (a card).
  final Map<String, String> emotes;
}

/// The broadcast behind a room card or page, apart from the room's
/// identity (the streamer id): 3.x kept `liveStreamId` in `link` and the
/// raw `playUrls` in `data`.
@immutable
final class KuaishouRoomData {
  /// Creates the data.
  const new({this.liveStreamId, this.playUrls, this.issuedAt});

  /// Id of the current broadcast (danmaku feed, app deep link); null when
  /// the room is offline.
  final String? liveStreamId;

  /// The raw `playUrls` value: the room page's `{h264, hevc}` object or a
  /// card's descriptor list. Null when it was not asked for (follow
  /// refresh).
  final Object? playUrls;

  /// When the response carrying [playUrls] arrived: the origin of the
  /// signed URLs' leases.
  final DateTime? issuedAt;
}

/// Pure parsing of Kuaishou responses (3.x's `KuaishowSite`, with the
/// archived v4 parser's fixes). Each function takes the response text and
/// status and returns 3.x's models or throws a `SiteError`.
abstract final class KuaishouApi {
  /// Desktop Chrome 140 on macOS, the UA 3.x sent to the media CDN
  /// (`PlaybackHeaderResolver`).
  static const String mediaUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Web origin; also the media requests' `Origin`.
  static const String origin = _origin;

  /// How long before the signature expiry a play URL is renewed (at most a
  /// quarter of its lifetime).
  static const Duration leaseLead = Duration(minutes: 10);

  /// The eight fixed first-level categories, in 3.x's order; their areas
  /// come from [areas].
  static const List<({String id, String name})> topCategories = [
    (id: '1', name: '热门'),
    (id: '2', name: '网游'),
    (id: '3', name: '单机'),
    (id: '4', name: '手游'),
    (id: '5', name: '棋牌'),
    (id: '6', name: '娱乐'),
    (id: '7', name: '综合'),
    (id: '8', name: '文化'),
  ];

  /// The room page of streamer [roomId]: `https://live.kuaishou.com/u/{id}`.
  static String roomPageUrl(String roomId) => '$_origin/u/${Uri.encodeComponent(roomId.trim())}';

  // Catalog -------------------------------------------------------------------

  /// `live_api/category/data`: the areas of category [categoryId] on one
  /// page, in server order without repeats; picture `poster`, else
  /// `iconUrl`. The server ignores `size` (50 a page); the next page exists
  /// while `hasMore` is true.
  static ({List<LiveArea> areas, bool hasMore}) areas(
    String body, {
    required String categoryId,
    required String categoryName,
    int status = 200,
  }) {
    final data = _apiData(body, status: status, what: 'category/data');
    final list = data['list'];
    if (list is! List) throw ApiChanged(_site, 'category/data: no list (${_snippet(body)})');
    final seen = <String>{};
    final areas = <LiveArea>[];
    for (final raw in list) {
      final item = _object(raw);
      final id = jsonString(item?['id']);
      if (item == null || id == null || !seen.add(id)) continue;
      areas.add(
        LiveArea(
          platform: _site,
          areaType: categoryId,
          typeName: categoryName,
          areaId: id,
          areaName: jsonString(item['name']) ?? '',
          areaPic: normalizeImageUrl(item['poster']).ifEmpty(() => normalizeImageUrl(item['iconUrl'])),
        ),
      );
    }
    return (areas: areas, hasMore: areas.isNotEmpty && _truthy(data['hasMore']));
  }

  /// `live_api/gameboard/list` and `non-gameboard/list`: live rooms of one
  /// area page, and the paging the server reports (`hasMore`, and the
  /// non-gameboard `cursor` the next page must send). A card without an
  /// author id is skipped; missing fields are empty (3.x failed the page).
  /// Cards carry the broadcast's start and, when they have streams, no
  /// restriction (see [LiveRoom.startedAt], [LiveRoom.restriction]).
  static ({List<LiveRoom> rooms, bool hasMore, String? cursor}) areaRooms(
    String body, {
    required DateTime issuedAt,
    String cookie = '',
    int status = 200,
  }) {
    final data = _apiData(body, status: status, what: 'area rooms');
    final list = data['list'];
    if (list is! List) throw ApiChanged(_site, 'area rooms: no list (${_snippet(body)})');
    final rooms = [for (final item in list) ?_card(item, issuedAt: issuedAt, cookie: cookie)];
    return (rooms: rooms, hasMore: rooms.isNotEmpty && _truthy(data['hasMore']), cursor: jsonString(data['cursor']));
  }

  /// `live_api/home/list`: every group's `gameLiveInfo[].liveInfo[]` in
  /// server order, one card per streamer. Cover and title come from the
  /// card (`poster`, `caption`) like the area lists; 3.x took the area
  /// poster and the streamer bio. The bio stays the introduction.
  static List<LiveRoom> recommendRooms(
    String body, {
    required DateTime issuedAt,
    String cookie = '',
    int status = 200,
  }) {
    final data = _apiData(body, status: status, what: 'home/list');
    final groups = data['list'];
    if (groups is! List) throw ApiChanged(_site, 'home/list: no list (${_snippet(body)})');
    final seen = <String>{};
    return [
      for (final group in groups)
        for (final label in _list(_object(group)?['gameLiveInfo']))
          for (final item in _list(_object(label)?['liveInfo']))
            if (_card(item, issuedAt: issuedAt, cookie: cookie, recommend: true) case final room?
                when seen.add(room.roomId))
              room,
    ];
  }

  // Search --------------------------------------------------------------------

  /// `live_api/search/author`: streamers, live or not (the live-stream
  /// search answers guests "服务器繁忙"). No audience figure, so none is
  /// shown instead of 0. `result` 2 is `RateLimited` and 10 `RiskControl`;
  /// 3.x read both as "no results".
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final data = _apiData(body, status: status, what: 'search/author');
    final list = data['list'];
    if (list is! List) {
      // result 1 without a list: the no-result answer (not recorded yet).
      if (jsonInt(data['result']) == 1) return const [];
      throw ApiChanged(_site, 'search/author: no list (${_snippet(body)})');
    }
    return [
      for (final raw in list)
        if (_object(raw) case final author? when jsonString(author['id']) != null) _searchRoom(author),
    ];
  }

  static LiveRoom _searchRoom(Map<String, dynamic> author) {
    final id = jsonString(author['id'])!;
    final name = _text(author['name']);
    final avatar = normalizeImageUrl(author['avatar']);
    final counts = _object(author['counts']);
    final banned = _object(author['bannedStatus'])?['banned'] == true;
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: id,
      nick: name,
      title: name,
      avatar: avatar,
      cover: avatar,
      watching: '',
      followers: counts?['fan']?.toString() ?? '0',
      introduction: author['description']?.toString(),
      link: roomPageUrl(id),
      liveStatus: banned
          ? LiveStatus.banned
          : author['living'] == true
          ? LiveStatus.live
          : LiveStatus.offline,
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// The room page `/u/{id}`: the room as the user asked for it
  /// ([requestedId]; a follow keeps its identity). `isLiving` (true, 1 or
  /// "true") alone decides live or offline; `errorType` 22 is `NotFound`,
  /// any other `errorType` `RiskControl`.
  ///
  /// The title is the streamer bio with line breaks as spaces (the page has
  /// no broadcast title). The page has no room audience either:
  /// `gameInfo.watchingCount` counts the whole area, so the audience stays
  /// empty until a card or the danmaku feed brings one. The broadcast's id
  /// and, with [withStreams], its `playUrls` go into [KuaishouRoomData];
  /// the danmaku arguments carry [cookie]. [url] is the page's final URL
  /// (a verification redirect is `RiskControl`).
  ///
  /// A living room's [LiveRoom.restriction] is [LiveRestriction.none] when
  /// `playUrls` has a playable quality and [LiveRestriction.unplayable]
  /// when the page says living but gives this client none; it is read with
  /// or without [withStreams]. `liveStream.privateLive` is not read: it was
  /// false on every recorded page, so what true means (and whether such a
  /// page still has streams) is unknown. The page has no broadcast start
  /// (the `startTime` values in it belong to site configuration), so
  /// [LiveRoom.startedAt] stays null; cards have it.
  static LiveRoom roomDetail(
    String body, {
    required String requestedId,
    required DateTime issuedAt,
    bool withStreams = true,
    String cookie = '',
    bool userCookie = false,
    int status = 200,
    Uri? url,
  }) {
    final state = _pageState(body, status: status, userCookie: userCookie, url: url);
    final room = _playItem(state, userCookie: userCookie);
    final author = _fields(room['author']);
    final stream = _fields(room['liveStream']);
    final game = _fields(room['gameInfo']);
    final description = _text(author['description']);
    final liveStreamId = jsonString(stream['id']);
    final id = requestedId.trim();
    final living = _truthy(room['isLiving']);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: description.replaceAll('\n', ' '),
      nick: _text(author['name']),
      avatar: normalizeImageUrl(author['avatar']),
      cover: _cover(stream['poster']),
      area: _text(game['name']),
      watching: '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: jsonString(_fields(author['counts'])['fan']) ?? '0',
      liveStatus: living ? LiveStatus.live : LiveStatus.offline,
      restriction: living ? _restriction(stream['playUrls']) ?? LiveRestriction.unplayable : null,
      link: roomPageUrl(id),
      introduction: description,
      notice: description,
      data: KuaishouRoomData(
        liveStreamId: liveStreamId,
        playUrls: withStreams ? stream['playUrls'] : null,
        issuedAt: issuedAt,
      ),
      danmakuData: liveStreamId == null
          ? null
          : KuaishouDanmakuArgs(liveStreamId: liveStreamId, cookie: cookie, emotes: emojiTable(state)),
    );
  }

  /// The emoji table of a room page's [state]
  /// (`pcConfig.pcConfig.config["pcLive.webConfig.emojiPanel"]`, 207 codes
  /// on 2026-10-01: `[笑哭]` → `//ali2.a.yximgs.com/bs2/emotion/….png`): what
  /// the site draws for the codes in comments. Addresses are made https;
  /// codes that are not `[…]` and entries without an address are skipped.
  /// Empty when the page has none.
  static Map<String, String> emojiTable(Map<String, dynamic> state) {
    final config = _fields(_fields(_fields(state['pcConfig'])['pcConfig'])['config']);
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in _fields(config['pcLive.webConfig.emojiPanel']).entries)
        if (key.length > 2 && key.startsWith('[') && key.endsWith(']'))
          if (normalizeImageUrl(value) case final url when url.isNotEmpty) key: url,
    });
  }

  /// The `window.__INITIAL_STATE__` object of a room page, cut by JSON
  /// structure: a `;` inside a string does not end it (3.x cut at the first
  /// `;`), and only a bare `undefined` becomes `null` (3.x also rewrote
  /// the word inside strings). A page without the state is a verification
  /// page (`RiskControl`, the user's cookie suspect when [userCookie]) or
  /// an unknown page (`ApiChanged`).
  static Map<String, dynamic> initialState(String html, {bool userCookie = false}) {
    final marker = _stateMarker.firstMatch(html);
    if (marker == null) {
      if (_challenge.hasMatch(html)) {
        throw RiskControl(_site, cookieSuspect: userCookie, detail: 'room page is a verification page');
      }
      throw const ApiChanged(_site, 'room page: no __INITIAL_STATE__');
    }
    final literal = _objectLiteral(html, marker.end);
    if (literal == null) throw const ApiChanged(_site, 'room page: __INITIAL_STATE__ is not a complete object');
    try {
      final state = jsonDecode(literal);
      if (state is Map<String, dynamic>) return state;
    } on FormatException {
      // Reported below.
    }
    throw const ApiChanged(_site, 'room page: __INITIAL_STATE__ is not a JSON object');
  }

  // Streams -------------------------------------------------------------------

  /// Qualities of a `playUrls` value, best first (3.x's
  /// `parsePlayQualities`):
  /// - per descriptor the first of `h264`, `avc`, `hevc`, `h265` that has
  ///   representations, else the descriptor itself (HEVC only when there is
  ///   no H.264);
  /// - only absolute `http://` and `https://` URLs;
  /// - `sort` is `level`, else `bitrate`, else 0; the name is `name`, else
  ///   `shortName`, else `qualityType`, else `清晰度 {sort}`;
  /// - one quality per (name, sort), its URLs merged in order without
  ///   repeats (descriptors are CDN lines); [LivePlayQuality.data] holds
  ///   them, [LivePlayQuality.id] is `name\u0000sort`;
  /// - a room page's H.265 qualities the H.264 set lacks (4K, 蓝光 质臻)
  ///   are added with “ · H.265” after the name and in the id; with
  ///   [preferH264] ("优先 H.264", on by default) they come after every
  ///   H.264 quality, else by sort. Their FLV is codec id 12.
  static List<LivePlayQuality> qualities(Object? playUrls, {bool preferH264 = true}) => [
    for (final tier in _tiers(playUrls, preferH264: preferH264))
      LivePlayQuality(
        quality:
            LiveQualityLabel.normalize(platform: _site, rawLabel: tier.name, id: tier.key) +
            (tier.hevcOnly ? _hevcSuffix : ''),
        id: tier.key,
        sort: tier.sort,
        data: List<String>.unmodifiable([for (final line in tier.lines) line.url]),
      ),
  ];

  /// The lines of [quality] in [playUrls] (the quality with the same id;
  /// else the next lower one, else the lowest), received at [issuedAt] for
  /// streamer [roomId]. Lines keep one codec (the first known one), carry
  /// the media headers with the user's [cookie], the CDN host as line id
  /// and the lease of their signature. No quality at all is
  /// `StreamUnavailable`.
  static LivePlayUrlResolution resolution(
    Object? playUrls, {
    required LivePlayQuality quality,
    required String roomId,
    required DateTime issuedAt,
    String? cookie,
  }) {
    final tiers = _tiers(playUrls);
    if (tiers.isEmpty) throw const StreamUnavailable(_site, 'playUrls: no playable representation');
    final tier = _choose(tiers, quality);
    final headers = mediaHeaders(roomId, cookie: cookie);
    final codec = tier.lines.map((line) => line.codec).nonNulls.firstOrNull;
    final hosts = <String, int>{};
    return LivePlayUrlResolution.lines([
      for (final line in tier.lines)
        if (codec == null || line.codec == null || line.codec == codec)
          LivePlayLine(
            line.url,
            headers: headers,
            format: line.uri.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv,
            codec: line.codec,
            lineId: _lineId(line.uri, hosts),
            lease: lease(line.uri, issuedAt),
          ),
    ], appliedQualityData: tier.key);
  }

  /// Media request headers for streamer [roomId] (3.x's
  /// `PlaybackHeaderResolver`): UA, Origin, the room page as Referer, and
  /// the cookie only when the user configured one (the anonymous session
  /// never goes to the CDN). Names are lower case, values single-line.
  static Map<String, String> mediaHeaders(String roomId, {String? cookie}) {
    final id = roomId.trim();
    final value = cookie?.replaceAll(_controlCharacters, '').trim() ?? '';
    return {
      'user-agent': mediaUserAgent,
      'origin': _origin,
      'referer': id.isEmpty ? '$_origin/' : roomPageUrl(id),
      if (value.isNotEmpty) 'cookie': value,
    };
  }

  /// The lease of a media URL received at [issuedAt]: the signature expiry
  /// is `txTime`, `wsTime` or `hwTime` (8 hex digits), `ty_Time` or the
  /// `bd-origin` `wsTime` (10 decimal digits), or the first field of the
  /// `ali-origin` `auth_key`; about 24 hours after issue. Renew [leaseLead]
  /// (at most a quarter of the lifetime) before. Expiry is checked when a
  /// connection opens, so it does not cut one. No expiry, or one already
  /// past, is no lease.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final expiry = _expiry(url.query);
    if (expiry == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  // Session -------------------------------------------------------------------

  /// The `name=value` pairs of a response's `Set-Cookie` headers (what 3.x's
  /// cookie jar kept from the session page): invalid names, empty or unsafe
  /// values and cookies already expired (`Max-Age` ≤ 0) are left out.
  static Map<String, String> setCookies(Iterable<String> headers) {
    final cookies = <String, String>{};
    for (final header in headers) {
      final parts = header.split(';');
      final separator = parts.first.indexOf('=');
      if (separator <= 0) continue;
      final name = parts.first.substring(0, separator).trim();
      final value = parts.first.substring(separator + 1).trim();
      if (!_cookieName.hasMatch(name) || value.isEmpty || _cookieUnsafe.hasMatch(value)) continue;
      final expired = parts.skip(1).any((attribute) {
        final maxAge = _maxAge.firstMatch(attribute)?.group(1);
        return maxAge != null && int.parse(maxAge) <= 0;
      });
      if (expired) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
    return cookies;
  }

  /// The `misc2` device report of a new session's [did] (3.x's `misc2dic`):
  /// the did with the fixed values of the web logger 3.x imitated.
  static Map<String, Object> devicePayload(String did, {required int timestamp, required int incrementId}) {
    const session = '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f';
    return {
      'common': {
        'identity_package': {'device_id': did, 'global_id': ''},
        'app_package': {'language': 'zh-CN', 'platform': 10, 'container': 'WEB', 'product_name': 'KS_GAME_LIVE_PC'},
        'device_package': {
          'os_version': 'NT 6.1',
          'model': 'Windows',
          'ua':
              'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/86.0.4240.198 Safari/537.36',
        },
        'need_encrypt': 'false',
        'network_package': {'type': 3},
        'h5_extra_attr':
            '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"",'
            '"host_product":"","resolution":"1600x900","screen_with":1600,"screen_height":900,'
            '"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
        'global_attr': '{}',
      },
      'logs': [
        {
          'client_timestamp': timestamp,
          'client_increment_id': incrementId,
          'session_id': session,
          'time_zone': 'GMT+08:00',
          'event_package': {
            'task_event': {
              'type': 1,
              'status': 0,
              'operation_type': 1,
              'operation_direction': 0,
              'session_id': session,
              'url_package': {
                'page': 'GAME_DETAL_PAGE',
                'identity': '5316c78e-f0b6-4be2-a076-c8f9d11ebc0a',
                'page_type': 2,
                'params': '{"game_id":1001,"game_name":"王者荣耀"}',
              },
              'element_package': <String, Object>{},
            },
          },
        },
      ],
    };
  }

  // Helpers -------------------------------------------------------------------

  static final RegExp _stateMarker = RegExp(r'window\.__INITIAL_STATE__\s*=\s*');
  static final RegExp _challenge = RegExp('captcha|验证码|安全验证|人机验证|滑块', caseSensitive: false);
  static final RegExp _decimalTime = RegExp(r'^\d{10}$');
  static final RegExp _hexTime = RegExp(r'^[0-9a-fA-F]{8}$');
  static final RegExp _authKeyTime = RegExp(r'^(\d{10})-');
  static final RegExp _pathCodec = RegExp('^[A-Za-z]*?(Avc|Hevc|H264|H265)');
  static final RegExp _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final RegExp _cookieUnsafe = RegExp(r'[\u0000- \u007F;,]');
  static final RegExp _maxAge = RegExp(r'^\s*max-age\s*=\s*(-?\d+)\s*$', caseSensitive: false);
  static final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

  /// Image extensions 3.x recognised on covers (site:32-49).
  static const Set<String> _imageExtensions = {
    'svgz', 'pjp', 'png', 'ico', 'avif', 'tiff', 'tif', 'jfif', 'svg', 'xbm', 'pjpeg', 'webp', 'jpg', 'jpeg', //
    'bmp', 'gif',
  };

  /// A list card of the area lists and recommendations. Every card is live
  /// (the lists hold live rooms; the card's own `living` is false even for
  /// them). 3.x kept `liveStreamId` in `link`; it is in [KuaishouRoomData]
  /// now and `link` is the room page.
  ///
  /// [LiveRoom.startedAt] is the card's `statrtTime` (the platform's
  /// spelling; `startTime` is accepted too), in epoch milliseconds. A card
  /// with a playable stream has no restriction ([LiveRestriction.none]); a
  /// card without one leaves it unknown, since a list may leave streams out
  /// and the room page decides.
  static LiveRoom? _card(Object? value, {required DateTime issuedAt, required String cookie, bool recommend = false}) {
    final item = _object(value);
    if (item == null) return null;
    final author = _fields(item['author']);
    final id = jsonString(author['id']);
    if (id == null) return null;
    final liveStreamId = jsonString(item['id']);
    final watching = _text(item['watchingCount']);
    final caption = _text(item['caption']);
    final bio = author['description']?.toString();
    final flatBio = bio?.replaceAll('\n', ' ');
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: recommend && caption.isEmpty ? flatBio ?? '' : caption,
      nick: _text(author['name']),
      avatar: normalizeImageUrl(author['avatar']),
      cover: _cover(item['poster']),
      area: _text(_fields(item['gameInfo'])['name']),
      watching: watching,
      onlineViewers: watching,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
      startedAt: _epochMilliseconds(item['statrtTime']) ?? _epochMilliseconds(item['startTime']),
      restriction: _restriction(item['playUrls']),
      link: roomPageUrl(id),
      introduction: recommend ? flatBio ?? '' : null,
      notice: recommend ? bio : null,
      data: KuaishouRoomData(liveStreamId: liveStreamId, playUrls: item['playUrls'], issuedAt: issuedAt),
      danmakuData: liveStreamId == null ? null : KuaishouDanmakuArgs(liveStreamId: liveStreamId, cookie: cookie),
    );
  }

  /// A cover as 3.x wrote it: made absolute, and `.jpg` appended when the
  /// path names no image type (the screenshot URLs have no extension; both
  /// forms serve the same JPEG). A URL with a query is kept as is (3.x
  /// appended into the query). Empty when there is none (3.x threw).
  static String _cover(Object? value) {
    final url = normalizeImageUrl(value);
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.hasQuery || uri.hasFragment) return url;
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 && _imageExtensions.contains(name.substring(dot + 1).toLowerCase()) ? url : '$url.jpg';
  }

  /// [LiveRestriction.none] when [playUrls] has a playable quality, else
  /// null (the caller decides what having none means).
  static LiveRestriction? _restriction(Object? playUrls) => _tiers(playUrls).isEmpty ? null : LiveRestriction.none;

  /// A time in epoch milliseconds; null for 0, negatives, values that are
  /// not milliseconds (before 2001 or after 2286, such as a time in
  /// seconds) and anything that is not an integer.
  static DateTime? _epochMilliseconds(Object? value) => switch (jsonInt(value)) {
    final int milliseconds when milliseconds >= 1000000000000 && milliseconds < 10000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    _ => null,
  };

  /// `liveroom.playList[0]` of a room page, with the status and `errorType`
  /// mapping applied.
  /// The [initialState] of a room page answered with [status] at [url].
  static Map<String, dynamic> _pageState(String body, {required int status, required bool userCookie, Uri? url}) {
    _checkStatus(status, 'room page', userCookie: userCookie);
    if (url != null && '${url.host}${url.path}'.toLowerCase().contains('captcha')) {
      throw RiskControl(_site, cookieSuspect: userCookie, detail: 'room page redirected to ${url.host}${url.path}');
    }
    return initialState(body, userCookie: userCookie);
  }

  static Map<String, dynamic> _playItem(Map<String, dynamic> state, {required bool userCookie}) {
    final list = _object(state['liveroom'])?['playList'];
    final room = list is List && list.isNotEmpty ? _object(list.first) : null;
    if (room == null) throw const ApiChanged(_site, 'room page: liveroom.playList[0] missing');
    final error = room['errorType'];
    if (error != null) {
      final type = jsonInt(_object(error)?['type'] ?? error);
      final title = jsonString(_object(error)?['title']) ?? '';
      if (type == 22) throw NotFound(_site, 'errorType 22 $title'.trim());
      throw RiskControl(_site, cookieSuspect: userCookie, detail: 'errorType $type $title'.trim());
    }
    return room;
  }

  /// The JavaScript object literal starting at [start], as JSON text: a bare
  /// `undefined` outside strings becomes `null`.
  static String? _objectLiteral(String text, int start) {
    var index = start;
    while (index < text.length && text.codeUnitAt(index) <= 0x20) {
      index++;
    }
    if (index >= text.length || text[index] != '{') return null;
    final out = StringBuffer();
    var depth = 0;
    var inString = false;
    for (; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        out.write(char);
        if (char == r'\' && index + 1 < text.length) {
          out.write(text[++index]);
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{' || char == '[') {
        depth++;
      } else if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) return (out..write(char)).toString();
      } else if (text.startsWith('undefined', index) &&
          !_identifierAt(text, index - 1) &&
          !_identifierAt(text, index + 'undefined'.length)) {
        out.write('null');
        index += 'undefined'.length - 1;
        continue;
      }
      out.write(char);
    }
    return null;
  }

  static bool _identifierAt(String text, int index) {
    if (index < 0 || index >= text.length) return false;
    final unit = text.codeUnitAt(index);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x24 ||
        unit == 0x5F;
  }

  static List<Object?> _representations(Object? descriptor) {
    final map = _object(descriptor);
    if (map == null) return const [];
    final set = _object(map['adaptationSet']);
    return _list(set == null ? map['representation'] : set['representation']);
  }

  /// The tiers of [playUrls], best first; with [preferH264] the H.265 tiers
  /// (`hevcOnly`) follow every other tier.
  static List<_Tier> _tiers(Object? playUrls, {bool preferH264 = true}) {
    final merged = <String, _Tier>{};
    final hevc = <Object?>[];
    for (final raw in playUrls is List ? playUrls : [playUrls]) {
      final descriptor = _object(raw);
      if (descriptor == null) continue;
      Object? chosen = descriptor;
      String? keyCodec;
      for (final (key, codec) in const [('h264', 'avc'), ('avc', 'avc'), ('hevc', 'hevc'), ('h265', 'hevc')]) {
        if (_representations(descriptor[key]).isNotEmpty) {
          chosen = descriptor[key];
          keyCodec = codec;
          break;
        }
      }
      _addTiers(merged, _representations(chosen), keyCodec);
      if (keyCodec == 'avc') {
        hevc.addAll(
          _representations(_representations(descriptor['hevc']).isNotEmpty ? descriptor['hevc'] : descriptor['h265']),
        );
      }
    }
    // H.265 qualities the H.264 set lacks (4K, 蓝光 质臻 on some rooms), apart
    // from the H.264 names so a saved preference never lands on them.
    final extra = <String, _Tier>{};
    _addTiers(extra, hevc, 'hevc', hevcOnly: true);
    extra.removeWhere((_, tier) => merged.containsKey('${tier.name}\u0000${tier.sort}'));
    final ordered = [...merged.values, ...extra.values].indexed.toList()
      ..sort((a, b) {
        if (preferH264 && a.$2.hevcOnly != b.$2.hevcOnly) return a.$2.hevcOnly ? 1 : -1;
        final bySort = b.$2.sort.compareTo(a.$2.sort);
        return bySort != 0 ? bySort : a.$1.compareTo(b.$1);
      });
    return [for (final (_, tier) in ordered) tier];
  }

  /// Adds [representations] to [tiers] by (name, sort); [codec] is the
  /// descriptor's, else read from each URL. [hevcOnly] tiers are keyed by
  /// their name with “ · H.265”.
  static void _addTiers(
    Map<String, _Tier> tiers,
    List<Object?> representations,
    String? codec, {
    bool hevcOnly = false,
  }) {
    for (final value in representations) {
      final item = _object(value);
      if (item == null) continue;
      final url = item['url']?.toString().trim() ?? '';
      final uri = _mediaUri(url);
      if (uri == null) continue;
      final sort = jsonInt(item['level']) ?? jsonInt(item['bitrate']) ?? 0;
      final name =
          jsonString(item['name']) ?? jsonString(item['shortName']) ?? jsonString(item['qualityType']) ?? '清晰度 $sort';
      final key = hevcOnly ? '$name$_hevcSuffix\u0000$sort' : '$name\u0000$sort';
      final tier = tiers.putIfAbsent(
        key,
        () => (key: key, name: name, sort: sort, lines: <_Line>[], hevcOnly: hevcOnly),
      );
      if (tier.lines.every((line) => line.url != url)) {
        tier.lines.add((url: url, uri: uri, codec: codec ?? _codecOf(uri)));
      }
    }
  }

  /// An absolute `http://` or `https://` URL (3.x's check: the prefix, and
  /// `Uri.isAbsolute`), or null.
  static Uri? _mediaUri(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    final uri = Uri.tryParse(url);
    return uri != null && uri.isAbsolute && uri.host.isNotEmpty ? uri : null;
  }

  /// The codec of a card URL (card descriptors name none): the part of the
  /// file name after the last `_` starts with letters and the codec
  /// (`{id}_GameAvcSdL1.flv`, `…_ShowAvc…`, `…_EcAvc…`); `{id}_ma1500.flv`
  /// names none.
  static String? _codecOf(Uri url) {
    final file = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    return switch (_pathCodec.firstMatch(file.split('_').last)?.group(1)) {
      'Avc' || 'H264' => 'avc',
      'Hevc' || 'H265' => 'hevc',
      _ => null,
    };
  }

  /// The tier with [wanted]'s id, else the next lower one (H.265-only tiers
  /// only when there is nothing else), else the lowest.
  static _Tier _choose(List<_Tier> tiers, LivePlayQuality wanted) {
    final id = wanted.id?.toString();
    for (final tier in tiers) {
      if (tier.key == id) return tier;
    }
    final pool = tiers.where((tier) => !tier.hevcOnly).toList();
    final candidates = pool.isEmpty ? tiers : pool;
    for (final tier in candidates) {
      if (tier.sort <= wanted.sort) return tier;
    }
    return candidates.last;
  }

  /// The CDN host, numbered when a quality has two URLs on it.
  static String _lineId(Uri url, Map<String, int> hosts) {
    final count = hosts.update(url.host, (value) => value + 1, ifAbsent: () => 1);
    return count == 1 ? url.host : '${url.host}#$count';
  }

  static int? _expiry(String query) {
    String? parameter(String name) =>
        RegExp('(?:^|&)${RegExp.escape(name)}=([^&]*)').firstMatch(query)?.group(1)?.trim();
    for (final key in const ['txTime', 'wsTime', 'hwTime', 'ty_Time']) {
      final value = parameter(key);
      if (value == null) continue;
      if (_decimalTime.hasMatch(value)) return int.parse(value);
      if (_hexTime.hasMatch(value)) return int.parse(value, radix: 16);
    }
    final authKey = _authKeyTime.firstMatch(parameter('auth_key') ?? '');
    return authKey == null ? null : int.parse(authKey.group(1)!);
  }
}

typedef _Line = ({String url, Uri uri, String? codec});

/// One quality: `hevcOnly` for an H.265 quality of a room page whose H.264
/// set lacks it.
typedef _Tier = ({String key, String name, int sort, List<_Line> lines, bool hevcOnly});

const _hevcSuffix = ' · H.265';

/// `data` of a `live_api` answer. List answers carry no `result`; a
/// `result` other than 1 is 2 `RateLimited` (“操作太快了”), 10
/// `RiskControl` (“服务器繁忙”, the guest gate) or `ApiChanged`.
Map<String, dynamic> _apiData(String body, {required int status, required String what}) {
  _checkStatus(status, what);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  final data = _object(_object(decoded)?['data']);
  if (data == null) throw ApiChanged(_site, '$what: no data object (${_snippet(body)})');
  final result = jsonInt(data['result']);
  if (result != null && result != 1) {
    final detail = '$what: result $result ${jsonString(data['error_msg']) ?? ''}'.trim();
    throw switch (result) {
      2 => RateLimited(_site, detail: detail),
      10 => RiskControl(_site, detail: detail),
      _ => ApiChanged(_site, detail),
    };
  }
  return data;
}

/// HTTP 429 → `RateLimited`; 5xx → `NetworkFailure`; 401 and 403 →
/// `RiskControl` (the user's cookie suspect when [userCookie]); any other
/// non-2xx → `ApiChanged`.
void _checkStatus(int status, String what, {bool userCookie = false}) {
  if (status >= 200 && status < 300) return;
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  if (status == 401 || status == 403) {
    throw RiskControl(_site, cookieSuspect: userCookie, detail: '$what: HTTP $status');
  }
  throw ApiChanged(_site, '$what: HTTP $status');
}

/// `isLiving` and the other flags: true, 1 or "true" in any case (3.x once
/// read a numeric flag as offline).
bool _truthy(Object? value) => value == true || value == 1 || (value is String && value.trim().toLowerCase() == 'true');

/// A field as 3.x wrote it (`toString()`), empty when missing (3.x wrote
/// "null" or threw).
String _text(Object? value) => value == null ? '' : '$value';

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

/// An object field, or an empty one: a missing field reads as empty.
Map<String, dynamic> _fields(Object? value) => value is Map<String, dynamic> ? value : const {};

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
