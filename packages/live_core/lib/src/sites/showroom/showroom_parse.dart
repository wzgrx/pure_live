import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'showroom';

/// One live of the `onlives` snapshot.
typedef ShowroomLive = ({String genreId, String genreName, RoomCard card, String urlKey, String telop});

/// Pure parsing of SHOWROOM responses (spec/sites/showroom.md).
abstract final class ShowroomParse {
  /// §1 a room id.
  static final RegExp roomIdPattern = RegExp(r'^[1-9][0-9]{0,18}$');

  /// §1 a public room key (`room_url_key`).
  static final RegExp urlKeyPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// §1 site paths that are not rooms.
  static const reserved = {
    'api', 'room', 'event', 'ranking', 'search', 'login', 'register', 'mypage', 'premium_live', 'r', //
    'onlive', 'campaign', 'about', 'lottery',
  };

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  /// §9 status mapping; SHOWROOM answers 404 with `errors[].code 1002` for
  /// unknown rooms and keys.
  static Map<String, dynamic> root(String body, {required String what, int status = 200}) {
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
    return _map(_json(body, what), what);
  }

  static Uri? _image(Object? value) {
    final url = jsonUrl(value);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    return host.endsWith('showroom-live.com') || host.endsWith('showroom-txlive.com') ? url : null;
  }

  /// §2 the `onlives` snapshot: every genre with its lives in order.
  /// Message cells (no `room_id`, `cell_type` 7) are skipped.
  static List<({String id, String name, List<ShowroomLive> lives})> onlives(String body, {int status = 200}) {
    final data = root(body, what: 'onlives', status: status);
    final groups = data['onlives'];
    if (groups is! List) throw const ApiChanged(_site, 'onlives: no list');
    final result = <({String id, String name, List<ShowroomLive> lives})>[];
    final seen = <String>{};
    for (final group in groups) {
      if (group is! Map) continue;
      final id = '${jsonInt(group['genre_id']) ?? ''}';
      final name = jsonString(group['genre_name']);
      if (id.isEmpty || name == null || !seen.add(id)) continue;
      final lives = <ShowroomLive>[];
      for (final raw in group['lives'] is List ? group['lives'] as List : const <Object?>[]) {
        if (raw is! Map || raw['room_id'] == null) continue;
        final roomId = '${jsonInt(raw['room_id']) ?? ''}';
        if (!roomIdPattern.hasMatch(roomId)) continue;
        final mainName = jsonString(raw['main_name']) ?? '';
        final telop = jsonString(raw['telop']) ?? '';
        final started = jsonInt(raw['started_at']);
        final views = jsonInt(raw['view_num']);
        lives.add((
          genreId: id,
          genreName: name,
          urlKey: jsonString(raw['room_url_key']) ?? '',
          telop: telop,
          card: RoomCard(
            ref: RoomRef(_site, roomId),
            title: telop.isEmpty ? mainName : telop,
            anchorName: mainName,
            state: LiveState.live,
            cover: _image(raw['image']) ?? _image(raw['image_square']),
            area: jsonString(raw['genre_name']),
            audience: Audience(cumulative: views != null && views >= 0 ? views : null),
            liveSince: started != null && started > 0
                ? DateTime.fromMillisecondsSinceEpoch(started * 1000, isUtc: true)
                : null,
            avatar: _image(raw['image_square']),
          ),
        ));
      }
      result.add((id: id, name: name, lives: lives));
    }
    if (result.isEmpty) throw const ApiChanged(_site, 'onlives: no genres');
    return result;
  }

  /// §2.1 genres as the areas of one category.
  static List<Category> categories(String body, {int status = 200}) => [
    Category(
      id: 'genre',
      name: 'SHOWROOM',
      areas: [
        for (final genre in onlives(body, status: status)) Area(id: genre.id, name: genre.name, categoryId: 'genre'),
      ],
    ),
  ];

  /// §2.2 the lives of genre [genreId] (one page); `0` is Popularity.
  static Page<RoomCard> genrePage(String body, {required String genreId, int status = 200}) {
    final genres = onlives(body, status: status);
    final genre = genres.where((g) => g.id == genreId).firstOrNull;
    if (genre == null) throw NotFound(_site, 'genre $genreId');
    return Page([for (final live in genre.lives) live.card]);
  }

