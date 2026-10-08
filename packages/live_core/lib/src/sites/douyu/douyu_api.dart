import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'douyu';

/// What a stored Douyu login cookie is worth (3.x's `DouyuSessionState`).
enum DouyuSessionState {
  /// No cookie.
  none,

  /// A cookie without a session token: requests go out as a guest.
  guest,

  /// A token that has not expired, or whose end is unknown.
  valid,

  /// Expired, but LTP0 and the login's device id can renew it.
  expiredRefreshable,

  /// Expired, with nothing to renew it with.
  expired,
}

/// One Douyu quality option: the opaque `rate` request code and the CDN
/// codes to sign it on, in line order (3.x's `DouyuPlayData`).
@immutable
final class DouyuPlayData {
  /// Creates the option data.
  new(this.rate, List<String> cdns) : cdns = List.unmodifiable(cdns);

  /// Request code (`0` is usually source, `-1` lets the server choose); never
  /// a bitrate, never compared by size.
  final int rate;

  /// CDN codes, one line each; `''` lets the server pick.
  final List<String> cdns;

  @override
  String toString() => 'DouyuPlayData($rate, $cdns)';
}

/// What the danmaku connection needs to join one room: the canonical rid
/// sent in `loginreq` and `joingroup` (3.x passed the rid alone). The
/// endpoint is [DouyuApi.danmakuServer].
@immutable
final class DouyuDanmakuArgs {
  /// Creates the arguments.
  const new(this.roomId);

  /// Canonical numeric room id (`room.room_id`).
  final String roomId;

  @override
  String toString() => 'DouyuDanmakuArgs($roomId)';
}

/// The encryption descriptor of `getEncryption`, which signs play requests
/// (3.x's `DouyuUtils._encKey`).
@immutable
final class DouyuDescriptor {
  /// Creates a descriptor.
  const new({
    required this.key,
    required this.randStr,
    required this.encData,
    required this.encTime,
    required this.expireAt,
    required this.isSpecial,
  });

  /// Reads the `data` object; null when a field is missing or blank, or
  /// `enc_time` is outside 1–16. Numbers may be strings.
  static DouyuDescriptor? fromJson(Object? value) {
    if (value is! Map) return null;
    final key = jsonString(value['key']);
    final randStr = jsonString(value['rand_str']);
    final encData = jsonString(value['enc_data']);
    final encTime = jsonInt(value['enc_time']);
    final expireAt = jsonInt(value['expire_at']);
    if (key == null || randStr == null || encData == null || encTime == null || expireAt == null) return null;
    if (encTime < 1 || encTime > 16) return null;
    return DouyuDescriptor(
      key: key,
      randStr: randStr,
      encData: encData,
      encTime: encTime,
      expireAt: DateTime.fromMillisecondsSinceEpoch(expireAt * 1000, isUtc: true),
      isSpecial: jsonInt(value['is_special']) == 1,
    );
  }

  /// Signing key.
  final String key;

  /// Initial secret.
  final String randStr;

  /// Passed through to the play form as is.
  final String encData;

  /// Hashing rounds, 1–16.
  final int encTime;

  /// When the platform stops accepting it.
  final DateTime expireAt;

  /// Special descriptors sign without the room id and time.
  final bool isSpecial;

  /// Usable when it expires more than [DouyuApi.descriptorMargin] after
  /// [now] (Unix seconds on both sides; 3.x once compared them with
  /// milliseconds and refetched it on every request).
  bool usableAt(DateTime now) => expireAt.isAfter(now.add(DouyuApi.descriptorMargin));

  /// `auth` for room [roomId] at Unix second [tt]: `rand_str` hashed with
  /// the key [encTime] times, then md5 of secret + key + rid + tt (without
  /// rid and tt when [isSpecial]).
  String auth(String roomId, int tt) {
    var secret = randStr;
    for (var round = 0; round < encTime; round++) {
      secret = md5.convert(utf8.encode('$secret$key')).toString();
    }
    final salt = isSpecial ? '' : '$roomId$tt';
    return md5.convert(utf8.encode('$secret$key$salt')).toString();
  }
}

/// Pure parsing of Douyu responses (3.x's `DouyuSite` and `DouyuUtils`,
/// with the archived v4 parser's fixes). Each function takes the response
/// text and status and returns 3.x's models or throws a `SiteError`.
abstract final class DouyuApi {
  /// Desktop Chrome 128, the UA 3.x sent with API and media requests.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0.0.0 Safari/537.36';

