import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'jdlive';

/// A broadcast's state as the play answer says it (3.x's `JdLiveState`).
enum JdLiveState {
  /// `status` 1.
  live,

  /// `status` 0: announced, not started.
  preview,

  /// `status` 2: ended.
  offline,

  /// `status` 3: ended, with a replay on JD's side (3.x showed it offline).
  replay,

  /// `status` 10 or 11: paused by the streamer.
  paused,

  /// `secret` 1: watchable in JD's app only, whatever the status.
  restricted,

  /// Any other status, or none.
  unknown,
}

/// One broadcast (3.x's `JdLiveRoom`): a featured list card, or the play
/// answer of a room (with its media when live), completed from a card
/// already seen ([enrich]). The play answer has no title, shop name,
/// avatar or views; 3.x wrote [JdLiveApi.siteName] for the names then.
///
/// It is also the [LiveRoom.data] of a room entry or recording detail: the
/// addresses carry no signature or expiry, and the streams are read from
/// it (never stored).
@immutable
final class JdLiveRoom {
  /// Creates a broadcast.
  const new({
    required this.liveId,
    required this.state,
    this.authorId = '',
    this.nick = JdLiveApi.siteName,
    this.title = JdLiveApi.siteName,
    this.avatar = '',
    this.cover = '',
    this.totalViews,
    this.hls,
    this.flv,
  });

  /// The broadcast (`liveId`): the room's identity. Every broadcast has its
  /// own; a follow tracks one broadcast (3.x).
  final String liveId;

  /// The shop's account (`authorId`); '' when unknown.
  final String authorId;

  /// The shop's name (`userName`), or [JdLiveApi.siteName].
  final String nick;

  /// The title, or [JdLiveApi.siteName].
  final String title;

  /// The shop's avatar (`userPic`); '' when unknown.
  final String avatar;

  /// The card's cover (`indexImage`) or the play answer's `blurredImg`.
  final String cover;

  /// Cumulative views (`pv`); null when unknown.
  final int? totalViews;

  /// The state.
  final JdLiveState state;

  /// The HLS playlist (`h5VideoUrl`) of a live broadcast.
  final Uri? hls;

  /// The FLV stream (`videoUrl`) of a live broadcast.
  final Uri? flv;

  /// This play answer with what it lacks taken from [known], a card of the
  /// same broadcast (3.x's `enrich`): the account, the names while they are
  /// the placeholder, the avatar, the cover while empty, the views. State
  /// and media stay this answer's.
  JdLiveRoom enrich(JdLiveRoom known) => JdLiveRoom(
    liveId: liveId,
    authorId: authorId.isEmpty ? known.authorId : authorId,
    nick: nick == JdLiveApi.siteName ? known.nick : nick,
    title: title == JdLiveApi.siteName ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    totalViews: totalViews ?? known.totalViews,
    state: state,
    hls: hls,
    flv: flv,
  );

  /// Why this broadcast cannot be played, or null (3.x's snapshot check):
  /// app-only is `NeedsLogin`; any state but live, or no playlist, is
  /// `StreamUnavailable`.
  SiteError? get streamError => switch (state) {
    JdLiveState.restricted => NeedsLogin(_site, '$liveId: JD app only (secret)'),
    JdLiveState.live when hls == null || flv == null => StreamUnavailable(_site, '$liveId: live without media'),
    JdLiveState.live => null,
    _ => StreamUnavailable(_site, '$liveId is ${state.name}'),
  };
}

/// One page of the featured list (3.x's `JdLivePage`).
@immutable
final class JdLivePage {
  /// Creates a page.
  new({required Iterable<JdLiveRoom> rooms, required this.nextCount, required this.hasMore})
    : rooms = List.unmodifiable(rooms);

  /// An empty last page (no request made).
  static final JdLivePage empty = JdLivePage(rooms: const [], nextCount: 0, hasMore: false);

  /// The broadcasts, in list order.
  final List<JdLiveRoom> rooms;

  /// `currentCount`: the entries served so far, sent with the next page.
  final int nextCount;

