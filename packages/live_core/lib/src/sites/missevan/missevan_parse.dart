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

const _site = 'missevan';

/// Pure parsing of Missevan responses (spec/sites/missevan.md).
abstract final class MissevanParse {
  /// §1 a room id: 1–18 digits, no leading zero.
  static final RegExp roomIdPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  /// §2.1 the query parameter of each area namespace.
  static const namespaceQuery = {'catalog': 'catalog_id', 'tag': 'tag_id', 'list': 'type'};

  /// §2.1 names of the namespaces as categories.
  static const namespaceNames = {'catalog': '分区', 'list': '团播', 'tag': '标签'};

  /// §5 the single quality (the pull URLs carry `qn=10000`).
  static const original = Quality(id: '10000', label: '原画', rank: 10000);

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

  /// §9 the `info` of an API response; maps the HTTP status and `code`.
  static Object? info(String body, {required String what, int status = 200}) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    final decoded = status == 404 && body.trim().isEmpty ? null : _json(body, what);
    final code = decoded is Map ? jsonInt(decoded['code']) : null;
    if (code == 500030004 || status == 404) throw NotFound(_site, '$what: code $code, HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
    final root = _map(decoded, what);
    if (code != 0) throw ApiChanged(_site, '$what code $code: ${jsonString(root['info']) ?? ''}');
    return root['info'];
  }

  /// §2.2 `//` covers get `https:`.
  static Uri? picture(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    return jsonUrl(text);
  }

  /// §2.1 `meta/data` tabs grouped by namespace; unknown tab types skipped.
  static List<Category> categories(String body, {int status = 200}) {
    final data = _map(info(body, what: 'meta/data', status: status), 'meta/data');
    final order = <String>[];
    final areas = <String, List<Area>>{};
    final seen = <String>{};
    for (final raw in _list(data['tabs'], 'meta/data.tabs')) {
      if (raw is! Map) continue;
      final type = jsonString(raw['type']);
      if (type == null || !namespaceQuery.containsKey(type)) continue;
      final id = jsonInt(raw[type == 'list' ? 'list_type' : '${type}_id']);
      final name = jsonString(raw['name']);
      if (id == null || id <= 0 || name == null || !seen.add('$type:$id')) continue;
      if (!areas.containsKey(type)) order.add(type);
      areas
          .putIfAbsent(type, () => [])
          .add(Area(id: '$id', name: name, categoryId: type, icon: picture(raw['icon_url'])));
    }
    if (areas.isEmpty) throw const ApiChanged(_site, 'meta/data: no known tabs');
    return [for (final type in order) Category(id: type, name: namespaceNames[type]!, areas: areas[type]!)];
  }

