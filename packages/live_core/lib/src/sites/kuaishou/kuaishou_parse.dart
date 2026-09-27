import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'kuaishou';
const _origin = 'https://live.kuaishou.com';

/// Caption prefix of a loop room: live on the room page, but playing a
/// recording (the KPL highlights card, recorded 2026-09-27).
const _replayPrefix = '【回放】';

/// §6 play headers: the fixed desktop Chrome user agent sent to the CDN.
const _playUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// §6 lease: how long before the signature expiry a fresh URL is fetched.
const _refreshLead = Duration(minutes: 10);

/// One quality tier: its identity and the line URLs with their codec.
typedef _Tier = ({Quality quality, List<({Uri url, String? codec})> lines});

/// Pure parsing of Kuaishou responses (spec/sites/kuaishou.md). Every
/// function takes the raw response text the adapter received and either
/// returns domain values or throws a `SiteError`.
///
/// Cursors are `page` or `page:token`, where the token is the non-gameboard
/// `data.cursor` or the author search `ussid`; only this class reads them, so
/// the request builders ([categoryUri], [areaRoomsUri], [searchUri]) live here
/// too.
abstract final class KuaishouParse {
  /// §2 the eight fixed first-level categories; their areas come from
  /// [areaPage].
  static const List<Category> topCategories = [
    Category(id: '1', name: '热门'),
    Category(id: '2', name: '网游'),
    Category(id: '3', name: '单机'),
    Category(id: '4', name: '手游'),
    Category(id: '5', name: '棋牌'),
    Category(id: '6', name: '娱乐'),
    Category(id: '7', name: '综合'),
    Category(id: '8', name: '文化'),
  ];

  // ---------------------------------------------------------------- requests

  /// §2 `category/data` for [categoryId] at [cursor] (page 1 when null). The
  /// server ignores `size` and answers 50 areas a page.
  static Uri categoryUri(String categoryId, {PageCursor? cursor}) {
    final (page, _) = _position(cursor);
    return Uri.https('live.kuaishou.com', '/live_api/category/data', {
      'type': categoryId,
      'page': '$page',
      'size': '30',
    });
  }

  /// §2 area rooms: ids shorter than 7 characters are game areas
  /// (`gameboard`), the rest are `non-gameboard`, whose later pages need the
  /// previous page's `data.cursor` (without it the server repeats page 1).
  static Uri areaRoomsUri(String areaId, {PageCursor? cursor}) {
    final (page, token) = _position(cursor);
    final board = areaId.length < 7 ? 'gameboard' : 'non-gameboard';
    return Uri.https('live.kuaishou.com', '/live_api/$board/list', {
      'filterType': '0',
      'pageSize': '20',
      'gameId': areaId,
      'page': '$page',
      'cursor': ?token,
    });
  }

  /// §3 author search; `lssid` carries the previous page's `ussid` when the
  /// cursor has one (whether the server needs it is still open, §12.5).
  static Uri searchUri(String keyword, {PageCursor? cursor}) {
    final (page, token) = _position(cursor);
    // Built by hand: Uri drops the `=` of an empty value, and the site gets `lssid=`.
    return Uri.parse(
      '$_origin/live_api/search/author?keyword=${Uri.encodeQueryComponent(keyword)}'
      '&page=$page&lssid=${Uri.encodeQueryComponent(token ?? '')}',
    );
  }

  /// §1 the room page of streamer [roomId].
  static Uri roomUri(String roomId) => Uri.parse('$_origin/u/${Uri.encodeComponent(roomId)}');

  // ----------------------------------------------------------------- catalog

  /// §2 one `category/data` page: areas in server order, duplicates removed.
  /// The next page exists only while `data.hasMore` is true.
  static Page<Area> areaPage(String body, {required String categoryId, PageCursor? cursor, int status = 200}) {
    final (page, _) = _position(cursor);
    final data = _apiData(body, status, 'category/data');
    final seen = <String>{};
    final areas = <Area>[];
    for (final item in _list(data['list'], 'category/data.list')) {
      if (item is! Map) continue;
      final id = jsonString(item['id']);
      if (id == null || !seen.add(id)) continue;
      areas.add(
        Area(
          id: id,
          name: jsonString(item['name']) ?? '',
          categoryId: categoryId,
          icon: jsonUrl(item['poster']) ?? jsonUrl(item['iconUrl']),
        ),
      );
    }
    final more = _truthy(data['hasMore']) && areas.isNotEmpty;
    return Page(areas, next: more ? _cursor(page + 1) : null);
  }