  /// §3 the snapshot filtered by room id, key, name, telop or genre.
  static Page<RoomCard> searchPage(String body, {required String keyword, int status = 200}) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const Page.empty();
    final seen = <String>{};
    return Page([
      for (final genre in onlives(body, status: status))
        for (final live in genre.lives)
          if ((live.card.ref.roomId == query ||
                  live.urlKey.toLowerCase() == query ||
                  live.card.anchorName.toLowerCase().contains(query) ||
                  live.telop.toLowerCase().contains(query) ||
                  live.genreName.toLowerCase().contains(query)) &&
              seen.add(live.card.ref.roomId))
            live.card,
    ]);
  }

  /// §1 `room/status?room_url_key=`: the room id of a key.
  static String roomIdOfStatus(String body, {int status = 200}) {
    final data = root(body, what: 'room/status', status: status);
    final id = '${jsonInt(data['room_id']) ?? ''}';
    if (!roomIdPattern.hasMatch(id)) throw const ApiChanged(_site, 'room/status: no room_id');
    return id;
  }

  /// §4 `live/live_info.live_status`: 2 live, 0 and 1 offline, others an
  /// unknown shape.
  static LiveState liveState(Map<String, dynamic> info) => switch (jsonInt(info['live_status'])) {
    2 => LiveState.live,
    0 || 1 => LiveState.offline,
    final other => throw ApiChanged(_site, 'live_status $other'),
  };

  /// §4 the room from `room/profile` and `live/live_info`.
  static RoomDetail detail(String profileBody, String infoBody, {int profileStatus = 200, int infoStatus = 200}) {
    final profile = root(profileBody, what: 'room/profile', status: profileStatus);
    final info = root(infoBody, what: 'live_info', status: infoStatus);
    final id = '${jsonInt(profile['room_id']) ?? ''}';
    if (!roomIdPattern.hasMatch(id)) throw const ApiChanged(_site, 'room/profile: no room_id');
    if ('${jsonInt(info['room_id'])}' != id) throw ApiChanged(_site, 'live_info of ${info['room_id']} for $id');
    final state = liveState(info);
    final name = jsonString(profile['main_name']) ?? jsonString(profile['room_name']) ?? '';
    final started = jsonInt(profile['current_live_started_at']);
    final views = jsonInt(profile['view_num']);
    final key = jsonString(profile['room_url_key']);
    final bcsvrKey = jsonString(info['bcsvr_key']);
    final bcsvrHost = jsonString(info['bcsvr_host']);
    final cover = _image(profile['image_square']) ?? _image(profile['image']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, id),
        title: jsonString(info['room_name']) ?? name,
        anchorName: name,
        state: state,
        cover: cover,
        area: jsonString(profile['genre_name']),
        audience: Audience(cumulative: state == LiveState.live && views != null && views >= 0 ? views : null),
        liveSince: state == LiveState.live && started != null && started > 0
            ? DateTime.fromMillisecondsSinceEpoch(started * 1000, isUtc: true)
            : null,
        avatar: cover,
      ),
      link: key != null && urlKeyPattern.hasMatch(key)
          ? Uri.parse('https://www.showroom-live.com/r/$key')
          : Uri.parse('https://www.showroom-live.com/room/profile?room_id=$id'),
      avatar: cover,
      introduction: jsonString(profile['description']),
      danmakuKeys: {
        if (state == LiveState.live && bcsvrKey != null) 'bcsvrKey': bcsvrKey,
        if (state == LiveState.live && bcsvrHost != null) 'bcsvrHost': bcsvrHost,
      },
    );
  }

  static const _qualityLabels = {1000: '原画', 200: '中', 100: '低'};

  /// §5 `live/streaming_url`: one quality per `hls` entry (by `quality`,
  /// best first) plus the adaptive `hls_all` master as “自动”; WebRTC
  /// entries are skipped.
  static StreamSet streams(String body, {required Map<String, String> headers, String? wanted, int status = 200}) {
    final data = root(body, what: 'streaming_url', status: status);
    final list = data['streaming_url_list'];
    final offered = <({Quality quality, Uri url})>[];
    final seen = <Uri>{};
    for (final raw in list is List ? list : const <Object?>[]) {
      if (raw is! Map) continue;
      final type = raw['type'];
      if (type != 'hls' && type != 'hls_all') continue;
      final url = jsonUrl(raw['url']);
      if (url == null || url.scheme != 'https' || !seen.add(url)) continue;
      final host = url.host.toLowerCase();
      if (!host.endsWith('showroom-live.com') && !host.endsWith('showroom-txlive.com')) continue;
      final level = jsonInt(raw['quality']) ?? 0;
      final quality = type == 'hls_all'
          ? const Quality(id: 'auto', label: '自动', rank: 0)
          : Quality(id: '$level', label: _qualityLabels[level] ?? jsonString(raw['label']) ?? '$level', rank: level);
      if (offered.any((o) => o.quality == quality)) continue;
      offered.add((quality: quality, url: url));
    }
    if (offered.isEmpty) throw const StreamUnavailable(_site, 'no HLS stream');
    offered.sort((a, b) => b.quality.rank.compareTo(a.quality.rank));
    final chosen = offered.where((o) => o.quality.id == wanted).firstOrNull ?? offered.first;
    return StreamSet(
      qualities: [for (final o in offered) o.quality],
      selected: chosen.quality,
      lines: [
        StreamLine(
          url: chosen.url,
          format: StreamFormat.hls,
          lineId: chosen.url.host,
          requested: chosen.quality,
          confirmed: chosen.quality.id == 'auto' ? null : chosen.quality,
          headers: headers,
        ),
      ],
    );
  }

  /// §1 what an input names: a room id, or a room key to look up; null for
  /// other input.
  static ({String? roomId, String? urlKey})? referenceOf(String input) {
    final text = input.trim();
    if (roomIdPattern.hasMatch(text)) return (roomId: text, urlKey: null);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !(url.host == 'showroom-live.com' || url.host.endsWith('.showroom-live.com'))) return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length == 2 && segments[0] == 'room' && segments[1] == 'profile') {
      final id = url.queryParameters['room_id'] ?? '';
      return roomIdPattern.hasMatch(id) ? (roomId: id, urlKey: null) : null;
    }
    final key = switch (segments) {
      ['r', final key] => key,
      [final key] => key,
      _ => null,
    };
    if (key == null || reserved.contains(key.toLowerCase()) || !urlKeyPattern.hasMatch(key)) return null;
    return (roomId: null, urlKey: key);
  }
}
