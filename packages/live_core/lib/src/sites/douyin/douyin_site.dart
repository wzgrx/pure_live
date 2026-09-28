import 'dart:async';
import 'dart:math';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/douyin/douyin_api.dart';
import 'package:live_core/src/sites/douyin/douyin_sign.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

const _site = 'douyin';
const _live = 'live.douyin.com';
const _amemv = 'webcast.amemv.com';
const _partitionPath = '/webcast/web/partition/detail/room/v2/';

/// Rooms per area page (3.x ignored the caller's page size).
const _areaPageSize = 15;

/// How long to go without an anonymous session after the home page set no
/// ttwid before asking again (the page is about 1 MB).
const _bootstrapRetry = Duration(minutes: 5);

/// Search asks at most this many name-matched partitions for rooms.
const _searchPartitions = 3;

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');
final RegExp _reflowPath = RegExp(r'(?:^|/)reflow/(\d+)(?:/|$)');
final Uri _homeUrl = Uri.https(_live, '/', {'from_nav': '1'});

/// Headers of 3.x's short-link requests.
const Map<String, String> _shortLinkHeaders = {
  'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'accept': '*/*',
  'origin': 'https://live.douyin.com',
  'referer': 'https://live.douyin.com/',
};

/// What a room's streams need besides its identity: the web_rid, this
/// broadcast's room_id (danmaku, the app's deep link), the stream
/// description (`room.stream_url` while live; the geometry hint reads its
/// `sdk_params`) and when it was fetched (the leases count from then).
@immutable
final class DouyinRoomData {
  /// Creates the data.
  const new({required this.webRid, required this.issuedAt, this.roomId, this.streamUrl});

  /// The room's lasting id.
  final String webRid;

  /// This broadcast's room_id; every broadcast gets a new one.
  final String? roomId;

  /// `room.stream_url` while live, else null.
  final Map<String, dynamic>? streamUrl;

  /// When the detail was received.
  final DateTime issuedAt;
}

/// The Douyin adapter (3.x's `DouyinSite` and `DouyinSearch`; parsing in
/// [DouyinApi], signing in [DouyinSigner]).
///
/// Requests carry the user's cookie, else an anonymous `ttwid` fetched once
/// per cookie and shared by concurrent callers; a changed cookie starts a
/// new session at once (REG-DOUYIN-017: 3.x kept the first cookie for the
/// whole process). Failures are `SiteError`s; nothing is disguised as an
/// offline room.
final class DouyinSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver, LivePlayRecoveryResolver {
  /// Creates the adapter. [cookies] holds the user's cookie, if any; [now]
  /// and [random] (visitor id, msToken, a_bogus) are injectable for tests.
  factory(LiveHttp http, {CookieVault? cookies, DateTime Function()? now, Random? random}) {
    final source = random ?? Random.secure();
    final clock = now ?? DateTime.now;
    return DouyinSite._(
      http,
      cookies,
      clock,
      DouyinSigner.visitorId(source),
      DouyinSigner(userAgent: DouyinApi.userAgent, now: clock, random: source),
    );
  }

  new _(this.http, this._cookies, this._now, this.visitorId, this._signer);

  /// Transport.
  final LiveHttp http;

  /// The 19-digit anonymous visitor id of the danmaku connection, the same
  /// for every room (3.x kept one per process).
  final String visitorId;

  final CookieVault? _cookies;
  final DateTime Function() _now;
  final DouyinSigner _signer;
  _Session? _session;

  /// Rooms the recommendation draws already delivered since page 1.
  final Set<String> _recommended = {};

  @override
  String get id => _site;

  @override
  String get name => '抖音直播';

  // Session -------------------------------------------------------------------

  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  /// The session of the current cookie; a changed cookie starts a new one.
  _Session _current() {
    final login = _login();
    final session = _session;
    if (session != null && session.login == login) return session;
    return _session = _Session(login);
  }

  /// The cookie of API requests: the user's, else the anonymous one. A
  /// session whose cookie changed while its bootstrap ran is not used.
  Future<String> _cookie() async {
    while (true) {
      final session = _current();
      final cookie = await _sessionCookie(session);
      if (identical(_current(), session)) return cookie;
    }
  }

  /// The cookie known without a request (media headers).
  String _knownCookie() {
    final session = _current();
    return session.login.isNotEmpty ? session.login : session.anonymous ?? '';
  }

  Future<String> _sessionCookie(_Session session) async {
    if (session.login.isNotEmpty) return session.login;
    final anonymous = session.anonymous;
    if (anonymous != null) return anonymous;
    final missedAt = session.missedAt;
    if (missedAt != null && _now().difference(missedAt) < _bootstrapRetry) return '';
    return await (session.bootstrap ??= _bootstrap(session)) ?? '';
  }

  /// `GET live.douyin.com/?from_nav=1` keeps its `ttwid` and `UIFID_TEMP`.
  /// A failed request gives none and the next request asks again; a page
  /// without a ttwid is not asked for again for five minutes.
  Future<String?> _bootstrap(_Session session) async {
    try {
      return _keep(session, await _get(_homeUrl, DouyinApi.apiHeaders('')));
    } on SiteError {
      return null;
    } finally {
      session.bootstrap = null;
    }
  }

  String? _keep(_Session session, LiveResponse response) {
    if (!response.isSuccess) return null;
    final cookie = DouyinApi.anonymousCookie(response.headers);
    if (cookie == null) {
      session.missedAt = _now();
      return null;
    }
    session.missedAt = null;
    return session.anonymous ??= cookie;
  }

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, Map<String, String> headers) =>
      _send(LiveRequest(site: _site, url: url, headers: headers));

  // Catalog -------------------------------------------------------------------

  /// The home page's categories; the same request starts the anonymous
  /// session when there is none yet (3.x asked for the page twice).
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final session = _current();
    final response = await _get(_homeUrl, DouyinApi.apiHeaders(_knownCookie()));
    if (session.login.isEmpty && session.anonymous == null) _keep(session, response);
    return DouyinApi.categories(response.text, status: response.status, headers: response.headers);
  }

  /// An area's rooms, 15 from `(page - 1) × 15`, signed with a_bogus. A
  /// captcha answer (the signature was refused) is asked once of the
  /// unsigned `webcast.amemv.com` host, which serves the same list.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final area = DouyinApi.partition(category.areaId);
    final offset = ((page < 1 ? 1 : page) - 1) * _areaPageSize;
    final cookie = await _cookie();
    final response = await _get(
      _signer.signedUrl(Uri.https(_live, _partitionPath), {
        'aid': DouyinApi.aid,
        'app_name': 'douyin_web',
        'live_id': '1',
        'device_platform': 'web',
        'language': 'zh-CN',
        'enter_from': 'link_share',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
        'browser_online': 'true',
        'count': '$_areaPageSize',
        'offset': '$offset',
        'partition': area.partition,
        'partition_type': area.type,
        'req_from': '2',
      }),
      DouyinApi.apiHeaders(cookie),
    );
    try {
      return DouyinApi.partitionRooms(
        response.text,
        offset: offset,
        areaName: category.areaName,
        status: response.status,
        headers: response.headers,
      ).rooms;
    } on RiskControl catch (signed) {
      try {
        return await _amemvRooms(
          area,
          count: _areaPageSize,
          offset: offset,
          cookie: cookie,
          areaName: category.areaName,
        );
      } on SiteError {
        throw signed;
      }
    }
  }

  /// 3.x's unsigned partition request to `webcast.amemv.com` (search
  /// headers, Chrome parameters).
  Future<List<LiveRoom>> _amemvRooms(
    ({String partition, String type}) area, {
    required int count,
    required int offset,
    required String cookie,
    required String areaName,
  }) async {
    final response = await _get(
      Uri.https(_amemv, _partitionPath, _searchPartitionParams(area, count: count, offset: offset)),
      DouyinApi.searchHeaders('', cookie),
    );
    return DouyinApi.partitionRooms(
      response.text,
      offset: offset,
      areaName: areaName,
      status: response.status,
      headers: response.headers,
    ).rooms;
  }

  static Map<String, String> _searchPartitionParams(
    ({String partition, String type}) area, {
    required int count,
    required int offset,
  }) => {
    'aid': DouyinApi.aid,
    'app_name': 'douyin_web',
    'live_id': '1',
    'device_platform': 'web',
    'language': 'zh-CN',
    'browser_language': 'zh-CN',
    'browser_platform': 'Win32',
    'browser_name': 'Chrome',
    'browser_version': '120.0.0.0',
    'partition': area.partition,
    'partition_type': area.type,
    'count': '$count',
    'offset': '$offset',
    'cookie_enabled': 'true',
    'screen_width': '1920',
    'screen_height': '1080',
  };

  /// The feed (unsigned). It takes no page: every request is a new random
  /// draw, so later pages give only the rooms not delivered since page 1 and
  /// a draw with nothing new ends the list (pure_live_TV's fix; 3.x appended
  /// the same rooms again).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page <= 1) _recommended.clear();
    final cookie = await _cookie();
    final response = await _get(
      Uri.https(_live, '/webcast/feed/', {
        'aid': DouyinApi.aid,
        'app_name': 'douyin_web',
        'need_map': '1',
        'is_draw': '1',
        'inner_from_drawer': '0',
        'enter_source': 'web_homepage_hot_web_live_card',
        'source_key': 'web_homepage_hot_web_live_card',
      }),
      DouyinApi.apiHeaders(cookie),
    );
    final rooms = DouyinApi.feed(response.text, status: response.status, headers: response.headers);
    return [
      for (final room in rooms)
        if (_recommended.add(room.roomId)) room,
    ];
  }

  // Search --------------------------------------------------------------------

  /// 3.x's three paths, each tried when the one before failed or found
  /// nothing: live search, general search (both need a signed-in cookie:
  /// anonymous requests answer 2483), then the rooms of the first three
  /// partitions whose name matches [keyword]. [pageSize] is limited to 1–50.
  /// A failure of the last path is reported (3.x answered "no results").
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final count = pageSize.clamp(1, 50);
    final offset = count * ((page < 1 ? 1 : page) - 1);
    final cookie = await _cookie();
    final headers = DouyinApi.searchHeaders(text, cookie);
    for (final (path, extra) in [
      (
        '/aweme/v1/web/live/search/',
        const {
          'search_source': 'switch_tab',
          'query_correct_type': '1',
          'need_filter_settings': '1',
          'list_type': 'single',
        },
      ),
      ('/aweme/v1/web/general/search/stream/', const <String, String>{}),
    ]) {
      try {
        final response = await _get(
          Uri.https('www.douyin.com', path, {
            'device_platform': 'webapp',
            'aid': DouyinApi.aid,
            'channel': 'channel_pc_web',
            'search_channel': 'aweme_live',
            ...extra,
            'keyword': text,
            'offset': '$offset',
            'count': '$count',
            'os_version': '10',
          }),
          headers,
        );
        final rooms = DouyinApi.searchRooms(response.text, status: response.status, headers: response.headers);
        if (rooms.isNotEmpty) return rooms;
      } on SiteError {
        continue;
      }
    }
    return await _searchByPartition(text, count: count, offset: offset, cookie: cookie);
  }

  /// The partitions whose name matches [keyword] (anonymous), as areas for
  /// [getCategoryRooms].
  Future<List<LiveArea>> searchAreas(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    return await _partitionSearch(text, await _cookie());
  }

  Future<List<LiveArea>> _partitionSearch(String keyword, String cookie) async {
    final response = await _get(
      Uri.https(_live, '/webcast/web/partition/search/', {'keyword': keyword, 'aid': DouyinApi.aid}),
      DouyinApi.searchHeaders(keyword, cookie),
    );
    return DouyinApi.partitionSearch(response.text, status: response.status, headers: response.headers);
  }

  Future<List<LiveRoom>> _searchByPartition(
    String keyword, {
    required int count,
    required int offset,
    required String cookie,
  }) async {
    final areas = await _partitionSearch(keyword, cookie);
    final merged = <LiveRoom>[];
    final seen = <String>{};
    SiteError? failure;
    var answered = false;
    for (final area in areas.take(_searchPartitions)) {
      final List<LiveRoom> rooms;
      try {
        rooms = await _searchPartitionRooms(area, count: count, offset: offset, cookie: cookie);
      } on SiteError catch (error) {
        failure ??= error;
        continue;
      }
      answered = true;
      for (final room in rooms) {
        if (!seen.add(room.roomId)) continue;
        merged.add(room);
        if (merged.length >= count) return merged;
      }
    }
    if (!answered && failure != null) throw failure;
    return merged;
  }

  /// One matched partition's rooms: `live.douyin.com`, signed (3.x asked it
  /// unsigned, which always meets the captcha), then `webcast.amemv.com`
  /// when that fails or is empty. Rooms without an area show the partition's.
  Future<List<LiveRoom>> _searchPartitionRooms(
    LiveArea area, {
    required int count,
    required int offset,
    required String cookie,
  }) async {
    final partition = DouyinApi.partition(area.areaId);
    try {
      final response = await _get(
        _signer.signedUrl(
          Uri.https(_live, _partitionPath),
          _searchPartitionParams(partition, count: count, offset: offset),
        ),
        DouyinApi.searchHeaders('', cookie),
      );
      final rooms = DouyinApi.partitionRooms(
        response.text,
        offset: offset,
        areaName: area.areaName,
        status: response.status,
        headers: response.headers,
      ).rooms;
      if (rooms.isNotEmpty) return rooms;
    } on SiteError {
      // The unsigned host below serves the same list.
    }
    return await _amemvRooms(partition, count: count, offset: offset, cookie: cookie, areaName: area.areaName);
  }

  // Rooms ---------------------------------------------------------------------

  /// A room by web_rid, or by a broadcast's room_id (over 16 digits; its
  /// identity becomes the owner's web_rid, and an ended broadcast is
  /// queried again by that web_rid, as in 3.x).
  Future<_Fetched> _fetch(String roomId) async {
    final id = roomId.trim();
    if (id.isEmpty) throw const NotFound(_site, 'empty room id');
    if (!DouyinApi.isRoomId(id)) return await _byWebRid(id);
    final reflowed = await _reflow(id);
    if (!reflowed.room.sessionEnded) return reflowed;
    return await _byWebRid(reflowed.room.room.roomId);
  }

  /// enter, then the room page when enter fails for any reason but NotFound
  /// (3.x fell back on every error, so a missing room surfaced as a failed
  /// HEAD request). A page without the room state reports enter's error.
  Future<_Fetched> _byWebRid(String webRid) async {
    try {
      return await _enter(webRid);
    } on NotFound {
      rethrow;
    } on SiteError catch (enterError) {
      try {
        return await _roomPage(webRid);
      } on ApiChanged {
        throw enterError;
      }
    }
  }

  Future<_Fetched> _enter(String webRid) async {
    final cookie = await _cookie();
    final response = await _get(
      _signer.signedUrl(Uri.https(_live, '/webcast/room/web/enter/'), {
        'app_name': 'douyin_web',
        'enter_from': 'web_live',
        'live_id': '1',
        'web_rid': webRid,
        'is_need_double_stream': 'false',
      }),
      DouyinApi.apiHeaders(cookie),
    );
    return (
      room: DouyinApi.enter(response.text, webRid: webRid, status: response.status, headers: response.headers),
      issuedAt: _now(),
      cookie: cookie,
    );
  }

  /// The room page with the session cookie (3.x first sent a HEAD for
  /// `ttwid`, `__ac_nonce` and `msToken`; the recorded page needed only the
  /// ttwid).
  Future<_Fetched> _roomPage(String webRid) async {
    final cookie = await _cookie();
    final response = await _get(Uri.https(_live, '/$webRid'), DouyinApi.apiHeaders(cookie));
    return (
      room: DouyinApi.roomPage(response.text, webRid: webRid, status: response.status, headers: response.headers),
      issuedAt: _now(),
      cookie: cookie,
    );
  }

  Future<_Fetched> _reflow(String roomId) async {
    final cookie = await _cookie();
    final response = await _get(
      Uri.https(_amemv, '/webcast/room/reflow/info/', {
        'type_id': '0',
        'live_id': '1',
        'room_id': roomId,
        'sec_user_id': '',
        'version_code': '99.99.99',
        'app_id': DouyinApi.aid,
      }),
      DouyinApi.apiHeaders(cookie),
    );
    return (
      room: DouyinApi.reflow(response.text, status: response.status, headers: response.headers),
      issuedAt: _now(),
      cookie: cookie,
    );
  }

  LiveRoom _detail(_Fetched fetched, {required bool danmaku}) {
    final (:room, :issuedAt, :cookie) = fetched;
    final webRid = room.room.roomId;
    return room.room.copyWith(
      data: DouyinRoomData(webRid: webRid, roomId: room.roomId, streamUrl: room.streamUrl, issuedAt: issuedAt),
      danmakuData: danmaku
          ? DouyinDanmakuArgs(
              webRid: webRid,
              roomId: room.roomId ?? '',
              userId: room.userUniqueId ?? visitorId,
              cookie: cookie,
            )
          : null,
    );
  }

  /// The room with its stream description and danmaku arguments. The
  /// identity is the web_rid: as requested, or the owner's for a room_id.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => _detail(await _fetch(roomId), danmaku: true);

  /// Follow-card refresh: the same lookup without danmaku arguments
  /// (pure_live_TV).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async =>
      _detail(await _fetch(roomId), danmaku: false);

  /// The detail already holds the streams; failures are thrown, never an
  /// offline-looking room (REG-DOUYIN-018).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => getRoomDetail(roomId: roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// [detail]'s stream data, fetched when the room came from elsewhere (a
  /// follow, a list).
  Future<DouyinRoomData> _data(LiveRoom detail) async => switch (detail.data) {
    final DouyinRoomData data => data,
    _ => (await getRoomDetailForRefresh(roomId: detail.roomId)).data! as DouyinRoomData,
  };

  /// The video qualities, best first; an offline room, or a live one without
  /// video (only audio or no stream; the detail marks it
  /// [LiveRestriction.unplayable]), is `StreamUnavailable` (3.x gave an empty
  /// list).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final data = await _data(detail);
    final qualities = DouyinApi.qualities(data.streamUrl);
    if (qualities.isEmpty) throw StreamUnavailable(_site, 'room ${data.webRid}: no video stream');
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] from the detail's stream description, with the
  /// media headers (3.x's `PlaybackHeaderResolver`) and a lease from each
  /// URL's expiry.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = await _data(detail);
    return DouyinApi.resolution(
      data.streamUrl,
      quality: quality,
      webRid: data.webRid,
      issuedAt: data.issuedAt,
      cookie: _knownCookie(),
    );
  }

  /// Fresh lines: the URLs come with the detail, so recovery fetches the
  /// detail again (never the cached, possibly expired URLs). [quality] is
  /// played when the new detail still offers it, else the best quality,
  /// which the resolution reports as applied.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final webRid = switch (detail.data) {
      final DouyinRoomData data => data.webRid,
      _ => detail.roomId,
    };
    final fetched = await _fetch(webRid);
    final streamUrl = fetched.room.streamUrl;
    final qualities = DouyinApi.qualities(streamUrl);
    if (qualities.isEmpty) throw StreamUnavailable(_site, 'room $webRid: no video stream');
    return DouyinApi.resolution(
      streamUrl,
      quality: DouyinApi.qualityFor(streamUrl, quality.id) ?? qualities.first,
      webRid: fetched.room.room.roomId,
      issuedAt: fetched.issuedAt,
      cookie: fetched.cookie,
    );
  }

  // Account -------------------------------------------------------------------

  /// The nickname of [cookie] (default: the stored one) from
  /// `webcast/user/me/`; `NeedsLogin` without a cookie (no request) or when
  /// the cookie is not signed in.
  Future<String> account({String? cookie}) async {
    final value = (cookie ?? _login()).replaceAll(_controlCharacters, '').trim();
    if (value.isEmpty) throw const NeedsLogin(_site, 'no cookie');
    final response = await _get(Uri.https(_live, '/webcast/user/me/', {'aid': DouyinApi.aid}), {
      'user-agent': DouyinApi.userAgent,
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'cookie': value,
    });
    return DouyinApi.account(response.text, status: response.status, headers: response.headers);
  }

  // Links ---------------------------------------------------------------------

  /// `live.douyin.com/{digits}[/…]` and `www.douyin.com/{1–20 digits}` (one
  /// segment only: videos, search pages and the bare site are not rooms,
  /// REG-DOUYIN-010/011).
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      return switch (uri.host.toLowerCase()) {
        _live => RoomPaths.firstSegment(uri, RegExp(r'^\d+$')),
        'www.douyin.com' => _webRoomId(uri),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  static String? _webRoomId(Uri uri) {
    final segments = RoomPaths.segments(uri);
    return segments.length == 1 && RegExp(r'^\d{1,20}$').hasMatch(segments.single) ? segments.single : null;
  }

  /// `v.douyin.com` share links and `webcast.amemv.com/…/reflow/{room_id}`.
  @override
  bool needsResolving(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return switch (uri.host.toLowerCase()) {
        'v.douyin.com' => RoomPaths.segments(uri).isNotEmpty,
        _amemv => _reflowPath.hasMatch(uri.path),
        _ => false,
      };
    } on FormatException {
      return false;
    }
  }

  /// 3.x's short-link rules (REG-DOUYIN-012): a `v.douyin.com` link is
  /// followed one redirect at a time, only through `v.douyin.com`,
  /// `www.douyin.com` and `webcast.amemv.com`; a room link ends it, and a
  /// reflow link is turned into the owner's web_rid by the reflow request.
  /// A direct reflow link gets the same request; when it fails, the room_id
  /// itself is the answer, as 3.x gave it (the detail turns it into the
  /// web_rid).
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.toLowerCase() == _amemv) {
      final roomId = _reflowPath.firstMatch(uri.path)?.group(1);
      if (roomId == null) return null;
      return LinkRoom(await _reflowWebRid(roomId, session) ?? roomId);
    }
    var current = uri;
    while (!session.isClosed) {
      final host = current.host.toLowerCase();
      if (host == _live || (host == 'www.douyin.com' && roomIdFromUrl('$current') != null)) {
        final roomId = roomIdFromUrl('$current');
        return roomId == null ? null : LinkRoom(roomId);
      }
      if (host != 'v.douyin.com' && host != 'www.douyin.com' && host != _amemv) return null;
      final roomId = host == 'v.douyin.com' ? null : _reflowPath.firstMatch(current.path)?.group(1);
      if (roomId != null) {
        final webRid = await _reflowWebRid(roomId, session);
        return webRid == null ? null : LinkRoom(webRid);
      }
      final target = ShortLinkSession.redirectTarget(current, await session.get(current, headers: _shortLinkHeaders));
      if (target == null) return null;
      current = target;
    }
    return null;
  }

  /// 3.x's reflow request of the short-link parser (`app_id=1128`).
  Future<String?> _reflowWebRid(String roomId, ShortLinkSession session) async {
    final response = await session.get(
      Uri.https(_amemv, '/webcast/room/reflow/info/', {
        'room_id': roomId,
        'verifyFp': '',
        'type_id': '0',
        'live_id': '1',
        'sec_user_id': '',
        'app_id': '1128',
      }),
      readBody: true,
      headers: _shortLinkHeaders,
    );
    if (response == null || response.status != 200) return null;
    return DouyinApi.reflowWebRid(response.text);
  }
}

typedef _Fetched = ({DouyinRoom room, DateTime issuedAt, String cookie});

/// The anonymous session of one cookie ('' when signed out).
final class _Session {
  new(this.login);

  /// The user's cookie.
  final String login;

  /// `ttwid=…; UIFID_TEMP=…` from the home page.
  String? anonymous;

  /// When the home page last set no ttwid.
  DateTime? missedAt;

  Future<String?>? bootstrap;
}
