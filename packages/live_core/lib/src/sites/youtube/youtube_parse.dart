import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'youtube';

Map<Object?, Object?> _obj(Object? value) => value is Map ? value : const <Object?, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

/// A player response reduced to what the adapter needs (spec/sites/youtube.md §4).
typedef YouTubePlayer = ({RoomDetail detail, String videoId, String? channelId, Uri? hls});

/// Pure parsing of YouTube InnerTube responses (spec/sites/youtube.md).
abstract final class YouTubeParse {
  /// §1 a video id.
  static final RegExp videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// §1 a channel id.
  static final RegExp channelId = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

  /// §2 the "Live" destination channel.
  static const liveDestination = 'UC4R8DWoMoI7CAwX8_LjQHig';

  /// §3 the search filter "Live".
  static const liveFilter = 'EgJAAQ%3D%3D';

  /// §5 the only quality: the HLS variant playlist.
  static const auto = Quality(id: 'hls', label: '自动', rank: 1);

  /// The room page: a watch page or a channel's live page.
  static Uri link(String id) => channelId.hasMatch(id)
      ? Uri.parse('https://www.youtube.com/channel/$id/live')
      : Uri.parse('https://www.youtube.com/watch?v=$id');

  static Map<String, dynamic> _json(String body, String what) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw ApiChanged(_site, '$what: not a JSON object');
  }

  /// Every value under [key] anywhere in [node], in document order.
  static List<Object?> find(Object? node, String key, [List<Object?>? into]) {
    final out = into ?? <Object?>[];
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key == key) out.add(entry.value);
        find(entry.value, key, out);
      }
    } else if (node is List) {
      for (final item in node) {
        find(item, key, out);
      }
    }
    return out;
  }

  /// The plain text of a `{runs: [...]}` or `{simpleText}` object.
  static String text(Object? value) {
    final map = _obj(value);
    final simple = map['simpleText'];
    if (simple is String) return simple;
    return [for (final run in _list(map['runs'])) '${_obj(run)['text'] ?? ''}'].join();
  }

  /// `11,001 watching` → 11001.
  static int? watching(Object? value) {
    final match = RegExp(r'^([\d,.\s]+)\s+watching', caseSensitive: false).firstMatch(text(value).trim());
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    return digits == null || digits.isEmpty ? null : int.tryParse(digits);
  }

  static bool _isLive(Map<Object?, Object?> renderer) {
    for (final badge in _list(renderer['badges'])) {
      if (_obj(_obj(badge)['metadataBadgeRenderer'])['style'] == 'BADGE_STYLE_TYPE_LIVE_NOW') return true;
    }
    for (final overlay in _list(renderer['thumbnailOverlays'])) {
      if (_obj(_obj(overlay)['thumbnailOverlayTimeStatusRenderer'])['style'] == 'LIVE') return true;
    }
    return watching(renderer['viewCountText']) != null;
  }

  static Uri? _thumbnail(Object? value) {
    final thumbnails = _list(_obj(value)['thumbnails']);
    if (thumbnails.isEmpty) return null;
    var url = jsonString(_obj(thumbnails.last)['url']);
    if (url == null) return null;
    if (url.startsWith('//')) url = 'https:$url';
    return jsonUrl(url);
  }

  /// §2/§3 the live `videoRenderer`s of a browse or search response.
  static List<RoomCard> liveCards(Object? root) {
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final raw in find(root, 'videoRenderer')) {
      final renderer = _obj(raw);
      final id = jsonString(renderer['videoId']);
      if (id == null || !videoId.hasMatch(id) || !_isLive(renderer) || !seen.add(id)) continue;
      final owner = renderer['ownerText'] ?? renderer['longBylineText'];
      final avatar = _obj(_obj(renderer['channelThumbnailSupportedRenderers'])['channelThumbnailWithLinkRenderer']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(text(renderer['title'])),
          anchorName: decodeHtmlEntities(text(owner)),
          state: LiveState.live,
          cover: _thumbnail(renderer['thumbnail']),
          audience: Audience(online: watching(renderer['viewCountText'])),
          avatar: _thumbnail(avatar['thumbnail']),
        ),
      );
    }
    return cards;
  }

  /// §2 the "Live" destination: one page of live broadcasts.
  static Page<RoomCard> destination(String body) => Page(liveCards(_json(body, 'browse')));

  /// §3 a search page (first or continuation); the last continuation item
  /// gives the next page.
  static Page<RoomCard> search(String body) {
    final root = _json(body, 'search');
    final cards = liveCards(root);
    final items = find(root, 'continuationItemRenderer');
    final token = items.isEmpty
        ? null
        : jsonString(_obj(_obj(_obj(items.last)['continuationEndpoint'])['continuationCommand'])['token']);
    return Page(cards, next: token == null || cards.isEmpty ? null : PageCursor(token));
  }

  /// §1/§4 `navigation/resolve_url`: a watch endpoint names a video, a browse
  /// endpoint a channel; null when the URL is neither.
  static ({String? video, String? channel}) resolved(String body) {
    final endpoint = _obj(_json(body, 'resolve_url')['endpoint']);
    final video = jsonString(_obj(endpoint['watchEndpoint'])['videoId']);
    final channel = jsonString(_obj(endpoint['browseEndpoint'])['browseId']);
    return (
      video: video != null && videoId.hasMatch(video) ? video : null,
      channel: channel != null && channelId.hasMatch(channel) ? channel : null,
    );
  }

  /// §4 the ANDROID `player` response; [roomId] is the room asked for (the
  /// video, or the channel whose live page named it).
  static YouTubePlayer player(String body, {required String roomId}) {
    final root = _json(body, 'player');
    final status = _obj(root['playabilityStatus']);
    final code = jsonString(status['status']);
    final reason = jsonString(status['reason']) ?? '';
    final details = _obj(root['videoDetails']);
    final id = jsonString(details['videoId']);
    switch (code) {
      case 'OK' || 'LIVE_STREAM_OFFLINE':
        break;
      case 'LOGIN_REQUIRED' || 'AGE_CHECK_REQUIRED' || 'CONTENT_CHECK_REQUIRED':
        throw NeedsLogin(_site, 'player: $code $reason');
      case 'ERROR' when id == null:
        throw NotFound(_site, 'player: $reason');
      case 'UNPLAYABLE' || 'ERROR':
        throw StreamUnavailable(_site, 'player: $code $reason');
      default:
        throw ApiChanged(_site, 'player: playability $code');
    }
    if (id == null || !videoId.hasMatch(id)) throw ApiChanged(_site, 'player: videoId $id');
    if (videoId.hasMatch(roomId) && id != roomId) throw ApiChanged(_site, 'player: asked $roomId, got $id');
    final live = details['isLive'] == true && code == 'OK';
    final views = jsonInt(details['viewCount']);
    final channel = jsonString(details['channelId']);
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, roomId),
          title: decodeHtmlEntities(jsonString(details['title']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(details['author']) ?? ''),
          state: live ? LiveState.live : LiveState.offline,
          cover: _thumbnail(details['thumbnail']),
          audience: Audience(cumulative: views != null && views >= 0 ? views : null),
        ),
        link: link(roomId),
        introduction: jsonString(details['shortDescription']),
        danmakuKeys: {'videoId': id, 'channelId': ?channel},
      ),
      videoId: id,
      channelId: channel,
      hls: live ? jsonUrl(_obj(root['streamingData'])['hlsManifestUrl']) : null,
    );
  }

  /// §5 the HLS line; the `/expire/<秒>/` path segment is the lease.
  static StreamLine line(Uri hls, {required Map<String, String> headers}) {
    final segments = hls.pathSegments;
    final at = segments.indexOf('expire');
    final seconds = at >= 0 && at + 1 < segments.length ? int.tryParse(segments[at + 1]) : null;
    final expires = seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    return StreamLine(
      url: hls,
      format: StreamFormat.hls,
      lineId: 'googlevideo',
      requested: auto,
      headers: headers,
      codec: 'avc',
      lease: expires == null
          ? null
          : Lease(refreshAt: expires.subtract(const Duration(minutes: 30)), expiresAt: expires, cutsConnection: false),
    );
  }

  /// §4 the channel name of an RSS feed (`feeds/videos.xml`).
  static String? feedTitle(String xml) {
    final match = RegExp('<title>([^<]*)</title>').firstMatch(xml);
    return match == null ? null : decodeHtmlEntities(match.group(1)!.trim());
  }
}
