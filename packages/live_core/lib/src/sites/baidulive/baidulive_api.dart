import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'baidulive';

/// A channel of the PC feed (3.x's `BaiduLiveCategory`): the feed's `tab`
/// and its `channel_id`.
@immutable
final class BaiduLiveCategory {
  /// Creates the channel.
  const new({required this.id, required this.name, required this.channelId});

  /// `type`, the feed's `tab` (`rec`, `shopping`); the area id.
  final String id;

  /// `name` (`推荐`, `购物`).
  final String name;

  /// `channel_id` (570, 574).
  final int channelId;
}

/// A broadcast's state as 3.x read it.
enum BaiduLiveState {
  /// Broadcasting (`status` 0, a card's `live_status` 1).
  live,

  /// Announced (`status` -1 or 1, `live_status` 0).
  preview,

  /// Not broadcasting (`status` 2 or 20, `live_status` 2).
  offline,

  /// Ended with a replay (`status` 3, `live_status` 3): a room is one
  /// broadcast, so an ended one is shown as offline, as in 3.x.
  replay,

  /// Paid, forbidden or banned: 3.x showed the state as unknown with a
  /// notice, never as offline.
  restricted,

  /// A state 3.x did not know.
  unknown,
}

/// One of 3.x's stream variants: a protocol at a resolution, with its URLs
/// (the lines) in the platform's order. Its id is the quality id,
/// `protocol:resolution:codec` (`hls:720:avc`; resolution 0 is the
/// source).
@immutable
final class BaiduLiveVariant {
  /// Creates the variant.
  new({
    required this.id,
    required this.protocol,
    required this.resolution,
    required this.codec,
    required Iterable<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  /// `protocol:resolution:codec`.
  final String id;

  /// `flv` or `hls`.
  final String protocol;

  /// Height in pixels; 0 for the source stream.
  final int resolution;

  /// `avc` (3.x read no other codec).
  final String codec;

  /// The URLs, one per line.
  final List<Uri> urls;
}

/// A room as 3.x read it from a feed card or from the room command 371
/// (3.x's `BaiduLiveRoom`). Room entry keeps it in `LiveRoom.data` for
/// playback, as 3.x did; a room is one broadcast, so its id is the only
/// platform id needed.
@immutable
final class BaiduLiveRoom {
  /// Creates the room; [status] defaults to [state] (a card has no
  /// restriction flags).
  new({
    required this.roomId,
    required this.userId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.category,
    required this.currentViewers,
    required this.followers,
    required this.state,
    BaiduLiveState? status,
    this.paid = false,
    this.blocked = false,
    Iterable<BaiduLiveVariant> variants = const [],
  }) : status = status ?? state,
       variants = List.unmodifiable(variants);

  /// The room id as asked for (a card's `room_id`).
  final String roomId;

  /// `host.uk`, the anchor; empty when not given.
  final String userId;

  /// `host.nick_name` (a card's `host.name`), else [BaiduLiveApi.anonymousName].
  final String nick;

  /// `video.title` (a card's `title`), else the nick.
  final String title;

  /// `host.image.image_33` (a card's `host.avatar`), when on an allowed host.
  final String avatar;

  /// `video.cover.cover_100`, else `vertical_cover` (a card's `cover`).
  final String cover;

  /// `category` (a card's `live_tag`, else `left_label.text`).
  final String category;

  /// `online_users` (a card's `audience_count`) while live.
  final int? currentViewers;

  /// `real_fans_num`, else `host.fans` (cards have none).
  final int? followers;

  /// The state shown (3.x): [BaiduLiveState.restricted] whenever the room
  /// is paid, forbidden or banned.
  final BaiduLiveState state;

  /// The state of `status` alone, restrictions aside.
  final BaiduLiveState status;

  /// `has_pay_service > 0`.
  final bool paid;

  /// `is_forbidden_url > 0` or `ban_status > 0`.
  final bool blocked;

  /// 3.x's variants while live, best first; empty otherwise.
  final List<BaiduLiveVariant> variants;

  /// This room with what [known] (an earlier card or detail of the same
  /// room) had where this one has nothing (3.x's `enrich`). Unlike 3.x, a
  /// known audience is kept only while the room is live: an ended room no
  /// longer shows the viewers of its card.
  BaiduLiveRoom enrich(BaiduLiveRoom known) => BaiduLiveRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    nick: nick == BaiduLiveApi.anonymousName ? known.nick : nick,
    title: title == BaiduLiveApi.anonymousName ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    category: category.isEmpty ? known.category : category,
    currentViewers: currentViewers ?? (state == BaiduLiveState.live ? known.currentViewers : null),
    followers: followers ?? known.followers,
    state: state,
    status: status,
    paid: paid,
    blocked: blocked,
    variants: variants,
  );

  /// Why this room cannot be played, or null: not live (`StreamUnavailable`,
  /// the platform's `status` decides), forbidden or banned
  /// (`StreamUnavailable`), paid (`NeedsLogin`), live without a stream 3.x
  /// or its fallback accepts (`StreamUnavailable`).
  SiteError? get unavailable {
    if (status != BaiduLiveState.live) return StreamUnavailable(_site, '$roomId is ${status.name}');
    if (blocked) return StreamUnavailable(_site, '$roomId is forbidden or banned');
    if (paid) return NeedsLogin(_site, '$roomId is a paid broadcast');
    if (variants.isEmpty) return StreamUnavailable(_site, '$roomId has no stream');
    return null;
  }
}

/// One page of the PC feed (3.x's `BaiduLivePage`).
@immutable
final class BaiduLivePage {
  /// Creates the page.
  new({
    required Iterable<BaiduLiveRoom> rooms,
    required Iterable<BaiduLiveCategory> categories,
    required this.sessionId,
    required this.refreshIndex,
    required this.hasMore,
  }) : rooms = List.unmodifiable(rooms),
       categories = List.unmodifiable(categories);

