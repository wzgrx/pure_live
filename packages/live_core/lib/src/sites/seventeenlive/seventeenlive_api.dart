import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = '17live';

/// What room entry keeps for playback (3.x kept its `SeventeenLiveRoom`
/// snapshot, streams included, in `data`): the qualities with their lines,
/// or why there is nothing to play.
@immutable
final class SeventeenLiveRoomData {
  /// Creates the data; [unavailable] is required when [qualities] is empty.
  new({required this.roomId, required this.userId, List<LivePlayQuality> qualities = const [], this.unavailable})
    : qualities = List.unmodifiable(qualities),
      assert(qualities.isNotEmpty || unavailable != null, 'an empty playback needs its reason');

  /// `liveStreamID`: the room the playback belongs to.
  final String roomId;

  /// `userID`: the broadcaster's UUID (the name of the pull streams).
  final String userId;

  /// Best first (原画, enhanced, HD, H.264: [SeventeenLiveApi.qualityFields]);
  /// the order shown is [SeventeenLiveApi.playQualities]'s. Each quality's
  /// `data` is its `List<LivePlayLine>`.
  final List<LivePlayQuality> qualities;

  /// Why there is nothing to play: offline, a state 3.x did not know, a
  /// locked (restricted) live, or a live without a readable pull URL.
  final SiteError? unavailable;
}

/// What the danmaku module needs for a room (M5, 33-4): the room id, which
/// is also the name of its Ably chat channel (the website subscribes to
/// `subscribeChatRoom(roomID)`). The token is anonymous
/// (`POST api-dsa.17app.co/api/v1/messenger/auth`) and asked by the chat
/// itself, so room entry hands the channel over without a request. The
/// channel is the broadcaster's and does not change between broadcasts.
@immutable
final class SeventeenLiveDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId});

  /// `liveStreamID`, the Ably channel name.
  final String roomId;

  @override
  bool operator ==(Object other) => other is SeventeenLiveDanmakuArgs && other.roomId == roomId;

  @override
  int get hashCode => roomId.hashCode;

  @override
  String toString() => 'SeventeenLiveDanmakuArgs($roomId)';
}

/// One page of the recommendation sections (`/api/v1/sections`).
@immutable
final class SeventeenLiveSectionsPage {
  /// Creates the page.
  new({required List<LiveRoom> rooms, this.nextCursor}) : rooms = List.unmodifiable(rooms);

  /// Live cards, one per room.
  final List<LiveRoom> rooms;

  /// The opaque cursor of the next page; null on the last.
  final String? nextCursor;

  /// Whether another page exists (3.x: a cursor).
  bool get hasMore => nextCursor != null;
}

/// A stream object as 3.x's `_room` read it (a section grid, a search row or
/// the `lives/<id>` answer).
final class _Stream {
  new({
    required this.roomId,
    required this.userId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.bio,
    required this.followers,
    required this.online,
    required this.total,
    required this.audioOnly,
    required this.status,
    required this.startedAt,
    required this.restriction,
  });

  final String roomId;
  final String userId;
  final String nick;
  final String title;
  final String avatar;
  final String cover;
  final String bio;
  final int? followers;
  final int? online;
  final int? total;
  final bool audioOnly;
  final LiveStatus status;

  /// `beginTime` while live (33-7).
  final DateTime? startedAt;

  /// From `premiumContent` while live; null otherwise or unreadable.
  final LiveRestriction? restriction;
}

/// A stream object 3.x refused (its `schema` and `identity` failures).
final class _Refused implements Exception {
  const new(this.reason);

  final String reason;
}

/// Pure parsing of 17LIVE responses (3.x's `SeventeenLiveApi`,
/// `SeventeenLiveLink` and the card rules of `SeventeenLiveSite`). Each
/// function takes the response text and status and returns 3.x's models or
/// throws a `SiteError`.
///
/// Anonymous and public: no cookie, no signature. A room is the
/// broadcaster's fixed `liveStreamID` (the owner's `userInfo.roomID`), kept
/// as asked for; the broadcaster's `userID` is a UUID and names the pull
/// streams. The pull URLs carry no signature and do not expire.
///
/// M4.U (docs/specs/UPGRADES.md 33-1 to 33-7): the Japan, Taiwan and Hong Kong
/// recommendations are the areas of one category; 3.x's 标准 is 原画 and
/// comes first, and "优先 H.264" puts the H.264 transcode before it; pull
/// URLs are https; keywords with a colon are searched and long ones cut;
/// `www.17.live` links are rooms; a live room has its `beginTime` and its
/// `premiumContent` lock (a locked live is live, marked and not played).
abstract final class SeventeenLiveApi {
  /// The API host.
  static const String apiHost = 'api-dsa.17app.co';

