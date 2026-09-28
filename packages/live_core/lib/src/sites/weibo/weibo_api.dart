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
  /// Anyone: the answer carries the media URLs of a live broadcast or the
  /// recording of a replay.
  public,

  /// `watch_limit` is not 0 (friends of the anchor only, the anchor only,
  /// paid, app only): the answer carries no media URL.
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
    this.replayUrl,
    this.tip,
  });

  /// `user.uid`: the anchor (the room's `userId`). A fresh answer for the
  /// same broadcast must name the same anchor.
  final int ownerId;

  /// `status` as the platform wrote it: 0 announced (the web page counts
  /// down), 1 live, 3 ended with a replay, 5 ended; anything else is not
  /// known.
  final int status;

  /// `watch_limit`: 0 for a public broadcast; see
  /// [WeiboApi.restrictionOfLimit].
  final int watchLimit;

  /// Who may watch.
  final WeiboAccess access;

  /// The media URLs of a public live broadcast (FLV first), empty otherwise.
  /// Only room entry reads them; every live playback asks again (3.x).
  final List<String> mediaUrls;

  /// The recording of a public replay (`replay_origin_url`, an HLS VOD,
  /// made https as the web player does), null otherwise.
  final String? replayUrl;

  /// The platform's explanation of a restriction (`pay_dialog_info.buy_tip`,
  /// such as 本场直播只有主播的好友可观看), null without one.
  final String? tip;
}

/// Pure parsing of Weibo Live (微博直播) responses (3.x's `WeiboApi` and
/// `WeiboLink`). Each function takes the response text and status and
/// returns 3.x's models or throws a `SiteError`.
///
/// The site has two anonymous endpoints under `weibo.com/l/!/2/wblive/`:
/// the recommendation snapshot `pc_recommend/list.json` (no paging, no
/// audience; only broadcasts on air) and the broadcast
/// `room/show_pc_live.json` (`{code: 100000, error_code: 0, data}`). A room
/// is one broadcast (`1022:2321325347923495092258`), not an anchor: the next
/// broadcast of the same anchor is another room, as 3.x told its users.
abstract final class WeiboApi {
  /// Website origin.
  static const String origin = 'https://weibo.com';

  /// The recommendation snapshot.
  static const String recommendPath = '/l/!/2/wblive/pc_recommend/list.json';

  /// The broadcast detail.
  static const String detailPath = '/l/!/2/wblive/room/show_pc_live.json';

  /// Rows asked of the snapshot (upgrade 18-1): the site answers about 51.
  /// 3.x asked for 10 and got 9 ([legacyRecommendCount]).
  static const int recommendCount = 100;

  /// What 3.x asked the snapshot for.
  static const int legacyRecommendCount = 10;

  /// The snapshot request (`?count=100&uid=`; 3.x's spelling with the larger
  /// count).
  static final Uri recommendUrl = Uri.parse('$origin$recommendPath?count=$recommendCount&uid=');

  /// The detail request of broadcast [liveId], spelled as 3.x sent it (the
  /// id query-encoded: `live_id=1022%3A…`).
  static Uri detailUrl(String liveId) => Uri.parse('$origin$detailPath?live_id=${Uri.encodeQueryComponent(liveId)}');

  /// Headers of the API requests (3.x's `WeiboApi.headers`), also of the
  /// `t.cn` short link requests.
  static const Map<String, String> headers = {'referer': '$origin/l/wblive/', 'user-agent': 'Mozilla/5.0'};

  /// Headers of the media requests: none. 3.x's `PlaybackHeaderResolver`
  /// had no Weibo branch, so the player and the recorder sent their own
  /// defaults; the CDN answers the FLV without any (checked 2026-09-28 with
  /// no user agent, `Mozilla/5.0` and `libmpv`, no referer), and so does the
  /// replay CDN (checked 2026-09-28).
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

  /// `status` of an ended broadcast without a replay: offline (upgrade
  /// 18-3; 3.x showed it as unknown). Seen on broadcasts from 2021 and from
  /// the day before (fixtures S02-ended, S04-shortlink-room).
  static const int endedStatusCode = 5;

