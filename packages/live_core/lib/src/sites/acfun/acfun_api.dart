import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'acfun';
const _live = 'https://live.acfun.cn';

/// Author ids (3.x's `normalizeAuthorId`): a positive decimal number of at
/// most 20 digits, no leading zero.
final RegExp _authorId = RegExp(r'^[1-9][0-9]{0,19}$');

/// "N 粉丝" on a search card (3.x's pattern; `\s` includes the `&ensp;`).
final RegExp _followers = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?[万亿]?)\s*粉丝\s*$');

/// The anonymous visitor session of `visitor/login`: what `startPlay` is
/// asked with, and what the danmaku link registers with.
@immutable
final class AcfunVisitor {
  /// Creates a session.
  const new({required this.userId, required this.deviceId, required this.token, this.security});

  /// The visitor's user id (`userId`).
  final String userId;

  /// The `_did` cookie the visitor logged in with (`web_` + 16 letters or
  /// digits), sent again as `did`.
  final String deviceId;

  /// The service token (`acfun.api.visitor_st`).
  final String token;

  /// `acSecurity`, the base64 key of the danmaku link's register exchange;
  /// null when the answer has none. Streams never need it (the archived v4
  /// required it and failed streams without it).
  final String? security;

  /// Diagnostics without the token and the key.
  @override
  String toString() => 'AcfunVisitor($userId, security: ${security == null ? 'none' : '<redacted>'})';
}

/// One quality of a `startPlay` answer: its id (`qualityType`, else
/// `id:<id>`), label, order and one URL per adaptive manifest (CDN).
@immutable
final class AcfunQuality {
  /// Creates a quality.
  new({required this.id, required this.label, required this.rank, required List<String> urls})
    : urls = List.unmodifiable(urls);

  /// Stable id (`BLUE_RAY`, `SUPER`, `HIGH`, `STANDARD`).
  final String id;

  /// Label (`name`, like “蓝光 8M”; 3.x's fallback by type without one).
  final String label;

  /// Order (3.x's rank): `1000000 + level` when the server gives a level,
  /// else the bitrate, so a quality without a level never outranks one with
  /// it (REG-ACFUN-005).
  final int rank;

  /// Signed URLs, one per manifest, in answer order.
  final List<String> urls;
}

/// The broadcast behind a live room, apart from its identity (the author
/// id): the `startPlay` answer the streams come from (3.x's
/// `AcfunPlayback` in `data`).
@immutable
final class AcfunRoomData {
  /// Creates the data.
  new({required this.liveId, required List<AcfunQuality> qualities, required this.issuedAt, this.startedAt})
    : qualities = List.unmodifiable(qualities);

  /// The broadcast id (`liveId`), new with every broadcast.
  final String liveId;

  /// Qualities, best first.
  final List<AcfunQuality> qualities;

  /// When the answer arrived: the origin of the URLs' leases.
  final DateTime issuedAt;

  /// When the broadcast started (`liveStartTime`, the `createTime` of
  /// `live/info`), or null.
  final DateTime? startedAt;

  /// The quality of id [id], or null.
  AcfunQuality? quality(Object? id) => qualities.where((quality) => quality.id == '$id').firstOrNull;
}

/// One gift of AcFun's gift table (`gift/list`, D07.6): what the danmaku's
/// gift signals, which carry only the id, are named and priced by.
@immutable
final class AcfunGiftInfo {
  /// Creates the entry.
  const new({required this.id, required this.name, required this.price, this.banana = false, this.iconUrl});

  /// `giftId`, the id the gift signal sends.
  final String id;

  /// `giftName` (`香蕉`, `快乐水`).
  final String name;

  /// `giftPrice`: the price of one, in AC coins (`payWalletType` 1, ten to a
  /// yuan), or in bananas for a [banana] gift; 0 or more.
  final int price;

  /// Paid in bananas (`payWalletType` 2): the platform's free currency, so
  /// the gift is free.
  final bool banana;

  /// The first `webpPicList` URL, else the first of `pngPicList`.
  final Uri? iconUrl;

