import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'sixroom';

/// A room's state as 3.x read the inroom answer.
enum SixRoomState {
  /// A live id and a stream name.
  live,

  /// Neither.
  offline,

  /// A private room (`isPriveRoom`) or a black screen
  /// (`blackScreenInfo.msg`): 3.x shows it as unknown with its own notice,
  /// never as offline.
  restricted,

  /// A search card: the result page says nothing 3.x read.
  unknown,
}

/// The one FLV stream of a live room (3.x's `SixRoomVariant` `flv:source`):
/// `https://wlive.6rooms.com/httpflv/<stream name>.flv`, and what the
/// answer's `streamInfo` says about it.
@immutable
final class SixRoomStream {
  /// Creates the stream.
  const new({required this.url, this.resolution = '', this.bitrate, this.codec});

  /// The FLV URL; not signed, no expiry.
  final Uri url;

  /// `streamInfo.resolution` (`1024x768`), or ''.
  final String resolution;

  /// `streamInfo.videoBitrate` (else `bitrate`) in kbps, when given.
  final int? bitrate;

  /// The video codec of `streamInfo.videoCodec` (`avc`, `hevc`), when known.
  final String? codec;
}

/// One room as 3.x's `SixRoomRoom` held it: a homepage card, a search card,
/// or a room read from the inroom answer.
@immutable
final class SixRoomRoom {
  /// Creates the room.
  const new({
    required this.roomId,
    required this.userId,
    required this.nick,
    required this.title,
    required this.state,
    this.liveId = '',
    this.avatar = '',
    this.cover = '',
    this.category = '',
    this.popularity,
    this.followers,
    this.ownerAvatar = '',
    this.stream,
    this.mediaError,
  });

  /// The room number (`rid`): the room's identity.
  final String roomId;

  /// The broadcaster's user id (`uid`, inroom `ruid`).
  final String userId;

  /// The broadcast id (`liveid`); '' when not live or not given.
  final String liveId;

  /// The broadcaster's name, or [SixRoomApi.placeholder].
  final String nick;

  /// The title, else the mood, else the name (3.x), or
  /// [SixRoomApi.placeholder].
  final String title;

  /// The avatar 3.x read (the homepage's `picuser`, the search card's image,
  /// inroom `headPicUrl` or `picuser`); ''.
  final String avatar;

  /// The poster; ''.
  final String cover;

  /// The area (`anchor_area`, else `rtypename`); ''.
  final String category;

  /// The homepage's `count`, platform popularity; null when not given.
  final int? popularity;

  /// Inroom `fans_num`; null when not given.
  final int? followers;

  /// The state.
  final SixRoomState state;

  /// Inroom `roominfo.uoption.picuser`, the broadcaster's avatar where 3.x
  /// did not look: shown only when there is neither [avatar] nor [cover].
  final String ownerAvatar;

  /// The live room's stream, read on room entry and for recording (3.x's
  /// `includeMedia`); null otherwise.
  final SixRoomStream? stream;

  /// Why a live room read with its media has no [stream]: a stream name
  /// that does not match the broadcaster and broadcast (3.x left the room
  /// without variants).
  final SiteError? mediaError;

  /// This room with the fields its answer lacks taken from [known], an
  /// earlier card or room of the same room (3.x's `enrich`): the user and
  /// live ids, avatars, cover and area when empty, the name and title when
  /// they are the placeholder, popularity and followers when not given, the
  /// state when unknown. The media stay this room's.
  SixRoomRoom enrich(SixRoomRoom known) => SixRoomRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    liveId: liveId.isEmpty ? known.liveId : liveId,
    nick: nick == SixRoomApi.placeholder ? known.nick : nick,
    title: title == SixRoomApi.placeholder ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    category: category.isEmpty ? known.category : category,
    popularity: popularity ?? known.popularity,
    followers: followers ?? known.followers,
    state: state == SixRoomState.unknown ? known.state : state,
    ownerAvatar: ownerAvatar.isEmpty ? known.ownerAvatar : ownerAvatar,
    stream: stream,
    mediaError: mediaError,
  );
}