  /// Whether 3.x asked for another page: this one had at least
  /// [JdLiveApi.pageSize] broadcasts.
  final bool hasMore;
}

/// Pure parsing of JD Live answers (3.x's `JdLiveApi`, `JdLiveLink` and the
/// room mapping of its `JdLiveSite`). Each function takes the answer and its
/// status and returns 3.x's models or throws a `SiteError`.
abstract final class JdLiveApi {
  /// The website.
  static const String webOrigin = 'https://lives.jd.com';

  /// The API host.
  static const String apiHost = 'api.m.jd.com';

  /// 3.x's user agent (iOS Safari) of every request.
  static const String userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';

  /// 3.x's headers of the API requests (`apiHeaders`).
  static const Map<String, String> apiHeaders = {
    'accept': 'application/json, text/plain, */*',
    'origin': webOrigin,
    'referer': '$webOrigin/',
    'user-agent': userAgent,
  };

  /// 3.x's media headers of [liveId] (`mediaHeaders`): what its room entry
  /// sent for the playlist check, and the rooms' `httpHeaders` (in the 3.x
  /// JSON). 3.x's player had no JD branch and sent none of them
  /// ([line]).
  static Map<String, String> mediaHeaders(String liveId) => {
    'origin': webOrigin,
    'referer': link(liveId),
    'user-agent': userAgent,
  };

  /// The largest API answer 3.x read, in UTF-8 bytes.
  static const int responseLimit = 4 * 1024 * 1024;

  /// The largest playlist 3.x checked, in characters.
  static const int playlistLimit = 1024 * 1024;

  /// 3.x's platform name: the category, the area's type, the cards' area,
  /// and the names the play answer lacks.
  static const String siteName = 'JD Live';

  /// `areaType` of the one area.
  static const String areaType = 'official';

  /// `areaId` of the one area: the featured list (`tabId` 1).
  static const String areaId = 'featured';

  /// The one area's name (3.x's zh.json `jdlive_category_featured`; the
  /// interface translates it by id, M13).
  static const String areaName = '精选直播购物';