  @override
  bool operator ==(Object other) =>
      other is AcfunGiftInfo &&
      other.id == id &&
      other.name == name &&
      other.price == price &&
      other.banana == banana &&
      other.iconUrl == iconUrl;

  @override
  int get hashCode => Object.hash(id, name, price, banana, iconUrl);

  @override
  String toString() => 'AcfunGiftInfo($id $name, $price ${banana ? 'bananas' : 'AC coins'})';
}

/// The gifts of an AcFun room's danmaku by gift id ([AcfunApi.giftList],
/// D07.6).
@immutable
final class AcfunGiftCatalog {
  /// Creates the catalogue.
  new(Map<String, AcfunGiftInfo> gifts) : _gifts = Map.unmodifiable(gifts);

  const new _empty() : _gifts = const {};

  /// No gifts.
  static const AcfunGiftCatalog empty = AcfunGiftCatalog._empty();

  final Map<String, AcfunGiftInfo> _gifts;

  /// The gift of [id], or null.
  AcfunGiftInfo? operator [](String id) => _gifts[id];

  /// The gift ids, in the table's order.
  Iterable<String> get ids => _gifts.keys;

  /// How many gifts.
  int get length => _gifts.length;

  /// Whether it has no gifts.
  bool get isEmpty => _gifts.isEmpty;

  @override
  String toString() => 'AcfunGiftCatalog($length)';
}

/// What the danmaku connection needs to join one broadcast. 3.x had no
/// AcFun danmaku (`EmptyDanmaku`); these are the values the web client's
/// link protocol uses (spec/sites/acfun.md §7), all from the requests
/// room entry makes anyway, for the danmaku module (M5) to use.
@immutable
final class AcfunDanmakuArgs {
  /// Creates the arguments.
  new({
    required this.authorId,
    required this.liveId,
    required this.visitor,
    required List<String> tickets,
    this.enterRoomAttach = '',
    this.refresh,
    this.gifts,
  }) : tickets = List.unmodifiable(tickets);

  /// The room (author id).
  final String authorId;

  /// The broadcast (`liveId`).
  final String liveId;

  /// The visitor session `startPlay` was asked with; its [AcfunVisitor.security]
  /// may be null, which fails only the danmaku register exchange.
  final AcfunVisitor visitor;

  /// `availableTickets`, tried in order.
  final List<String> tickets;

  /// `enterRoomAttach`, echoed when entering the room.
  final String enterRoomAttach;

  /// Handshake headers of the web client (UA and `Origin`).
  Map<String, String> get headers => const {'user-agent': AcfunApi.userAgent, 'origin': AcfunApi.origin};

  /// A new visitor session and broadcast (tickets expire; a new connection
  /// starts from a new session).
  final Future<AcfunDanmakuArgs> Function()? refresh;

  /// The room's gift table (D07.6), which the connection asks for once in
  /// the background when it starts; never throws (an empty catalogue when
  /// it cannot be had). Null: no gift names or prices.
  final Future<AcfunGiftCatalog> Function()? gifts;

  /// Diagnostics without the session secrets.
  @override
  String toString() => 'AcfunDanmakuArgs($authorId, $liveId, ${tickets.length} tickets, $visitor)';
}

/// Pure parsing of AcFun responses (3.x's `AcfunApi`, `AcfunSite.parseRoom`
/// and `AcfunSearchClient.parsePage`). Each function takes the response text
/// and status and returns 3.x's models or throws a `SiteError`.
abstract final class AcfunApi {
  /// Desktop Chrome 140, the UA 3.x sent with every AcFun request and to
  /// the media CDN.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// The live site: `Origin` of media requests and the danmaku handshake.
  static const String origin = _live;

  /// `Referer` of API and media requests.
  static const String referer = '$_live/';

  /// The headers 3.x sent with every API request (`playHeaders`), names in
  /// lower case.
  static const Map<String, String> apiHeaders = {'user-agent': userAgent, 'referer': referer};

  /// The headers of author search; without a browser UA the site answers
  /// 403 (REG-ACFUN-006).
  static const Map<String, String> searchHeaders = {'user-agent': userAgent, 'referer': 'https://www.acfun.cn/search'};