  /// The website.
  static const String origin = 'https://17.live';

  /// 3.x's desktop Chrome UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// Display name (3.x's `SeventeenLiveSite.name`, zh.json `site_17live`).
  static const String displayName = '17LIVE';

  /// The largest answer read (3.x's `responseLimit`, 4 MiB).
  static const int responseLimit = 4 * 1024 * 1024;

  /// The notice of every room (3.x's zh.json `seventeen_age_notice`).
  static const String ageNotice = '17LIVE 要求观看者年满 18 周岁。';

  /// The area of an audio-only broadcast (3.x's zh.json
  /// `seventeen_audio_room`).
  static const String audioRoom = '音频直播';

  /// The directory notice's text (key `seventeen_directory_scope`), in words
  /// a viewer understands (unified rule "说明文字"; 3.x's zh.json text was a
  /// developer note), covering the regions of 33-1. The interface's
  /// translations are M13's.
  static const String directoryScope =
      '推荐和分区里是 17LIVE 官网日本、台湾、香港区首页推荐的直播，不是全部直播。搜索只能找到正在直播的主播；也可以输入房间号，或粘贴 17LIVE 的直播间或主页链接。';

  /// The id of 原画 (33-2): the broadcaster's own stream, 3.x's `standard`.
  static const String sourceQualityId = 'source';

  /// The id of the H.264 transcode, the one quality that is always AVC.
  static const String h264QualityId = 'h264';

  /// The quality names (3.x's zh.json `seventeen_quality_*`; 33-2: 3.x's
  /// 标准 is 原画), best first. Each is shown as `<name> · FLV`, as 3.x did.
  static const Map<String, String> qualityNames = {
    sourceQualityId: '原画',
    'enhanced': '增强高清',
    'hd': '高清',
    h264QualityId: 'H.264',
  };

  /// The sort value of each quality: 3.x's `_qualitySort`, 原画 now the
  /// highest (33-2; 3.x's 标准 was 100, the lowest).
  static const Map<String, int> qualitySorts = {sourceQualityId: 500, 'enhanced': 400, 'hd': 300, h264QualityId: 200};

  /// The pull URL fields of each quality, best first (33-2; 3.x's order was
  /// enhanced, HD, H.264, standard): every field of every provider is a
  /// line. The source fields are the broadcaster's stream as pushed (no
  /// suffix; archived spec §5).
  static const Map<String, List<String>> qualityFields = {
    sourceQualityId: ['urlLowQuality', 'webUrlLowQuality', 'urlHighQuality'],
    'enhanced': ['urlQualityEnhancedHD'],
    'hd': ['urlLowBitrateHD', 'webUrl', 'url'],
    h264QualityId: ['url264'],
  };

  /// 3.x's quality ids whose quality has a new id (33-2), for M9 to migrate
  /// a stored quality once: `standard` (标准 · FLV) is `source` (原画 ·
  /// FLV). The other ids are unchanged.
  static const Map<String, String> legacyQualityIds = {'standard': sourceQualityId};

  /// The quality id for [id] as 3.x stored it ([legacyQualityIds], any
  /// case); any other id is kept, trimmed.
  static String qualityIdFromLegacy(String id) => legacyQualityIds[id.trim().toLowerCase()] ?? id.trim();

  /// The region of the recommendations (3.x asked for Japan only).
  static const String region = 'JP';

  /// `id` of the one category (33-1).
  static const String categoryId = 'region';

  /// Name of the one category (33-1); the interface's translations are
  /// M13's.
  static const String categoryName = '地区';

  /// The regions of the website's recommendation sections (33-1; the
  /// archived v4 measured these three: `US` only mixes Japan and Hong
  /// Kong), by `region` code, in order. The names are the interface's
  /// defaults (M13 translates them).
  static const Map<String, String> regions = {'JP': '日本', 'TW': '台湾', 'HK': '香港'};

  /// The areas of [category], one per region ([regions]): `areaId` is the
  /// `region` code sent.
  static const List<LiveArea> areas = [
    LiveArea(platform: _site, areaType: categoryId, typeName: categoryName, areaId: 'JP', areaName: '日本'),
    LiveArea(platform: _site, areaType: categoryId, typeName: categoryName, areaId: 'TW', areaName: '台湾'),
    LiveArea(platform: _site, areaType: categoryId, typeName: categoryName, areaId: 'HK', areaName: '香港'),
  ];

  /// The one category: the regions (33-1; 3.x had no catalog).
  static final LiveCategory category = LiveCategory(id: categoryId, name: categoryName, children: areas);