  /// `watch_limit` of a broadcast only the Weibo app plays (the web player
  /// sends the viewer to the app).
  static const int appOnlyLimit = 8;

  /// `watch_limit` of a broadcast for the anchor's friends only (S02-watch-
  /// limit: 本场直播只有主播的好友可观看).
  static const int friendsOnlyLimit = 10;

  /// `watch_limit` of a broadcast only the anchor may watch (S04-self-only-
  /// replay: 本场直播只有主播自己可观看).
  static const int selfOnlyLimit = 11;

  /// `watch_limit` of a paid broadcast (the web player offers a top-up).
  static const int paidLimit = 12;

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

  /// The notice on every room (3.x's `weibo_room_scope`, reworded for users):
  /// a follow tracks this broadcast, not the anchor.
  static const String roomScopeNotice = '微博每场直播都有单独的链接，这里关注的是这一场。主播下次开播时，请重新导入新的直播链接。';

  /// The line put before [roomScopeNotice] on a restricted broadcast (3.x's
  /// `weibo_restricted`, reworded; the card shows the kind, see
  /// [restrictionOf]).
  static const String restrictedNotice = '这场直播设置了观看限制（仅好友、仅主播本人、付费或仅限微博 App），这里无法播放。';

  /// The line put before [roomScopeNotice] on a broadcast whose playback is
  /// switched off (3.x showed [restrictedNotice] for it too).
  static const String disabledNotice = '这场直播已关闭播放，这里无法播放。';

  /// The directory's scope note (3.x's `weibo_directory_scope`, the text of
  /// the directory notice key, reworded: the cards now show that they are
  /// live).
  static const String directoryScope =
      '这里是微博官方推荐的正在直播的场次，没有观看人数。搜索页可以输入场次 ID、粘贴直播链接或 t.cn 短链，也可以按昵称筛选这份推荐；不是全站搜索。关注的是这一场直播，主播下次开播时要重新导入。';

  /// 3.x's quality of a live broadcast (`weibo_original_stream`).
  static const LivePlayQuality original = LivePlayQuality(quality: '原始流', id: 'original');

  /// The quality of a replay's recording (upgrade 18-5; new, so named 原画
  /// by the unified naming rule). One stream (`…_wb1080avc_index.m3u8`).
  static const LivePlayQuality replay = LivePlayQuality(quality: '原画', id: 'replay');

  // Envelopes -----------------------------------------------------------------

