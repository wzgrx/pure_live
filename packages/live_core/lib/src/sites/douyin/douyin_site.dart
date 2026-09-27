/// The Douyin adapter (spec/sites/douyin.md); see DouyuSite for the pattern.
library;

import 'dart:math';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/douyin/douyin_parse.dart';
import 'package:live_core/src/sites/douyin/douyin_sign.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'douyin';
const _live = 'https://live.douyin.com';

/// §6 the page that sets the anonymous `ttwid` and carries the categories.
final _homeUrl = Uri.https('live.douyin.com', '/', {'from_nav': '1'});

/// §1 short links: hosts a redirect may pass through, request and time caps.
const _shortLinkHops = {'v.douyin.com', 'www.douyin.com', 'webcast.amemv.com'};
const _shortLinkRequests = 8;
const _shortLinkBudget = Duration(seconds: 12);

/// `www.douyin.com` sections that are never rooms (REG-DOUYIN-010).
const _notRooms = {'video', 'note', 'search', 'user'};

/// How long a detail's stream description may serve the next [DouyinSite.streams].
const _handoffWindow = Duration(seconds: 30);

/// How long to go without a session after the home page set no ttwid before
/// fetching it again (the page is about 1 MB).
const _bootstrapRetry = Duration(minutes: 5);

final _digits = RegExp(r'^\d+$');
final _reflowPath = RegExp(r'(?:^|/)reflow/(\d+)(?:/|$)');

