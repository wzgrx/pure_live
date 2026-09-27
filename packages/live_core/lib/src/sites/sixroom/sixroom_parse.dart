import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'sixroom';

/// What a 6.cn room page says about the room (spec/sites/sixroom.md §4).
typedef SixRoomPage = ({RoomDetail detail, String userId, String? flvTitle, String? codec});

/// Pure parsing of 6.cn responses (spec/sites/sixroom.md).
abstract final class SixRoomParse {
  /// §1 room number.
  static final RegExp roomId = RegExp(r'^[1-9]\d{1,11}$');

  /// §2.1 the one top-level category.
  static const categoryId = 'v6';

  /// §2.1 list types with a platform area name.
  static const areas = [
    Area(id: 'u0', name: '歌区', categoryId: categoryId),
    Area(id: 'u1', name: '舞区', categoryId: categoryId),
    Area(id: 'u2', name: '脱口秀', categoryId: categoryId),
    Area(id: 'u8', name: '派对', categoryId: categoryId),
  ];

  /// §2.2 list type of the recommendation.
  static const recommendType = 'special';

  /// §2.2 rows per page.
  static const pageSize = 20;

  /// §5 the only quality.
  static const source = Quality(id: 'source', label: '原画', rank: 1);

  /// The room page.
  static Uri link(String id) => Uri.parse('https://v.6.cn/$id');