  /// §2 one `gameboard/list` or `non-gameboard/list` page. The next cursor
  /// carries `data.cursor` (REG-KUAISHOU-022); the list ends when `hasMore`
  /// is false. A card without `poster` has no cover instead of failing the
  /// page (REG-KUAISHOU-020).
  static Page<RoomCard> areaRooms(String body, {PageCursor? cursor, int status = 200}) {
    final (page, _) = _position(cursor);
    final data = _apiData(body, status, 'area rooms');
    final rooms = [for (final item in _list(data['list'], 'area rooms.list')) ?_card(item)];
    final more = _truthy(data['hasMore']) && rooms.isNotEmpty;
    return Page(rooms, next: more ? _cursor(page + 1, jsonString(data['cursor'])) : null);
  }

  /// §2 `home/list`: every group's `gameLiveInfo[].liveInfo[]` flattened,
  /// one card per streamer in server order, cover `poster` and title
  /// `caption` like the area lists (REG-KUAISHOU-017). Always one page.
  static Page<RoomCard> recommended(String body, {int status = 200}) {
    final data = _apiData(body, status, 'home/list');
    final seen = <RoomRef>{};
    final rooms = <RoomCard>[];
    for (final group in _list(data['list'], 'home/list.list')) {
      final subLabels = group is Map ? group['gameLiveInfo'] : null;
      if (subLabels is! List) continue;
      for (final subLabel in subLabels) {
        final cards = subLabel is Map ? subLabel['liveInfo'] : null;
        if (cards is! List) continue;
        for (final item in cards) {
          final card = _card(item);
          if (card != null && seen.add(card.ref)) rooms.add(card);
        }
      }
    }
    return Page(rooms);
  }

  // ------------------------------------------------------------------ search

  /// §3 author search. `result` 2 is [RateLimited] and 10 is [RiskControl]
  /// (REG-KUAISHOU-015); only `result` 1 with a list is a page, and an empty
  /// list is the last one. Search has no audience figure (REG-KUAISHOU-010).
  static Page<RoomCard> searchPage(String body, {PageCursor? cursor, int status = 200}) {
    final (page, _) = _position(cursor);
    final data = _apiData(body, status, 'search/author');
    final list = data['list'];
    if (jsonInt(data['result']) != 1 || list is! List) {
      throw ApiChanged(_site, 'search/author: result ${data['result']}, list ${list is List ? 'present' : 'missing'}');
    }
    final rooms = <RoomCard>[
      for (final item in list)
        if (item is Map && _ref(item['id']) != null)
          RoomCard(
            ref: _ref(item['id'])!,
            title: jsonString(item['name']) ?? '',
            anchorName: jsonString(item['name']) ?? '',
            state: !_banned(item['bannedStatus']) && _truthy(item['living']) ? LiveState.live : LiveState.offline,
            cover: jsonUrl(item['avatar']),
            // §3 `counts.fan` with units (`2960.4w`).
            followers: item['counts'] is Map ? _audience((item['counts'] as Map)['fan']) : null,
          ),
    ];
    return Page(rooms, next: list.isEmpty ? null : _cursor(page + 1, jsonString(data['ussid'])));
  }

  // -------------------------------------------------------------------- room

  /// §4 the `window.__INITIAL_STATE__` object of a room page, cut by JSON
  /// structure (REG-KUAISHOU-018): a `;` inside a string does not end it,
  /// and only a bare `undefined` becomes `null`. A page without the marker is
  /// a verification page ([RiskControl]) or an unknown page ([ApiChanged]).
  static Map<String, dynamic> initialState(String html, {bool userCookie = false}) {
    final marker = _stateMarker.firstMatch(html);
    if (marker == null) {
      if (_challenge.hasMatch(html)) {
        throw RiskControl(_site, cookieSuspect: userCookie, detail: 'room page is a verification page');
      }
      throw const ApiChanged(_site, 'room page: no __INITIAL_STATE__');
    }
    final literal = _objectLiteral(html, marker.end);
    if (literal == null) throw const ApiChanged(_site, 'room page: __INITIAL_STATE__ is not a complete object');
    return _map(_json(literal, '__INITIAL_STATE__'), '__INITIAL_STATE__');
  }