  /// Media request headers (3.x's `PlaybackHeaderResolver`: `playHeaders`
  /// plus `Origin`).
  static const Map<String, String> mediaHeaders = {'user-agent': userAgent, 'referer': referer, 'origin': origin};

  /// Authors a search page holds.
  static const int searchPageSize = 30;

  /// `startPlay`'s answer for a broadcast that has ended (`直播已关播`).
  static const int closedResult = 129004;

  /// `startPlay`'s answer for a paid show the viewer has no ticket for (the
  /// web player's `liveNotPaid`; the anonymous visitor never has one).
  static const int paidShowResult = 380205;

  /// The filter id of `全部`, which lists every live room: the
  /// recommendations, not an area (upgrade 10-2).
  static const int allFilterId = 0;

  /// The live page of author [authorId] (3.x's `link`).
  static String roomPageUrl(String authorId) => '$_live/live/${authorId.trim()}';

  /// Whether [value] is an author id.
  static bool isAuthorId(String value) => _authorId.hasMatch(value);

  /// The `filters` query value of an area: its filter type and id (3.x's
  /// `AcfunCategoryFilter.encode`).
  static String filterQuery({required int type, required int id}) => jsonEncode([
    {'filterType': type, 'filterId': id},
  ]);

  /// When a broadcast started, from `createTime` or `liveStartTime` (epoch
  /// milliseconds); null for 0, negatives, values that are not milliseconds
  /// (before 2001 or after 2286, such as a time in seconds) and anything
  /// that is not an integer.
  static DateTime? startedAt(Object? value) => switch (jsonInt(value)) {
    final int milliseconds when milliseconds >= 1000000000000 && milliseconds < 10000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    _ => null,
  };

  // Catalog -------------------------------------------------------------------

  /// `api/channel/list` (`count=1`): the areas of `channelFilters` in answer
  /// order, one per (type, id). `全部` ([allFilterId]) lists the same rooms
  /// as the recommendations and is left out (upgrade 10-2; 3.x listed it).
  /// [typeName] is the parent category's name (3.x used the site's display
  /// name). The list answer must be a success like any page.
  static List<LiveArea> areas(String body, {required String typeName, int status = 200}) {
    final root = _root(body, status: status, what: 'channel/list');
    _listData(root);
    final filters = _object(root['channelFilters']);
    final groups = filters?['liveChannelDisplayFilters'];
    if (groups is! List) throw ApiChanged(_site, 'channel/list: no channelFilters (${_snippet(body)})');
    final seen = <String>{};
    final areas = <LiveArea>[];
    for (final group in groups) {
      final list = _object(group)?['displayFilters'];
      if (list is! List) continue;
      for (final raw in list) {
        final filter = _object(raw);
        if (filter == null) continue;
        final type = jsonCount(filter['filterType']);
        final id = jsonCount(filter['filterId']);
        final name = _text(filter['name']);
        if (type == null || id == null || id == allFilterId || name.isEmpty || !seen.add('$type:$id')) continue;
        areas.add(
          LiveArea(
            platform: _site,
            areaType: '$type',
            typeName: typeName,
            areaId: '$id',
            areaName: name,
            areaPic: normalizeImageUrl(filter['cover']),
          ),
        );
      }
    }
    if (areas.isEmpty) throw ApiChanged(_site, 'channel/list: no area filters (${_snippet(body)})');
    return areas;
  }

  /// `api/channel/list`: the rooms of one page and the opaque cursor of the
  /// next; `no_more` or an empty cursor ends the list. A card whose author
  /// id or user does not check out is left out (3.x failed the page).
  static ({List<LiveRoom> rooms, String? next}) directory(String body, {int status = 200}) {
    final data = _listData(_root(body, status: status, what: 'channel/list'));
    final rooms = <LiveRoom>[
      for (final raw in data.list)
        if (_object(raw) case final item?)
          if (_text(item['authorId']) case final id when isAuthorId(id))
            if (_identity(item, id)) _room(item, id),
    ];
    return (rooms: rooms, next: data.cursor.isEmpty || data.cursor == 'no_more' ? null : data.cursor);
  }