  /// The `region` code of [area]: [region] for null (the recommendations),
  /// else the area's id (any case) when it is one of [regions]. An area of
  /// another platform, or another id, is a caller error (`ArgumentError`).
  static String regionOf(LiveArea? area) {
    if (area == null) return region;
    final code = area.areaId.trim().toUpperCase();
    if (area.platform.trim().toLowerCase() != _site || !regions.containsKey(code)) {
      throw ArgumentError.value(area, 'category', 'not a 17LIVE region');
    }
    return code;
  }

  /// Rows the website asks each section for (`count`).
  static const int sectionCount = 20;

  /// The last page `getDirectoryPage` replays to (3.x).
  static const int maxDirectoryPage = 20;

  /// The longest cursor 3.x sent or accepted.
  static const int maxCursorLength = 512;

  /// The longest keyword sent, in UTF-16 code units (3.x refused a longer
  /// one; 33-5 cuts it, as the archived v4 did).
  static const int maxKeywordLength = 100;

  /// Sections without current broadcasts (3.x skipped these three).
  static const Set<String> skippedSections = {'TopBanner', 'ArchiveVideo', 'Vod'};

  static final RegExp _roomId = RegExp(r'^[1-9][0-9]{0,11}$');
  static final RegExp _control = RegExp(r'[\x00-\x1f]');
  static final RegExp _locale = RegExp(r'^[a-z]{2}(?:-[a-z]{2,4})?$', caseSensitive: false);

  /// [raw] trimmed when it is a room id (1 to 12 digits, no leading zero);
  /// else null (3.x's `normalizeRoomId`).
  static String? normalizeRoomId(String raw) {
    final roomId = raw.trim();
    return _roomId.hasMatch(roomId) ? roomId : null;
  }

  /// The web page of [roomId] (3.x's `SeventeenLiveLink.url`, the room's
  /// `link` and the Referer of its requests).
  static String roomUrl(String roomId) => '$origin/en/live/$roomId';

  /// 3.x's headers of the room answer (`lives/<id>`).
  static Map<String, String> requestHeaders(String roomId) => {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': origin,
    'referer': roomUrl(roomId),
  };

