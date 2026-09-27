import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/bilibili/bilibili_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

const _site = 'bilibili';
const _liveApi = 'api.live.bilibili.com';
const _api = 'api.bilibili.com';

/// How long WBI keys and the `w_webid` access id are reused (§6.4).
const _sessionLifetime = Duration(hours: 6);

/// Pause before the one retry of a signed request after -352 (§4.1), and
/// between the two ranked recommendation attempts (§2.3).
const _retryDelay = Duration(milliseconds: 180);

/// §1.2 b23.tv budget: redirects answered, requests per resolution, time.
const _redirectStatuses = {301, 302, 303, 307, 308};
const _maxShortLinkRequests = 8;
const _shortLinkBudget = Duration(seconds: 12);

final _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// What the danmaku connector needs to join one room (spec §7.1, §7.2).
@immutable
final class BilibiliDanmakuInfo {
  /// Creates the info.
  const new({
    required this.roomId,
    required this.uid,
    required this.token,
    required this.servers,
    required this.buvid,
    required this.headers,
  });

  /// Long room id: the auth packet's `roomid`.
  final int roomId;

  /// §8.2 the auth packet's `uid`: 0 for a guest.
  final int uid;

  /// The auth packet's `key`.
  final String token;

  /// WebSocket endpoints in the order to try: the general gateway, then
  /// `host_list`.
  final List<Uri> servers;

  /// The auth packet's `buvid`: buvid3 of [headers]' cookie, '' when none.
  final String buvid;

  /// WebSocket request headers: UA, Origin, Referer (long id) and the cookie
  /// the token was issued to.
  final Map<String, String> headers;
}