  static RoomCard? _card(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['room_id'] ?? ''}';
    if (!roomIdPattern.hasMatch(id)) return null;
    final status = raw['status'];
    final open = status is Map ? jsonInt(status['open']) : null;
    if (open != 0 && open != 1) throw ApiChanged(_site, 'room $id: status.open $open');
    final statistics = raw['statistics'];
    final score = statistics is Map ? jsonInt(statistics['score']) : null;
    return RoomCard(
      ref: RoomRef(_site, id),
      title: decodeHtmlEntities(jsonString(raw['name']) ?? ''),
      anchorName: jsonString(raw['creator_username']) ?? '',
      state: open == 1 ? LiveState.live : LiveState.offline,
      cover: picture(raw['cover_url']),
      area: jsonString(raw['catalog_name']),
      audience: Audience(popularity: score != null && score >= 0 ? score : null),
      avatar: picture(raw['creator_iconurl']),
    );
  }

  static ({List<dynamic> rows, int? page, int? maxPage}) _page(Map<String, dynamic> data, String key, String what) {
    final pagination = data['pagination'];
    return (
      rows: _list(data[key] ?? const [], '$what.$key'),
      page: pagination is Map ? jsonInt(pagination['p']) : null,
      maxPage: pagination is Map ? jsonInt(pagination['maxpage']) : null,
    );
  }

  /// §2.2 a `chatroom/open/list` page: live rooms only, deduplicated; the
  /// last page is at `maxpage` or when `Datas` is empty.
  static Page<RoomCard> listPage(String body, {required int page, int status = 200}) {
    final data = _map(info(body, what: 'open/list', status: status), 'open/list');
    final result = _page(data, 'Datas', 'open/list');
    final seen = <String>{};
    final rooms = [
      for (final raw in result.rows)
        if (_card(raw) case final card? when card.state == LiveState.live && seen.add(card.ref.roomId)) card,
    ];
    final more = result.rows.isNotEmpty && result.maxPage != null && page < result.maxPage!;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 a `chatroom/search` page: live and offline rooms.
  static Page<RoomCard> searchPage(String body, {required int page, int status = 200}) {
    final data = _map(info(body, what: 'chatroom/search', status: status), 'chatroom/search');
    final result = _page(data, 'data', 'chatroom/search');
    final seen = <String>{};
    final rooms = [
      for (final raw in result.rows)
        if (_card(raw) case final card? when seen.add(card.ref.roomId)) card,
    ];
    final more = result.rows.isNotEmpty && result.maxPage != null && page < result.maxPage!;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 `live/<id>`.
  static RoomDetail detail(String body, {int status = 200}) {
    final data = _map(info(body, what: 'live', status: status), 'live');
    final room = _map(data['room'], 'live.room');
    final card = _card(room);
    if (card == null) throw const ApiChanged(_site, 'live.room: no room_id');
    final creator = data['creator'];
    if (creator is Map && '${creator['user_id']}' != '${room['creator_id']}') {
      throw const ApiChanged(_site, 'live: creator does not own the room');
    }
    final roomStatus = room['status'];
    final openTime = roomStatus is Map ? jsonInt(roomStatus['open_time']) : null;
    final avatar = (creator is Map ? picture(creator['iconurl']) : null) ?? card.avatar;
    final websockets = data['websocket'];
    final socket = websockets is List ? websockets.map(jsonUrlOrWs).whereType<String>().firstOrNull : null;
    return RoomDetail(
      card: RoomCard(
        ref: card.ref,
        title: card.title,
        anchorName: (creator is Map ? jsonString(creator['username']) : null) ?? card.anchorName,
        state: card.state,
        cover: card.cover,
        audience: card.audience,
        liveSince: card.state == LiveState.live && openTime != null && openTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(openTime, isUtc: true)
            : null,
        avatar: avatar,
      ),
      link: Uri.parse('https://fm.missevan.com/live/${card.ref.roomId}'),
      avatar: avatar,
      introduction: creator is Map ? jsonString(creator['introduction']) : null,
      notice: jsonString(room['announcement']),
      danmakuKeys: {'roomId': card.ref.roomId, 'websocket': ?socket},
    );
  }

  /// A `ws`/`wss` URL string from a JSON value, or null.
  static String? jsonUrlOrWs(Object? value) {
    final text = jsonString(value);
    final uri = text == null ? null : Uri.tryParse(text);
    return uri != null && (uri.scheme == 'wss' || uri.scheme == 'ws') && uri.host.isNotEmpty ? text : null;
  }

  /// §5 a pull URL: `*.bilivideo.com` with the expected suffix, upgraded to
  /// https; anything else is an unexpected shape.
  static Uri mediaUrl(String value, {required StreamFormat format}) {
    final uri = Uri.tryParse(value.trim());
    final suffix = format == StreamFormat.flv ? '.flv' : '.m3u8';
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.host.endsWith('.bilivideo.com') ||
        !uri.path.endsWith(suffix)) {
      throw ApiChanged(_site, 'pull URL: unexpected ${format.name} address');
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  /// §6.2 lease of a pull URL issued at [issuedAt]: `expires` (Unix s);
  /// refresh min(10 min, a quarter of the lifetime) before.
  static Lease? lease(Uri url, {required DateTime issuedAt, required bool cutsConnection}) {
    final expires = int.tryParse(url.queryParameters['expires'] ?? '');
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = Duration(
      microseconds: math.min(const Duration(minutes: 10).inMicroseconds, lifetime.inMicroseconds ~/ 4),
    );
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: cutsConnection);
  }

  /// §5/§6 the streams of a `live/<id>` response fetched at [issuedAt].
  static StreamSet streams(
    String body, {
    required DateTime issuedAt,
    required Map<String, String> headers,
    int status = 200,
  }) {
    final data = _map(info(body, what: 'live', status: status), 'live');
    final room = _map(data['room'], 'live.room');
    final card = _card(room);
    if (card == null) throw const ApiChanged(_site, 'live.room: no room_id');
    if (card.state != LiveState.live) throw const StreamUnavailable(_site, 'room is not live');
    final channel = room['channel'];
    final lines = <StreamLine>[
      for (final (key, format, id) in const [
        ('flv_pull_url', StreamFormat.flv, 'flv'),
        ('hls_pull_url', StreamFormat.hls, 'hls'),
      ])
        if (channel is Map && jsonString(channel[key]) != null)
          if (mediaUrl(jsonString(channel[key])!, format: format) case final url)
            StreamLine(
              url: url,
              format: format,
              lineId: id,
              requested: original,
              confirmed: original,
              headers: headers,
              lease: lease(url, issuedAt: issuedAt, cutsConnection: format == StreamFormat.hls),
            ),
    ];
    if (lines.isEmpty) throw const ApiChanged(_site, 'live room without pull URLs');
    return StreamSet(qualities: const [original], selected: original, lines: lines);
  }

  /// §1 the room id of an input: digits, or a `fm.missevan.com/live/<id>`
  /// link (also inside share text); null otherwise.
  static String? roomIdOf(String input) {
    final text = input.trim();
    if (roomIdPattern.hasMatch(text)) return text;
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || url.host != 'fm.missevan.com') return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    return segments.length == 2 && segments.first == 'live' && roomIdPattern.hasMatch(segments[1]) ? segments[1] : null;
  }
}
