import 'dart:convert';
import 'dart:math' as math;

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'douyin';
const _origin = 'https://live.douyin.com';

/// What the danmaku connection needs to join one broadcast (3.x's
/// `DouyinDanmakuArgs`, same fields).
@immutable
final class DouyinDanmakuArgs {
  /// Creates the arguments.
  const new({required this.webRid, required this.roomId, required this.userId, required this.cookie, this.refresh});

  /// The room page id (the Referer of the handshake).
  final String webRid;

  /// This broadcast's room_id (`room_id` of the connection); every broadcast
  /// gets a new one.
  final String roomId;

  /// The 19-digit visitor id (`user_unique_id`), the same for every room.
  final String userId;

  /// The cookie of the API requests (the user's, else the anonymous ttwid);
  /// empty when there is none.
  final String cookie;

  /// The arguments of the room's broadcast now, from a new detail request;
  /// null when the room is not live. The danmaku connection asks when it
  /// went quiet or gave up, to follow a streamer who went live again under
  /// a new [roomId] (M5.F B-5).
  final Future<DouyinDanmakuArgs?> Function()? refresh;

  /// The handshake headers 3.x sent: UA, the cookie when there is one,
  /// Origin and the room's Referer (REG-DOUYIN-003).
  Map<String, String> get headers => {
    'user-agent': DouyinApi.userAgent,
    if (cookie.trim().isNotEmpty) 'cookie': cookie,
    'origin': _origin,
    'referer': '$_origin/$webRid',
  };

  /// Diagnostics without the cookie (3.x redacted it too).
  @override
  String toString() =>
      jsonEncode({'webRid': webRid, 'roomId': roomId, 'userId': userId, 'cookie': cookie.isEmpty ? '' : '<redacted>'});
}

/// One room response: the room as 3.x built it, this broadcast's room_id,
/// the stream description (`room.stream_url`, live only) and, from reflow,
/// whether the queried broadcast has ended.
typedef DouyinRoom = ({
  LiveRoom room,
  String? roomId,
  Map<String, dynamic>? streamUrl,
  String? userUniqueId,
  bool sessionEnded,
});

/// Pure parsing of Douyin responses (3.x's `DouyinSite` and `DouyinSearch`,
/// with the archived v4 parser's fixes). Each function takes the response
/// text, status and headers and returns 3.x's models or throws a
/// `SiteError`. Request signing is in `DouyinSigner`.
abstract final class DouyinApi {
  /// Desktop Chrome 134, the UA of 3.x's API requests, the one a_bogus
  /// encodes and the danmaku handshake's.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/134.0.0.0 Safari/537.36';

  /// Douyin's web app id.
  static const String aid = '6383';

  /// `version_code` of the danmaku connection.
  static const String versionCode = '180800';

  /// `webcast_sdk_version` of the danmaku connection.
  static const String sdkVersion = '1.0.15';

  /// The area 3.x shows for a recommended room that names none.
  static const String recommendArea = '热门推荐';

  /// The longest lead before a play URL's expiry at which it is renewed
  /// (at most a quarter of its lifetime).
  static const Duration leaseLead = Duration(minutes: 10);

  /// Room ids of more than 16 digits are per-broadcast room_ids (3.x's rule);
  /// shorter ones are web_rids, the room's lasting identity.
  static bool isRoomId(String id) => RegExp(r'^\d{17,}$').hasMatch(id.trim());

  // Catalog -------------------------------------------------------------------

  /// The categories of the `live.douyin.com/?from_nav=1` page, whose data is
  /// the page's React Server Component payload (`self.__pace_f.push`).
  /// Ids are `id_str,type`; every category lists itself first as its "all"
  /// area. The third level (single games under 游戏's sub-categories, ids
  /// like `1010014,1`) follows its sub-category and has it as parent; a game
  /// listed under two sub-categories appears once, under the first.
  static List<LiveCategory> categories(String html, {int status = 200, Map<String, List<String>> headers = const {}}) {
    _checkHttp(html, status, headers, 'home page');
    final raw = _flightObject(_flightRows(html), 'categoryData')?['categoryData'];
    if (raw is! List) throw const ApiChanged(_site, 'home page: categoryData missing');
    return [
      for (final item in raw)
        if (_partition(_map(item)?['partition']) case final top?)
          LiveCategory(id: top.id, name: top.name, children: _areas(top, _list(_map(item)!['sub_partition']))),
    ];
  }

  /// [top] itself, then each sub-partition followed by its own (games).
  static List<LiveArea> _areas(({String id, String name}) top, List<Object?> subs) {
    final seen = <String>{};
    LiveArea? area(({String id, String name})? partition, ({String id, String name}) parent) =>
        partition != null && seen.add(partition.id)
        ? LiveArea(
            platform: _site,
            areaId: partition.id,
            areaType: parent.id,
            typeName: parent.name,
            areaName: partition.name,
          )
        : null;
    return [
      ?area(top, top),
      for (final sub in subs)
        if (_partition(_map(sub)?['partition']) case final partition?) ...[
          ?area(partition, top),
          for (final game in _list(_map(sub)!['sub_partition'])) ?area(_partition(_map(game)?['partition']), partition),
        ],
    ];
  }

  /// The `partition` and `partition_type` of an area id `id_str,type`;
  /// anything else is `NotFound`.
  static ({String partition, String type}) partition(String areaId) {
    final comma = areaId.lastIndexOf(',');
    if (comma <= 0 || comma == areaId.length - 1) throw NotFound(_site, 'area id "$areaId" is not id_str,type');
    return (partition: areaId.substring(0, comma).trim(), type: areaId.substring(comma + 1).trim());
  }

