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

const _site = 'douyu';

/// Pure parsing of Douyu responses (spec/sites/douyu.md). Every function
/// takes the raw response text the adapter received and either returns
/// domain values or throws a `SiteError`.
abstract final class DouyuParse {
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

  /// §2.1 `m.douyu.com/api/cate/list`: categories sorted by id, areas in order.
  static List<Category> categories(String body) {
    final data = _map(_map(_json(body, 'cate/list'), 'cate/list')['data'], 'cate/list.data');
    final areas = _list(data['cate2Info'], 'cate2Info');
    final categories = [
      for (final raw in _list(data['cate1Info'], 'cate1Info'))
        if (raw is Map && jsonString(raw['cate1Id']) != null)
          Category(
            id: jsonString(raw['cate1Id'])!,
            name: decodeHtmlEntities(jsonString(raw['cate1Name']) ?? ''),
            areas: [
              for (final area in areas)
                if (area is Map && jsonString(area['cate1Id']) == jsonString(raw['cate1Id']))
                  Area(
                    id: jsonString(area['cate2Id'])!,
                    name: decodeHtmlEntities(jsonString(area['cate2Name']) ?? ''),
                    categoryId: jsonString(raw['cate1Id'])!,
                    icon: jsonUrl(area['icon']),
                  ),
            ],
          ),
    ]..sort((a, b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0));
    return categories;
  }

