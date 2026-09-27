import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'baidulive';

/// A room command reduced to what the adapter needs (spec/sites/baidulive.md §4).
typedef BaiduLiveRoom = ({RoomDetail detail, bool paid, bool blocked, Map<String, dynamic> video});

/// Pure parsing of Baidu Live responses (spec/sites/baidulive.md).
abstract final class BaiduLiveParse {
  /// §1 room id.
  static final RegExp roomId = RegExp(r'^[1-9]\d{5,19}$');

  /// §2.1 the one top-level category.
  static const categoryId = 'baidu';

  /// §2.2 the recommendation tab.
  static const ({String tab, int channel}) recommendTab = (tab: 'rec', channel: 570);

  static const _feedSecret = 'CtmXzYPtdE58nCCcvqM0ectyqW3N5rfY';

  /// §5 the source quality (`avc_url`).
  static const origin = Quality(id: 'origin', label: '原画', rank: 10000);

  /// The room page.
  static Uri link(String id) => Uri.parse('https://live.baidu.com/m/room/$id');

  /// §2.2 feed signature: md5 of the sorted `key=value` pairs joined by `&`,
  /// then `&` and the web secret.
  static String feedSign(Map<String, String> form) {
    final keys = form.keys.where((key) => key != 'sign').toList()..sort();
    final canonical = keys.map((key) => '$key=${form[key]}').join('&');
    return md5.convert(utf8.encode('$canonical&$_feedSecret')).toString();
  }

  static Map<String, dynamic> _root(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final errno = jsonInt(decoded['errno']);
    if (errno != 0) throw ApiChanged(_site, '$what: errno $errno ${jsonString(decoded['errmsg']) ?? ''}');
    return decoded;
  }

  /// §2.2 an area id carries the tab and its channel: `shopping:574`.
  static ({String tab, int channel})? areaKey(String id) {
    final match = RegExp(r'^([a-z][a-z0-9_]{0,31}):(\d{1,6})$').firstMatch(id);
    return match == null ? null : (tab: match.group(1)!, channel: int.parse(match.group(2)!));
  }

  /// §2.1 the tabs of the first feed page, without the recommendation.
  static List<Category> categories(String body) {
    final data = _root(body, 'feed')['data'];
    final tab = data is Map ? data['tab'] : null;
    final items = tab is Map ? tab['items'] : null;
    if (items is! List) throw const ApiChanged(_site, 'feed: no tab list');
    final seen = <String>{};
    final areas = <Area>[
      for (final item in items)
        if (item is Map)
          if ((jsonString(item['type']), jsonString(item['name']), jsonInt(item['channel_id']))
              case (final String type, final String name, final int channel)
              when type != recommendTab.tab && seen.add(type))
            Area(id: '$type:$channel', name: name, categoryId: categoryId),
    ];
    return [Category(id: categoryId, name: '频道', areas: areas)];
  }

  /// §2.2 cursor `<session_id>:<refresh_index>`.
  static ({String session, int index})? cursor(PageCursor? cursor) {
    final match = RegExp(r'^(\d+):(\d+)$').firstMatch(cursor?.value ?? '');
    return match == null ? null : (session: match.group(1)!, index: int.parse(match.group(2)!));
  }

