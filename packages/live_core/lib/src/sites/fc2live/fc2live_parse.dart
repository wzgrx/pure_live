import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'fc2live';

Map<Object?, Object?> _obj(Object? value) => value is Map ? value : const <Object?, Object?>{};

/// A member answer reduced to what the adapter needs (spec/sites/fc2live.md §4).
typedef Fc2Member = ({RoomDetail detail, String version, bool restricted});

/// The anonymous control grant (spec/sites/fc2live.md §6.1).
typedef Fc2Grant = ({Uri socket, String controlToken, String orz});

/// Pure parsing of FC2 Live responses and control messages (spec/sites/fc2live.md).
abstract final class Fc2LiveParse {
  /// §1 a channel id.
  static final RegExp channelId = RegExp(r'^[1-9]\d{0,11}$');

  /// §1 language prefixes of channel links.
  static const locales = {'en', 'es', 'de', 'fr', 'id', 'ja', 'ko', 'pt', 'ru', 'th', 'tw', 'vi', 'zh'};

  static const _categoryId = 'fc2live';

  /// §2 the site's category filters (`category_set`): area id = the
  /// comma-separated `category` values it keeps.
  static const List<Area> areas = [
    Area(id: '1', name: '雑談', categoryId: _categoryId),
    Area(id: '2,3', name: 'ゲーム/作業', categoryId: _categoryId),
    Area(id: '4', name: '動画', categoryId: _categoryId),
    Area(id: '9', name: '音声', categoryId: _categoryId),
    Area(id: '5', name: 'その他', categoryId: _categoryId),
  ];

  /// §2 the one category holding [areas].
  static const Category category = Category(id: _categoryId, name: 'FC2ライブ', areas: areas);

  /// §5 qualities, best first; ids are the low-latency playlist modes.
  static const qualities = [
    Quality(id: '30', label: '高画質', rank: 3),
    Quality(id: '20', label: '標準', rank: 2),
    Quality(id: '10', label: '低画質', rank: 1),
  ];

  /// The channel page.
  static Uri link(String id) => Uri.parse('https://live.fc2.com/$id/');

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

  static int? _count(Object? value) {
    final count = jsonInt(value);
    return count != null && count >= 0 ? count : null;
  }

