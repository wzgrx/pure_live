import 'dart:convert';
import 'dart:math' as math;

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_master.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'chzzk';

/// A CHZZK channel: the room identity (3.x's `ChzzkChannel`), from
/// `/service/v1/channels/<id>` or a channel search result.
@immutable
final class ChzzkChannel {
  /// Creates a channel.
  const new({
    required this.id,
    required this.name,
    required this.avatar,
    this.description = '',
    this.followers,
    this.isLive = false,
  });

  /// `channelId`: 32 lower-case hex digits.
  final String id;

  /// `channelName`.
  final String name;

  /// `channelImageUrl`; empty unless it is an https image of NAVER's CDNs.
  final String avatar;

  /// `channelDescription`, trimmed.
  final String description;

  /// `followerCount`, when the answer has one.
  final int? followers;

  /// `openLive`.
  final bool isLive;
}

/// One HLS master of a live's `livePlaybackJson` (3.x's `ChzzkMedia`).
@immutable
final class ChzzkMedia {
  /// Creates the media.
  const new(this.id, this.url);

  /// `mediaId`: `HLS` (normal latency) or `LLHLS` (low latency); the line
  /// id of its variants.
  final String id;

  /// The master playlist, with its Akamai token (`hdnts`).
  final Uri url;
}

/// The latest live of a channel, from `v3.1 live-detail` (3.x's
/// `ChzzkLive`).
@immutable
final class ChzzkLive {
  /// Creates the live.
  new({
    required this.isLive,
    required this.title,
    required this.nick,
    required this.avatar,
    required this.cover,
    required this.area,
    required List<ChzzkMedia> media,
    this.online,
    this.adult = false,
    this.krOnly = false,
    this.abroadBlind = false,
    this.timeMachine = false,
    this.chatChannelId,
    this.mediaError,
  }) : media = List.unmodifiable(media);

  /// `status == OPEN` (`CLOSE` and `CLOSED` are offline).
  final bool isLive;

  /// `liveTitle`, else the channel name.
  final String title;

  /// The live's `channel.channelName`.
  final String nick;

  /// The live's `channel.channelImageUrl` (see [ChzzkChannel.avatar]).
  final String avatar;

  /// See [ChzzkApi.cover].
  final String cover;

  /// `liveCategoryValue` (when null, `liveCategory`).
  final String area;

  /// `concurrentUserCount` when `cvExposure` allows showing it.
  final int? online;

  /// `adult`: anonymous viewers get no playback.
  final bool adult;

  /// `krOnlyViewing`: only viewers in Korea get playback.
  final bool krOnly;

  /// `blindType == ABROAD`: hidden abroad.
  final bool abroadBlind;

  /// `timeMachineActive`: the live can be rewound on the website.
  final bool timeMachine;

  /// `chatChannelId` (null for a closed, region-locked or adult live).
  final String? chatChannelId;

  /// The HLS masters of `livePlaybackJson` in its order (empty when it has
  /// none, or is not usable: see [mediaError]).
  final List<ChzzkMedia> media;

  /// Why `livePlaybackJson` could not be read; room entry reports it, the
  /// room's other fields still stand.
  final SiteError? mediaError;
}

/// What room entry keeps for playback (3.x's `_ChzzkPlayback`): the
/// qualities with their lines, or why the live cannot be played.
@immutable
final class ChzzkRoomData {
  /// Creates the data; [unavailable] is required when [qualities] is empty.
  new({required this.channelId, List<LivePlayQuality> qualities = const [], this.unavailable})
    : qualities = List.unmodifiable(qualities),
      assert(qualities.isNotEmpty || unavailable != null, 'an empty playback needs its reason');

  /// The channel the playback belongs to.
  final String channelId;

  /// Best first; each quality's `data` is its `List<LivePlayLine>`.
  final List<LivePlayQuality> qualities;

