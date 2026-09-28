import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'weibo';

/// Who may watch a broadcast (3.x's `WeiboAccess`).
enum WeiboAccess {
  /// Anyone: the answer carries the media URLs of a live broadcast.
  public,

  /// `watch_limit` is not 0 (friends of the anchor only, paid, app only):
  /// the answer carries no media URL.
  restricted,

  /// `play_switch` is 0: playback is switched off.
  disabled,
}

/// What a room's detail knows besides its broadcast id: the anchor and the
/// fields that decide whether it plays. Every broadcast has its own id (the
/// room identity, as in 3.x); the anchor's uid is no room.
@immutable
final class WeiboRoomData {
  /// Creates the data.
  const new({
    required this.ownerId,
    required this.status,
    required this.watchLimit,
    required this.access,
    this.mediaUrls = const [],
  });

  /// `user.uid`: the anchor (the room's `userId`). A fresh answer for the
  /// same broadcast must name the same anchor.
  final int ownerId;

  /// `status` as the platform wrote it: 1 live, 3 ended with a replay, 5
  /// ended long ago (seen); anything else is not known.
  final int status;

  /// `watch_limit`: 0 for a public broadcast.
  final int watchLimit;

  /// Who may watch.
  final WeiboAccess access;

  /// The media URLs of a public live broadcast (FLV first), empty otherwise.
  /// Only room entry reads them; every playback asks again (3.x).
  final List<String> mediaUrls;
}

/// Pure parsing of Weibo Live (微博直播) responses (3.x's `WeiboApi` and
/// `WeiboLink`). Each function takes the response text and status and
/// returns 3.x's models or throws a `SiteError`.
///
/// The site has two anonymous endpoints under `weibo.com/l/!/2/wblive/`:
/// the recommendation snapshot `pc_recommend/list.json` (no paging, no
/// state, no audience) and the broadcast `room/show_pc_live.json`
/// (`{code: 100000, error_code: 0, data}`). A room is one broadcast
/// (`1022:2321325347923495092258`), not an anchor: the next broadcast of
/// the same anchor is another room, as 3.x told its users.
abstract final class WeiboApi {
  /// Website origin.
  static const String origin = 'https://weibo.com';

  /// The recommendation snapshot.
  static const String recommendPath = '/l/!/2/wblive/pc_recommend/list.json';

  /// The broadcast detail.
  static const String detailPath = '/l/!/2/wblive/room/show_pc_live.json';

  /// Rows 3.x asked the snapshot for (the site answers one fewer: 9).
  static const int recommendCount = 10;

  /// The snapshot request, spelled as 3.x sent it (`?count=10&uid=`).
  static final Uri recommendUrl = Uri.parse('$origin$recommendPath?count=$recommendCount&uid=');

  /// The detail request of broadcast [liveId], spelled as 3.x sent it (the
  /// id query-encoded: `live_id=1022%3A…`).
  static Uri detailUrl(String liveId) => Uri.parse('$origin$detailPath?live_id=${Uri.encodeQueryComponent(liveId)}');

  /// Headers of the API requests (3.x's `WeiboApi.headers`).
  static const Map<String, String> headers = {'referer': '$origin/l/wblive/', 'user-agent': 'Mozilla/5.0'};

  /// Headers of the media requests: none. 3.x's `PlaybackHeaderResolver`
  /// had no Weibo branch, so the player and the recorder sent their own
  /// defaults; the CDN answers the FLV without any (checked 2026-09-28 with
  /// no user agent, `Mozilla/5.0` and `libmpv`, no referer).
  static const Map<String, String> mediaHeaders = {};

  /// Largest answer 3.x accepted (1 MiB).
  static const int responseLimit = 1024 * 1024;

  /// `error_code` of the detail for a broadcast that does not exist
  /// ("LiveRoom does not exists!").
  static const int missingCode = 27401;

  /// `status` of a live broadcast.
  static const int liveStatusCode = 1;

  /// `status` of an ended broadcast with a replay, shown as a replay (3.x).
  static const int replayStatusCode = 3;