  static String _plain(String text) =>
      decodeHtmlEntities(text.replaceAll(RegExp('<[^>]*>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();

  static Uri? _image(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    return jsonUrl(text);
  }

  /// §2.2 `coop-mobile-getlivelistnew.php` for [type]; the page ends at
  /// `roomListCount[type]` or on an empty page.
  static Page<RoomCard> list(String body, {required String type, required int page}) {
    final Object? root;
    try {
      root = jsonDecode(body);
    } on FormatException {
      throw const ApiChanged(_site, 'getlivelistnew: not JSON');
    }
    if (root is! Map || root['flag'] != '001') {
      throw ApiChanged(_site, 'getlivelistnew: flag ${root is Map ? root['flag'] : null}');
    }
    final content = root['content'];
    // An empty type answers `content: []`.
    if (content is! Map) return const Page.empty();
    final rows = content[type] is List ? content[type] as List : const <Object?>[];
    final counts = content['roomListCount'];
    final total = counts is Map ? jsonInt(counts[type]) : null;
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = jsonString(row['rid']);
      if (id == null || !roomId.hasMatch(id) || !seen.add(id)) continue;
      final name = decodeHtmlEntities(jsonString(row['username']) ?? '');
      final title = [row['livetitle'], row['userMood']].map(jsonString).nonNulls.firstOrNull;
      final online = jsonInt(row['count']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: title == null ? name : _plain(title),
          anchorName: name,
          state: LiveState.live,
          cover: _image(row['pic']) ?? _image(row['pospic']),
          area: jsonString(row['anchor_area']),
          audience: Audience(online: online != null && online >= 0 ? online : null),
          avatar: _image(row['picuser']),
        ),
      );
    }
    final more = rows.isNotEmpty && (total == null || page * pageSize < total);
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `search.php` (HTML): streamers, live or not, one page. The "六间房提示您"
  /// page answers an over-long keyword.
  static Page<RoomCard> search(String html) {
    if (!html.contains('page-search-user')) {
      final message = RegExp('class="rcontent">([^<]*)<').firstMatch(html)?.group(1)?.trim();
      if (message != null && message.contains('过长')) return const Page.empty();
      throw ApiChanged(_site, 'search: ${message ?? 'no result list'}');
    }
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final block in html.split('<li data-uid="').skip(1)) {
      final id =
          RegExp(r'class="rid-num">(\d+)<').firstMatch(block)?.group(1) ??
          RegExp(r'href="/(?:profile/)?(\d+)"').firstMatch(block)?.group(1);
      if (id == null || !roomId.hasMatch(id) || !seen.add(id)) continue;
      final name = _plain(RegExp('class="alias[^"]*">([^<]*)<').firstMatch(block)?.group(1) ?? '');
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: name,
          anchorName: name,
          state: block.contains('class="live"') ? LiveState.live : LiveState.offline,
          avatar: _image(RegExp('data-src="([^"]+)"').firstMatch(block)?.group(1)),
        ),
      );
    }
    return Page(cards);
  }

  static String? _js(String html, String key) {
    final single = RegExp(key + r":\s*'((?:[^'\\]|\\.)*)'").firstMatch(html)?.group(1);
    if (single != null) return single.replaceAll(r"\'", "'");
    return RegExp(key + r':\s*"((?:[^"\\]|\\.)*)"').firstMatch(html)?.group(1)?.replaceAll(r'\"', '"');
  }

  /// The JSON object written after `key: ` in the page script.
  static Object? _jsObject(String html, String key) {
    final at = html.indexOf('$key: {');
    if (at < 0) return null;
    final start = html.indexOf('{', at);
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5c) {
          escaped = true;
        } else if (c == 0x22) {
          quoted = false;
        }
      } else if (c == 0x22) {
        quoted = true;
      } else if (c == 0x7b) {
        depth++;
      } else if (c == 0x7d && --depth == 0) {
        try {
          return jsonDecode(html.substring(start, i + 1));
        } on FormatException {
          return null;
        }
      }
    }
    return null;
  }

  /// §4 the room page `https://v.6.cn/<房间号>`: the page script names the
  /// streamer (`rid` is the user id, `roomid` the room number), the stream
  /// title and the broadcast id.
  static SixRoomPage page(String html, {required String expectedId, int status = 200}) {
    if (status == 404) throw NotFound(_site, 'room $expectedId');
    final id = RegExp(r'roomid:\s*(\d+)').firstMatch(html)?.group(1);
    final userId = RegExp(r"\brid:\s*'(\d+)'").firstMatch(html)?.group(1);
    if (id == null || userId == null) throw ApiChanged(_site, 'room page $expectedId: no roomid/rid');
    if (id != expectedId) throw ApiChanged(_site, 'room page: asked $expectedId, got $id');
    final liveId = _js(html, 'liveid') ?? '0';
    String? flvTitle;
    String? codec;
    final streams = _jsObject(html, 'flvTitle');
    if (streams is Map) {
      for (final lane in streams.values) {
        if (lane is! Map) continue;
        final name = jsonString(lane['flvtitle']);
        if (name == null || !RegExp(r'^v\d+-\d+(?:-many)?$').hasMatch(name)) continue;
        flvTitle = name;
        final info = lane['streamInfo'];
        final meta = info is Map ? info[name] : null;
        codec = switch (meta is Map ? jsonString(meta['videoCodec'])?.toLowerCase() : null) {
          'avc' || 'h264' => 'avc',
          'hevc' || 'h265' => 'hevc',
          _ => null,
        };
        break;
      }
    }
    final live = liveId != '0' && flvTitle != null;
    if (!live && liveId != '0') throw ApiChanged(_site, 'room page $id: liveid $liveId without a stream name');
    final name = _plain(_js(html, 'masterName') ?? '');
    final mood = _js(html, 'privNotic');
    final area = switch (_js(html, 'usertype')) {
      final String type => areas.where((a) => a.id == type).firstOrNull?.name,
      null => null,
    };
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, id),
          title: mood == null || _plain(mood).isEmpty ? name : _plain(mood),
          anchorName: name,
          state: live ? LiveState.live : LiveState.offline,
          cover: _image(_js(html, 'posterPic')),
          area: area,
        ),
        link: link(id),
        avatar: _image(_js(html, 'picuser')),
      ),
      userId: userId,
      flvTitle: live ? flvTitle : null,
      codec: codec,
    );
  }

  /// §6 the one FLV line of a live room.
  static StreamLine line(SixRoomPage page, {required Map<String, String> headers}) {
    final name = page.flvTitle;
    if (page.detail.state != LiveState.live || name == null) throw const StreamUnavailable(_site, 'not live');
    return StreamLine(
      url: Uri.parse('https://wlive.6rooms.com/httpflv/$name.flv'),
      format: StreamFormat.flv,
      lineId: 'wlive',
      requested: source,
      headers: headers,
      codec: page.codec,
    );
  }
}
