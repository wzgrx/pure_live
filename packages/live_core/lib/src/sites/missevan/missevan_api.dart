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

/// What a danmaku connection needs to join one room's chat (13-2, M5).
///
/// 3.x had no Missevan danmaku (`EmptyDanmaku`). The archived v4 joined
/// anonymously: a guest session first ([MissevanApi.guestSession] sets the
/// `FM_SESS` cookie; the connection asks for it itself, nothing is stored),
/// then [url] with that cookie and [headers], and a join message for
/// [roomId]; its `room/statistics` messages carry the real listener count.
/// Room entry hands these over without a request, live or not (an offline
/// room's answer lists its socket too). Whether and how the app connects is
/// the danmaku module's decision (M5).
@immutable
final class MissevanDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId, required this.url, this.headers = MissevanApi.headers});

  /// The room number, sent (as a number) in the join message.
  final String roomId;

  /// The room's socket: the detail's `websocket` entry
  /// (`wss://im.missevan.com/ws?room_id=…`), or that form when the answer
  /// lists none the adapter accepts.
  final Uri url;

  /// Handshake headers besides the session cookie: the API headers
  /// ([MissevanApi.headers]; the server checks `Origin`).
  final Map<String, String> headers;

  @override
  String toString() => 'MissevanDanmakuArgs($roomId, $url)';
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
///
/// The M4.U upgrades (docs/specs/UPGRADES.md rows 13-1 to 13-4 and the unified
/// principles): one 原画 quality with FLV and HLS lines, the danmaku
/// arguments, the catalog grouped by namespace, long keywords cut, start
/// times, no restriction for a playable live room, unreadable rows skipped
/// and the site's placeholder cover left empty.
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

  /// The name of the one category 3.x listed every tab under; areas it
  /// stored carry it as their `typeName` (M9 may rename them by
  /// [namespaceNames]; their identity does not change).
  static const String legacyCategoryName = '猫耳 FM';

  /// The categories the tabs are grouped in (13-3), by namespace: their
  /// `LiveCategory.id` is the namespace and their name this one, the
  /// archived v4's grouping.
  static const Map<String, String> namespaceNames = {'catalog': '分区', 'list': '团播', 'tag': '标签'};

  /// A room or area id: 1–18 digits, no leading zero.
  static final RegExp idPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  /// The area namespaces of `meta/data` tabs and the list parameter each is
  /// asked with. A catalog and a tag with the same number are different
  /// areas (REG-MISSEVAN-003); `list` (团播, team broadcasts) appeared after
  /// 3.x (REG-MISSEVAN-005).
  static const Map<String, String> namespaceQuery = {'catalog': 'catalog_id', 'tag': 'tag_id', 'list': 'type'};

  /// The id field of a tab of each namespace.
  static const Map<String, String> _tabId = {'catalog': 'catalog_id', 'tag': 'tag_id', 'list': 'list_type'};

  /// The longest keyword `chatroom/search` is sent, in characters (3.x's
  /// limit, 13-4).
  static const int maxKeywordLength = 100;

  static final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');

  /// The id of the room's one quality (13-1): the CDN's quality code the
  /// pull URLs carry (`qn=10000`, the source), as the archived v4 had it.
  static const String originalQualityId = '10000';

  /// The name of that quality (the unified naming: the source is 原画).
  static const String originalQualityName = '原画';

  /// 3.x's quality ids → the quality that plays the same stream now, for M9
  /// to migrate a stored quality preference. 3.x listed each transport as a
  /// quality of its own (`hls` 'HLS', `flv` 'FLV'), both the one stream the
  /// site offers; they are now the two lines of [originalQualityId].
  static const Map<String, String> legacyQualityIds = {'hls': originalQualityId, 'flv': originalQualityId};

  /// The quality id for a 3.x one ([legacyQualityIds]); any other id is kept.
  static String qualityIdFromLegacy(String id) => legacyQualityIds[id.trim().toLowerCase()] ?? id.trim();

  /// The guest session the danmaku socket needs (`Set-Cookie: FM_SESS`,
  /// three days; sample S05-user-info). Only the danmaku connection asks
  /// for it (M5); the API and media need no cookie.
  static final Uri guestSession = Uri.https('fm.missevan.com', '/api/user/info');

  /// The site's default picture (a grey cat) that rows without a cover of
  /// their own carry as `cover_url`: a stand-in, left empty so that it never
  /// replaces a stored cover (the unified placeholder rule).
  static const String placeholderCover = 'https://static.maoercdn.com/avatars/icon01.png';

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

  /// `meta/data`: the tabs grouped by namespace (13-3), one category each,
  /// in the order the site first lists a tab of it: 分区 (`catalog`), 团播
  /// (`list`) and 标签 (`tag`) in [namespaceNames]; areas keep the site's
  /// order within their group. An area's `areaType` is its namespace and
  /// its `typeName` the group's name (3.x put every tab under one category,
  /// 猫耳 FM).
  ///
  /// A tab of another type is skipped (3.x failed the whole catalog on the
  /// `list` tab the site added, REG-MISSEVAN-005), and so is a tab without
  /// a positive id or a name, or one that repeats an earlier tab (3.x
  /// failed the whole catalog; the unified "容错" rule). No usable tab at
  /// all is `ApiChanged`.
  static List<LiveCategory> categories(String body, {int status = 200}) {
    final data = info(body, what: 'meta/data', status: status);
    final tabs = data['tabs'];
    if (tabs is! List || tabs.isEmpty || tabs.length > 100) throw const ApiChanged(_site, 'meta/data: no tabs');
    final groups = <String, Map<String, LiveArea>>{};
    for (final raw in tabs) {
      if (raw is! Map<String, dynamic>) continue;
      final type = _text(raw['type']);
      final idField = _tabId[type];
      final id = idField == null ? null : _integer(raw[idField]);
      final name = _text(raw['name']);
      if (id == null || id <= 0 || name.isEmpty) continue;
      groups
          .putIfAbsent(type, () => {})
          .putIfAbsent(
            '$id',
            () => LiveArea(
              platform: _site,
              areaType: type,
              typeName: namespaceNames[type]!,
              areaId: '$id',
              areaName: name,
              areaPic: normalizeImageUrl(raw['icon_url']),
            ),
          );
    }
    if (groups.isEmpty) throw const ApiChanged(_site, 'meta/data: no usable tab');
    return [
      for (final MapEntry(key: type, value: areas) in groups.entries)
        LiveCategory(id: type, name: namespaceNames[type]!, children: areas.values.toList()),
    ];
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
  /// A row that cannot be read is skipped (3.x failed the page; the unified
  /// "容错" rule), but a page none of whose rows can be read is
  /// `ApiChanged`, never an empty page.
  ///
  /// The promoted rows of page 1 come again at their place on a later page
  /// (2026-09-29: 2 of 436 rows); the directory list drops rooms it already
  /// shows, as 3.x's did.
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
    for (final room in _rows(rows, 'open/list page $page')) {
      if (room.isLiveNow) rooms.putIfAbsent(room.roomId, () => room);
    }
    return LiveDirectoryPage(rooms: rooms.values, page: page, hasMore: page < maxPage);
  }

  /// A `chatroom/search` page: rooms live and offline, each once. The page
  /// must echo [page] and [pageSize], and rows are read, as in
  /// [directoryPage]. Search rows carry no start time.
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
    for (final room in _rows(rows, 'chatroom/search page $page')) {
      rooms.putIfAbsent(room.roomId, () => room);
    }
    return rooms.values.toList();
  }

  /// The rooms of the [rows] that can be read ([_room]); none of several is
  /// `ApiChanged`.
  static List<LiveRoom> _rows(List<dynamic> rows, String what) {
    final rooms = <LiveRoom>[];
    for (final raw in rows) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        rooms.add(_room(raw));
      } on ApiChanged {
        continue;
      }
    }
    if (rooms.isEmpty && rows.isNotEmpty) throw ApiChanged(_site, '$what: no readable row');
    return rooms;
  }

  /// [keyword] as `chatroom/search` is asked for it: trimmed and, when
  /// longer, cut to its first [maxKeywordLength] characters (Unicode code
  /// points, so an emoji is never split) and trimmed again (13-4; 3.x
  /// refused a longer keyword and the search page said the search failed;
  /// the site takes longer ones, checked 2026-09-29). Null for a blank
  /// keyword or one with control characters, which 3.x refused too.
  static String? searchKeyword(String keyword) {
    final text = keyword.trim();
    if (text.isEmpty || _control.hasMatch(text)) return null;
    final runes = text.runes;
    return runes.length <= maxKeywordLength ? text : String.fromCharCodes(runes.take(maxKeywordLength)).trimRight();
  }

  /// Whether `chatroom/search` can be asked for [keyword] ([searchKeyword]).
  static bool isSearchable(String keyword) => searchKeyword(keyword) != null;

  // Rooms ---------------------------------------------------------------------

  /// `live/{id}`: the room [roomId] as 3.x read it, under that id.
  ///
  /// The row as in the lists (with its start time); the creator's avatar and
  /// introduction, the follower count (`attention_count`) and, for a live
  /// room when [media] is set, the pull URLs ([MissevanRoomData]) and no
  /// restriction ([LiveRestriction.none]: the site hands them to anyone).
  /// A pull URL that is not a `*.bilivideo.com` address of its kind is left
  /// out, so only that line is missing (3.x failed the room; the unified
  /// "容错" rule); a live room with neither URL is `ApiChanged`. An offline
  /// room lists the URLs of an old broadcast; they are ignored
  /// (REG-MISSEVAN-004). There is no area name here.
  ///
  /// [withDanmaku] adds the danmaku arguments ([danmakuArgs]), live or not.
  ///
  /// A room or creator other than the one asked for is `ApiChanged`.
  static LiveRoom detail(
    String body, {
    required String roomId,
    bool media = true,
    bool withDanmaku = false,
    int status = 200,
  }) {
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
    if (withDanmaku) room = room.copyWith(danmakuData: danmakuArgs(data, roomId: room.roomId));
    if (!room.isLiveNow || !media) return room;
    final channel = _object(row['channel'], 'live.room.channel');
    String? pull(String key, StreamFormat format) {
      final raw = channel[key];
      if (raw is! String || raw.trim().isEmpty) return null;
      try {
        return mediaUrl(raw.trim(), format: format);
      } on ApiChanged {
        return null;
      }
    }

    final hls = pull('hls_pull_url', StreamFormat.hls);
    final flv = pull('flv_pull_url', StreamFormat.flv);
    if (hls == null && flv == null) throw ApiChanged(_site, 'live/$roomId: live without a usable pull URL');
    return room.copyWith(
      data: MissevanRoomData(hls: hls, flv: flv),
      restriction: LiveRestriction.none,
    );
  }

  /// The danmaku arguments of a `live/{id}` answer's `info`: the first
  /// `websocket` entry that is a `wss` URL on `missevan.com` or a subdomain,
  /// without user info, for this room when it names one; else
  /// `wss://im.missevan.com/ws?room_id={roomId}`, the form the site uses.
  /// The session cookie goes to that host, hence the check.
  static MissevanDanmakuArgs danmakuArgs(Map<String, dynamic> info, {required String roomId}) {
    final sockets = info['websocket'];
    for (final raw in sockets is List ? sockets : const <Object?>[]) {
      final uri = raw is String ? Uri.tryParse(raw.trim()) : null;
      if (uri == null ||
          uri.scheme != 'wss' ||
          uri.userInfo.isNotEmpty ||
          (uri.host != 'missevan.com' && !uri.host.endsWith('.missevan.com'))) {
        continue;
      }
      final String? named;
      try {
        named = uri.queryParameters['room_id'];
      } on FormatException {
        continue;
      }
      if (named == null || named == roomId) return MissevanDanmakuArgs(roomId: roomId, url: uri);
    }
    return MissevanDanmakuArgs(
      roomId: roomId,
      url: Uri(scheme: 'wss', host: 'im.missevan.com', path: '/ws', queryParameters: {'room_id': roomId}),
    );
  }

  /// A room row of the lists, the search and the detail: `status.open` 1 is
  /// live, 0 offline, anything else `ApiChanged`; `statistics.score` is the
  /// heat the site shows (not viewers: `online` is always 0,
  /// REG-MISSEVAN-002). The introduction is the creator's, the notice the
  /// room's announcement, the area the catalog name. A live row's start is
  /// `status.open_time` (epoch milliseconds; the lists and the detail have
  /// it, the search does not); an offline row's is the last broadcast's, so
  /// none. The site's default picture as the cover is left empty
  /// ([placeholderCover]).
  static LiveRoom _room(Map<String, dynamic> row) {
    final id = _id(row['room_id'], 'room_id');
    final state = _object(row['status'], 'room $id status');
    final open = _integer(state['open']);
    if (open != 0 && open != 1) throw ApiChanged(_site, 'room $id: status.open ${row['status']}');
    final score = _integer(_object(row['statistics'], 'room $id statistics')['score']);
    if (score != null && score < 0) throw ApiChanged(_site, 'room $id: score $score');
    final heat = score?.toString() ?? '';
    final cover = normalizeImageUrl(row['cover_url']);
    return LiveRoom(
      roomId: id,
      platform: _site,
      userId: _id(row['creator_id'], 'room $id creator_id'),
      link: roomUrl(id),
      title: _text(row['name']),
      nick: _text(row['creator_username']),
      cover: _isPlaceholderCover(cover) ? '' : cover,
      avatar: normalizeImageUrl(row['creator_iconurl']),
      introduction: _text(row['creator_introduction']),
      notice: _text(row['announcement']),
      area: _text(row['catalog_name']),
      watching: heat,
      popularity: heat,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: open == 1 ? LiveStatus.live : LiveStatus.offline,
      startedAt: open == 1 ? startedAt(state['open_time']) : null,
    );
  }

  /// `status.open_time` as a time: epoch milliseconds from 2000 on (13
  /// digits); null for anything else (0, blank, seconds, not a number).
  static DateTime? startedAt(Object? value) => switch (_integer(value)) {
    final int milliseconds when milliseconds >= 946684800000 && milliseconds < 10000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    _ => null,
  };

  static bool _isPlaceholderCover(String url) {
    final uri = Uri.tryParse(url);
    final placeholder = Uri.parse(placeholderCover);
    return uri != null && uri.host == placeholder.host && uri.path == placeholder.path;
  }

  /// The room's web page.
  static String roomUrl(String roomId) => '$origin/live/$roomId';

  // Streams -------------------------------------------------------------------

  /// The room's one quality (13-1): 原画 ([originalQualityId]), whose
  /// lines are the pull URLs, FLV first and HLS as its backup (the archived
  /// v4's order: the FLV connection outlives its signature, the HLS
  /// playlist does not). 3.x listed each transport as a quality of its own
  /// (HLS first) though both carry the one stream the site offers
  /// (`qn=10000`); [legacyQualityIds] maps those ids. The quality's data is
  /// its URLs. No quality without a URL.
  static List<LivePlayQuality> qualities(MissevanRoomData data) {
    final urls = [?data.flv, ?data.hls];
    if (urls.isEmpty) return const [];
    return List.unmodifiable([
      LivePlayQuality(quality: originalQualityName, id: originalQualityId, data: List<String>.unmodifiable(urls)),
    ]);
  }

  /// The lines of a [qualities] quality in its order, each with the media
  /// headers, its transport as the line id (`flv`, `hls`) and the lease of
  /// its `expires`; the quality is applied as asked (the site has one
  /// stream).
  static LivePlayUrlResolution resolution(LivePlayQuality quality) {
    final data = quality.data;
    return LivePlayUrlResolution.lines([
      for (final item in data is List ? data : const <Object?>[])
        if ('$item'.trim() case final url when url.isNotEmpty)
          LivePlayLine(url, headers: headers, format: formatOf(url), lineId: formatOf(url).name, lease: lease(url)),
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
