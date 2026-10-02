import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:live_core/src/aes.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'kilakila';

/// What a KilaKila link names.
enum KilakilaLinkKind {
  /// One broadcast (`roomIdStr`), new every time the anchor goes live; its
  /// anchor is found with `getRoomInfo`.
  broadcast,

  /// An anchor's uid: the room identity.
  owner,
}

/// A KilaKila link (3.x's `KilakilaLink`): an anchor page, or a broadcast
/// page whose id may be sealed in the website's encrypted share parameter.
@immutable
final class KilakilaLink {
  /// Creates a link.
  const new(this.kind, this.id);

  /// Broadcast or anchor.
  final KilakilaLinkKind kind;

  /// The broadcast id or the uid.
  final String id;

  // Public constants of the website's codec (uxin-security-url-crypto-v2.min.js,
  // SHA-256 2a031560d9ccd3770ff57969b8818e5eafd6d8a1e4f54c87e0f4bd983d4607e2),
  // not credentials.
  static const _readKeys = ['7cdyGRc6Sa93ilPt', 'c98be79a4347bc97'];
  static const _iv = '93x0ue23c2c9h8km';
  static const _signaturePrefix = r'pR@Wv%Wju@Pl&bKc$GyUrPeO';

  static final RegExp _unsafe = RegExp(r'[\x00-\x20\x7f]');
  static final RegExp _badEscape = RegExp('%(?![0-9a-fA-F]{2})');
  static final RegExp _rawPath = RegExp('^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]+([^?#]*)');
  static final RegExp _payload = RegExp(r'^[A-Za-z0-9_+/\-]+={0,2}$');
  static final RegExp _sign = RegExp(r'^[a-f0-9]{32}$');