  /// §4 room page → detail. `errorType` 22 is [NotFound], any other
  /// `errorType` is [RiskControl] (§9); `isLiving` (true, 1 or "true") alone
  /// decides live or offline. The page has no broadcast title: [cardTitle],
  /// the caption of the card the user came from, wins over the streamer bio,
  /// and a `【回放】` caption marks a loop room as replay. The page has no
  /// room-level audience figure (`gameInfo.watchingCount` counts the whole
  /// area), so the audience stays empty (REG-KUAISHOU-016).
  static RoomDetail detail(
    String body, {
    required String roomId,
    int status = 200,
    String? cardTitle,
    bool userCookie = false,
  }) {
    final room = _room(body, status, userCookie: userCookie);
    final author = _object(room['author']);
    final stream = _object(room['liveStream']);
    final game = _object(room['gameInfo']);
    final ref = _ref(author['id']) ?? RoomRef(_site, roomId);
    final description = jsonString(author['description']);
    final knownTitle = jsonString(cardTitle);
    final liveStreamId = jsonString(stream['id']);
    final state = !_truthy(room['isLiving'])
        ? LiveState.offline
        : (knownTitle?.startsWith(_replayPrefix) ?? false)
        ? LiveState.replay
        : LiveState.live;
    return RoomDetail(
      card: RoomCard(
        ref: ref,
        title: knownTitle ?? description?.replaceAll(RegExp(r'\r?\n'), ' ') ?? '',
        anchorName: jsonString(author['name']) ?? '',
        state: state,
        cover: jsonUrl(stream['poster']),
        area: jsonString(game['name']),
      ),
      link: roomUri(ref.roomId),
      avatar: jsonUrl(author['avatar']),
      introduction: description,
      notice: description,
      danmakuKeys: {'liveStreamId': ?liveStreamId},
    );
  }

  // ----------------------------------------------------------------- streams

  /// §6 streams from a freshly fetched room page: the same errors as
  /// [detail]; a room that is not living has no stream ([StreamUnavailable]).
  static StreamSet roomStreams(
    String body, {
    required String roomId,
    required DateTime issuedAt,
    Quality? quality,
    String? userCookie,
    int status = 200,
  }) {
    final cookie = _headerValue(userCookie);
    final room = _room(body, status, userCookie: cookie != null);
    if (!_truthy(room['isLiving'])) throw const StreamUnavailable(_site, 'room page: isLiving is false');
    final stream = _object(room['liveStream']);
    return streams(
      stream['playUrls'],
      roomId: jsonString(_object(room['author'])['id']) ?? roomId,
      issuedAt: issuedAt,
      quality: quality,
      userCookie: cookie,
    );
  }

  /// §5 qualities of a `playUrls` value (the room page's `{h264, hevc}`
  /// object or a card's descriptor list), best first.
  static List<Quality> qualities(Object? playUrls) => [for (final tier in _tiers(playUrls)) tier.quality];

  /// §5/§6 the stream set of a `playUrls` value at [quality] (the best when
  /// null; the next lower tier when it is not offered). Each line carries the
  /// play headers, its CDN host as line id, its codec and its lease; no
  /// quality at all is [StreamUnavailable].
  static StreamSet streams(
    Object? playUrls, {
    required String roomId,
    required DateTime issuedAt,
    Quality? quality,
    String? userCookie,
  }) {
    final tiers = _tiers(playUrls);
    if (tiers.isEmpty) throw const StreamUnavailable(_site, 'playUrls: no playable representation');
    final tier = _choose(tiers, quality);
    final headers = playHeaders(roomId, userCookie: userCookie);
    final hosts = <String, int>{};
    return StreamSet(
      qualities: [for (final tier in tiers) tier.quality],
      selected: tier.quality,
      lines: [
        for (final line in tier.lines)
          StreamLine(
            url: line.url,
            format: line.url.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv,
            lineId: _lineId(line.url, hosts),
            requested: tier.quality,
            headers: headers,
            codec: line.codec,
            lease: lease(line.url, issuedAt),
          ),
      ],
    );
  }

  /// §6 headers for the media CDN: lower-case names, no line breaks in
  /// values; the referer is the room page; the cookie only when the user
  /// configured one (the anonymous session cookie never goes to the CDN).
  static Map<String, String> playHeaders(String? roomId, {String? userCookie}) {
    final id = jsonString(roomId);
    return {
      'user-agent': _playUserAgent,
      'origin': _origin,
      'referer': id == null ? '$_origin/' : '$_origin/u/${Uri.encodeComponent(id)}',
      'cookie': ?_headerValue(userCookie),
    };
  }

