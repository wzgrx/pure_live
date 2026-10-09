import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_message.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'bilibili';

/// State of a QR login poll. Every state is a step of the flow, not a
/// failure.
enum BilibiliQrState {
  /// 86101: not scanned yet.
  waiting,

  /// 86090: scanned, waiting for the user to confirm on the phone.
  scanned,

  /// 86038: the code expired; generate a new one.
  expired,

  /// 0: confirmed; the login cookie is in the response's `Set-Cookie`.
  confirmed,
}

/// What the danmaku connection needs to join one room: the auth packet's
/// room id, uid, token and buvid, the endpoints in the order to try, and the
/// WebSocket headers of the cookie the token was issued to.
@immutable
final class BilibiliDanmakuArgs {
  /// Creates the arguments.
  const new({
    required this.roomId,
    required this.uid,
    required this.token,
    required this.servers,
    required this.buvid,
    required this.headers,
    this.refresh,
    this.giftCatalog,
  });

  /// Long room id.
  final int roomId;

  /// 0 for a guest; the logged-in user's uid from the same cookie.
  final int uid;

  /// Auth token; empty when discovery failed on room entry.
  final String token;

  /// The general gateway first, then the regional `host_list` nodes.
  final List<Uri> servers;

  /// buvid3 of the cookie.
  final String buvid;

  /// UA, Origin, Referer (long id) and the cookie.
  final Map<String, String> headers;

  /// Fetches fresh credentials with the full retry schedule (after an auth
  /// rejection, or when room entry had to go on without a token).
  final Future<BilibiliDanmakuArgs> Function()? refresh;

  /// The platform's gift table ([BilibiliGiftCatalog], D07.4), for the
  /// gifts whose packet has no picture or price; the site keeps it for
  /// every room. Null in tests and when there is none.
  final Future<BilibiliGiftCatalog> Function()? giftCatalog;
}

/// One gift of [BilibiliGiftCatalog] (`giftPanel/giftConfig`'s
/// `data.list[]`): `id`, `name`, `price` (in gold seeds, or silver seeds
/// when [silver]: `coin_type` `silver`, which the gift line counts as free)
/// and the picture `img_basic` (https).
@immutable
final class BilibiliGiftInfo {
  /// Creates the entry.
  const new({required this.id, required this.name, this.price = 0, this.silver = false, this.icon});

  /// The gift's id (`id`).
  final String id;

  /// The gift's name (`name`).
  final String name;

  /// The price of one (`price`), in gold seeds, or silver seeds when
  /// [silver]; 0 when missing.
  final int price;

  /// Whether it costs silver seeds (`coin_type` `silver`).
  final bool silver;

  /// The picture (`img_basic`), https.
  final Uri? icon;

  @override
  bool operator ==(Object other) =>
      other is BilibiliGiftInfo &&
      other.id == id &&
      other.name == name &&
      other.price == price &&
      other.silver == silver &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, price, silver, icon);

  @override
  String toString() => 'BilibiliGiftInfo($id $name, $price ${silver ? 'silver' : 'gold'})';
}

/// Bilibili's gift table (D07.4): `xlive/web-room/v1/giftPanel/giftConfig`,
/// public and anonymous, the same for every room (about 900 gifts,
/// 1.5 MB). The danmaku connection reads a gift's picture and price here
/// when the packet has none ([gifts] by id), and the guard pictures
/// ([guards], `guard_resources[]`: `level` 1 总督, 2 提督, 3 舰长).
@immutable
final class BilibiliGiftCatalog {
  /// Creates the table.
  const new({this.gifts = const {}, this.guards = const {}});

  /// No table (not fetched yet, or the fetch failed).
  static const BilibiliGiftCatalog empty = BilibiliGiftCatalog();

  /// The gifts by id.
  final Map<String, BilibiliGiftInfo> gifts;

  /// The guard levels' names and pictures by `level`.
  final Map<int, ({String name, Uri? icon})> guards;

  /// Whether it holds nothing.
  bool get isEmpty => gifts.isEmpty && guards.isEmpty;

  /// The gift [id], or null.
  BilibiliGiftInfo? operator [](String id) => gifts[id];
}

/// Pure parsing of Bilibili responses (3.x's `BiliBiliSite`, with the
/// archived v4 parser's fixes). Each function takes the response text and
/// status and returns 3.x's models or throws a `SiteError`.
abstract final class BilibiliApi {
  /// Desktop Chrome 138, the UA 3.x sent with every Bilibili request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/138.0.0.0 Safari/537.36';

  /// Referer of API requests.
  static const String referer = 'https://live.bilibili.com/';

  /// The general danmaku gateway, tried first: some ISP and mobile DNS
  /// resolvers intermittently miss the regional nodes.
  static const String danmakuGateway = 'wss://broadcastlv.chat.bilibili.com/sub';

  /// How long before `expires` a play URL is renewed (at most a quarter of
  /// its lifetime).
  static const Duration leaseLead = Duration(seconds: 60);

  // Catalog -------------------------------------------------------------------