/// What a room detail carries besides 3.x's fields: the broadcaster, the
/// state and, on room entry and for recording, the stream. The interface
/// shows the notice of [state] in its own language (M13).
@immutable
final class SixRoomRoomData {
  /// Creates the data.
  const new({
    required this.roomId,
    required this.userId,
    required this.state,
    this.liveId = '',
    this.stream,
    this.mediaError,
  });

  /// The room number.
  final String roomId;

  /// The broadcaster's user id (inroom `ruid`).
  final String userId;

  /// The broadcast id; '' when not live.
  final String liveId;

  /// The state.
  final SixRoomState state;

  /// The FLV stream, read on room entry and for recording; null for a
  /// refresh (3.x left refreshed rooms without data).
  final SixRoomStream? stream;

  /// Why the live room has no stream, when its stream name is unusable.
  final SiteError? mediaError;

  /// Why this room cannot be played, or null: not live (offline, private or
  /// black screen, unknown) is `StreamUnavailable`; a live one with an
  /// unusable stream name says so; a live one read without its stream (a
  /// refresh) is `StreamUnavailable` until the room is entered.
  SiteError? get streamError => switch (state) {
    SixRoomState.offline => StreamUnavailable(_site, '$roomId is offline'),
    SixRoomState.restricted => StreamUnavailable(_site, '$roomId is private or behind a black screen'),
    SixRoomState.unknown => StreamUnavailable(_site, '$roomId: state unknown'),
    SixRoomState.live when mediaError != null => mediaError,
    SixRoomState.live when stream == null => StreamUnavailable(
      _site,
      '$roomId: read without its stream; enter the room',
    ),
    SixRoomState.live => null,
  };
}

/// What the danmaku module needs for a room (M5): the room number and the
/// broadcaster's user id. 3.x had no Six Rooms chat (`EmptyDanmaku`); the
/// room page's chat is a private WebSocket (archive spec §7). Whether the
/// app shows it is the danmaku module's decision; room entry only hands the
/// ids over, without a request.
@immutable
final class SixRoomDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId, required this.userId});

  /// The room number.
  final String roomId;

  /// The broadcaster's user id.
  final String userId;

  @override
  String toString() => '$roomId/$userId';
}

/// One of 3.x's six areas: its id, name and the homepage `anchor_area` it
/// keeps (null for all rooms).
typedef _Area = ({String id, String name, String? anchorArea});

/// Pure parsing of 6.cn answers (3.x's `SixRoomApi`, `SixRoomLink` and the
/// models of its `SixRoomSite`). Each function takes the answer and its
/// status and returns 3.x's models or throws a `SiteError`.
abstract final class SixRoomApi {
  /// The web origin.
  static const String origin = 'https://v.6.cn';

  /// 3.x's browser user agent of the homepage, search and room pages.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's iOS client user agent of the inroom request.
  static const String mobileUserAgent = 'ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))';

  /// The largest answer 3.x read, in UTF-8 bytes.
  static const int responseLimit = 8 * 1024 * 1024;

  /// How long 3.x reused the homepage for category pages and later pages.
  static const Duration directoryCacheLifetime = Duration(seconds: 90);

  /// The platform's name (3.x's zh.json `site_sixroom`): the category, the
  /// areas' type and the area of a room without one.
  static const String siteName = '六间房直播';

  /// `areaType` of the areas.
  static const String areaType = 'official';

  /// 3.x's name and title of a room without them.
  static const String placeholder = 'Six Rooms';

  /// Rooms per directory page (3.x's `getDirectoryPage`).
  static const int pageSize = 30;

  /// The last directory page 3.x asked for.
  static const int maxPage = 10000;

  /// The largest page size of 3.x's lists and search.
  static const int maxPageSize = 100;

  /// The longest keyword 3.x sent; 6.cn itself takes 15 characters.
  static const int maxKeywordLength = 80;

  /// The notice of every room (3.x's zh.json `sixroom_chat_notice`).
  static const String chatNotice = '六间房远端聊天尚待接入；大厅 count 保留为平台热度，不标记为唯一并发人数，主播粉丝数单独展示。';

  /// The notice of a private or black-screen room, before [chatNotice]
  /// (`sixroom_restricted_notice`).
  static const String restrictedNotice = '该六间房直播受私密房或黑屏访问条件限制，界面保持未知状态，不将其显示成未开播。';

