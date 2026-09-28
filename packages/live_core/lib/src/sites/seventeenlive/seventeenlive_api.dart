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

  /// In 3.x's order (enhanced, HD, H.264, standard); each quality's `data`
  /// is its `List<LivePlayLine>`.
  final List<LivePlayQuality> qualities;

  /// Why there is nothing to play: offline, a state 3.x did not know, or a
  /// live without a pull URL.
  final SiteError? unavailable;
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

  /// 3.x's zh.json `seventeen_directory_scope`, the directory notice's text.
  static const String directoryScope = '官网日本区公开推荐按原生游标加载，不代表全站目录；搜索覆盖官网当前直播窗口，精确房间号与官方直播间/主播主页链接继续支持，未开播昵称不在搜索结果中。';

  /// The quality names (3.x's zh.json `seventeen_quality_*`), in 3.x's
  /// order.
  static const Map<String, String> qualityNames = {'enhanced': '增强高清', 'hd': '高清', 'h264': 'H.264', 'standard': '标准'};

  /// The sort value of each quality (3.x's `_qualitySort`).
  static const Map<String, int> qualitySorts = {'enhanced': 400, 'hd': 300, 'h264': 200, 'standard': 100};

  /// The pull URL fields of each quality, in 3.x's order: every field of
  /// every provider is a line.
  static const Map<String, List<String>> qualityFields = {
    'enhanced': ['urlQualityEnhancedHD'],
    'hd': ['urlLowBitrateHD', 'webUrl', 'url'],
    'h264': ['url264'],
    'standard': ['urlLowQuality', 'webUrlLowQuality', 'urlHighQuality'],
  };

  /// The region of the recommendations (3.x asked for Japan only).
  static const String region = 'JP';

  /// Rows the website asks each section for (`count`).
  static const int sectionCount = 20;

  /// The last page `getDirectoryPage` replays to (3.x).
  static const int maxDirectoryPage = 20;

  /// The longest cursor 3.x sent or accepted.
  static const int maxCursorLength = 512;

  /// The longest keyword searched (3.x).
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
    );
  }

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
  /// the current and this broadcast's viewers while live.
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

  /// The query of the sections page after [cursor] (3.x: Japan, the
  /// website's hot tab, 20 a section; an empty cursor on page 1).
  static Map<String, String> sectionsQuery(String? cursor) => {
    'count': '$sectionCount',
    'typeTab': '2',
    'region': region,
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
  /// of [refreshRoom] with its playback ([SeventeenLiveRoomData]). A live
  /// room without a pull URL is entered (3.x failed the entry); its stream
  /// says why. Pull data 3.x could not read fails the entry, as in 3.x.
  static LiveRoom enteredRoom(String body, {required String roomId, int status = 200}) {
    final data = _room(body, roomId: roomId, status: status);
    final stream = _checked(data, roomId);
    final List<LivePlayQuality> offered;
    final SiteError? unavailable;
    switch (stream.status) {
      case LiveStatus.live:
        offered = qualities(data, roomId: roomId);
        unavailable = offered.isEmpty ? StreamUnavailable(_site, 'lives/$roomId: no pull URL') : null;
      case LiveStatus.offline:
        offered = const [];
        unavailable = StreamUnavailable(_site, 'lives/$roomId: offline');
      case _:
        offered = const [];
        unavailable = ApiChanged(_site, 'lives/$roomId: status ${data['status']}');
    }
    return _card(stream).copyWith(
      data: SeventeenLiveRoomData(roomId: roomId, userId: stream.userId, qualities: offered, unavailable: unavailable),
    );
  }

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities of a live `lives/<id>` answer (`_streams`): the
  /// providers of `pullURLsInfo.rtmpURLs` (else `rtmpUrls`), in their order
  /// (only the first one serves at a time: REG-17LIVE-002); for each quality
  /// of [qualityFields], every field of every provider that is a pull URL
  /// ([pullUrl]) is a line, each URL once. Named `<name> · FLV`, sorted as
  /// 3.x ([qualitySorts]). Each line carries [mediaHeaders], the FLV format,
  /// its CDN (`tencent`, `wansu`) and, for the H.264 transcode, the `avc`
  /// codec (the other qualities follow the broadcaster's encoder and may be
  /// FLV codec 12, HEVC: REG-17LIVE-001). No lease: the URLs are unsigned.
  ///
  /// As 3.x, providers that are not a list of at most 16 objects, or a URL
  /// field that is not text, are `ApiChanged`. Empty when nothing is
  /// offered.
  static List<LivePlayQuality> qualities(Map<String, dynamic> data, {required String roomId}) {
    final what = 'lives/$roomId';
    Object? providers;
    final pull = data['pullURLsInfo'];
    if (pull is Map) providers = pull['rtmpURLs'];
    providers ??= data['rtmpUrls'];
    if (providers == null) return const [];
    if (providers is! List || providers.length > 16) throw ApiChanged(_site, '$what: rtmpURLs is not a list of 16');
    final lines = <String, List<LivePlayLine>>{};
    final headers = mediaHeaders(roomId);
    for (final item in providers) {
      final provider = _map(item) ?? (throw ApiChanged(_site, '$what: provider $item'));
      for (final MapEntry(key: id, value: fields) in qualityFields.entries) {
        for (final field in fields) {
          final value = provider[field];
          if (value == null || value == '') continue;
          if (value is! String) throw ApiChanged(_site, '$what: $field is not text');
          final url = pullUrl(value);
          if (url == null) continue;
          final list = lines.putIfAbsent(id, () => []);
          final text = url.toString();
          if (list.any((line) => line.url == text)) continue;
          list.add(
            LivePlayLine(
              text,
              headers: headers,
              format: StreamFormat.flv,
              codec: id == 'h264' ? 'avc' : null,
              lineId: url.host.toLowerCase().split('-').first,
            ),
          );
        }
      }
    }
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
  /// whitespace, user info or fragment; kept as given (3.x played the
  /// Tencent CDN over http). Null otherwise.
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
    return uri;
  }

  /// The lines of [quality] (by its id) among [data]'s qualities, applied as
  /// asked; a quality the room does not offer is `StreamUnavailable`, and a
  /// room with nothing to play reports why.
  static LivePlayUrlResolution resolution(SeventeenLiveRoomData data, LivePlayQuality quality) {
    final offered = playQualities(data);
    final wanted = '${quality.selectionId}';
    final match = offered.where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (match == null) throw StreamUnavailable(_site, 'quality $wanted is not offered');
    return LivePlayUrlResolution.lines(match.data! as List<LivePlayLine>, appliedQualityData: match.selectionId);
  }

  /// [data]'s qualities, or why there are none.
  static List<LivePlayQuality> playQualities(SeventeenLiveRoomData data) {
    if (data.qualities.isNotEmpty) return data.qualities;
    throw data.unavailable ?? const StreamUnavailable(_site, 'no quality');
  }

  // Links ---------------------------------------------------------------------

  /// The room of a 17LIVE page (3.x's `SeventeenLiveLink.parse`): http(s) on
  /// `17.live` exactly (any case, any port), without user info; the path
  /// (empty segments ignored, words in any case) `/live/<id>`,
  /// `/<locale>/live/<id>`, `/profile/r/<id>` or `/<locale>/profile/r/<id>`,
  /// the locale two letters with an optional `-` suffix (`ja`,
  /// `zh-Hant`), the id a room id. A path that cannot be decoded is no link
  /// (3.x threw). Other hosts (`www.17.live`) are not rooms, as in 3.x.
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != '17.live') {
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
