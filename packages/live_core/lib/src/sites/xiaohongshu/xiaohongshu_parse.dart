import 'dart:convert';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'xiaohongshu';

/// A share page reduced to what the adapter needs (spec/sites/xiaohongshu.md §4).
typedef XiaohongshuRoom = ({RoomDetail detail, bool restricted, Map<String, dynamic>? pullConfig});

/// Pure parsing of Xiaohongshu share pages and links (spec/sites/xiaohongshu.md).
abstract final class XiaohongshuParse {
  /// §1 room id.
  static final RegExp roomId = RegExp(r'^[1-9]\d{0,19}$');

  /// The share page.
  static Uri link(String id) => Uri.parse('https://www.xiaohongshu.com/livestream/$id');

  /// §1 a room id from a share-page URL or the app deep link; null for any
  /// other URL.
  static String? roomFromUrl(Uri url) {
    if (url.scheme.toLowerCase() == 'xhsdiscover') {
      if (url.host.toLowerCase() != 'live_audience') return null;
      final id = url.queryParameters['room_id'];
      return id != null && roomId.hasMatch(id) ? id : null;
    }
    final host = url.host.toLowerCase();
    if (host != 'www.xiaohongshu.com' && host != 'xiaohongshu.com') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = switch (segments) {
      ['livestream', final id] => id,
      ['livestream', final route, final id] when RegExp(r'^dynpath[A-Za-z0-9]{8}$').hasMatch(route) => id,
      ['hina', 'livestream', final id] || ['hina', 'livestream', final id, _] => id,
      _ => null,
    };
    return id != null && roomId.hasMatch(id) ? id : null;
  }

  /// §1 a short link on `xhslink.com`.
  static bool isShortLink(Uri url) =>
      url.host.toLowerCase() == 'xhslink.com' && RegExp(r'^/(?:m/)?[A-Za-z0-9]{1,64}/?$').hasMatch(url.path);

  /// §4 `window.__INITIAL_STATE__` with bare `undefined` placeholders turned
  /// into `null` outside strings; nothing else of JavaScript is accepted.
  static Map<String, dynamic> state(String html) {
    const marker = 'window.__INITIAL_STATE__=';
    final at = html.indexOf(marker);
    if (at < 0) throw const ApiChanged(_site, 'share page: no __INITIAL_STATE__');
    final end = html.indexOf('</script>', at);
    var source = html.substring(at + marker.length, end < 0 ? html.length : end).trim();
    if (source.endsWith(';')) source = source.substring(0, source.length - 1);
    final json = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (quoted) {
        json.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
        json.write(c);
      } else if (source.startsWith('undefined', i)) {
        json.write('null');
        i += 'undefined'.length - 1;
      } else {
        json.write(c);
      }
    }
    try {
      final decoded = jsonDecode(json.toString());
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw const ApiChanged(_site, 'share page: state is not JSON');
  }

  static Object? _jsonText(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }

  /// §4 the room of a share page. `pageStatus == "error"` ("未找到直播间")
  /// is a room that does not exist; `nextRoomInfo` (another live room the
  /// page recommends) is never used.
  static XiaohongshuRoom room(String html, {required String expectedId}) {
    final live = state(html)['liveStream'];
    if (live is! Map) throw const ApiChanged(_site, 'share page: no liveStream');
    final page = live['pageStatus'];
    if (page == 'error') throw NotFound(_site, 'room $expectedId: ${jsonString(live['errorMessage']) ?? ''}');
    if (page != 'success') throw ApiChanged(_site, 'share page: pageStatus $page');
    final data = live['roomData'];
    final info = data is Map ? data['roomInfo'] : null;
    final host = data is Map && data['hostInfo'] is Map ? data['hostInfo'] as Map : const <Object?, Object?>{};
    if (info is! Map) throw const ApiChanged(_site, 'share page: no roomInfo');
    final id = jsonString(info['roomId']);
    if (id != null && id != expectedId) throw ApiChanged(_site, 'share page: asked $expectedId, got $id');
    final status = jsonInt(info['status']);
    final liveState = switch ((status, live['liveStatus'])) {
      (2, 'success') => LiveState.live,
      (3, 'end') => LiveState.offline,
      _ => throw ApiChanged(_site, 'share page: status $status liveStatus ${live['liveStatus']}'),
    };
    final monetize = jsonInt(info['monetizeType']) ?? 0;
    final limits = _jsonText(info['joinLimitTypes']);
    final limited = limits is List && limits.any((value) => jsonInt(value) != 0);
    final config = _jsonText(info['pullConfig']);
    final name = decodeHtmlEntities(jsonString(host['nickName']) ?? '');
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, expectedId),
          title: decodeHtmlEntities(jsonString(info['roomTitle']) ?? name),
          anchorName: name,
          state: liveState,
          cover: jsonUrl(info['roomCover']),
        ),
        link: link(expectedId),
        avatar: jsonUrl(host['avatar']),
      ),
      restricted: monetize != 0 || limited,
      pullConfig: liveState == LiveState.live && config is Map<String, dynamic> ? config : null,
    );
  }

  /// §5 qualities in `pullConfig` order (H.264 first), deduplicated by
  /// `quality_type`.
  static List<Quality> qualities(Map<String, dynamic> config) {
    final seen = <String>{};
    final raw = <({String id, String label})>[];
    for (final codec in const ['h264', 'h265']) {
      for (final item in (config[codec] as List?) ?? const []) {
        if (item is! Map) continue;
        final id = jsonString(item['quality_type']);
        if (id == null || !seen.add(id)) continue;
        raw.add((id: id, label: jsonString(item['quality_type_name']) ?? id));
      }
    }
    return [for (final (index, q) in raw.indexed) Quality(id: q.id, label: q.label, rank: raw.length - index)];
  }

  /// §5/§6 lines of [quality]: FLV before HLS, H.264 before H.265, otherwise in
  /// `pullConfig` order.
  static List<StreamLine> lines(XiaohongshuRoom room, Quality quality, {required Map<String, String> headers}) {
    if (room.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (room.restricted) throw const NeedsLogin(_site, 'paid or limited room');
    final config = room.pullConfig;
    if (config == null) throw const StreamUnavailable(_site, 'no pullConfig');
    final seen = <Uri>{};
    final lines = <StreamLine>[];
    for (final (codec, name) in const [('h264', 'avc'), ('h265', 'hevc')]) {
      for (final item in (config[codec] as List?) ?? const []) {
        if (item is! Map || jsonString(item['quality_type']) != quality.id) continue;
        final url = jsonUrl(item['master_url']);
        if (url == null || !seen.add(url)) continue;
        final format = url.path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;
        lines.add(
          StreamLine(
            url: url,
            format: format,
            lineId: '${format.name}:${url.host.split('.').first}',
            requested: quality,
            headers: headers,
            codec: name,
          ),
        );
      }
    }
    if (lines.isEmpty) throw StreamUnavailable(_site, 'no ${quality.id} URL');
    // FLV first (steadier for live playback), keeping the platform order otherwise.
    return [
      ...lines.where((line) => line.format == StreamFormat.flv),
      ...lines.where((line) => line.format != StreamFormat.flv),
    ];
  }
}