  /// The one area.
  static const LiveArea area = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: siteName,
    areaId: areaId,
    areaName: areaName,
  );

  /// Broadcasts a page has when 3.x asks for the next one.
  static const int pageSize = 30;

  /// Largest recommendation slice (a larger page size is cut to it, 3.x).
  static const int maxRecommendSize = 30;

  /// Largest search page size 3.x served; a larger one gives nothing.
  static const int maxSearchSize = 100;

  /// Last page 3.x asked for.
  static const int maxPage = 10000;

  /// The notice of a room (3.x's zh.json `jdlive_chat_notice`).
  static const String chatNotice = '京东远端聊天尚待接入；公开目录的 pv 字段按累计观看展示，不标记为当前并发人数。';

  /// The notice of an app-only room (`jdlive_restricted_notice`).
  static const String restrictedNotice = '该京东直播仅限京东应用访问，界面保持未知状态，不将其显示成未开播。';

  /// Id of the HLS quality.
  static const String hlsId = 'hls';

  /// Id of the FLV quality.
  static const String flvId = 'flv';

  /// 3.x's first quality (zh.json `jdlive_quality_hls`).
  static const LivePlayQuality hlsQuality = LivePlayQuality(quality: 'HLS（推荐）', id: hlsId, sort: 2);

  /// 3.x's second quality (zh.json `jdlive_quality_flv`).
  static const LivePlayQuality flvQuality = LivePlayQuality(quality: 'FLV 原始线路', id: flvId, sort: 1);

  static final RegExp _liveId = RegExp(r'^[1-9]\d{4,17}$');
  static final RegExp _route = RegExp(r'^/?([1-9]\d{4,17})(?:/(?:live|notice|closed|replay))?(?:\?.*)?$');

  /// Whether [value] is a broadcast id: 5–18 digits, not starting with 0.
  static bool isLiveId(String value) => _liveId.hasMatch(value);

  /// The room page of [liveId] (3.x's `watchUrl`).
  static String link(String liveId) => '$webOrigin/#/$liveId';

  /// The broadcast of [raw] (3.x's `JdLiveLink.parseLiveId`): an id
  /// (trimmed), or a room link ([liveIdFromUrl]); null otherwise.
  static String? liveIdOf(String raw) {
    final value = raw.trim();
    return isLiveId(value) ? value : liveIdFromUrl(value);
  }

  /// The broadcast of a room link (3.x's `JdLiveLink.parseLiveId` for
  /// URLs): http(s) on `lives.jd.com` (any case), default port, no user
  /// info, the page routing by fragment: `#/<id>`, optionally followed by
  /// `/live`, `/notice`, `/closed` or `/replay` and a query
  /// (`#/48378944?origin=0`). A path or query before the fragment is
  /// ignored. Null for anything else.
  static String? liveIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'lives.jd.com' ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    return _route.firstMatch(uri.fragment)?.group(1);
  }

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `JD Live` with the one area.
  static List<LiveCategory> categories() => [
    LiveCategory(id: _site, name: siteName, children: const [area]),
  ];

  /// Whether [category] is the one area.
  static bool isArea(LiveArea category) =>
      category.platform == _site && category.areaType == areaType && category.areaId == areaId;

  /// Whether [room] matches the lower-case [query] of 3.x's search filter:
  /// in its id, the shop's account, name or title (the names case
  /// ignored).
  static bool matches(JdLiveRoom room, String query) =>
      room.liveId.contains(query) ||
      room.authorId.contains(query) ||
      room.nick.toLowerCase().contains(query) ||
      room.title.toLowerCase().contains(query);

  // Requests ------------------------------------------------------------------

  /// `liveListWithTabToM` page [page] after [count] entries, of the list
  /// first asked at [timestamp] (3.x's query; `v` is the clock [now]).
  static Uri listUrl({required int page, required int count, required int timestamp, required DateTime now}) =>
      Uri.https(apiHost, '/api', {
        'appid': 'h5-live',
        'functionId': 'liveListWithTabToM',
        'v': '${now.millisecondsSinceEpoch}',
        'body': jsonEncode({'tabId': 1, 'currentCount': '$count', 'page': page, 'timestamp': timestamp}),
      });

  /// `getImmediatePlayToM` for [liveId] (3.x's query; `t` is the clock
  /// [now]).
  static Uri playUrl(String liveId, {required DateTime now}) => Uri.https(apiHost, '/api', {
    'appid': 'h5-live',
    'functionId': 'getImmediatePlayToM',
    't': '${now.millisecondsSinceEpoch}',
    'body': jsonEncode({'liveId': liveId}),
  });

  // Featured list -------------------------------------------------------------

  /// `liveListWithTabToM` page [page] (3.x's `parseDirectoryJson`): the
  /// `templateType` 1 entries are broadcasts, the others (`-100`) are
  /// promotions and skipped. An entry without a valid id, whose `liveId`
  /// differs from its `id`, or repeating one, is skipped; an entry that is
  /// not an object, a broadcast without a `data` object, or a name or image
  /// that is not text, fails the page (`ApiChanged`). `currentCount` is
  /// required. There is another page when this one had at least [pageSize]
  /// broadcasts (3.x).
  static JdLivePage directory(String body, {required int page, int status = 200}) {
    const what = 'liveListWithTabToM';
    final data = _data(body, status: status, what: what);
    final rows = data['list'];
    if (rows is! List || rows.length > 1000) {
      throw ApiChanged(_site, '$what: list is ${rows is List ? '${rows.length} entries' : 'not a list'}');
    }
    final seen = <String>{};
    final rooms = <JdLiveRoom>[];
    for (final row in rows) {
      final card = _object(row, '$what entry');
      if (_int(card['templateType']) != 1) continue;
      final item = _object(card['data'], '$what broadcast');
      final liveId = _id(item['liveId'] ?? item['id']);
      if (liveId == null || _id(item['id']) != liveId || !seen.add(liveId)) continue;
      rooms.add(
        JdLiveRoom(
          liveId: liveId,
          authorId: _id(item['authorId']) ?? '',
          nick: _optionalText(item['userName'], 'userName of $liveId', fallback: siteName),
          title: _optionalText(item['title'], 'title of $liveId', fallback: siteName),
          avatar: _image(item['userPic'], 'userPic of $liveId'),
          cover: _image(item['indexImage'], 'indexImage of $liveId'),
          totalViews: _count(item['pv']),
          state: state(item['status']),
        ),
      );
    }
    final next = _count(data['currentCount']);
    if (next == null) throw ApiChanged(_site, '$what: currentCount is ${data['currentCount']}');
    return JdLivePage(rooms: rooms, nextCount: next, hasMore: rooms.length >= pageSize);
  }

  // Play answer ---------------------------------------------------------------

  /// `getImmediatePlayToM` for [liveId] (3.x's `parseRoomJson`): the state,
  /// the cover (`blurredImg`) and, when live, the HLS playlist and FLV
  /// stream of one stream key on JD Cloud (https, `*.jdcloud.com`, under
  /// `/live/`). A live answer without both, or with two keys, is
  /// `ApiChanged`, as is an answer for another broadcast. The answer has no
  /// names (see [JdLiveRoom]).
  static JdLiveRoom play(String body, {required String liveId, int status = 200}) {
    const what = 'getImmediatePlayToM';
    final data = _data(body, status: status, what: what);
    final answered = _id(data['liveId']);
    if (answered != liveId) throw ApiChanged(_site, '$what: asked $liveId, got ${data['liveId']}');
    final current = state(data['status'], secret: data['secret']);
    final hls = _media(data['h5VideoUrl'], '.m3u8', 'h5VideoUrl of $liveId');
    final flv = _media(data['videoUrl'], '.flv', 'videoUrl of $liveId');
    if (current == JdLiveState.live && (hls == null || flv == null || _streamKey(hls) != _streamKey(flv))) {
      throw ApiChanged(_site, '$what: $liveId is live without one stream in h5VideoUrl and videoUrl');
    }
    return JdLiveRoom(
      liveId: liveId,
      state: current,
      cover: _image(data['blurredImg'], 'blurredImg of $liveId'),
      hls: hls,
      flv: flv,
    );
  }

  /// 3.x's state of [status]: `secret` 1 is app-only whatever the status;
  /// 1 live, 0 preview, 2 ended, 3 replay, 10 and 11 paused, anything else
  /// (or none) unknown.
  static JdLiveState state(Object? status, {Object? secret}) {
    if ((_int(secret) ?? 0) == 1) return JdLiveState.restricted;
    return switch (_int(status)) {
      1 => JdLiveState.live,
      0 => JdLiveState.preview,
      2 => JdLiveState.offline,
      3 => JdLiveState.replay,
      10 || 11 => JdLiveState.paused,
      _ => JdLiveState.unknown,
    };
  }

  /// 3.x's check of a live broadcast's HLS playlist at room entry and
  /// before a recording (`validatePlaylist`): at most [playlistLimit]
  /// characters, starting with `#EXTM3U`, and every media reference (a URI
  /// line or a tag's `URI="…"`) resolving to https on [expected]'s host
  /// (port 443), under `/live/`, named after its stream key; at least one
  /// and at most 1000 of them. A 404 is `StreamUnavailable` (the stream is
  /// not on the CDN; 3.x said "missing", the room not found); another
  /// status is mapped as the API's; a playlist that fails the check is
  /// `ApiChanged`.
  static void checkPlaylist(String body, {required Uri expected, int status = 200}) {
    const what = 'playlist';
    if (status == 404) throw const StreamUnavailable(_site, '$what: HTTP 404');
    _checkStatus(status, what: what);
    if (body.length > playlistLimit || !body.trimLeft().startsWith('#EXTM3U')) {
      throw ApiChanged(_site, '$what: not an HLS playlist (${_snippet(body)})');
    }
    final stem = _streamKey(expected);
    var references = 0;
    for (final raw in const LineSplitter().convert(body)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        for (final match in RegExp('URI="([^"]+)"').allMatches(line)) {
          if (!_isChild(expected, match.group(1)!, stem)) throw ApiChanged(_site, '$what: foreign ${match.group(1)}');
          references++;
        }
        continue;
      }
      if (!_isChild(expected, line, stem)) throw ApiChanged(_site, '$what: foreign ${_snippet(line)}');
      references++;
      if (references > 1000) throw const ApiChanged(_site, '$what: over 1000 media references');
    }
    if (references < 1) throw const ApiChanged(_site, '$what: no media reference');
  }

  static bool _isChild(Uri expected, String raw, String stem) {
    final Uri child;
    try {
      child = expected.resolve(raw);
    } on FormatException {
      return false;
    }
    return child.isScheme('https') &&
        child.userInfo.isEmpty &&
        !child.hasFragment &&
        child.host.toLowerCase() == expected.host.toLowerCase() &&
        (!child.hasPort || child.port == 443) &&
        child.path.startsWith('/live/') &&
        child.pathSegments.isNotEmpty &&
        child.pathSegments.last.startsWith(stem);
  }

  // Rooms and streams ---------------------------------------------------------

  /// The room of [room] (3.x's `_room`): the broadcast id; the shop's
  /// account as user, else the broadcast; the title and shop name (the
  /// placeholder when unknown); the avatar, else the cover; the area `JD
  /// Live`; the views as cumulative viewers when known; live for live,
  /// offline for preview, ended and replay, unknown for app-only, paused
  /// and unknown; 3.x's notice and media headers. [withData] (room entry
  /// and recording) keeps [room] as the room's data, with its media.
  static LiveRoom room(JdLiveRoom room, {bool withData = false}) {
    final total = room.totalViews;
    return LiveRoom(
      roomId: room.liveId,
      platform: _site,
      userId: room.authorId.isEmpty ? room.liveId : room.authorId,
      link: link(room.liveId),
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: siteName,
      totalViewers: total == null ? '' : '$total',
      audienceMetricType: total == null ? AudienceMetricType.unknown : AudienceMetricType.totalViewers,
      liveStatus: switch (room.state) {
        JdLiveState.live => LiveStatus.live,
        JdLiveState.preview || JdLiveState.offline || JdLiveState.replay => LiveStatus.offline,
        JdLiveState.restricted || JdLiveState.paused || JdLiveState.unknown => LiveStatus.unknown,
      },
      notice: room.state == JdLiveState.restricted ? restrictedNotice : chatNotice,
      httpHeaders: mediaHeaders(room.liveId),
      data: withData ? room : null,
    );
  }

  /// 3.x's qualities of a live [room]: HLS, then FLV.
  static List<LivePlayQuality> qualities(JdLiveRoom room) => [hlsQuality, if (room.flv != null) flvQuality];

  /// The line of quality [qualityId] of a live [room]: its playlist (HLS)
  /// or stream (FLV), the host as line id. No headers: 3.x's player had no
  /// JD branch and sent its own defaults (the stream plays without them,
  /// spec §6). No lease: the addresses carry no signature or expiry. The
  /// codec is not written (the answer does not say it). Another quality is
  /// a caller error.
  static LivePlayLine line(JdLiveRoom room, String qualityId) {
    final (url, format) = switch (qualityId) {
      hlsId => (room.hls, StreamFormat.hls),
      flvId => (room.flv, StreamFormat.flv),
      _ => throw ArgumentError.value(qualityId, 'qualityId', 'not a JD Live quality'),
    };
    if (url == null) throw StreamUnavailable(_site, '${room.liveId}: no $qualityId');
    return LivePlayLine('$url', format: format, lineId: url.host);
  }
}