  /// The Edge 114 UA 3.x sent to `betard`.
  static const String detailUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';

  /// Origin of the web player.
  static const String origin = 'https://www.douyu.com';

  /// The only danmaku endpoint.
  static const String danmakuServer = 'wss://danmuproxy.douyu.com:8506';

  /// How long before `expire` a play URL is renewed (at most a quarter of
  /// its lifetime).
  static const Duration leaseLead = Duration(seconds: 45);

  /// The lifetime assumed, with the forced renewal on, for a FLV URL that
  /// states none (`expire=0`: signed-in URLs, and anonymous ones below
  /// source such as sample S09's rate 2), which the CDN may still cut on its
  /// own schedule (upgrade 2-1, the upstream TV app's `douyuForceRenewal`).
  static const Duration forcedLeaseLifetime = Duration(minutes: 5);

  /// A descriptor closer than this to its `expire_at` is not used.
  static const Duration descriptorMargin = Duration(seconds: 30);

  /// How long a descriptor is reused at most.
  static const Duration descriptorLifetime = Duration(minutes: 5);

  /// The web `dy_auth` lasts seven days from when it was saved.
  static const Duration webCookieLifetime = Duration(days: 7);

  /// A session is renewed within the last day.
  static const Duration renewalMargin = Duration(days: 1);

  /// Session tokens in order of preference: the H5 JWTs, then the web token.
  static const List<String> sessionTokenNames = ['acf_jwt_token', 'acf_auth', 'dy_auth'];

  /// The long-term renewal key; it only ever goes to the passport.
  static const String longTermKeyName = 'LTP0';

  /// The device id a login belongs to.
  static const String deviceIdName = 'dy_did';

  static const List<String> _passportFields = ['LTP0', 'acf_stk', 'acf_ccn', 'acf_ltkid', 'acf_ssid'];

  static const Set<String> _setCookieAttributes = {
    'path',
    'domain',
    'expires',
    'max-age',
    'samesite',
    'secure',
    'httponly',
  };

  // Catalog -------------------------------------------------------------------

