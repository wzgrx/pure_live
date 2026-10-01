import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'yy';
const _origin = 'https://www.yy.com';

/// What the danmaku connection needs to join one channel (3.x's
/// `YyDanmakuArgs`): the top channel and the sub channel it enters.
@immutable
final class YyDanmakuArgs {
  /// Creates the arguments.
  const new({required this.topSid, required this.subSid});

  /// Top channel (`sid`).
  final int topSid;

  /// Sub channel (`ssid`); the same as [topSid] for every room seen so far.
  final int subSid;

  @override
  bool operator ==(Object other) => other is YyDanmakuArgs && other.topSid == topSid && other.subSid == subSid;

  @override
  int get hashCode => Object.hash(topSid, subSid);

  /// 3.x's `toString`: `{"topSid":…,"subSid":…}`.
  @override
  String toString() => jsonEncode({'topSid': topSid, 'subSid': subSid});
}

/// The channel behind a room, apart from its identity: a room asked for by
/// its short number (`asid`, `www.yy.com/2149`) keeps that number, while
/// streams and danmaku use the canonical `sid` and `ssid`.
@immutable
final class YyRoomData {
  /// Creates the data.
  const new({required this.sid, required this.ssid});

  /// Canonical top channel.
  final String sid;

  /// Sub channel.
  final String ssid;
}

/// The listing module of an area page (`pageInfo.pageBar`): what
/// `more/page.action` needs. 3.x stored it as the area's `shortName`.
typedef YyModule = ({int moduleId, String biz, String subBiz});

/// One answer of the anonymous mobile HLS route.
typedef YyMobileHls = ({Uri url, int width, int height, String video});

/// What a room page says: the canonical channel, the streamer, the channel
/// title and the area name.
typedef YyRoomPage = ({String sid, String ssid, String uid, String nick, String avatar, String title, String area});

/// Pure parsing of YY responses (3.x's `YYSite`). Each function takes the
/// response text and status and returns 3.x's models or throws a
/// `SiteError`.
abstract final class YyApi {
  /// Desktop Chrome 128, the UA 3.x sent with every API request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0.0.0 Safari/537.36';

  /// Desktop Chrome 140, the UA 3.x sent to the media CDN
  /// (`PlaybackHeaderResolver`).
  static const String mediaUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// The iPhone Safari UA of the mobile HLS route.
  static const String mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1';

  /// Web origin; also the `Origin` of API and media requests.
  static const String origin = _origin;

  /// The web player's stream SDK version stream-manager is asked with.
  static const String sdkVersion = '5.23.0-beta.2';

  /// The two rates the mobile HLS route is asked for, lowest first.
  static const List<String> mobileHlsRates = ['1200', '4000'];

  /// Prefix of the quality ids and data of the mobile HLS route.
  static const String mobileHlsPrefix = 'mobile-hls:';

  /// How long before `t` a FLV URL is renewed (at most a quarter of its
  /// lifetime).
  static const Duration leaseLead = Duration(minutes: 1);

  /// The `biz` of the recommendations, and of most live details: no area.
  static const String otherBiz = 'other';

  /// Area names by `biz`, preset from the catalog (C-21): each area page's
  /// `pageBar` (2026-10-01, all 18 areas of `getCategory`) for the `biz`
  /// only one area uses. A detail's `biz` is its area's (checked on 298
  /// live rooms of 7 areas), so a room entered directly is named without
  /// reading an area page. Left out: `chicken` (和平精英, 天天吃鸡, 综合游戏
  /// and 无畏契约 tell it apart by `subBiz`, which details lack), `other`
  /// (no area). Names learnt from an area page come first.
  ///
  /// The module-less areas (`biz` `null` in their page) list their rooms
  /// in the page, and those rooms' details carry a `biz` of their own
  /// (M13.16, 2026-10-01: 82 live details from the 10 areas with rooms):
  /// 综合's rooms say `zonghe` (the area's path, `/others/zonghe`), which no
  /// other area uses; 手机直播's rooms carry the `biz` of their content area
  /// (`talk`, `dance`, …). 英雄联盟 had no live room to read.
  static const Map<String, String> bizAreaNames = {
    'sing': '音乐',
    'talk': '脱口秀',
    'dance': '舞蹈',
    'red': '户外',
    'pretty': '颜值',
    'mc': '喊麦',
    'sport': '体育',
    // The 二次元 page lists the `car` module.
    'car': '二次元',
    'game': '王者荣耀',
    'zonghe': '综合',
  };

  /// The words YY appends to the default title of a room without one
  /// (`<nickname> 正在直播`; search's `channelName` and the lists' and
  /// detail's `desc` carry the same value).
  static const String liveSuffix = '正在直播';

  /// The name YY shows for a user without one: a room page or card that
  /// names its streamer so names nobody (a placeholder, never stored).
  static const String placeholderName = 'YY用户';

