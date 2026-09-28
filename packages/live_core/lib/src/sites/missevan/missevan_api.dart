import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'missevan';

/// The pull URLs of a live room, upgraded to https (3.x kept them as the
/// room's qualities in `data`). One of them may be missing, never both.
/// Offline rooms, search results and list cards have none: an offline room's
/// detail still lists the addresses of a broadcast long gone (REG-MISSEVAN-004).
@immutable
final class MissevanRoomData {
  /// Creates the data.
  const new({this.hls, this.flv});

  /// `channel.hls_pull_url`: an HLS media playlist.
  final String? hls;

  /// `channel.flv_pull_url`: HTTP-FLV.
  final String? flv;
}

/// Pure parsing of Missevan (猫耳 FM) responses (3.x's `MissevanApi`). Each
/// function takes the response text and status and returns 3.x's models or
/// throws a `SiteError`.
///
/// Every API answer is `{code, info}` under `fm.missevan.com/api/v2/`; 3.x
/// checked each one strictly and so does this: a page whose echo, size or
/// rows do not match is `ApiChanged`, never a short page, and an unknown
/// error code is never taken for "offline".
///
/// An audio platform: a broadcast carries AAC with a 16×16 H.264 placeholder
/// picture. As in 3.x nothing here calls a room audio-only; the player goes
/// by the tracks it finds.
abstract final class MissevanApi {
  /// Web origin: the `Origin` of every request, and with a slash its
  /// `Referer`.
  static const String origin = 'https://fm.missevan.com';

  /// The user agent 3.x sent to the API and the media CDN
  /// (`MissevanApi.playHeaders`).
  static const String userAgent = 'Mozilla/5.0';

  /// Headers of the API and media requests (3.x's `playHeaders`, which its
  /// `PlaybackHeaderResolver` also gave the player and the recorder). No
  /// cookie: 3.x's Missevan was anonymous.
  static const Map<String, String> headers = {'referer': '$origin/', 'origin': origin, 'user-agent': userAgent};

  /// Rows the directory answers per page; a page may carry more (promoted
  /// rooms), never a different echo (REG-MISSEVAN-001).
  static const int serverPageSize = 20;

  /// Largest answer 3.x accepted (1 MiB).
  static const int responseLimit = 1024 * 1024;

  /// How long before `expires` a pull URL is renewed (3.x's
  /// `getPlayUrlRefreshAt`).
  static const Duration leaseLead = Duration(minutes: 1);

  /// Id and name of the one category the areas are listed under (3.x used
  /// the platform's).
  static const String categoryId = _site;

  /// See [categoryId].
  static const String categoryName = '猫耳 FM';

  /// A room or area id: 1–18 digits, no leading zero.
  static final RegExp idPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  /// The area namespaces of `meta/data` tabs and the list parameter each is
  /// asked with. A catalog and a tag with the same number are different
  /// areas (REG-MISSEVAN-003); `list` (团播, team broadcasts) appeared after
  /// 3.x (REG-MISSEVAN-005).
  static const Map<String, String> namespaceQuery = {'catalog': 'catalog_id', 'tag': 'tag_id', 'list': 'type'};

  /// The id field of a tab of each namespace.
  static const Map<String, String> _tabId = {'catalog': 'catalog_id', 'tag': 'tag_id', 'list': 'list_type'};

  static final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');

  // Envelope ------------------------------------------------------------------

  /// The `info` object of an answer. HTTP 401/403 is `RiskControl`, 404
  /// `NotFound`, 429 `RateLimited`, 5xx and any other status but 200
  /// `NetworkFailure` (3.x read no body then). Code 500030004 (an unknown
  /// room, sent with HTTP 404) is `NotFound`; any other code but 0, a body
  /// over [responseLimit] or not a JSON object is `ApiChanged`.
  static Map<String, dynamic> info(String body, {required String what, int status = 200}) {
    switch (status) {
      case 200:
        break;
      case 401 || 403:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw NotFound(_site, '$what: HTTP 404');
      case 429:
        throw RateLimited(_site, detail: '$what: HTTP 429');
      default:
        throw NetworkFailure(_site, '$what: HTTP $status');
    }
    if (body.length > responseLimit || utf8.encode(body).length > responseLimit) {
      throw ApiChanged(_site, '$what: answer over $responseLimit bytes');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
    }
    final root = _object(decoded, what);
    final code = _integer(root['code']);
    if (code == null) throw ApiChanged(_site, '$what: no code');
    // The only code seen for an unknown room; any other failure is no proof
    // that a broadcast ended.
    if (code == 500030004) throw NotFound(_site, '$what: code $code');
    if (code != 0) throw ApiChanged(_site, '$what: code $code');
    return _object(root['info'], '$what.info');
  }