  /// §2 `allchannellist.php`: every live channel. Only public rooms
  /// (`type == 1`) that need no payment, login or ticket are kept.
  static List<({RoomCard card, int category})> directory(String body) {
    final root = _json(body, 'allchannellist');
    final rows = root['channel'];
    if (rows is! List || jsonInt(root['time']) == null) {
      throw const ApiChanged(_site, 'allchannellist: no channel list');
    }
    final seen = <String>{};
    final out = <({RoomCard card, int category})>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = jsonString(row['id']);
      if (id == null || !channelId.hasMatch(id) || jsonInt(row['type']) != 1) continue;
      if (jsonInt(row['pay']) != 0 || jsonInt(row['login']) != 0 || jsonInt(row['tid']) != 0) continue;
      if (!seen.add(id)) continue;
      final name = decodeHtmlEntities(jsonString(row['name']) ?? id);
      final category = jsonInt(row['category']) ?? 0;
      out.add((
        card: RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(row['title']) ?? name),
          anchorName: name,
          state: LiveState.live,
          cover: jsonUrl(row['image']),
          area: areaName(category),
          audience: Audience(online: _count(row['count']), cumulative: _count(row['total'])),
        ),
        category: category,
      ));
    }
    return out;
  }

  /// The site's name of a `category` value, or null.
  static String? areaName(int category) {
    for (final area in areas) {
      if (area.id.split(',').contains('$category')) return area.name;
    }
    return null;
  }

  /// §2 one page of the directory, busiest first, optionally limited to an [area].
  static Page<RoomCard> page(String body, {Area? area}) {
    final keep = area?.id.split(',').map(int.tryParse).toSet();
    final rooms = [
      for (final row in directory(body))
        if (keep == null || keep.contains(row.category)) row.card,
    ]..sort((a, b) => (b.audience.online ?? 0).compareTo(a.audience.online ?? 0));
    return Page(rooms);
  }

  /// §4 `memberApi.php`.
  static Fc2Member member(String body, {required String roomId}) {
    final root = _json(body, 'memberApi');
    if (jsonInt(root['status']) != 1) throw ApiChanged(_site, 'memberApi: status ${root['status']}');
    final data = _obj(root['data']);
    final channel = _obj(data['channel_data']);
    final profile = _obj(data['profile_data']);
    if (jsonString(channel['channelid']) != roomId) throw const ApiChanged(_site, 'memberApi: another channel');
    // A channel that never existed has an empty profile (S02-member-missing).
    if (jsonString(profile['userid']) == null) throw NotFound(_site, 'no FC2 channel $roomId');
    final name = decodeHtmlEntities(jsonString(profile['name']) ?? jsonString(channel['tname']) ?? roomId);
    final published = jsonInt(channel['is_publish']);
    final state = switch (published) {
      1 => LiveState.live,
      0 => LiveState.offline,
      _ => throw ApiChanged(_site, 'memberApi: is_publish $published'),
    };
    final restricted = [
      'fee',
      'login_only',
      'ticketid',
      'ticket_only',
      'is_limited',
    ].any((key) => (jsonInt(channel[key]) ?? 0) != 0);
    final category = jsonInt(channel['category']) ?? 0;
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, roomId),
          title: decodeHtmlEntities(jsonString(channel['title']) ?? name),
          anchorName: name,
          state: state,
          cover: jsonUrl(channel['image']),
          area: areaName(category),
          audience: state == LiveState.live
              ? Audience(online: _count(channel['count']), cumulative: _count(channel['total']))
              : Audience.none,
        ),
        link: link(roomId),
        avatar: jsonUrl(profile['image']) ?? jsonUrl(profile['icon']),
        introduction: jsonString(channel['info']),
        danmakuKeys: {'channelId': roomId},
      ),
      version: jsonString(channel['version']) ?? '',
      restricted: restricted,
    );
  }

  /// §6.1 `getControlServer.php`.
  static Fc2Grant grant(String body, {required String roomId}) {
    final root = _json(body, 'getControlServer');
    final status = jsonInt(root['status']);
    if (status != 0) throw StreamUnavailable(_site, 'getControlServer: status $status');
    final socket = Uri.tryParse(jsonString(root['url']) ?? '');
    final token = jsonString(root['control_token']);
    final orz = jsonString(root['orz_raw']);
    if (socket == null ||
        socket.scheme != 'wss' ||
        !(socket.host == 'live.fc2.com' || socket.host.endsWith('.live.fc2.com')) ||
        socket.path != '/control/channels/$roomId' ||
        token == null ||
        orz == null ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(orz)) {
      throw const ApiChanged(_site, 'getControlServer: bad grant');
    }
    return (socket: socket, controlToken: token, orz: orz);
  }

  /// §6.2 the control socket URL of a [grant].
  static Uri controlUrl(Fc2Grant grant) => grant.socket.replace(queryParameters: {'control_token': grant.controlToken});

  /// §6.2 the `get_hls_information` answer: playlist URL by mode; the
  /// high-latency family (`playlists_high_latency`, modes 1/11/21/31/91)
  /// is preferred where present.
  static Map<int, Uri> playlists(Map<String, dynamic> arguments) {
    final status = jsonInt(arguments['status']);
    if (status != 0) throw StreamUnavailable(_site, 'get_hls_information: status $status');
    final out = <int, Uri>{};
    for (final key in ['playlists', 'playlists_middle_latency', 'playlists_high_latency']) {
      final list = arguments[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map || jsonInt(item['status']) != 0) continue;
        final mode = jsonInt(item['mode']);
        final url = jsonUrl(item['url']);
        if (mode != null && url != null && url.scheme == 'https') out[mode] = url;
      }
    }
    if (out.isEmpty) throw const ApiChanged(_site, 'get_hls_information: no playlists');
    return out;
  }

  /// §5 the line of [quality]: the high-latency playlist (mode + 1) when
  /// offered, else the low-latency one; null when neither is.
  static StreamLine? line(
    Map<int, Uri> playlists,
    Quality quality, {
    required Map<String, String> headers,
    Lease? lease,
  }) {
    final mode = int.parse(quality.id);
    final url = playlists[mode + 1] ?? playlists[mode];
    if (url == null) return null;
    return StreamLine(
      url: url,
      format: StreamFormat.hls,
      lineId: url.host,
      requested: quality,
      confirmed: quality,
      headers: headers,
      codec: 'avc',
      lease: lease,
    );
  }
}