  // Rooms ---------------------------------------------------------------------

  /// `api/live/info?authorId=`: the room of [authorId] (the requested id
  /// stays the identity). Live when it has a `liveId`, offline otherwise.
  /// An unknown author (`user.id` "0", no user or no name) is `NotFound`; a
  /// `result` other than 0 or an answer for another author `ApiChanged`.
  static LiveRoom roomDetail(String body, {required String authorId, int status = 200}) {
    final root = _root(body, status: status, what: 'live/info');
    final result = jsonInt(root['result']);
    if (result != 0) throw ApiChanged(_site, 'live/info: result ${root['result']} (${_snippet(body)})');
    final user = _object(root['user']);
    final userId = _text(user?['id']);
    if (user == null || user.isEmpty || userId.isEmpty || userId == '0' || _text(user['name']).isEmpty) {
      throw NotFound(_site, 'live/info: no author $authorId');
    }
    if (!_identity(root, authorId)) {
      throw ApiChanged(_site, 'live/info: answered author ${root['authorId']}/$userId for $authorId');
    }
    final signature = _text(user['signature']);
    return _room(root, authorId).copyWith(introduction: signature.isEmpty ? null : decodeHtmlEntities(signature));
  }

  /// A room card or detail (3.x's `parseRoom`): the online count as
  /// concurrent viewers, the followers as the site writes them. A live
  /// room also has its start (`createTime`, upgrade 10-3) and restriction
  /// ([_restriction]); an offline one neither.
  static LiveRoom _room(Map<String, dynamic> item, String authorId) {
    final user = _object(item['user']) ?? const <String, dynamic>{};
    final covers = item['coverUrls'];
    final count = jsonCount(item['onlineCount']);
    final viewers = count == null ? '' : '$count';
    final type = _object(item['type']);
    final live = _text(item['liveId']).isNotEmpty;
    return LiveRoom(
      platform: _site,
      roomId: authorId,
      userId: authorId,
      link: roomPageUrl(authorId),
      nick: _text(user['name']),
      avatar: normalizeImageUrl(user['headUrl']),
      title: _text(item['title']),
      cover: covers is List && covers.isNotEmpty ? normalizeImageUrl(covers.first) : '',
      area: type == null ? '' : _text(type['name']),
      onlineViewers: viewers,
      watching: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: _text(user['fanCountValue']),
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      startedAt: live ? startedAt(item['createTime']) : null,
      restriction: live ? _restriction(item) : null,
    );
  }

  /// A live room's restriction, read from the fields the web player reads
  /// (`live/info` is its `liveInfo`; list cards have the same shape): a paid
  /// show (`paidShowUuid`, the show a ticket is bought for) is
  /// [LiveRestriction.paid] unless the viewer bought it
  /// (`paidShowUserBuyStatus`, never true for the anonymous visitor). An
  /// answer with the paid-show fields and no show has no restriction; one
  /// without them says nothing (null).
  static LiveRestriction? _restriction(Map<String, dynamic> item) {
    if (_text(item['paidShowUuid']).isNotEmpty) {
      return item['paidShowUserBuyStatus'] == true ? LiveRestriction.none : LiveRestriction.paid;
    }
    return item.containsKey('paidShowUserBuyStatus') ? LiveRestriction.none : null;
  }

  /// Whether [item] is the room of [authorId]: the echoed `authorId` and
  /// `user.id` are it, and the user has a name (3.x's identity check).
  static bool _identity(Map<String, dynamic> item, String authorId) {
    final user = _object(item['user']);
    return _text(item['authorId']) == authorId && _text(user?['id']) == authorId && _text(user?['name']).isNotEmpty;
  }

  // Gifts (D07.6) ---------------------------------------------------------------

  /// `gift/list` for [visitor]'s session; a form POST with `visitorId` and
  /// `liveId` (the archived v4's request; the web client's too).
  static Uri giftListUrl(AcfunVisitor visitor) => Uri.https('api.kuaishouzt.com', '/rest/zt/live/web/gift/list', {
    'subBiz': 'mainApp',
    'kpn': 'ACFUN_APP',
    'kpf': 'PC_WEB',
    'userId': visitor.userId,
    'did': visitor.deviceId,
    'acfun.api.visitor_st': visitor.token,
  });

