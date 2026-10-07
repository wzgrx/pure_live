import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'inke';

/// What a live room's detail knows besides its uid: the current broadcast
/// (`live_share_pc`'s `liveid`, or the app's when it answered). Every
/// broadcast has a new id, so it is no room identity (the uid is); it names
/// the broadcast whose pull URL 3.x looked for in the website showcases,
/// which is still the fallback when the app API gives none.
@immutable
final class InkeRoomData {
  /// Creates the data.
  const new({required this.liveId, this.broadcast, this.receivedAt});

  /// The broadcast id (16 digits).
  final String liveId;

  /// The app's answer for this broadcast at room entry (`now_publish`), when
  /// it gave one: its signed lines serve the first play (see
  /// `InkeSite.answerReuse`).
  final InkeBroadcast? broadcast;

  /// When [broadcast] was received.
  final DateTime? receivedAt;
}

/// A live broadcast as the app API answers it (`now_publish`'s `live`,
/// `simpleall`'s `lives[]`).
@immutable
final class InkeBroadcast {
  /// Creates the broadcast.
  const new({
    required this.liveId,
    this.pullUrl,
    this.originUrl,
    this.title = '',
    this.cover = '',
    this.startedAt,
    this.online,
    this.heat,
  });

  /// `id`: the broadcast id.
  final String liveId;

  /// `stream_addr` when it is the Wangsu H.264 pull URL of this broadcast
  /// (see [InkeApi.plainFlv]); null otherwise.
  final String? pullUrl;

  /// `stream_multi_addr` when it is the Zego pull URL of this broadcast, the
  /// anchor's original stream (HEVC; see [InkeApi.zegoFlv]); null otherwise.
  final String? originUrl;

  /// `name`, the broadcast title; empty when missing or the platform's
  /// stand-in [InkeApi.placeholderTitle].
  final String title;

  /// `cover`, the broadcast's cover; empty when missing.
  final String cover;

  /// `start_time`, when the broadcast started.
  final DateTime? startedAt;

  /// `numbers.real`: the "N人在看" the app shows (concurrent viewers).
  final int? online;

  /// `online_users`: a larger display figure, kept as heat (REG-INKE-003).
  final int? heat;

  /// Whether the app gave this client a line: a broadcast with one plays
  /// for anyone ([LiveRestriction.none]); without one the answer says
  /// nothing about a restriction.
  bool get hasLine => pullUrl != null || originUrl != null;
}

/// Pure parsing of Inke (映客) responses (3.x's `InkeApi`). Each function
/// takes the response text and status and returns 3.x's models or throws a
/// `SiteError`.
///
/// The website API (`webapi.busi.inke.cn/web/…`, `{error_code, data}`) has
/// no index of live rooms, only finite showcases: the top list (8 rooms),
/// the hot lists and six channels. The app API (`service.inke.cn/api/live`,
/// `{dm_error, …}`) has the hot list `simpleall` (about 20 broadcasts with
/// titles, covers, start times and audiences; the recommendations since
/// M4.U) and `now_publish`, the current broadcast of any anchor with its
/// signed Wangsu (H.264) and Zego (the original, HEVC) lines. 3.x looked for
/// a room's pull URL in the showcases, so a broadcast outside them could not
/// be played (REG-INKE-001); the app is asked first, the showcases stay the
/// fallback of the H.264 line.
abstract final class InkeApi {
  /// Website origin: the `Origin` of every request, and with a slash its
  /// `Referer`.
  static const String origin = 'https://www.inke.cn';

  /// Website API base.
  static const String webApi = 'https://webapi.busi.inke.cn/web';

  /// App API base (the hot list and the current broadcast).
  static const String appApi = 'https://service.inke.cn/api/live';

  /// The user agent 3.x sent to the API and the media CDN
  /// (`InkeApi.playHeaders`).
  static const String userAgent = 'Mozilla/5.0';