  /// A broadcast id: 3–8 digits, a colon and 16–48 letters or digits. 3.x
  /// accepted only `1022:232132` + 16 digits and `1042152:` + 32 hex digits
  /// and refused older ids (`1022:2320508a…`, fixture S02-ended); the site
  /// answers an unknown id with [missingCode].
  static final RegExp liveIdPattern = RegExp(r'^[0-9]{3,8}:[0-9A-Za-z]{16,48}$');

  /// Id of the one category (3.x used the platform's).
  static const String categoryId = _site;

  /// The platform's display name, also the category's and the area's
  /// `typeName` (3.x's `site_weibo`).
  static const String siteName = '微博直播';

  /// `areaType` of the one area, the recommendation snapshot (3.x).
  static const String areaType = 'recommendation';

  /// `areaId` of the one area (3.x).
  static const String areaId = 'live';

  /// Name of the one area (3.x's `weibo_public_directory`).
  static const String areaName = '公开推荐';

  /// The notice on every room (3.x's `weibo_room_scope`): a follow tracks
  /// this broadcast, not the anchor.
  static const String roomScopeNotice = '收藏跟踪当前直播场次，不是主播账号；新场次需重新导入直播链接。';

  /// The line put before [roomScopeNotice] on a restricted or disabled
  /// broadcast (3.x's `weibo_restricted`).
  static const String restrictedNotice = '当前场次存在访问限制或播放已关闭；公开直播源不可用。';

  /// 3.x's one quality (`weibo_original_stream`).
  static const LivePlayQuality original = LivePlayQuality(quality: '原始流', id: 'original');

  // Envelopes -----------------------------------------------------------------

  /// The `data` of an answer. HTTP 401/403 is `RiskControl`, 404 `NotFound`,
  /// 429 `RateLimited`, 5xx and any other status but 200 `NetworkFailure`
  /// (3.x read no body then). A body over [responseLimit], not a JSON
  /// object, without integer `code` and `error_code`, or whose `data` is not
  /// an object is `ApiChanged`; so is any code but 100000/0, except
  /// [missingCode] when [missing] (the detail), which is `NotFound`.
  static Map<String, dynamic> data(String body, {required String what, int status = 200, bool missing = false}) {
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
    // A UTF-16 unit is at most three UTF-8 bytes: short bodies are not
    // encoded to be counted.
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: answer over $responseLimit bytes');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    final root = _object(decoded, what);
    final code = _count(root['code'], '$what.code');
    final error = _count(root['error_code'], '$what.error_code');
    if (missing && error == missingCode) throw NotFound(_site, '$what: ${jsonString(root['msg']) ?? error}');
    if (code != 100000 || error != 0) {
      throw ApiChanged(_site, '$what: code $code error_code $error ${jsonString(root['msg']) ?? ''}');
    }
    return _object(root['data'], '$what.data');
  }

  // Directory -----------------------------------------------------------------

  /// The one category, 微博直播, with the one area 公开推荐 (3.x).
  static List<LiveCategory> categories() => [
    LiveCategory(
      id: categoryId,
      name: siteName,
      children: const [
        LiveArea(platform: _site, areaType: areaType, typeName: siteName, areaId: areaId, areaName: areaName),
      ],
    ),
  ];

  /// Whether [area] is the one area of [categories].
  static bool isArea(LiveArea area) =>
      area.platform.trim().toLowerCase() == _site && area.areaType == areaType && area.areaId == areaId;