  /// The link [value] is, exactly as 3.x read it, or null:
  /// - `live.kilakila.cn` or `www.hongdoufm.com` (http or https, default
  ///   port): `/room/<id>` and `/PcLive/index/detail?id=<id>` name a
  ///   broadcast, `/zhubo/<uid>` (no query) an anchor;
  /// - `https://live.hongrenshuo.com.cn/index/roomuser/uid/<uid>` names an
  ///   anchor;
  /// - instead of the id, a room or anchor path may carry an encrypted
  ///   payload and a detail page `_specific_parameter`: URL-safe base64,
  ///   AES-128-CBC with one of the public keys, whose plaintext holds the id
  ///   and an MD5 `sign` over the scheme, host and route as written
  ///   (REG-KILAKILA-002). A payload that does not decrypt or whose
  ///   signature does not match (another host, a re-encoded route) is no
  ///   link.
  ///
  /// Whitespace, control characters, broken `%` escapes, user info, a
  /// fragment, repeated parameters or an id with a leading zero make it no
  /// link. The value is one URL, not a share text.
  static KilakilaLink? parse(String value) {
    if (value.length > 8192) return null;
    final input = value.trim();
    if (_unsafe.hasMatch(input) || _badEscape.hasMatch(input)) return null;
    final uri = Uri.tryParse(input);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final roomHost = KilakilaApi.roomHosts.contains(uri.host);
    final ownerHost = uri.host == KilakilaApi.ownerHost && uri.scheme == 'https';
    if (!roomHost && !ownerHost) return null;
    // Dart normalizes escaped unreserved path characters, but the signature
    // binds the route as written: read it from the input.
    final rawPath = _rawPath.firstMatch(input)?.group(1);
    if (rawPath == null) return null;
    try {
      final query = uri.queryParametersAll;
      if (query.values.any((values) => values.length != 1)) return null;
      final publicOwnerPath = roomHost && rawPath.startsWith('/zhubo/');
      if (publicOwnerPath && uri.hasQuery) return null;
      final pathPrefix = ownerHost ? '/index/roomuser/uid/' : (publicOwnerPath ? '/zhubo/' : '/room/');
      final isPath = rawPath.startsWith(pathPrefix);
      final isDetail = roomHost && (rawPath == '/PcLive/index/detail' || rawPath == '/PcLive/index/detail/');
      if (!isPath && !isDetail) return null;
      final kind = ownerHost || publicOwnerPath ? KilakilaLinkKind.owner : KilakilaLinkKind.broadcast;
      String payload;
      if (isPath) {
        if (query.containsKey('id') || query.containsKey('uid') || query.containsKey('_specific_parameter')) {
          return null;
        }
        payload = Uri.decodeComponent(rawPath.substring(pathPrefix.length));
        if (payload.contains('/')) return null;
        if (KilakilaApi.isId(payload)) return KilakilaLink(kind, payload);
      } else {
        if (query.containsKey('_specific_parameter')) {
          if (query.containsKey('id') || query.containsKey('sign')) return null;
          payload = query['_specific_parameter']!.single;
        } else {
          final id = query['id']?.single;
          return id != null && KilakilaApi.isId(id) ? KilakilaLink(kind, id) : null;
        }
      }
      if (payload.length > 4096 || !_payload.hasMatch(payload)) return null;
      final bytes = base64Url.decode(base64Url.normalize(payload));
      if (bytes.isEmpty || bytes.length % 16 != 0) return null;
      for (final key in _readKeys) {
        try {
          final plain = utf8.decode(Aes128Cbc.decrypt(bytes, key: utf8.encode(key), iv: utf8.encode(_iv)));
          final params = _parameters(plain);
          if (params == null) continue;
          final id = params['id'];
          final sign = params['sign'];
          if (id == null || !KilakilaApi.isId(id) || sign == null || !_sign.hasMatch(sign)) continue;
          var base = '${uri.origin}${isPath ? pathPrefix : '$rawPath?'}';
          String canonical;
          if (isPath && params.length == 2) {
            canonical = id;
          } else {
            if (isPath) base += '$id?';
            final keys = params.keys.where((key) => key != 'sign' && (!isPath || key != 'id')).toList()..sort();
            canonical = keys.map((key) => '$key=${params[key]}').join('&');
          }
          if (md5.convert(utf8.encode('$_signaturePrefix$base$canonical')).toString() == sign) {
            return KilakilaLink(kind, id);
          }
        } on FormatException {
          continue;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// The parameters of a decrypted payload: `<id>?k=v&…` (URL-encoded, the
  /// website's URLSearchParams) for paths, `k=v&…` (raw values) for the
  /// detail page; null when malformed.
  static Map<String, String>? _parameters(String plain) {
    if (plain.isEmpty || plain.length > 4096 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(plain)) return null;
    final result = <String, String>{};
    final question = plain.indexOf('?');
    var query = plain;
    if (question >= 0) {
      if (plain.indexOf('?', question + 1) >= 0) return null;
      final id = plain.substring(0, question);
      if (!KilakilaApi.isId(id)) return null;
      result['id'] = id;
      query = plain.substring(question + 1);
    }
    for (final pair in query.split('&')) {
      final equal = pair.indexOf('=');
      if (equal <= 0 || result.length >= 32) return null;
      var key = pair.substring(0, equal);
      var value = pair.substring(equal + 1);
      if (question >= 0) {
        key = Uri.decodeQueryComponent(key);
        value = Uri.decodeQueryComponent(value);
      } else if (value.contains('=')) {
        return null;
      }
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(key) ||
          value.length > 1024 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
          result.containsKey(key)) {
        return null;
      }
      result[key] = value;
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is KilakilaLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'KilakilaLink(${kind.name}, $id)';
}

/// One broadcast of an anchor (3.x's `KilakilaRoomSnapshot`): a timeline
/// row, an anchor's current card or `getRoomInfo`. The broadcast id is new
/// every time the anchor goes live; the uid is the room identity.
@immutable
final class KilakilaBroadcast {
  /// Creates the broadcast.
  const new({
    required this.broadcastId,
    required this.uid,
    required this.title,
    required this.nick,
    required this.status,
    required this.goldPrice,
    this.cover = '',
    this.avatar = '',
    this.startedAt,
    this.online,
    this.total,
    this.flv,
    this.hls,
  });

  /// `roomIdStr`.
  final String broadcastId;

  /// The anchor's uid.
  final String uid;

  /// Title.
  final String title;

  /// Anchor name.
  final String nick;

  /// `backPic`, else `defaultBackgroundPicUrl`.
  final String cover;

  /// Anchor avatar.
  final String avatar;

  /// The platform's state: 4 live, 10 ended (a replay); 3.x called only 4
  /// live and left every other value unknown.
  final int status;

  /// Price of a paid broadcast; 0 when free.
  final int goldPrice;

  /// When the broadcast went on air (`actualTime`, epoch milliseconds);
  /// only an anchor's card has it. Its `liveStartTime` (also `createTime`)
  /// is when the broadcast was set up, often a day before it went on air,
  /// and is not used.
  final DateTime? startedAt;

  /// Listeners now (`onlineNumber`); only an anchor's card has it.
  final int? online;

  /// Listeners of this broadcast so far (`watchNumber`, only ever grows;
  /// REG-KILAKILA-003).
  final int? total;

  /// The FLV pull URL of `getRoomInfo` (null elsewhere, or when it is not a
  /// pull URL of this broadcast).
  final String? flv;

  /// The HLS pull URL of `getRoomInfo`, as [flv].
  final String? hls;

  /// Whether the platform says live (status 4).
  bool get isLive => status == 4;

  /// Whether the platform says the broadcast is over (status 10; it may
  /// keep a recording, which the anchor's room does not play).
  bool get hasEnded => status == 10;

  /// What keeps the broadcast from playing: [LiveRestriction.paid] when it
  /// has a price, else [LiveRestriction.none].
  LiveRestriction get restriction => goldPrice == 0 ? LiveRestriction.none : LiveRestriction.paid;

  /// This broadcast (from `getRoomInfo`) with what only the anchor's
  /// [card] of the same broadcast has: the start, the listeners now, and
  /// its cover when it has one (the list's `backPic`, where `getRoomInfo`
  /// only has the default background; 15-7).
  KilakilaBroadcast withCard(KilakilaBroadcast card) => KilakilaBroadcast(
    broadcastId: broadcastId,
    uid: uid,
    title: title,
    nick: nick,
    status: status,
    goldPrice: goldPrice,
    cover: card.cover.isNotEmpty ? card.cover : cover,
    avatar: avatar,
    startedAt: card.startedAt,
    online: card.online,
    total: total ?? card.total,
    flv: flv,
    hls: hls,
  );
}

/// An anchor's public profile (`Tg/personalH5`, 3.x's
/// `KilakilaOwnerSnapshot`) and the broadcast it advertises, if any.
@immutable
final class KilakilaProfile {
  /// Creates the profile.
  const new({
    required this.uid,
    required this.nick,
    this.avatar = '',
    this.introduction = '',
    this.followers,
    this.current,
  });

  /// The anchor's uid.
  final String uid;

  /// Display name.
  final String nick;

  /// Avatar.
  final String avatar;

  /// Self-introduction (`userResp.introduction`).
  final String introduction;

  /// `userResp.statisticInfo.followerNumber`, when given.
  final int? followers;

  /// The current broadcast's card; null when the card holds only routing
  /// defaults (no current broadcast).
  final KilakilaBroadcast? current;
}

/// What room entry learnt about an anchor's current broadcast; never
/// stored (3.x kept the pull URLs as the room's qualities in `data`).
@immutable
final class KilakilaRoomData {
  /// Creates the data.
  const new({required this.issuedAt, this.broadcast});

  /// The current broadcast from `getRoomInfo` with its pull URLs; null when
  /// the profile advertised none.
  final KilakilaBroadcast? broadcast;

  /// When `getRoomInfo` answered: the start of the pull URLs' lease.
  final DateTime issuedAt;
}

/// The danmaku room of a broadcast. 3.x had no KilaKila danmaku
/// (`EmptyDanmaku`); room entry keeps the broadcast id the website's guest
/// chat joins, for M5 to decide on.
@immutable
final class KilakilaDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId});

  /// The current broadcast's `roomIdStr`.
  final String roomId;

  @override
  String toString() => 'KilakilaDanmakuArgs($roomId)';
}

/// Pure parsing of KilaKila (克拉克拉) responses (3.x's `KilakilaApi`). Each
/// function takes the response text and status and returns 3.x's models or
/// throws a `SiteError`.
///
/// A room is an anchor: its id is the anchor's uid, and every broadcast has
/// a new `roomIdStr` (REG-KILAKILA-001). Answers are checked as strictly as
/// 3.x did, except that one broken row of a list only drops that row
/// (docs/specs/UPGRADES.md, "容错"): a page whose echo or identity does not
/// match, or whose rows are all broken, is still `ApiChanged`. An anchor
/// the platform says has no broadcast, or whose broadcast ended, is
/// offline (15-1); any other state the platform does not name stays
/// unknown.
abstract final class KilakilaApi {
  /// The website: the API host of the timeline, `getRoomInfo` and search.
  static const String origin = 'https://live.kilakila.cn';

  /// Hosts of broadcast pages and `/zhubo/` anchor pages.
  static const Set<String> roomHosts = {'live.kilakila.cn', 'www.hongdoufm.com'};

  /// Host of anchor pages and of the profile API.
  static const String ownerHost = 'live.hongrenshuo.com.cn';

  /// Host of the pull URLs.
  static const String mediaHost = 'pull.live.hongrenshuo.com.cn';

  /// The user agent 3.x sent to the API and the media CDN.
  static const String userAgent = 'Mozilla/5.0';

  /// Headers of every API request and of the media (3.x's `playHeaders`,
  /// which its `PlaybackHeaderResolver` also gave the player and the
  /// recorder). No cookie: 3.x's KilaKila was anonymous.
  static const Map<String, String> headers = {'referer': '$origin/', 'user-agent': userAgent};

  /// Largest answer 3.x accepted (1 MiB).
  static const int responseLimit = 1024 * 1024;

  /// Longest lead before a pull URL's expiry at which it is renewed; at most
  /// a quarter of its lifetime.
  static const Duration leaseLead = Duration(minutes: 10);

  /// Id and name of the one category (3.x used the platform's).
  static const String categoryId = _site;

  /// See [categoryId].
  static const String categoryName = '克拉克拉';

  /// The two timelines, by `type`, with 3.x's names: 热门直播 (0) and
  /// 萌星推荐 (107, the rising stars).
  static const Map<String, String> timelines = {'0': '热门直播', '107': '萌星推荐'};

  /// Rows of a native directory page (3.x's directory pager).
  static const int pageSize = 10;

  /// The last timeline page read (15-3, REG-KILAKILA-005): the timelines
  /// repeat their anchors page after page (the hot one for dozens of pages
  /// before `isLastPage`; the rising stars once ran past page 300), so
  /// reading stops here.
  static const int maxPages = 100;

  /// Longest keyword sent to the user search, in UTF-16 code units (3.x's
  /// limit; a longer one is cut there, 15-5).
  static const int keywordLimit = 100;

  /// The one quality (15-6): the broadcast's own stream, as FLV and HLS
  /// lines that stand in for each other.
  static const String qualityId = 'original';

  /// See [qualityId].
  static const String qualityName = '原画';

  /// 3.x's quality ids, one per transport (named `FLV`, `HLS`), → the id
  /// of the quality that now holds both transports as lines, for M9 to
  /// migrate a stored quality once. The line of the old transport keeps
  /// its name as `lineId`.
  static const Map<String, String> legacyQualityIds = {'flv': qualityId, 'hls': qualityId};

  /// The quality id for [id] as stored before 15-6 ([legacyQualityIds],
  /// case-insensitive); any other id is kept.
  static String qualityIdFromLegacy(String id) => legacyQualityIds[id.trim().toLowerCase()] ?? id.trim();

  static final RegExp _idPattern = RegExp(r'^[1-9][0-9]{0,31}$');

  /// Keys of an anchor's `liveCard` when it advertises no broadcast.
  static const Set<String> _routingKeys = {'roomSourceType', 'recommendSource'};

  /// Whether [value] is a uid or broadcast id: 1–32 digits without a
  /// leading zero.
  static bool isId(String value) => _idPattern.hasMatch(value);

  /// The anchor's page, the room's link (3.x's `KilakilaSite.ownerUrl`).
  static String ownerUrl(String uid) => 'https://$ownerHost/index/roomuser/uid/$uid';

  // Envelopes -----------------------------------------------------------------

  /// Maps a status other than 200 as 3.x did (it read no body then): 401 and
  /// 403 `RiskControl`, 404 `NotFound`, 429 `RateLimited`, anything else
  /// (5xx, a redirect) `NetworkFailure`.
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

  /// The status, then 3.x's 1 MiB limit in UTF-8 bytes (a UTF-16 unit is at
  /// most three bytes, so only a long text is encoded to count).
  static void _checkBody(String body, String what, int status) {
    checkStatus(status, what);
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: answer over $responseLimit bytes');
    }
  }

  static Map<String, dynamic> _json(String body, String what, int status) {
    _checkBody(body, what, status);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    return _object(decoded, what);
  }

  /// A business code that must be 200 (3.x's `_businessCode`; it called
  /// other codes a service failure, which is no evidence of anything).
  static void _code(Object? value, String what) {
    final code = _integer(value);
    if (code == null) throw ApiChanged(_site, '$what: no code');
    if (code != 200) throw ApiChanged(_site, '$what: code $code');
  }

  /// The `{h, b}` header: `h.code` 200 and `h.success` true.
  static void _header(Map<String, dynamic> envelope, String what) {
    final header = _object(envelope['h'], '$what.h');
    _code(header['code'], '$what.h');
    if (header['success'] != true) throw ApiChanged(_site, '$what: h.success is ${header['success']}');
  }

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog: one category 克拉克拉 with the two [timelines] as areas
  /// (`areaType` `timeline`). The platform has no area API.
  static List<LiveCategory> categories() => [
    LiveCategory(
      id: categoryId,
      name: categoryName,
      children: [
        for (final MapEntry(:key, :value) in timelines.entries)
          LiveArea(platform: _site, areaType: 'timeline', typeName: categoryName, areaId: key, areaName: value),
      ],
    ),
  ];

  /// The timeline `type` of [area]: 0 for the recommendations (null), else a
  /// KilaKila `timeline` area of [timelines]. Anything else is a caller
  /// error (`ArgumentError`), refused before any request as in 3.x.
  static int timelineType(LiveArea? area) {
    if (area == null) return 0;
    if (area.platform != _site || area.areaType != 'timeline' || !timelines.containsKey(area.areaId)) {
      throw ArgumentError.value(area, 'category', 'not a KilaKila timeline');
    }
    return int.parse(area.areaId);
  }

  /// A `pcLive/timeline` page (3.x's `directory`): the live rows of timeline
  /// [type] (`dataType` 8, and 2 on the rising stars 107), each broadcast
  /// and each anchor once, and whether another page follows.
  ///
  /// The answer is wrapped twice (`code`, then `data.body` with `{h, b}`);
  /// `b` must echo [page] and [pageSize]. Rows of other types are skipped.
  /// A row that is broken (not an object, no type, a broadcast whose
  /// anchor, title or name is missing or does not match) is left out; a
  /// page with a broken row and no usable one is `ApiChanged`, so a changed
  /// API never reads as an empty timeline.
  ///
  /// The timeline ends at `isLastPage`, at a page without any row (the
  /// rising stars end with `{pageNo, pageSize, data: []}` and no
  /// `isLastPage`, which 3.x took for a changed API; S01-timeline-new-tail)
  /// and at [maxPages] (15-3). A page whose rows are all of other types
  /// does not end it (3.x). An `isLastPage` that is there must be a
  /// boolean.
  static LiveDirectoryPage timelinePage(
    String body, {
    required int page,
    required int pageSize,
    required int type,
    int status = 200,
  }) {
    final root = _json(body, 'timeline', status);
    _code(root['code'], 'timeline');
    final envelope = _object(_object(root['data'], 'timeline.data')['body'], 'timeline.data.body');
    _header(envelope, 'timeline');
    final data = _object(envelope['b'], 'timeline.b');
    final last = data['isLastPage'];
    if (_integer(data['pageNo']) != page || _integer(data['pageSize']) != pageSize || (last != null && last is! bool)) {
      throw ApiChanged(
        _site,
        'timeline page $page: echo pageNo ${data['pageNo']}, pageSize ${data['pageSize']}, isLastPage $last',
      );
    }
    final rows = data['data'];
    if (rows is! List || rows.length > 1000) throw const ApiChanged(_site, 'timeline.b.data: expected a list');
    final broadcasts = <String>{};
    final anchors = <String>{};
    final rooms = <LiveRoom>[];
    var broken = 0;
    for (final row in rows) {
      final KilakilaBroadcast broadcast;
      try {
        final fields = _object(row, 'timeline row');
        final kind = _nonNegative(fields['dataType'], 'timeline row dataType');
        if (kind != 8 && !(type == 107 && kind == 2)) continue;
        broadcast = _broadcast(
          _object(fields['roomResq'], 'timeline row roomResq'),
          _object(fields['userResp'], 'timeline row userResp'),
        );
      } on ApiChanged {
        broken++;
        continue;
      }
      if (!broadcasts.add(broadcast.broadcastId) || !anchors.add(broadcast.uid)) continue;
      rooms.add(room(broadcast));
    }
    if (broken > 0 && rooms.isEmpty) throw ApiChanged(_site, 'timeline page $page: $broken broken rows, none usable');
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: last != true && rows.isNotEmpty && page < maxPages);
  }