  /// Id of the one quality.
  static const String qualityId = 'flv:source';

  /// The one quality's name (`sixroom_quality_source`); with the resolution
  /// and bitrate `FLV 原始线路 · 1024x768 · 2652 kbps`
  /// (`sixroom_quality_source_detail`).
  static const String qualityName = 'FLV 原始线路';

  /// The one line's id: the FLV host.
  static const String lineId = 'wlive';

  static const List<_Area> _areas = [
    (id: 'all', name: '全部', anchorArea: null),
    (id: 'song', name: '歌区', anchorArea: '歌区'),
    (id: 'dance', name: '舞区', anchorArea: '舞区'),
    (id: 'talk', name: '脱口秀', anchorArea: '脱口秀'),
    (id: 'face', name: '星颜', anchorArea: '星颜'),
    (id: 'party', name: '派对', anchorArea: '派对'),
  ];

  /// The headers of the homepage, search and room pages (3.x's
  /// `webHeaders`).
  static const Map<String, String> webHeaders = {
    'user-agent': userAgent,
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'referer': '$origin/',
  };

  /// The headers of the inroom request (3.x's `mobileHeaders`, and the form
  /// type Dio added).
  static const Map<String, String> mobileHeaders = {
    'user-agent': mobileUserAgent,
    'accept': 'application/json,text/plain,*/*',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'referer': 'https://ios.6.cn/?ver=8.0.3&build=4',
    'content-type': 'application/x-www-form-urlencoded',
  };

  /// 3.x's `mediaHeaders`, written into rooms (`httpHeaders`, in 3.x's
  /// JSON). Its player and recorder sent none of them
  /// (`PlaybackHeaderResolver` had no Six Rooms branch), so lines carry none
  /// either.
  static Map<String, String> mediaHeaders(String roomId) => {
    'user-agent': mobileUserAgent,
    'origin': origin,
    'referer': link(roomId),
  };

  // Links ---------------------------------------------------------------------

  static final RegExp _roomId = RegExp(r'^[1-9]\d{1,11}$');
  static final RegExp _userId = RegExp(r'^[1-9]\d{1,12}$');

  /// Whether [value] is a broadcaster's user id (3.x's `_validUserId`).
  static bool isUserId(String? value) => value != null && _userId.hasMatch(value.trim());

  /// The room of [raw] (3.x's `SixRoomLink.parseRoomId`): a room number
  /// (2–12 digits, not starting with 0), or an http(s) link on `v.6.cn` or
  /// `m.6.cn` (no user info, no fragment, the default ports) whose path is
  /// `/<number>` or `/profile/<number>`; null for anything else.
  static String? roomIdOf(String raw) {
    final value = raw.trim();
    if (_roomId.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        !const {'v.6.cn', 'm.6.cn'}.contains(uri.host.toLowerCase()) ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((part) => part.isNotEmpty).toList(growable: false);
    } on FormatException {
      // `%FF` decodes to no text (3.x threw here).
      return null;
    }
    return switch (segments) {
      [final id] when _roomId.hasMatch(id) => id,
      [final profile, final id] when profile.toLowerCase() == 'profile' && _roomId.hasMatch(id) => id,
      _ => null,
    };
  }

  /// The room page of [roomId] (3.x's `watchUrl`), also the room's link.
  static String link(String roomId) => '$origin/$roomId';

  static String _requireRoomId(String raw) =>
      roomIdOf(raw) ?? (throw ArgumentError.value(raw, 'roomId', 'not a Six Rooms room'));

  // Requests ------------------------------------------------------------------

  /// The homepage: every live room, in `window.__SMARTY_ALL_VARIABLES__`.
  static final Uri homeUrl = Uri.parse('$origin/');

  /// The search page for [keyword].
  static Uri searchUrl(String keyword) =>
      Uri.parse('$origin/search.php').replace(queryParameters: {'type': 'use', 'key': keyword});

  /// The room page of [roomId] (for its broadcaster's user id).
  static Uri roomUrl(String roomId) => Uri.parse(link(roomId));