  /// Why there is nothing to play (offline, region-locked, adult, no
  /// playback data).
  final SiteError? unavailable;
}

/// The chat channel of a live. 3.x had no CHZZK danmaku (`EmptyDanmaku`);
/// room entry keeps the live's `chatChannelId` (the website's chat room,
/// joined with an access token from `comm-api.game.naver.com`) for M5 to
/// decide on.
@immutable
final class ChzzkDanmakuArgs {
  /// Creates the arguments.
  const new({required this.chatChannelId});

  /// `chatChannelId` of `live-detail`.
  final String chatChannelId;

  @override
  String toString() => 'ChzzkDanmakuArgs($chatChannelId)';
}

/// One page of the popular directory (`/service/v1/lives`).
@immutable
final class ChzzkLivesPage {
  /// Creates the page.
  new({required List<LiveRoom> rooms, this.nextCursor}) : rooms = List.unmodifiable(rooms);

  /// Live cards, one per channel.
  final List<LiveRoom> rooms;

  /// The opaque cursor of the next page; null on the last.
  final String? nextCursor;

  /// Whether another page exists (3.x: a cursor and a non-empty page).
  bool get hasMore => nextCursor != null && rooms.isNotEmpty;
}

/// Pure parsing of CHZZK (치지직, NAVER) responses (3.x's `ChzzkApi` and the
/// card rules of `ChzzkSite`). Each function takes the response text and
/// status and returns 3.x's models or throws a `SiteError`.
///
/// Anonymous and public: no cookie, no signature. A room is a channel, its
/// id the 32-hex `channelId` (a live's `liveId` changes every broadcast).
/// Answers are `{code, message, content}`; only `code == 200` is a success.
abstract final class ChzzkApi {
  /// The API host.
  static const String apiHost = 'api.chzzk.naver.com';

  /// The website.
  static const String origin = 'https://chzzk.naver.com';

