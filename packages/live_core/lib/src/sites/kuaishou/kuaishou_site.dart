import 'dart:math';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kuaishou/kuaishou_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'kuaishou';
const _host = 'live.kuaishou.com';

/// How long an anonymous session is sent before the next room entry starts
/// a new one (3.x: 30 minutes).
const _sessionLifetime = Duration(minutes: 30);

const _accept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,'
    'application/signed-exchange;v=b3';

/// Where a new session's device id is reported (3.x's `registerDid`).
final Uri _deviceReport = Uri.parse(
  'https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC',
);

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// Streamer ids: the generated `3x…` ids and custom Kuaishou ids.
final RegExp _roomIdPattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// The Kuaishou adapter (3.x's `KuaishowSite`; parsing in [KuaishouApi]).
///
/// Every request names one desktop browser ([BrowserUserAgent]: the UA and
/// matching client hints), picked anew with each anonymous session. Lists
/// and search go without a cookie. Room pages carry the user's cookie when
/// one is configured, else the anonymous session: a bare visit of the room
/// page whose `Set-Cookie` is kept for 30 minutes, its device id reported
/// once, shared by concurrent callers. Media requests carry only the
/// user's cookie. Failures are `SiteError`s; nothing is disguised as an
/// offline room.
final class KuaishouSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver, LivePlayRecoveryResolver {
  /// Creates the adapter. [_cookies] holds the user's cookie, if any;
  /// [preferH264] reads "优先 H.264" (on by default, the setting shared with
  /// 22-3) at each call: on, the H.265-only qualities of a room page come
  /// after its H.264 ones; off, every quality by sort. [now] and [random]
  /// (the browser identity, the report's counter) are injectable for tests.
  new(this.http, {this._cookies, bool Function()? preferH264, DateTime Function()? now, Random? random})
    : _preferH264 = preferH264 ?? _on,
      _now = now ?? DateTime.now,
      _random = random ?? Random();

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final bool Function() _preferH264;
  final DateTime Function() _now;

  static bool _on() => true;
  final Random _random;
  late BrowserUserAgent _browser = BrowserUserAgent.random(_random);
  _Session? _session;
  Future<_Visit>? _bootstrap;

  /// The device report of the latest session, while or after it is sent.
  Future<void> _reported = Future.value();

  /// What each area page after the first needs, by `areaId#page`: the
  /// previous page's `cursor` ('' for none) and the identities of the rooms
  /// listed on the pages before it; null past the last page.
  final Map<String, ({String cursor, Set<String> listed})?> _areaPages = {};

  @override
  String get id => _site;

  @override
  String get name => '快手直播';

  // Session -------------------------------------------------------------------

  /// The user's cookie ('' when signed out), control characters removed.
  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  /// The anonymous session's cookie header while it is younger than 30
  /// minutes, else null.
  String? _sessionCookie() {
    final session = _session;
    if (session == null) return null;
    if (_now().difference(session.since) < _sessionLifetime) return session.header;
    _session = null;
    return null;
  }

  /// The cookie the danmaku feed gets: the user's, else the session's.
  String _danmakuCookie() {
    final login = _login();
    return login.isNotEmpty ? login : _sessionCookie() ?? '';
  }

  /// Makes sure an anonymous session exists (3.x's `_ensureSession`): a bare
  /// GET of the room page [url] as a new browser, whose `Set-Cookie` (`did`,
  /// `clientid`, `client_key`, `kpn`, `kuaishou.live.bfb1s`) becomes the
  /// session, then the best-effort report of its `did` ([_reported]).
  /// Concurrent callers share one bootstrap.
  ///
  /// Returns that visit when it was of [url] (G03.1: it is the room page
  /// itself, which [_roomPage] reads before asking again), else null. The
  /// visit does not wait for the report.
  Future<LiveResponse?> _ensureSession(Uri url) async {
    if (_sessionCookie() != null) return null;
    final visit = await (_bootstrap ??= () async {
      try {
        _browser = BrowserUserAgent.random(_random);
        final response = await _get(url, _pageHeaders(null));
        final cookies = KuaishouApi.setCookies(response.headers['set-cookie'] ?? const []);
        if (cookies.isNotEmpty) {
          _session = _Session(cookies, _now());
          if (cookies['did'] case final did?) _reported = _reportDevice(did).then((_) {}, onError: (Object _) {});
        }
        return _Visit(url, response);
      } finally {
        _bootstrap = null;
      }
    }());
    return visit.url == url ? visit.page : null;
  }