  /// §6 lease of a media URL received at [issuedAt]. The expiry is the
  /// signature time of the CDN: `txTime`, `wsTime`, `hwTime` (8 hex digits),
  /// `ty_Time` and the `bd-origin` `wsTime` (10 decimal digits), or the first
  /// field of the `ali-origin` `auth_key`. Refresh 10 minutes (at most a
  /// quarter of the lifetime) before it. Expiry does not cut an established
  /// connection: the CDNs check the signature when a request starts, and §6
  /// keeps `false` until a long-recording probe says otherwise. No
  /// recognisable expiry, or one already past, is null (error-driven renewal).
  static Lease? lease(Uri url, DateTime issuedAt) {
    final expiry = _expiry(url.queryParameters);
    if (expiry == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = lifetime ~/ 4 < _refreshLead ? lifetime ~/ 4 : _refreshLead;
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }

  // ----------------------------------------------------------------- helpers

  static final _stateMarker = RegExp(r'window\.__INITIAL_STATE__\s*=\s*');
  static final _challenge = RegExp('captcha|验证码|安全验证|人机验证|滑块', caseSensitive: false);
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _decimalTime = RegExp(r'^\d{10}$');
  static final _hexTime = RegExp(r'^[0-9a-fA-F]{8}$');
  static final _authKeyTime = RegExp(r'^(\d{10})-');
  static final _pathCodec = RegExp('^[A-Za-z]*?(Avc|Hevc|H264|H265)');
  static final _count = RegExp(r'^(\d+(?:\.\d+)?)\s*(亿|万|千|[kwm])?\+?$');

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<dynamic> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  /// An object field, or an empty one (a missing field reads as empty,
  /// REG-KUAISHOU-020).
  static Map<dynamic, dynamic> _object(Object? value) => value is Map ? value : const {};

  static void _status(int status, String what, {bool userCookie = false}) {
    if (status >= 200 && status < 300) return;
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status == 401 || status == 403) {
      throw RiskControl(_site, cookieSuspect: userCookie, detail: '$what HTTP $status');
    }
    throw ApiChanged(_site, '$what HTTP $status');
  }

  /// `data` of a `live_api` answer. Lists answer without `result`; a
  /// `result` other than 1 is the §3/§9 failure table on every endpoint.
  static Map<String, dynamic> _apiData(String body, int status, String what) {
    _status(status, what);
    final data = _map(_map(_json(body, what), what)['data'], '$what.data');
    final result = jsonInt(data['result']);
    if (result != null && result != 1) {
      final message = jsonString(data['error_msg']) ?? '';
      throw switch (result) {
        2 => RateLimited(_site, detail: '$what result 2: $message'),
        10 => RiskControl(_site, detail: '$what result 10: $message'),
        _ => ApiChanged(_site, '$what result $result: $message'),
      };
    }
    return data;
  }

  static (int, String?) _position(PageCursor? cursor) {
    if (cursor == null) return (1, null);
    final value = cursor.value;
    final colon = value.indexOf(':');
    final page = int.tryParse(colon < 0 ? value : value.substring(0, colon));
    if (page == null || page < 1) throw ArgumentError.value(cursor, 'cursor', 'not a Kuaishou cursor');
    final token = colon < 0 ? '' : value.substring(colon + 1);
    return (page, token.isEmpty ? null : token);
  }

  static PageCursor _cursor(int page, [String? token]) => PageCursor(token == null ? '$page' : '$page:$token');

  /// §1 the streamer id, the only persistent room identity.
  static RoomRef? _ref(Object? value) {
    final id = jsonString(value);
    if (id == null || !_idPattern.hasMatch(id)) return null;
    try {
      return RoomRef(_site, id);
    } on FormatException {
      return null;
    }
  }

  /// §4 `isLiving` and the other flags: true, 1 or "true" in any case.
  static bool _truthy(Object? value) =>
      value == true || value == 1 || (value is String && value.trim().toLowerCase() == 'true');

  static bool _banned(Object? status) => status is Map && _truthy(status['banned']);

