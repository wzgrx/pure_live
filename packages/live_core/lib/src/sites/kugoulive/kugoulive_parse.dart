import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'kugoulive';

/// Pure parsing of Kugou Live (Fanxing) responses (spec/sites/kugoulive.md).
abstract final class KugouLiveParse {
  /// §1 room id.
  static final RegExp roomId = RegExp(r'^[1-9]\d{2,10}$');

  /// §2.1 the one top-level category.
  static const categoryId = 'fanxing';

  /// §2.1 category routes that are personal pages or the recommendation.
  static const _notAreas = {'3001', '3009', '3014', '3015', '8000'};

  /// The room page.
  static Uri link(String id) => Uri.parse('https://fanxing.kugou.com/$id');

  static Object? _decode(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _data(String body, String what) {
    final root = _decode(body, what);
    if (root is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final code = jsonInt(root['code']);
    if (code != 0) throw ApiChanged(_site, '$what: code $code ${jsonString(root['msg']) ?? ''}');
    final data = root['data'];
    if (data is! Map<String, dynamic>) throw ApiChanged(_site, '$what: no data');
    return data;
  }

  /// §2.4 images: relative paths live on `p3.fx.kgimg.com`.
  static Uri? image(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('/')) return Uri.parse('https://p3.fx.kgimg.com$text');
    return jsonUrl(text);
  }

  /// §2.1 the areas linked from the home page, in page order.
  static List<Category> categories(String html) {
    final pattern = RegExp(
      r'''href=["'](?:https://fanxing\.kugou\.com)?/pcindex/category/(\d{1,8})[^"']*["'][^>]*title=["']([^"']+)["']''',
    );
    final seen = <String>{};
    final areas = <Area>[
      for (final match in pattern.allMatches(html))
        if (!_notAreas.contains(match.group(1)) && seen.add(match.group(1)!))
          Area(id: match.group(1)!, name: decodeHtmlEntities(match.group(2)!.trim()), categoryId: categoryId),
    ];
    if (areas.isEmpty) throw const ApiChanged(_site, 'home page: no category links');
    return [Category(id: categoryId, name: '分类', areas: areas)];
  }

  /// §2.2 a list status: 0 and -1 are offline; 1 (camera) and 6 (phone or
  /// game) are live, as is any other positive value on a live list.
  static LiveState? _listState(Object? value) => switch (jsonInt(value)) {
    null => null,
    0 || -1 => LiveState.offline,
    final int n when n > 0 => LiveState.live,
    _ => null,
  };

  /// §2.2 one card; null for rows without a room id or a state.
  static RoomCard? card(Map<String, dynamic> raw) {
    final row = raw['uiType'] == 'star' && raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final id = jsonString(row['roomId']);
    if (id == null || !roomId.hasMatch(id)) return null;
    final state = _listState(row['liveStatus'] ?? row['liveType'] ?? row['status']);
    if (state == null) return null;
    final name = decodeHtmlEntities(jsonString(row['nickName']) ?? '');
    final title = [row['label'], row['topicContent'], row['performContent']].map(jsonString).nonNulls.firstOrNull;
    final online = jsonInt(row['viewerNum'] ?? row['getViewerNum']);
    final hot = jsonInt(row['hot']);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: decodeHtmlEntities(title ?? name),
      anchorName: name,
      state: state,
      cover: image(row['imgPath']) ?? image(row['imagePath']),
      audience: Audience(
        online: state == LiveState.live && online != null && online > 0 ? online : null,
        popularity: hot != null && hot > 0 ? hot : null,
      ),
      avatar: image(row['userLogo']) ?? image(row['logo']),
      followers: jsonCount(row['fansCount']),
    );
  }

  /// §2.2/§2.3 `index/list` and `index/list_v4`: `hasNextPage == 1` means
  /// another page.
  static Page<RoomCard> roomList(String body, {required int page}) {
    final data = _data(body, 'room list');
    final rows = data['list'];
    if (rows is! List) throw const ApiChanged(_site, 'room list: list is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[
      for (final row in rows)
        if (row is Map<String, dynamic>)
          if (card(row) case final card? when seen.add(card.ref.roomId)) card,
    ];
    final more = jsonInt(data['hasNextPage']) == 1 && rows.isNotEmpty;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `type_all.jsonp`: streamers, live or not, in one page.
  static Page<RoomCard> search(String body) {
    final text = body.trim();
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open <= 0 || close <= open) throw const ApiChanged(_site, 'search: not JSONP');
    final root = _decode(text.substring(open + 1, close), 'search');
    if (root is! Map<String, dynamic>) throw const ApiChanged(_site, 'search: not an object');
    final code = jsonInt(root['code']);
    if (code != 0) throw ApiChanged(_site, 'search: code $code');
    final data = root['data'];
    final anchor = data is Map ? data['anchor'] : null;
    final rows = anchor is Map ? anchor['list'] : null;
    if (rows is! List) return const Page.empty();
    final seen = <String>{};
    return Page([
      for (final row in rows)
        if (row is Map<String, dynamic>)
          if (card(row) case final card? when seen.add(card.ref.roomId)) card,
    ]);
  }