  /// 3.x's headers of the sections and the search.
  static const Map<String, String> catalogHeaders = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'ja-JP,ja;q=0.9,en;q=0.8',
    'origin': origin,
    'referer': '$origin/',
  };

  /// The pull streams' request headers (3.x's `mediaHeaders`, which its
  /// `PlaybackHeaderResolver` sent for 17LIVE): the pull hosts refuse a
  /// request without a Referer (REG-17LIVE-003).
  static Map<String, String> mediaHeaders(String roomId) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': roomUrl(roomId),
  };

  // Answers -------------------------------------------------------------------

  /// The failure of an answer that is not a 200, as 3.x's `_fetch` classed
  /// it, except where the platform showed otherwise: an unknown room is
  /// HTTP 520 `stream not found` (REG-17LIVE-004; 3.x said "service") and
  /// HTTP 420 `errorCode 7` is a refused parameter (3.x took it for
  /// throttling). 400 is a shape error, 401/403 refused, 404 missing, 429
  /// throttled, 5xx and anything else (3xx included: redirects are not
  /// followed) a network failure. Null for 200.
  static SiteError? statusError(int status, String body, String what) {
    if (status == 200) return null;
    if (_errorMessage(body) == 'stream not found') return NotFound(_site, '$what: HTTP $status stream not found');
    return switch (status) {
      400 || 420 => ApiChanged(_site, '$what: HTTP $status'),
      401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
      404 => NotFound(_site, '$what: HTTP 404'),
      429 => RateLimited(_site, detail: '$what: HTTP 429'),
      _ => NetworkFailure(_site, '$what: HTTP $status'),
    };
  }

  static String? _errorMessage(String body) {
    if (body.length > 65536) return null;
    try {
      final data = jsonDecode(body);
      final message = data is Map ? data['errorMessage'] : null;
      return message is String ? message.trim() : null;
    } on FormatException {
      return null;
    }
  }

  /// The decoded JSON of a 200 answer, or the failure.
  static Object? decode(String body, {required String what, int status = 200}) {
    if (statusError(status, body, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  // Values (3.x's helpers) ----------------------------------------------------

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : null;

  static int? _integer(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '');

  static int? _positiveInt(Object? value) => switch (_integer(value)) {
    final int number when number > 0 => number,
    _ => null,
  };

  /// 3.x's `_optionalNonNegativeInt`: null for absent; [invalid] for a value
  /// that is not a count.
  static int? _count(Object? value, {required int? Function(String reason) invalid}) {
    if (value == null || value == '') return null;
    final count = _integer(value);
    return count != null && count >= 0 ? count : invalid('count $value');
  }

  /// 3.x's `_optionalText`: absent is empty; [invalid] for a value that is
  /// not text.
  static String _text(Object? value, {required String Function(String reason) invalid}) {
    if (value == null || value == '') return '';
    if (value is! String || value.length > 131072) return invalid('text $value');
    return value.trim();
  }

  /// 3.x's `_text`: a required non-blank string, or null.
  static String? _requiredText(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) return null;
    return value.trim();
  }

  /// An image as 3.x accepted it: an http(s) URL on `cdn.17app.co` or
  /// `assets-17app.akamaized.net` without user info or fragment, or a bare
  /// file name there; always https. Empty otherwise.
  static String image(Object? value) {
    if (value is! String || value.isEmpty || value.length > 8192) return '';
    var uri = Uri.tryParse(value);
    if (uri != null && !uri.hasScheme) {
      if (value.contains('..') || !RegExp(r'^[a-zA-Z0-9._/?=&-]+$').hasMatch(value)) return '';
      uri = Uri.https('cdn.17app.co', value.startsWith('/') ? value : '/$value');
    }
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !const {'cdn.17app.co', 'assets-17app.akamaized.net'}.contains(host)) {
      return '';
    }
    return uri.replace(scheme: 'https').toString();
  }

  // Stream objects ------------------------------------------------------------

  /// A stream object by 3.x's rules (`_room`). Its identity is always
  /// checked: `liveStreamID` is [requested], the owner's `userInfo.roomID`
  /// (required with [ownerRequired]) names the same room, and `userID` is
  /// the owner's. With [strict] (list rows, which 3.x dropped for any of
  /// these) a field that is not what 3.x expected refuses the object too;
  /// without it (a room answer, which 3.x failed) the field is left empty.
  static _Stream _stream(
    Map<String, dynamic> data, {
    required String requested,
    required bool ownerRequired,
    required bool strict,
  }) {
    Never refuse(String reason) => throw _Refused(reason);
    final roomId = _positiveInt(data['liveStreamID'])?.toString() ?? refuse('liveStreamID ${data['liveStreamID']}');
    final user = _map(data['userInfo']) ?? refuse('no userInfo');
    final rawOwner = user['roomID'];
    final owner = rawOwner == null ? null : _positiveInt(rawOwner)?.toString() ?? refuse('roomID $rawOwner');
    if (roomId != requested || (ownerRequired && owner != requested) || (owner != null && owner != requested)) {
      refuse('room $roomId (owner $owner) for $requested');
    }
    final userId = _requiredText(data['userID']) ?? refuse('userID ${data['userID']}');
    if (_requiredText(user['userID']) != userId) refuse('userInfo.userID ${user['userID']} for $userId');
    String lenient(String reason) => strict ? refuse(reason) : '';
    int? noCount(String reason) => strict ? refuse(reason) : null;
    final status = switch (_integer(data['status'])) {
      2 => LiveStatus.live,
      0 => LiveStatus.offline,
      _ => LiveStatus.unknown,
    };
    var nick = '';
    for (final value in [user['displayName'], user['openID']]) {
      nick = _text(value, invalid: lenient);
      if (nick.isNotEmpty) break;
    }
    if (nick.isEmpty && strict) refuse('no displayName or openID');
    final title = _text(data['caption'], invalid: lenient);
    final live = status == LiveStatus.live;
    return _Stream(
      roomId: roomId,
      userId: userId,
      nick: nick,
      title: title.isEmpty ? nick : title,
      avatar: image(user['picture']),
      cover: image(data['coverPhoto'] ?? data['thumbnail']),
      bio: _text(user['bio'], invalid: lenient),
      followers: _count(user['followerCount'], invalid: noCount),
      online: live ? _count(data['liveViewerCount'], invalid: noCount) : null,
      total: live ? _count(data['viewerCount'], invalid: noCount) : null,
      audioOnly: _integer(data['audioOnly']) == 1,
      status: status,
      // 3.x read neither: one that cannot be read is left out, never a
      // reason to drop the row (33-7, unified rule on restrictions).
      startedAt: live ? startTime(data['beginTime']) : null,
      restriction: live ? restrictionOf(data['premiumContent']) : null,
    );
  }

  /// `beginTime` (Unix seconds; the room answer and search rows have it,
  /// section rows do not) as a UTC time (33-7); null when missing, not an
  /// integer, or outside 2000–2100 (an offline room's is the last
  /// broadcast's and is not read).
  static DateTime? startTime(Object? value) {
    final seconds = value is int ? value : null;
    if (seconds == null || seconds < 946684800 || seconds > 4102444800) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// A live's restriction from its `premiumContent`, by the website's rule
  /// (`isLocked`: a `premiumType` other than 0 that `paymentInfo.paid` does
  /// not unlock; the anonymous viewer never paid): `premiumType` 1 (PAID, a
  /// premium live) is [LiveRestriction.paid], 2 (ARMY, for the
  /// broadcaster's army members) [LiveRestriction.subscribersOnly], any
  /// other (3, NEW_USER, and later ones) [LiveRestriction.unplayable]. No
  /// `premiumContent` (the room answer leaves it out, search rows write
  /// null) or type 0 is [LiveRestriction.none]; one that is not an object
  /// cannot be read (null).
  static LiveRestriction? restrictionOf(Object? premium) {
    if (premium == null) return LiveRestriction.none;
    final content = _map(premium);
    if (content == null) return null;
    final type = _integer(content['premiumType']) ?? 0;
    if (type == 0 || _map(content['paymentInfo'])?['paid'] == true) return LiveRestriction.none;
    return switch (type) {
      1 => LiveRestriction.paid,
      2 => LiveRestriction.subscribersOnly,
      _ => LiveRestriction.unplayable,
    };
  }

  /// Why a live with [restriction] is not played: the website locks it for
  /// this (anonymous) viewer even when the answer carries pull URLs (it did
  /// on 2026-09-28, sample S04-live-army); 3.x played it.
  static StreamUnavailable lockedLive(String roomId, LiveRestriction restriction) =>
      StreamUnavailable(_site, switch (restriction) {
        LiveRestriction.paid => '$roomId: a premium live, for viewers who paid',
        LiveRestriction.subscribersOnly => "$roomId: a live for the broadcaster's army members only",
        _ => '$roomId: a locked live (${restriction.name})',
      });

  /// A list row (a section grid's `stream`, a search result) as 3.x kept
  /// it: a live object that passes 3.x's rules, else null.
  static _Stream? _liveRow(Object? value, {required bool ownerRequired}) {
    final data = _map(value);
    if (data == null) return null;
    final roomId = _positiveInt(data['liveStreamID'])?.toString();
    if (roomId == null) return null;
    try {
      final stream = _stream(data, requested: roomId, ownerRequired: ownerRequired, strict: true);
      return stream.status == LiveStatus.live ? stream : null;
    } on _Refused {
      return null;
    }
  }

  /// 3.x's card (`_card`): the age notice on every room, the audio area,
  /// the current and this broadcast's viewers while live; and, while live,
  /// the start time (33-7) and the restriction (a locked live stays live).
  static LiveRoom _card(_Stream stream) => LiveRoom(
    platform: _site,
    roomId: stream.roomId,
    userId: stream.userId,
    nick: stream.nick,
    title: stream.title,
    avatar: stream.avatar,
    cover: stream.cover,
    area: stream.audioOnly ? audioRoom : '',
    followers: stream.followers?.toString() ?? '',
    introduction: stream.bio,
    link: roomUrl(stream.roomId),
    liveStatus: stream.status,
    startedAt: stream.startedAt,
    restriction: stream.restriction,
    watching: '',
    onlineViewers: stream.online?.toString() ?? '',
    totalViewers: stream.total?.toString() ?? '',
    audienceMetricType: AudienceMetricType.onlineViewers,
    notice: ageNotice,
  );

  // Directory -----------------------------------------------------------------

  /// Checks a directory cursor as 3.x did before sending it: non-empty, at
  /// most [maxCursorLength] characters, no control character; anything else
  /// is a caller error.
  static void checkCursor(String? cursor) {
    if (cursor == null) return;
    if (cursor.isEmpty || cursor.length > maxCursorLength || cursor.contains(_control)) {
      throw ArgumentError.value(cursor, 'cursor', 'not a 17LIVE directory cursor');
    }
  }

  /// The query of the sections page after [cursor] (3.x: the website's hot
  /// tab, 20 a section; an empty cursor on page 1) of [regionCode]: Japan
  /// for the recommendations, as 3.x, or one of [regions] (33-1).
  static Map<String, String> sectionsQuery(String? cursor, {String regionCode = region}) => {
    'count': '$sectionCount',
    'typeTab': '2',
    'region': regionCode,
    'cursor': cursor ?? '',
  };

  /// A sections page fetched with [sectionsQuery] of [cursor].
  ///
  /// As 3.x: banner and archive sections ([skippedSections]) are skipped,
  /// a row is a card only when it is live and passes 3.x's rules (the rows
  /// carry no owner `roomID`), a room appears once, and the next cursor is
  /// the answer's unless it is empty or repeats [cursor]. A cursor that is
  /// not text, too long or has control characters is `ApiChanged`.
  ///
  /// Unlike 3.x, a section or grid that is not an object (or grids that are
  /// not a list) is skipped instead of failing the page.
  static SeventeenLiveSectionsPage sectionsPage(String body, {String? cursor, int status = 200}) {
    const what = 'sections';
    final data =
        _map(decode(body, what: what, status: status)) ?? (throw const ApiChanged(_site, '$what: not an object'));
    final sections = data['sections'];
    if (sections is! List) throw const ApiChanged(_site, '$what: no sections list');
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final item in sections) {
      final section = _map(item);
      if (section == null || skippedSections.contains(section['id'])) continue;
      final grids = section['grids'] ?? const <Object?>[];
      if (grids is! List) continue;
      for (final grid in grids) {
        final stream = _map(grid)?['stream'];
        if (stream == null) continue;
        final row = _liveRow(stream, ownerRequired: false);
        if (row != null && seen.add(row.roomId)) rooms.add(_card(row));
      }
    }
    final raw = data['cursor'];
    if (raw != null && raw is! String) throw ApiChanged(_site, '$what: cursor $raw');
    final next = raw is String && raw.isNotEmpty && raw != cursor ? raw : null;
    if (next != null && (next.length > maxCursorLength || next.contains(_control))) {
      throw const ApiChanged(_site, '$what: cursor too long or with control characters');
    }
    return SeventeenLiveSectionsPage(rooms: rooms, nextCursor: next);
  }

  // Search --------------------------------------------------------------------

  static final RegExp _url = RegExp('^[a-z][a-z0-9+.-]*://', caseSensitive: false);

  /// Whether [text] is a web address (`<scheme>://…`), which the search
  /// does not send as a keyword. Unlike 3.x (anything with a URI scheme),
  /// `Re:Zero` and other keywords with a colon are keywords (33-5).
  static bool isUrl(String text) => _url.hasMatch(text.trim());

  /// The keyword sent for [keyword]: trimmed and cut to [maxKeywordLength]
  /// UTF-16 code units (3.x's measure), never inside a surrogate pair, then
  /// trimmed again (33-5; 3.x found nothing for a longer one). Empty when
  /// there is nothing to search for.
  static String searchKeyword(String keyword) {
    var text = keyword.trim();
    if (text.length > maxKeywordLength) {
      var end = maxKeywordLength;
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) end--;
      text = text.substring(0, end).trim();
    }
    return text;
  }

  /// `liveStreams/search` results as cards: current broadcasts only, a room
  /// once; as 3.x, a row must name its owner's `roomID` and pass 3.x's
  /// rules, else it is skipped. The answer is a list (else `ApiChanged`).
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    const what = 'liveStreams/search';
    final data = decode(body, what: what, status: status);
    if (data is! List) throw const ApiChanged(_site, '$what: not a list');
    final seen = <String>{};
    return List.unmodifiable([
      for (final item in data)
        if (_liveRow(item, ownerRequired: true) case final row? when seen.add(row.roomId)) _card(row),
    ]);
  }

  // Rooms ---------------------------------------------------------------------

  static Map<String, dynamic> _room(String body, {required String roomId, required int status}) {
    final what = 'lives/$roomId';
    return _map(decode(body, what: what, status: status)) ?? (throw ApiChanged(_site, '$what: not an object'));
  }

  static _Stream _checked(Map<String, dynamic> data, String roomId) {
    try {
      return _stream(data, requested: roomId, ownerRequired: true, strict: false);
    } on _Refused catch (refused) {
      throw ApiChanged(_site, 'lives/$roomId: ${refused.reason}');
    }
  }

  /// The room [roomId] from `lives/<id>` without its streams (a follow
  /// refresh, a search by room): 3.x's card. The answer must be this room
  /// with its owner's `roomID` and `userID` (else `ApiChanged`); a status
  /// other than live (2) or offline (0) is an unknown state, as in 3.x.
  /// Unlike 3.x, a field that is not what 3.x expected (a blank name, a
  /// negative count) is left empty instead of failing the room.
  static LiveRoom refreshRoom(String body, {required String roomId, int status = 200}) =>
      _card(_checked(_room(body, roomId: roomId, status: status), roomId));

  /// The room [roomId] from `lives/<id>` as room entry reads it: the card
  /// of [refreshRoom] with its playback ([SeventeenLiveRoomData]) and the
  /// danmaku channel ([SeventeenLiveDanmakuArgs], 33-4). A room that cannot
  /// be played is entered; its stream says why: offline, a state 3.x did
  /// not know, a locked live ([lockedLive]; its pull URLs are not read), a
  /// live without a pull URL (3.x failed the entry), or pull data that
  /// cannot be read at all (`ApiChanged`; 3.x failed the entry).
  static LiveRoom enteredRoom(String body, {required String roomId, int status = 200}) {
    final data = _room(body, roomId: roomId, status: status);
    final stream = _checked(data, roomId);
    final what = 'lives/$roomId';
    var offered = const <LivePlayQuality>[];
    final SiteError? unavailable;
    switch (stream.status) {
      case LiveStatus.live when (stream.restriction ?? LiveRestriction.none) != LiveRestriction.none:
        unavailable = lockedLive(what, stream.restriction!);
      case LiveStatus.live:
        final skipped = <String>[];
        offered = qualities(data, roomId: roomId, skipped: skipped);
        unavailable = offered.isNotEmpty
            ? null
            : skipped.isEmpty
            ? StreamUnavailable(_site, '$what: no pull URL')
            : ApiChanged(_site, '$what: no readable pull URL (${skipped.join('; ')})');
      case LiveStatus.offline:
        unavailable = StreamUnavailable(_site, '$what: offline');
      case _:
        unavailable = ApiChanged(_site, '$what: status ${data['status']}');
    }
    return _card(stream).copyWith(
      data: SeventeenLiveRoomData(roomId: roomId, userId: stream.userId, qualities: offered, unavailable: unavailable),
      danmakuData: SeventeenLiveDanmakuArgs(roomId: roomId),
    );
  }

  // Streams -------------------------------------------------------------------

  /// The largest number of providers read (3.x refused more).
  static const int maxProviders = 16;

  /// CDNs (line ids) that serve no H.264 transcode: on 2026-10-08 every
  /// room served by Wansu (provider 5, AVC sources) answered its `url264`
  /// with 404 or no data, while Tencent's (provider 17) served (E03.18).
  static const Set<String> untranscodedCdns = {'wansu'};

  /// The qualities of a live `lives/<id>` answer (3.x's `_streams`): the
  /// providers of `pullURLsInfo.rtmpURLs` (else `rtmpUrls`), in their order
  /// (only the first one serves at a time: REG-17LIVE-002); for each quality
  /// of [qualityFields], best first, every field of every provider that is
  /// a pull URL ([pullUrl], https) is a line, each URL once. Named
  /// `<name> · FLV` (33-2: 原画 for 3.x's 标准), sorted by [qualitySorts].
  /// Each line carries [mediaHeaders], the FLV format, its CDN (`tencent`,
  /// `wansu`) and, for the H.264 transcode, the `avc` codec (the other
  /// qualities follow the broadcaster's encoder and may be FLV codec 12,
  /// HEVC: REG-17LIVE-001). No lease: the URLs are unsigned.
  ///
  /// Unlike 3.x (unified rule "容错"), a provider that is not an object, a
  /// URL field that is not text, providers beyond [maxProviders] and
  /// providers that are not a list only lose themselves; each is noted in
  /// [skipped]. Empty when nothing is offered.
  ///
  /// The H.264 transcode is offered only when the first CDN (the one
  /// serving) is not one of [untranscodedCdns], and never read from one of
  /// them (E03.18): 3.x listed it from every CDN, and with "优先 H.264" on
  /// a Wansu room opened on a quality nothing serves.
  static List<LivePlayQuality> qualities(Map<String, dynamic> data, {required String roomId, List<String>? skipped}) {
    void skip(String reason) => skipped?.add(reason);
    Object? providers;
    final pull = data['pullURLsInfo'];
    if (pull is Map) providers = pull['rtmpURLs'];
    providers ??= data['rtmpUrls'];
    if (providers == null) return const [];
    if (providers is! List) {
      skip('rtmpURLs is not a list');
      return const [];
    }
    if (providers.length > maxProviders) skip('${providers.length - maxProviders} providers over $maxProviders');
    final lines = <String, List<LivePlayLine>>{};
    final headers = mediaHeaders(roomId);
    String? firstCdn;
    for (final (index, item) in providers.take(maxProviders).indexed) {
      final provider = _map(item);
      if (provider == null) {
        skip('provider $index is not an object');
        continue;
      }
      for (final MapEntry(key: id, value: fields) in qualityFields.entries) {
        for (final field in fields) {
          final value = provider[field];
          if (value == null || value == '') continue;
          if (value is! String) {
            skip('provider $index: $field is not text');
            continue;
          }
          final url = pullUrl(value);
          if (url == null) continue;
          final cdn = url.host.toLowerCase().split('-').first;
          firstCdn ??= cdn;
          if (id == h264QualityId && untranscodedCdns.contains(cdn)) continue;
          final list = lines.putIfAbsent(id, () => []);
          final text = url.toString();
          if (list.any((line) => line.url == text)) continue;
          list.add(
            LivePlayLine(
              text,
              headers: headers,
              format: StreamFormat.flv,
              codec: id == h264QualityId ? 'avc' : null,
              lineId: cdn,
            ),
          );
        }
      }
    }
    if (untranscodedCdns.contains(firstCdn)) lines.remove(h264QualityId);
    return List.unmodifiable([
      for (final id in qualityFields.keys)
        if (lines[id] case final list?)
          LivePlayQuality(
            quality: '${qualityNames[id]} · FLV',
            id: id,
            sort: qualitySorts[id]!,
            data: List<LivePlayLine>.unmodifiable(list),
          ),
    ]);
  }

  /// A pull URL as 3.x accepted it (`_mediaUri`): http(s) on a
  /// `*.17app.co` host containing `pull-rtmp`, an `.flv` path, without
  /// whitespace, user info or fragment. Always https (33-3; 3.x played the
  /// Tencent CDN over http, which serves https too): an http URL is
  /// upgraded, except one with an explicit port other than 80, kept as
  /// given since its https port is unknown. Null otherwise.
  static Uri? pullUrl(String raw) {
    if (raw.isEmpty || raw.length > 65536 || raw.contains(RegExp(r'[\s\x00-\x1f]'))) return null;
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !host.endsWith('.17app.co') ||
        !host.contains('pull-rtmp') ||
        !uri.path.toLowerCase().endsWith('.flv')) {
      return null;
    }
    if (uri.scheme == 'https' || (uri.hasPort && uri.port != 80)) return uri;
    return Uri(scheme: 'https', host: uri.host, path: uri.path, query: uri.hasQuery ? uri.query : null);
  }

  /// The lines of [quality] (by its id; 3.x's `standard` is read through
  /// [qualityIdFromLegacy]) among [data]'s qualities, applied as the
  /// current id; a quality the room does not offer is `StreamUnavailable`,
  /// and a room with nothing to play reports why.
  static LivePlayUrlResolution resolution(SeventeenLiveRoomData data, LivePlayQuality quality) {
    final offered = playQualities(data);
    final wanted = qualityIdFromLegacy('${quality.selectionId}');
    final match = offered.where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (match == null) throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    return LivePlayUrlResolution.lines(match.data! as List<LivePlayLine>, appliedQualityData: match.selectionId);
  }

  /// [data]'s qualities in the order shown, or why there are none. With
  /// [preferH264] ("优先 H.264", on by default; 33-2 as 22-3) the H.264
  /// transcode comes first, so it is the default (the others may be HEVC:
  /// REG-17LIVE-001), then 原画 and the rest best first; off, best first
  /// (原画, enhanced, HD, H.264).
  static List<LivePlayQuality> playQualities(SeventeenLiveRoomData data, {bool preferH264 = true}) {
    final offered = data.qualities;
    if (offered.isEmpty) throw data.unavailable ?? const StreamUnavailable(_site, 'no quality');
    if (!preferH264) return offered;
    return List.unmodifiable([
      ...offered.where((quality) => quality.id == h264QualityId),
      ...offered.where((quality) => quality.id != h264QualityId),
    ]);
  }

  // Links ---------------------------------------------------------------------

  /// The hosts of the website: `www.17.live` redirects to `17.live` (33-6;
  /// 3.x knew only `17.live`).
  static const Set<String> webHosts = {'17.live', 'www.17.live'};

  /// The room of a 17LIVE page (3.x's `SeventeenLiveLink.parse`): http(s) on
  /// one of [webHosts] exactly (any case, any port), without user info; the
  /// path (empty segments ignored, words in any case) `/live/<id>`,
  /// `/<locale>/live/<id>`, `/profile/r/<id>` or `/<locale>/profile/r/<id>`,
  /// the locale two letters with an optional `-` suffix (`ja`,
  /// `zh-Hant`), the id a room id. A path that cannot be decoded is no link
  /// (3.x threw). Other hosts are not rooms.
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        !webHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    bool word(int index, String value) => segments[index].toLowerCase() == value;
    final id = switch (segments.length) {
      2 when word(0, 'live') => segments[1],
      3 when _locale.hasMatch(segments[0]) && word(1, 'live') => segments[2],
      3 when word(0, 'profile') && word(1, 'r') => segments[2],
      4 when _locale.hasMatch(segments[0]) && word(1, 'profile') && word(2, 'r') => segments[3],
      _ => null,
    };
    return id == null ? null : normalizeRoomId(id);
  }
}
