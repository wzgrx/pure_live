import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_master.dart';
import 'package:live_core/src/input_recipe.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'niconico';

/// A program's broadcast state on its watch page.
enum NiconicoProgramStatus {
  /// `RELEASED`: announced, not started.
  scheduled,

  /// `ON_AIR`.
  onAir,

  /// `ENDED`.
  ended,
}

/// Whether an anonymous viewer may watch a program (3.x's `NiconicoAccess`).
enum NiconicoAccess {
  /// `canWatch`.
  allowed,

  /// `programWatch.condition.needLogin`.
  loginRequired,

  /// `userProgramWatch.isCountryRestrictionTarget`.
  regionRestricted,

  /// Anything else that keeps `canWatch` false (member-only or paid).
  denied,
}

/// What 3.x kept of a watch page: the program, its state, whether it may be
/// watched and, when on air and watchable, the seat's WebSocket bootstrap
/// (short-lived: never stored in a room, used at once).
@immutable
final class NiconicoWatch {
  /// Creates the snapshot.
  const new({
    required this.programId,
    required this.title,
    required this.broadcaster,
    required this.status,
    required this.access,
    this.watchCount,
    this.socket,
    this.cover,
    this.avatar,
  });

  /// `lv…`: one broadcast, not its broadcaster.
  final String programId;

  /// Program title.
  final String title;

  /// `program.supplier.name`.
  final String broadcaster;

  /// Broadcast state.
  final NiconicoProgramStatus status;

  /// Whether an anonymous viewer may watch.
  final NiconicoAccess access;

  /// `statistics.watchCount`: cumulative visits, not concurrent viewers.
  final int? watchCount;

  /// The seat's WebSocket with `frontend_id`, only when on air and allowed.
  final Uri? socket;

  /// The live screenshot, else the program thumbnail.
  final String? cover;

  /// The broadcaster's icon.
  final String? avatar;

  /// Why the program's stream cannot be played now, or null: not on air is
  /// `StreamUnavailable`, then the access check (3.x checked in this order).
  SiteError? get streamError => switch ((status, access)) {
    (NiconicoProgramStatus.scheduled || NiconicoProgramStatus.ended, _) => StreamUnavailable(
      _site,
      '$programId is ${status.name}',
    ),
    (_, NiconicoAccess.regionRestricted) => RegionBlocked(_site, '$programId: country restriction'),
    (_, NiconicoAccess.loginRequired) => NeedsLogin(_site, '$programId: needLogin'),
    (_, NiconicoAccess.denied) => NeedsLogin(_site, '$programId: canWatch false'),
    _ => null,
  };

  @override
  String toString() => 'NiconicoWatch($programId, ${status.name}, ${access.name})';
}

/// What a room detail carries besides 3.x's fields: the state and access
/// behind its notice, so the interface can show the notice in its own
/// language (M13).
@immutable
final class NiconicoRoomData {
  /// Creates the data.
  const new({required this.status, required this.access});

  /// Broadcast state.
  final NiconicoProgramStatus status;

  /// Whether an anonymous viewer may watch.
  final NiconicoAccess access;
}

/// One media cookie of a stream grant; it applies to its path only.
@immutable
final class NiconicoCookie {
  /// Creates the cookie.
  const new({required this.name, required this.value, required this.path, this.expires});

  /// Cookie name.
  final String name;

  /// Cookie value.
  final String value;

  /// Path prefix (`/hls/playlists/…`, `/hls/segments/…`, `/hls/keys/…`).
  final String path;

  /// Expiry, when given.
  final DateTime? expires;

  @override
  String toString() => 'NiconicoCookie($name, $path)';
}

/// One revocable stream grant: the seat's `stream` message (3.x's
/// `NiconicoStream`). The HLS master and every playlist, segment and key
/// below it need the cookies of their own path on the media origin (all of
/// them in one header is refused with 403). A later `stream` message or the
/// seat's end revokes the grant; its cookies are dropped with it.
final class NiconicoGrant {
  new _(this.uri, this.quality, this.availableQualities, List<NiconicoCookie> cookies) : _cookies = cookies;

  /// The HLS master on `livedelivery.dlive.nicovideo.jp`.
  final Uri uri;

  /// The quality the seat asked for (`abr`).
  final String quality;

  /// `availableQualities` (`abr`, `super_high`, `1.5Mbps480p30fps`...).
  final List<String> availableQualities;

  final List<NiconicoCookie> _cookies;
  bool _active = true;