  /// `room/v1/Area/getList`: categories and their areas in platform order.
  /// Area pictures get the `@100w.png` size hint.
  static List<LiveCategory> categories(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'Area/getList');
    final data = root['data'];
    if (data is! List) throw ApiChanged(_site, 'Area/getList: data is not a list (${_snippet(body)})');
    return [
      for (final raw in data)
        if (_object(raw) case final category? when jsonString(category['id']) != null)
          LiveCategory(
            id: jsonString(category['id'])!,
            name: decodeHtmlEntities(jsonString(category['name']) ?? ''),
            children: [
              for (final rawArea in _list(category['list']))
                if (_object(rawArea) case final area? when jsonString(area['id']) != null)
                  LiveArea(
                    platform: _site,
                    areaId: jsonString(area['id'])!,
                    areaName: decodeHtmlEntities(jsonString(area['name']) ?? ''),
                    areaType: jsonString(area['parent_id']) ?? jsonString(category['id'])!,
                    typeName: decodeHtmlEntities(jsonString(area['parent_name']) ?? jsonString(category['name']) ?? ''),
                    areaPic: _image(area['pic'], '@100w.png'),
                  ),
            ],
          ),
    ];
  }

  /// `area/getRoomList` (area rooms, list in `data`), `second/getList` (its
  /// signed fallback), `getListByAreaID` (ranked recommendations, list in
  /// `data`) and `getMoreRecList` (the fallback feed, list in
  /// `data.recommend_room_list`). Every room is live; the page
  /// is sorted by popularity with identity ties, because neither list is
  /// reliably ordered. The page ends when `has_more` says so, else when it
  /// is empty.
  static ({List<LiveRoom> rooms, bool hasMore}) roomList(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'room list');
    final data = root['data'];
    final raw = data is Map<String, dynamic> ? (data['list'] ?? data['recommend_room_list']) : data;
    if (raw is! List) throw ApiChanged(_site, 'room list: no list (${_snippet(body)})');
    final rooms = sortByPopularity([
      for (final item in raw)
        if (_object(item) case final room?) ?_listRoom(room),
    ]);
    final flag = data is Map<String, dynamic> ? data['has_more'] : null;
    final more = switch (flag) {
      final bool value => value,
      _ => jsonInt(flag) == null ? raw.isNotEmpty : jsonInt(flag) != 0,
    };
    return (rooms: rooms, hasMore: raw.isNotEmpty && more);
  }

  /// Rooms sorted by popularity, highest first, then by identity, so equal
  /// values never shuffle on refresh.
  static List<LiveRoom> sortByPopularity(Iterable<LiveRoom> rooms) => rooms.toList()
    ..sort(
      (left, right) =>
          LiveRoom.compareAudienceRanking(left, right, preferRealOnline: false, platformEnabled: (_) => false),
    );

  static LiveRoom? _listRoom(Map<String, dynamic> item) {
    final id = _roomId(item['roomid'] ?? item['room_id']);
    if (id == null) return null;
    final online = jsonString(item['online']) ?? '';
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: decodeHtmlEntities(jsonString(item['title']) ?? ''),
      nick: decodeHtmlEntities(jsonString(item['uname']) ?? ''),
      avatar: _image(item['face']),
      cover: _image(item['cover'], '@400w.jpg').ifEmpty(() => _image(item['user_cover'], '@400w.jpg')),
      area: jsonString(item['area_v2_name']) ?? jsonString(item['area_name']) ?? jsonString(item['areaName']) ?? '',
      watching: online,
      popularity: online,
      totalViewers: _watched(item['watched_show'], live: true),
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.live,
    );
  }

  // Search --------------------------------------------------------------------

  /// `search/type?search_type=live`: `live_room` entries are live rooms;
  /// `live_user` entries are streamers whose name matched, the only place
  /// offline and carousel streamers appear (3.x ignored them). Those become
  /// cards after the rooms, on page 1 only (every page repeats them), without
  /// title, cover or audience, and only when their room is not listed yet.
  /// `live_status` is read as in [roomDetail]; a live entry's `live_time`
  /// (Beijing time) is its start. `cate_name` is highlighted like the title
  /// when the keyword names the area (`<em class="keyword">英雄联盟</em>`).
  static List<LiveRoom> searchRooms(String body, {required int page, int status = 200}) {
    final root = _checked(body, status: status, what: 'search');
    final result = _object(_object(root['data'])?['result']);
    final rooms = <LiveRoom>[
      for (final item in _list(result?['live_room']))
        if (_object(item) case final room?) ?_searchRoom(room),
    ];
    if (page <= 1) {
      final listed = {for (final room in rooms) room.roomId};
      for (final item in _list(result?['live_user'])) {
        final user = _object(item) == null ? null : _searchUser(_object(item)!);
        if (user != null && listed.add(user.roomId)) rooms.add(user);
      }
    }
    return rooms;
  }

  static LiveRoom? _searchRoom(Map<String, dynamic> item) {
    final id = _roomId(item['roomid']);
    if (id == null) return null;
    final state = _status(item['live_status']);
    final live = state == LiveStatus.live;
    final online = jsonString(item['online']) ?? '';
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _highlighted(item['title']),
      nick: _highlighted(item['uname']),
      avatar: _image(item['uface'], '@400w.jpg'),
      // `cover` is a keyframe screenshot; the room cover (what 3.x asked for
      // with cover_type=user_cover) is `user_cover`.
      cover: _image(item['user_cover'], '@400w.jpg').ifEmpty(() => _image(item['cover'], '@400w.jpg')),
      area: _highlighted(item['cate_name']),
      watching: online,
      popularity: online,
      totalViewers: _watched(item['watched_show'], live: live),
      followers: jsonString(item['attentions']) ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: state,
      startedAt: live ? _beijingTime(item['live_time']) : null,
    );
  }

  static LiveRoom? _searchUser(Map<String, dynamic> item) {
    final id = _roomId(item['roomid']);
    if (id == null) return null;
    final state = _status(item['live_status']);
    return LiveRoom(
      roomId: id,
      platform: _site,
      nick: _highlighted(item['uname']),
      avatar: _image(item['uface'], '@400w.jpg'),
      area: _highlighted(item['cate_name']),
      watching: '',
      followers: jsonString(item['attentions']) ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: state,
      startedAt: state == LiveStatus.live ? _beijingTime(item['live_time']) : null,
    );
  }

  /// `search/type?search_type=live_user`: streamers.
  static List<LiveAnchorItem> searchAnchors(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'search live_user');
    return [
      for (final item in _list(_object(root['data'])?['result']))
        if (_object(item) case final user? when _roomId(user['roomid']) != null)
          LiveAnchorItem(
            roomId: _roomId(user['roomid'])!,
            avatar: _image(user['uface'], '@400w.jpg'),
            userName: _highlighted(user['uname']),
            liveStatus: user['is_live'] == true || jsonInt(user['is_live']) == 1,
          ),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// `getInfoByRoom` (WBI signed): the room as the user asked for it
  /// ([requestedId], which may be a short id: the identity of a follow must
  /// not change) and the canonical long id used for streams and danmaku.
  ///
  /// `live_status` 1 (number or string) is live, 2 is the carousel (old
  /// videos looping while the streamer is off; 3.x showed it as offline) and
  /// anything else is offline. A live room's `live_start_time` (Unix seconds)
  /// is its start; `special_type` gives the restriction. Codes -404,
  /// 19002000 and 60004 are `NotFound`. The description's HTML becomes plain
  /// text.
  static ({LiveRoom room, String longId}) roomDetail(String body, {required String requestedId, int status = 200}) {
    final root = _checked(body, status: status, what: 'getInfoByRoom', notFound: const {-404, 19002000, 60004});
    final data = _object(root['data']);
    final room = _object(data?['room_info']);
    final anchor = _object(data?['anchor_info']);
    if (data == null || room == null || anchor == null) {
      throw ApiChanged(_site, 'getInfoByRoom: room_info or anchor_info missing (${_snippet(body)})');
    }
    final longId = _roomId(room['room_id']);
    if (longId == null) throw const ApiChanged(_site, 'getInfoByRoom: room_info.room_id missing');
    final state = _status(room['live_status']);
    final live = state == LiveStatus.live;
    final base = _object(anchor['base_info']);
    final online = jsonString(room['online']) ?? '';
    final notice = jsonString(_object(data['news_info'])?['content']);
    final id = requestedId.trim();
    return (
      longId: longId,
      room: LiveRoom(
        roomId: id,
        platform: _site,
        title: decodeHtmlEntities(jsonString(room['title']) ?? ''),
        nick: decodeHtmlEntities(jsonString(base?['uname']) ?? ''),
        avatar: _image(base?['face'], '@100w.jpg'),
        cover: _image(room['cover']),
        area: jsonString(room['area_name']) ?? '',
        watching: online,
        popularity: online,
        totalViewers: _watched(data['watched_show'], live: live),
        audienceMetricType: AudienceMetricType.popularity,
        liveStatus: state,
        startedAt: live ? _unixTime(room['live_start_time']) : null,
        restriction: _restriction(room['special_type'], live: live),
        link: 'https://live.bilibili.com/$id',
        introduction: _richText(room['description']) ?? '',
        notice: notice == null ? '' : decodeHtmlEntities(notice),
      ),
    );
  }

  /// `room/v1/Room/get_info`: whether the room is live.
  static bool liveStatus(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'Room/get_info');
    return _isLive(_object(root['data'])?['live_status']);
  }

  /// `SuperChat/getMessageList`: super chats with their display window.
  static List<LiveSuperChatMessage> superChats(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'SuperChat/getMessageList');
    DateTime? time(Object? seconds) => switch (jsonInt(seconds)) {
      final int value when value > 0 => DateTime.fromMillisecondsSinceEpoch(value * 1000),
      _ => null,
    };
    return [
      for (final item in _list(_object(root['data'])?['list']))
        if (_object(item) case final chat?)
          if ((time(chat['start_time']), time(chat['end_time'])) case (final start?, final end?))
            LiveSuperChatMessage(
              messageId: jsonString(chat['id']) ?? '',
              userName: jsonString(_object(chat['user_info'])?['uname']) ?? '',
              face: _image(_object(chat['user_info'])?['face'], '@200w.jpg'),
              message: jsonString(chat['message']) ?? '',
              price: jsonInt(chat['price']) ?? 0,
              startTime: start,
              endTime: end,
              backgroundColor: jsonString(chat['background_color']) ?? '',
              backgroundBottomColor: jsonString(chat['background_bottom_color']) ?? '',
            ),
    ];
  }

  // Gifts ---------------------------------------------------------------------

  /// The gift table ([BilibiliGiftCatalog], D07.4): public, anonymous and
  /// the same for every room (no room id).
  static final Uri giftConfigUrl = Uri.https('api.live.bilibili.com', '/xlive/web-room/v1/giftPanel/giftConfig', {
    'platform': 'pc',
  });

  /// `giftPanel/giftConfig`: `data.list[]` by `id` (an entry without an id
  /// or a name is left out) and `data.guard_resources[]` by `level`.
  static BilibiliGiftCatalog giftCatalog(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'giftPanel/giftConfig')['data']);
    if (data == null) throw ApiChanged(_site, 'giftPanel/giftConfig: no data (${_snippet(body)})');
    final gifts = <String, BilibiliGiftInfo>{};
    for (final raw in _list(data['list'])) {
      final gift = _object(raw);
      final id = jsonString(gift?['id']) ?? '';
      final name = jsonString(gift?['name'])?.trim() ?? '';
      if (gift == null || id.isEmpty || id == '0' || name.isEmpty) continue;
      final price = jsonInt(gift['price']) ?? 0;
      gifts[id] = BilibiliGiftInfo(
        id: id,
        name: name,
        price: price > 0 ? price : 0,
        silver: gift['coin_type'] == 'silver',
        icon: giftIcon(gift['img_basic']),
      );
    }
    final guards = <int, ({String name, Uri? icon})>{
      for (final raw in _list(data['guard_resources']))
        if (_object(raw) case final guard? when (jsonInt(guard['level']) ?? 0) > 0)
          jsonInt(guard['level'])!: (name: jsonString(guard['name'])?.trim() ?? '', icon: giftIcon(guard['img'])),
    };
    return BilibiliGiftCatalog(gifts: gifts, guards: guards);
  }

  /// A gift's picture: a web address ([normalizeImageUrl]), `hdslb.com`'s
  /// made https; null when there is none.
  static Uri? giftIcon(Object? value) {
    final url = normalizeImageUrl(value);
    final uri = url.isEmpty ? null : Uri.tryParse(url);
    if (uri == null) return null;
    final bilibili = uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com');
    return bilibili && uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
  }

  /// The name of guard `level` (`guard_level`): 1 总督, 2 提督, 3 舰长; empty
  /// for any other.
  static String guardName(int level) => switch (level) {
    1 => '总督',
    2 => '提督',
    3 => '舰长',
    _ => '',
  };

  // Streams -------------------------------------------------------------------

  /// `getRoomPlayInfo` → its `data`, whatever the room's state: a carousel
  /// that comes with a stream (possibly for a signed-in user) is played. A
  /// `playurl_info` of null (offline, a carousel for guests, a paid broadcast
  /// without a ticket) is `StreamUnavailable` naming the state; one without
  /// `playurl` is `ApiChanged`. A paid broadcast has 1 in
  /// `all_special_types` (what the web player checks before asking for a
  /// ticket).
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'getRoomPlayInfo');
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'getRoomPlayInfo: no data (${_snippet(body)})');
    if (data['playurl_info'] == null) {
      final paid = _list(data['all_special_types']).any((type) => jsonInt(type) == 1);
      final state = switch (_status(data['live_status'])) {
        LiveStatus.live when paid => 'paid broadcast without a ticket',
        LiveStatus.live => 'live without a stream for this client',
        LiveStatus.carousel => 'carousel without a stream for this client',
        _ => 'offline',
      };
      throw StreamUnavailable(_site, 'getRoomPlayInfo: $state (live_status ${data['live_status']})');
    }
    _playurl(data);
    return data;
  }

  /// Whether a `getRoomPlayInfo` answer is a carousel (`live_status` 2)
  /// without a stream for this client (guests): its video is then played
  /// from `getRoundPlayVideo` (1-1, [roundPlayVideo]). Anything that does
  /// not read as such an answer is false, and [playData] explains it.
  static bool carouselWithoutStream(String body, {int status = 200}) {
    try {
      final data = _object(_checked(body, status: status, what: 'getRoomPlayInfo')['data']);
      return data != null && data['playurl_info'] == null && _status(data['live_status']) == LiveStatus.carousel;
    } on SiteError {
      return false;
    }
  }

  /// The one quality of a carousel played from its video (1-1): the video's
  /// own tiers are not offered (a guest gets 480P at most).
  static const LivePlayQuality carouselQuality = LivePlayQuality(
    quality: '轮播',
    id: carouselQualityId,
    data: carouselQualityId,
  );

  /// The id and data of [carouselQuality].
  static const String carouselQualityId = 'carousel';

  /// `live/getRoundPlayVideo?room_id=` of the long [roomId]: the video the
  /// room's carousel is playing (works for guests, M4.01).
  static Uri roundPlayVideoUrl(String roomId) =>
      Uri.https('api.live.bilibili.com', '/live/getRoundPlayVideo', {'room_id': roomId});

  static final RegExp _bvid = RegExp(r'^BV[0-9A-Za-z]{10}$');

  /// The video a carousel is playing (`getRoundPlayVideo`'s `data`): its
  /// `bvid`, part `cid` and `play_time`, the seconds already played, where
  /// playback starts (M7.1; M4.01 notes). The answer's own `play_url` is
  /// dead (it redirects to an error page) and is not read. No `bvid` or no
  /// positive `cid` (nothing in rotation, or the room went live) is
  /// `StreamUnavailable`; a `play_time` that does not read as seconds
  /// (negative, not a number) starts at the beginning.
  static ({String bvid, int cid, Duration start}) roundPlayVideo(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'getRoundPlayVideo');
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'getRoundPlayVideo: no data (${_snippet(body)})');
    final bvid = jsonString(data['bvid'])?.trim() ?? '';
    final cid = jsonInt(data['cid']) ?? 0;
    if (!_bvid.hasMatch(bvid) || cid <= 0) {
      throw StreamUnavailable(_site, 'getRoundPlayVideo: no video in rotation (cid ${data['cid']})');
    }
    final played = jsonInt(data['play_time']) ?? 0;
    return (bvid: bvid, cid: cid, start: Duration(seconds: played > 0 ? played : 0));
  }

  /// `x/player/playurl` of part [cid] of [bvid] as one muxed MP4
  /// (`platform=html5`, the route of the TV client and `live_vod`): no WBI
  /// signature, and a guest gets it too.
  static Uri videoPlayUrl(String bvid, int cid) => Uri.https('api.bilibili.com', '/x/player/playurl', {
    'bvid': bvid,
    'cid': '$cid',
    'qn': '80',
    'fnval': '0',
    'fnver': '0',
    'fourk': '1',
    'platform': 'html5',
    'high_quality': '1',
  });

  /// The media headers of a video [bvid]: UA, the video page as Referer
  /// (the CDN checks it) and the cookie.
  static Map<String, String> videoHeaders(String bvid, {String? cookie}) => {
    'user-agent': userAgent,
    'referer': 'https://www.bilibili.com/video/$bvid/',
    if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// The lines of a carousel video's `x/player/playurl` answer: one per
  /// `durl` part's `url` and `backup_url` (http or https only), whole MP4
  /// files ([StreamFormat.other]) with [videoHeaders], started at [start]
  /// and confirmed as [carouselQuality]. No `durl` is `StreamUnavailable`.
  static LivePlayUrlResolution videoResolution(
    String body, {
    required String bvid,
    required Duration start,
    int status = 200,
    String? cookie,
  }) {
    final root = _checked(body, status: status, what: 'x/player/playurl');
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'x/player/playurl: no data (${_snippet(body)})');
    final headers = videoHeaders(bvid, cookie: cookie);
    final urls = <String>[];
    for (final part in _list(data['durl'])) {
      final map = _object(part);
      if (map == null) continue;
      for (final raw in [map['url'], ..._list(map['backup_url'])]) {
        final url = jsonString(raw)?.trim() ?? '';
        final uri = Uri.tryParse(url);
        if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) continue;
        if (!urls.contains(url)) urls.add(url);
      }
    }
    if (urls.isEmpty) throw StreamUnavailable(_site, 'x/player/playurl: no file for $bvid');
    return LivePlayUrlResolution.lines(
      [
        for (final (index, url) in urls.indexed)
          LivePlayLine(url, headers: headers, format: StreamFormat.other, lineId: '${Uri.parse(url).host}|mp4|$index'),
      ],
      appliedQualityData: carouselQualityId,
      start: start,
    );
  }

  /// Qualities: the union of every codec's `accept_qn` and `current_qn`,
  /// positive only, best first. Never `g_qn_desc` alone: it lists tiers no
  /// codec serves. Labels come from `g_qn_desc` through [LiveQualityLabel].
  static List<LivePlayQuality> qualities(Map<String, dynamic> data) {
    final playurl = _playurl(data);
    final names = _qnNames(playurl);
    final codes = <int>{};
    for (final entry in _codecs(playurl)) {
      for (final raw in _list(entry.codec['accept_qn'])) {
        if (jsonInt(raw) case final qn? when qn > 0) codes.add(qn);
      }
      if (jsonInt(entry.codec['current_qn']) case final current? when current > 0) codes.add(current);
    }
    return [
      for (final qn in codes.toList()..sort((a, b) => b.compareTo(a)))
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(platform: _site, rawLabel: names[qn] ?? '', id: qn),
          id: qn,
          data: qn,
          sort: qn,
        ),
    ];
  }

  /// The lines of one play response requested at [requestedQn].
  ///
  /// Candidates are ordered: `current_qn` equal to the request first, then
  /// `http_stream` before `http_hls`, `flv` < `ts` < `fmp4`, `avc` first,
  /// `mcdn` hosts last, then URL. The first candidate fixes the delivered qn
  /// (the platform's acknowledgement: guests asking 10000 get 250) and the
  /// codec; only lines with both are kept. Each line carries the media
  /// headers for the long [roomId] with [cookie] and its lease.
  static LivePlayUrlResolution resolution(
    Map<String, dynamic> data, {
    required Object? requestedQn,
    required String roomId,
    required DateTime issuedAt,
    String? cookie,
  }) {
    final playurl = _playurl(data);
    final requested = jsonInt(requestedQn);
    final candidates = <_Candidate>[];
    for (final entry in _codecs(playurl)) {
      final format = switch (entry.format) {
        'flv' => StreamFormat.flv,
        'ts' || 'fmp4' => StreamFormat.hls,
        _ => null,
      };
      final base = entry.codec['base_url'];
      final current = jsonInt(entry.codec['current_qn']);
      if (format == null || base is! String || base.isEmpty || current == null || current <= 0) continue;
      final codec = jsonString(entry.codec['codec_name'])?.toLowerCase();
      for (final info in _list(entry.codec['url_info'])) {
        final map = _object(info);
        if (map == null) continue;
        final host = map['host'];
        final extra = map['extra'];
        final url = '${host is String ? host.trim() : ''}$base${extra is String ? extra.trim() : ''}';
        final uri = Uri.tryParse(url);
        if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) continue;
        candidates.add((
          url: uri,
          qn: current,
          protocol: entry.protocol,
          format: entry.format,
          codec: codec,
          type: format,
        ));
      }
    }
    if (candidates.isEmpty) return LivePlayUrlResolution(urls: const [], appliedQualityData: requestedQn);
    candidates.sort((a, b) => _compareCandidates(a, b, requested));
    final first = candidates.first;
    final headers = mediaHeaders(roomId, cookie: cookie);
    final seen = <String>{};
    return LivePlayUrlResolution.lines([
      for (final candidate in candidates)
        if (candidate.qn == first.qn && candidate.codec == first.codec && seen.add(candidate.url.toString()))
          LivePlayLine(
            candidate.url.toString(),
            headers: headers,
            format: candidate.type,
            codec: candidate.codec,
            lineId: '${candidate.url.host}|${candidate.protocol}|${candidate.format}|${candidate.codec ?? ''}',
            lease: lease(candidate.url, issuedAt),
          ),
    ], appliedQualityData: first.qn);
  }

  /// Media request headers for the long [roomId]: UA, Origin, Referer and
  /// the cookie. Never `authority` or browser navigation headers: those made
  /// recordings fail while the player worked.
  static Map<String, String> mediaHeaders(String roomId, {String? cookie}) => {
    'user-agent': userAgent,
    'origin': 'https://live.bilibili.com',
    'referer': 'https://live.bilibili.com/$roomId',
    if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// The lease of a media URL received at [issuedAt], from its `expires`
  /// (Unix seconds, about an hour after issue): renew [leaseLead] (at most a
  /// quarter of the lifetime) before. Expiry does not cut an established
  /// connection. No `expires`, or one already past, is no lease.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final match = RegExp(r'(?:^|&)expires=(\d+)(?:&|$)').firstMatch(url.query);
    final expires = match == null ? null : int.tryParse(match.group(1)!);
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  // Session -------------------------------------------------------------------

  /// `x/frontend/finger/spi`: the guest buvid3 (`b_3`) and buvid4 (`b_4`).
  static ({String buvid3, String buvid4}) buvid(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'finger/spi')['data']);
    final buvid3 = jsonString(data?['b_3']);
    if (buvid3 == null) throw ApiChanged(_site, 'finger/spi: no b_3 (${_snippet(body)})');
    return (buvid3: buvid3, buvid4: jsonString(data?['b_4']) ?? '');
  }

  /// The cookie of API and media requests: the guest buvid pair, or the
  /// login cookie with the pair appended when it has no `buvid3`.
  static String cookie({required String buvid3, required String buvid4, String loginCookie = ''}) {
    final stored = loginCookie.trim();
    if (stored.isEmpty) return 'buvid3=$buvid3;buvid4=$buvid4;';
    if (RegExp(r'(?:^|;)\s*buvid3=').hasMatch(stored)) return stored;
    return '${stored.endsWith(';') ? stored : '$stored;'}buvid3=$buvid3;buvid4=$buvid4;';
  }

  /// API request headers; without a cookie only UA and Referer.
  static Map<String, String> apiHeaders(String cookie) => {
    'user-agent': userAgent,
    'referer': referer,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// `x/web-interface/nav`: the WBI keys are the file names of
  /// `data.wbi_img.img_url` and `sub_url`. A guest gets code -101 with the
  /// keys present, so the code only matters when the keys are missing.
  static ({String imgKey, String subKey}) wbiKeys(String body, {int status = 200}) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final image = _object(_object(_object(decoded)?['data'])?['wbi_img']);
    String? key(Object? url) {
      final text = jsonString(url);
      if (text == null) return null;
      final name = text.substring(text.lastIndexOf('/') + 1).split('.').first;
      return name.isEmpty ? null : name;
    }

    final imgKey = key(image?['img_url']);
    final subKey = key(image?['sub_url']);
    if (imgKey != null && subKey != null && status >= 200 && status < 300) return (imgKey: imgKey, subKey: subKey);
    _checked(body, status: status, what: 'nav');
    throw ApiChanged(_site, 'nav: no wbi_img keys (${_snippet(body)})');
  }

  static const List<int> _mixinTable = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, //
    38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62,
    11, 36, 20, 34, 44, 52,
  ];

  /// The WBI mixin key: imgKey + subKey permuted by the fixed table, first 32
  /// characters.
  static String mixinKey(String imgKey, String subKey) {
    final origin = '$imgKey$subKey';
    if (origin.length < 64) throw ApiChanged(_site, 'WBI keys too short (${origin.length} characters)');
    return [for (final index in _mixinTable) origin[index]].join().substring(0, 32);
  }

  static final RegExp _unsafe = RegExp("[!'()*]");

  /// The WBI query to sign: [params] plus `wts`, sorted by key, `!'()*`
  /// removed from values, percent-encoded like `encodeURIComponent`. The
  /// site appends `&w_rid=` + md5(query + mixin key).
  static String wbiQuery(Map<String, String> params, {required int wts}) {
    final all = {...params, 'wts': '$wts'};
    final keys = all.keys.toList()..sort();
    return [
      for (final key in keys) '${Uri.encodeComponent(key)}=${Uri.encodeComponent(all[key]!.replaceAll(_unsafe, ''))}',
    ].join('&');
  }

  /// `w_webid`: `"access_id":"…"` in the `live.bilibili.com/lol` page,
  /// backslashes removed.
  static String accessId(String html) {
    final id = RegExp('"access_id":"(.*?)"').firstMatch(html)?.group(1)?.replaceAll(r'\', '');
    if (id == null || id.isEmpty) throw const ApiChanged(_site, 'lol page: no access_id');
    return id;
  }

  /// `getDanmuInfo` (WBI signed, long id): the token and the endpoints, the
  /// general gateway first, then `host_list` with `wss_port` (443 omitted),
  /// without duplicates. An empty token is `ApiChanged`.
  static ({String token, List<Uri> servers}) danmakuInfo(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'getDanmuInfo')['data']);
    final token = jsonString(data?['token']);
    if (token == null) throw const ApiChanged(_site, 'getDanmuInfo: empty token');
    final servers = <String>[danmakuGateway];
    for (final item in _list(data?['host_list'])) {
      final host = jsonString(_object(item)?['host']);
      if (host == null) continue;
      final port = jsonInt(_object(item)?['wss_port']) ?? 443;
      final endpoint = 'wss://$host${port == 443 ? '' : ':$port'}/sub';
      if (!servers.contains(endpoint)) servers.add(endpoint);
    }
    return (token: token, servers: [for (final server in servers) Uri.parse(server)]);
  }

  /// The danmaku uid: 0 without a cookie; else `DedeUserID` of the same
  /// cookie (a separately stored uid can belong to an older login while the
  /// cookie already changed); else the verified [storedUid]; else 0.
  static int danmakuUid({required String cookie, required int storedUid}) {
    if (cookie.trim().isEmpty) return 0;
    final match = RegExp(r'(?:^|;)\s*DedeUserID=(\d+)(?:;|$)', caseSensitive: false).firstMatch(cookie);
    final uid = int.tryParse(match?.group(1) ?? '');
    if (uid != null && uid > 0) return uid;
    return storedUid > 0 ? storedUid : 0;
  }

  /// `qrcode/generate`: the key to poll with and the https URL to encode.
  static ({String key, Uri url}) qrCode(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'qrcode/generate')['data']);
    final key = jsonString(data?['qrcode_key']);
    final url = jsonUrl(data?['url']);
    if (key == null || url == null || !url.isScheme('https')) {
      throw ApiChanged(_site, 'qrcode/generate: no key or https url (${_snippet(body)})');
    }
    return (key: key, url: url);
  }

  /// `qrcode/poll`: `data.code` 86101, 86090, 86038 and 0 are flow states;
  /// any other code is `ApiChanged`.
  static BilibiliQrState qrPoll(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'qrcode/poll')['data']);
    return switch (jsonInt(data?['code'])) {
      86101 => BilibiliQrState.waiting,
      86090 => BilibiliQrState.scanned,
      86038 => BilibiliQrState.expired,
      0 => BilibiliQrState.confirmed,
      final code => throw ApiChanged(_site, 'qrcode/poll: code $code ${jsonString(data?['message']) ?? ''}'.trim()),
    };
  }

  /// `x/member/web/account`: signed in when `data.uname` and `data.mid` are
  /// set; -101 is `NeedsLogin` (the stored cookie expired).
  static ({int uid, String name}) account(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'member/web/account')['data']);
    final name = jsonString(data?['uname']);
    final uid = jsonInt(data?['mid']);
    if (name == null || uid == null || uid <= 0) {
      throw ApiChanged(_site, 'member/web/account: no uname or mid (${_snippet(body)})');
    }
    return (uid: uid, name: name);
  }

  // Helpers -------------------------------------------------------------------

  static Map<int, String> _qnNames(Map<String, dynamic> playurl) => {
    for (final raw in _list(playurl['g_qn_desc']))
      if (_object(raw) case final map? when jsonInt(map['qn']) != null && jsonString(map['desc']) != null)
        jsonInt(map['qn'])!: jsonString(map['desc'])!,
  };

  static Map<String, dynamic> _playurl(Map<String, dynamic> data) {
    final playurl = _object(_object(data['playurl_info'])?['playurl']);
    if (playurl == null) throw const ApiChanged(_site, 'getRoomPlayInfo: playurl_info.playurl missing');
    return playurl;
  }

  static Iterable<({String protocol, String format, Map<String, dynamic> codec})> _codecs(
    Map<String, dynamic> playurl,
  ) sync* {
    for (final stream in _list(playurl['stream'])) {
      final streamMap = _object(stream);
      if (streamMap == null) continue;
      final protocol = jsonString(streamMap['protocol_name']) ?? '';
      for (final format in _list(streamMap['format'])) {
        final formatMap = _object(format);
        if (formatMap == null) continue;
        final name = jsonString(formatMap['format_name']) ?? '';
        for (final codec in _list(formatMap['codec'])) {
          if (_object(codec) case final codecMap?) yield (protocol: protocol, format: name, codec: codecMap);
        }
      }
    }
  }

  static int _compareCandidates(_Candidate a, _Candidate b, int? requestedQn) {
    final byRequest = (a.qn == requestedQn ? 0 : 1).compareTo(b.qn == requestedQn ? 0 : 1);
    if (byRequest != 0) return byRequest;
    final byProtocol = (a.protocol == 'http_stream' ? 0 : 1).compareTo(b.protocol == 'http_stream' ? 0 : 1);
    if (byProtocol != 0) return byProtocol;
    final byFormat = _formatRank(a.format).compareTo(_formatRank(b.format));
    if (byFormat != 0) return byFormat;
    final byCodec = (a.codec == 'avc' ? 0 : 1).compareTo(b.codec == 'avc' ? 0 : 1);
    if (byCodec != 0) return byCodec;
    final byEdge = (a.url.toString().contains('mcdn') ? 1 : 0).compareTo(b.url.toString().contains('mcdn') ? 1 : 0);
    if (byEdge != 0) return byEdge;
    return a.url.toString().compareTo(b.url.toString());
  }

  static int _formatRank(String format) => switch (format) {
    'flv' => 0,
    'ts' => 1,
    'fmp4' => 2,
    _ => 3,
  };

  /// The `watched_show` "N人看过" count (cumulative viewers) when `switch` is
  /// true and the room is live; with `switch: false` it repeats the
  /// popularity. Empty when there is none.
  static String _watched(Object? value, {required bool live}) {
    final show = _object(value);
    if (show == null || show['switch'] != true || !live) return '';
    final count = jsonCount(show['num']);
    return count == null ? '' : '$count';
  }

  static final RegExp _emTag = RegExp(r'</?em\b[^>]*>', caseSensitive: false);

  /// Search text without the `<em class="keyword">` highlight, entities
  /// decoded.
  static String _highlighted(Object? value) => decodeHtmlEntities((jsonString(value) ?? '').replaceAll(_emTag, ''));

  /// HTML in `description` (`<p>…</p>`) as plain text: block ends and `<br>`
  /// become line breaks, other tags are dropped, entities decoded. 3.x kept
  /// the tags.
  static String? _richText(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    final lines = decodeHtmlEntities(
      text
          .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
          .replaceAll(RegExp('<[^>]*>'), ''),
    ).split('\n').map((line) => line.trim());
    final plain = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return plain.isEmpty ? null : plain;
  }

  /// `live_status` 1, as a number or a string (3.x once read `"1"` as
  /// offline).
  static bool _isLive(Object? value) => jsonInt(value) == 1;

  /// `live_status` (number or string): 1 live, 2 the carousel, anything
  /// else offline (3.x read 2 as offline too).
  static LiveStatus _status(Object? value) => switch (jsonInt(value)) {
    1 => LiveStatus.live,
    2 => LiveStatus.carousel,
    _ => LiveStatus.offline,
  };

  /// A positive Unix time in seconds as UTC; 0 (not live) is none.
  static DateTime? _unixTime(Object? value) => switch (jsonInt(value)) {
    final int seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    _ => null,
  };

  static final RegExp _localTime = RegExp(r'^(\d{4})-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');

  /// Search's `live_time`, `yyyy-MM-dd HH:mm:ss` in Beijing time (UTC+8), as
  /// UTC; the `0000-00-00 00:00:00` of an offline streamer is none.
  static DateTime? _beijingTime(Object? value) {
    final match = _localTime.firstMatch(jsonString(value)?.trim() ?? '');
    if (match == null || int.parse(match.group(1)!) < 2000) return null;
    return DateTime.tryParse('${match.group(0)!.replaceFirst(' ', 'T')}+08:00')?.toUtc();
  }

  /// `room_info.special_type`: 1 is a paid room (a ticket), 0 an ordinary
  /// room, 2 the New Year gala room. A paid room that is live is
  /// [LiveRestriction.paid]; otherwise there is no restriction. Without the
  /// field the response says nothing (null).
  static LiveRestriction? _restriction(Object? specialType, {required bool live}) => switch (jsonInt(specialType)) {
    null => null,
    1 when live => LiveRestriction.paid,
    _ => LiveRestriction.none,
  };
}