/// The Douyin adapter (spec/sites/douyin.md): parsing from [DouyinParse],
/// requests over [LiveHttp], a_bogus/msToken from [DouyinSigner].
///
/// The user's cookie is read from the [CookieVault] on every request; the
/// anonymous `ttwid` session is kept here and dropped as soon as the stored
/// cookie changes (REG-DOUYIN-017: nothing is process-wide).
final class DouyinSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [cookies] holds the user's cookie, if any; [now]
  /// and [random] (visitor id, msToken, a_bogus) are injectable for tests.
  factory(LiveHttp http, {CookieVault? cookies, DateTime Function()? now, Random? random}) {
    final source = random ?? Random.secure();
    final clock = now ?? DateTime.now;
    return DouyinSite._(
      http,
      cookies,
      clock,
      newVisitorId(source),
      DouyinSigner(userAgent: DouyinParse.userAgent, now: clock, random: source),
    );
  }

  new _(this.http, this._cookies, this._now, this.visitorId, this._signer);

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;
  final DouyinSigner _signer;

  /// §6 this adapter's anonymous visitor id (`user_unique_id`, 19 digits),
  /// kept for every room; the danmaku connection needs it (§7).
  final String visitorId;

  String? _vaultSeen;
  var _generation = 0;
  String? _anonymous;
  DateTime? _anonymousMissedAt;
  Future<String?>? _anonymousFetch;
  ({RoomRef ref, DouyinRoom room, DateTime issuedAt})? _handoff;

  @override
  String get id => _site;

  @override
  String get name => '抖音直播';

  /// §6 a visitor id like the web client's: `7`, a digit 3–9, 17 digits.
  static String newVisitorId(Random random) =>
      ['7', 3 + random.nextInt(7), for (var i = 0; i < 17; i++) random.nextInt(10)].join();

  // ---------------------------------------------------------------- session

  /// The stored cookie, normalised; null when signed out.
  String? _userCookie() {
    final raw = _cookies?.cookieFor(_site);
    if (raw == null) return null;
    final text = raw
        .replaceFirst(RegExp(r'^\s*cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Reads the vault; a changed value drops the anonymous session and makes
  /// an in-flight bootstrap's late result stale.
  String? _observeVault() {
    final user = _userCookie();
    if (user != _vaultSeen) {
      _vaultSeen = user;
      _anonymous = null;
      _anonymousMissedAt = null;
      _anonymousFetch = null;
      _generation++;
    }
    return user;
  }

  /// §8 the cookie for API requests and the danmaku handshake: the user's,
  /// else the anonymous `ttwid` session (fetched once, shared by concurrent
  /// callers). Null when the home page set no ttwid (retried after 5 min).
  Future<String?> sessionCookie() async {
    while (true) {
      final user = _observeVault();
      if (user != null) return user;
      final cached = _anonymous;
      if (cached != null) return cached;
      final missedAt = _anonymousMissedAt;
      if (missedAt != null && _now().difference(missedAt) < _bootstrapRetry) return null;
      final generation = _generation;
      final cookie = await (_anonymousFetch ??= _fetchAnonymous(generation));
      if (generation == _generation) return cookie;
    }
  }

  /// §6 `GET live.douyin.com/?from_nav=1`: keeps `ttwid` and `UIFID_TEMP`.
  /// The whole body is read before the cookie is used (REG-DOUYIN-016).
  Future<String?> _fetchAnonymous(int generation) async {
    try {
      final response = await _get(_homeUrl, _apiHeaders(null));
      _requireSuccess(response, 'home page');
      return _keepAnonymous(response, generation);
    } finally {
      if (generation == _generation) _anonymousFetch = null;
    }
  }

  /// Stores the session cookie of a home-page [response] requested in
  /// [generation], unless the vault changed meanwhile.
  String? _keepAnonymous(LiveResponse response, int generation) {
    _observeVault();
    final pairs = [
      for (final line in response.headers['set-cookie'] ?? const <String>[])
        if (line.split(';').first.trim() case final pair
            when pair.startsWith('ttwid=') || pair.startsWith('UIFID_TEMP='))
          pair,
    ];
    final current = generation == _generation && _vaultSeen == null;
    if (!pairs.any((pair) => pair.startsWith('ttwid=') && pair.length > 'ttwid='.length)) {
      if (current && _anonymous == null) _anonymousMissedAt = _now();
      return null;
    }
    final cookie = pairs.join('; ');
    if (current) {
      _anonymous ??= cookie;
      _anonymousMissedAt = null;
    }
    return cookie;
  }

  // --------------------------------------------------------------- requests

  /// §6 API headers (`authority` as legacy and the recordings sent it).
  static Map<String, String> _apiHeaders(String? cookie) => {
    'user-agent': DouyinParse.userAgent,
    'referer': _live,
    'authority': 'live.douyin.com',
    'cookie': ?cookie,
  };

  /// §3 search headers.
  static Map<String, String> _searchHeaders(String keyword, String? cookie) => {
    'user-agent': DouyinParse.userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'zh-CN,zh;q=0.9',
    'origin': 'https://www.douyin.com',
    'referer': 'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?source=switch_tab&type=live',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
    'cookie': ?cookie,
  };

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

  /// Response headers as the parser takes them.
  static Map<String, String> _headersOf(LiveResponse response) => {
    for (final entry in response.headers.entries) entry.key: entry.value.join(', '),
  };

  static void _requireSuccess(LiveResponse response, String what) {
    final status = response.status;
    if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what: HTTP $status');
    if (!response.isSuccess) throw ApiChanged(_site, '$what: HTTP $status');
  }

  // ---------------------------------------------------------------- catalog

  /// §2 categories from the home page, which also starts the anonymous
  /// session when there is none yet (one request instead of two).
  @override
  Future<List<Category>> categories() async {
    final user = _observeVault();
    final generation = _generation;
    final response = await _get(_homeUrl, _apiHeaders(user ?? _anonymous));
    if (user == null && response.isSuccess) _keepAnonymous(response, generation);
    return DouyinParse.categories(response.text, status: response.status, headers: _headersOf(response));
  }

  /// §2 partition rooms, 15 per page from `offset` (the cursor), signed. A
  /// risk-control answer (captcha, empty body) retries once on the unsigned
  /// `webcast.amemv.com` host, which serves the same list (spec §2).
  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final offset = int.tryParse(cursor?.value ?? '') ?? 0;
    final partition = DouyinParse.partitionParams(area.id);
    final cookie = await sessionCookie();
    final url = _signer.signedUrl(Uri.parse('$_live/webcast/web/partition/detail/room/v2/'), {
      'aid': '6383',
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
      'count': '15',
      'offset': '$offset',
      ...partition,
      'req_from': '2',
    });
    final response = await _get(url, _apiHeaders(cookie));
    try {
      return DouyinParse.partitionRooms(
        response.text,
        offset: offset,
        areaName: area.name,
        status: response.status,
        headers: _headersOf(response),
      );
    } on RiskControl catch (signedError) {
      final unsigned = await _get(
        Uri.https('webcast.amemv.com', '/webcast/web/partition/detail/room/v2/', {
          'aid': '6383',
          'app_name': 'douyin_web',
          'live_id': '1',
          'device_platform': 'web',
          'language': 'zh-CN',
          'browser_language': 'zh-CN',
          'browser_platform': 'Win32',
          'browser_name': 'Chrome',
          'browser_version': '120.0.0.0',
          ...partition,
          'count': '30',
          'offset': '$offset',
          'cookie_enabled': 'true',
          'screen_width': '1920',
          'screen_height': '1080',
        }),
        _apiHeaders(cookie),
      );
      try {
        return DouyinParse.partitionRooms(
          unsigned.text,
          offset: offset,
          areaName: area.name,
          status: unsigned.status,
          headers: _headersOf(unsigned),
        );
      } on SiteError {
        throw signedError;
      }
    }
  }

  /// §2 `webcast/feed/`: one page, no cursor.
  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final cookie = await sessionCookie();
    final response = await _get(
      Uri.https('live.douyin.com', '/webcast/feed/', {
        'aid': '6383',
        'app_name': 'douyin_web',
        'need_map': '1',
        'is_draw': '1',
        'inner_from_drawer': '0',
        'enter_source': 'web_homepage_hot_web_live_card',
        'source_key': 'web_homepage_hot_web_live_card',
      }),
      _apiHeaders(cookie),
    );
    return DouyinParse.feed(response.text, status: response.status, headers: _headersOf(response));
  }

  // ----------------------------------------------------------------- search

  /// §3 live-room search (unsigned), 30 per page from `offset`. Douyin
  /// refuses it without a signed-in cookie: NeedsLogin. Partitions whose name
  /// matches are a separate thing: [searchAreas].
  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final offset = int.tryParse(cursor?.value ?? '') ?? 0;
    final cookie = await sessionCookie();
    final response = await _get(
      Uri.https('www.douyin.com', '/aweme/v1/web/live/search/', {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'search_channel': 'aweme_live',
        'search_source': 'switch_tab',
        'query_correct_type': '1',
        'need_filter_settings': '1',
        'list_type': 'single',
        'keyword': text,
        'offset': '$offset',
        'count': '30',
        'os_version': '10',
      }),
      _searchHeaders(text, cookie),
    );
    return DouyinParse.searchPage(
      response.text,
      offset: offset,
      status: response.status,
      headers: _headersOf(response),
    );
  }

  /// §3 partitions whose name matches [keyword] (anonymous); browse one with
  /// [areaRooms]. These are not keyword results and must not be shown as such.
  Future<List<Area>> searchAreas(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final cookie = await sessionCookie();
    final response = await _get(
      Uri.https('live.douyin.com', '/webcast/web/partition/search/', {'keyword': text, 'aid': '6383'}),
      _searchHeaders(text, cookie),
    );
    return DouyinParse.partitionSearch(response.text, status: response.status, headers: _headersOf(response));
  }

  /// §8 the signed-in account's nickname (`webcast/user/me/`). NeedsLogin
  /// when no cookie is stored (no request) or the cookie is not signed in.
  /// A result for a cookie that changed meanwhile is discarded and re-read.
  Future<String> accountName() async {
    final user = _observeVault();
    if (user == null) throw const NeedsLogin(_site, 'no stored cookie');
    final response = await _get(Uri.https('live.douyin.com', '/webcast/user/me/', {'aid': '6383'}), {
      'user-agent': DouyinParse.userAgent,
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'cookie': user,
    });
    if (_observeVault() != user) return await accountName();
    return DouyinParse.accountName(response.text, status: response.status, headers: _headersOf(response));
  }

  // ------------------------------------------------------------------ rooms

  /// §4 detail: a room_id (over 16 digits) goes through reflow, and through
  /// enter with the owner's web_rid when that broadcast has ended; a web_rid
  /// goes to enter, then to the room page when enter is refused (risk
  /// control) or malformed. NotFound and network errors do not fall back.
  /// The detail is always identified by the web_rid; its [RoomDetail.danmakuKeys]
  /// carry `webRid`, `roomId` (this broadcast) and `userUniqueId`.
  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final fetched = await _room(ref);
    _handoff = (ref: fetched.room.detail.ref, room: fetched.room, issuedAt: fetched.issuedAt);
    return fetched.room.detail;
  }

  Future<({DouyinRoom room, DateTime issuedAt})> _room(RoomRef ref) async {
    if (ref.platform != _site) throw ArgumentError.value(ref, 'ref', 'not a Douyin room');
    final id = ref.roomId;
    if (!DouyinParse.isRoomId(id)) return await _byWebRid(id);
    final reflowed = await _reflow(id);
    if (!reflowed.room.sessionEnded) return reflowed;
    return await _byWebRid(reflowed.room.detail.ref.roomId);
  }

  Future<({DouyinRoom room, DateTime issuedAt})> _byWebRid(String webRid) async {
    try {
      return await _enter(webRid);
    } on SiteError catch (enterError) {
      if (enterError is! RiskControl && enterError is! ApiChanged) rethrow;
      try {
        return await _roomPage(webRid);
      } on ApiChanged {
        // A page without the room state (a challenge page) says less than
        // enter's own refusal.
        throw enterError;
      }
    }
  }

  /// §4 `room/web/enter/`, signed.
  Future<({DouyinRoom room, DateTime issuedAt})> _enter(String webRid) async {
    final cookie = await sessionCookie();
    final url = _signer.signedUrl(Uri.parse('$_live/webcast/room/web/enter/'), {
      'app_name': 'douyin_web',
      'enter_from': 'web_live',
      'live_id': '1',
      'web_rid': webRid,
      'is_need_double_stream': 'false',
    });
    final response = await _get(url, _apiHeaders(cookie));
    final room = DouyinParse.enter(
      response.text,
      webRid: webRid,
      status: response.status,
      headers: _headersOf(response),
    );
    return (room: _withVisitor(room), issuedAt: _now());
  }

  /// §4 fallback: the room page, with the session cookie (the recorded page
  /// needed nothing more; legacy's HEAD for `__ac_nonce` is not sent).
  Future<({DouyinRoom room, DateTime issuedAt})> _roomPage(String webRid) async {
    final cookie = await sessionCookie();
    final response = await _get(Uri.https('live.douyin.com', '/$webRid'), _apiHeaders(cookie));
    final room = DouyinParse.roomPage(
      response.text,
      webRid: webRid,
      status: response.status,
      headers: _headersOf(response),
    );
    return (room: _withVisitor(room), issuedAt: _now());
  }

  /// §1 rule 2 `room/reflow/info/` for a room_id.
  Future<({DouyinRoom room, DateTime issuedAt})> _reflow(String roomId) async {
    final cookie = await sessionCookie();
    final response = await _get(
      Uri.https('webcast.amemv.com', '/webcast/room/reflow/info/', {
        'type_id': '0',
        'live_id': '1',
        'room_id': roomId,
        'sec_user_id': '',
        'version_code': '99.99.99',
        'app_id': '6383',
      }),
      _apiHeaders(cookie),
    );
    final room = DouyinParse.reflow(response.text, status: response.status, headers: _headersOf(response));
    return (room: _withVisitor(room), issuedAt: _now());
  }

  /// Adds this adapter's [visitorId] unless the room page supplied one.
  DouyinRoom _withVisitor(DouyinRoom room) {
    final detail = room.detail;
    if (detail.danmakuKeys.containsKey('userUniqueId')) return room;
    return DouyinRoom(
      detail: RoomDetail(
        card: detail.card,
        link: detail.link,
        avatar: detail.avatar,
        introduction: detail.introduction,
        notice: detail.notice,
        danmakuKeys: {...detail.danmakuKeys, 'userUniqueId': visitorId},
      ),
      streamUrl: room.streamUrl,
      sessionEnded: room.sessionEnded,
    );
  }

  // ---------------------------------------------------------------- streams

  /// §6 streams come with the detail: the stream description of a [detail]
  /// call made for the same room in the last 30 s is used once, otherwise
  /// (and always on a retry) the detail is fetched again. Lines carry UA,
  /// origin and referer but no cookie; the lease never cuts the connection.
  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final handoff = _handoff;
    _handoff = null;
    final fetched = handoff != null && handoff.ref == room.ref && _now().difference(handoff.issuedAt) < _handoffWindow
        ? (room: handoff.room, issuedAt: handoff.issuedAt)
        : await _room(room.ref);
    final douyin = fetched.room;
    if (douyin.detail.state != LiveState.live) {
      throw StreamUnavailable(_site, 'room ${douyin.detail.ref.roomId} is not live');
    }
    return DouyinParse.streams(
      douyin.streamUrl,
      issuedAt: fetched.issuedAt,
      webRid: douyin.detail.ref.roomId,
      quality: quality?.id,
    );
  }

  // ------------------------------------------------------------------ links

  /// §1 a web_rid, a room_id (normalised through reflow), or the first
  /// Douyin link in share text: `live.douyin.com/<web_rid>`,
  /// `www.douyin.com/<web_rid>`, `/root/live/<id>`, `/follow/live/<id>`,
  /// `webcast.amemv.com/…/reflow/<room_id>` and `v.douyin.com` short links
  /// (followed hop by hop). Videos, search pages and the bare site are not
  /// rooms (null).
  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (_digits.hasMatch(text)) return await _normalise(text);
    final url = _firstLink(text);
    return url == null ? null : await _resolveUrl(url);
  }

  static Uri? _firstLink(String text) {
    const stop = '\\s<>"\'，。！？、；：）》」』”’';
    final candidates = [
      for (final match in RegExp('https?://[^$stop]+', caseSensitive: false).allMatches(text)) match.group(0)!,
      for (final match in RegExp(
        '(?:^|[^A-Za-z0-9.@/-])((?:live|v|www)\\.douyin\\.com/[^$stop]*)',
        caseSensitive: false,
      ).allMatches(text))
        'https://${match.group(1)!}',
    ];
    for (final candidate in candidates) {
      final url = Uri.tryParse(candidate.replaceFirst(RegExp(r'''[.,!?;:)\]}]+$'''), ''));
      if (url == null || url.userInfo.isNotEmpty) continue;
      final host = url.host.toLowerCase();
      if (host == 'douyin.com' || host.endsWith('.douyin.com') || host == 'webcast.amemv.com') return url;
    }
    return null;
  }

  Future<RoomRef?> _resolveUrl(Uri url) async {
    final host = url.host.toLowerCase();
    final segments = _segmentsOf(url);
    if (segments == null) return null;
    switch (host) {
      case 'live.douyin.com':
        final first = segments.firstOrNull;
        return first != null && _digits.hasMatch(first) ? await _normalise(first) : null;
      case 'www.douyin.com' || 'douyin.com':
        final id = _webRoomId(segments);
        return id == null ? null : await _normalise(id);
      case 'webcast.amemv.com':
        final roomId = _reflowPath.firstMatch(url.path)?.group(1);
        return roomId == null ? null : await _webRidOf(roomId);
      case 'v.douyin.com':
        return await _followShortLink(url);
    }
    return null;
  }

  /// `www.douyin.com/<id>` (one segment of 1–20 digits, REG-DOUYIN-010/011),
  /// `/root/live/<id>` or `/follow/live/<id>`.
  static String? _webRoomId(List<String> segments) {
    if (segments.length == 1 && RegExp(r'^\d{1,20}$').hasMatch(segments.single)) return segments.single;
    if (segments.length == 3 &&
        (segments[0] == 'root' || segments[0] == 'follow') &&
        segments[1] == 'live' &&
        _digits.hasMatch(segments[2])) {
      return segments[2];
    }
    return null;
  }

  /// §1 rule 1: up to 16 digits is a web_rid, longer a room_id.
  Future<RoomRef> _normalise(String id) async => DouyinParse.isRoomId(id) ? await _webRidOf(id) : RoomRef(_site, id);

  Future<RoomRef> _webRidOf(String roomId) async => (await _reflow(roomId)).room.detail.ref;

  /// §1 `v.douyin.com`: one hop at a time (no automatic redirects), only
  /// through Douyin hosts, at most 8 requests in 12 s, no loops, no
  /// userinfo or non-http(s) targets; ends at a room link or null. A 404 is
  /// NotFound.
  Future<RoomRef?> _followShortLink(Uri start) async {
    final clock = Stopwatch()..start();
    final seen = <Uri>{start.removeFragment()};
    var current = start;
    for (var requests = 0; requests < _shortLinkRequests; requests++) {
      final left = _shortLinkBudget - clock.elapsed;
      if (left <= Duration.zero) throw const NetworkFailure(_site, 'short link: 12 s budget spent');
      final response = await _send(
        LiveRequest(
          site: _site,
          url: current,
          headers: const {'user-agent': DouyinParse.userAgent, 'accept': '*/*', 'origin': _live, 'referer': '$_live/'},
          followRedirects: false,
          timeout: left,
        ),
      );
      final status = response.status;
      if (status == 404) throw NotFound(_site, 'short link ${start.path} does not exist');
      if (status >= 500) throw NetworkFailure(_site, 'short link: HTTP $status');
      final locations = {...?response.headers['location']};
      if (status < 300 || status >= 400 || locations.length != 1) return null;
      final target = _redirectTarget(current, locations.single);
      if (target == null || !seen.add(target.removeFragment())) return null;
      final host = target.host.toLowerCase();
      final segments = _segmentsOf(target);
      if (segments == null) return null;
      final isRoom =
          host == 'live.douyin.com' ||
          (host == 'webcast.amemv.com' && _reflowPath.hasMatch(target.path)) ||
          (host == 'www.douyin.com' && _webRoomId(segments) != null);
      if (isRoom) return await _resolveUrl(target);
      if (!_shortLinkHops.contains(host)) return null;
      if (host == 'www.douyin.com' && (segments.isEmpty || _notRooms.contains(segments.first))) return null;
      current = target;
    }
    return null;
  }

  /// The non-empty path segments, or null when they do not decode.
  static List<String>? _segmentsOf(Uri url) {
    try {
      return [
        for (final segment in url.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
    } on FormatException {
      return null;
    }
  }

  static Uri? _redirectTarget(Uri from, String location) {
    final parsed = Uri.tryParse(location.trim());
    if (parsed == null || location.trim().isEmpty) return null;
    final target = from.resolveUri(parsed);
    final scheme = target.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || target.host.isEmpty || target.userInfo.isNotEmpty) return null;
    return target;
  }
}