  /// §2.2 / §2.3 `mixList` and `allpage` pages. Only `type == 1` entries are
  /// rooms; all are live. The page ends on an empty `rl` or at `pgcnt` (when
  /// the endpoint reports one; allpage always says 0).
  static Page<RoomCard> roomListPage(String body, {required int page}) {
    final data = _map(_map(_json(body, 'room list'), 'room list')['data'], 'room list.data');
    final raw = _list(data['rl'] ?? const [], 'rl');
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map && jsonInt(item['type']) == 1 && jsonString(item['rid']) != null)
          RoomCard(
            ref: RoomRef(_site, jsonString(item['rid'])!),
            title: decodeHtmlEntities(jsonString(item['rn']) ?? ''),
            anchorName: decodeHtmlEntities(jsonString(item['nn']) ?? ''),
            state: LiveState.live,
            cover: jsonUrl(item['rs16']),
            area: jsonString(item['c2name']),
            audience: Audience(popularity: jsonInt(item['ol'])),
          ),
    ];
    final pages = jsonInt(data['pgcnt']) ?? 0;
    final more = raw.isNotEmpty && (pages <= 0 || page < pages);
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `searchShow`. `isLive == 1` with `roomType == 0` is live; `roomType
  /// == 3` is a loop room (the same room reports `videoLoop == 1`); the rest
  /// are offline. An empty result list is the last page.
  static Page<RoomCard> searchPage(String body, {required int page}) {
    final root = _map(_json(body, 'searchShow'), 'searchShow');
    final error = jsonInt(root['error']) ?? 0;
    if (error != 0) throw ApiChanged(_site, 'searchShow error $error: ${jsonString(root['msg']) ?? ''}');
    final data = root['data'];
    final raw = data is Map ? (data['relateShow'] as List?) ?? const <Object?>[] : const <Object?>[];
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map && jsonString(item['rid']) != null)
          RoomCard(
            ref: RoomRef(_site, jsonString(item['rid'])!),
            title: decodeHtmlEntities(jsonString(item['roomName']) ?? ''),
            anchorName: decodeHtmlEntities(jsonString(item['nickName']) ?? ''),
            state: switch ((jsonInt(item['isLive']), jsonInt(item['roomType']))) {
              (1, 0) => LiveState.live,
              (1, 3) => LiveState.replay,
              _ => LiveState.offline,
            },
            cover: jsonUrl(item['roomSrc']),
            area: jsonString(item['cateName']),
            audience: Audience(popularity: parseChineseCount(item['hot'])),
          ),
    ];
    return Page(rooms, next: rooms.isEmpty ? null : PageCursor('${page + 1}'));
  }

  /// §4 `betard/<rid>` detail. The body may be a JSON-encoded string. A 200
  /// HTML page ("该房间目前没有开放") is a room that does not exist.
  static RoomDetail detail(String body, {int status = 200}) {
    final trimmed = body.trimLeft();
    if (status == 404 || (status == 200 && trimmed.startsWith('<'))) {
      throw NotFound(_site, 'betard answered HTML (status $status)');
    }
    if (status == 403) throw const RiskControl(_site, detail: 'betard 403');
    var decoded = _json(body, 'betard');
    if (decoded is String) decoded = _json(decoded, 'betard string');
    final room = _map(_map(decoded, 'betard')['room'], 'betard.room');
    final rid = jsonString(room['room_id']);
    if (rid == null) throw const ApiChanged(_site, 'betard.room.room_id missing');
    final title = decodeHtmlEntities(jsonString(room['room_name']) ?? '');
    final replay = jsonInt(room['videoLoop']) == 1 || title.startsWith('【回放】');
    final state = replay
        ? LiveState.replay
        : jsonInt(room['show_status']) == 1
        ? LiveState.live
        : LiveState.offline;
    final biz = room['room_biz_all'];
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, rid),
        title: title,
        anchorName: decodeHtmlEntities(jsonString(room['owner_name']) ?? ''),
        state: state,
        cover: jsonUrl(room['room_pic']),
        area: jsonString(room['second_lvl_name']),
        audience: Audience(popularity: biz is Map ? parseChineseCount(biz['hot']) : null),
      ),
      link: Uri.parse('https://www.douyu.com/$rid'),
      avatar: jsonUrl(room['owner_avatar']),
      introduction: jsonString(room['show_details']) == null
          ? null
          : decodeHtmlEntities(room['show_details'].toString()),
      danmakuKeys: {'rid': rid},
    );
  }

  /// §6.3 H5 play response → its `data` object; §9 maps the failures.
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    if (status == 403) throw const RiskControl(_site, detail: 'getH5PlayV1 403');
    if (status >= 500) throw NetworkFailure(_site, 'getH5PlayV1 HTTP $status');
    final decoded = _json(body, 'getH5PlayV1');
    if (decoded is! Map<String, dynamic>) throw const ApiChanged(_site, 'getH5PlayV1: not an object');
    final error = jsonInt(decoded['error'] ?? decoded['code']) ?? 0;
    if (error != 0) {
      throw StreamUnavailable(_site, 'getH5PlayV1 error $error: ${jsonString(decoded['msg']) ?? ''}');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw const ApiChanged(_site, 'getH5PlayV1: no data');
    return data;
  }

  /// §5.1 qualities: `multirates` in server order, deduplicated by rate; an
  /// empty list becomes one "默认" entry for `data.rate`. Rank follows order.
  static List<Quality> qualities(Map<String, dynamic> data) {
    final seen = <String>{};
    final raw = [
      for (final item in (data['multirates'] as List?) ?? const [])
        if (item is Map && jsonInt(item['rate']) != null && seen.add('${jsonInt(item['rate'])}'))
          (id: '${jsonInt(item['rate'])}', label: decodeHtmlEntities(jsonString(item['name']) ?? '')),
    ];
    if (raw.isEmpty) {
      return [Quality(id: '${jsonInt(data['rate']) ?? -1}', label: '默认', rank: 0)];
    }
    return [for (var i = 0; i < raw.length; i++) Quality(id: raw[i].id, label: raw[i].label, rank: raw.length - i)];
  }

  /// §5.2 CDN codes: `cdnsWithName` in order without duplicates, `rtmp_cdn`
  /// first when missing, `scdn*` codes last; an empty list means "let the
  /// server pick" (`''`).
  static List<String> cdns(Map<String, dynamic> data) {
    final codes = <String>[];
    for (final item in (data['cdnsWithName'] as List?) ?? const []) {
      final code = item is Map ? jsonString(item['cdn']) : null;
      if (code != null && !codes.contains(code)) codes.add(code);
    }
    final current = jsonString(data['rtmp_cdn']);
    if (current != null && !codes.contains(current)) codes.insert(0, current);
    if (codes.isEmpty) return const [''];
    return [...codes.where((code) => !code.startsWith('scdn')), ...codes.where((code) => code.startsWith('scdn'))];
  }

  /// §5.3 the rate the server actually delivered: a non-negative integer, as
  /// a number or an integer string; anything else is unconfirmed (null).
  static String? confirmedRate(Map<String, dynamic> data) {
    final value = data['rate'];
    final rate = value is num
        ? (value == value.truncate() ? value.toInt() : null)
        : value is String
        ? int.tryParse(value.trim())
        : null;
    return rate != null && rate >= 0 ? '$rate' : null;
  }

  static bool _absolute(String value) => RegExp('^(https?|rtmp)://', caseSensitive: false).hasMatch(value);

  static bool _mediaPath(String value) {
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
    return path.endsWith('.flv') || path.endsWith('.m3u8') || path.endsWith('.mp4');
  }

  /// §6.5 the media URL, or null when there is none. A CDN base alone is
  /// never a media URL.
  static Uri? mediaUrl(Map<String, dynamic> data) {
    String? field(String key) {
      final text = jsonString(data[key]);
      return text == null ? null : decodeHtmlEntities(text);
    }

    final live = field('rtmp_live');
    if (live != null && _absolute(live)) return Uri.tryParse(live);
    final base = field('rtmp_url') ?? field('flv_url');
    if (live != null && base != null && _absolute(base)) {
      final left = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final right = live.startsWith('/') ? live.substring(1) : live;
      return Uri.tryParse('$left/$right');
    }
    for (final key in const ['player_1', 'stream_url', 'url']) {
      final value = field(key);
      if (value != null && _absolute(value)) return Uri.tryParse(value);
    }
    final flv = field('flv_url');
    if (flv != null && _absolute(flv) && _mediaPath(flv)) return Uri.tryParse(flv);
    return null;
  }

  /// §6.8 lease for a media URL issued at [issuedAt]: only URLs with
  /// `expire > 0`; refresh `min(45 s, expire / 4)` before expiry; expiry cuts
  /// the established connection.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final expire = int.tryParse(url.queryParameters['expire'] ?? '') ?? 0;
    if (expire <= 0) return null;
    final expiresAt = issuedAt.add(Duration(seconds: expire));
    final lead = math.min(45, expire ~/ 4);
    return Lease(
      refreshAt: expiresAt.subtract(Duration(seconds: lead)),
      expiresAt: expiresAt,
      cutsConnection: true,
    );
  }
}
