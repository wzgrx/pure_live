import 'dart:math';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/douyu/douyu_api.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

const _site = 'douyu';
const _www = 'www.douyu.com';

/// Room addresses accepted by the detail requests: a rid, a 靓号 (vip
/// number) or an alias.
final RegExp _roomKey = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _digits = RegExp(r'^\d{1,18}$');

/// The canonical rid a room's signing, stream and danmaku requests use (a
/// room asked for by its 靓号 or alias keeps that address as its identity).
@immutable
final class DouyuRoomData {
  /// Creates the data.
  const new(this.rid);

  /// Canonical numeric room id (`room.room_id`).
  final String rid;

  @override
  String toString() => 'DouyuRoomData($rid)';
}

/// Where the app keeps what renewing a Douyu login needs beside the cookie
/// (3.x's `douyuLtp0`, `douyuDid` and `douyuCookieSavedAt` settings), and
/// where a renewed cookie goes. The cookie itself is read from the
/// [CookieVault]; after [saveRenewed] the vault reports the new one.
abstract interface class DouyuLoginStore {
  /// LTP0 saved apart from the cookie (copied from the passport request).
  String? get longTermKey;

  /// The login's `dy_did` saved apart from the cookie.
  String? get deviceId;

  /// When the cookie was saved or last renewed; the web `dy_auth` lasts
  /// seven days from then.
  DateTime? get savedAt;

  /// Stores [cookie] as the login and [renewedAt] as its save time.
  Future<void> saveRenewed(String cookie, DateTime renewedAt);
}