  /// The mobile inroom request (a form POST).
  static final Uri inroomUrl = Uri.parse('$origin/coop/mobile/index.php?padapi=coop-mobile-inroom.php');

  /// The inroom form of [userId]'s room (3.x's fields, in its order).
  static Map<String, String> inroomForm(String userId) => {
    'av': '3.1',
    'encpass': '',
    'logiuid': '',
    'project': 'v6iphone',
    'rate': '1',
    'rid': '',
    'ruid': userId,
  };

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `六间房直播` with the first [limit] of its areas
  /// (全部, 歌区, 舞区, 脱口秀, 星颜, 派对).
  static List<LiveCategory> categories({int limit = 6}) => [
    LiveCategory(
      id: _site,
      name: siteName,
      children: [
        for (final area in _areas.take(limit))
          LiveArea(platform: _site, areaType: areaType, typeName: siteName, areaId: area.id, areaName: area.name),
      ],
    ),
  ];

  /// The area id of [category] (null is all rooms), or null when it is not
  /// one of 3.x's areas (another platform or type, an unknown id). The id
  /// is trimmed (3.x).
  static String? areaIdOf(LiveArea? category) {
    if (category == null) return 'all';
    if (category.platform != _site || category.areaType != areaType) return null;
    final id = category.areaId.trim();
    return _areas.any((area) => area.id == id) ? id : null;
  }

  /// The rooms of [rooms] in area [areaId]: all, or those whose area is the
  /// area's name (3.x filtered the homepage locally).
  static List<SixRoomRoom> inArea(List<SixRoomRoom> rooms, String areaId) {
    final anchorArea = _areas.firstWhere((area) => area.id == areaId).anchorArea;
    return anchorArea == null
        ? rooms
        : [
            for (final room in rooms)
              if (room.category == anchorArea) room,
          ];
  }

  // Directory -----------------------------------------------------------------

  /// The homepage's rooms (3.x's `parseDirectoryHtml`): the embedded
  /// `typeList` (JSON, or JSON text), in its order, once per room; a row
  /// needs a room number and a user id. Name, title (else mood, else name),
  /// avatar, cover (`pospic`, `pic`, `pospic_sp`), area and `count` as
  /// popularity; all live. No room at all is `ApiChanged`.
  static List<SixRoomRoom> directory(String body, {int status = 200}) {
    const what = 'homepage';
    _checkStatus(body, status: status, what: what);
    final root = _embeddedRoot(body);
    var rows = root['typeList'];
    if (rows is String) {
      try {
        rows = jsonDecode(rows);
      } on FormatException {
        throw const ApiChanged(_site, '$what: typeList is not JSON');
      }
    }
    if (rows is! List) throw const ApiChanged(_site, '$what: no typeList');
    final seen = <String>{};
    final rooms = <SixRoomRoom>[];
    for (final value in rows) {
      final row = _map(value);
      if (row == null) continue;
      final roomId = _string(row['rid']);
      final userId = _string(row['uid']);
      if (roomIdOf(roomId) != roomId || !isUserId(userId) || !seen.add(roomId)) continue;
      final nick = _text(row['username'], fallback: placeholder);
      rooms.add(
        SixRoomRoom(
          roomId: roomId,
          userId: userId,
          liveId: _string(row['liveid'] ?? row['lid']),
          nick: nick,
          title: _firstText([row['livetitle'], row['userMood'], nick], fallback: placeholder),
          avatar: _image(row['picuser']),
          cover: _firstImage([row['pospic'], row['pic'], row['pospic_sp']]),
          category: _text(row['anchor_area']),
          popularity: _count(row['count']),
          state: SixRoomState.live,
        ),
      );
    }
    if (rooms.isEmpty) throw const ApiChanged(_site, '$what: typeList has no room');
    return List.unmodifiable(rooms);
  }