  /// `partition/detail/room/v2` requested at [offset]: every room is live;
  /// the area is `tag_name`, else [areaName] (the amemv host leaves it
  /// empty). More pages follow while `data.count` is positive and
  /// `data.offset` (the next offset) advances. An empty 200 with
  /// `bdturing-verify` is a captcha: `RiskControl`.
  static ({List<LiveRoom> rooms, bool hasMore}) partitionRooms(
    String body, {
    required int offset,
    String? areaName,
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    final data = _map(_checked(body, status, headers, 'partition rooms')['data']);
    final list = data?['data'];
    if (data == null || list is! List) throw const ApiChanged(_site, 'partition rooms: data.data missing');
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final raw in list) {
      final item = _map(raw);
      final room = _map(item?['room']);
      if (item == null || room == null) continue;
      final owner = _map(room['owner']) ?? const {};
      final id = _firstId([item['web_rid'], owner['web_rid'], room['id_str']]);
      if (id == null || !seen.add(id)) continue;
      rooms.add(
        _listRoom(
          id,
          room: room,
          title: _text(room['title']) ?? '',
          nick: _text(owner['nickname']) ?? '',
          cover: _firstImage([room['cover']]),
          avatar: _firstImage([owner['avatar_thumb']]),
          area: _text(item['tag_name']) ?? areaName ?? '',
        ),
      );
    }
    final count = jsonInt(data['count']);
    final next = jsonInt(data['offset']);
    return (rooms: rooms, hasMore: (count == null || count > 0) && next != null && next > offset);
  }