  /// Headers of the API and media requests (3.x's `playHeaders`, which its
  /// `PlaybackHeaderResolver` also gave the player and the recorder). No
  /// cookie: 3.x's Inke was anonymous.
  static const Map<String, String> headers = {'referer': '$origin/', 'origin': origin, 'user-agent': userAgent};

  /// Largest answer 3.x accepted (1 MiB).
  static const int responseLimit = 1024 * 1024;

  /// `live_share_pc`'s "当前用户无直播" (also for a uid that does not exist):
  /// offline, on that endpoint only.
  static const int noLiveCode = 1099999920;

  /// `areaType` of every area (3.x).
  static const String areaType = 'showcase';

  /// `typeName` of every area (3.x).
  static const String typeName = '映客官网精选';

  /// Id and name of the one category the areas are listed under (3.x used
  /// the platform's).
  static const String categoryId = _site;

  /// See [categoryId].
  static const String categoryName = '映客';

  /// The website's top list (`Live_top_pc`, 8 slots), 3.x's recommendations,
  /// kept as the first area since the recommendations are the app's hot list
  /// (UPGRADES 14-1). Its id is the endpoint's name, which no channel key
  /// can be (they are alphanumeric).
  static const LiveArea topArea = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: typeName,
    areaId: 'Live_top_pc',
    areaName: '官网推荐',
  );

  /// The title the platform gives a broadcast its anchor did not name
  /// ("live now"; seen in `live_share_pc`'s `live_name` and the app's
  /// `name`). A stand-in, so it is treated as no title: the nickname stands
  /// in as for any untitled broadcast (3.x).
  static const String placeholderTitle = '正在直播中';

  /// A uid (the room) or broadcast id: 1–18 digits, no leading zero.
  static final RegExp idPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  static final RegExp _tabKey = RegExp(r'^[a-zA-Z0-9]{1,64}$');

  /// 3.x's one quality: the Wangsu FLV, an H.264 transcode (codec hint
  /// `avc`, G01.3).
  static const LivePlayQuality flv = LivePlayQuality(quality: 'FLV', id: 'flv', codec: 'avc');

  /// The anchor's original stream, the Zego FLV (HEVC, FLV codec id 12;
  /// REG-INKE-002), when the app gives it (UPGRADES 14-5). Ranked above
  /// [flv]; which of the two comes first is the "优先 H.264" setting's
  /// choice (`InkeSite`). Its codec hint `hevc` keeps "优先 H.264" from
  /// starting a room on it by name (G01.3).
  static const LivePlayQuality original = LivePlayQuality(quality: '原画', id: 'origin', sort: 1, codec: 'hevc');

  /// Line id of the Wangsu CDN (`live-pull-ws`).
  static const String lineId = 'ws';

  /// Line id of the Zego CDN (`live-pull-zego`).
  static const String zegoLineId = 'zego';

  /// How long before `wsABStime` a pull URL is renewed, at most a quarter of
  /// its lifetime (the archived v4 adapter; 3.x had no lease).
  static const Duration leaseLead = Duration(minutes: 10);

  /// The showcases 3.x looked for a broadcast's pull URL in, in order.
  static const List<String> showcasePaths = ['Live_top_pc', 'Live_hot_pc', 'Live_channel_pc'];

  // Envelopes -----------------------------------------------------------------

  /// The `data` of a website answer. HTTP 401/403 is `RiskControl`, 404
  /// `NotFound`, 429 `RateLimited`, 5xx and any other status but 200
  /// `NetworkFailure` (3.x read no body then). A body over [responseLimit],
  /// not a JSON object or without `error_code` is `ApiChanged`, and so is any
  /// code but 0 — except [noLiveCode] when [offline] (the room endpoint),
  /// which gives null.
  static Map<String, dynamic>? webData(String body, {required String what, int status = 200, bool offline = false}) {
    final root = _root(body, what, status);
    final code = _integer(root['error_code']);
    if (code == null) throw ApiChanged(_site, '$what: no error_code');
    if (offline && code == noLiveCode) return null;
    if (code != 0) throw ApiChanged(_site, '$what: error_code $code');
    return _object(root['data'], '$what.data');
  }

  /// An app answer (`{dm_error, error_msg, …}`), checked like [webData];
  /// any `dm_error` but 0 is `ApiChanged`.
  static Map<String, dynamic> appData(String body, {required String what, int status = 200}) {
    final root = _root(body, what, status);
    final code = _integer(root['dm_error']);
    if (code != 0) throw ApiChanged(_site, '$what: dm_error $code');
    return root;
  }

  static Map<String, dynamic> _root(String body, String what, int status) {
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
    return _object(decoded, what);
  }

  // Showcases -----------------------------------------------------------------

  /// `Live_channel_pc`: one category, 映客, whose areas are [topArea] and
  /// then the channels in the site's order. A channel without an
  /// alphanumeric `tab_key` (up to 64 characters), with one an earlier
  /// channel has, without a name or without a list of rows is skipped
  /// (3.x failed the catalog); more than 100 channels, or no list of them,
  /// is `ApiChanged`.
  static List<LiveCategory> categories(String body, {int status = 200}) => [
    LiveCategory(
      id: categoryId,
      name: categoryName,
      children: [
        topArea,
        for (final group in _channels(body, status))
          LiveArea(platform: _site, areaType: areaType, typeName: typeName, areaId: group.key, areaName: group.name),
      ],
    ),
  ];

  /// The rooms of channel [tabKey] of `Live_channel_pc`: one page, nothing
  /// more (3.x); an unknown channel is `NotFound`.
  static LiveDirectoryPage channelPage(String body, {required String tabKey, int status = 200}) {
    final group = _channels(body, status).where((group) => group.key == tabKey).firstOrNull;
    if (group == null) throw NotFound(_site, 'channel $tabKey');
    return LiveDirectoryPage(rooms: _unique(_cards(group.rows)), page: 1, hasMore: false);
  }

  /// Every room of every channel of `Live_channel_pc`, in the site's order
  /// (the keyword search's second part).
  static List<LiveRoom> channelRooms(String body, {int status = 200}) => [
    for (final group in _channels(body, status)) ..._cards(group.rows),
  ];

  /// `Live_top_pc`: the 8 slots of [topArea], as one page, each room once.
  static LiveDirectoryPage topPage(String body, {int status = 200}) {
    final data = webData(body, what: 'Live_top_pc', status: status)!;
    return LiveDirectoryPage(rooms: _unique(_cards(_rows(data['list'], 'Live_top_pc.list'))), page: 1, hasMore: false);
  }

  /// 3.x's nickname search, over the app's hot list too (UPGRADES 14-2):
  /// [rooms] (the top list, then the channels) and then [hot] (the app's
  /// hot list) whose nickname contains [keyword] (trimmed, case ignored),
  /// each uid once at its first place, page [page] of [pageSize]. A room the
  /// hot list also has is its hot card: the app's title, cover, audience and
  /// start time (UPGRADES 14-4). There is no server search.
  static List<LiveRoom> searchShowcases(
    String keyword,
    Iterable<LiveRoom> rooms, {
    Iterable<LiveRoom> hot = const [],
    int page = 1,
    int pageSize = 20,
  }) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final cards = <String, LiveRoom>{};
    for (final room in hot) {
      cards.putIfAbsent(room.roomId, () => room);
    }
    final matches = _unique([...rooms, ...hot].where((room) => room.nick.toLowerCase().contains(query)));
    final start = (page - 1) * pageSize;
    if (start >= matches.length) return const [];
    return List.unmodifiable(matches.skip(start).take(pageSize).map((room) => cards[room.roomId] ?? room));
  }

  /// The pull URLs 3.x found in showcase [path] (one of [showcasePaths]) for
  /// broadcast [liveId] of [uid]: rows of that uid and broadcast whose
  /// `stream_addr` passes [plainFlv], each once. Empty when the showcase
  /// does not hold the broadcast. A group that is no list of rows, or a row
  /// without a readable uid or broadcast id, is skipped.
  static List<String> showcaseUrls(
    String body, {
    required String path,
    required String uid,
    required String liveId,
    int status = 200,
  }) {
    final data = webData(body, what: path, status: status)!;
    final groups = switch (path) {
      'Live_hot_pc' => _object(data['list'], '$path.list').values.toList(),
      'Live_channel_pc' => [for (final group in _rows(data['list'], '$path.list')) group['list']],
      _ => <Object?>[_rows(data['list'], '$path.list')],
    };
    if (groups.length > 100) throw ApiChanged(_site, '$path: ${groups.length} groups');
    final urls = <String>{};
    for (final group in groups) {
      if (group is! List || group.length > 1000) continue;
      for (final row in group.whereType<Map<String, dynamic>>()) {
        if (_idOrNull(row['uid']) != uid || _idOrNull(row['live_id']) != liveId) continue;
        if (plainFlv(row['stream_addr'], liveId: liveId) case final url?) urls.add(url);
      }
    }
    return urls.toList();
  }

  static List<({String key, String name, List<Map<String, dynamic>> rows})> _channels(String body, int status) {
    final data = webData(body, what: 'Live_channel_pc', status: status)!;
    final groups = _rows(data['list'], 'Live_channel_pc.list');
    if (groups.length > 100) throw ApiChanged(_site, 'Live_channel_pc: ${groups.length} channels');
    final keys = <String>{};
    final channels = <({String key, String name, List<Map<String, dynamic>> rows})>[];
    for (final group in groups) {
      final key = _text(group['tab_key']);
      final name = _text(group['channel_name']);
      final rows = group['list'];
      if (!_tabKey.hasMatch(key) || name.isEmpty || rows is! List || rows.length > 1000 || !keys.add(key)) continue;
      channels.add((key: key, name: name, rows: _rows(rows, 'channel $key')));
    }
    return channels;
  }

  /// The cards of showcase [rows] that are readable (see [_card]).
  static Iterable<LiveRoom> _cards(List<Map<String, dynamic>> rows) => rows.map(_card).nonNulls;

  /// A showcase row as 3.x's card: live, the nickname as title, the
  /// portrait as avatar and cover, no audience (the showcases have none). A
  /// row without a uid, broadcast id or nickname is skipped (3.x failed the
  /// list).
  static LiveRoom? _card(Map<String, dynamic> row) {
    final uid = _idOrNull(row['uid']);
    final liveId = _idOrNull(row['live_id']);
    final nick = _text(row['nick']);
    if (uid == null || liveId == null || nick.isEmpty) return null;
    final portrait = normalizeImageUrl(row['portrait']);
    return LiveRoom(
      platform: _site,
      roomId: uid,
      userId: uid,
      nick: nick,
      title: nick,
      avatar: portrait,
      cover: portrait,
      link: roomUrl(uid, liveId: liveId),
      liveStatus: LiveStatus.live,
      watching: '',
      audienceMetricType: AudienceMetricType.unknown,
    );
  }

  /// [rooms] with each uid once (the first wins), in order.
  static List<LiveRoom> _unique(Iterable<LiveRoom> rooms) {
    final seen = <String>{};
    return [
      for (final room in rooms)
        if (seen.add(room.roomId)) room,
    ];
  }

  // App hot list --------------------------------------------------------------

  /// `simpleall`: the app's hot list (about 20 broadcasts, different at each
  /// request), the recommendations since M4.U (UPGRADES 14-1), as one page,
  /// each uid once. Every card is live, with the app's title, cover, start
  /// time and audience ([appRoom]). A row that is not a live broadcast
  /// (`status` 1) with a uid (`creator.id`) and a broadcast id is skipped.
  static LiveDirectoryPage hotPage(String body, {int status = 200}) {
    final root = appData(body, what: 'simpleall', status: status);
    final rooms = <LiveRoom>[];
    for (final row in _rows(root['lives'], 'simpleall.lives')) {
      final creator = row['creator'];
      if (creator is! Map<String, dynamic>) continue;
      final uid = _idOrNull(creator['id']);
      final liveId = _idOrNull(row['id']);
      if (uid == null || liveId == null || _integer(row['status']) != 1) continue;
      rooms.add(
        appRoom(
          uid: uid,
          nick: _text(creator['nick']),
          avatar: normalizeImageUrl(creator['portrait']),
          broadcast: _broadcast(row, liveId),
        ),
      );
    }
    return LiveDirectoryPage(rooms: _unique(rooms), page: 1, hasMore: false);
  }

  /// The live card of [broadcast] by anchor [uid]: its title (else the
  /// nickname, as 3.x titled untitled broadcasts), its cover (else the
  /// avatar, 3.x's cover), its start time, the app's "N人在看" as concurrent
  /// viewers and `online_users` as heat (UPGRADES 14-3), and no restriction
  /// when the app gave a line.
  static LiveRoom appRoom({
    required String uid,
    required String nick,
    required String avatar,
    required InkeBroadcast broadcast,
  }) {
    final audience = _audience(broadcast);
    return LiveRoom(
      platform: _site,
      roomId: uid,
      userId: uid,
      nick: nick,
      title: broadcast.title.isEmpty ? nick : broadcast.title,
      avatar: avatar,
      cover: broadcast.cover.isEmpty ? avatar : broadcast.cover,
      link: roomUrl(uid, liveId: broadcast.liveId),
      liveStatus: LiveStatus.live,
      watching: audience.watching,
      onlineViewers: audience.online,
      popularity: audience.heat,
      audienceMetricType: audience.type,
      startedAt: broadcast.startedAt,
      restriction: broadcast.hasLine ? LiveRestriction.none : null,
    );
  }

  static ({String watching, String online, String heat, AudienceMetricType type}) _audience(InkeBroadcast broadcast) {
    final online = broadcast.online?.toString();
    final heat = broadcast.heat?.toString();
    return (
      watching: online ?? heat ?? '',
      online: online ?? '',
      heat: heat ?? '',
      type: online != null
          ? AudienceMetricType.onlineViewers
          : heat != null
          ? AudienceMetricType.popularity
          : AudienceMetricType.unknown,
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// `live_share_pc?uid=`: the room [uid] as 3.x read it, under that uid.
  ///
  /// [noLiveCode] is offline, with nothing but the uid and a link without a
  /// broadcast (the answer has no profile). Otherwise the answer must be the
  /// live broadcast of that very anchor (`live_uid`, `media_info.inke_id`,
  /// `status` 1, a broadcast id and a nickname), or it is `ApiChanged`. The
  /// title is `live_name`, else (or when it is [placeholderTitle]) the
  /// nickname; the avatar is the anchor's portrait and the cover the room's
  /// (both the same picture); no audience. The broadcast goes into
  /// [InkeRoomData]. The app's answer is added by [withBroadcast].
  static LiveRoom detail(String body, {required String uid, int status = 200}) {
    final info = webData(body, what: 'live_share_pc', status: status, offline: true);
    if (info == null) {
      return LiveRoom(platform: _site, roomId: uid, userId: uid, link: roomUrl(uid), liveStatus: LiveStatus.offline);
    }
    if (_id(info['live_uid'], 'live_share_pc.live_uid') != uid || !const {1, '1', true}.contains(info['status'])) {
      throw ApiChanged(_site, 'live_share_pc: not the live room of $uid');
    }
    final liveId = _id(info['liveid'], 'live_share_pc.liveid');
    final owner = _object(info['media_info'], 'live_share_pc.media_info');
    final nick = _text(owner['nick']);
    if (_id(owner['inke_id'], 'live_share_pc.media_info.inke_id') != uid || nick.isEmpty) {
      throw ApiChanged(_site, 'live_share_pc: not the anchor $uid');
    }
    final name = _title(info['live_name']);
    return LiveRoom(
      platform: _site,
      roomId: uid,
      userId: uid,
      nick: nick,
      title: name.isEmpty ? nick : name,
      avatar: normalizeImageUrl(owner['portrait']),
      cover: normalizeImageUrl(info['portrait']),
      link: roomUrl(uid, liveId: liveId),
      liveStatus: LiveStatus.live,
      watching: '',
      audienceMetricType: AudienceMetricType.unknown,
      data: InkeRoomData(liveId: liveId),
    );
  }

  /// The live [room] of [detail] with the app's [broadcast], received at
  /// [receivedAt] (UPGRADES 14-3, 14-4): the app's title and cover where it
  /// has them, its audience and start time, no restriction when it gave a
  /// line, and its broadcast (for the link and the first play).
  static LiveRoom withBroadcast(LiveRoom room, InkeBroadcast broadcast, {required DateTime receivedAt}) {
    final audience = _audience(broadcast);
    return room.copyWith(
      title: broadcast.title.isEmpty ? null : broadcast.title,
      cover: broadcast.cover.isEmpty ? null : broadcast.cover,
      link: roomUrl(room.roomId, liveId: broadcast.liveId),
      watching: audience.watching.isEmpty ? null : audience.watching,
      onlineViewers: audience.online.isEmpty ? null : audience.online,
      popularity: audience.heat.isEmpty ? null : audience.heat,
      audienceMetricType: audience.type,
      startedAt: broadcast.startedAt,
      restriction: broadcast.hasLine ? LiveRestriction.none : null,
      data: InkeRoomData(liveId: broadcast.liveId, broadcast: broadcast, receivedAt: receivedAt),
    );
  }

  /// The room's web page; with [liveId] the broadcast's (3.x).
  static String roomUrl(String uid, {String? liveId}) =>
      '$origin/liveroom/index.html?uid=$uid${liveId == null ? '' : '&id=$liveId'}';

  /// Where "open in browser" goes (3.x's `InkeSite.externalRoomUrl`): the
  /// room's [LiveRoom.link] when it is this room's web page with one numeric
  /// broadcast id, else the website's home page (the room page needs both).
  static String externalRoomUrl(LiveRoom room) {
    final uri = Uri.tryParse(room.link?.trim() ?? '');
    if (uri != null && room.platform == _site && _webRoomUid(uri) == room.roomId) {
      try {
        final ids = uri.queryParametersAll['id'];
        if (ids != null && ids.length == 1 && RegExp(r'^[0-9]{1,32}$').hasMatch(ids.single)) return uri.toString();
      } on FormatException {
        // A malformed imported link goes to the home page.
      }
    }
    return '$origin/';
  }

  // Streams -------------------------------------------------------------------

  /// `now_publish?id=`: the broadcast the app says [uid] is live with, or
  /// null when it says none (`live` null, or a `status` other than 1). A
  /// broadcast of another anchor or without an id is `ApiChanged`.
  static InkeBroadcast? broadcast(String body, {required String uid, int status = 200}) {
    final live = appData(body, what: 'now_publish', status: status)['live'];
    if (live == null) return null;
    final map = _object(live, 'now_publish.live');
    if (_id(map['creator'], 'now_publish.live.creator') != uid) {
      throw ApiChanged(_site, 'now_publish: a broadcast of ${map['creator']} for $uid');
    }
    if (_integer(map['status']) != 1) return null;
    return _broadcast(map, _id(map['id'], 'now_publish.live.id'));
  }

  /// An app broadcast [live] with id [liveId] (see [InkeBroadcast]).
  static InkeBroadcast _broadcast(Map<String, dynamic> live, String liveId) {
    final numbers = live['numbers'];
    return InkeBroadcast(
      liveId: liveId,
      pullUrl: plainFlv(live['stream_addr'], liveId: liveId),
      originUrl: zegoFlv(live['stream_multi_addr'], liveId: liveId),
      title: _title(live['name']),
      cover: normalizeImageUrl(live['cover']),
      startedAt: startTime(live['start_time']),
      online: numbers is Map ? _count(numbers['real']) : null,
      heat: _count(live['online_users']),
    );
  }

  /// `start_time` (Unix seconds) as a UTC time; null for 0, a value that is
  /// not a count of seconds between 2000 and 2100, or anything else.
  static DateTime? startTime(Object? value) {
    final seconds = _integer(value);
    if (seconds == null || seconds < 946684800 || seconds > 4102444800) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// [value] when it is the Wangsu pull URL of broadcast [liveId] (3.x's
  /// check): http(s), host `live-pull-ws.ikstatic.cn`, the default port, no
  /// user info or fragment, path `/live/<liveId>_t.flv` (the H.264
  /// transcode). The signed query is kept as written; the Zego address never
  /// passes. Null otherwise.
  static String? plainFlv(Object? value, {required String liveId}) =>
      _pullUrl(value, host: 'live-pull-ws.ikstatic.cn', path: '/live/${liveId}_t.flv', liveId: liveId);

  /// [value] when it is the Zego pull URL of broadcast [liveId]: http(s),
  /// host `live-pull-zego.ikstatic.cn`, the default port, no user info or
  /// fragment, path `/inkemain/<liveId>_0_en.flv` (the anchor's original
  /// stream, HEVC when it says `codecInfo=8192`). Kept as written (the app
  /// gives http). Null otherwise.
  static String? zegoFlv(Object? value, {required String liveId}) =>
      _pullUrl(value, host: 'live-pull-zego.ikstatic.cn', path: '/inkemain/${liveId}_0_en.flv', liveId: liveId);

  static String? _pullUrl(Object? value, {required String host, required String path, required String liveId}) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !idPattern.hasMatch(liveId) ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        uri.host != host ||
        uri.hasFragment ||
        uri.path != path) {
      return null;
    }
    return text;
  }

  /// The codec of the Zego pull URL [url]: `hevc` for `codecInfo=8192`
  /// (every broadcast recorded or probed), null (not known) otherwise.
  static String? zegoCodec(String url) {
    try {
      return Uri.tryParse(url)?.queryParametersAll['codecInfo']?.singleOrNull == '8192' ? 'hevc' : null;
    } on FormatException {
      return null;
    }
  }

  /// The line of a Wangsu pull URL received at [issuedAt]: the media
  /// headers, FLV, H.264, the Wangsu line id and the lease of its
  /// `wsABStime`.
  static LivePlayLine line(String url, {required DateTime issuedAt}) => LivePlayLine(
    url,
    headers: headers,
    format: StreamFormat.flv,
    codec: 'avc',
    lineId: lineId,
    lease: lease(url, issuedAt: issuedAt),
  );

  /// The line of a Zego pull URL received at [issuedAt]: the media headers,
  /// FLV, its codec ([zegoCodec]), the Zego line id and the lease of its
  /// `wsABStime` (the broadcast's start plus a day).
  static LivePlayLine zegoLine(String url, {required DateTime issuedAt}) => LivePlayLine(
    url,
    headers: headers,
    format: StreamFormat.flv,
    codec: zegoCodec(url),
    lineId: zegoLineId,
    lease: lease(url, issuedAt: issuedAt),
  );

  /// The lines of [urls] for 3.x's quality [flv], applied as asked (the site
  /// has one H.264 stream).
  static LivePlayUrlResolution resolution(Iterable<String> urls, {required DateTime issuedAt}) =>
      LivePlayUrlResolution.lines([
        for (final url in urls) line(url, issuedAt: issuedAt),
      ], appliedQualityData: flv.selectionId);

  /// The line of the Zego pull URL [url] for [original], applied as asked.
  static LivePlayUrlResolution originalResolution(String url, {required DateTime issuedAt}) =>
      LivePlayUrlResolution.lines([zegoLine(url, issuedAt: issuedAt)], appliedQualityData: original.selectionId);

  /// The lease of a pull URL received at [issuedAt]: `wsABStime` is the
  /// expiry in hexadecimal Unix seconds (Wangsu about two hours after issue,
  /// Zego a day after the broadcast started); renew [leaseLead] (at most a
  /// quarter of the lifetime) before. The CDN checks it when a connection
  /// opens, so an established FLV connection keeps flowing. No single
  /// `wsABStime`, or one already past, is no lease.
  static PlayLease? lease(String url, {required DateTime issuedAt}) {
    final List<String>? values;
    try {
      values = Uri.tryParse(url)?.queryParametersAll['wsABStime'];
    } on FormatException {
      return null;
    }
    if (values == null || values.length != 1 || !RegExp(r'^[0-9a-fA-F]{1,12}$').hasMatch(values.single)) return null;
    final expires = int.parse(values.single, radix: 16);
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (expires <= 0 || lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  // Links ---------------------------------------------------------------------

  /// The uid of an Inke room link, without any request:
  /// - a web room page `https://www.inke.cn/liveroom/index.html?uid=…`
  ///   (hosts `inke.cn`, `www.inke.cn`, `inke.com`, `www.inke.com`; 3.x's
  ///   `roomFromUri`);
  /// - an app share page `https://mlive2.inke.cn/app/…?uid=…` (a
  ///   `mlive<n>.inke.cn` host and an `/app/` path; the app's `share_addr`,
  ///   which 3.x did not know).
  ///
  /// Both need http(s), the default port, no user info and exactly one
  /// `uid` that is a uid.
  static String? roomIdFromUri(Uri? uri) {
    if (uri == null) return null;
    return _webRoomUid(uri) ?? (_isShareHost(uri) && uri.path.startsWith('/app/') ? _uid(uri) : null);
  }

  static String? _webRoomUid(Uri uri) =>
      const {'inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com'}.contains(uri.host) &&
          uri.path == '/liveroom/index.html'
      ? _uid(uri)
      : null;

  static bool _isShareHost(Uri uri) => RegExp(r'^mlive[0-9]*\.inke\.cn$').hasMatch(uri.host);

  static String? _uid(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    try {
      final values = uri.queryParametersAll['uid'];
      if (values == null || values.length != 1) return null;
      final uid = values.single.trim();
      return idPattern.hasMatch(uid) ? uid : null;
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

/// 3.x's `_rows`: a list of at most 1000 entries, else `ApiChanged`; the
/// entries that are objects (a bad row is skipped).
List<Map<String, dynamic>> _rows(Object? value, String what) {
  if (value is! List || value.length > 1000) throw ApiChanged(_site, '$what: expected a list of rows');
  return value.whereType<Map<String, dynamic>>().toList();
}

/// 3.x's `_integer`: an int, or a string that parses as one.
int? _integer(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

/// A count: an int or digit string, not negative; null otherwise.
int? _count(Object? value) => switch (_integer(value)) {
  final int count when count >= 0 => count,
  _ => null,
};

/// 3.x's `_text`: a string trimmed, anything else empty.
String _text(Object? value) => value is String ? value.trim() : '';

/// A broadcast title: [_text], empty for [InkeApi.placeholderTitle].
String _title(Object? value) {
  final text = _text(value);
  return text == InkeApi.placeholderTitle ? '' : text;
}

/// An id field (number or string) as 3.x's `_id` read it; null when it is
/// not one.
String? _idOrNull(Object? value) {
  final text = value is int ? '$value' : _text(value);
  return InkeApi.idPattern.hasMatch(text) ? text : null;
}

/// [_idOrNull], `ApiChanged` when it is not one.
String _id(Object? value, String what) => _idOrNull(value) ?? (throw ApiChanged(_site, '$what: $value'));

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