  // Catalog -------------------------------------------------------------------

  /// `meta/data`: one category, 猫耳 FM, whose areas are the tabs in the
  /// site's order: catalogs, tags and team-broadcast lists (`areaType` is the
  /// namespace). A tab of another type is skipped; 3.x failed the whole
  /// catalog on the `list` tab the site added (REG-MISSEVAN-005). A known
  /// tab without a positive id or a name, or a repeated one, still fails the
  /// whole catalog, as in 3.x.
  static List<LiveCategory> categories(String body, {int status = 200}) {
    final data = info(body, what: 'meta/data', status: status);
    final tabs = data['tabs'];
    if (tabs is! List || tabs.isEmpty || tabs.length > 100) throw const ApiChanged(_site, 'meta/data: no tabs');
    final areas = <String, LiveArea>{};
    for (final raw in tabs) {
      final tab = _object(raw, 'meta/data tab');
      final type = _text(tab['type']);
      final idField = _tabId[type];
      if (idField == null) continue;
      final id = _integer(tab[idField]);
      final name = _text(tab['name']);
      if (id == null || id <= 0 || name.isEmpty) throw ApiChanged(_site, 'meta/data: $type tab without id or name');
      final key = '$type:$id';
      if (areas.containsKey(key)) throw ApiChanged(_site, 'meta/data: repeated tab $key');
      areas[key] = LiveArea(
        platform: _site,
        areaType: type,
        typeName: categoryName,
        areaId: '$id',
        areaName: name,
        areaPic: normalizeImageUrl(tab['icon_url']),
      );
    }
    if (areas.isEmpty) throw const ApiChanged(_site, 'meta/data: no known tab');
    return [LiveCategory(id: categoryId, name: categoryName, children: areas.values.toList())];
  }

  /// The list parameter of [area] (`catalog_id`, `tag_id` or `type`, see
  /// [namespaceQuery]). Another platform's area, an unknown namespace or an
  /// id that is not a number is a caller error (`ArgumentError`), as 3.x
  /// refused them before any request.
  static Map<String, String> areaQuery(LiveArea area) {
    final parameter = namespaceQuery[area.areaType.trim().toLowerCase()];
    final id = area.areaId.trim();
    if (area.platform.trim().toLowerCase() != _site || parameter == null || !idPattern.hasMatch(id)) {
      throw ArgumentError.value(area, 'area', 'not a Missevan area');
    }
    return {parameter: id};
  }

  // Lists ---------------------------------------------------------------------

  /// A `chatroom/open/list` page (the recommendations, or one area's): its
  /// live rooms, each once, and whether page `maxpage` is still ahead.
  ///
  /// Every row is kept, including those past `pagesize` (promoted rooms), and
  /// pages go by number (REG-MISSEVAN-001); a page whose rooms were all
  /// offline still has a next page. The page must echo [page], `pagesize`
  /// 20 and a `maxpage` and `count`; a page past `maxpage` must be empty.
  static LiveDirectoryPage directoryPage(String body, {required int page, int status = 200}) {
    final data = info(body, what: 'open/list', status: status);
    final pagination = _object(data['pagination'], 'open/list.pagination');
    final maxPage = _integer(pagination['maxpage']);
    final count = _integer(pagination['count']);
    final rows = data['Datas'];
    if (_integer(pagination['p']) != page ||
        _integer(pagination['pagesize']) != serverPageSize ||
        maxPage == null ||
        maxPage < 0 ||
        count == null ||
        count < 0 ||
        rows is! List ||
        rows.length > 100 ||
        (page > maxPage && rows.isNotEmpty)) {
      throw ApiChanged(_site, 'open/list page $page: unexpected pagination $pagination');
    }
    final rooms = <String, LiveRoom>{};
    for (final raw in rows) {
      final room = _room(_object(raw, 'open/list row'));
      if (room.isLiveNow) rooms.putIfAbsent(room.roomId, () => room);
    }
    return LiveDirectoryPage(rooms: rooms.values, page: page, hasMore: page < maxPage);
  }

  /// A `chatroom/search` page: rooms live and offline, each once. The page
  /// must echo [page] and [pageSize] (checked as in [directoryPage]).
  static List<LiveRoom> searchRooms(String body, {required int page, required int pageSize, int status = 200}) {
    final data = info(body, what: 'chatroom/search', status: status);
    final pagination = _object(data['pagination'], 'chatroom/search.pagination');
    final maxPage = _integer(pagination['maxpage']);
    final count = _integer(pagination['count']);
    final rows = data['data'];
    if (_integer(pagination['p']) != page ||
        _integer(pagination['pagesize']) != pageSize ||
        maxPage == null ||
        maxPage < 0 ||
        count == null ||
        count < 0 ||
        rows is! List ||
        rows.length > 100 ||
        (page > maxPage && rows.isNotEmpty)) {
      throw ApiChanged(_site, 'chatroom/search page $page: unexpected pagination $pagination');
    }
    final rooms = <String, LiveRoom>{};
    for (final raw in rows) {
      final room = _room(_object(raw, 'chatroom/search row'));
      rooms.putIfAbsent(room.roomId, () => room);
    }
    return rooms.values.toList();
  }

