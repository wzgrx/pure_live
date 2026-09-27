import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/text.dart';
import 'package:meta/meta.dart';

const _site = 'niconico';

Map<Object?, Object?> _obj(Object? value) => value is Map ? value : const <Object?, Object?>{};

/// What a watch page says (spec/sites/niconico.md §4).
typedef NiconicoWatch = ({RoomDetail detail, String programId, Uri? webSocket, SiteError? denied});

/// One cookie of a stream grant, scoped to a path (spec/sites/niconico.md §6.3).
@immutable
final class NiconicoCookie {
  /// Creates a cookie.
  const new({required this.name, required this.value, required this.path, required this.domain, this.expires});

  /// Cookie name (the same name repeats under different paths).
  final String name;

  /// Cookie value.
  final String value;

  /// Path prefix it applies to (`/hls/playlists/…`, `/hls/segments/…`, `/hls/keys/…`).
  final String path;

  /// Domain (`nicovideo.jp`).
  final String domain;

  /// Expiry, when given.
  final DateTime? expires;

  /// Whether this cookie is sent to [url].
  bool appliesTo(Uri url) => url.path.startsWith(path) && (url.host == domain || url.host.endsWith('.$domain'));
}

/// The `stream` message of a seat: the HLS master and its cookies.
@immutable
final class NiconicoGrant {
  /// Creates a grant.
  const new({required this.master, required this.cookies, required this.qualities});

  /// Multivariant playlist.
  final Uri master;

  /// Path-scoped cookies; every request under `/hls/` needs the ones whose
  /// path matches (§6.3).
  final List<NiconicoCookie> cookies;

  /// `availableQualities` (`abr`, `1.5Mbps480p30fps`, …).
  final List<String> qualities;

  /// The `Cookie` header for [url]: the cookies whose path matches.
  String cookieHeader(Uri url) =>
      cookies.where((cookie) => cookie.appliesTo(url)).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');

  /// The cookies as a Netscape cookie file (mpv `cookies-file`, FFmpeg's
  /// path-aware cookie store), one line per cookie.
  String netscapeCookies() => [
    for (final cookie in cookies)
      [
        '.${cookie.domain.replaceFirst(RegExp(r'^\.'), '')}',
        'TRUE',
        cookie.path,
        'TRUE',
        '${(cookie.expires?.millisecondsSinceEpoch ?? 0) ~/ 1000}',
        cookie.name,
        cookie.value,
      ].join('\t'),
  ].join('\n');
}

/// Pure parsing of niconico live responses (spec/sites/niconico.md).
abstract final class NiconicoParse {
  /// §1 a program id.
  static final RegExp programId = RegExp(r'^lv[1-9]\d{0,17}$');

  /// §1 a room id: a user's latest program, a channel, or a program.
  static final RegExp roomId = RegExp(r'^(?:user/[1-9]\d{0,18}|ch[1-9]\d{0,18}|lv[1-9]\d{0,17})$');

  /// §2.1 the one top-level category.
  static const categoryId = 'nicolive';

  /// §2.1 the recent-programs tabs (`live` is the game category).
  static const areas = [
    Area(id: 'common', name: '一般', categoryId: categoryId),
    Area(id: 'try', name: 'やってみた', categoryId: categoryId),
    Area(id: 'live', name: 'ゲーム', categoryId: categoryId),
    Area(id: 'req', name: '動画紹介', categoryId: categoryId),
    Area(id: 'face', name: '顔出し', categoryId: categoryId),
    Area(id: 'totu', name: '凸待ち', categoryId: categoryId),
    Area(id: 'vtuber', name: 'VTuber', categoryId: categoryId),
  ];

  /// §2.2 rows per recent page.
  static const recentSize = 70;

  /// §3 rows per search page.
  static const searchSize = 40;

  /// The watch page of a room id.
  static Uri link(String roomId) => Uri.parse('https://live.nicovideo.jp/watch/$roomId');

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static Uri? _image(Object? value) => jsonUrl(value);

  /// §1 the room id of a program row: the user for user programs, the
  /// channel for channel programs, the program itself otherwise.
  static String roomOf({required String program, String? provider, String? userId, String? channelId}) {
    if (provider == 'community' || provider == 'user') {
      if (userId != null && RegExp(r'^[1-9]\d{0,18}$').hasMatch(userId)) return 'user/$userId';
    }
    if (provider == 'channel' && channelId != null && RegExp(r'^ch[1-9]\d{0,18}$').hasMatch(channelId)) {
      return channelId;
    }
    return program;
  }