  /// Whether the grant was not revoked.
  bool get isActive => _active;

  /// Cookies kept (none after [revoke]).
  int get cookieCount => _cookies.length;

  /// The `Cookie` header for [target] at [now]: the unexpired cookies whose
  /// path is [target]'s path or a parent of it, on exactly the master's
  /// origin, longest path first, then in the order received; null when none
  /// applies or [target] has user info or a fragment. A revoked grant throws
  /// `StreamUnavailable`.
  String? cookieHeaderFor(Uri target, {DateTime? now}) {
    if (!_active) throw const StreamUnavailable(_site, 'the stream grant was revoked');
    if (target.userInfo.isNotEmpty || target.hasFragment || !target.isScheme('https') || target.host.isEmpty) {
      return null;
    }
    if (target.origin != uri.origin) return null;
    final at = now ?? DateTime.now();
    final matching =
        [
          for (final (index, cookie) in _cookies.indexed)
            if (_pathMatches(target.path, cookie.path) && (cookie.expires == null || cookie.expires!.isAfter(at)))
              (index: index, cookie: cookie),
        ]..sort((a, b) {
          final byPath = b.cookie.path.length.compareTo(a.cookie.path.length);
          return byPath != 0 ? byPath : a.index.compareTo(b.index);
        });
    if (matching.isEmpty) return null;
    return [for (final entry in matching) '${entry.cookie.name}=${entry.cookie.value}'].join('; ');
  }

  /// Drops the cookies; later [cookieHeaderFor] calls throw.
  void revoke() {
    _active = false;
    _cookies.clear();
  }

  static bool _pathMatches(String request, String cookie) =>
      request == cookie ||
      (request.startsWith(cookie) && (cookie.endsWith('/') || request.substring(cookie.length).startsWith('/')));

  @override
  String toString() => 'NiconicoGrant(${uri.host}, $quality, ${_cookies.length} cookies)';
}

/// One quality of a program: an exact video variant of the master, by
/// resolution and bandwidth (3.x's `NiconicoQuality`, bound to its program
/// like 3.x's `_Choice`). Never holds a media URL or a cookie.
@immutable
final class NiconicoQuality {
  /// Creates the quality.
  const new({required this.programId, required this.width, required this.height, required this.bandwidth});

  /// The program it was read from.
  final String programId;

  /// Video width.
  final int width;

  /// Video height.
  final int height;

  /// `BANDWIDTH`, bits per second.
  final int bandwidth;

  /// `800x450`.
  String get resolution => '${width}x$height';

  /// `800x450@1080800`: the quality id.
  String get id => '$resolution@$bandwidth';

  /// `800×450 · 1080800 bps`: 3.x's label.
  String get label => '$width×$height · $bandwidth bps';

  @override
  bool operator ==(Object other) => other is NiconicoQuality && other.programId == programId && other.id == id;

  @override
  int get hashCode => Object.hash(programId, id);

  @override
  String toString() => 'NiconicoQuality($programId, $id)';
}

/// The public recipe of a niconico input (3.x's `NiconicoInputRecipe`): the
/// program and the exact variant. There is no URL to export: playback and
/// recording each read the watch page, open a seat of their own, keep it
/// while they play and send every media request the cookies of its path
/// (M7, M8).
@immutable
final class NiconicoInputRecipe implements LiveInputRecipe {
  /// Creates the recipe; a [bandwidth] needs a [resolution].
  new({required this.programId, required this.resolution, this.bandwidth}) {
    if (!NiconicoApi.isProgramId(programId)) {
      throw ArgumentError.value(programId, 'programId', 'not a niconico program');
    }
    final rate = bandwidth;
    if (rate != null && (resolution == null || rate <= 0)) {
      throw ArgumentError('A positive bandwidth selector requires an explicit resolution');
    }
  }

  /// `lv…`.
  final String programId;

  /// `800x450`; null lets the player choose (the master itself).
  final String? resolution;

  /// The variant's `BANDWIDTH`, telling apart variants of one resolution.
  final int? bandwidth;

  @override
  String get identity => 'niconico:$programId:${resolution ?? 'auto'}:${bandwidth ?? 'auto'}';

  @override
  bool operator ==(Object other) => other is NiconicoInputRecipe && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'NiconicoInputRecipe($identity)';
}

