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

/// A broadcast's state, from the room command's `status` or a card's
/// `live_status`. A paid, forbidden or banned broadcast keeps its state
/// (30-5): the restriction is told apart ([BaiduLiveRoom.restriction]).
enum BaiduLiveState {
  /// Broadcasting (`status` 0, a card's `live_status` 1).
  live,

  /// Announced (`status` -1 or 1, `live_status` 0).
  preview,

  /// Not broadcasting (`status` 2 or 20, `live_status` 2).
  offline,

  /// Ended (`status` 3, `live_status` 3): a room is one broadcast, and an
  /// ended one plays its recording when the platform gives one (30-4).
  replay,

  /// A state 3.x did not know.
  unknown,
}

/// One URL of a quality and its container.
typedef BaiduLiveSource = ({Uri url, StreamFormat format});

/// One quality of a room: a tier (the source, a height, or a recording) in
/// one codec, with its URLs in line order (30-1, 30-2, 30-4).
@immutable
final class BaiduLiveVariant {
  /// Creates the variant.
  new({
    required this.id,
    required this.name,
    required this.sort,
    required this.codec,
    required Iterable<BaiduLiveSource> sources,
  }) : sources = List.unmodifiable(sources);

  /// The quality id: [BaiduLiveApi.sourceQualityId] or `<height>p`, with
  /// `:hevc` for H.265; a recording's is `replay`, `replay:<key>` or
  /// `replay:<key>:hevc`.
  final String id;

  /// The quality's name (`原画`, `720p`, `原画 · H.265`, `标清`).
  final String name;

  /// Rank among the room's qualities: higher is better (see
  /// [BaiduLiveApi.qualities]).
  final int sort;

  /// `avc` or `hevc`; null when the platform does not tell (the source of a
  /// room with a clarity list, see [BaiduLiveApi.liveVariants]).
  final String? codec;

  /// The URLs, one per line, in line order.
  final List<BaiduLiveSource> sources;
}

/// What the danmaku connection (M5.26, 30-3) needs of a live broadcast: the
/// message lists the room command 371 names. 3.x had no Baidu Live chat
/// (`EmptyDanmaku`).
///
/// Each list is an HLS-style playlist on `liveshowstatic.baidu.com` whose
/// segments are JSON message batches: [chatList] carries chat, the online
/// count and notices, [reliableList] gifts and notices, [hostList] (404
/// when recorded) the host's. The playlist URLs are signed (a
/// `bce-auth-v1` authorization, recorded valid 182.5 days, [expiresAt]);
/// room entry hands them over without a request, and a later connection
/// after they expired needs a new room command (the room detail).
@immutable
final class BaiduLiveDanmakuArgs {
  /// Creates the arguments.
  const new({
    required this.roomId,
    required this.chatList,
    this.reliableList,
    this.hostList,
    this.pullInterval = BaiduLiveApi.defaultPullInterval,
    this.expiresAt,
  });

  /// The room (one broadcast); messages naming another room are dropped.
  final String roomId;

  /// `chat_msg_hls_url` (else `video.msg_hls_url`, the same list).
  final Uri chatList;

  /// `reliable_msg_hls_url`, when given.
  final Uri? reliableList;

  /// `host_msg_hls_url`, when given.
  final Uri? hostList;

  /// `msg_hls_pull_internal_in_second`: the wait between two polls, 1–10 s
  /// ([BaiduLiveApi.defaultPullInterval] when missing).
  final Duration pullInterval;

  /// When the signature of [chatList] runs out (its `bce-auth-v1` time plus
  /// validity), or null when it does not say.
  final DateTime? expiresAt;

  /// Whether [expiresAt] has passed at [now].
  bool isExpiredAt(DateTime now) => switch (expiresAt) {
    final DateTime expiry => !now.isBefore(expiry),
    null => false,
  };

  @override
  bool operator ==(Object other) =>
      other is BaiduLiveDanmakuArgs &&
      other.roomId == roomId &&
      other.chatList == chatList &&
      other.reliableList == reliableList &&
      other.hostList == hostList &&
      other.pullInterval == pullInterval &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(roomId, chatList, reliableList, hostList, pullInterval, expiresAt);

  /// The room only: the list URLs carry signatures.
  @override
  String toString() => 'BaiduLiveDanmakuArgs($roomId)';
}

