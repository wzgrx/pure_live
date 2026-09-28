import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'showroom';

/// What room entry learned about a live room (3.x kept the qualities made of
/// it in `data`): the `streaming_url_list` rows as answered, checked only
/// when played, and the comment server of the broadcast.
@immutable
final class ShowroomRoomData {
  /// Creates the data.
  const new({required this.roomId, this.streams, this.bcsvrHost, this.bcsvrKey});

  /// The numeric room id the data belongs to.
  final String roomId;

  /// `streaming_url_list` of `live/streaming_url` at room entry, not yet
  /// checked; null when it was not asked for or the request failed (the
  /// qualities then ask again).
  final List<Object?>? streams;

  /// `live_info.bcsvr_host`: the comment WebSocket host of the broadcast
  /// (3.x had no SHOWROOM comments; kept for M5).
  final String? bcsvrHost;

  /// `live_info.bcsvr_key`: the broadcast's comment key.
  final String? bcsvrKey;
}

/// One live room of the `onlives` snapshot (3.x's `ShowroomLive`, without
/// the streams 3.x parsed there but never used).
@immutable
final class ShowroomLive {
  /// Creates the live.
  const new({
    required this.roomId,
    required this.roomUrlKey,
    required this.name,
    required this.cover,
    required this.genreName,
    this.followers,
    this.views,
    this.telop = '',
  });

  /// `room_id`.
  final int roomId;

  /// `room_url_key`: the public room key of `/r/{key}` links.
  final String roomUrlKey;

  /// `main_name`: the room's name.
  final String name;

  /// `image_square` (else `image`) when it is a SHOWROOM https image.
  final String cover;

  /// The live's own `genre_name` (Japanese, `ミュージック`).
  final String genreName;

  /// `follower_num`.
  final int? followers;

  /// `view_num`: the broadcast's visits, shown as total viewers.
  final int? views;

  /// `telop`: the caption the streamer sets, often empty.
  final String telop;
}

/// One genre of the snapshot and its live rooms in the site's order.
@immutable
final class ShowroomGenre {
  /// Creates the genre.
  new({required this.id, required this.name, required List<ShowroomLive> lives}) : lives = List.unmodifiable(lives);

  /// `genre_id` (0 is Popularity).
  final int id;

  /// `genre_name` of the group (English: `Popularity`, `Music`).
  final String name;

  /// Its live rooms.
  final List<ShowroomLive> lives;
}

/// The `live/onlives` snapshot: every live room, grouped by genre.
@immutable
final class ShowroomSnapshot {
  /// Creates the snapshot.
  new(List<ShowroomGenre> genres) : genres = List.unmodifiable(genres);

  /// Genres in the site's order.
  final List<ShowroomGenre> genres;

  /// Every live once, in genre order.
  Iterable<ShowroomLive> get uniqueLives sync* {
    final seen = <int>{};
    for (final genre in genres) {
      for (final live in genre.lives) {
        if (seen.add(live.roomId)) yield live;
      }
    }
  }

  /// The recommendations: the Popularity genre (0), else every live once.
  List<ShowroomLive> get popular =>
      genres.where((genre) => genre.id == 0).firstOrNull?.lives ?? uniqueLives.toList(growable: false);

  /// The lives of genre [id], or null when the snapshot has no such genre.
  List<ShowroomLive>? genre(int id) => genres.where((genre) => genre.id == id).firstOrNull?.lives;
}

/// `room/profile` of one room, as 3.x read it.
typedef ShowroomProfile = ({
  int roomId,
  String roomUrlKey,
  String name,
  String cover,
  String genreName,
  int? followers,
  int? views,
  String description,
});

/// Pure parsing of SHOWROOM responses (3.x's `ShowroomApi`, the models of
/// its `ShowroomSite` and its `ShowroomLink`). Each function takes the
/// response text and status and returns 3.x's models or throws a
/// `SiteError`.
abstract final class ShowroomApi {
  /// Web and API origin.
  static const String origin = 'https://www.showroom-live.com';