  /// The object after `window.__SMARTY_ALL_VARIABLES__ = ` (3.x's
  /// `_decodeEmbeddedRoot`: braces counted outside double-quoted strings).
  static Map<String, dynamic> _embeddedRoot(String body) {
    const marker = 'window.__SMARTY_ALL_VARIABLES__ = ';
    final at = body.indexOf(marker);
    final start = at < 0 ? -1 : body.indexOf('{', at + marker.length);
    if (start < 0) throw const ApiChanged(_site, 'homepage: no __SMARTY_ALL_VARIABLES__');
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = start; index < body.length; index++) {
      final code = body.codeUnitAt(index);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          quoted = false;
        }
        continue;
      }
      if (code == 0x22) {
        quoted = true;
      } else if (code == 0x7b) {
        depth++;
      } else if (code == 0x7d && --depth == 0) {
        return _decodeObject(body.substring(start, index + 1), 'homepage variables');
      }
    }
    throw const ApiChanged(_site, 'homepage: __SMARTY_ALL_VARIABLES__ does not end');
  }

  // Search --------------------------------------------------------------------

  /// The search page (3.x's `parseSearchHtml`): one card per
  /// `ul.search-user > li[data-uid]` of the `page-search-user` block, once
  /// per room: the user id, the room of the `a.user-box` link, the name
  /// (`.alias`) as name and title, the image of `.pic img` (`data-src`,
  /// else `src`) as avatar; state unknown (3.x read no live mark). 6.cn's
  /// "输入内容过长" page (a keyword over 15 characters) is no result; any
  /// other prompt page is `RiskControl` (3.x's `access`), anything else
  /// `ApiChanged`.
  static List<SixRoomRoom> search(String body, {int status = 200}) {
    const what = 'search page';
    _checkStatus(body, status: status, what: what);
    final root = HtmlElement.parseFragment(body);
    final page = root.query((element) => element.hasClass('page-search-user'));
    if (page == null) {
      final remind = root.query((element) => element.hasClass('remind'));
      if (remind == null) throw const ApiChanged(_site, '$what: no page-search-user');
      final message = _text(remind.query((element) => element.hasClass('rcontent'))?.text);
      if (message.contains('过长')) return const [];
      throw RiskControl(_site, detail: '$what: $message');
    }
    final seen = <String>{};
    final rooms = <SixRoomRoom>[];
    final items = page.queryAll(
      (element) =>
          element.tag == 'li' &&
          element.attributes.containsKey('data-uid') &&
          element.parent?.tag == 'ul' &&
          (element.parent?.hasClass('search-user') ?? false),
    );
    for (final item in items) {
      final userId = item.attributes['data-uid']!.trim();
      final href = item.query((element) => element.tag == 'a' && element.hasClass('user-box'))?.attributes['href'];
      final String? roomId;
      try {
        roomId = roomIdOf('${Uri.parse(origin).resolve(href ?? '')}');
      } on FormatException {
        continue;
      }
      if (roomId == null || !isUserId(userId) || !seen.add(roomId)) continue;
      final image = item.query(
        (element) =>
            element.tag == 'img' &&
            element.ancestors
                .takeWhile((ancestor) => !identical(ancestor, item))
                .any((ancestor) => ancestor.hasClass('pic')),
      );
      final nick = _text(item.query((element) => element.hasClass('alias'))?.text, fallback: placeholder);
      rooms.add(
        SixRoomRoom(
          roomId: roomId,
          userId: userId,
          nick: nick,
          title: nick,
          avatar: _firstImage([image?.attributes['data-src'], image?.attributes['src']]),
          state: SixRoomState.unknown,
        ),
      );
    }
    return List.unmodifiable(rooms);
  }

  // Room ----------------------------------------------------------------------

  /// `rid: '<user id>', roomid: <room number>` in the room page's script.
  /// 3.x required the room number quoted; the page now writes it as a
  /// number (both are accepted).
  static final RegExp _pageIds = RegExp(
    r'''\brid\s*:\s*['"]([1-9]\d{1,12})['"]\s*,\s*roomid\s*:\s*['"]?([1-9]\d{1,11})(?!\d)['"]?''',
  );

  /// The broadcaster's user id on the room page of [roomId] (a room number
  /// or link; 3.x's `parseRoomUserIdHtml`): the canonical link must be the
  /// room; a page without it is `NotFound` when it is a prompt page or
  /// short, else `ApiChanged`. The id is the `rid` next to the room's
  /// `roomid`. A [roomId] that is no room is a caller error.
  static String userIdOf(String body, {required String roomId, int status = 200}) {
    const what = 'room page';
    final id = _requireRoomId(roomId);
    _checkStatus(body, status: status, what: what);
    final root = HtmlElement.parseFragment(body);
    final canonical = root.query((element) => element.tag == 'link' && element.attributes['rel'] == 'canonical');
    if (roomIdOf(canonical?.attributes['href'] ?? '') != id) {
      if (root.query((element) => element.hasClass('remind')) != null || body.length < 4096) {
        throw NotFound(_site, '$what of $id: no such room');
      }
      throw ApiChanged(_site, '$what of $id: canonical ${canonical?.attributes['href']}');
    }
    for (final match in _pageIds.allMatches(body)) {
      if (match.group(2) == id) return match.group(1)!;
    }
    throw ApiChanged(_site, '$what of $id: no rid/roomid');
  }

  /// The inroom answer of room [roomId] and broadcaster [userId] (3.x's
  /// `parseRoomJson`): `flag` `001`, else 402 is `NotFound` (6.cn's "暂不能
  /// 进入此房间", sample S05-inroom-missing), another flag `RiskControl`
  /// (3.x's `access`), none `ApiChanged`. The room and broadcaster must be
  /// the ones asked. Private or black screen is restricted; a live id and a
  /// stream name are live; else offline. With [media], a live room's stream
  /// (`v<user id>-<live id>[-many]`, else [SixRoomRoom.mediaError]). A
  /// [roomId] (number or link) or [userId] that is no id is a caller error.
  static SixRoomRoom room(
    String body, {
    required String roomId,
    required String userId,
    bool media = true,
    int status = 200,
  }) {
    const what = 'inroom';
    final id = _requireRoomId(roomId);
    if (!isUserId(userId)) throw ArgumentError.value(userId, 'userId', 'not a Six Rooms user id');
    final uid = userId.trim();
    _checkStatus(body, status: status, what: what);
    final root = _decodeObject(body, what);
    final flag = root['flag'];
    if (flag is! String) throw ApiChanged(_site, '$what: flag is $flag');
    if (flag != '001') {
      final message = _text(root['content']);
      if (flag == '402') throw NotFound(_site, '$what of $uid: $message');
      throw RiskControl(_site, detail: '$what of $uid: flag $flag $message');
    }
    final content = _map(root['content']);
    final roomInfo = _map(content?['roominfo']);
    final liveInfo = _map(content?['liveinfo']);
    final params = _map(content?['roomParamInfo']);
    if (content == null || roomInfo == null || liveInfo == null || params == null) {
      throw const ApiChanged(_site, '$what: no roominfo, liveinfo or roomParamInfo');
    }
    final actualRoomId = _string(roomInfo['rid']);
    final actualUserId = _string(roomInfo['id'] ?? params['uid']);
    if (actualRoomId != id || actualUserId != uid) {
      throw ApiChanged(_site, '$what of $id/$uid names $actualRoomId/$actualUserId');
    }
    final liveId = _string(liveInfo['id']);
    final flvTitle = _string(liveInfo['flvtitle']);
    final restricted = _truthy(content['isPriveRoom']) || _text(_map(content['blackScreenInfo'])?['msg']).isNotEmpty;
    final state = restricted
        ? SixRoomState.restricted
        : liveId.isNotEmpty && flvTitle.isNotEmpty
        ? SixRoomState.live
        : SixRoomState.offline;
    final nick = _text(roomInfo['alias'], fallback: placeholder);
    SixRoomStream? stream;
    SiteError? mediaError;
    if (media && state == SixRoomState.live) {
      final url = mediaUri(userId: actualUserId, liveId: liveId, flvTitle: flvTitle);
      if (url == null) {
        mediaError = ApiChanged(_site, '$what of $id: stream name $flvTitle for live $liveId');
      } else {
        final info = _streamInfo(liveInfo, flvTitle);
        stream = SixRoomStream(
          url: url,
          resolution: _text(info?['resolution']),
          bitrate: _count(info?['videoBitrate'] ?? info?['bitrate']),
          codec: switch (_string(info?['videoCodec']).toLowerCase()) {
            'avc' || 'h264' => 'avc',
            'hevc' || 'h265' => 'hevc',
            _ => null,
          },
        );
      }
    }
    return SixRoomRoom(
      roomId: id,
      userId: actualUserId,
      liveId: liveId,
      nick: nick,
      title: _firstText([liveInfo['title'], roomInfo['userMood'], nick], fallback: placeholder),
      avatar: _firstImage([roomInfo['headPicUrl'], roomInfo['picuser']]),
      cover: _firstImage([liveInfo['spredPic'], liveInfo['pospic'], liveInfo['largepic'], liveInfo['pic']]),
      category: _firstText([roomInfo['anchor_area'], roomInfo['rtypename']]),
      followers: _count(params['fans_num']),
      state: state,
      ownerAvatar: _image(_map(roomInfo['uoption'])?['picuser']),
      stream: stream,
      mediaError: mediaError,
    );
  }

  /// 3.x's `mediaUri`: `https://wlive.6rooms.com/httpflv/<name>.flv` when
  /// [userId] and [liveId] are ids and [flvTitle] is
  /// `v<userId>-<liveId>`, optionally with `-many`; null otherwise.
  static Uri? mediaUri({required String userId, required String liveId, required String flvTitle}) {
    if (!isUserId(userId) || !isUserId(liveId)) return null;
    if (!RegExp('^v${RegExp.escape(userId)}-${RegExp.escape(liveId)}(?:-many)?\$').hasMatch(flvTitle)) return null;
    return Uri.parse('https://wlive.6rooms.com/httpflv/$flvTitle.flv');
  }

  /// `streamInfo[flvTitle]` of any lane of `liveinfo.content`.
  static Map<String, dynamic>? _streamInfo(Map<String, dynamic> liveInfo, String flvTitle) {
    final lanes = _map(liveInfo['content']);
    if (lanes == null) return null;
    for (final lane in lanes.values) {
      final info = _map(_map(_map(lane)?['streamInfo'])?[flvTitle]);
      if (info != null) return info;
    }
    return null;
  }

  // Rooms, qualities and lines ------------------------------------------------

  /// The card or room of [room] (3.x's `_room`): the avatar, else the cover
  /// (what 3.x showed: inroom has no avatar where 3.x looked), else
  /// [SixRoomRoom.ownerAvatar]; the area, else [siteName]; the popularity
  /// as the audience; followers; the state (restricted and unknown are
  /// unknown, never offline); 3.x's notice and headers; [data] and
  /// [danmaku] as given.
  static LiveRoom liveRoom(SixRoomRoom room, {SixRoomRoomData? data, SixRoomDanmakuArgs? danmaku}) {
    final popularity = room.popularity?.toString() ?? '';
    return LiveRoom(
      roomId: room.roomId,
      platform: _site,
      userId: room.userId,
      link: link(room.roomId),
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isNotEmpty
          ? room.avatar
          : room.cover.isNotEmpty
          ? room.cover
          : room.ownerAvatar,
      cover: room.cover,
      area: room.category.isEmpty ? siteName : room.category,
      watching: popularity,
      popularity: popularity,
      followers: room.followers?.toString() ?? '',
      audienceMetricType: room.popularity == null ? AudienceMetricType.unknown : AudienceMetricType.popularity,
      liveStatus: switch (room.state) {
        SixRoomState.live => LiveStatus.live,
        SixRoomState.offline => LiveStatus.offline,
        SixRoomState.restricted || SixRoomState.unknown => LiveStatus.unknown,
      },
      notice: room.state == SixRoomState.restricted ? '$restrictedNotice\n$chatNotice' : chatNotice,
      httpHeaders: mediaHeaders(room.roomId),
      data: data,
      danmakuData: danmaku,
    );
  }

  /// The room data of [room].
  static SixRoomRoomData roomData(SixRoomRoom room) => SixRoomRoomData(
    roomId: room.roomId,
    userId: room.userId,
    liveId: room.liveId,
    state: room.state,
    stream: room.stream,
    mediaError: room.mediaError,
  );

  /// 3.x's one quality of [stream]: `FLV 原始线路`, with the resolution and
  /// bitrate when known; ordered by bitrate (1 without).
  static LivePlayQuality quality(SixRoomStream stream) {
    final detail = [
      if (stream.resolution.isNotEmpty) stream.resolution,
      if (stream.bitrate != null) '${stream.bitrate} kbps',
    ];
    return LivePlayQuality(
      quality: detail.isEmpty ? qualityName : '$qualityName · ${detail.join(' · ')}',
      id: qualityId,
      sort: stream.bitrate ?? 1,
    );
  }

  /// The one line of [stream]: FLV, its codec, no headers (3.x's player and
  /// recorder sent none; the CDN answers without them, 2026-09-28) and no
  /// lease (no expiry in the address).
  static LivePlayLine line(SixRoomStream stream) =>
      LivePlayLine('${stream.url}', format: StreamFormat.flv, codec: stream.codec, lineId: lineId);
}