  /// Whether [keyword] is something `chatroom/search` accepts: at most 100
  /// characters, no control characters (3.x's check).
  static bool isSearchable(String keyword) {
    final text = keyword.trim();
    return text.isNotEmpty && text.length <= 100 && !_control.hasMatch(text);
  }

  // Rooms ---------------------------------------------------------------------

  /// `live/{id}`: the room [roomId] as 3.x read it, under that id.
  ///
  /// The row as in the lists; the creator's avatar and introduction, the
  /// follower count (`attention_count`) and, for a live room when [media]
  /// is set, the pull URLs ([MissevanRoomData]). A live room without either
  /// URL, or with one that is not a `*.bilivideo.com` address of its kind,
  /// is `ApiChanged`. An offline room lists the URLs of an old broadcast;
  /// they are ignored (REG-MISSEVAN-004). There is no area name here.
  ///
  /// A room or creator other than the one asked for is `ApiChanged`.
  static LiveRoom detail(String body, {required String roomId, bool media = true, int status = 200}) {
    final data = info(body, what: 'live/$roomId', status: status);
    final row = _object(data['room'], 'live.room');
    var room = _room(row);
    if (room.roomId != roomId) throw ApiChanged(_site, 'live/$roomId answered room ${room.roomId}');
    final rawCreator = data['creator'];
    if (rawCreator != null) {
      final creator = _object(rawCreator, 'live.creator');
      if (_id(creator['user_id'], 'live.creator.user_id') != room.userId) {
        throw ApiChanged(_site, 'live/$roomId: the creator does not own the room');
      }
      room = room.copyWith(avatar: normalizeImageUrl(creator['iconurl']), introduction: _text(creator['introduction']));
    }
    final followers = _integer(_object(row['statistics'], 'live.room.statistics')['attention_count']);
    if (followers != null && followers >= 0) room = room.copyWith(followers: '$followers');
    if (!room.isLiveNow || !media) return room;
    final channel = _object(row['channel'], 'live.room.channel');
    String? pull(String key, StreamFormat format) {
      final raw = channel[key];
      if (raw == null || raw == '') return null;
      return mediaUrl(_text(raw), format: format);
    }

    final hls = pull('hls_pull_url', StreamFormat.hls);
    final flv = pull('flv_pull_url', StreamFormat.flv);
    if (hls == null && flv == null) throw ApiChanged(_site, 'live/$roomId: live without pull URLs');
    return room.copyWith(
      data: MissevanRoomData(hls: hls, flv: flv),
    );
  }

  /// A room row of the lists, the search and the detail: `status.open` 1 is
  /// live, 0 offline, anything else `ApiChanged`; `statistics.score` is the
  /// heat the site shows (not viewers: `online` is always 0,
  /// REG-MISSEVAN-002). The introduction is the creator's, the notice the
  /// room's announcement, the area the catalog name.
  static LiveRoom _room(Map<String, dynamic> row) {
    final id = _id(row['room_id'], 'room_id');
    final open = _integer(_object(row['status'], 'room $id status')['open']);
    if (open != 0 && open != 1) throw ApiChanged(_site, 'room $id: status.open ${row['status']}');
    final score = _integer(_object(row['statistics'], 'room $id statistics')['score']);
    if (score != null && score < 0) throw ApiChanged(_site, 'room $id: score $score');
    final heat = score?.toString() ?? '';
    return LiveRoom(
      roomId: id,
      platform: _site,
      userId: _id(row['creator_id'], 'room $id creator_id'),
      link: roomUrl(id),
      title: _text(row['name']),
      nick: _text(row['creator_username']),
      cover: normalizeImageUrl(row['cover_url']),
      avatar: normalizeImageUrl(row['creator_iconurl']),
      introduction: _text(row['creator_introduction']),
      notice: _text(row['announcement']),
      area: _text(row['catalog_name']),
      watching: heat,
      popularity: heat,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: open == 1 ? LiveStatus.live : LiveStatus.offline,
    );
  }