  /// §2.2 one feed page; a non-empty page links to the next refresh.
  static Page<RoomCard> feed(String body) {
    final data = _root(body, 'feed')['data'];
    final feed = data is Map ? data['feed'] : null;
    if (feed is! Map) throw const ApiChanged(_site, 'feed: no feed');
    final inner = jsonInt(feed['inner_errno']);
    if (inner != 0) throw ApiChanged(_site, 'feed: inner_errno $inner');
    final items = feed['items'];
    if (items is! List) throw const ApiChanged(_site, 'feed: items is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = jsonString(item['room_id']);
      if (id == null || !roomId.hasMatch(id) || !seen.add(id)) continue;
      final state = switch (jsonInt(item['live_status'])) {
        1 => LiveState.live,
        0 || 2 || 3 => LiveState.offline,
        _ => null,
      };
      if (state == null) continue;
      final host = item['host'] is Map ? item['host'] as Map : const <Object?, Object?>{};
      final label = item['left_label'] is Map ? jsonString((item['left_label'] as Map)['text']) : null;
      final audience = jsonInt(item['audience_count']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(item['title']) ?? jsonString(host['name']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(host['name']) ?? ''),
          state: state,
          cover: jsonUrl(item['cover']),
          area: jsonString(item['live_tag']) ?? label,
          audience: Audience(online: state == LiveState.live && audience != null && audience >= 0 ? audience : null),
          avatar: jsonUrl(host['avatar']),
        ),
      );
    }
    final session = jsonString(feed['session_id']);
    final index = jsonInt(feed['refresh_index']);
    final more = items.isNotEmpty && session != null && index != null;
    return Page(cards, next: more ? PageCursor('$session:$index') : null);
  }

  /// §4 the room command 371; `data.371 == null` is a room that does not
  /// exist.
  static BaiduLiveRoom room(String body, {required String expectedId}) {
    final data = _root(body, 'searchbox')['data'];
    final command = data is Map ? data['371'] : null;
    if (command == null) throw NotFound(_site, 'room $expectedId');
    if (command is! Map<String, dynamic>) throw const ApiChanged(_site, 'searchbox: 371 is not an object');
    final error = jsonInt(command['error_code']);
    if (error == 1 || error == 4) throw NotFound(_site, 'room $expectedId: error_code $error');
    if (error != 0) throw ApiChanged(_site, 'searchbox: error_code $error');
    final host = command['host'] is Map ? command['host'] as Map : const <Object?, Object?>{};
    final video = command['video'] is Map<String, dynamic>
        ? command['video'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final status = jsonInt(command['status']);
    final state = switch (status) {
      0 => LiveState.live,
      -1 || 1 || 2 || 3 || 20 => LiveState.offline,
      _ => throw ApiChanged(_site, 'searchbox: status $status'),
    };
    final name = decodeHtmlEntities(jsonString(host['nick_name']) ?? jsonString(host['name']) ?? '');
    final cover = video['cover'] is Map ? video['cover'] as Map : const <Object?, Object?>{};
    final image = switch (host['image']) {
      final Map<Object?, Object?> map => map,
      _ => const <Object?, Object?>{},
    };
    final online = jsonInt(command['online_users']);
    final detail = RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, expectedId),
        title: decodeHtmlEntities(jsonString(video['title']) ?? name),
        anchorName: name,
        state: state,
        cover: jsonUrl(cover['cover_100']) ?? jsonUrl(cover['vertical_cover']),
        area: jsonString(command['category']),
        audience: Audience(online: state == LiveState.live && online != null && online >= 0 ? online : null),
      ),
      link: link(expectedId),
      avatar: jsonUrl(image['image_33']),
      introduction: jsonString(video['description']),
      danmakuKeys: {'roomId': expectedId},
    );
    return (
      detail: detail,
      paid: (jsonInt(command['has_pay_service']) ?? 0) > 0,
      blocked: (jsonInt(command['is_forbidden_url']) ?? 0) > 0 || (jsonInt(command['ban_status']) ?? 0) > 0,
      video: video,
    );
  }

  static Quality _resolution(int height) => Quality(id: '${height}p', label: '${height}p', rank: height);

  /// §5 qualities: the source, then each `url_list` resolution, best first.
  static List<Quality> qualities(Map<String, dynamic> video) {
    final heights = <int>{
      for (final item in (video['url_list'] as List?) ?? const [])
        if (item is Map && (jsonInt(item['resolution']) ?? 0) > 0) jsonInt(item['resolution'])!,
    }.toList()..sort((a, b) => b.compareTo(a));
    return [
      if ((jsonUrl(video['avc_url']) ?? jsonUrl(video['play_url'])) != null) origin,
      for (final height in heights) _resolution(height),
    ];
  }

  /// §5/§6 the lines of [quality]: FLV per CDN first, then HLS.
  static List<StreamLine> lines(BaiduLiveRoom room, Quality quality, {required Map<String, String> headers}) {
    if (room.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (room.paid) throw const NeedsLogin(_site, 'paid room');
    if (room.blocked) throw const StreamUnavailable(_site, 'forbidden or banned');
    final video = room.video;
    final flv = <Uri>[];
    final hls = <Uri>[];
    if (quality.id == origin.id) {
      final url = jsonUrl(video['avc_url']) ?? jsonUrl(video['play_url']);
      if (url != null) flv.add(url);
    } else {
      for (final item in (video['url_list'] as List?) ?? const []) {
        if (item is! Map || '${jsonInt(item['resolution'])}p' != quality.id) continue;
        for (final urls in (item['urls'] as List?) ?? const []) {
          if (urls is! Map) continue;
          if (jsonUrl(urls['flv']) case final url? when !flv.contains(url)) flv.add(url);
          if (jsonUrl(urls['hls']) case final url? when !hls.contains(url)) hls.add(url);
        }
      }
    }
    final lines = <StreamLine>[
      for (final (format, urls) in [(StreamFormat.flv, flv), (StreamFormat.hls, hls)])
        for (final url in urls)
          StreamLine(
            url: url,
            format: format,
            lineId: '${format.name}:${url.host.split('.').first}',
            requested: quality,
            headers: headers,
            codec: 'avc',
          ),
    ];
    if (lines.isEmpty) throw StreamUnavailable(_site, 'no ${quality.id} URL');
    return lines;
  }
}
