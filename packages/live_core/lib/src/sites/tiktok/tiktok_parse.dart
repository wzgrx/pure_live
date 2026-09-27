import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'tiktok';

Map<Object?, Object?> _obj(Object? value) => value is Map ? value : const <Object?, Object?>{};

/// A user's LIVE answer reduced to what the adapter needs (spec/sites/tiktok.md §4).
typedef TikTokRoom = ({RoomDetail detail, Map<String, Object?> pull, Map<Object?, Object?> options, bool restricted});

/// Pure parsing of TikTok LIVE responses (spec/sites/tiktok.md).
abstract final class TikTokParse {
  /// §1 a username (the room id), lower case.
  static final RegExp username = RegExp(r'^[a-z0-9_](?:[a-z0-9._]{0,22}[a-z0-9_])?$');

  /// §1 a numeric LIVE room id (changes every broadcast).
  static final RegExp liveRoomId = RegExp(r'^[1-9]\d{14,24}$');

  /// The LIVE page of [user].
  static Uri link(String user) => Uri.parse('https://www.tiktok.com/@$user/live');

  static Map<String, dynamic> _json(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    return decoded;
  }

  /// §4 `api-live/user/room`.
  static TikTokRoom userRoom(String body, {required String roomId}) {
    final root = _json(body, 'user/room');
    final code = jsonInt(root['statusCode']);
    if (code == 19881007) throw NotFound(_site, 'no TikTok user $roomId');
    if (code != 0) throw ApiChanged(_site, 'user/room: statusCode $code ${root['message'] ?? ''}');
    final data = _obj(root['data']);
    final user = _obj(data['user']);
    final live = _obj(data['liveRoom']);
    if (jsonString(user['uniqueId'])?.toLowerCase() != roomId) throw const ApiChanged(_site, 'user/room: another user');
    final status = jsonInt(live['status']) ?? jsonInt(user['status']);
    final state = switch (status) {
      2 => LiveState.live,
      4 => LiveState.offline,
      _ => throw ApiChanged(_site, 'user/room: status $status'),
    };
    final name = jsonString(user['nickname']) ?? roomId;
    final stats = _obj(live['liveRoomStats']);
    final viewers = jsonInt(stats['userCount']);
    final entered = jsonInt(stats['enterCount']);
    final paid = jsonInt(_obj(live['paidEvent'])['paid_type']) ?? 0;
    final pullData = _obj(_obj(live['streamData'])['pull_data']);
    final Object? pull;
    try {
      final raw = jsonString(pullData['stream_data']);
      pull = raw == null ? null : jsonDecode(raw);
    } on FormatException {
      throw const ApiChanged(_site, 'user/room: stream_data is not JSON');
    }
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, roomId),
          title: jsonString(live['title']) ?? name,
          anchorName: name,
          state: state,
          cover: jsonUrl(live['coverUrl']),
          audience: state == LiveState.live
              ? Audience(
                  online: viewers != null && viewers >= 0 ? viewers : null,
                  cumulative: entered != null && entered >= 0 ? entered : null,
                )
              : Audience.none,
        ),
        link: link(roomId),
        avatar: jsonUrl(user['avatarLarger']) ?? jsonUrl(user['avatarMedium']),
        introduction: jsonString(user['signature']),
        danmakuKeys: {'roomId': ?jsonString(user['roomId']), 'uniqueId': roomId},
      ),
      pull: state == LiveState.live && pull is Map<String, dynamic> ? pull : const {},
      options: _obj(pullData['options']),
      restricted: jsonInt(live['liveSubOnly']) == 1 || paid != 0,
    );
  }

  /// §1 `webcast/room/info`: the username behind a LIVE room id.
  static String roomOwner(String body) {
    final root = _json(body, 'room/info');
    final data = root['data'];
    if (data is! Map || jsonInt(root['status_code']) != 0) throw const NotFound(_site, 'no such LIVE room');
    final owner = jsonString(_obj(data['owner'])['display_id'])?.toLowerCase();
    if (owner == null || !username.hasMatch(owner)) throw const ApiChanged(_site, 'room/info: no owner');
    return owner;
  }

  /// §5 the qualities of a live room's `stream_data`, best first: names
  /// from `options.qualities` when given; audio-only (`ao`) is left out.
  static List<Quality> qualities(Map<String, Object?> pull, {Map<Object?, Object?> options = const {}}) {
    final data = _obj(pull['data']);
    final named = <String, ({String name, int level})>{};
    final listed = options['qualities'];
    if (listed is List) {
      for (final item in listed.whereType<Map<Object?, Object?>>()) {
        final key = jsonString(item['sdk_key']);
        if (key != null) named[key] = (name: jsonString(item['name']) ?? key, level: jsonInt(item['level']) ?? 0);
      }
    }
    const fallback = {'origin': 6, 'uhd': 5, 'hd': 4, 'sd': 3, 'ld': 2, 'md': 1};
    final out = [
      for (final key in data.keys.whereType<String>())
        if (key != 'ao')
          Quality(id: key, label: named[key]?.name ?? key, rank: named[key]?.level ?? fallback[key] ?? 0),
    ]..sort((a, b) => b.rank.compareTo(a.rank));
    return out;
  }

  /// §5 the FLV and HLS lines of [quality].
  static List<StreamLine> lines(Map<String, Object?> pull, Quality quality, {required Map<String, String> headers}) {
    final main = _obj(_obj(_obj(pull['data'])[quality.id])['main']);
    final Object? sdk;
    try {
      sdk = jsonDecode(jsonString(main['sdk_params']) ?? '{}');
    } on FormatException {
      throw const ApiChanged(_site, 'stream_data: sdk_params is not JSON');
    }
    final codec = switch (jsonString(_obj(sdk)['VCodec'])?.toLowerCase()) {
      'h264' => 'avc',
      'h265' || 'bytevc1' => 'hevc',
      _ => null,
    };
    return [
      for (final (key, format) in const [('flv', StreamFormat.flv), ('hls', StreamFormat.hls)])
        if (jsonUrl(main[key]) case final Uri url)
          StreamLine(
            url: url,
            format: format,
            lineId: key,
            requested: quality,
            confirmed: quality,
            headers: headers,
            codec: codec,
            lease: _lease(url),
          ),
    ];
  }

  /// §5 `expire` (seconds) of a signed media URL: refresh an hour before.
  static Lease? _lease(Uri url) {
    final expire = int.tryParse(url.queryParameters['expire'] ?? '');
    if (expire == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true);
    return Lease(refreshAt: at.subtract(const Duration(hours: 1)), expiresAt: at, cutsConnection: false);
  }
}