  /// `pc_recommend`: the snapshot as one page, nothing more (3.x).
  ///
  /// Each row is 3.x's card: the broadcast id as the room, the anchor's uid,
  /// the nickname as nick and title, the cover, the state unknown (the
  /// snapshot does not say it; the room answer does), no audience, and the
  /// scope notice. As in 3.x the whole list is checked: at most 500 rows,
  /// each an object with a broadcast id (each once), a positive integer uid
  /// and a string nickname; anything else fails the list.
  static LiveDirectoryPage recommendations(String body, {int status = 200}) {
    final rows = data(body, what: 'pc_recommend', status: status)['data'];
    if (rows is! List || rows.length > 500) throw const ApiChanged(_site, 'pc_recommend: data.data is not a list');
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final row in rows) {
      final item = _object(row, 'pc_recommend row');
      final id = _liveId(item['liveid'], 'pc_recommend liveid');
      if (!seen.add(id)) throw ApiChanged(_site, 'pc_recommend: $id twice');
      final nick = _string(item['nickname'], 'pc_recommend $id nickname');
      rooms.add(
        LiveRoom(
          platform: _site,
          roomId: id,
          userId: '${_uid(item['uid'], 'pc_recommend $id uid')}',
          nick: nick,
          title: nick,
          cover: normalizeImageUrl(item['cover']),
          link: roomUrl(id),
          liveStatus: LiveStatus.unknown,
          audienceMetricType: AudienceMetricType.unknown,
          watching: '',
          notice: roomScopeNotice,
        ),
      );
    }
    return LiveDirectoryPage(rooms: rooms, page: 1, hasMore: false);
  }

  /// 3.x's nickname search: [rooms] (the snapshot) whose nickname contains
  /// [keyword] (trimmed, case ignored), the first [pageSize]. There is no
  /// server search and no second page.
  static List<LiveRoom> searchSnapshot(String keyword, Iterable<LiveRoom> rooms, {required int pageSize}) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return List.unmodifiable(rooms.where((room) => room.nick.toLowerCase().contains(query)).take(pageSize));
  }

  // Rooms ---------------------------------------------------------------------

  /// `show_pc_live`: broadcast [liveId] as 3.x read it, under that id.
  ///
  /// The answer must be that broadcast (`liveId`), of [ownerId] when given,
  /// with 3.x's field checks (integer `status`, `watch_limit`, `width` and
  /// `height`, 0/1 `pay_live_status` and `play_switch`, string title and
  /// nickname), or it is `ApiChanged`; [missingCode] is `NotFound`.
  ///
  /// The state is 3.x's: a restricted or disabled broadcast is unknown with
  /// the restriction notice; otherwise `status` 1 is live, 3 a replay and
  /// anything else (5, ended long ago) unknown. Only a public live broadcast
  /// reads its media URLs (`live_origin_flv_url`, then
  /// `live_origin_hls_url`, which usually repeats the FLV), each once; a
  /// URL that is not plain http(s) fails the answer. The avatar is
  /// `profileImageUrl` and there is no audience (3.x).
  static LiveRoom detail(String body, {required String liveId, int? ownerId, int status = 200}) {
    final item = data(body, what: 'show_pc_live', status: status, missing: true);
    final id = _liveId(item['liveId'], 'show_pc_live.liveId');
    final user = _object(item['user'], 'show_pc_live.user');
    final owner = _uid(user['uid'], 'show_pc_live.user.uid');
    if (id != liveId) throw ApiChanged(_site, 'show_pc_live: asked $liveId, got $id');
    if (ownerId != null && owner != ownerId) throw ApiChanged(_site, 'show_pc_live: $id of $owner, not of $ownerId');
    final state = _count(item['status'], 'show_pc_live.status');
    final limit = _count(item['watch_limit'], 'show_pc_live.watch_limit');
    _flag(item['pay_live_status'], 'show_pc_live.pay_live_status');
    final enabled = _flag(item['play_switch'], 'show_pc_live.play_switch');
    final access = enabled == 0
        ? WeiboAccess.disabled
        : limit != 0
        ? WeiboAccess.restricted
        : WeiboAccess.public;
    final liveStatus = access != WeiboAccess.public
        ? LiveStatus.unknown
        : switch (state) {
            liveStatusCode => LiveStatus.live,
            replayStatusCode => LiveStatus.replay,
            _ => LiveStatus.unknown,
          };
    final urls = <String>{
      if (liveStatus == LiveStatus.live)
        for (final key in const ['live_origin_flv_url', 'live_origin_hls_url'])
          if (_string(item[key], 'show_pc_live.$key') case final url when url.isNotEmpty) _mediaUrl(url, key),
    };
    final title = _string(item['title'], 'show_pc_live.title');
    final nick = _string(user['screenName'], 'show_pc_live.user.screenName');
    _count(item['width'], 'show_pc_live.width');
    _count(item['height'], 'show_pc_live.height');
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: '$owner',
      title: title,
      nick: nick,
      avatar: normalizeImageUrl(user['profileImageUrl']),
      cover: normalizeImageUrl(item['cover']),
      link: roomUrl(id),
      liveStatus: liveStatus,
      audienceMetricType: AudienceMetricType.unknown,
      watching: '',
      notice: [if (access != WeiboAccess.public) restrictedNotice, roomScopeNotice].join('\n'),
      data: WeiboRoomData(
        ownerId: owner,
        status: state,
        watchLimit: limit,
        access: access,
        mediaUrls: List.unmodifiable(urls),
      ),
    );
  }

  /// Why the broadcast [data] describes cannot be played, or null when it
  /// can (3.x's checks, in its order):
  /// - restricted: `NeedsLogin` (an account the anchor allows; the app has
  ///   no Weibo login);
  /// - disabled, a replay, a state that is not live, or live without a
  ///   media URL: `StreamUnavailable`.
  static SiteError? unplayable(WeiboRoomData data) => switch (data) {
    WeiboRoomData(access: WeiboAccess.restricted) => NeedsLogin(_site, 'watch_limit ${data.watchLimit}'),
    WeiboRoomData(access: WeiboAccess.disabled) => const StreamUnavailable(_site, 'play_switch 0'),
    WeiboRoomData(status: replayStatusCode) => const StreamUnavailable(_site, 'an ended broadcast (replay)'),
    WeiboRoomData(status: != liveStatusCode) => StreamUnavailable(_site, 'status ${data.status}'),
    WeiboRoomData(mediaUrls: []) => const StreamUnavailable(_site, 'live without a media URL'),
    _ => null,
  };

  /// The room's web page (3.x's `WeiboLink.url`), also where "open in
  /// browser" goes.
  static String roomUrl(String liveId) => '$origin/l/wblive/p/show/$liveId';

  /// Where "open in browser" goes for room [roomId] (3.x's
  /// `RoomExternalOpener`): its web page, or null for an id that is no
  /// broadcast id (the room link is not trusted).
  static String? externalRoomUrl(String roomId) {
    final id = roomId.trim();
    return isLiveId(id) ? roomUrl(id) : null;
  }

  // Streams -------------------------------------------------------------------

  /// The line of media [url]: no headers ([mediaHeaders]), the format by
  /// extension (`.flv`, `.m3u8`; the HLS field usually holds the FLV), the
  /// codec of the stream name (`…_wb720avc.flv` is H.264, checked in the
  /// FLV header), the first path segment (`alicdn`) as the line id, else the
  /// host. The URLs carry no signature or expiry: no lease.
  static LivePlayLine line(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final name = segments.lastOrNull?.toLowerCase() ?? '';
    // No headers: [mediaHeaders] is empty, the line's default.
    return LivePlayLine(
      url,
      format: path.endsWith('.flv')
          ? StreamFormat.flv
          : path.endsWith('.m3u8')
          ? StreamFormat.hls
          : null,
      codec: name.contains('hevc') || name.contains('h265')
          ? 'hevc'
          : name.contains('avc')
          ? 'avc'
          : null,
      lineId: segments.length > 1 ? segments.first : uri.host,
    );
  }

  /// The lines of [urls] for 3.x's quality [original], applied as asked (the
  /// site has one stream).
  static LivePlayUrlResolution resolution(Iterable<String> urls) =>
      LivePlayUrlResolution.lines([for (final url in urls) line(url)], appliedQualityData: original.selectionId);

  // Links ---------------------------------------------------------------------

  /// Whether [value] is a broadcast id (see [liveIdPattern]).
  static bool isLiveId(String value) => liveIdPattern.hasMatch(value);

  /// The room [input] names exactly (3.x's `WeiboLink.parse`): a broadcast
  /// id, or a room link (see [liveIdFromUrl]); null for anything with a
  /// space or backslash inside, and for anything else.
  static String? exactRoom(String input) {
    final value = input.trim();
    if (RegExp(r'[\\\s]').hasMatch(value)) return null;
    return isLiveId(value) ? value : liveIdFromUrl(value);
  }

  /// The broadcast of a Weibo room link, without any request:
  /// - the watch page `https://weibo.com/l/wblive/p/show/<id>` or
  ///   `/m/show/<id>` (hosts `weibo.com`, `www.weibo.com`; 3.x's
  ///   `WeiboLink`): the path is read as written, before `Uri` removes dot
  ///   segments, with a trailing slash at most; only the id's colon may be
  ///   escaped (`%3A`), nothing is decoded twice;
  /// - the media centre's `https://live.media.weibo.com/live/show?id=<id>`
  ///   (older links; the site redirects it to the watch page), with exactly
  ///   one `id`.
  ///
  /// Both need http(s), the default port, no user info and no space or
  /// backslash. A profile (`/u/<uid>`) or a post is no room.
  static String? liveIdFromUrl(String raw) {
    final value = raw.trim();
    if (RegExp(r'[\\\s]').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    if (uri.host == 'live.media.weibo.com') return _mediaCentreId(uri);
    if (uri.host != 'weibo.com' && uri.host != 'www.weibo.com') return null;
    final authorityAndPath = value.substring(value.indexOf('://') + 3).split(RegExp('[?#]')).first;
    final slash = authorityAndPath.indexOf('/');
    if (slash < 0) return null;
    final match = RegExp(r'^/l/wblive/[pm]/show/([^/]+)/?$').firstMatch(authorityAndPath.substring(slash));
    if (match == null) return null;
    final id = match[1]!.replaceAll(RegExp('%3a', caseSensitive: false), ':');
    return isLiveId(id) ? id : null;
  }

  static String? _mediaCentreId(Uri uri) {
    if (uri.path != '/live/show') return null;
    try {
      final ids = uri.queryParametersAll['id'];
      if (ids == null || ids.length != 1) return null;
      return isLiveId(ids.single) ? ids.single : null;
    } on FormatException {
      return null;
    }
  }
}