/// A JD Cloud stream of [extension] (3.x's `_mediaUri`), or null: https,
/// `*.jdcloud.com`, port 443, no user info or fragment, under `/live/`,
/// without spaces or control characters, at most 8192 characters. A value
/// that is not text is `ApiChanged`.
Uri? _media(Object? value, String extension, String what) {
  final raw = _optionalText(value, what);
  if (raw.isEmpty || raw.length > 8192 || RegExp(r'[\s\x00-\x1f]').hasMatch(raw)) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !_hostIs(uri.host, 'jdcloud.com') ||
      (uri.hasPort && uri.port != 443) ||
      !uri.path.startsWith('/live/') ||
      !uri.path.toLowerCase().endsWith(extension)) {
    return null;
  }
  return uri;
}

/// The stream key of a JD Cloud address: its file name without `.m3u8` or
/// `.flv`.
String _streamKey(Uri uri) {
  final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  return name.replaceFirst(RegExp(r'\.(?:m3u8|flv)$', caseSensitive: false), '');
}

/// A JD image (3.x's `_image`): https on `*.360buyimg.com`, no user info or
/// fragment, as `Uri` writes it; '' for anything else. A value that is not
/// text is `ApiChanged`.
String _image(Object? value, String what) {
  final uri = Uri.tryParse(_optionalText(value, what));
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !_hostIs(uri.host, '360buyimg.com')) {
    return '';
  }
  return '$uri';
}

