import 'dart:convert';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'weibo';

/// A Weibo room response reduced to what the adapter needs.
typedef WeiboRoom = ({RoomDetail detail, int watchLimit, bool playEnabled, List<Uri> media});

/// Pure parsing of Weibo Live responses (spec/sites/weibo.md).
abstract final class WeiboParse {
  /// §1 broadcast id: digits, a colon and 16–48 letters or digits.
  static final RegExp liveId = RegExp(r'^\d{3,8}:[0-9A-Za-z]{16,48}$');

  /// The only quality (§5).
  static const origin = Quality(id: 'origin', label: '原画', rank: 1);

  static Map<String, dynamic> _envelope(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final code = jsonInt(decoded['code']);
    final error = jsonInt(decoded['error_code']);
    if (error == 27401) throw NotFound(_site, jsonString(decoded['msg']));
    if (code != 100000 || error != 0) {
      throw ApiChanged(_site, '$what: code $code error_code $error ${jsonString(decoded['msg']) ?? ''}');
    }
    return decoded;
  }

  /// The room page for [id].
  static Uri link(String id) => Uri.parse('https://weibo.com/l/wblive/p/show/$id');

  /// §2.2 recommendation snapshot: one page, every card live.
  static Page<RoomCard> recommended(String body) {
    final data = _envelope(body, 'pc_recommend')['data'];
    final rows = data is Map ? data['data'] : null;
    if (rows is! List) throw const ApiChanged(_site, 'pc_recommend: data.data is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = jsonString(row['liveid']);
      if (id == null || !liveId.hasMatch(id) || !seen.add(id)) continue;
      final name = decodeHtmlEntities(jsonString(row['nickname']) ?? '');
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: name,
          anchorName: name,
          state: LiveState.live,
          cover: jsonUrl(row['cover']),
        ),
      );
    }
    return Page(cards);
  }

  /// §4 room response; throws NotFound for a missing broadcast.
  static WeiboRoom room(String body, {required String expectedId}) {
    final data = _envelope(body, 'show_pc_live')['data'];
    if (data is! Map<String, dynamic>) throw const ApiChanged(_site, 'show_pc_live: data is not an object');
    final id = jsonString(data['liveId']);
    if (id != expectedId) throw ApiChanged(_site, 'show_pc_live: asked $expectedId, got $id');
    final state = switch (jsonInt(data['status'])) {
      1 => LiveState.live,
      3 || 5 => LiveState.offline,
      final other => throw ApiChanged(_site, 'show_pc_live: unknown status $other'),
    };
    final user = data['user'] is Map ? data['user'] as Map : const <String, dynamic>{};
    final started = jsonInt(data['startTime']) ?? 0;
    final media = <Uri>[];
    for (final key in const ['live_origin_flv_url', 'live_origin_hls_url']) {
      final url = jsonUrl(data[key]);
      if (url != null && !media.contains(url)) media.add(url);
    }
    final detail = RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, id!),
        title: decodeHtmlEntities(jsonString(data['title']) ?? ''),
        anchorName: decodeHtmlEntities(jsonString(user['screenName']) ?? ''),
        state: state,
        cover: jsonUrl(data['cover']),
        liveSince: started > 0 ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true) : null,
      ),
      link: link(id),
      avatar: jsonUrl(user['avatar']) ?? jsonUrl(user['profileImageUrl']),
    );
    return (
      detail: detail,
      watchLimit: jsonInt(data['watch_limit']) ?? 0,
      playEnabled: jsonInt(data['play_switch']) != 0,
      media: media,
    );
  }

  /// §5/§6 lines of a live room; throws the §9 errors when there are none.
  static List<StreamLine> lines(WeiboRoom room, {required Map<String, String> headers}) {
    if (room.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (room.watchLimit != 0) throw NeedsLogin(_site, 'watch_limit ${room.watchLimit}');
    if (!room.playEnabled) throw const StreamUnavailable(_site, 'play_switch 0');
    final lines = <StreamLine>[];
    for (final url in room.media) {
      final path = url.path.toLowerCase();
      final format = path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;
      final segment = url.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
      lines.add(
        StreamLine(
          url: url,
          format: format,
          lineId: segment != null && url.pathSegments.length > 1 ? segment : url.host,
          requested: origin,
          headers: headers,
          codec: path.contains('avc') ? 'avc' : null,
        ),
      );
    }
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'no media URL');
    return lines;
  }
}