/// The JSON object [body], or `ApiChanged`.
Map<String, dynamic> _decodeObject(String body, String what) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  return _map(decoded) ?? (throw ApiChanged(_site, '$what: not an object'));
}

/// [value] as a map with text keys, or null (3.x's `_map`).
Map<String, dynamic>? _map(Object? value) =>
    value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

/// 3.x's `_string`: any value as trimmed text; '' for null.
String _string(Object? value) => value?.toString().trim() ?? '';

/// 3.x's `_text`: [_string] with runs of white space made one space, or
/// [fallback] when empty.
String _text(Object? value, {String fallback = ''}) {
  final text = _string(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? fallback : text;
}

/// The first non-empty [_text] of [values], or [fallback].
String _firstText(Iterable<Object?> values, {String fallback = ''}) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

/// 3.x's `_integer`: an integer or number (truncated), or integer text with
/// `,` separators, when zero or more; null otherwise.
int? _count(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num) return value >= 0 ? value.toInt() : null;
  final parsed = int.tryParse(_string(value).replaceAll(',', ''));
  return parsed != null && parsed >= 0 ? parsed : null;
}

/// 3.x's `_truthy`: true, 1 or `'1'`.
bool _truthy(Object? value) => value == true || value == 1 || _string(value) == '1';

/// 3.x's `_image`: `//…` and `http://…` made https; an https URL without
/// user info, port or fragment on `6.cn`, `6rooms.com`, `xiu123.cn` or a
/// subdomain; '' otherwise.
String _image(Object? value) {
  var raw = _string(value);
  if (raw.startsWith('//')) raw = 'https:$raw';
  if (raw.startsWith('http://')) raw = 'https://${raw.substring(7)}';
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort || uri.fragment.isNotEmpty) {
    return '';
  }
  final host = uri.host.toLowerCase();
  const roots = ['6.cn', '6rooms.com', 'xiu123.cn'];
  return roots.any((root) => host == root || host.endsWith('.$root')) ? '$uri' : '';
}