  /// The cards, each room once.
  final List<BaiduLiveRoom> rooms;

  /// The channels of the `tab` block (the first page asks for it); empty
  /// without it.
  final List<BaiduLiveCategory> categories;

  /// `session_id`: the feed session the next page continues.
  final String sessionId;

  /// `refresh_index`: the page's place in the session.
  final int refreshIndex;

  /// Whether the page was full (3.x: ten items or more).
  final bool hasMore;
}

/// Pure parsing of Baidu Live (百度直播) responses (3.x's `BaiduLiveApi`,
/// `BaiduLiveLink` and the room rules of `BaiduLiveSite`). Each function
/// takes the response text and status and returns 3.x's models or throws a
/// `SiteError`.
///
/// Anonymous and public, from the website's origin:
/// - the directory is the PC feed, a signed form POST to
///   `tiebac.baidu.com/livefeed/feed` (md5 of the sorted fields and a web
///   constant), paged by a feed session;
/// - a room is the command 371 of `mbd.baidu.com/searchbox` (a GET whose
///   `data` is JSON). A room id is one broadcast: the anchor's next
///   broadcast is another room.
abstract final class BaiduLiveApi {
  /// The website.
  static const String webOrigin = 'https://live.baidu.com';

  /// The PC feed.
  static final Uri feedUrl = Uri.https('tiebac.baidu.com', '/livefeed/feed');

  /// The host of the room command.
  static const String roomHost = 'mbd.baidu.com';

  /// The path of the room command.
  static const String roomPath = '/searchbox';

  /// 3.x's desktop Chrome UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's API request headers (`apiHeaders`).
  static const Map<String, String> apiHeaders = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': webOrigin,
    'referer': '$webOrigin/',
  };

  /// The headers of a feed POST: [apiHeaders] and the form's content type
  /// without a charset, as Dio sent it.
  static const Map<String, String> feedHeaders = {...apiHeaders, 'content-type': 'application/x-www-form-urlencoded'};

  /// Media request headers of room [roomId] (3.x's `mediaHeaders`, which
  /// 3.x wrote into every room's `httpHeaders` where no player read them):
  /// the FLV hosts (`hls-live.bdstatic.com`) refuse a request without a
  /// `live.baidu.com` Referer (403).
  static Map<String, String> mediaHeaders(String roomId) => {
    'user-agent': userAgent,
    'origin': webOrigin,
    'referer': roomUrl(roomId),
  };

  /// The largest answer read (3.x's `responseLimit`, 4 MiB).
  static const int responseLimit = 4 * 1024 * 1024;

  /// The web constant of the feed signature (3.x's `_feedSecret`).
  static const String _feedSecret = 'CtmXzYPtdE58nCCcvqM0ectyqW3N5rfY';