  /// Throws the error of a non-200 [status] of the request [what]: HTTP
  /// 401/403 is `RiskControl`, 404 `NotFound`, 429 `RateLimited`, 5xx and
  /// any other status `NetworkFailure` (3.x read no body then).
  static void checkStatus(int status, String what) {
    switch (status) {
      case 200:
        return;
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

  /// The `data` of an answer. A status other than 200 fails as
  /// [checkStatus] says. A body over [responseLimit], not a JSON object,
  /// without integer `code` and `error_code`, or whose `data` is not an
  /// object is `ApiChanged`; so is any code but 100000/0, except
  /// [missingCode] when [missing] (the detail), which is `NotFound`.
  static Map<String, dynamic> data(String body, {required String what, int status = 200, bool missing = false}) {
    checkStatus(status, what);
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
  /// the nickname (HTML references decoded, 18-7) as nick and title, the
  /// cover, no audience, and the scope notice. The state is live (18-2): the
  /// snapshot lists broadcasts on air only (every one of the 51 rows of
  /// S01-recommend was live on its detail). It does not tell restrictions,
  /// so the card's restriction is not provided (null).
  ///
  /// A bad row is skipped (18-8): not an object, without a broadcast id, or
  /// a broadcast listed before; a uid that is no positive integer leaves the
  /// card without `userId`, a nickname that is no string leaves it empty.
  /// A list that is no list, has over 500 rows, or has rows but none usable
  /// fails the snapshot (`ApiChanged`), so a changed API is not shown as an
  /// empty directory.
  static LiveDirectoryPage recommendations(String body, {int status = 200}) {
    final rows = data(body, what: 'pc_recommend', status: status)['data'];
    if (rows is! List || rows.length > 500) throw const ApiChanged(_site, 'pc_recommend: data.data is not a list');
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = row['liveid'];
      if (id is! String || !isLiveId(id) || !seen.add(id)) continue;
      final nick = _text(row['nickname']);
      final uid = _uidOrNull(row['uid']);
      rooms.add(
        LiveRoom(
          platform: _site,
          roomId: id,
          userId: uid == null ? null : '$uid',
          nick: nick,
          title: nick,
          cover: normalizeImageUrl(row['cover']),
          link: roomUrl(id),
          liveStatus: LiveStatus.live,
          audienceMetricType: AudienceMetricType.unknown,
          watching: '',
          notice: roomScopeNotice,
        ),
      );
    }
    if (rooms.isEmpty && rows.isNotEmpty) throw const ApiChanged(_site, 'pc_recommend: no usable row');
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

  /// `show_pc_live`: broadcast [liveId], under that id.
  ///
  /// The answer must be that broadcast (`liveId`), of an anchor (`user.uid`,
  /// [ownerId] when given), with integer `status` and `watch_limit` and a
  /// 0/1 `play_switch`, or it is `ApiChanged`; [missingCode] is `NotFound`.
  /// Fields it does not use are not checked (18-8: `width`, `height`,
  /// `pay_live_status`); a title or nickname that is no string is empty, a
  /// media URL that is not plain http(s) is skipped.
  ///
  /// The state: `status` 1 is live, 3 a replay, 5 offline (18-3), anything
  /// else unknown (3.x). A restricted or switched-off broadcast keeps its
  /// state (18-4; 3.x showed it as unknown), carries the restriction
  /// ([restrictionOf]) and a notice line, and plays nothing. Only a public
  /// live broadcast reads its media URLs (`live_origin_flv_url`, then
  /// `live_origin_hls_url`, which usually repeats the FLV), each once; only
  /// a public replay reads its recording (`replay_origin_url`, 18-5).
  ///
  /// Also: the 1024 px `avatar` before the 50 px `profileImageUrl` (18-6);
  /// title and nickname with HTML references decoded (18-7); the start
  /// (`startTime`, epoch milliseconds) while live; no audience (3.x).
  static LiveRoom detail(String body, {required String liveId, int? ownerId, int status = 200}) {
    final item = data(body, what: 'show_pc_live', status: status, missing: true);
    final id = _liveId(item['liveId'], 'show_pc_live.liveId');
    final user = _object(item['user'], 'show_pc_live.user');
    final owner = _uid(user['uid'], 'show_pc_live.user.uid');
    if (id != liveId) throw ApiChanged(_site, 'show_pc_live: asked $liveId, got $id');
    if (ownerId != null && owner != ownerId) throw ApiChanged(_site, 'show_pc_live: $id of $owner, not of $ownerId');
    final state = _count(item['status'], 'show_pc_live.status');
    final limit = _count(item['watch_limit'], 'show_pc_live.watch_limit');
    final enabled = _flag(item['play_switch'], 'show_pc_live.play_switch');
    final access = enabled == 0
        ? WeiboAccess.disabled
        : limit != 0
        ? WeiboAccess.restricted
        : WeiboAccess.public;
    final liveStatus = switch (state) {
      liveStatusCode => LiveStatus.live,
      replayStatusCode => LiveStatus.replay,
      endedStatusCode => LiveStatus.offline,
      _ => LiveStatus.unknown,
    };
    final public = access == WeiboAccess.public;
    final urls = <String>{
      if (public && state == liveStatusCode)
        for (final key in const ['live_origin_flv_url', 'live_origin_hls_url']) ?_mediaUrl(item[key]),
    };
    final dialog = item['pay_dialog_info'];
    final roomData = WeiboRoomData(
      ownerId: owner,
      status: state,
      watchLimit: limit,
      access: access,
      mediaUrls: List.unmodifiable(urls),
      replayUrl: public && state == replayStatusCode ? _replayUrl(item['replay_origin_url']) : null,
      tip: access == WeiboAccess.restricted && dialog is Map ? jsonString(dialog['buy_tip']) : null,
    );
    final avatar = normalizeImageUrl(user['avatar']);
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: '$owner',
      title: _text(item['title']),
      nick: _text(user['screenName']),
      avatar: avatar.isNotEmpty ? avatar : normalizeImageUrl(user['profileImageUrl']),
      cover: normalizeImageUrl(item['cover']),
      link: roomUrl(id),
      liveStatus: liveStatus,
      startedAt: state == liveStatusCode ? startedAt(item['startTime']) : null,
      restriction: restrictionOf(roomData),
      audienceMetricType: AudienceMetricType.unknown,
      watching: '',
      notice: [
        if (access == WeiboAccess.restricted) restrictedNotice,
        if (access == WeiboAccess.disabled) disabledNotice,
        roomScopeNotice,
      ].join('\n'),
      data: roomData,
    );
  }

  /// A start from epoch milliseconds (`startTime`); null for anything that
  /// is not a time after 2001 and before 2286 (the platform writes 0 when
  /// there is none).
  static DateTime? startedAt(Object? value) => switch (value) {
    final int milliseconds when milliseconds >= 1000000000000 && milliseconds < 10000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    _ => null,
  };

  /// The kind of a `watch_limit` that is not 0: [appOnlyLimit] app only,
  /// [friendsOnlyLimit] and [selfOnlyLimit] private, [paidLimit] paid;
  /// another value (9 was seen, without a text) is unplayable, the kind M2.1
  /// keeps for a restriction that cannot be told apart.
  static LiveRestriction restrictionOfLimit(int watchLimit) => switch (watchLimit) {
    appOnlyLimit => LiveRestriction.appOnly,
    friendsOnlyLimit || selfOnlyLimit => LiveRestriction.private,
    paidLimit => LiveRestriction.paid,
    _ => LiveRestriction.unplayable,
  };

  /// The restriction of a live broadcast or a replay (M2.1's rules), null
  /// for any other state (not provided):
  /// - restricted: [restrictionOfLimit];
  /// - playback switched off: unplayable;
  /// - public: none, or unplayable when a live broadcast has no media URL or
  ///   a replay no recording.
  static LiveRestriction? restrictionOf(WeiboRoomData data) {
    if (data.status != liveStatusCode && data.status != replayStatusCode) return null;
    return switch (data.access) {
      WeiboAccess.restricted => restrictionOfLimit(data.watchLimit),
      WeiboAccess.disabled => LiveRestriction.unplayable,
      WeiboAccess.public =>
        (data.status == liveStatusCode ? data.mediaUrls.isNotEmpty : data.replayUrl != null)
            ? LiveRestriction.none
            : LiveRestriction.unplayable,
    };
  }

  /// Why the broadcast [data] describes cannot be played, or null when it
  /// can (then [qualityOf] is its quality). Every reason is
  /// `StreamUnavailable`, with the reason in the detail (M2.1's table; 3.x
  /// said `NeedsLogin` for a restriction, but the app has no Weibo account):
  /// - ended (5) or a state that is not known;
  /// - restricted (the kind and the platform's text) or switched off;
  /// - live without a media URL, a replay without a recording.
  static SiteError? unplayable(WeiboRoomData data) {
    if (data.status == endedStatusCode) return const StreamUnavailable(_site, 'the broadcast has ended');
    if (data.status != liveStatusCode && data.status != replayStatusCode) {
      return StreamUnavailable(_site, 'status ${data.status}');
    }
    switch (data.access) {
      case WeiboAccess.restricted:
        final kind = restrictionOfLimit(data.watchLimit).name;
        final tip = data.tip == null ? '' : ': ${data.tip}';
        return StreamUnavailable(_site, 'restricted broadcast ($kind, watch_limit ${data.watchLimit})$tip');
      case WeiboAccess.disabled:
        return const StreamUnavailable(_site, 'play_switch 0');
      case WeiboAccess.public:
        if (data.status == liveStatusCode && data.mediaUrls.isEmpty) {
          return const StreamUnavailable(_site, 'live without a media URL');
        }
        if (data.status == replayStatusCode && data.replayUrl == null) {
          return const StreamUnavailable(_site, 'an ended broadcast without a replay');
        }
        return null;
    }
  }

  /// The one quality the broadcast [data] plays: [original] live, [replay]
  /// for a replay; null when it plays nothing ([unplayable]).
  static LivePlayQuality? qualityOf(WeiboRoomData data) {
    if (unplayable(data) != null) return null;
    return data.status == liveStatusCode ? original : replay;
  }

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

  /// The one line of a replay's recording [url] for [replay]: an unsigned
  /// HLS VOD (`#EXT-X-ENDLIST`) without headers or lease.
  static LivePlayUrlResolution replayResolution(String url) =>
      LivePlayUrlResolution.lines([line(url)], appliedQualityData: replay.selectionId);

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
  /// backslash. A profile (`/u/<uid>`) or a post is no room; a `t.cn` short
  /// link needs a request ([shortLink]).
  static String? liveIdFromUrl(String raw) {
    final value = raw.trim();
    if (RegExp(r'[\\\s]').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !_plainHttp(uri)) return null;
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

  /// The request of a `t.cn` short link (Weibo's link shortener; a live
  /// post links its broadcast so, upgrade 18-9): http(s) on `t.cn` with the
  /// default port, no user info, no space or backslash, and one path
  /// segment of 4–16 letters or digits, with a trailing slash at most. The
  /// query and fragment are dropped and the request is made over https (the
  /// site answers both alike). Null for anything else. `t.cn` answers a 302
  /// to the target (S04-shortlink), or to `http://weibo.com/sorry` for an
  /// unknown code (S04-shortlink-missing).
  static Uri? shortLink(String raw) {
    final value = raw.trim();
    if (RegExp(r'[\\\s]').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !_plainHttp(uri) || uri.host != 't.cn') return null;
    final match = RegExp(r'^/([0-9A-Za-z]{4,16})/?$').firstMatch(uri.path);
    return match == null ? null : Uri.https('t.cn', '/${match[1]}');
  }

  /// Whether [uri] is http(s) with the default port and no user info.
  static bool _plainHttp(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == (uri.scheme == 'https' ? 443 : 80));

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

/// A display text (title, nickname): a string with HTML character
/// references decoded (18-7), empty for anything else (18-8; 3.x failed).
String _text(Object? value) => value is String ? decodeHtmlEntities(value) : '';

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

/// 3.x's `_owner`: a positive integer below 2^53, or null.
int? _uidOrNull(Object? value) => value is int && value >= 1 && value <= 9007199254740991 ? value : null;

/// [_uidOrNull], required.
int _uid(Object? value, String what) => _uidOrNull(value) ?? (throw ApiChanged(_site, '$what: $value'));

String _liveId(Object? value, String what) {
  if (value is String && WeiboApi.isLiveId(value)) return value;
  throw ApiChanged(_site, '$what: $value');
}

/// 3.x's `_url`: plain http(s) with a host, as written, without spaces,
/// backslashes, user info or a fragment; null for anything else, an empty
/// string included (18-8: a bad address only drops that line; 3.x failed
/// the room).
String? _mediaUrl(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (value.trim() != value ||
      RegExp(r'[\\\s]').hasMatch(value) ||
      uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return value;
}

/// A replay's recording ([_mediaUrl]) made https, as the web player does
/// (the replay CDN answers https, checked 2026-09-28).
String? _replayUrl(Object? value) => switch (_mediaUrl(value)) {
  final String url when url.toLowerCase().startsWith('http:') => 'https${url.substring('http'.length)}',
  final url => url,
};
