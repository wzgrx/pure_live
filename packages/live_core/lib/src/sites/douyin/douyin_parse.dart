import 'dart:convert';
import 'dart:math' as math;

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';
import 'package:meta/meta.dart';

const _site = 'douyin';
const _liveOrigin = 'https://live.douyin.com';

/// One Douyin room response: the detail plus the stream description that
/// Douyin returns with it (spec/sites/douyin.md §4, §6: there is no separate
/// play request).
///
/// [RoomDetail.danmakuKeys] holds `webRid`, `roomId` (this broadcast's
/// room_id, which the danmaku connection needs, spec §1/§7) and, from the
/// room page only, `userUniqueId` (the page's 19-digit visitor id, §6).
@immutable
final class DouyinRoom {
  /// Creates a parsed room.
  const new({required this.detail, this.streamUrl, this.sessionEnded = false});

  /// The room, identified by its web_rid.
  final RoomDetail detail;

  /// `room.stream_url` while live, for [DouyinParse.streams]; null offline.
  final Map<String, dynamic>? streamUrl;

  /// Reflow only: the queried room_id belongs to a broadcast that has ended
  /// (`status == 4`); the adapter must query enter with the web_rid (§4).
  final bool sessionEnded;
}

typedef _Row = ({bool text, String value});
typedef _Line = ({Uri url, StreamFormat format});
typedef _Variant = ({Quality quality, List<_Line> lines, String? codec});
typedef _Variants = ({List<_Variant> list, Map<String, String> aliases});

/// Pure parsing of Douyin responses (spec/sites/douyin.md). Every function
/// takes the raw response the adapter received (text, HTTP status, response
/// headers with lower-case names) and returns domain values or throws a
/// `SiteError`. Request signing (a_bogus, msToken) is adapter work.
abstract final class DouyinParse {
  /// The one desktop user agent for API requests, signing and playback
  /// (§6: a_bogus encodes the UA, so the adapter must sign with this string).
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/134.0.0.0 Safari/537.36';

  /// §1 rule 1: a numeric id longer than 16 digits is a per-broadcast
  /// room_id (normalise it through reflow); shorter ones are web_rids.
  static bool isRoomId(String id) => RegExp(r'^\d{17,}$').hasMatch(id.trim());

  // ---------------------------------------------------------------- catalog

  /// §2 categories from the `live.douyin.com/?from_nav=1` page. Area ids are
  /// `id_str,type` (the partition identity is the pair); every category
  /// lists itself first as its "all" entry. Deeper `sub_partition` levels
  /// (single games) are not areas.
  static List<Category> categories(String html, {int status = 200, Map<String, String> headers = const {}}) {
    _checkHttp(html, status, headers, 'home page');
    final raw = _flightObject(_flightRows(html), 'categoryData')?['categoryData'];
    if (raw is! List) throw const ApiChanged(_site, 'home page: categoryData missing');
    final categories = <Category>[];
    for (final item in raw) {
      final top = _partition(_asMap(item)?['partition']);
      if (top == null) continue;
      categories.add(
        Category(
          id: top.id,
          name: top.name,
          areas: [
            Area(id: top.id, name: top.name, categoryId: top.id),
            for (final sub in _listOf(_asMap(item)!['sub_partition']))
              if (_partition(_asMap(sub)?['partition']) case final area?)
                Area(id: area.id, name: area.name, categoryId: top.id),
          ],
        ),
      );
    }
    return categories;
  }

  /// The `partition` and `partition_type` request parameters of an area id
  /// built by [categories] or [partitionSearch].
  static Map<String, String> partitionParams(String areaId) {
    final comma = areaId.lastIndexOf(',');
    if (comma <= 0 || comma == areaId.length - 1) {
      throw ArgumentError.value(areaId, 'areaId', 'expected id_str,type');
    }
    return {'partition': areaId.substring(0, comma), 'partition_type': areaId.substring(comma + 1)};
  }