  /// 3.x's channels until the first feed page brings the platform's list
  /// (`fallbackCategories`).
  static const List<BaiduLiveCategory> fallbackCategories = [
    BaiduLiveCategory(id: 'rec', name: '推荐', channelId: 570),
    BaiduLiveCategory(id: 'shopping', name: '购物', channelId: 574),
    BaiduLiveCategory(id: 'finance', name: '财经', channelId: 611),
    BaiduLiveCategory(id: 'health', name: '健康', channelId: 612),
    BaiduLiveCategory(id: 'education', name: '教育', channelId: 613),
    BaiduLiveCategory(id: 'news', name: '新闻', channelId: 575),
    BaiduLiveCategory(id: 'leisure', name: '休闲', channelId: 616),
  ];

  /// Display name (3.x's zh.json `site_baidulive`), also the catalog's
  /// name and a room's area when it has none.
  static const String siteName = '百度直播';

  /// 3.x's zh.json `baidulive_directory_scope`, the directory notice's text.
  static const String directoryScope =
      '官网推荐与七个分类采用原生会话分页；精确房间号及 live.baidu.com 官方房间/分享链接可直接查询开播与未开播状态，昵称关键词搜索仍待公开网页合同。';

  /// The notice of every room (3.x's zh.json `baidulive_chat_notice`).
  static const String chatNotice = '百度远端聊天尚待接入；目录 audience_count 与房间 online_users 按当前观看人数展示，主播粉丝数单独展示。';

  /// The first notice line of a paid, forbidden or banned room (3.x's
  /// zh.json `baidulive_restricted_notice`).
  static const String restrictedNotice = '该百度直播受付费或访问范围限制，界面保持未知状态，不将其显示成未开播。';

  /// The nick (and title) of a room without one (3.x wrote it untranslated).
  static const String anonymousName = 'Baidu Live';

  /// The key of the directory notice.
  static const String directoryNoticeKey = 'baidulive_directory_scope';

  /// The last feed page asked for (3.x).
  static const int maxPage = 10000;

  /// Items of a full feed page (3.x: fewer ends the directory).
  static const int fullPage = 10;

  // Links and ids --------------------------------------------------------------

  static final RegExp _roomId = RegExp(r'^[1-9]\d{5,19}$');
  static final RegExp _shareCode = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _tab = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

  /// The room page (3.x's `BaiduLiveLink.watchUrl`, the room's `link`).
  static String roomUrl(String roomId) => '$webOrigin/m/room/$roomId';

  /// [raw] trimmed as a room id (6–20 digits, not starting with 0), or
  /// null.
  static String? normalizeRoomId(String raw) {
    final value = raw.trim();
    return _roomId.hasMatch(value) ? value : null;
  }

  /// A room id or a room link (3.x's `BaiduLiveLink.parseRoomId`, which
  /// search and every room call accepted); null for anything else.
  static String? parseRoomId(String raw) => normalizeRoomId(raw) ?? roomIdFromUrl(raw);

