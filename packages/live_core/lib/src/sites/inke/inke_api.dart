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
/// (`live_share_pc`'s `liveid`). Every broadcast has a new id, so it is no
/// room identity (the uid is); it names the broadcast whose pull URL 3.x
/// looked for in the website showcases, which is still the fallback when
/// the app API gives none.
@immutable
final class InkeRoomData {
  /// Creates the data.
  const new({required this.liveId});

  /// The broadcast id (16 digits).
  final String liveId;
}

/// The current broadcast `now_publish` reports for an anchor.
@immutable
final class InkeBroadcast {
  /// Creates the broadcast.
  const new({required this.liveId, this.pullUrl});

  /// `live.id`: the broadcast id.
  final String liveId;

  /// `live.stream_addr` when it is the Wangsu H.264 pull URL of this
  /// broadcast (see [InkeApi.plainFlv]); null otherwise.
  final String? pullUrl;
}

/// Pure parsing of Inke (映客) responses (3.x's `InkeApi`). Each function
/// takes the response text and status and returns 3.x's models or throws a
/// `SiteError`.
///
/// The website API (`webapi.busi.inke.cn/web/…`, `{error_code, data}`) has
/// no index of live rooms, only finite showcases: the top list (8 rooms),
/// the hot lists and six channels. 3.x built its directory and nickname
/// search from them, and looked for a room's pull URL in them too, so a
/// broadcast outside the showcases could not be played (REG-INKE-001). The
/// app API `service.inke.cn/api/live/now_publish` answers the current
/// broadcast of any anchor with the same signed Wangsu URL; it is asked
/// first, the showcases stay the fallback.
abstract final class InkeApi {
  /// Website origin: the `Origin` of every request, and with a slash its
  /// `Referer`.
  static const String origin = 'https://www.inke.cn';

  /// Website API base.
  static const String webApi = 'https://webapi.busi.inke.cn/web';

  /// App API base (the current broadcast).
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

  /// `areaType` of every channel (3.x).
  static const String areaType = 'showcase';

  /// `typeName` of every channel (3.x).
  static const String typeName = '映客官网精选';

  /// Id and name of the one category the channels are listed under (3.x
  /// used the platform's).
  static const String categoryId = _site;

  /// See [categoryId].
  static const String categoryName = '映客';

  /// A uid (the room) or broadcast id: 1–18 digits, no leading zero.
  static final RegExp idPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  static final RegExp _tabKey = RegExp(r'^[a-zA-Z0-9]{1,64}$');

  /// 3.x's one quality: the Wangsu FLV.
  static const LivePlayQuality flv = LivePlayQuality(quality: 'FLV', id: 'flv');

  /// Line id of the Wangsu CDN (`live-pull-ws`).
  static const String lineId = 'ws';

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

  /// `Live_channel_pc`: one category, 映客, whose areas are the channels in
  /// the site's order. As in 3.x the whole answer is checked first: at most
  /// 100 channels, each with a unique alphanumeric `tab_key`, a name and a
  /// list of rows; anything else fails the catalog.
  static List<LiveCategory> categories(String body, {int status = 200}) => [
    LiveCategory(
      id: categoryId,
      name: categoryName,
      children: [
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
    return LiveDirectoryPage(rooms: _unique(group.rows.map(_card)), page: 1, hasMore: false);
  }

  /// Every room of every channel of `Live_channel_pc`, in the site's order
  /// (the keyword search's second half).
  static List<LiveRoom> channelRooms(String body, {int status = 200}) => [
    for (final group in _channels(body, status)) ...group.rows.map(_card),
  ];

  /// `Live_top_pc`: the 8 recommendation slots, as one page, each room once.
  static LiveDirectoryPage topPage(String body, {int status = 200}) {
    final data = webData(body, what: 'Live_top_pc', status: status)!;
    return LiveDirectoryPage(
      rooms: _unique(_rows(data['list'], 'Live_top_pc.list').map(_card)),
      page: 1,
      hasMore: false,
    );
  }

  /// 3.x's nickname search: [rooms] (the top list, then the channels) whose
  /// nickname contains [keyword] (trimmed, case ignored), each uid once,
  /// page [page] of [pageSize]. There is no server search.
  static List<LiveRoom> searchShowcases(String keyword, Iterable<LiveRoom> rooms, {int page = 1, int pageSize = 20}) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final matches = _unique(rooms.where((room) => room.nick.toLowerCase().contains(query)));
    final start = (page - 1) * pageSize;
    if (start >= matches.length) return const [];
    return List.unmodifiable(matches.skip(start).take(pageSize));
  }

  /// The pull URLs 3.x found in showcase [path] (one of [showcasePaths]) for
  /// broadcast [liveId] of [uid]: rows of that uid and broadcast whose
  /// `stream_addr` passes [plainFlv], each once. Empty when the showcase
  /// does not hold the broadcast.
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
      _ => <Object?>[data['list']],
    };
    if (groups.length > 100) throw ApiChanged(_site, '$path: ${groups.length} groups');
    final urls = <String>{};
    for (final group in groups) {
      for (final row in _rows(group, '$path row')) {
        if (_id(row['uid'], '$path uid') != uid || _id(row['live_id'], '$path live_id') != liveId) continue;
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
      if (!_tabKey.hasMatch(key) || !keys.add(key) || name.isEmpty) {
        throw const ApiChanged(_site, 'Live_channel_pc: a channel without a unique key or a name');
      }
      channels.add((key: key, name: name, rows: _rows(group['list'], 'channel $key')));
    }
    return channels;
  }