  /// `webcast/feed/` recommendations, both generations (REG-DOUYIN-007):
  /// the envelope list of 2026-08 (room in `data[].data`, possibly a JSON
  /// string, or in `room`) and the older `data.data` room list. Identity is
  /// the web_rid, else the room_id; duplicates are dropped. A room without an
  /// area shows [recommendArea] as in 3.x.
  static List<LiveRoom> feed(String body, {int status = 200, Map<String, List<String>> headers = const {}}) {
    final root = _checked(body, status, headers, 'feed');
    var list = root['data'];
    if (list is Map) list = list['data'];
    if (list is! List) throw const ApiChanged(_site, 'feed: room list missing');
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final raw in list) {
      final envelope = _map(raw);
      if (envelope == null) continue;
      final room = [
        _map(envelope['data']),
        _map(envelope['room']),
        envelope,
      ].firstWhere((candidate) => candidate != null && _looksLikeRoom(candidate), orElse: () => null);
      if (room == null) continue;
      final owner = _map(room['owner']) ?? _map(envelope['owner']) ?? const {};
      final id = _firstId([envelope['web_rid'], owner['web_rid'], room['web_rid'], room['id_str'], room['id']]);
      if (id == null || !seen.add(id)) continue;
      rooms.add(
        _listRoom(
          id,
          room: room,
          title: _firstText([room['title'], envelope['title'], owner['nickname']]) ?? '',
          nick: _firstText([owner['nickname'], envelope['nickname']]) ?? '',
          cover: _firstImage([room['cover'], envelope['cover']]),
          avatar: _firstImage([owner['avatar_thumb'], owner['avatar_large'], envelope['avatar_thumb']]),
          area: _feedArea(envelope, room) ?? recommendArea,
        ),
      );
    }
    return rooms;
  }

  static LiveRoom _listRoom(
    String id, {
    required Map<String, dynamic> room,
    required String title,
    required String nick,
    required String cover,
    required String avatar,
    required String area,
  }) {
    final audience = _audience(room);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: title,
      nick: nick,
      cover: cover,
      avatar: avatar,
      area: area,
      watching: audience.watching,
      totalViewers: audience.total,
      onlineViewers: audience.online,
      audienceMetricType: audience.metric,
      liveStatus: LiveStatus.live,
      link: '$_origin/$id',
    );
  }

  // Search --------------------------------------------------------------------

  /// Live search (`aweme/v1/web/live/search/`) and general search
  /// (`general/search/stream/`, whose body is hex-length framed JSON
  /// documents). An anonymous request answers 2483 "请先登录": `NeedsLogin`.
  ///
  /// A room may be nested (`lives.rawdata`, `aweme_info.live_info`, …, JSON
  /// strings included). Identity is `owner.web_rid`, else the room_id
  /// (REG-DOUYIN-014); `status` 2 is live; duplicates are dropped. As in 3.x
  /// the card's picture is the streamer's large avatar, then the cover; a
  /// missing nickname stays empty.
  static List<LiveRoom> searchRooms(String body, {int status = 200, Map<String, List<String>> headers = const {}}) {
    _checkHttp(body, status, headers, 'search');
    final items = <Object?>[];
    for (final chunk in _chunks(body)) {
      final data = _checked(chunk, 200, const {}, 'search')['data'];
      if (data is List) items.addAll(data);
    }
    final seen = <String>{};
    return [
      for (final item in items)
        if (_searchRoom(_map(item) ?? const {}) case final room? when seen.add(room.roomId)) room,
    ];
  }

  static LiveRoom? _searchRoom(Map<String, dynamic> item) {
    Object? at(Object? node, String key) => _map(node)?[key];
    final raw = [
      at(at(item, 'lives'), 'rawdata'),
      at(at(item, 'lives'), 'raw_data'),
      at(at(item, 'live'), 'rawdata'),
      at(at(item, 'live_info'), 'rawdata'),
      at(at(at(item, 'aweme_info'), 'live_info'), 'rawdata'),
      at(at(item, 'data'), 'rawdata'),
      item['rawdata'],
      item['lives'],
      item['live'],
      item['live_info'],
      at(at(item, 'aweme_info'), 'live_info'),
      item['aweme_info'],
      item['data'],
      item,
    ].map(_map).firstWhere((candidate) => candidate != null, orElse: () => null);
    if (raw == null) return null;
    final room = _map(raw['room']) ?? const {};
    final owner = _map(raw['owner']) ?? const {};
    final roomOwner = _map(room['owner']) ?? const {};
    final roomId = _firstId([
      raw['id_str'],
      raw['room_id_str'],
      room['id_str'],
      room['id'],
      raw['room_id'],
      raw['roomId'],
    ]);
    if (roomId == null) return null;
    final id = _firstId([owner['web_rid'], raw['web_rid'], roomOwner['web_rid']]) ?? roomId;
    final nickname = _firstText([owner['nickname'], raw['nickname'], roomOwner['nickname'], item['nickname']]);
    final roadMap = _list(room['partition_road_map']);
    final live = jsonInt(raw['status']) == 2;
    final online = _online(room).ifEmpty(() => _online(raw));
    final total = _total(room).ifEmpty(() => _total(raw));
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _firstText([raw['title'], room['title'], item['title'], item['desc'], nickname]) ?? '',
      // No placeholder name (3.x wrote "抖音直播"): an empty one keeps a
      // follow's stored name, and the UI shows the site name (M2.1).
      nick: nickname ?? '',
      cover: _firstImage([owner['avatar_large'], raw['cover'], room['cover'], raw['cover_url']]),
      avatar: _firstImage([owner['avatar_thumb'], owner['avatar_large']]),
      area:
          _firstText([
            raw['video_feed_tag'],
            if (roadMap.isNotEmpty) _map(roadMap.first)?['title'],
            _map(raw['partition'])?['title'],
            item['search_keyword'],
          ]) ??
          '',
      watching: total.ifEmpty(() => online),
      totalViewers: total,
      onlineViewers: online,
      audienceMetricType: total.isNotEmpty ? AudienceMetricType.totalViewers : AudienceMetricType.onlineViewers,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      link: '$_origin/$id',
    );
  }

  /// `webcast/web/partition/search/`: the partitions whose name matches the
  /// keyword (anonymous), as areas `id_str,type`.
  static List<LiveArea> partitionSearch(String body, {int status = 200, Map<String, List<String>> headers = const {}}) {
    final root = _checked(body, status, headers, 'partition search');
    return [
      for (final item in _list(_map(root['data'])?['SearchResult']))
        if (_partition(_map(item)?['partition']) case final area?)
          LiveArea(platform: _site, areaId: area.id, areaName: area.name),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// `room/web/enter/` for [webRid] (the identity, as requested): the room is
  /// `data.data[0]`, the streamer `data.user` when the room is offline.
  /// `status` 2 is live and any other status offline, as in 3.x; a missing
  /// status defers to `data.room_status` (0 live, 2 ended; upgrade 4-1).
  /// 4001038 or an empty list is `NotFound`; an empty 200 (no ttwid, or a
  /// rejected signature) is `RiskControl`.
  static DouyinRoom enter(
    String body, {
    required String webRid,
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    final data = _map(_checked(body, status, headers, 'enter')['data']);
    final list = data?['data'];
    if (data == null || list is! List) throw const ApiChanged(_site, 'enter: data.data missing');
    if (list.isEmpty) throw NotFound(_site, 'enter: no room for $webRid');
    final room = _map(list.first);
    if (room == null) throw const ApiChanged(_site, 'enter: data.data[0] is not an object');
    return _room(
      webRid: webRid.trim(),
      room: room,
      person: _map(data['user']),
      live: _isLive(room, roomStatus: data['room_status']),
      roadMap: _map(data['partition_road_map']),
    );
  }

  /// `room/reflow/info/` for a room_id: the identity is `room.owner.web_rid`;
  /// `status` 4 means the queried broadcast ended (query enter with the
  /// web_rid instead, as 3.x did). It is the only room answer that carries
  /// the broadcast's start (`start_time`), see [LiveRoom.startedAt].
  static DouyinRoom reflow(String body, {int status = 200, Map<String, List<String>> headers = const {}}) {
    final root = _checked(body, status, headers, 'reflow');
    final room = _map(_map(root['data'])?['room']);
    if (room == null) throw const ApiChanged(_site, 'reflow: data.room missing');
    final webRid = _webRid(_map(room['owner'])?['web_rid']);
    if (webRid == null) throw const ApiChanged(_site, 'reflow: room.owner.web_rid missing or not numeric');
    return _room(webRid: webRid, room: room, live: _isLive(room), sessionEnded: jsonInt(room['status']) == 4);
  }

  /// The web_rid of a reflow answer as 3.x's short-link parser took it: a
  /// string or integer of digits at `data.room.owner.web_rid`; null for
  /// anything else.
  static String? reflowWebRid(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    return _webRid(_map(_map(_map(_map(decoded)?['data'])?['room'])?['owner'])?['web_rid']);
  }

  /// The room page `live.douyin.com/{web_rid}`, the fallback when enter
  /// fails. Its state (`roomStore.roomInfo.room` and `anchor`,
  /// `userStore.odin.user_unique_id`) is in the page's React Server
  /// Component payload; references like `"stream_data": "$13"` are resolved
  /// from its text rows (3.x only unescaped the page and lost them).
  static DouyinRoom roomPage(
    String html, {
    required String webRid,
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    _checkHttp(html, status, headers, 'room page');
    final rows = _flightRows(html);
    final holder = _flightObject(
      rows,
      'roomStore',
      where: (state) => _map(_map(_map(state['roomStore'])?['roomInfo'])?['room']) != null,
    );
    final state = _map(_resolve(holder, rows));
    final info = _map(_map(state?['roomStore'])?['roomInfo']);
    final room = _map(info?['room']);
    if (state == null || info == null || room == null) {
      throw const ApiChanged(_site, 'room page: roomStore.roomInfo.room missing');
    }
    final visitor = _text(_map(_map(state['userStore'])?['odin'])?['user_unique_id']);
    return _room(
      webRid: webRid.trim(),
      room: room,
      person: _map(info['anchor']),
      live: _isLive(room),
      userUniqueId: visitor != null && RegExp(r'^\d{19}$').hasMatch(visitor) ? visitor : null,
    );
  }

  /// A detail answer (enter, reflow, room page) as a room. While live:
  ///
  /// - [LiveRoom.startedAt] is `start_time`, else `create_time` (Unix
  ///   seconds; only reflow has them, lists write a placeholder 0);
  /// - [LiveRoom.restriction] is [LiveRestriction.unplayable] when
  ///   `stream_url` has no video quality for this client (the platform says
  ///   live but gives no stream), else [LiveRestriction.none]. Douyin's own
  ///   paid and secret-room fields (`paid_live_data.paid_type`,
  ///   `basis.secret_room`) were 0 or absent in every recorded room, so they
  ///   are not read.
  ///
  /// An offline room has neither. The area is the room's game or partition
  /// ([_detailArea]); 3.x left it empty.
  static DouyinRoom _room({
    required String webRid,
    required Map<String, dynamic> room,
    required bool live,
    Map<String, dynamic>? person,
    Map<String, dynamic>? roadMap,
    String? userUniqueId,
    bool sessionEnded = false,
  }) {
    final owner = _map(room['owner']);
    final online = live ? _online(room) : '';
    final total = live ? _total(room) : '';
    final streamUrl = live ? _map(room['stream_url']) : null;
    return (
      room: LiveRoom(
        roomId: webRid,
        platform: _site,
        title: _text(room['title']) ?? '',
        nick:
            (live
                ? _firstText([owner?['nickname'], person?['nickname']])
                : _firstText([person?['nickname'], owner?['nickname']])) ??
            '',
        avatar: live
            ? _firstImage([owner?['avatar_thumb'], person?['avatar_thumb']])
            : _firstImage([person?['avatar_thumb'], owner?['avatar_thumb']]),
        cover: live ? _firstImage([room['cover']]) : '',
        area: _detailArea(room, roadMap),
        watching: total.ifEmpty(() => online),
        totalViewers: total,
        onlineViewers: online,
        audienceMetricType: total.isNotEmpty ? AudienceMetricType.totalViewers : AudienceMetricType.onlineViewers,
        liveStatus: live ? LiveStatus.live : LiveStatus.offline,
        link: '$_origin/$webRid',
        introduction: _text(owner?['signature']) ?? '',
        notice: '',
        startedAt: live ? _epochSeconds(room['start_time']) ?? _epochSeconds(room['create_time']) : null,
        restriction: live
            ? (_variants(streamUrl).list.isEmpty ? LiveRestriction.unplayable : LiveRestriction.none)
            : null,
      ),
      roomId: _firstId([room['id_str'], room['id']]),
      streamUrl: streamUrl,
      userUniqueId: userUniqueId,
      sessionEnded: sessionEnded,
    );
  }

  /// The area a detail answer names, as the room page shows it (M4.D): the
  /// game (`game_data.game_tag_info.game_tag_name`, 英雄联盟手游), else the
  /// most specific title of enter's `partition_road_map` (sub-partition,
  /// then partition: 竞技游戏). Rooms outside the game partitions name none
  /// (an empty map, `game_tag_name` ""), and the area stays empty as in 3.x.
  static String _detailArea(Map<String, dynamic> room, Map<String, dynamic>? roadMap) {
    Object? title(Map<String, dynamic>? node) => _map(node?['partition'])?['title'];
    return _firstText([
          _map(_map(room['game_data'])?['game_tag_info'])?['game_tag_name'],
          title(_map(roadMap?['sub_partition'])),
          title(roadMap),
        ]) ??
        '';
  }

  /// `status` 2 (number or string) is live and any other status offline
  /// (3.x's rule). A missing status defers to enter's [roomStatus]
  /// (`data.room_status`: 0 live, 2 ended; upgrade 4-1, the archived v4's
  /// rule); without either the room is offline, as in 3.x.
  static bool _isLive(Map<String, dynamic> room, {Object? roomStatus}) => switch (jsonInt(room['status'])) {
    final int status => status == 2,
    null => jsonInt(roomStatus) == 0,
  };

  /// A time in Unix seconds; null for 0 (Douyin's placeholder), negatives,
  /// values too large to be seconds and anything that is not an integer.
  static DateTime? _epochSeconds(Object? value) => switch (jsonInt(value)) {
    final int seconds when seconds > 0 && seconds < 100000000000 => DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ),
    _ => null,
  };

  /// `webcast/user/me/`: the signed-in account's nickname. 20003 ("User
  /// doesn't login", also the answer without a cookie) is `NeedsLogin`
  /// (3.x showed the error data as the account).
  static String account(String body, {int status = 200, Map<String, List<String>> headers = const {}}) {
    final name = _text(_map(_checked(body, status, headers, 'user/me')['data'])?['nickname']);
    if (name == null) throw ApiChanged(_site, 'user/me: data.nickname missing (${_snippet(body)})');
    return name;
  }

  // Session -------------------------------------------------------------------

  /// The anonymous cookie of a home page response: its `ttwid` and
  /// `UIFID_TEMP` pairs; null without a ttwid.
  static String? anonymousCookie(Map<String, List<String>> headers) {
    final pairs = [
      for (final line in headers['set-cookie'] ?? const <String>[])
        if (line.split(';').first.trim() case final pair
            when pair.startsWith('ttwid=') || pair.startsWith('UIFID_TEMP='))
          pair,
    ];
    if (!pairs.any((pair) => pair.length > 'ttwid='.length && pair.startsWith('ttwid='))) return null;
    return pairs.join('; ');
  }

  /// Headers of the `live.douyin.com` API and pages (3.x also sent the
  /// non-standard `authority`).
  static Map<String, String> apiHeaders(String cookie) => {
    'authority': 'live.douyin.com',
    'referer': _origin,
    'user-agent': userAgent,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// Headers of the search requests: the web client's search page as the
  /// Referer (an empty [keyword] for the partition rooms, as in 3.x).
  static Map<String, String> searchHeaders(String keyword, String cookie) => {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'zh-CN,zh;q=0.9',
    'referer': 'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?source=switch_tab&type=live',
    'origin': 'https://www.douyin.com',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  // Streams -------------------------------------------------------------------

  /// The video qualities of `stream_url`, best first (3.x's
  /// `parseStreamQualities`):
  ///
  /// - `stream_data` (`data.{sdk_key}.main`) and the old `flv_pull_url`,
  ///   `hls_pull_url_map` maps are joined by sdk_key, case-insensitively,
  ///   never by position (REG-DOUYIN-004); the id is the lower-case key and
  ///   [LivePlayQuality.data] its URLs;
  /// - audio-only keys (`ao`, or every URL `only_audio=1`) are left out
  ///   (REG-DOUYIN-001);
  /// - known keys rank by tier, others by level, then bitrate
  ///   (REG-DOUYIN-005);
  /// - keys with the same URLs are one quality, the better-ranked
  ///   (REG-DOUYIN-006).
  static List<LivePlayQuality> qualities(Map<String, dynamic>? streamUrl) => [
    for (final variant in _variants(streamUrl).list) variant.quality,
  ];

  /// The lines of [quality] in `stream_url` issued at [issuedAt]: FLV then
  /// HLS as the platform lists them, each with its format, codec, the media
  /// headers of [webRid] and [cookie], its lease and the picture size the
  /// platform declares for the quality ([pictureSize], F.1b). An alias id
  /// plays its quality; an id `stream_url` does not have plays the URLs in
  /// [LivePlayQuality.data] without a size. The quality played is the
  /// applied one.
  static LivePlayUrlResolution resolution(
    Map<String, dynamic>? streamUrl, {
    required LivePlayQuality quality,
    required String webRid,
    required DateTime issuedAt,
    String? cookie,
  }) {
    final variant = _variantFor(_variants(streamUrl), quality.id);
    final lines = variant?.lines ?? [for (final url in _urls(quality.data)) (url: url, format: _formatOf(url))];
    final headers = mediaHeaders(webRid, cookie: cookie);
    final used = <StreamFormat, int>{};
    final result = <LivePlayLine>[];
    for (final line in lines) {
      final index = used[line.format] = (used[line.format] ?? 0) + 1;
      result.add(
        LivePlayLine(
          line.url.toString(),
          headers: headers,
          format: line.format,
          codec: variant?.codec,
          lineId: index == 1 ? line.format.name : '${line.format.name}-$index',
          lease: lease(line.url, issuedAt),
          width: variant?.size?.width,
          height: variant?.size?.height,
        ),
      );
    }
    return LivePlayUrlResolution.lines(result, appliedQualityData: variant?.quality.id ?? quality.id);
  }

  /// The quality of `stream_url` whose id is [id] or has [id] as an alias
  /// (keys with the same URLs); null when there is none.
  static LivePlayQuality? qualityFor(Map<String, dynamic>? streamUrl, Object? id) =>
      _variantFor(_variants(streamUrl), id)?.quality;

  static _Variant? _variantFor(_Variants variants, Object? id) {
    final key = id?.toString().trim().toLowerCase() ?? '';
    final target = variants.aliases[key] ?? key;
    return variants.list.where((variant) => variant.quality.id == target).firstOrNull;
  }

  /// The media request headers 3.x's player sent for Douyin: UA, Origin,
  /// the room's Referer (the site root without a web_rid) and the cookie.
  static Map<String, String> mediaHeaders(String webRid, {String? cookie}) => {
    'user-agent': userAgent,
    'origin': _origin,
    'referer': webRid.trim().isEmpty ? '$_origin/' : '$_origin/${Uri.encodeComponent(webRid.trim())}',
    if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// The lease of a play URL received at [issuedAt]. The expiry is an
  /// absolute time in the query: `expire` (decimal or hex Unix seconds),
  /// `volcTime`, `wsTime + keeptime` (hex) or `t` next to `k`; recorded URLs
  /// expire 7 days after issue. Values outside a day before to 31 days after
  /// issue are not expiries. Renew [leaseLead] (at most a quarter of the
  /// lifetime) before; expiry is not known to cut an established connection.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final expiresAt = _expiry(url.queryParameters, issuedAt);
    if (expiresAt == null) return null;
    final lifetime = expiresAt.difference(issuedAt);
    final lead = lifetime <= Duration.zero
        ? Duration.zero
        : Duration(microseconds: math.min(leaseLead.inMicroseconds, lifetime.inMicroseconds ~/ 4));
    return PlayLease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt);
  }

  static DateTime? _expiry(Map<String, String> query, DateTime issuedAt) {
    DateTime? plausible(int? seconds) {
      if (seconds == null) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      final ok =
          at.isAfter(issuedAt.subtract(const Duration(days: 1))) && at.isBefore(issuedAt.add(const Duration(days: 31)));
      return ok ? at : null;
    }

    DateTime? time(String? raw) {
      final text = raw?.trim() ?? '';
      if (text.isEmpty) return null;
      final decimal = RegExp(r'^\d+$').hasMatch(text) ? plausible(int.tryParse(text)) : null;
      return decimal ??
          (RegExp(r'^[0-9a-fA-F]{1,12}$').hasMatch(text) ? plausible(int.tryParse(text, radix: 16)) : null);
    }

    final direct = time(query['expire']) ?? time(query['volcTime']);
    if (direct != null) return direct;
    final wsTime = int.tryParse(query['wsTime'] ?? '', radix: 16);
    final keep = int.tryParse(query['keeptime'] ?? '', radix: 16);
    if (wsTime != null && keep != null) {
      final at = plausible(wsTime + keep);
      if (at != null) return at;
    }
    return query.containsKey('k') ? time(query['t']) : null;
  }

  static _Variants _variants(Map<String, dynamic>? streamUrl) {
    if (streamUrl == null) return (list: const [], aliases: const {});
    final pull = _map(_map(streamUrl['live_core_sdk_data'])?['pull_data']);
    final options = _map(pull?['options']);
    final streamData = _map(_map(pull?['stream_data'])?['data']) ?? const {};
    final flvMap = _map(streamUrl['flv_pull_url']) ?? const {};
    final hlsMap = _map(streamUrl['hls_pull_url_map']) ?? const {};
    final names = _map(streamUrl['resolution_name']) ?? const {};
    final defaultQuality = _map(options?['default_quality']);
    final defaultKey = (_text(defaultQuality?['sdk_key']) ?? _text(streamUrl['default_resolution']))?.toLowerCase();

    final descriptors = <String, Map<String, dynamic>>{};
    for (final option in _list(options?['qualities'])) {
      final map = _map(option);
      final key = _text(map?['sdk_key'])?.toLowerCase();
      if (map != null && key != null) descriptors.putIfAbsent(key, () => map);
    }
    for (final key in {...streamData.keys, ...flvMap.keys, ...hlsMap.keys}) {
      final text = key.trim().toLowerCase();
      if (text.isNotEmpty) descriptors.putIfAbsent(text, () => const {});
    }

    final ranked = <_Variant>[];
    for (final MapEntry(:key, value: descriptor) in descriptors.entries) {
      final main = _map(_map(_lookup(streamData, key))?['main']);
      final lines = <_Line>[];
      void add(Object? value, StreamFormat format) {
        final uri = Uri.tryParse(_text(value) ?? '');
        if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) return;
        if (lines.any((line) => line.url.toString() == uri.toString())) return;
        lines.add((url: uri, format: format));
      }

      add(main?['flv'], StreamFormat.flv);
      add(main?['hls'], StreamFormat.hls);
      add(_lookup(flvMap, key), StreamFormat.flv);
      add(_lookup(hlsMap, key), StreamFormat.hls);
      if (lines.isEmpty || _audioOnly(key, lines)) continue;

      final sdk = _map(main?['sdk_params']) ?? const {};
      final bitRate = jsonInt(descriptor['v_bit_rate']) ?? jsonInt(sdk['vbitrate']);
      final resolution = _text(descriptor['resolution']) ?? _text(sdk['resolution']);
      final level = jsonInt(descriptor['level']) ?? 0;
      final tier = _tier(key);
      final sort = tier > 0
          ? tier
          : level > 0
          ? level * 1000000
          : bitRate ?? 0;
      ranked.add((
        quality: LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: _text(descriptor['name']) ?? _text(_lookup(names, key)) ?? key,
            id: key,
            bitrate: bitRate,
            resolution: resolution,
          ),
          id: key,
          sort: sort,
          data: List<String>.unmodifiable([for (final line in lines) line.url.toString()]),
        ),
        lines: lines,
        codec: _codec(sdk['VCodec']) ?? _codec(descriptor['v_codec']),
        size: pictureSize(
          main: main,
          descriptor: descriptor,
          defaultQuality: key == defaultKey ? defaultQuality : null,
        ),
      ));
    }
    ranked.sort((a, b) {
      final bySort = b.quality.sort.compareTo(a.quality.sort);
      return bySort != 0 ? bySort : '${a.quality.id}'.compareTo('${b.quality.id}');
    });

    final kept = <_Variant>[];
    final aliases = <String, String>{};
    final bySet = <String, int>{};
    for (final variant in ranked) {
      final set = ([for (final line in variant.lines) line.url.toString()]..sort()).join('\u0000');
      final survivor = bySet[set];
      if (survivor != null) {
        final target = kept[survivor];
        aliases['${variant.quality.id}'] = '${target.quality.id}';
        // Same stream: the survivor takes a codec or a size only the alias
        // reports.
        if ((target.codec == null && variant.codec != null) || (target.size == null && variant.size != null)) {
          kept[survivor] = (
            quality: target.quality,
            lines: target.lines,
            codec: target.codec ?? variant.codec,
            size: target.size ?? variant.size,
          );
        }
        continue;
      }
      bySet[set] = kept.length;
      kept.add(variant);
    }
    return (list: kept, aliases: aliases);
  }

  /// The picture size the platform declares for one quality (3.x
  /// `LiveStreamGeometryHintResolver.resolveDouyin` for the selected URL):
  /// `main.width`/`height`, then `sdk_params.width`/`height`, then
  /// `sdk_params.resolution`, then the quality's `options.qualities[]`
  /// `resolution`, then `default_quality.resolution` when [defaultQuality] is
  /// given (the quality is the default one). A size outside 120–16384 or a
  /// ratio outside 0.30–3.50 does not count. `stream_orientation` and the
  /// top-level `extra.width`/`height` (also on square audio placeholders)
  /// are never read, as in 3.x.
  @visibleForTesting
  static ({int width, int height})? pictureSize({
    Map<String, dynamic>? main,
    Map<String, dynamic> descriptor = const {},
    Map<String, dynamic>? defaultQuality,
  }) {
    final sdk = _map(main?['sdk_params']);
    return _declaredSize(main) ??
        _declaredSize(sdk) ??
        _resolutionSize(sdk?['resolution']) ??
        _resolutionSize(descriptor['resolution']) ??
        _resolutionSize(defaultQuality?['resolution']);
  }

  static ({int width, int height})? _declaredSize(Map<String, dynamic>? map) =>
      map == null ? null : _plausibleSize(jsonInt(_lookup(map, 'width')), jsonInt(_lookup(map, 'height')));

  static ({int width, int height})? _resolutionSize(Object? value) {
    final match = RegExp(r'(\d{2,5})\s*[xX×*]\s*(\d{2,5})').firstMatch(_text(value) ?? '');
    if (match == null) return null;
    return _plausibleSize(int.tryParse(match[1]!), int.tryParse(match[2]!));
  }

  static ({int width, int height})? _plausibleSize(int? width, int? height) {
    if (width == null || height == null || width < 120 || height < 120 || width > 16384 || height > 16384) {
      return null;
    }
    final ratio = width / height;
    return ratio < 0.30 || ratio > 3.50 ? null : (width: width, height: height);
  }

  static bool _audioOnly(String key, List<_Line> lines) {
    final token = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
    if (const {'ao', 'audio', 'audioonly'}.contains(token)) return true;
    return lines.every((line) {
      final value = line.url.queryParameters['only_audio']?.toLowerCase();
      return value == '1' || value == 'true';
    });
  }

  /// 3.x's rank of the known sdk keys.
  static int _tier(String key) => switch (key.toUpperCase()) {
    'ORIGION' || 'ORIGIN' => 6000000,
    'FULL_HD1' || 'UHD' => 5000000,
    'HD1' || 'HD' => 4000000,
    'SD2' || 'SD' => 3000000,
    'SD1' || 'LD' => 2000000,
    'MD' => 1000000,
    _ => 0,
  };

  /// `sdk_params.VCodec` (`h264`, `h265`) or `options.qualities[].v_codec`
  /// (`264`, `bytevc1` = ByteDance's HEVC).
  static String? _codec(Object? value) => switch (_text(value)?.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '')) {
    'h264' || '264' || 'avc' || 'avc1' => 'avc',
    'h265' || '265' || 'hevc' || 'hev1' || 'hvc1' || 'bytevc1' => 'hevc',
    _ => null,
  };

  static List<Uri> _urls(Object? data) => [
    if (data is List)
      for (final value in data)
        if (Uri.tryParse('$value'.trim()) case final uri?
            when (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty)
          uri,
  ];

  static StreamFormat _formatOf(Uri url) =>
      url.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;

  // Audience --------------------------------------------------------------------

  /// 3.x's audience fields with REG-DOUYIN-008 fixed. `room_view_stats.
  /// display_value` is what Douyin shows for the room: the online count when
  /// `display_type` is 1 ("713在线观众", then the room has no cumulative
  /// count) and the cumulative count when it is 3 ("3055.0万人看过") or
  /// absent; 3.x called it cumulative either way, so a card keeps its number
  /// and only its meaning is corrected. Exact integers beat bucketed text
  /// (`user_count_str: "2000+"` against `stats.user_count_str: "2665"`); a
  /// cumulative 0 is a placeholder. The cumulative count leads, as in 3.x.
  static ({String watching, String online, String total, AudienceMetricType metric}) _audience(
    Map<String, dynamic> room,
  ) {
    final online = _online(room);
    final total = _total(room);
    return (
      watching: total.ifEmpty(() => online),
      online: online,
      total: total,
      metric: total.isNotEmpty ? AudienceMetricType.totalViewers : AudienceMetricType.onlineViewers,
    );
  }

  static String _online(Map<String, dynamic> room) {
    final view = _map(room['room_view_stats']) ?? const {};
    final stats = _map(room['stats']) ?? const {};
    return _count(allowZero: true, [
      room['user_count'],
      room['user_count_str'],
      room['online_user_count'],
      room['online_user_for_anchor'],
      if (jsonInt(view['display_type']) == 1) view['display_value'],
      view['user_count'],
      view['online_user_count'],
      view['online_user_for_anchor'],
      stats['user_count'],
      stats['online_user_count'],
      stats['online_user_for_anchor'],
      stats['user_count_str'],
    ]);
  }

  static String _total(Map<String, dynamic> room) {
    final view = _map(room['room_view_stats']) ?? const {};
    final stats = _map(room['stats']) ?? const {};
    final type = jsonInt(view['display_type']);
    // Douyin shows such a room by its online count; its cumulative fields
    // are a 0 placeholder and bucketed text ("10万+").
    if (type == 1) return '';
    return _count(allowZero: false, [
      if (type == null || type == 3) view['display_value'],
      view['total_user_str'],
      view['total_user'],
      stats['total_user_str'],
      stats['total_user'],
      room['total_user_str'],
      room['total_user'],
    ]);
  }

  /// The first exact integer among [candidates], else the first text with a
  /// count (as written); zero only with [allowZero].
  static String _count(List<Object?> candidates, {required bool allowZero}) {
    for (final candidate in candidates) {
      final value = candidate is bool ? null : jsonInt(candidate);
      if (value != null && (allowZero ? value >= 0 : value > 0)) return '$value';
    }
    for (final candidate in candidates) {
      final text = candidate is String ? candidate.trim() : '';
      if (text.isEmpty || !RegExp('[0-9]').hasMatch(text)) continue;
      if (allowZero || parseAudienceNumber(text) > 0) return text;
    }
    return '';
  }

  // Helpers -------------------------------------------------------------------

  static bool _looksLikeRoom(Map<String, dynamic> value) =>
      value['owner'] is Map || value['title'] != null || value['id_str'] != null || value['stream_url'] is Map;

  /// `tag_name`, else the first title of `partition_road_map` or `tags`.
  static String? _feedArea(Map<String, dynamic> envelope, Map<String, dynamic> room) {
    final direct = _firstText([room['tag_name'], envelope['tag_name']]);
    if (direct != null) return direct;
    for (final source in [room['partition_road_map'], envelope['tags']]) {
      for (final tag in _list(source)) {
        final map = _map(tag);
        final text = map == null ? null : _firstText([map['title'], map['name'], map['tag_name']]);
        if (text != null) return text;
      }
    }
    return null;
  }

  static ({String id, String name})? _partition(Object? raw) {
    final map = _map(raw);
    final id = _text(map?['id_str']);
    final type = _text(map?['type']);
    if (id == null || type == null) return null;
    return (id: '$id,$type', name: _text(map?['title']) ?? '');
  }

  /// A web_rid: a string or integer of digits.
  static String? _webRid(Object? value) {
    if (value is! String && value is! int) return null;
    final text = '$value'.trim();
    return RegExp(r'^\d+$').hasMatch(text) ? text : null;
  }

  /// The first image URL: the first entry of `url_list`, or a direct http(s)
  /// URL, made absolute.
  static String _firstImage(List<Object?> candidates) {
    for (final value in candidates) {
      final list = _map(value)?['url_list'];
      if (list is List) {
        final url = _firstText(list);
        if (url != null) return normalizeImageUrl(url);
      }
      final direct = _text(value);
      if (direct != null && (direct.startsWith('http://') || direct.startsWith('https://'))) return direct;
    }
    return '';
  }

  /// The React Server Component rows of a page by id: `id:<json>` lines and
  /// `id:T<hex byte length>,<text>` text rows, from its `self.__pace_f.push`
  /// chunks.
  static Map<String, _Row> _flightRows(String html) {
    final flight = StringBuffer();
    for (final match in RegExp(r'self\.__pace_f\.push\(\[1,"').allMatches(html)) {
      final start = match.end - 1;
      var index = start + 1;
      while (index < html.length) {
        final unit = html.codeUnitAt(index);
        if (unit == 0x5C) {
          index += 2;
        } else if (unit == 0x22) {
          break;
        } else {
          index++;
        }
      }
      if (index >= html.length) break;
      try {
        final chunk = jsonDecode(html.substring(start, index + 1));
        if (chunk is String) flight.write(chunk);
      } on FormatException {
        throw const ApiChanged(_site, 'page: undecodable __pace_f chunk');
      }
    }
    final bytes = utf8.encode(flight.toString());
    final rows = <String, _Row>{};
    var position = 0;
    while (position < bytes.length) {
      final colon = bytes.indexOf(0x3A, position);
      if (colon < 0) break;
      final id = latin1.decode(bytes.sublist(position, colon)).trim();
      if (colon + 1 < bytes.length && bytes[colon + 1] == 0x54) {
        final comma = bytes.indexOf(0x2C, colon + 2);
        final size = comma < 0 ? null : int.tryParse(latin1.decode(bytes.sublist(colon + 2, comma)), radix: 16);
        if (size == null) break;
        final end = math.min(comma + 1 + size, bytes.length);
        rows[id] = (text: true, value: utf8.decode(bytes.sublist(comma + 1, end), allowMalformed: true));
        position = end;
      } else {
        var end = bytes.indexOf(0x0A, colon + 1);
        if (end < 0) end = bytes.length;
        rows[id] = (text: false, value: utf8.decode(bytes.sublist(colon + 1, end), allowMalformed: true));
        position = end + 1;
      }
    }
    return rows;
  }

  /// The first object in the page's JSON rows that has [key] and satisfies
  /// [where] (pages also carry empty initial stores).
  static Map<String, dynamic>? _flightObject(
    Map<String, _Row> rows,
    String key, {
    bool Function(Map<String, dynamic> object)? where,
  }) {
    for (final row in rows.values) {
      if (row.text || !row.value.contains('"$key"')) continue;
      if (!row.value.startsWith('[') && !row.value.startsWith('{')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(row.value);
      } on FormatException {
        continue;
      }
      final found = _findKey(decoded, key, where ?? (_) => true);
      if (found != null) return found;
    }
    return null;
  }

  static Map<String, dynamic>? _findKey(Object? node, String key, bool Function(Map<String, dynamic>) where) {
    if (node is Map<String, dynamic>) {
      if (node.containsKey(key) && where(node)) return node;
      for (final value in node.values) {
        final found = _findKey(value, key, where);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findKey(value, key, where);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Decodes the payload's string encodings: `$$x` is `$x`, `$undefined` is
  /// null and `$<hex id>` is that row (a text row as a string).
  static Object? _resolve(Object? node, Map<String, _Row> rows, [int hops = 0]) {
    if (node is String) {
      if (!node.startsWith(r'$')) return node;
      if (node.startsWith(r'$$')) return node.substring(1);
      if (node == r'$undefined') return null;
      final match = RegExp(r'^\$([0-9a-fA-F]+)$').firstMatch(node);
      final row = match == null ? null : rows[match.group(1)];
      if (row == null || hops > 8) return node;
      if (row.text) return row.value;
      try {
        return _resolve(jsonDecode(row.value), rows, hops + 1);
      } on FormatException {
        return node;
      }
    }
    if (node is Map<String, dynamic>) return node.map((key, value) => MapEntry(key, _resolve(value, rows, hops)));
    if (node is List) return [for (final value in node) _resolve(value, rows, hops)];
    return node;
  }

  /// The JSON documents of a body; the general search frames them as
  /// `<hex byte length>\r\n<document>\r\n` chunks ending with `0\r\n\r\n`.
  static List<String> _chunks(String body) {
    if (!RegExp(r'^[0-9a-fA-F]+\r?\n').hasMatch(body)) return [body];
    final bytes = utf8.encode(body);
    final documents = <String>[];
    var position = 0;
    while (position < bytes.length) {
      final end = bytes.indexOf(0x0A, position);
      if (end < 0) break;
      final size = int.tryParse(latin1.decode(bytes.sublist(position, end)).trim().split(';').first, radix: 16);
      if (size == null) throw const ApiChanged(_site, 'search: bad chunk header');
      if (size == 0) break;
      final start = end + 1;
      if (start + size > bytes.length) throw const ApiChanged(_site, 'search: truncated chunk');
      documents.add(utf8.decode(bytes.sublist(start, start + size), allowMalformed: true));
      position = start + size;
      if (position < bytes.length && bytes[position] == 0x0D) position++;
      if (position < bytes.length && bytes[position] == 0x0A) position++;
    }
    if (documents.isEmpty) throw const ApiChanged(_site, 'search: no chunk');
    return documents;
  }

  /// HTTP-level failures before the body is read: a captcha
  /// (`bdturing-verify`), 429, 5xx, 401/403 and an empty 200 (no ttwid, a
  /// rejected signature) are risk, throttling or the network; any other
  /// non-2xx is `ApiChanged`.
  static void _checkHttp(String body, int status, Map<String, List<String>> headers, String what) {
    String? header(String name) {
      for (final MapEntry(:key, :value) in headers.entries) {
        if (key.toLowerCase() == name && value.isNotEmpty) return value.first;
      }
      return null;
    }

    if (header('bdturing-verify') != null || header('x-vc-bdturing-parameters') != null) {
      throw RiskControl(_site, detail: '$what: captcha (bdturing-verify)');
    }
    if (status == 429) {
      final seconds = int.tryParse(header('retry-after')?.trim() ?? '');
      throw RateLimited(
        _site,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
        detail: '$what: 429',
      );
    }
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what: HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status');
    if (body.trim().isEmpty) throw RiskControl(_site, detail: '$what: empty body (no ttwid, signature or captcha)');
  }

  /// A JSON API answer: [_checkHttp], then `status_code`: 4001038 (no such
  /// web_rid) is `NotFound`, 2483 and 20003 (not signed in) `NeedsLogin`,
  /// any other non-zero code `ApiChanged`. A body that is not JSON is a
  /// challenge page: `RiskControl`.
  static Map<String, dynamic> _checked(String body, int status, Map<String, List<String>> headers, String what) {
    _checkHttp(body, status, headers, what);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw RiskControl(_site, detail: '$what: not JSON (${_snippet(body)})');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
    final code = jsonInt(decoded['status_code']);
    if (code == null || code == 0) return decoded;
    final data = _map(decoded['data']);
    final message = _firstText([decoded['status_msg'], data?['prompts'], data?['message']]) ?? '';
    final detail = '$what: status_code $code $message'.trim();
    throw switch (code) {
      4001038 => NotFound(_site, detail),
      2483 || 20003 => NeedsLogin(_site, detail),
      _ => ApiChanged(_site, detail),
    };
  }
}

typedef _Row = ({bool text, String value});
typedef _Line = ({Uri url, StreamFormat format});
typedef _Variant = ({LivePlayQuality quality, List<_Line> lines, String? codec, ({int width, int height})? size});
typedef _Variants = ({List<_Variant> list, Map<String, String> aliases});

/// An object from a map or a JSON-encoded object string.
Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, entry) => MapEntry('$key', entry));
  if (value is String && value.trimLeft().startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
  return null;
}

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

Object? _lookup(Map<String, dynamic> map, String key) {
  final direct = map[key];
  if (direct != null) return direct;
  for (final entry in map.entries) {
    if (entry.key.toLowerCase() == key) return entry.value;
  }
  return null;
}

/// A trimmed non-empty text that is not a map, a list or `null`.
String? _text(Object? value) {
  if (value == null || value is Map || value is Iterable) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text != null) return text;
  }
  return null;
}

/// The first value usable as a room id (not `0` or another placeholder).
String? _firstId(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text != null && !const {'0', 'undefined', 'nan', 'none'}.contains(text.toLowerCase())) return text;
  }
  return null;
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}
