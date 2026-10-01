import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_message.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/bilibili/bilibili_api.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

const _site = 'bilibili';
const _liveApi = 'api.live.bilibili.com';
const _api = 'api.bilibili.com';

/// How long WBI keys and the `w_webid` access id are reused.
const _sessionLifetime = Duration(hours: 6);

/// Pause before the one retry of a signed request after -352, and between
/// the two ranked recommendation attempts.
const _retryDelay = Duration(milliseconds: 180);

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// The long room id a room's stream and danmaku requests use (a room asked
/// for by its short id keeps that id as its identity).
@immutable
final class BilibiliRoomData {
  /// Creates the data.
  const new(this.longId);

  /// Canonical long room id.
  final String longId;
}

/// The Bilibili adapter (3.x's `BiliBiliSite`; parsing in [BilibiliApi]).
///
/// An anonymous session (guest buvid, WBI keys, `w_webid`) is kept per login
/// cookie and shared by concurrent callers: a cold start asks for each once.
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class BilibiliSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver {
  /// Creates the adapter. [_cookies] holds the user's login cookie, if any;
  /// [storedUid] is the uid saved with it (the danmaku uid when the cookie
  /// has no `DedeUserID`). [now] and [sleep] are injectable for tests.
  new(
    this.http, {
    this._cookies,
    int Function()? storedUid,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _storedUid = storedUid ?? (() => 0),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final int Function() _storedUid;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  _Session? _session;
  final Map<String, String> _longIds = {};

  @override
  String get id => _site;

  @override
  String get name => '哔哩哔哩直播';

  // Session -------------------------------------------------------------------

  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  /// The session of the current login cookie; a changed cookie starts a new
  /// one (fetches that finish afterwards land in the discarded session).
  _Session _current() {
    final login = _login();
    final session = _session;
    if (session != null && session.login == login) return session;
    return _session = _Session(login);
  }

  /// The buvid pair: the login cookie's own, else the guest pair from
  /// finger/spi, requested once for concurrent callers. A failed request
  /// gives none; the next request asks again.
  Future<({String buvid3, String buvid4})?> _buvid(_Session session) {
    final own = _cookieField(session.login, 'buvid3');
    if (own != null) return Future.value((buvid3: own, buvid4: _cookieField(session.login, 'buvid4') ?? ''));
    final guest = session.guest;
    if (guest != null) return Future.value(guest);
    return session.guestFetch ??= () async {
      try {
        final response = await _send(
          LiveRequest(site: _site, url: Uri.https(_api, '/x/frontend/finger/spi'), headers: _headers(session.login)),
        );
        return session.guest = BilibiliApi.buvid(response.text, status: response.status);
      } on SiteError {
        return null;
      } finally {
        session.guestFetch = null;
      }
    }();
  }

  Future<String> _cookie(_Session session) async {
    final pair = await _buvid(session);
    if (pair == null) return session.login;
    return BilibiliApi.cookie(buvid3: pair.buvid3, buvid4: pair.buvid4, loginCookie: session.login);
  }

  /// WBI keys from nav, reused for 6 hours; [renew] fetches new ones.
  Future<({String imgKey, String subKey})> _keys(_Session session, {bool renew = false}) {
    final cached = session.keys;
    if (!renew && cached != null && _now().difference(cached.at) < _sessionLifetime) {
      return Future.value((imgKey: cached.imgKey, subKey: cached.subKey));
    }
    return session.keysFetch ??= () async {
      try {
        final response = await _get(Uri.https(_api, '/x/web-interface/nav'), await _cookie(session));
        final keys = BilibiliApi.wbiKeys(response.text, status: response.status);
        session.keys = (imgKey: keys.imgKey, subKey: keys.subKey, at: _now());
        return keys;
      } finally {
        session.keysFetch = null;
      }
    }();
  }

  /// `w_webid` from the /lol page, kept and renewed with the WBI keys.
  Future<String> _accessId(_Session session, {bool renew = false}) {
    final cached = session.accessId;
    if (!renew && cached != null && _now().difference(cached.at) < _sessionLifetime) return Future.value(cached.id);
    return session.accessIdFetch ??= () async {
      try {
        final response = await _get(Uri.https('live.bilibili.com', '/lol'), await _cookie(session));
        if (response.status == 412) throw const RateLimited(_site, detail: 'lol: HTTP 412');
        if (response.status >= 500) throw NetworkFailure(_site, 'lol: HTTP ${response.status}');
        final id = BilibiliApi.accessId(response.text);
        session.accessId = (id: id, at: _now());
        return id;
      } finally {
        session.accessIdFetch = null;
      }
    }();
  }

  /// The signed query for [params]: `wts` added, sorted, filtered,
  /// percent-encoded, then `&w_rid=` + md5 of that query and the mixin key.
  static String wbiSign(
    Map<String, String> params, {
    required String imgKey,
    required String subKey,
    required int wts,
  }) {
    final query = BilibiliApi.wbiQuery(params, wts: wts);
    return '$query&w_rid=${md5.convert(utf8.encode('$query${BilibiliApi.mixinKey(imgKey, subKey)}'))}';
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

  Future<LiveResponse> _get(Uri url, String cookie) =>
      _send(LiveRequest(site: _site, url: url, headers: _headers(cookie)));

  Future<LiveResponse> _unsigned(Uri url) async => await _get(url, await _cookie(_current()));

  /// A WBI-signed GET of `api.live.bilibili.com` [path]. A -352 answer
  /// renews the keys, the guest buvid and the access id and retries once
  /// after 180 ms; a second -352 is `RiskControl`.
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

  static Map<String, String> _headers(String cookie) => BilibiliApi.apiHeaders(cookie);

  static String? _cookieField(String cookie, String name) {
    final value = RegExp('(?:^|;)\\s*$name=([^;]*)').firstMatch(cookie)?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _longId(LiveRoom room) => switch (room.data) {
    final BilibiliRoomData data => data.longId,
    _ => _longIds[room.roomId] ?? room.roomId,
  };

  void _remember(String requested, String longId) {
    _longIds.remove(requested);
    _longIds[requested] = longId;
    if (_longIds.length > 512) _longIds.remove(_longIds.keys.first);
  }

  // Catalog and search --------------------------------------------------------

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final response = await _unsigned(
      Uri.https(_liveApi, '/room/v1/Area/getList', {'need_entrance': '1', 'parent_id': '0'}),
    );
    return BilibiliApi.categories(response.text, status: response.status);
  }

  /// The unsigned `room/v1/area/getRoomList` ([pageSize] limited to 1–30),
  /// then the signed `second/getList` (with `w_webid`) as a fallback. The
  /// signed list is what 3.x used, but guests get -352 on every page of it
  /// (seen since M4.1), so an area page never opened (M4.D). `RateLimited` is
  /// not retried; when the fallback fails too, the first list's error is
  /// reported.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final number = '${page < 1 ? 1 : page}';
    try {
      final response = await _unsigned(
        Uri.https(_liveApi, '/room/v1/area/getRoomList', {
          'platform': 'web',
          'parent_area_id': category.areaType,
          'area_id': category.areaId,
          'sort_type': 'online',
          'page': number,
          'page_size': '${pageSize.clamp(1, 30)}',
        }),
      );
      return BilibiliApi.roomList(response.text, status: response.status).rooms;
    } on RateLimited {
      rethrow;
    } on SiteError catch (first) {
      try {
        final result = await _signed(
          '/xlive/web-interface/v1/second/getList',
          {
            'platform': 'web',
            'parent_area_id': category.areaType,
            'area_id': category.areaId,
            'sort_type': 'online',
            'page': number,
          },
          (response) => BilibiliApi.roomList(response.text, status: response.status),
          webId: true,
        );
        return result.value.rooms;
      } on RateLimited {
        rethrow;
      } on SiteError {
        throw first;
      }
    }
  }

  /// The anonymous ranked list (`sort=online`), tried twice 180 ms apart,
  /// then the recommendation feed as a fallback; the result is re-sorted by
  /// popularity. `RateLimited` is never retried; when the fallback fails
  /// too, the ranked list's error is reported.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final number = page < 1 ? 1 : page;
    late SiteError ranked;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await _sleep(_retryDelay);
      try {
        final response = await _unsigned(
          Uri.https(_liveApi, '/room/v1/Area/getListByAreaID', {
            'areaId': '0',
            'parent_area_id': '0',
            'sort': 'online',
            'pageSize': '${pageSize.clamp(1, 30)}',
            'page': '$number',
          }),
        );
        return BilibiliApi.roomList(response.text, status: response.status).rooms;
      } on RateLimited {
        rethrow;
      } on SiteError catch (error) {
        ranked = error;
      }
    }
    try {
      final response = await _unsigned(
        Uri.https(_liveApi, '/xlive/web-interface/v1/webMain/getMoreRecList', {'platform': 'web', 'page': '$number'}),
      );
      return BilibiliApi.roomList(response.text, status: response.status).rooms;
    } on RateLimited {
      rethrow;
    } on SiteError {
      throw ranked;
    }
  }

  /// Live search; [pageSize] is sent, limited to 1–50. A blank keyword
  /// gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final number = page < 1 ? 1 : page;
    final response = await _unsigned(_searchUrl('live', text, number, pageSize: pageSize.clamp(1, 50)));
    return BilibiliApi.searchRooms(response.text, page: number, status: response.status);
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final response = await _unsigned(_searchUrl('live_user', text, page < 1 ? 1 : page));
    return BilibiliApi.searchAnchors(response.text, status: response.status);
  }

  static Uri _searchUrl(String type, String keyword, int page, {int? pageSize}) =>
      Uri.https(_api, '/x/web-interface/search/type', {
        'context': '',
        'search_type': type,
        'cover_type': 'user_cover',
        'order': '',
        'keyword': keyword,
        'category_id': '',
        '__refresh__': '',
        '_extra': '',
        'highlight': '0',
        'single_column': '0',
        'page': '$page',
        'page_size': ?pageSize?.toString(),
      });

  // Rooms ---------------------------------------------------------------------

  Future<LiveRoom> _detail(String roomId) async {
    final id = roomId.trim();
    if (!RegExp(r'^\d{1,18}$').hasMatch(id)) throw NotFound(_site, 'room id $id is not a number');
    final result = await _signed('/xlive/web-room/v1/index/getInfoByRoom', {
      'room_id': id,
    }, (response) => BilibiliApi.roomDetail(response.text, requestedId: id, status: response.status));
    _remember(id, result.value.longId);
    return result.value.room.copyWith(data: BilibiliRoomData(result.value.longId));
  }

  /// The room with its danmaku credentials. Playback comes first: room entry
  /// makes one quick discovery; when it fails the room still opens with an
  /// empty token, and the danmaku connection refreshes credentials with the
  /// full retry schedule.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    final room = await _detail(roomId);
    final longId = _longId(room);
    BilibiliDanmakuArgs args;
    try {
      args = await danmakuArgs(longId, maxAttempts: 1);
    } on SiteError {
      args = await _emptyDanmakuArgs(longId);
    }
    return room.copyWith(danmakuData: args);
  }

  /// Follow-card refresh: metadata only, no short-lived danmaku credentials.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The stream is resolved from the long id by a separate API, so the
  /// strict metadata-only room holds everything the recorder needs.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the room is live; a carousel is not.
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final response = await _unsigned(Uri.https(_liveApi, '/room/v1/Room/get_info', {'room_id': roomId.trim()}));
    return BilibiliApi.liveStatus(response.text, status: response.status);
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async {
    final id = _longIds[roomId.trim()] ?? roomId.trim();
    final response = await _unsigned(Uri.https(_liveApi, '/av/v1/SuperChat/getMessageList', {'room_id': id}));
    return BilibiliApi.superChats(response.text, status: response.status);
  }

  // Streams -------------------------------------------------------------------

  /// The room's qualities; a carousel without a stream for this client
  /// (guests) has the one [BilibiliApi.carouselQuality], played from its
  /// video (1-1).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final data = (await _play(_longId(detail), 0)).data;
    return data == null ? const [BilibiliApi.carouselQuality] : BilibiliApi.qualities(data);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// Lines at [quality] with the quality the server applied: guests asking
  /// for 10000 are served 250, and the lines say so. The room's state is not
  /// checked first: a carousel plays whenever the platform gives it a stream
  /// (signed in); without one (guests), and for
  /// [BilibiliApi.carouselQuality], it plays the video in rotation from
  /// where the carousel is ([_carousel]).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final longId = _longId(detail);
    if (quality.data == BilibiliApi.carouselQualityId) return await _carousel(longId);
    final play = await _play(longId, quality.data);
    final data = play.data;
    if (data == null) return await _carousel(longId);
    return BilibiliApi.resolution(
      data,
      requestedQn: quality.data,
      roomId: longId,
      issuedAt: play.issuedAt,
      cookie: play.cookie,
    );
  }

  /// The video [longId]'s carousel is playing (1-1): `getRoundPlayVideo`,
  /// then its MP4 (`x/player/playurl`), started at `play_time`. Two
  /// requests; when the video ends, recovery asks again and gets the next.
  Future<LivePlayUrlResolution> _carousel(String longId) async {
    final cookie = await _cookie(_current());
    final round = await _get(BilibiliApi.roundPlayVideoUrl(longId), cookie);
    final video = BilibiliApi.roundPlayVideo(round.text, status: round.status);
    final file = await _get(BilibiliApi.videoPlayUrl(video.bvid, video.cid), cookie);
    return BilibiliApi.videoResolution(
      file.text,
      bvid: video.bvid,
      start: video.start,
      status: file.status,
      cookie: cookie,
    );
  }

  /// `getRoomPlayInfo` at [qn]; `data` is null for a carousel without a
  /// stream for this client ([BilibiliApi.carouselWithoutStream]).
  Future<({Map<String, dynamic>? data, DateTime issuedAt, String cookie})> _play(String longId, Object? qn) async {
    final cookie = await _cookie(_current());
    final response = await _get(
      Uri.https(_liveApi, '/xlive/web-room/v2/index/getRoomPlayInfo', {
        'room_id': longId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0',
        'qn': '${qn ?? 0}',
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
    if (BilibiliApi.carouselWithoutStream(response.text, status: response.status)) {
      return (data: null, issuedAt: issuedAt, cookie: cookie);
    }
    return (data: BilibiliApi.playData(response.text, status: response.status), issuedAt: issuedAt, cookie: cookie);
  }

  // Danmaku -------------------------------------------------------------------

  /// Danmaku credentials for the long room id: signed `getDanmuInfo`, tried
  /// up to [maxAttempts] times, 180 ms × attempt apart, renewing the WBI
  /// keys on the second and fourth attempts.
  Future<BilibiliDanmakuArgs> danmakuArgs(String longId, {int maxAttempts = 4}) async {
    final numeric = int.tryParse(longId);
    if (numeric == null || numeric <= 0) throw NotFound(_site, 'room id $longId is not a number');
    SiteError? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt == 1 || attempt == 3) _current().keys = null;
      try {
        final result = await _signed('/xlive/web-room/v1/index/getDanmuInfo', {
          'id': longId,
          'type': '0',
        }, (response) => BilibiliApi.danmakuInfo(response.text, status: response.status));
        return BilibiliDanmakuArgs(
          roomId: numeric,
          uid: BilibiliApi.danmakuUid(cookie: result.session.login, storedUid: _uid(result.session)),
          token: result.value.token,
          servers: result.value.servers,
          buvid: _cookieField(result.cookie, 'buvid3') ?? '',
          headers: BilibiliApi.mediaHeaders(longId, cookie: result.cookie),
          refresh: () => danmakuArgs(longId),
        );
      } on SiteError catch (error) {
        last = error;
      }
      if (attempt + 1 < maxAttempts) await _sleep(_retryDelay * (attempt + 1));
    }
    throw last!;
  }

  Future<BilibiliDanmakuArgs> _emptyDanmakuArgs(String longId) async {
    final session = _current();
    final cookie = await _cookie(session);
    return BilibiliDanmakuArgs(
      roomId: int.tryParse(longId) ?? 0,
      uid: BilibiliApi.danmakuUid(cookie: session.login, storedUid: _uid(session)),
      token: '',
      servers: [Uri.parse(BilibiliApi.danmakuGateway)],
      buvid: _cookieField(cookie, 'buvid3') ?? '',
      headers: BilibiliApi.mediaHeaders(longId, cookie: cookie),
      refresh: () => danmakuArgs(longId),
    );
  }

  int _uid(_Session session) => session.verifiedUid > 0 ? session.verifiedUid : _storedUid();

  // Account -------------------------------------------------------------------

  /// A new login QR code: the key to poll with and the URL to encode.
  Future<({String key, Uri url})> qrCode() async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/generate'),
        headers: const {'user-agent': BilibiliApi.userAgent},
      ),
    );
    return BilibiliApi.qrCode(response.text, status: response.status);
  }

  /// One poll of [key]. When confirmed, `cookie` holds the `name=value`
  /// pairs of every `Set-Cookie`, for the caller to verify with [account]
  /// and store.
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/poll', {'qrcode_key': key}),
        headers: const {'user-agent': BilibiliApi.userAgent},
      ),
    );
    final state = BilibiliApi.qrPoll(response.text, status: response.status);
    if (state != BilibiliQrState.confirmed) return (state: state, cookie: null);
    final cookie = [
      for (final header in response.headers['set-cookie'] ?? const <String>[])
        if (header.split(';').first.replaceAll(_controlCharacters, '').trim() case final pair when pair.contains('='))
          pair,
    ].join('; ');
    if (cookie.isEmpty) throw const ApiChanged(_site, 'qrcode/poll: confirmed without Set-Cookie');
    return (state: state, cookie: cookie);
  }

  /// Checks [cookie] (default: the stored one) with `x/member/web/account`;
  /// -101 is `NeedsLogin` (the caller clears an expired cookie). A verified
  /// stored cookie's uid becomes the danmaku uid when the cookie has no
  /// `DedeUserID`.
  Future<({int uid, String name})> account({String? cookie}) async {
    final session = _current();
    final value = (cookie ?? session.login).replaceAll(_controlCharacters, '').trim();
    if (value.isEmpty) throw const NeedsLogin(_site, 'no cookie');
    final response = await _send(
      LiveRequest(site: _site, url: Uri.https(_api, '/x/member/web/account'), headers: {'cookie': value}),
    );
    final result = BilibiliApi.account(response.text, status: response.status);
    if (value == session.login) session.verifiedUid = result.uid;
    return result;
  }

  // Links ---------------------------------------------------------------------

  /// A room of `live.bilibili.com` (`/{id}`, `/h5/{id}`, `/blanc/{id}`) or
  /// the old `www.bilibili.com/{id}` alias. Other bilibili.com hosts are not
  /// rooms (`space.bilibili.com/{uid}`).
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = RoomPaths.segments(uri);
    if (segments.isEmpty) return null;
    final host = uri.host.toLowerCase();
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

  /// b23.tv short links.
  @override
  bool needsResolving(String url) => RoomPaths.hostIs(Uri.tryParse(url)?.host.toLowerCase() ?? '', 'b23.tv');

  /// Follows one redirect of a b23.tv link without fetching the target; the
  /// parser parses the target (another b23.tv hop included).
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final uri = Uri.parse(url);
    final target = ShortLinkSession.redirectTarget(
      uri,
      await session.get(uri, headers: const {'user-agent': BilibiliApi.userAgent}),
    );
    return target == null ? null : LinkRedirect(target);
  }

  /// A positive decimal room number without leading zeros, or null.
  static String? _roomNumber(String text) {
    if (!RegExp(r'^\d{1,18}$').hasMatch(text)) return null;
    final value = int.parse(text);
    return value > 0 ? '$value' : null;
  }
}

/// The anonymous session built for one login cookie: guest buvid pair, WBI
/// keys, access id and the verified uid.
final class _Session {
  new(this.login);

  /// The user's cookie ('' when signed out).
  final String login;

  ({String buvid3, String buvid4})? guest;
  Future<({String buvid3, String buvid4})?>? guestFetch;

  ({String imgKey, String subKey, DateTime at})? keys;
  Future<({String imgKey, String subKey})>? keysFetch;

  ({String id, DateTime at})? accessId;
  Future<String>? accessIdFetch;

  int verifiedUid = 0;
}