  /// POSTs the `misc2` report of [did]; failures are ignored (3.x did the
  /// same). The session cookie stays with `live.kuaishou.com`.
  Future<void> _reportDevice(String did) async {
    try {
      await _send(
        LiveRequest.json(
          site: _site,
          url: _deviceReport,
          json: KuaishouApi.devicePayload(
            did,
            timestamp: _now().millisecondsSinceEpoch,
            incrementId: _random.nextInt(8999) + 1000,
          ),
          headers: {..._browser.headers, 'origin': KuaishouApi.origin, 'referer': '${KuaishouApi.origin}/'},
        ),
      );
    } on SiteError {
      // Best effort: the room page decides.
    }
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

  /// The browser's headers for lists and search (3.x's fixed page headers,
  /// with a consistent browser identity).
  Map<String, String> _webHeaders() => {
    ..._browser.headers,
    'accept': _accept,
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': 'same-origin',
    'sec-fetch-user': '?1',
  };

  /// Room page headers: [_webHeaders] with `;q=0.9` on `accept`, and
  /// [cookie].
  Map<String, String> _pageHeaders(String? cookie) => {..._webHeaders(), 'accept': '$_accept;q=0.9', 'cookie': ?cookie};

  /// GETs the room page of [id] and hands it to [parse] with the cookie it
  /// carried.
  ///
  /// A user cookie goes alone, without a session or a retry; a refusal is
  /// the cookie's (`RiskControl.cookieSuspect`). Anonymous pages carry the
  /// live session; with [ensureSession] one is made first (room entry,
  /// recording, streams), without it the page goes as it is (follow
  /// refresh). A refused or unreadable page (`RiskControl`, `ApiChanged`)
  /// drops the session, makes a new one and is retried once (3.x retried
  /// the refresh the same way).
  ///
  /// A new session's visit is this page already (G03.1: on the K90 the
  /// second request made a first room entry take 1.0-1.35 s instead of
  /// 0.3-0.5 s): when it reads as one it is the answer, with the session
  /// for the danmaku feed, and the device report goes on alone. A visit
  /// that does not read leaves it to the page with the session, sent
  /// after the report as before.
  Future<T> _roomPage<T>(
    String id,
    T Function(LiveResponse response, {required String cookie, required bool userCookie}) parse, {
    required bool ensureSession,
  }) async {
    final url = Uri.parse(KuaishouApi.roomPageUrl(id));
    final login = _login();
    if (login.isNotEmpty) return parse(await _get(url, _pageHeaders(login)), cookie: login, userCookie: true);
    var visit = ensureSession ? await _ensureSession(url) : null;
    for (var attempt = 0; ; attempt++) {
      if (visit != null) {
        try {
          return parse(visit, cookie: _sessionCookie() ?? '', userCookie: false);
        } on SiteError {
          // The page with the session decides, as before.
        }
      }
      await _reported;
      final cookie = _sessionCookie();
      final response = await _get(url, _pageHeaders(cookie));
      try {
        return parse(response, cookie: cookie ?? '', userCookie: false);
      } on SiteError catch (error) {
        if (attempt > 0 || (error is! RiskControl && error is! ApiChanged)) rethrow;
      }
      _session = null;
      visit = await _ensureSession(url);
    }
  }

  // Catalog and search --------------------------------------------------------

  /// The eight fixed categories with every area: pages follow `hasMore`,
  /// and a page with nothing new ends a category (a server repeating a page
  /// cannot loop it). Any failing page fails the catalog (3.x went through
  /// the v4 bridge here and did the same).
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => [
    for (final top in KuaishouApi.topCategories)
      LiveCategory(id: top.id, name: top.name, children: await _areas(top.id, top.name)),
  ];

  Future<List<LiveArea>> _areas(String id, String name) async {
    final areas = <String, LiveArea>{};
    for (var page = 1; ; page++) {
      final response = await _get(
        Uri.https(_host, '/live_api/category/data', {'type': id, 'page': '$page', 'size': '30'}),
        _webHeaders(),
      );
      final result = KuaishouApi.areas(response.text, categoryId: id, categoryName: name, status: response.status);
      var added = false;
      for (final area in result.areas) {
        if (areas.containsKey(area.areaId)) continue;
        areas[area.areaId] = area;
        added = true;
      }
      if (!result.hasMore || !added) return [...areas.values];
    }
  }

  /// Rooms of [category]: ids shorter than 7 characters are game areas
  /// (`gameboard`), the rest `non-gameboard`, 20 a page. A non-gameboard
  /// page after the first sends the previous page's `cursor` (3.x never
  /// did and got page 1 again); a page not reached yet is walked to from
  /// page 1, and a page past the last is empty without a request.
  ///
  /// A room already listed on an earlier page since page 1 was last read,
  /// or earlier on the same page, is left out: the live ranking shifts
  /// between requests and a room moving down shows up again on the next
  /// page (docs/specs/UPGRADES.md, "翻页"). Reading page 1 again starts over.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _areaRooms(category.areaId.trim(), page < 1 ? 1 : page);

  Future<List<LiveRoom>> _areaRooms(String areaId, int page) async {
    var cursor = '';
    var listed = const <String>{};
    if (page > 1) {
      final key = '$areaId#$page';
      if (!_areaPages.containsKey(key)) await _areaRooms(areaId, page - 1);
      if (!_areaPages.containsKey(key)) return const [];
      final stored = _areaPages[key];
      if (stored == null) return const [];
      (:cursor, :listed) = stored;
    }
    final board = areaId.length < 7 ? 'gameboard' : 'non-gameboard';
    final response = await _get(
      Uri.https(_host, '/live_api/$board/list', {
        'filterType': '0',
        'pageSize': '20',
        'gameId': areaId,
        'page': '$page',
        if (cursor.isNotEmpty) 'cursor': cursor,
      }),
      _webHeaders(),
    );
    final result = KuaishouApi.areaRooms(
      response.text,
      issuedAt: _now(),
      cookie: _danmakuCookie(),
      status: response.status,
    );
    final seen = {...listed};
    final rooms = [
      for (final room in result.rooms)
        if (seen.add(room.identityKey)) room,
    ];
    final next = '$areaId#${page + 1}';
    _areaPages
      ..remove(next)
      ..[next] = result.hasMore ? (cursor: result.cursor ?? '', listed: Set.unmodifiable(seen)) : null;
    if (_areaPages.length > 256) _areaPages.remove(_areaPages.keys.first);
    return rooms;
  }

  /// The home list: one page (3.x answered every page with it), one card
  /// per streamer.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page > 1) return const [];
    final response = await _get(Uri.https(_host, '/live_api/home/list'), _webHeaders());
    return KuaishouApi.recommendRooms(
      response.text,
      issuedAt: _now(),
      cookie: _danmakuCookie(),
      status: response.status,
    );
  }