  // Search --------------------------------------------------------------------

  /// The keyword sent for [keyword]: trimmed and cut to [keywordLimit]
  /// UTF-16 code units, never inside a surrogate pair, then trimmed again
  /// (15-5; 3.x refused a longer keyword and the search page showed a
  /// failure). Empty when there is nothing to search for.
  static String searchKeyword(String keyword) {
    var text = keyword.trim();
    if (text.length > keywordLimit) {
      var end = keywordLimit;
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) end--;
      text = text.substring(0, end).trim();
    }
    return text;
  }

  /// The website's user search page of [keyword] ([searchKeyword]; `serach`
  /// is the site's spelling): `/aboutus/serach/kw/<keyword>`, `/p/<page>`
  /// after page 1.
  static Uri searchUrl(String keyword, int page) => Uri(
    scheme: 'https',
    host: 'live.kilakila.cn',
    pathSegments: [
      'aboutus',
      'serach',
      'kw',
      searchKeyword(keyword),
      if (page > 1) ...['p', '$page'],
    ],
  );

  /// A user search page (3.x's `searchOwners`): the anchors of the
  /// `.userList` links `/zhubo/<uid>`, each once, as rooms with their name
  /// (also the title, 3.x's card) and avatar. The page says nothing about
  /// broadcasts, so their state is unknown, as in 3.x. An entry whose link
  /// is not an anchor page or that has no name is left out; a page without
  /// the list, with more than 100 entries, or whose entries are all broken
  /// is `ApiChanged`.
  static List<LiveRoom> searchPage(String html, {int status = 200}) {
    _checkBody(html, 'search', status);
    final list = _Html.parse(html).firstWithClass('userList');
    if (list == null || list.children.length > 100) throw const ApiChanged(_site, 'search: no user list');
    final rooms = <String, LiveRoom>{};
    var broken = 0;
    for (final anchor in list.children.where((element) => element.name == 'a')) {
      final match = RegExp(r'^/zhubo/([1-9][0-9]{0,31})$').firstMatch(anchor.attributes['href'] ?? '');
      final nick = anchor.firstWithClass('anchor-name')?.text.trim() ?? '';
      if (match == null || nick.isEmpty) {
        broken++;
        continue;
      }
      final uid = match.group(1)!;
      final avatar = anchor.firstWithClass('anchorHeaderImg')?.first('img')?.attributes['src'];
      rooms.putIfAbsent(uid, () => _anchorRoom(uid, nick: nick, avatar: _picture(avatar), title: nick));
    }
    if (broken > 0 && rooms.isEmpty) throw ApiChanged(_site, 'search: $broken broken entries, none usable');
    return rooms.values.toList();
  }

  // Anchors and broadcasts ----------------------------------------------------

  /// `Tg/personalH5?uid=` (3.x's `owner`): the anchor [uid] and its current
  /// broadcast. Code 1013 is an unknown anchor (`NotFound`); any other code
  /// but 200 is `ApiChanged`. A `liveCard` holding only the routing defaults
  /// `roomSourceType` and `recommendSource` (or nothing) means no current
  /// broadcast; anything else must be a whole card of this anchor.
  static KilakilaProfile profile(String body, {required String uid, int status = 200}) {
    final root = _json(body, 'personalH5', status);
    if (_integer(root['code']) == 1013) throw NotFound(_site, 'personalH5: no anchor $uid');
    _code(root['code'], 'personalH5');
    final data = _object(root['data'], 'personalH5.data');
    final user = _object(data['userResp'], 'personalH5.userResp');
    final card = _object(data['liveCard'], 'personalH5.liveCard');
    final nick = _text(user['nickname']);
    if (nick.isEmpty || (user.containsKey('id') && _id(user['id'], 'personalH5.userResp.id') != uid)) {
      throw ApiChanged(_site, 'personalH5: not the anchor $uid');
    }
    KilakilaBroadcast? current;
    if (card.keys.every(_routingKeys.contains)) {
      for (final value in card.values) {
        _nonNegative(value, 'personalH5.liveCard');
      }
    } else {
      // The profile has no uid of its own: the card must name this anchor.
      if (_id(card['uid'], 'personalH5.liveCard.uid') != uid) {
        throw const ApiChanged(_site, 'personalH5: liveCard of another anchor');
      }
      current = _broadcast(card, {...user, 'id': uid});
    }
    final statistics = user['statisticInfo'];
    return KilakilaProfile(
      uid: uid,
      nick: nick,
      avatar: _picture(user['headPortraitUrl']),
      introduction: _text(user['introduction']),
      followers: statistics is Map<String, dynamic> ? jsonCount(statistics['followerNumber']) : null,
      current: current,
    );
  }

  /// `LiveRoom/getRoomInfo?roomId=` (3.x's `detail`): the broadcast
  /// [broadcastId] with its pull URLs; when [uid] is given it must be that
  /// anchor's. `h.code` 5201 is an unknown broadcast (`NotFound`), 5966 a
  /// historical replay (`StreamUnavailable`); any other code but 200, or
  /// another broadcast or anchor, is `ApiChanged`.
  static KilakilaBroadcast roomInfo(String body, {required String broadcastId, String? uid, int status = 200}) {
    final root = _json(body, 'getRoomInfo', status);
    final header = _object(root['h'], 'getRoomInfo.h');
    final code = _integer(header['code']);
    if (code == 5201) throw NotFound(_site, 'getRoomInfo: no broadcast $broadcastId');
    if (code == 5966) throw StreamUnavailable(_site, 'getRoomInfo: $broadcastId is a historical replay');
    _header(root, 'getRoomInfo');
    final room = _object(root['b'], 'getRoomInfo.b');
    if (_id(room['roomIdStr'], 'getRoomInfo.roomIdStr') != broadcastId ||
        (uid != null && _id(room['uid'], 'getRoomInfo.uid') != uid)) {
      throw ApiChanged(_site, 'getRoomInfo $broadcastId: another broadcast or anchor');
    }
    return _broadcast(room, _object(room['userInfo'], 'getRoomInfo.userInfo'), media: true);
  }

  /// A broadcast [room] of the anchor [owner] (3.x's `_snapshot`): ids,
  /// title, name, state and price are required, the cover is `backPic` or
  /// `defaultBackgroundPicUrl`. The start (`actualTime`), listeners now
  /// (`onlineNumber`) and so far (`watchNumber`) are read where the answer
  /// has them; a value that is not one is left out. The pull URLs are read
  /// only with [media]. The push address (`pushFlow`, the anchor's stream
  /// key) is never read (REG-KILAKILA-004).
  static KilakilaBroadcast _broadcast(Map<String, dynamic> room, Map<String, dynamic> owner, {bool media = false}) {
    final broadcastId = _id(room['roomIdStr'], 'roomIdStr');
    final uid = _id(room['uid'], 'broadcast $broadcastId uid');
    final title = _text(room['title']);
    final nick = _text(owner['nickname']);
    if (_id(owner['id'], 'broadcast $broadcastId owner') != uid || title.isEmpty || nick.isEmpty) {
      throw ApiChanged(_site, 'broadcast $broadcastId: owner, title or name missing');
    }
    final status = _nonNegative(room['status'], 'broadcast $broadcastId status');
    final price = _nonNegative(room['goldPrice'], 'broadcast $broadcastId goldPrice');
    final cover = _picture(room['backPic']);
    return KilakilaBroadcast(
      broadcastId: broadcastId,
      uid: uid,
      title: title,
      nick: nick,
      cover: cover.isNotEmpty ? cover : _picture(room['defaultBackgroundPicUrl']),
      avatar: _picture(owner['headPortraitUrl']),
      status: status,
      goldPrice: price,
      startedAt: startedAt(room['actualTime']),
      online: _count(room['onlineNumber']),
      total: _count(room['watchNumber']),
      flv: media ? mediaUrl(room['flvPlayUrl'], broadcastId: broadcastId, format: StreamFormat.flv) : null,
      hls: media ? mediaUrl(room['hlsPlayUrl'], broadcastId: broadcastId, format: StreamFormat.hls) : null,
    );
  }

  /// A broadcast's start from `actualTime` (epoch milliseconds): null for
  /// 0, negatives, fractions, values that are not milliseconds (before 2001
  /// or after 2286, such as seconds) and anything that is not an integer.
  static DateTime? startedAt(Object? value) => switch (_integer(value)) {
    final int milliseconds when milliseconds >= 1000000000000 && milliseconds < 10000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    _ => null,
  };

  /// A listener count: an integer of 0 or more (or its text), else null.
  static int? _count(Object? value) => switch (_integer(value)) {
    final int count when count >= 0 => count,
    _ => null,
  };

  // Rooms ---------------------------------------------------------------------

  /// The room of [broadcast] (3.x's `KilakilaSite._room`): the anchor's uid
  /// is the room id and the anchor page the link. The state is live when
  /// the platform says 4, offline when the broadcast ended (10, 15-1), else
  /// unknown. A live broadcast also has:
  /// - its listeners now (`onlineNumber`, only an anchor's card has them)
  ///   and so far (`watchNumber`, cumulative, never shown as online;
  ///   REG-KILAKILA-003) (15-2);
  /// - its start (`actualTime`, only an anchor's card has it);
  /// - its restriction: [LiveRestriction.paid] when it has a price, else
  ///   [LiveRestriction.none].
  static LiveRoom room(KilakilaBroadcast broadcast) {
    final live = broadcast.isLive;
    return LiveRoom(
      roomId: broadcast.uid,
      platform: _site,
      userId: broadcast.uid,
      link: ownerUrl(broadcast.uid),
      title: broadcast.title,
      nick: broadcast.nick,
      cover: broadcast.cover,
      avatar: broadcast.avatar,
      watching: '',
      onlineViewers: live ? broadcast.online?.toString() ?? '' : '',
      totalViewers: live ? broadcast.total?.toString() ?? '' : '',
      audienceMetricType: live ? AudienceMetricType.onlineViewers : AudienceMetricType.unknown,
      liveStatus: live ? LiveStatus.live : (broadcast.hasEnded ? LiveStatus.offline : LiveStatus.unknown),
      startedAt: live ? broadcast.startedAt : null,
      restriction: live ? broadcast.restriction : null,
    );
  }

  /// The room of [profile] when searched for (3.x's `_profileRoom`, for an
  /// anchor without a current broadcast): the name is also the title (3.x's
  /// card); offline, since the platform says there is no broadcast (15-1).
  static LiveRoom profileRoom(KilakilaProfile profile) => _anchorRoom(
    profile.uid,
    nick: profile.nick,
    avatar: profile.avatar,
    title: profile.nick,
    liveStatus: LiveStatus.offline,
  );

  /// The detail of [profile] (3.x's `KilakilaSite._detail` without the
  /// broadcast lookup): its current broadcast's room, else the anchor,
  /// offline (the card says there is no broadcast; 15-1). The introduction
  /// and follower count come along.
  static LiveRoom profileDetail(KilakilaProfile profile) {
    final current = profile.current;
    final base = current == null
        ? _anchorRoom(profile.uid, nick: profile.nick, avatar: profile.avatar, liveStatus: LiveStatus.offline)
        : room(current);
    return withProfile(base, profile);
  }

  /// Room entry's room: [broadcast] from `getRoomInfo` with what the
  /// anchor's card of the same broadcast adds (start, listeners now, and
  /// the card's cover, 15-7; see [KilakilaBroadcast.withCard]), and
  /// [profile]'s introduction and follower count.
  static LiveRoom enteredRoom(KilakilaProfile profile, KilakilaBroadcast broadcast) {
    final card = profile.current;
    final merged = card != null && card.broadcastId == broadcast.broadcastId ? broadcast.withCard(card) : broadcast;
    return withProfile(room(merged), profile);
  }

  /// [room] with [profile]'s introduction and follower count (3.x read
  /// neither).
  static LiveRoom withProfile(LiveRoom room, KilakilaProfile profile) =>
      room.copyWith(introduction: profile.introduction, followers: profile.followers?.toString());

  static LiveRoom _anchorRoom(
    String uid, {
    required String nick,
    required String avatar,
    String title = '',
    LiveStatus liveStatus = LiveStatus.unknown,
  }) => LiveRoom(
    roomId: uid,
    platform: _site,
    userId: uid,
    link: ownerUrl(uid),
    title: title,
    nick: nick,
    avatar: avatar,
    watching: '',
    audienceMetricType: AudienceMetricType.unknown,
    liveStatus: liveStatus,
  );

  // Streams -------------------------------------------------------------------

  /// The qualities of the broadcast [data] holds: one, [qualityName]
  /// ([qualityId]), whose data is the pull URLs, FLV then HLS (15-6; 3.x
  /// listed the transports as two qualities `FLV`, `HLS`). No broadcast, one
  /// that is not live (status other than 4) or without a pull URL is
  /// `StreamUnavailable`; so is a paid one (`goldPrice` above 0), naming
  /// [LiveRestriction.paid] and checked first as in 3.x (which called it
  /// `NeedsLogin`, though KilaKila has no login).
  static List<LivePlayQuality> qualities(KilakilaRoomData data) {
    final broadcast = data.broadcast;
    if (broadcast == null) throw const StreamUnavailable(_site, 'no current broadcast');
    if (broadcast.restriction == LiveRestriction.paid) {
      throw StreamUnavailable(_site, 'broadcast ${broadcast.broadcastId} is restricted (${LiveRestriction.paid.name})');
    }
    if (!broadcast.isLive) {
      throw StreamUnavailable(_site, 'broadcast ${broadcast.broadcastId} has status ${broadcast.status}');
    }
    final urls = [?broadcast.flv, ?broadcast.hls];
    if (urls.isEmpty) throw StreamUnavailable(_site, 'broadcast ${broadcast.broadcastId} has no pull URL');
    return List.unmodifiable([
      LivePlayQuality(quality: qualityName, id: qualityId, data: List<String>.unmodifiable(urls)),
    ]);
  }

  /// The lines of [quality] (by its id; a 3.x id `flv` or `hls` is taken
  /// for [qualityId], see [qualityIdFromLegacy]) among [data]'s
  /// [qualities]: FLV then HLS, each with the media [headers], its format,
  /// its transport as `lineId` and the lease of its `auth_key`. A bad or
  /// missing URL only drops its line. A quality the broadcast does not
  /// offer is `StreamUnavailable`.
  static LivePlayUrlResolution resolution(KilakilaRoomData data, LivePlayQuality quality) {
    final wanted = qualityIdFromLegacy('${quality.selectionId}');
    final offered = qualities(data).where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (offered == null) throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    LivePlayLine line(String url) {
      final format = Uri.parse(url).path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;
      return LivePlayLine(
        url,
        headers: headers,
        format: format,
        lineId: format.name,
        lease: lease(url, issuedAt: data.issuedAt),
      );
    }

    return LivePlayUrlResolution.lines([
      for (final url in offered.data! as List<String>) line(url),
    ], appliedQualityData: offered.selectionId);
  }

  /// [value] when it is the pull URL of [format] for [broadcastId] (3.x's
  /// `mediaUrl`): `https://pull.live.hongrenshuo.com.cn/hrs/<id>.flv` or
  /// `.m3u8`, the default port, no user info or fragment, exactly one
  /// non-empty `auth_key`; the text is kept as written. Else null (the
  /// `rtmpPlayUrl` and the push address never qualify).
  static String? mediaUrl(Object? value, {required String broadcastId, required StreamFormat format}) {
    if (format == StreamFormat.other) return null;
    final text = _text(value);
    if (text.length > 8192) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != mediaHost ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.path != '/hrs/$broadcastId.${format == StreamFormat.flv ? 'flv' : 'm3u8'}') {
      return null;
    }
    try {
      final auth = uri.queryParametersAll['auth_key'];
      if (auth == null || auth.length != 1 || auth.single.isEmpty || auth.single.length > 1024) return null;
      return text;
    } on FormatException {
      return null;
    }
  }

  /// The lease of a pull URL received at [issuedAt]: it stops at the first
  /// field of its `auth_key` (`<Unix seconds>-<rand>-<uid>-<md5>`, 30 days
  /// after issue) and is renewed [leaseLead] (at most a quarter of its
  /// lifetime) before. An HLS playlist is fetched again and again, so its
  /// expiry ends playback; an established FLV connection keeps flowing.
  /// Null without a future expiry. (3.x had no lease for KilaKila.)
  static PlayLease? lease(String url, {required DateTime issuedAt}) {
    final uri = Uri.tryParse(url);
    final String? key;
    try {
      key = uri?.queryParameters['auth_key'];
    } on FormatException {
      return null;
    }
    final expires = int.tryParse(key?.split('-').first ?? '');
    if (uri == null || expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = Duration(microseconds: math.min(leaseLead.inMicroseconds, lifetime.inMicroseconds ~/ 4));
    return PlayLease(
      refreshAt: expiresAt.subtract(lead),
      expiresAt: expiresAt,
      cutsConnection: uri.path.endsWith('.m3u8'),
    );
  }

  // Helpers -------------------------------------------------------------------

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  /// 3.x's `_text`: a string trimmed, anything else empty.
  static String _text(Object? value) => value is String ? value.trim() : '';

  /// 3.x's `_integer`: an int, or a string that parses as one.
  static int? _integer(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  static int _nonNegative(Object? value, String what) {
    final number = _integer(value);
    if (number == null || number < 0) throw ApiChanged(_site, '$what: $value');
    return number;
  }

  /// 3.x's `_id`: a positive int within JavaScript's exact range (a larger
  /// number may already have been rounded by the server), or an id string.
  static String _id(Object? value, String what) {
    if (value is int && value > 0 && value <= 9007199254740991) return '$value';
    if (value is String && isId(value)) return value;
    throw ApiChanged(_site, '$what: $value');
  }

  /// An image address, made absolute (`normalizeImageUrl`); one with user
  /// info is dropped, as 3.x's `_picture` did.
  static String _picture(Object? value) {
    final url = normalizeImageUrl(value is String ? value : null);
    return url.isEmpty || (Uri.tryParse(url)?.userInfo.isNotEmpty ?? true) ? '' : url;
  }
}

// A small reader for the search page ------------------------------------------

/// Enough of an HTML tree for the search page, in place of 3.x's
/// package:html: comments, scripts and styles are dropped, elements nest by
/// their tags (void elements never hold children, end tags close the
/// nearest open element of their name), and text and attribute values have
/// their character references decoded.
final class _Html {
  new _(this.source, this.name, this.attributes, this.start);

  /// The tree of [html] under a nameless root.
  factory parse(String html) {
    final source = html
        .replaceAll(RegExp(r'<!--[\s\S]*?(?:-->|$)'), '')
        .replaceAll(RegExp(r'<(script|style)\b[^>]*>[\s\S]*?(?:</\1\s*>|$)', caseSensitive: false), '');
    final root = _Html._(source, '', const {}, 0);
    final open = <_Html>[root];
    for (final tag in _tag.allMatches(source)) {
      final name = tag.group(2)!.toLowerCase();
      if (tag.group(1)!.isEmpty) {
        final element = _Html._(source, name, _attributes(tag.group(3)!), tag.end);
        open.last.children.add(element);
        if (_void.contains(name)) {
          element.end = tag.end;
        } else {
          open.add(element);
        }
        continue;
      }
      final index = open.lastIndexWhere((element) => element.name == name);
      if (index <= 0) continue;
      while (open.length > index) {
        open.removeLast().end = tag.start;
      }
    }
    for (final element in open) {
      element.end = source.length;
    }
    return root;
  }

  static final RegExp _tag = RegExp('<(/?)([A-Za-z][A-Za-z0-9:-]*)((?:[^>"\']|"[^"]*"|\'[^\']*\')*)>');
  static final RegExp _attribute = RegExp(r'''([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''');
  static const Set<String> _void = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'source',
    'track',
    'wbr',
  };

  static Map<String, String> _attributes(String text) {
    final attributes = <String, String>{};
    for (final match in _attribute.allMatches(text)) {
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attributes.putIfAbsent(match.group(1)!.toLowerCase(), () => decodeHtmlEntities(value));
    }
    return attributes;
  }

  final String source;
  final String name;
  final Map<String, String> attributes;
  final int start;
  int end = 0;
  final List<_Html> children = [];

  /// The text inside the element, tags removed and references decoded.
  String get text => decodeHtmlEntities(source.substring(start, end).replaceAll(RegExp('<[^>]*>'), ''));

  Iterable<_Html> get _descendants sync* {
    for (final child in children) {
      yield child;
      yield* child._descendants;
    }
  }

  /// The first descendant, in document order, with class [name].
  _Html? firstWithClass(String name) => _descendants
      .where((element) => (element.attributes['class'] ?? '').split(RegExp(r'\s+')).contains(name))
      .firstOrNull;

  /// The first descendant element called [tag].
  _Html? first(String tag) => _descendants.where((element) => element.name == tag).firstOrNull;
}
