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
///
/// The values follow LOOK's web client (`look.163.com`, app and Live
/// chunks): its `LIVE_STATUS_TYPE` is `{NOLIVE: 0, LIVING: 1, FORBID: -10}`;
/// the room page shows "- 直播间已关闭 -" for -1, 0 and -2, and for -4 hides
/// the stream behind "该直播间已涉嫌违规…整改期间直播内容将被屏蔽".
enum LookLiveState {
  /// `liveStatus` 1.
  live,

  /// `liveStatus` 0, -1 or -2 (upgrade 32-2: 3.x showed -2 as unknown).
  offline,

  /// `liveStatus` -10 (`FORBID`: the room may not broadcast) or -4 (blocked
  /// while it corrects a violation). Upgrade 32-2: 3.x read -10 as a
  /// private or account-restricted room and showed it as unknown, and -4 as
  /// unknown.
  banned,

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

/// The danmaku (chat) of a live LOOK room (M5.28; 3.x had none): room
/// entry and recording give it (`LiveRoom.danmakuData`) from the room
/// answer they already asked for, without another request.
///
/// LOOK's chat is a NetEase Yunxin (网易云信) chatroom: the website asks
/// `LookLiveApi.chatAddressPath` for the room's chat servers and joins the
/// chatroom `roomInfo.roomId` anonymously.
@immutable
final class LookLiveDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId, required this.chatroomId, this.anonymousMode = false});

  /// The room number (`liveRoomNo`): the chat servers are asked for it.
  final String roomId;

  /// The Yunxin chatroom of the room (`roomInfo.roomId`; not the room
  /// number).
  final String chatroomId;

  /// Whether the room hides its viewers' names (`anonymousMode`): LOOK's
  /// room page then shows a name's first character and `***`.
  final bool anonymousMode;

  @override
  bool operator ==(Object other) =>
      other is LookLiveDanmakuArgs &&
      other.roomId == roomId &&
      other.chatroomId == chatroomId &&
      other.anonymousMode == anonymousMode;

  @override
  int get hashCode => Object.hash(roomId, chatroomId, anonymousMode);

  @override
  String toString() => 'LookLiveDanmakuArgs($roomId, chatroom $chatroomId${anonymousMode ? ', anonymous' : ''})';
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
    this.startedAt,
    this.hasAddress = false,
    this.mediaChecked = false,
    this.paid,
    this.chatroomId = '',
    this.anonymousMode = false,
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

  /// The stream type: `liveStreamType` of the room answer, `type` of a list
  /// card's `liveData` (upgrade 32-4; 3.x read `liveStreamType` there, which
  /// the lists do not carry). LOOK's web client names 1 normal, 6 audio, 12
  /// mobile game, 19 music festival and 50 multi-person; 50 is a room type
  /// the website has no media for.
  final int? streamType;

  /// The state.
  final LookLiveState state;

  /// The list's heat (`popularity`); null when unknown.
  final int? popularity;

  /// The list's current viewers (`onlineNumber`); null when unknown.
  final int? currentViewers;

  /// When the broadcast started (`roomInfo.startTime`, epoch milliseconds),
  /// for a live room answer; null otherwise (the lists do not say).
  final DateTime? startedAt;

  /// Whether the answer or card carries a stream address (`hlsPullUrl` or
  /// `httpPullUrl` text, valid or not), read at every depth: a refresh
  /// tells an app-only room from one with streams without reading them.
  final bool hasAddress;

  /// Whether [variants] were read from this answer's addresses: a list card,
  /// or a live room answer at room entry and recording.
  final bool mediaChecked;

  /// Whether the broadcast needs a ticket: the room answer's `feeInfo.fee`
  /// without a `sessionKey` (LOOK's web client then shows "请购票后观看"
  /// instead of the stream). Null for a list card (the lists do not say).
  final bool? paid;

  /// The streams, HLS first: a list card's, or a live room's at room entry
  /// and recording; empty otherwise. An address that fails the checks is
  /// left out (upgrade 32-6).
  final List<LookLiveVariant> variants;

  /// The room's Yunxin chatroom (`roomInfo.roomId` of the room answer,
  /// M5.28); '' for a list card or an answer without one.
  final String chatroomId;

  /// Whether the room answer says the room hides its viewers' names
  /// (`anonymousMode`, M5.28); false for a list card.
  final bool anonymousMode;

  /// The chat of this room (M5.28): a live room answer with a chatroom;
  /// null otherwise (a list card, a room that is not live).
  LookLiveDanmakuArgs? get danmakuArgs => state == LookLiveState.live && chatroomId.isNotEmpty
      ? LookLiveDanmakuArgs(roomId: roomId, chatroomId: chatroomId, anonymousMode: anonymousMode)
      : null;

  /// Whether this room is watchable in LOOK's app only: stream type 50
  /// without streams (3.x), and without any address in the answer, so a
  /// refresh (which reads no streams) tells it too (3.x's refresh took
  /// every type 50 room for app-only).
  bool get isAppOnly => streamType == 50 && !hasAddress && variants.isEmpty;

  /// What keeps this client from playing a live room (M2.1): app-only, a
  /// ticket ([paid]), or no usable address (unplayable); none otherwise.
  /// Not live: none, except null for an unknown state; a list card that
  /// can be played says null, as it does not tell tickets.
  LiveRestriction? get restriction => switch (state) {
    LookLiveState.unknown => null,
    LookLiveState.live when isAppOnly => LiveRestriction.appOnly,
    LookLiveState.live when paid ?? false => LiveRestriction.paid,
    LookLiveState.live when variants.isEmpty && (mediaChecked || !hasAddress) => LiveRestriction.unplayable,
    LookLiveState.live when paid == null => null,
    _ => LiveRestriction.none,
  };

  /// This answer with what it lacks taken from [known], the last card or
  /// answer of the same room (3.x's `enrich`): the account, names and
  /// images while empty, the stream type while unknown; the audience of the
  /// same broadcast while this answer is live (upgrade 32-5; 3.x also gave
  /// an ended room its last heat and viewers); and that broadcast's streams
  /// while this live answer has none (unless the stream type is 50). State,
  /// kind, start, addresses, ticket and chat stay this answer's.
  LookLiveRoom enrich(LookLiveRoom known) {
    final sameSession = sessionId.isNotEmpty && sessionId == known.sessionId;
    final live = state == LookLiveState.live;
    final effectiveStreamType = streamType ?? known.streamType;
    final keepKnownVariants =
        variants.isEmpty && sameSession && live && known.state == LookLiveState.live && effectiveStreamType != 50;
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
      popularity: popularity ?? (sameSession && live ? known.popularity : null),
      currentViewers: currentViewers ?? (sameSession && live ? known.currentViewers : null),
      startedAt: startedAt,
      hasAddress: hasAddress,
      mediaChecked: mediaChecked,
      paid: paid,
      chatroomId: chatroomId,
      anonymousMode: anonymousMode,
      variants: keepKnownVariants ? known.variants : variants,
    );
  }

  /// Why this room cannot be played, or null (3.x's snapshot check), each
  /// `StreamUnavailable` with the reason: not live (offline, banned,
  /// unknown), app-only, a ticket, or no streams.
  SiteError? get streamError => switch (state) {
    LookLiveState.live when isAppOnly => StreamUnavailable(_site, '$roomId is watchable in the LOOK app only'),
    LookLiveState.live when paid ?? false => StreamUnavailable(_site, '$roomId needs a ticket (feeInfo.fee)'),
    LookLiveState.live when variants.isEmpty => StreamUnavailable(_site, '$roomId is live without streams'),
    LookLiveState.live => null,
    LookLiveState.banned => StreamUnavailable(_site, '$roomId is banned by LOOK'),
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
  /// `httpHeaders` (in the 3.x JSON), and the headers of every line
  /// (upgrade 32-3; 3.x's player had no LOOK branch and sent none of them).
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

  /// The notice of every room (text key `looklive_chat_notice`), in words
  /// for users (M4.U; 3.x: "LOOK 远端聊天尚待接入；官网 popularity 按平台热度展示，onlineNumber 按当前观看人数单独展示。").
  /// Chat is shown since M5.28, so the notice only explains the numbers
  /// (M4.U began it with "这里暂时看不到 LOOK 直播的聊天。").
  static const String chatNotice = '人数是正在观看的人数，热度另外显示。';

  /// The notice line of a banned room (text key `looklive_restricted_notice`;
  /// M4.U, 3.x: "该 LOOK 直播受私密房或账号访问条件限制，界面保持未知状态。", upgrade 32-2).
  static const String bannedNotice = '这个 LOOK 直播间被平台禁播或正在违规整改，现在不能观看。';

  /// The notice line of an app-only room (`looklive_app_only_notice`; M4.U,
  /// 3.x: "该直播使用官网未开放网页媒体的房型，请在 LOOK 客户端中观看。").
  static const String appOnlyNotice = '这场 LOOK 直播只能在 LOOK App 里观看。';

  /// The notice line of a ticketed broadcast (new text key
  /// `looklive_paid_notice`, M13).
  static const String paidNotice = '这场 LOOK 直播要购票才能观看。';

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

  /// Path of the chat servers of a live room (M5.28): LOOK's web client
  /// posts `/api/livestream/chat/address` (the Live chunk's chat service,
  /// module `qKXv`), which its request helper sends as this `weapi` path
  /// (app chunk, modules `jzhw` and `0CZ9`).
  static const String chatAddressPath = '/weapi/livestream/chat/address';

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

  /// The chat server request of [roomId], as LOOK's web client sends it
  /// (`{liveRoomNo, os: 0}`).
  static Map<String, Object> chatAddressPayload(String roomId) => {'liveRoomNo': roomId, 'os': 0};

  static final RegExp _chatAddress = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+:([0-9]{1,5})$',
  );

  /// The chat servers of a [chatAddressPath] answer: `data.address`, each a
  /// `host:port` of NetEase Yunxin's chatroom service
  /// (`chatwl01.yunxinfw.com:443`), in the answer's order, lower-cased;
  /// entries that are not a host name and a port (1 to 65535) are left out.
  /// The envelope is the other answers' ([room]'s status and `code`
  /// mapping): `code` 404 ("无资源", for a room that is not live) is
  /// `NotFound`. No `address` list, or none usable, is `ApiChanged`.
  static List<String> chatAddresses(String body, {int status = 200}) {
    const what = 'chat/address';
    final data = _data(body, status: status, what: what);
    final raw = data['address'];
    if (raw is! List) throw ApiChanged(_site, '$what: address is ${_kind(raw)}');
    final addresses = <String>{
      for (final entry in raw)
        if (_text(entry).toLowerCase() case final address)
          if (_chatAddress.firstMatch(address) case final match?)
            if (int.parse(match.group(4)!) case final port when port >= 1 && port <= 65535) address,
    };
    if (addresses.isEmpty) throw ApiChanged(_site, '$what: no usable address in ${_snippet(jsonEncode(raw))}');
    return addresses.toList();
  }

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
  /// once, where it first appeared, with the last card's data (3.x).
  ///
  /// An entry that cannot be read (not an object, a `liveType` other than 1
  /// or 2, a card failing [_card]'s checks) is skipped (upgrade 32-6: 3.x
  /// failed the page), unless nothing on the page can be read: then the
  /// page is `ApiChanged`, as are more than [maxEntries] entries and a
  /// `hasMore` that is not a boolean. A bad stream address costs only that
  /// stream of the card.
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
    var unreadable = 0;
    for (final row in rows) {
      final LookLiveRoom? room;
      try {
        room = _entry(row, kind: kind, what: what);
      } on ApiChanged {
        unreadable++;
        continue;
      }
      if (room != null) rooms[room.roomId] = room;
    }
    if (unreadable > 0 && rooms.isEmpty) throw ApiChanged(_site, '$what: $unreadable unreadable entries, no room');
    return LookLivePage(rooms: rooms.values, hasMore: hasMore);
  }

  /// The card of a list entry, or null for another kind of entry or card;
  /// `ApiChanged` when it cannot be read.
  static LookLiveRoom? _entry(Object? row, {required LookLiveKind kind, required String what}) {
    final item = _object(row, '$what entry');
    if ('${item['type']}' != '1' || item['liveData'] == null) return null;
    final live = _object(item['liveData'], '$what liveData');
    return _kindOf(live['liveType'], what) == kind ? _card(live, kind: kind, what: what) : null;
  }

  /// A list card (3.x's `_directoryRoom`): number `userInfo.liveRoomNo` (a
  /// room number, 2 to 18 digits: 3.x failed the page on another one when
  /// it made the room), account `userInfo.userId`, session `liveId` (all
  /// required ids), title `liveTitle`, name `userInfo.nickname`, avatar,
  /// cover, heat `popularity`, viewers `onlineNumber` (null when missing,
  /// else a non-negative integer), stream type `type` (32-4) and the
  /// streams of `liveUrl`; live.
  static LookLiveRoom _card(Map<String, dynamic> live, {required LookLiveKind kind, required String what}) {
    final user = _object(live['userInfo'], '$what userInfo');
    final roomId = _id(user['liveRoomNo'], '$what liveRoomNo');
    if (!isRoomNumber(roomId)) throw ApiChanged(_site, '$what: room number $roomId is not 2 to 18 digits');
    final urls = live['liveUrl'];
    return LookLiveRoom(
      roomId: roomId,
      userId: _id(user['userId'], 'userId of $roomId'),
      sessionId: _id(live['liveId'], 'liveId of $roomId'),
      title: _text(live['liveTitle']),
      nick: _text(user['nickname']),
      avatar: _picture(user['avatarUrl']),
      cover: _picture(live['liveCoverUrl']),
      kind: kind,
      streamType: _int(live['liveStreamType'] ?? live['type']),
      state: LookLiveState.live,
      popularity: _count(live['popularity'], 'popularity of $roomId'),
      currentViewers: _count(live['onlineNumber'], 'onlineNumber of $roomId'),
      hasAddress: _hasAddress(urls),
      mediaChecked: true,
      variants: _variants(urls),
    );
  }

  // Room ----------------------------------------------------------------------

  /// `room/get/v3` for [roomId] (3.x's `room`): the anchor must answer for
  /// this number (else `ApiChanged`); state from `liveStatus` (1 live; 0, -1
  /// and -2 offline; -10 and -4 banned; anything else unknown, see
  /// [LookLiveState]); kind from `roomInfo.liveType` (1 or 2, else
  /// `ApiChanged`); account, session (required ids), title, name, avatar,
  /// cover, stream type, whether it carries addresses, the ticket
  /// (`feeInfo`) and, when live, the start (`roomInfo.startTime`). The
  /// streams are read only with [withMedia] and when live (3.x: a refresh
  /// never looked at them); a bad address costs only its stream (32-6). No
  /// audience: the answer has none.
  static LookLiveRoom room(String body, {required String roomId, bool withMedia = true, int status = 200}) {
    const what = 'room/get/v3';
    final data = _data(body, status: status, what: what, room: true);
    final anchor = _object(data['anchor'], '$what anchor');
    final answered = _id(anchor['liveRoomNo'], '$what anchor.liveRoomNo');
    if (answered != roomId) throw ApiChanged(_site, '$what: asked $roomId, got $answered');
    final info = _object(data['roomInfo'], '$what roomInfo');
    final kind = _kindOf(info['liveType'], what);
    final state = switch (_int(data['liveStatus'])) {
      1 => LookLiveState.live,
      0 || -1 || -2 => LookLiveState.offline,
      -10 || -4 => LookLiveState.banned,
      _ => LookLiveState.unknown,
    };
    final live = state == LookLiveState.live;
    final urls = info['liveUrl'];
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
      startedAt: live ? _time(info['startTime']) : null,
      hasAddress: _hasAddress(urls),
      mediaChecked: withMedia && live,
      paid: _paid(data['feeInfo']),
      chatroomId: _optionalId(info['roomId']),
      anonymousMode: data['anonymousMode'] == true,
      variants: withMedia && live ? _variants(urls) : const [],
    );
  }

  // Streams -------------------------------------------------------------------

  /// The streams of `liveUrl` (3.x's `_variants`): the HLS playlist, then
  /// the FLV stream, each when present and accepted by [mediaUri]. A bad
  /// address, or a `liveUrl` that is not an object, costs only its streams
  /// (upgrade 32-6: 3.x failed the whole list page or room entry).
  static List<LookLiveVariant> _variants(Object? value) {
    if (value is! Map<String, dynamic>) return const [];
    return [
      for (final (id, key, format) in const [
        (hlsId, 'hlsPullUrl', StreamFormat.hls),
        (flvId, 'httpPullUrl', StreamFormat.flv),
      ])
        if (_text(value[key]) case final raw when raw.isNotEmpty)
          if (_mediaUriOrNull(raw, format) case final uri?) LookLiveVariant(id: id, format: format, uri: uri),
    ];
  }

  static Uri? _mediaUriOrNull(String raw, StreamFormat format) {
    try {
      return mediaUri(raw, format: format);
    } on ApiChanged {
      return null;
    }
  }

  /// Whether `liveUrl` carries an HLS or FLV address, valid or not.
  static bool _hasAddress(Object? value) =>
      value is Map && (_text(value['hlsPullUrl']).isNotEmpty || _text(value['httpPullUrl']).isNotEmpty);

  /// A stream address as 3.x accepted it (`mediaUri`), made https: http(s)
  /// on a `*.live.126.net` host (one label of letters, digits and hyphens),
  /// no user info, port or fragment, a query of at most 2048 characters,
  /// and the path `/live/<32 lower-case hex>/playlist.m3u8` (HLS) or
  /// `/live/<32 lower-case hex>.flv` (FLV). Anything else is `ApiChanged`
  /// (3.x failed the whole list page or room entry; the parsing now leaves
  /// that stream out, 32-6).
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
  /// host as line id, and the web's media headers ([mediaHeaders]: `Origin`,
  /// the room page as `Referer`, 3.x's user agent; upgrade 32-3, 3.x's
  /// player sent its own defaults). No lease: the addresses carry no
  /// signature or expiry. No codec: the answer does not say it (voice rooms
  /// have no video). A quality the room lacks is `StreamUnavailable`; one
  /// that is not LOOK's is a caller error.
  static LivePlayLine line(LookLiveRoom room, String qualityId) {
    if (qualityId != hlsId && qualityId != flvId) {
      throw ArgumentError.value(qualityId, 'qualityId', 'not a LOOK Live quality');
    }
    for (final variant in room.variants) {
      if (variant.id == qualityId) {
        return LivePlayLine(
          '${variant.uri}',
          headers: mediaHeaders(room.roomId),
          format: variant.format,
          lineId: variant.uri.host,
        );
      }
    }
    throw StreamUnavailable(_site, '${room.roomId} has no $qualityId');
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [room] (3.x's `_room`): the number, account, title and
  /// name; the avatar, else the cover; the area by kind; current viewers as
  /// the audience when known, else the heat (both kept apart); the state
  /// (live, offline, banned or unknown; upgrade 32-2: 3.x showed -10 as
  /// unknown); the start and the restriction ([LookLiveRoom.restriction]);
  /// the notice lines (banned, app-only, ticket, chat); 3.x's media
  /// headers. [withData] (room entry and recording) keeps [room] as the
  /// room's data, with its streams, and its chat as the danmaku data
  /// ([LookLiveRoom.danmakuArgs], M5.28). A number that is not 2 to 18
  /// digits is `ApiChanged`, as 3.x's link failed on it.
  static LiveRoom liveRoom(LookLiveRoom room, {bool withData = false}) {
    if (!isRoomNumber(room.roomId)) throw ApiChanged(_site, 'room number ${room.roomId} is not 2 to 18 digits');
    final online = room.currentViewers?.toString();
    final heat = room.popularity?.toString();
    final restriction = room.restriction;
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
        LookLiveState.banned => LiveStatus.banned,
        LookLiveState.unknown => LiveStatus.unknown,
      },
      startedAt: room.startedAt,
      restriction: restriction,
      watching: online ?? heat ?? '',
      onlineViewers: online ?? '',
      popularity: heat ?? '',
      audienceMetricType: online != null
          ? AudienceMetricType.onlineViewers
          : heat != null
          ? AudienceMetricType.popularity
          : AudienceMetricType.unknown,
      notice: [
        if (room.state == LookLiveState.banned) bannedNotice,
        if (restriction == LiveRestriction.appOnly) appOnlyNotice,
        if (restriction == LiveRestriction.paid) paidNotice,
        chatNotice,
      ].join('\n'),
      httpHeaders: mediaHeaders(room.roomId),
      data: withData ? room : null,
      danmakuData: withData ? room.danmakuArgs : null,
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

/// A time in epoch milliseconds (`startTime`), UTC; null when missing, zero
/// or not a number.
DateTime? _time(Object? value) => switch (_int(value)) {
  final int ms when ms > 0 => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  _ => null,
};

/// Whether `feeInfo` asks for a ticket, as LOOK's web client decides it:
/// `fee` set (true or a non-zero number) and no `sessionKey` (a bought
/// ticket; never for an anonymous client).
bool _paid(Object? feeInfo) {
  if (feeInfo is! Map) return false;
  final fee = feeInfo['fee'];
  final key = feeInfo['sessionKey'];
  return (fee == true || (fee is num && fee != 0)) && (key == null || key == '');
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

/// An id as [_id] reads it, or '' when missing or not one (the chatroom,
/// which only the chat needs: M5.28).
String _optionalId(Object? value) {
  final text = switch (value) {
    final int number => '$number',
    final String text => text.trim(),
    _ => '',
  };
  return LookLiveApi._identifier.hasMatch(text) ? text : '';
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
///
/// For the [room] answer, 424 and 555 say why the room cannot be watched
/// (LOOK's web client: 424 "暂不支持此直播，请在APP中查看", 555 opens the
/// password box of a private room), so they are `StreamUnavailable` with
/// that reason (M4.U: the unified rule on restricted rooms); 520 and 522
/// ("你当前无法进入直播间") stay `RiskControl`.
Map<String, dynamic> _data(String body, {required int status, required String what, bool room = false}) {
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
    case 424 when room:
      throw StreamUnavailable(_site, '$what: code 424, watchable in the LOOK app only $message'.trim());
    case 555 when room:
      throw StreamUnavailable(_site, '$what: code 555, a private room with a password $message'.trim());
    case 424 || 520 || 522 || 555:
      throw RiskControl(_site, detail: '$what: code $code $message'.trim());
    default:
      throw ApiChanged(_site, '$what: code ${_kind(root['code'])} $message'.trim());
  }
}