  /// `gift/list`: `data.giftList`, each with `giftId`, `giftName`,
  /// `giftPrice` and `payWalletType` (1 AC coins, 2 bananas) and the
  /// pictures (`webpPicList`, `pngPicList`: `[{url}]`). An entry without an
  /// id or a name is left out; a price that is not a count is 0. A `result`
  /// other than 1 is `RiskControl`, no list `ApiChanged`.
  static AcfunGiftCatalog giftList(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'gift/list');
    final result = jsonInt(root['result']);
    if (result != 1) throw RiskControl(_site, detail: 'gift/list: result ${root['result']}');
    final list = _object(root['data'])?['giftList'];
    if (list is! List) throw const ApiChanged(_site, 'gift/list: no giftList');
    final gifts = <String, AcfunGiftInfo>{};
    for (final value in list) {
      final item = _object(value);
      final id = jsonCount(item?['giftId']);
      final name = jsonString(item?['giftName']);
      if (item == null || id == null || name == null) continue;
      gifts['$id'] = AcfunGiftInfo(
        id: '$id',
        name: name,
        price: jsonCount(item['giftPrice']) ?? 0,
        banana: jsonInt(item['payWalletType']) == 2,
        iconUrl: _picture(item['webpPicList']) ?? _picture(item['pngPicList']),
      );
    }
    return AcfunGiftCatalog(gifts);
  }

  /// The first https `url` of a picture list.
  static Uri? _picture(Object? list) {
    if (list is! List) return null;
    for (final entry in list) {
      final url = jsonUrl(_object(entry)?['url']);
      if (url != null && url.scheme == 'https') return url;
    }
    return null;
  }

  // Visitor session and streams -----------------------------------------------

  /// `visitor/login`: the anonymous session, logged in with device id
  /// [deviceId]. A `result` other than 0 is `RiskControl`; no user id or
  /// token `ApiChanged`. `acSecurity` is optional (only danmaku uses it).
  static AcfunVisitor visitor(String body, {required String deviceId, int status = 200}) {
    final root = _root(body, status: status, what: 'visitor/login');
    final result = jsonInt(root['result']);
    if (result == null) throw ApiChanged(_site, 'visitor/login: no result (${_snippet(body)})');
    if (result != 0) throw RiskControl(_site, detail: 'visitor/login: result $result');
    final userId = _text(root['userId']);
    final token = _text(root['acfun.api.visitor_st']);
    if (!isAuthorId(userId) || token.isEmpty) throw const ApiChanged(_site, 'visitor/login: incomplete session');
    final security = _text(root['acSecurity']);
    return AcfunVisitor(userId: userId, deviceId: deviceId, token: token, security: security.isEmpty ? null : security);
  }

  /// `startPlay`: the broadcast, its qualities and the danmaku tickets.
  /// `result` 1 is live, with no restriction; [paidShowResult] (a paid
  /// show without a ticket) is live but restricted: no broadcast data,
  /// [LiveRestriction.paid] (3.x: a failed room). [closedResult] (the
  /// broadcast ended) is `StreamUnavailable`; any other `RiskControl` (the
  /// session was refused; the caller retries once with a new one).
  /// [issuedAt] is when the answer arrived.
  static ({AcfunRoomData? data, LiveRestriction restriction, List<String> tickets, String enterRoomAttach}) startPlay(
    String body, {
    required DateTime issuedAt,
    int status = 200,
  }) {
    final root = _root(body, status: status, what: 'startPlay');
    final result = jsonInt(root['result']);
    if (result == null) throw ApiChanged(_site, 'startPlay: no result (${_snippet(body)})');
    if (result == closedResult) throw StreamUnavailable(_site, 'startPlay: ${_text(root['error_msg'])} ($result)');
    if (result == paidShowResult) {
      return (data: null, restriction: LiveRestriction.paid, tickets: const [], enterRoomAttach: '');
    }
    if (result != 1) throw RiskControl(_site, detail: 'startPlay: result $result ${_text(root['error_msg'])}');
    final data = _object(root['data']);
    final liveId = _text(data?['liveId']);
    if (data == null || liveId.isEmpty) throw ApiChanged(_site, 'startPlay: no liveId (${_snippet(body)})');
    final tickets = data['availableTickets'];
    return (
      data: AcfunRoomData(
        liveId: liveId,
        qualities: qualities(data['videoPlayRes']),
        issuedAt: issuedAt,
        startedAt: startedAt(data['liveStartTime']),
      ),
      restriction: LiveRestriction.none,
      tickets: [for (final ticket in tickets is List ? tickets : const []) ?jsonString(ticket)],
      enterRoomAttach: _text(data['enterRoomAttach']),
    );
  }

  /// `videoPlayRes` (a JSON string or object): the qualities of every
  /// adaptive manifest, 3.x's rules: hidden representations and URLs that
  /// are not plain http(s) left out; one quality per id with the first
  /// label, the highest rank and every URL once, in manifest order; best
  /// first by rank, then by id. A representation without an id is left out
  /// (3.x failed the whole answer). No `liveAdaptiveManifest` list is
  /// `ApiChanged`; nothing playable `StreamUnavailable`.
  static List<AcfunQuality> qualities(Object? videoPlayRes) {
    var value = videoPlayRes;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        value = null;
      }
    }
    final manifests = _object(value)?['liveAdaptiveManifest'];
    if (manifests is! List) throw const ApiChanged(_site, 'startPlay: no liveAdaptiveManifest');
    final found = <String, ({String label, int rank, List<String> urls})>{};
    for (final manifest in manifests) {
      final representations = _object(_object(manifest)?['adaptationSet'])?['representation'];
      if (representations is! List) continue;
      for (final raw in representations) {
        final item = _object(raw);
        if (item == null || item['hidden'] == true) continue;
        final url = _text(item['url']);
        final uri = Uri.tryParse(url);
        if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) continue;
        if (uri.userInfo.isNotEmpty) continue;
        final type = _text(item['qualityType']);
        final number = jsonInt(item['id']);
        final id = type.isNotEmpty ? type : (number == null ? '' : 'id:$number');
        if (id.isEmpty) continue;
        final name = _text(item['name']);
        final label = name.isNotEmpty
            ? name
            : switch (type) {
                'STANDARD' => '高清',
                'HIGH' => '超清',
                'SUPER' => '蓝光',
                'BLUE_RAY' => '高码率',
                _ => '画质 $id',
              };
        final rank = qualityRank(level: jsonInt(item['level']), bitrate: jsonInt(item['bitrate']));
        final previous = found[id];
        found[id] = (
          label: previous?.label ?? label,
          rank: previous == null || rank > previous.rank ? rank : previous.rank,
          urls: [...?previous?.urls, if (!(previous?.urls.contains(url) ?? false)) url],
        );
      }
    }
    if (found.isEmpty) throw const StreamUnavailable(_site, 'startPlay: no playable representation');
    final ordered = found.entries.toList()
      ..sort((a, b) {
        final byRank = b.value.rank.compareTo(a.value.rank);
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
    return [
      for (final MapEntry(:key, :value) in ordered)
        AcfunQuality(id: key, label: value.label, rank: value.rank, urls: value.urls),
    ];
  }

  /// The order of a representation (3.x's rank): `level` and `bitrate` are
  /// different scales, so a known level ranks `1000000 + level` (capped),
  /// above every representation that only has a bitrate, which ranks by the
  /// bitrate (REG-ACFUN-005). The archived v4 compared `level ?? bitrate`
  /// directly, which put an 8000 kbps representation without a level above
  /// the level-130 source.
  static int qualityRank({int? level, int? bitrate}) {
    if (level != null && level >= 0) return 1000000 + level.clamp(0, 999999);
    return (bitrate ?? 0).clamp(0, 999999);
  }

  /// The qualities of [data] as 3.x listed them: label, id, rank as the
  /// sort value and the URLs as data.
  static List<LivePlayQuality> playQualities(AcfunRoomData data) => [
    for (final quality in data.qualities)
      LivePlayQuality(quality: quality.label, id: quality.id, sort: quality.rank, data: quality.urls),
  ];

  /// The lines of quality [qualityId] of [data]: every URL in answer order
  /// with the media headers, FLV or HLS by path, the CDN host as line id
  /// and the lease of its signature. The quality is the one asked for (the
  /// URLs are that quality's own). A quality the answer does not have is
  /// `StreamUnavailable` (3.x never fell back to another one).
  static LivePlayUrlResolution resolution(AcfunRoomData data, {required Object? qualityId}) {
    final quality = data.quality(qualityId);
    if (quality == null) throw StreamUnavailable(_site, 'startPlay: no quality $qualityId');
    final hosts = <String, int>{};
    final lines = <LivePlayLine>[];
    for (final url in quality.urls) {
      final uri = Uri.parse(url);
      final repeat = hosts.update(uri.host, (count) => count + 1, ifAbsent: () => 1);
      lines.add(
        LivePlayLine(
          url,
          headers: mediaHeaders,
          format: uri.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv,
          lineId: repeat == 1 ? uri.host : '${uri.host}#$repeat',
          lease: lease(uri, data.issuedAt),
        ),
      );
    }
    return LivePlayUrlResolution.lines(lines, appliedQualityData: quality.id);
  }

  /// The lease of a signed media URL: the first field of `auth_key` is its
  /// expiry in Unix seconds (30 days after issue). Renewed 10 minutes
  /// before (at most a quarter of the lifetime); an established connection
  /// is not known to be cut. Null without a key or once it has expired.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final seconds = int.tryParse(url.queryParameters['auth_key']?.split('-').first ?? '');
    if (seconds == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    final lead = quarter < const Duration(minutes: 10) ? quarter : const Duration(minutes: 10);
    return PlayLease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt);
  }

  // Search --------------------------------------------------------------------

  /// `www.acfun.cn/search?type=user&ajaxpipe=1`, server page [page]: the
  /// authors (live or not) of the BigPipe answer's `html` fragment and the
  /// total (`data-total`). Nothing in the answer is run.
  ///
  /// 3.x's checks on the answer stay: no total, more cards than the total
  /// leaves for this page, or no cards without the `empty-page` marker is
  /// `ApiChanged` (a blocked or cut answer is not "no results"). A card
  /// whose author, link or name does not check out, or that repeats an
  /// author, is left out (3.x failed the page).
  static ({List<LiveRoom> rooms, int total}) searchPage(String body, {required int page, int status = 200}) {
    _checkStatus(body, status: status, what: 'search');
    final end = body.indexOf('/*<!-- fetch-stream -->*/');
    final Object? decoded;
    try {
      decoded = jsonDecode(end < 0 ? body : body.substring(0, end));
    } on FormatException {
      throw ApiChanged(_site, 'search: not a JSON answer (${_snippet(body)})');
    }
    final content = _object(decoded)?['html'];
    if (content is! String) throw ApiChanged(_site, 'search: no html (${_snippet(body)})');
    final fragment = HtmlElement.parseFragment(content);
    final totalNode = fragment.query((e) => e.hasClass('total-num') && e.attributes.containsKey('data-total'));
    if (totalNode == null) throw ApiChanged(_site, 'search: no total (${_snippet(content)})');
    final cards = fragment.queryAll((e) => e.hasClass('search-up')).toList();
    final empty = fragment.query((e) => e.hasClass('empty-page')) != null;
    final totalText = totalNode.attributes['data-total']!.trim();
    var total = jsonInt(totalText);
    if (total == null &&
        totalText.isEmpty &&
        totalNode.text.replaceAll(RegExp(r'\s'), '') == '共0条结果' &&
        empty &&
        cards.isEmpty) {
      total = 0;
    }
    final left = total == null ? 0 : total - (page - 1) * searchPageSize;
    if (total == null ||
        total < 0 ||
        cards.length > searchPageSize ||
        cards.length > (left < 0 ? 0 : (left > searchPageSize ? searchPageSize : left))) {
      throw ApiChanged(_site, 'search: ${cards.length} cards for total $totalText on page $page');
    }
    if (cards.isEmpty && !empty) throw const ApiChanged(_site, 'search: no cards and no empty-page marker');
    final seen = <String>{};
    final rooms = <LiveRoom>[for (final card in cards) ?_searchCard(card, seen)];
    return (rooms: rooms, total: total);
  }

  /// One author card (3.x's checks): the id of `data-up-exposure-log`, the
  /// name link to `/u/<id>` on acfun.cn, live when `is_on_live` holds a
  /// broadcast id, unknown when it is neither text nor a flag.
  static LiveRoom? _searchCard(HtmlElement card, Set<String> seen) {
    Object? meta;
    try {
      meta = jsonDecode(card.attributes['data-up-exposure-log'] ?? '');
    } on FormatException {
      return null;
    }
    final log = _object(meta);
    final id = _text(log?['up_id']);
    if (log == null || !isAuthorId(id)) return null;
    final anchor = card.query(
      (e) => e.tag == 'a' && e.ancestors.takeWhile((a) => a != card.parent).any((a) => a.hasClass('up__main__name')),
    );
    final href = Uri.tryParse(anchor?.attributes['href'] ?? '');
    final name = anchor?.text.trim() ?? '';
    if (anchor == null ||
        href == null ||
        (href.hasScheme && !(href.isScheme('http') || href.isScheme('https'))) ||
        (href.hasAuthority && href.host != 'www.acfun.cn' && href.host != 'acfun.cn') ||
        href.userInfo.isNotEmpty ||
        href.path != '/u/$id' ||
        name.isEmpty ||
        !seen.add(id)) {
      return null;
    }
    final flag = log['is_on_live'];
    final live = flag is String ? flag.trim().isNotEmpty : (flag is bool ? flag : null);
    final followerText = card.query((e) => e.hasClass('info__danmaku-count'))?.text ?? '';
    final avatar = card.query((e) => e.tag == 'img' && e.hasClass('up__avatar'));
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: id,
      link: roomPageUrl(id),
      nick: name,
      avatar: normalizeImageUrl(avatar?.attributes['src']),
      introduction: card.query((e) => e.hasClass('up__main__intro'))?.text.trim(),
      watching: '',
      followers: _followers.firstMatch(followerText)?.group(1) ?? '',
      audienceMetricType: AudienceMetricType.unknown,
      liveStatus: switch (live) {
        true => LiveStatus.live,
        false => LiveStatus.offline,
        null => LiveStatus.unknown,
      },
    );
  }
}

