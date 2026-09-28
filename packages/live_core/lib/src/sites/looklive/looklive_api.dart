import 'dart:convert';

import 'package:live_core/src/aes.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'looklive';

/// Which list a room belongs to (3.x's `LookLiveKind`): `liveType` 1 is
/// video, 2 is voice.
enum LookLiveKind {
  /// Video (`liveType` 1).
  video,

  /// Voice (`liveType` 2).
  audio,
}

/// A room's state in the room answer (3.x's `LookLiveState`). List cards
/// are always live.
enum LookLiveState {
  /// `liveStatus` 1.
  live,

  /// `liveStatus` 0 or -1.
  offline,

  /// `liveStatus` -10: a private room or one with account conditions (3.x
  /// showed it as unknown with a notice).
  restricted,

  /// Any other `liveStatus`, or none.
  unknown,
}

/// One stream of a room (3.x's `LookLiveVariant`): the HLS playlist
/// (`hlsPullUrl`) or the FLV stream (`httpPullUrl`) on NetEase's CDN, made
/// https.
@immutable
final class LookLiveVariant {
  /// Creates a stream.
  const new({required this.id, required this.format, required this.uri});

  /// 3.x's id, also the quality id: `hls:source` or `flv:source`.
  final String id;

  /// HLS or FLV.
  final StreamFormat format;

  /// The address.
  final Uri uri;
}

/// A LOOK room (3.x's `LookLiveRoom`): a list card, or the room answer
/// (`room/get/v3`), completed from what was seen before ([enrich]).
///
/// It is also the [LiveRoom.data] of a room entry or recording detail: the
/// room's identity, the streamer's account and the broadcast's session, and
/// the streams read at that moment (never stored).
@immutable
final class LookLiveRoom {
  /// Creates a room.
  new({
    required this.roomId,
    required this.userId,
    required this.sessionId,
    required this.kind,
    required this.state,
    this.title = '',
    this.nick = '',
    this.avatar = '',
    this.cover = '',
    this.streamType,
    this.popularity,
    this.currentViewers,
    Iterable<LookLiveVariant> variants = const [],
  }) : variants = List.unmodifiable(variants);

  /// The room number (`liveRoomNo`): the room's identity.
  final String roomId;

  /// The streamer's account (`userId`).
  final String userId;

  /// The broadcast (`liveId` of a card, `roomInfo.id` of the room answer).
  final String sessionId;

  /// The title; '' when unknown.
  final String title;

  /// The streamer's name; '' when unknown.
  final String nick;

  /// The streamer's avatar, https; '' when unknown.
  final String avatar;

  /// The cover, https; '' when unknown.
  final String cover;

  /// Video or voice.
  final LookLiveKind kind;

  /// `liveStreamType` of the room answer (the lists do not carry it): 50 is
  /// a room type the website has no media for.
  final int? streamType;

  /// The state.
  final LookLiveState state;

  /// The list's heat (`popularity`); null when unknown.
  final int? popularity;

  /// The list's current viewers (`onlineNumber`); null when unknown.
  final int? currentViewers;

  /// The streams, HLS first: a list card's, or a live room's at room entry
  /// and recording; empty otherwise.
  final List<LookLiveVariant> variants;

  /// Whether this room is watchable in LOOK's app only: stream type 50
  /// without streams (3.x). A refreshed room has no streams, so its stream
  /// type alone decides.
  bool get isAppOnly => streamType == 50 && variants.isEmpty;

  /// This answer with what it lacks taken from [known], the last card or
  /// answer of the same room (3.x's `enrich`): the account, names and
  /// images while empty, the stream type while unknown; the audience of the
  /// same broadcast; and that broadcast's streams while this live answer
  /// has none (unless the stream type is 50). State and kind stay this
  /// answer's.
  LookLiveRoom enrich(LookLiveRoom known) {
    final sameSession = sessionId.isNotEmpty && sessionId == known.sessionId;
    final effectiveStreamType = streamType ?? known.streamType;
    final keepKnownVariants =
        variants.isEmpty &&
        sameSession &&
        state == LookLiveState.live &&
        known.state == LookLiveState.live &&
        effectiveStreamType != 50;
    return LookLiveRoom(
      roomId: roomId,
      userId: userId.isEmpty ? known.userId : userId,
      sessionId: sessionId,
      title: title.isEmpty ? known.title : title,
      nick: nick.isEmpty ? known.nick : nick,
      avatar: avatar.isEmpty ? known.avatar : avatar,
      cover: cover.isEmpty ? known.cover : cover,
      kind: kind,
      streamType: effectiveStreamType,
      state: state,
      popularity: popularity ?? (sameSession ? known.popularity : null),
      currentViewers: currentViewers ?? (sameSession ? known.currentViewers : null),
      variants: keepKnownVariants ? known.variants : variants,
    );
  }