bool _hostIs(String host, String root) {
  final value = host.toLowerCase();
  return value == root || value.endsWith('.$root');
}

/// 3.x's ids: a number or text of 5–18 digits, not starting with 0.
String? _id(Object? value) {
  final text = switch (value) {
    final int number => '$number',
    final String text => text.trim(),
    _ => '',
  };
  return JdLiveApi.isLiveId(text) ? text : null;
}

/// 3.x's integers: an integer, an integral finite number, or integer text.
int? _int(Object? value) => switch (value) {
  final int number => number,
  final num number when number.isFinite && number == number.toInt() => number.toInt(),
  final String text => int.tryParse(text.trim()),
  _ => null,
};

int? _count(Object? value) {
  final result = _int(value);
  return result != null && result >= 0 ? result : null;
}

/// 3.x's text of an envelope field: text trimmed, anything else written.
String _text(Object? value) => value is String ? value.trim() : value?.toString().trim() ?? '';

/// 3.x's optional text: null is [fallback]; text (at most 65536
/// characters) trimmed with runs of whitespace made one space, [fallback]
/// when blank; anything else is `ApiChanged`.
String _optionalText(Object? value, String what, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is! String || value.length > 65536) throw ApiChanged(_site, '$what is not text');
  final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? fallback : text;
}

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw ApiChanged(_site, '$what is not an object');
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping (`_throwStatus`): 200 is an answer; 400 and 422 are
/// `ApiChanged`, 401 and 403 `RiskControl`, 404 `NotFound`, 429
/// `RateLimited`; 5xx and every other status (redirects included: 3.x did
/// not follow them) `NetworkFailure`.
void _checkStatus(int status, {required String what}) {
  switch (status) {
    case 200:
      return;
    case 400 || 422:
      throw ApiChanged(_site, '$what: HTTP $status');
    case 401 || 403:
      throw RiskControl(_site, detail: '$what: HTTP $status');
    case 404:
      throw NotFound(_site, '$what: HTTP 404');
    case 429:
      throw RateLimited(_site, detail: '$what: HTTP 429');
    default:
      throw NetworkFailure(_site, '$what: HTTP $status');
  }
}

/// The `{code, subCode, data}` envelope (3.x's `_responseData`): `code` must
/// be `0` (else `ApiChanged`, such as `2` "the current API does not
/// exist"), `subCode` `0` (else `NotFound`, 3.x's "missing"), `data` an
/// object. An answer over [JdLiveApi.responseLimit] bytes or not JSON is
/// `ApiChanged`.
Map<String, dynamic> _data(String body, {required int status, required String what}) {
  _checkStatus(status, what: what);
  // UTF-8 needs at most three bytes per UTF-16 unit, so short bodies need no
  // encoding.
  if (body.length > JdLiveApi.responseLimit ||
      (body.length * 3 > JdLiveApi.responseLimit && utf8.encode(body).length > JdLiveApi.responseLimit)) {
    throw ApiChanged(_site, '$what: answer over ${JdLiveApi.responseLimit} bytes');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  final root = _object(decoded, what);
  final code = _text(root['code']);
  if (code != '0') throw ApiChanged(_site, '$what: code $code ${_text(root['echo'])}'.trim());
  final sub = _text(root['subCode']);
  if (sub != '0') throw NotFound(_site, '$what: subCode $sub');
  return _object(root['data'], '$what data');
}