  /// A showcase row as 3.x's card: live, the nickname as title, the
  /// portrait as avatar and cover, no audience (the showcases have none). A
  /// row without a uid, broadcast id or nickname fails the list, as in 3.x.
  static LiveRoom _card(Map<String, dynamic> row) {
    final uid = _id(row['uid'], 'showcase uid');
    final liveId = _id(row['live_id'], 'showcase $uid live_id');
    final nick = _text(row['nick']);
    if (nick.isEmpty) throw ApiChanged(_site, 'showcase $uid: no nick');
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

  // Rooms ---------------------------------------------------------------------

  /// `live_share_pc?uid=`: the room [uid] as 3.x read it, under that uid.
  ///
  /// [noLiveCode] is offline, with nothing but the uid and a link without a
  /// broadcast (the answer has no profile). Otherwise the answer must be the
  /// live broadcast of that very anchor (`live_uid`, `media_info.inke_id`,
  /// `status` 1, a broadcast id and a nickname), or it is `ApiChanged`. The
  /// title is `live_name`, else the nickname; the avatar is the anchor's
  /// portrait and the cover the room's (both the same picture); no audience.
  /// The broadcast goes into [InkeRoomData].
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
    final name = _text(info['live_name']);
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
    final liveId = _id(map['id'], 'now_publish.live.id');
    return InkeBroadcast(
      liveId: liveId,
      pullUrl: plainFlv(map['stream_addr'], liveId: liveId),
    );
  }

  /// [value] when it is the Wangsu pull URL of broadcast [liveId] (3.x's
  /// check): http(s), host `live-pull-ws.ikstatic.cn`, the default port, no
  /// user info or fragment, path `/live/<liveId>_t.flv` (the H.264
  /// transcode). The signed query is kept as written; the Zego address
  /// (`stream_multi_addr`, HEVC) never passes. Null otherwise.
  static String? plainFlv(Object? value, {required String liveId}) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !idPattern.hasMatch(liveId) ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        uri.host != 'live-pull-ws.ikstatic.cn' ||
        uri.hasFragment ||
        uri.path != '/live/${liveId}_t.flv') {
      return null;
    }
    return text;
  }

  /// The line of a pull URL received at [issuedAt]: the media headers, FLV,
  /// H.264, the Wangsu line id and the lease of its `wsABStime`.
  static LivePlayLine line(String url, {required DateTime issuedAt}) => LivePlayLine(
    url,
    headers: headers,
    format: StreamFormat.flv,
    codec: 'avc',
    lineId: lineId,
    lease: lease(url, issuedAt: issuedAt),
  );

  /// The lines of [urls] for 3.x's quality [flv], applied as asked (the site
  /// has one stream).
  static LivePlayUrlResolution resolution(Iterable<String> urls, {required DateTime issuedAt}) =>
      LivePlayUrlResolution.lines([
        for (final url in urls) line(url, issuedAt: issuedAt),
      ], appliedQualityData: flv.selectionId);

  /// The lease of a pull URL received at [issuedAt]: Wangsu's `wsABStime` is
  /// the expiry in hexadecimal Unix seconds (about two hours after issue);
  /// renew [leaseLead] (at most a quarter of the lifetime) before. Wangsu
  /// checks it when a connection opens, so an established FLV connection
  /// keeps flowing. No single `wsABStime`, or one already past, is no lease.
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

/// 3.x's `_rows`: a list of at most 1000 objects.
List<Map<String, dynamic>> _rows(Object? value, String what) {
  if (value is! List || value.length > 1000) throw ApiChanged(_site, '$what: expected a list of rows');
  return [for (final row in value) _object(row, what)];
}

/// 3.x's `_integer`: an int, or a string that parses as one.
int? _integer(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

/// 3.x's `_text`: a string trimmed, anything else empty.
String _text(Object? value) => value is String ? value.trim() : '';

/// An id field (number or string) as 3.x's `_id` read it; `ApiChanged` when
/// it is not one.
String _id(Object? value, String what) {
  final text = value is int ? '$value' : _text(value);
  if (!InkeApi.idPattern.hasMatch(text)) throw ApiChanged(_site, '$what: $value');
  return text;
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
