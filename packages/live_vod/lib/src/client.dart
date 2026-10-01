import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/parse.dart';

/// How long WBI keys are reused (same as the live adapter).
const Duration _keyLifetime = Duration(hours: 6);

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// The request plumbing every video-site call goes through (pure_live_TV
/// `b9d2f739` `bilibili_api_client.dart`): the user's Bilibili cookie from
/// the shared [CookieVault] (the live login serves both modes), a guest
/// buvid pair when signed out, WBI signing with the live adapter's
/// algorithm (`BilibiliSite.wbiSign`, M4.1), the csrf token of the write
/// endpoints, and typed errors.
///
/// Differences from the TV client, measured 2026-10-01 (M14.0):
/// - the guest buvid pair from `finger/spi` makes `x/player/playurl` answer
///   HTTP 412, so stream requests carry the login cookie only ([stream]);
/// - the WBI-signed `x/player/wbi/playurl` answers 412 to guests too, so
///   streams use the plain endpoint (the TV client already did, for its
///   `v_voucher` risk);
/// - a -352 answer of a signed request renews the keys and retries once.
final class BilibiliVodClient {
  /// Creates the client. [_cookies] holds the user's login cookie, if any.
  new(this.http, {this._cookies, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final DateTime Function() _now;

  String? _guestFor;
  ({String buvid3, String buvid4})? _guest;
  Future<({String buvid3, String buvid4})?>? _guestFetch;
  ({String imgKey, String subKey, DateTime at})? _keys;
  Future<({String imgKey, String subKey})>? _keysFetch;

  /// Referer of video-site API requests.
  static const String referer = 'https://www.bilibili.com/';

  /// The user's login cookie, control characters removed ('' when signed
  /// out).
  String get loginCookie => (_cookies?.cookieFor(vodSite) ?? '').replaceAll(_controlCharacters, '').trim();

  /// Whether a login cookie is stored.
  bool get isLoggedIn => loginCookie.isNotEmpty;

  /// The signed-in user's id (`DedeUserID`), 0 when signed out.
  int get myMid => int.tryParse(_field(loginCookie, 'DedeUserID') ?? '') ?? 0;

  /// The csrf token of the write endpoints (`bili_jct`).
  String get csrf => _field(loginCookie, 'bili_jct') ?? '';

  static String? _field(String cookie, String name) {
    final value = RegExp('(?:^|;)\\s*$name=([^;]*)').firstMatch(cookie)?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Throws `NeedsLogin` when no cookie is stored (every write and the
  /// personal lists).
  void requireLogin(String what) {
    if (!isLoggedIn) throw NeedsLogin(vodSite, '$what: signed out');
  }

  /// The cookie of API requests: the login cookie (with the guest pair
  /// appended when it has no buvid3), else the guest pair.
  Future<String> apiCookie() async {
    final login = loginCookie;
    if (_field(login, 'buvid3') != null) return login;
    final pair = await _guestPair(login);
    if (pair == null) return login;
    return BilibiliApi.cookie(buvid3: pair.buvid3, buvid4: pair.buvid4, loginCookie: login);
  }

  Future<({String buvid3, String buvid4})?> _guestPair(String login) {
    if (_guestFor != login) {
      _guestFor = login;
      _guest = null;
    }
    final guest = _guest;
    if (guest != null) return Future.value(guest);
    return _guestFetch ??= () async {
      try {
        final response = await _send(
          LiveRequest(
            site: vodSite,
            url: Uri.https('api.bilibili.com', '/x/frontend/finger/spi'),
            headers: const {'user-agent': BilibiliApi.userAgent, 'referer': referer},
          ),
        );
        return _guest = BilibiliApi.buvid(response.text, status: response.status);
      } on SiteError {
        return null;
      } finally {
        _guestFetch = null;
      }
    }();
  }

  Future<({String imgKey, String subKey})> _wbiKeys({bool renew = false}) {
    final cached = _keys;
    if (!renew && cached != null && _now().difference(cached.at) < _keyLifetime) {
      return Future.value((imgKey: cached.imgKey, subKey: cached.subKey));
    }
    return _keysFetch ??= () async {
      try {
        final response = await _send(
          LiveRequest(
            site: vodSite,
            url: Uri.https('api.bilibili.com', '/x/web-interface/nav'),
            headers: _headers(await apiCookie(), referer),
          ),
        );
        final keys = BilibiliApi.wbiKeys(response.text, status: response.status);
        _keys = (imgKey: keys.imgKey, subKey: keys.subKey, at: _now());
        return keys;
      } finally {
        _keysFetch = null;
      }
    }();
  }

  static Map<String, String> _headers(String cookie, String referer) => {
    'user-agent': BilibiliApi.userAgent,
    'referer': referer,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// Media and stream request headers: UA, the page as Referer, and the
  /// login cookie only (the guest pair makes playurl answer 412).
  Map<String, String> mediaHeaders(String pageUrl) => _headers(loginCookie, pageUrl);

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(vodSite, failure.toString());
    }
  }

  /// A GET of [url] with [query] and the API cookie.
  Future<LiveResponse> get(Uri url, {Map<String, Object?> query = const {}, String referer = referer}) async =>
      await _send(
        LiveRequest.get(site: vodSite, url: url, query: query, headers: _headers(await apiCookie(), referer)),
      );

  /// A GET without any cookie but the login one (streams, see the class
  /// note).
  Future<LiveResponse> stream(Uri url, {required String referer, Map<String, Object?> query = const {}}) =>
      _send(LiveRequest.get(site: vodSite, url: url, query: query, headers: mediaHeaders(referer)));

  /// A GET of an absolute file (subtitles, lyrics, danmaku XML): UA and
  /// Referer, no cookie.
  Future<LiveResponse> file(Uri url, {String referer = referer}) =>
      _send(LiveRequest(site: vodSite, url: url, headers: _headers('', referer)));

  /// A WBI-signed GET; -352 renews the keys and retries once, a second -352
  /// is `RiskControl`. [parse] turns the response into the result.
  Future<T> signed<T>(
    Uri url,
    Map<String, String> params,
    T Function(LiveResponse response) parse, {
    String referer = referer,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final keys = await _wbiKeys(renew: attempt > 0);
      final query = BilibiliSite.wbiSign(
        params,
        imgKey: keys.imgKey,
        subKey: keys.subKey,
        wts: _now().millisecondsSinceEpoch ~/ 1000,
      );
      final response = await _send(
        LiveRequest(
          site: vodSite,
          url: url.replace(query: query),
          headers: _headers(await apiCookie(), referer),
        ),
      );
      try {
        return parse(response);
      } on RiskControl {
        if (attempt > 0) rethrow;
      }
    }
  }

  /// A write: form POST with `csrf`, signed in only. Returns `data`.
  Future<Object?> post(Uri url, Map<String, String> form, {String referer = referer, String what = 'post'}) async {
    requireLogin(what);
    final response = await _send(
      LiveRequest.form(
        site: vodSite,
        url: url,
        fields: {...form, 'csrf': csrf},
        headers: _headers(await apiCookie(), referer),
      ),
    );
    return VodParse.data(response.text, status: response.status, what: what);
  }
}