  /// 3.x's desktop Chrome UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's request headers, for the API and the master playlists alike.
  static const Map<String, String> headers = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': origin,
    'referer': '$origin/',
  };

  /// Media request headers (3.x's `ChzzkApi.mediaHeaders`, which its
  /// `PlaybackHeaderResolver` sent for CHZZK).
  static const Map<String, String> mediaHeaders = {'user-agent': userAgent, 'referer': '$origin/'};

  /// The largest answer read (3.x's `responseLimit`, 2 MiB).
  static const int responseLimit = 2 * 1024 * 1024;

  /// Display name (3.x's `ChzzkSite.name`).
  static const String categoryName = 'CHZZK';

  /// The one area of 3.x's catalog: the site-wide popular lives (3.x's
  /// zh.json `chzzk_public_directory`).
  static const String directoryAreaName = '公开热门直播';

  /// 3.x's zh.json `chzzk_directory_scope`, the directory notice's text.
  static const String directoryScope =
      '官方公开热门直播目录，使用包含边界项的游标分页；原生频道搜索同时返回开播和未开播频道。仅在 cvExposure 允许时展示 concurrentUserCount。';

  /// The notice of an adult live (3.x's zh.json `chzzk_adult_notice`).
  static const String adultNotice = '成人分级房间未返回公开匿名媒体源。';

  /// The notice of a region-locked live (3.x's zh.json
  /// `chzzk_region_notice`).
  static const String regionNotice = '当前地区受到播放限制。';

  /// The notice of a live the website can rewind (3.x's zh.json
  /// `chzzk_time_machine_notice`).
  static const String timeMachineNotice = '实时 HLS 已启用；独立时光机回看会话纳入下一协议批次。';

  /// Rows of a directory page (3.x's `directory` size).
  static const int pageSize = 30;

  /// The last page `getDirectoryPage` replays to (3.x).
  static const int maxDirectoryPage = 20;

  /// Rows of a search page at most (3.x).
  static const int maxSearchPageSize = 30;

  /// The longest keyword searched (3.x).
  static const int maxKeywordLength = 100;

  /// The largest search offset (3.x).
  static const int maxSearchOffset = 1000000;

  /// How long before its token expires a line is renewed (at most a quarter
  /// of its lifetime).
  static const Duration leaseLead = Duration(minutes: 10);

  static final RegExp _channelId = RegExp(r'^[a-f0-9]{32}$');

  /// Whether [text] is a channel id as 3.x checked it (lower-case only).
  static bool isChannelId(String text) => _channelId.hasMatch(text);

  /// The web page of [channelId] (3.x's `ChzzkLink.url`, the room's `link`).
  static String roomUrl(String channelId) => '$origin/live/$channelId';

  // Answers -------------------------------------------------------------------

  /// The failure of a non-200 answer as 3.x's `_read` classed it: 400 a
  /// shape error, 401/403 refused, 404 missing, 429 throttled, 5xx and
  /// anything else (3xx included: redirects are not followed) a network
  /// failure. Null for 200.
  static SiteError? statusError(int status, String what) => switch (status) {
    200 => null,
    400 => ApiChanged(_site, '$what: HTTP 400'),
    401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
    404 => NotFound(_site, '$what: HTTP 404'),
    429 => RateLimited(_site, detail: '$what: HTTP 429'),
    _ => NetworkFailure(_site, '$what: HTTP $status'),
  };

  /// The `content` of an API answer (null when the answer has none).
  static Object? content(String body, {required String what, int status = 200}) {
    if (statusError(status, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map) throw ApiChanged(_site, '$what: not a JSON object');
    final code = jsonInt(decoded['code']);
    if (code != 200) throw ApiChanged(_site, '$what: code $code ${jsonString(decoded['message']) ?? ''}'.trim());
    return decoded['content'];
  }

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<Object?> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  /// A channel id in an answer, or null.
  static String? _id(Object? value) {
    final text = value is String ? value.trim() : null;
    return text != null && isChannelId(text) ? text : null;
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  /// An image as 3.x accepted it: https on `pstatic.net` or `akamaized.net`
  /// (or their subdomains), without user info or fragment; else empty.
  static String image(Object? value) {
    if (value is! String || value.length > 8192) return '';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) return '';
    final host = uri.host.toLowerCase();
    final allowed =
        host == 'pstatic.net' ||
        host.endsWith('.pstatic.net') ||
        host == 'akamaized.net' ||
        host.endsWith('.akamaized.net');
    return allowed ? value : '';
  }

  /// A cover (REG-CHZZK-003): `liveImageUrl` with its `{type}` set to 480,
  /// else `defaultThumbnailImageUrl`; empty when neither is an [image]
  /// (adult and region-locked lives have neither).
  static String cover(Object? primary, Object? fallback) {
    for (final value in [primary, fallback]) {
      if (value is! String || value.isEmpty) continue;
      final url = image(value.replaceAll('{type}', '480'));
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  /// Concurrent viewers only when `cvExposure` is true (REG-CHZZK-002).
  static int? _online(Map<String, dynamic> data) =>
      data['cvExposure'] == true ? jsonCount(data['concurrentUserCount']) : null;

  /// `liveCategoryValue`, or `liveCategory` when it is null (3.x: an empty
  /// value stays empty).
  static String _area(Map<String, dynamic> data) => _text(data['liveCategoryValue'] ?? data['liveCategory']);

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog: one category, CHZZK, with one area, the site-wide
  /// popular lives (the platform's own categories are not used,
  /// REG-CHZZK-004 is an upgrade candidate).
  static List<LiveCategory> categories() => [
    LiveCategory(
      id: _site,
      name: categoryName,
      children: const [
        LiveArea(
          platform: _site,
          areaType: 'directory',
          typeName: categoryName,
          areaId: 'popular',
          areaName: directoryAreaName,
        ),
      ],
    ),
  ];

  /// Checks that [area] is null or 3.x's popular area; anything else is a
  /// caller error (3.x refused it before any request).
  static void checkArea(LiveArea? area) {
    if (area == null) return;
    if (area.platform != _site || area.areaType != 'directory' || area.areaId != 'popular') {
      throw ArgumentError.value(area, 'category', 'not the CHZZK popular directory');
    }
  }

  /// The cursor after the row of [viewers] and [liveId]: 3.x's opaque JSON.
  static String encodeCursor(int viewers, int liveId) => jsonEncode({'v': viewers, 'l': liveId});

  /// The row a cursor of [encodeCursor] points after; anything else is a
  /// caller error.
  static ({int viewers, int liveId}) decodeCursor(String cursor) {
    Object? decoded;
    if (cursor.length <= 128) {
      try {
        decoded = jsonDecode(cursor);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is Map && decoded.length == 2) {
      final viewers = jsonCount(decoded['v']);
      final liveId = jsonInt(decoded['l']);
      if (viewers != null && liveId != null && liveId > 0) return (viewers: viewers, liveId: liveId);
    }
    throw ArgumentError.value(cursor, 'cursor', 'not a CHZZK directory cursor');
  }

  /// The query of the directory page after [cursor] (3.x): [pageSize] rows
  /// on the first page; after a cursor one more, because 3.x took the
  /// cursor for inclusive and drops the repeated row.
  static Map<String, String> livesQuery(String? cursor) {
    if (cursor == null) return {'size': '$pageSize'};
    final after = decodeCursor(cursor);
    return {'size': '${pageSize + 1}', 'concurrentUserCount': '${after.viewers}', 'liveId': '${after.liveId}'};
  }

  /// A directory page fetched with [livesQuery] of [cursor].
  ///
  /// As 3.x: a first row that is the cursor's own live is dropped, the rest
  /// is cut to [pageSize], a channel appears once, every card is live, and
  /// the next cursor is `page.next` unless it repeats [cursor].
  ///
  /// Unlike 3.x, a row that cannot be a card (no channel id or `liveId`) is
  /// skipped instead of failing the page, an empty title is the channel
  /// name, and when rows were cut the next cursor points after the last row
  /// kept: `page.next` names the last row sent, so 3.x skipped the cut row.
  static ChzzkLivesPage lives(String body, {String? cursor, int status = 200}) {
    const what = 'lives';
    final data = _object(content(body, what: what, status: status), what);
    final after = cursor == null ? null : decodeCursor(cursor);
    final rows = <({LiveRoom room, int liveId, int? viewers})>[];
    for (final item in _list(data['data'], '$what.data')) {
      if (item is! Map) continue;
      final row = _object(item, '$what row');
      final channel = row['channel'];
      final id = channel is Map ? _id(channel['channelId']) : null;
      final liveId = jsonInt(row['liveId']);
      if (channel is! Map || id == null || liveId == null || liveId <= 0) continue;
      rows.add((
        room: _liveCard(row, _object(channel, '$what channel'), id),
        liveId: liveId,
        viewers: jsonCount(row['concurrentUserCount']),
      ));
    }
    if (after != null && rows.isNotEmpty && rows.first.liveId == after.liveId) rows.removeAt(0);
    String? next;
    if (rows.length > pageSize) {
      rows.removeRange(pageSize, rows.length);
      final last = rows.last;
      next = last.viewers == null ? null : encodeCursor(last.viewers!, last.liveId);
    }
    if (next == null) {
      final page = data['page'];
      final pointer = page is Map ? page['next'] : null;
      if (pointer is Map) {
        final viewers = jsonCount(pointer['concurrentUserCount']);
        final liveId = jsonInt(pointer['liveId']);
        if (viewers == null || liveId == null || liveId <= 0) throw ApiChanged(_site, '$what: page.next $pointer');
        next = encodeCursor(viewers, liveId);
      }
    }
    final seen = <String>{};
    return ChzzkLivesPage(
      rooms: [
        for (final row in rows)
          if (seen.add(row.room.roomId)) row.room,
      ],
      nextCursor: next == cursor ? null : next,
    );
  }

  /// A live card of the directory (3.x's `_liveCard`).
  static LiveRoom _liveCard(Map<String, dynamic> row, Map<String, dynamic> channel, String id) {
    final name = _text(channel['channelName']);
    final title = _text(row['liveTitle']);
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: id,
      nick: name,
      title: title.isEmpty ? name : title,
      avatar: image(channel['channelImageUrl']),
      cover: cover(row['liveImageUrl'], row['defaultThumbnailImageUrl']),
      area: _area(row),
      link: roomUrl(id),
      liveStatus: LiveStatus.live,
      onlineViewers: _online(row)?.toString() ?? '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: row['adult'] == true ? adultNotice : null,
    );
  }

  // Search --------------------------------------------------------------------

  /// Channel search results as cards (3.x's `_channelCard`): the title is
  /// the channel name, the cover its avatar, live by `openLive`. A result
  /// without a channel id is skipped (3.x failed the page).
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    const what = 'search/channels';
    final data = _object(content(body, what: what, status: status), what);
    return [
      for (final item in _list(data['data'], '$what.data'))
        if (item is Map && item['channel'] is Map)
          if (_channel(_object(item['channel'], '$what channel')) case final channel?) channelCard(channel),
    ];
  }

  static ChzzkChannel? _channel(Map<String, dynamic> data) {
    final id = _id(data['channelId']);
    if (id == null) return null;
    return ChzzkChannel(
      id: id,
      name: _text(data['channelName']),
      avatar: image(data['channelImageUrl']),
      description: _text(data['channelDescription']),
      followers: jsonCount(data['followerCount']),
      isLive: data['openLive'] == true,
    );
  }

  /// A channel as a card (3.x's `_channelCard`, also the room of a channel
  /// that is not live).
  static LiveRoom channelCard(ChzzkChannel channel) => LiveRoom(
    platform: _site,
    roomId: channel.id,
    userId: channel.id,
    nick: channel.name,
    title: channel.name,
    avatar: channel.avatar,
    cover: channel.avatar,
    followers: channel.followers?.toString() ?? '',
    introduction: channel.description,
    link: roomUrl(channel.id),
    liveStatus: channel.isLive ? LiveStatus.live : LiveStatus.offline,
  );

  // Rooms ---------------------------------------------------------------------

  /// The channel [channelId] from `/service/v1/channels/<id>`. The platform
  /// answers 200 for an unknown id, with a null `channelId`
  /// (`(알 수 없음)`): `NotFound`, as is a null `content`; another channel
  /// is `ApiChanged`.
  static ChzzkChannel channel(String body, {required String channelId, int status = 200}) {
    const what = 'channels';
    final data = content(body, what: what, status: status);
    if (data == null) throw NotFound(_site, '$what: no content for $channelId');
    final map = _object(data, what);
    final raw = map['channelId'];
    if (raw == null) throw NotFound(_site, '$what: channelId is null for $channelId');
    final channel = _channel(map);
    if (channel == null || channel.id != channelId) throw ApiChanged(_site, '$what: channel $raw for $channelId');
    return channel;
  }

  /// The latest live of [owner] from `v3.1 live-detail` (REG-CHZZK-001: v2
  /// answers a region-locked live with HTTP 500 / 9004); null when the
  /// channel never broadcast. HTTP 404 is `NotFound`; a live of another
  /// channel or an unknown `status` is `ApiChanged` (never taken for
  /// offline). `livePlaybackJson` is read only for an open live; when it is
  /// not usable the live keeps its other fields and the reason is
  /// [ChzzkLive.mediaError].
  static ChzzkLive? liveDetail(String body, {required ChzzkChannel owner, int status = 200}) {
    const what = 'live-detail';
    final data = content(body, what: what, status: status);
    if (data == null) return null;
    final map = _object(data, what);
    final channel = map['channel'] is Map ? _object(map['channel'], '$what channel') : null;
    if (channel != null) {
      final id = _id(channel['channelId']);
      if (id != owner.id) throw ApiChanged(_site, '$what: channel ${channel['channelId']} for ${owner.id}');
    }
    final isLive = switch (map['status']) {
      'OPEN' => true,
      'CLOSE' || 'CLOSED' => false,
      final other => throw ApiChanged(_site, '$what: status $other'),
    };
    ({List<ChzzkMedia> media, SiteError? error}) playback = (media: const [], error: null);
    if (isLive) {
      try {
        playback = (media: media(map['livePlaybackJson']), error: null);
      } on ApiChanged catch (error) {
        playback = (media: const [], error: error);
      }
    }
    final title = _text(map['liveTitle']);
    final nick = channel == null ? '' : _text(channel['channelName']);
    return ChzzkLive(
      isLive: isLive,
      title: title.isEmpty ? owner.name : title,
      nick: nick.isEmpty ? owner.name : nick,
      avatar: channel == null ? owner.avatar : image(channel['channelImageUrl']),
      cover: cover(map['liveImageUrl'], map['defaultThumbnailImageUrl']),
      area: _area(map),
      online: _online(map),
      adult: map['adult'] == true,
      krOnly: map['krOnlyViewing'] == true,
      abroadBlind: map['blindType'] == 'ABROAD',
      timeMachine: map['timeMachineActive'] == true,
      chatChannelId: jsonString(map['chatChannelId']),
      media: playback.media,
      mediaError: playback.error,
    );
  }

  /// The HLS masters of `livePlaybackJson` (3.x's `_playbackMedia`): the
  /// `HLS` and `LLHLS` items of protocol `HLS`, in its order, each master
  /// once. Absent is none; anything 3.x refused is `ApiChanged`: not a JSON
  /// string, no `media` list, an item without protocol or id, or a master
  /// that is not a plain https URL on `akamaized.net`.
  static List<ChzzkMedia> media(Object? raw) {
    const what = 'livePlaybackJson';
    if (raw == null || raw == '') return const [];
    if (raw is! String || raw.length > responseLimit) throw const ApiChanged(_site, '$what: not a JSON string');
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ApiChanged(_site, '$what: not JSON');
    }
    final items = _list(_object(decoded, what)['media'], '$what.media');
    if (items.length > 16) throw ApiChanged(_site, '$what: ${items.length} media');
    final result = <ChzzkMedia>[];
    final seen = <Uri>{};
    for (final item in items) {
      final media = _object(item, '$what item');
      final protocol = _text(media['protocol']);
      final id = _text(media['mediaId']);
      if (protocol.isEmpty || id.isEmpty) throw const ApiChanged(_site, '$what: item without protocol or mediaId');
      if (protocol != 'HLS' || (id != 'HLS' && id != 'LLHLS')) continue;
      final url = _mediaUrl(media['path']);
      if (url == null) throw ApiChanged(_site, '$what: $id path is not an Akamai URL');
      if (seen.add(url)) result.add(ChzzkMedia(id, url));
    }
    return List.unmodifiable(result);
  }

  static Uri? _mediaUrl(Object? value) {
    if (value is! String || value.isEmpty || value.length > 16384 || value.contains(RegExp(r'[\s\x00-\x1f]'))) {
      return null;
    }
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(host == 'akamaized.net' || host.endsWith('.akamaized.net'))) {
      return null;
    }
    return uri;
  }

  /// The room of [owner] and its latest [live] (3.x's `_detail` without the
  /// stream): a live that is not open (or none) is the channel card, live by
  /// the channel's `openLive`; an open live is its card with the channel's
  /// followers and introduction and 3.x's notice (region, else adult
  /// without playback, else rewindable, else adult).
  static LiveRoom room(ChzzkChannel owner, ChzzkLive? live) {
    if (live == null || !live.isLive) return channelCard(owner);
    final String? notice;
    if (live.krOnly) {
      notice = regionNotice;
    } else if (live.adult && live.media.isEmpty) {
      notice = adultNotice;
    } else if (live.timeMachine) {
      notice = timeMachineNotice;
    } else {
      notice = live.adult ? adultNotice : null;
    }
    return LiveRoom(
      platform: _site,
      roomId: owner.id,
      userId: owner.id,
      nick: live.nick,
      title: live.title,
      avatar: live.avatar,
      cover: live.cover,
      area: live.area,
      link: roomUrl(owner.id),
      liveStatus: LiveStatus.live,
      onlineViewers: live.online?.toString() ?? '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: owner.followers?.toString() ?? '',
      introduction: owner.description,
      notice: notice,
    );
  }

  /// Why [live] has nothing to play: not live `StreamUnavailable`,
  /// region-locked (`krOnlyViewing`, or hidden abroad) `RegionBlocked`,
  /// adult `NeedsLogin`, anything else (a paid live...) `StreamUnavailable`.
  static SiteError unavailable(ChzzkLive? live) {
    if (live == null || !live.isLive) return const StreamUnavailable(_site, 'not live');
    if (live.mediaError case final error?) return error;
    if (live.krOnly || live.abroadBlind) return const RegionBlocked(_site, 'krOnlyViewing');
    if (live.adult) return const NeedsLogin(_site, 'adult live');
    return const StreamUnavailable(_site, 'live without playback');
  }

  // Streams -------------------------------------------------------------------

  /// A master playlist answer: its text, or the failure. The master is part
  /// of the live, so a missing one (404) means the stream is gone.
  static String master(String body, {required String what, int status = 200}) {
    if (status == 404) throw StreamUnavailable(_site, '$what: HTTP 404');
    if (statusError(status, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    return body;
  }

  /// 3.x's qualities from the fetched [masters] (in media order: `HLS`,
  /// `LLHLS`): one per `<height>p`, plus `60` at 50 fps or more, named
  /// `<id> · HLS`, ranked by height, then by the bandwidth of its first
  /// variant, best first. Each quality holds its lines (`data`), one per
  /// variant URL in master order: the line id is the media id, the headers
  /// are [mediaHeaders], the codec is the variant's and the lease that of
  /// its token. A master the shared parser refuses is `ApiChanged` (as in
  /// 3.x); a variant without a resolution (audio only, which failed 3.x's
  /// room) is left out; no video variant at all is `StreamUnavailable`.
  static List<LivePlayQuality> qualities(
    List<({ChzzkMedia media, String body})> masters, {
    required DateTime issuedAt,
  }) {
    final builders = <String, ({int rank, List<LivePlayLine> lines})>{};
    for (final master in masters) {
      final HlsMasterPlaylist playlist;
      try {
        playlist = HlsMasterPlaylist.parse(master.media.url, master.body);
      } on FormatException catch (error) {
        throw ApiChanged(_site, '${master.media.id} master: ${error.message}');
      }
      for (final variant in playlist.variants) {
        final height = int.tryParse((variant.attributes['RESOLUTION'] ?? '').split('x').last) ?? 0;
        if (height <= 0) continue;
        final frameRate = double.tryParse(variant.attributes['FRAME-RATE'] ?? '') ?? 0;
        final bandwidth = int.parse(variant.attributes['BANDWIDTH']!);
        final id = '${height}p${frameRate >= 50 ? '60' : ''}';
        final builder = builders.putIfAbsent(id, () => (rank: height * 10000000 + bandwidth, lines: []));
        final url = variant.uri.toString();
        if (builder.lines.any((line) => line.url == url)) continue;
        builder.lines.add(
          LivePlayLine(
            url,
            headers: mediaHeaders,
            format: StreamFormat.hls,
            codec: codecOf(variant.attributes['CODECS']),
            lineId: master.media.id,
            lease: lease(variant.uri, master: master.media.url, issuedAt: issuedAt),
          ),
        );
      }
    }
    final qualities = [
      for (final MapEntry(key: id, value: builder) in builders.entries)
        LivePlayQuality(
          quality: '$id · HLS',
          id: id,
          sort: builder.rank,
          data: List<LivePlayLine>.unmodifiable(builder.lines),
        ),
    ]..sort((a, b) => b.sort.compareTo(a.sort));
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no video variant');
    return List.unmodifiable(qualities);
  }

  /// The video codec of a `CODECS` attribute: `avc` or `hevc`, else null.
  static String? codecOf(String? codecs) {
    for (final name in (codecs ?? '').split(',')) {
      final codec = name.trim().toLowerCase();
      if (codec.startsWith('avc1') || codec.startsWith('avc3')) return 'avc';
      if (codec.startsWith('hvc1') || codec.startsWith('hev1')) return 'hevc';
    }
    return null;
  }

  static final RegExp _variantExpiry = RegExp(r'hdntl=exp=(\d{9,12})');
  static final RegExp _masterExpiry = RegExp(r'(?:^|~)exp=(\d{9,12})');

  /// The lease of a variant issued at [issuedAt]: its Akamai token expires
  /// at the `exp` of the variant path's `hdntl`, else of the master's
  /// `hdnts` (about 17 hours after issue); it is renewed [leaseLead] (at
  /// most a quarter of its lifetime) before. Each HLS segment is a new
  /// request, so expiry ends playback. Null without a future expiry. (3.x
  /// had no lease: it fetched the room again after a failure.)
  static PlayLease? lease(Uri variant, {required Uri master, required DateTime issuedAt}) {
    var exp = _variantExpiry.firstMatch(variant.path)?.group(1);
    if (exp == null) {
      try {
        exp = _masterExpiry.firstMatch(master.queryParameters['hdnts'] ?? '')?.group(1);
      } on FormatException {
        exp = null;
      }
    }
    if (exp == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = Duration(microseconds: math.min(leaseLead.inMicroseconds, lifetime.inMicroseconds ~/ 4));
    return PlayLease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: true);
  }

  /// The lines of [quality] (by its id) among [data]'s qualities, applied as
  /// asked; a quality the live does not offer is `StreamUnavailable`, and a
  /// live with nothing to play reports why.
  static LivePlayUrlResolution resolution(ChzzkRoomData data, LivePlayQuality quality) {
    final offered = playQualities(data);
    final wanted = '${quality.selectionId}';
    final match = offered.where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (match == null) throw StreamUnavailable(_site, 'quality $wanted is not offered');
    return LivePlayUrlResolution.lines(match.data! as List<LivePlayLine>, appliedQualityData: match.selectionId);
  }

  /// [data]'s qualities, or why there are none.
  static List<LivePlayQuality> playQualities(ChzzkRoomData data) {
    if (data.qualities.isNotEmpty) return data.qualities;
    throw data.unavailable ?? const StreamUnavailable(_site, 'no quality');
  }

  // Links ---------------------------------------------------------------------

  /// The channel of a live page (3.x's `ChzzkLink.parse`): http(s) on
  /// `chzzk.naver.com` exactly, without user info, the path `/live/<id>`
  /// (empty segments ignored), the id in any case; returned in lower case.
  /// Other pages (the channel page `/<id>`, `m.chzzk.naver.com`) are not
  /// rooms, as in 3.x.
  static String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'chzzk.naver.com') {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    if (segments.length != 2 || segments.first != 'live') return null;
    final id = segments[1].trim().toLowerCase();
    return isChannelId(id) ? id : null;
  }
}