  /// Why this room cannot be played, or null (3.x's snapshot check): a
  /// restricted room is `NeedsLogin`; a room that is not live, or has no
  /// streams (such as an app-only room), is `StreamUnavailable`.
  SiteError? get streamError => switch (state) {
    LookLiveState.restricted => NeedsLogin(_site, '$roomId is restricted (liveStatus -10)'),
    LookLiveState.live when isAppOnly => StreamUnavailable(_site, '$roomId is watchable in the LOOK app only'),
    LookLiveState.live when variants.isEmpty => StreamUnavailable(_site, '$roomId is live without streams'),
    LookLiveState.live => null,
    _ => StreamUnavailable(_site, '$roomId is ${state.name}'),
  };
}

/// One page of a recommendation list (3.x's `LookLivePage`).
@immutable
final class LookLivePage {
  /// Creates a page.
  new({required Iterable<LookLiveRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  /// An empty last page.
  static final LookLivePage empty = LookLivePage(rooms: const [], hasMore: false);

  /// The rooms, in list order, each room once.
  final List<LookLiveRoom> rooms;

  /// Whether the list has another page (`hasMore`).
  final bool hasMore;
}

/// Pure parsing of LOOK Live (NetEase) answers, the `weapi` request
/// envelope and the room links (3.x's `LookLiveApi`, `LookLiveLink` and the
/// room mapping of its `LookLiveSite`). Each function takes the answer and
/// its status and returns 3.x's models or throws a `SiteError`.
abstract final class LookLiveApi {
  /// The website.
  static const String origin = 'https://look.163.com';

  /// The API.
  static const String apiOrigin = 'https://api.look.163.com';

  /// 3.x's user agent of the requests and the media headers.
  static const String userAgent = 'Mozilla/5.0';

  /// 3.x's headers of every API request (`requestHeaders`, with dio's form
  /// content type).
  static const Map<String, String> requestHeaders = {
    'accept': 'application/json, text/plain, */*',
    'origin': origin,
    'referer': '$origin/',
    'user-agent': userAgent,
    'content-type': 'application/x-www-form-urlencoded',
  };

  /// 3.x's media headers of [roomId] (`mediaHeaders`): the rooms'
  /// `httpHeaders` (in the 3.x JSON). 3.x's player had no LOOK branch and
  /// sent none of them ([line]).
  static Map<String, String> mediaHeaders(String roomId) => {
    'origin': origin,
    'referer': link(roomId),
    'user-agent': userAgent,
  };

  /// The largest answer 3.x read, in UTF-8 bytes.
  static const int responseLimit = 2 * 1024 * 1024;

  /// Rooms a list request asks for (`limit`).
  static const int pageSize = 20;

  /// Most entries of a list answer 3.x accepted.
  static const int maxEntries = 100;

  /// Last page 3.x asked for.
  static const int maxPage = 10000;

  /// Largest search page size 3.x served; a larger one gives nothing.
  static const int maxSearchSize = 100;

  /// 3.x's platform name (zh.json `site_looklive`): the category and the
  /// areas' type.
  static const String siteName = 'LOOK 直播';

  /// `areaType` of the two areas.
  static const String areaType = 'official';

  /// 3.x's name of the video area (zh.json `looklive_category_video`; the
  /// interface translates it by id, M13).
  static const String videoAreaName = '视频直播';

  /// 3.x's name of the voice area (zh.json `looklive_category_audio`).
  static const String audioAreaName = '语音直播';

  /// The video area.
  static const LiveArea videoArea = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: siteName,
    areaId: 'video',
    areaName: videoAreaName,
  );

  /// The voice area.
  static const LiveArea audioArea = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: siteName,
    areaId: 'audio',
    areaName: audioAreaName,
  );