/// Pure parsing of niconico live answers (3.x's `NiconicoWatch`,
/// `NiconicoDirectory`, `NiconicoStream` and `NiconicoQuality`). Each
/// function takes the answer and its status and returns 3.x's models or
/// throws a `SiteError`.
abstract final class NiconicoApi {
  /// The site.
  static const String origin = 'https://live.nicovideo.jp';

  /// 3.x's headers of every page and list request.
  static const Map<String, String> headers = {'referer': '$origin/', 'user-agent': 'Mozilla/5.0'};

  /// The seat's WebSocket handshake headers (3.x's `Origin`).
  static const Map<String, String> seatHeaders = {'origin': origin};

  /// The largest page or list 3.x accepted, in UTF-8 bytes.
  static const int responseLimit = 2 * 1024 * 1024;

  /// Rows of a recent-programs page.
  static const int recentPageSize = 70;

  /// Rows of a search page.
  static const int searchPageSize = 40;

  /// The recent-programs tabs in 3.x's order. `live` is the game tab, not
  /// "every live program".
  static const List<String> tabs = ['common', 'try', 'live', 'req', 'face', 'totu', 'vtuber'];

  /// 3.x's area names (its zh.json `niconico_category_*`); the interface
  /// shows its own translation by area id (M13).
  static const Map<String, String> tabNames = {
    'common': '综合',
    'try': '创作与挑战',
    'live': '游戏',
    'req': '视频介绍',
    'face': '露脸直播',
    'totu': '连麦互动',
    'vtuber': 'VTuber',
  };

  /// The area type of the tabs.
  static const String areaType = 'recent';

  /// 3.x's zh.json text of the notice parts, by key.
  static const Map<String, String> noticeText = {
    'niconico_scheduled': '节目尚未开始。',
    'niconico_login_required': '此节目要求登录官方站点。',
    'niconico_region_restricted': '此节目设有地区访问限制。',
    'niconico_access_restricted': '此节目的当前观看权限受限。',
    'niconico_program_scope': '收藏对应本次节目，主播的新节目需重新添加；弹幕暂未接入。',
  };

  static final RegExp _programId = RegExp(r'^lv[1-9][0-9]{0,17}$');

  /// Whether [id] is a program id (`lv` and up to 18 digits, no leading 0).
  static bool isProgramId(String id) => _programId.hasMatch(id);

  /// The watch page of [programId].
  static String watchUrl(String programId) => '$origin/watch/$programId';

  static final RegExp _watchLink = RegExp(
    r'^https://live\.nicovideo\.jp/watch/(lv[1-9][0-9]{0,17})(?:\?[^#\s]*)?(?:#[^\s]*)?$',
  );

  /// The program of an https watch link as written (3.x's `NiconicoLink`):
  /// exactly `https://live.nicovideo.jp/watch/lv…` with an optional query
  /// and fragment. Other hosts, ports, credentials, `http`, encoded or
  /// dot-segment paths and user or channel pages are not programs.
  static String? programIdFromUrl(String url) {
    final value = url.trim();
    if (value.length > 2048) return null;
    return _watchLink.firstMatch(value)?.group(1);
  }

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category, `niconico`, whose areas are the [tabs].
  static LiveCategory category() => LiveCategory(
    id: _site,
    name: 'niconico',
    children: [
      for (final tab in tabs)
        LiveArea(platform: _site, areaType: areaType, areaId: tab, areaName: tabNames[tab]!, typeName: 'niconico'),
    ],
  );

