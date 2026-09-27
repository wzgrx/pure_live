import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'jdlive';

/// The play response reduced to what the adapter needs (spec/sites/jdlive.md §4).
typedef JdLivePlay = ({RoomDetail detail, bool appOnly, Uri? flv, Uri? hls});

/// Pure parsing of JD Live responses (spec/sites/jdlive.md).
abstract final class JdLiveParse {
  /// §1 broadcast id.
  static final RegExp liveId = RegExp(r'^[1-9]\d{4,17}$');

  /// §5 the only quality (`_fhd`).
  static const fhd = Quality(id: 'fhd', label: '超清', rank: 1);

  /// The room page.
  static Uri link(String id) => Uri.parse('https://lives.jd.com/#/$id');

  static Map<String, dynamic> _data(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final code = jsonString(decoded['code']);
    final sub = jsonString(decoded['subCode']);
    if (code != '0') throw ApiChanged(_site, '$what: code $code ${jsonString(decoded['echo']) ?? ''}');
    if (sub != '0') throw NotFound(_site, '$what: subCode $sub');
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw ApiChanged(_site, '$what: no data');
    return data;
  }

  /// §4 status: 1 live; 0 preview, 2 ended, 3 replay, 10/11 paused are all
  /// not broadcasting.
  static LiveState state(Object? status) => switch (jsonInt(status)) {
    1 => LiveState.live,
    0 || 2 || 3 || 10 || 11 => LiveState.offline,
    final other => throw ApiChanged(_site, 'unknown status $other'),
  };

  /// §2.2 cursor `<page>:<currentCount>:<timestamp>`.
  static ({int page, int count, int timestamp})? cursor(PageCursor? cursor) {
    final match = RegExp(r'^(\d+):(\d+):(\d+)$').firstMatch(cursor?.value ?? '');
    if (match == null) return null;
    return (page: int.parse(match.group(1)!), count: int.parse(match.group(2)!), timestamp: int.parse(match.group(3)!));
  }

  /// §2.2 `liveListWithTabToM`: only `templateType == 1` cards are rooms;
  /// a non-empty page links to the next.
  static Page<RoomCard> list(String body, {required int page, required int timestamp}) {
    final data = _data(body, 'liveListWithTabToM');
    final rows = data['list'];
    if (rows is! List) throw const ApiChanged(_site, 'liveListWithTabToM: list is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map || jsonInt(row['templateType']) != 1 || row['data'] is! Map) continue;
      final item = row['data'] as Map;
      final id = jsonString(item['liveId']) ?? jsonString(item['id']);
      if (id == null || !liveId.hasMatch(id) || !seen.add(id)) continue;
      final LiveState live;
      try {
        live = state(item['status']);
      } on ApiChanged {
        continue;
      }
      final pv = jsonInt(item['pv']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(item['title']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(item['userName']) ?? ''),
          state: live,
          cover: jsonUrl(item['indexImage']),
          audience: Audience(cumulative: pv != null && pv >= 0 ? pv : null),
          avatar: jsonUrl(item['userPic']),
        ),
      );
    }
    final count = jsonInt(data['currentCount']);
    final more = cards.isNotEmpty && count != null;
    return Page(cards, next: more ? PageCursor('${page + 1}:$count:$timestamp') : null);
  }

  /// §4 `getImmediatePlayToM`: state, cover and addresses. The response has
  /// no title or streamer name (§4).
  static JdLivePlay play(String body, {required String expectedId}) {
    final data = _data(body, 'getImmediatePlayToM');
    final id = jsonString(data['liveId']);
    if (id != expectedId) throw ApiChanged(_site, 'getImmediatePlayToM: asked $expectedId, got $id');
    final live = state(data['status']);
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, expectedId),
          title: '',
          anchorName: '',
          state: live,
          cover: jsonUrl(data['blurredImg']),
        ),
        link: link(expectedId),
      ),
      appOnly: jsonInt(data['secret']) == 1,
      flv: jsonUrl(data['videoUrl']) ?? jsonUrl(data['pcVideoUrl']),
      hls: jsonUrl(data['h5VideoUrl']),
    );
  }

  /// §5/§6 FLV then HLS.
  static List<StreamLine> lines(JdLivePlay play, {required Map<String, String> headers}) {
    if (play.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (play.appOnly) throw const NeedsLogin(_site, 'JD app only (secret)');
    final lines = <StreamLine>[
      for (final (url, format) in [(play.flv, StreamFormat.flv), (play.hls, StreamFormat.hls)])
        if (url != null)
          StreamLine(url: url, format: format, lineId: format.name, requested: fhd, headers: headers, codec: 'avc'),
    ];
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'no media URL');
    return lines;
  }
}
