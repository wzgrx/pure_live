import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'kugoulive';

/// The state of a room as the room info answers it (3.x's
/// `KugouLiveState`).
enum KugouLiveState {
  /// A live session (`liveSessionId`), camera or phone.
  live,

  /// `liveType` -1.
  offline,

  /// `limitType` above 0: the platform limits who may watch. Shown as
  /// unknown with 3.x's notice; the stream is refused.
  restricted,

  /// Neither: no session and not offline. Shown as unknown.
  unknown,
}

/// One quality of a room: the streams of one protocol, bitrate tier, codec
/// and layout, gathered from every line of the stream answer (3.x's
/// `KugouLiveVariant`).
@immutable
final class KugouLiveVariant {
  /// Creates the variant.
  new({
    required this.id,
    required this.protocol,
    required this.rate,
    required this.codec,
    required this.layout,
    required List<LivePlayLine> lines,
  }) : lines = List.unmodifiable(lines);

  /// `<protocol>:<rate>:<codec>:<layout>` (`flv:4:1:2`), the quality id.
  final String id;

  /// `flv` or `hls`.
  final String protocol;

  /// The platform's bitrate tier (`streamProfiles[].rate`).
  final int rate;

  /// The platform's codec number (1 is H.264).
  final int codec;

  /// The platform's layout number.
  final int layout;

  /// One line per distinct URL, in the answer's order of lines.
  final List<LivePlayLine> lines;
}

/// What room entry keeps for playback (3.x kept its `KugouLiveRoom`
/// snapshot, variants included, in `data`): the variants of a live room, or
/// why there is nothing to play.
@immutable
final class KugouLiveRoomData {
  /// Creates the data; [unavailable] is required when [variants] is empty.
  new({required this.roomId, List<KugouLiveVariant> variants = const [], this.unavailable})
    : variants = List.unmodifiable(variants),
      assert(variants.isNotEmpty || unavailable != null, 'an empty playback needs its reason');

  /// The room the data belongs to.
  final String roomId;

  /// Best first (3.x's order: bitrate tier, then the answer's order).
  final List<KugouLiveVariant> variants;

  /// Why there is nothing to play: offline, restricted, no live session, no
  /// stream in the answer.
  final SiteError? unavailable;
}

/// Pure parsing of Kugou Live (繁星, fanxing.kugou.com) responses and links
/// (3.x's `KugouLiveApi`, `KugouLiveLink` and the card rules of
/// `KugouLiveSite`). Each function takes the response text and status and
/// returns 3.x's models or throws a `SiteError`.
///
/// Anonymous and public: the home page lists the areas, the `mfanxing-home`
/// CDN lists rooms, `pt_search` answers JSONP, `getEnterRoomInfo` is the
/// room and `mutiline/streamaddr` its signed Tencent Cloud FLV lines. A
/// room is its number, 3 to 11 digits.
abstract final class KugouLiveApi {
  /// The website, Origin of every request.
  static const String webOrigin = 'https://fanxing.kugou.com';

  /// The host of the room lists, the search and the stream answer.
  static const String apiHost = 'fx1.service.kugou.com';

  /// The host of the room info.
  static const String roomHost = 'service2.fanxing.kugou.com';