/// A field as 3.x read it (`text`): a trimmed string, a number's digits,
/// anything else empty.
String _text(Object? value) => value is String ? value.trim() : (value is num ? '$value' : '');

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// HTTP 429 → `RateLimited`; 5xx → `NetworkFailure`; 401 and 403 →
/// `RiskControl`; any other non-2xx → `ApiChanged`. (3.x reported every
/// failed status as a transport error.)
void _checkStatus(String body, {required int status, required String what}) {
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what: HTTP $status');
  if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
}

/// The JSON object of an answer; see [_checkStatus] for the statuses.
Map<String, dynamic> _root(String body, {required int status, required String what}) {
  _checkStatus(body, status: status, what: what);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  return decoded;
}

/// `channelListData` (or the answer itself) of a list answer, 3.x's
/// envelope: `result` 0, a `liveList` list and a `pcursor` string or number.
({List<Object?> list, String cursor}) _listData(Map<String, dynamic> root) {
  final data = _object(root['channelListData']) ?? root;
  final result = jsonInt(data['result']);
  if (result != 0) throw ApiChanged(_site, 'channel/list: result ${data['result']}');
  final list = data['liveList'];
  final cursor = data['pcursor'];
  if (list is! List || (cursor is! String && cursor is! int)) {
    throw const ApiChanged(_site, 'channel/list: no liveList or pcursor');
  }
  return (list: list.cast<Object?>(), cursor: '$cursor'.trim());
}