  /// The notice of every room (3.x's zh.json `looklive_chat_notice`).
  static const String chatNotice = 'LOOK 远端聊天尚待接入；官网 popularity 按平台热度展示，onlineNumber 按当前观看人数单独展示。';

  /// The notice line of a restricted room (`looklive_restricted_notice`).
  static const String restrictedNotice = '该 LOOK 直播受私密房或账号访问条件限制，界面保持未知状态。';

  /// The notice line of an app-only room (`looklive_app_only_notice`).
  static const String appOnlyNotice = '该直播使用官网未开放网页媒体的房型，请在 LOOK 客户端中观看。';

  /// Id of the HLS quality.
  static const String hlsId = 'hls:source';

  /// Id of the FLV quality.
  static const String flvId = 'flv:source';

  /// 3.x's HLS quality (zh.json `looklive_quality_hls`).
  static const LivePlayQuality hlsQuality = LivePlayQuality(quality: 'HLS 原始线路', id: hlsId, sort: 2);

  /// 3.x's FLV quality (zh.json `looklive_quality_flv`).
  static const LivePlayQuality flvQuality = LivePlayQuality(quality: 'FLV 原始线路', id: flvId, sort: 1);

  /// Path of the video list.
  static const String videoListPath = '/weapi/livestream/homepage/recommend';

  /// Path of the voice list.
  static const String audioListPath = '/weapi/livestream/listen/homepage/recommend/list';

  /// Path of the room answer.
  static const String roomPath = '/weapi/livestream/room/get/v3';

  static final RegExp _roomNumber = RegExp(r'^[1-9][0-9]{1,17}$');
  static final RegExp _identifier = RegExp(r'^[1-9][0-9]{0,18}$');
  static final RegExp _mediaHost = RegExp(r'^[a-z0-9-]+\.live\.126\.net$');
  static final RegExp _hlsPath = RegExp(r'^/live/[a-f0-9]{32}/playlist\.m3u8$');
  static final RegExp _flvPath = RegExp(r'^/live/[a-f0-9]{32}\.flv$');

  // Links ---------------------------------------------------------------------

  /// Whether [value] is a room number: 2 to 18 digits, not starting with 0.
  static bool isRoomNumber(String value) => _roomNumber.hasMatch(value);

  /// The room page of [roomId] (3.x's `watchUrl`).
  static String link(String roomId) => '$origin/live?id=$roomId';

  /// The room of [raw] (3.x's `LookLiveLink.parseRoomId`): a room number
  /// (trimmed), or a room link ([roomIdFromUrl]); null otherwise.
  static String? roomIdOf(String raw) {
    final value = raw.trim();
    return isRoomNumber(value) ? value : roomIdFromUrl(value);
  }

