import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'sixroom';

/// A room's state.
enum SixRoomState {
  /// A list card; an inroom answer with a live id and a stream name, or a
  /// private or black-screen room with a live id; a search card with the
  /// page's live mark.
  live,

  /// An inroom answer without them; a search card without the live mark
  /// that links the broadcaster's profile.
  offline,

  /// A search card that says neither (M4.U.31: 3.x read no live mark, so
  /// every search card was unknown).
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

/// One room: a list card (homepage, mobile list, web subarea), a search
/// card, or a room read from the inroom answer (3.x's `SixRoomRoom`).
@immutable
final class SixRoomRoom {
  /// Creates the room.
  const new({
    required this.roomId,
    required this.userId,
    required this.state,
    this.nick = '',
    this.title = '',
    this.liveId = '',
    this.avatar = '',
    this.cover = '',
    this.category = '',
    this.popularity,
    this.followers,
    this.startedAt,
    this.restriction,
    this.restrictionNote = '',
    this.stream,
    this.mediaError,
  });

  /// The room number (`rid`): the room's identity.
  final String roomId;

  /// The broadcaster's user id (`uid`, inroom `ruid`).
  final String userId;

  /// The broadcast id (`liveid`); '' when not live or not given.
  final String liveId;

  /// The broadcaster's name; '' when the answer has none (M4.U.31: 3.x
  /// wrote `Six Rooms`, which overwrote a follow's name).
  final String nick;

  /// The title, else the broadcaster's signature, else the name; ''.
  final String title;

  /// The broadcaster's avatar (a card's `picuser`, the search card's image,
  /// inroom `headPicUrl`, `picuser` or `uoption.picuser`); '' when not
  /// given, never the cover (31-1). Mobile list cards have none.
  final String avatar;

  /// The poster; ''.
  final String cover;

  /// The area (`anchor_area`, else `rtypename`); ''.
  final String category;

  /// A card's `count`, platform popularity; null when not given.
  final int? popularity;

  /// Inroom `fans_num`; null when not given.
  final int? followers;

  /// When the broadcast began (a card's `realstarttime`, inroom
  /// `liveinfo.starttime`), UTC; null when not given or not live.
  final DateTime? startedAt;

  /// The restriction the inroom answer states: `private` (`isPriveRoom`),
  /// `unplayable` (a black screen, `blackScreenInfo.msg`) or `none`; null
  /// for cards and answers that say nothing about it.
  final LiveRestriction? restriction;

  /// The black screen's message; ''.
  final String restrictionNote;

  /// The state.
  final SixRoomState state;

  /// The live room's stream, read on room entry and for recording (3.x's
  /// `includeMedia`); null otherwise, and for restricted rooms.
  final SixRoomStream? stream;

  /// Why a live room read with its media has no [stream]: a stream name
  /// that does not match the broadcaster and broadcast (3.x left the room
  /// without variants).
  final SiteError? mediaError;

  /// Whether this room and [known] can be the same broadcast: either state
  /// is unknown, or both are offline, or both are live with no differing
  /// broadcast ids.
  bool _sameBroadcast(SixRoomRoom known) => switch ((state, known.state)) {
    (SixRoomState.unknown, _) || (_, SixRoomState.unknown) => true,
    (SixRoomState.live, SixRoomState.live) => liveId.isEmpty || known.liveId.isEmpty || liveId == known.liveId,
    (final current, final earlier) => current == earlier,
  };