  /// §4 `getEnterRoomInfo`; a room with no kugou id and no name does not
  /// exist.
  static ({RoomDetail detail, bool restricted}) detail(String body, {required String expectedId}) {
    final data = _data(body, 'getEnterRoomInfo');
    final info = data['normalRoomInfo'];
    if (info is! Map<String, dynamic>) throw const ApiChanged(_site, 'getEnterRoomInfo: no normalRoomInfo');
    final name = jsonString(info['nickName']);
    final kugouId = jsonInt(info['kugouId']) ?? 0;
    if (name == null && kugouId == 0) throw NotFound(_site, 'room $expectedId');
    final liveType = jsonInt(data['liveType']);
    final session = jsonString(data['liveSessionId']);
    final LiveState state;
    if (liveType == -1) {
      state = LiveState.offline;
    } else if (session != null) {
      state = LiveState.live;
    } else {
      throw ApiChanged(_site, 'getEnterRoomInfo: liveType $liveType without a session');
    }
    final anchor = decodeHtmlEntities(name ?? '');
    final title = jsonString(info['privateMesg']);
    final notice = jsonString(info['publicMesg']);
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, expectedId),
          title: title == null ? anchor : decodeHtmlEntities(title),
          anchorName: anchor,
          state: state,
          cover: image(info['imgPath']),
        ),
        link: link(expectedId),
        avatar: image(info['userLogo']),
        notice: notice == null ? null : decodeHtmlEntities(notice),
      ),
      restricted: (jsonInt(info['limitType']) ?? 0) > 0,
    );
  }

  /// §6.3 lease: `txTime` is the hex expiry of the Tencent signature.
  static Lease? lease(Uri url) {
    final raw = url.queryParameters['txTime'];
    final seconds = raw == null ? null : int.tryParse(raw, radix: 16);
    if (seconds == null) return null;
    final expires = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    return Lease(refreshAt: expires.subtract(const Duration(minutes: 10)), expiresAt: expires, cutsConnection: false);
  }

  /// §5 the source quality.
  static const source = Quality(id: 'source', label: '原画', rank: 1);

  /// §5/§6 `streamaddr`: one quality, one FLV (and HLS when given) per line.
  static StreamSet streams(String body, {required String expectedId, required Map<String, String> headers}) {
    final data = _data(body, 'streamaddr');
    if (jsonInt(data['status']) != 1) throw StreamUnavailable(_site, 'streamaddr status ${data['status']}');
    final id = jsonString(data['roomId']);
    if (id != expectedId) throw ApiChanged(_site, 'streamaddr: asked $expectedId, got $id');
    final lines = <StreamLine>[];
    final seen = <Uri>{};
    for (final line in (data['lines'] as List?) ?? const []) {
      if (line is! Map) continue;
      final sid = jsonString(line['sid']) ?? '${lines.length}';
      for (final profile in (line['streamProfiles'] as List?) ?? const []) {
        if (profile is! Map) continue;
        final codec = switch (jsonInt(profile['codec'])) {
          1 => 'avc',
          2 => 'hevc',
          _ => null,
        };
        for (final (key, format) in const [('httpsFlv', StreamFormat.flv), ('httpsHls', StreamFormat.hls)]) {
          final url = ((profile[key] as List?) ?? const []).map(jsonUrl).nonNulls.firstOrNull;
          if (url == null || !seen.add(url)) continue;
          lines.add(
            StreamLine(
              url: url,
              format: format,
              lineId: 'sid$sid-${format.name}',
              requested: source,
              headers: headers,
              codec: codec,
              lease: lease(url),
            ),
          );
        }
      }
    }
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'streamaddr: no line');
    return StreamSet(qualities: const [source], selected: source, lines: lines);
  }
}