  /// `recent/v1/programs` (`search: false`) or `search/v1/programs`: page
  /// [page] of on-air programs, more while `totalCount > page × size`.
  ///
  /// 3.x's checks: `meta` 200/`OK` (else the service failed:
  /// `NetworkFailure`); `totalCount` a count not below the rows; at most 70
  /// (40) rows; every row on air, of a known provider type, with a title, a
  /// name and a watch link to itself, and no program twice. Anything else is
  /// `ApiChanged` for the whole page.
  static LiveDirectoryPage directoryPage(String body, {required int page, required bool search, int status = 200}) {
    final what = search ? 'search' : 'recent';
    _status(status, what);
    final root = _json(body, what);
    final meta = _map(root['meta'], '$what.meta');
    if (meta['statusCode'] != 200 || meta['errorCode'] != 'OK') {
      throw NetworkFailure(_site, '$what: meta ${meta['statusCode']} ${meta['errorCode']}');
    }
    final data = search ? _map(root['data'], '$what.data') : meta;
    final total = _count(data['totalCount'], '$what.totalCount');
    final rows = search ? data['programs'] : root['data'];
    final size = search ? searchPageSize : recentPageSize;
    if (rows is! List || rows.length > size || total == null || total < rows.length) {
      throw ApiChanged(_site, '$what: ${rows is List ? rows.length : 'no'} rows, totalCount $total');
    }
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final row in rows) {
      final room = _listRoom(_map(row, '$what row'), search: search);
      if (!seen.add(room.roomId)) throw ApiChanged(_site, '$what: ${room.roomId} twice');
      rooms.add(room);
    }
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: total > page * size);
  }

  static LiveRoom _listRoom(Map<String, dynamic> row, {required bool search}) {
    final id = _text(row[search ? 'nicoliveProgramId' : 'id'], 'program id');
    if (!isProgramId(id)) throw ApiChanged(_site, 'list: program id $id');
    final link = _text(row['watchPageUrl'], 'watchPageUrl');
    if (programIdFromUrl(link) != id && link.trim() != id) throw ApiChanged(_site, 'list: $id links to $link');
    final state = row[search ? 'status' : 'liveCycle'];
    if (state != 'ON_AIR') throw ApiChanged(_site, 'list: $id is $state');
    if (!const {'community', 'channel', 'official'}.contains(row['providerType'])) {
      throw ApiChanged(_site, 'list: $id provider type ${row['providerType']}');
    }
    final provider = row[search ? 'supplier' : 'programProvider'];
    final social = row['socialGroup'];
    final name = provider is Map ? provider['name'] : null;
    final icons = provider is Map ? provider['icons'] : null;
    final icon = provider is Map ? (search ? (icons is Map ? icons['uri150x150'] : null) : provider['icon']) : null;
    final count = _count(_map(row['statistics'], 'list statistics')['watchCount'], 'list watchCount');
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _text(row['title'], 'title'),
      nick: _text(name ?? (social is Map ? social['name'] : null), 'name'),
      // A channel's program provider has an empty icon; 3.x only fell back
      // to the social group's for a missing one.
      avatar: publicImage(icon) ?? publicImage(social is Map ? social['thumbnailUrl'] : null) ?? '',
      cover: publicImage(row['flippedListingThumbnail']) ?? publicImage(row['listingThumbnail']) ?? '',
      link: watchUrl(id),
      liveStatus: LiveStatus.live,
      totalViewers: count == null ? '' : '$count',
      audienceMetricType: AudienceMetricType.totalViewers,
    );
  }

  // Watch page ----------------------------------------------------------------

  static final RegExp _scriptTag = RegExp(r'''<script\b((?:[^>"']|"[^"]*"|'[^']*')*)>''', caseSensitive: false);
  static final RegExp _tagAttribute = RegExp(r'''([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''');

  /// The watch page of [programId]: `<script id="embedded-data">`'s
  /// `data-props`, HTML-decoded JSON (3.x read it with package:html).
  ///
  /// 3.x's checks, all `ApiChanged`: exactly one such script; the program
  /// is [programId]; `status` `RELEASED`, `ON_AIR` or `ENDED`; the access
  /// flags are booleans; `watchCount` null or a count. When on air and
  /// watchable, the seat's `webSocketUrl` must be `wss://a.live2.nicovideo.jp`
  /// `/[unama/]wsapi/v2/watch/<n>?…` without port, credentials, fragment or
  /// repeated parameters, and `frontendId` 1–9999 (added as `frontend_id`).
  /// Images that are not https on `*.nimg.jp` or `*.nicovideo.jp` are left
  /// out without failing the page.
  static NiconicoWatch watch(String body, {required String programId, int status = 200}) {
    _status(status, 'watch page', notFound: true);
    _limit(body, 'watch page');
    final props = <String>[];
    for (final tag in _scriptTag.allMatches(body)) {
      final attributes = _attributes(tag.group(1)!);
      if (attributes['id'] == 'embedded-data') props.add(attributes['data-props'] ?? '');
    }
    if (props.length != 1) throw ApiChanged(_site, 'watch page: ${props.length} embedded-data scripts');
    final Map<String, dynamic> data;
    try {
      data = _map(jsonDecode(decodeHtmlEntities(props.single)), 'embedded-data');
    } on FormatException {
      throw const ApiChanged(_site, 'watch page: embedded-data is not JSON');
    }
    return watchData(data, programId: programId);
  }

  /// [watch] from the decoded `embedded-data`.
  static NiconicoWatch watchData(Map<String, dynamic> data, {required String programId}) {
    final program = _map(data['program'], 'program');
    final id = program['nicoliveProgramId'];
    if (id is! String || id != programId) throw ApiChanged(_site, 'watch page: asked for $programId, got $id');
    final status = switch (program['status']) {
      'RELEASED' => NiconicoProgramStatus.scheduled,
      'ON_AIR' => NiconicoProgramStatus.onAir,
      'ENDED' => NiconicoProgramStatus.ended,
      final other => throw ApiChanged(_site, 'watch page: status $other'),
    };
    final needsLogin = _boolean(
      _map(_map(data['programWatch'], 'programWatch')['condition'], 'condition')['needLogin'],
    );
    final user = _map(data['userProgramWatch'], 'userProgramWatch');
    final countryRestricted = _boolean(user['isCountryRestrictionTarget']);
    final canWatch = _boolean(user['canWatch']);
    final access = countryRestricted
        ? NiconicoAccess.regionRestricted
        : needsLogin
        ? NiconicoAccess.loginRequired
        : canWatch
        ? NiconicoAccess.allowed
        : NiconicoAccess.denied;
    final count = _count(_map(program['statistics'], 'statistics')['watchCount'], 'watchCount');
    Uri? socket;
    if (status == NiconicoProgramStatus.onAir && access == NiconicoAccess.allowed) {
      final site = _map(data['site'], 'site');
      socket = _socket(_map(site['relive'], 'relive')['webSocketUrl'], site['frontendId']);
    }
    final supplier = _map(program['supplier'], 'supplier');
    final icons = supplier['icons'];
    return NiconicoWatch(
      programId: programId,
      title: _string(program['title'], 'title'),
      broadcaster: _string(supplier['name'], 'supplier.name'),
      status: status,
      access: access,
      watchCount: count,
      socket: socket,
      cover: _screenshot(program['screenshot']) ?? _thumbnail(program['thumbnail']),
      avatar: icons is Map ? publicImage(icons['uri150x150']) : null,
    );
  }

  static Uri _socket(Object? value, Object? frontend) {
    final raw = _string(value, 'webSocketUrl');
    if (frontend is! int || frontend <= 0 || frontend > 9999) {
      throw ApiChanged(_site, 'watch page: frontendId $frontend');
    }
    final uri = Uri.tryParse(raw);
    if (raw.length > 8192 ||
        uri == null ||
        !isSeatSocket(uri) ||
        !raw.startsWith('wss://a.live2.nicovideo.jp${uri.path}?') ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      throw const ApiChanged(_site, 'watch page: unexpected webSocketUrl');
    }
    return uri.replace(queryParameters: {...uri.queryParameters, 'frontend_id': '$frontend'});
  }

  /// Whether [uri] is a seat WebSocket: `wss://a.live2.nicovideo.jp`
  /// `/[unama/]wsapi/v2/watch/<n>` without port, credentials or fragment.
  static bool isSeatSocket(Uri uri) =>
      uri.isScheme('wss') &&
      uri.host == 'a.live2.nicovideo.jp' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment &&
      RegExp(r'^/(?:unama/)?wsapi/v2/watch/[1-9][0-9]*$').hasMatch(uri.path);

  static String? _screenshot(Object? value) {
    if (value is! Map || value['urlSet'] is! Map) return null;
    final urls = value['urlSet'] as Map;
    return publicImage(urls['middle']) ?? publicImage(urls['large']) ?? publicImage(urls['small']);
  }

  static String? _thumbnail(Object? value) {
    if (value is! Map) return null;
    final huge = value['huge'];
    return publicImage(huge is Map ? huge['s640x360'] : null) ??
        publicImage(value['large']) ??
        publicImage(value['small']);
  }

  /// [value] when it is an https image link on `*.nimg.jp` or
  /// `*.nicovideo.jp`, written without port, credentials or fragment; else
  /// null (3.x's `publicImage`: artwork is optional, so a bad link drops
  /// the picture, not the room).
  static String? publicImage(Object? value) {
    if (value is! String || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isScheme('https') || uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment) {
      return null;
    }
    if (!(uri.host.endsWith('.nimg.jp') || uri.host.endsWith('.nicovideo.jp'))) return null;
    // Uri drops an explicit :443; the link must be written without one.
    final base = 'https://${uri.host}';
    if (value != base && !value.startsWith('$base/') && !value.startsWith('$base?')) return null;
    return value;
  }

  /// The room of [watch] (3.x's detail): live when on air, else offline
  /// (scheduled and ended alike); cumulative visits as `totalViewers`; the
  /// notice 3.x wrote ([notice]); [NiconicoRoomData] for the interface.
  static LiveRoom room(NiconicoWatch watch) => LiveRoom(
    roomId: watch.programId,
    platform: _site,
    title: watch.title,
    nick: watch.broadcaster,
    cover: watch.cover ?? '',
    avatar: watch.avatar ?? '',
    link: watchUrl(watch.programId),
    liveStatus: watch.status == NiconicoProgramStatus.onAir ? LiveStatus.live : LiveStatus.offline,
    totalViewers: watch.watchCount == null ? '' : '${watch.watchCount}',
    audienceMetricType: AudienceMetricType.totalViewers,
    notice: notice(watch.status, watch.access),
    data: NiconicoRoomData(status: watch.status, access: watch.access),
  );

  /// 3.x's notice in its zh.json text: "not started" for a scheduled
  /// program, the access restriction of a program on air, and always that a
  /// follow is this one program.
  static String notice(NiconicoProgramStatus status, NiconicoAccess access) {
    final restriction = switch (access) {
      NiconicoAccess.loginRequired => noticeText['niconico_login_required'],
      NiconicoAccess.regionRestricted => noticeText['niconico_region_restricted'],
      NiconicoAccess.denied => noticeText['niconico_access_restricted'],
      NiconicoAccess.allowed => null,
    };
    return [
      if (status == NiconicoProgramStatus.scheduled) noticeText['niconico_scheduled']!,
      if (status == NiconicoProgramStatus.onAir && restriction != null) restriction,
      noticeText['niconico_program_scope']!,
    ].join(' ');
  }

  // Seat ----------------------------------------------------------------------

  static final RegExp _qualityName = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
  static final RegExp _cookieName = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  static final RegExp _cookieValue = RegExp(r'^[\x21-\x7e]*$');
  static final RegExp _cookiePath = RegExp(r'^/hls/[A-Za-z0-9_/-]+$');

  /// Most cookies in one grant.
  static const int maxCookies = 64;

  /// Most characters of one cookie (origin, name, value and path).
  static const int maxCookieCharacters = 4096;

  /// Most characters of all cookies of a grant.
  static const int maxGrantCharacters = 16 * 1024;

  /// The seat's `stream` message data at [now] (3.x's
  /// `NiconicoStream.parse`, checked as a whole):
  ///
  /// - `protocol` `hls`; `uri` an https `.m3u8` under `/hls/playlists/` on
  ///   `livedelivery.dlive.nicovideo.jp`, as written, without port,
  ///   credentials or fragment;
  /// - `quality` one of `availableQualities` (1–32 distinct names);
  /// - at most 64 `cookies`, each a token name (not `__Host-`), a printable
  ///   value without `;`, `"` or `\`, a `/hls/…` path, domain
  ///   `nicovideo.jp`, secure, `expires` null or an HTTP date, no name
  ///   twice on one path, within the size limits.
  ///
  /// Anything else is `ApiChanged`. Cookies already expired at [now] are
  /// dropped.
  static NiconicoGrant grant(Map<String, dynamic> data, {DateTime? now}) {
    if (data['protocol'] != 'hls') throw ApiChanged(_site, 'stream: protocol ${data['protocol']}');
    final raw = data['uri'];
    final uri = raw is String && raw.length <= 8192 ? Uri.tryParse(raw) : null;
    if (raw is! String ||
        uri == null ||
        !uri.isScheme('https') ||
        uri.host != 'livedelivery.dlive.nicovideo.jp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        !uri.path.startsWith('/hls/playlists/') ||
        !uri.path.endsWith('.m3u8') ||
        !raw.startsWith('https://livedelivery.dlive.nicovideo.jp${uri.path}')) {
      throw const ApiChanged(_site, 'stream: unexpected uri');
    }
    final quality = data['quality'];
    final qualities = data['availableQualities'];
    if (quality is! String ||
        !_qualityName.hasMatch(quality) ||
        qualities is! List ||
        qualities.isEmpty ||
        qualities.length > 32 ||
        qualities.any((value) => value is! String || !_qualityName.hasMatch(value)) ||
        qualities.toSet().length != qualities.length ||
        !qualities.contains(quality)) {
      throw const ApiChanged(_site, 'stream: unexpected quality list');
    }
    final rawCookies = data['cookies'];
    if (rawCookies is! List || rawCookies.length > maxCookies) throw const ApiChanged(_site, 'stream: cookies');
    final at = now ?? DateTime.now();
    final cookies = <NiconicoCookie>[];
    final keys = <(String, String)>{};
    var total = 0;
    for (final entry in rawCookies) {
      if (entry is! Map<String, dynamic>) throw const ApiChanged(_site, 'stream: cookie is not an object');
      final name = entry['name'];
      final value = entry['value'];
      final path = entry['path'];
      final domain = entry['domain'];
      final expires = entry['expires'];
      if (name is! String ||
          !_cookieName.hasMatch(name) ||
          name.startsWith('__Host-') ||
          value is! String ||
          !_cookieValue.hasMatch(value) ||
          value.contains(';') ||
          value.contains('"') ||
          value.contains(r'\') ||
          path is! String ||
          !_cookiePath.hasMatch(path) ||
          (domain != 'nicovideo.jp' && domain != '.nicovideo.jp') ||
          entry['secure'] != true ||
          (expires != null && expires is! String) ||
          !keys.add((path, name))) {
        throw ApiChanged(_site, 'stream: unexpected cookie ${name is String ? name : ''}');
      }
      final expiry = expires == null ? null : parseHttpDate(expires as String);
      if (expires != null && expiry == null) throw ApiChanged(_site, 'stream: cookie $name expires "$expires"');
      final size = uri.origin.length + name.length + value.length + path.length;
      total += size;
      if (size > maxCookieCharacters || total > maxGrantCharacters) {
        throw const ApiChanged(_site, 'stream: cookies too large');
      }
      if (expiry != null && !expiry.isAfter(at)) continue;
      cookies.add(NiconicoCookie(name: name, value: value, path: path, expires: expiry));
    }
    return NiconicoGrant._(uri, quality, List.unmodifiable(qualities.cast<String>()), cookies);
  }

  /// `seat.keepIntervalSec`: 1–300 seconds, else `ApiChanged`.
  static int seatInterval(Object? data) {
    final seconds = data is Map ? data['keepIntervalSec'] : null;
    if (seconds is! int || seconds < 1 || seconds > 300) throw ApiChanged(_site, 'seat: keepIntervalSec $seconds');
    return seconds;
  }

  /// The failure an `error` message reports, by `code` (3.x only knew it
  /// failed): no permission or a ticket needed is `NeedsLogin`, too many
  /// connections `RateLimited`, a rejected request `ApiChanged`, anything
  /// else `StreamUnavailable`.
  static SiteError seatError(Object? data) {
    final code = data is Map ? '${data['code']}' : 'unknown';
    return switch (code) {
      'NO_PERMISSION' || 'NOT_PLAYABLE' || 'TICKET_REQUIRED' => NeedsLogin(_site, 'seat error $code'),
      'TOO_MANY_CONNECTIONS' || 'CONNECT_ERROR' => RateLimited(_site, detail: 'seat error $code'),
      'INVALID_STREAM_QUALITY' || 'INVALID_MESSAGE' => ApiChanged(_site, 'seat error $code'),
      _ => StreamUnavailable(_site, 'seat error $code'),
    };
  }

  /// A `disconnect` message (the program ended, the seat was taken...):
  /// `StreamUnavailable` with its reason.
  static SiteError seatDisconnect(Object? data) =>
      StreamUnavailable(_site, 'seat disconnect ${data is Map ? data['reason'] : ''}'.trim());

  // Qualities -----------------------------------------------------------------

  /// The qualities of [programId] in the master at [source] (3.x's
  /// `NiconicoQuality.parse`): one per video variant, by its `RESOLUTION`
  /// and `BANDWIDTH`, highest first (height, width, then bandwidth). A
  /// variant without a resolution, two variants with the same pair, or a
  /// variant whose audio is ambiguous cannot be selected exactly, so the
  /// master is `ApiChanged` (3.x's schema failure) rather than offering a
  /// row that cannot play. The status is checked like the seat's media:
  /// 401/403 `RiskControl`, 404/410 `StreamUnavailable`, 429
  /// `RateLimited`, 5xx `NetworkFailure`, anything but 200 `ApiChanged`.
  static List<LivePlayQuality> qualities(
    String text, {
    required Uri source,
    required String programId,
    int status = 200,
  }) {
    switch (status) {
      case 200:
        break;
      case 401 || 403:
        throw RiskControl(_site, detail: 'master: HTTP $status');
      case 404 || 410:
        throw StreamUnavailable(_site, 'master: HTTP $status');
      case 429:
        throw const RateLimited(_site, detail: 'master: HTTP 429');
      case >= 500:
        throw NetworkFailure(_site, 'master: HTTP $status');
      default:
        throw ApiChanged(_site, 'master: HTTP $status');
    }
    final choices = <NiconicoQuality>[];
    try {
      final master = HlsMasterPlaylist.parse(source, text);
      final ids = <String>{};
      for (final variant in master.variants) {
        final resolution = variant.attributes['RESOLUTION'];
        if (resolution == null) throw const FormatException('Missing video resolution');
        final size = resolution.split('x').map(int.parse).toList();
        final quality = NiconicoQuality(
          programId: programId,
          width: size[0],
          height: size[1],
          bandwidth: int.parse(variant.attributes['BANDWIDTH']!),
        );
        if (!ids.add(quality.id)) throw const FormatException('Ambiguous quality selector');
        master.select(video: variant.uri);
        choices.add(quality);
      }
    } on FormatException catch (error) {
      throw ApiChanged(_site, 'master: ${error.message}');
    }
    choices.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      final byWidth = b.width.compareTo(a.width);
      return byWidth != 0 ? byWidth : b.bandwidth.compareTo(a.bandwidth);
    });
    return List.unmodifiable([
      for (final choice in choices) LivePlayQuality(quality: choice.label, id: choice.id, data: choice),
    ]);
  }

  // Helpers -------------------------------------------------------------------

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static final RegExp _httpDate = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  /// An RFC 1123 HTTP date (`Mon, 28 Sep 2026 18:41:00 GMT`) in UTC, or
  /// null.
  static DateTime? parseHttpDate(String text) {
    final match = _httpDate.firstMatch(text.trim());
    if (match == null) return null;
    final month = _months.indexOf(match.group(2)!) + 1;
    final [day, year, hour, minute, second] = [
      for (final group in [1, 3, 4, 5, 6]) int.parse(match.group(group)!),
    ];
    if (month == 0 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return null;
    final date = DateTime.utc(year, month, day, hour, minute, second);
    return date.day == day ? date : null;
  }

  static Map<String, String> _attributes(String text) => {
    for (final match in _tagAttribute.allMatches(text))
      match.group(1)!.toLowerCase(): match.group(2) ?? match.group(3) ?? match.group(4) ?? '',
  };

  /// 3.x's status mapping of pages and lists: 401/403/406 `RiskControl`
  /// (its "access"), 404 `NotFound` for a watch page and `ApiChanged` for a
  /// list endpoint (its "missing"), 429 `RateLimited`, anything else but 200
  /// (5xx, a redirect, which is not followed, another 4xx) `NetworkFailure`
  /// (its "service" and "transport").
  static void _status(int status, String what, {bool notFound = false}) {
    switch (status) {
      case 200:
        return;
      case 401 || 403 || 406:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw notFound ? NotFound(_site, '$what: HTTP 404') : ApiChanged(_site, '$what: HTTP 404');
      case 429:
        throw RateLimited(_site, detail: '$what: HTTP 429');
    }
    throw NetworkFailure(_site, '$what: HTTP $status');
  }

  static void _limit(String body, String what) {
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: over ${responseLimit ~/ 1024} KiB');
    }
  }

  static Map<String, dynamic> _json(String body, String what) {
    _limit(body, what);
    try {
      return _map(jsonDecode(body), what);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: not an object');
  }

  /// A string (may be empty).
  static String _string(Object? value, String what) {
    if (value is String) return value;
    throw ApiChanged(_site, '$what: not a string');
  }

  /// A non-blank string of at most 8192 characters.
  static String _text(Object? value, String what) {
    if (value is String && value.trim().isNotEmpty && value.length <= 8192) return value;
    throw ApiChanged(_site, 'list: $what missing');
  }

  static bool _boolean(Object? value) {
    if (value is bool) return value;
    throw const ApiChanged(_site, 'watch page: access flag is not a boolean');
  }

  /// Null, or an integer 0–2^53-1.
  static int? _count(Object? value, String what) {
    if (value == null) return null;
    if (value is int && value >= 0 && value <= 9007199254740991) return value;
    throw ApiChanged(_site, '$what: $value');
  }
}