  /// `m.douyu.com/api/cate/list`: `cate1Info` sorted by id, each with the
  /// `cate2Info` areas of that id in platform order. The area picture is
  /// `icon`, else `smallIcon`, else `pic` (an area can come with an empty
  /// `icon`: 辐射：避难所Online, 2026-09-30).
  static List<LiveCategory> categories(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'cate/list')['data']);
    final groups = data?['cate1Info'];
    final areas = data?['cate2Info'];
    if (groups is! List || areas is! List) throw const ApiChanged(_site, 'cate/list: no cate1Info or cate2Info');
    final categories = [
      for (final raw in groups)
        if (_object(raw) case final group? when jsonString(group['cate1Id']) != null)
          LiveCategory(
            id: jsonString(group['cate1Id'])!,
            name: decodeHtmlEntities(jsonString(group['cate1Name']) ?? ''),
            children: [
              for (final rawArea in areas)
                if (_object(rawArea) case final area?
                    when jsonString(area['cate1Id']) == jsonString(group['cate1Id']) &&
                        jsonString(area['cate2Id']) != null)
                  LiveArea(
                    platform: _site,
                    areaType: jsonString(group['cate1Id'])!,
                    typeName: decodeHtmlEntities(jsonString(group['cate1Name']) ?? ''),
                    areaId: jsonString(area['cate2Id'])!,
                    areaName: decodeHtmlEntities(jsonString(area['cate2Name']) ?? ''),
                    areaPic: _areaPicture(area),
                  ),
            ],
          ),
    ];
    return categories..sort((a, b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0));
  }

  static String _areaPicture(Map<String, dynamic> area) {
    for (final key in const ['icon', 'smallIcon', 'pic']) {
      final url = normalizeImageUrl(area[key]);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  /// `gapi/rkc/directory/mixList/2_<area>/<page>` (area rooms, 120 a page)
  /// and `japi/weblist/apinc/allpage/6/<page>` (recommendations, 40 a page).
  /// Only `type == 1` entries are rooms, all live. The page ends on an empty
  /// `rl` or at `pgcnt` (mixList; allpage always says 0), never by count.
  static ({List<LiveRoom> rooms, bool hasMore}) roomList(String body, {required int page, int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'room list')['data']);
    final raw = data?['rl'];
    if (data == null || (raw != null && raw is! List)) throw ApiChanged(_site, 'room list: no rl (${_snippet(body)})');
    final items = _list(raw);
    final rooms = [
      for (final item in items)
        if (_object(item) case final room? when jsonInt(room['type']) == 1) ?_listRoom(room),
    ];
    final pages = jsonInt(data['pgcnt']) ?? 0;
    return (rooms: rooms, hasMore: items.isNotEmpty && (pages <= 0 || page < pages));
  }

  static LiveRoom? _listRoom(Map<String, dynamic> item) {
    final id = _roomId(item['rid']);
    if (id == null) return null;
    final online = jsonString(item['ol']);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: decodeHtmlEntities(jsonString(item['rn']) ?? ''),
      nick: decodeHtmlEntities(jsonString(item['nn']) ?? ''),
      avatar: _listAvatar(item['av']),
      cover: normalizeImageUrl(item['rs16']),
      area: jsonString(item['c2name']) ?? '',
      watching: online ?? '0',
      popularity: online ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.live,
    );
  }

  /// `av` of the room lists: a path on mixList (`avatar_v3/2026…`, made
  /// `https://apic.douyucdn.cn/upload/<av>_middle.jpg`), a full URL on
  /// allpage; empty when there is none (3.x wrote `…/upload/null_middle.jpg`).
  static String _listAvatar(Object? value) {
    final url = normalizeImageUrl(value);
    if (url.isNotEmpty) return url;
    final path = jsonString(value);
    if (path == null || !RegExp(r'^[\w./-]+$').hasMatch(path)) return '';
    return 'https://apic.douyucdn.cn/upload/${path.startsWith('/') ? path.substring(1) : path}_middle.jpg';
  }

  // Search --------------------------------------------------------------------

  /// `japi/search/api/searchShow`: `isLive == 1` with `roomType == 0` is
  /// live, `roomType == 3` a loop room (replay, as its `betard` says), the
  /// rest offline. `hot` stays the platform's text (`353.9万`).
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'searchShow');
    return [
      for (final item in _list(_object(root['data'])?['relateShow']))
        if (_object(item) case final room?) ?_searchRoom(room),
    ];
  }

  static LiveRoom? _searchRoom(Map<String, dynamic> item) {
    final id = _roomId(item['rid']);
    if (id == null) return null;
    final hot = jsonString(item['hot']);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: decodeHtmlEntities(jsonString(item['roomName']) ?? ''),
      nick: decodeHtmlEntities(jsonString(item['nickName']) ?? ''),
      avatar: normalizeImageUrl(item['avatar']),
      cover: normalizeImageUrl(item['roomSrc']),
      area: jsonString(item['cateName']) ?? '',
      watching: hot ?? '0',
      popularity: hot ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: switch ((jsonInt(item['isLive']), jsonInt(item['roomType']) ?? 0)) {
        (1, 0) => LiveStatus.live,
        (1, 3) => LiveStatus.replay,
        _ => LiveStatus.offline,
      },
    );
  }

  /// `japi/search/api/searchUser`: streamers; live only with `roomType 0`.
  static List<LiveAnchorItem> searchAnchors(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'searchUser');
    return [
      for (final item in _list(_object(root['data'])?['relateUser']))
        if (_object(_object(item)?['anchorInfo']) case final anchor? when _roomId(anchor['rid']) != null)
          LiveAnchorItem(
            roomId: _roomId(anchor['rid'])!,
            avatar: normalizeImageUrl(anchor['avatar']),
            userName: decodeHtmlEntities(jsonString(anchor['nickName']) ?? ''),
            liveStatus: jsonInt(anchor['isLive']) == 1 && (jsonInt(anchor['roomType']) ?? 0) == 0,
          ),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// `betard/<rid>`: the room as the user asked for it ([requestedId]: the
  /// identity of a follow never changes) and the canonical rid
  /// (`room.room_id`) used for signing, streams and danmaku. The body may be
  /// a JSON-encoded string.
  ///
  /// `videoLoop == 1` is a loop room (replay); `show_status == 1` without a
  /// `【回放】` title is live; anything else offline, as in 3.x. A live room
  /// starts at `show_time` (Unix seconds; offline it is the last show's, so
  /// it is left out). A 200 HTML page ("该房间目前没有开放", or "已被关闭"
  /// for a 靓号) is `NotFound`; 403 (an alias) is `RiskControl`.
  static ({LiveRoom room, String rid}) roomDetail(String body, {required String requestedId, int status = 200}) {
    _status(status, 'betard', body);
    if (body.trimLeft().startsWith('<')) throw NotFound(_site, 'betard/$requestedId: HTML page (${_pageText(body)})');
    if (status < 200 || status >= 300) throw ApiChanged(_site, 'betard: HTTP $status (${_snippet(body)})');
    var decoded = _decode(body);
    if (decoded is String) decoded = _decode(decoded);
    final room = _object(_object(decoded)?['room']);
    if (room == null) throw ApiChanged(_site, 'betard: no room (${_snippet(body)})');
    final rid = _roomId(room['room_id']);
    if (rid == null) throw const ApiChanged(_site, 'betard: room.room_id missing');
    final rawTitle = jsonString(room['room_name']) ?? '';
    final replay = jsonInt(room['videoLoop']) == 1;
    final live = jsonInt(room['show_status']) == 1 && !replay && !rawTitle.startsWith('【回放】');
    final hot = jsonString(_object(room['room_biz_all'])?['hot']);
    final id = requestedId.trim();
    return (
      rid: rid,
      room: LiveRoom(
        roomId: id,
        platform: _site,
        title: decodeHtmlEntities(rawTitle),
        nick: decodeHtmlEntities(jsonString(room['owner_name']) ?? ''),
        avatar: normalizeImageUrl(room['owner_avatar']),
        cover: normalizeImageUrl(room['room_pic']),
        area: jsonString(room['second_lvl_name']) ?? '',
        watching: hot ?? '0',
        popularity: hot ?? '',
        audienceMetricType: AudienceMetricType.popularity,
        liveStatus: replay
            ? LiveStatus.replay
            : live
            ? LiveStatus.live
            : LiveStatus.offline,
        link: 'https://www.douyu.com/$id',
        introduction: decodeHtmlEntities(jsonString(room['show_details']) ?? ''),
        notice: '',
        startedAt: live ? _seconds(room['show_time']) : null,
      ),
    );
  }

  /// A Unix-seconds time; null when missing or not after 1970.
  static DateTime? _seconds(Object? value) => switch (jsonInt(value)) {
    final int seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    _ => null,
  };

  /// The canonical rid a room page names: `www.douyu.com/<靓号>` is served
  /// directly with `window.room_id = <rid>` (or `"room_id":<rid>` in its
  /// data), while `betard/<靓号>` answers "房间已被关闭". Null when the page
  /// names none (a missing room gets the home page).
  static String? roomIdInPage(String html) {
    final match =
        RegExp(r'window\.room_id\s*=\s*(\d+)').firstMatch(html) ??
        RegExp(r'\\?"room_id\\?"\s*:\s*\\?"?(\d+)').firstMatch(html);
    return _roomId(match?.group(1));
  }

  /// The rid in a room address [target] (an alias page redirects to
  /// `/<rid>`), or null.
  static String? roomIdAt(Uri target) {
    final host = target.host.toLowerCase();
    if (host != 'douyu.com' && !host.endsWith('.douyu.com')) return null;
    final first = target.pathSegments.where((segment) => segment.isNotEmpty).firstOrNull;
    return first != null && RegExp(r'^\d{1,18}$').hasMatch(first) ? _roomId(first) : null;
  }

  // Streams -------------------------------------------------------------------

  /// `getEncryption`: the descriptor, which must be complete and usable at
  /// [now]; anything else is `ApiChanged`.
  static DouyuDescriptor descriptor(String body, {required DateTime now, int status = 200}) {
    final root = _checked(body, status: status, what: 'getEncryption');
    final descriptor = DouyuDescriptor.fromJson(root['data']);
    if (descriptor == null || !descriptor.usableAt(now)) {
      throw const ApiChanged(_site, 'getEncryption: descriptor incomplete or expired');
    }
    return descriptor;
  }

  /// The `getH5PlayV1` form for room [roomId] at Unix second [tt]. [did]
  /// must be the one the descriptor was issued for and the cookie carries.
  /// Only AVC is asked for (`hevc=0`).
  static Map<String, String> signedForm(
    DouyuDescriptor descriptor, {
    required String roomId,
    required int tt,
    required String did,
    int rate = -1,
    String cdn = '',
  }) => {
    'enc_data': descriptor.encData,
    'tt': '$tt',
    'did': did,
    'auth': descriptor.auth(roomId, tt),
    'cdn': cdn,
    'rate': '$rate',
    'hevc': '0',
    'fa': '0',
    'ive': '0',
    'ver': 'Douyu_new',
    'iar': '0',
  };

  /// `getH5PlayV1` → its `data`. HTTP 403 (the edge's bare `"鉴权失败"`) is
  /// `RiskControl`; `error != 0` (`-5` 房间未开播) is `StreamUnavailable`,
  /// which a retry cannot fix; no `data` is `ApiChanged`. `error` may be a
  /// string; without `error` the `code` counts.
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    _status(status, 'getH5PlayV1', body);
    final decoded = _decode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiChanged(_site, 'getH5PlayV1: HTTP $status, not an object (${_snippet(body)})');
    }
    final code = jsonInt(decoded['error'] ?? decoded['code']);
    if (code == null) throw ApiChanged(_site, 'getH5PlayV1: no error code (${_snippet(body)})');
    if (code != 0) {
      throw StreamUnavailable(_site, 'getH5PlayV1: error $code ${jsonString(decoded['msg']) ?? ''}'.trim());
    }
    final data = _object(decoded['data']);
    if (data == null || status < 200 || status >= 300) throw ApiChanged(_site, 'getH5PlayV1: HTTP $status, no data');
    return data;
  }

  /// Qualities of a metadata answer (`rate=-1`): `multirates` in the
  /// platform's order (never sorted: `rate` is a request code), first of a
  /// rate wins, each with [cdns] of the answer. Without `multirates`, one
  /// "默认" option for `data.rate`.
  ///
  /// `streamStatus: 0` is `StreamUnavailable` (E01.7): the room is on air
  /// (`betard`) but no stream is pushed, and the URL it still carries
  /// answers 404 on every CDN (14 such rooms on 2026-10-08, against about
  /// 60 with `1` that all played). Only the metadata answer is judged: a
  /// per-rate answer of a room that played once said `0`
  /// (S09-24422-r2-hw-h5).
  static List<LivePlayQuality> qualities(Map<String, dynamic> data) {
    if (jsonInt(data['streamStatus']) == 0) {
      throw const StreamUnavailable(_site, 'getH5PlayV1: streamStatus 0 (no stream pushed)');
    }
    final lines = cdns(data);
    final items = [for (final raw in _list(data['multirates'])) ?_object(raw)];
    final seen = <int>{};
    final qualities = <LivePlayQuality>[
      for (final (index, item) in items.indexed)
        if (jsonInt(item['rate']) case final rate? when seen.add(rate))
          LivePlayQuality(
            quality: LiveQualityLabel.normalize(platform: _site, rawLabel: jsonString(item['name']) ?? '', id: rate),
            id: rate,
            sort: items.length - index,
            data: DouyuPlayData(rate, lines),
          ),
    ];
    if (qualities.isNotEmpty) return qualities;
    final rate = jsonInt(data['rate']) ?? -1;
    return [
      LivePlayQuality(
        quality: LiveQualityLabel.normalize(platform: _site, rawLabel: 'default', id: rate),
        id: rate,
        sort: 1,
        data: DouyuPlayData(rate, lines),
      ),
    ];
  }

  /// CDN codes: `cdnsWithName` in order without duplicates, the answering
  /// `rtmp_cdn` first when it is missing, `scdn*` codes last; `['']` (the
  /// server picks) when there are none. A line's identity is its code, never
  /// its index.
  static List<String> cdns(Map<String, dynamic> data) {
    final codes = <String>[];
    for (final item in _list(data['cdnsWithName'])) {
      final code = jsonString(_object(item)?['cdn']);
      if (code != null && !codes.contains(code)) codes.add(code);
    }
    final current = jsonString(data['rtmp_cdn']);
    if (current != null && !codes.contains(current)) codes.insert(0, current);
    if (codes.isEmpty) return const [''];
    return [...codes.where((code) => !code.startsWith('scdn')), ...codes.where((code) => code.startsWith('scdn'))];
  }

  /// The rate the server delivered: an integer (number or integer string,
  /// `"0"` included) of 0 or more; missing, negative, fractional or text is
  /// unconfirmed (null), never truncated into source quality.
  static int? confirmedRate(Map<String, dynamic> data) => switch (jsonInt(data['rate'])) {
    final int rate when rate >= 0 => rate,
    _ => null,
  };

  /// The media URL of a play answer, entities decoded, or null:
  /// an absolute `rtmp_live` as is; else `rtmp_url` (then `flv_url`) joined
  /// with `rtmp_live`; else `player_1`, `stream_url` or `url`; else an
  /// `flv_url` ending in `.flv`, `.m3u8` or `.mp4`. A CDN base alone is
  /// never media ("输入流地址格式错误").
  static String? mediaUrl(Map<String, dynamic> data) {
    String field(String key) => decodeHtmlEntities(jsonString(data[key]) ?? '');
    final live = field('rtmp_live');
    if (_playable(live)) return live;
    for (final key in const ['rtmp_url', 'flv_url']) {
      final base = field(key);
      if (base.isEmpty || live.isEmpty) continue;
      final joined = '${base.replaceFirst(RegExp(r'/+$'), '')}/${live.replaceFirst(RegExp('^/+'), '')}';
      if (_playable(joined)) return joined;
    }
    for (final key in const ['player_1', 'stream_url', 'url']) {
      final value = field(key);
      if (_playable(value)) return value;
    }
    final flv = field('flv_url');
    final path = Uri.tryParse(flv)?.path.toLowerCase() ?? '';
    if (_playable(flv) && (path.endsWith('.flv') || path.endsWith('.m3u8') || path.endsWith('.mp4'))) return flv;
    return null;
  }

  /// One CDN's answer as a line of room [roomId] signed at [issuedAt], with
  /// the rate the server confirmed; [forceRenewal] as in [lease]. No media
  /// URL is `ApiChanged`.
  static ({LivePlayLine line, int? rate}) answer(
    Map<String, dynamic> data, {
    required String roomId,
    required String cdn,
    required String cookie,
    required DateTime issuedAt,
    bool forceRenewal = false,
  }) {
    final url = mediaUrl(data);
    if (url == null) throw const ApiChanged(_site, 'getH5PlayV1: no playable URL');
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return (
      line: LivePlayLine(
        url,
        headers: mediaHeaders(roomId, cookie: cookie),
        format: path.endsWith('.flv')
            ? StreamFormat.flv
            : path.endsWith('.m3u8')
            ? StreamFormat.hls
            : null,
        lineId: cdn.isEmpty ? null : cdn,
        lease: lease(url, issuedAt, forceRenewal: forceRenewal),
      ),
      rate: confirmedRate(data),
    );
  }

  /// The lines for one requested rate from the CDNs' [answers] (in CDN
  /// order). CDNs may confirm different rates, and one label must never
  /// cover a mix: the group confirming [requestedRate] wins, else the first
  /// confirmed group, else the unconfirmed one (marked so).
  static LivePlayUrlResolution resolution(
    List<({LivePlayLine line, int? rate})> answers, {
    required int requestedRate,
  }) {
    if (answers.isEmpty) return LivePlayUrlResolution(urls: const []);
    final groups = <int?, List<LivePlayLine>>{};
    for (final answer in answers) {
      final group = groups.putIfAbsent(answer.rate, () => []);
      if (group.every((line) => line.url != answer.line.url)) group.add(answer.line);
    }
    final applied = groups.containsKey(requestedRate) ? requestedRate : groups.keys.whereType<int>().firstOrNull;
    return LivePlayUrlResolution.lines(
      groups[applied]!,
      appliedQualityData: applied,
      qualityUnconfirmed: applied == null,
    );
  }

  /// The lifetime a media URL states: its `expire` seconds when above 0
  /// (there is no absolute time in the URL); null for `expire=0` or none.
  static Duration? statedLifetime(String url) {
    final query = Uri.tryParse(url)?.query ?? '';
    final expire = int.tryParse(RegExp(r'(?:^|&)expire=(\d+)(?:&|$)').firstMatch(query)?.group(1) ?? '');
    return expire == null || expire <= 0 ? null : Duration(seconds: expire);
  }

  /// The lease of a media URL issued at [issuedAt]: its [statedLifetime];
  /// with [forceRenewal], a FLV URL that states none gets
  /// [forcedLeaseLifetime] (upgrade 2-1). Renew [leaseLead] (at most a
  /// quarter of the lifetime) before. Expiry closes the established
  /// connection, so the renewed stream is spliced in.
  static PlayLease? lease(String url, DateTime issuedAt, {bool forceRenewal = false}) {
    final lifetime =
        statedLifetime(url) ??
        (forceRenewal && (Uri.tryParse(url)?.path.toLowerCase().endsWith('.flv') ?? false)
            ? forcedLeaseLifetime
            : null);
    if (lifetime == null) return null;
    final expiresAt = issuedAt.toUtc().add(lifetime);
    final quarter = Duration(seconds: lifetime.inSeconds ~/ 4);
    return PlayLease(
      refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead),
      expiresAt: expiresAt,
      cutsConnection: true,
    );
  }

  /// API request headers; the referer is room [roomId]'s page, or the home
  /// page without one.
  static Map<String, String> apiHeaders(String cookie, {String? roomId}) => {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'origin': origin,
    'referer': roomId == null || roomId.isEmpty ? 'https://www.douyu.com/' : 'https://www.douyu.com/$roomId',
    'user-agent': userAgent,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// Media request headers for room [roomId], shared by playback and
  /// recording (3.x's `PlaybackHeaderResolver` branch): Origin, the room's
  /// Referer, UA and the DID cookie.
  static Map<String, String> mediaHeaders(String roomId, {required String cookie}) => {
    'origin': origin,
    'referer': 'https://www.douyu.com/$roomId',
    'user-agent': userAgent,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  // Session -------------------------------------------------------------------

  /// A new per-process device id: 32 lower-case hex digits.
  static String generateDeviceId(Random random) =>
      [for (var i = 0; i < 32; i++) random.nextInt(16).toRadixString(16)].join();

  /// [cookie] without control characters, outer blanks or a pasted
  /// `Cookie:` prefix.
  static String normalizeCookie(String cookie) =>
      cookie.replaceAll(_controls, '').trim().replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '').trim();

  /// The `name=value` fields of [cookie] in order; a malformed name is
  /// skipped and a later field replaces an earlier one of the same name.
  static Map<String, String> cookieFields(String cookie) {
    final fields = <String, String>{};
    for (final part in normalizeCookie(cookie).split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (!_cookieName.hasMatch(name)) continue;
      fields[name] = part.substring(separator + 1).trim();
    }
    return fields;
  }

  /// Field [name] of [cookie] (any case), or null when absent or blank.
  static String? cookieField(String cookie, String name) {
    final wanted = name.toLowerCase();
    for (final MapEntry(:key, :value) in cookieFields(cookie).entries) {
      if (key.toLowerCase() == wanted) return value.isEmpty ? null : value;
    }
    return null;
  }

  /// The device id of every request: the account cookie's `dy_did` (the
  /// login belongs to it; signing with another is answered as a guest),
  /// else [processDid].
  static String deviceId(String account, String processDid) => cookieField(account, deviceIdName) ?? processDid;

  /// The request cookie: `dy_did` and `acf_did` set to [did] first, then the
  /// account fields without their own device ids and without `LTP0`
  /// (passport only; the play edge answers 403 to it). Values are sent
  /// verbatim (`%2B` stays encoded).
  static String cookieHeader({required String account, required String did}) => [
    'dy_did=$did',
    'acf_did=$did',
    for (final MapEntry(:key, :value) in cookieFields(account).entries)
      if (!const {'dy_did', 'acf_did', 'ltp0'}.contains(key.toLowerCase())) '$key=$value',
  ].join('; ');

  /// The session token: `acf_jwt_token`, else `acf_auth`, else `dy_auth`.
  static String? sessionToken(String cookie) {
    for (final name in sessionTokenNames) {
      final value = cookieField(cookie, name);
      if (value != null) return value;
    }
    return null;
  }

  /// The payload of a JWT, or null when [token] is not one.
  static Map<String, Object?>? jwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// When the session ends: the JWT's `exp` (H5 tokens), else [savedAt]
  /// plus seven days (the opaque web `dy_auth`); null when nothing says,
  /// never guessed.
  static DateTime? sessionExpiry(String cookie, {DateTime? savedAt}) {
    final token = sessionToken(cookie);
    if (token == null) return null;
    final exp = jsonInt(jwtPayload(token)?['exp']);
    if (exp != null && exp > 0) return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    return savedAt?.add(webCookieLifetime);
  }

  /// What [cookie] is worth at [now]; [ltp0] and [did] are the renewal
  /// credentials ([renewalCredentials]).
  static DouyuSessionState sessionState(
    String cookie, {
    required DateTime now,
    DateTime? savedAt,
    String? ltp0,
    String? did,
  }) {
    if (normalizeCookie(cookie).isEmpty) return DouyuSessionState.none;
    if (sessionToken(cookie) == null) return DouyuSessionState.guest;
    final end = sessionExpiry(cookie, savedAt: savedAt);
    if (end == null || end.isAfter(now)) return DouyuSessionState.valid;
    return ltp0 != null && did != null ? DouyuSessionState.expiredRefreshable : DouyuSessionState.expired;
  }

  /// Whether to renew before a play request: no token, or within
  /// [renewalMargin] of the end. An unknown end is left alone.
  static bool shouldRenew(String cookie, {required DateTime now, DateTime? savedAt}) {
    if (sessionToken(cookie) == null) return true;
    final end = sessionExpiry(cookie, savedAt: savedAt);
    return end != null && !now.isBefore(end.subtract(renewalMargin));
  }

  /// LTP0 and the device id a renewal needs: typed, else the cookie's own
  /// fields, else the separately stored ones. The device id never falls
  /// back to the process DID (the passport refuses another device).
  static ({String? ltp0, String? did}) renewalCredentials(
    String cookie, {
    String? typedLtp0,
    String? typedDid,
    String? storedLtp0,
    String? storedDid,
  }) => (
    ltp0: _clean(typedLtp0) ?? cookieField(cookie, longTermKeyName) ?? _clean(storedLtp0),
    did: _clean(typedDid) ?? cookieField(cookie, deviceIdName) ?? _clean(storedDid),
  );

  /// A cookie copied from the passport request: renewal fields and no
  /// session token. It is no login and must not be sent to play endpoints.
  static bool isPassportCookie(String cookie) =>
      sessionToken(cookie) == null && _passportFields.any((name) => cookieField(cookie, name) != null);

  /// [cookie] with a renewal's `Set-Cookie` [lines] merged in: fields the
  /// answer did not mention stay (LTP0 among them, or the next renewal has
  /// nothing to use), emptied ones are removed, attributes are ignored.
  static String mergeSetCookie(String cookie, Iterable<String> lines) {
    final merged = cookieFields(cookie);
    for (final line in lines) {
      final pair = line.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      if (!_cookieName.hasMatch(name) || _setCookieAttributes.contains(name.toLowerCase())) continue;
      final value = pair.substring(separator + 1).replaceAll(_controls, '').trim();
      if (value.isEmpty) {
        merged.remove(name);
      } else {
        merged[name] = value;
      }
    }
    return merged.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  /// The renewed login from a passport answer's `Set-Cookie` [lines]: null
  /// when there are none (nothing was renewed, and the save time must not
  /// move) or the merge left no session token (keep the old cookie).
  static String? renewedCookie(String cookie, List<String> lines) {
    if (lines.isEmpty) return null;
    final merged = mergeSetCookie(cookie, lines);
    return sessionToken(merged) == null ? null : merged;
  }

  static final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _cookieName = RegExp(r"^[A-Za-z0-9_!#$%&'*+.^`|~-]+$");

  static String? _clean(String? value) {
    final text = value?.replaceAll(_controls, '').trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _playable(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.host.isNotEmpty && const {'http', 'https', 'rtmp'}.contains(uri.scheme.toLowerCase());
  }
}

/// Douyu room ids are positive decimal integers.
String? _roomId(Object? value) {
  final id = jsonInt(value);
  return id != null && id > 0 ? '$id' : null;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The visible text of an HTML error page, for the diagnostic.
String _pageText(String html) => _snippet(
  html
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp('<[^>]*>'), ' '),
);

/// Status codes every endpoint shares: 403 is the edge refusing the client
/// (`RiskControl`), 412 and 429 `RateLimited`, 5xx `NetworkFailure`.
void _status(int status, String what, String body) {
  if (status == 403) throw RiskControl(_site, detail: '$what: HTTP 403 (${_snippet(body)})');
  if (status == 412 || status == 429) throw RateLimited(_site, detail: '$what: HTTP $status');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
}

/// The `{error|code, msg, data}` envelope: [_status] first; a non-object
/// body, a non-2xx status or a non-zero `error`/`code` is `ApiChanged` with
/// the platform's message.
Map<String, dynamic> _checked(String body, {required int status, required String what}) {
  _status(status, what, body);
  final decoded = _decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw ApiChanged(_site, '$what: HTTP $status, not an object (${_snippet(body)})');
  }
  final code = jsonInt(decoded['error'] ?? decoded['code']);
  if (code != null && code != 0) {
    throw ApiChanged(_site, '$what: error $code ${jsonString(decoded['msg']) ?? ''}'.trim());
  }
  if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
  return decoded;
}