  /// The room of a room link (3.x's `BaiduLiveLink.parseRoomId` for URLs):
  /// https on `live.baidu.com` with the default port, without user info or
  /// fragment (http is refused, as 3.x's test pins), and
  /// - `/m/room/<id>` (empty segments ignored), or
  /// - `room_id=<id>` on the PC player `/m/media/pclive/pchome/live.html`
  ///   or on a share page `/m/media/multipage/liveshow/index/<code>` (the
  ///   room command's `share_url`).
  ///
  /// Null for anything else, a link that does not decode included (3.x
  /// threw).
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'live.baidu.com' ||
        (uri.hasPort && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    try {
      final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
      if (segments.length == 3 && segments[0] == 'm' && segments[1] == 'room' && _roomId.hasMatch(segments[2])) {
        return segments[2];
      }
      final roomId = uri.queryParameters['room_id']?.trim();
      if (roomId == null || !_roomId.hasMatch(roomId)) return null;
      if ('/${segments.join('/')}' == '/m/media/pclive/pchome/live.html') return roomId;
      if (segments.length == 6 &&
          segments.take(5).join('/') == 'm/media/multipage/liveshow/index' &&
          _shareCode.hasMatch(segments.last)) {
        return roomId;
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  // Requests ------------------------------------------------------------------

  /// 3.x's feed signature: md5 of the fields other than `sign`, sorted by
  /// name and joined as `k=v&k=v`, followed by `&` and the web constant.
  static String signFeed(Map<String, String> fields) {
    final keys = fields.keys.where((key) => key != 'sign').toList(growable: false)..sort();
    final canonical = keys.map((key) => '$key=${fields[key]}').join('&');
    return md5.convert(utf8.encode('$canonical&$_feedSecret')).toString();
  }

  /// The signed feed form of [channel] (3.x's `directory`, fields in its
  /// order): the first page asks for the banner, the tabs and the feed with
  /// a new session and `refresh_index` 1; a later page continues
  /// [sessionId] at [refreshIndex].
  static Map<String, String> feedForm({
    required BaiduLiveCategory channel,
    required bool first,
    required String deviceId,
    required DateTime now,
    required String sessionId,
    required int refreshIndex,
  }) {
    final form = <String, String>{
      'appname': 'pclive',
      'sid': '',
      'ua': '320_480_pc_1.0_0',
      'uid': deviceId,
      'timestamp': '${now.millisecondsSinceEpoch ~/ 1000}',
      'source': 'pclive',
      'resource': first ? 'banner,tab,feed' : 'feed',
      'scene': 'pc_channel',
      'session_id': first ? '' : sessionId,
      'refresh_type': first ? '0' : '1',
      'refresh_index': '$refreshIndex',
      'tab': channel.id,
      'channel_id': '${channel.channelId}',
    };
    form['sign'] = signFeed(form);
    return form;
  }

  /// The query of the room command 371 for [roomId] (3.x's `room`, in its
  /// order): `data` is JSON naming the room and [deviceId].
  static Map<String, String> roomQuery(String roomId, {required String deviceId, required DateTime now}) => {
    'cmd': '371',
    'action': 'star',
    'service': 'bdbox',
    'osname': 'pc',
    'data': jsonEncode({
      'data': {'room_id': roomId, 'device_id': deviceId, 'source_type': 0},
      'replay_slice': 0,
      'nid': '',
      'schemeParams': {
        'src_pre': 'pc',
        'src_suf': 'other',
        'bd_vid': '',
        'share_uid': '',
        'share_cuk': '',
        'share_ecid': '',
        'zb_tag': '',
        'shareTaskInfo': jsonEncode({'room_id': roomId}),
        'share_from': '',
        'ext_params': '',
        'nid': '',
      },
    }),
    'ua': '360_740_ANDROID_0',
    'bd_vid': '',
    'uid': deviceId,
    '_': '${now.millisecondsSinceEpoch}',
  };

  // Answers -------------------------------------------------------------------

  /// The failure of an answer's status (3.x's `_throwStatus`, typed):
  /// 400/422 a shape the platform refused, 401/403 refused, 451 region, 404
  /// and 410 missing, 429 throttled, 5xx and anything else (3xx included:
  /// redirects are not followed) a network failure. Null for 2xx.
  static SiteError? statusError(int status, String what) => switch (status) {
    >= 200 && < 300 => null,
    400 || 422 => ApiChanged(_site, '$what: HTTP $status'),
    401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
    451 => RegionBlocked(_site, '$what: HTTP 451'),
    404 || 410 => NotFound(_site, '$what: HTTP $status'),
    429 => RateLimited(_site, detail: '$what: HTTP 429'),
    _ => NetworkFailure(_site, '$what: HTTP $status'),
  };

  /// An answer as a JSON object whose `errno` is 0 (3.x: `service`
  /// otherwise; a number or a numeric string).
  static Map<String, Object?> _answer(String body, {required String what, required int status}) {
    if (statusError(status, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    final root = _map(decoded);
    if (root == null) throw ApiChanged(_site, '$what: not a JSON object');
    final errno = jsonInt(root['errno']);
    if (errno != 0) throw ApiChanged(_site, '$what: errno ${root['errno']} ${_text(root['errmsg'])}');
    return root;
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : null;

  static List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static String _firstText(Iterable<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static int? _positive(Object? value) {
    final number = jsonInt(value);
    return number != null && number > 0 ? number : null;
  }

  /// An image as 3.x accepted it: https on `bdstatic.com`, `bdimg.com` or
  /// `bcebos.com` (or a subdomain), without user info or fragment; else
  /// empty.
  static String image(Object? value) {
    final uri = Uri.tryParse(_text(value));
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) return '';
    final host = uri.host.toLowerCase();
    const roots = ['bdstatic.com', 'bdimg.com', 'bcebos.com'];
    return roots.any((root) => host == root || host.endsWith('.$root')) ? uri.toString() : '';
  }

  static String _firstImage(Iterable<Object?> values) {
    for (final value in values) {
      final url = image(value);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  // Directory -----------------------------------------------------------------

  /// A feed page (3.x's `parseDirectoryJson`): `errno` and the feed's
  /// `inner_errno` must be 0 and the session and refresh index given
  /// (`ApiChanged` otherwise); the cards are each room once; the channels
  /// are the `tab` block's; a page of [fullPage] items or more has more.
  ///
  /// Unlike 3.x, a `tab` block that failed (`inner_errno` not 0) leaves the
  /// channels empty (the site keeps the ones it has) instead of failing the
  /// page.
  static BaiduLivePage page(String body, {int status = 200}) {
    const what = 'feed';
    final data = _map(_answer(body, what: what, status: status)['data']) ?? const {};
    final feed = _map(data['feed']) ?? const {};
    final inner = jsonInt(feed['inner_errno']);
    if (inner != 0) throw ApiChanged(_site, '$what: inner_errno ${feed['inner_errno']}');
    final items = _list(feed['items']);
    final seen = <String>{};
    final rooms = [
      for (final item in items)
        if (card(_map(item) ?? const {}) case final room? when seen.add(room.roomId)) room,
    ];
    final sessionId = _text(feed['session_id']);
    final refreshIndex = jsonCount(feed['refresh_index']);
    if (sessionId.isEmpty || refreshIndex == null) {
      throw ApiChanged(_site, '$what: session ${feed['session_id']}, refresh_index ${feed['refresh_index']}');
    }
    return BaiduLivePage(
      rooms: rooms,
      categories: channels(data['tab']),
      sessionId: sessionId,
      refreshIndex: refreshIndex,
      hasMore: items.length >= fullPage,
    );
  }

  /// The channels of a feed's `tab` block (3.x's `parseCategoriesJson`):
  /// `type` (a lower-case id), `name` and a positive `channel_id`, each id
  /// once. Empty without the block or when it failed.
  static List<BaiduLiveCategory> channels(Object? value) {
    final tab = _map(value);
    if (tab == null || tab.isEmpty || jsonInt(tab['inner_errno']) != 0) return const [];
    final seen = <String>{};
    return List.unmodifiable([
      for (final value in _list(tab['items']))
        if (_map(value) case final item?)
          if ((_text(item['type']).toLowerCase(), _text(item['name']), _positive(item['channel_id']))
              case (final String id, final String name, final int channelId)
              when _tab.hasMatch(id) && name.isNotEmpty && seen.add(id))
            BaiduLiveCategory(id: id, name: name, channelId: channelId),
    ]);
  }

  /// A feed card (3.x's `_directoryCard`): `room_id`, the anchor
  /// `host.uk`/`name`/`avatar`, `title`, `cover`, `live_tag` (else
  /// `left_label.text`) and, while live, `audience_count`; `live_status` 1
  /// live, 0 preview, 2 offline, 3 replay, else unknown. Null without a
  /// room id.
  static BaiduLiveRoom? card(Map<String, Object?> item) {
    final roomId = parseRoomId(_text(item['room_id']));
    if (roomId == null) return null;
    final host = _map(item['host']) ?? const {};
    final state = switch (jsonInt(item['live_status'])) {
      1 => BaiduLiveState.live,
      0 => BaiduLiveState.preview,
      2 => BaiduLiveState.offline,
      3 => BaiduLiveState.replay,
      _ => BaiduLiveState.unknown,
    };
    final nick = _firstText([host['name']], fallback: anonymousName);
    return BaiduLiveRoom(
      roomId: roomId,
      userId: _text(host['uk']),
      nick: nick,
      title: _firstText([item['title'], nick], fallback: anonymousName),
      avatar: image(host['avatar']),
      cover: image(item['cover']),
      category: _firstText([item['live_tag'], (_map(item['left_label']) ?? const {})['text']]),
      currentViewers: state == BaiduLiveState.live ? jsonCount(item['audience_count']) : null,
      followers: null,
      state: state,
    );
  }

  /// 3.x's catalog: one category, the site, whose areas are [channels]
  /// (`official`, the feed tab as id).
  static List<LiveCategory> categories(List<BaiduLiveCategory> channels) => [
    LiveCategory(
      id: _site,
      name: siteName,
      children: [
        for (final channel in channels)
          LiveArea(
            platform: _site,
            areaType: 'official',
            areaId: channel.id,
            areaName: channel.name,
            typeName: siteName,
          ),
      ],
    ),
  ];

  // Rooms ---------------------------------------------------------------------

  /// Room [expectedRoomId] from the command 371 (3.x's `parseRoomJson`):
  /// - no command (`data.371` null), `error_code` 1 or 4, or neither `host`
  ///   nor `video` is `NotFound`; another `error_code` (or none) and a
  ///   `share_url` of another room are `ApiChanged`;
  /// - paid (`has_pay_service`), forbidden (`is_forbidden_url`) or banned
  ///   (`ban_status`) is restricted; else `status` 0 live, -1/1 preview,
  ///   2/20 offline, 3 replay (ended), anything else unknown;
  /// - the anchor `host.uk`, `nick_name` (else `name`), `image.image_33`;
  ///   `video.title` (else the nick), `cover.cover_100` (else
  ///   `vertical_cover`); `category`; while live `online_users`;
  ///   `real_fans_num` (else `host.fans`); while live the [variants].
  static BaiduLiveRoom room(String body, {required String expectedRoomId, int status = 200}) {
    const what = 'searchbox 371';
    final data = _map(_answer(body, what: what, status: status)['data']) ?? const {};
    final command = _map(data['371']) ?? const {};
    if (command.isEmpty) throw NotFound(_site, 'room $expectedRoomId');
    final error = jsonInt(command['error_code']);
    if (error == 1 || error == 4) throw NotFound(_site, 'room $expectedRoomId: error_code $error');
    if (error != 0) throw ApiChanged(_site, '$what: error_code ${command['error_code']}');
    final shared = parseRoomId(_text(command['share_url']));
    if (shared != null && shared != expectedRoomId) {
      throw ApiChanged(_site, '$what: share_url of room $shared for $expectedRoomId');
    }
    final host = _map(command['host']) ?? const {};
    final video = _map(command['video']) ?? const {};
    if (host.isEmpty && video.isEmpty) throw NotFound(_site, 'room $expectedRoomId: no host or video');
    final broadcast = switch (jsonInt(command['status'])) {
      0 => BaiduLiveState.live,
      -1 || 1 => BaiduLiveState.preview,
      2 || 20 => BaiduLiveState.offline,
      3 => BaiduLiveState.replay,
      _ => BaiduLiveState.unknown,
    };
    final paid = (jsonInt(command['has_pay_service']) ?? 0) > 0;
    final blocked = (jsonInt(command['is_forbidden_url']) ?? 0) > 0 || (jsonInt(command['ban_status']) ?? 0) > 0;
    final state = paid || blocked ? BaiduLiveState.restricted : broadcast;
    final nick = _firstText([host['nick_name'], host['name']], fallback: anonymousName);
    final cover = _map(video['cover']) ?? const {};
    final live = state == BaiduLiveState.live;
    return BaiduLiveRoom(
      roomId: expectedRoomId,
      userId: _text(host['uk']),
      nick: nick,
      title: _firstText([video['title'], nick], fallback: anonymousName),
      avatar: image((_map(host['image']) ?? const {})['image_33']),
      cover: _firstImage([cover['cover_100'], cover['vertical_cover']]),
      category: _text(command['category']),
      currentViewers: live ? jsonCount(command['online_users']) : null,
      followers: jsonCount(command['real_fans_num'] ?? host['fans']),
      state: state,
      status: broadcast,
      paid: paid,
      blocked: blocked,
      variants: live ? variants(video, expectedRoomId) : const [],
    );
  }

  /// The room 3.x showed for [room] (3.x's `BaiduLiveSite._room`): the
  /// anchor id (else the room id), the avatar (else the cover), the category
  /// (else [siteName]); live, offline (preview, offline and ended) or
  /// unknown (restricted, a state 3.x did not know); viewers while live; the
  /// restriction notice and [chatNotice]. [withData] keeps [room] for
  /// playback (room entry and recordings).
  ///
  /// Unlike 3.x, no `httpHeaders`: the media headers travel on the lines.
  static LiveRoom liveRoom(BaiduLiveRoom room, {bool withData = false}) {
    final online = room.currentViewers?.toString();
    return LiveRoom(
      platform: _site,
      roomId: room.roomId,
      userId: room.userId.isEmpty ? room.roomId : room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: room.category.isEmpty ? siteName : room.category,
      link: roomUrl(room.roomId),
      liveStatus: switch (room.state) {
        BaiduLiveState.live => LiveStatus.live,
        BaiduLiveState.preview || BaiduLiveState.offline || BaiduLiveState.replay => LiveStatus.offline,
        BaiduLiveState.restricted || BaiduLiveState.unknown => LiveStatus.unknown,
      },
      watching: online ?? '',
      onlineViewers: online ?? '',
      followers: room.followers?.toString() ?? '',
      audienceMetricType: online == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      notice: [if (room.state == BaiduLiveState.restricted) restrictedNotice, chatNotice].join('\n'),
      data: withData ? room : null,
    );
  }

  // Streams -------------------------------------------------------------------

  static bool _strictHost(String host) =>
      host == 'hls-live.bdstatic.com' || host == 'flv-live.bdstatic.com' || host.endsWith('.liveshow.bdstatic.com');

  static bool _fallbackHost(String host) => host.endsWith('.liveshow.lss-user.baidubce.com');

  /// [raw] as a stream URL of room [roomId] in [protocol] (`flv`, `hls`),
  /// as 3.x accepted it (`validateMediaUri`): on `hls-live.bdstatic.com`,
  /// `flv-live.bdstatic.com` or a `*.liveshow.bdstatic.com` host (http made
  /// https), https on the default port, without user info or fragment, a
  /// `/live/` path ending in `.flv` or `.m3u8` that names the room
  /// (`_<id>` followed by `-`, `.`, `/` or the end); else null.
  ///
  /// With [fallback] (only when 3.x found no URL at all) also the platform's
  /// current CDN, `*.liveshow.lss-user.baidubce.com`, kept as given: its
  /// https certificate does not match the host, so its http URLs stay http.
  static Uri? mediaUrl(String raw, {required String roomId, required String protocol, bool fallback = false}) {
    var uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final strict = _strictHost(host);
    final secondary = fallback && !strict && _fallbackHost(host);
    if (!strict && !secondary) return null;
    if (strict && uri.scheme == 'http') uri = uri.replace(scheme: 'https');
    final extension = protocol == 'hls' ? '.m3u8' : '.flv';
    final defaultPort = uri.scheme == 'http' ? 80 : 443;
    if (!(uri.scheme == 'https' || (secondary && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != defaultPort) ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(extension) ||
        !RegExp('(?:^|_)${RegExp.escape(roomId)}(?:[-./]|\$)').hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  /// 3.x's variants of a live room (`_detailVariants`), best first (height,
  /// then FLV before HLS), each URL once per variant:
  /// - each `url_clarity_list` entry at its `resolution`: `avc_flv` and
  ///   `flv` as FLV, `hls` as HLS;
  /// - each `url_list` entry at its `resolution`: every `urls[]` pair;
  /// - `live_hls_url` as HLS at the `url_list` resolution of the same file
  ///   name (else 0);
  /// - without clarity entries, `live_flv_url` and `live_flv_url_origin` as
  ///   the FLV source (0).
  ///
  /// Only the URLs [mediaUrl] accepts count. When none does (3.x then failed
  /// the room entry), the same fields are read again with the platform's
  /// current CDN accepted, plus `avc_url` and `play_url` as the FLV source
  /// and `live_hls_url_origin` as the HLS source (the archived v4's
  /// fields).
  static List<BaiduLiveVariant> variants(Map<String, Object?> video, String roomId) {
    final strict = _variants(video, roomId, fallback: false);
    return strict.isNotEmpty ? strict : _variants(video, roomId, fallback: true);
  }

  static List<BaiduLiveVariant> _variants(Map<String, Object?> video, String roomId, {required bool fallback}) {
    final grouped = <String, ({String protocol, int resolution, List<Uri> urls})>{};

    void add(Object? raw, String protocol, int resolution) {
      final uri = mediaUrl(_text(raw), roomId: roomId, protocol: protocol, fallback: fallback);
      if (uri == null) return;
      final bucket = grouped.putIfAbsent(
        '$protocol:$resolution:avc',
        () => (protocol: protocol, resolution: resolution, urls: <Uri>[]),
      );
      if (!bucket.urls.contains(uri)) bucket.urls.add(uri);
    }

    final clarity = _list(video['url_clarity_list']);
    for (final value in clarity) {
      final item = _map(value) ?? const {};
      final resolution = _positive(item['resolution']) ?? 0;
      final urls = _map(item['urls']) ?? const {};
      add(urls['avc_flv'], 'flv', resolution);
      add(urls['flv'], 'flv', resolution);
      add(urls['hls'], 'hls', resolution);
    }
    final urlList = _list(video['url_list']);
    for (final value in urlList) {
      final item = _map(value) ?? const {};
      final resolution = _positive(item['resolution']) ?? 0;
      for (final pair in _list(item['urls'])) {
        final urls = _map(pair) ?? const {};
        add(urls['flv'], 'flv', resolution);
        add(urls['hls'], 'hls', resolution);
      }
    }
    final hls = _text(video['live_hls_url']);
    add(hls, 'hls', _resolutionOf(hls, urlList));
    if (clarity.isEmpty) {
      add(video['live_flv_url'], 'flv', 0);
      add(video['live_flv_url_origin'], 'flv', 0);
    }
    if (fallback) {
      add(video['avc_url'], 'flv', 0);
      add(video['play_url'], 'flv', 0);
      add(video['live_hls_url_origin'], 'hls', 0);
    }
    final variants =
        [
          for (final MapEntry(:key, :value) in grouped.entries)
            BaiduLiveVariant(
              id: key,
              protocol: value.protocol,
              resolution: value.resolution,
              codec: 'avc',
              urls: value.urls,
            ),
        ]..sort((left, right) {
          final resolution = right.resolution.compareTo(left.resolution);
          return resolution != 0 ? resolution : left.protocol.compareTo(right.protocol);
        });
    return List.unmodifiable(variants);
  }

  /// The `url_list` resolution whose HLS URL has [raw]'s file name (3.x's
  /// `_resolutionFor`); 0 when none.
  static int _resolutionOf(String raw, List<Object?> urlList) {
    final name = _fileName(raw);
    if (name.isEmpty) return 0;
    for (final value in urlList) {
      final item = _map(value) ?? const {};
      final resolution = _positive(item['resolution']);
      if (resolution == null) continue;
      for (final pair in _list(item['urls'])) {
        if (_fileName(_text((_map(pair) ?? const {})['hls'])) == name) return resolution;
      }
    }
    return 0;
  }

  /// The last path segment of [raw]; empty when there is none or it does
  /// not decode.
  static String _fileName(String raw) {
    try {
      return Uri.tryParse(raw)?.pathSegments.lastOrNull ?? '';
    } on FormatException {
      return '';
    }
  }

  /// A variant's name (3.x's zh.json `baidulive_quality_resolution` and
  /// `baidulive_quality_source`): `HLS 720P · AVC`, `FLV 原始线路 · AVC`.
  static String qualityName(BaiduLiveVariant variant) {
    final protocol = variant.protocol.toUpperCase();
    final codec = variant.codec.toUpperCase();
    return variant.resolution > 0 ? '$protocol ${variant.resolution}P · $codec' : '$protocol 原始线路 · $codec';
  }

  /// 3.x's qualities of [room]: one per variant, id the variant's, ranked
  /// height × 10 + 2 for FLV and + 1 for HLS. A room that cannot be played
  /// says why (see [BaiduLiveRoom.unavailable]).
  static List<LivePlayQuality> qualities(BaiduLiveRoom room) {
    if (room.unavailable case final error?) throw error;
    return List.unmodifiable([
      for (final variant in room.variants)
        LivePlayQuality(
          quality: qualityName(variant),
          id: variant.id,
          sort: variant.resolution * 10 + (variant.protocol == 'hls' ? 1 : 2),
        ),
    ]);
  }

  /// The lines of [variant] of room [roomId]: its URLs in order, with the
  /// media headers, the format, AVC and the host as line id. The URLs carry
  /// no signature or expiry, so no lease.
  static List<LivePlayLine> lines(BaiduLiveVariant variant, String roomId) {
    final headers = mediaHeaders(roomId);
    return List.unmodifiable([
      for (final url in variant.urls)
        LivePlayLine(
          '$url',
          headers: headers,
          format: variant.protocol == 'hls' ? StreamFormat.hls : StreamFormat.flv,
          codec: variant.codec,
          lineId: url.host,
        ),
    ]);
  }

  /// The lines of [quality] (by its id) in [room], applied as asked; a
  /// quality the room no longer offers is `StreamUnavailable`, and a room
  /// that cannot be played says why.
  static LivePlayUrlResolution resolution(BaiduLiveRoom room, LivePlayQuality quality) {
    if (room.unavailable case final error?) throw error;
    final wanted = '${quality.selectionId}';
    final variant = room.variants.where((variant) => variant.id == wanted).firstOrNull;
    if (variant == null) throw StreamUnavailable(_site, 'quality $wanted is not offered');
    return LivePlayUrlResolution.lines(lines(variant, room.roomId), appliedQualityData: variant.id);
  }
}