/// The Douyu adapter (3.x's `DouyuSite` and `DouyuUtils`; parsing in
/// [DouyuApi]).
///
/// Every request carries one device id: the login cookie's `dy_did`, else a
/// random one per adapter. The signing descriptor is fetched for that id,
/// reused for up to five minutes and shared by concurrent callers. Failures
/// are `SiteError`s; nothing is disguised as an offline room.
final class DouyuSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayUrlCursorResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter. [_cookies] holds the user's login cookie, if any;
  /// with [_login] an expiring login is renewed before play requests, as
  /// 3.x did. [forceRenewal] reads the cookie page's forced renewal setting
  /// (`douyuForceRenew`, off by default; see [DouyuApi.lease]) each time a
  /// URL is resolved or its lease looked up. [now] and [random] are
  /// injectable for tests.
  new(this.http, {this._cookies, this._login, bool Function()? forceRenewal, DateTime Function()? now, Random? random})
    : _forceRenewal = forceRenewal ?? _off,
      _now = now ?? DateTime.now,
      _processDid = DouyuApi.generateDeviceId(random ?? Random.secure());

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final DouyuLoginStore? _login;
  final bool Function() _forceRenewal;
  final DateTime Function() _now;
  final String _processDid;

  static bool _off() => false;

  ({String did, DouyuDescriptor descriptor, DateTime at})? _descriptor;
  ({String did, Future<DouyuDescriptor> future})? _descriptorFetch;
  Future<void>? _renewal;
  final Map<String, String> _rids = {};
  final Map<String, PlayLease> _leases = {};

  @override
  String get id => _site;

  @override
  String get name => '斗鱼直播';

  /// The device id of the next request: the login cookie's `dy_did`, else
  /// this adapter's random one.
  String get deviceId => DouyuApi.deviceId(_account(), _processDid);

  // Requests ------------------------------------------------------------------

  String _account() => DouyuApi.normalizeCookie(_cookies?.cookieFor(_site) ?? '');

  /// The request cookie and the device id it carries, read together.
  ({String cookie, String did}) _identity() {
    final account = _account();
    final did = DouyuApi.deviceId(account, _processDid);
    return (cookie: DouyuApi.cookieHeader(account: account, did: did), did: did);
  }

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// A GET with the API headers (the DID cookie, as the web player sends).
  Future<LiveResponse> _api(Uri url, {String? referer}) => _send(
    LiveRequest(site: _site, url: url, headers: {...DouyuApi.apiHeaders(_identity().cookie), 'referer': ?referer}),
  );

  // Catalog and search --------------------------------------------------------

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('m.douyu.com', '/api/cate/list'),
        headers: const {'user-agent': DouyuApi.userAgent},
      ),
    );
    return DouyuApi.categories(response.text, status: response.status);
  }

  /// One `mixList` page of 120 rooms.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final number = page < 1 ? 1 : page;
    final response = await _api(Uri.https(_www, '/gapi/rkc/directory/mixList/2_${category.areaId.trim()}/$number'));
    return DouyuApi.roomList(response.text, page: number, status: response.status).rooms;
  }

  /// One `allpage` page of 40 rooms.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final number = page < 1 ? 1 : page;
    final response = await _api(Uri.https(_www, '/japi/weblist/apinc/allpage/6/$number'));
    return DouyuApi.roomList(response.text, page: number, status: response.status).rooms;
  }

  /// Rooms, live and offline; [pageSize] is sent, limited to 1–50. A blank
  /// keyword gives nothing without a request (the platform answers it with
  /// an error).
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final response = await _api(
      Uri.https(_www, '/japi/search/api/searchShow', {
        'kw': text,
        'page': '${page < 1 ? 1 : page}',
        'pageSize': '${pageSize.clamp(1, 50)}',
      }),
      referer: 'https://www.douyu.com/search/',
    );
    return DouyuApi.searchRooms(response.text, status: response.status);
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final response = await _api(
      Uri.https(_www, '/japi/search/api/searchUser', {
        'kw': text,
        'page': '${page < 1 ? 1 : page}',
        'pageSize': '${pageSize.clamp(1, 50)}',
        'filterType': '1',
      }),
      referer: 'https://www.douyu.com/search/',
    );
    return DouyuApi.searchAnchors(response.text, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// The room at [roomId] (a rid, a 靓号 or an alias), which stays its
  /// identity. `betard` only knows rids: an alias is looked up on its room
  /// page first, and a number `betard` does not know is tried as a 靓号.
  Future<LiveRoom> _detail(String roomId) async {
    final id = roomId.trim();
    if (!_roomKey.hasMatch(id)) throw NotFound(_site, 'room id "$id" is not a room address');
    final rid = _rids[id] ?? (_digits.hasMatch(id) ? id : await _ridFromPage(id));
    if (rid == null) throw NotFound(_site, 'alias $id does not lead to a room');
    try {
      return await _detailOf(id, rid);
    } on NotFound {
      final mapped = await _ridFromPage(rid);
      if (mapped == null || mapped == rid) rethrow;
      return await _detailOf(id, mapped);
    }
  }

  Future<LiveRoom> _detailOf(String requested, String rid) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https(_www, '/betard/$rid'),
        headers: {'referer': 'https://www.douyu.com/$rid', 'user-agent': DouyuApi.detailUserAgent},
      ),
    );
    final result = DouyuApi.roomDetail(response.text, requestedId: requested, status: response.status);
    _remember(requested, result.rid);
    return result.room.copyWith(data: DouyuRoomData(result.rid), danmakuData: DouyuDanmakuArgs(result.rid));
  }

  /// The rid behind room page `www.douyu.com/<address>`: an alias redirects
  /// to `/<rid>`, a 靓号 page names its rid; null when neither.
  Future<String?> _ridFromPage(String address) async {
    final page = Uri.https(_www, '/$address');
    final response = await _send(
      LiveRequest(site: _site, url: page, headers: const {'user-agent': DouyuApi.userAgent}, followRedirects: false),
    );
    if (response.status >= 500) throw NetworkFailure(_site, 'room page: HTTP ${response.status}');
    if (response.status >= 300 && response.status < 400) {
      final location = response.header('location');
      return location == null ? null : DouyuApi.roomIdAt(page.resolve(location.trim()));
    }
    return response.isSuccess ? DouyuApi.roomIdInPage(response.text) : null;
  }

  void _remember(String requested, String rid) {
    _rids.remove(requested);
    _rids[requested] = rid;
    if (_rids.length > 512) _rids.remove(_rids.keys.first);
  }

  String _rid(LiveRoom room) => switch (room.data) {
    final DouyuRoomData data => data.rid,
    _ => _rids[room.roomId] ?? room.roomId,
  };

  /// The room with its danmaku arguments (the rid; no request needed).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// Strict: a failed `betard` is thrown, never turned into an offline room
  /// (3.x once stopped recordings that way).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Live only; a loop room is not.
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// Qualities and CDN lines from one metadata request (`rate=-1`).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      DouyuApi.qualities((await _play(_rid(detail), rate: -1, cdn: '')).data);

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// Every CDN of [quality] signed at its rate, in line order; the lines of
  /// one confirmed rate are kept ([DouyuApi.resolution]). A failing CDN is
  /// skipped; when all fail, the last failure is thrown.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = quality.data;
    if (data is! DouyuPlayData) return LivePlayUrlResolution(urls: const []);
    final rid = _rid(detail);
    final answers = <({LivePlayLine line, int? rate})>[];
    SiteError? last;
    for (final cdn in data.cdns) {
      try {
        answers.add(await _answer(rid, data.rate, cdn));
      } on SiteError catch (error) {
        last = error;
      }
    }
    if (answers.isEmpty && last != null) throw last;
    return DouyuApi.resolution(answers, requestedRate: data.rate);
  }

  /// Fresh metadata first (the CDN set changes while a connection pauses),
  /// then the committed rate on the current CDNs; old URLs are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final qualities = await getPlayQualities(detail: detail);
    if (qualities.isEmpty) return LivePlayUrlResolution(urls: const []);
    final wanted = '${quality.selectionId}';
    final matching = qualities.where((item) => '${item.selectionId}' == wanted).firstOrNull;
    final fresh = qualities.first.data;
    final requested = quality.data;
    final request =
        matching ??
        (fresh is DouyuPlayData && requested is DouyuPlayData
            ? LivePlayQuality(
                quality: quality.quality,
                id: quality.selectionId,
                data: DouyuPlayData(requested.rate, fresh.cdns),
              )
            : qualities.first);
    return await resolvePlayUrlsRaw(detail: detail, quality: request);
  }

  /// Signs only line [lineIndex] (recording starts on one line and moves on
  /// after a failure); past the last line nothing is requested.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) async {
    final data = quality.data;
    if (data is! DouyuPlayData || lineIndex < 0 || lineIndex >= data.cdns.length) {
      return LivePlayUrlResolution(urls: const []);
    }
    final answer = await _answer(_rid(detail), data.rate, data.cdns[lineIndex]);
    return DouyuApi.resolution([answer], requestedRate: data.rate);
  }

  Future<({LivePlayLine line, int? rate})> _answer(String rid, int rate, String cdn) async {
    final play = await _play(rid, rate: rate, cdn: cdn);
    final answer = DouyuApi.answer(
      play.data,
      roomId: rid,
      cdn: cdn,
      cookie: play.cookie,
      issuedAt: play.issuedAt,
      forceRenewal: _forceRenewal(),
    );
    final lease = answer.line.lease;
    if (lease != null) {
      _leases.remove(answer.line.url);
      _leases[answer.line.url] = lease;
      if (_leases.length > 64) _leases.remove(_leases.keys.first);
    }
    return answer;
  }

  /// One signed `getH5PlayV1` for (rate, cdn), at most twice: after a failed
  /// first attempt the login is renewed (when it can be) and the second
  /// attempt fetches a new descriptor. `error != 0` (`-5` 房间未开播) is a
  /// room state and is not retried.
  Future<({Map<String, dynamic> data, DateTime issuedAt, String cookie})> _play(
    String rid, {
    required int rate,
    required String cdn,
  }) async {
    if (!_digits.hasMatch(rid)) throw NotFound(_site, 'room id "$rid" is not a number');
    await _renew();
    SiteError? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final identity = _identity();
        final descriptor = await _descriptorFor(identity, force: attempt > 0);
        final issuedAt = _now();
        final response = await _send(
          LiveRequest.form(
            site: _site,
            url: Uri.https(_www, '/lapi/live/getH5PlayV1/$rid'),
            headers: DouyuApi.apiHeaders(identity.cookie, roomId: rid),
            fields: DouyuApi.signedForm(
              descriptor,
              roomId: rid,
              tt: issuedAt.millisecondsSinceEpoch ~/ 1000,
              did: identity.did,
              rate: rate,
              cdn: cdn,
            ),
          ),
        );
        return (
          data: DouyuApi.playData(response.text, status: response.status),
          issuedAt: issuedAt,
          cookie: identity.cookie,
        );
      } on StreamUnavailable {
        rethrow;
      } on SiteError catch (error) {
        last = error;
      }
      if (attempt == 0) await _renew(force: true);
    }
    throw last!;
  }

  /// The descriptor for [identity]'s device id: reused while it is younger
  /// than five minutes and usable, fetched once for concurrent callers;
  /// [force] fetches a new one (or joins a fetch already running).
  Future<DouyuDescriptor> _descriptorFor(({String cookie, String did}) identity, {bool force = false}) {
    final did = identity.did;
    final cached = _descriptor;
    final now = _now();
    if (!force &&
        cached != null &&
        cached.did == did &&
        now.difference(cached.at) < DouyuApi.descriptorLifetime &&
        cached.descriptor.usableAt(now)) {
      return Future.value(cached.descriptor);
    }
    final running = _descriptorFetch;
    if (running != null && running.did == did) return running.future;
    final future = () async {
      try {
        final response = await _send(
          LiveRequest(
            site: _site,
            url: Uri.https(_www, '/wgapi/livenc/liveweb/websec/getEncryption', {'did': did}),
            headers: DouyuApi.apiHeaders(identity.cookie),
          ),
        );
        final descriptor = DouyuApi.descriptor(response.text, now: _now(), status: response.status);
        _descriptor = (did: did, descriptor: descriptor, at: _now());
        return descriptor;
      } finally {
        if (_descriptorFetch?.did == did) _descriptorFetch = null;
      }
    }();
    _descriptorFetch = (did: did, future: future);
    return future;
  }

  /// When to fetch a new URL for [url]: from the lease its resolution
  /// computed, else as if it was issued at [now].
  @override
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) => _leaseOf(url, now)?.refreshAt;

  /// The last instant [url] can open a new connection (`expire` after it
  /// was issued).
  @override
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => _leaseOf(url, now)?.expiresAt;

  /// The lease of [url] under the current forced renewal setting: an
  /// assumed lease computed while it was on is dropped once it is off.
  PlayLease? _leaseOf(String url, DateTime? now) {
    final force = _forceRenewal();
    final known = _leases[url];
    if (known != null && (force || DouyuApi.statedLifetime(url) != null)) return known;
    return DouyuApi.lease(url, now ?? _now(), forceRenewal: force);
  }

  // Account -------------------------------------------------------------------

  /// 3.x's `ensureFreshSession`: with a login store, a stored login that has
  /// LTP0 and its device id is renewed when it is within a day of its end
  /// (or has no token), or always with [force] (a play request just
  /// failed). Never throws: a failed renewal leaves the request to go out
  /// with the current cookie. Concurrent callers share one renewal.
  Future<void> _renew({bool force = false}) async {
    final store = _login;
    final cookie = _account();
    if (store == null || cookie.isEmpty) return;
    final credentials = DouyuApi.renewalCredentials(cookie, storedLtp0: store.longTermKey, storedDid: store.deviceId);
    final ltp0 = credentials.ltp0;
    final did = credentials.did;
    if (ltp0 == null || did == null) return;
    if (!force && !DouyuApi.shouldRenew(cookie, now: _now(), savedAt: store.savedAt)) return;
    await (_renewal ??= () async {
      try {
        final renewed = await renewSession(cookie: cookie, ltp0: ltp0, did: did);
        if (renewed != null) await store.saveRenewed(renewed, _now());
      } on Exception {
        // Keep the current cookie; the request may go out as a guest.
      } finally {
        _renewal = null;
      }
    }());
  }

  /// Renews login [cookie] at the passport with [ltp0] and [did]: that
  /// request's cookie is only `dy_did` and `LTP0`, and only the answer's
  /// `Set-Cookie` is read. Returns the merged cookie, or null when nothing
  /// was renewed (no `Set-Cookie`, or no session token after the merge); the
  /// caller then keeps the old cookie and its save time. A transport
  /// failure is `NetworkFailure`.
  Future<String?> renewSession({required String cookie, required String ltp0, required String did}) async {
    final stamp = '${_now().millisecondsSinceEpoch}';
    final key = DouyuApi.renewalCredentials('', typedLtp0: ltp0, typedDid: did);
    if (key.ltp0 == null || key.did == null) throw const NeedsLogin(_site, 'no LTP0 or device id');
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('passport.douyu.com', '/lapi/passport/iframe/safeAuth', {
          'client_id': '1',
          't': stamp,
          '_': stamp,
          'callback': 'axiosJsonpCallback',
        }),
        headers: {
          ...DouyuApi.apiHeaders(''),
          'cookie': '${DouyuApi.deviceIdName}=${key.did};${DouyuApi.longTermKeyName}=${key.ltp0}',
        },
      ),
    );
    return DouyuApi.renewedCookie(DouyuApi.normalizeCookie(cookie), response.headers['set-cookie'] ?? const []);
  }

  // Links ---------------------------------------------------------------------

  /// A room page of douyu.com or a subdomain (`www.douyu.com/9999`,
  /// `m.douyu.com/9999`), or a share page `/room/share/<number>`. The number
  /// may be a 靓号; the detail maps it to the rid.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_douyu(uri)) return null;
    final segments = RoomPaths.segments(uri);
    if (segments.length == 3 && segments[0] == 'room' && segments[1] == 'share' && _digits.hasMatch(segments[2])) {
      return segments[2];
    }
    return RoomPaths.firstSegment(uri, RegExp(r'^\d+$'));
  }

  /// An alias page (`www.douyu.com/lpl`): one path segment that is not a
  /// number, a reserved page or an area page (`g_LOL`).
  @override
  bool needsResolving(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_douyu(uri)) return false;
    final segments = RoomPaths.segments(uri);
    if (segments.length != 1) return false;
    final alias = segments.single;
    return RoomPaths.isRoomIdentifier(alias, RegExp(r'^[A-Za-z0-9_-]+$')) &&
        !_digits.hasMatch(alias) &&
        !alias.toLowerCase().startsWith('g_') &&
        !const {'room', 'member', 'cms'}.contains(alias.toLowerCase());
  }

  /// An alias page redirects to `/<rid>` (`betard` refuses aliases); one
  /// request, not followed.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final alias = RoomPaths.segments(Uri.parse(url)).single;
    final page = Uri.https(_www, '/$alias');
    final target = ShortLinkSession.redirectTarget(
      page,
      await session.get(page, headers: const {'user-agent': DouyuApi.userAgent}),
    );
    final rid = target == null ? null : DouyuApi.roomIdAt(target);
    return rid == null ? null : LinkRoom(rid);
  }

  static bool _douyu(Uri uri) =>
      (uri.isScheme('http') || uri.isScheme('https')) && RoomPaths.hostIs(uri.host.toLowerCase(), 'douyu.com');
}