/// A room as read from a feed card or from the room command 371 (3.x's
/// `BaiduLiveRoom`). Room entry keeps it in `LiveRoom.data` for playback,
/// as 3.x did; a room is one broadcast, so its id is the only platform id
/// needed.
@immutable
final class BaiduLiveRoom {
  /// Creates the room.
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
    this.introduction = '',
    this.startedAt,
    this.restriction,
    this.paid = false,
    this.blocked = false,
    Iterable<BaiduLiveVariant> variants = const [],
    this.danmaku,
  }) : variants = List.unmodifiable(variants);

  /// The room id as asked for (a card's `room_id`).
  final String roomId;

  /// `host.uk`, the anchor; empty when not given.
  final String userId;

  /// `host.nick_name` (a card's `host.name`); empty when not given (30-10:
  /// no stand-in name).
  final String nick;

  /// `video.title` (a card's `title`), else the nick; empty when neither is
  /// given.
  final String title;

  /// `host.image.image_33` (a card's `host.avatar`), when on an allowed host.
  final String avatar;

  /// `video.cover.cover_100`, else `vertical_cover` (a card's `cover`).
  final String cover;

  /// `category` (a card's `live_tag`, else `left_label.text`).
  final String category;

  /// `video.description`, the broadcast's introduction (30-7); cards have
  /// none.
  final String introduction;

  /// `online_users` (a card's `audience_count`) while live.
  final int? currentViewers;

  /// `real_fans_num`, else `host.fans` (cards have none).
  final int? followers;

  /// The broadcast's state (30-4, 30-5).
  final BaiduLiveState state;

  /// When the broadcast started (the room command's `create_time`), while
  /// live; cards have none.
  final DateTime? startedAt;

  /// The restriction of a live or ended broadcast (30-4, 30-5): blocked is
  /// [LiveRestriction.unplayable], paid [LiveRestriction.paid], an ended
  /// broadcast without a recording (or a live one without a stream)
  /// [LiveRestriction.unplayable], else [LiveRestriction.none]; null where
  /// the answer does not tell (a state that is not live or ended, a card
  /// without `has_pay_service`).
  final LiveRestriction? restriction;

  /// `has_pay_service > 0`.
  final bool paid;

  /// `is_forbidden_url > 0` or `ban_status > 0` (the room command only).
  final bool blocked;

  /// The qualities, best first: the live stream's while live, the
  /// recording's when ended; empty otherwise and on cards.
  final List<BaiduLiveVariant> variants;

  /// The chat's message lists while live (M5.26); null otherwise and on
  /// cards.
  final BaiduLiveDanmakuArgs? danmaku;

  /// This room with what [known] (an earlier card or detail of the same
  /// room) had where this one has nothing (3.x's `enrich`). Unlike 3.x, a
  /// known audience is kept only while the room is live: an ended room no
  /// longer shows the viewers of its card.
  BaiduLiveRoom enrich(BaiduLiveRoom known) => BaiduLiveRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    nick: nick.isEmpty ? known.nick : nick,
    title: title.isEmpty ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    category: category.isEmpty ? known.category : category,
    introduction: introduction.isEmpty ? known.introduction : introduction,
    currentViewers: currentViewers ?? (state == BaiduLiveState.live ? known.currentViewers : null),
    followers: followers ?? known.followers,
    state: state,
    startedAt: startedAt,
    restriction: restriction,
    paid: paid,
    blocked: blocked,
    variants: variants,
    danmaku: danmaku,
  );

  /// Why this room cannot be played, or null. Not live and not ended, or an
  /// ended broadcast without a recording, is `StreamUnavailable`; so is a
  /// restricted broadcast, with the kind in the message (30-5: blocked
  /// `unplayable`, then `paid`; Baidu Live has no sign-in here), and a live
  /// one without a stream this client accepts.
  SiteError? get unavailable {
    if (state != BaiduLiveState.live && state != BaiduLiveState.replay) {
      return StreamUnavailable(_site, '$roomId is ${state.name}');
    }
    if (blocked) return StreamUnavailable(_site, '$roomId is restricted (unplayable: forbidden or banned)');
    if (paid) return StreamUnavailable(_site, '$roomId is restricted (paid)');
    if (variants.isEmpty) {
      return StreamUnavailable(
        _site,
        state == BaiduLiveState.replay ? '$roomId ended without a recording (unplayable)' : '$roomId has no stream',
      );
    }
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
/// takes the response text and status and returns the models or throws a
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

  /// The directory notice's Chinese text (the key
  /// [directoryNoticeKey], 3.x's `baidulive_directory_scope`), written for
  /// users (30-10); the UI translates the key (M13).
  static const String directoryScope = '这里是百度直播官网的推荐和各个频道，往下翻会继续加载。搜索只能输入房间号，或粘贴百度直播的直播间、分享链接，还不能按主播名字搜索。';

  /// The notice of every room (3.x's zh.json key `baidulive_chat_notice`),
  /// written for users (30-10). 30-10's text began with
  /// "这里暂时看不到百度直播间的聊天。"; chat is shown since M5.26.
  static const String chatNotice = '人数是正在观看的人数，主播的粉丝数另外显示。';

  /// 3.x's room notice, kept for the parity tests and the 3.x migration.
  static const String legacyChatNotice = '百度远端聊天尚待接入；目录 audience_count 与房间 online_users 按当前观看人数展示，主播粉丝数单独展示。';

  /// The first notice line of a paid, forbidden or banned room (3.x's
  /// zh.json key `baidulive_restricted_notice`), written for users (30-10):
  /// such a room is shown as its state with the restriction marked (30-5).
  static const String restrictedNotice = '这场直播需要付费观看或受到平台限制，暂时不能在这里播放。';

  /// The key of the directory notice.
  static const String directoryNoticeKey = 'baidulive_directory_scope';

  /// The last feed page asked for (3.x).
  static const int maxPage = 10000;

  /// Items of a full feed page (3.x: fewer ends the directory).
  static const int fullPage = 10;

  /// The host of the chat's message lists (M5.26).
  static const String messageListHost = 'liveshowstatic.baidu.com';

  /// The wait between two polls of the message lists when the room command
  /// names none (`msg_hls_pull_internal_in_second` was 5 in every recorded
  /// answer).
  static const Duration defaultPullInterval = Duration(seconds: 5);

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
  /// https or http (30-8; 3.x took https only) on `live.baidu.com` with the
  /// scheme's default port, without user info or fragment, and
  /// - `/m/room/<id>` (empty segments ignored), or
  /// - `room_id=<id>` on the PC player `/m/media/pclive/pchome/live.html`
  ///   or on a share page `/m/media/multipage/liveshow/index/<code>` (the
  ///   room command's `share_url`).
  ///
  /// Null for anything else, a link that does not decode included (3.x
  /// threw).
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    final defaultPort = switch (scheme) {
      'https' => 443,
      'http' => 80,
      _ => null,
    };
    if (defaultPort == null ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'live.baidu.com' ||
        (uri.hasPort && uri.port != defaultPort) ||
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

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
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

  /// A broadcast start from the room command's `create_time` (Unix
  /// seconds); null unless positive whole seconds of at most ten digits.
  static DateTime? startedAt(Object? value) {
    final seconds = jsonInt(value);
    if (seconds == null || seconds <= 0 || seconds > 9999999999) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
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
  /// live, 0 preview, 2 offline, 3 ended (a replay, 30-4), else unknown.
  /// The restriction (30-4, 30-5): paid by `has_pay_service`; an ended card
  /// without a recording in its `play_url` is `unplayable`; a live card
  /// without `has_pay_service` does not tell. Null without a room id.
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
    final nick = _text(host['name']);
    final payFlag = jsonInt(item['has_pay_service']);
    final paid = (payFlag ?? 0) > 0;
    return BaiduLiveRoom(
      roomId: roomId,
      userId: _text(host['uk']),
      nick: nick,
      title: _firstText([item['title'], nick]),
      avatar: image(host['avatar']),
      cover: image(item['cover']),
      category: _firstText([item['live_tag'], (_map(item['left_label']) ?? const {})['text']]),
      currentViewers: state == BaiduLiveState.live ? jsonCount(item['audience_count']) : null,
      followers: null,
      state: state,
      paid: paid,
      restriction: switch (state) {
        BaiduLiveState.live || BaiduLiveState.replay when paid => LiveRestriction.paid,
        BaiduLiveState.live => payFlag == null ? null : LiveRestriction.none,
        BaiduLiveState.replay =>
          replayUrl(item['play_url'], roomId) == null ? LiveRestriction.unplayable : LiveRestriction.none,
        _ => null,
      },
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
  /// - `status` 0 live, -1/1 preview, 2/20 offline, 3 ended (a replay,
  ///   30-4), anything else unknown; paid (`has_pay_service`), forbidden
  ///   (`is_forbidden_url`) and banned (`ban_status`) keep the state and set
  ///   the [BaiduLiveRoom.restriction] (30-5);
  /// - the anchor `host.uk`, `nick_name` (else `name`), `image.image_33`;
  ///   `video.title` (else the nick), `cover.cover_100` (else
  ///   `vertical_cover`), `description` (30-7); `category`; while live
  ///   `online_users` and `create_time` (the start); `real_fans_num` (else
  ///   `host.fans`); the [liveVariants] while live, the [replayVariants]
  ///   when ended; the chat's [danmakuArgs] while live (M5.26).
  static BaiduLiveRoom room(String body, {required String expectedRoomId, int status = 200}) {
    const what = 'searchbox 371';
    final data = _map(_answer(body, what: what, status: status)['data']) ?? const {};
    final command = _map(data['371']) ?? const {};
    if (command.isEmpty) throw NotFound(_site, 'room $expectedRoomId');
    final error = jsonInt(command['error_code']);
    // An announced broadcast answers in another shape: no `error_code`, the
    // `template` "preview", its fields at the top (3.x refused it).
    final preview = command['error_code'] == null && _text(command['template']) == 'preview';
    if (error == 1 || error == 4) throw NotFound(_site, 'room $expectedRoomId: error_code $error');
    if (error != 0 && !preview) throw ApiChanged(_site, '$what: error_code ${command['error_code']}');
    final shared = parseRoomId(_text(command['share_url']));
    if (shared != null && shared != expectedRoomId) {
      throw ApiChanged(_site, '$what: share_url of room $shared for $expectedRoomId');
    }
    final host = _map(command['host']) ?? const {};
    final video = _map(command['video']) ?? const {};
    if (host.isEmpty && video.isEmpty) throw NotFound(_site, 'room $expectedRoomId: no host or video');
    final top = preview ? command : const <String, Object?>{};
    final state = switch (jsonInt(command['status'])) {
      0 => BaiduLiveState.live,
      -1 || 1 => BaiduLiveState.preview,
      2 || 20 => BaiduLiveState.offline,
      3 => BaiduLiveState.replay,
      _ => BaiduLiveState.unknown,
    };
    final paid = (jsonInt(command['has_pay_service']) ?? 0) > 0;
    final blocked = (jsonInt(command['is_forbidden_url']) ?? 0) > 0 || (jsonInt(command['ban_status']) ?? 0) > 0;
    final nick = _firstText([host['nick_name'], host['name'], top['source']]);
    final cover = _map(video['cover']) ?? const {};
    final live = state == BaiduLiveState.live;
    final variants = switch (state) {
      BaiduLiveState.live => liveVariants(video, expectedRoomId),
      BaiduLiveState.replay => replayVariants(command['replay_list'], expectedRoomId),
      _ => const <BaiduLiveVariant>[],
    };
    return BaiduLiveRoom(
      roomId: expectedRoomId,
      userId: _firstText([host['uk'], top['uk']]),
      nick: nick,
      title: _firstText([video['title'], top['title'], nick]),
      avatar: _firstImage([(_map(host['image']) ?? const {})['image_33'], top['avatar']]),
      cover: _firstImage([cover['cover_100'], cover['vertical_cover'], top['cover'], top['vertical_cover']]),
      category: _text(command['category']),
      introduction: _firstText([video['description'], top['description']]),
      currentViewers: live ? jsonCount(command['online_users']) : null,
      followers: jsonCount(command['real_fans_num'] ?? host['fans']),
      state: state,
      startedAt: live ? startedAt(command['create_time']) : null,
      restriction: switch (state) {
        BaiduLiveState.live || BaiduLiveState.replay when blocked => LiveRestriction.unplayable,
        BaiduLiveState.live || BaiduLiveState.replay when paid => LiveRestriction.paid,
        BaiduLiveState.live || BaiduLiveState.replay when variants.isEmpty => LiveRestriction.unplayable,
        BaiduLiveState.live || BaiduLiveState.replay => LiveRestriction.none,
        _ => null,
      },
      paid: paid,
      blocked: blocked,
      variants: variants,
      danmaku: live ? danmakuArgs(command, expectedRoomId) : null,
    );
  }

  /// A message list of the room command (M5.26): an http or https URL on
  /// [messageListHost] whose path ends in `.m3u8`; null otherwise. http
  /// becomes https, as the room page rewrites it to its own protocol
  /// (pchome.live.fcb2dc0e.js); the signed query is kept as given.
  static Uri? messageList(Object? value) {
    final uri = Uri.tryParse(_text(value));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    if (uri.host.toLowerCase() != messageListHost || uri.userInfo.isNotEmpty || uri.hasFragment) return null;
    if (!uri.path.endsWith('.m3u8')) return null;
    return uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
  }

  /// When the signature of [list] runs out: its `authorization`
  /// (`bce-auth-v1/<key>/<UTC time>/<seconds>/<headers>/<signature>`) time
  /// plus its validity; null when the URL has no such signature.
  static DateTime? signatureExpiry(Uri list) {
    const name = 'authorization=';
    final field = list.query.split('&').where((field) => field.startsWith(name)).firstOrNull ?? '';
    // Recorded answers wrote the separators both plain and escaped.
    final parts = field
        .substring(field.isEmpty ? 0 : name.length)
        .replaceAll(RegExp('%2F', caseSensitive: false), '/')
        .replaceAll(RegExp('%3A', caseSensitive: false), ':')
        .split('/');
    if (parts.length < 4 || parts[0] != 'bce-auth-v1') return null;
    final time = parts[2];
    final signed = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$').hasMatch(time) ? DateTime.tryParse(time) : null;
    final seconds = RegExp(r'^\d{1,10}$').hasMatch(parts[3]) ? int.parse(parts[3]) : null;
    // DateTime rolls a 13th month or a 45th day over; such a time is no time.
    if (signed == null || signed.toIso8601String().substring(0, 19) != time.substring(0, 19)) return null;
    return seconds == null || seconds == 0 ? null : signed.add(Duration(seconds: seconds));
  }

  /// The chat arguments of a live room command (M5.26): the chat list
  /// (`chat_msg_hls_url`, else `video.msg_hls_url`), the reliable and host
  /// lists when valid ([messageList]), the poll interval
  /// (`msg_hls_pull_internal_in_second`, else the video's; a positive
  /// number of seconds within 1–10, else [defaultPullInterval]) and when
  /// the chat list's signature runs out ([signatureExpiry]). Null without a
  /// valid chat list.
  static BaiduLiveDanmakuArgs? danmakuArgs(Map<String, Object?> command, String roomId) {
    final video = _map(command['video']) ?? const {};
    final chat = messageList(command['chat_msg_hls_url']) ?? messageList(video['msg_hls_url']);
    if (chat == null) return null;
    final seconds = jsonInt(command['msg_hls_pull_internal_in_second'] ?? video['msg_hls_pull_internal_in_second']);
    return BaiduLiveDanmakuArgs(
      roomId: roomId,
      chatList: chat,
      reliableList: messageList(command['reliable_msg_hls_url']),
      hostList: messageList(command['host_msg_hls_url']),
      pullInterval: seconds != null && seconds > 0 ? Duration(seconds: seconds.clamp(1, 10)) : defaultPullInterval,
      expiresAt: signatureExpiry(chat),
    );
  }

  /// The room shown for [room] (3.x's `BaiduLiveSite._room`): the anchor id
  /// (else the room id), the avatar (else the cover), the category (else
  /// [siteName]); live, offline (preview and offline), replay (ended, 30-4)
  /// or unknown; the start and the restriction; the introduction (30-7);
  /// viewers while live; the restriction notice (paid or blocked) and
  /// [chatNotice]. [withData] keeps [room] for playback (room entry and
  /// recordings); [withChat] (default [withData]) keeps its chat arguments
  /// ([BaiduLiveRoom.danmaku]) for the danmaku connection (M5.26), which a
  /// refresh also brings so that a connection whose signature expired
  /// reconnects with fresh lists (E05.4).
  ///
  /// Unlike 3.x, no `httpHeaders`: the media headers travel on the lines;
  /// and no stand-in name or title (30-10): the UI shows the platform's
  /// name for an empty nick.
  static LiveRoom liveRoom(BaiduLiveRoom room, {bool withData = false, bool? withChat}) {
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
        BaiduLiveState.preview || BaiduLiveState.offline => LiveStatus.offline,
        BaiduLiveState.replay => LiveStatus.replay,
        BaiduLiveState.unknown => LiveStatus.unknown,
      },
      startedAt: room.startedAt,
      restriction: room.restriction,
      watching: online ?? '',
      onlineViewers: online ?? '',
      followers: room.followers?.toString() ?? '',
      audienceMetricType: online == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      introduction: room.introduction.isEmpty ? null : room.introduction,
      notice: [if (room.paid || room.blocked) restrictedNotice, chatNotice].join('\n'),
      data: withData ? room : null,
      danmakuData: (withChat ?? withData) ? room.danmaku : null,
    );
  }

  // Streams -------------------------------------------------------------------

  /// The source quality's id (30-1).
  static const String sourceQualityId = 'source';

  /// The source quality's name (30-1, UPGRADES "画质命名").
  static const String sourceQualityName = '原画';

  /// The suffix of an H.265 quality's name (30-2).
  static const String hevcSuffix = ' · H.265';

  /// The id and name of an ended broadcast's recording when the platform
  /// lists no clarity for it (30-4).
  static const String replayQualityId = 'replay';

  /// See [replayQualityId].
  static const String replayQualityName = '回放';

  /// 3.x's quality ids (`<flv|hls>:<height>:avc`, 0 the source) of the
  /// heights 3.x produced from the recorded answers, and their current ids
  /// (30-1): each 3.x quality is now the lines of one tier.
  /// [qualityIdFromLegacy] maps any height.
  static const Map<String, String> legacyQualityIds = {
    'flv:0:avc': sourceQualityId,
    'hls:0:avc': sourceQualityId,
    'flv:1080:avc': '1080p',
    'hls:1080:avc': '1080p',
    'flv:720:avc': '720p',
    'hls:720:avc': '720p',
    'flv:540:avc': '540p',
    'hls:540:avc': '540p',
    'flv:480:avc': '480p',
    'hls:480:avc': '480p',
  };

  static final RegExp _legacyQualityId = RegExp(r'^(?:flv|hls):(\d{1,5}):avc$', caseSensitive: false);

  /// The quality id for a stored one (30-1): 3.x's `<flv|hls>:<height>:avc`
  /// is the tier's id ([sourceQualityId] for height 0, else
  /// `<height>p`); M9 migrates a stored quality with it once. Any other id
  /// is kept (trimmed); applying it twice changes nothing.
  static String qualityIdFromLegacy(String id) {
    final value = id.trim();
    final match = _legacyQualityId.firstMatch(value);
    return match == null ? value : _tierId(int.parse(match[1]!));
  }

  static String _tierId(int height) => height == 0 ? sourceQualityId : '${height}p';

  static String _tierName(int height) => height == 0 ? sourceQualityName : '${height}p';

  static bool _primaryHost(String host) =>
      host == 'hls-live.bdstatic.com' || host == 'flv-live.bdstatic.com' || host.endsWith('.liveshow.bdstatic.com');

  static bool _backupHost(String host) => host.endsWith('.liveshow.lss-user.baidubce.com');

  /// [raw] as a live stream URL of room [roomId] in [protocol] (`flv`,
  /// `hls`), or null. Accepted:
  /// - 3.x's hosts, `hls-live.bdstatic.com` and `*.liveshow.bdstatic.com`
  ///   as https (http made https, as 3.x did), and `flv-live.bdstatic.com`
  ///   as http (30-9: its https certificate does not match the host);
  /// - the platform's current CDN `*.liveshow.lss-user.baidubce.com`, kept
  ///   as given (its https certificate chain does not verify), for the
  ///   backup lines of a tier (30-1);
  ///
  /// on the scheme's default port, without user info or fragment, a
  /// `/live/` path ending in `.flv` or `.m3u8` whose stream names the room
  /// (`_<id>` followed by `-`, `_`, `.`, `/` or the end).
  static Uri? mediaUrl(String raw, {required String roomId, required String protocol}) {
    var uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final primary = _primaryHost(host);
    if (!primary && !_backupHost(host)) return null;
    // A port the scheme does not default to stays and is refused below.
    if (host == 'flv-live.bdstatic.com') {
      if (uri.scheme == 'https' && !uri.hasPort) uri = uri.replace(scheme: 'http');
    } else if (primary && uri.scheme == 'http' && !uri.hasPort) {
      uri = uri.replace(scheme: 'https');
    }
    final extension = protocol == 'hls' ? '.m3u8' : '.flv';
    if (!(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasPort ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(extension) ||
        !RegExp('(?:^|_)${RegExp.escape(roomId)}(?:[-_./]|\$)').hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  /// The stream of a media URL: the file name without its extension, or
  /// the directory of an HLS `playlist.m3u8`; empty when there is none.
  static String _streamName(Uri url) {
    final List<String> segments;
    try {
      segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return '';
    }
    if (segments.isEmpty) return '';
    var name = segments.last;
    if (name.toLowerCase() == 'playlist.m3u8' && segments.length > 1) return segments[segments.length - 2];
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name;
  }

  /// The qualities of a live room (30-1, 30-2), best first: 原画 (the
  /// source) and one per height (720p, 480p; 1080p and 540p where the room
  /// has a clarity list), each in one codec; an H.265 one is separate and
  /// named with [hevcSuffix].
  ///
  /// The URLs are placed by their stream (the file name): the source is the
  /// stream named `…_<room id>`; a height is the one of the `url_list` or
  /// `url_clarity_list` entry that lists the stream. Read:
  /// - `url_clarity_list[].urls`: `avc_flv`, `flv` (FLV) and `hls` as AVC,
  ///   `hevc_flv` as H.265, at the entry's `resolution`;
  /// - `url_list[].urls[]`: `flv` and `hls` as AVC at the entry's
  ///   `resolution` (the platform's two CDNs);
  /// - `live_flv_url`, `avc_url`, `play_url` (FLV), `live_hls_url` and
  ///   `avc_hls_url` (HLS) as AVC, placed by their stream;
  /// - `live_flv_url_origin` (FLV) and `live_hls_url_origin` (HLS), the
  ///   source, and `hevc_url` (FLV) as the source in H.265.
  ///
  /// The source's codec: AVC when one of the AVC fields names the source
  /// stream; H.265 when the room has no clarity list and the AVC fields name
  /// a transcode instead (the platform then gives an AVC 720p for an H.265
  /// original, 2026-09-29 survey); not known otherwise (codec null).
  ///
  /// A tier's lines: 3.x's hosts first (the lines 3.x played), then the
  /// platform's current CDN as backups (30-1); FLV before HLS within each;
  /// a stream once per host. A URL [mediaUrl] refuses, or whose stream has
  /// no tier, is left out: it costs one line, not the room.
  static List<BaiduLiveVariant> liveVariants(Map<String, Object?> video, String roomId) {
    final heights = <String, int>{};
    final sourceName = RegExp('(?:^|_)${RegExp.escape(roomId)}\$');

    Uri? accept(Object? raw, String protocol) => mediaUrl(_text(raw), roomId: roomId, protocol: protocol);

    final clarity = _list(video['url_clarity_list']);
    final listed = <({int height, String? codec, String protocol, Uri url})>[];
    for (final value in clarity) {
      final item = _map(value) ?? const {};
      final height = _positive(item['resolution']);
      if (height == null) continue;
      final urls = _map(item['urls']) ?? const {};
      for (final (key, protocol, codec) in const [
        ('avc_flv', 'flv', 'avc'),
        ('flv', 'flv', 'avc'),
        ('hls', 'hls', 'avc'),
        ('hevc_flv', 'flv', 'hevc'),
      ]) {
        if (accept(urls[key], protocol) case final url?) {
          listed.add((height: height, codec: codec, protocol: protocol, url: url));
        }
      }
    }
    for (final value in _list(video['url_list'])) {
      final item = _map(value) ?? const {};
      final height = _positive(item['resolution']);
      if (height == null) continue;
      for (final pair in _list(item['urls'])) {
        final urls = _map(pair) ?? const {};
        for (final protocol in const ['flv', 'hls']) {
          if (accept(urls[protocol], protocol) case final url?) {
            listed.add((height: height, codec: 'avc', protocol: protocol, url: url));
          }
        }
      }
    }
    for (final entry in listed) {
      if (entry.codec == 'avc') heights.putIfAbsent(_streamName(entry.url), () => entry.height);
    }

    // The AVC fields, placed by their stream.
    var avcSource = false;
    var avcTranscode = false;
    final named = <({int height, String? codec, String protocol, Uri url})>[];
    for (final (key, protocol) in const [
      ('live_hls_url', 'hls'),
      ('live_flv_url', 'flv'),
      ('avc_url', 'flv'),
      ('play_url', 'flv'),
      ('avc_hls_url', 'hls'),
    ]) {
      final url = accept(video[key], protocol);
      if (url == null) continue;
      final name = _streamName(url);
      if (sourceName.hasMatch(name)) {
        avcSource = true;
        named.add((height: 0, codec: 'avc', protocol: protocol, url: url));
      } else if (heights[name] case final height?) {
        if (key != 'live_hls_url') avcTranscode = true;
        named.add((height: height, codec: 'avc', protocol: protocol, url: url));
      }
    }
    final sourceCodec = avcSource
        ? 'avc'
        : clarity.isEmpty && avcTranscode
        ? 'hevc'
        : null;

    // The source fields.
    for (final (key, protocol) in const [('live_flv_url_origin', 'flv'), ('live_hls_url_origin', 'hls')]) {
      final url = accept(video[key], protocol);
      if (url == null) continue;
      final name = _streamName(url);
      if (sourceName.hasMatch(name)) {
        named.add((height: 0, codec: sourceCodec, protocol: protocol, url: url));
      } else if (heights[name] case final height?) {
        named.add((height: height, codec: 'avc', protocol: protocol, url: url));
      }
    }
    if (accept(video['hevc_url'], 'flv') case final url?) {
      named.add((height: 0, codec: 'hevc', protocol: 'flv', url: url));
    }

    // 3.x's reading order (clarity, url_list, live_hls_url, live_flv_url,
    // live_flv_url_origin) keeps 3.x's URLs first within a tier.
    final tiers = <String, ({int height, String? codec, List<({Uri url, String protocol})> urls})>{};
    for (final entry in [...listed, ...named]) {
      final id = '${_tierId(entry.height)}${entry.codec == 'hevc' ? ':hevc' : ''}';
      final tier = tiers.putIfAbsent(id, () => (height: entry.height, codec: entry.codec, urls: []));
      tier.urls.add((url: entry.url, protocol: entry.protocol));
    }
    final variants = [
      for (final MapEntry(key: id, value: tier) in tiers.entries)
        BaiduLiveVariant(
          id: id,
          name: '${_tierName(tier.height)}${tier.codec == 'hevc' ? hevcSuffix : ''}',
          sort: (tier.height == 0 ? 100000 : tier.height) * 10 + _codecRank(tier.codec),
          codec: tier.codec,
          sources: _lineOrder(tier.urls),
        ),
    ]..sort((left, right) => right.sort.compareTo(left.sort));
    return List.unmodifiable(variants);
  }

  static int _codecRank(String? codec) => switch (codec) {
    'avc' => 2,
    null => 1,
    _ => 0,
  };

  /// [urls] as lines: 3.x's hosts before the current CDN, FLV before HLS,
  /// each stream once per host (the first URL of it).
  static List<BaiduLiveSource> _lineOrder(List<({Uri url, String protocol})> urls) {
    int group(({Uri url, String protocol}) entry) =>
        (_primaryHost(entry.url.host.toLowerCase()) ? 0 : 2) + (entry.protocol == 'flv' ? 0 : 1);
    final ordered = [
      for (var rank = 0; rank < 4; rank++)
        for (final entry in urls)
          if (group(entry) == rank) entry,
    ];
    final seen = <String>{};
    return [
      for (final entry in ordered)
        if (seen.add('${entry.url.host.toLowerCase()}${entry.url.path}'))
          (url: entry.url, format: entry.protocol == 'hls' ? StreamFormat.hls : StreamFormat.flv),
    ];
  }

  /// [value] as a recording of room [roomId] (30-4): an https `.m3u8` on a
  /// `bdstatic.com` host (http made https), on the default port, without
  /// user info or fragment, under the room's stream directory (`_<id>/`);
  /// else null.
  static Uri? replayUrl(Object? value, String roomId) {
    var uri = Uri.tryParse(_text(value));
    if (uri == null || !uri.host.toLowerCase().endsWith('.bdstatic.com')) return null;
    if (uri.scheme == 'http' && !uri.hasPort) uri = uri.replace(scheme: 'https');
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasPort ||
        !uri.path.toLowerCase().endsWith('.m3u8') ||
        !uri.path.contains('_$roomId/')) {
      return null;
    }
    return uri;
  }

  static final RegExp _replayKey = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

  /// The qualities of an ended broadcast's recording (30-4), from the first
  /// `replay_list` entry that has one: each `videoInfo.ext.clarityUrl`
  /// entry (H.264, named by its `title`, else its `key`; id
  /// `replay:<key>`), or without them the entry's `video` ([replayQualityId]);
  /// then each `video_hevc` entry (a JSON object of key to URL, H.265, named
  /// `<key>` with [hevcSuffix]; id `replay:<key>:hevc`, 30-2). Only the
  /// URLs [replayUrl] accepts count; each is one HLS line (a recording, not
  /// a live stream).
  static List<BaiduLiveVariant> replayVariants(Object? replayList, String roomId) {
    for (final value in _list(replayList)) {
      final item = _map(value) ?? const {};
      final avc = <({String id, String name, Uri url})>[];
      final seen = <String>{};
      final ext = _map((_map(item['videoInfo']) ?? const {})['ext']) ?? const {};
      for (final clarity in _list(ext['clarityUrl'])) {
        final entry = _map(clarity) ?? const {};
        final key = _text(entry['key']);
        final url = replayUrl(entry['url'], roomId);
        if (url == null || !_replayKey.hasMatch(key) || !seen.add(key.toLowerCase())) continue;
        avc.add((id: '$replayQualityId:${key.toLowerCase()}', name: _firstText([entry['title'], key]), url: url));
      }
      if (avc.isEmpty) {
        if (replayUrl(item['video'], roomId) case final url?) {
          avc.add((id: replayQualityId, name: replayQualityName, url: url));
        }
      }
      final hevc = <({String id, String name, Uri url})>[];
      var hevcList = item['video_hevc'];
      if (hevcList is String) {
        try {
          hevcList = jsonDecode(hevcList);
        } on FormatException {
          hevcList = null;
        }
      }
      final hevcSeen = <String>{};
      for (final MapEntry(:key, :value) in (_map(hevcList) ?? const <String, Object?>{}).entries) {
        final url = replayUrl(value, roomId);
        final name = key.trim();
        if (url == null || !_replayKey.hasMatch(name) || !hevcSeen.add(name.toLowerCase())) continue;
        hevc.add((id: '$replayQualityId:${name.toLowerCase()}:hevc', name: '$name$hevcSuffix', url: url));
      }
      if (avc.isEmpty && hevc.isEmpty) continue;
      final all = [
        for (final entry in avc) (entry: entry, codec: 'avc'),
        for (final entry in hevc) (entry: entry, codec: 'hevc'),
      ];
      return List.unmodifiable([
        for (final (index, (:entry, :codec)) in all.indexed)
          BaiduLiveVariant(
            id: entry.id,
            name: entry.name,
            sort: (all.length - index) * 10 + _codecRank(codec),
            codec: codec,
            sources: [(url: entry.url, format: StreamFormat.hls)],
          ),
      ]);
    }
    return const [];
  }

  /// [variants] in menu order (30-2): with [preferH264] ("优先 H.264", on by
  /// default) the H.264 qualities first (best first), then those whose
  /// codec is not known, then the H.265 ones, so the default is H.264 and
  /// H.265 is only picked by hand; off, best first (a tier's H.264 before
  /// its H.265).
  static List<BaiduLiveVariant> ordered(List<BaiduLiveVariant> variants, {bool preferH264 = true}) {
    final best = [...variants]..sort((left, right) => right.sort.compareTo(left.sort));
    if (!preferH264) return List.unmodifiable(best);
    return List.unmodifiable([
      for (final rank in const [2, 1, 0])
        for (final variant in best)
          if (_codecRank(variant.codec) == rank) variant,
    ]);
  }

  /// The qualities of [room] (30-1, 30-2, 30-4), in [ordered] order: name,
  /// id and sort of each variant. A room that cannot be played says why
  /// (see [BaiduLiveRoom.unavailable]).
  static List<LivePlayQuality> qualities(BaiduLiveRoom room, {bool preferH264 = true}) {
    if (room.unavailable case final error?) throw error;
    return List.unmodifiable([
      for (final variant in ordered(room.variants, preferH264: preferH264))
        LivePlayQuality(quality: variant.name, id: variant.id, sort: variant.sort),
    ]);
  }

  /// The lines of [variant] of room [roomId]: its URLs in order, with the
  /// media headers, the format, the codec (when known) and the host as line
  /// id (`<host>#2` for a second URL on the same host). The URLs carry no
  /// signature or expiry, so no lease.
  static List<LivePlayLine> lines(BaiduLiveVariant variant, String roomId) {
    final headers = mediaHeaders(roomId);
    final hosts = <String, int>{};
    final lines = <LivePlayLine>[];
    for (final source in variant.sources) {
      final host = source.url.host;
      final count = hosts.update(host, (count) => count + 1, ifAbsent: () => 1);
      lines.add(
        LivePlayLine(
          '${source.url}',
          headers: headers,
          format: source.format,
          codec: variant.codec,
          lineId: count == 1 ? host : '$host#$count',
        ),
      );
    }
    return List.unmodifiable(lines);
  }

  /// The lines of [quality] (by its id; a 3.x id is read through
  /// [qualityIdFromLegacy]) in [room]; the applied quality is the current
  /// id. A quality the room no longer offers is `StreamUnavailable`, and a
  /// room that cannot be played says why.
  static LivePlayUrlResolution resolution(BaiduLiveRoom room, LivePlayQuality quality) {
    if (room.unavailable case final error?) throw error;
    final wanted = qualityIdFromLegacy('${quality.selectionId}');
    final variant = room.variants.where((variant) => variant.id == wanted).firstOrNull;
    if (variant == null) throw StreamUnavailable(_site, 'quality $wanted is not offered');
    return LivePlayUrlResolution.lines(lines(variant, room.roomId), appliedQualityData: variant.id);
  }
}