  /// §2 `partition/detail/room/v2` page requested at [offset]. All rooms are
  /// live. The page ends when `data.count` is 0 or `data.offset` (the next
  /// offset) does not advance. [areaName] labels rooms whose `tag_name` is
  /// empty. An empty 200 with `bdturing-verify` is a captcha (RiskControl).
  static Page<RoomCard> partitionRooms(
    String body, {
    required int offset,
    String? areaName,
    int status = 200,
    Map<String, String> headers = const {},
  }) {
    final root = _api(body, 'partition rooms', status: status, headers: headers);
    final data = _asMap(root['data']);
    final list = data?['data'];
    if (data == null || list is! List) throw const ApiChanged(_site, 'partition rooms: data.data missing');
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final raw in list) {
      final item = _asMap(raw);
      final room = _asMap(item?['room']);
      if (item == null || room == null) continue;
      final owner = _asMap(room['owner']) ?? const {};
      final id = _firstId([item['web_rid'], owner['web_rid'], room['id_str']]);
      if (id == null || !seen.add(id)) continue;
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: _text(room['title']) ?? '',
          anchorName: _text(owner['nickname']) ?? '',
          state: LiveState.live,
          cover: _image(room['cover']),
          area: _text(item['tag_name']) ?? areaName,
          audience: _audience(room),
          avatar: _image(owner['avatar_thumb']),
        ),
      );
    }
    final count = jsonInt(data['count']);
    final next = jsonInt(data['offset']);
    final more = (count == null || count > 0) && next != null && next > offset;
    return Page(rooms, next: more ? PageCursor('$next') : null);
  }

  /// §2 `webcast/feed/` recommendations. Accepts the envelope list (rooms in
  /// `data[].data`, possibly a JSON string, or `room`) and the older
  /// `data.data` list; deduplicates by identity (web_rid, else room_id). The
  /// feed takes no offset, so it is always one page.
  static Page<RoomCard> feed(String body, {int status = 200, Map<String, String> headers = const {}}) {
    final root = _api(body, 'feed', status: status, headers: headers);
    var list = root['data'];
    if (list is Map) list = list['data'];
    if (list is! List) throw const ApiChanged(_site, 'feed: room list missing');
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final raw in list) {
      final envelope = _asMap(raw);
      if (envelope == null) continue;
      final room = [
        _asMap(envelope['data']),
        _asMap(envelope['room']),
        envelope,
      ].firstWhere((candidate) => candidate != null && _looksLikeRoom(candidate), orElse: () => null);
      if (room == null) continue;
      final owner = _asMap(room['owner']) ?? _asMap(envelope['owner']) ?? const {};
      final id = _firstId([envelope['web_rid'], owner['web_rid'], room['web_rid'], room['id_str'], room['id']]);
      if (id == null || !seen.add(id)) continue;
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: _firstText([room['title'], envelope['title'], owner['nickname']]) ?? '',
          anchorName: _firstText([owner['nickname'], envelope['nickname']]) ?? '',
          state: LiveState.live,
          cover: _image(room['cover']) ?? _image(envelope['cover']),
          area: _feedArea(envelope, room),
          audience: _audience(room),
          avatar: _image(owner['avatar_thumb']) ?? _image(owner['avatar_large']) ?? _image(envelope['avatar_thumb']),
        ),
      );
    }
    return Page(rooms);
  }

  // ----------------------------------------------------------------- search

  /// §3 live search (`aweme/v1/web/live/search/`) and general search
  /// (`general/search/stream/`, whose body is hex-length framed chunks) at
  /// [offset]. Anonymous requests answer 2483 "请先登录" → NeedsLogin.
  /// Rooms may be nested (`lives.rawdata`, JSON strings, …); identity is
  /// `owner.web_rid`, else the room_id; `status == 2` is live. The next page
  /// is `cursor` while `has_more` is set.
  static Page<RoomCard> searchPage(
    String body, {
    required int offset,
    int status = 200,
    Map<String, String> headers = const {},
  }) {
    _checkHttp(body, status, headers, 'search');
    final items = <Object?>[];
    Object? hasMore;
    Object? cursor;
    for (final chunk in _chunks(body)) {
      final root = _api(chunk, 'search', status: 200, headers: const {});
      final data = root['data'];
      if (data is List) items.addAll(data);
      hasMore = root['has_more'] ?? hasMore;
      cursor = root['cursor'] ?? cursor;
    }
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final item in items) {
      final card = _searchCard(_asMap(item) ?? const {});
      if (card != null && seen.add(card.ref.roomId)) rooms.add(card);
    }
    final next = jsonInt(cursor);
    final more = (hasMore == true || jsonInt(hasMore) == 1) && next != null && next > offset;
    return Page(rooms, next: more ? PageCursor('$next') : null);
  }

  /// §3 `webcast/web/partition/search/`: partitions whose name matches the
  /// keyword (anonymous). These are areas, not keyword results; their parent
  /// category is not in the response, so [Area.categoryId] is empty.
  static List<Area> partitionSearch(String body, {int status = 200, Map<String, String> headers = const {}}) {
    final root = _api(body, 'partition search', status: status, headers: headers);
    return [
      for (final item in _listOf(_asMap(root['data'])?['SearchResult']))
        if (_partition(_asMap(item)?['partition']) case final area?) Area(id: area.id, name: area.name, categoryId: ''),
    ];
  }

  // ------------------------------------------------------------------ rooms

  /// §4 `room/web/enter/` for [webRid]: room `data.data[0]`, anchor
  /// `data.user`. Live when `room.status == 2` (`data.room_status == 0` when
  /// status is absent). 4001038 (or an empty list) → NotFound; an empty 200
  /// (no ttwid, rejected signature) → RiskControl.
  static DouyinRoom enter(
    String body, {
    required String webRid,
    int status = 200,
    Map<String, String> headers = const {},
  }) {
    final root = _api(body, 'enter', status: status, headers: headers);
    final data = _asMap(root['data']);
    final list = data?['data'];
    if (data == null || list is! List) throw const ApiChanged(_site, 'enter: data.data missing');
    if (list.isEmpty) throw NotFound(_site, 'enter: no room for $webRid');
    final room = _asMap(list.first);
    if (room == null) throw const ApiChanged(_site, 'enter: data.data[0] is not an object');
    return _room(
      webRid: webRid,
      room: room,
      person: _asMap(data['user']),
      state: _liveState(room, roomStatus: data['room_status']),
    );
  }

  /// §1 rule 2 / §4 step 1 `room/reflow/info/` for a room_id: identity is
  /// `room.owner.web_rid`. [DouyinRoom.sessionEnded] (`status == 4`) tells
  /// the adapter to query enter with that web_rid instead.
  static DouyinRoom reflow(String body, {int status = 200, Map<String, String> headers = const {}}) {
    final root = _api(body, 'reflow', status: status, headers: headers);
    final room = _asMap(_asMap(root['data'])?['room']);
    if (room == null) throw const ApiChanged(_site, 'reflow: data.room missing');
    final webRid = _text(_asMap(room['owner'])?['web_rid']);
    if (webRid == null || !RegExp(r'^\d+$').hasMatch(webRid)) {
      throw const ApiChanged(_site, 'reflow: room.owner.web_rid missing or not numeric');
    }
    return _room(webRid: webRid, room: room, state: _liveState(room), sessionEnded: jsonInt(room['status']) == 4);
  }

  /// §4 HTML fallback `live.douyin.com/{web_rid}`. The page streams its
  /// React Server Component payload in `self.__pace_f.push` scripts; the
  /// state is `roomStore.roomInfo` (`room`, `anchor`) and
  /// `userStore.odin.user_unique_id` (kept when 19 digits). References such
  /// as `stream_data: "$13"` are resolved from the payload's text rows.
  static DouyinRoom roomPage(
    String html, {
    required String webRid,
    int status = 200,
    Map<String, String> headers = const {},
  }) {
    _checkHttp(html, status, headers, 'room page');
    final rows = _flightRows(html);
    final holder = _flightObject(
      rows,
      'roomStore',
      where: (state) => _asMap(_asMap(_asMap(state['roomStore'])?['roomInfo'])?['room']) != null,
    );
    final state = _asMap(_resolve(holder, rows));
    final info = _asMap(_asMap(state?['roomStore'])?['roomInfo']);
    final room = _asMap(info?['room']);
    if (state == null || info == null || room == null) {
      throw const ApiChanged(_site, 'room page: roomStore.roomInfo.room missing');
    }
    final visitor = _text(_asMap(_asMap(state['userStore'])?['odin'])?['user_unique_id']);
    return _room(
      webRid: webRid,
      room: room,
      person: _asMap(info['anchor']),
      state: _liveState(room),
      extraKeys: {if (visitor != null && RegExp(r'^\d{19}$').hasMatch(visitor)) 'userUniqueId': visitor},
    );
  }

  /// §8 `webcast/user/me/`: the account's nickname; 20003 → NeedsLogin.
  static String accountName(String body, {int status = 200, Map<String, String> headers = const {}}) {
    final root = _api(body, 'user/me', status: status, headers: headers);
    final name = _text(_asMap(root['data'])?['nickname']);
    if (name == null) throw const ApiChanged(_site, 'user/me: data.nickname missing');
    return name;
  }

  // ---------------------------------------------------------------- streams

  /// §5 video qualities in `stream_url`, best first: keys joined by sdk_key
  /// (case-insensitive, id = lower-case key), audio-only keys excluded, and
  /// keys with the same URL set collapsed onto the better-ranked one.
  static List<Quality> qualities(Map<String, dynamic> streamUrl) => [
    for (final variant in _variants(streamUrl).list) variant.quality,
  ];

  /// §5 rule 9 the platform's default quality (`options.default_quality`,
  /// else `default_resolution`) as an offered id, or null.
  static String? defaultQuality(Map<String, dynamic> streamUrl) {
    final variants = _variants(streamUrl);
    final options = _asMap(_asMap(_asMap(streamUrl['live_core_sdk_data'])?['pull_data'])?['options']);
    for (final raw in [_asMap(options?['default_quality'])?['sdk_key'], streamUrl['default_resolution']]) {
      final id = _resolveQuality(variants, _text(raw));
      if (id != null) return id;
    }
    return null;
  }

  /// §5/§6 the lines of [quality] (default: the best), one per URL in
  /// platform order (FLV first, then HLS), each with its format, line id
  /// (`flv`, `hls`, then `flv-2`…), codec (`avc`/`hevc`), the playback
  /// headers and the [lease] for a URL issued at [issuedAt]. Throws
  /// StreamUnavailable when no video quality has a URL.
  static StreamSet streams(
    Map<String, dynamic>? streamUrl, {
    required DateTime issuedAt,
    String? webRid,
    String? quality,
    String userAgent = userAgent,
  }) {
    final variants = streamUrl == null
        ? (list: const <_Variant>[], aliases: const <String, String>{})
        : _variants(streamUrl);
    if (variants.list.isEmpty) throw const StreamUnavailable(_site, 'stream_url has no video quality');
    final id = _resolveQuality(variants, quality);
    final chosen = variants.list.firstWhere((variant) => variant.quality.id == id, orElse: () => variants.list.first);
    final headers = playHeaders(webRid: webRid, userAgent: userAgent);
    final used = <StreamFormat, int>{};
    final lines = <StreamLine>[];
    for (final line in chosen.lines) {
      final index = used[line.format] = (used[line.format] ?? 0) + 1;
      lines.add(
        StreamLine(
          url: line.url,
          format: line.format,
          lineId: index == 1 ? line.format.name : '${line.format.name}-$index',
          requested: chosen.quality,
          headers: headers,
          codec: chosen.codec,
          lease: lease(line.url, issuedAt),
        ),
      );
    }
    return StreamSet(
      qualities: [for (final variant in variants.list) variant.quality],
      selected: chosen.quality,
      lines: lines,
    );
  }

  /// §6 playback headers: UA, `origin` and `referer` of the room page. No
  /// cookie: the CDN is not shown to need it, and the user's cookie must not
  /// leak to CDN hosts.
  static Map<String, String> playHeaders({String? webRid, String userAgent = userAgent}) => {
    'user-agent': userAgent,
    'origin': _liveOrigin,
    'referer': webRid == null || webRid.isEmpty ? '$_liveOrigin/' : '$_liveOrigin/$webRid',
  };

  /// §6 lease of a URL issued at [issuedAt]. The expiry is absolute:
  /// `expire` (decimal or hex Unix seconds), `volcTime`, `wsTime + keeptime`
  /// (hex) or `t` (with `k`); recorded URLs expire 7 days after issue. Refresh
  /// `min(10 min, lifetime / 4)` before expiry. Expiry does not cut an
  /// established connection (the spec forbids assuming Douyu's rule until a
  /// long recording proves it). Null when no expiry can be read.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final expiresAt = _expiry(url.queryParameters, issuedAt);
    if (expiresAt == null) return null;
    final lifetime = expiresAt.difference(issuedAt);
    final lead = lifetime <= Duration.zero
        ? Duration.zero
        : Duration(microseconds: math.min(const Duration(minutes: 10).inMicroseconds, lifetime.inMicroseconds ~/ 4));
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }

  // ---------------------------------------------------------------- helpers

  /// §9 HTTP-level failures, before the body is read.
  static void _checkHttp(String body, int status, Map<String, String> headers, String what) {
    String? header(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
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
        detail: '$what: HTTP 429',
      );
    }
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what: HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status');
    if (body.trim().isEmpty) {
      throw RiskControl(_site, detail: '$what: empty body (missing ttwid, rejected signature or captcha)');
    }
  }

  /// A JSON API response: HTTP checks, then `status_code` (§9).
  static Map<String, dynamic> _api(
    String body,
    String what, {
    required int status,
    required Map<String, String> headers,
  }) {
    _checkHttp(body, status, headers, what);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw RiskControl(_site, detail: '$what: body is not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: expected an object');
    final code = jsonInt(decoded['status_code']);
    if (code == null || code == 0) return decoded;
    final data = _asMap(decoded['data']);
    final message = _firstText([decoded['status_msg'], data?['prompts'], data?['message']]) ?? '';
    throw switch (code) {
      4001038 => NotFound(_site, '$what: status_code $code $message'),
      2483 || 20003 => NeedsLogin(_site, '$what: status_code $code $message'),
      _ => ApiChanged(_site, '$what: status_code $code $message'),
    };
  }

  /// The JSON documents of a body; the general search streams them as
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

  /// The page's RSC rows by id: `id:<json>\n` or `id:T<hex byte length>,<text>`.
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
  /// [where] (the page also carries empty initial stores).
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

  /// Resolves RSC string encodings: `$$x` → `$x`, `$undefined` → null and
  /// `$<hex id>` → that row (text rows as strings).
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

  static DouyinRoom _room({
    required String webRid,
    required Map<String, dynamic> room,
    required LiveState state,
    Map<String, dynamic>? person,
    Map<String, String> extraKeys = const {},
    bool sessionEnded = false,
  }) {
    final live = state == LiveState.live;
    final owner = _asMap(room['owner']);
    final roomId = _firstId([room['id_str'], room['id']]);
    return DouyinRoom(
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, webRid),
          title: _text(room['title']) ?? '',
          anchorName: _firstText([owner?['nickname'], person?['nickname']]) ?? '',
          state: state,
          cover: live ? _image(room['cover']) : null,
          audience: live ? _audience(room) : Audience.none,
        ),
        link: Uri.parse('$_liveOrigin/$webRid'),
        avatar: _image(owner?['avatar_thumb']) ?? _image(person?['avatar_thumb']),
        introduction: _text(owner?['signature']),
        danmakuKeys: {'webRid': webRid, 'roomId': ?roomId, ...extraKeys},
      ),
      streamUrl: live ? _asMap(room['stream_url']) : null,
      sessionEnded: sessionEnded,
    );
  }

  /// §4: `room.status == 2` is live, any other value offline; enter's
  /// `data.room_status` (0 live, 2 ended) decides only when status is absent.
  static LiveState _liveState(Map<String, dynamic> room, {Object? roomStatus}) {
    final status = jsonInt(room['status']);
    if (status != null) return status == 2 ? LiveState.live : LiveState.offline;
    final fallback = jsonInt(roomStatus);
    if (fallback != null) return fallback == 0 ? LiveState.live : LiveState.offline;
    throw const ApiChanged(_site, 'room.status missing');
  }

  /// §4 audience, corrected: `room_view_stats.display_value` is online when
  /// `display_type == 1` ("713在线观众") and cumulative when it is 3
  /// ("人看过"); other types are ignored. Exact integers beat bucketed text
  /// (`user_count_str: "2000+"`); a cumulative 0 is a placeholder.
  static Audience _audience(Map<String, dynamic> room) {
    final view = _asMap(room['room_view_stats']) ?? const {};
    final stats = _asMap(room['stats']) ?? const {};
    final displayType = jsonInt(view['display_type']);
    return Audience(
      online: _count(allowZero: true, [
        room['user_count'],
        room['online_user_count'],
        room['online_user_for_anchor'],
        if (displayType == 1) view['display_value'],
        view['user_count'],
        view['online_user_count'],
        view['online_user_for_anchor'],
        stats['user_count'],
        stats['online_user_count'],
        stats['online_user_for_anchor'],
        stats['user_count_str'],
        room['user_count_str'],
      ]),
      cumulative: _count(allowZero: false, [
        if (displayType == 3) view['display_value'],
        view['total_user'],
        view['total_user_str'],
        stats['total_user'],
        stats['total_user_str'],
        room['total_user'],
        room['total_user_str'],
      ]),
    );
  }

  static int? _count(List<Object?> candidates, {required bool allowZero}) {
    bool accepted(int? value) => value != null && (allowZero ? value >= 0 : value > 0);
    for (final candidate in candidates) {
      final value = candidate is bool ? null : jsonInt(candidate);
      if (accepted(value)) return value;
    }
    for (final candidate in candidates) {
      final value = candidate is String ? parseChineseCount(candidate.trim()) : null;
      if (accepted(value)) return value;
    }
    return null;
  }

  static bool _looksLikeRoom(Map<String, dynamic> value) =>
      value['owner'] is Map || value['title'] != null || value['id_str'] != null || value['stream_url'] is Map;

  /// §2 feed area: `tag_name`, then `partition_road_map[]`/`tags[]` titles;
  /// null when none (the legacy "热门推荐" is UI copy, not an area).
  static String? _feedArea(Map<String, dynamic> envelope, Map<String, dynamic> room) {
    final direct = _firstText([room['tag_name'], envelope['tag_name']]);
    if (direct != null) return direct;
    for (final source in [room['partition_road_map'], envelope['tags']]) {
      for (final tag in _listOf(source)) {
        final map = _asMap(tag);
        final text = map == null ? null : _firstText([map['title'], map['name'], map['tag_name']]);
        if (text != null) return text;
      }
    }
    return null;
  }

  static RoomCard? _searchCard(Map<String, dynamic> item) {
    Object? at(Object? node, String key) => _asMap(node)?[key];
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
    ].map(_asMap).firstWhere((candidate) => candidate != null, orElse: () => null);
    if (raw == null) return null;
    final room = _asMap(raw['room']) ?? const {};
    final owner = _asMap(raw['owner']) ?? const {};
    final roomOwner = _asMap(room['owner']) ?? const {};
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
    final live = jsonInt(raw['status']) == 2;
    final roadMap = _listOf(room['partition_road_map']);
    final roomAudience = _audience(room);
    final rawAudience = _audience(raw);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: _firstText([raw['title'], room['title'], item['title'], item['desc'], nickname]) ?? '',
      anchorName: nickname ?? '',
      state: live ? LiveState.live : LiveState.offline,
      cover: _image(raw['cover']) ?? _image(room['cover']) ?? jsonUrl(raw['cover_url']),
      area: _firstText([if (roadMap.isNotEmpty) _asMap(roadMap.first)?['title'], _asMap(raw['partition'])?['title']]),
      audience: live
          ? Audience(
              online: roomAudience.online ?? rawAudience.online,
              cumulative: roomAudience.cumulative ?? rawAudience.cumulative,
            )
          : Audience.none,
    );
  }

  static ({String id, String name})? _partition(Object? raw) {
    final map = _asMap(raw);
    final id = _text(map?['id_str']);
    final type = _text(map?['type']);
    if (id == null || type == null) return null;
    return (id: '$id,$type', name: _text(map?['title']) ?? '');
  }

  // --------------------------------------------------------- stream parsing

  static String? _resolveQuality(_Variants variants, String? id) {
    if (id == null) return null;
    final key = id.trim().toLowerCase();
    final target = variants.aliases[key] ?? key;
    return variants.list.any((variant) => variant.quality.id == target) ? target : null;
  }

  /// §5 rules 1–7.
  static _Variants _variants(Map<String, dynamic> streamUrl) {
    final pull = _asMap(_asMap(streamUrl['live_core_sdk_data'])?['pull_data']);
    final options = _asMap(pull?['options']);
    final streamData = _asMap(_asMap(pull?['stream_data'])?['data']) ?? const {};
    final flvMap = _asMap(streamUrl['flv_pull_url']) ?? const {};
    final hlsMap = _asMap(streamUrl['hls_pull_url_map']) ?? const {};
    final names = _asMap(streamUrl['resolution_name']) ?? const {};

    final descriptors = <String, Map<String, dynamic>>{};
    for (final option in _listOf(options?['qualities'])) {
      final map = _asMap(option);
      final key = _text(map?['sdk_key'])?.toLowerCase();
      if (map != null && key != null) descriptors.putIfAbsent(key, () => map);
    }
    for (final key in {...streamData.keys, ...flvMap.keys, ...hlsMap.keys}) {
      final text = key.trim().toLowerCase();
      if (text.isNotEmpty) descriptors.putIfAbsent(text, () => const {});
    }

    final ranked = <(_Variant, int)>[];
    for (final MapEntry(:key, value: descriptor) in descriptors.entries) {
      final main = _asMap(_asMap(_lookup(streamData, key))?['main']);
      final lines = <_Line>[];
      void add(Object? value, StreamFormat format) {
        final text = _text(value);
        final uri = text == null ? null : Uri.tryParse(text);
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return;
        if (lines.any((line) => line.url.toString() == uri.toString())) return;
        lines.add((url: uri, format: format));
      }

      add(main?['flv'], StreamFormat.flv);
      add(main?['hls'], StreamFormat.hls);
      add(_lookup(flvMap, key), StreamFormat.flv);
      add(_lookup(hlsMap, key), StreamFormat.hls);
      if (lines.isEmpty || _audioOnly(key, lines)) continue;

      final sdk = _asMap(main?['sdk_params']) ?? const {};
      final bitRate = jsonInt(descriptor['v_bit_rate']) ?? jsonInt(sdk['vbitrate']);
      final level = jsonInt(descriptor['level']) ?? 0;
      final tier = _tier(key);
      final rank = tier > 0
          ? tier * 1000000
          : level > 0
          ? level * 1000000
          : bitRate ?? 0;
      final label = _label(key, _text(descriptor['name']) ?? _text(_lookup(names, key)));
      ranked.add((
        (
          quality: Quality(id: key, label: label, rank: rank),
          lines: lines,
          codec: _codec(sdk['VCodec']) ?? _codec(descriptor['v_codec']),
        ),
        rank,
      ));
    }
    ranked.sort((a, b) {
      final byRank = b.$2.compareTo(a.$2);
      return byRank != 0 ? byRank : a.$1.quality.id.compareTo(b.$1.quality.id);
    });

    final kept = <_Variant>[];
    final aliases = <String, String>{};
    final bySet = <String, String>{};
    for (final (variant, _) in ranked) {
      final set = (variant.lines.map((line) => line.url.toString()).toList()..sort()).join('\u0000');
      final survivor = bySet[set];
      if (survivor != null) {
        aliases[variant.quality.id] = survivor;
        // Same stream: the survivor inherits a codec only the alias reports.
        final index = kept.indexWhere((candidate) => candidate.quality.id == survivor);
        final target = kept[index];
        if (target.codec == null && variant.codec != null) {
          kept[index] = (quality: target.quality, lines: target.lines, codec: variant.codec);
        }
        continue;
      }
      bySet[set] = variant.quality.id;
      kept.add(variant);
    }
    return (list: kept, aliases: aliases);
  }

  /// §5 rule 3: `ao`/`audio`/`audioonly` keys, or every URL `only_audio=1`.
  static bool _audioOnly(String key, List<_Line> lines) {
    final token = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
    if (const {'ao', 'audio', 'audioonly'}.contains(token)) return true;
    return lines.every((line) {
      final value = line.url.queryParameters['only_audio']?.toLowerCase();
      return value == '1' || value == 'true';
    });
  }

  /// §5 rule 5 semantic tier of the known keys.
  static int _tier(String key) => switch (key.toUpperCase()) {
    'ORIGION' || 'ORIGIN' => 6,
    'FULL_HD1' || 'UHD' => 5,
    'HD1' || 'HD' => 4,
    'SD2' || 'SD' => 3,
    'SD1' || 'LD' => 2,
    'MD' => 1,
    _ => 0,
  };

  /// §5 rule 4: the platform's Chinese name, else the key's usual name.
  static String _label(String key, String? name) {
    if (name != null && RegExp('[\u3400-\u9fff]').hasMatch(name)) return name;
    final token = (name ?? key).toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
    return switch (token) {
      'origin' || 'origion' || 'original' || 'source' => '原画',
      'fullhd' || 'fullhd1' || 'uhd' || 'uhd1' || 'blueray' || 'bluray' => '蓝光',
      'fhd' || 'hd' || 'hd1' => '超清',
      'sd' || 'sd2' => '高清',
      'ld' || 'sd1' => '标清',
      'md' => '流畅',
      _ => name ?? key,
    };
  }

  /// `sdk_params.VCodec` (`h264`/`h265`) or `options.qualities[].v_codec`
  /// (`264`, `bytevc1` = ByteDance's HEVC).
  static String? _codec(Object? value) => switch (_text(value)?.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '')) {
    'h264' || '264' || 'avc' || 'avc1' => 'avc',
    'h265' || '265' || 'hevc' || 'hev1' || 'hvc1' || 'bytevc1' => 'hevc',
    _ => null,
  };

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

  // ------------------------------------------------------------ JSON access

  /// An object from a map or a JSON-encoded object string.
  static Map<String, dynamic>? _asMap(Object? value) {
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

  static List<Object?> _listOf(Object? value) => value is List ? value : const [];

  static Object? _lookup(Map<String, dynamic> map, String key) {
    final direct = map[key];
    if (direct != null) return direct;
    for (final entry in map.entries) {
      if (entry.key.toLowerCase() == key) return entry.value;
    }
    return null;
  }

  static String? _text(Object? value) {
    if (value == null || value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static String? _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text != null) return text;
    }
    return null;
  }

  /// The first value usable as a room id (RoomRef rejects `0` and other
  /// placeholders).
  static String? _firstId(Iterable<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text != null && !const {'0', 'undefined', 'nan', 'none'}.contains(text.toLowerCase())) return text;
    }
    return null;
  }

  /// The first http(s) URL of an image's `url_list` (or a direct URL).
  static Uri? _image(Object? value) {
    final list = _asMap(value)?['url_list'];
    if (list is List) {
      for (final url in list) {
        final uri = jsonUrl(url);
        if (uri != null) return uri;
      }
    }
    return value is String ? jsonUrl(value) : null;
  }
}