  /// The streamer search (`lssid` empty, as in 3.x), at most [pageSize]
  /// results. A blank keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final number = page < 1 ? 1 : page;
    final encoded = Uri.encodeQueryComponent(text);
    final response = await _get(
      // Built by hand: Uri drops the `=` of an empty value, and the site gets `lssid=`.
      Uri.parse('https://$_host/live_api/search/author?keyword=$encoded&page=$number&lssid='),
      {..._webHeaders(), 'referer': 'https://$_host/search?keyword=$encoded'},
    );
    return KuaishouApi.searchRooms(response.text, status: response.status).take(max(pageSize, 0)).toList();
  }

  /// The streamers of [searchRooms] (3.x answered none; pure_live_TV maps
  /// the same search).
  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => [
    for (final room in await searchRooms(keyword, page: page, pageSize: pageSize))
      LiveAnchorItem(roomId: room.roomId, avatar: room.avatar, userName: room.nick, liveStatus: room.isLiveNow),
  ];

  // Rooms ---------------------------------------------------------------------

  Future<LiveRoom> _detail(String roomId, {required bool withStreams, required bool ensureSession}) async {
    final id = roomId.trim();
    if (id.isEmpty) throw const NotFound(_site, 'empty room id');
    return await _roomPage(
      id,
      (response, {required cookie, required userCookie}) => KuaishouApi.roomDetail(
        response.text,
        requestedId: id,
        issuedAt: _now(),
        withStreams: withStreams,
        cookie: cookie,
        userCookie: userCookie,
        status: response.status,
        url: response.url,
      ),
      ensureSession: ensureSession,
    );
  }

  /// The room with its streams and danmaku arguments, after making sure of
  /// a session.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, withStreams: true, ensureSession: true);

  /// Follow-card refresh: the page without its streams, sent as it is (a
  /// session is made only when the page is refused).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) =>
      _detail(roomId, withStreams: false, ensureSession: false);

  /// The same page as room entry; every failure is thrown and only
  /// `isLiving` false is offline.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) =>
      _detail(roomId, withStreams: true, ensureSession: true);

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// Qualities of the streams [detail] carries (a room without them, like a
  /// refreshed follow, fetches its page).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final qualities = KuaishouApi.qualities((await _streams(detail, fresh: false)).playUrls, preferH264: _preferH264());
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'playUrls: no playable representation');
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] from the streams [detail] carries: media
  /// headers with the user's cookie only, CDN host, codec and the lease of
  /// the signature.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(detail, quality, await _streams(detail, fresh: false));

  /// Renewal and recovery read a fresh room page: the signed URLs [detail]
  /// carries expire, and a new broadcast has new ones.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(detail, quality, await _streams(detail, fresh: true));

  LivePlayUrlResolution _resolve(
    LiveRoom detail,
    LivePlayQuality quality,
    ({Object? playUrls, DateTime issuedAt}) streams,
  ) => KuaishouApi.resolution(
    streams.playUrls,
    quality: quality,
    roomId: detail.roomId,
    issuedAt: streams.issuedAt,
    cookie: _login(),
  );

  /// The `playUrls` [detail] carries, or (when it has none, or [fresh]) the
  /// ones of a new room page; a room that is not living has none
  /// (`StreamUnavailable`).
  Future<({Object? playUrls, DateTime issuedAt})> _streams(LiveRoom detail, {required bool fresh}) async {
    if (detail.data case KuaishouRoomData(:final playUrls?, :final issuedAt) when !fresh) {
      return (playUrls: playUrls, issuedAt: issuedAt ?? _now());
    }
    final room = await _detail(detail.roomId, withStreams: true, ensureSession: true);
    final data = room.data;
    if (!room.isLiveNow || data is! KuaishouRoomData) {
      throw StreamUnavailable(_site, 'room page: ${detail.roomId} is not living');
    }
    return (playUrls: data.playUrls, issuedAt: data.issuedAt ?? _now());
  }

  // Links ---------------------------------------------------------------------

  /// A room page `/u/{id}` on `live.kuaishou.com` or `live.kuaishou.cn`;
  /// other pages there (search, categories) are not rooms. Share links
  /// (`v.kuaishou.com`) and mobile pages are not supported, as in 3.x.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    final host = uri.host.toLowerCase();
    if (host != _host && host != 'live.kuaishou.cn') return null;
    final segments = RoomPaths.segments(uri);
    if (segments.length < 2 || segments.first.toLowerCase() != 'u') return null;
    final id = segments[1].trim();
    return RoomPaths.isRoomIdentifier(id, _roomIdPattern) ? id : null;
  }
}

/// A session's first visit: the room page it was made on.
final class _Visit {
  new(this.url, this.page);

  final Uri url;
  final LiveResponse page;
}

/// The anonymous session: the room page's cookies and when they came.
final class _Session {
  new(this.cookies, this.since);

  final Map<String, String> cookies;
  final DateTime since;

  String get header => [for (final MapEntry(:key, :value) in cookies.entries) '$key=$value'].join('; ');
}