  /// YY's default portraits (`yystatic.com/pc/images/portrait/person/1.jpg`,
  /// `…/default_portrait-….png`): no avatar.
  static final RegExp _defaultPortrait = RegExp(r'yystatic\.com/.*portrait', caseSensitive: false);

  /// The room page, 3.x's `link`.
  static String roomUrl(String roomId) => '$_origin/${roomId.trim()}';

  // Headers -------------------------------------------------------------------

  /// 3.x's API headers (`getHeaders`), with the user's cookie when set.
  static Map<String, String> apiHeaders({String cookie = ''}) => {
    'accept': '*/*',
    'origin': _origin,
    'referer': '$_origin/',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-site',
    'user-agent': userAgent,
    if (cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// stream-manager: the API headers with the channel page as Referer and
  /// the JSON body declared `text/plain`, as the web SDK sends it (some
  /// channels refuse `application/json`).
  static Map<String, String> streamManagerHeaders(String sid, String ssid, {String cookie = ''}) => {
    ...apiHeaders(cookie: cookie),
    'content-type': 'text/plain;charset=UTF-8',
    'referer': '$_origin/$sid/$ssid',
  };

  /// The mobile HLS route: the API headers as the mobile page on an iPhone.
  static Map<String, String> mobileHlsHeaders(String sid, String ssid, {String cookie = ''}) => {
    ...apiHeaders(cookie: cookie),
    'referer': 'https://wap.yy.com/mobileweb/$sid/$ssid',
    'user-agent': mobileUserAgent,
  };

  /// Media request headers (3.x's `PlaybackHeaderResolver` for YY): Origin,
  /// the site root as Referer, desktop Chrome, and the user's cookie when
  /// set.
  static Map<String, String> mediaHeaders({String cookie = ''}) => {
    'origin': _origin,
    'referer': '$_origin/',
    'user-agent': mediaUserAgent,
    if (cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  // Catalog -------------------------------------------------------------------

  /// `yyweb/module/data/header`: the top-level categories (`categoryTabs`,
  /// id and title). Their areas come from [areas].
  static List<({String id, String name})> categoryTabs(String body, {int status = 200}) {
    final root = _object(_decoded(body, status: status, what: 'header'));
    final tabs = root?['categoryTabs'];
    if (tabs is! List) throw ApiChanged(_site, 'header: no categoryTabs (${_snippet(body)})');
    return [
      for (final raw in tabs)
        if (_object(raw) case final tab? when jsonString(tab['id']) != null)
          (id: jsonString(tab['id'])!, name: jsonString(tab['title']) ?? ''),
    ];
  }

  /// Whether an area [page] is a short-video page (`www.yy.com/sv/`, 小视频
  /// under 其他): no live rooms, so the catalog leaves it out (C-19).
  static bool isShortVideoPage(Uri? page) {
    final segments = page?.pathSegments.where((segment) => segment.isNotEmpty);
    return segments != null && segments.isNotEmpty && segments.first.toLowerCase() == 'sv';
  }

  /// `category/getCategory.action?parentId=`: the areas of one category in
  /// server order, each with the page its listing module is read from
  /// ([pageInfo]). The body is JSON served as `text/html`.
  static List<({LiveArea area, Uri? page})> areas(
    String body, {
    required String categoryId,
    required String categoryName,
    int status = 200,
  }) {
    final root = _object(_decoded(body, status: status, what: 'getCategory'));
    final data = root?['data'];
    if (data is! List) throw ApiChanged(_site, 'getCategory: no data (${_snippet(body)})');
    return [
      for (final raw in data)
        if (_object(raw) case final item? when jsonString(item['id']) != null)
          (
            area: LiveArea(
              platform: _site,
              areaType: categoryId,
              typeName: categoryName,
              areaId: jsonString(item['id'])!,
              areaName: jsonString(item['title']) ?? '',
              areaPic: _image(item['cover']),
            ),
            page: jsonUrl(_https(jsonString(item['url']) ?? '')),
          ),
    ];
  }

  /// The listing module in an area page's `pageInfo` (3.x's
  /// `parseCategoryPageInfo`): `moduleId`, `biz` and `subBiz`, or null when
  /// the page has none of them. Server-rendered areas answer `moduleId: 0`
  /// and `biz: 'null'` ([hasListing] is false).
  static YyModule? pageInfo(String html) {
    final source = RegExp(r'pageInfo\s*=\s*(\{[\s\S]*?\})\s*;').firstMatch(html)?.group(1);
    if (source == null) return null;
    final moduleId = int.tryParse(RegExp(r'''moduleId\s*:\s*['"]?(-?\d+)''').firstMatch(source)?.group(1) ?? '');
    final biz = RegExp(r'''biz\s*:\s*['"]([^'"]+)''').firstMatch(source)?.group(1)?.trim() ?? '';
    final subBiz = RegExp(r'''subBiz\s*:\s*['"]([^'"]+)''').firstMatch(source)?.group(1)?.trim() ?? '';
    if (moduleId == null || biz.isEmpty || subBiz.isEmpty) return null;
    return (moduleId: moduleId, biz: biz, subBiz: subBiz);
  }

  /// [module] as 3.x stored it in `LiveArea.shortName`:
  /// `{"moduleId":313,"biz":"dance","subBiz":"idx"}`.
  static String shortName(YyModule module) =>
      jsonEncode({'moduleId': module.moduleId, 'biz': module.biz, 'subBiz': module.subBiz});

  /// The module a stored `shortName` holds (3.x's areas and follows), or
  /// null when it holds none.
  static YyModule? moduleOf(String shortName) {
    Object? decoded;
    try {
      decoded = jsonDecode(shortName);
    } on FormatException {
      return null;
    }
    final map = _object(decoded);
    final moduleId = jsonInt(map?['moduleId']);
    final biz = jsonString(map?['biz']);
    final subBiz = jsonString(map?['subBiz']);
    if (moduleId == null || biz == null || subBiz == null) return null;
    return (moduleId: moduleId, biz: biz, subBiz: subBiz);
  }

  /// Whether [module] lists rooms. The server-rendered areas (英雄联盟,
  /// 综合, 手机直播) have `moduleId: 0, biz: 'null'`; their listing is
  /// always empty.
  static bool hasListing(YyModule module) => module.moduleId != 0 && module.biz != 'null' && module.subBiz != 'null';

  /// `more/page.action`: live rooms of an area (area label [area]) or of the
  /// recommendations (label from [areaNames] by `biz`, else empty: 3.x
  /// showed the raw `biz`, `other` for every recommendation). `data: null`
  /// (an area without listing) is empty.
  static List<LiveRoom> roomList(
    String body, {
    String? area,
    Map<String, String> areaNames = const {},
    int status = 200,
  }) {
    final root = _checked(body, status: status, what: 'page.action');
    final data = root['data'];
    if (data != null && data is! Map) throw const ApiChanged(_site, 'page.action: data is not an object');
    final list = _object(data)?['data'];
    if (list != null && list is! List) throw const ApiChanged(_site, 'page.action: data.data is not a list');
    return [
      for (final raw in _list(list))
        if (_object(raw) case final item?) ?_card(item, area: area ?? _areaOf(item['biz'], areaNames)),
    ];
  }

  static LiveRoom? _card(Map<String, dynamic> item, {required String area}) {
    final sid = _channel(item['sid']);
    if (sid == null) return null;
    final users = jsonString(item['users']) ?? '';
    return LiveRoom(
      roomId: sid,
      platform: _site,
      userId: jsonString(item['uid']) ?? '',
      title: title(item['desc']),
      nick: jsonString(item['name']) ?? '',
      avatar: _image(item['avatar']),
      cover: _image(item['thumb2']).ifEmpty(() => _image(item['thumb'])),
      area: area,
      watching: users,
      popularity: users,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.live,
      startedAt: startedAt(item['startTime']),
      data: YyRoomData(sid: sid, ssid: _channel(item['ssid']) ?? sid),
    );
  }

  /// A room title without YY's default suffix: a room without a title of its
  /// own is titled `<nickname> 正在直播` (also `<nickname>正在直播`), which
  /// becomes `<nickname>`; other titles are kept as they are.
  static String title(Object? value) {
    final text = jsonString(value) ?? '';
    if (!text.endsWith(liveSuffix)) return text;
    return text.substring(0, text.length - liveSuffix.length).trim();
  }

  /// The broadcast's start from a list or detail `startTime` (Unix seconds);
  /// 0, negative and implausible values are none.
  static DateTime? startedAt(Object? value) => switch (jsonInt(value)) {
    final int seconds when seconds > 0 && seconds < 100000000000 => DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ),
    _ => null,
  };

  // Search --------------------------------------------------------------------

  /// `apiSearch/doSearch.json?t=120`: rooms matching the keyword. Live is
  /// `liveOn` 1 (every result seen so far); the title is `channelName`
  /// without the default title's ` 正在直播` ([title]). Results carry no
  /// start time.
  static List<LiveRoom> searchRooms(String body, {int status = 200}) => [
    for (final item in _docs(body, status: status, tab: '120'))
      if (_channel(item['sid']) case final sid?)
        LiveRoom(
          roomId: sid,
          platform: _site,
          userId: jsonString(item['uid']) ?? '',
          title: title(item['channelName']),
          nick: jsonString(item['name']) ?? '',
          avatar: _image(item['headurl']),
          cover: _image(item['posterurl']),
          // 3.x read `biz`, which search results do not have; `category` is
          // the area name.
          area: jsonString(item['category']) ?? '',
          watching: jsonString(item['users']) ?? '',
          popularity: jsonString(item['users']) ?? '',
          audienceMetricType: AudienceMetricType.popularity,
          liveStatus: _isLive(item['liveOn']) ? LiveStatus.live : LiveStatus.offline,
          link: roomUrl(sid),
          data: YyRoomData(sid: sid, ssid: _channel(item['ssid']) ?? sid),
        ),
  ];

  /// `apiSearch/doSearch.json?t=1`: streamers, live or not. `liveOn` is the
  /// streamer's own state: it agreed with `liveInfoDetail` of the channel in
  /// 59 of 60 checks (2026-09-29). The exception is a shared channel (a
  /// guild's, `22490906`) live with another performer: the streamer is
  /// offline while the channel is not. Neither `t=120` (it misses live
  /// streamers whose room does not match the keyword) nor hiding the state
  /// would be more accurate, so it is kept.
  static List<LiveAnchorItem> searchAnchors(String body, {int status = 200}) => [
    for (final item in _docs(body, status: status, tab: '1'))
      if (_channel(item['sid']) ?? _channel(item['ssid']) case final sid?)
        LiveAnchorItem(
          roomId: sid,
          avatar: _image(item['headurl']),
          userName: jsonString(item['name']) ?? jsonString(item['stageName']) ?? '',
          liveStatus: _isLive(item['liveOn']),
        ),
  ];

  static List<Map<String, dynamic>> _docs(String body, {required int status, required String tab}) {
    final root = _object(_decoded(body, status: status, what: 'doSearch'));
    if (root == null) throw ApiChanged(_site, 'doSearch: not a JSON object (${_snippet(body)})');
    if (root['success'] == false || (jsonInt(root['status']) ?? 0) != 0) {
      throw ApiChanged(_site, 'doSearch: status ${root['status']} ${jsonString(root['message']) ?? ''}'.trim());
    }
    final result = _object(_object(root['data'])?['searchResult']);
    if (result == null) throw ApiChanged(_site, 'doSearch: no searchResult (${_snippet(body)})');
    return [for (final raw in _list(_object(_object(result['response'])?[tab])?['docs'])) ?_object(raw)];
  }

  // Rooms ---------------------------------------------------------------------

  /// `api/liveInfoDetail/<sid>/<sid>/0`: the live room of a channel as the
  /// user asked for it ([requestedId], which may be a short number: the
  /// identity of a follow must not change), or null when the channel is not
  /// broadcasting. Offline, unknown and short numbers all answer `data:
  /// null`; the room page tells them apart ([roomPage]). The area is
  /// [areaNames] by `biz`, else empty (3.x showed the raw `biz`, mostly
  /// `other`). The start is `startTime`.
  static LiveRoom? liveDetail(
    String body, {
    required String requestedId,
    Map<String, String> areaNames = const {},
    int status = 200,
  }) {
    final root = _checked(body, status: status, what: 'liveInfoDetail');
    final data = root['data'];
    if (data == null) return null;
    final item = _object(data);
    if (item == null) throw ApiChanged(_site, 'liveInfoDetail: data is not an object (${_snippet(body)})');
    final id = requestedId.trim();
    final sid = _channel(item['sid']) ?? id;
    final ssid = _channel(item['ssid']) ?? sid;
    final users = jsonString(item['users']) ?? '';
    return LiveRoom(
      roomId: id,
      platform: _site,
      userId: jsonString(item['uid']) ?? '',
      title: title(item['desc']),
      nick: jsonString(item['name']) ?? '',
      avatar: _image(item['avatar']),
      cover: _image(item['thumb2']).ifEmpty(() => _image(item['thumb'])),
      area: _areaOf(item['biz'], areaNames),
      watching: users,
      popularity: users,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.live,
      startedAt: startedAt(item['startTime']),
      link: roomUrl(id),
      data: YyRoomData(sid: sid, ssid: ssid),
      danmakuData: danmakuArgs(sid: sid, ssid: ssid),
    );
  }

  /// The live rooms an area page renders itself. Areas without a JSON
  /// listing (`moduleId: 0`: 手机直播, 综合, 英雄联盟) show their rooms as
  /// `li[data-sid]` cards in the page; 3.x listed nothing there. Each card
  /// gives the title (`data-title`, cut by the server), cover, streamer,
  /// the audience text (`2.1万`) and the start (the fourth part of
  /// `data-pid`, `startTime`). A page without cards (小视频, a short-video
  /// page) is empty.
  static List<LiveRoom> pageRooms(String html, {required String area}) => [
    for (final card in HtmlElement.parseFragment(
      html,
    ).queryAll((element) => element.tag == 'li' && element.attributes.containsKey('data-sid')))
      ?_pageCard(card, area: area),
  ];

  static LiveRoom? _pageCard(HtmlElement card, {required String area}) {
    final sid = _channel(card.attributes['data-sid']);
    if (sid == null) return null;
    HtmlElement? part(String name) => card.query((element) => element.hasClass(name));
    String picture(HtmlElement? box) =>
        _image(box?.query((element) => element.tag == 'img')?.attributes['data-original']);
    final users = parseChineseCount(part('usr')?.text.trim());
    final pid = (card.attributes['data-pid'] ?? '').split('_');
    return LiveRoom(
      roomId: sid,
      platform: _site,
      userId: _channel(card.attributes['data-uid']) ?? '',
      title: title(card.query((element) => element.hasClass('box'))?.attributes['data-title'] ?? part('title')?.text),
      nick: _name(part('intro')?.text),
      avatar: _avatar(picture(part('avt'))),
      cover: picture(part('cover')),
      area: area,
      watching: users == null ? '' : '$users',
      popularity: users == null ? '' : '$users',
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.live,
      startedAt: startedAt(pid.length > 3 ? pid[3] : null),
      data: YyRoomData(sid: sid, ssid: _channel(card.attributes['data-ssid']) ?? sid),
    );
  }

  /// A streamer name, empty for YY's [placeholderName].
  static String _name(String? value) {
    final name = value?.trim() ?? '';
    return name == placeholderName ? '' : name;
  }

  /// An avatar, empty for YY's default portraits.
  static String _avatar(String url) => _defaultPortrait.hasMatch(url) ? '' : url;

  /// The room page `www.yy.com/<sid or short number>`: the canonical channel
  /// (`pageInfo.sid`, `ssid`), the streamer (`nick`, `logo`), the channel
  /// title (`roomName`) and the area name (`owInfo.stringBiz`). A streamer
  /// named [placeholderName] with a default portrait is none (M4.D: the
  /// page of a channel whose owner has no name). The 404 page (it loads
  /// `yycom_404`, with status 200) is `NotFound`.
  static YyRoomPage roomPage(String html, {int status = 200}) {
    if (status == 404 || html.contains('yycom_404')) throw const NotFound(_site, 'room page is the 404 page');
    if (status >= 500) throw NetworkFailure(_site, 'room page: HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, 'room page: HTTP $status');
    final source = RegExp(r'pageInfo\s*=\s*\{[\s\S]*?\};').firstMatch(html)?.group(0);
    if (source == null) throw ApiChanged(_site, 'room page: no pageInfo (${_snippet(html)})');
    String? field(String name) {
      final match = RegExp('\\b$name\\s*:\\s*(?:decodeURIComponent\\()?"([^"]*)"').firstMatch(source);
      if (match == null) return null;
      final value = match.group(1)!;
      return jsonString(match.group(0)!.contains('decodeURIComponent') ? _percentDecode(value) : value);
    }

    final sid = _channel(field('sid'));
    if (sid == null) throw ApiChanged(_site, 'room page: no sid (${_snippet(html)})');
    return (
      sid: sid,
      ssid: _channel(field('ssid')) ?? sid,
      uid: field('uid') ?? '',
      nick: _name(field('nick')),
      avatar: _avatar(_image(field('logo'))),
      title: field('roomName') ?? '',
      area: field('stringBiz') ?? '',
    );
  }

  /// The room of a channel that is not broadcasting. Without its [page]
  /// (a refresh of a room whose page was read before) it is 3.x's room: the
  /// id and the state, and the canonical [channel]. With the page (room
  /// entry, the first refresh) it also names the streamer, the channel
  /// title and area, and carries the danmaku arguments of the canonical
  /// channel (the chat stays open while nobody broadcasts); never a cover,
  /// an audience or a start.
  static LiveRoom offlineRoom({required String requestedId, YyRoomPage? page, YyRoomData? channel}) {
    final id = requestedId.trim();
    if (page == null) return LiveRoom(roomId: id, platform: _site, liveStatus: LiveStatus.offline, data: channel);
    return LiveRoom(
      roomId: id,
      platform: _site,
      userId: page.uid,
      title: page.title,
      nick: page.nick,
      avatar: page.avatar,
      area: page.area,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: LiveStatus.offline,
      link: roomUrl(id),
      data: YyRoomData(sid: page.sid, ssid: page.ssid),
      danmakuData: danmakuArgs(sid: page.sid, ssid: page.ssid),
    );
  }

  /// The danmaku arguments of a channel (3.x's, numbers).
  static YyDanmakuArgs danmakuArgs({required String sid, required String ssid}) =>
      YyDanmakuArgs(topSid: int.tryParse(sid) ?? 0, subSid: int.tryParse(ssid) ?? 0);

  // Streams -------------------------------------------------------------------

  /// The stream-manager request body for [gear] (3.x's, sent as JSON text:
  /// 3.x handed Dio the map with a `text/plain` type, and Dio form-encoded
  /// it, which the server answers with HTTP 500). [line] is the CDN line
  /// (`line_seq`) asked for; -1 lets the server choose, as 3.x did.
  static Map<String, Object> streamManagerBody({
    required String sid,
    required String ssid,
    required int gear,
    required int sequence,
    int line = -1,
  }) => {
    'head': {
      'seq': sequence,
      'appidstr': '0',
      'bidstr': '121',
      'cidstr': sid,
      'sidstr': ssid,
      'uid64': 0,
      'client_type': 108,
      'client_ver': sdkVersion,
      'stream_sys_ver': 1,
      'app': 'yylive_web',
      'playersdk_ver': sdkVersion,
      'thundersdk_ver': '0',
      'streamsdk_ver': sdkVersion,
    },
    'client_attribute': {
      'client': 'web',
      'model': 'web0',
      'cpu': '',
      'graphics_card': '',
      'os': 'chrome',
      'osversion': '128.0.0.0',
      'vsdk_version': '',
      'app_identify': '',
      'app_version': '',
      'business': '',
      'width': '1366',
      'height': '768',
      'scale': '',
      'client_type': 8,
      'h265': 0,
    },
    'avp_parameter': {
      'version': 1,
      'client_type': 8,
      'service_type': 0,
      'imsi': 0,
      'send_time': sequence ~/ 1000,
      'line_seq': line,
      'gear': gear,
      'ssl': 1,
      'stream_format': 0,
    },
  };

  /// A stream-manager answer. HTTP 5xx is `NetworkFailure`, any other
  /// non-2xx status or a body that is not a JSON object `ApiChanged`.
  static Map<String, dynamic> streams(String body, {int status = 200}) {
    if (status >= 500) throw NetworkFailure(_site, 'stream-manager: HTTP $status (${_snippet(body)})');
    if (status < 200 || status >= 300) throw ApiChanged(_site, 'stream-manager: HTTP $status (${_snippet(body)})');
    final root = _object(_decoded(body, status: status, what: 'stream-manager'));
    if (root == null) throw ApiChanged(_site, 'stream-manager: not a JSON object (${_snippet(body)})');
    return root;
  }

  /// The qualities of a stream-manager answer (3.x's `parsePlayQualities`):
  /// each stream's `json` holds `gear_info` (`gear`, `name`) and `rate`;
  /// the first stream of a gear wins, a name used by two gears gets the
  /// gear appended, best rate first. Only streams with a `stream_key` are
  /// listed: the others (`mix` 1) have no web stream, and asking for their
  /// gear is answered with another gear's stream.
  static List<LivePlayQuality> qualities(Map<String, dynamic> streams) {
    final records = <({String name, String gear, int rate})>[];
    final seen = <String>{};
    for (final stream in _streams(streams)) {
      if (jsonString(stream.raw['stream_key']) == null) continue;
      final info = _object(stream.json?['gear_info']);
      final name = jsonString(info?['name']);
      final gear = jsonString(info?['gear']);
      if (name == null || gear == null || !seen.add(gear)) continue;
      records.add((name: name, gear: gear, rate: jsonInt(stream.json?['rate']) ?? 0));
    }
    final names = <String, int>{};
    for (final record in records) {
      names.update(record.name, (count) => count + 1, ifAbsent: () => 1);
    }
    return [
      for (final record in records)
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: names[record.name] == 1 ? record.name : '${record.name} · ${record.gear}',
            id: record.gear,
            bitrate: record.rate > 0 ? record.rate * 1000 : null,
          ),
          id: record.gear,
          sort: record.rate,
          data: record.gear,
        ),
    ]..sort((left, right) => right.sort.compareTo(left.sort));
  }

  /// The lines of a stream-manager answer received at [issuedAt]: every
  /// `stream_line_addr` URL in server order (3.x's `parsePlayUrls`), FLV,
  /// with the media headers, `line_seq` as line id and the lease of `t`.
  /// The applied quality is the gear of the stream the server chose (asking
  /// for a gear without a web stream is answered with another).
  static LivePlayUrlResolution resolution(
    Map<String, dynamic> streams, {
    required DateTime issuedAt,
    String cookie = '',
  }) {
    final gears = {
      for (final stream in _streams(streams))
        if ((jsonString(stream.raw['stream_key']), jsonString(_object(stream.json?['gear_info'])?['gear'])) case (
          final key?,
          final gear?,
        ))
          key: gear,
    };
    final headers = mediaHeaders(cookie: cookie);
    final lines = <LivePlayLine>[];
    final seen = <String>{};
    String? applied;
    final addresses = _object(_object(streams['avp_info_res'])?['stream_line_addr']);
    for (final MapEntry(:key, :value) in (addresses ?? const <String, dynamic>{}).entries) {
      final address = _object(value);
      var url = jsonString(_object(address?['cdn_info'])?['url']) ?? '';
      if (url.startsWith('//')) url = 'https:$url';
      final uri = jsonUrl(url);
      if (uri == null || !seen.add(url)) continue;
      applied ??= gears[key];
      lines.add(
        LivePlayLine(
          url,
          headers: headers,
          format: _format(uri),
          lineId: jsonString(address?['line_seq']) ?? uri.host,
          lease: lease(uri, issuedAt),
        ),
      );
    }
    return LivePlayUrlResolution.lines(
      lines,
      appliedQualityData: applied,
      qualityUnconfirmed: lines.isNotEmpty && applied == null,
    );
  }

  /// The other CDN lines (`line_seq`) the served stream is on, in server
  /// order: `stream_line_list` of the served `stream_key`, without the lines
  /// it was served on. One more request each (asking the served gear on
  /// that line) gives the stream there; measured: line 10 is `tx-flv-web`,
  /// 14 `ks-flv-web`.
  static List<int> otherLines(Map<String, dynamic> streams) {
    final avp = _object(streams['avp_info_res']);
    final addresses = _object(avp?['stream_line_addr']);
    if (addresses == null || addresses.isEmpty) return const [];
    final served = {for (final value in addresses.values) ?jsonInt(_object(value)?['line_seq'])};
    final infos = _object(_object(avp?['stream_line_list'])?[addresses.keys.first])?['line_infos'];
    final lines = <int>[];
    for (final raw in _list(infos)) {
      final line = jsonInt(_object(raw)?['line_seq']);
      if (line != null && line >= 0 && !served.contains(line) && !lines.contains(line)) lines.add(line);
    }
    return lines;
  }

  /// [first] followed by the lines of [others] (the answers on
  /// [otherLines]) that serve the same gear, each with its own lease: one
  /// quality, several CDN lines backing each other up. An answer serving
  /// another gear, and a [first] whose gear is unknown, add nothing.
  static LivePlayUrlResolution withLines(LivePlayUrlResolution first, Iterable<LivePlayUrlResolution> others) {
    final applied = first.appliedQualityData;
    if (applied == null) return first;
    final seen = {for (final line in first.lines) line.url};
    return LivePlayUrlResolution.lines(
      [
        ...first.lines,
        for (final other in others)
          if (other.appliedQualityData == applied)
            for (final line in other.lines)
              if (seen.add(line.url)) line,
      ],
      appliedQualityData: applied,
      qualityUnconfirmed: first.qualityUnconfirmed,
    );
  }

  /// The stream-manager quality that stands for the mobile HLS quality
  /// [id] among a channel's stream-manager [qualities] (best first), for
  /// moving a remembered choice when stream-manager lists the qualities
  /// (`YySite.flvFirst`): `mobile-hls:4000` serves the channel's best
  /// stream (`…_0_0_0`, 蓝光 or 高清 by channel), the first quality;
  /// `mobile-hls:1200` its lowest, the last. Any other id is returned as it
  /// is; null when [qualities] is empty.
  static String? flvQualityId(String id, List<LivePlayQuality> qualities) {
    if (qualities.isEmpty) return null;
    final quality = switch (id) {
      '${mobileHlsPrefix}4000' => qualities.first,
      '${mobileHlsPrefix}1200' => qualities.last,
      _ => null,
    };
    return quality == null ? id : '${quality.selectionId}';
  }

  /// The lease of a FLV URL received at [issuedAt]: `t` is the Unix second
  /// its signature stops opening connections (issue + 600 s); renew
  /// [leaseLead] (at most a quarter of the lifetime) before. An open
  /// connection keeps flowing past it (780 s held, spec §6.3). No `t`, or
  /// one already past, is no lease. Mobile HLS URLs carry the issue time in
  /// `t`, not an expiry: they get none.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    if (_format(url) != StreamFormat.flv) return null;
    final expiry = int.tryParse(url.queryParameters['t'] ?? '');
    if (expiry == null || expiry < 1000000000) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  /// A mobile HLS answer (`hls/new/get/<sid>/<ssid>/<rate>`, JSONP-like
  /// `({…})`): the playlist and the stream it serves, or null when the
  /// channel has none (`code` not 0, or no http(s) `hls`: an offline
  /// channel).
  static YyMobileHls? mobileHls(String body, {int status = 200}) {
    if (status >= 500) throw NetworkFailure(_site, 'mobile HLS: HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, 'mobile HLS: HTTP $status');
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    Object? decoded;
    if (start >= 0 && end > start) {
      try {
        decoded = jsonDecode(body.substring(start, end + 1));
      } on FormatException {
        decoded = null;
      }
    }
    final data = _object(decoded);
    if (data == null) throw ApiChanged(_site, 'mobile HLS: no JSON object (${_snippet(body)})');
    if (jsonInt(data['code']) != 0) return null;
    final url = jsonUrl(data['hls']);
    if (url == null) return null;
    return (
      url: url,
      width: jsonInt(data['width']) ?? 0,
      height: jsonInt(data['height']) ?? 0,
      video: jsonString(data['video']) ?? '',
    );
  }

  /// The qualities of the mobile HLS answers by rate (3.x's
  /// `_getMobileHlsQualities`): 1200 is 流畅 and 4000 高清, with the short
  /// edge (`流畅 · 360p`); rates that serve the same stream keep the later
  /// (higher) request; best first.
  static List<LivePlayQuality> mobileQualities(List<({String rate, YyMobileHls? hls})> answers) {
    final byStream = <String, LivePlayQuality>{};
    for (final (:rate, :hls) in answers) {
      if (hls == null) continue;
      final shortEdge = hls.width > 0 && hls.height > 0 ? (hls.width < hls.height ? hls.width : hls.height) : 0;
      final identity = hls.video.isNotEmpty ? hls.video : '${hls.width}x${hls.height}';
      final tier = rate == mobileHlsRates.first ? '流畅' : '高清';
      byStream[identity] = LivePlayQuality(
        quality: '$tier${shortEdge > 0 ? ' · ${shortEdge}p' : ''}',
        id: '$mobileHlsPrefix$rate',
        sort: int.tryParse(rate) ?? 0,
        data: '$mobileHlsPrefix$rate',
      );
    }
    return byStream.values.toList()..sort((left, right) => right.sort.compareTo(left.sort));
  }

  /// The one HLS line of a mobile answer, with the media headers. [rate] is
  /// the confirmed quality when a mobile quality was asked for; standing in
  /// for a stream-manager quality confirms nothing.
  static LivePlayUrlResolution mobileResolution(YyMobileHls hls, {String? rate, String cookie = ''}) =>
      LivePlayUrlResolution.lines([
        LivePlayLine(
          hls.url.toString(),
          headers: mediaHeaders(cookie: cookie),
          format: StreamFormat.hls,
          lineId: hls.url.host,
        ),
      ], appliedQualityData: rate == null ? null : '$mobileHlsPrefix$rate');

  // Helpers -------------------------------------------------------------------

  /// Each `channel_stream_info.streams[]` with its `json` decoded (null when
  /// it is not a JSON object).
  static Iterable<({Map<String, dynamic> raw, Map<String, dynamic>? json})> _streams(
    Map<String, dynamic> streams,
  ) sync* {
    for (final raw in _list(_object(streams['channel_stream_info'])?['streams'])) {
      final stream = _object(raw);
      if (stream == null) continue;
      Object? decoded;
      final text = jsonString(stream['json']);
      if (text != null) {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          decoded = null;
        }
      }
      yield (raw: stream, json: _object(decoded));
    }
  }

  static StreamFormat? _format(Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.flv')) return StreamFormat.flv;
    if (path.endsWith('.m3u8')) return StreamFormat.hls;
    return null;
  }

  /// The area named by [biz], learnt from an area page, else preset
  /// ([bizAreaNames]), else empty: the raw key (`chicken`) is no name, and
  /// `other`, the key of every recommendation, is no area.
  static String _areaOf(Object? biz, Map<String, String> areaNames) {
    final key = jsonString(biz) ?? '';
    if (key == otherBiz) return '';
    return areaNames[key] ?? bizAreaNames[key] ?? '';
  }

  /// `liveOn` and friends: 1, true or `live` (3.x's `isLiveValue`).
  static bool _isLive(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'live';
  }

  /// `decodeURIComponent` without throwing: a malformed escape stays as
  /// written, malformed UTF-8 becomes U+FFFD.
  static String _percentDecode(String text) {
    final bytes = <int>[];
    for (var i = 0; i < text.length; i++) {
      final byte = text[i] == '%' && i + 2 < text.length ? int.tryParse(text.substring(i + 1, i + 3), radix: 16) : null;
      if (byte != null) {
        bytes.add(byte);
        i += 2;
      } else {
        bytes.addAll(utf8.encode(text[i]));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// A YY channel number: a positive decimal without leading zeros.
String? _channel(Object? value) {
  final text = jsonString(value);
  return text != null && RegExp(r'^[1-9]\d{0,15}$').hasMatch(text) ? text : null;
}

/// 3.x's `validImgUrl` and `normalizeWebUrl`: protocol-relative and http
/// addresses are served over https.
String _https(String url) {
  final value = url.trim();
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

/// An image address made absolute by [normalizeImageUrl], over https
/// (3.x's `validImgUrl`); empty when there is none.
String _image(Object? value) => _https(normalizeImageUrl(value));

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The decoded JSON of [body]: HTTP 429 → `RateLimited`, 5xx →
/// `NetworkFailure`, any other non-2xx → `ApiChanged`; a body that is not
/// JSON is null.
Object? _decoded(String body, {required int status, required String what}) {
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// The `{resultCode, data}` envelope of `page.action` and `liveInfoDetail`:
/// any `resultCode` but 0, or a body that is not a JSON object, is
/// `ApiChanged`.
Map<String, dynamic> _checked(String body, {required int status, required String what}) {
  final root = _object(_decoded(body, status: status, what: what));
  if (root == null) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  final code = jsonInt(root['resultCode']);
  if (code != 0) throw ApiChanged(_site, '$what: resultCode $code (${_snippet(body)})');
  return root;
}