  /// This room with the fields its answer lacks taken from [known], an
  /// earlier card or room of the same room (3.x's `enrich`): the user id,
  /// name, title, avatar, cover and area when empty, the followers when not
  /// given, the state when unknown. What belongs to one broadcast (the
  /// broadcast id, popularity, start time and restriction) is taken only
  /// from the same live broadcast (31-5: 3.x kept the last card's
  /// popularity on a room that had ended). The media stay this room's.
  SixRoomRoom enrich(SixRoomRoom known) {
    final same = _sameBroadcast(known);
    final live = state != SixRoomState.offline && known.state == SixRoomState.live && same;
    return SixRoomRoom(
      roomId: roomId,
      userId: userId.isEmpty ? known.userId : userId,
      liveId: liveId.isEmpty && live ? known.liveId : liveId,
      nick: nick.isEmpty ? known.nick : nick,
      title: title.isEmpty ? known.title : title,
      avatar: avatar.isEmpty ? known.avatar : avatar,
      cover: cover.isEmpty ? known.cover : cover,
      category: category.isEmpty ? known.category : category,
      popularity: popularity ?? (live ? known.popularity : null),
      followers: followers ?? known.followers,
      startedAt: startedAt ?? (live ? known.startedAt : null),
      restriction: restriction ?? (same ? known.restriction : null),
      restrictionNote: restriction == null && same ? known.restrictionNote : restrictionNote,
      state: state == SixRoomState.unknown ? known.state : state,
      stream: stream,
      mediaError: mediaError,
    );
  }
}

/// What a room detail carries besides the model's fields: the broadcaster,
/// the state, the restriction and, on room entry and for recording, the
/// stream. The interface shows the notice of the restriction in its own
/// language (M13).
@immutable
final class SixRoomRoomData {
  /// Creates the data.
  const new({
    required this.roomId,
    required this.userId,
    required this.state,
    this.liveId = '',
    this.restriction,
    this.restrictionNote = '',
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

  /// The restriction the answer states (see [SixRoomRoom.restriction]).
  final LiveRestriction? restriction;

  /// The black screen's message; ''.
  final String restrictionNote;

  /// The FLV stream, read on room entry and for recording; null for a
  /// refresh (3.x left refreshed rooms without data) and for restricted
  /// rooms.
  final SixRoomStream? stream;

  /// Why the live room has no stream, when its stream name is unusable.
  final SiteError? mediaError;

  /// Why this room cannot be played, or null: offline or unknown is
  /// `StreamUnavailable`; so is a live private or black-screen room, with
  /// the reason; a live one with an unusable stream name says so; a live one
  /// read without its stream (a refresh) is `StreamUnavailable` until the
  /// room is entered.
  SiteError? get streamError => switch (state) {
    SixRoomState.offline => StreamUnavailable(_site, '$roomId is offline'),
    SixRoomState.unknown => StreamUnavailable(_site, '$roomId: state unknown'),
    SixRoomState.live when restriction == LiveRestriction.private => StreamUnavailable(
      _site,
      '$roomId is a private room',
    ),
    SixRoomState.live when restriction == LiveRestriction.unplayable => StreamUnavailable(
      _site,
      '$roomId has a black screen${restrictionNote.isEmpty ? '' : ': $restrictionNote'}',
    ),
    SixRoomState.live when mediaError != null => mediaError,
    SixRoomState.live when stream == null => StreamUnavailable(
      _site,
      '$roomId: read without its stream; enter the room',
    ),
    SixRoomState.live => null,
  };
}

/// One page of a mobile list: its cards, and whether the list goes on.
typedef SixRoomListPage = ({List<SixRoomRoom> rooms, bool hasMore});

/// What the danmaku module needs for a room (M5): the room number and the
/// broadcaster's user id. 3.x had no Six Rooms chat (`EmptyDanmaku`); the
/// room page's chat is a private WebSocket (archive spec §7), which M5.27
/// joins as a guest: the user id picks the chat servers and is the login's
/// `roomid`, the room number is the Referer of the server list request. Room
/// entry only hands the ids over, without a request.
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

/// One of 3.x's six areas: its id and name (3.x's, kept so followed areas
/// stay valid) and where its rooms come from (31-4): a mobile list type,
/// a web subarea, or neither for all rooms (the homepage, 3.x).
typedef _Area = ({String id, String name, String? mobileType, int? subarea});

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

  /// How long a list read whole (the homepage, a web subarea) serves its
  /// later pages (3.x's homepage snapshot).
  static const Duration directoryCacheLifetime = Duration(seconds: 90);

  /// The platform's name (3.x's zh.json `site_sixroom`): the category and
  /// the areas' type. A room without an area has none (3.x showed this
  /// name, which a follow then stored).
  static const String siteName = '六间房直播';

  /// `areaType` of the areas.
  static const String areaType = 'official';

  /// Rooms per directory page (3.x's `getDirectoryPage`), also asked of the
  /// mobile lists (which take any `size`).
  static const int pageSize = 30;

  /// The mobile list type of the recommendations (31-4, the archived
  /// adapter's): the live rooms of every area by popularity.
  static const String recommendType = 'special';

  /// The last directory page 3.x asked for.
  static const int maxPage = 10000;

  /// The largest page size of 3.x's lists and search.
  static const int maxPageSize = 100;

  /// The longest keyword 3.x sent; 6.cn itself takes 15 characters.
  static const int maxKeywordLength = 80;

  /// The notice of every room (`sixroom_chat_notice`, in words for users
  /// since M4.U.31; 3.x's was a developer's note). Chat is shown since M5.27,
  /// so it only says what the audience number is.
  static const String chatNotice = '人数是平台的热度，不是正在观看的人数。';

  /// The notice of a private or black-screen room, before [chatNotice]
  /// (`sixroom_restricted_notice`, in words for users since M4.U.31).
  static const String restrictedNotice = '这个六间房直播间是私密房或暂时黑屏，现在不能在这里观看。';

  /// Id of the one quality.
  static const String qualityId = 'flv:source';

  /// The one quality's name (`sixroom_quality_source`); with the resolution
  /// and bitrate `FLV 原始线路 · 1024x768 · 2652 kbps`
  /// (`sixroom_quality_source_detail`).
  static const String qualityName = 'FLV 原始线路';

  /// The one line's id: the FLV host.
  static const String lineId = 'wlive';

  /// 3.x's areas and their sources (31-4). The mobile list has no "all"
  /// and answers `content: []` for 星颜 (`u10`, sample S06-list-u10-p1),
  /// so all rooms stay the homepage and 星颜 is the web's subarea 10.
  static const List<_Area> _areas = [
    (id: 'all', name: '全部', mobileType: null, subarea: null),
    (id: 'song', name: '歌区', mobileType: 'u0', subarea: null),
    (id: 'dance', name: '舞区', mobileType: 'u1', subarea: null),
    (id: 'talk', name: '脱口秀', mobileType: 'u2', subarea: null),
    (id: 'face', name: '星颜', mobileType: null, subarea: 10),
    (id: 'party', name: '派对', mobileType: 'u8', subarea: null),
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
    ...listHeaders,
    'content-type': 'application/x-www-form-urlencoded',
  };

  /// The headers of the mobile lists: 3.x's mobile headers without a body.
  static const Map<String, String> listHeaders = {
    'user-agent': mobileUserAgent,
    'accept': 'application/json,text/plain,*/*',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'referer': 'https://ios.6.cn/?ver=8.0.3&build=4',
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

  /// Page [page] of [size] rooms of the mobile list [type] (`u0`,
  /// `special`; the app's `coop-mobile-getlivelistnew.php`, 31-4).
  static Uri listUrl(String type, {required int page, required int size}) => Uri.parse('$origin/coop/mobile/index.php')
      .replace(
        queryParameters: {
          'padapi': 'coop-mobile-getlivelistnew.php',
          'av': '3.1',
          'encpass': '',
          'logiuid': '',
          'isnew': '1',
          'size': '$size',
          'p': '$page',
          'type': type,
        },
      );

  /// The web's list of subarea [subarea] (10 is 星颜; the channel pages of
  /// v.6.cn, 31-4): every live room of it in one answer.
  static Uri subareaUrl(int subarea) =>
      Uri.parse('$origin/subareaIndex/getSubareaIndexNew.php').replace(queryParameters: {'subarea': '$subarea'});

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

  /// The area id of [category], or null when it is not one of 3.x's areas
  /// (another platform or type, an unknown id). The id is trimmed (3.x).
  static String? areaIdOf(LiveArea category) {
    if (category.platform != _site || category.areaType != areaType) return null;
    final id = category.areaId.trim();
    return _areas.any((area) => area.id == id) ? id : null;
  }

  /// The mobile list type of area [areaId] (`song` is `u0`), or null for
  /// all rooms (the homepage) and 星颜 (the web's subarea).
  static String? mobileTypeOf(String areaId) => _areas.firstWhere((area) => area.id == areaId).mobileType;

  /// The web subarea of area [areaId] (星颜 is 10), or null.
  static int? subareaOf(String areaId) => _areas.firstWhere((area) => area.id == areaId).subarea;

  // Directory -----------------------------------------------------------------

  /// The live card of a list row (homepage, mobile list, web subarea), or
  /// null when it has no room number or user id: name (`username`, the
  /// subarea's featured rows `alias`), title (else the signature
  /// `userMood`, else the name), avatar (`picuser`, which the mobile list
  /// lacks), cover (`pospic`, `pic`, `pospic_sp`), area, `count` as
  /// popularity and `realstarttime` as the start.
  static SixRoomRoom? _card(Map<String, dynamic> row) {
    final roomId = _string(row['rid']);
    final userId = _string(row['uid']);
    if (roomIdOf(roomId) != roomId || !isUserId(userId)) return null;
    final nick = _firstText([row['username'], row['alias']]);
    return SixRoomRoom(
      roomId: roomId,
      userId: userId,
      liveId: _string(row['liveid'] ?? row['lid']),
      nick: nick,
      title: _firstText([row['livetitle'], row['userMood'], nick]),
      avatar: _image(row['picuser']),
      cover: _firstImage([row['pospic'], row['pic'], row['pospic_sp']]),
      category: _text(row['anchor_area']),
      popularity: _count(row['count']),
      startedAt: _time(row['realstarttime']),
      state: SixRoomState.live,
    );
  }

  /// The cards of [rows], in order, once per room; rows without a room
  /// number or user id are skipped.
  static List<SixRoomRoom> _cards(Iterable<Object?> rows) {
    final seen = <String>{};
    final rooms = <SixRoomRoom>[];
    for (final value in rows) {
      final row = _map(value);
      final room = row == null ? null : _card(row);
      if (room != null && seen.add(room.roomId)) rooms.add(room);
    }
    return rooms;
  }

  /// The homepage's rooms (3.x's `parseDirectoryHtml`): the embedded
  /// `typeList` (JSON, or JSON text), in its order, once per room; a row
  /// needs a room number and a user id (see [_card]); all live. No room at
  /// all is `ApiChanged`.
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
    final rooms = _cards(rows);
    if (rooms.isEmpty) throw const ApiChanged(_site, '$what: typeList has no room');
    return List.unmodifiable(rooms);
  }

  /// The `content` of a 6.cn JSON answer whose `flag` is `001`; another
  /// flag is `RiskControl` (with the message), none `ApiChanged`.
  static Object? _content(String body, {required int status, required String what}) {
    _checkStatus(body, status: status, what: what);
    final root = _decodeObject(body, what);
    final flag = root['flag'];
    if (flag is! String) throw ApiChanged(_site, '$what: flag is $flag');
    if (flag != '001') throw RiskControl(_site, detail: '$what: flag $flag ${_text(root['content'])}');
    return root['content'];
  }

  /// Page [page] of [size] rooms of the mobile list [type] (31-4, the
  /// archived adapter's `getlivelistnew`): the rows of `content[type]` as
  /// live cards (see [_card]; a bad row is skipped), and whether the list
  /// goes on: the page had rows and `roomListCount[type]` is past it (a full
  /// page when it is not given). A type without rooms answers
  /// `content: []`. A list whose rows are all unreadable, or no list for the
  /// type, is `ApiChanged`.
  static SixRoomListPage list(
    String body, {
    required String type,
    required int page,
    required int size,
    int status = 200,
  }) {
    final what = 'mobile list $type';
    final content = _content(body, status: status, what: what);
    if (content is List && content.isEmpty) return (rooms: const [], hasMore: false);
    final map = _map(content);
    final rows = map?[type];
    if (map == null || rows is! List) throw ApiChanged(_site, '$what: no $type list');
    final rooms = _cards(rows);
    if (rooms.isEmpty && rows.isNotEmpty) throw ApiChanged(_site, '$what: no readable room');
    final total = _count(_map(map['roomListCount'])?[type]);
    final hasMore = rows.isNotEmpty && (total == null ? rows.length >= size : page * size < total);
    return (rooms: List.unmodifiable(rooms), hasMore: hasMore);
  }

  /// The web's subarea list (星颜 is subarea 10, 31-4): the featured rows of
  /// `bigLiveList.list`, then `liveList` (an object by user id), as live
  /// cards once per room (see [_card]; a bad row is skipped). Neither list
  /// is `ApiChanged`; rows but no readable room too.
  static List<SixRoomRoom> subarea(String body, {int status = 200}) {
    const what = 'subarea list';
    final content = _map(_content(body, status: status, what: what));
    final featured = _map(content?['bigLiveList'])?['list'];
    final others = content?['liveList'];
    final rows = [
      if (featured is List) ...featured,
      if (others is Map) ...others.values else if (others is List) ...others,
    ];
    if (featured is! List && others is! Map && others is! List) {
      throw const ApiChanged(_site, '$what: no bigLiveList or liveList');
    }
    final rooms = _cards(rows);
    if (rooms.isEmpty && rows.isNotEmpty) throw const ApiChanged(_site, '$what: no readable room');
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
  /// else `src`) as avatar. The state (31-3; 3.x read none, so every card
  /// was unknown): live with the page's live mark (`i.live`, "直播中"),
  /// offline without it when the link is the broadcaster's profile
  /// (`/profile/<room>`, which the page gives rooms that are not live),
  /// else unknown. 6.cn's "输入内容过长" page (a keyword over 15 characters)
  /// is no result; any other prompt page is `RiskControl` (3.x's `access`),
  /// anything else `ApiChanged`.
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
      final Uri link;
      final String? roomId;
      try {
        link = Uri.parse(origin).resolve(href ?? '');
        roomId = roomIdOf('$link');
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
      final nick = _text(item.query((element) => element.hasClass('alias'))?.text);
      final live = item.query((element) => element.tag == 'i' && element.hasClass('live')) != null;
      // roomIdOf accepted the path, so its segments decode.
      final profile = link.pathSegments.first.toLowerCase() == 'profile';
      rooms.add(
        SixRoomRoom(
          roomId: roomId,
          userId: userId,
          nick: nick,
          title: nick,
          avatar: _firstImage([image?.attributes['data-src'], image?.attributes['src']]),
          state: live
              ? SixRoomState.live
              : profile
              ? SixRoomState.offline
              : SixRoomState.unknown,
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
  /// the ones asked.
  ///
  /// A live id and a stream name are live, else offline. A private room
  /// (`isPriveRoom`) is restriction `private`, a black screen
  /// (`blackScreenInfo.msg`) `unplayable`, otherwise `none` (null when the
  /// answer has neither field); such a room is live with a live id alone
  /// (3.x showed it as unknown; M2.1: a restricted broadcast is live). The
  /// title is the broadcast's title, else the broadcaster's signature
  /// (3.x's `roominfo.userMood`, which answers do not have, then
  /// `roomParamInfo.operation.userMood`, 31-2), else the name; the avatar
  /// `headPicUrl`,
  /// `picuser`, else `uoption.picuser` (31-1); a live room's start is
  /// `liveinfo.starttime`. With [media], an unrestricted live room's stream
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
    final blackScreen = _text(_map(content['blackScreenInfo'])?['msg']);
    final restriction = _truthy(content['isPriveRoom'])
        ? LiveRestriction.private
        : blackScreen.isNotEmpty
        ? LiveRestriction.unplayable
        : content.containsKey('isPriveRoom') || content.containsKey('blackScreenInfo')
        ? LiveRestriction.none
        : null;
    final restricted = restriction != null && restriction != LiveRestriction.none;
    final state = liveId.isNotEmpty && (flvTitle.isNotEmpty || restricted) ? SixRoomState.live : SixRoomState.offline;
    final nick = _text(roomInfo['alias']);
    SixRoomStream? stream;
    SiteError? mediaError;
    if (media && state == SixRoomState.live && !restricted) {
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
      title: _firstText([liveInfo['title'], roomInfo['userMood'], _map(params['operation'])?['userMood'], nick]),
      avatar: _firstImage([roomInfo['headPicUrl'], roomInfo['picuser'], _map(roomInfo['uoption'])?['picuser']]),
      cover: _firstImage([liveInfo['spredPic'], liveInfo['pospic'], liveInfo['largepic'], liveInfo['pic']]),
      category: _firstText([roomInfo['anchor_area'], roomInfo['rtypename']]),
      followers: _count(params['fans_num']),
      startedAt: state == SixRoomState.live ? _time(liveInfo['starttime']) : null,
      restriction: restriction,
      restrictionNote: restriction == LiveRestriction.unplayable ? blackScreen : '',
      state: state,
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

  /// The card or room of [room] (3.x's `_room`): the avatar (never the
  /// cover, 31-1), the area, the name and title as given ('' when the
  /// answer has none: a follow keeps what it stored, M2.1); the popularity
  /// as the audience; followers; the state; the start and restriction
  /// (M2.1; the start only while live); the notices and 3.x's headers;
  /// [data] and [danmaku] as given.
  static LiveRoom liveRoom(SixRoomRoom room, {SixRoomRoomData? data, SixRoomDanmakuArgs? danmaku}) {
    final popularity = room.popularity?.toString() ?? '';
    final restricted = room.restriction != null && room.restriction != LiveRestriction.none;
    return LiveRoom(
      roomId: room.roomId,
      platform: _site,
      userId: room.userId,
      link: link(room.roomId),
      title: room.title,
      nick: room.nick,
      avatar: room.avatar,
      cover: room.cover,
      area: room.category,
      watching: popularity,
      popularity: popularity,
      followers: room.followers?.toString() ?? '',
      audienceMetricType: room.popularity == null ? AudienceMetricType.unknown : AudienceMetricType.popularity,
      liveStatus: switch (room.state) {
        SixRoomState.live => LiveStatus.live,
        SixRoomState.offline => LiveStatus.offline,
        SixRoomState.unknown => LiveStatus.unknown,
      },
      startedAt: room.state == SixRoomState.live ? room.startedAt : null,
      restriction: room.restriction,
      notice: restricted ? '$restrictedNotice\n$chatNotice' : chatNotice,
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
    restriction: room.restriction,
    restrictionNote: room.restrictionNote,
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

/// 3.x's `_text`: [_string] with runs of white space made one space.
String _text(Object? value) => _string(value).replaceAll(RegExp(r'\s+'), ' ').trim();

/// The first non-empty [_text] of [values], or ''.
String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// 3.x's `_integer`: an integer or number (truncated), or integer text with
/// `,` separators, when zero or more; null otherwise.
int? _count(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num) return value >= 0 ? value.toInt() : null;
  final parsed = int.tryParse(_string(value).replaceAll(',', ''));
  return parsed != null && parsed >= 0 ? parsed : null;
}

/// A time in epoch seconds (a number or digits), UTC; null for 0, a
/// negative or anything else.
DateTime? _time(Object? value) {
  final seconds = _count(value);
  return seconds == null || seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
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