// Helpers ---------------------------------------------------------------------

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw ApiChanged(_site, '$what: expected an object');
}

/// 3.x's `_text`: a string, as written.
String _string(Object? value, String what) {
  if (value is String) return value;
  throw ApiChanged(_site, '$what: expected a string');
}

/// 3.x's `_number`: an integer of zero or more.
int _count(Object? value, String what) {
  if (value is int && value >= 0) return value;
  throw ApiChanged(_site, '$what: $value');
}

/// 3.x's `_binary`: 0 or 1.
int _flag(Object? value, String what) {
  final flag = _count(value, what);
  if (flag > 1) throw ApiChanged(_site, '$what: $value');
  return flag;
}

/// 3.x's `_owner`: a positive integer below 2^53.
int _uid(Object? value, String what) {
  if (value is int && value >= 1 && value <= 9007199254740991) return value;
  throw ApiChanged(_site, '$what: $value');
}

String _liveId(Object? value, String what) {
  final id = _string(value, what);
  if (!WeiboApi.isLiveId(id)) throw ApiChanged(_site, '$what: $id');
  return id;
}

/// 3.x's `_url`: plain http(s) with a host, as written, without spaces,
/// backslashes, user info or a fragment.
String _mediaUrl(String text, String what) {
  final uri = Uri.tryParse(text);
  if (text.trim() != text ||
      RegExp(r'[\\\s]').hasMatch(text) ||
      uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw ApiChanged(_site, 'show_pc_live.$what: not a media URL');
  }
  return text;
}