  /// The room's web page.
  static String roomUrl(String roomId) => '$origin/live/$roomId';

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities of a live room: one per transport, HLS (`hls`, sort 2)
  /// first, then FLV (`flv`, sort 1), labelled by it. Both carry the one
  /// stream the site offers (`qn=10000`); a quality's data is its URL.
  static List<LivePlayQuality> qualities(MissevanRoomData data) {
    final qualities = <LivePlayQuality>[];
    for (final (id, url) in [('hls', data.hls), ('flv', data.flv)]) {
      if (url == null) continue;
      qualities.add(
        LivePlayQuality(
          quality: id.toUpperCase(),
          id: id,
          sort: 2 - qualities.length,
          data: List<String>.unmodifiable([url]),
        ),
      );
    }
    return List.unmodifiable(qualities);
  }

  /// The line of a [qualities] quality, with the media headers and the
  /// lease of its `expires`; the quality is applied as asked (the site has
  /// one stream).
  static LivePlayUrlResolution resolution(LivePlayQuality quality) {
    final data = quality.data;
    return LivePlayUrlResolution.lines([
      for (final item in data is List ? data : const <Object?>[])
        if ('$item'.trim() case final url when url.isNotEmpty)
          LivePlayLine(
            url,
            headers: headers,
            format: formatOf(url),
            lineId: '${quality.selectionId}',
            lease: lease(url),
          ),
    ], appliedQualityData: quality.selectionId);
  }

  /// [value] as an https pull URL of [format] (3.x's `mediaUrl`, like the
  /// site's own player): http(s) on a `*.bilivideo.com` host, the default
  /// port, no user info or fragment, a `.m3u8` or `.flv` path, at most one
  /// ten-digit `expires`. The signed query is kept as written. Anything
  /// else is `ApiChanged`.
  static String mediaUrl(String value, {required StreamFormat format}) {
    final uri = Uri.tryParse(value);
    if (uri == null || !_isPullUrl(uri, format)) throw ApiChanged(_site, 'pull URL: unexpected ${format.name} address');
    return uri.replace(scheme: 'https', port: 443).toString();
  }

  static bool _isPullUrl(Uri uri, StreamFormat format) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        !uri.host.endsWith('.bilivideo.com') ||
        !uri.path.endsWith(format == StreamFormat.hls ? '.m3u8' : '.flv')) {
      return false;
    }
    try {
      final expires = uri.queryParametersAll['expires'];
      return expires == null || (expires.length == 1 && RegExp(r'^[0-9]{10}$').hasMatch(expires.single));
    } on FormatException {
      return false;
    }
  }

  /// The container of a pull URL by its path: `.m3u8` HLS, else FLV (3.x's
  /// rule).
  static StreamFormat formatOf(String url) =>
      (Uri.tryParse(url)?.path ?? '').endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;

  /// The lease of a pull URL: it stops at `expires` (Unix seconds, about two
  /// hours after issue) and is renewed [leaseLead] before, as in 3.x. An
  /// HLS playlist is fetched again and again, so its expiry ends playback;
  /// an established FLV connection keeps flowing (the same CDN as
  /// Bilibili). Null for a URL that is not a pull URL or has no `expires`.
  static PlayLease? lease(String url) {
    final uri = Uri.tryParse(url);
    final format = formatOf(url);
    if (uri == null || !_isPullUrl(uri, format)) return null;
    final expires = int.tryParse(uri.queryParameters['expires'] ?? '');
    if (expires == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    return PlayLease(
      refreshAt: expiresAt.subtract(leaseLead),
      expiresAt: expiresAt,
      cutsConnection: format == StreamFormat.hls,
    );
  }

  // Links ---------------------------------------------------------------------

  /// The room of a `fm.missevan.com/live/{id}` link (3.x's `roomFromUri`):
  /// http(s), that host exactly, the default port, no user info, and the
  /// path `live/{id}` with at most a trailing slash; a query is allowed.
  static String? roomIdFromUri(Uri? uri) {
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host != 'fm.missevan.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final List<String> parts;
    try {
      parts = uri.pathSegments.toList();
    } on FormatException {
      return null;
    }
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    return parts.length == 2 && parts.first == 'live' && idPattern.hasMatch(parts.last) ? parts.last : null;
  }
}

// Helpers ---------------------------------------------------------------------

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw ApiChanged(_site, '$what: expected an object');
}

/// 3.x's `_integer`: an int, or a string that parses as one.
int? _integer(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

/// 3.x's `_text`: a string trimmed, anything else empty.
String _text(Object? value) => value is String ? value.trim() : '';

/// An id field (number or string) as 3.x's `roomId('$value')` read it;
/// `ApiChanged` when it is not one.
String _id(Object? value, String what) {
  final text = '$value'.trim();
  if (!MissevanApi.idPattern.hasMatch(text)) throw ApiChanged(_site, '$what: $value');
  return text;
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