/// The Bilibili adapter (spec/sites/bilibili.md): parsing from
/// [BilibiliParse] and [BilibiliSession], requests over [LiveHttp], an
/// anonymous session (guest buvid, WBI keys, `w_webid`) kept per login cookie.
final class BilibiliSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [_cookies] holds the user's login cookie, if any;
  /// its change notifications drop the anonymous session unless it already
  /// belongs to the new cookie (call [dispose] to stop listening). [hevc]
  /// also asks for HEVC lines (`codec=0,1`; the spec asks for AVC only,
  /// §6.1). [now] and [sleep] are injectable for tests.
  new(this.http, {this._cookies, this.hevc = false, DateTime Function()? now, Future<void> Function(Duration)? sleep})
    : _now = now ?? DateTime.now,
      _sleep = sleep ?? Future<void>.delayed {
    _subscription = _cookies?.changes.listen((site) {
      if (site == _site && _session?.login != _login()) _session = null;
    });
  }

  /// Transport.
  final LiveHttp http;

  /// Whether stream requests also ask for HEVC; one set never mixes codecs.
  final bool hevc;

  final CookieVault? _cookies;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  StreamSubscription<String>? _subscription;
  _Session? _session;

  /// Room ids seen by [detail] → canonical long id (ADR 0010 revision: the
  /// adapter keeps short ids out of `RoomDetail` and remembers them itself).
  final Map<String, String> _canonicalIds = {};

  @override
  String get id => _site;

  @override
  String get name => '哔哩哔哩';

  /// Stops following the cookie vault.
  Future<void> dispose() async {
    await _subscription?.cancel();
  }

  /// §6.4 the signed query for [params]: `wts` added, sorted, filtered and
  /// percent-encoded by [BilibiliSession.wbiQuery], then `&w_rid=` + md5 of
  /// that query and the mixin key.
  static String wbiSign(
    Map<String, String> params, {
    required String imgKey,
    required String subKey,
    required int wts,
  }) {
    final query = BilibiliSession.wbiQuery(params, wts: wts);
    final rid = md5.convert(utf8.encode('$query${BilibiliSession.mixinKey(imgKey, subKey)}'));
    return '$query&w_rid=$rid';
  }

  // Session -----------------------------------------------------------------

  /// The user's cookie, control characters removed (§8.2).
  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  /// The session for the current login cookie. The change notification is
  /// asynchronous, so a cookie that changed before it arrives also starts a
  /// new session.
  _Session _current() {
    final login = _login();
    final session = _session;
    if (session != null && session.login == login) return session;
    return _session = _Session(login);
  }

  /// §8.1 the buvid pair: the login cookie's own `buvid3`, else the guest
  /// pair from finger/spi, requested once for concurrent callers. A failed
  /// request gives none; the next request asks again.
  Future<({String buvid3, String buvid4})?> _buvid(_Session session) {
    final own = _cookieField(session.login, 'buvid3');
    if (own != null) return Future.value((buvid3: own, buvid4: _cookieField(session.login, 'buvid4') ?? ''));
    final guest = session.guest;
    if (guest != null) return Future.value(guest);
    return session.guestFetch ??= _fetchGuest(session);
  }

  Future<({String buvid3, String buvid4})?> _fetchGuest(_Session session) async {
    try {
      final response = await _send(
        LiveRequest(site: _site, url: Uri.https(_api, '/x/frontend/finger/spi'), headers: _apiHeaders(session.login)),
      );
      return session.guest = BilibiliSession.buvid(response.text, status: response.status);
    } on SiteError {
      return null;
    } finally {
      session.guestFetch = null;
    }
  }

  /// §6.3 the cookie of API and media requests.
  Future<String> _cookie(_Session session) async {
    final pair = await _buvid(session);
    if (pair == null) return session.login;
    return BilibiliSession.cookie(buvid3: pair.buvid3, buvid4: pair.buvid4, loginCookie: session.login);
  }

  /// §6.4 WBI keys from nav, reused for 6 hours; [renew] fetches new ones.
  /// Concurrent callers share one request.
  Future<({String imgKey, String subKey})> _keys(_Session session, {bool renew = false}) {
    final cached = session.keys;
    if (!renew && cached != null && _now().difference(cached.at) < _sessionLifetime) {
      return Future.value((imgKey: cached.imgKey, subKey: cached.subKey));
    }
    return session.keysFetch ??= () async {
      try {
        final response = await _get(Uri.https(_api, '/x/web-interface/nav'), await _cookie(session));
        final keys = BilibiliSession.wbiKeys(response.text, status: response.status);
        session.keys = (imgKey: keys.imgKey, subKey: keys.subKey, at: _now());
        return keys;
      } finally {
        session.keysFetch = null;
      }
    }();
  }

  /// §2.2 `w_webid` from the /lol page, kept as long as the WBI keys and
  /// renewed with them.
  Future<String> _accessId(_Session session, {bool renew = false}) {
    final cached = session.accessId;
    if (!renew && cached != null && _now().difference(cached.at) < _sessionLifetime) return Future.value(cached.id);
    return session.accessIdFetch ??= () async {
      try {
        final response = await _get(Uri.https('live.bilibili.com', '/lol'), await _cookie(session));
        if (response.status == 412) throw const RateLimited(_site, detail: 'lol: HTTP 412');
        if (response.status >= 500) throw NetworkFailure(_site, 'lol: HTTP ${response.status}');
        final id = BilibiliSession.accessId(response.text);
        session.accessId = (id: id, at: _now());
        return id;
      } finally {
        session.accessIdFetch = null;
      }
    }();
  }

  // Requests ----------------------------------------------------------------

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, String cookie) =>
      _send(LiveRequest(site: _site, url: url, headers: _apiHeaders(cookie)));

  /// An unsigned API request with the session cookie.
  Future<LiveResponse> _unsigned(Uri url) async => await _get(url, await _cookie(_current()));

  /// A WBI-signed GET of `api.live.bilibili.com` [path] (§6.4). A -352 answer
  /// renews the WBI keys, the guest buvid and the access id and retries once
  /// after 180 ms; a second -352 is RiskControl (§9). Other failures,
  /// RateLimited included, are not retried. Returns the parsed value with the
  /// session and the cookie the request carried.
  Future<({T value, _Session session, String cookie})> _signed<T>(
    String path,
    Map<String, String> params,
    T Function(LiveResponse response) parse, {
    bool webId = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final renew = attempt > 0;
      final session = _current();
      if (renew) session.guest = null;
      final keys = await _keys(session, renew: renew);
      final cookie = await _cookie(session);
      final query = wbiSign(
        {...params, if (webId) 'w_webid': await _accessId(session, renew: renew)},
        imgKey: keys.imgKey,
        subKey: keys.subKey,
        wts: _now().millisecondsSinceEpoch ~/ 1000,
      );
      final response = await _get(Uri.parse('https://$_liveApi$path?$query'), cookie);
      try {
        return (value: parse(response), session: session, cookie: cookie);
      } on RiskControl {
        if (renew) rethrow;
      }
      await _sleep(_retryDelay);
    }
  }

  static Map<String, String> _apiHeaders(String cookie) => cookie.isEmpty
      ? {'user-agent': BilibiliParse.userAgent, 'referer': 'https://live.bilibili.com/'}
      : BilibiliSession.apiHeaders(cookie);

  static String? _cookieField(String cookie, String name) {
    final value = RegExp('(?:^|;)\\s*$name=([^;]*)').firstMatch(cookie)?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int _page(PageCursor? cursor) {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    return page < 1 ? 1 : page;
  }

  // Catalog and search ------------------------------------------------------

  @override
  Future<List<Category>> categories() async {
    final response = await _unsigned(
      Uri.https(_liveApi, '/room/v1/Area/getList', {'need_entrance': '1', 'parent_id': '0'}),
    );
    return BilibiliParse.categories(response.text, status: response.status);
  }

  /// §2.2 signed, with `w_webid`. Guests get -352 on every page today
  /// (DIAGNOSIS), which surfaces as RiskControl after the one renewal.
  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final page = _page(cursor);
    final result = await _signed(
      '/xlive/web-interface/v1/second/getList',
      {
        'platform': 'web',
        'parent_area_id': area.categoryId,
        'area_id': area.id,
        'sort_type': 'online',
        'page': '$page',
      },
      (response) => BilibiliParse.areaRoomsPage(response.text, page: page, status: response.status),
      webId: true,
    );
    return result.value;
  }

  /// §2.3 the ranked list, tried twice 180 ms apart, then the recommendation
  /// feed as a fallback. RateLimited is never retried; when the fallback
  /// fails too, the ranked list's error is reported.
  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = _page(cursor);
    late SiteError ranked;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await _sleep(_retryDelay);
      try {
        final response = await _unsigned(
          Uri.https(_liveApi, '/room/v1/Area/getListByAreaID', {
            'areaId': '0',
            'parent_area_id': '0',
            'sort': 'online',
            'pageSize': '30',
            'page': '$page',
          }),
        );
        return BilibiliParse.recommendPage(response.text, page: page, status: response.status);
      } on RateLimited {
        rethrow;
      } on SiteError catch (error) {
        ranked = error;
      }
    }
    try {
      final response = await _unsigned(
        Uri.https(_liveApi, '/xlive/web-interface/v1/webMain/getMoreRecList', {'platform': 'web', 'page': '$page'}),
      );
      return BilibiliParse.recommendPage(response.text, page: page, status: response.status);
    } on RateLimited {
      rethrow;
    } on SiteError {
      throw ranked;
    }
  }

  /// §3 live search, 20 per page (REG-BILIBILI-024). A blank keyword is an
  /// empty last page without a request.
  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = _page(cursor);
    final response = await _unsigned(
      Uri.https(_api, '/x/web-interface/search/type', {
        'context': '',
        'search_type': 'live',
        'cover_type': 'user_cover',
        'order': '',
        'keyword': text,
        'category_id': '',
        '__refresh__': '',
        '_extra': '',
        'highlight': '0',
        'single_column': '0',
        'page': '$page',
        'page_size': '20',
      }),
    );
    return BilibiliParse.searchPage(response.text, page: page, status: response.status);
  }

  // Rooms and streams -------------------------------------------------------

  /// §4 signed `getInfoByRoom`. Short ids are accepted; the detail's ref is
  /// always the canonical long id, and the mapping is remembered for
  /// [resolve].
  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final roomId = ref.roomId;
    if (!RegExp(r'^\d+$').hasMatch(roomId)) throw NotFound(_site, 'room id $roomId is not a number');
    final result = await _signed('/xlive/web-room/v1/index/getInfoByRoom', {
      'room_id': roomId,
    }, (response) => BilibiliParse.detail(response.text, status: response.status));
    final canonical = result.value.ref.roomId;
    _remember(roomId, canonical);
    _remember(canonical, canonical);
    return result.value;
  }

  void _remember(String input, String canonical) {
    _canonicalIds.remove(input);
    _canonicalIds[input] = canonical;
    if (_canonicalIds.length > 512) _canonicalIds.remove(_canonicalIds.keys.first);
  }

  /// §5, §6: qualities and lines for the long room id. With [quality] one
  /// request at its qn. Without, a `qn=0` request lists the qualities; when
  /// the server's default is already the best offered it is used as is,
  /// otherwise the best is requested. A guest asking for 10000 is served 250:
  /// the lines say so in `confirmed` (REG-BILIBILI-001).
  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final roomId = room.ref.roomId;
    if (quality != null) return await _playSet(roomId, quality);
    final probe = await _play(roomId, '0');
    final offered = BilibiliParse.qualities(probe.data);
    final best = offered.firstOrNull;
    final set = BilibiliParse.streams(
      probe.data,
      roomId: roomId,
      issuedAt: probe.issuedAt,
      requested: best,
      cookie: probe.cookie,
    );
    if (best == null || set.lines.first.confirmed == best) return set;
    return await _playSet(roomId, best);
  }

  Future<StreamSet> _playSet(String roomId, Quality quality) async {
    final play = await _play(roomId, quality.id);
    return BilibiliParse.streams(
      play.data,
      roomId: roomId,
      issuedAt: play.issuedAt,
      requested: quality,
      cookie: play.cookie,
    );
  }

  /// §6.1 one unsigned `getRoomPlayInfo` at [qn].
  Future<({Map<String, dynamic> data, DateTime issuedAt, String cookie})> _play(String roomId, String qn) async {
    final cookie = await _cookie(_current());
    final response = await _get(
      Uri.https(_liveApi, '/xlive/web-room/v2/index/getRoomPlayInfo', {
        'room_id': roomId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': hevc ? '0,1' : '0',
        'qn': qn,
        'platform': 'web',
        'ptype': '8',
        'dolby': '5',
        'panorama': '1',
        'mask': '0',
        'no_playurl': '0',
      }),
      cookie,
    );
    final issuedAt = _now();
    return (data: BilibiliParse.playData(response.text, status: response.status), issuedAt: issuedAt, cookie: cookie);
  }

  /// §7.1 signed `getDanmuInfo` for [room]'s long id, with the uid (§8.2),
  /// buvid and WebSocket headers (§7.2) of the same cookie. One request, plus
  /// the -352 renewal; the connector's own retry schedule (§7.1, §7.2) and
  /// the one-attempt rule on room entry are live_danmaku's.
  Future<BilibiliDanmakuInfo> danmakuInfo(RoomDetail room) async {
    final roomId = room.danmakuKeys['roomId'] ?? room.ref.roomId;
    final numeric = int.tryParse(roomId);
    if (numeric == null || numeric <= 0) throw NotFound(_site, 'room id $roomId is not a number');
    final result = await _signed('/xlive/web-room/v1/index/getDanmuInfo', {
      'id': roomId,
      'type': '0',
    }, (response) => BilibiliSession.danmakuInfo(response.text, status: response.status));
    final session = result.session;
    return BilibiliDanmakuInfo(
      roomId: numeric,
      uid: BilibiliSession.danmakuUid(cookie: session.login, storedUid: session.verifiedUid),
      token: result.value.token,
      servers: result.value.servers,
      buvid: _cookieField(result.cookie, 'buvid3') ?? '',
      headers: BilibiliParse.mediaHeaders(roomId, cookie: result.cookie),
    );
  }

  // Account -----------------------------------------------------------------

  /// §8.3 a new login QR code: the key to poll with and the URL to encode.
  Future<({String key, Uri url})> qrCode() async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/generate'),
        headers: const {'user-agent': BilibiliParse.userAgent},
      ),
    );
    return BilibiliSession.qrCode(response.text, status: response.status);
  }

  /// §8.3 one poll of [key]. When confirmed, `cookie` is the `name=value`
  /// pairs of every `Set-Cookie`, for the caller to verify with [account]
  /// and store; pacing and back-off are the caller's.
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/poll', {'qrcode_key': key}),
        headers: const {'user-agent': BilibiliParse.userAgent},
      ),
    );
    final state = BilibiliSession.qrPoll(response.text, status: response.status);
    if (state != BilibiliQrState.confirmed) return (state: state, cookie: null);
    final cookie = [
      for (final header in response.headers['set-cookie'] ?? const <String>[])
        if (header.split(';').first.replaceAll(_controlCharacters, '').trim() case final pair when pair.contains('='))
          pair,
    ].join('; ');
    if (cookie.isEmpty) throw const ApiChanged(_site, 'qrcode/poll: confirmed without Set-Cookie');
    return (state: state, cookie: cookie);
  }

  /// §8.2 checks [cookie] (default: the vault's) with `x/member/web/account`,
  /// sending only the cookie. -101 is NeedsLogin: the caller clears a stored
  /// cookie as expired. A verified vault cookie's uid is the danmaku uid
  /// when the cookie has no `DedeUserID`.
  Future<({int uid, String name})> account({String? cookie}) async {
    final session = _current();
    final value = (cookie ?? session.login).replaceAll(_controlCharacters, '').trim();
    if (value.isEmpty) throw const NeedsLogin(_site, 'no cookie');
    final response = await _send(
      LiveRequest(site: _site, url: Uri.https(_api, '/x/member/web/account'), headers: {'cookie': value}),
    );
    final account = BilibiliSession.account(response.text, status: response.status);
    if (value == session.login) session.verifiedUid = account.uid;
    return account;
  }

  // Links -------------------------------------------------------------------

  /// §1.2 a room number, a room link or a b23.tv short link (the redirect
  /// is followed without fetching the final page), alone or in share text.
  /// The result is the canonical long id: an id [detail] has not seen is
  /// looked up once, so a room that does not exist is NotFound.
  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    var id = _roomNumber(text);
    if (id == null) {
      for (final url in _links(text)) {
        final target = _isShortLinkHost(url.host) ? await _followShortLink(url) : url;
        id = target == null ? null : _roomIdOf(target);
        if (id != null) break;
      }
    }
    if (id == null) return null;
    final known = _canonicalIds[id];
    if (known != null) return RoomRef(_site, known);
    return (await detail(RoomRef(_site, id))).ref;
  }

  /// A positive decimal room number without leading zeros, or null.
  static String? _roomNumber(String text) {
    if (!RegExp(r'^\d{1,18}$').hasMatch(text)) return null;
    final value = int.parse(text);
    return value > 0 ? '$value' : null;
  }

  /// http(s) links in share text, in order; trailing punctuation dropped,
  /// user info, other schemes and undecodable paths rejected.
  static Iterable<Uri> _links(String text) sync* {
    for (final match in RegExp(
      r'(?:https?://|www\.)[\x21\x23-\x3B\x3D\x3F-\x7E]+',
      caseSensitive: false,
    ).allMatches(text)) {
      var raw = match.group(0)!.replaceFirst(RegExp(r'''[.,!?;:)\]}'"]+$'''), '');
      if (raw.toLowerCase().startsWith('www.')) raw = 'https://$raw';
      final url = Uri.tryParse(raw);
      if (url == null || !_isWebUrl(url)) continue;
      try {
        url.pathSegments;
      } on FormatException {
        continue;
      }
      yield url;
    }
  }

  static bool _isWebUrl(Uri url) =>
      (url.isScheme('http') || url.isScheme('https')) && url.host.isNotEmpty && url.userInfo.isEmpty;

  static bool _isShortLinkHost(String host) {
    final name = host.toLowerCase();
    return name == 'b23.tv' || name.endsWith('.b23.tv');
  }

  /// §1.2 the room of a live.bilibili.com page (`/{id}`, `/h5/{id}`,
  /// `/blanc/{id}`) or the legacy `www.bilibili.com/{id}` alias. Other
  /// bilibili.com hosts are not rooms (`space.bilibili.com/{uid}`).
  static String? _roomIdOf(Uri url) {
    final List<String> segments;
    try {
      segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    } on FormatException {
      return null;
    }
    if (segments.isEmpty) return null;
    final host = url.host.toLowerCase();
    if (host == 'live.bilibili.com') {
      if (segments.length >= 2 && (segments.first == 'h5' || segments.first == 'blanc')) {
        return _roomNumber(segments[1]);
      }
      return _roomNumber(segments.first);
    }
    if ((host == 'www.bilibili.com' || host == 'bilibili.com') && segments.length == 1) {
      return _roomNumber(segments.single);
    }
    return null;
  }

  /// §1.2 follows a b23.tv link hop by hop (no automatic redirects) until it
  /// leaves the short-link host, without requesting that target. Only 301,
  /// 302, 303, 307 and 308 with exactly one Location count; a loop, more than
  /// 8 requests or anything else is no room (null).
  Future<Uri?> _followShortLink(Uri start) async {
    final deadline = _now().add(_shortLinkBudget);
    final visited = <String>{};
    var current = start.removeFragment();
    while (visited.length < _maxShortLinkRequests && visited.add(current.toString())) {
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) throw const NetworkFailure(_site, 'b23.tv: redirect budget exhausted');
      final response = await _send(
        LiveRequest(
          site: _site,
          url: current,
          headers: const {'user-agent': BilibiliParse.userAgent},
          followRedirects: false,
          timeout: remaining < const Duration(seconds: 1) ? const Duration(seconds: 1) : remaining,
        ),
      );
      final locations = response.headers['location'] ?? const <String>[];
      if (!_redirectStatuses.contains(response.status) || locations.length != 1) return null;
      final Uri target;
      try {
        target = current.resolve(locations.single.trim());
      } on FormatException {
        return null;
      }
      if (!_isWebUrl(target)) return null;
      if (!_isShortLinkHost(target.host)) return target;
      current = target.removeFragment();
    }
    return null;
  }
}

/// The anonymous session state built for one login cookie (ADR 0011 rule 4):
/// guest buvid pair, WBI keys, access id and the verified uid. A cookie
/// change replaces the whole object, so a fetch that finishes afterwards
/// lands in a discarded session.
final class _Session {
  new(this.login);

  /// The user's cookie this session belongs to ('' when signed out).
  final String login;

  ({String buvid3, String buvid4})? guest;
  Future<({String buvid3, String buvid4})?>? guestFetch;

  ({String imgKey, String subKey, DateTime at})? keys;
  Future<({String imgKey, String subKey})>? keysFetch;

  ({String id, DateTime at})? accessId;
  Future<String>? accessIdFetch;

  /// uid that `account()` verified for [login]; 0 when none.
  int verifiedUid = 0;
}