/// The first non-empty [_image] of [values].
String _firstImage(Iterable<Object?> values) {
  for (final value in values) {
    final image = _image(value);
    if (image.isNotEmpty) return image;
  }
  return '';
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping (`_throwStatus`): 2xx is an answer; 404 and 410 are
/// `NotFound`, 429 `RateLimited`, 401, 403 and redirects (3.x did not follow
/// them) `RiskControl` (3.x's `access`), 5xx and every other status
/// `NetworkFailure`. An answer over [SixRoomApi.responseLimit] bytes is
/// `ApiChanged`.
void _checkStatus(String body, {required int status, required String what}) {
  if (status < 200 || status >= 300) {
    throw switch (status) {
      404 || 410 => NotFound(_site, '$what: HTTP $status'),
      429 => RateLimited(_site, detail: '$what: HTTP 429'),
      401 || 403 || (>= 300 && < 400) => RiskControl(_site, detail: '$what: HTTP $status'),
      _ => NetworkFailure(_site, '$what: HTTP $status'),
    };
  }
  // UTF-8 needs at most three bytes per UTF-16 unit, so short bodies need no
  // encoding.
  if (body.length > SixRoomApi.responseLimit ||
      (body.length * 3 > SixRoomApi.responseLimit && utf8.encode(body).length > SixRoomApi.responseLimit)) {
    throw ApiChanged(_site, '$what: answer over ${SixRoomApi.responseLimit} bytes');
  }
}