  static Map<String, dynamic> _meta(Map<String, dynamic> root, String what) {
    final meta = _map(root['meta'], '$what.meta');
    if (jsonInt(meta['statusCode']) != 200 || meta['errorCode'] != 'OK') {
      throw ApiChanged(_site, '$what: ${meta['statusCode']} ${meta['errorCode']}');
    }
    return meta;
  }

  static Map<String, dynamic> _root(String body, String what) {
    try {
      return _map(jsonDecode(body), what);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  /// §2.2 `recent/v1/programs`: on-air programs of a tab; more pages while
  /// `page × 70 < totalCount`.
  static Page<RoomCard> recent(String body, {required int page}) {
    final root = _root(body, 'recent');
    final total = jsonInt(_meta(root, 'recent')['totalCount']) ?? 0;
    final rows = root['data'];
    if (rows is! List) throw const ApiChanged(_site, 'recent: data is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final program = jsonString(row['id']);
      if (program == null || !programId.hasMatch(program) || row['liveCycle'] != 'ON_AIR') continue;
      final provider = _obj(row['programProvider']);
      final social = _obj(row['socialGroup']);
      final id = roomOf(
        program: program,
        provider: jsonString(row['providerType']),
        userId: jsonString(provider['id']),
        channelId: jsonString(social['id']),
      );
      if (!seen.add(id)) continue;
      final watch = jsonInt(_obj(row['statistics'])['watchCount']);
      final begin = jsonInt(row['beginAt']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(row['title']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(provider['name']) ?? jsonString(social['name']) ?? ''),
          state: LiveState.live,
          cover: _image(row['listingThumbnail']),
          audience: Audience(cumulative: watch != null && watch >= 0 ? watch : null),
          liveSince: begin == null ? null : DateTime.fromMillisecondsSinceEpoch(begin, isUtc: true),
          avatar: _image(provider['icon']) ?? _image(social['thumbnailUrl']),
        ),
      );
    }
    final more = rows.isNotEmpty && page * recentSize < total;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `search/v1/programs` (on air only); more pages while
  /// `page × 40 < totalCount`.
  static Page<RoomCard> search(String body, {required int page}) {
    final root = _root(body, 'search');
    _meta(root, 'search');
    final data = _map(root['data'], 'search.data');
    final total = jsonInt(data['totalCount']) ?? 0;
    final rows = data['programs'];
    if (rows is! List) throw const ApiChanged(_site, 'search: programs is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final program = jsonString(row['nicoliveProgramId']);
      if (program == null || !programId.hasMatch(program) || row['status'] != 'ON_AIR') continue;
      final supplier = _obj(row['supplier']);
      final social = _obj(row['socialGroup']);
      final id = roomOf(
        program: program,
        provider: jsonString(row['providerType']),
        userId: jsonString(supplier['programProviderId']),
        channelId: jsonString(social['id']),
      );
      if (!seen.add(id)) continue;
      final icons = _obj(supplier['icons']);
      final watch = jsonInt(_obj(row['statistics'])['watchCount']);
      final begin = jsonInt(row['beginTime']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(row['title']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(supplier['name']) ?? ''),
          state: LiveState.live,
          cover: _image(row['listingThumbnail']),
          audience: Audience(cumulative: watch != null && watch >= 0 ? watch : null),
          liveSince: begin == null ? null : DateTime.fromMillisecondsSinceEpoch(begin * 1000, isUtc: true),
          avatar: _image(icons['uri150x150']),
        ),
      );
    }
    final more = rows.isNotEmpty && page * searchSize < total;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 the `embedded-data` props of a watch page.
  static Map<String, dynamic> props(String html) {
    final match = RegExp('<script id="embedded-data" data-props="([^"]*)"').firstMatch(html);
    if (match == null) throw const ApiChanged(_site, 'watch page: no embedded-data');
    try {
      return _map(jsonDecode(decodeHtmlEntities(match.group(1)!)), 'embedded-data');
    } on FormatException {
      throw const ApiChanged(_site, 'watch page: embedded-data is not JSON');
    }
  }

  /// §4 a watch page for [roomId]: the program, its state, the seat socket
  /// and why it cannot be watched anonymously, if so.
  static NiconicoWatch watch(String html, {required String roomId}) {
    final data = props(html);
    final program = _map(data['program'], 'program');
    final id = jsonString(program['nicoliveProgramId']);
    if (id == null || !programId.hasMatch(id)) throw ApiChanged(_site, 'watch page: program id $id');
    if (programId.hasMatch(roomId) && id != roomId) throw ApiChanged(_site, 'watch page: asked $roomId, got $id');
    final status = program['status'];
    final state = switch (status) {
      'ON_AIR' => LiveState.live,
      'ENDED' || 'RELEASED' => LiveState.offline,
      _ => throw ApiChanged(_site, 'watch page: status $status'),
    };
    final condition = _obj(data['programWatch'])['condition'];
    final user = _obj(data['userProgramWatch']);
    final denied = user['isCountryRestrictionTarget'] == true
        ? RegionBlocked(_site, '$id: country restriction')
        : condition is Map && condition['needLogin'] == true
        ? NeedsLogin(_site, '$id: needLogin')
        : user['canWatch'] != true
        ? NeedsLogin(_site, '$id: canWatch false')
        : null;
    Uri? socket;
    final site = _obj(data['site']);
    final relive = _obj(site['relive']);
    final raw = jsonString(relive['webSocketUrl']);
    final frontend = jsonInt(site['frontendId']);
    if (raw != null && raw.startsWith('wss://')) {
      final url = Uri.parse(raw);
      socket = url.replace(queryParameters: {...url.queryParameters, 'frontend_id': '${frontend ?? 9}'});
    }
    final supplier = _obj(program['supplier']);
    final icons = _obj(supplier['icons']);
    final screenshot = _obj(program['screenshot'])['urlSet'];
    final thumbnail = _obj(program['thumbnail']);
    final huge = _obj(thumbnail['huge']);
    final watchCount = jsonInt(_obj(program['statistics'])['watchCount']);
    final begin = jsonInt(program['beginTime']);
    final description = jsonString(program['description']);
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, roomId),
          title: decodeHtmlEntities(jsonString(program['title']) ?? ''),
          anchorName: decodeHtmlEntities(jsonString(supplier['name']) ?? ''),
          state: state,
          cover: screenshot is Map
              ? _image(screenshot['middle']) ?? _image(screenshot['large'])
              : _image(huge['s640x360']) ?? _image(thumbnail['large']),
          audience: Audience(cumulative: watchCount != null && watchCount >= 0 ? watchCount : null),
          liveSince: state == LiveState.live && begin != null
              ? DateTime.fromMillisecondsSinceEpoch(begin * 1000, isUtc: true)
              : null,
        ),
        link: link(roomId),
        avatar: _image(icons['uri150x150']),
        introduction: description == null
            ? null
            : decodeHtmlEntities(description.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp('<[^>]*>'), '')),
        danmakuKeys: {'programId': id},
      ),
      programId: id,
      webSocket: state == LiveState.live ? socket : null,
      denied: denied,
    );
  }

  /// §6.2 the `stream` message data.
  static NiconicoGrant grant(Map<String, dynamic> data) {
    final master = jsonUrl(data['uri']);
    if (data['protocol'] != 'hls' || master == null) throw ApiChanged(_site, 'stream: protocol ${data['protocol']}');
    final cookies = <NiconicoCookie>[
      for (final raw in (data['cookies'] as List?) ?? const [])
        if (raw is Map)
          if ((jsonString(raw['name']), jsonString(raw['value']), jsonString(raw['path'])) case (
            final String name,
            final String value,
            final String path,
          ))
            NiconicoCookie(
              name: name,
              value: value,
              path: path,
              domain: (jsonString(raw['domain']) ?? 'nicovideo.jp').replaceFirst(RegExp(r'^\.'), ''),
              expires: switch (jsonString(raw['expires'])) {
                final String text => _httpDate(text),
                null => null,
              },
            ),
    ];
    return NiconicoGrant(
      master: master,
      cookies: cookies,
      qualities: [for (final q in (data['availableQualities'] as List?) ?? const []) '$q'],
    );
  }

  static DateTime? _httpDate(String text) {
    // `Mon, 28 Sep 2026 16:59:46 GMT`
    final match = RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$').firstMatch(text);
    if (match == null) return null;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months.indexOf(match.group(2)!) + 1;
    if (month == 0) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}