  /// The room of a room link (3.x's `LookLiveLink.parseRoomId` for URLs):
  /// http(s) on `look.163.com` (any case), no user info, port 80 or 443 or
  /// none, no fragment, the one path segment `live` (any case, empty
  /// segments ignored) and exactly one `id` that is a room number
  /// (`https://look.163.com/live?id=21623631&position=3`). Null for
  /// anything else, spaces and control characters included.
  static String? roomIdFromUrl(String url) {
    final value = url.trim();
    if (value.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.toLowerCase() != 'look.163.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    try {
      final segments = [
        for (final segment in uri.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
      if (segments.length != 1 || segments.single.toLowerCase() != 'live') return null;
      final ids = uri.queryParametersAll['id'];
      if (ids == null || ids.length != 1 || !isRoomNumber(ids.single)) return null;
      return ids.single;
    } on FormatException {
      return null;
    }
  }

  // Requests ------------------------------------------------------------------

  static const String _nonce = '0CoJUm6Qyw8W8jud';
  static const String _secretKey = '0123456789abcdef';
  static const String _iv = '0102030405060708';

  /// The web client's RSA modulus (public).
  static final BigInt _modulus = BigInt.parse(
    '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec'
    '4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813'
    'cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
    radix: 16,
  );

  /// `encSecKey`: the reversed secret key read as hexadecimal, raised to
  /// 65537 modulo the web client's modulus, 256 hex digits. The secret key
  /// is fixed, so this is a constant.
  static final String encSecKey = BigInt.parse(
    utf8.encode(_secretKey).reversed.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    radix: 16,
  ).modPow(BigInt.from(0x10001), _modulus).toRadixString(16).padLeft(256, '0');

  static String _aes(String text, String key) =>
      base64Encode(AesCbc.encrypt(utf8.encode(text), key: utf8.encode(key), iv: utf8.encode(_iv)));

  /// The `weapi` form of [payload] (3.x's `encryptPayload`, NetEase's web
  /// envelope): `params` is the compact JSON AES-128-CBC encrypted (PKCS#7,
  /// IV `0102030405060708`) with the web nonce, Base64, encrypted again with
  /// the secret key, Base64; `encSecKey` is [encSecKey].
  static Map<String, String> envelope(Object? payload) => {
    'params': _aes(_aes(jsonEncode(payload), _nonce), _secretKey),
    'encSecKey': encSecKey,
  };

  /// The body of the form POST of [payload], encoded as 3.x's
  /// `Uri(queryParameters: …).query`.
  static String formBody(Object? payload) => Uri(queryParameters: envelope(payload)).query;

  /// The list request of page [page] (3.x: 20 rooms from `(page - 1) × 20`).
  static Map<String, int> listPayload(int page) => {'offset': (page - 1) * pageSize, 'limit': pageSize};

  /// The room request of [roomId].
  static Map<String, String> roomPayload(String roomId) => {'liveRoomNo': roomId};

  /// The list path of [kind].
  static String listPath(LookLiveKind kind) => kind == LookLiveKind.audio ? audioListPath : videoListPath;

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `LOOK 直播` with the video and voice areas, the
  /// first [pageSize] of them.
  static List<LiveCategory> categories({int pageSize = 2}) => [
    LiveCategory(id: _site, name: siteName, children: [videoArea, audioArea].take(pageSize).toList()),
  ];

  /// The list of [category] (3.x's `_category`): null for none; the video or
  /// voice area; anything else (another platform, type or area) is a caller
  /// error.
  static LookLiveKind? kindOf(LiveArea? category) {
    if (category == null) return null;
    if (category.platform == _site && category.areaType == areaType) {
      switch (category.areaId) {
        case 'video':
          return LookLiveKind.video;
        case 'audio':
          return LookLiveKind.audio;
      }
    }
    throw ArgumentError.value(category, 'category', 'not a LOOK Live area');
  }

  /// Whether [room] matches the lower-case [query] of 3.x's search filter:
  /// in its number, or its name or title (case ignored).
  static bool matches(LookLiveRoom room, String query) =>
      room.roomId.contains(query) ||
      room.nick.toLowerCase().contains(query) ||
      room.title.toLowerCase().contains(query);

  // Lists ---------------------------------------------------------------------

  /// A recommendation page of [kind] (3.x's `directory`): the `type` "1"
  /// entries with live data; a card of the other kind is skipped (the voice
  /// list injects video cards), as is an entry without `liveData`. Each room
  /// once, where it first appeared, with the last card's data (3.x). An
  /// entry that is not an object, a `liveType` other than 1 or 2, or a card
  /// failing 3.x's checks ([_card]) fails the page (`ApiChanged`), as do
  /// more than [maxEntries] entries and a `hasMore` that is not a boolean.
  ///
  /// A list past its end answers `itemList: null` with `hasMore: false`
  /// (S04-video-p2); that is an empty last page. 3.x required a list there,
  /// so its merged directory failed from page 2 on.
  static LookLivePage directory(String body, {required LookLiveKind kind, int status = 200}) {
    final what = kind == LookLiveKind.audio ? 'voice list' : 'video list';
    final data = _data(body, status: status, what: what);
    final rows = data['itemList'];
    final hasMore = data['hasMore'];
    if (rows == null && hasMore == false) return LookLivePage.empty;
    if (rows is! List || rows.length > maxEntries || hasMore is! bool) {
      throw ApiChanged(
        _site,
        '$what: itemList ${rows is List ? 'of ${rows.length}' : 'is ${_kind(rows)}'}, '
        'hasMore ${_kind(hasMore)}',
      );
    }
    final rooms = <String, LookLiveRoom>{};
    for (final row in rows) {
      final item = _object(row, '$what entry');
      if ('${item['type']}' != '1' || item['liveData'] == null) continue;
      final live = _object(item['liveData'], '$what liveData');
      final cardKind = _kindOf(live['liveType'], what);
      if (cardKind != kind) continue;
      final room = _card(live, kind: kind, what: what);
      rooms[room.roomId] = room;
    }
    return LookLivePage(rooms: rooms.values, hasMore: hasMore);
  }

  /// A list card (3.x's `_directoryRoom`): number `userInfo.liveRoomNo`,
  /// account `userInfo.userId`, session `liveId` (all required ids), title
  /// `liveTitle`, name `userInfo.nickname`, avatar, cover, heat
  /// `popularity`, viewers `onlineNumber` (null when missing, else a
  /// non-negative integer) and the streams of `liveUrl`; live. The list has
  /// no `liveStreamType`.
  static LookLiveRoom _card(Map<String, dynamic> live, {required LookLiveKind kind, required String what}) {
    final user = _object(live['userInfo'], '$what userInfo');
    final roomId = _id(user['liveRoomNo'], '$what liveRoomNo');
    return LookLiveRoom(
      roomId: roomId,
      userId: _id(user['userId'], 'userId of $roomId'),
      sessionId: _id(live['liveId'], 'liveId of $roomId'),
      title: _text(live['liveTitle']),
      nick: _text(user['nickname']),
      avatar: _picture(user['avatarUrl']),
      cover: _picture(live['liveCoverUrl']),
      kind: kind,
      streamType: _int(live['liveStreamType']),
      state: LookLiveState.live,
      popularity: _count(live['popularity'], 'popularity of $roomId'),
      currentViewers: _count(live['onlineNumber'], 'onlineNumber of $roomId'),
      variants: _variants(live['liveUrl'], roomId),
    );
  }

  // Room ----------------------------------------------------------------------

  /// `room/get/v3` for [roomId] (3.x's `room`): the anchor must answer for
  /// this number (else `ApiChanged`); state from `liveStatus` (1 live, 0 and
  /// -1 offline, -10 restricted, anything else unknown); kind from
  /// `roomInfo.liveType` (1 or 2, else `ApiChanged`); account, session
  /// (required ids), title, name, avatar, cover and stream type. The
  /// streams are read only with [withMedia] and when live (3.x: a refresh
  /// never looked at them). No audience: the answer has none.
  static LookLiveRoom room(String body, {required String roomId, bool withMedia = true, int status = 200}) {
    const what = 'room/get/v3';
    final data = _data(body, status: status, what: what);
    final anchor = _object(data['anchor'], '$what anchor');
    final answered = _id(anchor['liveRoomNo'], '$what anchor.liveRoomNo');
    if (answered != roomId) throw ApiChanged(_site, '$what: asked $roomId, got $answered');
    final info = _object(data['roomInfo'], '$what roomInfo');
    final kind = _kindOf(info['liveType'], what);
    final state = switch (_int(data['liveStatus'])) {
      1 => LookLiveState.live,
      0 || -1 => LookLiveState.offline,
      -10 => LookLiveState.restricted,
      _ => LookLiveState.unknown,
    };
    return LookLiveRoom(
      roomId: roomId,
      userId: _id(anchor['userId'], 'userId of $roomId'),
      sessionId: _id(info['id'], 'roomInfo.id of $roomId'),
      title: _text(info['title']),
      nick: _text(anchor['nickName']),
      avatar: _picture(anchor['avatarUrl']),
      cover: _picture(info['liveCoverUrl']),
      kind: kind,
      streamType: _int(info['liveStreamType']),
      state: state,
      variants: withMedia && state == LookLiveState.live ? _variants(info['liveUrl'], roomId) : const [],
    );
  }

  // Streams -------------------------------------------------------------------

  /// The streams of `liveUrl` (3.x's `_variants`): the HLS playlist, then
  /// the FLV stream, each when present ([mediaUri]); none for null. A
  /// `liveUrl` that is not an object is `ApiChanged`.
  static List<LookLiveVariant> _variants(Object? value, String roomId) {
    if (value == null) return const [];
    final urls = _object(value, 'liveUrl of $roomId');
    return [
      for (final (id, key, format) in const [
        (hlsId, 'hlsPullUrl', StreamFormat.hls),
        (flvId, 'httpPullUrl', StreamFormat.flv),
      ])
        if (_text(urls[key]) case final raw when raw.isNotEmpty)
          LookLiveVariant(
            id: id,
            format: format,
            uri: mediaUri(raw, format: format),
          ),
    ];
  }

  /// A stream address as 3.x accepted it (`mediaUri`), made https: http(s)
  /// on a `*.live.126.net` host (one label of letters, digits and hyphens),
  /// no user info, port or fragment, a query of at most 2048 characters,
  /// and the path `/live/<32 lower-case hex>/playlist.m3u8` (HLS) or
  /// `/live/<32 lower-case hex>.flv` (FLV). Anything else is `ApiChanged`
  /// (3.x failed the whole list page or room entry).
  static Uri mediaUri(String raw, {required StreamFormat format}) {
    final source = Uri.tryParse(raw.trim());
    final path = switch (format) {
      StreamFormat.hls => _hlsPath,
      StreamFormat.flv => _flvPath,
      StreamFormat.other => null,
    };
    if (source == null ||
        (!source.isScheme('http') && !source.isScheme('https')) ||
        source.userInfo.isNotEmpty ||
        source.hasPort ||
        source.fragment.isNotEmpty ||
        !_mediaHost.hasMatch(source.host.toLowerCase()) ||
        source.query.length > 2048 ||
        path == null ||
        !path.hasMatch(source.path)) {
      throw ApiChanged(_site, 'not a LOOK ${format.name.toUpperCase()} address: ${_snippet(raw)}');
    }
    return source.replace(scheme: 'https');
  }

  /// 3.x's qualities of a playable [room]: one per stream, HLS first.
  static List<LivePlayQuality> qualities(LookLiveRoom room) => [
    for (final variant in room.variants)
      if (variant.format == StreamFormat.hls) hlsQuality else flvQuality,
  ];

  /// The line of quality [qualityId] of a playable [room]: its stream, the
  /// host as line id. No headers: 3.x's player had no LOOK branch and sent
  /// its own defaults. No lease: the addresses carry no signature or expiry.
  /// No codec: the answer does not say it (voice rooms have no video). A
  /// quality the room lacks is `StreamUnavailable`; one that is not LOOK's
  /// is a caller error.
  static LivePlayLine line(LookLiveRoom room, String qualityId) {
    if (qualityId != hlsId && qualityId != flvId) {
      throw ArgumentError.value(qualityId, 'qualityId', 'not a LOOK Live quality');
    }
    for (final variant in room.variants) {
      if (variant.id == qualityId) {
        return LivePlayLine('${variant.uri}', format: variant.format, lineId: variant.uri.host);
      }
    }
    throw StreamUnavailable(_site, '${room.roomId} has no $qualityId');
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [room] (3.x's `_room`): the number, account, title and
  /// name; the avatar, else the cover; the area by kind; current viewers as
  /// the audience when known, else the heat (both kept apart); live,
  /// offline, or unknown for restricted and unknown states; the notice
  /// lines (restricted, app-only, chat); 3.x's media headers. [withData]
  /// (room entry and recording) keeps [room] as the room's data, with its
  /// streams. A number that is not 2 to 18 digits (a list may carry one)
  /// is `ApiChanged`, as 3.x's link failed on it.
  static LiveRoom liveRoom(LookLiveRoom room, {bool withData = false}) {
    if (!isRoomNumber(room.roomId)) throw ApiChanged(_site, 'room number ${room.roomId} is not 2 to 18 digits');
    final online = room.currentViewers?.toString();
    final heat = room.popularity?.toString();
    return LiveRoom(
      platform: _site,
      roomId: room.roomId,
      userId: room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: room.kind == LookLiveKind.audio ? audioAreaName : videoAreaName,
      link: link(room.roomId),
      liveStatus: switch (room.state) {
        LookLiveState.live => LiveStatus.live,
        LookLiveState.offline => LiveStatus.offline,
        LookLiveState.restricted || LookLiveState.unknown => LiveStatus.unknown,
      },
      watching: online ?? heat ?? '',
      onlineViewers: online ?? '',
      popularity: heat ?? '',
      audienceMetricType: online != null
          ? AudienceMetricType.onlineViewers
          : heat != null
          ? AudienceMetricType.popularity
          : AudienceMetricType.unknown,
      notice: [
        if (room.state == LookLiveState.restricted) restrictedNotice,
        if (room.isAppOnly) appOnlyNotice,
        chatNotice,
      ].join('\n'),
      httpHeaders: mediaHeaders(room.roomId),
      data: withData ? room : null,
    );
  }
}

// Fields ----------------------------------------------------------------------

LookLiveKind _kindOf(Object? liveType, String what) => switch (_int(liveType)) {
  1 => LookLiveKind.video,
  2 => LookLiveKind.audio,
  _ => throw ApiChanged(_site, '$what: liveType ${_kind(liveType)}'),
};

/// 3.x's text: text trimmed, anything else ''.
String _text(Object? value) => value is String ? value.trim() : '';

/// 3.x's integers: an integer, or text that is one (not trimmed).
int? _int(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

/// 3.x's counts: null when missing, else a non-negative integer
/// (`ApiChanged` otherwise).
int? _count(Object? value, String what) {
  if (value == null) return null;
  final count = _int(value);
  if (count == null || count < 0) throw ApiChanged(_site, '$what is ${_kind(value)}');
  return count;
}

/// 3.x's ids: a number, or text trimmed, of 1 to 19 digits not starting
/// with 0 (`ApiChanged` otherwise).
String _id(Object? value, String what) {
  final text = switch (value) {
    final int number => '$number',
    final String text => text.trim(),
    _ => '',
  };
  if (!LookLiveApi._identifier.hasMatch(text)) throw ApiChanged(_site, '$what is ${_kind(value)}');
  return text;
}

/// 3.x's pictures: http(s) with a host, no user info, port or fragment,
/// made https; '' for anything else.
String _picture(Object? value) {
  final uri = Uri.tryParse(_text(value));
  if (uri == null ||
      (!uri.isScheme('http') && !uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.fragment.isNotEmpty) {
    return '';
  }
  return uri.replace(scheme: 'https').toString();
}

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw ApiChanged(_site, '$what is ${_kind(value)}');
}

/// A short description of [value] for error details.
String _kind(Object? value) => switch (value) {
  null => 'missing',
  final String text => '"${_snippet(text)}"',
  num() || bool() => '$value',
  List() => 'a list',
  Map() => 'an object',
  _ => value.runtimeType.toString(),
};

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping: 200 is an answer; 401 and 403 are `RiskControl`
/// (3.x's "access"), 404 `NotFound`, 429 `RateLimited`; 5xx and every other
/// status (redirects included: 3.x did not follow them) `NetworkFailure`.
void _checkStatus(int status, {required String what}) {
  switch (status) {
    case 200:
      return;
    case 401 || 403:
      throw RiskControl(_site, detail: '$what: HTTP $status');
    case 404:
      throw NotFound(_site, '$what: HTTP 404');
    case 429:
      throw RateLimited(_site, detail: '$what: HTTP 429');
    default:
      throw NetworkFailure(_site, '$what: HTTP $status');
  }
}

/// The `{code, data}` envelope (3.x's `_post`): an answer over
/// [LookLiveApi.responseLimit] bytes or not a JSON object is `ApiChanged`;
/// `code` 404 is `NotFound`, 424, 520, 522 and 555 are `RiskControl`
/// (3.x's "access"), anything but 200 is `ApiChanged`; `data` must be an
/// object.
Map<String, dynamic> _data(String body, {required int status, required String what}) {
  _checkStatus(status, what: what);
  // UTF-8 needs at most three bytes per UTF-16 unit, so short bodies need no
  // encoding.
  if (body.length > LookLiveApi.responseLimit ||
      (body.length * 3 > LookLiveApi.responseLimit && utf8.encode(body).length > LookLiveApi.responseLimit)) {
    throw ApiChanged(_site, '$what: answer over ${LookLiveApi.responseLimit} bytes');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  final root = _object(decoded, what);
  final code = _int(root['code']);
  final message = _text(root['message']);
  switch (code) {
    case 200:
      return _object(root['data'], '$what data');
    case 404:
      throw NotFound(_site, '$what: code 404 $message'.trim());
    case 424 || 520 || 522 || 555:
      throw RiskControl(_site, detail: '$what: code $code $message'.trim());
    default:
      throw ApiChanged(_site, '$what: code ${_kind(root['code'])} $message'.trim());
  }
}