  /// 3.x's desktop Chrome UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's request headers (`apiHeaders`), for every request, the home page
  /// included.
  static const Map<String, String> apiHeaders = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': webOrigin,
    'referer': '$webOrigin/',
  };

  /// Media request headers of room [roomId] (3.x's `mediaHeaders`, which it
  /// wrote into every room's `httpHeaders`; its player never sent them, see
  /// docs/modules/M4.29-kugoulive.md). The CDN serves the FLV with and
  /// without them.
  static Map<String, String> mediaHeaders(String roomId) => {
    'user-agent': userAgent,
    'origin': webOrigin,
    'referer': roomUrl(roomId),
  };

  /// The largest answer read (3.x's `responseLimit`, 4 MiB).
  static const int responseLimit = 4 * 1024 * 1024;

  /// Display name (3.x's zh.json `site_kugoulive`), also the category, the
  /// areas' type and every room's area.
  static const String siteName = '酷狗直播';

  /// 3.x's zh.json `kugoulive_directory_scope`, the directory notice's text.
  static const String directoryScope = '官网推荐与分类目录采用原生分页；原生搜索同时返回开播和未开播主播，精确房间号及 fanxing.kugou.com 官方链接可直接解析房间状态。';

  /// The notice of every room (3.x's zh.json `kugoulive_chat_notice`).
  static const String chatNotice = '酷狗远端聊天尚待接入；viewerNum/getViewerNum 按当前观看人数展示，hot 按平台热度展示，fansCount 单独作为粉丝数。';

  /// The first notice line of a restricted room (3.x's zh.json
  /// `kugoulive_restricted_notice`).
  static const String restrictedNotice = '该酷狗直播受访问范围限制，界面保持未知状态，不将其显示成未开播。';

  /// The area of the recommendations (推荐), listed by the home page too; its
  /// rooms come from the recommendation list, not `list_v4`.
  static const String recommendAreaId = '8000';

  /// The area type of the home page's areas (3.x).
  static const String areaType = 'official';

  /// The last page asked for (3.x).
  static const int maxPage = 10000;

  /// Streamers one search asks for (3.x's `nums=200,0,0,0`); they are paged
  /// locally.
  static const int searchSize = 200;

  /// The largest page of a search (3.x).
  static const int maxSearchPageSize = 100;

  /// The longest keyword searched (3.x).
  static const int maxKeywordLength = 100;

  /// How long before `txTime` a media URL is renewed (3.x's
  /// `mediaRefreshAt`).
  static const Duration leaseLead = Duration(minutes: 5);

  /// 3.x's areas when the home page lists none.
  static const List<({String id, String name})> fallbackAreas = [
    (id: '8000', name: '推荐'),
    (id: '100001', name: '一起玩'),
    (id: '100002', name: '音乐'),
    (id: '31050', name: '高清'),
    (id: '7024', name: '舞蹈'),
    (id: '1009', name: '颜值'),
    (id: '1001', name: '新秀'),
    (id: '3007', name: '酷次元'),
    (id: '7041', name: '搞笑'),
    (id: '31', name: '国风'),
    (id: '6201', name: '游戏女神'),
    (id: '6007', name: '王者荣耀'),
    (id: '6004', name: '和平精英'),
    (id: '6003', name: '网游竞技'),
  ];

  /// The home page's personal routes: 关注, 我看过的, 我管理的, 我守护的.
  static const Set<String> _personalRoutes = {'3001', '3009', '3014', '3015'};

  // Links ---------------------------------------------------------------------

  static final RegExp _roomId = RegExp(r'^[1-9]\d{2,10}$');

  static const Set<String> _hosts = {'fanxing.kugou.com', 'mfanxing.kugou.com'};

  /// [raw] as a room (3.x's `KugouLiveLink.parseRoomId`): a trimmed room
  /// number, or a room link (see [roomIdFromUrl]); null for anything else.
  static String? parseRoomId(String raw) {
    final value = raw.trim();
    if (_roomId.hasMatch(value)) return value;
    return roomIdFromUrl(value);
  }

  /// The room of a room link (3.x's `KugouLiveLink.parseRoomId`): http(s)
  /// on `fanxing.kugou.com` or `mfanxing.kugou.com`, the default port, no
  /// user info or fragment; the path is one room number, or empty with a
  /// `roomId` query. Null for anything else, a room number alone included.
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        !_hosts.contains(uri.host.toLowerCase()) ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    try {
      final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList(growable: false);
      if (segments.length == 1 && _roomId.hasMatch(segments.single)) return segments.single;
      final queryId = uri.queryParameters['roomId']?.trim();
      return segments.isEmpty && queryId != null && _roomId.hasMatch(queryId) ? queryId : null;
    } on FormatException {
      // Undecodable escapes (`/%FF`): not a room link.
      return null;
    }
  }

  /// The room page of [roomId] (3.x's `KugouLiveLink.watchUrl`, the room's
  /// `link`).
  static String roomUrl(String roomId) => '$webOrigin/$roomId';

  // Answers -------------------------------------------------------------------

  /// The failure of an answer's status (3.x's `_throwStatus`): 400/422 a
  /// broken request, 401/403 refused, 451 blocked, 404/410 missing, 429
  /// throttled, 5xx and anything else (3xx included: redirects are not
  /// followed) a network failure. Null for 2xx.
  static SiteError? statusError(int status, String what) => switch (status) {
    >= 200 && < 300 => null,
    400 || 422 => ApiChanged(_site, '$what: HTTP $status'),
    401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
    451 => RegionBlocked(_site, '$what: HTTP 451'),
    404 || 410 => NotFound(_site, '$what: HTTP $status'),
    429 => RateLimited(_site, detail: '$what: HTTP 429'),
    _ => NetworkFailure(_site, '$what: HTTP $status'),
  };

  /// [body] decoded as JSON after the status and size checks.
  static Object? _decode(String body, {required String what, required int status}) {
    if (statusError(status, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  /// The `data` of a `{code: 0, data: {...}}` answer (3.x's
  /// `_responseData`): another code, or an empty or missing `data`, is
  /// `ApiChanged`.
  static Map<String, Object?> _data(String body, {required String what, required int status}) {
    final root = _map(_decode(body, what: what, status: status));
    final code = jsonInt(root?['code']);
    if (code != 0) throw ApiChanged(_site, '$what: code $code ${jsonString(root?['msg']) ?? ''}'.trim());
    final data = _map(root!['data']);
    if (data == null || data.isEmpty) throw ApiChanged(_site, '$what: no data');
    return data;
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : null;

  static List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

  /// 3.x's `_string`: the trimmed text of any value, '' for null.
  static String _text(Object? value) => jsonString(value) ?? '';

  /// The first of [values] with text other than `null` (3.x's `_firstText`).
  static String _firstText(List<Object?> values, {required String fallback}) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty && text != 'null') return text;
    }
    return fallback;
  }

  /// An image as 3.x accepted it (`_image`): a doubled `/v2/fxuserlogo/`
  /// folded, protocol-relative made https, a root-relative path put on
  /// `p3.fx.kgimg.com`, http made https; only `kgimg.com` and `kugou.com`
  /// hosts (and subdomains) on the default ports without user info. Empty
  /// for anything else.
  static String image(Object? raw) {
    var value = _text(raw);
    if (value.isEmpty || value == 'null') return '';
    value = value.replaceFirst('/v2/fxuserlogo//v2/fxuserlogo/', '/v2/fxuserlogo/');
    if (value.startsWith('//')) value = 'https:$value';
    if (value.startsWith('/')) value = 'https://p3.fx.kgimg.com$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        !(RoomPaths.hostIs(uri.host, 'kgimg.com') || RoomPaths.hostIs(uri.host, 'kugou.com'))) {
      return '';
    }
    if (uri.scheme == 'http') value = uri.replace(scheme: 'https').toString();
    return Uri.tryParse(value)?.scheme == 'https' ? value : '';
  }

  // Catalog and directory -----------------------------------------------------

  static final RegExp _areaLink = RegExp(
    r'''href=["'](?:https://fanxing\.kugou\.com)?/pcindex/category/(\d{1,8})[^"']*["'][^>]*title=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// The areas the home page links (3.x's `parseCategoriesHtml`): every
  /// `/pcindex/category/<id>` link with a `title`, in page order, once each,
  /// without the personal routes; 推荐 (8000) included. A page without such
  /// links gives 3.x's [fallbackAreas].
  static List<LiveArea> areas(String html, {int status = 200}) {
    if (statusError(status, 'home page') case final error?) throw error;
    if (html.length > responseLimit) throw const ApiChanged(_site, 'home page: over $responseLimit characters');
    final seen = <String>{};
    final found = [
      for (final match in _areaLink.allMatches(html))
        if (decodeHtmlEntities(match.group(2)!).trim() case final name
            when !_personalRoutes.contains(match.group(1)) && name.isNotEmpty && seen.add(match.group(1)!))
          (id: match.group(1)!, name: name),
    ];
    return [for (final area in found.isEmpty ? fallbackAreas : found) _area(area.id, area.name)];
  }

  static LiveArea _area(String id, String name) =>
      LiveArea(platform: _site, areaType: areaType, typeName: siteName, areaId: id, areaName: name);

  /// 3.x's catalog: one category, 酷狗直播, with the first [pageSize] of
  /// [areas].
  static List<LiveCategory> catalog(List<LiveArea> areas, int pageSize) => [
    LiveCategory(id: _site, name: siteName, children: areas.take(pageSize).toList()),
  ];

  static final RegExp _areaId = RegExp(r'^\d{1,8}$');

  /// The area id to list for [area]: 推荐 for null; a caller error for an
  /// area of another platform or type, or an id that is not 1–8 digits (3.x
  /// refused these before any request).
  static String areaId(LiveArea? area) {
    if (area == null) return recommendAreaId;
    if (area.platform != _site || area.areaType != areaType) {
      throw ArgumentError.value(area, 'category', 'not a Kugou Live area');
    }
    final id = area.areaId.trim();
    if (!_areaId.hasMatch(id)) throw ArgumentError.value(area, 'category', 'not a Kugou Live area id');
    return id;
  }

  /// A page of [areaId] (3.x's `directory`): 推荐 is `index/list`, another
  /// area `index/list_v4` with its `cid`; 3.x's parameters in its order.
  static Uri directoryUrl(int page, String areaId) {
    final recommend = areaId == recommendAreaId;
    return Uri.https(
      apiHost,
      recommend ? '/mfanxing-home/h5/cdn/room/index/list' : '/mfanxing-home/h5/cdn/room/index/list_v4',
      {
        'pid': '0',
        'kugouId': '0',
        'doubleLiveFirst': '1',
        'sysVersion': '0',
        'platform': '7',
        'device': 'PureLive-Web',
        'channel': '0',
        'version': '99999',
        'longitude': '0',
        'latitude': '0',
        'appid': '1010',
        'liveTypeFilter': '0',
        'isNew': '0',
        'entranceType': '0',
        'uiMode': '0',
        'page': '$page',
        if (!recommend) 'cid': areaId,
      },
    );
  }

  /// A room list page (3.x's `parseDirectoryJson`): the cards of `list`
  /// (`star` rows unwrapped), a room once; more pages while `hasNextPage`
  /// is 1 or true.
  static LiveDirectoryPage directoryPage(String body, {required int page, int status = 200}) {
    final data = _data(body, what: 'room list', status: status);
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final entry in _list(data['list'])) {
      final wrapper = _map(entry) ?? const {};
      final raw = wrapper['uiType'] == 'star' ? _map(wrapper['data']) ?? const {} : wrapper;
      if (card(raw) case final room? when seen.add(room.roomId)) rooms.add(room);
    }
    final more = data['hasNextPage'];
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: more == true || jsonInt(more) == 1);
  }

  /// A list or search card (3.x's `_card` and `_room`); null without a room
  /// number.
  ///
  /// - State from `liveStatus`, else `status`, else `liveType`: 1 live, 0 or
  ///   -1 offline, anything else (6, a phone broadcast, included) unknown.
  /// - Title `label`, else `topicContent`, `performContent`, the nick, else
  ///   `Kugou Live`; nick `nickName`, else `Kugou Live`.
  /// - Avatar `userLogo` (a present `logo` only when it is absent), else the
  ///   cover; cover `imgPath`, else `imagePath` (see [image]).
  /// - Viewers `viewerNum`/`getViewerNum`, popularity `hot`, followers
  ///   `fansCount`; the metric is viewers when given, else popularity.
  static LiveRoom? card(Map<String, Object?> raw) {
    final id = parseRoomId(_text(raw['roomId']));
    if (id == null) return null;
    final nick = _text(raw['nickName']);
    return _room(
      roomId: id,
      userId: _text(raw['userId']),
      kugouId: _text(raw['kugouId']),
      nick: nick.isEmpty ? 'Kugou Live' : nick,
      title: _firstText([raw['label'], raw['topicContent'], raw['performContent'], nick], fallback: 'Kugou Live'),
      avatar: image(raw['userLogo'] ?? raw['logo']),
      cover: image(raw['imgPath'] ?? raw['imagePath']),
      viewers: jsonInt(raw['viewerNum'] ?? raw['getViewerNum']),
      followers: jsonInt(raw['fansCount']),
      popularity: jsonInt(raw['hot']),
      state: switch (jsonInt(raw['liveStatus'] ?? raw['status'] ?? raw['liveType'])) {
        1 => KugouLiveState.live,
        0 || -1 => KugouLiveState.offline,
        _ => KugouLiveState.unknown,
      },
    );
  }

  /// 3.x's `KugouLiveSite._room`: the room as the interface shows it.
  static LiveRoom _room({
    required String roomId,
    required String userId,
    required String kugouId,
    required String nick,
    required String title,
    required String avatar,
    required String cover,
    required int? viewers,
    required int? followers,
    required int? popularity,
    required KugouLiveState state,
  }) {
    final online = viewers?.toString();
    final heat = popularity?.toString();
    return LiveRoom(
      platform: _site,
      roomId: roomId,
      userId: userId.isEmpty ? kugouId : userId,
      title: title,
      nick: nick,
      avatar: avatar.isEmpty ? cover : avatar,
      cover: cover,
      area: siteName,
      link: roomUrl(roomId),
      liveStatus: switch (state) {
        KugouLiveState.live => LiveStatus.live,
        KugouLiveState.offline => LiveStatus.offline,
        KugouLiveState.restricted || KugouLiveState.unknown => LiveStatus.unknown,
      },
      watching: online ?? heat ?? '',
      onlineViewers: online ?? '',
      popularity: heat ?? '',
      followers: followers?.toString() ?? '',
      audienceMetricType: online != null
          ? AudienceMetricType.onlineViewers
          : heat != null
          ? AudienceMetricType.popularity
          : AudienceMetricType.unknown,
      notice: [if (state == KugouLiveState.restricted) restrictedNotice, chatNotice].join('\n'),
    );
  }

  // Search --------------------------------------------------------------------

  /// The search of [keyword] (3.x's `search`): [searchSize] streamers, live
  /// or not, answered as JSONP to [callback].
  static Uri searchUrl(String keyword, String callback) => Uri.https(apiHost, '/pt_search/pcsearch/v1/type_all.jsonp', {
    'keywords': keyword,
    'nums': '$searchSize,0,0,0',
    'callback': callback,
  });

  static final RegExp _callbackName = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.]*$');

  /// The streamers of a search answer (3.x's `parseSearchJsonp`): JSONP to
  /// [callback] (when given) with nothing after it but `;`; `status` (else
  /// `code`) 0 or 1; the cards of `data.anchor.list`, a room once.
  static List<LiveRoom> searchRooms(String body, {String? callback, int status = 200}) {
    if (statusError(status, 'search') case final error?) throw error;
    if (body.length > responseLimit) throw const ApiChanged(_site, 'search: answer over $responseLimit characters');
    final text = body.trim();
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open <= 0 || close <= open || text.substring(close + 1).trim().replaceAll(';', '').isNotEmpty) {
      throw const ApiChanged(_site, 'search: not JSONP');
    }
    final name = text.substring(0, open).trim();
    if (!_callbackName.hasMatch(name) || (callback != null && name != callback)) {
      throw ApiChanged(_site, 'search: JSONP to $name, not $callback');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(open + 1, close));
    } on FormatException {
      throw const ApiChanged(_site, 'search: not JSON');
    }
    final root = _map(decoded) ?? const {};
    final code = jsonInt(root['status'] ?? root['code']);
    if (code != null && code != 0 && code != 1) throw ApiChanged(_site, 'search: code $code');
    final seen = <String>{};
    return [
      for (final row in _list(_map(_map(root['data'])?['anchor'])?['list']))
        if (card(_map(row) ?? const {}) case final room? when seen.add(room.roomId)) room,
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// The room info of [roomId] (3.x's `room`).
  static Uri roomInfoUrl(String roomId) =>
      Uri.https(roomHost, '/roomcen/room/web/cdn/getEnterRoomInfo', {'roomId': roomId});

  /// Room [roomId] from `getEnterRoomInfo` (3.x's `parseRoomJson` and
  /// `_room`), with its [KugouLiveState]:
  /// - no such room (`normalRoomInfo` without a nick and with `kugouId` 0)
  ///   is `NotFound` (3.x read `kugouId` 0 as present and showed a room
  ///   named "Kugou Live");
  /// - `limitType` above 0 restricted, `liveType` -1 offline, a
  ///   `liveSessionId` live, else unknown;
  /// - title `publicMesg`, else `privateMesg`, the nick, `Kugou Live`; nick,
  ///   avatar `userLogo`, cover `imgPath`, followers `fansCount`; no audience
  ///   (the list cards have it).
  static ({LiveRoom room, KugouLiveState state}) roomInfo(String body, {required String roomId, int status = 200}) {
    final data = _data(body, what: 'getEnterRoomInfo', status: status);
    final info = _map(data['normalRoomInfo']);
    if (info == null || info.isEmpty) throw const ApiChanged(_site, 'getEnterRoomInfo: no normalRoomInfo');
    final nick = _text(info['nickName']);
    final kugouId = _text(info['kugouId']);
    if (nick.isEmpty && (kugouId.isEmpty || jsonInt(kugouId) == 0)) throw NotFound(_site, 'room $roomId');
    final session = _text(data['liveSessionId']);
    final state = (jsonInt(info['limitType']) ?? 0) > 0
        ? KugouLiveState.restricted
        : jsonInt(data['liveType']) == -1
        ? KugouLiveState.offline
        : session.isNotEmpty
        ? KugouLiveState.live
        : KugouLiveState.unknown;
    return (
      state: state,
      room: _room(
        roomId: roomId,
        userId: _text(info['userId']),
        kugouId: kugouId,
        nick: nick.isEmpty ? 'Kugou Live' : nick,
        title: _firstText([info['publicMesg'], info['privateMesg'], nick], fallback: 'Kugou Live'),
        avatar: image(info['userLogo']),
        cover: image(info['imgPath']),
        viewers: null,
        followers: jsonInt(info['fansCount']),
        popularity: null,
        state: state,
      ),
    );
  }

  /// Why a room in [state] cannot be played, or null when it is live:
  /// offline and without a live session `StreamUnavailable`, restricted
  /// `NeedsLogin`.
  static SiteError? playbackError(KugouLiveState state, String roomId) => switch (state) {
    KugouLiveState.live => null,
    KugouLiveState.offline => StreamUnavailable(_site, 'room $roomId is offline'),
    KugouLiveState.restricted => NeedsLogin(_site, 'room $roomId is restricted (limitType)'),
    KugouLiveState.unknown => StreamUnavailable(_site, 'room $roomId has no live session'),
  };

  /// The stream answer of [roomId] (3.x's `streamaddr` request, `_` the
  /// time in milliseconds).
  static Uri streamUrl(String roomId, {required int millis}) =>
      Uri.https(apiHost, '/video/pc/live/pull/mutiline/streamaddr', {
        'std_rid': roomId,
        'std_plat': '7',
        'std_kid': '0',
        'streamType': '1-2-4-5-8',
        'ua': 'fx-flash',
        'targetLiveTypes': '1-5-6',
        'version': '1000',
        'supportEncryptMode': '1',
        'appid': '1010',
        '_': '$millis',
      });

  /// The variants of a stream answer for [roomId] (3.x's `parseMediaJson`):
  /// the `httpsFlv` and `httpsHls` URLs of every line's profiles, grouped
  /// by protocol, rate, codec and layout, each URL once (the first line
  /// wins), only URLs [mediaUrl] accepts; groups without a URL dropped;
  /// sorted by rate, highest first, the answer's order otherwise.
  ///
  /// `status` other than 1 (offline) or no accepted URL is
  /// `StreamUnavailable`; an answer for another room is `ApiChanged`.
  static List<KugouLiveVariant> variants(String body, {required String roomId, int status = 200}) {
    final data = _data(body, what: 'streamaddr', status: status);
    final answered = _text(data['roomId']);
    if (answered != roomId) throw ApiChanged(_site, 'streamaddr: asked $roomId, got $answered');
    if (jsonInt(data['status']) != 1) throw StreamUnavailable(_site, 'streamaddr: status ${data['status']}');
    final headers = mediaHeaders(roomId);
    final groups = <String, ({String protocol, int rate, int codec, int layout, List<LivePlayLine> lines})>{};
    for (final lineValue in _list(data['lines'])) {
      final line = _map(lineValue) ?? const {};
      final sid = jsonString(line['sid']);
      for (final profileValue in _list(line['streamProfiles'])) {
        final profile = _map(profileValue) ?? const {};
        final rate = jsonInt(profile['rate']) ?? 0;
        final codec = jsonInt(profile['codec']) ?? 0;
        final layout = jsonInt(profile['layout']) ?? 0;
        for (final (key, protocol, format) in const [
          ('httpsFlv', 'flv', StreamFormat.flv),
          ('httpsHls', 'hls', StreamFormat.hls),
        ]) {
          final group = groups.putIfAbsent(
            '$protocol:$rate:$codec:$layout',
            () => (protocol: protocol, rate: rate, codec: codec, layout: layout, lines: <LivePlayLine>[]),
          );
          for (final raw in _list(profile[key])) {
            final url = mediaUrl(_text(raw), roomId: roomId, protocol: protocol);
            if (url == null || group.lines.any((line) => line.url == '$url')) continue;
            group.lines.add(
              LivePlayLine(
                '$url',
                headers: headers,
                format: format,
                codec: codec == 1 ? 'avc' : null,
                lineId: sid == null ? null : 'sid$sid',
                lease: lease(url),
              ),
            );
          }
        }
      }
    }
    final ordered = [
      for (final MapEntry(key: id, value: group) in groups.entries)
        if (group.lines.isNotEmpty)
          KugouLiveVariant(
            id: id,
            protocol: group.protocol,
            rate: group.rate,
            codec: group.codec,
            layout: group.layout,
            lines: group.lines,
          ),
    ];
    // A stable sort, as 3.x's short lists were.
    final indexed = ordered.indexed.toList()
      ..sort((left, right) {
        final byRate = right.$2.rate.compareTo(left.$2.rate);
        return byRate != 0 ? byRate : left.$1.compareTo(right.$1);
      });
    if (indexed.isEmpty) throw StreamUnavailable(_site, 'streamaddr: no playable URL for $roomId');
    return [for (final (_, variant) in indexed) variant];
  }

  static final RegExp _txTime = RegExp(r'^[0-9A-Fa-f]{8,16}$');

  /// [raw] as a media URL of [roomId] as 3.x accepted it
  /// (`validateMediaUri`): https on `liveplay.live.kugou.com` or a
  /// subdomain, the default port, no user info or fragment, a `/live/` path
  /// ending in `.flv` (`.m3u8` for [protocol] `hls`), a `txSecret`, a hex
  /// `txTime` and a `token` starting with `0-<roomId>-`; else null.
  static Uri? mediaUrl(String raw, {required String roomId, required String protocol}) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !RoomPaths.hostIs(uri.host, 'liveplay.live.kugou.com') ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(protocol == 'hls' ? '.m3u8' : '.flv')) {
      return null;
    }
    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } on FormatException {
      return null;
    }
    if (_text(query['txSecret']).isEmpty || !_txTime.hasMatch(_text(query['txTime']))) return null;
    return (query['token'] ?? '').startsWith('0-$roomId-') ? uri : null;
  }

  /// When [url] stops opening connections: its `txTime`, hex Unix seconds
  /// (about 12 hours after issue; 3.x's `mediaInvalidAt`). Null without a
  /// valid one.
  static DateTime? invalidAt(String url) {
    final String? value;
    try {
      value = Uri.tryParse(url)?.queryParameters['txTime'];
    } on FormatException {
      return null;
    }
    if (value == null || !_txTime.hasMatch(value)) return null;
    final seconds = int.tryParse(value, radix: 16);
    return seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// When to renew [url] (3.x's `mediaRefreshAt`): [leaseLead] before
  /// [invalidAt], or [now] when that has passed.
  static DateTime? refreshAt(String url, {required DateTime now}) {
    final invalid = invalidAt(url);
    if (invalid == null) return null;
    final refresh = invalid.subtract(leaseLead);
    return refresh.isAfter(now) ? refresh : now;
  }

  /// The lease of a media [url]: renew [leaseLead] before its `txTime`.
  /// Expiry is checked when a connection opens (Tencent Cloud's signature),
  /// so it only prefetches.
  static PlayLease? lease(Uri url) {
    final expires = invalidAt('$url');
    return expires == null ? null : PlayLease(refreshAt: expires.subtract(leaseLead), expiresAt: expires);
  }

  /// 3.x's qualities: one per variant, `<FLV|HLS> 码率档 <rate>` (3.x's
  /// zh.json `kugoulive_quality_rate`), id the variant id, sort rate × 10
  /// plus 2 for FLV or 1 for HLS; in the variants' order.
  static List<LivePlayQuality> qualities(List<KugouLiveVariant> variants) => [
    for (final variant in variants)
      LivePlayQuality(
        id: variant.id,
        quality: '${variant.protocol.toUpperCase()} 码率档 ${variant.rate}',
        sort: variant.rate * 10 + (variant.protocol == 'hls' ? 1 : 2),
      ),
  ];

  /// The lines of [variant], its id the applied quality (3.x).
  static LivePlayUrlResolution resolution(KugouLiveVariant variant) =>
      LivePlayUrlResolution.lines(variant.lines, appliedQualityData: variant.id);
}
