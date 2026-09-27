import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'steambroadcast';

/// Pure parsing of Steam broadcast responses (spec/sites/steambroadcast.md).
abstract final class SteamBroadcastParse {
  /// §1 a 64-bit Steam id of an individual account.
  static final RegExp steamId = RegExp(r'^7656119\d{10}$');

  /// §5 the only quality: the HLS master playlist.
  static const auto = Quality(id: 'auto', label: '自动', rank: 1);

  /// The watch page of [id].
  static Uri link(String id) => Uri.parse('https://steamcommunity.com/broadcast/watch/$id');

  /// §4 the account id Steam's mini profile uses (steam id minus the base).
  static String accountId(String steamId) => '${BigInt.parse(steamId) - BigInt.parse('76561197960265728')}';

  static Map<String, dynamic> _json(String body, String what) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw ApiChanged(_site, '$what: not a JSON object');
  }

  static String _text(String html) =>
      decodeHtmlEntities(html.replaceAll(RegExp('<[^>]*>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _first(RegExp pattern, String block) {
    final value = pattern.firstMatch(block)?.group(1);
    return value == null ? null : _text(value);
  }

  static final _watch = RegExp(r'href="https://steamcommunity\.com/broadcast/watch/(\d{17})"');
  static final _type = RegExp('class="apphub_CardContentType">([^<]*)<');
  static final _preview = RegExp('class="apphub_CardContentPreviewImage" src="([^"]+)"');
  static final _viewers = RegExp('class="apphub_CardContentViewers[^"]*">([^<]*)<');
  static final _game = RegExp('class="apphub_CardContentTitle[^"]*">([^<]*)<');
  static final _avatar = RegExp('class="appHubIconHolder[^"]*"><img src="([^"]+)"');
  static final _author = RegExp('class="apphub_CardContentAuthorName[^"]*">(?:<a[^>]*>)?([^<]*)<');

  /// `4,927 viewers` → 4927; null for anything else.
  static int? viewerCount(String? text) {
    final match = RegExp(r'^\s*([\d,.\s]+?)\s+viewers?\b', caseSensitive: false).firstMatch(text ?? '');
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    return digits == null || digits.isEmpty ? null : int.tryParse(digits);
  }

  /// §2.2 the trending broadcasts page (HTML): one card per broadcaster;
  /// the hidden form's `p` and `broadcastsoffset` say whether a next page
  /// exists.
  static Page<RoomCard> directory(String html, {required int page}) {
    final blocks = html.split('class="Broadcast_Card').skip(1);
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final block in blocks) {
      final id = _watch.firstMatch(block)?.group(1);
      if (id == null || !steamId.hasMatch(id) || !seen.add(id)) continue;
      final game = _first(_game, block) ?? '';
      final type = (_first(_type, block) ?? '').replaceFirst(RegExp(r':\s*Broadcast\s*$', caseSensitive: false), '');
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: type.isEmpty ? game : type,
          anchorName: _first(_author, block) ?? id,
          state: LiveState.live,
          cover: jsonUrl(decodeHtmlEntities(_preview.firstMatch(block)?.group(1) ?? '')),
          area: game.isEmpty ? null : game,
          audience: Audience(online: viewerCount(_first(_viewers, block))),
          avatar: jsonUrl(_avatar.firstMatch(block)?.group(1)),
        ),
      );
    }
    final next = int.tryParse(RegExp(r'name="p" value="(\d+)"').firstMatch(html)?.group(1) ?? '');
    final offset = int.tryParse(RegExp(r'name="broadcastsoffset" value="(\d+)"').firstMatch(html)?.group(1) ?? '');
    final more = cards.isNotEmpty && next == page + 1 && offset == page * 10;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4.2 mini profile → (persona name, avatar).
  static ({String name, Uri? avatar}) profile(String body) {
    final json = _json(body, 'miniprofile');
    final name = jsonString(json['persona_name']);
    if (name == null) throw const ApiChanged(_site, 'miniprofile: no persona_name');
    return (name: decodeHtmlEntities(name), avatar: jsonUrl(json['avatar_url']));
  }

  /// §4.1 `getbroadcastinfo` + the mini profile → the detail.
  static RoomDetail detail(String infoBody, {required String steamId, required String name, Uri? avatar}) {
    final info = _json(infoBody, 'getbroadcastinfo');
    final success = jsonInt(info['success']);
    final LiveState state;
    if (success == 42) {
      state = LiveState.offline;
    } else if (success == 1) {
      final online = info['is_online'] == true;
      state = !online
          ? LiveState.offline
          : jsonInt(info['is_replay']) == 1
          ? LiveState.replay
          : LiveState.live;
    } else {
      throw ApiChanged(_site, 'getbroadcastinfo: success $success');
    }
    final game = jsonString(info['app_title']);
    final title = jsonString(info['title']);
    final viewers = state == LiveState.offline ? null : jsonInt(info['viewer_count']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, steamId),
        title: decodeHtmlEntities(title ?? game ?? ''),
        anchorName: name,
        state: state,
        cover: state == LiveState.offline ? null : jsonUrl(info['thumbnail_url']),
        area: game == null ? null : decodeHtmlEntities(game),
        audience: Audience(online: viewers != null && viewers >= 0 ? viewers : null),
      ),
      link: link(steamId),
      avatar: avatar,
      danmakuKeys: {'steamid': steamId},
    );
  }

  /// §6 `getbroadcastmpd` → the master playlist, with the CDN parameters
  /// appended when Steam sends any.
  static Uri master(String body) {
    final json = _json(body, 'getbroadcastmpd');
    final success = jsonString(json['success']);
    switch (success) {
      case 'ready':
        break;
      case 'unavailable' || 'offline' || 'not_live' || 'no_broadcast' || 'waiting' || 'waiting_to_start':
        throw StreamUnavailable(_site, 'getbroadcastmpd: $success');
      case 'user_restricted':
        throw const NeedsLogin(_site, 'getbroadcastmpd: user_restricted');
      default:
        throw ApiChanged(_site, 'getbroadcastmpd: success $success');
    }
    final url = jsonUrl(json['hls_url']);
    if (url == null || !url.path.endsWith('.m3u8')) throw const ApiChanged(_site, 'getbroadcastmpd: no hls_url');
    var auth = jsonString(json['cdn_auth_url_parameters']) ?? '';
    while (auth.startsWith('&') || auth.startsWith('?')) {
      auth = auth.substring(1);
    }
    if (auth.isEmpty) return url;
    return Uri.parse('$url${url.hasQuery ? '&' : '?'}$auth');
  }

  /// §5 the one HLS line.
  static StreamLine line(Uri master, {required Map<String, String> headers}) => StreamLine(
    url: master,
    format: StreamFormat.hls,
    lineId: 'steamcontent',
    requested: auto,
    headers: headers,
    codec: 'avc',
  );
}