  /// Desktop Chrome 140, the UA 3.x sent with every request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's API request headers.
  static const Map<String, String> headers = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'referer': '$origin/',
  };

  /// 3.x's media request headers (`ShowroomApi.mediaHeaders`, used by its
  /// `PlaybackHeaderResolver` and set on every room).
  static const Map<String, String> mediaHeaders = {'user-agent': userAgent, 'referer': '$origin/'};

  /// `areaType` of the genres.
  static const String areaType = 'genre';

  /// Name of the one category (and `typeName` of its genres).
  static const String categoryName = 'SHOWROOM';

  /// Rooms per native directory page (3.x's `getDirectoryPage`).
  static const int directoryPageSize = 30;

  /// Largest slice 3.x served; a larger page size gives nothing.
  static const int maxPageSize = 100;

  /// A public room key (`room_url_key`).
  static final RegExp keyPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// A room id as links write it.
  static final RegExp _linkRoomId = RegExp(r'^[1-9][0-9]{0,18}$');

  /// First path segments that are site pages, not room keys: 3.x's list,
  /// plus the pages the archived v4 found (`r`, `onlive`, `campaign`,
  /// `about`, `lottery`), which 3.x took for keys and failed on.
  static const Set<String> reservedPaths = {
    'api',
    'room',
    'event',
    'ranking',
    'search',
    'login',
    'register',
    'mypage',
    'premium_live',
    'r',
    'onlive',
    'campaign',
    'about',
    'lottery',
  };

  // Snapshot ------------------------------------------------------------------

  /// `live/onlives`: every genre (a repeated `genre_id` is skipped) with its
  /// live rooms. A genre with nobody live holds a message cell (`cell_type`
  /// 7, no `room_id`), which is skipped (REG-SHOWROOM-001). Any other
  /// irregular row fails the whole snapshot (`ApiChanged`), as 3.x's test
  /// fixed: a row without a name is not shown half-read. The rows' own
  /// `streaming_url_list` is not read: 3.x checked it strictly but never
  /// used it (a room's streams come from `live/streaming_url`).
  static ShowroomSnapshot snapshot(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'onlives');
    final genres = <ShowroomGenre>[];
    final seen = <int>{};
    for (final raw in _list(root['onlives'], 'onlives', max: 128)) {
      final group = _object(raw, 'onlives genre');
      final id = _count(group['genre_id'], 'genre_id');
      if (!seen.add(id)) continue;
      final name = _text(group['genre_name'], 'genre_name');
      genres.add(
        ShowroomGenre(
          id: id,
          name: name,
          lives: [
            for (final cell in _list(group['lives'], 'lives of genre $id', max: 5000))
              if (_object(cell, 'live of genre $id') case final row
                  when row['room_id'] != null || row['cell_type'] == null)
                _live(row),
          ],
        ),
      );
    }
    if (genres.isEmpty) throw const ApiChanged(_site, 'onlives: no genre');
    return ShowroomSnapshot(genres);
  }

  static ShowroomLive _live(Map<String, dynamic> row) {
    final roomId = _positive(row['room_id'], 'room_id');
    _count(row['genre_id'], 'genre_id of $roomId');
    return ShowroomLive(
      roomId: roomId,
      roomUrlKey: _key(row['room_url_key'], 'room_url_key of $roomId'),
      name: _text(row['main_name'], 'main_name of $roomId'),
      cover: _image(row['image_square'] ?? row['image']),
      genreName: _optionalText(row['genre_name'], 'genre_name of $roomId'),
      followers: _optionalCount(row['follower_num'], 'follower_num of $roomId'),
      views: _optionalCount(row['view_num'], 'view_num of $roomId'),
      telop: _optionalText(row['telop'], 'telop of $roomId'),
    );
  }

  /// The one category `SHOWROOM` whose areas are the snapshot's genres, in
  /// its order, empty ones included (3.x).
  static List<LiveCategory> categories(ShowroomSnapshot snapshot) => [
    LiveCategory(
      id: _site,
      name: categoryName,
      children: [
        for (final genre in snapshot.genres)
          LiveArea(
            platform: _site,
            areaType: areaType,
            typeName: categoryName,
            areaId: '${genre.id}',
            areaName: genre.name,
          ),
      ],
    ),
  ];

  /// A live room card (3.x's `_card`): the telop as title when there is one,
  /// else the name; `view_num` as total viewers (REG-SHOWROOM-002); the
  /// cover as avatar too; 3.x's media headers.
  static LiveRoom card(ShowroomLive live) {
    final audience = live.views == null ? '' : '${live.views}';
    return LiveRoom(
      roomId: '${live.roomId}',
      platform: _site,
      link: '$origin/r/${live.roomUrlKey}',
      title: live.telop.isEmpty ? live.name : live.telop,
      nick: live.name,
      avatar: live.cover,
      cover: live.cover,
      area: live.genreName,
      followers: live.followers == null ? '' : '${live.followers}',
      watching: audience,
      totalViewers: audience,
      audienceMetricType: AudienceMetricType.totalViewers,
      liveStatus: LiveStatus.live,
      httpHeaders: mediaHeaders,
    );
  }

  /// Page [page] (from 1) of [lives], 30 a page (3.x's `getDirectoryPage`).
  static LiveDirectoryPage directoryPage(List<ShowroomLive> lives, {required int page}) {
    final start = (page - 1) * directoryPageSize;
    if (start >= lives.length) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final end = (start + directoryPageSize).clamp(start, lives.length);
    return LiveDirectoryPage(
      rooms: [for (final live in lives.sublist(start, end)) card(live)],
      page: page,
      hasMore: end < lives.length,
    );
  }

  /// Page [page] of [pageSize] of [values] (3.x's `_page`): nothing for a
  /// page or size below 1, a size over [maxPageSize] or a page past the end.
  static List<T> slice<T>(List<T> values, {required int page, required int pageSize}) {
    if (!validSlice(page: page, pageSize: pageSize)) return const [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return const [];
    return values.sublist(start, (start + pageSize).clamp(start, values.length));
  }

  /// Whether 3.x served anything for [page] of [pageSize].
  static bool validSlice({required int page, required int pageSize}) =>
      page >= 1 && pageSize >= 1 && pageSize <= maxPageSize;

  /// The lives matching [keyword] (3.x's search, over every live once): the
  /// room id or key equal to it (case ignored), or the name, telop or live
  /// genre name containing it (case ignored).
  static List<ShowroomLive> search(ShowroomSnapshot snapshot, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return [
      for (final live in snapshot.uniqueLives)
        if ('${live.roomId}' == query ||
            live.roomUrlKey.toLowerCase() == query ||
            live.name.toLowerCase().contains(query) ||
            live.telop.toLowerCase().contains(query) ||
            live.genreName.toLowerCase().contains(query))
          live,
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// The room number [reference] names by itself (3.x's `resolveRoomId`: an
  /// integer above 0), or null when it is a room key or nothing.
  static int? roomNumber(String reference) {
    final number = int.tryParse(reference.trim());
    return number != null && number > 0 ? number : null;
  }

  /// `room/status?room_url_key=`: the room id of a key. An unknown key is
  /// HTTP 404 (`NotFound`, sample S02-status-notfound).
  static int roomIdOfStatus(String body, {int status = 200}) =>
      _positive(_checked(body, status: status, what: 'room/status')['room_id'], 'room/status room_id');

  /// `room/profile` of [roomId] (3.x's checks: the answer is for that room,
  /// a valid key and name, `genre_id`, `is_onlive`). An unknown room is HTTP
  /// 404 (`NotFound`, sample S03-profile-notfound).
  static ShowroomProfile profile(String body, {required int roomId, int status = 200}) {
    final data = _checked(body, status: status, what: 'room/profile');
    final actual = _positive(data['room_id'], 'room/profile room_id');
    if (actual != roomId) throw ApiChanged(_site, 'room/profile: answer for room $actual, asked $roomId');
    final profile = (
      roomId: actual,
      roomUrlKey: _key(data['room_url_key'], 'room/profile room_url_key'),
      name: _text(data['main_name'] ?? data['room_name'], 'room/profile main_name'),
      cover: _image(data['image_square']),
      genreName: _optionalText(data['genre_name'], 'room/profile genre_name'),
      followers: _optionalCount(data['follower_num'], 'room/profile follower_num'),
      views: _optionalCount(data['view_num'], 'room/profile view_num'),
      description: _optionalText(data['description'], 'room/profile description'),
    );
    _count(data['genre_id'], 'room/profile genre_id');
    if (data['is_onlive'] is! bool) throw ApiChanged(_site, 'room/profile: is_onlive is ${data['is_onlive']}');
    return profile;
  }

  /// `live/live_info` of [roomId]: live when `live_status` is 2; 0 and 1 are
  /// offline; anything else, or an answer for another room, is `ApiChanged`
  /// (3.x). The comment server is kept for a live room.
  static ({bool live, String? bcsvrHost, String? bcsvrKey}) liveInfo(
    String body, {
    required int roomId,
    int status = 200,
  }) {
    final data = _checked(body, status: status, what: 'live_info');
    final actual = _positive(data['room_id'], 'live_info room_id');
    if (actual != roomId) throw ApiChanged(_site, 'live_info: answer for room $actual, asked $roomId');
    final state = _count(data['live_status'], 'live_status');
    if (state > 2) throw ApiChanged(_site, 'live_info: live_status $state');
    final live = state == 2;
    return (
      live: live,
      bcsvrHost: live ? _optionalString(data['bcsvr_host']) : null,
      bcsvrKey: live ? _optionalString(data['bcsvr_key']) : null,
    );
  }

  /// The room of [profile] (3.x's `_detailCard`): the name as title and
  /// streamer, `view_num` as total viewers even when offline (3.x), the
  /// square picture as cover and avatar, the description, 3.x's media
  /// headers.
  static LiveRoom room(ShowroomProfile profile, {required bool live}) {
    final audience = profile.views == null ? '' : '${profile.views}';
    return LiveRoom(
      roomId: '${profile.roomId}',
      platform: _site,
      link: '$origin/r/${profile.roomUrlKey}',
      title: profile.name,
      nick: profile.name,
      avatar: profile.cover,
      cover: profile.cover,
      area: profile.genreName,
      followers: profile.followers == null ? '' : '${profile.followers}',
      watching: audience,
      totalViewers: audience,
      audienceMetricType: AudienceMetricType.totalViewers,
      introduction: profile.description,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      httpHeaders: mediaHeaders,
    );
  }

  /// The external page of a room (3.x's `ShowroomLink.roomUrl`, used by its
  /// "open in browser"): the profile page of a room id; null for anything
  /// else.
  static String? roomUrl(String roomId) {
    final id = roomId.trim();
    return _linkRoomId.hasMatch(id) ? '$origin/room/profile?room_id=$id' : null;
  }

  // Streams -------------------------------------------------------------------

  /// `live/streaming_url`: the `streaming_url_list` rows (at most 64), not
  /// yet checked. An offline room has none (sample S05-streaming-offline).
  static List<Object?> streamRows(String body, {int status = 200}) => List.unmodifiable(
    _list(_checked(body, status: status, what: 'streaming_url')['streaming_url_list'], 'streaming_url_list', max: 64),
  );

  /// 3.x's qualities of [rows], best first: the adaptive `hls_all` master as
  /// 自动 (sort 2000), then each `hls` tier by `quality` (1000 原画, 200
  /// 中画质, lower 低画质); WebRTC and other types are skipped, a repeated URL
  /// too. The id is `{type}:{id}:{quality}` (`hls:2:1000`), the data the
  /// one URL. Any other irregular row fails them all (`ApiChanged`), as in
  /// 3.x: a URL that is not https on a SHOWROOM host, a missing label, id or
  /// `is_default`. None is `StreamUnavailable`.
  static List<LivePlayQuality> qualities(List<Object?> rows) {
    if (rows.length > 64) throw ApiChanged(_site, 'streaming_url: ${rows.length} rows');
    final qualities = <LivePlayQuality>[];
    final seen = <String>{};
    for (final raw in rows) {
      final row = _object(raw, 'streaming_url row');
      final type = _optionalText(row['type'], 'streaming_url type');
      if (type != 'hls' && type != 'hls_all') continue;
      final url = _mediaUrl(row['url']);
      if (!seen.add(url)) continue;
      final id = _count(row['id'], 'streaming_url id');
      _text(row['label'], 'streaming_url label');
      final level = _count(row['quality'], 'streaming_url quality');
      if (row['is_default'] is! bool) throw ApiChanged(_site, 'streaming_url: is_default is ${row['is_default']}');
      qualities.add(
        LivePlayQuality(
          quality: switch ((type, level)) {
            ('hls_all', _) => '自动',
            (_, >= 1000) => '原画',
            (_, >= 200) => '中画质',
            _ => '低画质',
          },
          id: '$type:$id:$level',
          data: List<String>.unmodifiable([url]),
          sort: type == 'hls_all' ? 2000 : level,
        ),
      );
    }
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no HLS stream');
    qualities.sort((left, right) {
      final rank = right.sort.compareTo(left.sort);
      return rank != 0 ? rank : '${left.selectionId}'.compareTo('${right.selectionId}');
    });
    return List.unmodifiable(qualities);
  }

  /// The line of [quality] (one of [qualities]' results): its HLS URL with
  /// 3.x's media headers and the host as line id; the quality itself is the
  /// applied one (3.x confirmed what was asked). The URLs are not signed and
  /// do not expire, so there is no lease.
  static LivePlayUrlResolution resolution(LivePlayQuality quality) {
    final data = quality.data;
    return LivePlayUrlResolution.lines([
      if (data is List)
        for (final url in data)
          LivePlayLine('$url', headers: mediaHeaders, format: StreamFormat.hls, lineId: Uri.tryParse('$url')?.host),
    ], appliedQualityData: quality.selectionId);
  }

  // Links ---------------------------------------------------------------------

  /// What a SHOWROOM link names (3.x's `ShowroomLink.parse`): the room id of
  /// `room/profile?room_id={id}`, or the key of `/r/{key}` and `/{key}`, on
  /// `showroom-live.com` or a subdomain over http(s) without user info. Site
  /// pages ([reservedPaths]) and anything else are null.
  static ({String? roomId, String? key})? link(Uri? uri) {
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.userInfo.isNotEmpty ||
        !_isHost(uri.host.toLowerCase())) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
      if (segments.length == 2 && segments[0] == 'room' && segments[1] == 'profile') {
        final id = uri.queryParameters['room_id']?.trim() ?? '';
        return _linkRoomId.hasMatch(id) ? (roomId: id, key: null) : null;
      }
    } on FormatException {
      return null;
    }
    final key = switch (segments) {
      ['r', final key] || [final key] => key.trim(),
      _ => null,
    };
    if (key == null || reservedPaths.contains(key.toLowerCase()) || !keyPattern.hasMatch(key)) return null;
    return (roomId: null, key: key);
  }

  static bool _isHost(String host) => host == 'showroom-live.com' || host.endsWith('.showroom-live.com');

  // Helpers -------------------------------------------------------------------

  static bool _trustedHost(String host) =>
      host == 'showroom-live.com' ||
      host.endsWith('.showroom-live.com') ||
      host == 'showroom-txlive.com' ||
      host.endsWith('.showroom-txlive.com');

  /// 3.x's `_image`: an https image on a SHOWROOM host, as written; '' for
  /// anything else.
  static String _image(Object? value) {
    if (value is! String || value.length > 8192) return '';
    final uri = Uri.tryParse(value);
    return uri != null && uri.isScheme('https') && uri.userInfo.isEmpty && _trustedHost(uri.host.toLowerCase())
        ? value
        : '';
  }

  /// 3.x's `mediaUrl`: an https URL on a SHOWROOM host without spaces,
  /// controls, user info or fragment; `ApiChanged` otherwise.
  static String _mediaUrl(Object? value) {
    if (value is! String || value.length > 8192 || value.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw ApiChanged(_site, 'streaming_url: url ${_snippet('$value')}');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isScheme('https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        !_trustedHost(uri.host.toLowerCase())) {
      throw ApiChanged(_site, 'streaming_url: url ${_snippet(value)}');
    }
    return value;
  }
}

/// 3.x's integers: a JSON integer or an integer string.
int? _integer(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '');

int _positive(Object? value, String what) => switch (_integer(value)) {
  final int number when number > 0 => number,
  _ => throw ApiChanged(_site, '$what is $value'),
};

int _count(Object? value, String what) => switch (_integer(value)) {
  final int number when number >= 0 => number,
  _ => throw ApiChanged(_site, '$what is $value'),
};

int? _optionalCount(Object? value, String what) => value == null || value == '' ? null : _count(value, what);

/// 3.x's `_text`: a string of at most 8192 characters, not blank, trimmed.
String _text(Object? value, String what) {
  if (value is! String || value.trim().isEmpty || value.length > 8192) throw ApiChanged(_site, '$what is $value');
  return value.trim();
}

/// 3.x's `_optionalText`: '' for null, else a string of at most 131072
/// characters, trimmed.
String _optionalText(Object? value, String what) {
  if (value == null) return '';
  if (value is! String || value.length > 131072) throw ApiChanged(_site, '$what is not text');
  return value.trim();
}

/// A room key (`room_url_key`).
String _key(Object? value, String what) {
  final key = _text(value, what);
  if (!ShowroomApi.keyPattern.hasMatch(key)) throw ApiChanged(_site, '$what "$key" is not a room key');
  return key;
}

String? _optionalString(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw ApiChanged(_site, '$what is not an object');
}

List<Object?> _list(Object? value, String what, {required int max}) {
  if (value is! List || value.length > max) {
    throw ApiChanged(_site, '$what is ${value is List ? '${value.length} items' : 'not a list'}');
  }
  return value.cast<Object?>();
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping: 200 is an answer; 401 and 403 are `RiskControl`,
/// 404 `NotFound` (SHOWROOM's `errors[].code 1002`), 429 `RateLimited`;
/// 5xx and every other status (redirects included: 3.x did not follow them)
/// `NetworkFailure`. The answer must be a JSON object (`ApiChanged`).
Map<String, dynamic> _checked(String body, {required int status, required String what}) {
  switch (status) {
    case 200:
      break;
    case 401 || 403:
      throw RiskControl(_site, detail: '$what: HTTP $status');
    case 404:
      throw NotFound(_site, '$what: HTTP 404');
    case 429:
      throw RateLimited(_site, detail: '$what: HTTP 429');
    default:
      throw NetworkFailure(_site, '$what: HTTP $status');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  return _object(decoded, what);
}