typedef _Candidate = ({Uri url, int qn, String protocol, String format, String? codec, StreamFormat type});

/// Bilibili room ids are positive decimal integers.
String? _roomId(Object? value) {
  final id = jsonInt(value);
  return id != null && id > 0 ? '$id' : null;
}

/// An image URL made absolute by [normalizeImageUrl] (3.x wrote `https:` in
/// front of whatever came), with the size [suffix]; empty when there is none.
String _image(Object? value, [String suffix = '']) {
  final url = normalizeImageUrl(value);
  return url.isEmpty ? '' : '$url$suffix';
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The `{code, message, data}` envelope: HTTP 412 or code -412 →
/// `RateLimited`; HTTP 5xx → `NetworkFailure`; -352 → `RiskControl`; -101 →
/// `NeedsLogin`; codes in [notFound] → `NotFound`; any other non-zero code,
/// non-2xx status or non-object body → `ApiChanged`.
Map<String, dynamic> _checked(String body, {required int status, required String what, Set<int> notFound = const {}}) {
  if (status == 412) throw RateLimited(_site, detail: '$what: HTTP 412');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  final ok = status >= 200 && status < 300;
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) {
    throw ApiChanged(_site, '$what: ${ok ? 'not a JSON object' : 'HTTP $status'} (${_snippet(body)})');
  }
  final code = jsonInt(decoded['code']);
  if (code == 0 && ok) return decoded;
  final detail = '$what: code $code ${jsonString(decoded['message']) ?? jsonString(decoded['msg']) ?? ''}'.trim();
  switch (code) {
    case -352:
      throw RiskControl(_site, detail: detail);
    case -412:
      throw RateLimited(_site, detail: detail);
    case -101:
      throw NeedsLogin(_site, detail);
    case final int value when notFound.contains(value):
      throw NotFound(_site, detail);
  }
  throw ApiChanged(_site, ok ? detail : 'HTTP $status, $detail');
}