  /// §4 counts with units: `3824`, `1.0万`, `10万+`, `2.5w`, `3k`, `1,234`.
  static int? _audience(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    final text = jsonString(value)?.toLowerCase().replaceAll(RegExp('[,，]'), '');
    final match = text == null ? null : _count.firstMatch(text);
    if (match == null) return null;
    final scale = switch (match.group(2)) {
      '亿' => 100000000,
      '万' || 'w' => 10000,
      '千' || 'k' => 1000,
      'm' => 1000000,
      _ => 1,
    };
    return (double.parse(match.group(1)!) * scale).round();
  }

  /// §2 a list card (area lists and recommendations). The list itself is the
  /// live signal (the card's `living` is false even for live rooms); a
  /// `【回放】` caption is a loop room.
  static RoomCard? _card(Object? item) {
    if (item is! Map) return null;
    final author = _object(item['author']);
    final ref = _ref(author['id']);
    if (ref == null) return null;
    final title = jsonString(item['caption']) ?? '';
    final started = jsonInt(item['statrtTime']);
    return RoomCard(
      ref: ref,
      title: title,
      anchorName: jsonString(author['name']) ?? '',
      state: title.startsWith(_replayPrefix) ? LiveState.replay : LiveState.live,
      cover: jsonUrl(item['poster']),
      area: jsonString(_object(item['gameInfo'])['name']),
      audience: Audience(online: _audience(item['watchingCount'])),
      liveSince: started != null && started > 0 ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true) : null,
    );
  }

  /// `liveroom.playList[0]` with the §9 `errorType` mapping applied.
  static Map<dynamic, dynamic> _room(String body, int status, {required bool userCookie}) {
    _status(status, 'room page', userCookie: userCookie);
    final liveroom = initialState(body, userCookie: userCookie)['liveroom'];
    final playList = liveroom is Map ? liveroom['playList'] : null;
    final room = playList is List && playList.isNotEmpty ? playList.first : null;
    if (room is! Map) throw const ApiChanged(_site, 'room page: liveroom.playList[0] missing');
    final error = room['errorType'];
    if (error != null) {
      final type = error is Map ? jsonInt(error['type']) : jsonInt(error);
      final title = error is Map ? jsonString(error['title']) ?? '' : '';
      if (type == 22) throw NotFound(_site, 'errorType 22: $title');
      throw RiskControl(_site, cookieSuspect: userCookie, detail: 'errorType $type: $title');
    }
    return room;
  }

  /// The JavaScript object literal starting at [start], as JSON text.
  static String? _objectLiteral(String text, int start) {
    var index = start;
    while (index < text.length && text.codeUnitAt(index) <= 0x20) {
      index++;
    }
    if (index >= text.length || text[index] != '{') return null;
    final out = StringBuffer();
    var depth = 0;
    var inString = false;
    for (; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        out.write(char);
        if (char == r'\' && index + 1 < text.length) {
          out.write(text[++index]);
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{' || char == '[') {
        depth++;
      } else if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) return (out..write(char)).toString();
      } else if (text.startsWith('undefined', index) &&
          !_identifierAt(text, index - 1) &&
          !_identifierAt(text, index + 'undefined'.length)) {
        out.write('null');
        index += 'undefined'.length - 1;
        continue;
      }
      out.write(char);
    }
    return null;
  }

  static bool _identifierAt(String text, int index) {
    if (index < 0 || index >= text.length) return false;
    final unit = text.codeUnitAt(index);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x24 ||
        unit == 0x5F;
  }

  static List<dynamic> _representations(Object? descriptor) {
    if (descriptor is! Map) return const [];
    final set = descriptor['adaptationSet'];
    final representations = set is Map ? set['representation'] : descriptor['representation'];
    return representations is List ? representations : const [];
  }

  /// §5 rules 1–6: per descriptor the first codec key with representations
  /// (`h264`, `avc`, `hevc`, `h265`; else the descriptor itself); only
  /// absolute http(s) URLs; `sort = level ?? bitrate ?? 0`; name from `name`,
  /// `shortName`, `qualityType` or `清晰度 {sort}`; tiers keyed by
  /// (name, sort) with their URLs merged in order without duplicates; best
  /// first. HEVC is only a fallback: when any H.264 (or unmarked) URL exists,
  /// HEVC URLs are dropped, also across descriptors (REG-KUAISHOU-002).
  static List<_Tier> _tiers(Object? playUrls) {
    final found = <({String name, int sort, Uri url, String? codec})>[];
    for (final descriptor in playUrls is List ? playUrls : [playUrls]) {
      if (descriptor is! Map) continue;
      Object? chosen = descriptor;
      String? codec;
      for (final (key, name) in const [('h264', 'avc'), ('avc', 'avc'), ('hevc', 'hevc'), ('h265', 'hevc')]) {
        if (_representations(descriptor[key]).isNotEmpty) {
          chosen = descriptor[key];
          codec = name;
          break;
        }
      }
      for (final item in _representations(chosen)) {
        if (item is! Map) continue;
        final url = jsonUrl(item['url']);
        if (url == null) continue;
        final sort = jsonInt(item['level']) ?? jsonInt(item['bitrate']) ?? 0;
        final name =
            jsonString(item['name']) ?? jsonString(item['shortName']) ?? jsonString(item['qualityType']) ?? '清晰度 $sort';
        found.add((name: name, sort: sort, url: url, codec: codec ?? _codecOf(url)));
      }
    }
    final avcFound = found.any((entry) => entry.codec != 'hevc');
    final merged = <String, ({String name, int sort, List<({Uri url, String? codec})> lines})>{};
    for (final entry in found) {
      if (avcFound && entry.codec == 'hevc') continue;
      final key = '${entry.name}\u0000${entry.sort}';
      final tier = merged.putIfAbsent(key, () => (name: entry.name, sort: entry.sort, lines: []));
      if (tier.lines.every((line) => line.url.toString() != entry.url.toString())) {
        tier.lines.add((url: entry.url, codec: entry.codec));
      }
    }
    final ordered = merged.entries.indexed.toList()
      ..sort((a, b) {
        final bySort = b.$2.value.sort.compareTo(a.$2.value.sort);
        return bySort != 0 ? bySort : a.$1.compareTo(b.$1);
      });
    return [
      for (final (_, MapEntry(:key, :value)) in ordered)
        (quality: Quality(id: key, label: _label(value.name), rank: value.sort), lines: value.lines),
    ];
  }

  /// §5 display name: the platform's name with spaces collapsed; a bare
  /// `qualityType` gets the name Kuaishou itself shows for it.
  static String _label(String name) {
    final text = name.replaceAll(RegExp(r'\s+'), ' ');
    return switch (text) {
      'STANDARD' => '高清',
      'HIGH' => '超清',
      'SUPER' => '蓝光',
      'BLUE_RAY' => '蓝光Plus',
      'WQHD_2K' => '2K',
      _ => text,
    };
  }

  /// Codec from the stream name: the part after the last `_` (the id may
  /// hold `_` and `-`) starts with letters and the codec
  /// (`{id}_GameAvcSdL1Lto-AuditAvcOriginL3.flv`, `…_ShowAvc…`, `…_EcAvc…`);
  /// `{id}_ma1500.flv` and `{id}_ma1500-AuditAvc…` name no codec of their own.
  static String? _codecOf(Uri url) {
    final file = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    final name = file.split('_').last;
    return switch (_pathCodec.firstMatch(name)?.group(1)) {
      'Avc' || 'H264' => 'avc',
      'Hevc' || 'H265' => 'hevc',
      _ => null,
    };
  }

  static _Tier _choose(List<_Tier> tiers, Quality? wanted) {
    if (wanted == null) return tiers.first;
    for (final tier in tiers) {
      if (tier.quality.id == wanted.id) return tier;
    }
    for (final tier in tiers) {
      if (tier.quality.rank <= wanted.rank) return tier;
    }
    return tiers.last;
  }

  /// §5 line identity: the CDN host, numbered when a tier has two URLs on it.
  static String _lineId(Uri url, Map<String, int> hosts) {
    final count = hosts.update(url.host, (value) => value + 1, ifAbsent: () => 1);
    return count == 1 ? url.host : '${url.host}#$count';
  }

  static int? _expiry(Map<String, String> query) {
    for (final key in const ['txTime', 'wsTime', 'hwTime', 'ty_Time']) {
      final value = query[key]?.trim();
      if (value == null) continue;
      if (_decimalTime.hasMatch(value)) return int.parse(value);
      if (_hexTime.hasMatch(value)) return int.parse(value, radix: 16);
    }
    final authKey = _authKeyTime.firstMatch(query['auth_key'] ?? '');
    return authKey == null ? null : int.parse(authKey.group(1)!);
  }

  static String? _headerValue(String? value) {
    final text = value?.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return text == null || text.isEmpty ? null : text;
  }
}
